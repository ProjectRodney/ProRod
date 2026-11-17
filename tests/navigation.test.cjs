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
