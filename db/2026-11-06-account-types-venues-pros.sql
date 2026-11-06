-- 6 November 2026 — account types (personal / pro / venue), venue accounts with dashboard, pro sheets and
-- in-venue talents, enquiries, simulated passes, feedback, app settings (simulation, 3 h cap). Apply in order
-- with the Supabase SQL editor (postgres role). Tables first, then functions, then grants.

-- ===== 1. Tables and settings =====
alter table public.profiles add column if not exists account_type text not null default 'personal' check (account_type in ('personal','pro','venue'));
alter table public.profiles alter column birth_date drop not null;
create table if not exists private.app_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());
alter table private.app_settings enable row level security;
revoke all on private.app_settings from public, anon, authenticated;
insert into private.app_settings(key,value) values ('simulation','true'), ('max_session_minutes','180'), ('pass_rule','"everyone"'), ('feedback_email','null') on conflict (key) do nothing;
create or replace function private.setting(p_key text) returns jsonb language sql stable security definer set search_path = '' as $$ select value from private.app_settings where key=p_key $$;
revoke all on function private.setting(text) from public, anon, authenticated;
create table if not exists public.venue_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  venue_name text not null check (char_length(btrim(venue_name)) between 2 and 100),
  category text not null check (category in ('restaurant','pub','chicha','nightclub','barber','test')),
  address text not null check (char_length(btrim(address)) between 5 and 200),
  hours text check (hours is null or char_length(hours) <= 300),
  contact text check (contact is null or char_length(contact) <= 120),
  duration_minutes integer not null default 60 check (duration_minutes between 15 and 180),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  venue_id uuid references private.venues(id) on delete set null,
  decision text, decided_at timestamptz, decided_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists venue_applications_user_idx on public.venue_applications(user_id, created_at desc);
alter table public.venue_applications enable row level security;
revoke all on public.venue_applications from anon, authenticated;
create table if not exists private.venue_managers (
  user_id uuid not null references auth.users(id) on delete cascade,
  venue_id uuid not null references private.venues(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, venue_id)
);
alter table private.venue_managers enable row level security;
revoke all on private.venue_managers from public, anon, authenticated;
alter table private.venues add column if not exists hours text;
alter table private.venues add column if not exists contact text;
alter table private.venues drop constraint if exists venues_duration_minutes_check;
alter table private.venues add constraint venues_duration_minutes_check check (duration_minutes between 15 and 180);
create table if not exists public.venue_announcements (
  id uuid primary key default gen_random_uuid(),
  venue_id uuid not null references private.venues(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 300),
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (now() + interval '12 hours')
);
create index if not exists venue_announcements_venue_idx on public.venue_announcements(venue_id, created_at desc);
alter table public.venue_announcements enable row level security;
revoke all on public.venue_announcements from anon, authenticated;
create table if not exists public.pro_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  business_name text not null check (char_length(btrim(business_name)) between 2 and 100),
  professional_name text check (professional_name is null or char_length(professional_name) <= 80),
  category text not null check (char_length(btrim(category)) between 2 and 60),
  pitch text not null check (char_length(btrim(pitch)) between 10 and 600),
  website text check (website is null or website ~ '^https?://'),
  socials jsonb not null default '{}'::jsonb,
  city text check (city is null or char_length(city) <= 80),
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  decision text, decided_at timestamptz,
  subscription_until timestamptz,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default now()
);
alter table public.pro_profiles enable row level security;
revoke all on public.pro_profiles from anon, authenticated;
create table if not exists public.enquiries (
  id uuid primary key default gen_random_uuid(),
  from_id uuid not null references auth.users(id) on delete cascade,
  pro_id uuid not null references auth.users(id) on delete cascade,
  venue_id uuid references private.venues(id),
  message text not null check (char_length(btrim(message)) between 1 and 1000),
  contact text check (contact is null or char_length(contact) <= 120),
  created_at timestamptz not null default clock_timestamp(),
  check (from_id <> pro_id)
);
create index if not exists enquiries_pro_idx on public.enquiries(pro_id, created_at desc);
alter table public.enquiries enable row level security;
revoke all on public.enquiries from anon, authenticated;
create table if not exists public.passes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  venue_id uuid references private.venues(id),
  session_id uuid references public.venue_sessions(id) on delete set null,
  kind text not null default 'venue_pass' check (kind in ('venue_pass','talent_subscription')),
  status text not null default 'active' check (status in ('active','refunded','expired')),
  simulated boolean not null default true,
  amount_cents integer not null default 0,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null
);
create index if not exists passes_user_idx on public.passes(user_id, status, expires_at);
alter table public.passes enable row level security;
revoke all on public.passes from anon, authenticated;
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  account_type text, score integer check (score between 1 and 4), change_text text check (change_text is null or char_length(change_text) <= 1000),
  bug boolean not null default false, bug_text text check (bug_text is null or char_length(bug_text) <= 1000),
  context jsonb not null default '{}'::jsonb, emailed_at timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
alter table public.feedback enable row level security;
revoke all on public.feedback from anon, authenticated;

-- ===== 2. Functions =====
create or replace function private.profile_complete(p public.profiles) returns boolean language sql immutable set search_path = '' as $$
  select case when p.account_type='venue' then p.display_name is not null and p.locale is not null
         else p.display_name is not null and p.birth_date is not null and p.locale is not null
              and p.bio is not null and char_length(btrim(p.bio)) > 0 and p.avatar_path is not null end
$$;
create table if not exists private.account_choices (user_id uuid primary key references auth.users(id) on delete cascade, account_type text not null check (account_type in ('personal','pro','venue')), created_at timestamptz not null default now());
alter table private.account_choices enable row level security;
revoke all on private.account_choices from public, anon, authenticated;
create or replace function private.set_account_type(p_type text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); existing text;
begin
  if p_type not in ('personal','pro','venue') then raise exception 'invalid_type'; end if;
  select account_type into existing from public.profiles where user_id=uid;
  if found then
    if (existing='venue') <> (p_type='venue') then raise exception 'type_locked'; end if;
    update public.profiles set account_type=p_type, updated_at=now() where user_id=uid;
  end if;
  insert into private.account_choices(user_id,account_type) values(uid,p_type) on conflict(user_id) do update set account_type=excluded.account_type;
  return jsonb_build_object('account_type',p_type);
end $$;
create or replace function private.my_account_type() returns text language sql stable security definer set search_path = '' as $$
  select coalesce((select account_type from public.profiles where user_id=auth.uid()),(select account_type from private.account_choices where user_id=auth.uid()))
$$;
create or replace function private.save_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text default null,p_avatar_path text default null)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); result public.profiles; existing public.profiles; t text;
begin
  select * into existing from public.profiles where user_id=uid;
  t := coalesce(existing.account_type,(select account_type from private.account_choices where user_id=uid),'personal');
  if p_accept_rules is distinct from true then raise exception 'rules_required'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 40 then raise exception 'name_length'; end if;
  if p_locale is null or p_locale not in ('fr','en') then raise exception 'unsupported_language'; end if;
  if t<>'venue' then
    if p_birth_date is null or p_birth_date > (current_date - interval '18 years')::date or p_birth_date < (current_date - interval '120 years')::date then raise exception 'adults_only'; end if;
    if existing.user_id is not null and existing.birth_date is not null and existing.birth_date <> p_birth_date then raise exception 'birth_date_locked'; end if;
  end if;
  if p_bio is not null and char_length(btrim(p_bio)) not between 1 and 300 then raise exception 'bio_length'; end if;
  if p_avatar_path is not null and (p_avatar_path !~ ('^u/' || uid::text || '/[A-Za-z0-9._-]+$') or not exists(select 1 from storage.objects where bucket_id='avatars' and name=p_avatar_path)) then raise exception 'photo_missing'; end if;
  insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,avatar_updated_at,account_type)
  values(uid,btrim(p_name),case when t='venue' then null else p_birth_date end,p_locale,nullif(btrim(p_bio),''),p_avatar_path,case when p_avatar_path is null then null else now() end,t)
  on conflict(user_id) do update set display_name=excluded.display_name,locale=excluded.locale,
    birth_date=coalesce(public.profiles.birth_date,excluded.birth_date),
    bio=coalesce(excluded.bio,public.profiles.bio),
    avatar_path=coalesce(excluded.avatar_path,public.profiles.avatar_path),
    avatar_updated_at=case when excluded.avatar_path is null then public.profiles.avatar_updated_at else now() end,
    updated_at=now()
  returning * into result;
  return result;
end $$;
create or replace function private.require_person() returns uuid language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  if exists(select 1 from public.profiles p where p.user_id=uid and p.account_type='venue') then raise exception 'venue_account' using errcode='42501'; end if;
  return uid;
end $$;
revoke all on function private.require_person() from public, anon, authenticated;
create or replace function private.join_venue(p_token text) returns public.venue_sessions language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); invitation private.venue_invites; venue private.venues; result public.venue_sessions; me public.profiles;
begin
  perform 1 from auth.users where id=uid for update;
  select * into me from public.profiles where user_id=uid;
  if not found or not private.profile_complete(me) then raise exception 'profile_required'; end if;
  perform private.preview_venue(p_token);
  select * into invitation from private.venue_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for share;
  select * into venue from private.venues where id=invitation.venue_id for share;
  if invitation.revoked_at is not null or invitation.expires_at<=now() or not venue.active then raise exception 'invalid_invitation'; end if;
  select * into result from public.venue_sessions where user_id=uid and invite_id=invitation.id and ended_at is null and expires_at>now();
  if found then return result; end if;
  update public.venue_sessions set ended_at=now() where user_id=uid and ended_at is null;
  insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
  values(uid,venue.id,invitation.id,venue.name,now()+make_interval(mins=>least(venue.duration_minutes,coalesce((private.setting('max_session_minutes'))::int,180)))) returning * into result;
  return result;
end $$;
create or replace function private.venue_members() returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_person(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return query
    select p.user_id, p.display_name, date_part('year', age(p.birth_date))::integer, p.bio, p.avatar_path, s.started_at
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type<>'venue' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
    order by s.started_at desc;
end $$;
create or replace function private.apply_venue(p_name text, p_category text, p_address text, p_hours text, p_contact text, p_duration integer) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); row public.venue_applications;
begin
  if not exists(select 1 from public.profiles p where p.user_id=uid and p.account_type='venue') then raise exception 'venue_account_required'; end if;
  if not exists(select 1 from public.profiles p where p.user_id=uid and private.profile_complete(p)) then raise exception 'profile_required'; end if;
  if exists(select 1 from public.venue_applications a where a.user_id=uid and a.status='pending') then raise exception 'application_pending'; end if;
  insert into public.venue_applications(user_id,venue_name,category,address,hours,contact,duration_minutes)
  values(uid,btrim(p_name),p_category,btrim(p_address),nullif(btrim(p_hours),''),nullif(btrim(p_contact),''),least(coalesce(p_duration,60),180)) returning * into row;
  return jsonb_build_object('id',row.id,'status',row.status);
end $$;
create or replace function private.my_venue() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member(); v private.venues; app public.venue_applications;
begin
  select v2.* into v from private.venues v2 join private.venue_managers m on m.venue_id=v2.id where m.user_id=uid limit 1;
  if not found then
    select * into app from public.venue_applications where user_id=uid order by created_at desc limit 1;
    return jsonb_build_object('venue',null,'application',case when app.id is null then null else jsonb_build_object('id',app.id,'status',app.status,'venue_name',app.venue_name,'decision',app.decision,'created_at',app.created_at) end);
  end if;
  return jsonb_build_object('venue',jsonb_build_object('id',v.id,'name',v.name,'category',v.category,'address',v.address,'hours',v.hours,'contact',v.contact,'duration_minutes',v.duration_minutes,'active',v.active,
      'present',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.ended_at is null and s.expires_at>now()),
      'today',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.started_at>now()-interval '24 hours'),
      'open_reports',(select count(*) from public.reports r where r.venue_id=v.id and r.status='open'),
      'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'expires_at',i.expires_at,'revoked_at',i.revoked_at,'uses',(select count(*) from public.venue_sessions s where s.invite_id=i.id)) order by i.expires_at desc) from private.venue_invites i where i.venue_id=v.id and i.revoked_at is null and i.expires_at>now()),'[]'::jsonb),
      'announcements',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'body',a.body,'created_at',a.created_at,'expires_at',a.expires_at) order by a.created_at desc) from public.venue_announcements a where a.venue_id=v.id and a.expires_at>now()),'[]'::jsonb)),
    'application',null);
end $$;
create or replace function private.venue_create_invite(p_days integer default 7) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); vid uuid; token text; row private.venue_invites;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  if vid is null then raise exception 'venue_required'; end if;
  if p_days is null or p_days not between 1 and 90 then raise exception 'invalid_duration'; end if;
  token := translate(encode(extensions.gen_random_bytes(32),'base64'),'+/=','-_');
  insert into private.venue_invites(venue_id,token_hash,expires_at) values(vid,encode(extensions.digest(token,'sha256'),'hex'),now()+make_interval(days=>p_days)) returning * into row;
  return jsonb_build_object('id',row.id,'token',token,'expires_at',row.expires_at);
end $$;
create or replace function private.venue_revoke_invite(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); vid uuid;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  update private.venue_invites set revoked_at=now() where id=p_id and venue_id=vid and revoked_at is null;
  update public.venue_sessions set ended_at=now() where invite_id=p_id and venue_id=vid and ended_at is null;
end $$;
create or replace function private.venue_update(p_hours text, p_contact text, p_duration integer) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); vid uuid;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  if vid is null then raise exception 'venue_required'; end if;
  if p_duration is null or p_duration not between 15 and 180 then raise exception 'invalid_duration'; end if;
  update private.venues set hours=nullif(btrim(p_hours),''), contact=nullif(btrim(p_contact),''), duration_minutes=p_duration where id=vid;
end $$;
create or replace function private.venue_announce(p_body text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); vid uuid; row public.venue_announcements;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  if vid is null then raise exception 'venue_required'; end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 300 then raise exception 'message_length'; end if;
  insert into public.venue_announcements(venue_id,author_id,body) values(vid,uid,btrim(p_body)) returning * into row;
  return jsonb_build_object('id',row.id);
end $$;
create or replace function private.venue_delete_announcement(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); vid uuid;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  update public.venue_announcements set expires_at=now() where id=p_id and venue_id=vid;
end $$;
create or replace function private.venue_room() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_person(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return jsonb_build_object(
    'present',(select count(*) from public.venue_sessions s join public.profiles p on p.user_id=s.user_id where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and p.account_type<>'venue'),
    'announcements',coalesce((select jsonb_agg(jsonb_build_object('body',a.body,'created_at',a.created_at) order by a.created_at desc) from (select * from public.venue_announcements where venue_id=mine.venue_id and expires_at>now() order by created_at desc limit 3) a),'[]'::jsonb));
end $$;
create or replace function private.save_pro_profile(p_business text, p_professional text, p_category text, p_pitch text, p_website text, p_socials jsonb, p_city text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); row public.pro_profiles; clean jsonb := '{}'::jsonb; k text; v text;
begin
  if not exists(select 1 from public.profiles p where p.user_id=uid and p.account_type='pro') then raise exception 'pro_account_required'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p_socials,'{}'::jsonb)) loop
    if k in ('instagram','tiktok','linkedin','facebook','youtube','x') and v is not null and char_length(v) between 1 and 120 then clean := clean || jsonb_build_object(k, btrim(v)); end if;
  end loop;
  insert into public.pro_profiles(user_id,business_name,professional_name,category,pitch,website,socials,city)
  values(uid,btrim(p_business),nullif(btrim(p_professional),''),btrim(p_category),btrim(p_pitch),nullif(btrim(p_website),''),clean,nullif(btrim(p_city),''))
  on conflict(user_id) do update set business_name=excluded.business_name,professional_name=excluded.professional_name,category=excluded.category,pitch=excluded.pitch,website=excluded.website,socials=excluded.socials,city=excluded.city,
    status=case when public.pro_profiles.status='approved' then 'approved' else 'pending' end, updated_at=now()
  returning * into row;
  return jsonb_build_object('status',row.status,'subscription_until',row.subscription_until);
end $$;
create or replace function private.my_pro_profile() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member(); row public.pro_profiles;
begin
  select * into row from public.pro_profiles where user_id=uid;
  if not found then return null; end if;
  return jsonb_build_object('business_name',row.business_name,'professional_name',row.professional_name,'category',row.category,'pitch',row.pitch,'website',row.website,'socials',row.socials,'city',row.city,'status',row.status,'decision',row.decision,'subscription_until',row.subscription_until,'subscription_active',row.subscription_until is not null and row.subscription_until>now(),
    'enquiries',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'message',e.message,'contact',e.contact,'created_at',e.created_at,'from',(select display_name from public.profiles where user_id=e.from_id),'venue',(select name from private.venues where id=e.venue_id)) order by e.created_at desc) from (select * from public.enquiries where pro_id=uid order by created_at desc limit 50) e),'[]'::jsonb));
end $$;
create or replace function private.venue_talents() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_person(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'avatar_path',p.avatar_path,'business_name',t.business_name,'professional_name',t.professional_name,'category',t.category,'pitch',t.pitch,'website',t.website,'socials',t.socials,'city',t.city) order by s.started_at desc)
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id join public.pro_profiles t on t.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type='pro' and t.status='approved' and t.subscription_until is not null and t.subscription_until>now()
      and private.profile_complete(p) and not private.blocked_between(uid,s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)),'[]'::jsonb);
end $$;
create or replace function private.send_enquiry(p_pro uuid, p_message text, p_contact text default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); mine public.venue_sessions; theirs public.venue_sessions; row public.enquiries;
begin
  if p_message is null or char_length(btrim(p_message)) not between 1 and 1000 then raise exception 'message_length'; end if;
  mine := private.live_session(uid); theirs := private.live_session(p_pro);
  if mine.id is null or theirs.id is null or theirs.venue_id<>mine.venue_id then raise exception 'not_co_present'; end if;
  if not exists(select 1 from public.pro_profiles t where t.user_id=p_pro and t.status='approved') then raise exception 'not_co_present'; end if;
  if private.blocked_between(uid,p_pro) then raise exception 'not_co_present'; end if;
  if (select count(*) from public.enquiries e where e.from_id=uid and e.created_at>now()-interval '1 day')>=10 then raise exception 'introduction_limit'; end if;
  insert into public.enquiries(from_id,pro_id,venue_id,message,contact) values(uid,p_pro,mine.venue_id,btrim(p_message),nullif(btrim(p_contact),'')) returning * into row;
  perform private.notify(p_pro,'introduction_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'venue',(select name from private.venues where id=mine.venue_id),'enquiry',true),row.id::text);
  return jsonb_build_object('id',row.id);
end $$;
create or replace function private.admin_venue_applications(p_status text default 'pending') returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'venue_name',a.venue_name,'category',a.category,'address',a.address,'hours',a.hours,'contact',a.contact,'duration_minutes',a.duration_minutes,'status',a.status,'decision',a.decision,'created_at',a.created_at,'applicant',(select display_name from public.profiles where user_id=a.user_id)) order by a.created_at desc) from public.venue_applications a where p_status is null or a.status=p_status),'[]'::jsonb);
end $$;
create or replace function private.admin_decide_venue(p_id uuid, p_approve boolean, p_decision text default null) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); app public.venue_applications; v private.venues;
begin
  select * into app from public.venue_applications where id=p_id and status='pending' for update;
  if not found then raise exception 'application_missing'; end if;
  if p_approve then
    insert into private.venues(name,category,duration_minutes,address,hours,contact,active) values(app.venue_name,app.category,app.duration_minutes,app.address,app.hours,app.contact,true) returning * into v;
    insert into private.venue_managers(user_id,venue_id) values(app.user_id,v.id) on conflict do nothing;
    update public.venue_applications set status='approved',venue_id=v.id,decision=p_decision,decided_at=now(),decided_by=uid where id=app.id;
    perform private.notify(app.user_id,'account_reinstated',jsonb_build_object('venue',v.name,'approved',true),null);
  else
    update public.venue_applications set status='rejected',decision=p_decision,decided_at=now(),decided_by=uid where id=app.id;
    perform private.notify(app.user_id,'account_restricted',jsonb_build_object('venue',app.venue_name,'rejected',true,'reason',coalesce(p_decision,'')),null);
  end if;
  perform private.log_admin(uid,case when p_approve then 'venue_approved' else 'venue_rejected' end,app.id::text,jsonb_build_object('venue_name',app.venue_name));
  return jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'venue_id',v.id);
end $$;
create or replace function private.admin_pro_profiles(p_status text default 'pending') returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',t.user_id,'member',private.member_card(t.user_id),'business_name',t.business_name,'professional_name',t.professional_name,'category',t.category,'pitch',t.pitch,'website',t.website,'socials',t.socials,'city',t.city,'status',t.status,'decision',t.decision,'subscription_until',t.subscription_until,'created_at',t.created_at) order by t.created_at desc) from public.pro_profiles t where p_status is null or t.status=p_status),'[]'::jsonb);
end $$;
create or replace function private.admin_decide_pro(p_user uuid, p_approve boolean, p_decision text default null) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin();
begin
  update public.pro_profiles set status=case when p_approve then 'approved' else 'rejected' end, decision=p_decision, decided_at=now(), updated_at=now() where user_id=p_user;
  if not found then raise exception 'profile_missing'; end if;
  perform private.notify(p_user,case when p_approve then 'account_reinstated' else 'account_restricted' end,jsonb_build_object('pro',true,'approved',p_approve,'reason',coalesce(p_decision,'')),null);
  perform private.log_admin(uid,case when p_approve then 'pro_approved' else 'pro_rejected' end,p_user::text,null);
end $$;

-- ===== 3. Public wrappers and grants =====
create or replace function public.set_account_type(p_type text) returns jsonb language sql security invoker set search_path = '' as $$ select private.set_account_type(p_type) $$;
create or replace function public.my_account_type() returns text language sql security invoker set search_path = '' as $$ select private.my_account_type() $$;
create or replace function public.apply_venue(p_name text, p_category text, p_address text, p_hours text, p_contact text, p_duration integer) returns jsonb language sql security invoker set search_path = '' as $$ select private.apply_venue(p_name,p_category,p_address,p_hours,p_contact,p_duration) $$;
create or replace function public.my_venue() returns jsonb language sql security invoker set search_path = '' as $$ select private.my_venue() $$;
create or replace function public.venue_create_invite(p_days integer default 7) returns jsonb language sql security invoker set search_path = '' as $$ select private.venue_create_invite(p_days) $$;
create or replace function public.venue_revoke_invite(p_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.venue_revoke_invite(p_id) $$;
create or replace function public.venue_update(p_hours text, p_contact text, p_duration integer) returns void language sql security invoker set search_path = '' as $$ select private.venue_update(p_hours,p_contact,p_duration) $$;
create or replace function public.venue_announce(p_body text) returns jsonb language sql security invoker set search_path = '' as $$ select private.venue_announce(p_body) $$;
create or replace function public.venue_delete_announcement(p_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.venue_delete_announcement(p_id) $$;
create or replace function public.venue_room() returns jsonb language sql security invoker set search_path = '' as $$ select private.venue_room() $$;
create or replace function public.save_pro_profile(p_business text, p_professional text, p_category text, p_pitch text, p_website text, p_socials jsonb, p_city text) returns jsonb language sql security invoker set search_path = '' as $$ select private.save_pro_profile(p_business,p_professional,p_category,p_pitch,p_website,p_socials,p_city) $$;
create or replace function public.my_pro_profile() returns jsonb language sql security invoker set search_path = '' as $$ select private.my_pro_profile() $$;
create or replace function public.venue_talents() returns jsonb language sql security invoker set search_path = '' as $$ select private.venue_talents() $$;
create or replace function public.send_enquiry(p_pro uuid, p_message text, p_contact text default null) returns jsonb language sql security invoker set search_path = '' as $$ select private.send_enquiry(p_pro,p_message,p_contact) $$;
create or replace function public.admin_venue_applications(p_status text default 'pending') returns jsonb language sql security invoker set search_path = '' as $$ select private.admin_venue_applications(p_status) $$;
create or replace function public.admin_decide_venue(p_id uuid, p_approve boolean, p_decision text default null) returns jsonb language sql security invoker set search_path = '' as $$ select private.admin_decide_venue(p_id,p_approve,p_decision) $$;
create or replace function public.admin_pro_profiles(p_status text default 'pending') returns jsonb language sql security invoker set search_path = '' as $$ select private.admin_pro_profiles(p_status) $$;
create or replace function public.admin_decide_pro(p_user uuid, p_approve boolean, p_decision text default null) returns void language sql security invoker set search_path = '' as $$ select private.admin_decide_pro(p_user,p_approve,p_decision) $$;
do $$ declare f text; begin
  for f in select unnest(array['set_account_type(text)','my_account_type()','apply_venue(text,text,text,text,text,integer)','my_venue()','venue_create_invite(integer)','venue_revoke_invite(uuid)','venue_update(text,text,integer)','venue_announce(text)','venue_delete_announcement(uuid)','venue_room()','save_pro_profile(text,text,text,text,text,jsonb,text)','my_pro_profile()','venue_talents()','send_enquiry(uuid,text,text)','admin_venue_applications(text)','admin_decide_venue(uuid,boolean,text)','admin_pro_profiles(text)','admin_decide_pro(uuid,boolean,text)']) loop
    execute format('revoke all on function private.%s from public, anon, authenticated', f);
    execute format('grant execute on function private.%s to authenticated', f);
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ===== 4. Simulation: venue passes and talent subscriptions (no money moves; everyone follows the same neutral rule) =====
-- pass_rule setting: "everyone" (a pass is needed to read accepted replies in that venue session) or "none" (free chat).
-- Nothing here depends on gender. Real pricing stays out until the client validates the model legally.
create or replace function private.needs_pass(p_conv public.conversations, p_uid uuid) returns boolean language sql stable security definer set search_path = '' as $$
  select (private.setting('pass_rule') #>> '{}')='everyone'
     and not exists(select 1 from public.passes p where p.user_id=p_uid and p.venue_id=p_conv.venue_id and p.status='active' and p.kind='venue_pass' and p_conv.created_at<=p.expires_at)
$$;
revoke all on function private.needs_pass(public.conversations,uuid) from public, anon, authenticated;
create or replace function private.buy_pass_simulated() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); mine public.venue_sessions; row public.passes;
begin
  if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'; end if;
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select * into row from public.passes where user_id=uid and venue_id=mine.venue_id and status='active' and kind='venue_pass' and expires_at>now();
  if found then return jsonb_build_object('id',row.id,'expires_at',row.expires_at,'simulated',row.simulated,'already',true); end if;
  insert into public.passes(user_id,venue_id,session_id,kind,simulated,amount_cents,expires_at) values(uid,mine.venue_id,mine.id,'venue_pass',true,0,mine.expires_at) returning * into row;
  return jsonb_build_object('id',row.id,'expires_at',row.expires_at,'simulated',row.simulated,'already',false);
end $$;
create or replace function private.my_passes() returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'kind',p.kind,'status',p.status,'simulated',p.simulated,'amount_cents',p.amount_cents,'created_at',p.created_at,'expires_at',p.expires_at,'venue',(select name from private.venues v where v.id=p.venue_id),'active',p.status='active' and p.expires_at>now()) order by p.created_at desc)
    from public.passes p where p.user_id=private.require_member()),'[]'::jsonb)
$$;
create or replace function private.subscribe_talent_simulated() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); row public.pro_profiles;
begin
  if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'; end if;
  select * into row from public.pro_profiles where user_id=uid for update;
  if not found or row.status<>'approved' then raise exception 'pro_not_approved'; end if;
  update public.pro_profiles set subscription_until=greatest(coalesce(subscription_until,now()),now())+interval '30 days', updated_at=now() where user_id=uid returning * into row;
  insert into public.passes(user_id,venue_id,kind,simulated,amount_cents,expires_at) values(uid,null,'talent_subscription',true,0,row.subscription_until);
  return jsonb_build_object('subscription_until',row.subscription_until,'simulated',true);
end $$;
create or replace function private.admin_passes() returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'member',private.member_card(p.user_id),'kind',p.kind,'status',p.status,'simulated',p.simulated,'amount_cents',p.amount_cents,'created_at',p.created_at,'expires_at',p.expires_at,'venue',(select name from private.venues v where v.id=p.venue_id)) order by p.created_at desc)
    from (select * from public.passes order by created_at desc limit 200) p where private.require_admin() is not null),'[]'::jsonb)
$$;
create or replace function private.admin_refund_pass(p_id uuid) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin();
begin
  update public.passes set status='refunded' where id=p_id and status='active';
  if not found then raise exception 'pass_missing'; end if;
  perform private.log_admin(uid,'pass_refunded',p_id::text,null);
end $$;
create or replace function private.app_settings_public() returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('simulation',private.setting('simulation'),'max_session_minutes',private.setting('max_session_minutes'),'pass_rule',private.setting('pass_rule'))
$$;
-- Reads now respect the pass rule: the other person's messages stay hidden ("locked") until a pass covers the conversation. Nothing else changes.
create or replace function private.conversation_messages(p_id uuid) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); conv public.conversations; other uuid; msgs jsonb; mine_count int; theirs_count int; locked boolean;
begin
  select * into conv from public.conversations where id=p_id and (a_id=uid or b_id=uid);
  if not found then raise exception 'conversation_unavailable'; end if;
  other := case when conv.a_id=uid then conv.b_id else conv.a_id end;
  if private.blocked_between(uid,other) then raise exception 'conversation_unavailable'; end if;
  locked := private.needs_pass(conv,uid);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'body',case when locked and m.sender_id<>uid then null else m.body end,'locked',locked and m.sender_id<>uid,'mine',m.sender_id=uid,'created_at',m.created_at) order by m.created_at),'[]'::jsonb) into msgs from public.messages m where m.conversation_id=conv.id;
  select count(*) filter (where sender_id=uid), count(*) filter (where sender_id=other) into mine_count, theirs_count from public.messages where conversation_id=conv.id;
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid) on conflict(conversation_id,user_id) do update set read_at=now();
  update public.notifications set read_at=now() where user_id=uid and read_at is null and kind in ('reply_received','message_received','conversation_closed') and (payload->>'key'=conv.id::text or payload->>'key'=conv.id::text||':meeting');
  return jsonb_build_object('id',conv.id,'closed_at',conv.closed_at,'closed_by_me',conv.closed_by=uid,'with',private.member_card(other),'venue',(select name from private.venues v where v.id=conv.venue_id),'venue_id',conv.venue_id,'locked',locked,'messages',msgs,
    'meeting',private.meeting_state(conv,uid)||jsonb_build_object('can_ask',conv.closed_at is null and mine_count>=2 and theirs_count>=2));
end $$;
create or replace function private.send_message(p_conversation uuid, p_body text) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); conv public.conversations; other uuid; row public.messages;
begin
  if p_body is null or char_length(btrim(p_body)) not between 1 and 2000 then raise exception 'message_length'; end if;
  select * into conv from public.conversations where id=p_conversation and (a_id=uid or b_id=uid) for update;
  if not found then raise exception 'conversation_unavailable'; end if;
  if conv.closed_at is not null then raise exception 'conversation_closed'; end if;
  other := case when conv.a_id=uid then conv.b_id else conv.a_id end;
  if private.blocked_between(uid,other) then raise exception 'conversation_unavailable'; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=other and r.suspended) then raise exception 'conversation_unavailable'; end if;
  if private.needs_pass(conv,uid) then raise exception 'pass_required'; end if;
  insert into public.messages(conversation_id,sender_id,body) values(conv.id,uid,btrim(p_body)) returning * into row;
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid) on conflict(conversation_id,user_id) do update set read_at=now();
  perform private.notify(other,'message_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'conversation',conv.id),conv.id::text);
  return jsonb_build_object('id',row.id,'created_at',row.created_at);
end $$;

-- ===== 5. Feedback after one hour of use (collected in the admin portal, e-mailed to the operator when a Brevo key is in the Vault) =====
create or replace function private.submit_feedback(p_score integer, p_change text, p_bug boolean, p_bug_text text, p_context jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); row public.feedback;
begin
  if p_score is null or p_score not between 1 and 4 then raise exception 'invalid_score'; end if;
  if (select count(*) from public.feedback f where f.user_id=uid and f.created_at>now()-interval '1 day')>=5 then raise exception 'report_limit'; end if;
  insert into public.feedback(user_id,account_type,score,change_text,bug,bug_text,context)
  values(uid,(select account_type from public.profiles where user_id=uid),p_score,nullif(btrim(p_change),''),coalesce(p_bug,false),nullif(btrim(p_bug_text),''),
         jsonb_build_object('lang',p_context->>'lang','minutes',p_context->>'minutes','screen',p_context->>'screen','installed',p_context->>'installed','ua',left(p_context->>'ua',200)))
  returning * into row;
  return jsonb_build_object('id',row.id);
end $$;
create or replace function private.admin_feedback() returns jsonb language sql stable security definer set search_path = '' as $$
  select coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'member',case when f.user_id is null then null else private.member_card(f.user_id) end,'account_type',f.account_type,'score',f.score,'change_text',f.change_text,'bug',f.bug,'bug_text',f.bug_text,'context',f.context,'emailed_at',f.emailed_at,'created_at',f.created_at) order by f.created_at desc)
    from (select * from public.feedback order by created_at desc limit 300) f where private.require_admin() is not null),'[]'::jsonb)
$$;
create or replace function public.buy_pass_simulated() returns jsonb language sql security invoker set search_path = '' as $$ select private.buy_pass_simulated() $$;
create or replace function public.my_passes() returns jsonb language sql security invoker set search_path = '' as $$ select private.my_passes() $$;
create or replace function public.subscribe_talent_simulated() returns jsonb language sql security invoker set search_path = '' as $$ select private.subscribe_talent_simulated() $$;
create or replace function public.admin_passes() returns jsonb language sql security invoker set search_path = '' as $$ select private.admin_passes() $$;
create or replace function public.admin_refund_pass(p_id uuid) returns void language sql security invoker set search_path = '' as $$ select private.admin_refund_pass(p_id) $$;
create or replace function public.app_settings_public() returns jsonb language sql security invoker set search_path = '' as $$ select private.app_settings_public() $$;
create or replace function public.submit_feedback(p_score integer, p_change text, p_bug boolean, p_bug_text text, p_context jsonb default '{}'::jsonb) returns jsonb language sql security invoker set search_path = '' as $$ select private.submit_feedback(p_score,p_change,p_bug,p_bug_text,p_context) $$;
create or replace function public.admin_feedback() returns jsonb language sql security invoker set search_path = '' as $$ select private.admin_feedback() $$;
do $$ declare f text; begin
  for f in select unnest(array['buy_pass_simulated()','my_passes()','subscribe_talent_simulated()','admin_passes()','admin_refund_pass(uuid)','app_settings_public()','submit_feedback(integer,text,boolean,text,jsonb)','admin_feedback()']) loop
    execute format('revoke all on function private.%s from public, anon, authenticated', f);
    execute format('grant execute on function private.%s to authenticated', f);
    execute format('revoke all on function public.%s from public, anon', f);
    execute format('grant execute on function public.%s to authenticated', f);
  end loop;
end $$;

-- ===== 6. Feedback e-mails from the database (pg_net + pg_cron + Vault) =====
-- The Brevo API key lives in the Vault under the name brevo_api_key (Project Settings → Vault); the destination and the
-- validated sender live in private.app_settings (feedback_email, feedback_sender). Nothing is sent while any of the three is missing.
create extension if not exists pg_net with schema extensions;
create extension if not exists pg_cron;
insert into private.app_settings(key,value) values ('feedback_sender','null'), ('feedback_subject','"[P.Rod test] Nouveau retour"') on conflict (key) do nothing;
create or replace function private.send_feedback_emails() returns integer language plpgsql security definer set search_path = '' as $$
declare api_key text; to_addr text; from_addr text; subj text; f record; n integer := 0; body text; faces text[] := array['😕','😐','🙂','🤩'];
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name='brevo_api_key' limit 1;
  to_addr := private.setting('feedback_email') #>> '{}'; from_addr := private.setting('feedback_sender') #>> '{}'; subj := coalesce(private.setting('feedback_subject') #>> '{}','[P.Rod test] Nouveau retour');
  if api_key is null or to_addr is null or from_addr is null then return 0; end if;
  for f in select fb.*, (select display_name from public.profiles p where p.user_id=fb.user_id) as who from public.feedback fb where fb.emailed_at is null order by fb.created_at limit 20 loop
    body := 'Nouveau retour P.Rod (test)' || E'\n\n' ||
      'Note : ' || coalesce(faces[f.score],'') || ' ' || f.score || '/4' || E'\n' ||
      'Compte : ' || coalesce(f.who,'(supprimé)') || ' · type ' || coalesce(f.account_type,'?') || E'\n' ||
      'Utilisation : ' || coalesce(f.context->>'minutes','?') || ' min · ' || coalesce(f.context->>'lang','') || ' · ' || case when f.context->>'installed'='true' then 'app installée' else 'navigateur' end || ' · écran ' || coalesce(f.context->>'screen','') || E'\n' ||
      'Envoyé le : ' || to_char(f.created_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI') || E'\n\n' ||
      'À changer en premier :' || E'\n' || coalesce(f.change_text,'(vide)') || E'\n\n' ||
      case when f.bug then 'BUG signalé :' || E'\n' || coalesce(f.bug_text,'(sans détail)') || E'\n\n' else '' end ||
      'Détail complet dans le portail d’administration, onglet Retours.';
    perform net.http_post(url:='https://api.brevo.com/v3/smtp/email',
      headers:=jsonb_build_object('api-key',api_key,'content-type','application/json','accept','application/json'),
      body:=jsonb_build_object('sender',jsonb_build_object('email',from_addr,'name','P.Rod test'),'to',jsonb_build_array(jsonb_build_object('email',to_addr)),'subject',subj || ' ' || coalesce(faces[f.score],'') || case when f.bug then ' · bug' else '' end,'textContent',body));
    update public.feedback set emailed_at=now() where id=f.id; n := n+1;
  end loop;
  return n;
end $$;
revoke all on function private.send_feedback_emails() from public, anon, authenticated;
select cron.schedule('prod-feedback-emails','*/5 * * * *',$$select private.send_feedback_emails()$$);
-- Operator values (never in Git): update private.app_settings set value=to_jsonb('<address>'::text) where key in ('feedback_email','feedback_sender');
-- Vault key: Supabase dashboard → Project Settings → Vault → Add new secret → name brevo_api_key, value = the Brevo API key (v3).
