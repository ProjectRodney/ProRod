-- UPZONE, 17 November 2026 (review): the blurred preview no longer reveals who is behind it.
-- Run once in the Supabase SQL editor of the ProRod project, after db/2026-11-14-*.sql. Safe to run again.
--
-- Before: without a pass, venue_members returned blur_path = 'u/<member id>/blur-….jpg'. The file name carried
-- the member's id, which the veiled list must never reveal (rule of 11 Nov 2026: no id before the pass).
-- Now:
-- • the 20-pixel blurred picture is stored as a small data URL in the member's own profile row (avatar_blur),
--   made on the member's phone as before; it is checked here (JPEG only, at most 6 000 characters);
-- • without a pass, venue_members returns that picture inline (blur_data) and blur_path is always empty:
--   no file name, no id;
-- • the storage rule that let co-present members read blur-… files is removed, and old blur paths are cleared.
--   Old blur files stay readable by their owner only; members' phones create the new preview by themselves
--   at their next visit (the app re-makes it from their own photo).

alter table public.profiles add column if not exists avatar_blur text;
alter table public.profiles drop constraint if exists profiles_avatar_blur_check;
alter table public.profiles add constraint profiles_avatar_blur_check
  check (avatar_blur is null or (char_length(avatar_blur) <= 6000 and avatar_blur ~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$'));

create or replace function private.set_avatar_blur_data(p_data text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person();
begin
  if p_data is not null and (char_length(p_data) > 6000 or p_data !~ '^data:image/jpeg;base64,[A-Za-z0-9+/]+={0,2}$') then
    raise exception 'photo_invalid';
  end if;
  update public.profiles set avatar_blur=p_data, avatar_blur_path=null, updated_at=now() where user_id=uid;
  return jsonb_build_object('avatar_blur', p_data is not null);
end $$;
create or replace function public.set_avatar_blur_data(p_data text) returns jsonb language sql set search_path = '' as $$ select private.set_avatar_blur_data(p_data) $$;
revoke all on function private.set_avatar_blur_data(text), public.set_avatar_blur_data(text) from public, anon;
grant execute on function private.set_avatar_blur_data(text) to authenticated;
grant execute on function public.set_avatar_blur_data(text) to authenticated, service_role;

-- The old file-based call stays callable by phones that still run the previous version, but stores nothing.
create or replace function private.set_avatar_blur(p_path text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person();
begin
  update public.profiles set avatar_blur_path=null where user_id=uid and avatar_blur_path is not null;
  return jsonb_build_object('avatar_blur_path', null);
end $$;

update public.profiles set avatar_blur_path=null where avatar_blur_path is not null;
drop policy if exists avatars_blur_select on storage.objects;

drop function if exists public.venue_members();
drop function if exists private.venue_members();
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean, blur_path text, blur_data text)
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
           p.department, private.age_band(p.birth_date), not open,
           null::text,
           case when not open then p.avatar_blur end
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
               department text, age_band text, veiled boolean, blur_path text, blur_data text)
 language sql set search_path to '' as $function$ select * from private.venue_members() $function$;
revoke all on function private.venue_members(), public.venue_members() from public, anon;
grant execute on function private.venue_members() to authenticated;
grant execute on function public.venue_members() to authenticated, service_role;

select 'Blurred preview without id installed' as result;
