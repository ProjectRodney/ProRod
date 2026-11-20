// Welcome page of upzoneapp.fr (20 Nov 2026): light page, FR/EN, and people who already use the app skip it.
const test=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const vm=require('node:vm');
const html=fs.readFileSync('public/index.html','utf8'),js=fs.readFileSync('public/landing.js','utf8'),app=fs.readFileSync('src/account.js','utf8');
test('the page offers sign-up, sign-in, the pro/event entry and the legal pages, in French and English',()=>{
  for(const href of ['./account.html?start=signup','./account.html?start=signin','./account.html?start=pro-kind','./confidentialite.html','./cgu.html'])assert.ok(html.includes(`href="${href}"`),href);
  const fr=(html.match(/data-fr="/g)||[]).length,en=(html.match(/data-en="/g)||[]).length;assert.ok(fr>=14);assert.equal(fr,en,'every text has both languages');
  assert.match(app,/\['signup','signin','pro-kind'\]\.includes\(entryMode\)/);
  assert.doesNotMatch(html,/gratuit|free\b/i,'no price promise on the welcome page');
  assert.doesNotMatch(html,/noindex/);
});
test('known phones, the installed app and links meant for the app go straight to the app',()=>{
  const run=(o)=>{let to=null;const store=o.store||{};const ctx={URLSearchParams,location:{search:o.search||'',hash:o.hash||'',replace:u=>{to=u;}},localStorage:{getItem:k=>store[k]||null},navigator:{standalone:!!o.standalone},window:{},document:{addEventListener(){},documentElement:{lang:'fr'},querySelectorAll:()=>[]}};vm.runInNewContext(js,ctx);return to;};
  assert.equal(run({}),null,'a new visitor sees the page');
  assert.equal(run({search:'?venue=abc'}),'./account.html?venue=abc','QR link');
  assert.equal(run({hash:'#access_token=x&type=signup'}),'./account.html#access_token=x&type=signup','e-mail link');
  assert.equal(run({store:{'prorod-auth':'{}'}}),'./account.html','signed in');
  assert.equal(run({store:{'upzone-visited':'1'}}),'./account.html','has used the app');
  assert.equal(run({standalone:true}),'./account.html','installed app');
  assert.equal(run({search:'?landing=1',store:{'prorod-auth':'{}'}}),null,'?landing=1 shows the page');
});
