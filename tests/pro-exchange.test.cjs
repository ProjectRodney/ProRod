// Exchange between a member and a professional (26 Nov 2026): rules that must stay in the server script and the app.
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');
const sql=fs.readFileSync('db/2026-11-26-pro-exchange.sql','utf8');const check=fs.readFileSync('db/verify-pro-exchange.sql','utf8');
const app=fs.readFileSync('src/account.js','utf8');const tu=fs.readFileSync('src/tu.js','utf8');

test('messages of an exchange are never readable by a client directly',()=>{
  assert.match(sql,/alter table public\.enquiry_messages enable row level security;/);
  assert.match(sql,/revoke all on public\.enquiry_messages from anon, authenticated;/);
  assert.ok(!/create policy[^;]*enquiry_messages/i.test(sql),'no policy opens the table');
});
test('only the two people of a thread read it or write in it',()=>{
  for(const fn of ['reply_enquiry','enquiry_thread','close_enquiry','enquiry_block','enquiry_report']){
    const body=sql.slice(sql.indexOf(`function private.${fn}(`));
    assert.match(body.slice(0,900),/private\.require_person\(\)/,fn+' needs a personal or pro account');
    assert.match(body.slice(0,1400),/\(from_id=uid or pro_id=uid\)/,fn+' is limited to the two people');
  }
});
test('a professional answers, never starts and never chases',()=>{
  assert.ok(!/insert into public\.enquiries/i.test(sql),'this script opens no thread: only send_enquiry does, from the member');
  assert.match(sql,/if private\.enquiry_pro_streak\(e\)>=3 then raise exception 'enquiry_wait'/);
  assert.ok(!/insert into public\.(introductions|conversations)/i.test(sql),'nothing is created on the dating side');
});
test('a block, a suspension or a sheet no longer approved closes the thread for writing',()=>{
  const open=sql.slice(sql.indexOf('function private.enquiry_open('),sql.indexOf('function private.enquiry_pro_streak('));
  for(const needle of ['e.closed_at is null','private.blocked_between(e.from_id,e.pro_id)','r.suspended',"t.status='approved'"])assert.ok(open.includes(needle),needle);
  assert.match(sql,/create trigger close_enquiries_on_block after insert on public\.blocks/);
});
test('functions are closed to anonymous callers and helpers to everyone',()=>{
  assert.match(sql,/revoke all on function public\.reply_enquiry\(uuid,text\)[^;]*from public, anon;/);
  assert.match(sql,/revoke all on function private\.enquiry_open\(public\.enquiries\)[^;]*from public, anon, authenticated;/);
});
test('the check script leaves nothing behind and uses no temporary object',()=>{
  assert.match(check,/^begin;/m);assert.match(check,/^rollback;/m);
  assert.ok(!/temp table|pg_temp/i.test(check));
  assert.match(check,/PASS: exchange between a member and a professional/);
});
test('the app shows the thread on both sides with close, block and report, and never holds the other person\'s id',()=>{
  for(const needle of ['function enquiryView','function enquiryList',"rpc('enquiry_thread'","rpc('reply_enquiry'","rpc('my_enquiries'","rpc('close_enquiry'","rpc('enquiry_block'","rpc('enquiry_report'",'data-action="enquiry-close"','data-action="enquiry-block"'])assert.ok(app.includes(needle),needle);
  const view=app.slice(app.indexOf('function enquiryView'),app.indexOf('async function openEnquiry'));
  assert.ok(!view.includes('data-user='),'no user id in the thread screen');
  assert.ok(!view.includes('translate'),'no message of the thread is sent anywhere');
});
test('new sentences that address a member have their « tu » version',()=>{
  for(const fr of ['Vous avez fermé cet échange. Il reste lisible ici.','À part de vos conversations de rencontre.','Échange professionnel uniquement, séparé de vos conversations de rencontre. Vous pouvez le fermer à tout moment.']){
    assert.ok(app.includes(fr),fr);assert.ok(tu.includes(`'${fr}':`),'tu: '+fr);
  }
});
