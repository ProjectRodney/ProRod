const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('src/account.js','utf8');
function extract(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\nfunction ',start+1);return source.slice(start,end);}
function context(overrides={}){return vm.createContext({T:(en,fr)=>en,esc:s=>String(s??''),user:{email:'fixture@example.invalid'},profile:{display_name:'Test member',birth_date:'1995-01-01',locale:'en',bio:'Hello'},avatarUrl:'',passes:[],isAdmin:false,isVenue:()=>false,isPro:()=>false,complete:()=>true,recovery:false,view:'home',unreadTotal:()=>2,age:()=>31,field:()=>'<input name="displayName">',photoField:()=>'<input name="photo" type="file">',pushBlock:()=>'<h3>Notifications</h3><button data-action="push-on">Enable</button>',passkeysBlock:()=>'<h3>Passkeys</h3><button data-action="passkey-register">Add</button>',signInMethodsBlock:()=>'<h3>Ways to sign in</h3><form data-form="link-phone"></form>',...overrides});}
test('member navigation has three destinations and excludes guests, incomplete profiles and venue accounts',()=>{const c=context();vm.runInContext(extract('uiIcon')+'\n'+extract('memberNav'),c);let h=vm.runInContext('memberNav()',c);assert.equal((h.match(/<button /g)||[]).length,3);assert.match(h,/data-action="messages"/);assert.match(h,/data-view="settings"/);assert.match(h,/aria-current="page"/);for(const overrides of [{user:null},{complete:()=>false},{isVenue:()=>true},{recovery:true}]){const x=context(overrides);vm.runInContext(extract('uiIcon')+'\n'+extract('memberNav'),x);assert.equal(vm.runInContext('memberNav()',x),'');}});
test('grouped settings keep each editable profile, recovery, export, delete and sign-out control once',()=>{const c=context();vm.runInContext(extract('genderField')+'\n'+extract('interestField')+'\n'+extract('settingsContent')+'\n'+extract('settingsView'),c);const h=vm.runInContext('settingsView()',c);for(const attr of ['data-form="settings"','data-form="link-phone"','data-action="export"','data-action="delete"','data-action="signout"','data-action="push-on"','data-action="passkey-register"'])assert.equal(h.split(attr).length-1,1,attr);assert.equal((h.match(/<details/g)||[]).length,5);assert.equal((h.match(/<form/g)||[]).length,(h.match(/<\/form>/g)||[]).length);assert.doesNotMatch(h,/undefined/);});

test('gender choices remain optional, bilingual, private and editable',()=>{
 for(const french of [false,true]){
  const c=context({T:(en,fr)=>french?fr:en}); vm.runInContext(extract('genderField'),c);
  for(const value of ['', 'woman','man','non_binary','another_identity','prefer_not_to_say']){
   const html=vm.runInContext(`genderField('${value}')`,c);
   assert.match(html,new RegExp(`value="${value}" selected`));
   assert.equal((html.match(/<option /g)||[]).length,6);
   assert.doesNotMatch(html,/required/);
   assert.match(html,/gender-hint/);
  }
  assert.match(vm.runInContext("genderField('')",c),french?/non affiché aux autres membres/:/not shown to other members/);
 }
 assert.equal((source.match(/rpc\('save_member_profile'/g)||[]).length,2);
});
