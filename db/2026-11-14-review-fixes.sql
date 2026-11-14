-- Fixes from the security review of 14 November 2026. Nothing changes for normal use of the app.
-- 1. Blocking or reporting is possible only towards someone the member has met: an exchange between them
--    (hello or enquiry), or a visit to the same place at the same time in the last 7 days. Before, any account
--    identifier was accepted.
-- 2. The data export gives the name of a blocked person only when the two exchanged a hello or an enquiry.
--    Before, blocking an identifier and exporting revealed that person's name without a pass.
-- 3. Five hellos per place per 12 hours. Before, leaving and scanning again gave five more.
begin;

CREATE OR REPLACE FUNCTION private.exchanged_with(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select a is not null and b is not null and a <> b and (
    exists(select 1 from public.introductions i where (i.sender_id=a and i.recipient_id=b) or (i.sender_id=b and i.recipient_id=a))
    or exists(select 1 from public.enquiries e where (e.from_id=a and e.pro_id=b) or (e.from_id=b and e.pro_id=a)))
$function$;

CREATE OR REPLACE FUNCTION private.has_met(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select private.exchanged_with(a,b) or exists(
    select 1 from public.venue_sessions x join public.venue_sessions y on x.venue_id=y.venue_id
    where x.user_id=a and y.user_id=b
      and x.started_at < coalesce(y.ended_at,y.expires_at) and y.started_at < coalesce(x.ended_at,x.expires_at)
      and greatest(x.started_at,y.started_at) > now()-interval '7 days')
$function$;
revoke all on function private.exchanged_with(uuid, uuid) from public, anon, authenticated;
revoke all on function private.has_met(uuid, uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.block_member(p_user uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'verified_account_required' using errcode='42501'; end if;
  if p_user is null or p_user=uid then raise exception 'invalid_recipient'; end if;
  if not private.has_met(uid,p_user) then raise exception 'invalid_recipient'; end if;
  insert into public.blocks(blocker_id,blocked_id) values(uid,p_user) on conflict do nothing;
  update public.conversations set closed_at=now(), closed_by=uid where closed_at is null and ((a_id=uid and b_id=p_user) or (a_id=p_user and b_id=uid));
  update public.introductions set status='declined', responded_at=now() where status='pending' and ((sender_id=uid and recipient_id=p_user) or (sender_id=p_user and recipient_id=uid));
end $function$;

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
  if not private.has_met(uid,p_user) then raise exception 'invalid_recipient'; end if;
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

CREATE OR REPLACE FUNCTION private.my_data_export()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member();
begin
  return jsonb_build_object(
    'exported_at',now(),
    'account',(select jsonb_build_object('email',u.email,'created_at',u.created_at,'last_sign_in_at',u.last_sign_in_at) from auth.users u where u.id=uid),
    'profile',(select to_jsonb(p) from public.profiles p where p.user_id=uid),
    'venue_sessions',(select coalesce(jsonb_agg(jsonb_build_object('venue',s.venue_name,'started_at',s.started_at,'expires_at',s.expires_at,'ended_at',s.ended_at) order by s.started_at),'[]'::jsonb) from public.venue_sessions s where s.user_id=uid),
    'introductions_sent',(select coalesce(jsonb_agg(jsonb_build_object('to',(select display_name from public.profiles where user_id=i.recipient_id),'message',i.message,'created_at',i.created_at,'status',case when i.status='accepted' then 'accepted' else 'pending' end) order by i.created_at),'[]'::jsonb) from public.introductions i where i.sender_id=uid),
    'introductions_received',(select coalesce(jsonb_agg(jsonb_build_object('from',(select display_name from public.profiles where user_id=i.sender_id),'message',i.message,'created_at',i.created_at,'status',i.status) order by i.created_at),'[]'::jsonb) from public.introductions i where i.recipient_id=uid),
    'conversations',(select coalesce(jsonb_agg(jsonb_build_object('with',(select display_name from public.profiles where user_id=case when c.a_id=uid then c.b_id else c.a_id end),'created_at',c.created_at,'closed_at',c.closed_at,
        'messages',(select coalesce(jsonb_agg(jsonb_build_object('mine',m.sender_id=uid,'body',case when private.message_hidden(c,uid,m.sender_id,m.created_at) then null else m.body end,'created_at',m.created_at) order by m.created_at),'[]'::jsonb) from public.messages m where m.conversation_id=c.id)) order by c.created_at),'[]'::jsonb) from public.conversations c where c.a_id=uid or c.b_id=uid),
    'blocks',(select coalesce(jsonb_agg(jsonb_build_object('blocked',(select display_name from public.profiles where user_id=b.blocked_id and private.exchanged_with(uid,b.blocked_id)),'created_at',b.created_at)),'[]'::jsonb) from public.blocks b where b.blocker_id=uid),
    'reports_made',(select coalesce(jsonb_agg(jsonb_build_object('category',r.category,'details',r.details,'created_at',r.created_at,'status',r.status)),'[]'::jsonb) from public.reports r where r.reporter_id=uid),
    'notifications',(select coalesce(jsonb_agg(jsonb_build_object('kind',n.kind,'created_at',n.created_at,'read_at',n.read_at)),'[]'::jsonb) from public.notifications n where n.user_id=uid));
end $function$;

create or replace function private.send_introduction(p_to uuid, p_message text) returns jsonb
 language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_member(); mine public.venue_sessions; theirs public.venue_sessions; row public.introductions;
begin
  if p_to is null or p_to=uid then raise exception 'invalid_recipient'; end if;
  if p_message is null or char_length(btrim(p_message)) not between 1 and 500 then raise exception 'message_length'; end if;
  mine := private.live_session(uid); if mine.id is null then raise exception 'no_live_session'; end if;
  if not private.venue_unlocked(uid, mine.venue_id) then raise exception 'pass_required'; end if;
  theirs := private.live_session(p_to);
  if theirs.id is null or theirs.venue_id<>mine.venue_id then raise exception 'not_co_present'; end if;
  if private.blocked_between(uid,p_to) then raise exception 'not_co_present'; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=p_to and r.suspended) then raise exception 'not_co_present'; end if;
  if exists(select 1 from public.profiles p where p.user_id=p_to and not private.profile_complete(p)) then raise exception 'not_co_present'; end if;
  if exists(select 1 from public.introductions i where i.recipient_id=uid and i.sender_id=p_to and i.session_id=theirs.id and i.status='pending') then raise exception 'introduction_received'; end if;
  if exists(select 1 from public.introductions i where i.sender_id=uid and i.recipient_id=p_to and (i.session_id=mine.id or i.status<>'accepted')) then raise exception 'introduction_exists'; end if;
  if (select count(*) from public.introductions i where i.sender_id=uid and i.venue_id=mine.venue_id and i.created_at>now()-interval '12 hours')>=5 then raise exception 'introduction_limit'; end if;
  insert into public.introductions(sender_id,recipient_id,venue_id,session_id,message) values(uid,p_to,mine.venue_id,mine.id,btrim(p_message)) returning * into row;
  perform private.notify(p_to,'introduction_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'venue',(select name from private.venues where id=mine.venue_id)),row.id::text);
  return jsonb_build_object('id',row.id,'status',row.status,'created_at',row.created_at);
end $function$;

commit;

select 'Review fixes installed' as result;
