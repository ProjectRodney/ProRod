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
