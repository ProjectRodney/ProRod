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
test('Android: the upright-only screen is declared optional, so Google Play does not hide the app from tablets (20 Nov)',()=>{
  const cfg=fs.readFileSync('mobile/app.config.js','utf8');
  assert.match(cfg,/withAndroidManifest/);
  assert.match(cfg,/'android\.hardware\.screen\.portrait', 'android\.hardware\.screen\.landscape'/);
  assert.match(cfg,/'android:required': 'false'/);
  assert.match(cfg,/module\.exports = \(\) => optionalScreen\(\{/);
});
test('iPhone: the build can be sent to TestFlight from GitHub (App Store Connect app named, latest build without rebuilding)',()=>{
  const eas=JSON.parse(fs.readFileSync('mobile/eas.json','utf8')),wf=fs.readFileSync('.github/workflows/ios-build.yml','utf8');
  assert.match(eas.submit.production.ios.ascAppId,/^\d{9,11}$/);
  assert.match(wf,/if: \$\{\{ inputs\.submit_latest \}\}\n\s+run: eas submit --platform ios --profile production --latest --non-interactive --no-wait/);
  assert.match(wf,/if: \$\{\{ !inputs\.submit_latest \}\}\n\s+run: eas build --platform ios/);
});
test('Android closed test: two reminders a day planned on the phone, ending on a set date, nothing sent to a server',()=>{
  // How the reminders behave is run for real, with a pretend phone, in tests/reminders.test.cjs. Here: what must never be there.
  const app=fs.readFileSync('mobile/App.js','utf8'),rem=fs.readFileSync('mobile/reminders.js','utf8'),cfg=fs.readFileSync('mobile/app.config.js','utf8');
  assert.match(cfg,/extra: \{ testRemindersUntil: '\d{4}-\d{2}-\d{2}', appUrl:/,'the last day is written in the configuration');
  assert.match(rem,/const REMIND_AT = \[\[12, 30\], \[19, 30\]\];/);
  assert.match(app,/import \{ planTestReminders \} from '\.\/reminders';/);
  assert.match(app,/if \(!r\.allowed\) inviteToAllow\(\);/);
  assert.match(app,/window\.__upzoneNotif=\$\{JSON\.stringify\(notifDiag\)\}/);
  assert.match(fs.readFileSync('src/account.js','utf8'),/esc\(window\.__upzoneNotif\.slice\(0,200\)\)/,'the readout is escaped and bounded');
  for(const code of [app,rem]){
    assert.doesNotMatch(code,/getExpoPushTokenAsync|getDevicePushTokenAsync/,'no push token: the phone is never identified');
    assert.doesNotMatch(code,/fetch\(|XMLHttpRequest/,'the shell itself sends nothing');
    assert.doesNotMatch(code,/\.catch\(\(\) => \{\}\); \}, \[\]\)/,'a failure while planning is never swallowed silently');
  }
});
test('updates over the air: tied to the builds they fit, published by hand, on the production channel',()=>{
  const cfg=fs.readFileSync('mobile/app.config.js','utf8'),eas=JSON.parse(fs.readFileSync('mobile/eas.json','utf8')),wf=fs.readFileSync('.github/workflows/mobile-update.yml','utf8'),pkg=JSON.parse(fs.readFileSync('mobile/package.json','utf8'));
  assert.ok(pkg.dependencies['expo-updates'],'the update mechanism is part of the app');
  assert.match(cfg,/runtimeVersion: \{ policy: 'fingerprint' \}/,'an update never reaches a build whose native parts differ');
  assert.match(cfg,/url: `https:\/\/u\.expo\.dev\/\$\{id\.easProjectId\}`/);
  assert.equal(eas.build.production.channel,'production');
  assert.match(wf,/on:\n  workflow_dispatch:/,'by hand only');
  assert.doesNotMatch(wf,/\n  push:|\n  schedule:/);
  assert.match(wf,/eas update --channel production --environment production --message "\$UPDATE_MESSAGE" --non-interactive/);
  assert.match(wf,/UPDATE_MESSAGE: \$\{\{ inputs\.message \}\}/,'the message is passed as a variable, never pasted into the command');
});
test('the app tells the website which version runs, and the settings show it (to follow updates over the air)',()=>{
  const app=fs.readFileSync('mobile/App.js','utf8'),web=fs.readFileSync('src/account.js','utf8'),inst=fs.readFileSync('public/pwa-install.js','utf8');
  assert.match(app,/const APP_MARK = `UPZONEApp\/1\.0 \(\$\{Updates\.isEmbeddedLaunch \|\| !Updates\.updateId \? 'base' : Updates\.updateId\.slice\(0, 8\)\}\)`;/);
  assert.match(app,/applicationNameForUserAgent=\{APP_MARK\}/);
  assert.match(inst,/\/UPZONEApp\/\.test\(navigator\.userAgent\)/,'the install banner still recognises the app');
  assert.match(web,/function appVersionLine\(\)\{const m=\/UPZONEApp\\\/\(\[\\d\.\]\+\)\(\?: \\\(\(\[\^\)\]\+\)\\\)\)\?\/\.exec\(navigator\.userAgent\|\|''\);if\(!m\)return '';/,'nothing is shown in a browser');
});
