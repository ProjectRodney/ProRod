-- UPZONE, 11 November 2026 (client decisions of 10–11 November): people in a venue stay veiled until you hold a pass.
-- Run once in the Supabase SQL editor of the ProRod project, after db/2026-11-10-height-safety.sql.
-- • Each member enters their own département (where they live). Shown on the card once unlocked, and on the veiled card.
-- • Without an active pass for the venue (pass_rule = "everyone"), the venue list shows only veiled entries:
--   a neutral silhouette, the département and an age range (18-20, 21-25, 26-30…). No id, name, bio, exact age,
--   height, photo path or arrival time ever leaves the database for them. With the pass, the list is the usual one.
-- • Photos follow the same rule on the storage side: a co-present member reads a photo only when unlocked, or when
--   that person already introduced themselves to them / talks with them.
-- • Introducing yourself needs the pass (you cannot introduce yourself to someone you cannot see).
-- • With pass_rule = "none" nothing is veiled. The pass rule is the same for everyone (never based on gender).

alter table public.profiles add column if not exists department text;
alter table public.profiles drop constraint if exists profiles_department_check;
alter table public.profiles add constraint profiles_department_check
  check (department is null or department ~ '^(0[1-9]|1[0-9]|2[1-9]|[3-8][0-9]|9[0-5]|2A|2B|97[1-6])$');

-- Age range from the private birth date: 18-20, then steps of five (21-25, 26-30…).
create or replace function private.age_band(p_birth date) returns text language sql stable set search_path = '' as $$
  select case when a is null then null when a <= 20 then '18-20' else (21 + 5*((a-21)/5))::text || '-' || (25 + 5*((a-21)/5))::text end
  from (select date_part('year', age(p_birth))::int as a) x
$$;
revoke all on function private.age_band(date) from public, anon, authenticated;

-- True when this member may see the people of this venue: no pass needed, or an active venue pass there.
create or replace function private.venue_unlocked(p_uid uuid, p_venue uuid) returns boolean
 language sql stable security definer set search_path = '' as $$
  select p_uid is not null and p_venue is not null and (
    (private.setting('pass_rule') #>> '{}') is distinct from 'everyone'
    or exists(select 1 from public.passes p where p.user_id=p_uid and p.venue_id=p_venue and p.status='active' and p.kind='venue_pass' and p.expires_at>now()))
$$;
revoke all on function private.venue_unlocked(uuid,uuid) from public, anon, authenticated;

create or replace function private.set_department(p_department text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); d text := nullif(upper(btrim(coalesce(p_department,''))),'');
begin
  if d is not null and d !~ '^(0[1-9]|1[0-9]|2[1-9]|[3-8][0-9]|9[0-5]|2A|2B|97[1-6])$' then raise exception 'invalid_department'; end if;
  update public.profiles set department=d, updated_at=now() where user_id=uid;
  return jsonb_build_object('department',d);
end $$;
create or replace function public.set_department(p_department text) returns jsonb language sql set search_path = '' as $$ select private.set_department(p_department) $$;
revoke all on function private.set_department(text), public.set_department(text) from public, anon;
grant execute on function private.set_department(text) to authenticated;
grant execute on function public.set_department(text) to authenticated, service_role;

drop function if exists public.venue_members();
drop function if exists private.venue_members();
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean)
 language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; wants text; open boolean;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select p.interested_in into wants from public.profiles p where p.user_id=uid;
  open := private.venue_unlocked(uid, mine.venue_id);
  return query
    select case when open then p.user_id end, case when open then p.display_name end,
           case when open then date_part('year', age(p.birth_date))::integer end, case when open then p.bio end,
           case when open then p.avatar_path end, case when open then s.started_at end, case when open then p.height_cm end,
           p.department, private.age_band(p.birth_date), not open
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type<>'venue' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
      and (wants is null or wants='everyone' or (wants='women' and p.gender='woman') or (wants='men' and p.gender='man'))
    order by case when open then s.started_at end desc nulls last, p.department nulls last, 9;
end $function$;
create or replace function public.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean)
 language sql set search_path to '' as $function$ select * from private.venue_members() $function$;
revoke all on function private.venue_members(), public.venue_members() from public, anon;
grant execute on function private.venue_members() to authenticated;
grant execute on function public.venue_members() to authenticated, service_role;

-- Card of a person already in contact with you (introduction, conversation): now with the département.
create or replace function private.member_card(p_user uuid) returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'age',date_part('year',age(p.birth_date))::int,'bio',p.bio,'avatar_path',p.avatar_path,'height_cm',p.height_cm,'department',p.department)
  from public.profiles p where p.user_id=p_user
$function$;

-- Photos: co-present AND (unlocked in that venue, or already in contact through an introduction or a conversation).
create or replace function private.photo_visible(viewer uuid, owner uuid) returns boolean
 language sql stable security definer set search_path to '' as $function$
  select private.co_present(viewer, owner) and (
    private.venue_unlocked(viewer, (private.live_session(viewer)).venue_id)
    or exists(select 1 from public.introductions i where (i.sender_id=owner and i.recipient_id=viewer) or (i.sender_id=viewer and i.recipient_id=owner))
    or exists(select 1 from public.conversations c where (c.a_id=viewer and c.b_id=owner) or (c.a_id=owner and c.b_id=viewer)))
$function$;
revoke all on function private.photo_visible(uuid,uuid) from public, anon, authenticated;
grant execute on function private.photo_visible(uuid,uuid) to authenticated;
drop policy if exists avatars_venue_select on storage.objects;
create policy avatars_venue_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u'
         and private.photo_visible((select auth.uid()), ((storage.foldername(name))[2])::uuid));

-- Introducing yourself needs the pass of the venue (same rule for everyone).
create or replace function private.send_introduction(p_to uuid, p_message text) returns jsonb
 language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_member(); mine public.venue_sessions; theirs public.venue_sessions; row public.introductions;
begin
  if p_to is null or p_to=uid then raise exception 'invalid_recipient'; end if;
  if p_message is null or char_length(btrim(p_message)) not between 1 and 500 then raise exception 'message_length'; end if;
  mine := private.live_session(uid); if mine.id is null then raise exception 'no_live_session'; end if;
  if not private.venue_unlocked(uid, mine.venue_id) then raise exception 'pass_required'; end if;
  theirs := private.live_session(p_to);
  if theirs.id is null or theirs.venue_id<>mine.venue_id then raise exception 'not_co_present'; end if;
  if private.blocked_between(uid,p_to) then raise exception 'not_co_present'; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=p_to and r.suspended) then raise exception 'not_co_present'; end if;
  if exists(select 1 from public.profiles p where p.user_id=p_to and not private.profile_complete(p)) then raise exception 'not_co_present'; end if;
  if exists(select 1 from public.introductions i where i.recipient_id=uid and i.sender_id=p_to and i.session_id=theirs.id and i.status='pending') then raise exception 'introduction_received'; end if;
  if exists(select 1 from public.introductions i where i.sender_id=uid and i.recipient_id=p_to and (i.session_id=mine.id or i.status<>'accepted')) then raise exception 'introduction_exists'; end if;
  if (select count(*) from public.introductions i where i.sender_id=uid and i.session_id=mine.id)>=5 then raise exception 'introduction_limit'; end if;
  insert into public.introductions(sender_id,recipient_id,venue_id,session_id,message) values(uid,p_to,mine.venue_id,mine.id,btrim(p_message)) returning * into row;
  perform private.notify(p_to,'introduction_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'venue',(select name from private.venues where id=mine.venue_id)),row.id::text);
  return jsonb_build_object('id',row.id,'status',row.status,'created_at',row.created_at);
end $function$;
