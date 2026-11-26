-- Checks for db/2026-11-26-purchases.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: server side of real purchases
begin;
-- A = member in the place (alerts on, holds a simulated pass), P = approved professional in the place,
-- X = member who is not in any place, admin.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009801','pu-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009802','pu-p@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009803','pu-x@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009809','pu-admin@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,account_type,talent_alerts_at)
select u.id, 'Membre '||right(u.id::text,2), '1995-01-01', 'fr', 'Bio de test', 'u/'||u.id||'/a.jpg',
       case when right(u.id::text,2)='02' then 'pro' else 'personal' end,
       case when right(u.id::text,2)='01' then now() else null end
from auth.users u where u.email like 'pu-%@example.invalid';
insert into public.pro_profiles(user_id,business_name,category,pitch,status) values
('00000000-0000-4000-8000-000000009802','Studio Test','DJ','Mixes pour vos soirées.','approved');
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000009811','Purchase test','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009821','00000000-0000-4000-8000-000000009811',encode(extensions.digest(repeat('y',40),'sha256'),'hex'),now()+interval '1 day');
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
select u, '00000000-0000-4000-8000-000000009811','00000000-0000-4000-8000-000000009821','Purchase test',now()+interval '2 hours'
from unnest(array['00000000-0000-4000-8000-000000009801','00000000-0000-4000-8000-000000009802']::uuid[]) u;
insert into public.passes(user_id,venue_id,kind,simulated,amount_cents,expires_at)
values ('00000000-0000-4000-8000-000000009801','00000000-0000-4000-8000-000000009811','venue_pass',true,0,now()+interval '2 hours');
update private.app_settings set value='"everyone"' where key='pass_rule';

-- No phone can record, refund or read a purchase.
do $$ begin
  if has_function_privilege('authenticated','public.record_purchase(uuid,text,text,text,integer,text)','execute')
     or has_function_privilege('anon','public.record_purchase(uuid,text,text,text,integer,text)','execute')
     or has_function_privilege('authenticated','private.record_purchase(uuid,text,text,text,integer,text)','execute')
     or has_function_privilege('authenticated','public.refund_purchase(text,text)','execute')
     or has_function_privilege('anon','public.refund_purchase(text,text)','execute') then raise exception 'TEST: a client can record or refund a purchase'; end if;
  if has_table_privilege('authenticated','public.purchases','select') or has_table_privilege('anon','public.purchases','select')
     or has_table_privilege('authenticated','public.purchases','insert') then raise exception 'TEST: purchases table open to clients'; end if;
  if not has_function_privilege('service_role','public.record_purchase(uuid,text,text,text,integer,text)','execute')
     or not has_function_privilege('service_role','private.record_purchase(uuid,text,text,text,integer,text)','execute')
     or not has_function_privilege('service_role','public.refund_purchase(text,text)','execute')
     or not has_schema_privilege('service_role','private','usage') then raise exception 'TEST: the service key cannot record a purchase'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009801","role":"authenticated"}',true);
do $$ begin
  begin perform public.record_purchase('00000000-0000-4000-8000-000000009801','apple','venue_pass','TX-SELF-000001',299,'EUR'); raise exception 'TEST: a member granted themselves a pass';
  exception when insufficient_privilege then null; end;
  begin perform public.admin_purchases(10); raise exception 'TEST: a member read the purchases';
  exception when others then if sqlerrm<>'admin_required' then raise; end if; end;
end $$;
reset role;

-- The server (service key) records confirmed purchases. The checks call the same functions as the owner of the
-- database, and verify separately that the service key is allowed to call them.
do $$ declare r jsonb; begin
  -- Member pass: granted once, for the visit; the store's repeated notice changes nothing.
  r := private.record_purchase('00000000-0000-4000-8000-000000009801','apple','venue_pass','TX-APPLE-000001',299,'eur');
  if (r->>'granted')::boolean is not true or (r->>'already')::boolean then raise exception 'TEST: pass not granted %', r; end if;
  r := private.record_purchase('00000000-0000-4000-8000-000000009801','apple','venue_pass','TX-APPLE-000001',299,'EUR');
  if (r->>'already')::boolean is not true then raise exception 'TEST: repeated notice not recognised'; end if;
  begin perform private.record_purchase('00000000-0000-4000-8000-000000009803','apple','venue_pass','TX-APPLE-000001',299,'EUR'); raise exception 'TEST: one transaction used for two people';
  exception when others then if sqlerrm<>'purchase_conflict' then raise; end if; end;
  -- A second purchase while the pass is active: written down, not granted (to refund).
  r := private.record_purchase('00000000-0000-4000-8000-000000009801','google','venue_pass','TX-GOOGLE-000002',299,'EUR');
  if (r->>'granted')::boolean or r->>'note'<>'already_active' then raise exception 'TEST: double purchase %', r; end if;
  -- Paid outside a place: written down, not granted.
  r := private.record_purchase('00000000-0000-4000-8000-000000009803','apple','venue_pass','TX-APPLE-000003',299,'EUR');
  if (r->>'granted')::boolean or r->>'note'<>'no_visit' then raise exception 'TEST: purchase outside a place %', r; end if;
  -- A professional account cannot buy the members' pass; a member cannot buy the professionals' evening.
  r := private.record_purchase('00000000-0000-4000-8000-000000009802','apple','venue_pass','TX-APPLE-000004',299,'EUR');
  if (r->>'granted')::boolean or r->>'note'<>'wrong_account' then raise exception 'TEST: pro bought the member pass %', r; end if;
  r := private.record_purchase('00000000-0000-4000-8000-000000009801','apple','pro_evening','TX-APPLE-000005',999,'EUR');
  if (r->>'granted')::boolean or r->>'note'<>'pro_not_approved' then raise exception 'TEST: member bought the pro evening %', r; end if;
  -- The professional's evening: granted for the visit.
  r := private.record_purchase('00000000-0000-4000-8000-000000009802','google','pro_evening','TX-GOOGLE-000006',999,'EUR');
  if (r->>'granted')::boolean is not true then raise exception 'TEST: pro evening not granted %', r; end if;
  -- Nonsense is refused.
  begin perform private.record_purchase('00000000-0000-4000-8000-000000009801','apple','gold_membership','TX-APPLE-000007',299,'EUR'); raise exception 'TEST: unknown product accepted';
  exception when others then if sqlerrm<>'purchase_invalid' then raise; end if; end;
  begin perform private.record_purchase('00000000-0000-4000-8000-000000009803','paypal','venue_pass','TX-OTHER-000008',299,'EUR'); raise exception 'TEST: unknown store accepted';
  exception when check_violation then null; end;
  begin perform private.record_purchase('00000000-0000-4000-8000-000000009803','apple','venue_pass','TX-APPLE-000009',0,'EUR'); raise exception 'TEST: zero amount accepted';
  exception when check_violation then null; end;
  begin perform private.record_purchase(gen_random_uuid(),'apple','venue_pass','TX-APPLE-000010',299,'EUR'); raise exception 'TEST: purchase for nobody accepted';
  exception when others then if sqlerrm<>'purchase_invalid' then raise; end if; end;
end $$;
reset role;

do $$ begin
  if (select count(*) from public.passes where user_id='00000000-0000-4000-8000-000000009801' and kind='venue_pass' and status='active' and not simulated and amount_cents=299)<>1 then raise exception 'TEST: one paid pass expected'; end if;
  if exists(select 1 from public.passes where user_id='00000000-0000-4000-8000-000000009801' and kind='venue_pass' and status='active' and simulated) then raise exception 'TEST: simulated pass left active beside the paid one'; end if;
  if abs(extract(epoch from ((select expires_at from public.passes where user_id='00000000-0000-4000-8000-000000009801' and not simulated)-(now()+interval '2 hours'))))>5 then raise exception 'TEST: paid pass does not end with the visit'; end if;
  if not private.venue_unlocked('00000000-0000-4000-8000-000000009801','00000000-0000-4000-8000-000000009811') then raise exception 'TEST: place not unlocked by the paid pass'; end if;
  if not private.talent_listed('00000000-0000-4000-8000-000000009802') then raise exception 'TEST: professional not listed after paying'; end if;
  if (select count(*) from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009801')<>1 then raise exception 'TEST: opted-in member not told'; end if;
  if (select count(*) from public.purchases where transaction_id like 'TX-%')<>6 then raise exception 'TEST: expected 6 purchases written down, got %',(select count(*) from public.purchases where transaction_id like 'TX-%'); end if;
  if (select count(*) from public.purchases where transaction_id like 'TX-%' and not granted)<>4 then raise exception 'TEST: purchases to refund not all listed'; end if;
  if (select currency from public.purchases where transaction_id='TX-APPLE-000001')<>'EUR' then raise exception 'TEST: currency not normalised'; end if;
end $$;

-- The administrator sees what was paid, including what was not granted.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009809","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare l jsonb := public.admin_purchases(50); begin
  if (select count(*) from jsonb_array_elements(l) x where x->>'transaction' like 'TX-%')<>6 then raise exception 'TEST: admin list incomplete'; end if;
  if not exists(select 1 from jsonb_array_elements(l) x where x->>'transaction'='TX-APPLE-000003' and (x->>'granted')::boolean is false and x->>'note'='no_visit') then raise exception 'TEST: ungranted purchase not flagged'; end if;
  if l::text like '%00000000-0000-4000-8000-0000000098%' then raise exception 'TEST: user id in the admin list'; end if;
end $$;
reset role;

-- Refunds reported by the store stop what was bought.
do $$ declare r jsonb; begin
  r := private.refund_purchase('apple','TX-APPLE-000001');
  if r->>'status'<>'refunded' or (r->>'already')::boolean then raise exception 'TEST: refund %', r; end if;
  if (private.refund_purchase('apple','TX-APPLE-000001')->>'already')::boolean is not true then raise exception 'TEST: repeated refund not recognised'; end if;
  perform private.refund_purchase('google','TX-GOOGLE-000006');
  begin perform private.refund_purchase('apple','TX-NOT-KNOWN-1'); raise exception 'TEST: refund of an unknown purchase accepted';
  exception when others then if sqlerrm<>'purchase_missing' then raise; end if; end;
end $$;
reset role;
do $$ begin
  if private.venue_unlocked('00000000-0000-4000-8000-000000009801','00000000-0000-4000-8000-000000009811') then raise exception 'TEST: place still unlocked after the refund'; end if;
  if private.talent_listed('00000000-0000-4000-8000-000000009802') then raise exception 'TEST: professional still listed after the refund'; end if;
  if (select count(*) from public.passes where status='refunded' and not simulated and user_id in ('00000000-0000-4000-8000-000000009801','00000000-0000-4000-8000-000000009802'))<>2 then raise exception 'TEST: passes not marked refunded'; end if;
end $$;
rollback;
select 'PASS: server side of real purchases' as result;
