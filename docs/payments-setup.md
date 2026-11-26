# Real payments: what is in place and what the operator still has to do (26 November 2026)

Nothing takes money yet. This file lists the pieces, in the order they have to be done. The operator answers for every
account below (RevenueCat, Google Play, Apple, Supabase): keys and secrets are typed by the operator in those
dashboards, never sent in a chat and never put in this repository.

## How a payment will work
1. In the phone app, the member taps the purchase button. Apple's or Google's own payment window opens.
2. RevenueCat checks the purchase with the store, then calls the server function `revenuecat-webhook`.
3. The function asks the database to record it (`record_purchase`, service key only). The database switches the pass or
   the professional's visibility on, for the visit that is live. A phone can never do this by itself.
4. A refund made by the store arrives the same way and stops what was bought (`refund_purchase`).

## Done
- Database: `db/2026-11-26-purchases.sql`, installed on the project and verified (`db/verify-purchases.sql`: PASS).
- Server function: `supabase/functions/revenuecat-webhook/index.ts` (in the repository, **not deployed yet**).
- RevenueCat project (created 26 Nov 2026), set up from this repository's identifiers:
  - apps « UPZONE Android » (`fr.upzoneapp.app`) and « UPZONE iPhone » (`com.upzone.app`);
  - products `upzone_venue_pass` and `upzone_pro_evening`, one-time and consumable, on both apps;
  - offering `default` with the two packages;
  - webhook « UPZONE Supabase » towards the server function, limited to purchases and refunds, **switched off** until
    the steps below are done.

## To do, by the operator
### 1. Supabase
1. Edge Functions → deploy `revenuecat-webhook` from the repository, with « Verify JWT » off.
2. Edge Functions → Secrets → `REVENUECAT_WEBHOOK_AUTH`: a long random value (24 characters at least) that you invent.
3. For the test period only, also `REVENUECAT_ALLOW_SANDBOX` = `true`, so that the stores' test purchases are accepted.
   Remove it before the public release: with it, a test purchase grants a real pass.

### 2. RevenueCat
1. Integrations → Webhooks → « UPZONE Supabase » → « Authorization header »: the same value as `REVENUECAT_WEBHOOK_AUTH`.
2. Switch the webhook on.
3. Check who owns the RevenueCat account: it should be the company that operates UPZONE.

### 3. Google Play
1. Play Console → set up the payments profile (bank and tax details) and accept the terms for paid content.
2. Monetise → In-app products → create `upzone_venue_pass` and `upzone_pro_evening` (one-time products), with the
   prices decided by the operator. The identifiers must be exactly these.
3. Give RevenueCat access to Play: a service account, whose file is uploaded in RevenueCat → « UPZONE Android ».
   RevenueCat's own guide is linked on that page.
4. Play Console → licence testing: add the testers' Google accounts, so that their purchases are not charged.
5. Declarations to update on that day: `docs/google-play-listing.md`, section « The day payments become real ».

### 4. Apple
1. App Store Connect → Agreements → accept the Paid Apps agreement, with bank and tax details.
2. Create the two in-app purchases, type consumable, with the same identifiers and the prices decided.
3. Create an In-App Purchase key and give it to RevenueCat → « UPZONE iPhone ».

### 5. In the app (DZOFT)
- Purchase buttons in the phone apps, through RevenueCat's component. This is native code: it needs a new build sent to
  the stores, it cannot be pushed as a remote update.
- The members' payment rule is still to be decided by the operator. No rule or price may depend on gender.
- Before the public release: remove `REVENUECAT_ALLOW_SANDBOX`, replace the « simulation » wording, add RevenueCat to
  the privacy policy (purchase data is processed by RevenueCat) and to Google's and Apple's data declarations.

## Testing, once steps 1 to 4 are done
A licence tester buys each product once on a test phone, inside a place. Expected: the pass (or the visibility) is on
within a few seconds; the purchase appears in the administrator's list; a second purchase in the same visit is recorded
as « not granted » (to refund); a refund from Play Console switches the pass off.
