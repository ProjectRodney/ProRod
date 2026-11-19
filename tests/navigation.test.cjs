// Back and forward between the app's screens (17 Nov 2026): the phone's back gesture follows the app's screens.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const app=fs.readFileSync('src/account.js','utf8');
test('each screen change adds one history step, the back gesture restores the screen',()=>{
  assert.match(app,/root\.insertAdjacentHTML\('beforeend',memberNav\(\)\);syncHistory\(\);/);
  const f=app.slice(app.indexOf('function syncHistory('),app.indexOf('\n',app.indexOf('function syncHistory(')));
  assert.match(f,/if\(k===navKey\)return;/,'no step when the screen does not change');
  assert.match(f,/history\.pushState\(st,''\)/);assert.match(f,/history\.replaceState\(st,''\)/);
  assert.match(app,/window\.addEventListener\('popstate',e=>\{const st=e\.state;if\(!st\|\|!st\.upz\|\|!user\|\|recovery\|\|busy\)return;goBackTo\(st\);\}\);/);
});
test('only the screen name and a visible id are kept in the history, and going back never re-enters a place',()=>{
  const g=app.slice(app.indexOf('function goBackTo('),app.indexOf("window.addEventListener('popstate'"));
  assert.doesNotMatch(g,/join_venue|joinNow|buy-pass|buy_pass/);
  assert.match(g,/stopScan\(\);stopThread\(\);/);
  const n=app.slice(app.indexOf('const navId='),app.indexOf('\n',app.indexOf('const navId=')));
  assert.doesNotMatch(n,/display_name|email|birth|message|body/);
});
test('in the home-screen app, a swipe from the left edge goes back and from the right edge goes forward',()=>{
  assert.match(app,/const standaloneApp=\(\)=>navigator\.standalone===true\|\|matchMedia\('\(display-mode: standalone\)'\)\.matches;/);
  assert.match(app,/if\(!standaloneApp\(\)\|\|!user\|\|e\.touches\.length!==1\)return;/,'only in the home-screen app, never twice with the system gesture');
  assert.match(app,/if\(side==='back'\)history\.back\(\);else history\.forward\(\);/);
  assert.match(app,/if\(Math\.abs\(dy\)>Math\.abs\(dx\)&&Math\.abs\(dy\)>10\)\{edge=null;/,'scrolling up and down is not a swipe');
});
test('on the three main screens, a sideways slide moves between « Le lieu », « Messages » and « Profil »',()=>{
  assert.match(app,/const TAB_SCREENS=\{home:0,messages:1,settings:2\};/);
  const f=app.slice(app.indexOf("document.addEventListener('touchstart',e=>{tabSwipe=null;"),app.indexOf("document.addEventListener('touchcancel',()=>{tabSwipe=null;"));
  assert.match(f,/if\(t\.clientX<=28\|\|t\.clientX>=w-28\)return;/,'the screen edges stay for the back gesture');
  assert.match(f,/closest\('input,textarea,select,video/,'never while typing or scanning');
  assert.match(f,/Math\.abs\(dx\)<70/,'only a clear slide');
  assert.match(f,/document\.querySelectorAll\('nav\.member-nav button'\)\[next\]\?\.click\(\)/,'same as tapping the bottom menu');
});
test('Face ID after sign-out: offered on the welcome screen and in the e-mail autofill',()=>{
  assert.match(app,/autocomplete="\$\{mode==='signin'\?'username webauthn':'email'\}"/,'sign-in e-mail field offers passkeys in the autofill');
  assert.match(app,/client\.auth\.signInWithPasskey\(\{options:\{mediation:'conditional',signal:ac\.signal\}\}\)/);
  assert.match(app,/if\(action==='passkey-signin'\)\{stopPasskeyAutofill\(\);/,'one WebAuthn request at a time');
  assert.match(app,/if\(!user&&mode==='signin'\)passkeyAutofill\(\);else stopPasskeyAutofill\(\);/);
  assert.match(app,/passkeyReady\(\)&&passkeyOnPhone\(\)\?`<button class="button wide passkey-quick" data-action="passkey-signin">/);
  const mark=app.slice(app.indexOf('const markPasskeyPhone'),app.indexOf('\n',app.indexOf('const markPasskeyPhone')));
  assert.match(mark,/setItem\(PASSKEY_PHONE,'1'\)/,'only a flag is kept on the phone, never an account or a key');
});
test('the former github.io address sends the phone to the app’s own address, keeping its link',()=>{
  assert.match(app,/location\.hostname\.endsWith\('\.github\.io'\)&&location\.origin!==home\.origin\?new URL\('\.\/account\.html'\+location\.search\+location\.hash,home\)\.href:''/);
  assert.match(app,/if\(movedTo\)location\.replace\(movedTo\);/);
});
test('passkey changes on an account with two-step verification ask for the authenticator code, then resume',()=>{
  assert.match(app,/const needsCode=e=>\/insufficient_aal\//);
  assert.match(app,/if\(needsCode\(error\)\)\{pkPending=\{kind:'register'\};render\(\);/);
  assert.match(app,/client\.auth\.mfa\.challengeAndVerify\(\{factorId:totp\.id,code:String\(values\.totp\|\|''\)\.trim\(\)\}\)/);
  assert.match(app,/if\(p\?\.kind==='delete'\)await passkeyDeleteNow\(p\.id\);else await passkeyRegisterNow\(\);/);
  assert.match(app,/data-form="passkey-code"/);
});
