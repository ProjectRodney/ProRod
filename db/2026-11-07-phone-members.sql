-- ANZIAK migration of 7 November 2026: members who signed up with their phone number are verified members too.
-- Before: private.require_member() accepted only a confirmed e-mail, so an account created with « Continue with my phone
-- number » (confirmed phone, no e-mail) was refused everywhere (profile, venues, messages). Run once in the SQL editor.
CREATE OR REPLACE FUNCTION private.require_member()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null or not exists(select 1 from auth.users where id=uid and (email_confirmed_at is not null or phone_confirmed_at is not null) and coalesce(is_anonymous,false)=false) then
    raise exception 'verified_account_required' using errcode='42501';
  end if;
  if exists(select 1 from private.account_restrictions where user_id=uid and suspended) then
    raise exception 'account_restricted' using errcode='42501';
  end if;
  return uid;
end $function$;
