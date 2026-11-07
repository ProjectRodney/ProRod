-- P.Rod migration of 7 November 2026: a venue pass counts only while it is valid.
-- Before: needs_pass accepted any pass that expired after the conversation began, so a pass from an earlier visit
-- unlocked writing on every later visit; the inbox preview and the data export also returned replies hidden behind the pass.
-- After: writing needs a pass valid now (send_message → pass_required); a message from the other person is readable when
-- a pass of the reader covered the moment it was sent (pass expiry ≥ message time), hidden otherwise, in the thread, the inbox
-- preview and the data export alike. Run once in the Supabase SQL editor of the ProRod project, then section 3 of
-- db/verify-accounts-and-venues.sql.

CREATE OR REPLACE FUNCTION private.needs_pass(p_conv conversations, p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select (private.setting('pass_rule') #>> '{}')='everyone'
     and not exists(select 1 from public.passes p where p.user_id=p_uid and p.venue_id=p_conv.venue_id and p.status='active' and p.kind='venue_pass' and p.expires_at>now())
$function$;

CREATE OR REPLACE FUNCTION private.message_hidden(p_conv public.conversations, p_uid uuid, p_sender uuid, p_at timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p_sender<>p_uid and (private.setting('pass_rule') #>> '{}')='everyone'
     and not exists(select 1 from public.passes p where p.user_id=p_uid and p.venue_id=p_conv.venue_id and p.status='active' and p.kind='venue_pass' and p.expires_at>=p_at)
$function$;

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
  return jsonb_build_object('id',conv.id,'closed_at',conv.closed_at,'closed_by_me',conv.closed_by=uid,'with',private.member_card(other),'venue',(select name from private.venues v where v.id=conv.venue_id),'venue_id',conv.venue_id,'locked',locked,'live',live,'messages',msgs,
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
  select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'created_at',c.created_at,'closed_at',c.closed_at,'closed_by_me',c.closed_by=uid,'venue',(select name from private.venues v where v.id=c.venue_id),
      'with',private.member_card(case when c.a_id=uid then c.b_id else c.a_id end),
      'last',(select jsonb_build_object('body',case when private.message_hidden(c,uid,m.sender_id,m.created_at) then null else m.body end,'locked',private.message_hidden(c,uid,m.sender_id,m.created_at),'mine',m.sender_id=uid,'created_at',m.created_at) from public.messages m where m.conversation_id=c.id order by m.created_at desc limit 1),
      'unread',(select count(*) from public.messages m where m.conversation_id=c.id and m.sender_id<>uid and m.created_at>coalesce((select r.read_at from public.conversation_reads r where r.conversation_id=c.id and r.user_id=uid),'epoch'::timestamptz)))
    order by coalesce((select max(m.created_at) from public.messages m where m.conversation_id=c.id),c.created_at) desc),'[]'::jsonb)
  into convs from public.conversations c where (c.a_id=uid or c.b_id=uid) and not private.blocked_between(uid,case when c.a_id=uid then c.b_id else c.a_id end);
  return jsonb_build_object('received',received,'sent',sent,'conversations',convs);
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
    'blocks',(select coalesce(jsonb_agg(jsonb_build_object('blocked',(select display_name from public.profiles where user_id=b.blocked_id),'created_at',b.created_at)),'[]'::jsonb) from public.blocks b where b.blocker_id=uid),
    'reports_made',(select coalesce(jsonb_agg(jsonb_build_object('category',r.category,'details',r.details,'created_at',r.created_at,'status',r.status)),'[]'::jsonb) from public.reports r where r.reporter_id=uid),
    'notifications',(select coalesce(jsonb_agg(jsonb_build_object('kind',n.kind,'created_at',n.created_at,'read_at',n.read_at)),'[]'::jsonb) from public.notifications n where n.user_id=uid));
end $function$;

revoke all on function private.message_hidden(public.conversations,uuid,uuid,timestamptz) from public, anon, authenticated;
