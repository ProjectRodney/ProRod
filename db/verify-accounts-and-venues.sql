-- Transaction-only fixtures; no emails sent and no test users remain afterward.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000000001','pro-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000000002','pro-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000000003','pro-unconfirmed@example.invalid',null,false);
insert into private.venues(id,name,category,duration_minutes) values
('00000000-0000-4000-8000-000000000011','Test A','test',60),
('00000000-0000-4000-8000-000000000012','Test B','test',120);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000011',encode(extensions.digest(repeat('a',40),'sha256'),'hex'),now()+interval '1 day'),
('00000000-0000-4000-8000-000000000022','00000000-0000-4000-8000-000000000012',encode(extensions.digest(repeat('b',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),
('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin perform public.save_profile('Minor',(current_date-interval '17 years')::date,'en',true,'hi','u/00000000-0000-4000-8000-000000000001/avatar.jpg'); raise exception 'TEST: minor accepted'; exception when others then if sqlerrm <> 'adults_only' then raise; end if; end;
  begin perform public.save_profile('Alex','2000-01-01','en',true,repeat('x',301),'u/00000000-0000-4000-8000-000000000001/avatar.jpg'); raise exception 'TEST: long bio accepted'; exception when others then if sqlerrm <> 'bio_length' then raise; end if; end;
  begin perform public.save_profile('Alex','2000-01-01','en',true,'hi','u/00000000-0000-4000-8000-000000000002/avatar.jpg'); raise exception 'TEST: another member photo accepted'; exception when others then if sqlerrm <> 'photo_missing' then raise; end if; end;
  begin perform public.save_profile('Alex','2000-01-01','en',true,'hi','u/00000000-0000-4000-8000-000000000001/nope.jpg'); raise exception 'TEST: missing photo accepted'; exception when others then if sqlerrm <> 'photo_missing' then raise; end if; end;
end $$;
select public.save_profile('Alex','2000-01-01','en',true);
do $$ begin
  begin perform public.join_venue(repeat('a',40)); raise exception 'TEST: incomplete profile (no photo, no bio) joined'; exception when others then if sqlerrm<>'profile_required' then raise; end if; end;
  begin perform count(*) from storage.objects where name like 'u/00000000-0000-4000-8000-000000000002/%'; if (select count(*) from storage.objects where name like 'u/00000000-0000-4000-8000-000000000002/%')<>0 then raise exception 'TEST: another member photo listed'; end if; end;
end $$;
select public.save_profile('Alex','2000-01-01','en',true,'Jazz and coffee','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
select public.join_venue(repeat('a',40));
do $$ declare first_expiry timestamptz; second_expiry timestamptz; begin
  select expires_at into first_expiry from public.venue_sessions where ended_at is null;
  select expires_at into second_expiry from public.join_venue(repeat('a',40));
  if first_expiry<>second_expiry then raise exception 'TEST: rescan extended session'; end if;
  begin update public.venue_sessions set expires_at=now()+interval '100 days'; raise exception 'TEST: session tampering allowed'; exception when insufficient_privilege then null; end;
  begin perform count(*) from private.venue_invites; raise exception 'TEST: invite leak'; exception when insufficient_privilege then null; end;
  begin perform public.preview_venue(repeat('z',40)); raise exception 'TEST: invalid invitation accepted'; exception when others then if sqlerrm<>'invalid_invitation' then raise; end if; end;
end $$;
select public.join_venue(repeat('b',40));
do $$ begin
  if (select count(*) from public.venue_sessions where ended_at is null)<>1 then raise exception 'TEST: multiple venues'; end if;
  perform public.join_venue(repeat('a',40));
  if (select count(*) from public.venue_sessions where ended_at is null)<>1 or (select venue_name from public.venue_sessions where ended_at is null)<>'Test A' then raise exception 'TEST: rejoin with a valid invitation failed'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ begin
  if (select count(*) from public.profiles)<>0 or (select count(*) from public.venue_sessions)<>0 then raise exception 'TEST: other account data exposed'; end if;
  begin perform public.join_venue(repeat('a',40)); raise exception 'TEST: incomplete profile joined'; exception when others then if sqlerrm<>'profile_required' then raise; end if; end;
end $$;
select public.save_profile('Maya','2000-01-01','fr',true,'Ici pour la musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select public.join_venue(repeat('a',40));
select public.leave_venue();
do $$ begin if exists(select 1 from public.venue_sessions where ended_at is null) then raise exception 'TEST: leave failed'; end if; end $$;
select public.delete_account();
reset role;
do $$ begin
  if exists(select 1 from auth.users where id='00000000-0000-4000-8000-000000000002') or exists(select 1 from public.profiles where user_id='00000000-0000-4000-8000-000000000002') or exists(select 1 from public.venue_sessions where user_id='00000000-0000-4000-8000-000000000002') then raise exception 'TEST: account deletion incomplete'; end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ begin
  begin perform public.save_profile('Nope','2000-01-01','en',true,'hi',null); raise exception 'TEST: unconfirmed accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.venue_sessions set started_at=now()-interval '2 hours', expires_at=now()-interval '1 second' where user_id='00000000-0000-4000-8000-000000000001' and ended_at is null;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  perform public.join_venue(repeat('b',40));
  if not exists(select 1 from public.venue_sessions where ended_at is null and expires_at>now() and venue_name='Test B') then raise exception 'TEST: rejoin after expiry failed'; end if;
  if (select count(*) from public.venue_sessions where ended_at is null)<>1 then raise exception 'TEST: expired session left open'; end if;
end $$;
reset role;
update private.venue_invites set revoked_at=now() where id='00000000-0000-4000-8000-000000000021';
update private.venue_invites set expires_at=now()-interval '1 second' where id='00000000-0000-4000-8000-000000000022';
set local role authenticated;
do $$ begin
  begin perform public.preview_venue(repeat('a',40)); raise exception 'TEST: revoked invitation accepted'; exception when others then if sqlerrm<>'invalid_invitation' then raise; end if; end;
  begin perform public.preview_venue(repeat('b',40)); raise exception 'TEST: expired invitation accepted'; exception when others then if sqlerrm<>'invalid_invitation' then raise; end if; end;
end $$;
reset role;
insert into private.account_restrictions(user_id,suspended) values('00000000-0000-4000-8000-000000000001',true);
set local role authenticated;
do $$ begin
  begin perform public.save_profile('Alex','2000-01-01','en',true,'hi',null); raise exception 'TEST: suspended account allowed'; exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
  begin perform public.preview_venue(repeat('a',40)); raise exception 'TEST: anonymous RPC permitted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: profile ownership and completeness (photo, bio), private photos, verified accounts, age, server session controls, venue switching, rejoin without extension, account deletion, anonymous denial' as result;
rollback;

-- Discovery: members present in the caller's live venue only; photos readable only while co-present and unblocked.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000000001','pro-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000000002','pro-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000000004','pro-c@example.invalid',now(),false);
insert into private.venues(id,name,category,duration_minutes) values
('00000000-0000-4000-8000-000000000011','Test A','test',60),('00000000-0000-4000-8000-000000000012','Test B','test',120);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000011',encode(extensions.digest(repeat('a',40),'sha256'),'hex'),now()+interval '1 day'),
('00000000-0000-4000-8000-000000000022','00000000-0000-4000-8000-000000000012',encode(extensions.digest(repeat('b',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),
('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002'),
('avatars','u/00000000-0000-4000-8000-000000000004/avatar.jpg','00000000-0000-4000-8000-000000000004');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.save_profile('Alex','2000-01-01','en',true,'Jazz','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
do $$ begin begin perform public.venue_members(); raise exception 'TEST: discovery without session'; exception when others then if sqlerrm<>'no_live_session' then raise; end if; end; end $$;
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select public.save_profile('Chris','1990-01-01','en',true,'Elsewhere','u/00000000-0000-4000-8000-000000000004/avatar.jpg');
select public.join_venue(repeat('b',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare n int; begin
  select count(*) into n from public.venue_members(); if n<>1 then raise exception 'TEST: expected exactly Maya, got %', n; end if;
  if (select display_name from public.venue_members())<>'Maya' then raise exception 'TEST: wrong member'; end if;
  if (select age from public.venue_members())<>date_part('year',age(date '1995-06-15'))::int then raise exception 'TEST: age mismatch'; end if;
  if (select count(*) from storage.objects where name='u/00000000-0000-4000-8000-000000000002/avatar.jpg')<>1 then raise exception 'TEST: co-present photo not readable'; end if;
  if (select count(*) from storage.objects where name='u/00000000-0000-4000-8000-000000000004/avatar.jpg')<>0 then raise exception 'TEST: other-venue photo readable'; end if;
end $$;
reset role;
insert into public.blocks(blocker_id,blocked_id) values('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ begin
  if (select count(*) from public.venue_members())<>0 then raise exception 'TEST: blocked member still listed'; end if;
  if (select count(*) from storage.objects where name='u/00000000-0000-4000-8000-000000000002/avatar.jpg')<>0 then raise exception 'TEST: blocked photo readable'; end if;
  if (select count(*) from public.blocks)<>0 then raise exception 'TEST: block by someone else visible'; end if;
end $$;
reset role;
delete from public.blocks;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.leave_venue();
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  if (select count(*) from public.venue_members())<>0 then raise exception 'TEST: left member still listed'; end if;
  if (select count(*) from storage.objects where name='u/00000000-0000-4000-8000-000000000002/avatar.jpg')<>0 then raise exception 'TEST: photo readable after leaving'; end if;
end $$;
reset role;
select 'PASS: discovery scoped to the live venue, age only, photos readable only while co-present and unblocked' as result;
rollback;
