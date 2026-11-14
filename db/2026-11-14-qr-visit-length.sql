-- The administrator chooses how long a visit lasts when generating a QR code (client request, 14 November 2026).
-- A QR code may carry its own visit length (15 minutes to 12 hours). People who scan it get that length;
-- a QR code without one keeps the venue's length, capped by the server setting max_session_minutes as before.
-- Only the administrator can set it. Nothing changes for QR codes that already exist.
begin;

alter table private.venue_invites add column if not exists duration_minutes integer
  check (duration_minutes is null or duration_minutes between 15 and 720);

drop function if exists public.admin_create_invite(uuid, integer);
drop function if exists private.admin_create_invite(uuid, integer);

CREATE OR REPLACE FUNCTION private.admin_create_invite(p_venue uuid, p_days integer DEFAULT 30, p_minutes integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); token text; row private.venue_invites;
begin
  if not exists(select 1 from private.venues where id=p_venue) then raise exception 'venue_missing'; end if;
  if p_days is null or p_days not between 1 and 365 then raise exception 'invalid_duration'; end if;
  if p_minutes is not null and p_minutes not between 15 and 720 then raise exception 'invalid_duration'; end if;
  token := translate(encode(extensions.gen_random_bytes(32),'base64'),'+/=','-_');
  insert into private.venue_invites(venue_id,token_hash,expires_at,duration_minutes) values(p_venue,encode(extensions.digest(token,'sha256'),'hex'),now()+make_interval(days=>p_days),p_minutes) returning * into row;
  perform private.log_admin(uid,'invite_created',row.id::text,jsonb_build_object('venue',p_venue,'expires_at',row.expires_at,'duration_minutes',row.duration_minutes));
  return jsonb_build_object('id',row.id,'token',token,'expires_at',row.expires_at,'duration_minutes',row.duration_minutes);
end $function$;

CREATE OR REPLACE FUNCTION public.admin_create_invite(p_venue uuid, p_days integer DEFAULT 30, p_minutes integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_create_invite(p_venue,p_days,p_minutes) $function$;

revoke all on function private.admin_create_invite(uuid, integer, integer) from public, anon;
revoke all on function public.admin_create_invite(uuid, integer, integer) from public, anon;
grant execute on function private.admin_create_invite(uuid, integer, integer) to authenticated;
grant execute on function public.admin_create_invite(uuid, integer, integer) to authenticated, service_role;

CREATE OR REPLACE FUNCTION private.join_venue(p_token text)
 RETURNS venue_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  values(uid,venue.id,invitation.id,venue.name,now()+make_interval(mins=>coalesce(invitation.duration_minutes,least(venue.duration_minutes,coalesce((private.setting('max_session_minutes'))::int,180))))) returning * into result;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION private.preview_venue(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
  perform private.require_member();
  if p_token is null or length(p_token) not between 32 and 256 then raise exception 'invalid_invitation'; end if;
  select jsonb_build_object('name',v.name,'category',v.category,'duration_minutes',coalesce(i.duration_minutes,least(v.duration_minutes,coalesce((private.setting('max_session_minutes'))::int,180))),'address',v.address)
  into result from private.venue_invites i join private.venues v on v.id=i.venue_id
  where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.revoked_at is null and i.expires_at>now() and v.active;
  if result is null then raise exception 'invalid_invitation'; end if;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION private.admin_venues()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'category',v.category,'duration_minutes',v.duration_minutes,'address',v.address,'active',v.active,
      'live',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.ended_at is null and s.expires_at>now()),
      'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'expires_at',i.expires_at,'duration_minutes',i.duration_minutes,'revoked_at',i.revoked_at,'uses',(select count(*) from public.venue_sessions s where s.invite_id=i.id)) order by i.expires_at desc) from private.venue_invites i where i.venue_id=v.id),'[]'::jsonb)) order by v.name) from private.venues v),'[]'::jsonb);
end $function$;

commit;

select 'QR visit length installed' as result;
