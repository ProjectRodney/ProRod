-- Checks for db/2026-11-17-pro-accounts.sql. Transaction-only fixtures; everything is rolled back.
-- Expected last line: PASS: professional accounts …
begin;
-- P = professional (approved sheet), A and B = personal, C = personal who becomes pro. All in the same venue with a pass.
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009401','pa-p@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009402','pa-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009403','pa-b@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009404','pa-c@example.invalid',now(),false);
insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,account_type)
select u.id, 'Membre '||right(u.id::text,2), '1995-01-01', 'fr', 'Bio de test', 'u/'||u.id||'/a.jpg',
       case when right(u.id::text,2)='01' then 'pro' else 'personal' end
from auth.users u where u.email like 'pa-%@example.invalid';
insert into public.pro_profiles(user_id,business_name,category,pitch,status) values
('00000000-0000-4000-8000-000000009401','Studio Test','DJ','Mixes pour vos soirées.','approved');
insert into private.venues(id,name,category,duration_minutes) values ('00000000-0000-4000-8000-000000009411','Pro test','test',180);
insert into private.venue_invites(id,venue_id,token_hash,expires_at) values
('00000000-0000-4000-8000-000000009421','00000000-0000-4000-8000-000000009411',encode(extensions.digest(repeat('p',40),'sha256'),'hex'),now()+interval '1 day');
insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
select u.id,'00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009421','Pro test',now()+interval '2 hours'
from auth.users u where u.email like 'pa-%@example.invalid';
insert into public.passes(user_id,venue_id,kind,simulated,amount_cents,expires_at)
select u.id,'00000000-0000-4000-8000-000000009411','venue_pass',true,0,now()+interval '1 day' from auth.users u where u.email like 'pa-%@example.invalid';
-- Before the change: P had a conversation with A, and B had sent P a hello still waiting.
insert into public.introductions(id,sender_id,recipient_id,venue_id,session_id,message,status)
select '00000000-0000-4000-8000-000000009431','00000000-0000-4000-8000-000000009402','00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009411',s.id,'Bonjour','accepted'
from public.venue_sessions s where s.user_id='00000000-0000-4000-8000-000000009402';
insert into public.conversations(id,introduction_id,venue_id,a_id,b_id) values
('00000000-0000-4000-8000-000000009441','00000000-0000-4000-8000-000000009431','00000000-0000-4000-8000-000000009411','00000000-0000-4000-8000-000000009402','00000000-0000-4000-8000-000000009401');
insert into public.messages(conversation_id,sender_id,body) values ('00000000-0000-4000-8000-000000009441','00000000-0000-4000-8000-000000009402','Bonjour');
insert into public.introductions(id,sender_id,recipient_id,venue_id,session_id,message)
select '00000000-0000-4000-8000-000000009432','00000000-0000-4000-8000-000000009403','00000000-0000-4000-8000-000000009401','00000000-0000-4000-8000-000000009411',s.id,'Salut'
from public.venue_sessions s where s.user_id='00000000-0000-4000-8000-000000009403';
update private.app_settings set value='true' where key='simulation';
set local role authenticated;

-- The professional: stays pro, does not see the meeting list, cannot say hello, accept one, or write in a conversation.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009401","role":"authenticated"}',true);
do $$ begin
  begin perform public.set_account_type('personal'); raise exception 'TEST: pro switched back to personal';
  exception when others then if sqlerrm<>'pro_locked' then raise; end if; end;
  if public.my_account_type()<>'pro' then raise exception 'TEST: type changed'; end if;
  begin perform count(*) from public.venue_members(); raise exception 'TEST: pro sees the meeting list';
  exception when others then if sqlerrm<>'pro_account_dating' then raise; end if; end;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000009402','Bonjour'); raise exception 'TEST: pro sent a hello';
  exception when others then if sqlerrm<>'pro_account_dating' then raise; end if; end;
  begin perform public.respond_introduction('00000000-0000-4000-8000-000000009432',true,'Avec plaisir'); raise exception 'TEST: pro accepted a hello';
  exception when others then if sqlerrm<>'pro_account_dating' then raise; end if; end;
  begin perform public.send_message('00000000-0000-4000-8000-000000009441','Un verre ce soir ?'); raise exception 'TEST: pro wrote in a conversation';
  exception when others then if sqlerrm<>'pro_account_dating' then raise; end if; end;
  if (select count(*) from public.conversation_messages('00000000-0000-4000-8000-000000009441'))<>1 then raise exception 'TEST: history no longer readable'; end if;
  if public.respond_introduction('00000000-0000-4000-8000-000000009432',false)->>'status'<>'declined' then raise exception 'TEST: pro cannot decline'; end if;
end $$;

-- A personal member: sees only personal members, cannot say hello to the pro or write to it, can still send an enquiry.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009402","role":"authenticated"}',true);
do $$ begin
  if exists(select 1 from public.venue_members() m where m.user_id='00000000-0000-4000-8000-000000009401') then raise exception 'TEST: pro in the meeting list'; end if;
  if not exists(select 1 from public.venue_members() m where m.user_id='00000000-0000-4000-8000-000000009403') then raise exception 'TEST: personal member missing'; end if;
  begin perform public.send_introduction('00000000-0000-4000-8000-000000009401','Bonjour'); raise exception 'TEST: hello sent to a pro';
  exception when others then if sqlerrm<>'not_co_present' then raise; end if; end;
  begin perform public.send_message('00000000-0000-4000-8000-000000009441','Tu es libre ?'); raise exception 'TEST: message to a pro';
  exception when others then if sqlerrm<>'pro_conversation_closed' then raise; end if; end;
  perform public.send_enquiry('00000000-0000-4000-8000-000000009401','Disponible samedi pour une soirée ?',null);
  if public.send_introduction('00000000-0000-4000-8000-000000009403','Bonjour')->>'status'<>'pending' then raise exception 'TEST: personal hello refused'; end if;
end $$;

-- A personal account may become pro, then cannot go back.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009404","role":"authenticated"}',true);
do $$ begin
  perform public.set_account_type('pro');
  begin perform public.set_account_type('personal'); raise exception 'TEST: new pro switched back';
  exception when others then if sqlerrm<>'pro_locked' then raise; end if; end;
end $$;

-- The helper is not callable from the app.
reset role; set local role anon;
do $$ begin
  begin perform private.is_pro('00000000-0000-4000-8000-000000009401'); raise exception 'TEST: anonymous call accepted';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: professional accounts (locked type, out of the meeting list, no hello sent, received or accepted, no new message, history readable, decline allowed, enquiries kept, personal hellos unchanged, anonymous denial)' as result;
rollback;
