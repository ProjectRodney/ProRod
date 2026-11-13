-- UPZONE, 13 November 2026 (client request): before the pass, the venue list shows a blurred version of each photo
-- instead of a neutral silhouette. Run once in the Supabase SQL editor of the ProRod project, after
-- db/2026-11-12-apply-pending-migrations.sql. Safe to run again.
--
-- How it stays private:
-- • The blurred picture is a separate, tiny file (about 20 pixels wide) made on the member's own phone when they
--   upload their photo, stored as u/<their id>/blur-….jpg. Nobody can rebuild the real photo from it.
-- • Without a pass, venue_members returns only the path of that blurred file (plus département and age range):
--   still no id, name, bio, exact age, height, arrival time or real photo path.
-- • Storage: a member present in the same venue may read files named blur-… of the people there; the real photo
--   still needs the pass (private.photo_visible, unchanged).
-- • A member without a blurred file keeps the neutral silhouette.

alter table public.profiles add column if not exists avatar_blur_path text;

create or replace function private.set_avatar_blur(p_path text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person();
begin
  if p_path is not null and (p_path !~ ('^u/' || uid::text || '/blur-[A-Za-z0-9._-]+$')
     or not exists(select 1 from storage.objects where bucket_id='avatars' and name=p_path)) then raise exception 'photo_missing'; end if;
  update public.profiles set avatar_blur_path=p_path, updated_at=now() where user_id=uid;
  return jsonb_build_object('avatar_blur_path',p_path);
end $$;
create or replace function public.set_avatar_blur(p_path text) returns jsonb language sql set search_path = '' as $$ select private.set_avatar_blur(p_path) $$;
revoke all on function private.set_avatar_blur(text), public.set_avatar_blur(text) from public, anon;
grant execute on function private.set_avatar_blur(text) to authenticated;
grant execute on function public.set_avatar_blur(text) to authenticated, service_role;

drop function if exists public.venue_members();
drop function if exists private.venue_members();
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean, blur_path text)
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
           case when not open then p.avatar_blur_path end
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
               department text, age_band text, veiled boolean, blur_path text)
 language sql set search_path to '' as $function$ select * from private.venue_members() $function$;
revoke all on function private.venue_members(), public.venue_members() from public, anon;
grant execute on function private.venue_members() to authenticated;
grant execute on function public.venue_members() to authenticated, service_role;

-- Blurred files only: readable by members present in the same venue (and not blocked), pass or not.
drop policy if exists avatars_blur_select on storage.objects;
create policy avatars_blur_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u' and storage.filename(name) like 'blur-%'
         and private.co_present((select auth.uid()), ((storage.foldername(name))[2])::uuid));

select 'Blurred preview installed' as result;
