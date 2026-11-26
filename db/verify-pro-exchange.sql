-- Checks for db/2026-11-26-pro-exchange.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: exchange between a member and a professional
begin;
-- P = professional (approved sheet), A, B and C = personal members, X = a personal member who has nothing to do with it.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009601','px-p@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009602','px-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009603','px-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009604','px-c@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009605','px-x@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009609','px-admin@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,account_type)
select u.id, 'Membre '||right(u.id::text,2), '1995-01-01', 'fr', 'Bio de test', 'u/'||u.id||'/a.jpg',
       case when right(u.id::text,2)='01' then 'pro' else 'personal' end
from auth.users u where u.email like 'px-%@example.invalid';
insert into public.pro_profiles(user_id,business_name,category,pitch,status) values
('00000000-0000-4000-8000-000000009601','Studio Test','DJ','Mixes pour vos soirées.','approved');
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000009611','Exchange test','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009621','00000000-0000-4000-8000-000000009611',encode(extensions.digest(repeat('x',40),'sha256'),'hex'),now()+interval '1 day');
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
select u.id,'00000000-0000-4000-8000-000000009611','00000000-0000-4000-8000-000000009621','Exchange test',now()+interval '2 hours'
from auth.users u where u.email like 'px-%@example.invalid' and u.email<>'px-admin@example.invalid';
-- A, B and C each open a request, as before (both people in the same place).
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009602","role":"authenticated"}',true); select public.send_enquiry('00000000-0000-4000-8000-000000009601','Bonjour, êtes-vous libre le 12 ?','a@example.invalid');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009603","role":"authenticated"}',true); select public.send_enquiry('00000000-0000-4000-8000-000000009601','Un devis pour un mariage ?',null);
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009604","role":"authenticated"}',true); select public.send_enquiry('00000000-0000-4000-8000-000000009601','Vos tarifs ?',null);
reset role;
-- Everyone leaves the place: answering does not need the two people to still be there.
update public.venue_sessions set started_at=now()-interval '2 hours', expires_at=now()-interval '1 minute' where venue_id='00000000-0000-4000-8000-000000009611';
set local role authenticated;
-- The professional reads the thread and answers; never more than three messages in a row.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009601","role":"authenticated"}',true);
-- The thread ids are learnt the way the app learns them (from the professional's own list), never from the tables.
select set_config('px.'||x.k,(select e->>'id' from jsonb_array_elements(public.my_pro_profile()->'enquiries') e where e->>'from'=x.n),true)
from (values('a','Membre 02'),('b','Membre 03'),('c','Membre 04')) x(k,n);
do $$ declare t jsonb; id uuid := current_setting('px.a')::uuid; p jsonb;
begin
  p := public.my_pro_profile();
  if jsonb_array_length(p->'enquiries')<>3 then raise exception 'TEST: pro does not see three requests'; end if;
  if (select (e->>'unread')::int from jsonb_array_elements(p->'enquiries') e where e->>'id'=id::text)<>1 then raise exception 'TEST: new request not counted unread'; end if;
  t := public.enquiry_thread(id);
  if t->>'role'<>'pro' or t->>'with'<>'Membre 02' or (t->>'open')::boolean is not true then raise exception 'TEST: pro thread wrong %', t; end if;
  if jsonb_array_length(t->'messages')<>1 or (t->'messages'->0->>'mine')::boolean then raise exception 'TEST: first message wrong'; end if;
  if t->>'contact'<>'a@example.invalid' then raise exception 'TEST: contact left not shown to the pro'; end if;
  if t::text like '%00000000-0000-4000-8000-000000009602%' then raise exception 'TEST: member id leaked to the pro'; end if;
  if (select (e->>'unread')::int from jsonb_array_elements(public.my_pro_profile()->'enquiries') e where e->>'id'=id::text)<>0 then raise exception 'TEST: opening the thread did not mark it read'; end if;
  perform public.reply_enquiry(id,'Oui, libre le 12.');
  perform public.reply_enquiry(id,'Voici mes disponibilités.');
  perform public.reply_enquiry(id,'Dites-moi.');
  begin perform public.reply_enquiry(id,'Encore moi'); raise exception 'TEST: fourth message in a row accepted';
  exception when others then if sqlerrm<>'enquiry_wait' then raise; end if; end;
  if (public.enquiry_thread(id)->>'wait')::boolean is not true then raise exception 'TEST: wait not announced'; end if;
  begin perform public.reply_enquiry(id,'   '); raise exception 'TEST: empty message accepted';
  exception when others then if sqlerrm<>'enquiry_length' then raise; end if; end;
  begin perform public.reply_enquiry(id,repeat('x',1001)); raise exception 'TEST: too long message accepted';
  exception when others then if sqlerrm<>'enquiry_length' then raise; end if; end;
  -- A professional still cannot start anything: no thread without a member's request.
  begin perform public.reply_enquiry(gen_random_uuid(),'Bonsoir'); raise exception 'TEST: reply to a thread that does not exist';
  exception when others then if sqlerrm<>'enquiry_missing' then raise; end if; end;
end $$;

-- The member sees the answers, answers back, and the professional may write again.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009602","role":"authenticated"}',true);
do $$ declare l jsonb; t jsonb; id uuid := current_setting('px.a')::uuid;
begin
  l := public.my_enquiries();
  if jsonb_array_length(l)<>1 or l->0->>'with'<>'Studio Test' or (l->0->>'unread')::int<>3 or (l->0->>'open')::boolean is not true then raise exception 'TEST: member list wrong %', l; end if;
  if l->0->>'last'<>'Dites-moi.' or (l->0->>'last_mine')::boolean then raise exception 'TEST: last message wrong'; end if;
  t := public.enquiry_thread(id);
  if t->>'role'<>'member' or t->>'with'<>'Studio Test' or jsonb_array_length(t->'messages')<>4 or (t->'messages'->0->>'mine')::boolean is not true then raise exception 'TEST: member thread wrong %', t; end if;
  if t::text like '%00000000-0000-4000-8000-000000009601%' then raise exception 'TEST: pro id leaked to the member'; end if;
  if (public.my_enquiries()->0->>'unread')::int<>0 then raise exception 'TEST: member thread not marked read'; end if;
  perform public.reply_enquiry(id,'Parfait, je réserve.');
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009601","role":"authenticated"}',true);
do $$ declare id uuid := current_setting('px.a')::uuid;
begin
  if (select (e->>'unread')::int from jsonb_array_elements(public.my_pro_profile()->'enquiries') e where e->>'id'=id::text)<>1 then raise exception 'TEST: member answer not counted unread'; end if;
  perform public.reply_enquiry(id,'Merci, à bientôt.');
end $$;

-- Somebody else reads nothing and writes nothing.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009605","role":"authenticated"}',true);
do $$ declare id uuid := current_setting('px.a')::uuid;
begin
  begin perform public.enquiry_thread(id); raise exception 'TEST: outsider read a thread';
  exception when others then if sqlerrm<>'enquiry_missing' then raise; end if; end;
  begin perform public.reply_enquiry(id,'Coucou'); raise exception 'TEST: outsider wrote in a thread';
  exception when others then if sqlerrm<>'enquiry_missing' then raise; end if; end;
  begin perform public.close_enquiry(id); raise exception 'TEST: outsider closed a thread';
  exception when others then if sqlerrm<>'enquiry_missing' then raise; end if; end;
  begin perform public.enquiry_block(id); raise exception 'TEST: outsider blocked through a thread';
  exception when others then if sqlerrm<>'enquiry_missing' then raise; end if; end;
  begin perform public.enquiry_report(id,'other',null); raise exception 'TEST: outsider reported through a thread';
  exception when others then if sqlerrm<>'enquiry_missing' then raise; end if; end;
  if jsonb_array_length(public.my_enquiries())<>0 then raise exception 'TEST: outsider has requests'; end if;
  begin perform count(*) from public.enquiry_messages; raise exception 'TEST: messages table readable by a client';
  exception when insufficient_privilege then null; end;
end $$;

-- The member closes: nobody writes any more, the thread stays readable.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009602","role":"authenticated"}',true);
do $$ declare id uuid := current_setting('px.a')::uuid;
begin
  perform public.close_enquiry(id);
  begin perform public.reply_enquiry(id,'Encore une question'); raise exception 'TEST: wrote in a closed thread';
  exception when others then if sqlerrm<>'enquiry_closed' then raise; end if; end;
  if (public.enquiry_thread(id)->>'open')::boolean or (public.enquiry_thread(id)->>'closed_by_me')::boolean is not true then raise exception 'TEST: closed state wrong'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009601","role":"authenticated"}',true);
do $$ declare id uuid := current_setting('px.a')::uuid;
begin
  begin perform public.reply_enquiry(id,'Une dernière chose'); raise exception 'TEST: pro wrote in a closed thread';
  exception when others then if sqlerrm<>'enquiry_closed' then raise; end if; end;
  if jsonb_array_length(public.enquiry_thread(id)->'messages')<>6 then raise exception 'TEST: closed thread no longer readable'; end if;
  -- The professional blocks B from the thread, without ever holding B's identifier.
  perform public.enquiry_block(current_setting('px.b')::uuid);
  if jsonb_array_length(public.my_pro_profile()->'enquiries')<>2 then raise exception 'TEST: blocked request still listed'; end if;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009603","role":"authenticated"}',true);
do $$ declare id uuid := current_setting('px.b')::uuid;
begin
  begin perform public.reply_enquiry(id,'Alors ?'); raise exception 'TEST: wrote through a block';
  exception when others then if sqlerrm<>'enquiry_closed' then raise; end if; end;
  if jsonb_array_length(public.my_enquiries())<>0 then raise exception 'TEST: blocked thread still listed for the member'; end if;
end $$;
-- C reports the professional from the thread: the report carries the thread, and C no longer hears from the professional.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009601","role":"authenticated"}',true);
select public.reply_enquiry(current_setting('px.c')::uuid,'Tarifs sur demande.');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009604","role":"authenticated"}',true);
select public.enquiry_report(current_setting('px.c')::uuid,'inappropriate','Réponse déplacée');
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009601","role":"authenticated"}',true);
do $$ begin
  begin perform public.reply_enquiry(current_setting('px.c')::uuid,'Pardon ?'); raise exception 'TEST: wrote after being reported';
  exception when others then if sqlerrm<>'enquiry_closed' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009609","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare r jsonb;
begin
  select x into r from jsonb_array_elements(public.admin_reports('open')) x where x->>'details'='Réponse déplacée';
  if r is null then raise exception 'TEST: report not listed'; end if;
  if jsonb_array_length(r->'conversation')<>2 or (r->'conversation'->0->>'from_reported')::boolean or (r->'conversation'->1->>'from_reported')::boolean is not true then raise exception 'TEST: thread not attached to the report %', r->'conversation'; end if;
end $$;
reset role;

do $$ declare ida uuid := current_setting('px.a')::uuid;
begin
  -- Each new message announces itself once while unread, in the "messages" group, without any text of the message.
  if (select count(*) from public.notifications where user_id='00000000-0000-4000-8000-000000009602' and kind='message_received' and payload->>'key'='enquiry:'||ida::text)<>2 then raise exception 'TEST: member notifications wrong'; end if;
  if exists(select 1 from public.notifications where payload->>'key' like 'enquiry:%' and (payload::text like '%libre le 12%' or payload::text like '%Parfait%')) then raise exception 'TEST: message text in a notification'; end if;
  if exists(select 1 from public.notifications where user_id='00000000-0000-4000-8000-000000009602' and read_at is null and payload->>'key'='enquiry:'||ida::text and created_at<(select from_read_at from public.enquiries where id=ida)) then raise exception 'TEST: notification left unread after opening the thread'; end if;
  -- Nothing here touched the dating side.
  if exists(select 1 from public.introductions where sender_id::text like '00000000-0000-4000-8000-0000000096%' or recipient_id::text like '00000000-0000-4000-8000-0000000096%') then raise exception 'TEST: an introduction was created'; end if;
  if exists(select 1 from public.conversations where a_id::text like '00000000-0000-4000-8000-0000000096%' or b_id::text like '00000000-0000-4000-8000-0000000096%') then raise exception 'TEST: a conversation was created'; end if;
  if not exists(select 1 from public.blocks where blocker_id='00000000-0000-4000-8000-000000009601' and blocked_id='00000000-0000-4000-8000-000000009603') then raise exception 'TEST: block not recorded'; end if;
  if not exists(select 1 from public.reports where enquiry_id=current_setting('px.c')::uuid and reporter_id='00000000-0000-4000-8000-000000009604') then raise exception 'TEST: report not linked to the thread'; end if;
  -- Not callable without an account, and the helpers are not callable by a client at all.
  if has_function_privilege('anon','public.reply_enquiry(uuid,text)','execute') or has_function_privilege('anon','public.enquiry_thread(uuid)','execute') or has_function_privilege('anon','public.my_enquiries()','execute') then raise exception 'TEST: open to anonymous callers'; end if;
  if has_function_privilege('authenticated','private.enquiry_open(public.enquiries)','execute') then raise exception 'TEST: helper callable by a client'; end if;
  if has_table_privilege('authenticated','public.enquiry_messages','select') or has_table_privilege('anon','public.enquiry_messages','select') then raise exception 'TEST: messages table open'; end if;
end $$;

-- A sheet that is no longer approved, or a suspended account, closes its threads for writing.
update public.enquiries set closed_at=null, closed_by=null where id=current_setting('px.a')::uuid;
update public.pro_profiles set status='pending' where user_id='00000000-0000-4000-8000-000000009601';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009602","role":"authenticated"}',true);
do $$ begin
  begin perform public.reply_enquiry(current_setting('px.a')::uuid,'Toujours là ?'); raise exception 'TEST: wrote to a sheet no longer approved';
  exception when others then if sqlerrm<>'enquiry_closed' then raise; end if; end;
end $$;
reset role;
update public.pro_profiles set status='approved' where user_id='00000000-0000-4000-8000-000000009601';
insert into private.account_restrictions(user_id,suspended) values('00000000-0000-4000-8000-000000009601',true)
  on conflict (user_id) do update set suspended=true;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009602","role":"authenticated"}',true);
do $$ begin
  begin perform public.reply_enquiry(current_setting('px.a')::uuid,'Toujours là ?'); raise exception 'TEST: wrote to a suspended account';
  exception when others then if sqlerrm<>'enquiry_closed' then raise; end if; end;
end $$;
reset role;
-- A block made anywhere else in the app closes the thread too.
delete from private.account_restrictions where user_id='00000000-0000-4000-8000-000000009601';
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009602","role":"authenticated"}',true);
select public.reply_enquiry(current_setting('px.a')::uuid,'Une question encore.');
select public.block_member('00000000-0000-4000-8000-000000009601');
reset role;
do $$ begin
  if exists(select 1 from public.enquiries where id=current_setting('px.a')::uuid and closed_at is null) then raise exception 'TEST: block elsewhere left the thread open'; end if;
end $$;
rollback;
select 'PASS: exchange between a member and a professional' as result;
