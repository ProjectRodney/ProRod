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
test('settings and help views exist in both languages and account deletion goes through the server',()=>{
  const source=fs.readFileSync('src/account.js','utf8');
  for(const needle of ['function settingsView','function helpView','data-view="help"','data-view="settings"',"rpc('delete_account')",'Aide et sécurité','Help & safety','Supprimer mon compte','Delete my account','112'])assert.ok(source.includes(needle),needle);
  assert.ok(source.includes("p_birth_date:profile.birth_date"),'settings must not change the birth date');
});
test('QR scanning uses the rear camera only to read a venue invitation, explains it, and never asks for a selfie',()=>{
  const source=fs.readFileSync('src/account.js','utf8');
  for(const needle of ['data-action="scan"',"facingMode:{ideal:'environment'}",'getTracks().forEach(t=>t.stop())','Aucune photo n’est prise ni conservée','No photo is taken or stored',"searchParams.get('venue')",'Saisir le code d’invitation à la place'])assert.ok(source.includes(needle),needle);
  assert.doesNotMatch(source,/capture="user"|facingMode:\s*['"]user/);
  const scanner=source.slice(source.indexOf('async function startScan'),source.indexOf('function render('));
  assert.doesNotMatch(scanner,/toDataURL|toBlob|\.upload\(|from\('avatars'\)/,'no camera frame is exported');
});
test('profile onboarding requires name, photo, date of birth and bio, and photos go to the private avatars bucket',()=>{
  const source=fs.readFileSync('src/account.js','utf8');
  for(const needle of ['function complete(p)','p.bio&&p.avatar_path','id="photo" name="photo" type="file" accept="image/*"','<textarea id="bio" name="bio" required','p_bio:values.bio','p_avatar_path:path',"from('avatars').upload","createSignedUrl(profile.avatar_path",'function age(date)'])assert.ok(source.includes(needle),needle);
  assert.doesNotMatch(source,/capture="user"/);
});
test('venue discovery is server-scoped and only reachable from a live session',()=>{
  const source=fs.readFileSync('src/account.js','utf8');
  for(const needle of ["rpc('venue_members')",'function peopleView','function personView','data-action="people"','createSignedUrl(m.avatar_path,900)'])assert.ok(source.includes(needle),needle);
  assert.doesNotMatch(source,/from\('profiles'\)\.select\('\*'\)\.neq|birth_date[^,]*other/,'no client-side listing of other profiles');
});
test('conversations are consent-gated and every screen exposes end, block and report',()=>{
  const source=fs.readFileSync('src/account.js','utf8');
  for(const needle of ["rpc('send_introduction'","rpc('respond_introduction'","rpc('my_inbox')","rpc('conversation_messages'","rpc('send_message'","rpc('close_conversation'","rpc('block_member'","rpc('report_member'",'This person is not obliged to respond','Cette personne n’est pas obligée de répondre','data-action="block"','data-action="report"','data-action="close"'])assert.ok(source.includes(needle),needle);
  assert.doesNotMatch(source,/from\('(messages|conversations|introductions|reports|blocks)'\)/,'no direct table access from the client');
});
test('private auth/API calls and token-bearing assets bypass the offline cache',()=>{
  const handlers={};
  vm.runInNewContext(fs.readFileSync('public/sw.js','utf8'),{URL,self:{registration:{scope:'https://test.example/'},location:{origin:'https://test.example'},addEventListener:(name,fn)=>handlers[name]=fn}});
  for(const url of ['https://blqcmpqctetmjqsfdvsq.supabase.co/auth/v1/user','https://test.example/account.bundle.js?access_token=secret','https://test.example/rest/v1/profiles']){
    let called=false;handlers.fetch({request:{url,method:'GET',mode:'cors'},respondWith(){called=true;}});assert.equal(called,false);
  }
});
