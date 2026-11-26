// Server side of real purchases (26 Nov 2026): only a server holding the service key can switch a paid pass on.
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');
const sql=fs.readFileSync('db/2026-11-26-purchases.sql','utf8');const check=fs.readFileSync('db/verify-purchases.sql','utf8');
const fn=fs.readFileSync('db/functions.sql','utf8');const app=fs.readFileSync('src/account.js','utf8');
const body=(name)=>{const i=sql.indexOf('function '+name);assert.ok(i>=0,name);return sql.slice(i,sql.indexOf('$function$;',i));};

test('no client can record, refund or read a purchase',()=>{
  assert.match(sql,/revoke all on public\.purchases from anon, authenticated;/);
  assert.match(sql,/alter table public\.purchases enable row level security;/);
  assert.ok(!/create policy[^;]*purchases/i.test(sql));
  assert.match(sql,/revoke all on function private\.record_purchase\(uuid,text,text,text,integer,text\), private\.refund_purchase\(text,text\), public\.record_purchase\(uuid,text,text,text,integer,text\), public\.refund_purchase\(text,text\) from public, anon, authenticated;/);
  assert.match(sql,/grant execute on function private\.record_purchase\([^)]*\), private\.refund_purchase\([^)]*\), public\.record_purchase\([^)]*\), public\.refund_purchase\([^)]*\) to service_role;/);
  assert.ok(!/grant execute on function[^;]*record_purchase[^;]*to (anon|authenticated)/.test(sql));
  assert.ok(!app.includes("rpc('record_purchase'")&&!app.includes("rpc('refund_purchase'"),'the app never calls them');
});
test('a transaction counts once, and never for two people',()=>{
  const f=body('private.record_purchase(');
  assert.match(sql,/unique \(store, transaction_id\)/);
  assert.match(f,/pg_advisory_xact_lock\(hashtextextended\(p_store\|\|':'\|\|p_transaction,0\)\)/);
  assert.match(f,/if row\.user_id is distinct from p_user or row\.product<>p_product then raise exception 'purchase_conflict'/);
});
test('what is bought is for the live visit, and money taken is always written down',()=>{
  const f=body('private.record_purchase(');
  assert.match(f,/elsif mine\.id is null then why := 'no_visit'/);
  assert.match(f,/values\(p_user,mine\.venue_id,mine\.id,'venue_pass',false,p_amount_cents,mine\.expires_at\)/);
  assert.match(f,/values\(p_user,mine\.venue_id,mine\.id,'talent_subscription',false,p_amount_cents,mine\.expires_at\)/);
  assert.match(f,/insert into public\.purchases\([^)]*\)\s+values\(p_user,p_store,p_product,p_transaction,p_amount_cents,upper\(p_currency\),why is null,why,/,'recorded whether granted or not');
  assert.match(sql,/amount_cents integer not null check \(amount_cents between 1 and 100000\)/);
});
test('a refund stops what was bought',()=>{
  const f=body('private.refund_purchase(');
  assert.match(f,/update public\.passes set status='refunded', expires_at=least\(expires_at,now\(\)\) where id=row\.pass_id/);
  assert.match(f,/update public\.pro_profiles set subscription_until=null where user_id=row\.user_id and subscription_session=row\.session_id/);
});
test('nothing depends on gender, and the administrator list carries no user id',()=>{
  const code=sql.split('\n').filter(l=>!l.trim().startsWith('--')).join('\n');
  assert.ok(!/gender|interested_in/.test(code));
  const a=body('private.admin_purchases(');
  assert.match(a,/private\.require_admin\(\)/);assert.ok(!/'user_id'/.test(a));
});
test('the check script leaves nothing behind, and the reference file has the functions',()=>{
  assert.match(check,/^begin;/m);assert.match(check,/^rollback;/m);assert.ok(!/temp table|pg_temp/i.test(check));
  assert.match(check,/PASS: server side of real purchases/);
  for(const n of ['private.record_purchase(','private.refund_purchase(','private.admin_purchases('])assert.ok(fn.includes('FUNCTION '+n),n);
  assert.ok(!/grant execute on function (private|public)\.(record|refund)_purchase[^;]*to (anon|authenticated);/.test(fn));
});
