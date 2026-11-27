// The automatic check of the live site (27 Nov 2026): it must only look, and never carry a secret.
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');
const js=fs.readFileSync('scripts/live-check.mjs','utf8');
const yml=fs.readFileSync('.github/workflows/live-check.yml','utf8');
const doc=fs.readFileSync('docs/live-check.md','utf8');

test('the check only looks: sign-in is the only form it sends, navigation the only buttons it presses',()=>{
  const clicks=[...js.matchAll(/\.click\(\)/g)].length;
  const submits=[...js.matchAll(/button\[type="submit"\]/g)].map(m=>js.slice(Math.max(0,m.index-40),m.index));
  assert.ok(clicks>0);
  for(const s of submits)assert.ok(s.includes('form[data-form="auth"] '),'only the sign-in form is sent');
  assert.match(js,/const SAFE_ACTIONS = \['messages', 'people', 'talents'\];/,'the only actions pressed are the ones that show a screen');
  for(const banned of ['buy-pass','meet','block','report','delete','subscribe','join','leave','accept','decline','close','scan','push-on'])
    assert.ok(!js.includes('data-action="'+banned+'"'),'never presses '+banned);
  for(const m of js.matchAll(/page\.fill\('([^']*)'/g))assert.ok(m[1].startsWith('form[data-form="auth"] input[name="'),'types only into the sign-in form: '+m[1]);
});
test('no secret in the repository: accounts come from GitHub secrets, and the administration is never signed in to',()=>{
  for(const k of ['MEMBER','PRO','EVENT'])for(const f of ['EMAIL','PASSWORD'])assert.ok(yml.includes(`LIVE_CHECK_${k}_${f}: \${{ secrets.LIVE_CHECK_${k}_${f} }}`),k+' '+f);
  assert.ok(!/LIVE_CHECK_ADMIN/.test(js+yml+doc),'no administrator account in an automatic check');
  assert.ok(!/echo\s+.*secrets\./.test(yml),'a secret is never printed');
  assert.match(yml,/permissions:\n  contents: read\n/,'the workflow can only read the repository');
  assert.ok(!/@(?!example\.(com|invalid))[a-z0-9-]+\.[a-z]{2,}/i.test(js.replace(/https?:\/\/\S+/g,'')),'no real address in the script');
  assert.ok(doc.includes('Never write these in a file, a chat or a message'));
});
test('it runs after each publication, daily and on demand, and says what it does not cover',()=>{
  assert.match(yml,/workflow_run:\n    workflows: \["Deploy to GitHub Pages"\]/);
  assert.ok(fs.readFileSync('.github/workflows/deploy.yml','utf8').startsWith('name: Deploy to GitHub Pages'),'same name as the publishing workflow');
  assert.match(yml,/schedule:\n    - cron: /);assert.match(yml,/workflow_dispatch:/);
  assert.match(yml,/github\.event\.workflow_run\.conclusion == 'success'/,'not after a failed publication');
  assert.ok(js.includes('Not covered by this check: the installed phone app, notifications arriving on a phone'),'honest about its limits');
  for(const page of ['cgu.html','confidentialite.html','protection-des-mineurs.html','supprimer-mon-compte.html','admin.html'])assert.ok(js.includes("'"+page+"'")&&fs.existsSync('public/'+page),page);
});
