-- A member and a professional can exchange inside the app (26 Nov 2026, decision of DZOFT: part of the delivery).
-- Until now a member sent one request and the professional could only answer by the contact left, outside the app.
-- A request becomes a thread: the member opens it (as before, while both are in the same venue), then both can write.
-- It stays apart from the dating side: nothing here creates an introduction or a conversation, a professional still
-- cannot start anything, and no message is read or analysed. Same protections as everywhere: close, block, report.
begin;

create table if not exists public.enquiry_messages (
  id uuid primary key default gen_random_uuid(),
  enquiry_id uuid not null references public.enquiries(id) on delete cascade,
  sender_id uuid not null references auth.users(id) on delete cascade,
  body text not null check (char_length(btrim(body)) between 1 and 1000),
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists enquiry_messages_thread_idx on public.enquiry_messages(enquiry_id, created_at);
alter table public.enquiry_messages enable row level security;
revoke all on public.enquiry_messages from anon, authenticated;

alter table public.enquiries add column if not exists closed_at timestamptz;
alter table public.enquiries add column if not exists closed_by uuid references auth.users(id) on delete set null;
alter table public.enquiries add column if not exists from_read_at timestamptz;
alter table public.enquiries add column if not exists pro_read_at timestamptz;
create index if not exists enquiries_from_idx on public.enquiries(from_id, created_at desc);
alter table public.reports add column if not exists enquiry_id uuid references public.enquiries(id) on delete set null;

-- Whether the thread still accepts messages, seen from one of its two people. A block is never named: it reads as closed.
create or replace function private.enquiry_open(e public.enquiries) returns boolean
 language sql stable security definer set search_path to '' as $function$
  select e.closed_at is null and not private.blocked_between(e.from_id,e.pro_id)
    and not exists(select 1 from private.account_restrictions r where r.user_id in (e.from_id,e.pro_id) and r.suspended)
    and exists(select 1 from public.pro_profiles t join public.profiles p on p.user_id=t.user_id
               where t.user_id=e.pro_id and t.status='approved' and p.account_type='pro')
$function$;

-- How many messages the professional has sent since the member last wrote. Three unanswered at most: a professional
-- answers a request, he does not chase a member.
create or replace function private.enquiry_pro_streak(e public.enquiries) returns integer
 language sql stable security definer set search_path to '' as $function$
  select count(*)::integer from public.enquiry_messages m where m.enquiry_id=e.id and m.sender_id=e.pro_id
    and m.created_at > coalesce((select max(x.created_at) from public.enquiry_messages x where x.enquiry_id=e.id and x.sender_id=e.from_id), e.created_at)
$function$;

create or replace function private.reply_enquiry(p_id uuid, p_body text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); e public.enquiries; row public.enquiry_messages; other uuid; shown text;
begin
  if p_body is null or char_length(btrim(p_body)) not between 1 and 1000 then raise exception 'enquiry_length'; end if;
  select * into e from public.enquiries where id=p_id and (from_id=uid or pro_id=uid) for update;
  if not found then raise exception 'enquiry_missing'; end if;
  if not private.enquiry_open(e) then raise exception 'enquiry_closed'; end if;
  if uid=e.pro_id then
    if private.enquiry_pro_streak(e)>=3 then raise exception 'enquiry_wait'; end if;
    other := e.from_id;
    select coalesce(nullif(btrim(t.business_name),''),p.display_name) into shown from public.pro_profiles t join public.profiles p on p.user_id=t.user_id where t.user_id=uid;
  else
    if (select count(*) from public.enquiry_messages m where m.sender_id=uid and m.created_at>now()-interval '1 day')>=60 then raise exception 'enquiry_limit'; end if;
    other := e.pro_id;
    select display_name into shown from public.profiles where user_id=uid;
  end if;
  insert into public.enquiry_messages(enquiry_id,sender_id,body) values(e.id,uid,btrim(p_body)) returning * into row;
  if uid=e.pro_id then update public.enquiries set pro_read_at=clock_timestamp() where id=e.id;
  else update public.enquiries set from_read_at=clock_timestamp() where id=e.id; end if;
  perform private.notify(other,'message_received',jsonb_build_object('from',shown,'enquiry',true),'enquiry:'||e.id::text);
  return jsonb_build_object('id',row.id,'created_at',row.created_at);
end $function$;

-- One thread, for one of its two people only. No identifier of the other person leaves the server.
create or replace function private.enquiry_thread(p_id uuid)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); e public.enquiries; is_pro boolean; open boolean;
begin
  select * into e from public.enquiries where id=p_id and (from_id=uid or pro_id=uid);
  if not found then raise exception 'enquiry_missing'; end if;
  is_pro := uid=e.pro_id; open := private.enquiry_open(e);
  if is_pro then update public.enquiries set pro_read_at=clock_timestamp() where id=e.id;
  else update public.enquiries set from_read_at=clock_timestamp() where id=e.id; end if;
  update public.notifications set read_at=now() where user_id=uid and read_at is null and payload->>'key' in (e.id::text,'enquiry:'||e.id::text);
  return jsonb_build_object('id',e.id,'role',case when is_pro then 'pro' else 'member' end,
    'with',case when is_pro then (select p.display_name from public.profiles p where p.user_id=e.from_id)
                else (select coalesce(nullif(btrim(t.business_name),''),t.professional_name) from public.pro_profiles t where t.user_id=e.pro_id) end,
    'category',case when is_pro then null else (select t.category from public.pro_profiles t where t.user_id=e.pro_id) end,
    'venue',(select v.name from private.venues v where v.id=e.venue_id),
    'contact',e.contact,'created_at',e.created_at,'open',open,'closed_by_me',e.closed_by=uid,
    'wait',is_pro and open and private.enquiry_pro_streak(e)>=3,
    'messages',jsonb_build_array(jsonb_build_object('id',e.id,'mine',not is_pro,'body',e.message,'created_at',e.created_at))
      || coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'mine',m.sender_id=uid,'body',m.body,'created_at',m.created_at) order by m.created_at)
                   from public.enquiry_messages m where m.enquiry_id=e.id),'[]'::jsonb));
end $function$;

-- The member's own requests, most recent exchange first.
create or replace function private.my_enquiries()
 returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_person();
begin
  return coalesce((select jsonb_agg(x.row order by x.last_at desc) from (
    select greatest(e.created_at,coalesce(l.created_at,e.created_at)) as last_at,
      jsonb_build_object('id',e.id,
        'with',(select coalesce(nullif(btrim(t.business_name),''),t.professional_name) from public.pro_profiles t where t.user_id=e.pro_id),
        'category',(select t.category from public.pro_profiles t where t.user_id=e.pro_id),
        'last',left(coalesce(l.body,e.message),90),'last_mine',coalesce(l.sender_id,e.from_id)=uid,
        'last_at',greatest(e.created_at,coalesce(l.created_at,e.created_at)),
        'unread',(select count(*) from public.enquiry_messages m where m.enquiry_id=e.id and m.sender_id<>uid and m.created_at>coalesce(e.from_read_at,e.created_at)),
        'open',private.enquiry_open(e)) as row
    from (select * from public.enquiries where from_id=uid order by created_at desc limit 50) e
    left join lateral (select m.body,m.sender_id,m.created_at from public.enquiry_messages m where m.enquiry_id=e.id order by m.created_at desc limit 1) l on true
    where not private.blocked_between(uid,e.pro_id)) x),'[]'::jsonb);
end $function$;

-- Either person closes the thread: nothing more can be written, what was written stays readable.
create or replace function private.close_enquiry(p_id uuid)
 returns void language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person();
begin
  update public.enquiries set closed_at=now(), closed_by=uid where id=p_id and (from_id=uid or pro_id=uid) and closed_at is null;
  if not found and not exists(select 1 from public.enquiries where id=p_id and (from_id=uid or pro_id=uid)) then raise exception 'enquiry_missing'; end if;
end $function$;

-- Block or report the other person of a thread, without the app ever holding their identifier.
create or replace function private.enquiry_block(p_id uuid)
 returns void language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); e public.enquiries;
begin
  select * into e from public.enquiries where id=p_id and (from_id=uid or pro_id=uid);
  if not found then raise exception 'enquiry_missing'; end if;
  perform private.block_member(case when uid=e.pro_id then e.from_id else e.pro_id end);
  update public.enquiries set closed_at=coalesce(closed_at,now()), closed_by=coalesce(closed_by,uid) where id=e.id;
end $function$;

create or replace function private.enquiry_report(p_id uuid, p_category text, p_details text default null)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare uid uuid := private.require_person(); e public.enquiries; r jsonb;
begin
  select * into e from public.enquiries where id=p_id and (from_id=uid or pro_id=uid);
  if not found then raise exception 'enquiry_missing'; end if;
  r := private.report_member(case when uid=e.pro_id then e.from_id else e.pro_id end,p_category,p_details,null);
  update public.reports set enquiry_id=e.id where id=(r->>'id')::uuid;
  update public.enquiries set closed_at=coalesce(closed_at,now()), closed_by=coalesce(closed_by,uid) where id=e.id;
  return r;
end $function$;

-- Blocking someone anywhere also closes the threads between the two.
create or replace function private.close_enquiries_on_block() returns trigger
 language plpgsql security definer set search_path to '' as $function$
begin
  update public.enquiries set closed_at=now(), closed_by=new.blocker_id
    where closed_at is null and ((from_id=new.blocker_id and pro_id=new.blocked_id) or (from_id=new.blocked_id and pro_id=new.blocker_id));
  return new;
end $function$;
drop trigger if exists close_enquiries_on_block on public.blocks;
create trigger close_enquiries_on_block after insert on public.blocks for each row execute function private.close_enquiries_on_block();

-- The professional's list of requests also says what is unread and whether the thread is still open.
create or replace function private.my_pro_profile()
 returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_member(); row public.pro_profiles;
begin
  select * into row from public.pro_profiles where user_id=uid;
  if not found then return null; end if;
  return jsonb_build_object('business_name',row.business_name,'professional_name',row.professional_name,'category',row.category,'pitch',row.pitch,'website',row.website,'socials',row.socials,'city',row.city,'status',row.status,'decision',row.decision,'subscription_until',row.subscription_until,'subscription_active',row.subscription_until is not null and row.subscription_until>now(),
    'enquiries',coalesce((select jsonb_agg(jsonb_build_object('id',e.id,'message',e.message,'contact',e.contact,'created_at',e.created_at,'from',(select display_name from public.profiles where user_id=e.from_id),'venue',(select name from private.venues where id=e.venue_id),
        'unread',(select count(*) from public.enquiry_messages m where m.enquiry_id=e.id and m.sender_id<>uid and m.created_at>coalesce(e.pro_read_at,e.created_at)) + case when e.pro_read_at is null then 1 else 0 end,
        'answered',exists(select 1 from public.enquiry_messages m where m.enquiry_id=e.id and m.sender_id=uid),
        'last_at',greatest(e.created_at,coalesce((select max(m.created_at) from public.enquiry_messages m where m.enquiry_id=e.id),e.created_at)),
        'open',private.enquiry_open(e)) order by e.created_at desc)
      from (select * from public.enquiries where pro_id=uid and not private.blocked_between(uid,from_id) order by created_at desc limit 50) e),'[]'::jsonb));
end $function$;

-- A report made from a thread shows that thread to the administrator, as a report from a conversation shows it.
create or replace function private.admin_reports(p_status text default 'open'::text)
 returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'created_at',r.created_at,'category',r.category,'details',r.details,'status',r.status,'decision',r.decision,'decided_at',r.decided_at,
      'venue',(select name from private.venues v where v.id=r.venue_id),
      'reporter',private.member_card(r.reporter_id),'reported',private.member_card(r.reported_id),
      'reported_suspended',exists(select 1 from private.account_restrictions a where a.user_id=r.reported_id and a.suspended),
      'reported_report_count',(select count(*) from public.reports x where x.reported_id=r.reported_id),
      'conversation',case
        when r.conversation_id is not null then (select jsonb_agg(jsonb_build_object('from_reported',m.sender_id=r.reported_id,'body',m.body,'created_at',m.created_at) order by m.created_at) from public.messages m where m.conversation_id=r.conversation_id)
        when r.enquiry_id is not null then (select jsonb_build_array(jsonb_build_object('from_reported',e.from_id=r.reported_id,'body',e.message,'created_at',e.created_at))
            || coalesce((select jsonb_agg(jsonb_build_object('from_reported',m.sender_id=r.reported_id,'body',m.body,'created_at',m.created_at) order by m.created_at) from public.enquiry_messages m where m.enquiry_id=e.id),'[]'::jsonb)
          from public.enquiries e where e.id=r.enquiry_id)
        else null end)
    order by r.created_at desc) from public.reports r where p_status is null or r.status=p_status),'[]'::jsonb);
end $function$;

create or replace function public.reply_enquiry(p_id uuid, p_body text) returns jsonb language sql set search_path to '' as $function$ select private.reply_enquiry(p_id,p_body) $function$;
create or replace function public.enquiry_thread(p_id uuid) returns jsonb language sql set search_path to '' as $function$ select private.enquiry_thread(p_id) $function$;
create or replace function public.my_enquiries() returns jsonb language sql set search_path to '' as $function$ select private.my_enquiries() $function$;
create or replace function public.close_enquiry(p_id uuid) returns void language sql set search_path to '' as $function$ select private.close_enquiry(p_id) $function$;
create or replace function public.enquiry_block(p_id uuid) returns void language sql set search_path to '' as $function$ select private.enquiry_block(p_id) $function$;
create or replace function public.enquiry_report(p_id uuid, p_category text, p_details text default null) returns jsonb language sql set search_path to '' as $function$ select private.enquiry_report(p_id,p_category,p_details) $function$;

revoke all on function private.enquiry_open(public.enquiries), private.enquiry_pro_streak(public.enquiries), private.close_enquiries_on_block() from public, anon, authenticated;
revoke all on function private.reply_enquiry(uuid,text), private.enquiry_thread(uuid), private.my_enquiries(), private.close_enquiry(uuid), private.enquiry_block(uuid), private.enquiry_report(uuid,text,text) from public, anon;
revoke all on function public.reply_enquiry(uuid,text), public.enquiry_thread(uuid), public.my_enquiries(), public.close_enquiry(uuid), public.enquiry_block(uuid), public.enquiry_report(uuid,text,text) from public, anon;
grant execute on function private.reply_enquiry(uuid,text), private.enquiry_thread(uuid), private.my_enquiries(), private.close_enquiry(uuid), private.enquiry_block(uuid), private.enquiry_report(uuid,text,text) to authenticated;
grant execute on function public.reply_enquiry(uuid,text), public.enquiry_thread(uuid), public.my_enquiries(), public.close_enquiry(uuid), public.enquiry_block(uuid), public.enquiry_report(uuid,text,text) to authenticated, service_role;

commit;

select 'Exchange between a member and a professional installed' as result;
