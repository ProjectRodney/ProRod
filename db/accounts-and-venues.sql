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
