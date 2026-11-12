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
| 7 November 2026 (evening) | Passkey on a real Android phone: created after sign-in, then sign-in with biometrics (no email, password or code) | PASS |

## 8 November 2026 - member interface redesign

- Short bilingual welcome/installer with direct registration and sign-in links.
- Member screens share a mobile layout and three persistent tabs: venue, messages, profile. Venue-management accounts retain their separate workflow.
- Venue home prioritises scan/join/discovery. Session/pass details are expandable; simulated-payment labels remain visible.
- Settings group the existing profile, sign-in methods, passkeys, notifications, data, account and safety controls. Email sign-in remains available behind an explicit disclosure.
- Discovery uses photo cards; chat and consent screens inherit the same spacing, contrast and typography. No backend, entitlement or moderation rule changed.
- Validation: production build; 44 Node tests; browser checks at 390px and desktop for welcome and sign-in; local fictional fixtures for venue home, settings and discovery. No real account mutation or SMS sent. Fixtures are not shipped.
- Remaining: real-device signed-in pilot, SMS delivery diagnosis, client acceptance. These UI checks do not certify those integrations.


## 9 November 2026 — optional private gender and meeting readiness
- Added optional gender (woman/man/non-binary/another identity/prefer not to say, plus clear/blank) to personal/pro onboarding and settings, FR/EN. Venue onboarding unchanged. No attraction field or pricing rule added.
- `save_member_profile` wraps the existing validated profile save in one transaction. Owner-only profiles RLS unchanged; explicit RPC grants, no anonymous access. Old save_profile remains compatible with cached clients and venue accounts.
- Live transaction-only `db/verify-private-gender.sql`: PASS for all choices, reload, clearing, export, invalid value rollback, other-user isolation, venue denial and anonymous privilege check. Synthetic users rolled back.
- Full existing `db/verify-accounts-and-venues.sql` executed without SQL errors after correcting global pending-application counts to scope assertions to fixtures. The original assertion assumed an empty live queue; no real application was changed. This verifies backend rules, not handset acceptance.
- Supabase security advisor: no new error; existing leaked-password protection warning remains. No-policy RLS notices correspond to RPC-only tables; do not add broad access policies to silence them.
- Meeting readiness and launch gaps: `docs/meeting-readiness.md`. No payment, SMS purchase, legal approval or store publication claimed.

| 10 November 2026 | Venue joined only by QR (typed code removed); `db/seed-test-venue.sql` (test venue + 6 fictional profiles) tested twice and cleaned up on a local PostgreSQL 16 with stand-in tables; poster QR decoded back to the right link | PASS locally; to run on ProRod |
| 10 November 2026 | Test bots (`db/2026-11-10-test-bots.sql`): full journey played on a local PostgreSQL 16 loaded with the project schema and all functions — tester sees 6 profiles, Maya accepts (reply hidden until the simulated pass, writing refused without it), Karim declines (tester sees waiting), Sam introduces himself, chat answers, meeting proposed and agreed, notifications created, bots never talk to each other | PASS locally; to run on ProRod |
| 10 November 2026 | « Who would you like to see? » (`db/2026-11-10-interest-filter.sql`) on a local PostgreSQL 16 with the project schema: refused without consent; women → the 3 women, men → the 3 men, everyone/blank → all 6; member card without gender or preference; own export includes it; withdrawal erases consent. Test venue profiles now carry a gender | PASS locally; to run on ProRod |
| 10 November 2026 | `db/2026-11-10-height-safety.sql` on a local PostgreSQL 16 built in the production state: height saved and refused out of range, shown in list and card; end reason stored, invalid reason refused, other person sees it and is notified; report « insults » blocks automatically (pending introduction cancelled, no longer listed, cannot introduce again); warning refused for non-admins, works for an admin with aal2 (notification, report actioned, logged). Pin photos checked in a browser | PASS locally; to run on ProRod |
| 11 November 2026 | `db/2026-11-11-veiled-venue.sql` on a local PostgreSQL 16 built from the project schema, migrations and functions: without a pass the venue list returns only veiled rows (0 identifying fields out of 6 rows), département + age range correct; introduction refused (`pass_required`); storage shows only one's own photo; with the simulated pass the full list, the département and all photos; the recipient of an introduction (no pass) sees the sender's photo and no other; `pass_rule` none → nothing veiled; départements 20 and 99 refused, « 2a » saved as 2A; age ranges 18-20 / 21-25 / 26-30 / 36-40 / 41-45 checked. Standalone file `db/verify-veiled-venue.sql` PASS locally (to rerun on ProRod after the migration). Seed re-run with départements. 52 Node tests pass. | PASS (local) |
| 12 November 2026 | `db/2026-11-12-apply-pending-migrations.sql` (the five pending migrations in one transaction) on a local PostgreSQL 16 rebuilt in the live state found by the review (functions as of `dfd5582`: no preference/height/département columns, old venue list, report without block): applied, then applied a second time without error; `db/verify-veiled-venue.sql` PASS; full journey as the app calls it: profile + preference + height + département saved, venue veiled before the pass (no name), women-only list after the pass, introduction, bot reply, message, end with reason, report → automatic block → reported person disappears from the reporter's list, `admin_warn_member` present. Not yet applied on ProRod: the Supabase connector of this session only reaches another organisation. | PASS (local) |
