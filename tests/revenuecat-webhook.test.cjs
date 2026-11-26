// Purchases confirmed by RevenueCat (26 Nov 2026): what the server function does with each event.
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');const mod=require('node:module');
const ts=fs.readFileSync('supabase/functions/revenuecat-webhook/index.ts','utf8');
const sql=fs.readFileSync('db/2026-11-26-purchases.sql','utf8');
const {decide}=(()=>{const js=mod.stripTypeScriptTypes(ts).replace(/^export /gm,'');const out={};new Function('out','Deno',js+';out.decide=decide;')(out,undefined);return out;})();
const U='00000000-0000-4000-8000-000000000001';
const buy={type:'NON_RENEWING_PURCHASE',environment:'PRODUCTION',store:'APP_STORE',product_id:'upzone_venue_pass',transaction_id:'2000000123456789',app_user_id:U,price_in_purchased_currency:2.99,currency:'EUR'};

test('a confirmed purchase is recorded for the signed-in account, with the store price',()=>{
  assert.deepEqual(decide(buy,false),{action:'record',user:U,store:'apple',product:'venue_pass',transaction:'2000000123456789',cents:299,currency:'EUR'});
  const pro=decide({...buy,store:'PLAY_STORE',product_id:'upzone_pro_evening',transaction_id:'GPA.3300-1111-2222-33333',price_in_purchased_currency:9.99,currency:'eur'},false);
  assert.deepEqual([pro.store,pro.product,pro.cents,pro.currency],['google','pro_evening',999,'EUR']);
});
test('a missing or odd price falls back to the listed price, never to zero',()=>{
  for(const p of [null,undefined,0,-2.99,'abc'])assert.equal(decide({...buy,price_in_purchased_currency:p},false).cents,299);
  assert.equal(decide({...buy,price_in_purchased_currency:99999},false).cents,100000,'capped');
  assert.equal(decide({...buy,currency:'€'},false).currency,'EUR');
});
test('a refund stops the purchase, whoever the event names',()=>{
  assert.deepEqual(decide({...buy,type:'CANCELLATION',app_user_id:'$RCAnonymousID:abc',price_in_purchased_currency:-2.99,cancel_reason:'CUSTOMER_SUPPORT'},false),{action:'refund',store:'apple',transaction:'2000000123456789'});
});
test('test purchases are ignored unless the test switch is on',()=>{
  assert.deepEqual(decide({...buy,environment:'SANDBOX'},false),{action:'ignore',why:'sandbox'});
  assert.equal(decide({...buy,environment:'SANDBOX'},true).action,'record');
  assert.equal(decide({...buy,environment:undefined},false).action,'ignore');
});
test('anything unexpected is ignored: other events, stores, products, accounts',()=>{
  assert.equal(decide({...buy,type:'INITIAL_PURCHASE'},false).why,'event_type');
  assert.equal(decide({...buy,type:'RENEWAL'},false).why,'event_type');
  assert.equal(decide({...buy,store:'STRIPE'},false).why,'store');
  assert.equal(decide({...buy,product_id:'upzone_gold'},false).why,'product');
  assert.equal(decide({...buy,product_id:'venue_pass'},false).why,'product','only the exact identifiers');
  assert.equal(decide({...buy,app_user_id:'$RCAnonymousID:1234'},false).why,'user');
  assert.equal(decide({...buy,app_user_id:U+"' or 1=1"},false).why,'user');
  assert.equal(decide({...buy,transaction_id:'x'},false).why,'transaction');
  for(const junk of [null,undefined,'x',42,[]])assert.equal(decide(junk,true).action,'ignore');
});
test('the function is closed without its secret, and only talks to the two purchase functions',()=>{
  assert.match(ts,/if \(!secret \|\| secret\.length < 24 \|\| !url \|\| !key\) return json\(\{ error: "not_configured" \}, 500\);/);
  assert.match(ts,/if \(!sameSecret\(req\.headers\.get\("authorization"\) \|\| "", secret\)\) return json\(\{ error: "forbidden" \}, 401\);/);
  assert.ok(ts.indexOf('sameSecret(req.headers')<ts.indexOf('await req.json()'),'the secret is checked before the body is read');
  const calls=[...ts.matchAll(/"(record_purchase|refund_purchase|[a-z_]+)", \{ p_/g)].map(m=>m[1]);
  assert.deepEqual(calls,['refund_purchase','record_purchase']);
  assert.ok(!/console\.log\([^)]*(secret|key)/i.test(ts),'no secret in the logs');
});
test('the products of the function are the products the database knows',()=>{
  for(const p of [...ts.matchAll(/product: "([a-z_]+)"/g)].map(m=>m[1]))assert.ok(sql.includes(`'${p}'`),p);
  assert.ok(!/gender/i.test(ts));
});
