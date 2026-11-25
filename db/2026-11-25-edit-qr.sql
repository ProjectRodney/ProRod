-- Change an existing QR code instead of making a new one (25 Nov 2026, asked by DZOFT).
-- The administrator can change the visit length of a QR code that is still valid, apply it to the people who already
-- came in with it, and push back its last day. The link and the picture already shared keep working: nothing about the
-- QR code's secret changes. Lengths stay between 15 minutes and 12 hours, as for a new QR code.
begin;

create or replace function private.admin_update_invite(p_id uuid, p_minutes integer default null, p_apply boolean default true, p_days integer default null)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_admin(); inv private.venue_invites; n integer := 0;
begin
  select * into inv from private.venue_invites where id=p_id and revoked_at is null and expires_at>now() for update;
  if not found then raise exception 'invite_missing'; end if;
  if p_minutes is null and p_days is null then raise exception 'nothing_to_change'; end if;
  if p_minutes is not null and p_minutes not between 15 and 720 then raise exception 'invalid_duration'; end if;
  if p_days is not null and p_days not between 1 and 365 then raise exception 'invalid_duration'; end if;
  if p_minutes is not null then
    update private.venue_invites set duration_minutes=p_minutes where id=p_id;
    if coalesce(p_apply,true) then
      -- A visit lasts the new length counted from its own start; one that began longer ago than that ends now.
      -- The pass taken for a visit ends with that visit: it follows the visit's new end, or the member would lose the
      -- unveiled view at the old time while still inside.
      with moved as (
        update public.venue_sessions set expires_at=started_at+make_interval(mins=>p_minutes)
          where invite_id=p_id and ended_at is null and expires_at>now() returning id, expires_at
      ), passes_moved as (
        update public.passes p set expires_at=m.expires_at from moved m
          where p.session_id=m.id and p.kind='venue_pass' and p.status='active' returning 1
      )
      select count(*) into n from moved;
    end if;
  end if;
  -- Pushing back the last day adds days to it; it never brings it closer.
  if p_days is not null then update private.venue_invites set expires_at=least(expires_at+make_interval(days=>p_days),now()+interval '365 days') where id=p_id; end if;
  select * into inv from private.venue_invites where id=p_id;
  perform private.log_admin(uid,'invite_updated',p_id::text,jsonb_build_object('duration_minutes',inv.duration_minutes,'expires_at',inv.expires_at,'visits_changed',n));
  return jsonb_build_object('id',inv.id,'duration_minutes',inv.duration_minutes,'expires_at',inv.expires_at,'visits_changed',n);
end $function$;

create or replace function public.admin_update_invite(p_id uuid, p_minutes integer default null, p_apply boolean default true, p_days integer default null)
 returns jsonb language sql set search_path to '' as $function$ select private.admin_update_invite(p_id,p_minutes,p_apply,p_days) $function$;

-- The portal's list also says how many people are in the venue with each QR code, so the administrator knows whom a
-- change reaches.
create or replace function private.admin_venues()
 returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'category',v.category,'duration_minutes',v.duration_minutes,'address',v.address,'active',v.active,
      'live',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.ended_at is null and s.expires_at>now()),
      'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'expires_at',i.expires_at,'duration_minutes',i.duration_minutes,'revoked_at',i.revoked_at,
        'uses',(select count(*) from public.venue_sessions s where s.invite_id=i.id),
        'live',(select count(*) from public.venue_sessions s where s.invite_id=i.id and s.ended_at is null and s.expires_at>now())) order by i.expires_at desc) from private.venue_invites i where i.venue_id=v.id),'[]'::jsonb)) order by v.name) from private.venues v),'[]'::jsonb);
end $function$;

revoke all on function private.admin_update_invite(uuid,integer,boolean,integer) from public, anon;
revoke all on function public.admin_update_invite(uuid,integer,boolean,integer) from public, anon;
grant execute on function private.admin_update_invite(uuid,integer,boolean,integer) to authenticated;
grant execute on function public.admin_update_invite(uuid,integer,boolean,integer) to authenticated, service_role;

commit;

select 'QR code editing installed' as result;
