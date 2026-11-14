-- Checks for db/2026-11-14-review-fixes.sql. Transaction-only fixtures; everything is rolled back.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009301','rf-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009302','rf-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009303','rf-c@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009304','rf-d@example.invalid',now(),false);
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000009311','Review fixes','test',120);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009321','00000000-0000-4000-8000-000000009311',encode(extensions.digest(repeat('r',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner)
select 'avatars','u/'||id||'/avatar.jpg',id from auth.users where email like 'rf-%@example.invalid';
update private.app_settings set value='"everyone"' where key='pass_rule';
set local role authenticated;

-- Four members with a complete profile; A and B are in the place, C and D never came.
do $$ declare u text; n int := 0; begin
  foreach u in array array['00000000-0000-4000-8000-000000009301','00000000-0000-4000-8000-000000009302','00000000-0000-4000-8000-000000009303','00000000-0000-4000-8000-000000009304'] loop
    n := n+1; perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
    perform public.save_profile('Member '||n,'2000-01-01','fr',true,'A few words','u/'||u||'/avatar.jpg');
    if n<=2 then perform public.join_venue(repeat('r',40)); end if;
  end loop;
end $$;

select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009301","role":"authenticated"}',true);
do $$ declare x jsonb; begin
  -- Someone never met cannot be blocked or reported, and an unknown identifier gives the same answer.
  begin perform public.block_member('00000000-0000-4000-8000-000000009303'); raise exception 'TEST: blocked a stranger';
  exception when others then if sqlerrm<>'invalid_recipient' then raise; end if; end;
  begin perform public.report_member('00000000-0000-4000-8000-000000009303','other','x'); raise exception 'TEST: reported a stranger';
  exception when others then if sqlerrm<>'invalid_recipient' then raise; end if; end;
  begin perform public.block_member('00000000-0000-4000-8000-00000000dead'); raise exception 'TEST: blocked an unknown identifier';
  exception when others then if sqlerrm<>'invalid_recipient' then raise; end if; end;
  if exists(select 1 from public.blocks where blocker_id=auth.uid()) then raise exception 'TEST: a refused block was recorded'; end if;
  -- Someone present in the same place can be reported (which blocks them), without any pass.
  x := public.report_member('00000000-0000-4000-8000-000000009302','inappropriate','test');
  if (x->>'blocked')::boolean is not true then raise exception 'TEST: report of a person present did not block'; end if;
  -- The export does not give that person's name: they never exchanged.
  x := public.my_data_export();
  if jsonb_array_length(x->'blocks')<>1 or (x->'blocks'->0->>'blocked') is not null then raise exception 'TEST: export names a blocked person never exchanged with: %', x->'blocks'; end if;
end $$;

-- A and D exchanged a hello in the past: A can block D later, from anywhere, and the export names D.
reset role;
insert into public.introductions(sender_id,recipient_id,venue_id,session_id,message,status)
select '00000000-0000-4000-8000-000000009304','00000000-0000-4000-8000-000000009301',s.venue_id,s.id,'Hello','declined'
from public.venue_sessions s where s.user_id='00000000-0000-4000-8000-000000009301';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009301","role":"authenticated"}',true);
do $$ declare x jsonb; begin
  perform public.block_member('00000000-0000-4000-8000-000000009304');
  x := public.my_data_export();
  if not exists(select 1 from jsonb_array_elements(x->'blocks') b where b->>'blocked'='Member 4') then raise exception 'TEST: export hides the name of someone exchanged with: %', x->'blocks'; end if;
end $$;

-- Five hellos per place per 12 hours, even after leaving and scanning again.
reset role;
delete from public.blocks where blocker_id='00000000-0000-4000-8000-000000009301';
insert into auth.users(id,email,email_confirmed_at,is_anonymous)
select ('00000000-0000-4000-8000-0000000094'||lpad(g::text,2,'0'))::uuid,'rf-x'||g||'@example.invalid',now(),false from generate_series(1,5) g;
insert into public.introductions(sender_id,recipient_id,venue_id,session_id,message)
select '00000000-0000-4000-8000-000000009301',('00000000-0000-4000-8000-0000000094'||lpad(g::text,2,'0'))::uuid,s.venue_id,s.id,'Hello'
from generate_series(1,5) g, public.venue_sessions s where s.user_id='00000000-0000-4000-8000-000000009301';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009301","role":"authenticated"}',true);
do $$ begin
  perform public.leave_venue(); perform public.join_venue(repeat('r',40)); perform public.buy_pass_simulated();
  begin perform public.send_introduction('00000000-0000-4000-8000-000000009302','Hello'); raise exception 'TEST: a sixth hello after scanning again';
  exception when others then if sqlerrm<>'introduction_limit' then raise; end if; end;
end $$;
reset role;
select 'PASS: review fixes (block and report only someone met, export without names of strangers, five hellos per place)' as result;
rollback;
