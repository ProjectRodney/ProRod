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
  assert.match(fn,/JSON\.stringify\(\{ title: "ANZIAK", body: data\.lang === "en" \? en : fr, badge, tag: data\.kind \|\| "anziak", url: "\.\/account\.html" \}\)/);
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
test('ANZIAK icons exist at the declared sizes and the iPhone icon is 180 px',()=>{
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
  assert.match(fs.readFileSync('src/account.js','utf8'),/avatar-initial/);
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
