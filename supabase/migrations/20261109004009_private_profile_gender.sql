-- Optional self-description, owner-only through profiles RLS. Never a payment entitlement.
begin;
alter table public.profiles add column gender text;
alter table public.profiles add constraint profiles_gender_check check
 (gender is null or gender in ('woman','man','non_binary','another_identity','prefer_not_to_say'));

create function private.save_member_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text,p_avatar_path text,p_gender text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); result public.profiles;
begin
  if p_gender is not null and p_gender not in ('woman','man','non_binary','another_identity','prefer_not_to_say') then
    raise exception 'invalid_gender';
  end if;
  result := private.save_profile(p_name,p_birth_date,p_locale,p_accept_rules,p_bio,p_avatar_path);
  if result.account_type = 'venue' then raise exception 'person_required'; end if;
  update public.profiles set gender=p_gender, updated_at=now() where user_id=uid returning * into result;
  return result;
end $$;
create function public.save_member_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text,p_avatar_path text,p_gender text)
returns public.profiles language sql security invoker set search_path = '' as $$
  select private.save_member_profile(p_name,p_birth_date,p_locale,p_accept_rules,p_bio,p_avatar_path,p_gender)
$$;
revoke all on function private.save_member_profile(text,date,text,boolean,text,text,text) from public,anon;
revoke all on function public.save_member_profile(text,date,text,boolean,text,text,text) from public,anon;
grant execute on function private.save_member_profile(text,date,text,boolean,text,text,text) to authenticated;
grant execute on function public.save_member_profile(text,date,text,boolean,text,text,text) to authenticated;
notify pgrst, 'reload schema';
commit;
