-- Checks for db/2026-11-11-veiled-venue.sql and db/2026-11-13-blurred-preview.sql. Synthetic accounts and a synthetic venue only; everything is rolled back.
-- Run in the Supabase SQL editor of the ProRod project. Expected last row: PASS: veiled venue …
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009101','veil-viewer@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009102','veil-other@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009103','veil-third@example.invalid',now(),false);
insert into private.venues(id,name,category,duration_minutes,active,address) values ('00000000-0000-4000-8000-000000009110','Veil test venue','test',180,true,'Fictional');
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values ('00000000-0000-4000-8000-000000009111','00000000-0000-4000-8000-000000009110',encode(extensions.digest('veil-test-token-0123456789abcdefghijk','sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000009101/a.jpg','00000000-0000-4000-8000-000000009101'),
('avatars','u/00000000-0000-4000-8000-000000009102/a.jpg','00000000-0000-4000-8000-000000009102'),
('avatars','u/00000000-0000-4000-8000-000000009103/a.jpg','00000000-0000-4000-8000-000000009103');
insert into private.app_settings(key,value) values ('pass_rule','"everyone"') on conflict (key) do update set value='"everyone"';

-- Three members with a département, all present in the venue.
do $$ declare u uuid; i int := 0; begin
  foreach u in array array['00000000-0000-4000-8000-000000009101','00000000-0000-4000-8000-000000009102','00000000-0000-4000-8000-000000009103']::uuid[] loop
    i := i+1;
    perform set_config('request.jwt.claims',jsonb_build_object('sub',u,'role','authenticated')::text,true);
    perform public.save_member_profile('Veil '||i,(current_date-interval '27 years')::date,'fr',true,'Bio '||i,'u/'||u||'/a.jpg',null);
    perform public.set_department(case i when 1 then ' 2a ' when 2 then '93' else '971' end);
    if i=2 then  -- member 2 has a blurred file (db/2026-11-13-blurred-preview.sql)
      insert into storage.objects(bucket_id,name,owner) values ('avatars','u/'||u||'/blur-a.jpg',u);
      perform public.set_avatar_blur('u/'||u||'/blur-a.jpg');
      begin perform public.set_avatar_blur('u/'||u||'/a.jpg'); raise exception 'TEST: real photo accepted as blurred file'; exception when others then if sqlerrm <> 'photo_missing' then raise; end if; end;
      begin perform public.set_avatar_blur('u/00000000-0000-4000-8000-000000009103/blur-a.jpg'); raise exception 'TEST: someone else''s blurred file accepted'; exception when others then if sqlerrm <> 'photo_missing' then raise; end if; end;
    end if;
    perform public.join_venue('veil-test-token-0123456789abcdefghijk');
  end loop;
end $$;

select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009101","role":"authenticated"}',true);
do $$ declare n int; leaked int; begin
  if (select department from public.profiles where user_id=auth.uid()) <> '2A' then raise exception 'TEST: département not normalised'; end if;
  begin perform public.set_department('20'); raise exception 'TEST: 20 accepted'; exception when others then if sqlerrm <> 'invalid_department' then raise; end if; end;
  begin perform public.set_department('99'); raise exception 'TEST: 99 accepted'; exception when others then if sqlerrm <> 'invalid_department' then raise; end if; end;
  -- Without a pass: only veiled rows, nothing identifying.
  select count(*), count(user_id)+count(display_name)+count(age)+count(bio)+count(avatar_path)+count(height_cm)+count(since) into n, leaked from public.venue_members();
  if n <> 2 or leaked <> 0 then raise exception 'TEST: veiled list leaks (% rows, % fields)', n, leaked; end if;
  if exists(select 1 from public.venue_members() where not veiled or age_band <> '26-30' or department is null) then raise exception 'TEST: veiled card content'; end if;
  if (select count(*) from public.venue_members() where blur_path = 'u/00000000-0000-4000-8000-000000009102/blur-a.jpg') <> 1
     or (select count(*) from public.venue_members() where blur_path is not null) <> 1 then raise exception 'TEST: blurred file path missing or leaked'; end if;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000009102','Hello'); raise exception 'TEST: introduction without pass';
  exception when others then if sqlerrm <> 'pass_required' then raise; end if; end;
  if private.photo_visible(auth.uid(),'00000000-0000-4000-8000-000000009102') then raise exception 'TEST: photo readable without pass'; end if;
end $$;
set local role authenticated;
do $$ begin
  if (select count(*) from storage.objects where bucket_id='avatars' and name not like '%/blur-%') <> 1 then raise exception 'TEST: storage shows other real photos without pass'; end if;
  if (select count(*) from storage.objects where bucket_id='avatars' and name like '%/blur-%') <> 1 then raise exception 'TEST: blurred file of a co-present member not readable'; end if;
end $$;
reset role;

-- With the (simulated) pass: the usual list, photos and introductions.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009101","role":"authenticated"}',true);
do $$ begin
  perform public.buy_pass_simulated();
  if exists(select 1 from public.venue_members() where veiled or user_id is null or display_name is null) then raise exception 'TEST: still veiled with pass'; end if;
  if exists(select 1 from public.venue_members() where blur_path is not null) then raise exception 'TEST: blurred path sent once unlocked'; end if;
  if (select department from public.venue_members() where user_id='00000000-0000-4000-8000-000000009102') <> '93' then raise exception 'TEST: département missing once unlocked'; end if;
  perform public.send_introduction('00000000-0000-4000-8000-000000009102','Hello');
end $$;
set local role authenticated;
do $$ begin if (select count(*) from storage.objects where bucket_id='avatars' and name not like '%/blur-%') <> 3 then raise exception 'TEST: storage hides photos with pass'; end if; end $$;
reset role;

-- The person who received the introduction (no pass) sees that sender's photo, not the others'.
do $$ begin
  if not private.photo_visible('00000000-0000-4000-8000-000000009102','00000000-0000-4000-8000-000000009101') then raise exception 'TEST: sender photo hidden from recipient'; end if;
  if private.photo_visible('00000000-0000-4000-8000-000000009102','00000000-0000-4000-8000-000000009103') then raise exception 'TEST: unrelated photo visible without pass'; end if;
  if private.age_band((current_date-interval '20 years')::date) <> '18-20' or private.age_band((current_date-interval '21 years')::date) <> '21-25'
     or private.age_band((current_date-interval '25 years')::date) <> '21-25' or private.age_band((current_date-interval '26 years')::date) <> '26-30' then raise exception 'TEST: age ranges'; end if;
end $$;

-- pass_rule "none": nothing veiled.
update private.app_settings set value='"none"' where key='pass_rule';
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009103","role":"authenticated"}',true);
do $$ begin if exists(select 1 from public.venue_members() where veiled) then raise exception 'TEST: veiled while pass_rule is none'; end if; end $$;
reset role;
do $$ begin
  if has_function_privilege('anon','public.set_department(text)','execute') or has_function_privilege('anon','public.venue_members()','execute') then raise exception 'TEST: anonymous access'; end if;
  if has_function_privilege('authenticated','private.age_band(date)','execute') then raise exception 'TEST: helper exposed'; end if;
end $$;
select 'PASS: veiled venue (no identity before the pass, département + age range, blurred file only, photos, introductions, pass_rule none, départements, anonymous denial)' as result;
rollback;
