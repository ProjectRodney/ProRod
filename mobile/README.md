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
2. First build, once, from a computer: `npm ci`, then `npx eas-cli build -p ios`. It asks to sign in to Expo and to the
   Apple developer account, and creates the signing credentials.
3. Later builds: GitHub → Actions → « iPhone build (Expo) » → Run workflow. Needs the repository secret `EXPO_TOKEN`.

## Before the App Store
- App Store Review Guideline 4.2: more than a repackaged website (native notifications, scanner, sign-in).
- Guideline 3.1.1: the pass must use Apple's in-app purchase.
- Guideline 1.2: filtering of objectionable content and a published contact address, besides reporting and blocking.
- No « simulated payments » wording.
