// Native shells (iPhone and Android): identity filled in by the operator, minimal permissions.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
test('the Android shell uses the package chosen in Google Play and asks for the camera only',()=>{
  const id=JSON.parse(fs.readFileSync('mobile/identity.json','utf8'));
  assert.equal(id.androidPackage,'fr.upzoneapp.app');assert.equal(id.appUrl,'https://upzoneapp.fr/account.html');
  const cfg=fs.readFileSync('mobile/app.config.js','utf8');
  assert.match(cfg,/package: id\.androidPackage/);assert.match(cfg,/permissions: \['android\.permission\.CAMERA'\]/);
  assert.doesNotMatch(cfg,/ACCESS_FINE_LOCATION|READ_CONTACTS/);
  const wf=fs.readFileSync('.github/workflows/android-build.yml','utf8');
  assert.match(wf,/workflow_dispatch/);assert.doesNotMatch(wf,/\n\s+push:/,'never on a push');assert.match(wf,/eas build --platform android/);
  assert.match(fs.readFileSync('mobile/App.js','utf8'),/hardwareBackPress/);
});
