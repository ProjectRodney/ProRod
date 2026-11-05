# ProRod

Project Rodney. Product name: **PRod** (roadmap of 5 November 2026; earlier working names Zélo and Mêla). The name lives in `src/brand.js`.

## Platform

Progressive Web App, responsive on iPhone and Android. iPhone installation uses Safari's Share → Add to Home Screen flow, with an in-app guide. A publicly reachable HTTPS test deployment is required for remote iPhone testing. Localhost links are not shareable to Rodney's phone. No native Expo build or App Store submission is required for the first PWA test.

## Scope decision — 5 November 2026

Remove the mandatory selfie-taking requirement entirely. No selfie capture during onboarding, venue check-in or chat. Do not request camera permission for identity verification. QR scanning is a separate venue-entry function and must be clearly explained if it requests camera access; opening a venue QR URL with the phone's own scanner is the preferred first testing path.

## Product requirements

- Venue-scoped access following QR check-in; no browsing people or talents in another venue.
- One introduction; no additional messages until recipient accepts and replies.
- Men purchase a venue-session pass covering accepted conversations; women use chat free.
- Payment never overrides consent, blocks or closure. Hidden replies must stay out of notification previews and unauthorized API responses.
- End, block and report controls for everyone, including before payment. Blocks survive session expiry and subsequent scans.
- A meeting requires two affirmative choices. Declining or not answering does not close the chat. Five-second prompt can be reopened; no repeated automatic prompts after refusal.
- Paid talent visibility is limited to the scanned venue.
- Moderation queue, access-controlled evidence, suspension and appeal process. Do not claim alerts reach venue staff without an actual staffed integration.
- French and English throughout the client and administration journeys.

## Decisions pending

- Session lengths by restaurant/pub/chicha/nightclub and exactly how departure changes expiry.
- Pass price, refunds, and handling venue re-entry.
- Presence verification beyond possession of a QR URL.
- Production account ownership, hosting, payment provider and moderation operations.

## Delivery sequence

1. PWA shell, manifest, icons, offline fallback and installation guide.
2. Venue sessions, profiles and authentication.
3. Consent-gated conversations and persistent safety controls.
4. Moderation interface and tests of cross-user access restrictions.
5. Payment sandbox, session expiry, then controlled iPhone testing.

The earlier safety preview contains fictional browser-only state. It is a design reference, not a production backend or security boundary. Do not cache private messages, reports or authentication responses in the service worker.

## Status

Update 5 November 2026 (evening): product renamed to PRod (`src/brand.js`, new icon), email redirect driven by `siteUrl` in `src/public-config.js`, GitHub Pages deploy workflow added (gated by the `PAGES_ENABLED` repository variable), `db/create-invite.sql` issues venue invitations, `CLAUDE.md` documents the project rules.


The separate `account.html` now connects signup/sign-in, private profiles and invitation-based venue sessions to ProRod's dedicated Supabase project. SMTP and redirect configuration must be verified before testing email signup. The original `index.html` remains a fictional consent demo; its chat, payment and moderation actions are not production services. Run `npm ci`, `npm run build`, then `npm test`. Real email delivery, iPhone installation and browser interaction testing remain required. See `docs/account-and-venue-build.md` for verified database checks and remaining work.
