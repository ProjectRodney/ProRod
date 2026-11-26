// Professionals are visible for one evening, tied to their visit (26 Nov 2026); the scan lands on the list.
const test=require('node:test');const assert=require('node:assert');const fs=require('node:fs');
const sql=fs.readFileSync('db/2026-11-26-pro-evening.sql','utf8');const check=fs.readFileSync('db/verify-pro-evening.sql','utf8');
const app=fs.readFileSync('src/account.js','utf8');const tu=fs.readFileSync('src/tu.js','utf8');
const body=(name)=>{const i=sql.indexOf('function '+name);assert.ok(i>=0,name);return sql.slice(i,sql.indexOf('$function$;',i));};

test('visibility is taken on site, for the live visit, and never stacks days',()=>{
  const f=body('private.subscribe_talent_simulated()');
  assert.match(f,/if mine\.id is null then raise exception 'pro_visit_required'/);
  assert.match(f,/set subscription_until=mine\.expires_at, subscription_session=mine\.id/);
  assert.ok(!/interval '30 days'/.test(sql),'no 30-day subscription left');
  assert.match(f,/row\.status<>'approved' then raise exception 'pro_not_approved'/);
  assert.match(f,/is distinct from true then raise exception 'simulation_only'/,'nothing can be taken while no real payment exists');
  assert.match(f,/values\(uid,mine\.venue_id,mine\.id,'talent_subscription',true,0,mine\.expires_at\)/,'simulated, 0 €');
});
test('a professional is listed only in the place and during the visit the visibility was taken for',()=>{
  assert.match(body('private.venue_talents()'),/and t\.subscription_session=s\.id/);
  assert.match(body('private.talent_listed(p_pro uuid)'),/join public\.venue_sessions s on s\.id=t\.subscription_session and s\.user_id=p\.user_id and s\.ended_at is null and s\.expires_at>now\(\)/);
  assert.match(sql,/update public\.pro_profiles set subscription_until=null where subscription_session is null and subscription_until is not null;/,'old 30-day dates stop');
});
test('the visibility follows its visit when the visit ends or its length changes',()=>{
  assert.match(sql,/create trigger talent_visibility_follows_visit after update of expires_at, ended_at on public\.venue_sessions/);
  assert.match(body('private.talent_visibility_follows_visit()'),/case when new\.ended_at is not null then null else new\.expires_at end/);
  assert.match(sql,/revoke all on function private\.talent_listed\(uuid\), private\.talent_visibility_follows_visit\(\) from public, anon, authenticated;/);
});
test('no rule depends on gender, and nothing is charged',()=>{
  assert.ok(!/gender|interested_in/.test(sql));
  assert.ok(!/amount_cents\s*[,=]\s*[1-9]/.test(sql));
});
test('the check script leaves nothing behind',()=>{
  assert.match(check,/^begin;/m);assert.match(check,/^rollback;/m);assert.ok(!/temp table|pg_temp/i.test(check));
  assert.match(check,/PASS: professional visibility per evening/);
});
test('the pro screen offers the evening only inside a place, and says it is simulated',()=>{
  const v=app.slice(app.indexOf('function proView'),app.indexOf('function talentsView'));
  assert.ok(v.includes('Être visible ce soir (simulation)'));
  assert.ok(v.includes('data-action="scan"'),'outside a place, the button is the scanner');
  assert.ok(!v.includes('30 jours')&&!v.includes('abonnement talent'));
  assert.ok(!/9,99|10 €/.test(v),'no price shown while payment is simulated');
  assert.ok(app.includes("pro_visit_required:["));
});
test('after the scan a personal account lands on the list; pro and event accounts do not',()=>{
  const j=app.slice(app.indexOf('async function joinNow'),app.indexOf('async function startScan'));
  assert.match(j,/if\(isPro\(\)\|\|isVenue\(\)\)\{view='home';render\(\);return;\}try\{await loadPeople\(\);\}/);
  assert.match(j,/if\(before\.includes\(session\.venue_name\)\)\{view='back';render\(\);return;\}/,'a place already visited keeps its « Te revoilà » screen');
});
test('the empty list says the member is among the first, with its « tu » version',()=>{
  const fr='Vous êtes parmi les premiers ici. La liste se remplit au fil des arrivées.';
  assert.ok(app.includes(fr));assert.ok(tu.includes(`'${fr}':'Tu es parmi les premiers ici.`));
});
