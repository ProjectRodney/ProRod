-- ANZIAK migration of 7 November 2026: push notifications (Web Push) and the unread count on the app icon.
-- Run once in the Supabase SQL editor of the ProRod project, after creating the Edge Function send-push and its secrets.
-- Privacy: a push only says that something happened (kind + unread count), never a name or a message, like the in-app
-- notifications. Subscriptions are private: no client can read the table; members save or remove only their own.

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique check (char_length(endpoint) between 20 and 1000 and endpoint like 'https://%'),
  p256dh text not null check (char_length(p256dh) between 20 and 200),
  auth text not null check (char_length(auth) between 8 and 100),
  created_at timestamptz not null default now(),
  last_sent_at timestamptz
);
create index if not exists push_subscriptions_user on public.push_subscriptions(user_id);
alter table public.push_subscriptions enable row level security;
revoke all on public.push_subscriptions from anon, authenticated;

-- Unread total, same formula as the app's « Messages » dot: introductions waiting + unread messages + unread notifications.
create or replace function private.unread_total(p_uid uuid) returns integer language sql stable security definer set search_path = '' as $$
  select (
    (select count(*) from public.introductions i where i.recipient_id=p_uid and i.status='pending' and not private.blocked_between(p_uid,i.sender_id))
  + (select count(*) from public.messages m join public.conversations c on c.id=m.conversation_id
       where (c.a_id=p_uid or c.b_id=p_uid) and m.sender_id<>p_uid
         and not private.blocked_between(p_uid,case when c.a_id=p_uid then c.b_id else c.a_id end)
         and m.created_at>coalesce((select r.read_at from public.conversation_reads r where r.conversation_id=c.id and r.user_id=p_uid),'epoch'::timestamptz))
  + (select count(*) from public.notifications n where n.user_id=p_uid and n.read_at is null))::integer
$$;
revoke all on function private.unread_total(uuid) from public, anon, authenticated;

create or replace function private.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint) not between 20 and 1000
     or char_length(coalesce(p_p256dh,'')) not between 20 and 200 or char_length(coalesce(p_auth,'')) not between 8 and 100 then
    raise exception 'invalid_subscription';
  end if;
  -- One browser = one endpoint: signing in with another account on the same phone moves it to that account.
  insert into public.push_subscriptions(user_id,endpoint,p256dh,auth) values(uid,p_endpoint,p_p256dh,p_auth)
  on conflict (endpoint) do update set user_id=excluded.user_id, p256dh=excluded.p256dh, auth=excluded.auth, created_at=now();
  -- At most 10 devices per member.
  delete from public.push_subscriptions where user_id=uid and id not in (select id from public.push_subscriptions where user_id=uid order by created_at desc limit 10);
end $$;

create or replace function private.delete_push_subscription(p_endpoint text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  delete from public.push_subscriptions where endpoint=p_endpoint and user_id=uid;
end $$;

create or replace function private.push_status() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member();  -- checked first, whatever the table holds
begin
  return jsonb_build_object('devices',(select count(*) from public.push_subscriptions where user_id=uid));
end $$;

create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void language sql set search_path = '' as $$ select private.save_push_subscription(p_endpoint,p_p256dh,p_auth) $$;
create or replace function public.delete_push_subscription(p_endpoint text) returns void language sql set search_path = '' as $$ select private.delete_push_subscription(p_endpoint) $$;
create or replace function public.push_status() returns jsonb language sql set search_path = '' as $$ select private.push_status() $$;
revoke all on function private.save_push_subscription(text,text,text), private.delete_push_subscription(text), private.push_status() from public, anon;
grant execute on function private.save_push_subscription(text,text,text), private.delete_push_subscription(text), private.push_status() to authenticated;
revoke all on function public.save_push_subscription(text,text,text), public.delete_push_subscription(text), public.push_status() from public, anon;
grant execute on function public.save_push_subscription(text,text,text), public.delete_push_subscription(text), public.push_status() to authenticated, service_role;

-- Where the database calls the sending function (public address, not a secret) and the shared secret (Vault, never in Git).
insert into private.app_settings(key,value) values ('push_function_url','"https://blqcmpqctetmjqsfdvsq.supabase.co/functions/v1/send-push"')
on conflict (key) do nothing;

-- After each new notification: if the member has devices, ask send-push to deliver it (asynchronous, pg_net).
-- Silent while the Vault secret push_hook_secret is missing. A failure here never blocks the notification itself.
create or replace function private.push_on_notification() returns trigger language plpgsql security definer set search_path = '' as $$
declare secret text; url text; subs jsonb; lang text;
begin
  begin
    select jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)) into subs from public.push_subscriptions s where s.user_id=new.user_id;
    if subs is null then return new; end if;
    select decrypted_secret into secret from vault.decrypted_secrets where name='push_hook_secret' limit 1;
    url := private.setting('push_function_url') #>> '{}';
    if secret is null or url is null then return new; end if;
    select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=new.user_id;
    perform net.http_post(url:=url,
      headers:=jsonb_build_object('content-type','application/json','x-push-secret',secret),
      body:=jsonb_build_object('kind',new.kind,'lang',coalesce(lang,'fr'),'badge',private.unread_total(new.user_id),'subscriptions',subs));
    update public.push_subscriptions set last_sent_at=now() where user_id=new.user_id;
  exception when others then
    raise warning 'push_on_notification: %', sqlerrm;
  end;
  return new;
end $$;
revoke all on function private.push_on_notification() from public, anon, authenticated;
drop trigger if exists push_after_notification on public.notifications;
create trigger push_after_notification after insert on public.notifications for each row execute function private.push_on_notification();

-- Vault secret (same value as the Edge Function secret PUSH_HOOK_SECRET), once, in Project Settings → Vault:
--   name push_hook_secret, value = the secret given by DZOFT (never in Git).
