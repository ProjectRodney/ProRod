const test=require('node:test');const assert=require('node:assert');const fs=require('fs');
test('app icon badge shows only a count, from the in-app unread total, and asks permission only on a tap',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/function syncAppBadge\(\)\{if\(!\('setAppBadge' in navigator\)\)return;const n=user\?unreadTotal\(\):0;/);
  assert.match(s,/navigator\.setAppBadge\(n\)/);assert.match(s,/navigator\.clearAppBadge\(\)/);
  assert.equal((s.match(/Notification\.requestPermission\(\)/g)||[]).length,1,'permission requested in one place only');
  assert.match(s,/action==='badge-permission'\)\{try\{await Notification\.requestPermission\(\)/);
  assert.doesNotMatch(fs.readFileSync('public/sw.js','utf8'),/setAppBadge|my_inbox|my_notifications/,'no private data in the service worker');
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
