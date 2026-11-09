-- Synthetic accounts only, no emails; all changes rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009001','gender-test@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009002','gender-other@example.invalid',now(),false);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009001","role":"authenticated"}',true);
do $$ declare g text; p public.profiles; begin
  foreach g in array array['woman','man','non_binary','another_identity','prefer_not_to_say'] loop
    p:= public.save_member_profile('Test member','1990-01-01','fr',true,'Hello',null,g);
    if p.gender is distinct from g then raise exception 'TEST: save failed'; end if;
    if (select gender from public.profiles where user_id=auth.uid()) is distinct from g then raise exception 'TEST: reload failed'; end if;
  end loop;
  if public.my_data_export()->'profile'->>'gender' <> 'prefer_not_to_say' then raise exception 'TEST: export missing'; end if;
  begin
    perform public.save_member_profile('Changed name','1990-01-01','fr',true,'Hello',null,'invalid');
    raise exception 'TEST: invalid accepted';
  exception when others then if sqlerrm <> 'invalid_gender' then raise; end if; end;
  if (select display_name from public.profiles where user_id=auth.uid()) <> 'Test member' then raise exception 'TEST: partial save'; end if;
  p:=public.save_member_profile('Test member','1990-01-01','en',true,'Hello',null,null);
  if p.gender is not null then raise exception 'TEST: cannot clear'; end if;
  begin update public.profiles set gender='man'; raise exception 'TEST: direct update allowed'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009002","role":"authenticated"}',true);
do $$ begin
  if exists(select 1 from public.profiles where user_id='00000000-0000-4000-8000-000000009001') then raise exception 'TEST: private profile exposed'; end if;
  perform public.set_account_type('venue');
  begin perform public.save_member_profile('Venue',null,'fr',true,null,null,'man'); raise exception 'TEST: venue accepted';
  exception when others then if sqlerrm <> 'person_required' then raise; end if; end;
  if exists(select 1 from public.profiles where user_id=auth.uid()) then raise exception 'TEST: venue partial save'; end if;
end $$;
reset role;
do $$ begin
 if has_function_privilege('anon','public.save_member_profile(text,date,text,boolean,text,text,text)','execute') then raise exception 'TEST: anonymous access'; end if;
end $$;
select 'PASS: choices, reload, clear, export, atomic validation, owner privacy, venue exclusion, anonymous denial' as result;
rollback;
