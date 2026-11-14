-- Checks for db/2026-11-14-feedback-digest.sql. Transaction-only fixtures; everything is rolled back,
-- including the e-mail request, so no e-mail leaves.
begin;
insert into auth.users(id,email,email_confirmed_at,is_anonymous) values
('00000000-0000-4000-8000-000000009501','fd-a@example.invalid',now(),false),
('00000000-0000-4000-8000-000000009509','fd-admin@example.invalid',now(),false);
update private.app_settings set value='"digest@example.invalid"' where key='feedback_email';
update private.app_settings set value=coalesce(nullif(value,'null'::jsonb),'"sender@example.invalid"'::jsonb) where key='feedback_sender';
update public.feedback set emailed_at=coalesce(emailed_at,now());
insert into public.feedback(user_id,account_type,score,change_text,bug,bug_text,context,created_at) values
('00000000-0000-4000-8000-000000009501','personal',4,'Plus de temps pour répondre.',false,null,'{"minutes":"65","installed":"false"}',now()-interval '2 hours'),
('00000000-0000-4000-8000-000000009501','personal',2,null,true,'Le scanner est resté noir.','{"minutes":"80","installed":"true"}',now()-interval '30 hours');
-- Real feedback may already be there: the expected numbers are counted, not assumed.
select set_config('fdtest.day',(select count(*) from public.feedback where created_at>now()-interval '24 hours')::text,true);
select set_config('fdtest.all',(select least(count(*),300) from public.feedback)::text,true);
set local role authenticated;

-- A member cannot send the feedback.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009501","role":"authenticated"}',true);
do $$ begin
  begin perform public.admin_send_feedback(); raise exception 'TEST: a member sent the feedback';
  exception when others then if sqlerrm<>'admin_required' then raise; end if; end;
end $$;

-- The automatic e-mail per feedback is off.
reset role;
do $$ begin
  if private.send_feedback_emails()<>0 then raise exception 'TEST: automatic e-mails still leave'; end if;
  if (select count(*) from public.feedback where emailed_at is null)<>2 then raise exception 'TEST: automatic sending marked the feedback'; end if;
end $$;
set local role authenticated;

-- The administrator sends the last 24 hours (one feedback), then everything.
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009509","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
do $$ declare r jsonb; begin
  begin perform public.admin_send_feedback(0); raise exception 'TEST: zero hours accepted';
  exception when others then if sqlerrm<>'invalid_duration' then raise; end if; end;
  r := public.admin_send_feedback(24);
  if (r->>'count')::int<>current_setting('fdtest.day')::int or r->>'to'<>'digest@example.invalid' then raise exception 'TEST: last 24 hours gave %, expected %', r, current_setting('fdtest.day'); end if;
  r := public.admin_send_feedback();
  if (r->>'count')::int<>current_setting('fdtest.all')::int then raise exception 'TEST: everything gave %, expected %', r, current_setting('fdtest.all'); end if;
  if current_setting('fdtest.all')::int<=current_setting('fdtest.day')::int then raise exception 'TEST: the older feedback is missing from the count'; end if;
end $$;
reset role;
do $$ begin
  if exists(select 1 from public.feedback where emailed_at is null) then raise exception 'TEST: sent feedback not marked as sent'; end if;
  if not exists(select 1 from private.admin_actions where action='feedback_sent') then raise exception 'TEST: sending is not in the admin journal'; end if;
  -- Without a destination address, the button says so instead of pretending.
  update private.app_settings set value='null' where key='feedback_email';
  perform set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000009509","role":"authenticated","aal":"aal2","app_metadata":{"prod_admin":true}}',true);
  begin perform private.admin_send_feedback(); raise exception 'TEST: sent without an address';
  exception when others then if sqlerrm<>'feedback_email_not_configured' then raise; end if; end;
end $$;
select 'PASS: feedback on demand' as result;
rollback;
