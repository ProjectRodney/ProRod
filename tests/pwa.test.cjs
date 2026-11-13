const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
test('PWA manifest uses real local icon and relative deployment scope', () => {
  const manifest=JSON.parse(fs.readFileSync('public/manifest.webmanifest','utf8'));
  assert.equal(manifest.display,'standalone');assert.equal(manifest.scope,'./');
  for(const icon of manifest.icons){const bytes=fs.readFileSync('public/'+icon.src);assert.equal(icon.sizes,`${bytes.readUInt32BE(16)}x${bytes.readUInt32BE(20)}`);}
});
test('service worker intercepts shell only, not private data or POST', () => {
  const handlers={};
  vm.runInNewContext(fs.readFileSync('public/sw.js','utf8'),{URL,self:{registration:{scope:'https://test.example/ProRod/'},location:{origin:'https://test.example'},addEventListener:(name,fn)=>handlers[name]=fn}});
  for(const [path,method] of [['api/messages','GET'],['reports','GET'],['index.html','POST'],['app.js?token=secret','GET']]){
    let intercepted=false;handlers.fetch({request:{url:'https://test.example/ProRod/'+path,method,mode:'cors'},respondWith(){intercepted=true;}});assert.equal(intercepted,false,path);
  }
});
test('browser scripts parse and no camera capture exists', () => {
  for(const file of ['app.js','install.js','sw.js'])new vm.Script(fs.readFileSync('public/'+file,'utf8'));
  const source=fs.readFileSync('public/app.js','utf8');assert.doesNotMatch(source,/getUserMedia|capture="user"/);
});
test('legal pages exist in both languages and are linked from the app',()=>{
  for(const file of ['public/confidentialite.html','public/cgu.html']){const html=fs.readFileSync(file,'utf8');assert.match(html,/id="fr" lang="fr"/);assert.match(html,/id="en" lang="en"/);}
  assert.match(fs.readFileSync("public/cgu.html","utf8"),/112/);
  const app=fs.readFileSync('src/account.js','utf8');assert.ok(app.includes('./confidentialite.html')&&app.includes('./cgu.html'));
});
test('product name comes from src/brand.js and no former working name remains', () => {
  const brand=fs.readFileSync('src/brand.js','utf8');assert.match(brand,/name: 'UPZONE'/);
  for(const file of ['public/index.html','public/account.html','public/app.js','public/install.js','public/sw.js','public/manifest.webmanifest','src/account.js','public/admin.html','public/cgu.html','public/confidentialite.html','public/demo.html','public/pwa-install.js','src/admin.js','supabase/functions/send-sms/index.ts'])assert.doesNotMatch(fs.readFileSync(file,'utf8'),/Z[ée]lo|M[êe]la|P\.Rod|prod-logo/i,file);
});

test('the URL is an installer: welcome page with install button, app banner, manifest and iOS metadata',()=>{
  const index=fs.readFileSync('public/index.html','utf8'), account=fs.readFileSync('public/account.html','utf8'), helper=fs.readFileSync('public/pwa-install.js','utf8');
  assert.match(index,/data-install="button"/);assert.match(index,/rel="manifest"/);assert.match(index,/apple-mobile-web-app-capable/);
  assert.match(account,/data-install="banner"/);assert.match(account,/pwa-install\.js/);
  new vm.Script(helper);assert.match(helper,/beforeinstallprompt/);assert.match(helper,/Sur l’écran d’accueil/);assert.doesNotMatch(helper,/getUserMedia/);
  const manifest=JSON.parse(fs.readFileSync('public/manifest.webmanifest','utf8'));assert.equal(manifest.display,'standalone');assert.equal(manifest.short_name,'UPZONE');
});
test('the service worker always revalidates the app shell, so a release shows on the next reload',()=>{
  const sw=fs.readFileSync('public/sw.js','utf8');
  assert.equal((sw.match(/cache: 'no-cache'/g)||[]).length,2,'pages and shell files');
  assert.match(sw,/self\.skipWaiting\(\)/);
});
