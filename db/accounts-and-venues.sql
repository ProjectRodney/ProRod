-- ProRod foundation. Apply only to the dedicated ProRod project.
create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(btrim(display_name)) between 2 and 40),
  birth_date date not null,
  locale text not null check (locale in ('fr','en')),
  rules_version text not null default '2026-11-05',
  rules_accepted_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  bio text check (bio is null or char_length(btrim(bio)) between 1 and 300),
  avatar_path text,
  avatar_updated_at timestamptz
);
alter table public.profiles enable row level security;
revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
create policy own_profile on public.profiles for select to authenticated using ((select auth.uid()) = user_id);

-- Private photo storage: each member reads and writes only u/<own user id>/...
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', false, 2097152, array['image/jpeg','image/png','image/webp']);
create policy avatars_own_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u' and (storage.foldername(name))[2] = (select auth.uid())::text);
create policy avatars_own_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u' and (storage.foldername(name))[2] = (select auth.uid())::text);
create policy avatars_own_update on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u' and (storage.foldername(name))[2] = (select auth.uid())::text);
create policy avatars_own_delete on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u' and (storage.foldername(name))[2] = (select auth.uid())::text);

create table private.venues (
  id uuid primary key default gen_random_uuid(), name text not null check(char_length(name) between 2 and 100),
  category text not null check(category in ('restaurant','pub','chicha','nightclub','barber','test')),
  duration_minutes integer not null check(duration_minutes between 15 and 720), active boolean not null default true,
  address text
);
create table private.venue_invites (
  id uuid primary key default gen_random_uuid(), venue_id uuid not null references private.venues(id),
  token_hash text not null unique, expires_at timestamptz not null, revoked_at timestamptz
);
create index on private.venue_invites(venue_id);
create table private.account_restrictions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  suspended boolean not null default false
);
alter table private.venues enable row level security;
alter table private.venue_invites enable row level security;
alter table private.account_restrictions enable row level security;
revoke all on all tables in schema private from public, anon, authenticated;

create table public.venue_sessions (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  venue_id uuid not null references private.venues(id), invite_id uuid not null references private.venue_invites(id),
  venue_name text not null, started_at timestamptz not null default now(),
  expires_at timestamptz not null, ended_at timestamptz,
  check(expires_at > started_at)
);
create unique index one_open_venue on public.venue_sessions(user_id) where ended_at is null;
create index on public.venue_sessions(venue_id);
create index on public.venue_sessions(invite_id);
alter table public.venue_sessions enable row level security;
revoke all on public.venue_sessions from anon, authenticated;
grant select on public.venue_sessions to authenticated;
create policy own_sessions on public.venue_sessions for select to authenticated using ((select auth.uid()) = user_id);

-- Privileged implementation is in a non-exposed schema. Public wrappers are invokers.
create function private.require_member() returns uuid language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null or not exists(select 1 from auth.users where id=uid and email_confirmed_at is not null and coalesce(is_anonymous,false)=false) then
    raise exception 'verified_account_required' using errcode='42501';
  end if;
  if exists(select 1 from private.account_restrictions where user_id=uid and suspended) then
    raise exception 'account_restricted' using errcode='42501';
  end if;
  return uid;
end $$;
create function private.profile_complete(p public.profiles) returns boolean language sql immutable set search_path = '' as $$
  select p.display_name is not null and p.birth_date is not null and p.locale is not null
     and p.bio is not null and char_length(btrim(p.bio)) > 0 and p.avatar_path is not null
$$;
create function private.save_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text default null,p_avatar_path text default null)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); result public.profiles; existing public.profiles;
begin
  if p_accept_rules is distinct from true then raise exception 'rules_required'; end if;
  if p_birth_date is null or p_birth_date > (current_date - interval '18 years')::date or p_birth_date < (current_date - interval '120 years')::date then raise exception 'adults_only'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 40 then raise exception 'name_length'; end if;
  if p_locale is null or p_locale not in ('fr','en') then raise exception 'unsupported_language'; end if;
  if p_bio is not null and char_length(btrim(p_bio)) not between 1 and 300 then raise exception 'bio_length'; end if;
  if p_avatar_path is not null and (p_avatar_path !~ ('^u/' || uid::text || '/[A-Za-z0-9._-]+$') or not exists(select 1 from storage.objects where bucket_id='avatars' and name=p_avatar_path)) then raise exception 'photo_missing'; end if;
  select * into existing from public.profiles where user_id=uid;
  -- Date of birth cannot be changed after onboarding to circumvent age policy.
  if found and existing.birth_date <> p_birth_date then raise exception 'birth_date_locked'; end if;
  insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,avatar_updated_at)
  values(uid,btrim(p_name),p_birth_date,p_locale,nullif(btrim(p_bio),''),p_avatar_path,case when p_avatar_path is null then null else now() end)
  on conflict(user_id) do update set display_name=excluded.display_name,locale=excluded.locale,
    bio=coalesce(excluded.bio,public.profiles.bio),
    avatar_path=coalesce(excluded.avatar_path,public.profiles.avatar_path),
    avatar_updated_at=case when excluded.avatar_path is null then public.profiles.avatar_updated_at else now() end,
    updated_at=now()
  returning * into result;
  return result;
end $$;
create function private.preview_venue(p_token text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
  perform private.require_member();
  if p_token is null or length(p_token) not between 32 and 256 then raise exception 'invalid_invitation'; end if;
  select jsonb_build_object('name',v.name,'category',v.category,'duration_minutes',v.duration_minutes,'address',v.address)
  into result from private.venue_invites i join private.venues v on v.id=i.venue_id
  where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.revoked_at is null and i.expires_at>now() and v.active;
  if result is null then raise exception 'invalid_invitation'; end if;
  return result;
end $$;
create function private.join_venue(p_token text) returns public.venue_sessions language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); invitation private.venue_invites; venue private.venues; result public.venue_sessions; me public.profiles;
begin
  -- Serialize concurrent joins/leaves for this account.
  perform 1 from auth.users where id=uid for update;
  select * into me from public.profiles where user_id=uid;
  if not found or not private.profile_complete(me) then raise exception 'profile_required'; end if;
  perform private.preview_venue(p_token);
  select * into invitation from private.venue_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for share;
  select * into venue from private.venues where id=invitation.venue_id for share;
  if invitation.revoked_at is not null or invitation.expires_at<=now() or not venue.active then raise exception 'invalid_invitation'; end if;
  -- Rescanning during a live session returns it unchanged: never an extension. A valid
  -- invitation can be used again after leaving or expiry (a printed QR serves returning visitors).
  select * into result from public.venue_sessions where user_id=uid and invite_id=invitation.id and ended_at is null and expires_at>now();
  if found then return result; end if;
  update public.venue_sessions set ended_at=now() where user_id=uid and ended_at is null;
  insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
  values(uid,venue.id,invitation.id,venue.name,now()+make_interval(mins=>venue.duration_minutes)) returning * into result;
  return result;
end $$;
create function private.leave_venue() returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'verified_account_required' using errcode='42501'; end if;
  perform 1 from auth.users where id=uid for update;
  update public.venue_sessions set ended_at=now() where user_id=uid and ended_at is null;
end $$;
-- Account deletion by the member (profile and sessions cascade from auth.users).
create function private.delete_account() returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'verified_account_required' using errcode='42501'; end if;
  delete from auth.users where id=uid;
end $$;
create function public.save_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text default null,p_avatar_path text default null)
returns public.profiles language sql security invoker set search_path = '' as $$ select private.save_profile(p_name,p_birth_date,p_locale,p_accept_rules,p_bio,p_avatar_path) $$;
create function public.preview_venue(p_token text) returns jsonb language sql security invoker set search_path = '' as $$ select private.preview_venue(p_token) $$;
create function public.join_venue(p_token text) returns public.venue_sessions language sql security invoker set search_path = '' as $$ select private.join_venue(p_token) $$;
create function public.leave_venue() returns void language sql security invoker set search_path = '' as $$ select private.leave_venue() $$;
create function public.delete_account() returns void language sql security invoker set search_path = '' as $$ select private.delete_account() $$;
revoke all on all functions in schema private from public, anon, authenticated;
grant execute on function private.save_profile(text,date,text,boolean,text,text),private.preview_venue(text),private.join_venue(text),private.leave_venue(),private.delete_account() to authenticated;
revoke all on function public.save_profile(text,date,text,boolean,text,text),public.preview_venue(text),public.join_venue(text),public.leave_venue(),public.delete_account() from public, anon;
grant execute on function public.save_profile(text,date,text,boolean,text,text),public.preview_venue(text),public.join_venue(text),public.leave_venue(),public.delete_account() to authenticated;

-- Blocks are authoritative across venues and sessions. Written only through server functions.
create table public.blocks (
  blocker_id uuid not null references auth.users(id) on delete cascade,
  blocked_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);
create index on public.blocks(blocked_id);
alter table public.blocks enable row level security;
revoke all on public.blocks from anon, authenticated;
grant select on public.blocks to authenticated;
create policy own_blocks on public.blocks for select to authenticated using ((select auth.uid()) = blocker_id);
create function private.blocked_between(a uuid, b uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.blocks where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a))
$$;
create function private.live_session(uid uuid) returns public.venue_sessions language sql stable security definer set search_path = '' as $$
  select s from public.venue_sessions s where s.user_id=uid and s.ended_at is null and s.expires_at>now() limit 1
$$;
revoke all on function private.live_session(uuid) from public, anon, authenticated;
-- Members currently present in the caller's venue: display name, age, bio, photo path. Never the birth date or email.
create function private.venue_members() returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return query
    select p.user_id, p.display_name, date_part('year', age(p.birth_date))::integer, p.bio, p.avatar_path, s.started_at
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
    order by s.started_at desc;
end $$;
create function public.venue_members() returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamptz)
language sql security invoker set search_path = '' as $$ select * from private.venue_members() $$;
revoke all on function private.venue_members() from public, anon, authenticated;
grant execute on function private.venue_members() to authenticated;
revoke all on function public.venue_members() from public, anon;
grant execute on function public.venue_members() to authenticated;
revoke all on function private.blocked_between(uuid,uuid) from public, anon, authenticated;
grant execute on function private.blocked_between(uuid,uuid) to authenticated;
-- A member's photo is readable by another member only while both share a live session in the same venue and neither blocks the other.
-- Co-presence is evaluated with definer rights: members only see their own sessions under RLS.
create function private.co_present(viewer uuid, owner uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select viewer is not null and owner is not null and viewer <> owner and exists (
    select 1 from public.venue_sessions a join public.venue_sessions b on a.venue_id=b.venue_id
    where a.user_id=viewer and a.ended_at is null and a.expires_at>now()
      and b.user_id=owner and b.ended_at is null and b.expires_at>now()
  ) and not private.blocked_between(viewer, owner)
$$;
revoke all on function private.co_present(uuid,uuid) from public, anon, authenticated;
grant execute on function private.co_present(uuid,uuid) to authenticated;
create policy avatars_venue_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u'
         and private.co_present((select auth.uid()), ((storage.foldername(name))[2])::uuid));

-- Consent-based conversations. Tables are not readable directly by members: every read and write goes
-- through private.* definer functions, so visibility rules (and later paid entitlements) live in one place.
create table public.introductions (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  venue_id uuid not null references private.venues(id),
  session_id uuid not null references public.venue_sessions(id) on delete cascade,
  message text not null check (char_length(btrim(message)) between 1 and 500),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (sender_id <> recipient_id),
  unique (sender_id, recipient_id, session_id)
);
create index on public.introductions(recipient_id, status);
create index on public.introductions(sender_id, status);
alter table public.introductions enable row level security;
revoke all on public.introductions from anon, authenticated;
create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  introduction_id uuid not null unique references public.introductions(id) on delete cascade,
  venue_id uuid not null references private.venues(id),
  a_id uuid not null references auth.users(id) on delete cascade,
  b_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  closed_by uuid references auth.users(id) on delete set null,
  check (a_id <> b_id)
);
create index on public.conversations(a_id);
create index on public.conversations(b_id);
alter table public.conversations enable row level security;
revoke all on public.conversations from anon, authenticated;
create table public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);
create index on public.messages(conversation_id, created_at);
alter table public.messages enable row level security;
revoke all on public.messages from anon, authenticated;
create table public.conversation_reads (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (conversation_id, user_id)
);
alter table public.conversation_reads enable row level security;
revoke all on public.conversation_reads from anon, authenticated;
-- Reports are never visible to the reported person. Evidence stays with restricted access (moderation).
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references auth.users(id) on delete cascade,
  reported_id uuid not null references auth.users(id) on delete cascade,
  category text not null check (category in ('harassment','inappropriate','impersonation','prohibited','other')),
  details text check (details is null or char_length(details) <= 1000),
  conversation_id uuid references public.conversations(id) on delete set null,
  venue_id uuid references private.venues(id),
  status text not null default 'open' check (status in ('open','reviewed','actioned','dismissed')),
  decision text,
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  check (reporter_id <> reported_id)
);
create index on public.reports(status, created_at);
alter table public.reports enable row level security;
revoke all on public.reports from anon, authenticated;
-- Functions (bodies as applied on 5 November 2026, migration introductions_conversations_safety):
--   private.member_card(uuid)                      public card: name, age, bio, photo path (never birth date or email)
--   private.send_introduction(uuid,text)           one per person per visit, both co-present, no block, max 5 per visit
--   private.respond_introduction(uuid,boolean,text) consent = accept + reply → conversation with the introduction as first message
--   private.my_inbox()                             received (pending), sent (always shown as pending to the sender), conversations with unread counts
--   private.conversation_messages(uuid)            participants only, blocks respected, records the read receipt
--   private.send_message(uuid,text)                open conversation, not blocked, other not suspended
--   private.close_conversation(uuid)               neutral closure visible to the other participant
--   private.block_member(uuid)                     idempotent; closes shared conversations and pending introductions both ways
--   private.report_member(uuid,text,text,uuid)     categories harassment|inappropriate|impersonation|prohibited|other; max 20 per day
-- Each has a public.* security-invoker wrapper granted to authenticated; private.* execute is granted to authenticated as well
-- (they are reachable only through the wrappers because schema private has no usage for anon and exposes nothing through PostgREST).

-- Administration (migration admin_portal_moderation, 5 November 2026). Admin = Auth claim app_metadata.prod_admin = true
-- (never user_metadata); aal2 required when the admin has a verified MFA factor. Every sensitive action is journaled.
create table private.admin_actions (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid not null references auth.users(id) on delete set null,
  action text not null, target text, details jsonb, created_at timestamptz not null default now()
);
alter table private.admin_actions enable row level security;
revoke all on private.admin_actions from public, anon, authenticated;
-- Functions: private.require_admin(), private.log_admin(), private.admin_overview(), admin_venues(), admin_save_venue(uuid,text,text,integer,text,boolean),
-- admin_create_invite(uuid,integer), admin_revoke_invite(uuid), admin_reports(text), admin_decide_report(uuid,text,text,boolean), admin_members(text),
-- admin_restrict(uuid,boolean,text), admin_audit(integer), public.is_admin(); public.* wrappers granted to authenticated. Bodies: see the migration.

-- In-app notifications (migration in_app_notifications). Payloads never carry message contents.
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check (kind in ('introduction_received','reply_received','message_received','conversation_closed','report_handled','account_restricted','account_reinstated')),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  read_at timestamptz
);
create index on public.notifications(user_id, read_at, created_at desc);
alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
-- private.notify(user, kind, payload, dedupe_key), private.my_notifications(mark_read) + public wrapper granted to authenticated.
