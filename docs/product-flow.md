# PRod — product flow (reference)

Status legend: **DONE** (connected to real accounts and server-side rules), **PART** (partly built), **TODO** (not started), **DECIDE** (client decision pending). Status as of 5 November 2026.

Intended flow: install PRod → create an account → complete a profile → scan a venue's QR code → discover people in that venue → send one introduction → receive consent → unlock eligible conversations → chat → optionally meet → leave or let the session expire.

## 1. Install and open PRod — DONE
Website `https://rdzoagbe.github.io/ProRod/account.html`. iPhone: Safari → Share → Add to Home Screen. Android: browser install option. Usable in the browser too. Welcome screen with Create account, Sign in, FR/EN. Installation alone creates nothing.

## 2. Create and verify an account — DONE
Email + password, confirmation email (custom SMTP), return to PRod. Checks: email not confirmed → instructions + resend; profile incomplete → onboarding; profile complete → home. A valid stored session goes straight to home.

## 3. Complete onboarding — DONE
Required before any venue: display name, profile photo (chosen from the phone, resized on the device, stored in a private bucket readable only by its owner until discovery is built), private date of birth (18+, locked; other members will see the age only), language, a short bio (≤ 300 characters), acceptance of community rules. The server refuses to join a venue until the profile is complete. No selfie at check-in, ever.

## 4. Home screen — DONE
Without a session: scan a QR / enter an invitation; « Mon profil et réglages » (display name, language, read-only birth date, account deletion); « Aide et sécurité » (how it works, community rules, what to do in a problem, data). No browsing outside the joined venue (enforced server-side). With an active session: back to that venue.

## 5. Scan and join a venue — DONE
In-app « Scanner le QR code du lieu » button (rear camera, used only to read the code, nothing stored; phone camera app and manual code remain as fallbacks). Invitation preview (name, duration, conditions) before joining. Server-timed session, countdown, one venue per account (joining another ends the previous one), rescanning never extends a session. Rule chosen on 5 November 2026: a valid invitation can be used again by the same account after leaving or expiry (a venue's printed QR serves returning visitors); rescanning during a live session returns it unchanged. Venues carry an address, shown before joining. Durations per venue type and departure detection: DECIDE. A QR alone does not prove presence.

## 6. Discover someone and send one introduction — DONE (talents TODO)
Introduction DONE: from a member's profile, one message (≤ 500 characters) shown with the warning « This person is not obliged to respond »; further messages are locked until the recipient accepts and replies; the recipient can ignore, decline (the sender only ever sees « waiting »), block or report; one introduction per person per visit, maximum five per visit. Discovery DONE: « Voir qui est là » lists members with a live session in the same venue only (display name, age, bio, photo), excluding blocked pairs and suspended accounts; photos are readable only while co-present and unblocked (storage policy). Talents: TODO. Warning before sending: "This person is not obliged to respond. Please respect their choice." After one introduction, further messages are locked until the recipient accepts and replies. Recipient can ignore, decline, block or report. No response = no conversation.

## 7. Acceptance and payment — TODO, model DECIDE (legal validation required before any build)
| Situation | Intended result |
|---|---|
| Recipient has not accepted and replied | Sender cannot continue messaging |
| Recipient accepts and replies; man has no active pass | Notify him, keep the content hidden |
| Man purchases a valid venue pass | Unlock accepted conversations of that venue session |
| Man already has a valid pass | Open the accepted conversation |
| Woman uses the app | No chat payment required |
The pass covers accepted conversations in that venue session only; each new conversation still requires consent. Gender-based pricing, eligibility (self-declared field, non-binary cases, no inference from email) and payment conditions must be validated before launch. Hidden replies never appear in notification previews or unauthorized API responses.

## 8. Chat with ongoing control — DONE
Both can message once accepted (the pass rule of step 7 is not built). Messages, introductions and reports are never readable directly by clients: every read goes through a server function, so entitlement checks can be added in one place. At any time: end (neutral notice), block (survives venues and sessions), report (always free, never shown to the reported person).

## 9. Optional meeting — TODO, timing DECIDE
Five-second prompt after an agreed point. Both yes → suggest a public meeting point (the counter). Either no, or no answer → no meeting, chat continues. No repeated pressure after a refusal.

## 10. Leave or session expiry — DONE for presence; conversation rules DECIDE
Leaving, switching venue or expiry ends presence and discovery; the account remains. Pass expiry rules, read-only history, retention and reopening with fresh consent: DECIDE. Blocking and reporting must survive expiry.

## 11. Talent journey — TODO, offer DECIDE
Talent profile + agreed subscription; visible only inside the active venue, moderated; no bypass of consent, no visibility in other venues.

## 12. Behind the scenes (admin portal) — TODO (invitations via `db/create-invite.sql` meanwhile)
Venues, QR invitations and durations; reports and restrictions; talent content; passes, subscriptions, failed payments and refunds; errors and notifications; history of sensitive actions; two-factor authentication for administrators.

## Next complete milestone
Install → register → confirm email → complete profile → join a test venue → leave or expire, verified on a real phone. Server side verified on 5 November 2026 with a test account; pilot venue « Barbier · Noisy-le-Grand » (60 minutes, to confirm) created with a 90-day invitation; the phone test by the client is next. Then: consent-based conversations and minimal moderation (steps 6, 8 and the reporting part of 12).
