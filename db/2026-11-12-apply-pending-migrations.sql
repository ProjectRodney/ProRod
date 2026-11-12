-- UPZONE, 12 November 2026: the five pending migrations in one transaction (all or nothing).
-- Run once in the Supabase SQL editor of the ProRod project. If any statement fails, nothing is changed.
-- Contents, in order: 2026-11-10-interest-filter, 2026-11-10-rename-upzone, 2026-11-10-height-safety,
-- 2026-11-11-veiled-venue, 2026-11-10-test-bots (bots stay off until the seed switches them on).
-- Then run db/verify-veiled-venue.sql and db/verify-accounts-and-venues.sql (both roll back).
begin;
-- The venue list changes shape below; dropping it first makes this file safe to run again.
drop function if exists public.venue_members();
drop function if exists private.venue_members();

-- ===== db/2026-11-10-interest-filter.sql =====
-- ANZIAK, 10 November 2026: optional « who would you like to see? » (women / men / everyone) to filter the venue list.
-- Run once in the Supabase SQL editor of the ProRod project.
--
-- Data protection: together with gender, this choice reveals sexual orientation, a special category of personal data
-- (GDPR article 9). So: optional; saved only with the member's explicit consent (interest_consent_at); private (owner-only
-- profiles RLS, never in venue_members, member_card or any other member's view); used only to filter the member's own
-- venue list, on the server, without sending anyone's gender to the phone; withdrawable at any time (set to null, consent
-- erased); included in the member's own data export (my_data_export returns the whole profile row). Never used for pricing.

alter table public.profiles add column if not exists interested_in text;
alter table public.profiles add column if not exists interest_consent_at timestamptz;
alter table public.profiles drop constraint if exists profiles_interested_in_check;
alter table public.profiles add constraint profiles_interested_in_check check (interested_in is null or interested_in in ('women','men','everyone'));
alter table public.profiles drop constraint if exists profiles_interest_consent_check;
alter table public.profiles add constraint profiles_interest_consent_check check (interested_in is null or interest_consent_at is not null);

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
revoke all on function private.set_interest(text,boolean) from public, anon;
revoke all on function public.set_interest(text,boolean) from public, anon;
grant execute on function private.set_interest(text,boolean) to authenticated;
grant execute on function public.set_interest(text,boolean) to authenticated, service_role;

-- The venue list follows the viewer's own choice; nobody else's choice or gender leaves the server.
-- « women » / « men »: only members who declared that gender. « everyone » or no choice: everybody, as before.
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


-- ===== db/2026-11-10-rename-upzone.sql =====
-- UPZONE migration of 10 November 2026: the product is renamed from ANZIAK to UPZONE (client decision; run by the client's company).
-- Only the operator feedback e-mails carry the product name inside the database. Run once in the Supabase SQL editor.
update private.app_settings set value='"[UPZONE test] Nouveau retour"' where key='feedback_subject';
update private.venues set name='UPZONE · Lieu de test' where id='a2c1a2c1-0000-4000-8000-000000000001';

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


-- ===== db/2026-11-10-height-safety.sql =====
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


-- ===== db/2026-11-11-veiled-venue.sql =====
-- UPZONE, 11 November 2026 (client decisions of 10–11 November): people in a venue stay veiled until you hold a pass.
-- Run once in the Supabase SQL editor of the ProRod project, after db/2026-11-10-height-safety.sql.
-- • Each member enters their own département (where they live). Shown on the card once unlocked, and on the veiled card.
-- • Without an active pass for the venue (pass_rule = "everyone"), the venue list shows only veiled entries:
--   a neutral silhouette, the département and an age range (18-20, 21-25, 26-30…). No id, name, bio, exact age,
--   height, photo path or arrival time ever leaves the database for them. With the pass, the list is the usual one.
-- • Photos follow the same rule on the storage side: a co-present member reads a photo only when unlocked, or when
--   that person already introduced themselves to them / talks with them.
-- • Introducing yourself needs the pass (you cannot introduce yourself to someone you cannot see).
-- • With pass_rule = "none" nothing is veiled. The pass rule is the same for everyone (never based on gender).

alter table public.profiles add column if not exists department text;
alter table public.profiles drop constraint if exists profiles_department_check;
alter table public.profiles add constraint profiles_department_check
  check (department is null or department ~ '^(0[1-9]|1[0-9]|2[1-9]|[3-8][0-9]|9[0-5]|2A|2B|97[1-6])$');

-- Age range from the private birth date: 18-20, then steps of five (21-25, 26-30…).
create or replace function private.age_band(p_birth date) returns text language sql stable set search_path = '' as $$
  select case when a is null then null when a <= 20 then '18-20' else (21 + 5*((a-21)/5))::text || '-' || (25 + 5*((a-21)/5))::text end
  from (select date_part('year', age(p_birth))::int as a) x
$$;
revoke all on function private.age_band(date) from public, anon, authenticated;

-- True when this member may see the people of this venue: no pass needed, or an active venue pass there.
create or replace function private.venue_unlocked(p_uid uuid, p_venue uuid) returns boolean
 language sql stable security definer set search_path = '' as $$
  select p_uid is not null and p_venue is not null and (
    (private.setting('pass_rule') #>> '{}') is distinct from 'everyone'
    or exists(select 1 from public.passes p where p.user_id=p_uid and p.venue_id=p_venue and p.status='active' and p.kind='venue_pass' and p.expires_at>now()))
$$;
revoke all on function private.venue_unlocked(uuid,uuid) from public, anon, authenticated;

create or replace function private.set_department(p_department text) returns jsonb
 language plpgsql security definer set search_path = '' as $$
declare uid uuid := private.require_person(); d text := nullif(upper(btrim(coalesce(p_department,''))),'');
begin
  if d is not null and d !~ '^(0[1-9]|1[0-9]|2[1-9]|[3-8][0-9]|9[0-5]|2A|2B|97[1-6])$' then raise exception 'invalid_department'; end if;
  update public.profiles set department=d, updated_at=now() where user_id=uid;
  return jsonb_build_object('department',d);
end $$;
create or replace function public.set_department(p_department text) returns jsonb language sql set search_path = '' as $$ select private.set_department(p_department) $$;
revoke all on function private.set_department(text), public.set_department(text) from public, anon;
grant execute on function private.set_department(text) to authenticated;
grant execute on function public.set_department(text) to authenticated, service_role;

drop function if exists public.venue_members();
drop function if exists private.venue_members();
create or replace function private.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean)
 language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); mine public.venue_sessions; wants text; open boolean;
begin
  mine := private.live_session(uid);
  if mine.id is null then raise exception 'no_live_session'; end if;
  select p.interested_in into wants from public.profiles p where p.user_id=uid;
  open := private.venue_unlocked(uid, mine.venue_id);
  return query
    select case when open then p.user_id end, case when open then p.display_name end,
           case when open then date_part('year', age(p.birth_date))::integer end, case when open then p.bio end,
           case when open then p.avatar_path end, case when open then s.started_at end, case when open then p.height_cm end,
           p.department, private.age_band(p.birth_date), not open
    from public.venue_sessions s join public.profiles p on p.user_id=s.user_id
    where s.venue_id=mine.venue_id and s.ended_at is null and s.expires_at>now() and s.user_id<>uid
      and p.account_type<>'venue' and private.profile_complete(p)
      and not private.blocked_between(uid, s.user_id)
      and not exists(select 1 from private.account_restrictions r where r.user_id=s.user_id and r.suspended)
      and (wants is null or wants='everyone' or (wants='women' and p.gender='woman') or (wants='men' and p.gender='man'))
    order by case when open then s.started_at end desc nulls last, p.department nulls last, 9;
end $function$;
create or replace function public.venue_members()
 returns table(user_id uuid, display_name text, age integer, bio text, avatar_path text, since timestamp with time zone, height_cm smallint,
               department text, age_band text, veiled boolean)
 language sql set search_path to '' as $function$ select * from private.venue_members() $function$;
revoke all on function private.venue_members(), public.venue_members() from public, anon;
grant execute on function private.venue_members() to authenticated;
grant execute on function public.venue_members() to authenticated, service_role;

-- Card of a person already in contact with you (introduction, conversation): now with the département.
create or replace function private.member_card(p_user uuid) returns jsonb language sql stable security definer set search_path to '' as $function$
  select jsonb_build_object('user_id',p.user_id,'display_name',p.display_name,'age',date_part('year',age(p.birth_date))::int,'bio',p.bio,'avatar_path',p.avatar_path,'height_cm',p.height_cm,'department',p.department)
  from public.profiles p where p.user_id=p_user
$function$;

-- Photos: co-present AND (unlocked in that venue, or already in contact through an introduction or a conversation).
create or replace function private.photo_visible(viewer uuid, owner uuid) returns boolean
 language sql stable security definer set search_path to '' as $function$
  select private.co_present(viewer, owner) and (
    private.venue_unlocked(viewer, (private.live_session(viewer)).venue_id)
    or exists(select 1 from public.introductions i where (i.sender_id=owner and i.recipient_id=viewer) or (i.sender_id=viewer and i.recipient_id=owner))
    or exists(select 1 from public.conversations c where (c.a_id=viewer and c.b_id=owner) or (c.a_id=owner and c.b_id=viewer)))
$function$;
revoke all on function private.photo_visible(uuid,uuid) from public, anon, authenticated;
grant execute on function private.photo_visible(uuid,uuid) to authenticated;
drop policy if exists avatars_venue_select on storage.objects;
create policy avatars_venue_select on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = 'u'
         and private.photo_visible((select auth.uid()), ((storage.foldername(name))[2])::uuid));

-- Introducing yourself needs the pass of the venue (same rule for everyone).
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
  if (select count(*) from public.introductions i where i.sender_id=uid and i.session_id=mine.id)>=5 then raise exception 'introduction_limit'; end if;
  insert into public.introductions(sender_id,recipient_id,venue_id,session_id,message) values(uid,p_to,mine.venue_id,mine.id,btrim(p_message)) returning * into row;
  perform private.notify(p_to,'introduction_received',jsonb_build_object('from',(select display_name from public.profiles where user_id=uid),'venue',(select name from private.venues where id=mine.venue_id)),row.id::text);
  return jsonb_build_object('id',row.id,'status',row.status,'created_at',row.created_at);
end $function$;


-- ===== db/2026-11-10-test-bots.sql =====
-- UPZONE pilot: automatic fictional members (« test bots ») in the test venue, so one tester can go through the whole
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

commit;
select 'Migrations applied: preferences, UPZONE, height + safety, veiled venue, test bots' as result;
