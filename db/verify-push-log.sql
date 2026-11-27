-- Checks for db/2026-11-27-push-log.sql. Transaction-only fixtures; everything is rolled back, nothing is sent.
-- Expected last line: PASS: push log …
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009501','pl-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009502','pl-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009503','pl-admin@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale) values
('00000000-0000-4000-8000-000000009501','Membre A','1995-01-01','fr'),
('00000000-0000-4000-8000-000000009502','Membre B','1995-01-01','fr');
-- A pretend address (nothing is reached: the request is rolled back with the rest) and, only if the project has none, a throwaway secret.
insert into private.app_settings(key,value) values('push_function_url','"https://example.invalid/send-push"') on conflict (key) do update set value=excluded.value;
do $$ begin
  if not exists(select 1 from vault.decrypted_secrets where name='push_hook_secret') then perform vault.create_secret('test-secret','push_hook_secret'); end if;
end $$;
insert into public.app_devices(user_id,token,platform) values('00000000-0000-4000-8000-000000009501','ExponentPushToken[pushlogtestaaaaaaaaaaaa]','android');
-- Only this test's own lines are looked at: those written after this point.
select set_config('pl.start',coalesce((select max(id) from private.push_log),0)::text,true);
select set_config('pl.net','yes',true);

-- 1. One send = one line, waiting for its answer. A member with no browser and no phone = no line.
do $$ declare n int; r private.push_log; begin
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009502','report_handled');
  select count(*) into n from private.push_log where id>current_setting('pl.start')::bigint;
  if n<>1 then raise exception 'TEST: expected one line, found %', n; end if;
  select * into r from private.push_log where id>current_setting('pl.start')::bigint;
  if r.kind<>'report_handled' or r.browsers<>0 or r.phones<>1 or r.request_id is null or r.checked_at is not null or r.problem is not null then raise exception 'TEST: wrong line %', to_jsonb(r); end if;
end $$;

-- 2. The line says nothing about the member.
do $$ begin
  if exists(select 1 from information_schema.columns where table_schema='private' and table_name='push_log'
            and column_name not in ('id','created_at','kind','browsers','phones','request_id','checked_at','http_status','sent','removed','phones_sent','phones_removed','problem')) then
    raise exception 'TEST: the record has a column that was not planned';
  end if;
end $$;

-- 3. Answers. Written by hand into pg_net's table when the SQL editor may write there; otherwise this part is skipped and said so.
do $$ declare r private.push_log; req bigint; begin
  select request_id into req from private.push_log where id>current_setting('pl.start')::bigint;
  begin
    insert into net._http_response(id,status_code,content,timed_out) values(req,200,'{"sent":0,"removed":0,"phones":1,"phonesRemoved":0}',false);
  exception when insufficient_privilege then perform set_config('pl.net','no',true); return; end;
  perform private.push_collect();
  select * into r from private.push_log where request_id=req;
  if r.checked_at is null or r.http_status<>200 or r.phones_sent<>1 or r.sent<>0 or r.problem is not null then raise exception 'TEST: delivered answer not read %', to_jsonb(r); end if;

  -- Refused by the function (wrong secret).
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select request_id into req from private.push_log order by id desc limit 1;
  insert into net._http_response(id,status_code,content,timed_out) values(req,401,'{"error":"forbidden"}',false);
  perform private.push_collect();
  select * into r from private.push_log where request_id=req;
  if r.problem<>'forbidden' or r.http_status<>401 then raise exception 'TEST: refusal not read %', to_jsonb(r); end if;

  -- No answer in time.
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select request_id into req from private.push_log order by id desc limit 1;
  insert into net._http_response(id,status_code,content,timed_out,error_msg) values(req,null,null,true,'Timeout was reached');
  perform private.push_collect();
  select * into r from private.push_log where request_id=req;
  if r.problem<>'timeout' then raise exception 'TEST: timeout not read %', to_jsonb(r); end if;

  -- An answer that is not what we expect must not break anything.
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select request_id into req from private.push_log order by id desc limit 1;
  insert into net._http_response(id,status_code,content,timed_out) values(req,200,'{not json',false);
  perform private.push_collect();
  select * into r from private.push_log where request_id=req;
  if r.checked_at is null or r.sent is not null or r.problem is not null then raise exception 'TEST: odd answer %', to_jsonb(r); end if;
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select request_id into req from private.push_log order by id desc limit 1;
  insert into net._http_response(id,status_code,content,timed_out) values(req,502,'<html>Bad gateway</html>',false);
  perform private.push_collect();
  select * into r from private.push_log where request_id=req;
  if r.problem<>'http_502' then raise exception 'TEST: gateway error %', to_jsonb(r); end if;
end $$;

-- 4. A line never answered is closed after a day; lines are erased after 30 days.
do $$ declare a bigint; b bigint; begin
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select id into a from private.push_log order by id desc limit 1;
  update private.push_log set created_at=now()-interval '2 days' where id=a;
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select id into b from private.push_log order by id desc limit 1;
  update private.push_log set created_at=now()-interval '31 days' where id=b;
  perform private.push_collect();
  if (select problem from private.push_log where id=a) is distinct from 'answer_not_found' then raise exception 'TEST: old line not closed'; end if;
  if exists(select 1 from private.push_log where id=b) then raise exception 'TEST: line older than 30 days kept'; end if;
end $$;

-- 5. Not configured (no address): the member's action still works, and the line says why nothing left.
do $$ declare r private.push_log; begin
  delete from private.app_settings where key='push_function_url';
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','report_handled');
  select * into r from private.push_log order by id desc limit 1;
  if r.problem<>'not_configured' or r.request_id is not null then raise exception 'TEST: missing configuration not recorded %', to_jsonb(r); end if;
  insert into private.app_settings(key,value) values('push_function_url','"https://example.invalid/send-push"');
end $$;

-- 6. A switched-off group still sends nothing and writes no line.
do $$ declare n bigint; begin
  select count(*) into n from private.push_log;
  insert into private.notification_mutes(user_id,grp) values('00000000-0000-4000-8000-000000009501','messages');
  insert into public.notifications(user_id,kind) values('00000000-0000-4000-8000-000000009501','message_received');
  if (select count(*) from private.push_log)<>n then raise exception 'TEST: a switched-off group was recorded as a send'; end if;
end $$;

-- 7. Who may look. A member: nothing. The administrator: totals and lines, with no member in them.
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009501","role":"authenticated"}',true);
do $$ begin
  begin perform public.admin_push_log(); raise exception 'TEST: a member can read the record';
  exception when insufficient_privilege then null; end;
  begin perform 1 from private.push_log; raise exception 'TEST: a member can read the table';
  exception when insufficient_privilege then null; end;
  begin perform private.push_collect(); raise exception 'TEST: a member can call push_collect';
  exception when insufficient_privilege then null; end;
  begin perform private.push_totals(now()); raise exception 'TEST: a member can call push_totals';
  exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009503","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare j jsonb := public.admin_push_log(50); begin
  if (j->'day'->>'sends')::int<1 or (j->>'phones')::int<1 or (j->>'configured')::boolean is not true then raise exception 'TEST: totals %', j - 'rows'; end if;
  if jsonb_array_length(j->'rows')<1 then raise exception 'TEST: no lines for the administrator'; end if;
  if j::text ~ '00000000-0000-4000-8000-0000000095' or j::text ilike '%ExponentPushToken%' or j::text ilike '%Membre%' or j::text ilike '%example.invalid%' then raise exception 'TEST: the record shows a member, a phone or an address'; end if;
  if current_setting('pl.net')='yes' then
    if (j->'day'->>'delivered')::int<1 or (j->'day'->>'problems')::int<3 then raise exception 'TEST: delivered / problems not counted %', j->'day'; end if;
  end if;
end $$;
reset role;
select 'PASS: push log (one line per send, no member in it, answers read, refusal, timeout, closing, 30 days, access)'
  || case when current_setting('pl.net')='yes' then '' else ' — answers not simulated (pg_net table not writable here)' end as result;
rollback;
