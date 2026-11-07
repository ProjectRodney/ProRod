# PRod — product flow (reference)

Status legend: **DONE** (implemented and verified with two accounts in the database checks, see `docs/verification-log.md`), **PART** (partly built), **TODO** (not started), **DECIDE** (client decision pending), **ACCEPTED** (tried and approved by Rodney; none yet). Status as of 7 November 2026. Repository transferred to Rodney's GitHub account (ProjectRodney/ProRod) on 7 November 2026; the app address became https://projectrodney.github.io/ProRod/ and every QR code was regenerated.

Intended flow: install PRod → create an account → complete a profile → scan a venue's QR code → discover people in that venue → send one introduction → receive consent → unlock eligible conversations → chat → optionally meet → leave or let the session expire.

## 1. Install and open P.Rod — DONE (landing page)
Before any account: a landing page in the app (language choice Français / English, what P.Rod is, how it works in three steps, the three kinds of accounts, safety principles, « Créer mon compte » / « J’ai déjà un compte »). The language chosen there follows the member through setup; the profile keeps its own language field.
The URL `https://projectrodney.github.io/ProRod/` is the installer: welcome page with « Installer P.Rod sur mon téléphone » (native install prompt on Android/desktop, guided « Partager → Sur l'écran d'accueil » on iPhone) and « Continuer dans le navigateur »; once installed the URL opens the app directly; the app shows a dismissible install banner until installed.
Website `https://projectrodney.github.io/ProRod/` (opens `account.html`; the fictional concept demo lives at `demo.html`). iPhone: Safari → Share → Add to Home Screen. Android: browser install option. Usable in the browser too. Welcome screen with Create account, Sign in, FR/EN. Installation alone creates nothing.

## 2. Create and verify an account — DONE (Google and phone sign-in ready behind flags)
Email + password, confirmation email (custom SMTP), return to PRod. Optional sign-in methods are driven by `src/public-config.js` (`providers.google`, `providers.phone`; phone switched on 6 November 2026): Google needs an OAuth client enabled in Supabase (free), phone sign-in codes go out through Brevo SMS via the `send-sms` Edge Function plugged into Supabase's Send SMS hook (no third SMS company; test numbers with a fixed code cost nothing); Sign in with Apple is deferred (Apple Developer Program required). Supabase keeps one account per email address or phone number, so a method already used cannot open a second account. Checks: email not confirmed → instructions + resend; profile incomplete → onboarding; profile complete → home. A valid stored session goes straight to home.

## 3. Complete onboarding — DONE (three account types)
First screen after sign-up: « Je suis ici en tant que… » person / professional / venue (`set_account_type`, stored before the profile exists; a venue account can never become a person account and vice-versa). Persons and professionals then complete the full profile below; venues only name their account and apply for their place (name, type, address, hours, contact, session length) which the team approves in the admin portal (« Candidatures »).
Required before any venue: display name, profile photo (chosen from the phone, resized on the device, stored in a private bucket readable only by its owner until discovery is built), private date of birth (18+, locked; other members will see the age only), language, a short bio (≤ 300 characters), acceptance of community rules. The server refuses to join a venue until the profile is complete. No selfie at check-in, ever.

## 4. Home screen — DONE
Without a session: scan a QR / enter an invitation; « Mon profil et réglages » (display name, language, read-only birth date, account deletion); « Aide et sécurité » (how it works, community rules, what to do in a problem, data). No browsing outside the joined venue (enforced server-side). With an active session: back to that venue.

## 5. Scan and join a venue — DONE
In-app « Scanner le QR code du lieu » button (rear camera, used only to read the code, nothing stored; phone camera app and manual code remain as fallbacks). Invitation preview (name, duration, conditions) before joining. Server-timed session, countdown, one venue per account (joining another ends the previous one), rescanning never extends a session. Rule chosen on 5 November 2026: a valid invitation can be used again by the same account after leaving or expiry (a venue's printed QR serves returning visitors); rescanning during a live session returns it unchanged. Venues carry an address, shown before joining. Durations per venue type and departure detection: DECIDE. A QR alone does not prove presence.

## 6. Discover someone and send one introduction — DONE (talents: see 11)
Introduction DONE: from a member's profile, one message (≤ 500 characters) shown with the warning « This person is not obliged to respond »; further messages are locked until the recipient accepts and replies; the recipient can ignore, decline (the sender only ever sees « waiting »), block or report; one introduction per person per visit, maximum five per visit. Since 6 November 2026 (evening): a declined or unanswered introduction closes the door for good, in any venue, unless that person writes first. Discovery DONE: « Voir qui est là » lists members with a live session in the same venue only (display name, age, bio, photo), excluding blocked pairs and suspended accounts; photos are readable only while co-present and unblocked (storage policy). Talents: see 11 (DONE for the test). Warning before sending: "This person is not obliged to respond. Please respect their choice." After one introduction, further messages are locked until the recipient accepts and replies. Recipient can ignore, decline, block or report. No response = no conversation.

## 7. Acceptance and payment — SIMULATED during the test (model DECIDE, legal validation required before any real payment)
Test rule, neutral for everyone (`pass_rule` = everyone, setting on the server): once a person accepts and replies, their messages stay hidden (« Réponse masquée ») and writing is refused until the member holds a venue pass for that session. The pass is obtained with one tap in the app, labelled SIMULATION, costs nothing and is recorded in `passes` (simulated = true, 0 €); the admin portal lists passes and can mark a simulated refund. Setting `pass_rule` to none removes the gate. No gender-based rule exists anywhere in the code; the table below remains the client's intended model, to validate legally first.
| Situation | Intended result |
|---|---|
| Recipient has not accepted and replied | Sender cannot continue messaging |
| Recipient accepts and replies; man has no active pass | Notify him, keep the content hidden |
| Man purchases a valid venue pass | Unlock accepted conversations of that venue session |
| Man already has a valid pass | Open the accepted conversation |
| Woman uses the app | No chat payment required |
The pass covers accepted conversations in that venue session only; each new conversation still requires consent. Since 7 November 2026 the server enforces it: a pass counts only while it is valid (it ends with the venue session it was bought in), so writing on a later visit needs a new pass; a reply from the other person is readable when one of the reader's passes covered the moment it was sent, and stays hidden otherwise, in the conversation, the inbox preview and the data export alike (`private.needs_pass`, `private.message_hidden`, migration `db/2026-11-07-pass-expiry.sql`). Gender-based pricing, eligibility (self-declared field, non-binary cases, no inference from email) and payment conditions must be validated before launch. Hidden replies never appear in notification previews or unauthorized API responses.

## 8. Chat with ongoing control — DONE (translation FR ⇄ EN; chat only while co-present)
Decision of 6 November 2026 (evening, Roland): writing is possible only while both people are checked in at the conversation's venue; history stays readable; the meeting prompt also needs co-presence. Leaving or expiry pauses the conversation, a new visit resumes it. Rodney can relax this later.
Each received message has « Traduire »; a toggle translates received messages automatically; « Traduire mon message » translates a draft before sending (the member reviews it). Translation runs through the Edge Function `translate` (DeepL, key `DEEPL_API_KEY` in Supabase secrets, never in the client) only on the member's request; the privacy policy states it. Without the key the app says translation is not available yet.
Once accepted, both can message within the pass rule of step 7. Messages, introductions and reports are never readable directly by clients: every read goes through a server function, so entitlement checks can be added in one place. At any time: end (neutral notice), block (survives venues and sessions), report (always free, never shown to the reported person).

## 9. Optional meeting — DONE (timing: after two messages from each side; DECIDE if different)
Five-second prompt once the other person proposed; either side can propose from the conversation. Both yes → « meet at a public spot, e.g. the counter ». Both yes → suggest a public meeting point (the counter). Either no, or no answer → no meeting, chat continues. No repeated pressure after a refusal.

## 10. Leave or session expiry — DONE (conversations pause when either person leaves; retention DECIDE) · Privacy policy and terms pages (FR/EN) DONE as drafts with operator fields to complete · « Télécharger mes données » DONE
Leaving, switching venue or expiry ends presence and discovery; the account remains. Pass expiry: a pass ends with its venue session (see 7). Read-only history while apart is in place (see 8). Retention, and whether returning to an existing conversation should need fresh consent: DECIDE. Blocking and reporting must survive expiry.

## 11. Talent journey — DONE for the test (offer and price DECIDE)
Professional accounts fill a sheet (business name, professional name, category, pitch, website, Instagram/TikTok/LinkedIn, city). The team approves it (« Fiches pro »). With an approved sheet and an active subscription (simulated, 30 days, one tap) the sheet appears in « Talents ici » for people checked in the same venue only; others can send an enquiry (not a chat; optional contact left), notified in-app. Blocks and reports apply to talents as well.

Talent profile + agreed subscription; visible only inside the active venue, moderated; no bypass of consent, no visibility in other venues.

## 11b. Notifications — DONE (in-app); email/push TODO
In-app activity feed and badge: introduction received, reply received (content never included), new message (one unread per conversation), conversation ended, report reviewed, account restricted/reinstated. Email digests and web push need a sending function with a Brevo key on the ProRod project: TODO.

## 12. Behind the scenes (admin portal) — DONE for the pilot (`admin.html`)
New tabs on 6 November 2026: Candidatures (venue applications → approve creates the venue and hands its QR codes to the venue account), Fiches pro, Passes (simulation, refund), Retours (feedback).
Admin role = Auth claim `app_metadata.prod_admin` (set by the operator in Supabase, never by the app); two-step verification (authenticator app) is mandatory: the portal enrols the admin on first sign-in and every admin function refuses a session without it. Portal in French and English. Overview tiles; venues (create/edit, category, duration, address, active — deactivating ends live sessions); invitations (QR shown once, revoke ends sessions); reports queue with the conversation attached, motivated decision, optional suspension; members by display name only, suspend/reinstate; audit log of every sensitive action.
Venues, QR invitations and durations; reports and restrictions; talent content; passes, subscriptions, failed payments and refunds; errors and notifications; history of sensitive actions; two-factor authentication for administrators.

## 12b. Venue accounts — DONE
Dashboard for an approved venue: people checked in now, check-ins over 24 h, open reports; QR codes generated on the phone (shown once, downloadable PNG, revocable, 7/30/90 days); announcements shown to people present for 12 hours (e.g. happy hour); opening hours, contact and session length (15 min to 3 h; the test caps every session at 3 hours). Venue accounts never see profiles, messages or who is present by name.

## 12c. Feedback — DONE
After one hour of real use on the device (foreground time), a short pop-up: a face (1–4), what to change first, optional bug; « Répondre maintenant » or « Plus tard » (snoozed 30 minutes, at most three prompts). Also available from the settings. Answers are stored on the server (admin « Retours ») and e-mailed to the operator every 5 minutes by the database once the Brevo key is in the Supabase Vault (`brevo_api_key`) and the addresses are set in `private.app_settings`.

## Next complete milestone
1. Pass expiry fix (7 November 2026): DONE, applied on ProRod and verified (section 3b with every other section PASS).
2. One documented pilot with two member phones, one venue account and an admin: install, sign-up, confirmation e-mail, QR entry, introduction, acceptance and reply, pass, chat, refusal, block, report, leaving, re-entry, a second visit needing a new pass. Results go into `docs/verification-log.md`; features the client approves become ACCEPTED.
3. External services checked on real devices: confirmation and reset e-mails (Brevo SMTP), SMS codes (Brevo), translation (DeepL), feedback e-mails.
Server checks (sections 1–7) passed on 5–6 November 2026; the Node tests mostly check source text, so the pilot is the evidence that people can really use it.
