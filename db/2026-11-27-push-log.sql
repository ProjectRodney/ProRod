-- UPZONE — 27 November 2026: a record of every notification send, so the administrator can see whether notifications
-- really leave the server (asked by DZOFT after a tester's report: nobody could tell from our side).
--
-- What is kept, per send: the date, the kind of notification (« message_received »…), how many browsers and phones it
-- was addressed to, and what the sending function answered (delivered, no longer registered, refused, no answer).
-- What is NOT kept: who it was for, any name, any text of a message. Lines are erased after 30 days.
-- Nothing changes for members: same notifications, same choices.
--
-- How: the trigger keeps the number pg_net gives to its call; the answer of the function « send-push » is read later
-- from pg_net's own table of answers (kept a few hours by Supabase), at the next send or when the administrator opens
-- the page. No change to the function itself: nothing to redeploy.
--
-- Safe to run again. Needs db/2026-11-23-app-push.sql (already installed on ProRod).
begin;

do $$ begin
  if to_regclass('public.app_devices') is null then raise exception 'Install db/2026-11-23-app-push.sql first.'; end if;
  -- The columns this script reads from pg_net. If Supabase renames them, stop here rather than install something blind.
  perform 1 from information_schema.columns where table_schema='net' and table_name='_http_response' and column_name in ('id','status_code','content','timed_out','error_msg')
    having count(*)=5;
  if not found then raise exception 'pg_net: net._http_response does not have the expected columns.'; end if;
end $$;

create table if not exists private.push_log (
  id bigint generated always as identity primary key,
  created_at timestamptz not null default now(),
  kind text not null,
  browsers int not null default 0,
  phones int not null default 0,
  request_id bigint,
  checked_at timestamptz,
  http_status int,
  sent int, removed int, phones_sent int, phones_removed int,
  problem text
);
create index if not exists push_log_created on private.push_log(created_at desc);
create index if not exists push_log_unchecked on private.push_log(request_id) where checked_at is null;
alter table private.push_log enable row level security;
revoke all on private.push_log from public, anon, authenticated;

-- Reads the answers that have arrived since last time. Never raises: a problem here must not stop a notification.
create or replace function private.push_collect() returns void language plpgsql security definer set search_path = '' as $$
begin
  begin
    update private.push_log l set checked_at=now(), http_status=r.status_code,
      sent=case when j.b ? 'sent' then (j.b->>'sent')::int end,
      removed=case when j.b ? 'removed' then (j.b->>'removed')::int end,
      phones_sent=case when j.b ? 'phones' then (j.b->>'phones')::int end,
      phones_removed=case when j.b ? 'phonesRemoved' then (j.b->>'phonesRemoved')::int end,
      problem=case when r.timed_out then 'timeout'
                   when r.status_code is null then left(coalesce(r.error_msg,'no_answer'),120)
                   when r.status_code<>200 then left(coalesce(j.b->>'error','http_'||r.status_code),120) end
    from net._http_response r
    cross join lateral (select case when r.status_code is not null and left(ltrim(coalesce(r.content,'')),1)='{' and length(r.content)<2000
                                    then private.push_json(r.content) else '{}'::jsonb end as b) j
    where l.checked_at is null and l.request_id=r.id;
    -- pg_net forgets its answers after a few hours: a line still without answer after a day will never get one.
    update private.push_log set checked_at=now(), problem='answer_not_found' where checked_at is null and created_at<now()-interval '1 day';
    delete from private.push_log where created_at<now()-interval '30 days';
  exception when others then
    raise warning 'push_collect: %', sqlerrm;
  end;
end $$;

-- Text to JSON without ever raising (an answer that is not JSON counts as empty).
create or replace function private.push_json(p text) returns jsonb language plpgsql immutable set search_path = '' as $$
begin
  return p::jsonb;
exception when others then
  return '{}'::jsonb;
end $$;

-- Same trigger as db/2026-11-23-app-push.sql, plus one line in the record per send.
create or replace function private.push_on_notification() returns trigger language plpgsql security definer set search_path = '' as $$
declare secret text; url text; subs jsonb; devs jsonb; lang text; v_group text := private.push_group(new.kind); req bigint;
begin
  begin
    if v_group <> 'account' and exists(select 1 from private.notification_mutes m where m.user_id=new.user_id and m.grp=v_group) then return new; end if;
    select jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)) into subs from public.push_subscriptions s where s.user_id=new.user_id;
    select jsonb_agg(d.token) into devs from public.app_devices d where d.user_id=new.user_id;
    if subs is null and devs is null then return new; end if;
    select decrypted_secret into secret from vault.decrypted_secrets where name='push_hook_secret' limit 1;
    url := private.setting('push_function_url') #>> '{}';
    if secret is null or url is null then
      insert into private.push_log(kind,browsers,phones,checked_at,problem)
        values(left(new.kind,60),coalesce(jsonb_array_length(subs),0),coalesce(jsonb_array_length(devs),0),now(),'not_configured');
      return new;
    end if;
    select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=new.user_id;
    req := net.http_post(url:=url,
      headers:=jsonb_build_object('content-type','application/json','x-push-secret',secret),
      body:=jsonb_build_object('kind',new.kind,'group',v_group,'lang',coalesce(lang,'fr'),'badge',private.unread_total(new.user_id),
                               'subscriptions',coalesce(subs,'[]'::jsonb),'devices',coalesce(devs,'[]'::jsonb)));
    update public.push_subscriptions set last_sent_at=now() where user_id=new.user_id;
    update public.app_devices set last_sent_at=now() where user_id=new.user_id;
    begin
      perform private.push_collect();
      insert into private.push_log(kind,browsers,phones,request_id)
        values(left(new.kind,60),coalesce(jsonb_array_length(subs),0),coalesce(jsonb_array_length(devs),0),req);
    exception when others then
      raise warning 'push_log: %', sqlerrm;
    end;
  exception when others then
    raise warning 'push_on_notification: %', sqlerrm;
  end;
  return new;
end $$;

-- What the administrator sees: totals for 24 hours and 7 days, the last sends, never a member.
create or replace function private.admin_push_log(p_limit integer default 30) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); res jsonb;
begin
  perform private.push_collect();
  select jsonb_build_object(
    'day', (select private.push_totals(now()-interval '1 day')),
    'week', (select private.push_totals(now()-interval '7 days')),
    'browsers', (select count(*) from public.push_subscriptions),
    'phones', (select count(*) from public.app_devices),
    'configured', exists(select 1 from vault.decrypted_secrets where name='push_hook_secret') and private.setting('push_function_url') is not null,
    'rows', coalesce((select jsonb_agg(x.row order by x.created_at desc) from (
      select l.created_at, jsonb_build_object('at',l.created_at,'kind',l.kind,'browsers',l.browsers,'phones',l.phones,'checked',l.checked_at is not null,
        'sent',l.sent,'removed',l.removed,'phones_sent',l.phones_sent,'phones_removed',l.phones_removed,'problem',l.problem) as row
      from private.push_log l order by l.created_at desc limit least(greatest(coalesce(p_limit,30),1),200)) x),'[]'::jsonb)) into res;
  return res;
end $$;

create or replace function private.push_totals(p_since timestamptz) returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'sends', count(*),
    'waiting', count(*) filter (where checked_at is null),
    'problems', count(*) filter (where problem is not null),
    'addressed', coalesce(sum(browsers+phones),0),
    'delivered', coalesce(sum(coalesce(sent,0)+coalesce(phones_sent,0)),0),
    'removed', coalesce(sum(coalesce(removed,0)+coalesce(phones_removed,0)),0),
    'refused', coalesce(sum(greatest(browsers+phones-coalesce(sent,0)-coalesce(phones_sent,0)-coalesce(removed,0)-coalesce(phones_removed,0),0)) filter (where checked_at is not null and problem is null),0),
    'last_ok', max(created_at) filter (where coalesce(sent,0)+coalesce(phones_sent,0)>0),
    'last_problem', max(created_at) filter (where problem is not null))
  from private.push_log where created_at>=p_since
$$;

create or replace function public.admin_push_log(p_limit integer default 30) returns jsonb language sql set search_path = '' as $$ select private.admin_push_log(p_limit) $$;

revoke all on function private.push_collect(), private.push_json(text), private.push_totals(timestamptz), private.push_on_notification() from public, anon, authenticated;
revoke all on function private.admin_push_log(integer), public.admin_push_log(integer) from public, anon;
grant execute on function private.admin_push_log(integer) to authenticated;
grant execute on function public.admin_push_log(integer) to authenticated, service_role;

commit;
