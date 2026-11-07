# Account and venue implementation

Status: dedicated Supabase project `blqcmpqctetmjqsfdvsq` (ProRod), Paris (`eu-west-3`). Account UI and application schema are connected. Email/password signup, confirmation callbacks, password recovery, private profile onboarding, invitation preview, join and leave are implemented at `account.html`. Email SMTP/redirect configuration and real-device testing remain unverified.

`db/accounts-and-venues.sql` is the applied schema snapshot. `db/verify-accounts-and-venues.sql` runs transaction-only tests with fictional accounts and rolls everything back. Verified: age enforcement, confirmed email, owner-only reads, blocked direct session writes, invitation secrecy, invalid invitation rejection, one venue per account, rescan idempotency, closed invitation reuse denial, leaving and anonymous denial. Security advisor reports only informational notices for three intentionally policy-free private tables; those tables deny client access and are accessed only by tightly scoped server functions.

The pilot has one explicitly labelled test venue, with a 60-minute test session. This is not a decision about production venue durations. Each invitation can be used once per account; a fresh visit requires a fresh invitation. No venue administration UI, member discovery, messages or payments are implemented yet. Do not treat the existing role-switching demo as an authenticated admin interface.

Build: `npm ci`, `npm run build`, `npm test`. The build bundles the pinned Supabase client locally; no runtime CDN dependency. Static hosting serves `dist/`. Only a publishable API key is shipped. Authentication responses and private data are never service-worker cached.

Before real signup testing: deploy to a public HTTPS address (`.github/workflows/deploy.yml` builds, tests and publishes `dist/` to GitHub Pages at https://projectrodney.github.io/ProRod/; the earlier ChatGPT Sites deployment was owner-private and unusable for the client), set `siteUrl` in `src/public-config.js` to that address, then in the ProRod Supabase project configure the Brevo SMTP (the built-in email service only delivers to organization members), Site URL and the allowed redirect `<siteUrl>/account.html`. Keep email confirmation enabled and verify actual inbox delivery with an agreed test user.

## First real journey

1. Register with email and password; verify email before entering a venue.
2. Create profile: display name, private date of birth (18+), French/English preference, acceptance of community rules. No selfie, compulsory photo, surname or telephone required for this social app's first test.
3. Open the venue's QR link. Preserve the invitation through sign-in without joining automatically.
4. Show the venue name, session length and rules; ask the user to join.
5. Create a server-timed session. Only one active venue per account; switching ends the old session atomically. Reopening a QR must not silently extend an existing session.
6. Show time remaining and Leave venue. Expiry or departure removes access server-side.

## Data boundaries

- Separate ProRod Supabase project. Never use another Supabase project.
- Private profile: user ID, date of birth, onboarding version and acceptance timestamp. Email stays in Auth. Never expose birth dates or email in venue discovery.
- Display profile: display name and optional bio. Visibility requires both users' live sessions in the same venue and no block in either direction.
- Venue configuration: category, approved session duration, active status. No client write permission.
- QR invitation: high-entropy revocable token, stored hashed; expiry and venue linkage checked on the server. A QR link alone is not proof of physical presence; operational verification remains a product decision.
- Session: server start/expiry, venue and user IDs, explicit end time. Users cannot set their own expiry or grant themselves passes.
- Blocks and moderation status remain authoritative across venues and sessions.
- Use RLS on exposed tables; a user can only read/edit their own private profile. Do not authorize from user-editable metadata.
- Do not infer gender from email. Self-declared profile fields must not directly grant paid entitlements. Payment eligibility and handling nonbinary users require an explicit policy before billing launches.

## Verification before activation

Test confirmed and unconfirmed accounts, password recovery, fresh-device confirmation, own-profile access, denial of another user's private profile, expired/revoked QR links, session switching, expiry boundaries, and cross-venue exclusion using two real test accounts.

The existing demo stays clearly labelled. No signup UI should claim to create an account until a real backend is connected. Production email requires a configured sender and successful delivery test; do not rely on an API acceptance as proof of delivery.
