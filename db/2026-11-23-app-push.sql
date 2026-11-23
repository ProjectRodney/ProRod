-- UPZONE migration of 23 November 2026: notifications sent to the phone apps (Android, iPhone), and a choice per kind.
-- Until now a notification reached a phone only through the browser's own push (Web Push), which does not exist inside
-- the apps: there, « someone says hello », « new message »… were visible only once the app was opened.
-- Run once in the Supabase SQL editor of the ProRod project, then redeploy the Edge Function send-push
-- (see docs/app-push-setup.md). Nothing changes for the website's browser notifications.
--
-- Privacy, unchanged: a push only says that something happened (kind + unread count), never a name or a message.
-- A phone is known by the token its app obtains for notifications, kept only while the member is signed in on it.
begin;

-- One row per phone app signed in. No client can read the table; members add or remove only their own phone.
create table if not exists public.app_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique check (token ~ '^Expo(nent)?PushToken\[[A-Za-z0-9_:-]{10,200}\]$'),
  platform text not null check (platform in ('android','ios')),
  created_at timestamptz not null default now(),
  last_sent_at timestamptz
);
create index if not exists app_devices_user on public.app_devices(user_id);
alter table public.app_devices enable row level security;
revoke all on public.app_devices from anon, authenticated;

-- What a member has switched off. No row = on. Account information (warning, restriction, report handled) cannot be
-- switched off: it is not marketing, the member needs to know.
create table if not exists private.notification_mutes (
  user_id uuid not null references auth.users(id) on delete cascade,
  grp text not null check (grp in ('meet','messages','talents')),
  created_at timestamptz not null default now(),
  primary key (user_id, grp)
);
alter table private.notification_mutes enable row level security;
revoke all on private.notification_mutes from public, anon, authenticated;

-- The group of each kind of notification; also the name of the notification category on the phone.
create or replace function private.push_group(p_kind text) returns text language sql immutable set search_path = '' as $$
  select case
    when p_kind in ('introduction_received','reply_received','conversation_closed') then 'meet'
    when p_kind = 'message_received' then 'messages'
    when p_kind = 'talent_here' then 'talents'
    else 'account' end
$$;

create or replace function private.register_device(p_token text, p_platform text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  if p_token is null or p_token !~ '^Expo(nent)?PushToken\[[A-Za-z0-9_:-]{10,200}\]$' or p_platform is null or p_platform not in ('android','ios') then
    raise exception 'invalid_device';
  end if;
  -- One phone app = one token: signing in with another account on the same phone moves it to that account.
  insert into public.app_devices(user_id,token,platform,created_at) values(uid,p_token,p_platform,clock_timestamp())
  on conflict (token) do update set user_id=excluded.user_id, platform=excluded.platform, created_at=clock_timestamp();
  -- At most 5 phones per member.
  delete from public.app_devices where user_id=uid and id not in (select id from public.app_devices where user_id=uid order by created_at desc limit 5);
end $$;

create or replace function private.unregister_device(p_token text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  delete from public.app_devices where token=p_token and user_id=uid;
end $$;

create or replace function private.notification_prefs() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  return jsonb_build_object(
    'meet', not exists(select 1 from private.notification_mutes m where m.user_id=uid and m.grp='meet'),
    'messages', not exists(select 1 from private.notification_mutes m where m.user_id=uid and m.grp='messages'),
    'talents', not exists(select 1 from private.notification_mutes m where m.user_id=uid and m.grp='talents'),
    'phones', (select count(*) from public.app_devices d where d.user_id=uid),
    'browsers', (select count(*) from public.push_subscriptions s where s.user_id=uid));
end $$;

create or replace function private.set_notification_pref(p_group text, p_on boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  if p_group is null or p_group not in ('meet','messages','talents') or p_on is null then raise exception 'invalid_group'; end if;
  if p_on then delete from private.notification_mutes where user_id=uid and grp=p_group;
  else insert into private.notification_mutes(user_id,grp) values(uid,p_group) on conflict do nothing;
  end if;
  return private.notification_prefs();
end $$;

create or replace function public.register_device(p_token text, p_platform text) returns void language sql set search_path = '' as $$ select private.register_device(p_token,p_platform) $$;
create or replace function public.unregister_device(p_token text) returns void language sql set search_path = '' as $$ select private.unregister_device(p_token) $$;
create or replace function public.notification_prefs() returns jsonb language sql set search_path = '' as $$ select private.notification_prefs() $$;
create or replace function public.set_notification_pref(p_group text, p_on boolean) returns jsonb language sql set search_path = '' as $$ select private.set_notification_pref(p_group,p_on) $$;

-- The trigger that announces a new notification: now also to the member's phone apps, and never for a group the member
-- switched off. A failure here never blocks the notification itself.
create or replace function private.push_on_notification() returns trigger language plpgsql security definer set search_path = '' as $$
declare secret text; url text; subs jsonb; devs jsonb; lang text; v_group text := private.push_group(new.kind);
begin
  begin
    if v_group <> 'account' and exists(select 1 from private.notification_mutes m where m.user_id=new.user_id and m.grp=v_group) then return new; end if;
    select jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)) into subs from public.push_subscriptions s where s.user_id=new.user_id;
    select jsonb_agg(d.token) into devs from public.app_devices d where d.user_id=new.user_id;
    if subs is null and devs is null then return new; end if;
    select decrypted_secret into secret from vault.decrypted_secrets where name='push_hook_secret' limit 1;
    url := private.setting('push_function_url') #>> '{}';
    if secret is null or url is null then return new; end if;
    select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=new.user_id;
    perform net.http_post(url:=url,
      headers:=jsonb_build_object('content-type','application/json','x-push-secret',secret),
      body:=jsonb_build_object('kind',new.kind,'group',v_group,'lang',coalesce(lang,'fr'),'badge',private.unread_total(new.user_id),
                               'subscriptions',coalesce(subs,'[]'::jsonb),'devices',coalesce(devs,'[]'::jsonb)));
    update public.push_subscriptions set last_sent_at=now() where user_id=new.user_id;
    update public.app_devices set last_sent_at=now() where user_id=new.user_id;
  exception when others then
    raise warning 'push_on_notification: %', sqlerrm;
  end;
  return new;
end $$;

revoke all on function private.push_group(text), private.push_on_notification() from public, anon, authenticated;
revoke all on function private.register_device(text,text), private.unregister_device(text), private.notification_prefs(), private.set_notification_pref(text,boolean) from public, anon;
revoke all on function public.register_device(text,text), public.unregister_device(text), public.notification_prefs(), public.set_notification_pref(text,boolean) from public, anon;
grant execute on function private.register_device(text,text), private.unregister_device(text), private.notification_prefs(), private.set_notification_pref(text,boolean) to authenticated;
grant execute on function public.register_device(text,text), public.unregister_device(text), public.notification_prefs(), public.set_notification_pref(text,boolean) to authenticated, service_role;

commit;
