-- Checks for db/2026-11-17-my-places.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: my places …
begin;
-- A = member with visits, B = another member, E = event account.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009401','pl-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009402','pl-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009403','pl-e@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,account_type) values
('00000000-0000-4000-8000-000000009401','Membre A','1995-01-01','fr','Bio','u/00000000-0000-4000-8000-000000009401/a.jpg','personal'),
('00000000-0000-4000-8000-000000009402','Membre B','1995-01-01','fr','Bio','u/00000000-0000-4000-8000-000000009402/a.jpg','personal'),
('00000000-0000-4000-8000-000000009403','Lieu E','1995-01-01','fr',null,null,'venue');
-- V1 open bar, V2 closed bar, V3 one-off event, V4 visited 100 days ago, V5 visited only by B.
insert into private.venues(id,name,category,duration_minutes,active) values
('00000000-0000-4000-8000-000000009411','Bar ouvert','pub',180,true),
('00000000-0000-4000-8000-000000009412','Bar fermé','pub',180,false),
('00000000-0000-4000-8000-000000009413','Soirée unique','event',180,true),
('00000000-0000-4000-8000-000000009414','Vieux bar','pub',180,true),
('00000000-0000-4000-8000-000000009415','Bar de B','pub',180,true);
insert into private.venue_invites(id,venue_id,token_hash,expires_at)
select ('00000000-0000-4000-8000-0000000094'||(20+n))::uuid, ('00000000-0000-4000-8000-0000000094'||(10+n))::uuid, md5('pl'||n), now()+interval '1 day' from generate_series(1,5) n;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,started_at,expires_at,ended_at) values
('00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009421','Bar ouvert',now()-interval '20 days',now()-interval '20 days'+interval '2 hours',now()-interval '20 days'+interval '1 hour'),
('00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009421','Bar ouvert',now()-interval '3 days',now()-interval '3 days'+interval '2 hours',now()-interval '3 days'+interval '1 hour'),
('00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009412','00000000-0000-4000-8000-000000009422','Bar fermé',now()-interval '10 days',now()-interval '10 days'+interval '2 hours',now()-interval '10 days'+interval '1 hour'),
('00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009413','00000000-0000-4000-8000-000000009423','Soirée unique',now()-interval '5 days',now()-interval '5 days'+interval '2 hours',now()-interval '5 days'+interval '1 hour'),
('00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009414','00000000-0000-4000-8000-000000009424','Vieux bar',now()-interval '100 days',now()-interval '100 days'+interval '2 hours',now()-interval '100 days'+interval '1 hour'),
('00000000-0000-4000-8000-000000009402','00000000-0000-4000-8000-000000009415','00000000-0000-4000-8000-000000009425','Bar de B',now()-interval '1 day',now()-interval '1 day'+interval '2 hours',now()-interval '1 day'+interval '1 hour');
insert into public.venue_announcements(venue_id,author_id,body,expires_at) values
('00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009403','Ancienne annonce',now()-interval '1 hour'),
('00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009403','Happy hour jusqu’à 21 h',now()+interval '5 hours'),
('00000000-0000-4000-8000-000000009412','00000000-0000-4000-8000-000000009403','Annonce d’un lieu fermé',now()+interval '5 hours');
set local role authenticated;

select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009401","role":"authenticated"}',true);
do $$ declare r jsonb; begin
  r := public.my_places();
  if jsonb_array_length(r)<>2 then raise exception 'TEST: expected 2 places (open bar, closed bar), got %', r; end if;
  if r->0->>'name'<>'Bar ouvert' or (r->0->>'visits')::int<>2 or (r->0->>'open')::boolean is not true then raise exception 'TEST: first place wrong: %', r->0; end if;
  if r->0->>'announcement'<>'Happy hour jusqu’à 21 h' then raise exception 'TEST: current announcement missing: %', r->0; end if;
  if r->1->>'name'<>'Bar fermé' or (r->1->>'open')::boolean or r->1->>'announcement' is not null then raise exception 'TEST: closed place wrong: %', r->1; end if;
  if r::text like '%Soirée unique%' then raise exception 'TEST: a one-off event is listed'; end if;
  if r::text like '%Vieux bar%' then raise exception 'TEST: a visit older than 90 days is listed'; end if;
  if r::text like '%Bar de B%' then raise exception 'TEST: another member''s visit is listed'; end if;
  -- Hide one place, then a new visit brings it back with only the new visit.
  perform public.hide_place('00000000-0000-4000-8000-000000009411');
  if public.my_places()::text like '%Bar ouvert%' then raise exception 'TEST: hidden place still listed'; end if;
  -- Hiding someone else's place changes nothing for them.
  perform public.hide_place('00000000-0000-4000-8000-000000009415');
end $$;
reset role;
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,started_at,expires_at)
values ('00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009421','Bar ouvert',now(),now()+interval '2 hours');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009401","role":"authenticated"}',true);
do $$ declare r jsonb; begin
  r := public.my_places();
  if r->0->>'name'<>'Bar ouvert' or (r->0->>'visits')::int<>1 then raise exception 'TEST: a new visit should list the place again with 1 visit: %', r; end if;
  perform public.clear_places();
  if jsonb_array_length(public.my_places())<>0 then raise exception 'TEST: clear left places'; end if;
end $$;
-- Visits are kept (hidden only), and B's visit was never touched.
reset role;
do $$ begin
  if (select count(*) from public.venue_sessions where user_id='00000000-0000-4000-8000-000000009401')<>6 then raise exception 'TEST: visits were deleted'; end if;
  if exists(select 1 from public.venue_sessions where user_id='00000000-0000-4000-8000-000000009402' and history_hidden_at is not null) then raise exception 'TEST: another member''s history was changed'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009402","role":"authenticated"}',true);
do $$ begin
  if public.my_places()->0->>'name'<>'Bar de B' then raise exception 'TEST: B''s own list'; end if;
end $$;
-- Event accounts have no visits and cannot call it.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009403","role":"authenticated"}',true);
do $$ begin
  begin perform public.my_places(); raise exception 'TEST: event account listed places';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.my_places(); raise exception 'TEST: anonymous call accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: my places (own visits only, 90 days, no one-off events, closed places, current announcement, hide, new visit, clear without deleting visits, event account and anonymous denied)' as result;
rollback;
