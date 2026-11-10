-- ANZIAK pilot: automatic fictional members (« test bots ») in the test venue, so one tester can go through the whole
-- journey alone: introduction, acceptance or refusal, simulated pass, conversation, meeting proposal, receiving an
-- introduction. Run once in the Supabase SQL editor of the ProRod project, after db/seed-test-venue.sql.
--
-- Safety:
-- • Only accounts whose e-mail ends with « .test@example.invalid » act (created by db/seed-test-venue.sql, marked
--   « (test) »), only in the test venue a2c1a2c1-…-0001, and only while private.app_settings test_bots = true.
-- • Each action goes through the app's own functions while impersonating the fictional member (request.jwt.claims),
--   so every server rule applies exactly as for a real person: presence, consent, one introduction, pass, blocks,
--   notifications (and push). A bot never writes to a real member outside the test venue (co-presence is required).
-- • Bots never talk to each other. Any failing action is skipped, never blocks the others.
-- Switch off: update private.app_settings set value='false' where key='test_bots';  (the job then does nothing)

insert into private.app_settings(key,value) values ('test_bots','false') on conflict (key) do nothing;

create or replace function private.bot_as(p_uid uuid) returns void language sql set search_path = '' as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else jsonb_build_object('sub',p_uid::text,'role','authenticated')::text end, true)::void
$$;
revoke all on function private.bot_as(uuid) from public, anon, authenticated;

create or replace function private.run_test_bots() returns integer language plpgsql security definer set search_path = '' as $$
declare
  v_venue constant uuid := 'a2c1a2c1-0000-4000-8000-000000000001';
  v_invite constant uuid := 'a2c1a2c1-0000-4000-8000-000000000002';
  decliner constant uuid := 'a2c1a2c1-0000-4000-8000-0000000000f4';  -- Karim (test): always declines
  opener constant uuid := 'a2c1a2c1-0000-4000-8000-0000000000f2';    -- Sam (test): introduces himself first
  b record; i record; c record; m record; n integer := 0; lang text; mine int; theirs int; bot_is_a boolean;
  lines_fr text[] := array['Sympa ! Je suis venu·e avec des amis ce soir.','Tu viens souvent ici ?','Ça te dirait qu’on se dise bonjour au comptoir tout à l’heure ?','Avec plaisir, à tout à l’heure !','(Profil de test) Merci d’avoir testé la conversation.'];
  lines_en text[] := array['Nice! I came with friends tonight.','Do you come here often?','Shall we say hi at the counter later?','Great, see you in a bit!','(Test profile) Thanks for testing the conversation.'];
begin
  if coalesce((private.setting('test_bots') #>> '{}')::boolean,false) is not true then return 0; end if;

  -- 1. Bots stay present in the test venue (3 h visits, renewed) and hold a simulated pass.
  for b in select u.id from auth.users u where u.email like '%.test@example.invalid' loop
    begin
      if not exists(select 1 from public.venue_sessions s where s.user_id=b.id and s.venue_id=v_venue and s.ended_at is null and s.expires_at>now()+interval '5 minutes') then
        update public.venue_sessions set ended_at=now() where user_id=b.id and ended_at is null;
        insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
          values(b.id,v_venue,v_invite,(select v.name from private.venues v where v.id=v_venue),now()+interval '180 minutes');
      end if;
      perform private.bot_as(b.id); perform public.buy_pass_simulated();
    exception when others then null; end;
  end loop;

  -- 2. Introductions received by a bot (at least 20 s old): Karim declines, the others accept with a reply.
  for i in select x.id, x.recipient_id, x.sender_id from public.introductions x join auth.users u on u.id=x.recipient_id
           where u.email like '%.test@example.invalid' and x.status='pending' and x.created_at<now()-interval '20 seconds'
             and not exists(select 1 from auth.users s where s.id=x.sender_id and s.email like '%.test@example.invalid') loop
    begin
      select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=i.sender_id;
      perform private.bot_as(i.recipient_id);
      if i.recipient_id=decliner then perform public.respond_introduction(i.id,false,null);
      else perform public.respond_introduction(i.id,true,case when lang='en' then 'Hi! Happy to chat. Are you here for the whole evening?' else 'Salut ! Avec plaisir. Tu es là pour toute la soirée ?' end); end if;
      n := n+1;
    exception when others then null; end;
  end loop;

  -- 3. Conversations with a bot where the other person wrote last (at least 15 s ago): the bot answers,
  --    proposes to meet once both wrote twice, and says yes when the other person proposed.
  for c in select cv.* from public.conversations cv
           where cv.closed_at is null and cv.venue_id=v_venue
             and ((select u.email from auth.users u where u.id=cv.a_id) like '%.test@example.invalid')
                 <> ((select u.email from auth.users u where u.id=cv.b_id) like '%.test@example.invalid') loop
    begin
      bot_is_a := (select u.email like '%.test@example.invalid' from auth.users u where u.id=c.a_id);
      select * into m from public.messages where conversation_id=c.id order by created_at desc limit 1;
      select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=case when bot_is_a then c.b_id else c.a_id end;
      perform private.bot_as(case when bot_is_a then c.a_id else c.b_id end);
      if m.sender_id <> (case when bot_is_a then c.a_id else c.b_id end) and m.created_at<now()-interval '15 seconds' then
        select count(*) filter (where sender_id=(case when bot_is_a then c.a_id else c.b_id end)), count(*) filter (where sender_id<>(case when bot_is_a then c.a_id else c.b_id end))
          into mine, theirs from public.messages where conversation_id=c.id;
        perform public.send_message(c.id, (case when lang='en' then lines_en else lines_fr end)[least(greatest(mine,1),5)]);
        n := n+1;
      end if;
      select count(*) filter (where sender_id=(case when bot_is_a then c.a_id else c.b_id end)), count(*) filter (where sender_id<>(case when bot_is_a then c.a_id else c.b_id end))
        into mine, theirs from public.messages where conversation_id=c.id;
      if mine>=2 and theirs>=2 and (case when bot_is_a then c.meeting_a else c.meeting_b end) is null then
        perform public.meeting_answer(c.id,true);
      end if;
    exception when others then null; end;
  end loop;

  -- 4. Sam (test) introduces himself to each real member present in the test venue for at least 1 minute, once.
  for b in select s.user_id from public.venue_sessions s join public.profiles p on p.user_id=s.user_id join auth.users u on u.id=s.user_id
           where s.venue_id=v_venue and s.ended_at is null and s.expires_at>now() and s.started_at<now()-interval '1 minute'
             and u.email not like '%.test@example.invalid' and p.account_type<>'venue'
             and not exists(select 1 from public.introductions x where (x.sender_id=opener and x.recipient_id=s.user_id) or (x.sender_id=s.user_id and x.recipient_id=opener)) loop
    begin
      select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=b.user_id;
      perform private.bot_as(opener);
      perform public.send_introduction(b.user_id, case when lang='en' then 'Hi! I''m Sam (test profile). Fancy a chat?' else 'Salut ! Je suis Sam (profil de test). On discute ?' end);
      n := n+1;
    exception when others then null; end;
  end loop;

  perform private.bot_as(null);
  return n;
end $$;
revoke all on function private.run_test_bots() from public, anon, authenticated;

-- Every minute (pg_cron). Silent while test_bots is false.
select cron.schedule('anziak-test-bots', '* * * * *', $$select private.run_test_bots()$$);
