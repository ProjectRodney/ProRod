// Forgotten password (20 Nov 2026): own screens, same answer whether or not the account exists, code from the e-mail,
// and the two-step code asked when the account is protected by an authenticator app.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const s=fs.readFileSync('src/account.js','utf8'),tu=fs.readFileSync('src/tu.js','utf8'),mail=fs.readFileSync('supabase/templates/reset-password.html','utf8');
test('« Mot de passe oublié ? » opens its own screen, then « check your e-mails »',()=>{
  assert.match(s,/if\(action==='reset'\)\{forgotPrefill=document\.getElementById\('email'\)\?\.value\?\.trim\(\)\|\|'';mode='forgot';/);
  assert.match(s,/if\(resetEmail\)return resetSentView\(\);if\(mode==='forgot'\)return forgotView\(\);/);
  assert.match(s,/case 'forgot':\{[\s\S]{0,200}resetPasswordForEmail\(addr,\{redirectTo:redirect\}\);if\(error\)throw error;forgotPrefill='';setResetEmail\(addr\);/);
});
test('the answer does not say whether an account exists for the address',()=>{
  assert.match(s,/T\('If an account exists for','Si un compte existe pour'\)/);
  const sent=s.slice(s.indexOf('function resetSentView'),s.indexOf('function newPasswordView'));
  assert.doesNotMatch(sent,/no account|aucun compte|introuvable|not found/i);
});
test('the code written in the e-mail opens the new-password screen without leaving the app',()=>{
  assert.match(s,/case 'reset-code':\{const \{error\}=await client\.auth\.verifyOtp\(\{email:resetEmail,token:String\(values\.resetCode\|\|''\)\.trim\(\),type:'recovery'\}\)/);
  assert.equal((mail.match(/\{\{ \.Token \}\}/g)||[]).length,2,'one code per language branch');
  assert.match(mail,/\{\{ if \.Data\.mail_en \}\}[\s\S]*Your code[\s\S]*\{\{ else \}\}[\s\S]*Ton code[\s\S]*\{\{ end \}\}/,'English only for accounts set to English, French otherwise');
  assert.doesNotMatch(mail,/ConfirmationURL/,'no button: a single code (client request, 20 Nov)');
  assert.match(s,/localStorage\.setItem\('upzone-reset-email',JSON\.stringify\(\{email:v,at:Date\.now\(\)\}\)\)/,'the screen survives closing the app to read the e-mail');
  assert.match(s,/Date\.now\(\)-r\.at<3600000/,'for one hour only');
});
test('an account protected by an authenticator app is asked for its code before the password changes',()=>{
  assert.match(s,/getAuthenticatorAssuranceLevel\(\)\.then\(\(\{data\}\)=>\{if\(data&&data\.nextLevel==='aal2'&&data\.currentLevel!=='aal2'&&recovery\)\{pwNeedsCode=true;/);
  assert.match(s,/case 'password':\{if\(values\.totp\)\{[\s\S]{0,400}challengeAndVerify\(\{factorId:totp\.id,code:String\(values\.totp\)\.trim\(\)\}\)/);
  assert.ok(s.includes("if(/insufficient_aal|aal2/i.test("),'the refusal is recognised');
  assert.ok(s.includes("&&!values.totp){pwNeedsCode=true;pwDraft=String(values.password||'');render();"),'a refusal shows the code field and keeps what was typed');
});
test('a confirmation screen follows, and the new password needs 12 characters',()=>{
  assert.match(s,/recovery=false;pwNeedsCode=null;setResetEmail\(null\);passwordDone=true;/);
  assert.match(s,/root\.innerHTML=recovery&&user\?newPasswordView\(\):passwordDone&&user\?passwordDoneView\(\)/);
  const v=s.slice(s.indexOf('function newPasswordView'),s.indexOf('function passwordDoneView'));
  assert.match(v,/required minlength="12" autocomplete="new-password"/);
});
test('personal accounts read the new screens with « tu »',()=>{
  for(const t of ['Consulte tes e-mails','Saisis l’adresse e-mail de ton compte','Ton nouveau mot de passe est enregistré'])assert.ok(tu.includes(t),t);
});
test('the e-mail language follows the member\'s language: one flag in the account metadata, never an authorisation',()=>{
  assert.match(s,/function syncMailLang\(\)\{if\(!user\)return;const want=lang==='en';if\(!!user\.user_metadata\?\.mail_en===want\)return;/);
  assert.match(s,/client\.auth\.updateUser\(\{data:\{mail_en:want\}\}\)/);
  assert.match(s,/data:\{mail_en:lang==='en',/,'set at sign-up too');
  assert.doesNotMatch(s,/mail_en[^;]{0,120}(is_admin|prod_admin|approved|require_)/,'mail_en only chooses a language');
});
