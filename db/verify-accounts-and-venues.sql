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
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin perform public.save_profile('Minor',(current_date-interval '17 years')::date,'en',true); raise exception 'TEST: minor accepted'; exception when others then if sqlerrm <> 'adults_only' then raise; end if; end;
end $$;
select public.save_profile('Alex','2000-01-01','en',true);
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
  begin perform public.join_venue(repeat('a',40)); raise exception 'TEST: ended invitation reused'; exception when others then if sqlerrm<>'invitation_already_used' then raise; end if; end;
end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ begin
  if (select count(*) from public.profiles)<>0 or (select count(*) from public.venue_sessions)<>0 then raise exception 'TEST: other account data exposed'; end if;
  begin perform public.join_venue(repeat('a',40)); raise exception 'TEST: incomplete profile joined'; exception when others then if sqlerrm<>'profile_required' then raise; end if; end;
end $$;
select public.save_profile('Maya','2000-01-01','fr',true);
select public.join_venue(repeat('a',40));
select public.leave_venue();
do $$ begin if exists(select 1 from public.venue_sessions where ended_at is null) then raise exception 'TEST: leave failed'; end if; end $$;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ begin
  begin perform public.save_profile('Nope','2000-01-01','en',true); raise exception 'TEST: unconfirmed accepted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
update public.venue_sessions set started_at=now()-interval '2 hours', expires_at=now()-interval '1 second' where user_id='00000000-0000-4000-8000-000000000001' and ended_at is null;
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"00000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ begin
  begin perform public.join_venue(repeat('b',40)); raise exception 'TEST: expired session renewed'; exception when others then if sqlerrm<>'invitation_already_used' then raise; end if; end;
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
  begin perform public.save_profile('Alex','2000-01-01','en',true); raise exception 'TEST: suspended account allowed'; exception when insufficient_privilege then null; end;
end $$;
set local role anon;
do $$ begin
  begin perform public.preview_venue(repeat('a',40)); raise exception 'TEST: anonymous RPC permitted'; exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'PASS: profile ownership, verified accounts, age, server session controls, venue switching, invitation reuse, anonymous denial' as result;
rollback;
