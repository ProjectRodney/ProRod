-- Checks for db/2026-11-26-pro-evening.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: professional visibility per evening
begin;
-- P and Q = professionals with an approved sheet, R = professional not approved, A = member with talent alerts on,
-- C = member with alerts on who arrives later.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009701','pe-p@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009702','pe-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009703','pe-c@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009704','pe-q@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009705','pe-r@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,account_type,talent_alerts_at)
select u.id, 'Membre '||right(u.id::text,2), '1995-01-01', 'fr', 'Bio de test', 'u/'||u.id||'/a.jpg',
       case when right(u.id::text,2) in ('01','04','05') then 'pro' else 'personal' end,
       case when right(u.id::text,2) in ('02','03') then now() else null end
from auth.users u where u.email like 'pe-%@example.invalid';
insert into public.pro_profiles(user_id,business_name,category,pitch,status,subscription_until) values
('00000000-0000-4000-8000-000000009701','Studio Test','DJ','Mixes pour vos soirées.','approved',null),
('00000000-0000-4000-8000-000000009704','Ancien Abonné','DJ','Mixes pour vos soirées.','approved',null),
('00000000-0000-4000-8000-000000009705','Pas Approuvé','DJ','Mixes pour vos soirées.','pending',null);
insert into private.venues(id,name,category,duration_minutes) values
('00000000-0000-4000-8000-000000009711','Evening test','test',180),('00000000-0000-4000-8000-000000009712','Other place','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009721','00000000-0000-4000-8000-000000009711',encode(extensions.digest(repeat('v',40),'sha256'),'hex'),now()+interval '1 day'),
('00000000-0000-4000-8000-000000009722','00000000-0000-4000-8000-000000009712',encode(extensions.digest(repeat('w',40),'sha256'),'hex'),now()+interval '1 day');
update private.app_settings set value='true' where key='simulation';
-- A visibility date without a visit (what the old 30-day subscription left) lists nobody.
update public.pro_profiles set subscription_until=now()+interval '20 days' where user_id='00000000-0000-4000-8000-000000009704';
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
select u, '00000000-0000-4000-8000-000000009711','00000000-0000-4000-8000-000000009721','Evening test',now()+interval '2 hours'
from unnest(array['00000000-0000-4000-8000-000000009702','00000000-0000-4000-8000-000000009704','00000000-0000-4000-8000-000000009705']::uuid[]) u;

set local role authenticated;
-- Outside a place: the professional cannot turn visibility on.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009701","role":"authenticated"}',true);
do $$ begin
  begin perform public.subscribe_talent_simulated(); raise exception 'TEST: visibility taken outside a place';
  exception when others then if sqlerrm<>'pro_visit_required' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009705","role":"authenticated"}',true);
do $$ begin
  begin perform public.subscribe_talent_simulated(); raise exception 'TEST: visibility taken without an approved sheet';
  exception when others then if sqlerrm<>'pro_not_approved' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009702","role":"authenticated"}',true);
do $$ begin
  if jsonb_array_length(public.venue_talents())<>0 then raise exception 'TEST: a professional is listed without visibility for this visit: %', public.venue_talents(); end if;
end $$;
reset role;

-- P arrives: nothing yet. P takes the evening: listed, and the member who asked for alerts is told once.
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009701','00000000-0000-4000-8000-000000009711','00000000-0000-4000-8000-000000009721','Evening test',now()+interval '2 hours');
do $$ begin if exists(select 1 from public.notifications where kind='talent_here') then raise exception 'TEST: alert sent before the professional took the evening'; end if; end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009701","role":"authenticated"}',true);
do $$ declare r jsonb; p jsonb; begin
  r := public.subscribe_talent_simulated();
  if (r->>'already')::boolean or r->>'venue'<>'Evening test' or (r->>'simulated')::boolean is not true then raise exception 'TEST: answer wrong %', r; end if;
  if abs(extract(epoch from ((r->>'subscription_until')::timestamptz-(now()+interval '2 hours'))))>5 then raise exception 'TEST: visibility does not end with the visit: %', r; end if;
  r := public.subscribe_talent_simulated();
  if (r->>'already')::boolean is not true then raise exception 'TEST: second tap not recognised'; end if;
  p := public.my_pro_profile();
  if (p->>'subscription_active')::boolean is not true then raise exception 'TEST: sheet does not say it is visible'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009702","role":"authenticated"}',true);
do $$ declare t jsonb := public.venue_talents(); begin
  if jsonb_array_length(t)<>1 or t->0->>'business_name'<>'Studio Test' then raise exception 'TEST: professional not listed after taking the evening: %', t; end if;
end $$;
reset role;
do $$ begin
  if (select count(*) from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009702')<>1 then raise exception 'TEST: expected one alert, got %',(select count(*) from public.notifications where kind='talent_here'); end if;
  if (select count(*) from public.passes where user_id='00000000-0000-4000-8000-000000009701' and kind='talent_subscription' and simulated and amount_cents=0)<>1 then raise exception 'TEST: one simulated pass expected'; end if;
end $$;
-- A member who arrives later, with alerts on, is told about the professional visible now.
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009703','00000000-0000-4000-8000-000000009711','00000000-0000-4000-8000-000000009721','Evening test',now()+interval '2 hours');
do $$ begin
  if (select count(*) from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009703')<>1 then raise exception 'TEST: late arrival not told'; end if;
end $$;

-- An administrator lengthens the visit: the visibility follows. Shortened: it follows too.
update public.venue_sessions set expires_at=now()+interval '5 hours' where user_id='00000000-0000-4000-8000-000000009701' and ended_at is null;
do $$ begin
  if abs(extract(epoch from ((select subscription_until from public.pro_profiles where user_id='00000000-0000-4000-8000-000000009701')-(now()+interval '5 hours'))))>5 then raise exception 'TEST: visibility did not follow a longer visit'; end if;
  if abs(extract(epoch from ((select expires_at from public.passes where user_id='00000000-0000-4000-8000-000000009701' and kind='talent_subscription')-(now()+interval '5 hours'))))>5 then raise exception 'TEST: pass did not follow a longer visit'; end if;
end $$;

-- The visit ends: not listed any more, and a new visit (here or elsewhere) starts without visibility.
update public.venue_sessions set ended_at=now() where user_id='00000000-0000-4000-8000-000000009701' and ended_at is null;
do $$ begin
  if (select subscription_until from public.pro_profiles where user_id='00000000-0000-4000-8000-000000009701') is not null then raise exception 'TEST: visibility kept after the visit ended'; end if;
  if private.talent_listed('00000000-0000-4000-8000-000000009701') then raise exception 'TEST: still listed after the visit ended'; end if;
end $$;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009701','00000000-0000-4000-8000-000000009711','00000000-0000-4000-8000-000000009721','Evening test',now()+interval '2 hours');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009702","role":"authenticated"}',true);
do $$ begin
  if jsonb_array_length(public.venue_talents())<>0 then raise exception 'TEST: listed at the next visit without taking the evening again'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009701","role":"authenticated"}',true);
do $$ begin
  if (public.my_pro_profile()->>'subscription_active')::boolean then raise exception 'TEST: sheet says visible at the next visit'; end if;
  if (public.subscribe_talent_simulated()->>'already')::boolean then raise exception 'TEST: next visit treated as already taken'; end if;
end $$;
reset role;
do $$ begin
  -- Taking the evening again during the same visit of A sends no second alert.
  if (select count(*) from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009702')<>1 then raise exception 'TEST: same visit alerted twice'; end if;
  if has_function_privilege('anon','public.subscribe_talent_simulated()','execute') then raise exception 'TEST: open to anonymous callers'; end if;
  if has_function_privilege('authenticated','private.talent_visibility_follows_visit()','execute') then raise exception 'TEST: helper callable by a client'; end if;
end $$;
-- Simulation switched off: nothing can be taken (no real payment exists yet).
update private.app_settings set value='false' where key='simulation';
update public.venue_sessions set ended_at=now() where user_id='00000000-0000-4000-8000-000000009701' and ended_at is null;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009701','00000000-0000-4000-8000-000000009712','00000000-0000-4000-8000-000000009722','Other place',now()+interval '2 hours');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009701","role":"authenticated"}',true);
do $$ begin
  begin perform public.subscribe_talent_simulated(); raise exception 'TEST: taken with simulation off';
  exception when others then if sqlerrm<>'simulation_only' then raise; end if; end;
end $$;
reset role;
rollback;
select 'PASS: professional visibility per evening' as result;
