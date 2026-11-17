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
