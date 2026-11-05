# Account and venue implementation

Status: implementation contract and validation tests prepared. Dedicated Supabase project `blqcmpqctetmjqsfdvsq` (ProRod) provisioned in Paris (`eu-west-3`) under DeSaint08's Org and verified ACTIVE_HEALTHY. Auth UI, application schema and delivery configuration are not connected yet. Joblytics pause was requested to free the active free-project slot; RD-Clients is unchanged.

## First real journey

1. Register with email and password; verify email before entering a venue.
2. Create profile: display name, private date of birth (18+), French/English preference, acceptance of community rules. No selfie, compulsory photo, surname or telephone required for this social app's first test.
3. Open the venue's QR link. Preserve the invitation through sign-in without joining automatically.
4. Show the venue name, session length and rules; ask the user to join.
5. Create a server-timed session. Only one active venue per account; switching ends the old session atomically. Reopening a QR must not silently extend an existing session.
6. Show time remaining and Leave venue. Expiry or departure removes access server-side.

## Data boundaries

- Separate ProRod Supabase project. Never use RD-Clients or Joblytics.
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
