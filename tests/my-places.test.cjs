// « Mes lieux » (17 Nov 2026): the member's own places, 90 days, entering still needs the QR scan.
// Server checks: db/verify-my-places.sql.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');
const sql=fs.readFileSync('db/2026-11-17-my-places.sql','utf8');
const app=fs.readFileSync('src/account.js','utf8');
const tu=fs.readFileSync('src/tu.js','utf8');
const privacy=fs.readFileSync('public/confidentialite.html','utf8');
const fnBody=n=>{const i=sql.indexOf('function private.'+n+'(');assert.ok(i>=0,n);return sql.slice(i,sql.indexOf('$$;',i));};

test('the list is the member’s own visits, 90 days, without one-off events',()=>{
  const f=fnBody('my_places');
  for(const rule of ['private.require_person()','s.user_id=uid','s.history_hidden_at is null',"s.started_at>now()-interval '90 days'","v.category<>'event'",'case when v.active then'])assert.ok(f.includes(rule),rule);
});
test('hiding keeps the visits and only touches the member’s own rows',()=>{
  for(const n of ['hide_place','clear_places']){const f=fnBody(n);assert.match(f,/update public\.venue_sessions set history_hidden_at=now\(\)/);assert.match(f,/where user_id=uid/);assert.doesNotMatch(f,/delete from/i);}
  assert.match(sql,/revoke all on function private\.my_places\(\), private\.hide_place\(uuid\), private\.clear_places\(\),\s+public\.my_places\(\), public\.hide_place\(uuid\), public\.clear_places\(\) from public, anon;/);
});
test('entering always goes through the QR code: a place only opens the scanner',()=>{
  const start=app.indexOf('function placeView(');const code=app.slice(start,app.indexOf('\nconst leftText',start));
  assert.doesNotMatch(code,/join_venue|data-action="join"/);
  assert.match(code,/data-action="scan" data-expect=/);
  assert.match(app,/if\(expectPlace&&venue\?\.name===expectPlace\)\{expectPlace=null;await joinNow\(\);return;\}/,'straight in only after a real scan of that place');
  const join=app.slice(app.indexOf('async function joinNow('),app.indexOf('\nasync function startScan('));
  assert.match(join,/rpc\('join_venue',\{p_token:invite\}\)/);
});
test('the list and the place screen render; closed places offer nothing',()=>{
  const pick=n=>{const i=app.indexOf(n);return app.slice(i,app.indexOf('\n',i));};
  const code=['const dayMonth','const catName','const pinBadge','function placesBlock','function placeView'].map(pick).join('\n');
  const run=(pl,expr)=>{const c=vm.createContext({lang:'fr',T:(en,fr)=>fr,esc:s=>String(s??''),uiIcon:()=>'<svg></svg>',VENUE_CATS:()=>[['pub','Bar / pub']],places:pl,place:pl[0]});vm.runInContext(code,c);return vm.runInContext(expr,c);};
  const open={venue:'v1',name:'Au Comptoir',category:'pub',open:true,visits:3,last_visit:'2026-11-14T20:00:00Z',announcement:'Happy hour'};
  const list=run([open,{...open,venue:'v2',name:'Fermé',open:false}],'placesBlock()');
  assert.match(list,/data-place="v1"/);assert.match(list,/place-row closed/);assert.match(list,/data-action="clear-places"/);
  assert.equal(run([],'placesBlock()'),'');
  const card=run([open],'placeView()');assert.match(card,/Je suis sur place : scanner pour entrer/);assert.match(card,/Happy hour/);assert.match(card,/data-action="hide-place"/);
  const closed=run([{...open,open:false}],'placeView()');assert.doesNotMatch(closed,/data-action="scan" data-expect/);assert.doesNotMatch(closed,/Happy hour/);
  assert.doesNotMatch(card+list,/undefined/);
});
test('« tu » versions and privacy policy',()=>{
  for(const fr of ['Visible par vous seul.','Vous revoilà à','VOTRE PASS'])assert.ok(tu.includes(`'${fr}':`),fr);
  assert.ok(privacy.includes('<b>Mes lieux :</b>')&&privacy.includes('<b>My places:</b>'));
});
