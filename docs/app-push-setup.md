# Notifications sent to the phone apps: what to set up

Since 23 November 2026 UPZONE can send its notifications (someone says hello, a reply, a message, a talent in the
place, account information) to the Android and iPhone apps, through Expo's push service. The code is in the repository;
this page lists what must be done **once, on the operator's accounts**, and in which order. Nothing here is a secret
to commit: every key stays in the service that issues it.

Until these steps are done, nothing breaks: the apps keep working, and the settings say that this version only
receives the test reminders.

## What already works without any of this
- The database migration and the settings screen are harmless on their own.
- The build in the closed test (1.0.0 (6)) has no push service: it answers « no address » and receives nothing.

## Steps

### 1. Database (Supabase, project ProRod)
1. SQL Editor → paste `db/2026-11-23-app-push.sql` → Run.
2. Paste `db/verify-app-push.sql` → Run. Expected last line: `PASS: app push …`. Everything it creates is rolled back.

### 2. Server function (Supabase → Edge Functions → send-push)
Replace its code with `supabase/functions/send-push/index.ts` and deploy, « Verify JWT » still off. No new secret is
needed. Only if « enhanced security for push notifications » is switched on in the Expo account: add the secret
`EXPO_ACCESS_TOKEN`.

### 3. Android: Firebase (Google's push service)
1. https://console.firebase.google.com → create a project (or use the operator's) → add an **Android app** with the
   package name `fr.upzoneapp.app`.
2. Download `google-services.json`. **Do not commit it.**
3. expo.dev → project → Environment variables → add `GOOGLE_SERVICES_JSON`, type **File**, environment
   **production**, visibility secret, and upload that file.
4. Firebase → Project settings → Service accounts → « Generate new private key » (a JSON file). **Never commit it.**
5. expo.dev → project → Credentials → Android → `fr.upzoneapp.app` → « FCM V1 service account key » → upload that JSON.

### 4. New Android build
Run the workflow « Android build (Expo) », upload the `.aab` to the closed test in Play Console, and publish. This
build has a new runtime version: updates over the air published afterwards reach this build, no longer 1.0.0 (6).

### 5. Google Play declaration (operator's declaration)
Play Console → App content → Data safety: declare **Device or other IDs** (collected, not shared for advertising,
optional, purpose « app functionality »: the address of the phone for notifications, removed at sign-out). The text in
`docs/google-play-listing.md` says what to tick.

### 6. iPhone
1. On a computer with the Expo account: `eas credentials` → iOS → set up a **push notifications key** (it asks to sign
   in to the Apple developer account; Apple's two-factor code is needed, so this cannot be done from GitHub).
2. Run the workflow « iPhone build (Expo) » and send the build to TestFlight.

## How to check
1. Install the new build, sign in, allow notifications.
2. Profil → Réglages → Notifications: the sentence about « this version only receives the test reminders » is gone,
   and the three choices (Rencontres, Messages, Talents) are shown.
3. From a second account in the same place, say hello to the first one with the first phone locked: a notification
   « Quelqu’un dit bonjour. » arrives.
4. Supabase → Edge Functions → send-push → Logs: the answer shows `"phones":1`.

## What is sent, and to whom
- The text is generic (« Nouveau message. »), with the number of unread items. Never a name, a message or an id.
- The phone's address (an Expo push token) is stored in `public.app_devices`, readable by no client, for the signed-in
  member only; signing in with another account on the same phone moves it; sign-out and account deletion remove it.
- The alert goes through Expo (650 Industries, United States), then Google or Apple. The privacy policy says so; the
  operator should have that paragraph checked with the rest of the policy.
