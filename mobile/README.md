# UPZONE for iPhone (first step: TestFlight)

A native shell that opens the UPZONE web app. It is a first step to get UPZONE onto iPhones through TestFlight;
it is not ready for the App Store as it is (see « Before the App Store »).

## What it does
- Opens the web app full screen, with the camera allowed for the QR scanner and the profile photo.
- Links outside UPZONE open in the browser.
- Shows a retry screen when there is no connection.
- The web app's « install » banner is hidden inside the app.

## What does not work yet inside the app
- Notifications: web notifications do not exist in an app shell; they need Apple's notification service.
- Opening the app by scanning the venue QR code with the camera app, and passkeys: both need UPZONE on its own domain.

## To build
1. Fill in `identity.json`: `owner` and `slug` (the Expo account and project), `easProjectId` (shown on the Expo project page),
   `iosBundleIdentifier` (chosen by the operator; permanent once a build is uploaded to Apple).
2. First build, once, from a computer: `npm ci`, then `npx eas-cli@latest build -p ios`. It asks to sign in to Expo and to the
   Apple developer account, and creates the signing credentials.
3. Later builds: GitHub → Actions → « iPhone build (Expo) » → Run workflow. Needs the repository secret `EXPO_TOKEN`.
   Tick « submit » to send the new build to TestFlight when it is ready, or « submit_latest » to send the latest finished
   build without building again. The App Store Connect app is named in `eas.json` (`ascAppId`, the app's Apple ID, not a secret).

## Before the App Store
- App Store Review Guideline 4.2: more than a repackaged website (native notifications, scanner, sign-in).
- Guideline 3.1.1: the pass must use Apple's in-app purchase.
- Guideline 1.2: filtering of objectionable content and a published contact address, besides reporting and blocking.
- No « simulated payments » wording.

## Android (Google Play)
- Package name: `androidPackage` in `identity.json` (`fr.upzoneapp.app`, chosen in Google Play Console on 20 November 2026;
  permanent).
- Same shell as the iPhone: opens the web app full screen, camera allowed for the QR scanner and the profile photo, the
  phone's back button goes to the previous screen. Only the camera permission is requested.
- To build: GitHub → Actions → « Android build (Expo) » → Run workflow (needs the repository secret `EXPO_TOKEN`). The
  `.aab` file appears on expo.dev → Builds; download it and upload it in Google Play Console → Tests → Test interne.
- Installed on a real Android phone through the closed test on 20 November 2026. Notifications from the web app do not
  work inside the shell (same as iPhone).
- Reminders of the closed test (20 November 2026): until `testRemindersUntil` (`app.config.js`), the Android app plans two
  reminders a day (12:30 and 19:30) on the phone itself with `expo-notifications`. No server, no push token, no data
  collected. Opening the app cancels that day's reminders. To stop them earlier, put a past date and build again; after
  the date the app cancels them by itself. Remove the feature (or keep the date in the past) for the public release.
- Before production on Google Play: the store listing, the content rating and target audience (18+), the data safety
  form, a public account-deletion page, and Google Play Billing for the pass once payments are real.
