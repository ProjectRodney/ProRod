const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const crypto=require('node:crypto');
const pages=fs.readdirSync('public').filter(f=>f.endsWith('.html'));
test('every page carries a content security policy: own scripts only, no plugins, data only to our Supabase project (17 Nov)',()=>{
  assert.ok(pages.length>=6);
  for(const f of pages){
    const h=fs.readFileSync('public/'+f,'utf8');
    const m=h.match(/<meta charset="utf-8"><meta http-equiv="Content-Security-Policy" content="([^"]+)">/);
    assert.ok(m,f+': policy right after the charset');
    const csp=m[1];
    for(const d of ["default-src 'self'","object-src 'none'","base-uri 'self'","form-action 'self'","frame-src 'none'"])assert.ok(csp.includes(d),f+': '+d);
    const script=csp.match(/script-src ([^;]+)/)[1];
    assert.doesNotMatch(script,/unsafe-inline|unsafe-eval|https?:|\*/,f+': no inline, eval or outside scripts');
    for(const d of ['connect-src','img-src'])assert.doesNotMatch(csp.match(new RegExp(d+' ([^;]+)'))[1],/(^|\s)(https:|\*)(\s|$)/,f+': '+d+' names hosts');
    // Each inline script is allowed by its exact hash, nothing else.
    const inline=[...h.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(x=>"'sha256-"+crypto.createHash('sha256').update(x[1]).digest('base64')+"'");
    assert.deepEqual(script.split(/\s+/).filter(x=>x.startsWith("'sha256-")).sort(),inline.sort(),f+': inline script hashes are current (edit a script, update its hash)');
    assert.doesNotMatch(h,/\son[a-z]+="/i,f+': no inline event handlers');
  }
});
test('the app builds no inline event handlers the policy would block',()=>{
  for(const f of ['src/account.js','src/admin.js'])assert.doesNotMatch(fs.readFileSync(f,'utf8'),/\son(click|change|input|submit|load|error|focus)="/,f);
});
