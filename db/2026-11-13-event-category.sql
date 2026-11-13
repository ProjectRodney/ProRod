-- UPZONE, 13 November 2026 (client request): the « établissement » account is presented as « événement » in the app,
-- and a place can be of type « event » (party, show, fair…). Run once in the Supabase SQL editor of the ProRod
-- project. Safe to run again. Only the list of allowed types changes; nothing else.

alter table private.venues drop constraint if exists venues_category_check;
alter table private.venues add constraint venues_category_check
  check (category in ('restaurant','pub','chicha','nightclub','barber','event','test'));

alter table public.venue_applications drop constraint if exists venue_applications_category_check;
alter table public.venue_applications add constraint venue_applications_category_check
  check (category in ('restaurant','pub','chicha','nightclub','barber','event','test'));

CREATE OR REPLACE FUNCTION private.admin_save_venue(p_id uuid, p_name text, p_category text, p_duration integer, p_address text, p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); row private.venues;
begin
  if p_name is null or char_length(btrim(p_name)) not between 2 and 100 then raise exception 'name_length'; end if;
  if p_category not in ('restaurant','pub','chicha','nightclub','barber','event','test') then raise exception 'invalid_category'; end if;
  if p_duration is null or p_duration not between 15 and 720 then raise exception 'invalid_duration'; end if;
  if p_id is null then
    insert into private.venues(name,category,duration_minutes,address,active) values(btrim(p_name),p_category,p_duration,nullif(btrim(p_address),''),coalesce(p_active,true)) returning * into row;
  else
    update private.venues set name=btrim(p_name),category=p_category,duration_minutes=p_duration,address=nullif(btrim(p_address),''),active=coalesce(p_active,true) where id=p_id returning * into row;
    if not found then raise exception 'venue_missing'; end if;
    if not row.active then update public.venue_sessions set ended_at=now() where venue_id=row.id and ended_at is null; end if;
  end if;
  perform private.log_admin(uid,'venue_saved',row.id::text,jsonb_build_object('name',row.name,'active',row.active,'duration',row.duration_minutes));
  return jsonb_build_object('id',row.id);
end $function$;

select 'Event type installed' as result;
