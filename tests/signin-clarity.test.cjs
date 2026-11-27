// Sign-in screen and first screen (27 Nov 2026, after a tester reported « j'appuie sur connexion plusieurs fois en vain »).
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');
const app=fs.readFileSync('src/account.js','utf8');

test('tapping the tab that is already open leads to the e-mail field instead of doing nothing',()=>{
  assert.match(app,/if\(target\.dataset\.mode===mode&&!user&&\(mode==='signin'\|\|mode==='signup'\)\)\{const d=root\.querySelector\('details\.email-method'\);if\(d\)d\.open=true;/);
  assert.match(app,/f\.scrollIntoView\(\{block:'center'\}\);f\.focus\(\);\}return;\}/);
});
test('the e-mail form comes first unless this phone already signed in with a passkey',()=>{
  assert.match(app,/\$\{passkeyOnPhone\(\)&&mode==='signin'\?providersBlock\(\):''\}<details class="email-method"/);
  assert.match(app,/<\/details>\$\{passkeyOnPhone\(\)&&mode==='signin'\?'':providersBlock\(\)\}/);
});
test('the passkey attempt made in the background never shows an error by itself',()=>{
  const f=app.slice(app.indexOf('function passkeyAutofill'),app.indexOf('function passkeyMessage'));
  assert.ok(!f.includes('notice('),'only the passkey button, tapped by the member, reports an error');
  assert.match(f,/markPasskeyPhone\(\);mode='signin';await load\(\);/);
});
test('a member already in a place opens the app on the list, once, and never a pro or event account',()=>{
  assert.match(app,/const first=!opened;opened=true;render\(\);/);
  assert.match(app,/if\(first&&view==='home'&&live\(\)&&complete\(profile\)&&!isPro\(\)&&!isVenue\(\)&&!invite&&!venue&&!recovery\)\{loadPeople\(\)\.catch\(\(\)=>\{view='home';render\(\);\}\);\}/);
});
test('« Te revoilà » leads to the list, with or without taking the pass again',()=>{
  const v=app.slice(app.indexOf('function backView'),app.indexOf('function backView')+2400);
  assert.ok(v.includes('data-action="people"')&&v.includes('Voir qui est là'));
  assert.match(app,/else if\(view==='people'\|\|view==='back'\)\{await loadPeople\(\);\}/);
});
