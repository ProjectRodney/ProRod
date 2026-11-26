// Professional accounts for professional use only (17 Nov 2026, client decision). Server rules: db/2026-11-17-pro-accounts.sql,
// checked by db/verify-pro-accounts.sql. No message is read: the rule follows the account type only.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');
const sql=fs.readFileSync('db/2026-11-17-pro-accounts.sql','utf8');const fn=fs.readFileSync('db/functions.sql','utf8');
const app=fs.readFileSync('src/account.js','utf8');const tu=fs.readFileSync('src/tu.js','utf8');
const body=(src,name)=>{const i=src.toLowerCase().indexOf(name.toLowerCase());assert.ok(i>=0,name);return src.slice(i,src.indexOf('end $function$;',i));};

test('a pro account cannot turn itself back into a personal one',()=>{
  for(const src of [sql,fn])assert.match(body(src,'FUNCTION private.set_account_type('),/if existing='pro' and p_type<>'pro' then raise exception 'pro_locked'/);
});
test('the meeting side is for personal accounts only, in the migration and in functions.sql',()=>{
  for(const src of [sql,fn]){
    const vm=body(src,'function private.venue_members()');
    assert.match(vm,/if private\.is_pro\(uid\) then raise exception 'pro_account_dating'/);
    assert.match(vm,/p\.account_type='personal' and private\.profile_complete\(p\)/);
    const si=body(src,'function private.send_introduction(');
    assert.match(si,/if private\.is_pro\(uid\) then raise exception 'pro_account_dating'/);
    assert.match(si,/if private\.is_pro\(p_to\) then raise exception 'not_co_present'/);
    const ri=body(src,'FUNCTION private.respond_introduction(');
    assert.ok(ri.indexOf("if p_accept is distinct from true")<ri.indexOf('private.is_pro(uid)'),'declining stays possible');
    const sm=body(src,'FUNCTION private.send_message(');
    assert.match(sm,/if private\.is_pro\(uid\) then raise exception 'pro_account_dating'/);
    assert.match(sm,/if private\.is_pro\(other\) then raise exception 'pro_conversation_closed'/);
  }
  assert.match(sql,/revoke all on function private\.is_pro\(uuid\) from public, anon, authenticated;/);
  assert.doesNotMatch(sql,/messages m|m\.body|p_body ~|ilike/,'the rule never reads message content');
});
test('the app explains the rule to pros, asks before becoming pro, and offers the switch',()=>{
  assert.match(app,/\$\{isPro\(\)\?`<div class="pro-only">.*?\$\{switchRow\(\)\}<\/div>`:`<button data-action="people"/);
  assert.match(app,/action==='become-pro'\)\{if\(!confirm\(/);
  for(const code of ['pro_account_dating','pro_conversation_closed','pro_locked'])assert.match(app,new RegExp(code+":\\['"));
  for(const k of ['Compte professionnel : vous n’apparaissez pas','Un compte professionnel reste professionnel : il n’apparaîtra plus'])assert.ok(tu.includes("'"+k),k);
});
