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
test('product name comes from src/brand.js and no former working name remains', () => {
  const brand=fs.readFileSync('src/brand.js','utf8');assert.match(brand,/name: 'PRod'/);
  for(const file of ['public/index.html','public/account.html','public/app.js','public/install.js','public/sw.js','public/manifest.webmanifest','src/account.js'])assert.doesNotMatch(fs.readFileSync(file,'utf8'),/Z[ée]lo|M[êe]la/i,file);
});
