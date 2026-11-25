-- Checks for db/2026-11-25-edit-qr.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: QR code editing
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009501','eq-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009502','eq-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009509','eq-admin@example.invalid',now(),false);
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000009511','QR edit test','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at,duration_minutes) values
('00000000-0000-4000-8000-000000009521','00000000-0000-4000-8000-000000009511',encode(extensions.digest(repeat('e',40),'sha256'),'hex'),now()+interval '2 days',180),
('00000000-0000-4000-8000-000000009522','00000000-0000-4000-8000-000000009511',encode(extensions.digest(repeat('f',40),'sha256'),'hex'),now()+interval '2 days',180),
('00000000-0000-4000-8000-000000009523','00000000-0000-4000-8000-000000009511',encode(extensions.digest(repeat('g',40),'sha256'),'hex'),now()-interval '1 day',180);
update private.venue_invites set revoked_at=now() where id='00000000-0000-4000-8000-000000009522';
-- A came in one hour ago, B five hours ago (a long visit, as in a test venue); both with the first QR code.
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,started_at,expires_at) values
('00000000-0000-4000-8000-000000009501','00000000-0000-4000-8000-000000009511','00000000-0000-4000-8000-000000009521','QR edit test',now()-interval '1 hour',now()+interval '2 hours'),
('00000000-0000-4000-8000-000000009502','00000000-0000-4000-8000-000000009511','00000000-0000-4000-8000-000000009521','QR edit test',now()-interval '5 hours',now()+interval '7 hours');
-- Both took the pass for their visit: it ends when the visit ends.
insert into public.passes(user_id,venue_id,session_id,kind,simulated,amount_cents,expires_at)
select s.user_id,s.venue_id,s.id,'venue_pass',true,0,s.expires_at from public.venue_sessions s where s.invite_id='00000000-0000-4000-8000-000000009521';
set local role authenticated;

-- A member cannot change a QR code.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009501","role":"authenticated"}',true);
do $$ begin
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009521',360); raise exception 'TEST: a member changed a QR code';
  exception when others then if sqlerrm<>'admin_required' then raise; end if; end;
end $$;

select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009509","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare r jsonb; m numeric; h text; begin
  -- Refusals: out of range, nothing asked, a deleted QR code, an expired one, an unknown one.
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009521',10); raise exception 'TEST: 10 minutes accepted';
  exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009521',721); raise exception 'TEST: more than 12 hours accepted';
  exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009521',null,true,400); raise exception 'TEST: 400 days accepted';
  exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009521'); raise exception 'TEST: nothing to change accepted';
  exception when others then if sqlerrm<>'nothing_to_change' then raise; end if; end;
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009522',360); raise exception 'TEST: a deleted QR code was changed';
  exception when others then if sqlerrm<>'invite_missing' then raise; end if; end;
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009523',360); raise exception 'TEST: an expired QR code was changed';
  exception when others then if sqlerrm<>'invite_missing' then raise; end if; end;
  begin perform public.admin_update_invite('00000000-0000-4000-8000-000000009599',360); raise exception 'TEST: an unknown QR code was changed';
  exception when others then if sqlerrm<>'invite_missing' then raise; end if; end;

  -- One accepted change as an authenticated administrator: the grants let the portal call it.
  r := public.admin_update_invite('00000000-0000-4000-8000-000000009521',240,false);
  if (r->>'duration_minutes')::int<>240 or (r->>'visits_changed')::int<>0 then raise exception 'TEST: change without apply %', r; end if;
end $$;
reset role;

-- From here the checks read the tables directly (as the database owner; the administrator's identity stays in place).
do $$ declare r jsonb; m numeric; h text; begin
  -- The list says how many people are in with each QR code.
  if (select (i->>'live')::int from jsonb_array_elements(public.admin_venues()) v, jsonb_array_elements(v->'invites') i where i->>'id'='00000000-0000-4000-8000-000000009521')<>2 then raise exception 'TEST: people present per QR code'; end if;

  -- Without « apply »: the QR code changes, the visits in progress do not.
  select token_hash into h from private.venue_invites where id='00000000-0000-4000-8000-000000009521';
  m := (select extract(epoch from expires_at-now())/60 from public.venue_sessions where user_id='00000000-0000-4000-8000-000000009501');
  if m is null or m not between 119 and 121 then raise exception 'TEST: a visit moved without apply (% min left)', m; end if;

  -- With « apply », 6 hours: A (in for 1 h) has 5 h left, B (in for 5 h) has 1 h left.
  r := public.admin_update_invite('00000000-0000-4000-8000-000000009521',360,true);
  if (r->>'visits_changed')::int<>2 then raise exception 'TEST: visits changed %', r; end if;
  m := (select extract(epoch from expires_at-now())/60 from public.venue_sessions where user_id='00000000-0000-4000-8000-000000009501');
  if m is null or m not between 299 and 301 then raise exception 'TEST: A has % minutes left, expected 300', m; end if;
  m := (select extract(epoch from expires_at-now())/60 from public.venue_sessions where user_id='00000000-0000-4000-8000-000000009502');
  if m is null or m not between 59 and 61 then raise exception 'TEST: B has % minutes left, expected 60', m; end if;

  -- The pass follows its visit: A's pass now ends with A's visit, five hours from now.
  m := (select extract(epoch from p.expires_at-now())/60 from public.passes p where p.user_id='00000000-0000-4000-8000-000000009501');
  if m is null or m not between 299 and 301 then raise exception 'TEST: A''s pass has % minutes left, expected 300', m; end if;
  if exists(select 1 from public.passes p join public.venue_sessions s on s.id=p.session_id where p.expires_at<>s.expires_at and s.invite_id='00000000-0000-4000-8000-000000009521') then raise exception 'TEST: a pass no longer ends with its visit'; end if;

  -- With « apply », 2 hours: B, in for 5 hours, is no longer in the venue; A has 1 h left. Nothing is deleted.
  r := public.admin_update_invite('00000000-0000-4000-8000-000000009521',120,true);
  if (select count(*) from public.venue_sessions where invite_id='00000000-0000-4000-8000-000000009521' and ended_at is null and expires_at>now())<>1 then raise exception 'TEST: who is still in after shortening'; end if;
  if (select count(*) from public.venue_sessions where invite_id='00000000-0000-4000-8000-000000009521')<>2 then raise exception 'TEST: a visit was deleted'; end if;

  -- The link already shared keeps working: the secret is untouched, and a new visitor gets the new length.
  if (select token_hash from private.venue_invites where id='00000000-0000-4000-8000-000000009521')<>h then raise exception 'TEST: the QR code secret changed'; end if;
  if (public.preview_venue(repeat('e',40))->>'duration_minutes')::int<>120 then raise exception 'TEST: the preview does not announce the new length'; end if;

  -- Pushing back the last day, alone.
  -- Pushing back the last day, alone: 30 days are added to the 2 days left, never taken away.
  r := public.admin_update_invite('00000000-0000-4000-8000-000000009521',null,true,30);
  if (r->>'duration_minutes')::int<>120 then raise exception 'TEST: the length moved when only the last day was asked'; end if;
  m := extract(epoch from (r->>'expires_at')::timestamptz-now())/86400;
  if m is null or m not between 31.9 and 32.1 then raise exception 'TEST: last day in % days, expected 32', m; end if;
  r := public.admin_update_invite('00000000-0000-4000-8000-000000009521',null,true,10);
  m := extract(epoch from (r->>'expires_at')::timestamptz-now())/86400;
  if m is null or m not between 41.9 and 42.1 then raise exception 'TEST: a later last day was brought closer (% days)', m; end if;
  r := public.admin_update_invite('00000000-0000-4000-8000-000000009521',null,true,365);
  m := extract(epoch from (r->>'expires_at')::timestamptz-now())/86400;
  if m is null or m > 365.1 then raise exception 'TEST: a QR code valid more than a year (% days)', m; end if;

  -- Journaled.
  if (select count(*) from private.admin_actions where action='invite_updated' and target='00000000-0000-4000-8000-000000009521')<>6 then raise exception 'TEST: journal'; end if;
end $$;
select 'PASS: QR code editing' as result;
rollback;
