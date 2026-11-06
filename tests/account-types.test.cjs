const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const source=fs.readFileSync('src/account.js','utf8');
const admin=fs.readFileSync('src/admin.js','utf8');
const migration=fs.readFileSync('db/2026-11-06-account-types-venues-pros.sql','utf8');
test('three account types are chosen once, venue accounts never take part in encounters',()=>{
  for(const needle of ['function typeView',"opt('personal'","opt('pro'","opt('venue'",'data-type="${k}"',"rpc('set_account_type'","rpc('my_account_type')",'function venueHomeView','function venueProfileView',"rpc('apply_venue'","rpc('my_venue')","rpc('venue_create_invite'","rpc('venue_revoke_invite'","rpc('venue_announce'","rpc('venue_room')"])assert.ok(source.includes(needle),needle);
  assert.ok(migration.includes("create or replace function private.require_person()"),'server-side person guard');
  for(const fn of ['join_venue','venue_members','venue_talents','send_enquiry','buy_pass_simulated'])assert.ok(migration.includes(`function private.${fn}(`)&&migration.split(`function private.${fn}(`)[1].split('$$;')[0].includes('private.require_person()'),fn+' must call require_person');
  assert.ok(migration.includes("p.account_type<>'venue' and private.profile_complete(p)"),'venue accounts excluded from discovery');
});
test('venue QR codes are generated on the phone from a one-time token and sessions are capped at 3 hours',()=>{
  for(const needle of ["import qrDataUrl from './qr.js'","qrDataUrl(url)","download=\"prod-qr-",'function durationOptions','max_session_minutes'])assert.ok(source.includes(needle),needle);
  assert.ok(migration.includes("check (duration_minutes between 15 and 180)"));
  assert.ok(migration.includes("least(venue.duration_minutes,coalesce((private.setting('max_session_minutes'))::int,180))"));
  assert.ok(admin.includes('max="180"'),'admin venue form capped');
  assert.doesNotMatch(admin,/max="720"/);
});
test('professional sheets are approved before being listed, only inside the live venue, with enquiries scoped to co-presence',()=>{
  for(const needle of ['function proSheetView','function proView','function talentsView','function talentView',"rpc('save_pro_profile'","rpc('my_pro_profile')","rpc('venue_talents')","rpc('send_enquiry'",'data-action="talents"'])assert.ok(source.includes(needle),needle);
  assert.ok(migration.includes("t.status='approved' and t.subscription_until is not null and t.subscription_until>now()"),'talent listing requires approval and subscription');
  assert.ok(migration.includes("if private.blocked_between(uid,p_pro) then raise exception 'not_co_present'"),'enquiries respect blocks');
  for(const tab of ["'applications'","'pros'","admin_decide_venue","admin_decide_pro"])assert.ok(admin.includes(tab),tab);
});
test('payments are simulated only: a neutral pass rule, no amounts, no gender, clear SIMULATION label',()=>{
  for(const needle of ["rpc('buy_pass_simulated')","rpc('subscribe_talent_simulated')",'SIMULATION','function passBlock','m.locked','pass_required'])assert.ok(source.includes(needle),needle);
  assert.ok(migration.includes("(private.setting('pass_rule') #>> '{}')='everyone'"),'pass rule is a neutral setting');
  assert.ok(migration.includes("if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'"),'simulated purchase refuses outside simulation');
  assert.doesNotMatch(migration,/\b(homme|femme|sexe|is_male|is_female|gender_|gender\s*=)/i,'no gender-based rule anywhere');
  assert.doesNotMatch(source,/stripe|paypal|revolut|card_number|iban/i,'no real payment code');
  assert.doesNotMatch(fs.readFileSync('src/public-config.js','utf8'),/sb_secret_|service_role|api-key/);
});
test('feedback appears after one hour of real use, can be postponed at most a few times, and is sent through the server only',()=>{
  for(const needle of ['function feedbackDialog','function maybeFeedback','usedMs()<60*60*1000','prorod-feedback-reminders','data-action="feedback-later"',"rpc('submit_feedback'",'name="score"','name="bug"'])assert.ok(source.includes(needle),needle);
  assert.doesNotMatch(source,/mailto:|brevo|api\.brevo\.com/i,'no e-mail sending from the client');
  assert.ok(migration.includes("vault.decrypted_secrets where name='brevo_api_key'"),'key read from the Vault only');
  assert.ok(admin.includes("admin_feedback"),'admin tab');
});
test('optional sign-in providers stay behind configuration flags and are off by default',()=>{
  const config=JSON.parse(fs.readFileSync('src/public-config.js','utf8').match(/export const config = (\{.*\});/)[1]);
  assert.deepEqual(config.providers,{google:false,phone:false});
  for(const needle of ["config.providers?.google","config.providers?.phone","signInWithOAuth({provider:'google'","signInWithOtp({phone:","verifyOtp({phone:phoneValue,token:values.code,type:'sms'})"])assert.ok(source.includes(needle),needle);
});
test('a landing page with a language choice comes before account creation, and chat translation is opt-in through the server only',()=>{
  for(const needle of ["mode='landing'","function landingView","function langChips",'data-mode="signup"','data-mode="signin"','Comment ça marche','How it works',"functions.invoke('translate'",'data-toggle="autotranslate"','data-action="translate-draft"','function autoTranslateThread'])assert.ok(source.includes(needle),needle);
  assert.doesNotMatch(source,/deepl\.com|DeepL-Auth-Key/,'no translation key or provider call in the client');
  const fn=fs.readFileSync('supabase/functions/translate/index.ts','utf8');
  for(const needle of ['Deno.env.get("DEEPL_API_KEY")','text.length > 2000','api-free.deepl.com','not_configured','req.headers.get("Authorization")'])assert.ok(fn.includes(needle),needle);
  assert.doesNotMatch(fn,/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}:fx/,'no key in the function source');
  const privacy=fs.readFileSync('public/confidentialite.html','utf8');
  assert.ok(privacy.includes('DeepL SE')&&privacy.includes('Translation (optional)')&&privacy.includes('Traduction (facultative)'),'privacy policy mentions translation in both languages');
});
test('chat only while both are checked in, refusals hold across visits, administrators always use two-step verification, admin portal in English too',()=>{
  const fn=fs.readFileSync('db/functions.sql','utf8');
  assert.ok(fn.includes("if not private.co_present_in(conv,uid) then raise exception 'visit_over'"),'send_message requires co-presence');
  assert.ok(fn.split('FUNCTION private.meeting_answer')[1].includes("raise exception 'visit_over'"),'meeting needs co-presence');
  assert.ok(fn.includes("(i.session_id=mine.id or i.status<>'accepted')) then raise exception 'introduction_exists'"),'refusals hold across visits');
  assert.ok(fn.split('FUNCTION private.require_admin')[1].includes("coalesce(claims->>'aal','') <> 'aal2' then raise exception 'mfa_required'"),'aal2 always');
  for(const needle of ["visit_over:[","t.live===false","mfa.challengeAndVerify","mfa.enroll({factorType:'totp'","getAuthenticatorAssuranceLevel","function mfaView","data-language","function localize","const EN=["])assert.ok((source+admin).includes(needle),needle);
  assert.ok(fs.readFileSync('public/admin.html','utf8').includes('data-language="en"'));
  assert.equal((fn.match(/CREATE OR REPLACE FUNCTION/g)||[]).length>100,true,'full function export present');
});
