-- UPZONE, 17 November 2026 (client decision): a professional account is for professional use only.
-- Run once in the Supabase SQL editor of the ProRod project; safe to run again. Then run db/verify-pro-accounts.sql.
--  1. A pro account stays pro: it can no longer switch itself back to personal (pro_locked). Someone who also wants to
--     meet people keeps a separate personal account and switches between the two on the phone (« Passer à … »).
--  2. The meeting side is for personal accounts only: pros are not in the venue list, cannot see it, cannot send, receive
--     or accept a « hello » (pro_account_dating). Clients still reach a pro from its sheet in « Talents ici » (enquiries,
--     unchanged), and talent alerts are unchanged.
--  3. No new message in a conversation with a pro account; its history stays readable. A pending « hello » to or from a
--     pro can still be declined, never accepted. The personal side gets pro_conversation_closed.
-- No message is read or analysed: the rule follows the account type only.

create or replace function private.is_pro(p_user uuid) returns boolean language sql stable security definer set search_path to '' as $function$
  select exists(select 1 from public.profiles p where p.user_id=p_user and p.account_type='pro')
$function$;
revoke all on function private.is_pro(uuid) from public, anon, authenticated;

CREATE OR REPLACE FUNCTION private.set_account_type(p_type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); existing text;
begin
  if p_type not in ('personal','pro','venue') then raise exception 'invalid_type'; end if;
  select account_type into existing from public.profiles where user_id=uid;
  if found then
    if (existing='venue') <> (p_type='venue') then raise exception 'type_locked'; end if;
    if existing='pro' and p_type<>'pro' then raise exception 'pro_locked'; end if;
    update public.profiles set account_type=p_type, updated_at=now() where user_id=uid;
  end if;
  insert into private.account_choices(user_id,account_type) values(uid,p_type) on conflict(user_id) do update set account_type=excluded.account_type;
  return jsonb_build_object('account_type',p_type);
end $function$;

create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean, blur_path text, blur_data text)
 language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; wants text; open boolean;
begin
  if private.is_pro(uid) then raise exception 'pro_account_dating'; end if;
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select p.interested_in into wants from public.profiles p where p.user_id=uid;
  open := private.venue_unlocked(uid, mine.venue_id);
  return query
    select case when open then p.user_id end, case when open then p.display_name end,
           case when open then date_part('year', age(p.birth_date))::integer end, case when open then p.bio end,
           case when open then p.avatar_path end, case when open then s.started_at end, case when open then p.height_cm end,
           p.department, private.age_band(p.birth_date), not open,
           null::text,
           case when not open then p.avatar_blur end
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type='personal' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
      and (wants is null or wants='everyone' or (wants='women' and p.gender='woman') or (wants='men' and p.gender='man'))
    order by case when open then s.started_at end desc nulls last, p.department nulls last, 9;
end $function$;

create or replace function private.send_introduction(p_to uuid, p_message text) returns jsonb
 language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_member(); mine public.venue_sessions; theirs public.venue_sessions; row public.introductions;
begin
  if p_to is null or p_to=uid then raise exception 'invalid_recipient'; end if;
  if private.is_pro(uid) then raise exception 'pro_account_dating'; end if;
  if private.is_pro(p_to) then raise exception 'not_co_present'; end if;
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

CREATE OR REPLACE FUNCTION private.respond_introduction(p_id uuid, p_accept boolean, p_reply text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); row public.introductions; conv public.conversations;
begin
  select * into row from public.introductions where id=p_id and recipient_id=uid for update;
  if not found or row.status<>'pending' then raise exception 'introduction_unavailable'; end if;
  if private.blocked_between(uid,row.sender_id) then raise exception 'introduction_unavailable'; end if;
  if p_accept is distinct from true then
    update public.introductions set status='declined', responded_at=now() where id=row.id;
    return jsonb_build_object('status','declined');
  end if;
  if private.is_pro(uid) then raise exception 'pro_account_dating'; end if;
  if private.is_pro(row.sender_id) then raise exception 'pro_conversation_closed'; end if;
  if p_reply is null or char_length(btrim(p_reply)) not between 1 and 2000 then raise exception 'reply_required'; end if;
  update public.introductions set status='accepted', responded_at=now() where id=row.id;
  insert into public.conversations(introduction_id,venue_id,a_id,b_id) values(row.id,row.venue_id,row.sender_id,uid) returning * into conv;
  insert into public.messages(conversation_id,sender_id,body,created_at) values(conv.id,row.sender_id,row.message,row.created_at);
  insert into public.messages(conversation_id,sender_id,body) values(conv.id,uid,btrim(p_reply));
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid);
  perform private.notify(row.sender_id,'reply_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'conversation',conv.id),conv.id::text);
  return jsonb_build_object('status','accepted','conversation_id',conv.id);
end $function$;

CREATE OR REPLACE FUNCTION private.send_message(p_conversation uuid, p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); conv public.conversations; other uuid; row public.messages;
begin
  if p_body is null or char_length(btrim(p_body)) not between 1 and 2000 then raise exception 'message_length'; end if;
  select * into conv from public.conversations where id=p_conversation and (a_id=uid or b_id=uid) for update;
  if not found then raise exception 'conversation_unavailable'; end if;
  if conv.closed_at is not null then raise exception 'conversation_closed'; end if;
  other := case when conv.a_id=uid then conv.b_id else conv.a_id end;
  if private.is_pro(uid) then raise exception 'pro_account_dating'; end if;
  if private.is_pro(other) then raise exception 'pro_conversation_closed'; end if;
  if private.blocked_between(uid,other) then raise exception 'conversation_unavailable'; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=other and r.suspended) then raise exception 'conversation_unavailable'; end if;
  if not private.co_present_in(conv,uid) then raise exception 'visit_over'; end if;
  if private.needs_pass(conv,uid) then raise exception 'pass_required'; end if;
  insert into public.messages(conversation_id,sender_id,body) values(conv.id,uid,btrim(p_body)) returning * into row;
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid) on conflict(conversation_id,user_id) do update set read_at=now();
  perform private.notify(other,'message_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'conversation',conv.id),conv.id::text);
  return jsonb_build_object('id',row.id,'created_at',row.created_at);
end $function$;

select 'Professional accounts locked to professional use' as result;
