-- ANZIAK, 10 November 2026: optional « who would you like to see? » (women / men / everyone) to filter the venue list.
-- Run once in the Supabase SQL editor of the ProRod project.
--
-- Data protection: together with gender, this choice reveals sexual orientation, a special category of personal data
-- (GDPR article 9). So: optional; saved only with the member's explicit consent (interest_consent_at); private (owner-only
-- profiles RLS, never in venue_members, member_card or any other member's view); used only to filter the member's own
-- venue list, on the server, without sending anyone's gender to the phone; withdrawable at any time (set to null, consent
-- erased); included in the member's own data export (my_data_export returns the whole profile row). Never used for pricing.

alter table public.profiles add column if not exists interested_in text;
alter table public.profiles add column if not exists interest_consent_at timestamptz;
alter table public.profiles drop constraint if exists profiles_interested_in_check;
alter table public.profiles add constraint profiles_interested_in_check check (interested_in is null or interested_in in ('women','men','everyone'));
alter table public.profiles drop constraint if exists profiles_interest_consent_check;
alter table public.profiles add constraint profiles_interest_consent_check check (interested_in is null or interest_consent_at is not null);

create or replace function private.set_interest(p_interest text, p_consent boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); me public.profiles;
begin
  select * into me from public.profiles where user_id=uid for update;
  if not found then raise exception 'profile_required'; end if;
  if me.account_type='venue' then raise exception 'person_required'; end if;
  if p_interest is null or p_interest='' then
    update public.profiles set interested_in=null, interest_consent_at=null, updated_at=now() where user_id=uid;
    return jsonb_build_object('interested_in',null);
  end if;
  if p_interest not in ('women','men','everyone') then raise exception 'invalid_interest'; end if;
  if p_consent is distinct from true then raise exception 'interest_consent_required'; end if;
  update public.profiles set interested_in=p_interest, interest_consent_at=coalesce(case when interested_in is not null then interest_consent_at end, now()), updated_at=now() where user_id=uid;
  return jsonb_build_object('interested_in',p_interest);
end $$;
create or replace function public.set_interest(p_interest text, p_consent boolean) returns jsonb language sql set search_path = '' as $$ select private.set_interest(p_interest,p_consent) $$;
revoke all on function private.set_interest(text,boolean) from public, anon;
revoke all on function public.set_interest(text,boolean) from public, anon;
grant execute on function private.set_interest(text,boolean) to authenticated;
grant execute on function public.set_interest(text,boolean) to authenticated, service_role;

-- The venue list follows the viewer's own choice; nobody else's choice or gender leaves the server.
-- « women » / « men »: only members who declared that gender. « everyone » or no choice: everybody, as before.
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone)
 language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; wants text;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select p.interested_in into wants from public.profiles p where p.user_id=uid;
  return query
    select p.user_id, p.display_name, date_part('year', age(p.birth_date))::integer, p.bio, p.avatar_path, s.started_at
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type<>'venue' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
      and (wants is null or wants='everyone' or (wants='women' and p.gender='woman') or (wants='men' and p.gender='man'))
    order by s.started_at desc;
end $function$;
