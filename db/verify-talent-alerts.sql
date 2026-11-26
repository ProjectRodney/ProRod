-- Checks for db/2026-11-17-talent-alerts.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: talent alerts …
begin;
-- P = professional (approved, takes the evening once in the place), B = opted in, C = not opted in, D = opted in but blocked P,
-- E = opted in, other venue, F = opted in, suspended, Q = professional not subscribed, G = arrives later, opted in.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009301','ta-p@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009302','ta-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009303','ta-c@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009304','ta-d@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009305','ta-e@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009306','ta-f@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009307','ta-q@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009308','ta-g@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,account_type)
select u.id, 'Membre '||right(u.id::text,2), '1995-01-01', 'fr', 'Bio de test', 'u/'||u.id||'/a.jpg',
       case when right(u.id::text,2) in ('01','07') then 'pro' else 'personal' end
from auth.users u where u.email like 'ta-%@example.invalid';
insert into public.pro_profiles(user_id,business_name,category,pitch,status,subscription_until) values
('00000000-0000-4000-8000-000000009301','Studio Test','Photographe / vidéo','Portraits et photos de soirée.','approved',null),
('00000000-0000-4000-8000-000000009307','Sans Abonnement','DJ','Mixes pour vos soirées.','approved',null);
insert into private.venues(id,name,category,duration_minutes) values
('00000000-0000-4000-8000-000000009311','Talent test','test',180),('00000000-0000-4000-8000-000000009312','Autre lieu','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009321','00000000-0000-4000-8000-000000009311',encode(extensions.digest(repeat('t',40),'sha256'),'hex'),now()+interval '1 day'),
('00000000-0000-4000-8000-000000009322','00000000-0000-4000-8000-000000009312',encode(extensions.digest(repeat('u',40),'sha256'),'hex'),now()+interval '1 day');
insert into public.blocks(blocker_id,blocked_id) values ('00000000-0000-4000-8000-000000009304','00000000-0000-4000-8000-000000009301');
update private.app_settings set value='true' where key='simulation';
set local role authenticated;

-- Consent: off by default; turning it on without the consent box is refused; on, then off erases the date.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009302","role":"authenticated"}',true);
do $$ begin
  if (select talent_alerts_at from public.profiles where user_id=auth.uid()) is not null then raise exception 'TEST: alerts on by default'; end if;
  begin perform public.set_talent_alerts(true,false); raise exception 'TEST: alerts turned on without consent';
  exception when others then if sqlerrm<>'talent_alerts_consent_required' then raise; end if; end;
  begin perform public.set_talent_alerts(true,null); raise exception 'TEST: alerts turned on with null consent';
  exception when others then if sqlerrm<>'talent_alerts_consent_required' then raise; end if; end;
  perform public.set_talent_alerts(true,true);
  if (select talent_alerts_at from public.profiles where user_id=auth.uid()) is null then raise exception 'TEST: consent date not saved'; end if;
  perform public.set_talent_alerts(false,null);
  if (select talent_alerts_at from public.profiles where user_id=auth.uid()) is not null then raise exception 'TEST: withdrawal kept the consent date'; end if;
  perform public.set_talent_alerts(true,true);
end $$;
-- A member cannot call the internal alert functions.
do $$ begin
  begin perform private.send_talent_alert(auth.uid(),gen_random_uuid(),'00000000-0000-4000-8000-000000009301','x'); raise exception 'TEST: member called send_talent_alert';
  exception when insufficient_privilege then null; end;
  begin perform private.announce_talent('00000000-0000-4000-8000-000000009301',null::public.venue_sessions); raise exception 'TEST: member called announce_talent';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.profiles set talent_alerts_at=now() where user_id in ('00000000-0000-4000-8000-000000009304','00000000-0000-4000-8000-000000009305','00000000-0000-4000-8000-000000009306','00000000-0000-4000-8000-000000009308');
insert into private.account_restrictions(user_id,suspended) values ('00000000-0000-4000-8000-000000009306',true);

-- Everyone but E is in the test venue; E is elsewhere. Then the professional P arrives and takes the evening.
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
select u, '00000000-0000-4000-8000-000000009311','00000000-0000-4000-8000-000000009321','Talent test',now()+interval '2 hours'
from unnest(array['00000000-0000-4000-8000-000000009302','00000000-0000-4000-8000-000000009303','00000000-0000-4000-8000-000000009304','00000000-0000-4000-8000-000000009306','00000000-0000-4000-8000-000000009307']::uuid[]) u;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009305','00000000-0000-4000-8000-000000009312','00000000-0000-4000-8000-000000009322','Autre lieu',now()+interval '2 hours');
do $$ begin if exists(select 1 from public.notifications where kind='talent_here') then raise exception 'TEST: an unsubscribed professional triggered an alert'; end if; end $$;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009301','00000000-0000-4000-8000-000000009311','00000000-0000-4000-8000-000000009321','Talent test',now()+interval '2 hours');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009301","role":"authenticated"}',true);
select public.subscribe_talent_simulated();
reset role;

do $$ declare n public.notifications; begin
  if (select count(*) from public.notifications where kind='talent_here')<>1 then raise exception 'TEST: expected exactly one alert, got %',(select count(*) from public.notifications where kind='talent_here'); end if;
  select * into n from public.notifications where kind='talent_here';
  if n.user_id<>'00000000-0000-4000-8000-000000009302' then raise exception 'TEST: the alert went to the wrong person'; end if;
  if n.payload->>'business'<>'Studio Test' or n.payload->>'venue'<>'Talent test' then raise exception 'TEST: alert content'; end if;
  if n.payload::text like '%00000000-0000-4000-8000-000000009301%' then raise exception 'TEST: the alert carries the professional id'; end if;
end $$;

-- The professional leaves and comes back during the same visit of B: no second alert.
update public.venue_sessions set ended_at=now() where user_id='00000000-0000-4000-8000-000000009301' and ended_at is null;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009301','00000000-0000-4000-8000-000000009311','00000000-0000-4000-8000-000000009321','Talent test',now()+interval '2 hours');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009301","role":"authenticated"}',true);
select public.subscribe_talent_simulated();
reset role;
do $$ begin if (select count(*) from public.notifications where kind='talent_here')<>1 then raise exception 'TEST: same visit alerted twice'; end if; end $$;

-- G arrives later, opted in: G is told about the professional already present (and not about Q, unsubscribed).
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
values ('00000000-0000-4000-8000-000000009308','00000000-0000-4000-8000-000000009311','00000000-0000-4000-8000-000000009321','Talent test',now()+interval '2 hours');
do $$ begin
  if (select count(*) from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009308')<>1 then raise exception 'TEST: late arrival not told about the talent present'; end if;
end $$;

-- Q activates the subscription during the visit: B and G are told (D, blocked, is not: D blocked P, not Q, so D is told).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009307","role":"authenticated"}',true);
select public.subscribe_talent_simulated();
reset role;
do $$ begin
  if (select count(*) from public.notifications where kind='talent_here' and payload->>'business'='Sans Abonnement')<>3 then
    raise exception 'TEST: subscription during a visit: expected B, D and G, got %',(select array_agg(user_id) from public.notifications where kind='talent_here' and payload->>'business'='Sans Abonnement'); end if;
  if exists(select 1 from public.notifications where kind='talent_here' and user_id in ('00000000-0000-4000-8000-000000009303','00000000-0000-4000-8000-000000009305','00000000-0000-4000-8000-000000009306','00000000-0000-4000-8000-000000009301')) then
    raise exception 'TEST: an alert reached someone not opted in, elsewhere, suspended or the professional'; end if;
  if exists(select 1 from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009304' and payload->>'business'='Studio Test') then raise exception 'TEST: alert across a block'; end if;
end $$;

-- Daily limit: at most 5 talent alerts per person per 24 hours.
do $$ declare i int; begin
  for i in 1..10 loop perform private.send_talent_alert('00000000-0000-4000-8000-000000009302',gen_random_uuid(),'00000000-0000-4000-8000-000000009301','Talent test'); end loop;
  if (select count(*) from public.notifications where kind='talent_here' and user_id='00000000-0000-4000-8000-000000009302')<>5 then raise exception 'TEST: daily limit not applied'; end if;
end $$;

-- Withdrawal stops alerts immediately.
update public.notifications set created_at=now()-interval '2 days' where user_id='00000000-0000-4000-8000-000000009302';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009302","role":"authenticated"}',true);
select public.set_talent_alerts(false,null);
reset role;
do $$ begin
  if private.send_talent_alert('00000000-0000-4000-8000-000000009302',gen_random_uuid(),'00000000-0000-4000-8000-000000009301','Talent test') then raise exception 'TEST: alert after withdrawal'; end if;
end $$;

-- Anonymous visitors cannot change the setting.
set local role anon;
do $$ begin
  begin perform public.set_talent_alerts(true,true); raise exception 'TEST: anonymous call accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: talent alerts (opt-in with consent, withdrawal, same venue only, one per visit, late arrival, subscription during a visit, blocks, suspension, daily limit, no id, anonymous denial)' as result;
rollback;
