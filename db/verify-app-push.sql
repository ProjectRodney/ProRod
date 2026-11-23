-- Checks for db/2026-11-23-app-push.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: app push …
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009401','ap-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009402','ap-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009403','ap-unconfirmed@example.invalid',null,false);
insert into public.profiles(user_id,display_name,birth_date,locale) values
('00000000-0000-4000-8000-000000009401','Membre A','1995-01-01','fr'),
('00000000-0000-4000-8000-000000009402','Membre B','1995-01-01','en');
-- Where the announcement goes: a pretend address and secret, so the trigger has something to call.
insert into private.app_settings(key,value) values('push_function_url','"https://example.invalid/send-push"') on conflict (key) do update set value=excluded.value;

-- The groups.
do $$ begin
  if private.push_group('introduction_received')<>'meet' or private.push_group('reply_received')<>'meet' or private.push_group('conversation_closed')<>'meet' then raise exception 'TEST: meet group'; end if;
  if private.push_group('message_received')<>'messages' or private.push_group('talent_here')<>'talents' then raise exception 'TEST: messages / talents group'; end if;
  if private.push_group('account_warned')<>'account' or private.push_group('account_restricted')<>'account' or private.push_group('report_handled')<>'account' or private.push_group('anything_new')<>'account' then raise exception 'TEST: account group'; end if;
end $$;

set local role authenticated;
-- A member registers their phone; a wrong token or platform is refused; the table itself cannot be read or written.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009401","role":"authenticated"}',true);
do $$ begin
  perform public.register_device('ExponentPushToken[aaaaaaaaaaaaaaaaaaaaaa]','android');
  begin perform public.register_device('not-a-token','android'); raise exception 'TEST: wrong token accepted';
  exception when others then if sqlerrm<>'invalid_device' then raise; end if; end;
  begin perform public.register_device('ExponentPushToken[bbbbbbbbbbbbbbbbbbbbbb]','windows'); raise exception 'TEST: wrong platform accepted';
  exception when others then if sqlerrm<>'invalid_device' then raise; end if; end;
  begin perform public.register_device(null,'android'); raise exception 'TEST: null token accepted';
  exception when others then if sqlerrm<>'invalid_device' then raise; end if; end;
  begin perform 1 from public.app_devices; raise exception 'TEST: a member can read app_devices';
  exception when insufficient_privilege then null; end;
  begin insert into public.app_devices(user_id,token,platform) values(auth.uid(),'ExponentPushToken[cccccccccccccccccccccc]','ios'); raise exception 'TEST: a member can write app_devices';
  exception when insufficient_privilege then null; end;
  begin perform private.push_group('x'); raise exception 'TEST: a member can call push_group';
  exception when insufficient_privilege then null; end;
  if (public.notification_prefs()->>'phones')::int<>1 then raise exception 'TEST: phone not counted'; end if;
  if public.notification_prefs() - 'phones' - 'browsers' <> '{"meet":true,"messages":true,"talents":true}'::jsonb then raise exception 'TEST: everything should be on by default: %', public.notification_prefs(); end if;
end $$;
-- An unconfirmed account and a visitor cannot register a phone.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009403","role":"authenticated"}',true);
do $$ begin
  begin perform public.register_device('ExponentPushToken[dddddddddddddddddddddd]','android'); raise exception 'TEST: unconfirmed account registered a phone';
  exception when others then if sqlerrm<>'verified_account_required' then raise; end if; end;
  begin perform public.notification_prefs(); raise exception 'TEST: unconfirmed account read preferences';
  exception when others then if sqlerrm<>'verified_account_required' then raise; end if; end;
end $$;
reset role;
set local role anon;
do $$ begin
  begin perform public.register_device('ExponentPushToken[eeeeeeeeeeeeeeeeeeeeee]','android'); raise exception 'TEST: a visitor can call register_device';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- A notification for A is announced to A's phone, with its group; nothing is announced to B (no phone, no browser).
-- The test never writes a secret: it uses the project's own push_hook_secret when there is one, and creates a throwaway
-- one (rolled back) only when there is none. Requests are read from pg_net's queue when the SQL editor may read it;
-- (only this test's own requests, to the address set above, are counted);
-- otherwise the test relies on last_sent_at, which the trigger sets only after it has queued a request.
do $$ begin
  if not exists(select 1 from vault.decrypted_secrets where name='push_hook_secret') then perform vault.create_secret('test-secret','push_hook_secret'); end if;
end $$;
create or replace function pg_temp.calls() returns bigint language plpgsql as $f$
begin return (select count(*) from net.http_request_queue where url='https://example.invalid/send-push');
exception when insufficient_privilege or undefined_table then return null; end $f$;
create or replace function pg_temp.last_call() returns jsonb language plpgsql as $f$
begin return (select convert_from(body,'UTF8')::jsonb from net.http_request_queue where url='https://example.invalid/send-push' order by id desc limit 1);
exception when insufficient_privilege or undefined_table then return null; end $f$;
create or replace function pg_temp.unsent() returns void language sql as $f$ update public.app_devices set last_sent_at=null where user_id='00000000-0000-4000-8000-000000009401' $f$;
create or replace function pg_temp.sent() returns boolean language sql as $f$ select exists(select 1 from public.app_devices where user_id='00000000-0000-4000-8000-000000009401' and last_sent_at is not null) $f$;
do $$ declare n0 bigint := pg_temp.calls(); b jsonb; begin
  perform pg_temp.unsent();
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009401','introduction_received');
  if not pg_temp.sent() then raise exception 'TEST: no announcement for a member with a phone'; end if;
  if n0 is not null then
    if pg_temp.calls()<>n0+1 then raise exception 'TEST: expected exactly one request'; end if;
    b := pg_temp.last_call();
    if b->>'group'<>'meet' or b->>'kind'<>'introduction_received' or b->>'lang'<>'fr' then raise exception 'TEST: wrong announcement %', b; end if;
    if b->'devices'<>'["ExponentPushToken[aaaaaaaaaaaaaaaaaaaaaa]"]'::jsonb or b->'subscriptions'<>'[]'::jsonb then raise exception 'TEST: wrong targets %', b; end if;
    if b ? 'user_id' or b::text like '%Membre%' or b::text like '%example.invalid/ap-%' then raise exception 'TEST: the announcement carries personal data %', b; end if;
  end if;
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009402','message_received');
  if n0 is not null and pg_temp.calls()<>n0+1 then raise exception 'TEST: announcement for a member without any device'; end if;
end $$;

-- A switches « messages » off: no announcement for a message, still one for a hello, and always one for the account.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009401","role":"authenticated"}',true);
do $$ begin
  begin perform public.set_notification_pref('account',false); raise exception 'TEST: account information switched off';
  exception when others then if sqlerrm<>'invalid_group' then raise; end if; end;
  begin perform public.set_notification_pref('messages',null); raise exception 'TEST: null choice accepted';
  exception when others then if sqlerrm<>'invalid_group' then raise; end if; end;
  if (public.set_notification_pref('messages',false)->>'messages')::boolean then raise exception 'TEST: messages still on'; end if;
  perform public.set_notification_pref('messages',false); -- twice: no error
end $$;
reset role;
do $$ declare n0 bigint := pg_temp.calls(); begin
  perform pg_temp.unsent();
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009401','message_received');
  if pg_temp.sent() or pg_temp.calls()<>n0 then raise exception 'TEST: a switched-off group was announced'; end if;
  if (select count(*) from public.notifications where user_id='00000000-0000-4000-8000-000000009401' and kind='message_received')<>1 then raise exception 'TEST: the notification itself must still exist in the app'; end if;
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009401','reply_received');
  if not pg_temp.sent() or pg_temp.calls()<>n0+1 then raise exception 'TEST: another group was silenced too'; end if;
  perform pg_temp.unsent();
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009401','account_restricted');
  if not pg_temp.sent() or pg_temp.calls()<>n0+2 or pg_temp.last_call()->>'group'<>'account' then raise exception 'TEST: account information not announced'; end if;
end $$;
set local role authenticated;
do $$ begin
  if not (public.set_notification_pref('messages',true)->>'messages')::boolean then raise exception 'TEST: messages not back on'; end if;
end $$;

-- B signs in on the same phone: the phone moves to B, A no longer receives anything on it. B can remove only their own.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009402","role":"authenticated"}',true);
do $$ begin
  perform public.register_device('ExponentPushToken[aaaaaaaaaaaaaaaaaaaaaa]','android');
  if (public.notification_prefs()->>'phones')::int<>1 then raise exception 'TEST: phone not moved to B'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009401","role":"authenticated"}',true);
do $$ begin
  if (public.notification_prefs()->>'phones')::int<>0 then raise exception 'TEST: A still has the phone'; end if;
  perform public.unregister_device('ExponentPushToken[aaaaaaaaaaaaaaaaaaaaaa]'); -- not A's any more: nothing happens
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009402","role":"authenticated"}',true);
do $$ begin
  if (public.notification_prefs()->>'phones')::int<>1 then raise exception 'TEST: A removed B''s phone'; end if;
  -- At most 5 phones per member.
  for i in 1..7 loop perform public.register_device('ExponentPushToken[phone'||i||'xxxxxxxxxxxxxxxx]','ios'); end loop;
  if (public.notification_prefs()->>'phones')::int<>5 then raise exception 'TEST: more than 5 phones kept: %', public.notification_prefs()->>'phones'; end if;
  perform public.unregister_device('ExponentPushToken[phone7xxxxxxxxxxxxxxxx]');
  if (public.notification_prefs()->>'phones')::int<>4 then raise exception 'TEST: own phone not removed'; end if;
end $$;
reset role;
-- Deleting the account removes its phones and choices.
do $$ begin
  insert into private.notification_mutes(user_id,grp) values('00000000-0000-4000-8000-000000009402','talents');
  delete from auth.users where id='00000000-0000-4000-8000-000000009402';
  if exists(select 1 from public.app_devices where user_id='00000000-0000-4000-8000-000000009402') or exists(select 1 from private.notification_mutes where user_id='00000000-0000-4000-8000-000000009402') then raise exception 'TEST: phones or choices survive the account'; end if;
end $$;
select 'PASS: app push (register, refuse, groups, switch off, move between accounts, limit, deletion)'
  || case when pg_temp.calls() is null then ' — content of the request not read (pg_net queue not readable here)' else ' — content of the request checked' end as result;
rollback;
