-- ANZIAK pilot: a fictional test venue, its QR invitation and 6 fictional profiles checked in there.
-- Run in the Supabase SQL editor of the ProRod project (postgres role). Everything is in one transaction.
-- Re-run it any time: it is idempotent and puts the 6 profiles back « present » for 3 hours.
--
-- The QR code's token is NEVER stored here (public repository): DZOFT generates it, keeps it out of Git and
-- replaces REPLACE_WITH_TOKEN_HASH below by sha256(token) in hexadecimal. The QR code encodes
-- https://projectrodney.github.io/ProRod/account.html?venue=<token>.
--
-- The fictional people are marked « (test) » in their name and « [Profil de test] » in their bio, have no password
-- (nobody can sign in as them), use the reserved domain example.invalid, and have no photo (the app shows their
-- initial). They never answer: they only let testers see a populated venue and send introductions.
-- Remove everything with the clean-up block at the end of this file.

begin;

do $$ begin
  if 'REPLACE_WITH_TOKEN_HASH' !~ '^[0-9a-f]{64}$' then raise exception 'Fill in the sha256 of the QR token first (given by DZOFT, never in Git)'; end if;
end $$;

insert into private.venues (id, name, category, duration_minutes, active, address)
values ('a2c1a2c1-0000-4000-8000-000000000001', 'ANZIAK · Lieu de test', 'test', 180, true, 'Lieu fictif du pilote')
on conflict (id) do update set active = true, duration_minutes = 180, name = excluded.name;

insert into private.venue_invites (id, venue_id, token_hash, expires_at)
values ('a2c1a2c1-0000-4000-8000-000000000002', 'a2c1a2c1-0000-4000-8000-000000000001', 'REPLACE_WITH_TOKEN_HASH', now() + interval '30 days')
on conflict (id) do update set token_hash = excluded.token_hash, expires_at = excluded.expires_at, revoked_at = null;

insert into auth.users (id, email, email_confirmed_at, is_anonymous) values
  ('a2c1a2c1-0000-4000-8000-0000000000f1', 'maya.test@example.invalid',  now(), false),
  ('a2c1a2c1-0000-4000-8000-0000000000f2', 'sam.test@example.invalid',   now(), false),
  ('a2c1a2c1-0000-4000-8000-0000000000f3', 'lea.test@example.invalid',   now(), false),
  ('a2c1a2c1-0000-4000-8000-0000000000f4', 'karim.test@example.invalid', now(), false),
  ('a2c1a2c1-0000-4000-8000-0000000000f5', 'aicha.test@example.invalid', now(), false),
  ('a2c1a2c1-0000-4000-8000-0000000000f6', 'tom.test@example.invalid',   now(), false)
on conflict (id) do nothing;

insert into public.profiles (user_id, display_name, birth_date, locale, bio, avatar_path, account_type, gender) values
  ('a2c1a2c1-0000-4000-8000-0000000000f1', 'Maya (test)',  '1999-04-12', 'fr', '[Profil de test] Jazz, terrasses et concerts.', 'u/a2c1a2c1-0000-4000-8000-0000000000f1/test.jpg', 'personal', 'woman'),
  ('a2c1a2c1-0000-4000-8000-0000000000f2', 'Sam (test)',   '1995-09-03', 'en', '[Test profile] New in town, loves live music.', 'u/a2c1a2c1-0000-4000-8000-0000000000f2/test.jpg', 'personal', 'man'),
  ('a2c1a2c1-0000-4000-8000-0000000000f3', 'Léa (test)',   '2002-01-25', 'fr', '[Profil de test] Danse et voyages.', 'u/a2c1a2c1-0000-4000-8000-0000000000f3/test.jpg', 'personal', 'woman'),
  ('a2c1a2c1-0000-4000-8000-0000000000f4', 'Karim (test)', '1997-06-30', 'fr', '[Profil de test] Football et cuisine.', 'u/a2c1a2c1-0000-4000-8000-0000000000f4/test.jpg', 'personal', 'man'),
  ('a2c1a2c1-0000-4000-8000-0000000000f5', 'Aïcha (test)', '1993-11-08', 'fr', '[Profil de test] Photo et expositions.', 'u/a2c1a2c1-0000-4000-8000-0000000000f5/test.jpg', 'personal', 'woman'),
  ('a2c1a2c1-0000-4000-8000-0000000000f6', 'Tom (test)',   '2000-02-14', 'en', '[Test profile] Live music and board games.', 'u/a2c1a2c1-0000-4000-8000-0000000000f6/test.jpg', 'personal', 'man')
on conflict (user_id) do update set display_name = excluded.display_name, bio = excluded.bio, avatar_path = excluded.avatar_path, gender = excluded.gender;

-- Present now, for 3 hours (the venue's maximum): close any open visit, then open a fresh one.
update public.venue_sessions set ended_at = now()
where user_id in (select id from auth.users where email like '%.test@example.invalid') and ended_at is null;

insert into public.venue_sessions (user_id, venue_id, invite_id, venue_name, expires_at)
select u.id, 'a2c1a2c1-0000-4000-8000-000000000001', 'a2c1a2c1-0000-4000-8000-000000000002', 'ANZIAK · Lieu de test', now() + interval '180 minutes'
from auth.users u where u.email like '%.test@example.invalid';

-- Test bots on (db/2026-11-10-test-bots.sql must have been run once): the fictional people answer, chat,
-- propose to meet and Sam introduces himself; Karim always declines.
insert into private.app_settings(key,value) values ('test_bots','true') on conflict (key) do update set value='true';

commit;

select 'Test venue ready: ' || count(*) || ' fictional profiles present until ' || to_char(max(s.expires_at) at time zone 'Europe/Paris', 'HH24:MI') || ' (Paris)' as result
from public.venue_sessions s where s.venue_id = 'a2c1a2c1-0000-4000-8000-000000000001' and s.ended_at is null and s.expires_at > now()
  and s.user_id in (select id from auth.users where email like '%.test@example.invalid');

-- Clean-up after the pilot (uncomment and run): stops the bots, removes the 6 fictional accounts (their profiles, visits,
-- introductions and messages follow), then revokes the QR code and closes the venue.
-- update private.app_settings set value='false' where key='test_bots';
-- delete from auth.users where email like '%.test@example.invalid';
-- update private.venue_invites set revoked_at = now() where id = 'a2c1a2c1-0000-4000-8000-000000000002';
-- update public.venue_sessions set ended_at = now() where venue_id = 'a2c1a2c1-0000-4000-8000-000000000001' and ended_at is null;
-- update private.venues set active = false where id = 'a2c1a2c1-0000-4000-8000-000000000001';
