// Account switching (17 Nov 2026, client request): a person can keep a personal and a professional account on the same
// phone and go from one to the other without retyping a password. Each account stays a separate Supabase account;
// only the sign-in of the accounts that are not open is kept on this phone.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');
const source=fs.readFileSync('src/account.js','utf8');
const pick=(start,end)=>{const i=source.indexOf(start);assert.ok(i>=0,start);const j=source.indexOf(end,i);assert.ok(j>i,end);return source.slice(i,j);};
const code=pick('const ACCOUNTS_KEY=','function switchFailed(');
function sandbox({user={id:'me',email:'me@example.invalid'},accountType='pro',stored=[],setSession}={}){
  const store=new Map();if(stored.length)store.set('upzone-accounts',JSON.stringify(stored));store.set('prorod-auth','{"current":true}');
  const calls=[];const c=vm.createContext({lang:'en',T:(en)=>en,esc:s=>String(s??'').replace(/[&<>"']/g,''),user,profile:{display_name:'Pro me'},accountType,calls,
    localStorage:{getItem:k=>store.has(k)?store.get(k):null,setItem:(k,v)=>store.set(k,String(v)),removeItem:k=>store.delete(k)},
    sessionStorage:{setItem:(k,v)=>calls.push(['session',k,v])},
    location:{replace:u=>calls.push(['go',u])},
    client:{auth:{stopAutoRefresh:()=>calls.push(['stop']),getSession:async()=>({data:{session:{access_token:'AT-me',refresh_token:'RT-me'}}}),setSession:async(s)=>{calls.push(['set',s.refresh_token]);return setSession?setSession(s):{data:{session:{}},error:null};}}}});
  vm.runInContext(code,c);return {c,store,calls};
}
const other={id:'perso',name:'Perso me',type:'personal',login:'perso@example.invalid',at:'AT-p',rt:'RT-p'};

test('settings show a switch button for each other account on the phone, never the open one, never a token',()=>{
  const {c}=sandbox({stored:[other,{...other,id:'me',name:'Pro me',rt:'RT-old'}]});
  const h=vm.runInContext('switchRow()',c);
  assert.equal((h.match(/data-action="switch-account"/g)||[]).length,1);
  assert.match(h,/Switch to Perso me · Personal/);
  assert.match(h,/data-action="add-account"/);assert.match(h,/data-action="forget-account"/);
  assert.doesNotMatch(h,/RT-|AT-/,'tokens never reach the page');
  const none=sandbox().c;const e=vm.runInContext('switchRow()',none);
  assert.doesNotMatch(e,/switch-account/);assert.match(e,/Add an account \(personal or professional\)/);
});

test('switching keeps the open account on the phone, opens the other one, and removes it from the waiting list',async()=>{
  const {c,store,calls}=sandbox({stored:[other]});
  await vm.runInContext('switchTo("perso")',c);
  assert.deepEqual(calls[0],['stop'],'no token refresh while switching');
  assert.ok(calls.some(x=>x[0]==='set'&&x[1]==='RT-p'));
  const left=JSON.parse(store.get('upzone-accounts'));
  assert.deepEqual(left.map(a=>a.id),['me']);assert.equal(left[0].rt,'RT-me');assert.equal(left[0].type,'pro');
  assert.deepEqual(calls.at(-1),['go','./account.html']);
});

test('a refused sign-in drops that account and reopens the previous one',async()=>{
  const {c,store,calls}=sandbox({stored:[other],setSession:s=>s.refresh_token==='RT-p'?{data:{session:null},error:{message:'revoked'}}:{data:{session:{}},error:null}});
  await vm.runInContext('switchTo("perso")',c);
  assert.ok(calls.some(x=>x[0]==='set'&&x[1]==='RT-me'),'back to the account that was open');
  assert.equal(store.get('upzone-accounts'),undefined,'neither account left waiting');
  assert.ok(calls.some(x=>x[0]==='session'&&x[1]==='upzone-switch-failed'));
  assert.deepEqual(calls.at(-1),['go','./account.html']);
});

test('adding an account keeps the open one and goes to the sign-in screen without signing it out',async()=>{
  const {c,store,calls}=sandbox();
  await vm.runInContext('addAccount()',c);
  assert.equal(store.get('prorod-auth'),undefined);
  assert.equal(JSON.parse(store.get('upzone-accounts'))[0].rt,'RT-me');
  assert.deepEqual(calls.at(-1),['go','./account.html?start=signin']);
  assert.doesNotMatch(code,/signOut/,'a server sign-out would revoke the kept account');
});

test('the switch is offered on the profile screen, the event screens and the sign-in screens; the open account is never kept twice',()=>{
  assert.match(source,/<\/p><\/div><\/div>\$\{switchRow\(\)\}/);
  assert.equal(source.split('${switchRow()}<button data-action="signout"').length-1,2);
  assert.match(source,/mode==='landing'\)return savedRow\(\)\+landingView\(\)/);
  assert.match(source,/mode==='signin'\?savedRow\(\):''/);
  assert.match(source,/if\(savedAccounts\(\)\.some\(a=>a\.id===user\.id\)\)storeAccounts\(savedAccounts\(\)\.filter\(a=>a\.id!==user\.id\)\);/);
  assert.match(source,/action==='forget-account'\)\{if\(!confirm\(/);
});
