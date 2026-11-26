-- Real purchases, server side (26 Nov 2026). Nothing here takes money: it is the part that switches a pass on once a
-- purchase has been confirmed with Apple, Google or a card provider by a server function holding the service key.
-- No client can call it, so a phone can never grant itself a pass. Works the same whatever tool confirms the purchase.
-- Same rule for everyone: no price and no right depends on gender.
begin;

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  store text not null check (store in ('apple','google','card')),
  product text not null check (product in ('venue_pass','pro_evening')),
  transaction_id text not null check (char_length(transaction_id) between 6 and 200),
  amount_cents integer not null check (amount_cents between 1 and 100000),
  currency text not null default 'EUR' check (currency ~ '^[A-Z]{3}$'),
  status text not null default 'paid' check (status in ('paid','refunded')),
  granted boolean not null default false,
  note text,
  venue_id uuid references private.venues(id),
  session_id uuid references public.venue_sessions(id) on delete set null,
  pass_id uuid references public.passes(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  refunded_at timestamptz,
  unique (store, transaction_id)
);
create index if not exists purchases_user_idx on public.purchases(user_id, created_at desc);
alter table public.purchases enable row level security;
revoke all on public.purchases from anon, authenticated;

-- Records a confirmed purchase once and switches on what was bought, for the visit that is live.
-- Called again with the same transaction (the stores repeat their notices), it changes nothing.
create or replace function private.record_purchase(p_user uuid, p_store text, p_product text, p_transaction text, p_amount_cents integer, p_currency text default 'EUR')
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare row public.purchases; mine public.venue_sessions; pass public.passes; pro public.pro_profiles; why text;
begin
  if p_user is null or p_transaction is null then raise exception 'purchase_invalid'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_store||':'||p_transaction,0));
  select * into row from public.purchases where store=p_store and transaction_id=p_transaction;
  if found then
    if row.user_id is distinct from p_user or row.product<>p_product then raise exception 'purchase_conflict'; end if;
    return jsonb_build_object('id',row.id,'granted',row.granted,'status',row.status,'note',row.note,'already',true);
  end if;
  if not exists(select 1 from auth.users u where u.id=p_user and (u.email_confirmed_at is not null or u.phone_confirmed_at is not null) and coalesce(u.is_anonymous,false)=false) then raise exception 'purchase_invalid'; end if;

  mine := private.live_session(p_user);
  if exists(select 1 from private.account_restrictions r where r.user_id=p_user and r.suspended) then why := 'suspended';
  elsif mine.id is null then why := 'no_visit';
  elsif p_product='venue_pass' then
    if exists(select 1 from public.profiles p where p.user_id=p_user and p.account_type<>'personal') then why := 'wrong_account';
    elsif exists(select 1 from public.passes x where x.user_id=p_user and x.venue_id=mine.venue_id and x.status='active' and x.kind='venue_pass' and x.expires_at>now() and not x.simulated) then why := 'already_active';
    else
      -- A simulated pass of the test period gives way to the paid one.
      update public.passes set status='expired' where user_id=p_user and venue_id=mine.venue_id and status='active' and kind='venue_pass' and simulated;
      insert into public.passes(user_id,venue_id,session_id,kind,simulated,amount_cents,expires_at)
        values(p_user,mine.venue_id,mine.id,'venue_pass',false,p_amount_cents,mine.expires_at) returning * into pass;
    end if;
  elsif p_product='pro_evening' then
    select * into pro from public.pro_profiles where user_id=p_user for update;
    if not found or pro.status<>'approved' or not private.is_pro(p_user) then why := 'pro_not_approved';
    elsif pro.subscription_session=mine.id and pro.subscription_until>now() and exists(select 1 from public.passes x where x.session_id=mine.id and x.user_id=p_user and x.kind='talent_subscription' and x.status='active' and not x.simulated) then why := 'already_active';
    else
      update public.passes set status='expired' where user_id=p_user and session_id=mine.id and kind='talent_subscription' and status='active' and simulated;
      update public.pro_profiles set subscription_until=mine.expires_at, subscription_session=mine.id, updated_at=now() where user_id=p_user;
      insert into public.passes(user_id,venue_id,session_id,kind,simulated,amount_cents,expires_at)
        values(p_user,mine.venue_id,mine.id,'talent_subscription',false,p_amount_cents,mine.expires_at) returning * into pass;
      begin perform private.announce_talent(p_user, mine);
      exception when others then raise warning 'talent alert skipped: %', sqlerrm; end;
    end if;
  else raise exception 'purchase_invalid';
  end if;

  -- The money was taken, so the purchase is always written down, granted or not: a purchase that could not be
  -- granted is the list of refunds to make.
  insert into public.purchases(user_id,store,product,transaction_id,amount_cents,currency,granted,note,venue_id,session_id,pass_id)
    values(p_user,p_store,p_product,p_transaction,p_amount_cents,upper(p_currency),why is null,why,mine.venue_id,mine.id,pass.id) returning * into row;
  return jsonb_build_object('id',row.id,'granted',row.granted,'status',row.status,'note',row.note,'already',false);
end $function$;

-- A refund reported by the store: what was bought stops at once.
create or replace function private.refund_purchase(p_store text, p_transaction text)
 returns jsonb language plpgsql security definer set search_path to '' as $function$
declare row public.purchases;
begin
  select * into row from public.purchases where store=p_store and transaction_id=p_transaction for update;
  if not found then raise exception 'purchase_missing'; end if;
  if row.status='refunded' then return jsonb_build_object('id',row.id,'status','refunded','already',true); end if;
  update public.purchases set status='refunded', refunded_at=now() where id=row.id;
  if row.pass_id is not null then
    update public.passes set status='refunded', expires_at=least(expires_at,now()) where id=row.pass_id;
    if row.product='pro_evening' then
      update public.pro_profiles set subscription_until=null where user_id=row.user_id and subscription_session=row.session_id;
    end if;
  end if;
  return jsonb_build_object('id',row.id,'status','refunded','already',false);
end $function$;

-- The administrator's list: what was paid, and above all what was paid without being granted.
create or replace function private.admin_purchases(p_limit integer default 100)
 returns jsonb language plpgsql stable security definer set search_path to '' as $function$
declare uid uuid := private.require_admin();
begin
  return coalesce((select jsonb_agg(x.row order by x.created_at desc) from (
    select p.created_at, jsonb_build_object('id',p.id,'created_at',p.created_at,'store',p.store,'product',p.product,'amount_cents',p.amount_cents,'currency',p.currency,
      'status',p.status,'granted',p.granted,'note',p.note,'refunded_at',p.refunded_at,'transaction',p.transaction_id,
      'venue',(select name from private.venues v where v.id=p.venue_id),
      'member',(select display_name from public.profiles f where f.user_id=p.user_id)) as row
    from public.purchases p order by p.created_at desc limit least(greatest(coalesce(p_limit,100),1),500)) x),'[]'::jsonb);
end $function$;
create or replace function public.admin_purchases(p_limit integer default 100) returns jsonb language sql stable set search_path to '' as $function$ select private.admin_purchases(p_limit) $function$;

-- Only a server holding the service key may record or refund a purchase.
create or replace function public.record_purchase(p_user uuid, p_store text, p_product text, p_transaction text, p_amount_cents integer, p_currency text default 'EUR') returns jsonb language sql set search_path to '' as $function$ select private.record_purchase(p_user,p_store,p_product,p_transaction,p_amount_cents,p_currency) $function$;
create or replace function public.refund_purchase(p_store text, p_transaction text) returns jsonb language sql set search_path to '' as $function$ select private.refund_purchase(p_store,p_transaction) $function$;
revoke all on function private.record_purchase(uuid,text,text,text,integer,text), private.refund_purchase(text,text), public.record_purchase(uuid,text,text,text,integer,text), public.refund_purchase(text,text) from public, anon, authenticated;
grant execute on function private.record_purchase(uuid,text,text,text,integer,text), private.refund_purchase(text,text), public.record_purchase(uuid,text,text,text,integer,text), public.refund_purchase(text,text) to service_role;
grant usage on schema private to service_role;
revoke all on function private.admin_purchases(integer), public.admin_purchases(integer) from public, anon;
grant execute on function private.admin_purchases(integer) to authenticated;
grant execute on function public.admin_purchases(integer) to authenticated, service_role;

commit;

select 'Server side of real purchases installed' as result;
