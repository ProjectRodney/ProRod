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
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.leave_venue();
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  if (select count(*) from public.venue_members())<>0 then raise exception 'TEST: left member still listed'; end if;
  if (select count(*) from storage.objects where name='u/00000000-0000-4000-8000-000000000002/avatar.jpg')<>0 then raise exception 'TEST: photo readable after leaving'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin if (select count(*) from public.venue_members())<>1 then raise exception 'TEST: rejoined member not listed'; end if; end $$;
reset role;
insert into public.blocks(blocker_id,blocked_id) values('00000000-0000-4000-8000-000000000002','00000000-0000-4000-8000-000000000001');
set local role authenticated;
do $$ begin
  if (select count(*) from public.venue_members())<>0 then raise exception 'TEST: blocked member still listed'; end if;
  if (select count(*) from storage.objects where name='u/00000000-0000-4000-8000-000000000002/avatar.jpg')<>0 then raise exception 'TEST: blocked photo readable'; end if;
  if (select count(*) from public.blocks)<>0 then raise exception 'TEST: block by someone else visible'; end if;
end $$;
reset role;
select 'PASS: discovery scoped to the live venue, age only, photos readable only while co-present and unblocked' as result;
rollback;

-- Introductions, consent, conversations, closure, blocks and reports.
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
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select public.save_profile('Chris','1990-01-01','en',true,'Elsewhere','u/00000000-0000-4000-8000-000000000004/avatar.jpg');
select public.join_venue(repeat('b',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.send_introduction('00000000-0000-4000-8000-000000000002','Hello Maya, same taste in jazz?');
do $$ begin
  begin perform public.send_introduction('00000000-0000-4000-8000-000000000002','again'); raise exception 'TEST: second introduction allowed'; exception when others then if sqlerrm<>'introduction_exists' then raise; end if; end;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000000004','hi'); raise exception 'TEST: cross-venue introduction allowed'; exception when others then if sqlerrm<>'not_co_present' then raise; end if; end;
  begin perform count(*) from public.introductions; raise exception 'TEST: introductions readable'; exception when insufficient_privilege then null; end;
  begin perform count(*) from public.messages; raise exception 'TEST: messages readable'; exception when insufficient_privilege then null; end;
  if jsonb_array_length(public.my_inbox()->'sent')<>1 or (public.my_inbox()->'sent'->0->>'status')<>'pending' then raise exception 'TEST: sent introduction missing'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare intro uuid; result jsonb; begin
  if jsonb_array_length(public.my_inbox()->'received')<>1 then raise exception 'TEST: received introduction missing'; end if;
  if (public.my_inbox()->'received'->0->'from'->>'display_name')<>'Alex' or (public.my_inbox()->'received'->0->'from') ? 'birth_date' then raise exception 'TEST: sender card wrong'; end if;
  intro := (public.my_inbox()->'received'->0->>'id')::uuid;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000000001','me too'); raise exception 'TEST: counter-introduction allowed'; exception when others then if sqlerrm<>'introduction_received' then raise; end if; end;
  begin perform public.respond_introduction(intro,true,null); raise exception 'TEST: accept without reply allowed'; exception when others then if sqlerrm<>'reply_required' then raise; end if; end;
  result := public.respond_introduction(intro,true,'Yes! Coltrane fan here.');
  if result->>'status'<>'accepted' or result->>'conversation_id' is null then raise exception 'TEST: accept failed'; end if;
  if jsonb_array_length(public.my_inbox()->'received')<>0 or jsonb_array_length(public.my_inbox()->'conversations')<>1 then raise exception 'TEST: inbox after accept wrong'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare conv uuid; thread jsonb; begin
  if jsonb_array_length(public.my_inbox()->'conversations')<>1 or (public.my_inbox()->'conversations'->0->>'unread')::int<>1 or jsonb_array_length(public.my_inbox()->'sent')<>0 then raise exception 'TEST: conversation list wrong'; end if;
  conv := (public.my_inbox()->'conversations'->0->>'id')::uuid;
  thread := public.conversation_messages(conv);
  if jsonb_array_length(thread->'messages')<>2 or (thread->'messages'->0->>'mine')<>'true' or (thread->'messages'->1->>'mine')<>'false' then raise exception 'TEST: thread wrong'; end if;
  -- pass rule "everyone": the reply stays hidden and writing is refused until a (simulated) pass covers the venue session
  if not (thread->>'locked')::boolean or thread->'messages'->1->>'body' is not null or not (thread->'messages'->1->>'locked')::boolean then raise exception 'TEST: reply not locked without pass: %', thread; end if;
  begin perform public.send_message(conv,'Great, see you by the counter?'); raise exception 'TEST: wrote without pass'; exception when others then if sqlerrm<>'pass_required' then raise; end if; end;
  perform public.buy_pass_simulated();
  if not (public.buy_pass_simulated()->>'already')::boolean then raise exception 'TEST: pass bought twice'; end if;
  if jsonb_array_length(public.my_passes())<>1 or not (public.my_passes()->0->>'simulated')::boolean or (public.my_passes()->0->>'amount_cents')::int<>0 then raise exception 'TEST: pass list wrong'; end if;
  begin perform count(*) from public.passes; raise exception 'TEST: passes readable'; exception when insufficient_privilege then null; end;
  thread := public.conversation_messages(conv);
  if (thread->>'locked')::boolean or thread->'messages'->1->>'body'<>'Yes! Coltrane fan here.' then raise exception 'TEST: pass did not unlock'; end if;
  if (public.my_inbox()->'conversations'->0->>'unread')::int<>0 then raise exception 'TEST: read receipt not recorded'; end if;
  perform public.send_message(conv,'Great, see you by the counter?');
  -- chat only while both are checked in at the venue: history stays readable, writing resumes when the other person is back
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true); perform public.leave_venue(); perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  thread := public.conversation_messages(conv);
  if (thread->>'live')::boolean or jsonb_array_length(thread->'messages')<>3 or (thread->'meeting'->>'can_ask')::boolean then raise exception 'TEST: visit state wrong: %', thread; end if;
  begin perform public.send_message(conv,'still here?'); raise exception 'TEST: wrote after the other person left'; exception when others then if sqlerrm<>'visit_over' then raise; end if; end;
  begin perform public.meeting_answer(conv,true); raise exception 'TEST: meeting proposed after leaving'; exception when others then if sqlerrm<>'visit_over' then raise; end if; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true); perform public.join_venue(repeat('a',40)); perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  perform public.send_message(conv,'welcome back');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
  begin perform public.conversation_messages(conv); raise exception 'TEST: outsider read conversation'; exception when others then if sqlerrm<>'conversation_unavailable' then raise; end if; end;
  begin perform public.send_message(conv,'intruder'); raise exception 'TEST: outsider wrote'; exception when others then if sqlerrm<>'conversation_unavailable' then raise; end if; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
  perform public.buy_pass_simulated();
  perform public.close_conversation(conv);
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
  begin perform public.send_message(conv,'still there?'); raise exception 'TEST: wrote after close'; exception when others then if sqlerrm<>'conversation_closed' then raise; end if; end;
  if (public.my_inbox()->'conversations'->0->>'closed_by_me')<>'false' or (public.my_inbox()->'conversations'->0->>'closed_at') is null then raise exception 'TEST: closure not neutral'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.block_member('00000000-0000-4000-8000-000000000001');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  if jsonb_array_length(public.my_inbox()->'conversations')<>0 then raise exception 'TEST: blocked conversation still listed'; end if;
  if (select count(*) from public.venue_members())<>0 then raise exception 'TEST: blocker still discoverable'; end if;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000000002','hey'); raise exception 'TEST: introduction to blocker allowed'; exception when others then if sqlerrm<>'not_co_present' then raise; end if; end;
  if (public.report_member('00000000-0000-4000-8000-000000000002','harassment','details')->>'id') is null then raise exception 'TEST: report failed'; end if;
  begin perform count(*) from public.reports; raise exception 'TEST: reports readable'; exception when insufficient_privilege then null; end;
  begin perform public.report_member('00000000-0000-4000-8000-000000000002','bogus',null); raise exception 'TEST: bad category'; exception when others then if sqlerrm<>'invalid_category' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
select public.join_venue(repeat('a',40));
select public.send_introduction('00000000-0000-4000-8000-000000000001','Hi Alex');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare intro uuid; begin
  intro := (public.my_inbox()->'received'->0->>'id')::uuid;
  if (public.respond_introduction(intro,false,null)->>'status')<>'declined' then raise exception 'TEST: decline failed'; end if;
  if jsonb_array_length(public.my_inbox()->'received')<>0 then raise exception 'TEST: declined still received'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated"}',true);
do $$ begin
  if (public.my_inbox()->'sent'->0->>'status')<>'pending' then raise exception 'TEST: decline leaked to sender'; end if;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000000001','again?'); raise exception 'TEST: re-solicitation allowed'; exception when others then if sqlerrm<>'introduction_exists' then raise; end if; end;
  -- a refusal holds across visits: leaving and coming back does not reopen the door
  perform public.leave_venue(); perform public.join_venue(repeat('a',40));
  begin perform public.send_introduction('00000000-0000-4000-8000-000000000001','new visit, new luck?'); raise exception 'TEST: re-solicitation after rejoining allowed'; exception when others then if sqlerrm<>'introduction_exists' then raise; end if; end;
end $$;
reset role;
select 'PASS: one introduction, consent with reply, venue-scoped, private threads, simulated pass unlocks replies, chat only while both are present, refusals hold across visits, neutral closure, blocks everywhere, reports hidden' as result;
rollback;

-- Section 3b (7 November 2026). A venue pass counts only while it is valid: a pass from an earlier visit neither lets
-- the member write on a later visit nor reveals replies sent after it expired (thread, inbox preview, data export).
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000000001','pass-a@example.invalid',now(),false),('00000000-0000-4000-8000-000000000002','pass-b@example.invalid',now(),false);
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000000011','Test A','test',60);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000011',encode(extensions.digest(repeat('a',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.save_profile('Alex','2000-01-01','en',true,'Jazz','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.send_introduction('00000000-0000-4000-8000-000000000002','Hello Maya');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.respond_introduction((public.my_inbox()->'received'->0->>'id')::uuid,true,'First visit reply');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.buy_pass_simulated();
select public.send_message((public.my_inbox()->'conversations'->0->>'id')::uuid,'Nice to meet you');
reset role;
-- Alex's first visit (and the pass bought for it) ended three days ago; everything so far moves back three days.
update public.venue_sessions set started_at=started_at-interval '3 days', expires_at=expires_at-interval '3 days' where user_id='00000000-0000-4000-8000-000000000001';
update public.passes set created_at=created_at-interval '3 days', expires_at=expires_at-interval '3 days' where user_id='00000000-0000-4000-8000-000000000001';
update public.conversations set created_at=created_at-interval '3 days';
update public.messages set created_at=created_at-interval '3 days';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.buy_pass_simulated();
select public.send_message((public.my_inbox()->'conversations'->0->>'id')::uuid,'Second visit reply');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare conv uuid := (public.my_inbox()->'conversations'->0->>'id')::uuid; thread jsonb; old_reply jsonb; new_reply jsonb; begin
  begin perform public.send_message(conv,'hello again'); raise exception 'TEST: expired pass let the member write'; exception when others then if sqlerrm<>'pass_required' then raise; end if; end;
  thread := public.conversation_messages(conv);
  if not (thread->>'locked')::boolean then raise exception 'TEST: thread not locked with an expired pass'; end if;
  if jsonb_array_length(thread->'messages')<>4 then raise exception 'TEST: thread length: %', thread; end if;
  old_reply := thread->'messages'->1; new_reply := thread->'messages'->3;
  if (old_reply->>'mine')::boolean or old_reply->>'body' is distinct from 'First visit reply' then raise exception 'TEST: reply covered by the earlier pass hidden: %', thread; end if;
  if (new_reply->>'mine')::boolean or new_reply->>'body' is not null or not (new_reply->>'locked')::boolean then raise exception 'TEST: reply after pass expiry readable: %', thread; end if;
  if public.my_inbox()->'conversations'->0->'last'->>'body' is not null then raise exception 'TEST: inbox preview leaks a hidden reply'; end if;
  if exists(select 1 from jsonb_array_elements(public.my_data_export()->'conversations'->0->'messages') e where e->>'body'='Second visit reply') then raise exception 'TEST: data export leaks a hidden reply'; end if;
  perform public.buy_pass_simulated();
  thread := public.conversation_messages(conv);
  if (thread->>'locked')::boolean or thread->'messages'->3->>'body' is distinct from 'Second visit reply' then raise exception 'TEST: new pass did not unlock: %', thread; end if;
  if public.my_inbox()->'conversations'->0->'last'->>'body' is distinct from 'Second visit reply' then raise exception 'TEST: inbox preview not unlocked'; end if;
  perform public.send_message(conv,'hello again');
end $$;
reset role;
select 'PASS: a venue pass counts only while valid; replies after its expiry stay hidden in the thread, inbox and export until a new pass' as result;
rollback;

-- Administration: role from app_metadata only, venues, invitations, report decisions, suspension, audit.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_app_meta_data) values
('00000000-0000-4000-8000-000000000001','pro-a@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000002','pro-b@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000009','admin@example.invalid',now(),false,'{"prod_admin":true}');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),
('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","user_metadata":{"prod_admin":true},"app_metadata":{}}',true);
do $$ begin
  begin perform public.admin_overview(); raise exception 'TEST: member reached admin'; exception when insufficient_privilege then null; end;
  if public.is_admin() then raise exception 'TEST: is_admin from user_metadata'; end if;
end $$;
select public.save_profile('Alex','2000-01-01','en',true,'Jazz','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare v jsonb; inv jsonb; rep jsonb; n int; begin
  if not public.is_admin() then raise exception 'TEST: is_admin false for admin'; end if;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal1","app_metadata":{"prod_admin":true}}',true);
  begin perform public.admin_overview(); raise exception 'TEST: admin without two-step verification allowed'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
  v := public.admin_save_venue(null,'Café test','pub',90,'1 rue Test',true);
  inv := public.admin_create_invite((v->>'id')::uuid,7);
  if length(inv->>'token')<40 then raise exception 'TEST: token missing'; end if;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  perform public.join_venue(inv->>'token');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  perform public.join_venue(inv->>'token');
  perform public.send_introduction('00000000-0000-4000-8000-000000000001','hi');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  rep := public.report_member('00000000-0000-4000-8000-000000000002','harassment','rude');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
  if (public.admin_overview()->>'reports_open')::int<>1 or (public.admin_overview()->>'sessions_live')::int<>2 then raise exception 'TEST: overview wrong'; end if;
  if (public.admin_reports('open')->0->'reported'->>'display_name')<>'Maya' or (public.admin_reports('open')->0->'reporter'->>'display_name')<>'Alex' then raise exception 'TEST: report cards wrong'; end if;
  perform public.admin_decide_report((rep->>'id')::uuid,'actioned','Suspended after review',true);
  if (public.admin_overview()->>'reports_open')::int<>0 or (public.admin_overview()->>'suspended')::int<>1 then raise exception 'TEST: decision not applied'; end if;
  if (select count(*) from jsonb_array_elements(public.admin_members('May')) m where (m->>'suspended')::boolean)<>1 then raise exception 'TEST: member search/suspension wrong'; end if;
  perform public.admin_revoke_invite((inv->>'id')::uuid);
  select count(*) into n from jsonb_array_elements(public.admin_audit(50)); if n<>4 then raise exception 'TEST: audit incomplete (%)', n; end if;
  if (public.admin_overview()->>'sessions_live')::int<>0 then raise exception 'TEST: revoke did not end sessions'; end if;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  begin perform public.my_inbox(); raise exception 'TEST: suspended member still active'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
  perform public.admin_restrict('00000000-0000-4000-8000-000000000002',false,'appeal accepted');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  perform public.my_inbox();
end $$;
reset role;
select 'PASS: admin claim from app_metadata only and two-step verification always required, venues, invitations, report decisions with suspension, member search, audit, reinstatement' as result;
rollback;

-- Notifications: never message contents, deduplicated per conversation, cleared on read.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_app_meta_data) values
('00000000-0000-4000-8000-000000000001','pro-a@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000002','pro-b@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000009','admin@example.invalid',now(),false,'{"prod_admin":true}');
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000000011','Test A','test',60);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values ('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000011',encode(extensions.digest(repeat('a',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),
('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
select public.save_profile('Alex','2000-01-01','en',true,'Jazz','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
select public.send_introduction('00000000-0000-4000-8000-000000000002','Hello Maya, secret words here');
do $$ declare n jsonb; intro uuid; conv uuid; begin
  begin perform count(*) from public.notifications; raise exception 'TEST: notifications readable'; exception when insufficient_privilege then null; end;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  n := public.my_notifications(false);
  if (n->>'unread')::int<>1 or (n->'items'->0->>'kind')<>'introduction_received' or (n->'items'->0->'payload'->>'from')<>'Alex' then raise exception 'TEST: introduction notification wrong: %', n; end if;
  if n::text like '%secret words%' then raise exception 'TEST: message content leaked in notification'; end if;
  intro := (public.my_inbox()->'received'->0->>'id')::uuid;
  conv := (public.respond_introduction(intro,true,'Yes, hidden reply text')->>'conversation_id')::uuid;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  n := public.my_notifications(false);
  if (n->>'unread')::int<>1 or (n->'items'->0->>'kind')<>'reply_received' then raise exception 'TEST: reply notification wrong: %', n; end if;
  if n::text like '%hidden reply%' then raise exception 'TEST: reply content leaked'; end if;
  perform public.conversation_messages(conv);
  if (public.my_notifications(false)->>'unread')::int<>0 then raise exception 'TEST: read did not clear'; end if;
  perform public.buy_pass_simulated();
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  perform public.buy_pass_simulated();
  perform public.send_message(conv,'one'); perform public.send_message(conv,'two'); perform public.send_message(conv,'three');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  if (public.my_notifications(false)->>'unread')::int<>1 then raise exception 'TEST: message notifications not deduplicated'; end if;
  perform public.my_notifications(true);
  if (public.my_notifications(false)->>'unread')::int<>0 then raise exception 'TEST: mark read failed'; end if;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  perform public.close_conversation(conv);
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  if (public.my_notifications(false)->'items'->0->>'kind')<>'conversation_closed' then raise exception 'TEST: closure notification missing'; end if;
  perform public.report_member('00000000-0000-4000-8000-000000000002','other','x');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
  perform public.admin_decide_report((public.admin_reports('open')->0->>'id')::uuid,'dismissed','no issue',false);
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  if (public.my_notifications(false)->'items'->0->>'kind')<>'report_handled' then raise exception 'TEST: report notification missing'; end if;
end $$;
reset role;
select 'PASS: notifications without content, deduplicated, cleared on read, for introductions, replies, messages, closures and report decisions' as result;
rollback;

-- Meeting prompt and data export.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_app_meta_data) values
('00000000-0000-4000-8000-000000000001','pro-a@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000002','pro-b@example.invalid',now(),false,'{}');
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000000011','Test A','test',60);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values ('00000000-0000-4000-8000-000000000021','00000000-0000-4000-8000-000000000011',encode(extensions.digest(repeat('a',40),'sha256'),'hex'),now()+interval '1 day');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),
('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
select public.save_profile('Alex','2000-01-01','en',true,'Jazz','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
select public.join_venue(repeat('a',40));
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
select public.send_introduction('00000000-0000-4000-8000-000000000002','Hello');
do $$ declare intro uuid; conv uuid; st jsonb; ex jsonb; begin
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  intro := (public.my_inbox()->'received'->0->>'id')::uuid;
  conv := (public.respond_introduction(intro,true,'Hi!')->>'conversation_id')::uuid;
  begin perform public.meeting_answer(conv,true); raise exception 'TEST: meeting allowed too early'; exception when others then if sqlerrm<>'meeting_too_early' then raise; end if; end;
  perform public.buy_pass_simulated();
  perform public.send_message(conv,'two');
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
  perform public.buy_pass_simulated();
  perform public.send_message(conv,'two');
  if not ((public.conversation_messages(conv)->'meeting'->>'can_ask')::boolean) then raise exception 'TEST: can_ask false after two each'; end if;
  st := public.meeting_answer(conv,true);
  if (st->>'agreed')::boolean then raise exception 'TEST: one yes counted as agreement'; end if;
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
  st := public.conversation_messages(conv)->'meeting';
  if not (st->>'other_answered')::boolean or st->>'my_answer' is not null then raise exception 'TEST: prompt state wrong: %', st; end if;
  st := public.meeting_answer(conv,false);
  if (st->>'agreed')::boolean then raise exception 'TEST: no counted as agreement'; end if;
  perform public.send_message(conv,'still chatting');
  st := public.meeting_answer(conv,true);
  if not (st->>'agreed')::boolean then raise exception 'TEST: two yes not agreed'; end if;
  ex := public.my_data_export();
  if ex->'profile'->>'display_name'<>'Maya' or jsonb_array_length(ex->'conversations')<>1 or ex::text not like '%Alex%' or ex::text like '%pro-a@example%' then raise exception 'TEST: export wrong: %', left(ex::text,200); end if;
end $$;
reset role;
select 'PASS: meeting needs two yes after a real exchange, no never agrees, export contains own data and only display names of others' as result;
rollback;

-- Account types: venue accounts (application → approval → dashboard), pro sheets (approval → talents in the venue → enquiry), person-only guards.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_app_meta_data) values
('00000000-0000-4000-8000-000000000001','pro-a@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000002','pro-b@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000004','venue@example.invalid',now(),false,'{}'),
('00000000-0000-4000-8000-000000000009','admin@example.invalid',now(),false,'{"prod_admin":true}');
insert into storage.objects(bucket_id,name,owner) values
('avatars','u/00000000-0000-4000-8000-000000000001/avatar.jpg','00000000-0000-4000-8000-000000000001'),
('avatars','u/00000000-0000-4000-8000-000000000002/avatar.jpg','00000000-0000-4000-8000-000000000002');
set local role authenticated;
-- Venue account: no birth date, no photo; cannot join venues or see people; applies for a venue.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{}}',true);
do $$ begin if public.my_account_type() is not null then raise exception 'TEST: type before choice'; end if; end $$;
select public.set_account_type('venue');
do $$ begin
  if public.my_account_type()<>'venue' then raise exception 'TEST: choice not stored'; end if;
  begin perform public.apply_venue('Le Bar','pub','1 rue Test, 93140 Bondy',null,null,60); raise exception 'TEST: venue applied without a profile'; exception when others then if sqlerrm<>'venue_account_required' then raise; end if; end;
end $$;
select public.save_profile('Le Bar de test',null,'fr',true);
do $$ declare r jsonb; begin
  begin perform public.set_account_type('personal'); raise exception 'TEST: venue switched to personal'; exception when others then if sqlerrm<>'type_locked' then raise; end if; end;
  r := public.apply_venue('Le Bar de test','pub','1 rue Test, 93140 Bondy','18h-2h','01 00 00 00 00',240);
  if r->>'status'<>'pending' then raise exception 'TEST: application not pending'; end if;
  begin perform public.apply_venue('Le Bar de test','pub','1 rue Test, 93140 Bondy',null,null,60); raise exception 'TEST: second pending application'; exception when others then if sqlerrm<>'application_pending' then raise; end if; end;
  if (public.my_venue()->'application'->>'status')<>'pending' then raise exception 'TEST: my_venue application missing'; end if;
  begin perform public.venue_create_invite(7); raise exception 'TEST: invite without venue'; exception when others then if sqlerrm<>'venue_required' then raise; end if; end;
  begin perform public.venue_members(); raise exception 'TEST: venue account listed people'; exception when insufficient_privilege then null; end;
  begin perform public.venue_talents(); raise exception 'TEST: venue account listed talents'; exception when insufficient_privilege then null; end;
end $$;
-- Admin approves the venue.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare apps jsonb; r jsonb; begin
  apps := public.admin_venue_applications('pending');
  if jsonb_array_length(apps)<>1 then raise exception 'TEST: pending applications %', apps; end if;
  r := public.admin_decide_venue((apps->0->>'id')::uuid,true,'Bienvenue');
  if r->>'status'<>'approved' then raise exception 'TEST: approval failed'; end if;
  if jsonb_array_length(public.admin_venue_applications('pending'))<>0 then raise exception 'TEST: still pending'; end if;
end $$;
-- Venue dashboard: invite (capped at 180 min), announcement, update, present count.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{}}',true);
select set_config('prod_test.invite_token',public.venue_create_invite(30)->>'token',true);
do $$ declare v jsonb; begin
  v := public.my_venue()->'venue';
  if v is null or (v->>'duration_minutes')::int<>180 then raise exception 'TEST: venue duration not capped: %', v; end if;
  if jsonb_array_length(v->'invites')<>1 then raise exception 'TEST: invite missing'; end if;
  perform public.venue_announce('Happy hour jusqu''à 20h');
  begin perform public.venue_update(null,null,500); raise exception 'TEST: 500 min accepted'; exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  perform public.venue_update('18h-2h','01 00 00 00 00',120);
  v := public.my_venue()->'venue';
  if (v->>'duration_minutes')::int<>120 or jsonb_array_length(v->'announcements')<>1 then raise exception 'TEST: update or announcement failed'; end if;
  begin perform count(*) from public.venue_announcements; raise exception 'TEST: announcements readable directly'; exception when insufficient_privilege then null; end;
end $$;
-- Pro account: full profile + pro sheet, pending until approved; not shown as talent before approval + subscription.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
select public.set_account_type('pro');
select public.save_profile('Alex','2000-01-01','en',true,'Jazz','u/00000000-0000-4000-8000-000000000001/avatar.jpg');
do $$ declare r jsonb; begin
  begin perform public.save_profile('Alex',null,'en',true,'Jazz'); raise exception 'TEST: pro without birth date'; exception when others then if sqlerrm<>'adults_only' then raise; end if; end;
  r := public.save_pro_profile('Studio Alex','DJ Alex','DJ','Ambiance soul et funk pour vos soirées.','https://example.invalid','{"instagram":"@alex","evil":"x"}','Bondy');
  if r->>'status'<>'pending' then raise exception 'TEST: pro sheet not pending'; end if;
  if public.my_pro_profile()->'socials' ? 'evil' then raise exception 'TEST: unknown social kept'; end if;
  perform public.join_venue(current_setting('prod_test.invite_token'));
  begin perform count(*) from public.pro_profiles; raise exception 'TEST: pro_profiles readable directly'; exception when insufficient_privilege then null; end;
end $$;
-- A personal member in the same venue sees the room (announcement, count) but no talent yet.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
select public.save_profile('Maya','1995-06-15','fr',true,'Musique','u/00000000-0000-4000-8000-000000000002/avatar.jpg');
do $$ declare room jsonb; begin
  if public.my_account_type()<>'personal' then raise exception 'TEST: default type'; end if;
  begin perform public.venue_room(); raise exception 'TEST: room without session'; exception when others then if sqlerrm<>'no_live_session' then raise; end if; end;
  perform public.join_venue(current_setting('prod_test.invite_token'));
  room := public.venue_room();
  if (room->>'present')::int<>2 or jsonb_array_length(room->'announcements')<>1 then raise exception 'TEST: room %', room; end if;
  if jsonb_array_length(public.venue_talents())<>0 then raise exception 'TEST: unapproved talent listed'; end if;
  if (select count(*) from public.venue_members())<>1 then raise exception 'TEST: members count'; end if;
  begin perform public.send_enquiry('00000000-0000-4000-8000-000000000001','Bonjour',null); raise exception 'TEST: enquiry to unapproved pro'; exception when others then if sqlerrm<>'not_co_present' then raise; end if; end;
end $$;
-- Admin approves the pro sheet; subscription is still required to appear (simulated later from the app).
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000009","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ begin
  if jsonb_array_length(public.admin_pro_profiles('pending'))<>1 then raise exception 'TEST: pending pro sheets'; end if;
  perform public.admin_decide_pro('00000000-0000-4000-8000-000000000001',true,'OK');
end $$;
reset role;
update public.pro_profiles set subscription_until=now()+interval '30 days' where user_id='00000000-0000-4000-8000-000000000001';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated","app_metadata":{}}',true);
do $$ declare t jsonb; begin
  t := public.venue_talents();
  if jsonb_array_length(t)<>1 or t->0->>'business_name'<>'Studio Alex' then raise exception 'TEST: talent not listed %', t; end if;
  perform public.send_enquiry('00000000-0000-4000-8000-000000000001','Dispo pour samedi ?','06 00 00 00 00');
  begin perform count(*) from public.enquiries; raise exception 'TEST: enquiries readable directly'; exception when insufficient_privilege then null; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated","app_metadata":{}}',true);
do $$ declare p jsonb; begin
  p := public.my_pro_profile();
  if not (p->>'subscription_active')::boolean or jsonb_array_length(p->'enquiries')<>1 or p->'enquiries'->0->>'from'<>'Maya' then raise exception 'TEST: enquiry missing %', p; end if;
  if (select count(*) from jsonb_array_elements(public.my_notifications(false)->'items') n where n->>'kind'='introduction_received')<>1 then raise exception 'TEST: enquiry notification'; end if;
end $$;
-- Venue revokes the invite: both sessions end.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000004","role":"authenticated","app_metadata":{}}',true);
do $$ declare v jsonb; begin
  v := public.my_venue()->'venue';
  if (v->>'present')::int<>2 then raise exception 'TEST: present count %', v; end if;
  perform public.venue_revoke_invite((v->'invites'->0->>'id')::uuid);
  v := public.my_venue()->'venue';
  if (v->>'present')::int<>0 or jsonb_array_length(v->'invites')<>0 then raise exception 'TEST: revoke failed %', v; end if;
  perform public.venue_delete_announcement((v->'announcements'->0->>'id')::uuid);
  if jsonb_array_length(public.my_venue()->'venue'->'announcements')<>0 then raise exception 'TEST: announcement removal failed'; end if;
end $$;
select 'PASS: venue accounts apply/approve/dashboard (invites capped at 3 h, announcements, revoke ends sessions), pro sheets approved + subscribed only, enquiries scoped to the venue, venue accounts never list people' as result;
rollback;

-- Section 8 (7 November 2026). Push notifications: members save and remove only their own devices, https only, the table is
-- never readable by clients, and the unread count matches the app (introductions waiting + unread messages + notifications).
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values ('00000000-0000-4000-8000-000000000001','push-a@example.invalid',now(),false),('00000000-0000-4000-8000-000000000002','push-b@example.invalid',now(),false);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
select public.save_push_subscription('https://push.example.invalid/endpoint-a-1234567890','BPpublickey-abcdefghijklmnopqrstuvwxyz','authsecret123');
do $$ begin
  begin perform public.save_push_subscription('http://push.example.invalid/x-1234567890','BPpublickey-abcdefghijklmnopqrstuvwxyz','authsecret123'); raise exception 'TEST: http endpoint accepted'; exception when others then if sqlerrm<>'invalid_subscription' then raise; end if; end;
  begin perform count(*) from public.push_subscriptions; raise exception 'TEST: subscriptions readable'; exception when insufficient_privilege then null; end;
  if (public.push_status()->>'devices')::int<>1 then raise exception 'TEST: device not saved'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
select public.delete_push_subscription('https://push.example.invalid/endpoint-a-1234567890');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  if (public.push_status()->>'devices')::int<>1 then raise exception 'TEST: another member removed the device'; end if;
  perform public.delete_push_subscription('https://push.example.invalid/endpoint-a-1234567890');
  if (public.push_status()->>'devices')::int<>0 then raise exception 'TEST: own device not removed'; end if;
end $$;
reset role;
do $$ begin if private.unread_total('00000000-0000-4000-8000-000000000001')<>0 then raise exception 'TEST: unread total'; end if; end $$;
select 'PASS: push devices private and owned, https only, removal by owner only, unread total' as result;
rollback;

-- Section 8b (7 November 2026). An account confirmed by phone only (no e-mail) is a verified member; an unconfirmed one is not.
begin;
insert into auth.users(id,phone,phone_confirmed_at,is_anonymous) values ('00000000-0000-4000-8000-000000000031','33600000031',now(),false),('00000000-0000-4000-8000-000000000032','33600000032',null,false);
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000031","role":"authenticated"}',true);
do $$ begin if (public.push_status()->>'devices')::int<>0 then raise exception 'TEST: phone member refused'; end if; end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000032","role":"authenticated"}',true);
do $$ begin begin perform public.push_status(); raise exception 'TEST: unconfirmed phone accepted'; exception when others then if sqlerrm<>'verified_account_required' then raise; end if; end; end $$;
reset role;
select 'PASS: phone-confirmed accounts are members, unconfirmed ones are not' as result;
rollback;

