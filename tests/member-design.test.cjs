const test=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs');
const vm=require('node:vm');
const source=fs.readFileSync('src/account.js','utf8');
function extract(name){const start=source.indexOf('function '+name+'(');assert.ok(start>=0,name);const end=source.indexOf('\nfunction ',start+1);return source.slice(start,end);}
function context(overrides={}){return vm.createContext({lang:'en',T:(en,fr)=>en,esc:s=>String(s??''),user:{email:'fixture@example.invalid'},profile:{display_name:'Test member',birth_date:'1995-01-01',locale:'en',bio:'Hello'},avatarUrl:'',passes:[],isAdmin:false,isVenue:()=>false,isPro:()=>false,complete:()=>true,recovery:false,view:'home',unreadTotal:()=>2,age:()=>31,field:()=>'<input name="displayName">',photoField:()=>'<input name="photo" type="file">',pushBlock:()=>'<h3>Notifications</h3><button data-action="push-on">Enable</button>',talentAlertsBlock:()=>'<h3>Talent alerts</h3><form data-form="talent-alerts"></form>',passkeysBlock:()=>'<h3>Passkeys</h3><button data-action="passkey-register">Add</button>',signInMethodsBlock:()=>'<h3>Ways to sign in</h3><form data-form="link-phone"></form>',switchRow:()=>'<div class="account-switch"><button class="link" data-action="add-account">+ Add an account</button></div>',...overrides});}
test('member navigation has three destinations and excludes guests, incomplete profiles and venue accounts',()=>{const c=context();vm.runInContext(extract('uiIcon')+'\n'+extract('memberNav'),c);let h=vm.runInContext('memberNav()',c);assert.equal((h.match(/<button /g)||[]).length,3);assert.match(h,/data-action="messages"/);assert.match(h,/data-view="settings"/);assert.match(h,/aria-current="page"/);for(const overrides of [{user:null},{complete:()=>false},{isVenue:()=>true},{recovery:true}]){const x=context(overrides);vm.runInContext(extract('uiIcon')+'\n'+extract('memberNav'),x);assert.equal(vm.runInContext('memberNav()',x),'');}});
test('profile editing and settings keep each editable profile, recovery, export, delete and sign-out control once',()=>{
  const line=pre=>{const i=source.indexOf(pre);assert.ok(i>=0,pre);return source.slice(i,source.indexOf('\n',i));};
  const helpers=['const GEAR','const PEN','const ageBand','const deptName','const heightText','const subHead','const DEPTS'].map(line).join('\n');
  for(const pro of [false,true]){
    const c=context({photoPreview:'',isPro:()=>pro,pinPhoto:()=>'<span class="pin"></span>',when:()=>'1/1',proData:pro?{status:'approved',enquiries:[]}:null,switchRow:()=>'<div class="account-switch"></div>',langChips:()=>'<div class="lang-choice"></div>',talentAlertsBlock:()=>'<h3>Talent alerts</h3>'});
    vm.runInContext(helpers+'\n'+['genderField','interestField','departmentField','heightField','editView','prefsView','profileHubView'].map(extract).join('\n'),c);
    const h=vm.runInContext('editView()+prefsView()',c);
    for(const attr of ['data-form="settings"','data-form="link-phone"','data-action="export"','data-action="delete"','data-action="signout"','data-action="push-on"','data-action="passkey-register"'])assert.equal(h.split(attr).length-1,1,attr+(pro?' (pro)':''));
    assert.equal((h.match(/<form/g)||[]).length,(h.match(/<\/form>/g)||[]).length);
    assert.doesNotMatch(h,/undefined/);
    if(pro){assert.doesNotMatch(h,/id="gender"|id="interest"/,'no dating fields for a pro account');assert.doesNotMatch(h,/data-action="become-pro"/);}
    else{assert.match(h,/id="gender"/);assert.match(h,/name="interestConsent"/);assert.match(h,/data-action="become-pro"/);assert.match(h,/id="private-info"/);}
  }
  const c=context({pinPhoto:m=>m.veiled?'<span class="pin pin-veiled"></span>':'<span class="pin"></span>',profileTab:'veiled',live:()=>false});
  vm.runInContext(['const GEAR','const PEN','const ageBand','const deptName','const heightText','const DEPTS'].map(line).join('\n')+'\n'+extract('profileHubView'),c);
  const v=vm.runInContext('profile.department="75";profileHubView()',c);
  assert.match(v,/pin-veiled/);assert.match(v,/31-35/);assert.doesNotMatch(v,/Test member|Hello/,'the « seen without a pass » preview never shows the name or the bio');
});
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
test('the profile screen opens the settings once (gear at the top), not twice',()=>{
  const i=source.indexOf('function profileHubView(');const f=source.slice(i,source.indexOf('\nfunction ',i+1));
  assert.equal(f.split('data-view="prefs"').length-1,1);
});
test('top right corner: the member\'s photo opens their profile; the language is chosen in the settings (20 Nov)',()=>{
  const s=fs.readFileSync('src/account.js','utf8');
  assert.match(s,/function headerNav\(\)\{if\(user&&accountType&&complete\(profile\)&&!recovery&&!passwordDone\)\{/,'only for a signed-in member with a finished profile');
  assert.match(s,/class="head-me" data-view="\$\{venueAcc\?'venue-settings':'settings'\}"/);
  assert.match(s,/return `<button type="button" data-language="fr" aria-pressed="\$\{lang==='fr'\}">FR<\/button><button type="button" data-language="en"/,'a visitor without an account keeps FR / EN');
  assert.match(s,/<h3 class="pref-title">\$\{T\('Language','Langue'\)\}<\/h3>\$\{langChips\(\)\}/,'the language is in « Réglages »');
});
