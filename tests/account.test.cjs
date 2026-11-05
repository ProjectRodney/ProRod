const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
test('built account client parses and is included in offline shell',()=>{
  new vm.Script(fs.readFileSync('public/account.bundle.js','utf8'));
  assert.match(fs.readFileSync('public/sw.js','utf8'),/account\.bundle\.js/);
  assert.equal(JSON.parse(fs.readFileSync('public/manifest.webmanifest')).start_url,'./account.html');
});
test('all local account assets exist and no secret key is in public configuration',()=>{
  const page=fs.readFileSync('public/account.html','utf8');
  for(const match of page.matchAll(/(?:src|href)="\.\/([^"#?]+)"/g))assert.ok(fs.existsSync('public/'+match[1]),match[1]);
  const config=fs.readFileSync('src/public-config.js','utf8');
  assert.match(config,/sb_publishable_/);
  assert.doesNotMatch(config,/sb_secret_|service_role/);
});
test('private auth/API calls and token-bearing assets bypass the offline cache',()=>{
  const handlers={};
  vm.runInNewContext(fs.readFileSync('public/sw.js','utf8'),{URL,self:{registration:{scope:'https://test.example/'},location:{origin:'https://test.example'},addEventListener:(name,fn)=>handlers[name]=fn}});
  for(const url of ['https://blqcmpqctetmjqsfdvsq.supabase.co/auth/v1/user','https://test.example/account.bundle.js?access_token=secret','https://test.example/rest/v1/profiles']){
    let called=false;handlers.fetch({request:{url,method:'GET',mode:'cors'},respondWith(){called=true;}});assert.equal(called,false);
  }
});
