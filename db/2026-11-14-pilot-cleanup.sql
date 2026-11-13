-- UPZONE, 14 November 2026: clean slate before the client's first real test with guests.
-- Run once in the Supabase SQL editor of the ProRod project. Everything is in one transaction; safe to run again.
-- What it does:
--   1. switches the test bots off and removes their every-minute job;
--   2. deletes the 6 fictional accounts « (test) » (their profiles, visits, introductions, messages and passes follow);
--   3. closes the fictional test venue and revokes its QR code (the venue row is kept, inactive, for the history).
-- What it does NOT touch: real accounts, real venues, settings (payments stay simulated), reports, the audit log.
-- Real test accounts (yours, the client's) are not deleted here: do it from each account (Profil → Supprimer mon compte),
-- or look at the list printed at the end and decide.

begin;

insert into private.app_settings(key,value) values ('test_bots','false') on conflict (key) do update set value='false';
do $$ begin
  if exists(select 1 from pg_extension where extname='pg_cron') and exists(select 1 from cron.job where jobname='anziak-test-bots') then
    perform cron.unschedule('anziak-test-bots');
  end if;
end $$;

update public.venue_sessions set ended_at = now()
where venue_id = 'a2c1a2c1-0000-4000-8000-000000000001' and ended_at is null;
update private.venue_invites set revoked_at = coalesce(revoked_at, now())
where venue_id = 'a2c1a2c1-0000-4000-8000-000000000001';
update private.venues set active = false where id = 'a2c1a2c1-0000-4000-8000-000000000001';

delete from auth.users where email like '%.test@example.invalid';

commit;

-- What is left (nothing here is changed): check it looks like a clean start.
select 'fictional accounts left' as item, count(*)::text as value from auth.users where email like '%.test@example.invalid'
union all select 'test bots', (select value::text from private.app_settings where key='test_bots')
union all select 'real accounts', count(*)::text from auth.users where email not like '%.test@example.invalid' or email is null
union all select 'people checked in right now', count(*)::text from public.venue_sessions where ended_at is null and expires_at > now()
union all select 'active venues', count(*)::text from private.venues where active
union all select 'open reports', count(*)::text from public.reports where status='open'
union all select 'pass rule', (select value::text from private.app_settings where key='pass_rule')
union all select 'payments simulated', (select value::text from private.app_settings where key='simulation');
