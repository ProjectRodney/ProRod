// Administration portal: going back (20 Nov 2026).
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const s=fs.readFileSync('src/admin.js','utf8'),html=fs.readFileSync('public/admin.html','utf8');
test('a visible way back to the app, in the header and next to « Se déconnecter »',()=>{
  assert.match(html,/<a href="\.\/account\.html" class="to-app">← Retour à l’application<\/a>/);
  assert.match(s,/<a class="link" href="\.\/account\.html">← Retour à l’application<\/a><button class="link" data-action="signout">/);
});
test('a back link above each screen: to the list when a venue is open, to the overview otherwise, none on the overview',()=>{
  assert.match(s,/function backLink\(\)\{if\(tab==='venues'&&data\.editing\)return `<button class="link back" data-action="cancel-edit">← Retour à la liste des lieux<\/button>`;return tab==='overview'\?'':`<button class="link back" data-tab="overview">← Vue d’ensemble<\/button>`;\}/);
  assert.match(s,/<section class="panel">\$\{backLink\(\)\}<h2 class="panel-title">/);
  assert.ok(s.includes('<div class="item editing" id="venue-edit"><button class="link back" data-action="cancel-edit">← Retour à la liste des lieux</button>'),'also at the top of the open venue, where the eye is');
});
test('the phone or browser back button returns to the previous screen of the portal',()=>{
  assert.match(s,/function syncHistory\(\)\{if\(!user\|\|!admin\|\|mfa\)return;/,'only once inside the portal');
  assert.match(s,/history\.replaceState\(st,''\):history\.pushState\(st,''\)/);
  assert.match(s,/window\.addEventListener\('popstate',e=>\{const st=e\.state;if\(!st\|\|!st\.adm\|\|!user\|\|!admin\|\|busy\)return;/);
  assert.match(s,/function navState\(\)\{return \{adm:1,tab,edit:data\.editing\?\.id\|\|null\};\}/,'the history holds a section name and a venue id, nothing else');
});
test('the new labels exist in English',()=>{
  for(const t of ['← Back to the list of venues','← Back to the app','← Overview'])assert.ok(s.includes(t),t);
});
