# Meeting readiness — 9 November 2026

## Honest status

This is a functional pilot, not a production-ready or store-delivered application. A completion percentage would hide the remaining payment, operating and device-validation work. The review covers source code, database contracts, automated tests and existing verification records; it does not substitute for an end-to-end session on two real phones.

## Reviewed areas

| Area | Keep / verified foundation | Remaining work |
|---|---|---|
| Welcome and installation | Simple mobile welcome, FR/EN, PWA installation guidance | Observe first-time iPhone and Android installation without assistance; verify installed-app updates and keyboard layout |
| Registration and recovery | Email flow, profile setup, passkey/SMS integration, linked sign-in methods | SMS delivery remains unproven; confirm recovery on a second device and final domain before depending on passkeys |
| Profile/settings | Name, photo, adult birth date, bio, language, optional private gender, export/delete, notifications and sign-in methods | Block-list management, clearer support/report follow-up and final privacy/contact information; no inferred orientation or automatic gender pricing |
| Venue presence | Server expiry, one active venue, co-presence visibility, QR revocation | Decide duration per venue type, leaving behavior and how to prevent remote use of copied QR codes |
| Introductions/chat | One introduction, consent before chat, block/report/end controls, hidden-reply checks | Real two-phone acceptance test; decide whether a permanent unanswered-introduction restriction is the desired rule |
| Meeting invitation | Mutual yes; refusal does not force meeting or end chat | Validate timing and accessibility of the five-second prompt with guests |
| Passes and billing | Clearly simulated zero-euro passes and talent subscriptions | Real checkout, payment webhooks, idempotency, failed/cancelled payments, receipts, billing history, refunds, subscription cancellation and admin reconciliation are missing |
| Connectivity before payment | Existing API errors handled | Add pre-payment connection check and clear warning at the user's actual seat; a successful check cannot guarantee later reception. Do not promise a blanket liability waiver |
| Professional accounts | Moderated professional sheet, venue-limited visibility, enquiries | Confirm offer, subscription duration/price and who sees talent cards; test approval/rejection and enquiries on devices |
| Venue accounts | Application, admin approval, QR, announcements, aggregate counts | Confirm approval/support process and operational venue contact; never expose member identities in venue statistics |
| Administration | MFA, applications, moderation, restrictions, audit, simulated passes | Assign moderator and response process, test full report resolution, payment operations and support workflow; do not expose private gender to admin lists by default |
| Notifications | In-app activity and generic push implementation | Verify closed-app push on iPhone/Android, permission denied/re-enabled, translation and feedback-email delivery. A successful server request is not proof of delivery |
| Privacy/security | Owner-only profile access, scoped RPCs, private photos, export/delete; automated backend checks pass | Fill operator/contact/retention drafts; assess age assurance, privacy and payment model before public launch; enable leaked-password protection when available; establish backup/restore and incident procedures |
| Distribution | Public GitHub Pages PWA for testing | Native packaging/store delivery remains separate unfinished work. Confirm developer-account ownership, fees, builds, review requirements and release testing; a PWA link is not store publication |

## Decisions to record at the meeting

1. Final brand name and logo; repository currently uses ANZIAK. Do not rebrand repeatedly without a written choice.
2. Price, pass duration and exactly who pays in each situation, including same-gender conversations and people who do not disclose gender. Validate the model before implementing charging. Buying a pass never purchases a reply or a meeting.
3. Does one pass cover all accepted conversations in the current venue visit? What happens after leaving, returning or expiry?
4. Restaurant, bar, chicha and nightclub durations; intended proof of presence.
5. Professional visibility/subscription offer and venue responsibilities.
6. Moderation owner, support contact, response expectations, appeals and retention.
7. External service budgets and developer-account ownership. Account owner enters payment details directly into providers; no card details in chat.
8. Agree pilot acceptance criteria and distinguish original contracted delivery from newly requested extras in writing.

## Priority order

**Before the meeting:** private gender field and backend checks completed; use email login for the demo unless SMS has been verified; prepare one approved venue and two consenting test accounts. Do not approve a real venue application automatically just to make the demo work.

**At the meeting (20–30 minutes):** install/open → sign in → profile → same QR → one introduction → acceptance → simulated pass → chat → end/block/report → moderator review. Then review expiry/return and professional/venue dashboards. Record actual success/failure, not assumed success.

**Next implementation milestone:** lock written decisions, implement payment and billing in provider test mode, add connectivity warning, complete settings/support and operational moderation. Verify webhook retries and no access granted from client-side payment claims.

**Before public launch:** device acceptance, working production services, final privacy/terms and operating contacts, payment validation, store delivery plan and account recovery/backup exercises.

## Guest questionnaire for 14 November

Ask after participants try the app, without coaching:

1. In one sentence, what do you think the app lets you do?
2. Could you install, join a place and send one introduction without help? Where did you stop?
3. Name: score /10 and what it suggests to you.
4. Logo: score /10 and whether it is recognizable at phone-icon size.
5. After explaining the exact offer and price: would you pay? Why/why not? Do not ask a price score without showing the amount and duration.
6. Do you feel in control of incoming messages? Can you find end, block and report?
7. Is it clear that payment never obliges someone to answer or meet?
8. What one thing would you change first?

Participation is optional. Avoid collecting unnecessary identity or sensitive information in feedback.
