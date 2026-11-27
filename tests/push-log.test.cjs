// The record of notification sends (27 Nov 2026): what the server keeps, who may read it, and what the admin page says.
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');
const strip=s=>s.split('\n').filter(l=>!l.trim().startsWith('--')).join('\n');
const sql=strip(fs.readFileSync('db/2026-11-27-push-log.sql','utf8'));
const verify=fs.readFileSync('db/verify-push-log.sql','utf8');
const admin=fs.readFileSync('src/admin.js','utf8');

test('the record keeps no member, no device address and no text',()=>{
  const table=sql.slice(sql.indexOf('create table if not exists private.push_log'),sql.indexOf(');',sql.indexOf('create table if not exists private.push_log')));
  for(const banned of ['user_id','endpoint','token','body','display_name','email'])assert.ok(!table.includes(banned),'no '+banned+' column');
  for(const col of ['kind','browsers','phones','request_id','problem'])assert.ok(table.includes(col),col);
  assert.match(sql,/delete from private\.push_log where created_at<now\(\)-interval '30 days'/,'erased after 30 days');
});
test('the table and its helpers are closed to members; only the administrator reads it',()=>{
  assert.match(sql,/alter table private\.push_log enable row level security/);
  assert.match(sql,/revoke all on private\.push_log from public, anon, authenticated/);
  assert.match(sql,/revoke all on function private\.push_collect\(\), private\.push_json\(text\), private\.push_totals\(timestamptz\), private\.push_on_notification\(\) from public, anon, authenticated/);
  assert.match(sql,/function private\.admin_push_log[^$]*\$\$\s*declare uid uuid := private\.require_admin\(\)/,'administrator only');
  assert.ok(!/grant execute on function p\w+\.admin_push_log\(integer\) to[^;]*anon/.test(sql),'never open to visitors');
});
test('recording a send can never stop a notification',()=>{
  const trig=sql.slice(sql.indexOf('function private.push_on_notification()'),sql.indexOf('function private.admin_push_log'));
  assert.match(trig,/req := net\.http_post\(/,'the trigger keeps the number of its call');
  assert.match(trig,/begin\s+perform private\.push_collect\(\);[\s\S]*exception when others then\s+raise warning 'push_log: %'/,'the record has its own safety net');
  assert.match(sql,/function private\.push_collect\(\)[\s\S]*exception when others then\s+raise warning 'push_collect: %'/,'reading the answers never raises');
  assert.match(trig,/notification_mutes/,'the member’s choices are still respected');
  assert.match(sql,/if to_regclass\('public\.app_devices'\) is null then raise exception/,'refuses to install on a base without the phone push migration');
});
test('the checks cover refusals, timeouts, odd answers, closing and access',()=>{
  for(const needle of ['TEST: expected one line','TEST: the record has a column that was not planned','TEST: refusal not read','TEST: timeout not read','TEST: odd answer','TEST: old line not closed','TEST: line older than 30 days kept','TEST: missing configuration not recorded','TEST: a switched-off group was recorded as a send','TEST: a member can read the record','TEST: the record shows a member, a phone or an address'])assert.ok(verify.includes(needle),needle);
  assert.ok(!/pg_temp|create temp/i.test(verify),'no temporary objects (the SQL editor refuses them here)');
  assert.match(verify,/rollback;\s*$/,'everything is rolled back');
});
test('admin portal: « Notifications » under « Plus », honest about what « accepté » means',()=>{
  assert.match(admin,/MORE_SUBS=\[\['passes','Pass \(simulation\)'\],\['feedback','Retours des testeurs'\],\['push','Notifications'\],\['audit','Journal des actions'\]\]/);
  assert.match(admin,/rpc\('admin_push_log',\{p_limit:30\}\)/);
  assert.match(admin,/catch\(e\)\{if\(e\?\.code!=='PGRST202'\)throw e;data\.push=null;data\.pushMissing=true;\}/,'says so when the database is not updated yet');
  assert.ok(admin.includes('« Accepté » veut dire accepté par le service d’envoi'),'explains the limit of the word');
  assert.ok(admin.includes('Aucun membre, aucun nom et aucun texte de message n’apparaît ici.'));
  for(const fr of ['Les notifications partent normalement.','Derniers envois','En attente de réponse','pas de réponse à temps']){const i=admin.indexOf("['"+fr+"','");assert.ok(i>0,'English for: '+fr);}
  const en=[...admin.matchAll(/\['[^']*','([^']*)'\]/g)].map(m=>m[1]).filter(t=>/Notifications are|waiting for|no reply|Result received|“Accepted”/.test(t));
  for(const t of en)assert.ok(!/ans/.test(t),'no « ans » inside an English text (the short rule ans→yrs would break it): '+t);
});
