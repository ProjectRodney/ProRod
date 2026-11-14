-- Checks for db/2026-11-14-qr-visit-length.sql. Transaction-only fixtures; everything is rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009201','qr-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009209','qr-admin@example.invalid',now(),false);
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000009211','QR length test','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009221','00000000-0000-4000-8000-000000009211',encode(extensions.digest(repeat('q',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values ('avatars','u/00000000-0000-4000-8000-000000009201/avatar.jpg','00000000-0000-4000-8000-000000009201');
update private.app_settings set value='120' where key='max_session_minutes';
set local role authenticated;

-- A member cannot create a QR code, with or without a visit length.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009201","role":"authenticated"}',true);
do $$ begin
  begin perform public.admin_create_invite('00000000-0000-4000-8000-000000009211',30,360); raise exception 'TEST: a member created a QR code';
  exception when others then if sqlerrm<>'admin_required' then raise; end if; end;
end $$;
select public.save_profile('Alex','2000-01-01','fr',true,'Jazz and coffee','u/00000000-0000-4000-8000-000000009201/avatar.jpg');

-- The administrator creates QR codes of 6 hours, 4 hours and without a length; out-of-range lengths are refused.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009209","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare r jsonb; begin
  begin perform public.admin_create_invite('00000000-0000-4000-8000-000000009211',30,10); raise exception 'TEST: 10 minutes accepted';
  exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  begin perform public.admin_create_invite('00000000-0000-4000-8000-000000009211',30,721); raise exception 'TEST: more than 12 hours accepted';
  exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  r := public.admin_create_invite('00000000-0000-4000-8000-000000009211',30,360);
  if (r->>'duration_minutes')::int<>360 then raise exception 'TEST: 6 hours not returned'; end if;
  perform set_config('qrtest.six',r->>'token',true);
  r := public.admin_create_invite('00000000-0000-4000-8000-000000009211',30,240); perform set_config('qrtest.four',r->>'token',true);
  r := public.admin_create_invite('00000000-0000-4000-8000-000000009211'); perform set_config('qrtest.none',r->>'token',true);
  if r->>'duration_minutes' is not null then raise exception 'TEST: a QR code without a length carries one'; end if;
  if not exists(select 1 from jsonb_array_elements(public.admin_venues()) v, jsonb_array_elements(v->'invites') i where (i->>'duration_minutes')::int=360) then raise exception 'TEST: the portal list does not show the length'; end if;
end $$;

-- The member's visit follows the QR code scanned.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009201","role":"authenticated"}',true);
do $$ declare s public.venue_sessions; m numeric; begin
  if (public.preview_venue(current_setting('qrtest.six'))->>'duration_minutes')::int<>360 then raise exception 'TEST: preview does not announce 6 hours'; end if;
  s := public.join_venue(current_setting('qrtest.six')); m := extract(epoch from s.expires_at-now())/60;
  if m not between 359 and 361 then raise exception 'TEST: 6-hour QR gave % minutes', m; end if;
  s := public.join_venue(current_setting('qrtest.four')); m := extract(epoch from s.expires_at-now())/60;
  if m not between 239 and 241 then raise exception 'TEST: 4-hour QR gave % minutes', m; end if;
  -- Without a length: the venue's 180 minutes, capped by the server setting (120).
  if (public.preview_venue(current_setting('qrtest.none'))->>'duration_minutes')::int<>120 then raise exception 'TEST: preview without length is not capped'; end if;
  s := public.join_venue(current_setting('qrtest.none')); m := extract(epoch from s.expires_at-now())/60;
  if m not between 119 and 121 then raise exception 'TEST: QR without length gave % minutes', m; end if;
  -- A QR code created before this change behaves as before.
  s := public.join_venue(repeat('q',40)); m := extract(epoch from s.expires_at-now())/60;
  if m not between 119 and 121 then raise exception 'TEST: older QR gave % minutes', m; end if;
end $$;
reset role;
select 'PASS: QR visit length' as result;
rollback;
