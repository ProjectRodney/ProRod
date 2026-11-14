-- Two-step verification for the administration portal becomes a server setting.
-- It stays ON unless the operator turns it off. Turning it off is the operator's decision:
-- the portal gives access to members' data, and the CNIL recommends multi-factor
-- authentication for sensitive data (recommendation of March 2025, section 3.1).
--   Off: update private.app_settings set value='false', updated_at=now() where key='admin_two_step';
--   On : update private.app_settings set value='true',  updated_at=now() where key='admin_two_step';
begin;

insert into private.app_settings(key,value) values ('admin_two_step','true') on conflict (key) do nothing;

create or replace function private.require_admin()
 returns uuid
 language plpgsql
 stable security definer
 set search_path to ''
as $function$
declare uid uuid := auth.uid(); claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
begin
  if uid is null or coalesce(claims->'app_metadata'->>'prod_admin','') <> 'true' then raise exception 'admin_required' using errcode='42501'; end if;
  if coalesce(private.setting('admin_two_step'),'true'::jsonb) <> 'false'::jsonb and coalesce(claims->>'aal','') <> 'aal2' then raise exception 'mfa_required' using errcode='42501'; end if;
  return uid;
end $function$;

create or replace function public.admin_two_step_required()
 returns boolean
 language sql
 stable security definer
 set search_path to ''
as $function$ select coalesce(private.setting('admin_two_step'),'true'::jsonb) <> 'false'::jsonb $function$;
revoke all on function public.admin_two_step_required() from public, anon;
grant execute on function public.admin_two_step_required() to authenticated;

commit;

select 'Two-step switch installed' as result, value as admin_two_step from private.app_settings where key='admin_two_step';
