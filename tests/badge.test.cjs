const test=require('node:test');const assert=require('node:assert');const fs=require('fs');
test('app icon badge shows only a count, from the in-app unread total; permission asked only on a tap',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/function syncAppBadge\(\)\{if\(!\('setAppBadge' in navigator\)\)return;const n=user\?unreadTotal\(\):0;/);
  assert.match(s,/navigator\.setAppBadge\(n\)/);assert.match(s,/navigator\.clearAppBadge\(\)/);
  assert.equal((s.match(/Notification\.requestPermission\(\)/g)||[]).length,1,'permission requested in one place only');
  assert.match(s,/async function pushEnable\(\)\{const perm=await Notification\.requestPermission\(\)/);
  assert.match(s,/action==='push-on'\)\{await pushEnable\(\);\}/);
});
test('push notifications: generic text only, private subscriptions, removed at sign-out and account deletion',()=>{
  const s=fs.readFileSync('src/account.js','utf8'),sw=fs.readFileSync('public/sw.js','utf8'),fn=fs.readFileSync('supabase/functions/send-push/index.ts','utf8'),db=fs.readFileSync('db/2026-11-07-push-notifications.sql','utf8');
  assert.match(s,/action==='signout'\)\{await pushDisable\(true\);/);assert.match(s,/await pushDisable\(true\);await rpc\('delete_account'\)/);
  assert.match(s,/userVisibleOnly:true,applicationServerKey:keyBytes\(config\.vapidPublicKey\)/);
  assert.doesNotMatch(sw,/my_inbox|my_notifications|supabase|localStorage|indexedDB/,'no private data or API calls in the service worker');
  assert.match(sw,/target\.startsWith\(self\.registration\.scope\)/,'notification click only opens app pages');
  // the push payload is built from the notification kind only, never its payload (names, conversation ids)
  assert.match(db,/body:=jsonb_build_object\('kind',new\.kind,'lang',coalesce\(lang,'fr'\),'badge',private\.unread_total\(new\.user_id\),'subscriptions',subs\)/);
  assert.doesNotMatch(db,/new\.payload/);
  assert.match(fn,/JSON\.stringify\(\{ title: "UPZONE", body: data\.lang === "en" \? en : fr, badge, tag: data\.kind \|\| "upzone", url: "\.\/account\.html" \}\)/);
  assert.match(fn,/sameSecret\(req\.headers\.get\("x-push-secret"\)/);assert.doesNotMatch(fn,/VAPID_PRIVATE_KEY\s*=\s*"/);
  assert.match(db,/revoke all on public\.push_subscriptions from anon, authenticated;/);
  assert.match(db,/private\.save_push_subscription[\s\S]*?private\.require_member\(\)/);
  assert.match(db,/delete from public\.push_subscriptions where endpoint=p_endpoint and user_id=uid;/);
  const cfg=fs.readFileSync('src/public-config.js','utf8');assert.match(cfg,/"vapidPublicKey":"B[A-Za-z0-9_-]{86}"/);
});
test('one account, several sign-in methods: phone or e-mail added to the current account',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/client\.auth\.updateUser\(\{phone:values\.linkPhone\}\)/);
  assert.match(s,/verifyOtp\(\{phone:linkPhone,token:values\.linkCode,type:'phone_change'\}\)/);
  assert.match(s,/client\.auth\.updateUser\(\{email:values\.linkEmail\},\{emailRedirectTo:redirect\}\)/);
});
test('UPZONE icons exist at the declared sizes and the iPhone icon is 180 px',()=>{
  const b=fs.readFileSync('public/assets/apple-touch-icon.png');assert.equal(b.readUInt32BE(16),180);
  for(const f of ['account.html','index.html'])assert.match(fs.readFileSync('public/'+f,'utf8'),/rel="apple-touch-icon" href="\.\/assets\/apple-touch-icon\.png"/);
});
test('password fields: eye toggle everywhere, strong suggestion only on new passwords, crypto generator, clear e-mail sending error',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/data-pw-toggle=/);assert.match(s,/\/new-password\/\.test\(extra\)\?`<button type="button" class="link pw-suggest"/);
  const gen=s.slice(s.indexOf('function strongPassword'),s.indexOf('function setPwVisible'));
  assert.match(gen,/crypto\.getRandomValues/);assert.doesNotMatch(gen,/Math\.random/);
  assert.match(s,/autocomplete="\$\{mode==='signup'\?'new-password':'current-password'\}"/);
  assert.match(s,/confirmation email could not be sent/);
});
test('accounts confirmed by phone only are verified members (require_member)',()=>{
  for(const f of ['db/functions.sql','db/accounts-and-venues.sql','db/2026-11-07-phone-members.sql'])
    assert.match(fs.readFileSync(f,'utf8'),/\(email_confirmed_at is not null or phone_confirmed_at is not null\) and coalesce\(is_anonymous,false\)=false/,f);
});
test('push_status checks membership before reading anything (fix found by check 8b)',()=>{
  for(const f of ['db/2026-11-07-push-notifications.sql','db/2026-11-07-push-status-fix.sql','db/functions.sql']){
    const s=fs.readFileSync(f,'utf8').replace(/\r\n/g,'\n');const fn=s.slice(s.indexOf('function private.push_status()'));
    assert.match(fn,/^function private\.push_status\(\) returns jsonb language plpgsql[^$]*\$\$\ndeclare uid uuid := private\.require_member\(\);/,f);
  }
});
test('typed form values survive a redraw (refused save, language switch, counts refresh); passwords and files never copied',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/function render\(\)\{const drafts=snapshotForms\(\);/);assert.match(s,/;restoreForms\(drafts\);/);
  assert.match(s,/\['password','file','hidden','submit'\]\.includes\(el\.type\)/);
  assert.match(s,/form\.querySelector\('#photo'\)\?\.files\?\.\[0\]\|\|pendingPhoto/);
  assert.match(s,/!root\.querySelector\('form\[data-form\] :focus'\)\)render\(\)/);
  for(const k of ['rules_required','unsupported_language','name_length'])assert.ok(s.includes(k+':['),k);
});
test('a failed SMS code says so instead of the generic message',()=>{
  const s=fs.readFileSync('src/account.js','utf8');assert.match(s,/The SMS code could not be sent\./);assert.equal((s.match(/error.smsStep=true/g)||[]).length,2,'sign-in and add-number both tagged');
});
test('SMS hook sends the code to the new number when a phone is added (phone_change), never logs numbers or codes',()=>{
  const s=fs.readFileSync('supabase/functions/send-sms/index.ts','utf8');
  assert.match(s,/data\.sms\?\.new_phone \|\| data\.new_phone/);
  for(const line of s.split('\n').filter(l=>/console\./.test(l)))assert.doesNotMatch(line,/[,(]\s*(phone|otp|content|target|payload)\s*[,)]/,'never log the number, the code or the text: '+line.trim());
});
test('passkeys: behind a flag, offered once after sign-in, SMS/e-mail stay as fallback, cancel handled',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/const passkeyReady=\(\)=>!!\(config\.providers\?\.passkey&&window\.PublicKeyCredential&&window\.isSecureContext\)/);
  assert.match(s,/client\.auth\.signInWithPasskey\(\)/);assert.match(s,/client\.auth\.registerPasskey\(\)/);assert.match(s,/client\.auth\.passkey\.delete\(\{passkeyId:target\.dataset\.id\}\)/);
  assert.match(s,/ERROR_CEREMONY_ABORTED/);assert.match(s,/\$\{pk\}\$\{g\}\$\{ph\}/,'passkey first, other methods still offered');
  assert.match(s,/passkeyLaterKey\(\)/);
});
test('a venue is joined only by scanning its QR code: no typed invitation code anywhere in the member app',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.doesNotMatch(s,/data-form="invite"/);assert.doesNotMatch(s,/case 'invite':/);
  assert.doesNotMatch(s,/Enter a code instead|Saisir un code|Venue invitation code/);
  assert.match(s,/data-action="scan"/);assert.match(s,/searchParams\.get\('venue'\)/,'the QR link (camera app) still works');
});
test('a member without a readable photo shows an initial, never a broken image',()=>{
  assert.match(fs.readFileSync('src/account.js','utf8'),/pin-initial/);assert.match(fs.readFileSync('src/account.js','utf8'),/function pinPhoto\(m,size\)/);
});
test('test bots: only fictional accounts, only the test venue, only when switched on, through the app functions',()=>{
  const s=fs.readFileSync('db/2026-11-10-test-bots.sql','utf8');
  assert.match(s,/if coalesce\(\(private\.setting\('test_bots'\) #>> '\{\}'\)::boolean,false\) is not true then return 0;/);
  assert.ok((s.match(/like '%\.test@example\.invalid'/g)||[]).length>=5,'every step limited to fictional accounts');
  for(const f of ['public.respond_introduction(','public.send_message(','public.meeting_answer(','public.send_introduction(','public.buy_pass_simulated()'])assert.ok(s.includes(f),f);
  assert.doesNotMatch(s,/insert into public\.(messages|introductions|conversations|passes)/,'bots never write around the rules');
  assert.match(s,/revoke all on function private\.run_test_bots\(\) from public, anon, authenticated/);
  const seed=fs.readFileSync('db/seed-test-venue.sql','utf8');assert.match(seed,/REPLACE_WITH_TOKEN_HASH/);assert.match(seed,/set value='false' where key='test_bots'/);
});
test('incomplete e-mail addresses and expired e-mail links get a clear message',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  const m=s.match(/const validEmail=v=>(\/.*?\/)\.test/);assert.ok(m);const re=eval(m[1]);
  for(const ok of ['name@yahoo.fr','a.b@mail.example.com'])assert.ok(re.test(ok),ok);
  for(const bad of ['name@yahoo.','name@yahoo','name@.fr','na me@yahoo.fr'])assert.ok(!re.test(bad),bad);
  assert.match(s,/case 'auth':\{values\.email=String\(values\.email\|\|''\)\.trim\(\);if\(!validEmail\(values\.email\)\)/);assert.match(s,/if\(!validEmail\(email\.value\)\)/);
  assert.match(s,/otp_expired/);assert.ok((s.match(/showLinkError\(\)/g)||[]).length>=3,'link message shown on every signed-out path');assert.match(s,/validation_failed:\[/);
});
test('« who would you like to see »: optional, explicit consent, private, filters only the viewer\'s own venue list on the server',()=>{
  const s=fs.readFileSync('src/account.js','utf8'),db=fs.readFileSync('db/2026-11-10-interest-filter.sql','utf8');
  assert.match(s,/if\(values\.interest&&values\.interestConsent!=='on'\)/,'consent checked before saving');
  assert.match(db,/if p_consent is distinct from true then raise exception 'interest_consent_required'/);
  assert.match(db,/check \(interested_in is null or interest_consent_at is not null\)/,'no choice without a consent date');
  assert.match(db,/interested_in=null, interest_consent_at=null/,'withdrawal erases consent');
  const vm=db.slice(db.indexOf('function private.venue_members'));
  assert.match(vm,/returns table\(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone\)/,'no gender or preference returned');
  assert.match(vm,/wants is null or wants='everyone'/);
  assert.doesNotMatch(fs.readFileSync('db/functions.sql','utf8').slice(0,0)+s,/interested_in[^']*display/);
  const card=fs.readFileSync('db/functions.sql','utf8');const mc=card.slice(card.indexOf('FUNCTION private.member_card'),card.indexOf('$function$;',card.indexOf('FUNCTION private.member_card')));
  assert.doesNotMatch(mc,/interested_in|gender/,'member cards never show gender or preference');
});
test('meeting of 10 November: height on the profile, report = automatic block, warnings, conversation end reasons',()=>{
  const db=fs.readFileSync('db/2026-11-10-height-safety.sql','utf8'),s=fs.readFileSync('src/account.js','utf8'),a=fs.readFileSync('src/admin.js','utf8');
  assert.match(db,/check \(height_cm is null or height_cm between 120 and 230\)/);
  assert.match(db,/perform private\.block_member\(p_user\);/,'a report blocks the reported person for the reporter');
  assert.match(db,/'harassment','insults','inappropriate'/);
  assert.match(db,/function private\.admin_warn_member\(p_report uuid, p_message text\)[\s\S]*?private\.require_admin\(\)/,'only admins warn');
  assert.match(db,/closed_reason in \('not_available','left_venue','not_interested','other'\)/);
  assert.match(s,/rpc\('end_conversation',\{p_id:target\.dataset\.conversation,p_reason:reason\}\)/);
  assert.match(s,/rpc\('set_height',\{p_cm:/);assert.match(a,/rpc\('admin_warn_member'/);
  assert.match(s,/Stay respectful\. Insults, vulgar language or harassment/);
});
test('veiled venue (11 November): nothing identifying before the pass, département + age range, photos and introductions follow the pass',()=>{
  const db=fs.readFileSync('db/2026-11-11-veiled-venue.sql','utf8'),s=fs.readFileSync('src/account.js','utf8'),v=fs.readFileSync('db/verify-veiled-venue.sql','utf8');
  const vm=db.slice(db.indexOf('create or replace function private.venue_members()'),db.indexOf('end $function$;',db.indexOf('create or replace function private.venue_members()')));
  for(const col of ['p.user_id','p.display_name','p.bio','p.avatar_path','s.started_at','p.height_cm'])assert.ok(vm.includes(`case when open then ${col} end`),`${col} only once unlocked`);
  assert.match(vm,/case when open then date_part\('year', age\(p\.birth_date\)\)::integer end/,'exact age only once unlocked');
  assert.match(vm,/open := private\.venue_unlocked\(uid, mine\.venue_id\)/);
  assert.match(db,/is distinct from 'everyone'[\s\S]*?p\.kind='venue_pass' and p\.expires_at>now\(\)/,'unlocked = no pass rule or an active pass for that venue');
  assert.match(db,/when a <= 20 then '18-20' else \(21 \+ 5\*\(\(a-21\)\/5\)\)/,'age ranges 18-20 then steps of five');
  assert.match(db,/private\.photo_visible\(\(select auth\.uid\(\)\)/,'storage photos follow the same rule');
  assert.match(db,/if not private\.venue_unlocked\(uid, mine\.venue_id\) then raise exception 'pass_required'/,'introductions need the pass');
  assert.match(db,/revoke all on function private\.age_band\(date\) from public, anon, authenticated/);
  assert.doesNotMatch(db,/gender'?\s*=\s*'(woman|man)'[\s\S]{0,80}pass/,'never a pass rule based on gender');
  assert.match(v,/PASS: veiled venue/);
  assert.match(s,/rpc\('set_department',\{p_department:/);
  assert.match(s,/function personCard\(m\)\{if\(m\.veiled\)return veiledCard\(m\);/);
  assert.match(s,/function veiledCard\(m\)\{return `<div class="person veiled">/,'veiled cards are not clickable');
  assert.doesNotMatch(s.slice(s.indexOf('function veiledCard'),s.indexOf('function personCard')),/display_name|user_id|bio|photo/,'veiled card shows nothing identifying');
});
