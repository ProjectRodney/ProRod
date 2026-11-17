-- UPZONE, 17 November 2026: « Un talent est présent dans ton lieu » (client request).
-- Run once in the Supabase SQL editor of the ProRod project, after db/2026-11-17-blur-without-id.sql. Safe to run again.
--
-- When a professional with an approved sheet and an active talent subscription is present in a venue, the people present
-- in the same venue who turned the alert on receive one in-app notification (and the generic phone notification).
--
-- Why opt-in: the alert advertises a business. French law requires the prior, free and explicit consent of private
-- individuals before electronic commercial prospecting (CNIL, « La prospection commerciale par courrier électronique,
-- SMS-MMS et automate d'appel »; CPCE art. L34-5). Whether an in-app or push notification falls under that rule is not
-- settled in the texts we checked, so the alert follows the strictest reading:
-- • off by default; switched on only by the member, with an unticked consent box (talent_alerts_at = date of consent);
-- • withdrawable at any time in one tap (settings, or the alert itself): the date is erased;
-- • only for people present in the same venue at that moment, never elsewhere;
-- • at most one alert per professional per visit, and at most 5 talent alerts per person per 24 hours;
-- • never between people who blocked each other, never from or to a suspended account;
-- • the phone shows a generic sentence (no name); the business name appears only inside the app;
-- • no identifier of the professional in the alert (the de-duplication key is a hash); it opens « Talents ici », where the usual rules apply.
-- Event accounts never receive or trigger alerts (they have no visit).

alter table public.profiles add column if not exists talent_alerts_at timestamptz;

-- New notification kind « talent_here ». Every kind already allowed (or already stored) stays allowed.
do $$ declare kinds text[];
begin
  select array_agg(distinct k order by k) into kinds from (
    select unnest(array['introduction_received','reply_received','message_received','conversation_closed','report_handled',
                        'account_restricted','account_reinstated','account_warned','talent_here']) k
    union select distinct kind from public.notifications) x;
  alter table public.notifications drop constraint if exists notifications_kind_check;
  execute format('alter table public.notifications add constraint notifications_kind_check check (kind = any (%L::text[]))', kinds);
end $$;

create or replace function private.set_talent_alerts(p_on boolean, p_consent boolean) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person();
begin
  if p_on is distinct from true then
    update public.profiles set talent_alerts_at=null, updated_at=now() where user_id=uid;
    return jsonb_build_object('talent_alerts',false);
  end if;
  if p_consent is distinct from true then raise exception 'talent_alerts_consent_required'; end if;
  update public.profiles set talent_alerts_at=coalesce(talent_alerts_at,now()), updated_at=now() where user_id=uid;
  return jsonb_build_object('talent_alerts',true);
end $$;
create or replace function public.set_talent_alerts(p_on boolean, p_consent boolean) returns jsonb language sql set search_path = '' as $$ select private.set_talent_alerts(p_on,p_consent) $$;
revoke all on function private.set_talent_alerts(boolean,boolean), public.set_talent_alerts(boolean,boolean) from public, anon;
grant execute on function private.set_talent_alerts(boolean,boolean) to authenticated;
grant execute on function public.set_talent_alerts(boolean,boolean) to authenticated, service_role;

-- Same conditions as the « Talents ici » list (private.venue_talents).
create or replace function private.talent_listed(p_pro uuid) returns boolean
 language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p join public.pro_profiles t on t.user_id=p.user_id
    where p.user_id=p_pro and p.account_type='pro' and t.status='approved' and t.subscription_until is not null and t.subscription_until>now()
      and private.profile_complete(p)
      and not exists(select 1 from private.account_restrictions r where r.user_id=p_pro and r.suspended))
$$;

-- One alert to one person about one professional, if every rule allows it.
create or replace function private.send_talent_alert(p_to uuid, p_to_session uuid, p_pro uuid, p_venue text) returns boolean
 language plpgsql security definer set search_path = '' as $$
declare me public.profiles; t public.pro_profiles; k text := md5('talent:'||p_pro::text||':'||p_to_session::text);
begin
  if p_to is null or p_to=p_pro then return false; end if;
  select * into me from public.profiles where user_id=p_to;
  if not found or me.talent_alerts_at is null or me.account_type='venue' or not private.profile_complete(me) then return false; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=p_to and r.suspended) then return false; end if;
  if private.blocked_between(p_to,p_pro) then return false; end if;
  -- One alert per professional per visit (read or not), five per person per 24 hours.
  if exists(select 1 from public.notifications n where n.user_id=p_to and n.kind='talent_here' and n.payload->>'key'=k) then return false; end if;
  if (select count(*) from public.notifications n where n.user_id=p_to and n.kind='talent_here' and n.created_at>now()-interval '24 hours')>=5 then return false; end if;
  select * into t from public.pro_profiles where user_id=p_pro;
  perform private.notify(p_to,'talent_here',jsonb_build_object('business',t.business_name,'category',t.category,'venue',p_venue),k);
  return true;
end $$;

-- Tell the people present that this professional is here (on arrival, or when the subscription starts during a visit).
create or replace function private.announce_talent(p_pro uuid, p_session public.venue_sessions) returns integer
 language plpgsql security definer set search_path = '' as $$
declare s record; n integer := 0;
begin
  if p_session.id is null or not private.talent_listed(p_pro) then return 0; end if;
  for s in select v.id, v.user_id from public.venue_sessions v
    where v.venue_id=p_session.venue_id and v.ended_at is null and v.expires_at>now() and v.user_id<>p_pro loop
    if private.send_talent_alert(s.user_id, s.id, p_pro, p_session.venue_name) then n := n+1; end if;
  end loop;
  return n;
end $$;

-- Someone starts a visit: if they are a listed professional, the people present are told; if they turned the alert on,
-- they are told about the professionals already present. An alert problem never blocks the visit.
create or replace function private.talent_alerts_on_visit() returns trigger
 language plpgsql security definer set search_path = '' as $$
declare t record;
begin
  begin
    perform private.announce_talent(new.user_id, new);
    for t in select v.user_id from public.venue_sessions v
      where v.venue_id=new.venue_id and v.ended_at is null and v.expires_at>now() and v.user_id<>new.user_id loop
      if private.talent_listed(t.user_id) then perform private.send_talent_alert(new.user_id, new.id, t.user_id, new.venue_name); end if;
    end loop;
  exception when others then
    raise warning 'talent alert skipped: %', sqlerrm;
  end;
  return new;
end $$;
drop trigger if exists talent_alerts_after_visit on public.venue_sessions;
create trigger talent_alerts_after_visit after insert on public.venue_sessions for each row execute function private.talent_alerts_on_visit();

revoke all on function private.talent_listed(uuid), private.send_talent_alert(uuid,uuid,uuid,text), private.announce_talent(uuid,public.venue_sessions), private.talent_alerts_on_visit() from public, anon, authenticated;

-- Activating the subscription during a visit announces the professional to the people present (same rules).
create or replace function private.subscribe_talent_simulated()
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); row public.pro_profiles;
begin
  if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'; end if;
  select * into row from public.pro_profiles where user_id=uid for update;
  if not found or row.status<>'approved' then raise exception 'pro_not_approved'; end if;
  update public.pro_profiles set subscription_until=greatest(coalesce(subscription_until,now()),now())+interval '30 days', updated_at=now() where user_id=uid returning * into row;
  insert into public.passes(user_id,venue_id,kind,simulated,amount_cents,expires_at) values(uid,null,'talent_subscription',true,0,row.subscription_until);
  begin
    perform private.announce_talent(uid, private.live_session(uid));
  exception when others then
    raise warning 'talent alert skipped: %', sqlerrm;
  end;
  return jsonb_build_object('subscription_until',row.subscription_until,'simulated',true);
end $function$;
