// Talent alerts (17 Nov 2026): a subscribed professional's presence is announced only to people present in the same
// venue who turned the alert on with an explicit, unticked consent box. Server checks: db/verify-talent-alerts.sql.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const sql=fs.readFileSync('db/2026-11-17-talent-alerts.sql','utf8');
const fn=fs.readFileSync('db/functions.sql','utf8');
const app=fs.readFileSync('src/account.js','utf8');
const tu=fs.readFileSync('src/tu.js','utf8');
const push=fs.readFileSync('supabase/functions/send-push/index.ts','utf8');
const privacy=fs.readFileSync('public/confidentialite.html','utf8');
const body=(src,name)=>{const i=src.indexOf(name);assert.ok(i>=0,name);return src.slice(i,src.indexOf('$$;',i)>0?src.indexOf('$$;',i):undefined);};

test('turning alerts on needs explicit consent; off erases the consent date',()=>{
  const f=body(sql,'function private.set_talent_alerts(');
  assert.match(f,/if p_consent is distinct from true then raise exception 'talent_alerts_consent_required'/);
  assert.match(f,/set talent_alerts_at=null/);
  assert.match(f,/private\.require_person\(\)/);
  assert.match(sql,/add column if not exists talent_alerts_at timestamptz;/);
  assert.doesNotMatch(sql,/talent_alerts_at timestamptz (not null|default)/,'alerts must be off by default');
  assert.match(sql,/revoke all on function private\.set_talent_alerts\(boolean,boolean\), public\.set_talent_alerts\(boolean,boolean\) from public, anon;/);
});

test('an alert respects consent, blocks, suspension, one per visit and 5 a day, without the professional id',()=>{
  const f=body(sql,'function private.send_talent_alert(');
  for(const rule of ['me.talent_alerts_at is null',"me.account_type='venue'",'r.suspended','private.blocked_between(p_to,p_pro)',"interval '24 hours')>=5","n.payload->>'key'=k"])assert.ok(f.includes(rule),rule);
  assert.match(f,/k text := md5\(/,'the de-duplication key must not expose the professional id');
  assert.doesNotMatch(f,/'user_id'|'pro'\s*,\s*p_pro/);
  const listed=body(sql,'function private.talent_listed(');
  assert.ok(listed.includes("t.status='approved' and t.subscription_until is not null and t.subscription_until>now()"),'same rule as Talents ici');
  const announce=body(sql,'function private.announce_talent(');
  assert.ok(announce.includes('v.venue_id=p_session.venue_id and v.ended_at is null and v.expires_at>now()'),'same venue, live visits only');
  assert.match(sql,/revoke all on function private\.talent_listed\(uuid\), private\.send_talent_alert\(uuid,uuid,uuid,text\), private\.announce_talent\(uuid,public\.venue_sessions\), private\.talent_alerts_on_visit\(\) from public, anon, authenticated;/);
});

test('arrival and subscription trigger the alert; a failure never blocks the visit',()=>{
  assert.match(sql,/create trigger talent_alerts_after_visit after insert on public\.venue_sessions/);
  assert.match(body(sql,'function private.talent_alerts_on_visit('),/exception when others then\s+raise warning/);
  assert.match(body(sql,'function private.subscribe_talent_simulated('),/private\.announce_talent\(uid, private\.live_session\(uid\)\)/);
  assert.match(sql,/'talent_here'\]\) k\s+union select distinct kind from public\.notifications/,'existing notification kinds stay allowed');
  // Since 26 Nov 2026 (db/2026-11-26-pro-evening.sql) the announcement uses the visit the visibility was taken for.
  assert.ok(fn.includes('FUNCTION private.send_talent_alert(')&&fn.includes('private.announce_talent(uid, mine)'),'functions.sql is in sync');
});

test('the app asks consent with an unticked box and offers a one-tap stop',()=>{
  const block=app.slice(app.indexOf('function talentAlertsBlock'),app.indexOf('function pushBlock'));
  assert.match(block,/<input type="checkbox" name="consent" required>/);
  assert.doesNotMatch(block,/name="consent"[^>]*checked/);
  assert.ok(app.includes("rpc('set_talent_alerts',{p_on:true,p_consent:true})"));
  assert.ok(app.includes("rpc('set_talent_alerts',{p_on:false,p_consent:null})"));
  assert.ok(app.includes("n.kind==='talent_here'")&&app.includes('data-action="talent-alerts-off"'),'stop link on the alert');
  assert.ok(app.includes("case 'talent_here':"));
  assert.ok(app.includes('pushBlock()+talentAlertsBlock()'));
});

test('lock screen stays generic; texts in FR/EN with « tu »; privacy policy informs both sides',()=>{
  assert.match(push,/talent_here: \["Un talent est présent dans le lieu\.", "A talent is at the venue\."\]/);
  for(const fr of ['que vous. C’est de la publicité pour son activité','Vous n’en recevrez plus de nouvelles.','Cochez la case pour activer les alertes talents.'])assert.ok(tu.includes(fr),'tu version: '+fr);
  assert.ok(privacy.includes('Alertes talents (facultatives)')&&privacy.includes('Talent alerts (optional)'));
  assert.ok(privacy.includes('prévenues de votre présence')&&privacy.includes('are told you are there'));
});

test('the settings block renders off (consent form) and on (date + stop) states',()=>{
  const vm=require('node:vm');const start=app.indexOf('function talentAlertsBlock(');const code=app.slice(start,app.indexOf('\nfunction ',start+1));
  const run=profile=>{const c=vm.createContext({T:(en,fr)=>fr,esc:s=>String(s??''),when:s=>'17/11/2026',profile});vm.runInContext(code,c);return vm.runInContext('talentAlertsBlock()',c);};
  const off=run({talent_alerts_at:null});
  assert.match(off,/data-form="talent-alerts"/);assert.match(off,/type="checkbox" name="consent" required>J’accepte/);assert.doesNotMatch(off,/talent-alerts-off|undefined/);
  const on=run({talent_alerts_at:'2026-11-17T10:00:00Z'});
  assert.match(on,/Activées depuis le 17\/11\/2026/);assert.match(on,/data-action="talent-alerts-off"/);assert.doesNotMatch(on,/data-form="talent-alerts"|undefined/);
});
