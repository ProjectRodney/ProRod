# Verification log

Three statuses per feature, kept in `docs/product-flow.md`:

- **implemented**: code and database functions exist, Node tests pass (`npm test`).
- **verified with two accounts**: the matching section of `db/verify-accounts-and-venues.sql` ran against the ProRod project and printed PASS (each section creates two to four fixture accounts and rolls everything back), or a two-phone test took place.
- **accepted by Rodney**: the client tried it and said yes.

How to run the database checks: open the Supabase SQL editor on the ProRod project, paste one section (from `begin;` to `rollback;`) and run it; the last row must read `PASS: …`. Nothing is kept: every section ends with `rollback`.

How to refresh `db/functions.sql` after a migration: run in the SQL editor
`select pg_get_functiondef(p.oid) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('private','public') and p.prokind='f' and not exists(select 1 from pg_depend d where d.objid=p.oid and d.deptype='e') order by n.nspname desc, p.proname;`
and replace the definitions in the file (grants at the end of the file stay as they are unless a function was added).

| Date | Sections | Result |
|---|---|---|
| 5 November 2026 | 1 base, 2 discovery, 3 introductions, 4 admin, 5 notifications, 6 meeting/export | all PASS |
| 6 November 2026 (night) | 1–6 re-run with the pass rule, 7 account types / venues / pros | all PASS |
| 6 November 2026 (evening) | 3 with chat-only-while-co-present and refusals across visits, 4 with two-step verification always required | PASS, PASS |
| 7 November 2026 | 3b pass expiry (new): logic run on a local PostgreSQL 16 with stand-in tables (old rule reproduced the bug, new rule passed); migration parsed | migration applied on ProRod |
| 7 November 2026 (afternoon) | whole file in one run (1, 2, 3, 3b, 4, 5, 6, 7) after `db/2026-11-07-pass-expiry.sql` | all PASS (run stops at the first failure; final row was section 7's PASS) |
| 7 November 2026 (evening) | `db/2026-11-07-rename-anziak.sql` applied on ProRod (feedback e-mails renamed ANZIAK) | Success |
| 7 November 2026 (evening) | Edge Function `send-sms` redeployed from the repository (ANZIAK text and SMS sender) | Deployed; SMS delivery still to test on a phone |
| 7 November 2026 (evening) | Supabase Auth SMTP: sender ANZIAK, Brevo relay port 587, login = the client's Brevo SMTP login (only active key, created 7 November) | Configured; delivery to confirm with a real sign-up |
| 7 November 2026 (15:07 Paris) | Real sign-up: confirmation e-mail delivered from ANZIAK through the client's Brevo SMTP (arrived in Yahoo spam: free-mail sender, expected until a domain is authenticated) | Delivered; link click and spam rate to follow |
| 7 November 2026 (afternoon) | Confirmation link opened after moving the e-mail out of Yahoo spam: account confirmed, signed in to ANZIAK (pilot step 2.2) | PASS; e-mails land in spam until a domain is authenticated |
| 7 November 2026 (evening) | Push notifications, local checks: web-push encryption with the project VAPID keys decrypted as a phone would; service worker shows « ANZIAK — Nouveau message. » and opens the app (Chromium, CDP push); migration + trigger on PostgreSQL 16 with stand-in tables (body = kind, language, count; ownership; https only; silent without secret/devices; failure never blocks) | PASS locally; sections 8 and 8b to run on ProRod after deployment |
| 7 November 2026 (evening) | `db/2026-11-07-phone-members.sql` and `db/2026-11-07-push-notifications.sql` applied on ProRod | Success; Edge Function send-push, secrets and sections 8/8b next |
| 7 November 2026 (evening) | Edge Function secrets saved for push (VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, PUSH_HOOK_SECRET, VAPID_SUBJECT), key pair rotated before first use | Saved; Vault secret, send-push deployment and sections 8/8b next |
| 7 November 2026 (evening) | Edge Function send-push deployed; check 8 PASS on ProRod; check 8b found push_status skipping the membership check when no device exists → fixed (`db/2026-11-07-push-status-fix.sql`, verified locally) | 8 PASS; 8b to re-run after the fix |
| 7 November 2026 (evening) | `db/2026-11-07-push-status-fix.sql` applied; whole check file re-run on ProRod, final row = section 8b PASS (every section before it passed) | all PASS |
| 7 November 2026 (evening) | Supabase Authentication → Passkeys enabled (display name ANZIAK, RP ID projectrodney.github.io, origin https://projectrodney.github.io); app flag providers.passkey on | Configured; real-phone test next |
