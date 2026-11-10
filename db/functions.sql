-- UPZONE (formerly ANZIAK, P.Rod) — every database function, exported from the live project with pg_get_functiondef (schemas private and public).
-- Regenerate after each migration (docs/verification-log.md says how). Tables, indexes, RLS and storage policies: db/accounts-and-venues.sql.
-- Apply order on a fresh project: tables (db/accounts-and-venues.sql), then this file (definitions, then the grants at the end).

CREATE OR REPLACE FUNCTION private.admin_audit(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'created_at',a.created_at,'action',a.action,'target',a.target,'details',a.details,'admin',(select p.display_name from public.profiles p where p.user_id=a.admin_id)) order by a.created_at desc)
    from (select * from private.admin_actions order by created_at desc limit least(coalesce(p_limit,100),500)) a),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_create_invite(p_venue uuid, p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); token text; row private.venue_invites;
begin
  if not exists(select 1 from private.venues where id=p_venue) then raise exception 'venue_missing'; end if;
  if p_days is null or p_days not between 1 and 365 then raise exception 'invalid_duration'; end if;
  token := translate(encode(extensions.gen_random_bytes(32),'base64'),'+/=','-_');
  insert into private.venue_invites(venue_id,token_hash,expires_at) values(p_venue,encode(extensions.digest(token,'sha256'),'hex'),now()+make_interval(days=>p_days)) returning * into row;
  perform private.log_admin(uid,'invite_created',row.id::text,jsonb_build_object('venue',p_venue,'expires_at',row.expires_at));
  return jsonb_build_object('id',row.id,'token',token,'expires_at',row.expires_at);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_decide_pro(p_user uuid, p_approve boolean, p_decision text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  update public.pro_profiles set status=case when p_approve then 'approved' else 'rejected' end, decision=p_decision, decided_at=now(), updated_at=now() where user_id=p_user;
  if not found then raise exception 'profile_missing'; end if;
  perform private.notify(p_user,case when p_approve then 'account_reinstated' else 'account_restricted' end,jsonb_build_object('pro',true,'approved',p_approve,'reason',coalesce(p_decision,'')),null);
  perform private.log_admin(uid,case when p_approve then 'pro_approved' else 'pro_rejected' end,p_user::text,null);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_decide_report(p_id uuid, p_status text, p_decision text, p_suspend boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); row public.reports;
begin
  if p_status not in ('reviewed','actioned','dismissed') then raise exception 'invalid_status'; end if;
  update public.reports set status=p_status,decision=nullif(left(p_decision,1000),''),decided_at=now(),decided_by=uid where id=p_id returning * into row;
  if not found then raise exception 'report_missing'; end if;
  if p_suspend then
    insert into private.account_restrictions(user_id,suspended) values(row.reported_id,true) on conflict(user_id) do update set suspended=true;
    update public.venue_sessions set ended_at=now() where user_id=row.reported_id and ended_at is null;
    perform private.notify(row.reported_id,'account_restricted',jsonb_build_object('reason',coalesce(nullif(left(p_decision,300),''),'')),null);
  end if;
  perform private.notify(row.reporter_id,'report_handled',jsonb_build_object('status',p_status),row.id::text);
  perform private.log_admin(uid,'report_decided',p_id::text,jsonb_build_object('status',p_status,'suspend',p_suspend));
end $function$;

CREATE OR REPLACE FUNCTION private.admin_decide_venue(p_id uuid, p_approve boolean, p_decision text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); app public.venue_applications; v private.venues;
begin
  select * into app from public.venue_applications where id=p_id and status='pending' for update;
  if not found then raise exception 'application_missing'; end if;
  if p_approve then
    insert into private.venues(name,category,duration_minutes,address,hours,contact,active) values(app.venue_name,app.category,app.duration_minutes,app.address,app.hours,app.contact,true) returning * into v;
    insert into private.venue_managers(user_id,venue_id) values(app.user_id,v.id) on conflict do nothing;
    update public.venue_applications set status='approved',venue_id=v.id,decision=p_decision,decided_at=now(),decided_by=uid where id=app.id;
    perform private.notify(app.user_id,'account_reinstated',jsonb_build_object('venue',v.name,'approved',true),null);
  else
    update public.venue_applications set status='rejected',decision=p_decision,decided_at=now(),decided_by=uid where id=app.id;
    perform private.notify(app.user_id,'account_restricted',jsonb_build_object('venue',app.venue_name,'rejected',true,'reason',coalesce(p_decision,'')),null);
  end if;
  perform private.log_admin(uid,case when p_approve then 'venue_approved' else 'venue_rejected' end,app.id::text,jsonb_build_object('venue_name',app.venue_name));
  return jsonb_build_object('status',case when p_approve then 'approved' else 'rejected' end,'venue_id',v.id);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_feedback()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'member',case when f.user_id is null then null else private.member_card(f.user_id) end,'account_type',f.account_type,'score',f.score,'change_text',f.change_text,'bug',f.bug,'bug_text',f.bug_text,'context',f.context,'emailed_at',f.emailed_at,'created_at',f.created_at) order by f.created_at desc)
    from (select * from public.feedback order by created_at desc limit 300) f where private.require_admin() is not null),'[]'::jsonb)
$function$;

CREATE OR REPLACE FUNCTION private.admin_members(p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'age',date_part('year',age(p.birth_date))::int,'complete',private.profile_complete(p),'created_at',p.rules_accepted_at,
      'suspended',exists(select 1 from private.account_restrictions a where a.user_id=p.user_id and a.suspended),
      'reports_against',(select count(*) from public.reports r where r.reported_id=p.user_id),
      'live_venue',(select s.venue_name from public.venue_sessions s where s.user_id=p.user_id and s.ended_at is null and s.expires_at>now() limit 1))
    order by p.rules_accepted_at desc) from public.profiles p where p_search is null or p.display_name ilike '%'||p_search||'%' limit 200),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_overview()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return jsonb_build_object(
    'venues_active',(select count(*) from private.venues where active),
    'sessions_live',(select count(*) from public.venue_sessions where ended_at is null and expires_at>now()),
    'members',(select count(*) from public.profiles),
    'members_complete',(select count(*) from public.profiles p where private.profile_complete(p)),
    'reports_open',(select count(*) from public.reports where status='open'),
    'suspended',(select count(*) from private.account_restrictions where suspended),
    'conversations_24h',(select count(*) from public.conversations where created_at>now()-interval '24 hours'),
    'introductions_24h',(select count(*) from public.introductions where created_at>now()-interval '24 hours'));
end $function$;

CREATE OR REPLACE FUNCTION private.admin_passes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'member',private.member_card(p.user_id),'kind',p.kind,'status',p.status,'simulated',p.simulated,'amount_cents',p.amount_cents,'created_at',p.created_at,'expires_at',p.expires_at,'venue',(select name from private.venues v where v.id=p.venue_id)) order by p.created_at desc)
    from (select * from public.passes order by created_at desc limit 200) p where private.require_admin() is not null),'[]'::jsonb)
$function$;

CREATE OR REPLACE FUNCTION private.admin_pro_profiles(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',t.user_id,'member',private.member_card(t.user_id),'business_name',t.business_name,'professional_name',t.professional_name,'category',t.category,'pitch',t.pitch,'website',t.website,'socials',t.socials,'city',t.city,'status',t.status,'decision',t.decision,'subscription_until',t.subscription_until,'created_at',t.created_at) order by t.created_at desc) from public.pro_profiles t where p_status is null or t.status=p_status),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_refund_pass(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  update public.passes set status='refunded' where id=p_id and status='active';
  if not found then raise exception 'pass_missing'; end if;
  perform private.log_admin(uid,'pass_refunded',p_id::text,null);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_reports(p_status text DEFAULT 'open'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'category',r.category,'details',r.details,'status',r.status,'decision',r.decision,'decided_at',r.decided_at,
      'venue',(select name from private.venues v where v.id=r.venue_id),
      'reporter',private.member_card(r.reporter_id),'reported',private.member_card(r.reported_id),
      'reported_suspended',exists(select 1 from private.account_restrictions a where a.user_id=r.reported_id and a.suspended),
      'reported_report_count',(select count(*) from public.reports x where x.reported_id=r.reported_id),
      'conversation',case when r.conversation_id is null then null else (select jsonb_agg(jsonb_build_object('from_reported',m.sender_id=r.reported_id,'body',m.body,'created_at',m.created_at) order by m.created_at) from public.messages m where m.conversation_id=r.conversation_id) end)
    order by r.created_at desc) from public.reports r where p_status is null or r.status=p_status),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_restrict(p_user uuid, p_suspended boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  insert into private.account_restrictions(user_id,suspended) values(p_user,coalesce(p_suspended,false)) on conflict(user_id) do update set suspended=excluded.suspended;
  if coalesce(p_suspended,false) then update public.venue_sessions set ended_at=now() where user_id=p_user and ended_at is null; end if;
  perform private.log_admin(uid,case when p_suspended then 'member_suspended' else 'member_reinstated' end,p_user::text,jsonb_build_object('reason',p_reason));
end $function$;

CREATE OR REPLACE FUNCTION private.admin_revoke_invite(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  update private.venue_invites set revoked_at=now() where id=p_id and revoked_at is null;
  update public.venue_sessions set ended_at=now() where invite_id=p_id and ended_at is null;
  perform private.log_admin(uid,'invite_revoked',p_id::text,null);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_save_venue(p_id uuid, p_name text, p_category text, p_duration integer, p_address text, p_active boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin(); row private.venues;
begin
  if p_name is null or char_length(btrim(p_name)) not between 2 and 100 then raise exception 'name_length'; end if;
  if p_category not in ('restaurant','pub','chicha','nightclub','barber','test') then raise exception 'invalid_category'; end if;
  if p_duration is null or p_duration not between 15 and 720 then raise exception 'invalid_duration'; end if;
  if p_id is null then
    insert into private.venues(name,category,duration_minutes,address,active) values(btrim(p_name),p_category,p_duration,nullif(btrim(p_address),''),coalesce(p_active,true)) returning * into row;
  else
    update private.venues set name=btrim(p_name),category=p_category,duration_minutes=p_duration,address=nullif(btrim(p_address),''),active=coalesce(p_active,true) where id=p_id returning * into row;
    if not found then raise exception 'venue_missing'; end if;
    if not row.active then update public.venue_sessions set ended_at=now() where venue_id=row.id and ended_at is null; end if;
  end if;
  perform private.log_admin(uid,'venue_saved',row.id::text,jsonb_build_object('name',row.name,'active',row.active,'duration',row.duration_minutes));
  return jsonb_build_object('id',row.id);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_venue_applications(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'venue_name',a.venue_name,'category',a.category,'address',a.address,'hours',a.hours,'contact',a.contact,'duration_minutes',a.duration_minutes,'status',a.status,'decision',a.decision,'created_at',a.created_at,'applicant',(select display_name from public.profiles where user_id=a.user_id)) order by a.created_at desc) from public.venue_applications a where p_status is null or a.status=p_status),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.admin_venues()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',v.id,'name',v.name,'category',v.category,'duration_minutes',v.duration_minutes,'address',v.address,'active',v.active,
      'live',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.ended_at is null and s.expires_at>now()),
      'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'expires_at',i.expires_at,'revoked_at',i.revoked_at,'uses',(select count(*) from public.venue_sessions s where s.invite_id=i.id)) order by i.expires_at desc) from private.venue_invites i where i.venue_id=v.id),'[]'::jsonb)) order by v.name) from private.venues v),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.app_settings_public()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('simulation',private.setting('simulation'),'max_session_minutes',private.setting('max_session_minutes'),'pass_rule',private.setting('pass_rule'))
$function$;

CREATE OR REPLACE FUNCTION private.apply_venue(p_name text, p_category text, p_address text, p_hours text, p_contact text, p_duration integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); row public.venue_applications;
begin
  if not exists(select 1 from public.profiles p where p.user_id=uid and p.account_type='venue') then raise exception 'venue_account_required'; end if;
  if not exists(select 1 from public.profiles p where p.user_id=uid and private.profile_complete(p)) then raise exception 'profile_required'; end if;
  if exists(select 1 from public.venue_applications a where a.user_id=uid and a.status='pending') then raise exception 'application_pending'; end if;
  insert into public.venue_applications(user_id,venue_name,category,address,hours,contact,duration_minutes)
  values(uid,btrim(p_name),p_category,btrim(p_address),nullif(btrim(p_hours),''),nullif(btrim(p_contact),''),least(coalesce(p_duration,60),180)) returning * into row;
  return jsonb_build_object('id',row.id,'status',row.status);
end $function$;

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
  insert into public.blocks(blocker_id,blocked_id) values(uid,p_user) on conflict do nothing;
  update public.conversations set closed_at=now(), closed_by=uid where closed_at is null and ((a_id=uid and b_id=p_user) or (a_id=p_user and b_id=uid));
  update public.introductions set status='declined', responded_at=now() where status='pending' and ((sender_id=uid and recipient_id=p_user) or (sender_id=p_user and recipient_id=uid));
end $function$;

CREATE OR REPLACE FUNCTION private.blocked_between(a uuid, b uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.blocks where (blocker_id=a and blocked_id=b) or (blocker_id=b and blocked_id=a))
$function$;

CREATE OR REPLACE FUNCTION private.buy_pass_simulated()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; row public.passes;
begin
  if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'; end if;
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select * into row from public.passes where user_id=uid and venue_id=mine.venue_id and status='active' and kind='venue_pass' and expires_at>now();
  if found then return jsonb_build_object('id',row.id,'expires_at',row.expires_at,'simulated',row.simulated,'already',true); end if;
  insert into public.passes(user_id,venue_id,session_id,kind,simulated,amount_cents,expires_at) values(uid,mine.venue_id,mine.id,'venue_pass',true,0,mine.expires_at) returning * into row;
  return jsonb_build_object('id',row.id,'expires_at',row.expires_at,'simulated',row.simulated,'already',false);
end $function$;

CREATE OR REPLACE FUNCTION private.close_conversation(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); conv public.conversations;
begin
  update public.conversations set closed_at=now(), closed_by=uid where id=p_id and (a_id=uid or b_id=uid) and closed_at is null returning * into conv;
  if found then perform private.notify(case when conv.a_id=uid then conv.b_id else conv.a_id end,'conversation_closed',jsonb_build_object('conversation',conv.id),conv.id::text); end if;
end $function$;

CREATE OR REPLACE FUNCTION private.co_present(viewer uuid, owner uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select viewer is not null and owner is not null and viewer <> owner and exists (
    select 1 from public.venue_sessions a join public.venue_sessions b on a.venue_id=b.venue_id
    where a.user_id=viewer and a.ended_at is null and a.expires_at>now()
      and b.user_id=owner and b.ended_at is null and b.expires_at>now()
  ) and not private.blocked_between(viewer, owner)
$function$;

CREATE OR REPLACE FUNCTION private.co_present_in(p_conv conversations, p_uid uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists(select 1 from public.venue_sessions a join public.venue_sessions b on b.venue_id=a.venue_id
    where a.user_id=p_uid and b.user_id=case when p_conv.a_id=p_uid then p_conv.b_id else p_conv.a_id end
      and a.venue_id=p_conv.venue_id and a.ended_at is null and a.expires_at>now() and b.ended_at is null and b.expires_at>now())
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

CREATE OR REPLACE FUNCTION private.delete_account()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'verified_account_required' using errcode='42501'; end if;
  delete from auth.users where id=uid;
end $function$;

CREATE OR REPLACE FUNCTION private.join_venue(p_token text)
 RETURNS venue_sessions
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); invitation private.venue_invites; venue private.venues; result public.venue_sessions; me public.profiles;
begin
  perform 1 from auth.users where id=uid for update;
  select * into me from public.profiles where user_id=uid;
  if not found or not private.profile_complete(me) then raise exception 'profile_required'; end if;
  perform private.preview_venue(p_token);
  select * into invitation from private.venue_invites where token_hash=encode(extensions.digest(p_token,'sha256'),'hex') for share;
  select * into venue from private.venues where id=invitation.venue_id for share;
  if invitation.revoked_at is not null or invitation.expires_at<=now() or not venue.active then raise exception 'invalid_invitation'; end if;
  select * into result from public.venue_sessions where user_id=uid and invite_id=invitation.id and ended_at is null and expires_at>now();
  if found then return result; end if;
  update public.venue_sessions set ended_at=now() where user_id=uid and ended_at is null;
  insert into public.venue_sessions(user_id,venue_id,invite_id,venue_name,expires_at)
  values(uid,venue.id,invitation.id,venue.name,now()+make_interval(mins=>least(venue.duration_minutes,coalesce((private.setting('max_session_minutes'))::int,180)))) returning * into result;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION private.leave_venue()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'verified_account_required' using errcode='42501'; end if;
  perform 1 from auth.users where id=uid for update;
  update public.venue_sessions set ended_at=now() where user_id=uid and ended_at is null;
end $function$;

CREATE OR REPLACE FUNCTION private.live_session(uid uuid)
 RETURNS venue_sessions
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select s from public.venue_sessions s where s.user_id=uid and s.ended_at is null and s.expires_at>now() limit 1
$function$;

CREATE OR REPLACE FUNCTION private.log_admin(p_admin uuid, p_action text, p_target text, p_details jsonb DEFAULT NULL::jsonb)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into private.admin_actions(admin_id,action,target,details) values(p_admin,p_action,p_target,p_details)
$function$;

CREATE OR REPLACE FUNCTION private.meeting_answer(p_conversation uuid, p_yes boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); conv public.conversations; other uuid; mine_count int; theirs_count int;
begin
  select * into conv from public.conversations where id=p_conversation and (a_id=uid or b_id=uid) for update;
  if not found or conv.closed_at is not null then raise exception 'conversation_unavailable'; end if;
  other := case when conv.a_id=uid then conv.b_id else conv.a_id end;
  if private.blocked_between(uid,other) then raise exception 'conversation_unavailable'; end if;
  if not private.co_present_in(conv,uid) then raise exception 'visit_over'; end if;
  select count(*) filter (where sender_id=uid), count(*) filter (where sender_id=other) into mine_count, theirs_count from public.messages where conversation_id=conv.id;
  if mine_count<2 or theirs_count<2 then raise exception 'meeting_too_early'; end if;
  if conv.a_id=uid then update public.conversations set meeting_a=p_yes, meeting_prompted_at=coalesce(meeting_prompted_at,now()) where id=conv.id returning * into conv;
  else update public.conversations set meeting_b=p_yes, meeting_prompted_at=coalesce(meeting_prompted_at,now()) where id=conv.id returning * into conv; end if;
  if conv.meeting_a is true and conv.meeting_b is true and conv.meeting_agreed_at is null then
    update public.conversations set meeting_agreed_at=now() where id=conv.id returning * into conv;
    perform private.notify(other,'reply_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'conversation',conv.id,'meeting',true),conv.id::text||':meeting');
  end if;
  return private.meeting_state(conv,uid);
end $function$;

CREATE OR REPLACE FUNCTION private.meeting_state(conv conversations, uid uuid)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'eligible', conv.closed_at is null,
    'my_answer', case when conv.a_id=uid then conv.meeting_a else conv.meeting_b end,
    'other_answered', (case when conv.a_id=uid then conv.meeting_b else conv.meeting_a end) is not null,
    'agreed', conv.meeting_agreed_at is not null,
    'agreed_at', conv.meeting_agreed_at)
$function$;

CREATE OR REPLACE FUNCTION private.member_card(p_user uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'age',date_part('year',age(p.birth_date))::int,'bio',p.bio,'avatar_path',p.avatar_path)
  from public.profiles p where p.user_id=p_user
$function$;

CREATE OR REPLACE FUNCTION private.my_account_type()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select account_type from public.profiles where user_id=auth.uid()),(select account_type from private.account_choices where user_id=auth.uid()))
$function$;

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

CREATE OR REPLACE FUNCTION private.my_notifications(p_mark_read boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id',n.id,'kind',n.kind,'payload',n.payload - 'key','created_at',n.created_at,'read',n.read_at is not null) order by n.created_at desc),'[]'::jsonb)
  into result from (select * from public.notifications where user_id=uid order by created_at desc limit 50) n;
  if p_mark_read then update public.notifications set read_at=now() where user_id=uid and read_at is null; end if;
  return jsonb_build_object('items',result,'unread',(select count(*) from public.notifications where user_id=uid and read_at is null));
end $function$;

CREATE OR REPLACE FUNCTION private.my_passes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'kind',p.kind,'status',p.status,'simulated',p.simulated,'amount_cents',p.amount_cents,'created_at',p.created_at,'expires_at',p.expires_at,'venue',(select name from private.venues v where v.id=p.venue_id),'active',p.status='active' and p.expires_at>now()) order by p.created_at desc)
    from public.passes p where p.user_id=private.require_member()),'[]'::jsonb)
$function$;

CREATE OR REPLACE FUNCTION private.my_pro_profile()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); row public.pro_profiles;
begin
  select * into row from public.pro_profiles where user_id=uid;
  if not found then return null; end if;
  return jsonb_build_object('business_name',row.business_name,'professional_name',row.professional_name,'category',row.category,'pitch',row.pitch,'website',row.website,'socials',row.socials,'city',row.city,'status',row.status,'decision',row.decision,'subscription_until',row.subscription_until,'subscription_active',row.subscription_until is not null and row.subscription_until>now(),
    'enquiries',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'message',e.message,'contact',e.contact,'created_at',e.created_at,'from',(select display_name from public.profiles where user_id=e.from_id),'venue',(select name from private.venues where id=e.venue_id)) order by e.created_at desc) from (select * from public.enquiries where pro_id=uid order by created_at desc limit 50) e),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.my_venue()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); v private.venues; app public.venue_applications;
begin
  select v2.* into v from private.venues v2 join private.venue_managers m on m.venue_id=v2.id where m.user_id=uid limit 1;
  if not found then
    select * into app from public.venue_applications where user_id=uid order by created_at desc limit 1;
    return jsonb_build_object('venue',null,'application',case when app.id is null then null else jsonb_build_object('id',app.id,'status',app.status,'venue_name',app.venue_name,'decision',app.decision,'created_at',app.created_at) end);
  end if;
  return jsonb_build_object('venue',jsonb_build_object('id',v.id,'name',v.name,'category',v.category,'address',v.address,'hours',v.hours,'contact',v.contact,'duration_minutes',v.duration_minutes,'active',v.active,
      'present',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.ended_at is null and s.expires_at>now()),
      'today',(select count(*) from public.venue_sessions s where s.venue_id=v.id and s.started_at>now()-interval '24 hours'),
      'open_reports',(select count(*) from public.reports r where r.venue_id=v.id and r.status='open'),
      'invites',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'expires_at',i.expires_at,'revoked_at',i.revoked_at,'uses',(select count(*) from public.venue_sessions s where s.invite_id=i.id)) order by i.expires_at desc) from private.venue_invites i where i.venue_id=v.id and i.revoked_at is null and i.expires_at>now()),'[]'::jsonb),
      'announcements',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'body',a.body,'created_at',a.created_at,'expires_at',a.expires_at) order by a.created_at desc) from public.venue_announcements a where a.venue_id=v.id and a.expires_at>now()),'[]'::jsonb)),
    'application',null);
end $function$;

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

CREATE OR REPLACE FUNCTION private.notify(p_user uuid, p_kind text, p_payload jsonb DEFAULT '{}'::jsonb, p_dedupe_key text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if p_user is null then return; end if;
  -- One unread notification per (kind, dedupe key): a busy conversation does not flood the inbox.
  if p_dedupe_key is not null and exists(select 1 from public.notifications n where n.user_id=p_user and n.kind=p_kind and n.read_at is null and n.payload->>'key'=p_dedupe_key) then return; end if;
  insert into public.notifications(user_id,kind,payload) values(p_user,p_kind,coalesce(p_payload,'{}'::jsonb)||case when p_dedupe_key is null then '{}'::jsonb else jsonb_build_object('key',p_dedupe_key) end);
  delete from public.notifications where user_id=p_user and id not in (select id from public.notifications where user_id=p_user order by created_at desc limit 200);
end $function$;

CREATE OR REPLACE FUNCTION private.preview_venue(p_token text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
  perform private.require_member();
  if p_token is null or length(p_token) not between 32 and 256 then raise exception 'invalid_invitation'; end if;
  select jsonb_build_object('name',v.name,'category',v.category,'duration_minutes',v.duration_minutes,'address',v.address)
  into result from private.venue_invites i join private.venues v on v.id=i.venue_id
  where i.token_hash=encode(extensions.digest(p_token,'sha256'),'hex') and i.revoked_at is null and i.expires_at>now() and v.active;
  if result is null then raise exception 'invalid_invitation'; end if;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION private.profile_complete(p profiles)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select case when p.account_type='venue' then p.display_name is not null and p.locale is not null
         else p.display_name is not null and p.birth_date is not null and p.locale is not null
              and p.bio is not null and char_length(btrim(p.bio)) > 0 and p.avatar_path is not null end
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
  if p_category is null or p_category not in ('harassment','inappropriate','impersonation','prohibited','other') then raise exception 'invalid_category'; end if;
  if p_conversation is not null then
    select * into conv from public.conversations where id=p_conversation and (a_id=uid or b_id=uid);
    if not found then p_conversation := null; end if;
  end if;
  if (select count(*) from public.reports r where r.reporter_id=uid and r.created_at>now()-interval '1 day')>=20 then raise exception 'report_limit'; end if;
  insert into public.reports(reporter_id,reported_id,category,details,conversation_id,venue_id) values(uid,p_user,p_category,nullif(left(p_details,1000),''),p_conversation,coalesce(conv.venue_id,(private.live_session(uid)).venue_id)) returning * into row;
  return jsonb_build_object('id',row.id,'created_at',row.created_at);
end $function$;

CREATE OR REPLACE FUNCTION private.require_admin()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid(); claims jsonb := coalesce(auth.jwt(), '{}'::jsonb);
begin
  if uid is null or coalesce(claims->'app_metadata'->>'prod_admin','') <> 'true' then raise exception 'admin_required' using errcode='42501'; end if;
  if coalesce(claims->>'aal','') <> 'aal2' then raise exception 'mfa_required' using errcode='42501'; end if;
  return uid;
end $function$;

CREATE OR REPLACE FUNCTION private.require_member()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := auth.uid();
begin
  if uid is null or not exists(select 1 from auth.users where id=uid and (email_confirmed_at is not null or phone_confirmed_at is not null) and coalesce(is_anonymous,false)=false) then
    raise exception 'verified_account_required' using errcode='42501';
  end if;
  if exists(select 1 from private.account_restrictions where user_id=uid and suspended) then
    raise exception 'account_restricted' using errcode='42501';
  end if;
  return uid;
end $function$;

CREATE OR REPLACE FUNCTION private.require_person()
 RETURNS uuid
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member();
begin
  if exists(select 1 from public.profiles p where p.user_id=uid and p.account_type='venue') then raise exception 'venue_account' using errcode='42501'; end if;
  return uid;
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
  if p_reply is null or char_length(btrim(p_reply)) not between 1 and 2000 then raise exception 'reply_required'; end if;
  update public.introductions set status='accepted', responded_at=now() where id=row.id;
  insert into public.conversations(introduction_id,venue_id,a_id,b_id) values(row.id,row.venue_id,row.sender_id,uid) returning * into conv;
  insert into public.messages(conversation_id,sender_id,body,created_at) values(conv.id,row.sender_id,row.message,row.created_at);
  insert into public.messages(conversation_id,sender_id,body) values(conv.id,uid,btrim(p_reply));
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid);
  perform private.notify(row.sender_id,'reply_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'conversation',conv.id),conv.id::text);
  return jsonb_build_object('status','accepted','conversation_id',conv.id);
end $function$;

CREATE OR REPLACE FUNCTION private.save_pro_profile(p_business text, p_professional text, p_category text, p_pitch text, p_website text, p_socials jsonb, p_city text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); row public.pro_profiles; clean jsonb := '{}'::jsonb; k text; v text;
begin
  if not exists(select 1 from public.profiles p where p.user_id=uid and p.account_type='pro') then raise exception 'pro_account_required'; end if;
  for k, v in select key, value #>> '{}' from jsonb_each(coalesce(p_socials,'{}'::jsonb)) loop
    if k in ('instagram','tiktok','linkedin','facebook','youtube','x') and v is not null and char_length(v) between 1 and 120 then clean := clean || jsonb_build_object(k, btrim(v)); end if;
  end loop;
  insert into public.pro_profiles(user_id,business_name,professional_name,category,pitch,website,socials,city)
  values(uid,btrim(p_business),nullif(btrim(p_professional),''),btrim(p_category),btrim(p_pitch),nullif(btrim(p_website),''),clean,nullif(btrim(p_city),''))
  on conflict(user_id) do update set business_name=excluded.business_name,professional_name=excluded.professional_name,category=excluded.category,pitch=excluded.pitch,website=excluded.website,socials=excluded.socials,city=excluded.city,
    status=case when public.pro_profiles.status='approved' then 'approved' else 'pending' end, updated_at=now()
  returning * into row;
  return jsonb_build_object('status',row.status,'subscription_until',row.subscription_until);
end $function$;

CREATE OR REPLACE FUNCTION private.save_profile(p_name text, p_birth_date date, p_locale text, p_accept_rules boolean, p_bio text DEFAULT NULL::text, p_avatar_path text DEFAULT NULL::text)
 RETURNS profiles
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); result public.profiles; existing public.profiles; t text;
begin
  select * into existing from public.profiles where user_id=uid;
  t := coalesce(existing.account_type,(select account_type from private.account_choices where user_id=uid),'personal');
  if p_accept_rules is distinct from true then raise exception 'rules_required'; end if;
  if p_name is null or char_length(btrim(p_name)) not between 2 and 40 then raise exception 'name_length'; end if;
  if p_locale is null or p_locale not in ('fr','en') then raise exception 'unsupported_language'; end if;
  if t<>'venue' then
    if p_birth_date is null or p_birth_date > (current_date - interval '18 years')::date or p_birth_date < (current_date - interval '120 years')::date then raise exception 'adults_only'; end if;
    if existing.user_id is not null and existing.birth_date is not null and existing.birth_date <> p_birth_date then raise exception 'birth_date_locked'; end if;
  end if;
  if p_bio is not null and char_length(btrim(p_bio)) not between 1 and 300 then raise exception 'bio_length'; end if;
  if p_avatar_path is not null and (p_avatar_path !~ ('^u/' || uid::text || '/[A-Za-z0-9._-]+$') or not exists(select 1 from storage.objects where bucket_id='avatars' and name=p_avatar_path)) then raise exception 'photo_missing'; end if;
  insert into public.profiles(user_id,display_name,birth_date,locale,bio,avatar_path,avatar_updated_at,account_type)
  values(uid,btrim(p_name),case when t='venue' then null else p_birth_date end,p_locale,nullif(btrim(p_bio),''),p_avatar_path,case when p_avatar_path is null then null else now() end,t)
  on conflict(user_id) do update set display_name=excluded.display_name,locale=excluded.locale,
    birth_date=coalesce(public.profiles.birth_date,excluded.birth_date),
    bio=coalesce(excluded.bio,public.profiles.bio),
    avatar_path=coalesce(excluded.avatar_path,public.profiles.avatar_path),
    avatar_updated_at=case when excluded.avatar_path is null then public.profiles.avatar_updated_at else now() end,
    updated_at=now()
  returning * into result;
  return result;
end $function$;

CREATE OR REPLACE FUNCTION private.send_enquiry(p_pro uuid, p_message text, p_contact text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; theirs public.venue_sessions; row public.enquiries;
begin
  if p_message is null or char_length(btrim(p_message)) not between 1 and 1000 then raise exception 'message_length'; end if;
  mine := private.live_session(uid); theirs := private.live_session(p_pro);
  if mine.id is null or theirs.id is null or theirs.venue_id<>mine.venue_id then raise exception 'not_co_present'; end if;
  if not exists(select 1 from public.pro_profiles t where t.user_id=p_pro and t.status='approved') then raise exception 'not_co_present'; end if;
  if private.blocked_between(uid,p_pro) then raise exception 'not_co_present'; end if;
  if (select count(*) from public.enquiries e where e.from_id=uid and e.created_at>now()-interval '1 day')>=10 then raise exception 'introduction_limit'; end if;
  insert into public.enquiries(from_id,pro_id,venue_id,message,contact) values(uid,p_pro,mine.venue_id,btrim(p_message),nullif(btrim(p_contact),'')) returning * into row;
  perform private.notify(p_pro,'introduction_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'venue',(select name from private.venues where id=mine.venue_id),'enquiry',true),row.id::text);
  return jsonb_build_object('id',row.id);
end $function$;

CREATE OR REPLACE FUNCTION private.send_feedback_emails()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare api_key text; to_addr text; from_addr text; subj text; f record; n integer := 0; body text; faces text[] := array['😕','😐','🙂','🤩'];
begin
  select decrypted_secret into api_key from vault.decrypted_secrets where name='brevo_api_key' limit 1;
  to_addr := private.setting('feedback_email') #>> '{}'; from_addr := private.setting('feedback_sender') #>> '{}'; subj := coalesce(private.setting('feedback_subject') #>> '{}','[UPZONE test] Nouveau retour');
  if api_key is null or to_addr is null or from_addr is null then return 0; end if;
  for f in select fb.*, (select display_name from public.profiles p where p.user_id=fb.user_id) as who from public.feedback fb where fb.emailed_at is null order by fb.created_at limit 20 loop
    body := 'Nouveau retour UPZONE (test)' || E'\n\n' ||
      'Note : ' || coalesce(faces[f.score],'') || ' ' || f.score || '/4' || E'\n' ||
      'Compte : ' || coalesce(f.who,'(supprimé)') || ' · type ' || coalesce(f.account_type,'?') || E'\n' ||
      'Utilisation : ' || coalesce(f.context->>'minutes','?') || ' min · ' || coalesce(f.context->>'lang','') || ' · ' || case when f.context->>'installed'='true' then 'app installée' else 'navigateur' end || ' · écran ' || coalesce(f.context->>'screen','') || E'\n' ||
      'Envoyé le : ' || to_char(f.created_at at time zone 'Europe/Paris','DD/MM/YYYY HH24:MI') || E'\n\n' ||
      'À changer en premier :' || E'\n' || coalesce(f.change_text,'(vide)') || E'\n\n' ||
      case when f.bug then 'BUG signalé :' || E'\n' || coalesce(f.bug_text,'(sans détail)') || E'\n\n' else '' end ||
      'Détail complet dans le portail d’administration, onglet Retours.';
    perform net.http_post(url:='https://api.brevo.com/v3/smtp/email',
      headers:=jsonb_build_object('api-key',api_key,'content-type','application/json','accept','application/json'),
      body:=jsonb_build_object('sender',jsonb_build_object('email',from_addr,'name','UPZONE test'),'to',jsonb_build_array(jsonb_build_object('email',to_addr)),'subject',subj || ' ' || coalesce(faces[f.score],'') || case when f.bug then ' · bug' else '' end,'textContent',body));
    update public.feedback set emailed_at=now() where id=f.id; n := n+1;
  end loop;
  return n;
end $function$;

CREATE OR REPLACE FUNCTION private.send_introduction(p_to uuid, p_message text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); mine public.venue_sessions; theirs public.venue_sessions; row public.introductions;
begin
  if p_to is null or p_to=uid then raise exception 'invalid_recipient'; end if;
  if p_message is null or char_length(btrim(p_message)) not between 1 and 500 then raise exception 'message_length'; end if;
  mine := private.live_session(uid); if mine.id is null then raise exception 'no_live_session'; end if;
  theirs := private.live_session(p_to);
  if theirs.id is null or theirs.venue_id<>mine.venue_id then raise exception 'not_co_present'; end if;
  if private.blocked_between(uid,p_to) then raise exception 'not_co_present'; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=p_to and r.suspended) then raise exception 'not_co_present'; end if;
  if exists(select 1 from public.profiles p where p.user_id=p_to and not private.profile_complete(p)) then raise exception 'not_co_present'; end if;
  if exists(select 1 from public.introductions i where i.recipient_id=uid and i.sender_id=p_to and i.session_id=theirs.id and i.status='pending') then raise exception 'introduction_received'; end if;
  if exists(select 1 from public.introductions i where i.sender_id=uid and i.recipient_id=p_to and (i.session_id=mine.id or i.status<>'accepted')) then raise exception 'introduction_exists'; end if;
  if (select count(*) from public.introductions i where i.sender_id=uid and i.session_id=mine.id)>=5 then raise exception 'introduction_limit'; end if;
  insert into public.introductions(sender_id,recipient_id,venue_id,session_id,message) values(uid,p_to,mine.venue_id,mine.id,btrim(p_message)) returning * into row;
  perform private.notify(p_to,'introduction_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'venue',(select name from private.venues where id=mine.venue_id)),row.id::text);
  return jsonb_build_object('id',row.id,'status',row.status,'created_at',row.created_at);
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
  if private.blocked_between(uid,other) then raise exception 'conversation_unavailable'; end if;
  if exists(select 1 from private.account_restrictions r where r.user_id=other and r.suspended) then raise exception 'conversation_unavailable'; end if;
  if not private.co_present_in(conv,uid) then raise exception 'visit_over'; end if;
  if private.needs_pass(conv,uid) then raise exception 'pass_required'; end if;
  insert into public.messages(conversation_id,sender_id,body) values(conv.id,uid,btrim(p_body)) returning * into row;
  insert into public.conversation_reads(conversation_id,user_id) values(conv.id,uid) on conflict(conversation_id,user_id) do update set read_at=now();
  perform private.notify(other,'message_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'conversation',conv.id),conv.id::text);
  return jsonb_build_object('id',row.id,'created_at',row.created_at);
end $function$;

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
    update public.profiles set account_type=p_type, updated_at=now() where user_id=uid;
  end if;
  insert into private.account_choices(user_id,account_type) values(uid,p_type) on conflict(user_id) do update set account_type=excluded.account_type;
  return jsonb_build_object('account_type',p_type);
end $function$;

CREATE OR REPLACE FUNCTION private.setting(p_key text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$ select value from private.app_settings where key=p_key $function$;

CREATE OR REPLACE FUNCTION private.submit_feedback(p_score integer, p_change text, p_bug boolean, p_bug_text text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); row public.feedback;
begin
  if p_score is null or p_score not between 1 and 4 then raise exception 'invalid_score'; end if;
  if (select count(*) from public.feedback f where f.user_id=uid and f.created_at>now()-interval '1 day')>=5 then raise exception 'report_limit'; end if;
  insert into public.feedback(user_id,account_type,score,change_text,bug,bug_text,context)
  values(uid,(select account_type from public.profiles where user_id=uid),p_score,nullif(btrim(p_change),''),coalesce(p_bug,false),nullif(btrim(p_bug_text),''),
         jsonb_build_object('lang',p_context->>'lang','minutes',p_context->>'minutes','screen',p_context->>'screen','installed',p_context->>'installed','ua',left(p_context->>'ua',200)))
  returning * into row;
  return jsonb_build_object('id',row.id);
end $function$;

CREATE OR REPLACE FUNCTION private.subscribe_talent_simulated()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); row public.pro_profiles;
begin
  if (private.setting('simulation'))::boolean is distinct from true then raise exception 'simulation_only'; end if;
  select * into row from public.pro_profiles where user_id=uid for update;
  if not found or row.status<>'approved' then raise exception 'pro_not_approved'; end if;
  update public.pro_profiles set subscription_until=greatest(coalesce(subscription_until,now()),now())+interval '30 days', updated_at=now() where user_id=uid returning * into row;
  insert into public.passes(user_id,venue_id,kind,simulated,amount_cents,expires_at) values(uid,null,'talent_subscription',true,0,row.subscription_until);
  return jsonb_build_object('subscription_until',row.subscription_until,'simulated',true);
end $function$;

CREATE OR REPLACE FUNCTION private.venue_announce(p_body text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); vid uuid; row public.venue_announcements;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  if vid is null then raise exception 'venue_required'; end if;
  if p_body is null or char_length(btrim(p_body)) not between 1 and 300 then raise exception 'message_length'; end if;
  insert into public.venue_announcements(venue_id,author_id,body) values(vid,uid,btrim(p_body)) returning * into row;
  return jsonb_build_object('id',row.id);
end $function$;

CREATE OR REPLACE FUNCTION private.venue_create_invite(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); vid uuid; token text; row private.venue_invites;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  if vid is null then raise exception 'venue_required'; end if;
  if p_days is null or p_days not between 1 and 90 then raise exception 'invalid_duration'; end if;
  token := translate(encode(extensions.gen_random_bytes(32),'base64'),'+/=','-_');
  insert into private.venue_invites(venue_id,token_hash,expires_at) values(vid,encode(extensions.digest(token,'sha256'),'hex'),now()+make_interval(days=>p_days)) returning * into row;
  return jsonb_build_object('id',row.id,'token',token,'expires_at',row.expires_at);
end $function$;

CREATE OR REPLACE FUNCTION private.venue_delete_announcement(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); vid uuid;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  update public.venue_announcements set expires_at=now() where id=p_id and venue_id=vid;
end $function$;

-- Updated 10 November 2026 (db/2026-11-10-interest-filter.sql): follows the viewer's « who would you like to see ».
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone)
 language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; wants text;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select p.interested_in into wants from public.profiles p where p.user_id=uid;
  return query
    select p.user_id, p.display_name, date_part('year', age(p.birth_date))::integer, p.bio, p.avatar_path, s.started_at
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type<>'venue' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
      and (wants is null or wants='everyone' or (wants='women' and p.gender='woman') or (wants='men' and p.gender='man'))
    order by s.started_at desc;
end $function$;

CREATE OR REPLACE FUNCTION private.venue_revoke_invite(p_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); vid uuid;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  update private.venue_invites set revoked_at=now() where id=p_id and venue_id=vid and revoked_at is null;
  update public.venue_sessions set ended_at=now() where invite_id=p_id and venue_id=vid and ended_at is null;
end $function$;

CREATE OR REPLACE FUNCTION private.venue_room()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return jsonb_build_object(
    'present',(select count(*) from public.venue_sessions s join public.profiles p on p.user_id=s.user_id where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and p.account_type<>'venue'),
    'announcements',coalesce((select jsonb_agg(jsonb_build_object('body',a.body,'created_at',a.created_at) order by a.created_at desc) from (select * from public.venue_announcements where venue_id=mine.venue_id and expires_at>now() order by created_at desc limit 3) a),'[]'::jsonb));
end $function$;

CREATE OR REPLACE FUNCTION private.venue_talents()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_person(); mine public.venue_sessions;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  return coalesce((select jsonb_agg(jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'avatar_path',p.avatar_path,'business_name',t.business_name,'professional_name',t.professional_name,'category',t.category,'pitch',t.pitch,'website',t.website,'socials',t.socials,'city',t.city) order by s.started_at desc)
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id join public.pro_profiles t on t.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type='pro' and t.status='approved' and t.subscription_until is not null and t.subscription_until>now()
      and private.profile_complete(p) and not private.blocked_between(uid,s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)),'[]'::jsonb);
end $function$;

CREATE OR REPLACE FUNCTION private.venue_update(p_hours text, p_contact text, p_duration integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare uid uuid := private.require_member(); vid uuid;
begin
  select venue_id into vid from private.venue_managers where user_id=uid limit 1;
  if vid is null then raise exception 'venue_required'; end if;
  if p_duration is null or p_duration not between 15 and 180 then raise exception 'invalid_duration'; end if;
  update private.venues set hours=nullif(btrim(p_hours),''), contact=nullif(btrim(p_contact),''), duration_minutes=p_duration where id=vid;
end $function$;

CREATE OR REPLACE FUNCTION public.admin_audit(p_limit integer DEFAULT 100)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_audit(p_limit) $function$;

CREATE OR REPLACE FUNCTION public.admin_create_invite(p_venue uuid, p_days integer DEFAULT 30)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_create_invite(p_venue,p_days) $function$;

CREATE OR REPLACE FUNCTION public.admin_decide_pro(p_user uuid, p_approve boolean, p_decision text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_decide_pro(p_user,p_approve,p_decision) $function$;

CREATE OR REPLACE FUNCTION public.admin_decide_report(p_id uuid, p_status text, p_decision text, p_suspend boolean DEFAULT false)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_decide_report(p_id,p_status,p_decision,p_suspend) $function$;

CREATE OR REPLACE FUNCTION public.admin_decide_venue(p_id uuid, p_approve boolean, p_decision text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_decide_venue(p_id,p_approve,p_decision) $function$;

CREATE OR REPLACE FUNCTION public.admin_feedback()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_feedback() $function$;

CREATE OR REPLACE FUNCTION public.admin_members(p_search text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_members(p_search) $function$;

CREATE OR REPLACE FUNCTION public.admin_overview()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_overview() $function$;

CREATE OR REPLACE FUNCTION public.admin_passes()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_passes() $function$;

CREATE OR REPLACE FUNCTION public.admin_pro_profiles(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_pro_profiles(p_status) $function$;

CREATE OR REPLACE FUNCTION public.admin_refund_pass(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_refund_pass(p_id) $function$;

CREATE OR REPLACE FUNCTION public.admin_reports(p_status text DEFAULT 'open'::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_reports(p_status) $function$;

CREATE OR REPLACE FUNCTION public.admin_restrict(p_user uuid, p_suspended boolean, p_reason text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_restrict(p_user,p_suspended,p_reason) $function$;

CREATE OR REPLACE FUNCTION public.admin_revoke_invite(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_revoke_invite(p_id) $function$;

CREATE OR REPLACE FUNCTION public.admin_save_venue(p_id uuid, p_name text, p_category text, p_duration integer, p_address text, p_active boolean)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_save_venue(p_id,p_name,p_category,p_duration,p_address,p_active) $function$;

CREATE OR REPLACE FUNCTION public.admin_venue_applications(p_status text DEFAULT 'pending'::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_venue_applications(p_status) $function$;

CREATE OR REPLACE FUNCTION public.admin_venues()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.admin_venues() $function$;

CREATE OR REPLACE FUNCTION public.app_settings_public()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.app_settings_public() $function$;

CREATE OR REPLACE FUNCTION public.apply_venue(p_name text, p_category text, p_address text, p_hours text, p_contact text, p_duration integer)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.apply_venue(p_name,p_category,p_address,p_hours,p_contact,p_duration) $function$;

CREATE OR REPLACE FUNCTION public.block_member(p_user uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.block_member(p_user) $function$;

CREATE OR REPLACE FUNCTION public.buy_pass_simulated()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.buy_pass_simulated() $function$;

CREATE OR REPLACE FUNCTION public.close_conversation(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.close_conversation(p_id) $function$;

CREATE OR REPLACE FUNCTION public.conversation_messages(p_id uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.conversation_messages(p_id) $function$;

CREATE OR REPLACE FUNCTION public.delete_account()
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.delete_account() $function$;

CREATE OR REPLACE FUNCTION public.is_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce((auth.jwt()->'app_metadata'->>'prod_admin') = 'true', false)
$function$;

CREATE OR REPLACE FUNCTION public.join_venue(p_token text)
 RETURNS venue_sessions
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.join_venue(p_token) $function$;

CREATE OR REPLACE FUNCTION public.leave_venue()
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.leave_venue() $function$;

CREATE OR REPLACE FUNCTION public.meeting_answer(p_conversation uuid, p_yes boolean)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.meeting_answer(p_conversation,p_yes) $function$;

CREATE OR REPLACE FUNCTION public.my_account_type()
 RETURNS text
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_account_type() $function$;

CREATE OR REPLACE FUNCTION public.my_data_export()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_data_export() $function$;

CREATE OR REPLACE FUNCTION public.my_inbox()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_inbox() $function$;

CREATE OR REPLACE FUNCTION public.my_notifications(p_mark_read boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_notifications(p_mark_read) $function$;

CREATE OR REPLACE FUNCTION public.my_passes()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_passes() $function$;

CREATE OR REPLACE FUNCTION public.my_pro_profile()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_pro_profile() $function$;

CREATE OR REPLACE FUNCTION public.my_venue()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.my_venue() $function$;

CREATE OR REPLACE FUNCTION public.preview_venue(p_token text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.preview_venue(p_token) $function$;

CREATE OR REPLACE FUNCTION public.report_member(p_user uuid, p_category text, p_details text DEFAULT NULL::text, p_conversation uuid DEFAULT NULL::uuid)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.report_member(p_user,p_category,p_details,p_conversation) $function$;

CREATE OR REPLACE FUNCTION public.respond_introduction(p_id uuid, p_accept boolean, p_reply text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.respond_introduction(p_id,p_accept,p_reply) $function$;

CREATE OR REPLACE FUNCTION public.save_pro_profile(p_business text, p_professional text, p_category text, p_pitch text, p_website text, p_socials jsonb, p_city text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.save_pro_profile(p_business,p_professional,p_category,p_pitch,p_website,p_socials,p_city) $function$;

CREATE OR REPLACE FUNCTION public.save_profile(p_name text, p_birth_date date, p_locale text, p_accept_rules boolean, p_bio text DEFAULT NULL::text, p_avatar_path text DEFAULT NULL::text)
 RETURNS profiles
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.save_profile(p_name,p_birth_date,p_locale,p_accept_rules,p_bio,p_avatar_path) $function$;

CREATE OR REPLACE FUNCTION public.send_enquiry(p_pro uuid, p_message text, p_contact text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.send_enquiry(p_pro,p_message,p_contact) $function$;

CREATE OR REPLACE FUNCTION public.send_introduction(p_to uuid, p_message text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.send_introduction(p_to,p_message) $function$;

CREATE OR REPLACE FUNCTION public.send_message(p_conversation uuid, p_body text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.send_message(p_conversation,p_body) $function$;

CREATE OR REPLACE FUNCTION public.set_account_type(p_type text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.set_account_type(p_type) $function$;

CREATE OR REPLACE FUNCTION public.submit_feedback(p_score integer, p_change text, p_bug boolean, p_bug_text text, p_context jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.submit_feedback(p_score,p_change,p_bug,p_bug_text,p_context) $function$;

CREATE OR REPLACE FUNCTION public.subscribe_talent_simulated()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.subscribe_talent_simulated() $function$;

CREATE OR REPLACE FUNCTION public.venue_announce(p_body text)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_announce(p_body) $function$;

CREATE OR REPLACE FUNCTION public.venue_create_invite(p_days integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_create_invite(p_days) $function$;

CREATE OR REPLACE FUNCTION public.venue_delete_announcement(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_delete_announcement(p_id) $function$;

CREATE OR REPLACE FUNCTION public.venue_members()
 RETURNS TABLE(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone)
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select * from private.venue_members() $function$;

CREATE OR REPLACE FUNCTION public.venue_revoke_invite(p_id uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_revoke_invite(p_id) $function$;

CREATE OR REPLACE FUNCTION public.venue_room()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_room() $function$;

CREATE OR REPLACE FUNCTION public.venue_talents()
 RETURNS jsonb
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_talents() $function$;

CREATE OR REPLACE FUNCTION public.venue_update(p_hours text, p_contact text, p_duration integer)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$ select private.venue_update(p_hours,p_contact,p_duration) $function$;

-- Privileges (as exported). Private helpers not listed are reachable only from other SECURITY DEFINER functions.
revoke all on all functions in schema private from public, anon, authenticated;
revoke all on all functions in schema public from public, anon;
grant execute on function private.admin_audit(p_limit integer DEFAULT 100) to authenticated;
grant execute on function private.admin_create_invite(p_venue uuid, p_days integer DEFAULT 30) to authenticated;
grant execute on function private.admin_decide_pro(p_user uuid, p_approve boolean, p_decision text DEFAULT NULL::text) to authenticated;
grant execute on function private.admin_decide_report(p_id uuid, p_status text, p_decision text, p_suspend boolean DEFAULT false) to authenticated;
grant execute on function private.admin_decide_venue(p_id uuid, p_approve boolean, p_decision text DEFAULT NULL::text) to authenticated;
grant execute on function private.admin_feedback() to authenticated;
grant execute on function private.admin_members(p_search text DEFAULT NULL::text) to authenticated;
grant execute on function private.admin_overview() to authenticated;
grant execute on function private.admin_passes() to authenticated;
grant execute on function private.admin_pro_profiles(p_status text DEFAULT 'pending'::text) to authenticated;
grant execute on function private.admin_refund_pass(p_id uuid) to authenticated;
grant execute on function private.admin_reports(p_status text DEFAULT 'open'::text) to authenticated;
grant execute on function private.admin_restrict(p_user uuid, p_suspended boolean, p_reason text DEFAULT NULL::text) to authenticated;
grant execute on function private.admin_revoke_invite(p_id uuid) to authenticated;
grant execute on function private.admin_save_venue(p_id uuid, p_name text, p_category text, p_duration integer, p_address text, p_active boolean) to authenticated;
grant execute on function private.admin_venue_applications(p_status text DEFAULT 'pending'::text) to authenticated;
grant execute on function private.admin_venues() to authenticated;
grant execute on function private.app_settings_public() to authenticated;
grant execute on function private.apply_venue(p_name text, p_category text, p_address text, p_hours text, p_contact text, p_duration integer) to authenticated;
grant execute on function private.block_member(p_user uuid) to authenticated;
grant execute on function private.blocked_between(a uuid, b uuid) to authenticated;
grant execute on function private.buy_pass_simulated() to authenticated;
grant execute on function private.close_conversation(p_id uuid) to authenticated;
grant execute on function private.co_present(viewer uuid, owner uuid) to authenticated;
grant execute on function private.conversation_messages(p_id uuid) to authenticated;
grant execute on function private.delete_account() to authenticated;
grant execute on function private.join_venue(p_token text) to authenticated;
grant execute on function private.leave_venue() to authenticated;
grant execute on function private.meeting_answer(p_conversation uuid, p_yes boolean) to authenticated;
grant execute on function private.my_account_type() to authenticated;
grant execute on function private.my_data_export() to authenticated;
grant execute on function private.my_inbox() to authenticated;
grant execute on function private.my_notifications(p_mark_read boolean DEFAULT false) to authenticated;
grant execute on function private.my_passes() to authenticated;
grant execute on function private.my_pro_profile() to authenticated;
grant execute on function private.my_venue() to authenticated;
grant execute on function private.preview_venue(p_token text) to authenticated;
grant execute on function private.report_member(p_user uuid, p_category text, p_details text DEFAULT NULL::text, p_conversation uuid DEFAULT NULL::uuid) to authenticated;
grant execute on function private.respond_introduction(p_id uuid, p_accept boolean, p_reply text DEFAULT NULL::text) to authenticated;
grant execute on function private.save_pro_profile(p_business text, p_professional text, p_category text, p_pitch text, p_website text, p_socials jsonb, p_city text) to authenticated;
grant execute on function private.save_profile(p_name text, p_birth_date date, p_locale text, p_accept_rules boolean, p_bio text DEFAULT NULL::text, p_avatar_path text DEFAULT NULL::text) to authenticated;
grant execute on function private.send_enquiry(p_pro uuid, p_message text, p_contact text DEFAULT NULL::text) to authenticated;
grant execute on function private.send_introduction(p_to uuid, p_message text) to authenticated;
grant execute on function private.send_message(p_conversation uuid, p_body text) to authenticated;
grant execute on function private.set_account_type(p_type text) to authenticated;
grant execute on function private.submit_feedback(p_score integer, p_change text, p_bug boolean, p_bug_text text, p_context jsonb DEFAULT '{}'::jsonb) to authenticated;
grant execute on function private.subscribe_talent_simulated() to authenticated;
grant execute on function private.venue_announce(p_body text) to authenticated;
grant execute on function private.venue_create_invite(p_days integer DEFAULT 7) to authenticated;
grant execute on function private.venue_delete_announcement(p_id uuid) to authenticated;
grant execute on function private.venue_members() to authenticated;
grant execute on function private.venue_revoke_invite(p_id uuid) to authenticated;
grant execute on function private.venue_room() to authenticated;
grant execute on function private.venue_talents() to authenticated;
grant execute on function private.venue_update(p_hours text, p_contact text, p_duration integer) to authenticated;
grant execute on function public.admin_audit(p_limit integer DEFAULT 100) to authenticated, service_role;
grant execute on function public.admin_create_invite(p_venue uuid, p_days integer DEFAULT 30) to authenticated, service_role;
grant execute on function public.admin_decide_pro(p_user uuid, p_approve boolean, p_decision text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.admin_decide_report(p_id uuid, p_status text, p_decision text, p_suspend boolean DEFAULT false) to authenticated, service_role;
grant execute on function public.admin_decide_venue(p_id uuid, p_approve boolean, p_decision text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.admin_feedback() to authenticated, service_role;
grant execute on function public.admin_members(p_search text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.admin_overview() to authenticated, service_role;
grant execute on function public.admin_passes() to authenticated, service_role;
grant execute on function public.admin_pro_profiles(p_status text DEFAULT 'pending'::text) to authenticated, service_role;
grant execute on function public.admin_refund_pass(p_id uuid) to authenticated, service_role;
grant execute on function public.admin_reports(p_status text DEFAULT 'open'::text) to authenticated, service_role;
grant execute on function public.admin_restrict(p_user uuid, p_suspended boolean, p_reason text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.admin_revoke_invite(p_id uuid) to authenticated, service_role;
grant execute on function public.admin_save_venue(p_id uuid, p_name text, p_category text, p_duration integer, p_address text, p_active boolean) to authenticated, service_role;
grant execute on function public.admin_venue_applications(p_status text DEFAULT 'pending'::text) to authenticated, service_role;
grant execute on function public.admin_venues() to authenticated, service_role;
grant execute on function public.app_settings_public() to authenticated, service_role;
grant execute on function public.apply_venue(p_name text, p_category text, p_address text, p_hours text, p_contact text, p_duration integer) to authenticated, service_role;
grant execute on function public.block_member(p_user uuid) to authenticated, service_role;
grant execute on function public.buy_pass_simulated() to authenticated, service_role;
grant execute on function public.close_conversation(p_id uuid) to authenticated, service_role;
grant execute on function public.conversation_messages(p_id uuid) to authenticated, service_role;
grant execute on function public.delete_account() to authenticated, service_role;
grant execute on function public.is_admin() to authenticated, service_role;
grant execute on function public.join_venue(p_token text) to authenticated, service_role;
grant execute on function public.leave_venue() to authenticated, service_role;
grant execute on function public.meeting_answer(p_conversation uuid, p_yes boolean) to authenticated, service_role;
grant execute on function public.my_account_type() to authenticated, service_role;
grant execute on function public.my_data_export() to authenticated, service_role;
grant execute on function public.my_inbox() to authenticated, service_role;
grant execute on function public.my_notifications(p_mark_read boolean DEFAULT false) to authenticated, service_role;
grant execute on function public.my_passes() to authenticated, service_role;
grant execute on function public.my_pro_profile() to authenticated, service_role;
grant execute on function public.my_venue() to authenticated, service_role;
grant execute on function public.preview_venue(p_token text) to authenticated, service_role;
grant execute on function public.report_member(p_user uuid, p_category text, p_details text DEFAULT NULL::text, p_conversation uuid DEFAULT NULL::uuid) to authenticated, service_role;
grant execute on function public.respond_introduction(p_id uuid, p_accept boolean, p_reply text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.save_pro_profile(p_business text, p_professional text, p_category text, p_pitch text, p_website text, p_socials jsonb, p_city text) to authenticated, service_role;
grant execute on function public.save_profile(p_name text, p_birth_date date, p_locale text, p_accept_rules boolean, p_bio text DEFAULT NULL::text, p_avatar_path text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.send_enquiry(p_pro uuid, p_message text, p_contact text DEFAULT NULL::text) to authenticated, service_role;
grant execute on function public.send_introduction(p_to uuid, p_message text) to authenticated, service_role;
grant execute on function public.send_message(p_conversation uuid, p_body text) to authenticated, service_role;
grant execute on function public.set_account_type(p_type text) to authenticated, service_role;
grant execute on function public.submit_feedback(p_score integer, p_change text, p_bug boolean, p_bug_text text, p_context jsonb DEFAULT '{}'::jsonb) to authenticated, service_role;
grant execute on function public.subscribe_talent_simulated() to authenticated, service_role;
grant execute on function public.venue_announce(p_body text) to authenticated, service_role;
grant execute on function public.venue_create_invite(p_days integer DEFAULT 7) to authenticated, service_role;
grant execute on function public.venue_delete_announcement(p_id uuid) to authenticated, service_role;
grant execute on function public.venue_members() to authenticated, service_role;
grant execute on function public.venue_revoke_invite(p_id uuid) to authenticated, service_role;
grant execute on function public.venue_room() to authenticated, service_role;
grant execute on function public.venue_talents() to authenticated, service_role;
grant execute on function public.venue_update(p_hours text, p_contact text, p_duration integer) to authenticated, service_role;

-- Push notifications (migration db/2026-11-07-push-notifications.sql, applied on ProRod on the date logged in docs/verification-log.md).
create or replace function private.unread_total(p_uid uuid) returns integer language sql stable security definer set search_path = '' as $$
  select (
    (select count(*) from public.introductions i where i.recipient_id=p_uid and i.status='pending' and not private.blocked_between(p_uid,i.sender_id))
  + (select count(*) from public.messages m join public.conversations c on c.id=m.conversation_id
       where (c.a_id=p_uid or c.b_id=p_uid) and m.sender_id<>p_uid
         and not private.blocked_between(p_uid,case when c.a_id=p_uid then c.b_id else c.a_id end)
         and m.created_at>coalesce((select r.read_at from public.conversation_reads r where r.conversation_id=c.id and r.user_id=p_uid),'epoch'::timestamptz))
  + (select count(*) from public.notifications n where n.user_id=p_uid and n.read_at is null))::integer
$$;

create or replace function private.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  if p_endpoint is null or p_endpoint not like 'https://%' or char_length(p_endpoint) not between 20 and 1000
     or char_length(coalesce(p_p256dh,'')) not between 20 and 200 or char_length(coalesce(p_auth,'')) not between 8 and 100 then
    raise exception 'invalid_subscription';
  end if;
  -- One browser = one endpoint: signing in with another account on the same phone moves it to that account.
  insert into public.push_subscriptions(user_id,endpoint,p256dh,auth) values(uid,p_endpoint,p_p256dh,p_auth)
  on conflict (endpoint) do update set user_id=excluded.user_id, p256dh=excluded.p256dh, auth=excluded.auth, created_at=now();
  -- At most 10 devices per member.
  delete from public.push_subscriptions where user_id=uid and id not in (select id from public.push_subscriptions where user_id=uid order by created_at desc limit 10);
end $$;

create or replace function private.delete_push_subscription(p_endpoint text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member();
begin
  delete from public.push_subscriptions where endpoint=p_endpoint and user_id=uid;
end $$;

create or replace function private.push_status() returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := private.require_member();  -- checked first, whatever the table holds
begin
  return jsonb_build_object('devices',(select count(*) from public.push_subscriptions where user_id=uid));
end $$;

create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text) returns void language sql set search_path = '' as $$ select private.save_push_subscription(p_endpoint,p_p256dh,p_auth) $$;

create or replace function public.delete_push_subscription(p_endpoint text) returns void language sql set search_path = '' as $$ select private.delete_push_subscription(p_endpoint) $$;

create or replace function public.push_status() returns jsonb language sql set search_path = '' as $$ select private.push_status() $$;

create or replace function private.push_on_notification() returns trigger language plpgsql security definer set search_path = '' as $$
declare secret text; url text; subs jsonb; lang text;
begin
  begin
    select jsonb_agg(jsonb_build_object('endpoint',s.endpoint,'p256dh',s.p256dh,'auth',s.auth)) into subs from public.push_subscriptions s where s.user_id=new.user_id;
    if subs is null then return new; end if;
    select decrypted_secret into secret from vault.decrypted_secrets where name='push_hook_secret' limit 1;
    url := private.setting('push_function_url') #>> '{}';
    if secret is null or url is null then return new; end if;
    select coalesce(p.locale,'fr') into lang from public.profiles p where p.user_id=new.user_id;
    perform net.http_post(url:=url,
      headers:=jsonb_build_object('content-type','application/json','x-push-secret',secret),
      body:=jsonb_build_object('kind',new.kind,'lang',coalesce(lang,'fr'),'badge',private.unread_total(new.user_id),'subscriptions',subs));
    update public.push_subscriptions set last_sent_at=now() where user_id=new.user_id;
  exception when others then
    raise warning 'push_on_notification: %', sqlerrm;
  end;
  return new;
end $$;
revoke all on function private.unread_total(uuid), private.push_on_notification() from public, anon, authenticated;
grant execute on function private.save_push_subscription(text,text,text), private.delete_push_subscription(text), private.push_status() to authenticated;
grant execute on function public.save_push_subscription(text,text,text), public.delete_push_subscription(text), public.push_status() to authenticated, service_role;

-- Private profile gender, deployed 9 November 2026.
create or replace function private.save_member_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text,p_avatar_path text,p_gender text)
returns public.profiles language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); result public.profiles;
begin
  if p_gender is not null and p_gender not in ('woman','man','non_binary','another_identity','prefer_not_to_say') then
    raise exception 'invalid_gender';
  end if;
  result := private.save_profile(p_name,p_birth_date,p_locale,p_accept_rules,p_bio,p_avatar_path);
  if result.account_type = 'venue' then raise exception 'person_required'; end if;
  update public.profiles set gender=p_gender, updated_at=now() where user_id=uid returning * into result;
  return result;
end $$;
create or replace function public.save_member_profile(p_name text,p_birth_date date,p_locale text,p_accept_rules boolean,p_bio text,p_avatar_path text,p_gender text)
returns public.profiles language sql security invoker set search_path = '' as $$
  select private.save_member_profile(p_name,p_birth_date,p_locale,p_accept_rules,p_bio,p_avatar_path,p_gender)
$$;
revoke all on function private.save_member_profile(text,date,text,boolean,text,text,text) from public,anon;
revoke all on function public.save_member_profile(text,date,text,boolean,text,text,text) from public,anon;
grant execute on function private.save_member_profile(text,date,text,boolean,text,text,text) to authenticated;
grant execute on function public.save_member_profile(text,date,text,boolean,text,text,text) to authenticated;

-- Test bots for the pilot venue (db/2026-11-10-test-bots.sql).
create or replace function private.bot_as(p_uid uuid) returns void language sql set search_path = '' as $$
  select set_config('request.jwt.claims', case when p_uid is null then '' else jsonb_build_object('sub',p_uid::text,'role','authenticated')::text end, true)::void
$$;

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

-- « Who would you like to see? » (db/2026-11-10-interest-filter.sql).
create or replace function private.set_interest(p_interest text, p_consent boolean) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_member(); me public.profiles;
begin
  select * into me from public.profiles where user_id=uid for update;
  if not found then raise exception 'profile_required'; end if;
  if me.account_type='venue' then raise exception 'person_required'; end if;
  if p_interest is null or p_interest='' then
    update public.profiles set interested_in=null, interest_consent_at=null, updated_at=now() where user_id=uid;
    return jsonb_build_object('interested_in',null);
  end if;
  if p_interest not in ('women','men','everyone') then raise exception 'invalid_interest'; end if;
  if p_consent is distinct from true then raise exception 'interest_consent_required'; end if;
  update public.profiles set interested_in=p_interest, interest_consent_at=coalesce(case when interested_in is not null then interest_consent_at end, now()), updated_at=now() where user_id=uid;
  return jsonb_build_object('interested_in',p_interest);
end $$;

create or replace function public.set_interest(p_interest text, p_consent boolean) returns jsonb language sql set search_path = '' as $$ select private.set_interest(p_interest,p_consent) $$;
grant execute on function private.set_interest(text,boolean) to authenticated;
grant execute on function public.set_interest(text,boolean) to authenticated, service_role;
