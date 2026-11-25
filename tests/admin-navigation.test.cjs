// Administration portal: going back (20 Nov 2026).
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const s=fs.readFileSync('src/admin.js','utf8'),html=fs.readFileSync('public/admin.html','utf8');
test('a visible way back to the app, in the header and next to « Se déconnecter »',()=>{
  assert.match(html,/<a href="\.\/account\.html" class="to-app">← Retour à l’application<\/a>/);
  assert.match(s,/<a class="link" href="\.\/account\.html">← Retour à l’application<\/a><button class="link" data-action="signout">/);
});
test('a back link above each screen: to the list when a venue is open, to « À traiter » otherwise, none on « À traiter »',()=>{
  assert.match(s,/function backLink\(\)\{if\(tab==='venues'&&data\.editing\)return `<button class="link back" data-action="cancel-edit">← Retour à la liste des lieux<\/button>`;return tab==='todo'\?'':`<button class="link back" data-tab="todo">← À traiter<\/button>`;\}/);
  assert.match(s,/<section class="panel">\$\{backLink\(\)\}<h2 class="panel-title">/);
  assert.ok(s.includes('<div class="item editing" id="venue-edit"><button class="link back" data-action="cancel-edit">← Retour à la liste des lieux</button>'),'also at the top of the open venue, where the eye is');
});
test('the phone or browser back button returns to the previous screen of the portal',()=>{
  assert.match(s,/function syncHistory\(\)\{if\(!user\|\|!admin\|\|mfa\)return;/,'only once inside the portal');
  assert.match(s,/history\.replaceState\(st,''\):history\.pushState\(st,''\)/);
  assert.match(s,/window\.addEventListener\('popstate',e=>\{const st=e\.state;if\(!st\|\|!st\.adm\|\|!user\|\|!admin\|\|busy\)return;/);
  assert.match(s,/function navState\(\)\{return \{adm:1,tab,edit:data\.editing\?\.id\|\|null,sub:subOf\(\)\};\}/,'the history holds a section name, a sub-section name and a venue id, nothing else');
  assert.match(s,/const known=TAB_LABELS\[st\.tab\]\?st\.tab:'todo';/,'an entry left by the old portal opens « À traiter », never a blank screen');
});
test('the new labels exist in English',()=>{
  for(const t of ['← Back to the list of venues','← Back to the app','← To handle'])assert.ok(s.includes(t),t);
});

// Administration reworked (25 Nov 2026): four sections, decisions on their card, QR code created on approval.
const css=fs.readFileSync('public/admin.css','utf8');
test('four sections instead of nine, and what waits for a decision is counted on the first one',()=>{
  assert.match(s,/const TAB_LIST=\[\['todo','À traiter'\],\['venues','Lieux'\],\['people','Personnes'\],\['more','Plus'\]\];/);
  assert.match(s,/let user=null, admin=false, tab='todo'/,'the portal opens on what waits for a decision');
  assert.match(s,/const pending=\(\)=>\(\{reports:\(data\.reports\|\|\[\]\)\.filter\(x=>x\.status==='open'\),apps:\(data\.applications\|\|\[\]\)\.filter\(x=>x\.status==='pending'\),pros:\(data\.pros\|\|\[\]\)\.filter\(x=>x\.status==='pending'\)\}\);/);
  assert.match(s,/k==='todo'&&n\?`<b class="count">\$\{n\}<\/b>`:''/);
  for(const view of ['passesView()','feedbackView()','auditView()','membersView()','prosView()','reportsView()'])assert.ok(s.includes(view),view+' is still reachable');
});
test('« À traiter »: reports first, each decision on its card with what approving does, and a plain « nothing waiting »',()=>{
  const view=s.split('function todoView()')[1].split('\nfunction peopleView')[0];
  assert.ok(view.indexOf('p.reports.map')<view.indexOf('p.apps.map')&&view.indexOf('p.apps.map')<view.indexOf('p.pros.map'),'a report, where waiting can hurt someone, comes first');
  assert.ok(view.includes('Tout est à jour')&&view.includes('Aucune candidature, aucune fiche, aucun signalement en attente.'));
  assert.ok(s.includes('Si vous approuvez : le lieu ouvre, son QR code est créé tout de suite'),'the consequence is written on the card');
  assert.ok(s.includes('<div class="decide"><button class="button" name="approve" value="1">Approuver</button><button class="button secondary" name="approve" value="">Refuser</button></div>'));
  assert.doesNotMatch(view,/alerte|prévenu par e-mail/i,'no promise of an alert that does not exist');
});
test('approving an application is still an administrator’s decision, and it creates the venue’s QR code in the same step',()=>{
  const submit=s.split("case 'decide-venue':")[1].split("case 'decide-pro':")[0];
  assert.ok(submit.includes("if(!ok&&!confirm(tx('Refuser cette candidature ?')))return;"),'a refusal is confirmed');
  assert.ok(submit.indexOf("rpc('admin_decide_venue'")<submit.indexOf('await newQr(res.venue_id'),'the server decides first; the QR code is for the venue it returns');
  assert.ok(submit.includes("catch{qrOk=false;}")&&submit.includes('Le lieu est ouvert, mais son QR code n’a pas pu être créé.'),'a failed QR code is said, the approval is not undone');
  assert.doesNotMatch(s,/setInterval\([^)]*admin_decide|auto.?approve/i,'nothing approves by itself');
  const fn=fs.readFileSync('db/functions.sql','utf8');
  assert.ok(fn.split('FUNCTION private.admin_decide_venue')[1].split('$function$;')[0].includes('private.require_admin()'),'the server still checks the administrator');
});
test('the new QR code: a link to copy, a picture to keep, a poster to print, and it is said to be shown once',()=>{
  const panel=s.split('function qrPanel()')[1].split('\n')[0];
  for(const needle of ['data-action="qr-print"','data-action="qr-copy"','download="upzone-qr.png"','<input id="qr-link-${k}" readonly value="${esc(t.url)}">','ne sont affichés qu’une fois'])assert.ok(panel.includes(needle),needle);
  assert.ok(s.includes("await navigator.clipboard.writeText(tokens[k].url);notice('Lien copié.');"));
  assert.ok(s.includes("if(a==='qr-print'){data.posterK=Number(t.dataset.k);render();window.print();return;}"),'the poster printed is the one whose button was pressed');
  assert.match(css,/@media print\{[\s\S]*body\.admin:has\(\.poster\)>header,body\.admin:has\(\.poster\) \.admin-layout,body\.admin:has\(\.poster\) #feedback\{display:none!important\}[\s\S]*body\.admin:has\(\.poster\) \.poster\{display:flex/,'on paper, only the poster, and only while a fresh QR code is on screen');
  assert.doesNotMatch(css.split('@media print{')[1],/\n  body\.admin>header|\n  \.admin-layout/,'any other screen of the portal still prints');
  assert.match(css,/\n\.poster\{display:none\}/,'and never on screen');
  const poster=s.split('function posterView()')[1].split('\n')[0];
  assert.ok(poster.includes('Un même lieu. De nouvelles rencontres.')&&poster.includes('18 ans et plus'),'the poster uses the landing page’s validated wording');
  assert.doesNotMatch(poster,/€|gratuit|prix/i,'no price promise on a poster');
});
test('a venue nobody can enter is flagged, and a link left by the QR code never reaches the history',()=>{
  assert.ok(s.includes('Aucun QR code actif : personne ne peut entrer'));
  assert.doesNotMatch(s.split('function navState()')[1].split('\n')[0],/token|url|lastToken/);
});
test('on a phone the four sections sit in a bar at the bottom, and the page leaves room for it',()=>{
  assert.match(css,/@media\(max-width:860px\)\{\s*\.admin-shell\{padding:12px 12px 96px\}\s*body\.admin \.tabs\{position:fixed;left:0;right:0;bottom:0;/);
  assert.match(css,/grid-template-columns:repeat\(4,minmax\(0,1fr\)\)/);
});
test('every new sentence exists in English',()=>{
  for(const t of ['All up to date','Venue application','Professional sheet','Print the poster','Copy the link','Save the image','Link copied.','People','No active QR code: no one can come in','Handled applications (','Add a venue without an organiser'])assert.ok(s.includes(t),t);
});
test('on a phone the way back to the app is still in the header, where the bottom bar did not take its place',()=>{
  assert.match(css,/@media\(max-width:860px\)\{body\.admin header nav a\.to-app\{display:inline;/);
});

// Changing a QR code in place (25 Nov 2026).
test('a valid QR code is changed in place: its length, for the people already in if asked, and its last day; only an administrator can',()=>{
  const db=fs.readFileSync('db/2026-11-25-edit-qr.sql','utf8');
  const fn=db.split('function private.admin_update_invite(')[1].split('$function$;')[0];
  assert.ok(fn.includes('declare uid uuid := private.require_admin()'),'administrator only');
  assert.ok(fn.includes("where id=p_id and revoked_at is null and expires_at>now() for update")&&fn.includes("raise exception 'invite_missing'"),'not a deleted or expired QR code');
  assert.ok(fn.includes("p_minutes not between 15 and 720 then raise exception 'invalid_duration'"),'same limits as a new QR code');
  assert.ok(fn.includes('update public.venue_sessions set expires_at=started_at+make_interval(mins=>p_minutes)')&&fn.includes('where invite_id=p_id and ended_at is null and expires_at>now()'),'only visits in progress with this QR code, counted from their own start');
  assert.doesNotMatch(fn,/token_hash\s*=|delete from/i,'the link already shared keeps working, and nothing is deleted');
  assert.ok(fn.includes("private.log_admin(uid,'invite_updated'"),'journaled');
  assert.match(db,/revoke all on function public\.admin_update_invite\(uuid,integer,boolean,integer\) from public, anon;/);
  const verify=fs.readFileSync('db/verify-edit-qr.sql','utf8');
  for(const needle of ['TEST: a member changed a QR code','TEST: a deleted QR code was changed','TEST: an expired QR code was changed','TEST: the QR code secret changed','TEST: a visit was deleted'])assert.ok(verify.includes(needle),needle);
  assert.match(verify,/rollback;\s*$/,'the test leaves nothing behind');
});
test('the portal: « Modifier » is the one button on a venue that has a valid QR code, and « Générer » only when nobody can come in',()=>{
  const card=s.split('function venueCard(x)')[1].split('\nfunction venuesView')[0];
  assert.ok(card.includes("'Modifier le lieu et ses QR codes'"));
  assert.ok(card.indexOf('Aucun QR code actif : personne ne peut entrer')<card.indexOf('data-action="invite"'),'the « Générer » button of the card belongs to the venue nobody can enter');
  const list=s.split('function qrList(x)')[1].split('\n')[0];
  for(const needle of ['data-form="invite"','name="apply" type="checkbox" checked','Une visite commencée depuis plus longtemps se termine.','data-action="extend"','data-action="revoke"','Créer un QR code supplémentaire'])assert.ok(list.includes(needle),needle);
  assert.ok(s.includes("rpc('admin_update_invite',{p_id:f.dataset.id,p_minutes:Number(v.minutes),p_apply:v.apply==='on'})"));
  assert.ok(s.includes("if(e?.code==='PGRST202'){notice('La modification d’un QR code n’est pas encore installée : la base de données doit être mise à jour.',true);return;}"),'said plainly while the database is not updated');
  for(const t of ['Save the length','Extend by 30 days','Edit the venue and its QR codes','Create an additional QR code'])assert.ok(s.includes(t),t);
});

// Findings of the code review of 25 Nov 2026.
test('a fresh QR code is never lost: each one stays on screen until the administrator says it is kept',()=>{
  assert.ok(s.includes("function qrPanel(){return tokens.map((t,k)=>"),'every pending QR code has its panel');
  assert.ok(s.includes("tokens.push(lastToken);"),'a new QR code is added, it does not replace the previous one');
  assert.ok(s.includes("if(a==='qr-done'){tokens.splice(Number(t.dataset.k),1);render();return;}")&&s.includes('J’ai gardé ce QR code : le masquer'));
  assert.ok(s.includes("if(t.dataset.tab){tab=t.dataset.tab;render();run(loadTab);return;}"),'changing section does not throw a QR code away');
  assert.doesNotMatch(s,/lastToken=null;(?!\s*,)/,'nothing clears it behind the administrator’s back');
});
test('« À traiter »: one list that fails does not hide the others, and « Tout est à jour » is never shown on a partial answer',()=>{
  const load=s.split('async function loadTodo()')[1].split('\n')[0];
  assert.ok(load.includes('Promise.allSettled')&&load.includes('data.todoPartial=!!failed;'));
  assert.ok(s.includes("(tokens.length||data.todoPartial?'':`<div class=\"all-done\">"));
  assert.ok(s.includes('Une partie de la liste n’a pas pu être chargée.'));
});
test('nothing the old portal said or showed was dropped: the check before approving, and the two figures',()=>{
  const card=s.split('function applicationCard(x)')[1].split('\n')[0];
  assert.ok(card.includes('Vérifiez l’existence du lieu ou de l’organisateur (Google, site, téléphone) avant d’approuver'));
  const stats=s.split('function statsLine()')[1].split('\n')[0];
  assert.ok(stats.includes('o.members_complete')&&stats.includes('o.suspended'));
});
test('names typed by people are never rewritten by the English rendering, on screen or on the poster',()=>{
  assert.ok(s.includes("if(!walker.currentNode.parentElement?.closest('[data-raw]'))texts.push(walker.currentNode);"));
  assert.ok(s.split('function posterView()')[1].split('\n')[0].includes('<b data-raw>${esc(t.venue)}</b>'));
  for(const needle of ['<b data-raw>${esc(x.name)}</b>','<b data-raw>${esc(x.venue_name)}</b>','<b data-raw>${esc(x.business_name)}</b>','<b data-raw>${esc(x.display_name)}</b>'])assert.ok(s.includes(needle),needle);
  for(const t of ["['à traiter','to handle']","['Chargement…','Loading…']"])assert.ok(s.includes(t),t);
});
test('changing a visit: the pass follows the visit, « add 30 days » never shortens, and the app asks the server before ending a visit',()=>{
  const db=fs.readFileSync('db/2026-11-25-edit-qr.sql','utf8'),app=fs.readFileSync('src/account.js','utf8'),verify=fs.readFileSync('db/verify-edit-qr.sql','utf8');
  assert.match(db,/update public\.passes p set expires_at=m\.expires_at from moved m\s+where p\.session_id=m\.id and p\.kind='venue_pass' and p\.status='active'/);
  assert.ok(db.includes("set expires_at=least(expires_at+make_interval(days=>p_days),now()+interval '365 days')"));
  for(const needle of ['TEST: a pass no longer ends with its visit','TEST: a later last day was brought closer','TEST: a QR code valid more than a year'])assert.ok(verify.includes(needle),needle);
  assert.ok(app.includes('if(!seconds)visitCheck(true);}'),'the countdown reaching zero asks the server first');
  assert.ok(app.includes("if(failed){if(ending){session=null;render();}return;}"),'without an answer the visit still ends when its time is up');
  assert.ok(app.includes("new Promise(done=>setTimeout(()=>done({error:{message:'timeout'}}),5000))"),'and the app does not wait for the server more than five seconds');
  assert.ok(app.includes("document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&session)visitCheck(false);});"));
});
