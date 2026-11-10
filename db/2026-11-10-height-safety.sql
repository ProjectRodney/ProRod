-- UPZONE, 10 November 2026 (meeting with the client): height on the profile, and safety.
-- Run once in the Supabase SQL editor of the ProRod project.
-- • Height (cm, optional, 120–230) shown on the profile card and in the venue list.
-- • A report automatically blocks the reported person for the reporter (they can no longer write or introduce
--   themselves); new reason « insults / vulgar language ».
-- • Moderation can warn a member (notification asking for respect), besides the existing suspension.
-- • Ending a conversation records a reason (kept as proof); the other person sees it in neutral words.

alter table public.profiles add column if not exists height_cm smallint;
alter table public.profiles drop constraint if exists profiles_height_cm_check;
alter table public.profiles add constraint profiles_height_cm_check check (height_cm is null or height_cm between 120 and 230);

alter table public.conversations add column if not exists closed_reason text;
alter table public.conversations drop constraint if exists conversations_closed_reason_check;
alter table public.conversations add constraint conversations_closed_reason_check check (closed_reason is null or closed_reason in ('not_available','left_venue','not_interested','other'));

alter table public.reports drop constraint if exists reports_category_check;
alter table public.reports add constraint reports_category_check check (category in ('harassment','insults','inappropriate','impersonation','prohibited','other'));

alter table public.notifications drop constraint if exists notifications_kind_check;
alter table public.notifications add constraint notifications_kind_check check (kind in ('introduction_received','reply_received','message_received','conversation_closed','report_handled','account_restricted','account_reinstated','account_warned'));

create or replace function private.set_height(p_cm integer) returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  if exists(select 1 from public.profiles where user_id=uid and account_type='venue') then raise exception 'person_required'; end if;
  if p_cm is not null and p_cm not between 120 and 230 then raise exception 'invalid_height'; end if;
  update public.profiles set height_cm=p_cm, updated_at=now() where user_id=uid;
  if not found then raise exception 'profile_required'; end if;
  return jsonb_build_object('height_cm',p_cm);
end $$;
create or replace function public.set_height(p_cm integer) returns jsonb language sql set search_path = '' as $$ select private.set_height(p_cm) $$;

create or replace function private.end_conversation(p_id uuid, p_reason text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); conv public.conversations;
begin
  if p_reason is null or p_reason not in ('not_available','left_venue','not_interested','other') then raise exception 'invalid_reason'; end if;
  update public.conversations set closed_at=now(), closed_by=uid, closed_reason=p_reason where id=p_id and (a_id=uid or b_id=uid) and closed_at is null returning * into conv;
  if found then perform private.notify(case when conv.a_id=uid then conv.b_id else conv.a_id end,'conversation_closed',jsonb_build_object('conversation',conv.id,'reason',p_reason),conv.id::text); end if;
end $$;
create or replace function public.end_conversation(p_id uuid, p_reason text) returns void language sql set search_path = '' as $$ select private.end_conversation(p_id,p_reason) $$;

create or replace function private.admin_warn_member(p_report uuid, p_message text) returns void language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_admin(); row public.reports;
begin
  select * into row from public.reports where id=p_report;
  if not found then raise exception 'report_missing'; end if;
  perform private.notify(row.reported_id,'account_warned',jsonb_build_object('message',coalesce(nullif(left(btrim(p_message),300),''),'')),null);
  update public.reports set status=case when status='open' then 'actioned' else status end, decided_at=coalesce(decided_at,now()), decided_by=coalesce(decided_by,uid) where id=p_report;
  perform private.log_admin(uid,'member_warned',row.reported_id::text,jsonb_build_object('report',p_report));
end $$;
create or replace function public.admin_warn_member(p_report uuid, p_message text) returns void language sql set search_path = '' as $$ select private.admin_warn_member(p_report,p_message) $$;

revoke all on function private.set_height(integer), private.end_conversation(uuid,text), private.admin_warn_member(uuid,text) from public, anon;
revoke all on function public.set_height(integer), public.end_conversation(uuid,text), public.admin_warn_member(uuid,text) from public, anon;
grant execute on function private.set_height(integer), private.end_conversation(uuid,text), private.admin_warn_member(uuid,text) to authenticated;
grant execute on function public.set_height(integer), public.end_conversation(uuid,text), public.admin_warn_member(uuid,text) to authenticated, service_role;

-- The venue list gains the height column: its return type changes, so both functions are recreated.
drop function if exists public.venue_members();
drop function if exists private.venue_members();
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint)
 language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; wants text;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select p.interested_in into wants from public.profiles p where p.user_id=uid;
  return query
    select p.user_id, p.display_name, date_part('year', age(p.birth_date))::integer, p.bio, p.avatar_path, s.started_at, p.height_cm
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type<>'venue' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
      and (wants is null or wants='everyone' or (wants='women' and p.gender='woman') or (wants='men' and p.gender='man'))
    order by s.started_at desc;
end $function$;
create or replace function public.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint)
 language sql set search_path to '' as $function$ select * from private.venue_members() $function$;
revoke all on function private.venue_members(), public.venue_members() from public, anon;
grant execute on function private.venue_members() to authenticated;
grant execute on function public.venue_members() to authenticated, service_role;

CREATE OR REPLACE FUNCTION private.member_card(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'age',date_part('year',age(p.birth_date))::int,'bio',p.bio,'avatar_path',p.avatar_path,'height_cm',p.height_cm)
  from public.profiles p where p.user_id=p_user
$function$;

CREATE OR REPLACE FUNCTION private.report_member(p_user uuid, p_category text, p_details text DEFAULT NULL::text, p_conversation uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid(); row public.reports; conv public.conversations;
begin
  if uid is null then raise exception 'verified_account_required' using errcode='42501'; end if;
  if p_user is null or p_user=uid then raise exception 'invalid_recipient'; end if;
  if p_category is null or p_category not in ('harassment','insults','inappropriate','impersonation','prohibited','other') then raise exception 'invalid_category'; end if;
  if p_conversation is not null then
    select * into conv from public.conversations where id=p_conversation and (a_id=uid or b_id=uid);
    if not found then p_conversation := null; end if;
  end if;
  if (select count(*) from public.reports r where r.reporter_id=uid and r.created_at>now()-interval '1 day')>=20 then raise exception 'report_limit'; end if;
  insert into public.reports(reporter_id,reported_id,category,details,conversation_id,venue_id) values(uid,p_user,p_category,nullif(left(p_details,1000),''),p_conversation,coalesce(conv.venue_id,(private.live_session(uid)).venue_id)) returning * into row;
  -- Decision of 10 November 2026: whoever reports someone no longer receives anything from them (automatic block,
  -- conversations closed, pending introductions declined). Moderation then warns or suspends.
  perform private.block_member(p_user);
  return jsonb_build_object('id',row.id,'created_at',row.created_at,'blocked',true);
end $function$;

CREATE OR REPLACE FUNCTION private.conversation_messages(p_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); conv public.conversations; other uuid; msgs jsonb; mine_count int; theirs_count int; locked boolean; live boolean;
begin
  select * into conv from public.conversations where id=p_id and (a_id=uid or b_id=uid);
  if not found then raise exception 'conversation_unavailable'; end if;
  other := case when conv.a_id=uid then conv.b_id else conv.a_id end;
  if private.blocked_between(uid,other) then raise exception 'conversation_unavailable'; end if;
  locked := private.needs_pass(conv,uid); live := private.co_present_in(conv,uid);
  select coalesce(jsonb_agg(jsonb_build_object('id',m.id,'body',case when private.message_hidden(conv,uid,m.sender_id,m.created_at) then null else m.body end,'locked',private.message_hidden(conv,uid,m.sender_id,m.created_at),'mine',m.sender_id=uid,'created_at',m.created_at) order by m.created_at),'[]'::jsonb) into msgs from public.messages m where m.conversation_id=conv.id;
  select count(*) filter (where sender_id=uid), count(*) filter (where sender_id=other) into mine_count, theirs_count from public.messages where conversation_id=conv.id;
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid) on conflict(conversation_id,user_id) do update set read_at=now();
  update public.notifications set read_at=now() where user_id=uid and read_at is null and kind in ('reply_received','message_received','conversation_closed') and (payload->>'key'=conv.id::text or payload->>'key'=conv.id::text||':meeting');
  return jsonb_build_object('id',conv.id,'closed_at',conv.closed_at,'closed_by_me',conv.closed_by=uid,'closed_reason',conv.closed_reason,'with',private.member_card(other),'venue',(select name from private.venues v where v.id=conv.venue_id),'venue_id',conv.venue_id,'locked',locked,'live',live,'messages',msgs,
    'meeting',private.meeting_state(conv,uid)||jsonb_build_object('can_ask',conv.closed_at is null and live and mine_count>=2 and theirs_count>=2));
end $function$;

CREATE OR REPLACE FUNCTION private.my_inbox()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); received jsonb; sent jsonb; convs jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'message',i.message,'created_at',i.created_at,'venue',(select name from private.venues v where v.id=i.venue_id),'from',private.member_card(i.sender_id)) order by i.created_at desc),'[]'::jsonb)
  into received from public.introductions i where i.recipient_id=uid and i.status='pending' and not private.blocked_between(uid,i.sender_id)
    and not exists(select 1 from private.account_restrictions r where r.user_id=i.sender_id and r.suspended);
  select coalesce(jsonb_agg(jsonb_build_object('id',i.id,'message',i.message,'created_at',i.created_at,'status',case when i.status='accepted' then 'accepted' else 'pending' end,'to',private.member_card(i.recipient_id)) order by i.created_at desc),'[]'::jsonb)
  into sent from public.introductions i where i.sender_id=uid and i.created_at>now()-interval '7 days' and not exists(select 1 from public.conversations c where c.introduction_id=i.id);
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'closed_at',c.closed_at,'closed_by_me',c.closed_by=uid,'closed_reason',c.closed_reason,'venue',(select name from private.venues v where v.id=c.venue_id),
      'with',private.member_card(case when c.a_id=uid then c.b_id else c.a_id end),
      'last',(select jsonb_build_object('body',case when private.message_hidden(c,uid,m.sender_id,m.created_at) then null else m.body end,'locked',private.message_hidden(c,uid,m.sender_id,m.created_at),'mine',m.sender_id=uid,'created_at',m.created_at) from public.messages m where m.conversation_id=c.id order by m.created_at desc limit 1),
      'unread',(select count(*) from public.messages m where m.conversation_id=c.id and m.sender_id<>uid and m.created_at>coalesce((select r.read_at from public.conversation_reads r where r.conversation_id=c.id and r.user_id=uid),'epoch'::timestamptz)))
    order by coalesce((select max(m.created_at) from public.messages m where m.conversation_id=c.id),c.created_at) desc),'[]'::jsonb)
  into convs from public.conversations c where (c.a_id=uid or c.b_id=uid) and not private.blocked_between(uid,case when c.a_id=uid then c.b_id else c.a_id end);
  return jsonb_build_object('received',received,'sent',sent,'conversations',convs);
end $function$;

notify pgrst, 'reload schema';
