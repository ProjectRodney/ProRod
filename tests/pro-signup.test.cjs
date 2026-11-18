// Pro & event sign-up (18 Nov 2026, client request): « Professionnel ou événement ? » → kind → activity or place type → account.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');
const src=fs.readFileSync('src/account.js','utf8');
const pick=(a,b)=>{const i=src.indexOf(a);assert.ok(i>=0,a);return src.slice(i,src.indexOf(b,i));};
function ctx(store={}){const c=vm.createContext({T:(en)=>en,PRO_CATS:()=>['DJ','Music','Photo','Barber','Beauty','Artist','Coach','Organiser','Other'],catName:k=>k,localStorage:{getItem:k=>store[k]??null,setItem:(k,v)=>{store[k]=v;},removeItem:k=>{delete store[k];}}});vm.runInContext(pick('const INTENT_KEY=','function proStep(').replace('let proIntent=','var proIntent='),c);return c;}

test('the remembered choice is checked and only used for the account that made it',()=>{
  const c=ctx();
  assert.equal(vm.runInContext("cleanIntent({kind:'admin',cat:'dj'})",c),null,'unknown kinds are dropped');
  assert.equal(vm.runInContext("cleanIntent({kind:'pro',cat:'nightclub'}).cat",c),null,'a category must belong to its kind');
  assert.equal(vm.runInContext("cleanIntent({kind:'event',cat:'pub',name:'x'.repeat(300)}).name.length",c),100);
  vm.runInContext("saveIntent({kind:'pro',cat:'dj',name:'DJ Nova',email:'Nova@Example.invalid'})",c);
  assert.equal(vm.runInContext("intentFor({email:'nova@example.invalid',user_metadata:{}}).cat",c),'dj');
  assert.equal(vm.runInContext("intentFor({email:'someone@example.invalid',user_metadata:{}})",c),null,'another account on the same phone never inherits it');
  assert.equal(vm.runInContext("intentFor({email:'other@example.invalid',user_metadata:{signup_intent:{kind:'event',cat:'pub'}}}).kind",c),'event','an e-mail link opened in another browser still works');
});
test('the choice only preselects: the type goes through set_account_type, approval stays with the team',()=>{
  assert.match(src,/if\(!accountType\)\{const it=intentFor\(user\);if\(it\)\{try\{const t=it\.kind==='event'\?'venue':'pro';await rpc\('set_account_type',\{p_type:t\}\)/);
  assert.match(src,/options:\{emailRedirectTo:redirect,\.\.\.\(proSignup\?\{data:\{signup_intent:\{kind:proIntent\.kind,cat:proIntent\.cat,name:proIntent\.name\}\}\}:\{\}\)\}/);
  assert.doesNotMatch(src,/user_metadata\?\.signup_intent[^;]*(is_admin|prod_admin|approved)/);
});
test('welcome button opens the three steps; « vous » on these screens; radios keep their choice when the screen redraws',()=>{
  assert.match(src,/<button class="pro-entry-btn" data-mode="pro-kind">/);
  assert.match(src,/if\(mode==='pro-kind'\)return proKindView\(\);/);
  assert.match(src,/\|\|\(!user&&String\(mode\)\.startsWith\('pro-'\)\)/);
  assert.match(src,/if\(el\.type==='radio'\)\{if\(el\.checked\)o\[el\.name\]=el\.value;return;\}/);
  assert.doesNotMatch(src,/Everything a person can do/,'pros are no longer described as able to meet people');
});
