-- Professionals are visible for one evening, not for 30 days (26 Nov 2026, decision of the client: one rule for every
-- professional, pay for the evening, no subscription, pay again next time). Still simulated: nothing is charged.
-- A professional turns visibility on while checked in a place. It is tied to that visit: it ends when the visit ends,
-- follows the visit if an administrator changes its length, and is not valid in another place or at the next visit.
begin;

alter table public.pro_profiles add column if not exists subscription_session uuid references public.venue_sessions(id) on delete set null;
-- The old 30-day simulated subscriptions are not tied to a visit: they stop here.
update public.pro_profiles set subscription_until=null where subscription_session is null and subscription_until is not null;

-- Listed = approved sheet + visibility taken for the visit that is live now.
create or replace function private.talent_listed(p_pro uuid) returns boolean
 language sql stable security definer set search_path to '' as $function$
  select exists(select 1 from public.profiles p join public.pro_profiles t on t.user_id=p.user_id
    join public.venue_sessions s on s.id=t.subscription_session and s.user_id=p.user_id and s.ended_at is null and s.expires_at>now()
    where p.user_id=p_pro and p.account_type='pro' and t.status='approved' and t.subscription_until is not null and t.subscription_until>now()
      and private.profile_complete(p)
      and not exists(select 1 from private.account_restrictions r where r.user_id=p_pro and r.suspended))
$function$;

create or replace function private.venue_talents()
 returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'avatar_path',p.avatar_path,'business_name',t.business_name,'professional_name',t.professional_name,'category',t.category,'pitch',t.pitch,'website',t.website,'socials',t.socials,'city',t.city) order by s.started_at desc)
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id join public.pro_profiles t on t.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type='pro' and t.status='approved' and t.subscription_until is not null and t.subscription_until>now()
      and t.subscription_session=s.id
      and private.profile_complete(p) and not private.blocked_between(uid,s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)),'[]'::jsonb);
end $function$;

-- Same name as before, so an app that has not reloaded yet keeps working: it now gives the evening, not 30 days.
create or replace function private.subscribe_talent_simulated()
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); row public.pro_profiles; mine public.venue_sessions;
begin
  if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'; end if;
  select * into row from public.pro_profiles where user_id=uid for update;
  if not found or row.status<>'approved' then raise exception 'pro_not_approved'; end if;
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'pro_visit_required'; end if;
  if row.subscription_session=mine.id and row.subscription_until is not null and row.subscription_until>now() then
    return jsonb_build_object('subscription_until',row.subscription_until,'venue',mine.venue_name,'simulated',true,'already',true);
  end if;
  update public.pro_profiles set subscription_until=mine.expires_at, subscription_session=mine.id, updated_at=now() where user_id=uid returning * into row;
  insert into public.passes(user_id,venue_id,session_id,kind,simulated,amount_cents,expires_at) values(uid,mine.venue_id,mine.id,'talent_subscription',true,0,mine.expires_at);
  begin
    perform private.announce_talent(uid, mine);
  exception when others then
    raise warning 'talent alert skipped: %', sqlerrm;
  end;
  return jsonb_build_object('subscription_until',row.subscription_until,'venue',mine.venue_name,'simulated',true,'already',false);
end $function$;

-- The visibility follows its visit: it stops when the visit ends, and moves with it when its end changes.
create or replace function private.talent_visibility_follows_visit() returns trigger
 language plpgsql security definer set search_path to '' as $function$
begin
  update public.pro_profiles set subscription_until=case when new.ended_at is not null then null else new.expires_at end
    where subscription_session=new.id;
  update public.passes set expires_at=case when new.ended_at is not null then least(expires_at,new.ended_at) else new.expires_at end
    where session_id=new.id and kind='talent_subscription';
  return new;
end $function$;
drop trigger if exists talent_visibility_follows_visit on public.venue_sessions;
create trigger talent_visibility_follows_visit after update of expires_at, ended_at on public.venue_sessions
  for each row when (old.expires_at is distinct from new.expires_at or old.ended_at is distinct from new.ended_at)
  execute function private.talent_visibility_follows_visit();

revoke all on function private.talent_listed(uuid), private.talent_visibility_follows_visit() from public, anon, authenticated;
revoke all on function private.venue_talents(), private.subscribe_talent_simulated() from public, anon;
grant execute on function private.venue_talents(), private.subscribe_talent_simulated() to authenticated;

commit;

select 'Professional visibility per evening installed' as result;
