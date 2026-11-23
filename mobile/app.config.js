// UPZONE for iPhone and Android: a native shell around the web app (first step: TestFlight and Google Play testing).
// The identity values live in identity.json. They are not secrets, but they are permanent once a build
// is uploaded to Apple or Google, so they are filled in once, by the operator, and never guessed.
const id = require('./identity.json');
const { withAndroidManifest } = require('expo/config-plugins');

// The app is shown upright only. Android reads that as « needs a portrait screen » and Google Play then hides the app
// from devices that do not declare one (some tablets, Chromebooks). Marking both orientations as optional keeps the
// app installable everywhere; it still opens upright.
const optionalScreen = config => withAndroidManifest(config, cfg => {
  const manifest = cfg.modResults.manifest;
  const names = ['android.hardware.screen.portrait', 'android.hardware.screen.landscape'];
  manifest['uses-feature'] = (manifest['uses-feature'] || []).filter(f => !names.includes(f.$['android:name']))
    .concat(names.map(name => ({ $: { 'android:name': name, 'android:required': 'false' } })));
  return cfg;
});

module.exports = () => optionalScreen({
  name: 'UPZONE',
  slug: id.slug || 'upzone',
  owner: id.owner || undefined,
  version: '1.0.0',
  orientation: 'portrait',
  icon: './assets/icon.png',
  userInterfaceStyle: 'light',
  splash: { image: './assets/splash-icon.png', resizeMode: 'contain', backgroundColor: '#fffadd' },
  ios: {
    bundleIdentifier: id.iosBundleIdentifier || undefined,
    supportsTablet: false,
    config: { usesNonExemptEncryption: false },
    infoPlist: {
      NSCameraUsageDescription: 'UPZONE utilise l’appareil photo pour scanner le QR code du lieu et pour prendre ta photo de profil.',
      NSPhotoLibraryUsageDescription: 'UPZONE accède à tes photos seulement quand tu choisis une photo de profil.',
      CFBundleDevelopmentRegion: 'fr',
    },
  },
  android: {
    package: id.androidPackage || undefined,
    adaptiveIcon: { foregroundImage: './assets/icon.png', backgroundColor: '#fffc00' },
    // Camera: the venue QR scanner and the profile photo. Nothing else is requested.
    permissions: ['android.permission.CAMERA'],
    blockedPermissions: ['android.permission.RECORD_AUDIO', 'android.permission.READ_EXTERNAL_STORAGE', 'android.permission.WRITE_EXTERNAL_STORAGE'],
    // Notifications sent by UPZONE to the phone (23 Nov 2026) go through Google's push service, which needs the app's
    // Firebase file. It is given to the build as an Expo environment variable of type « file » (GOOGLE_SERVICES_JSON),
    // never committed: see docs/app-push-setup.md. Without it the app builds as before and receives no such notification.
    ...(process.env.GOOGLE_SERVICES_JSON ? { googleServicesFile: process.env.GOOGLE_SERVICES_JSON } : {}),
  },
  // Updates over the air (20 Nov 2026): the app checks at launch for a newer version of its own script on Expo's update
  // service and uses it at the next launch. Only the script can change this way; a new native part or permission still
  // needs a build and the store. « fingerprint » ties each update to the builds whose native parts it was made for, so
  // an update can never reach an app it does not fit.
  runtimeVersion: { policy: 'fingerprint' },
  updates: id.easProjectId ? { url: `https://u.expo.dev/${id.easProjectId}`, checkAutomatically: 'ON_LOAD', fallbackToCacheTimeout: 0 } : undefined,
  // Reminders of the closed test: planned on the phone, in the app's purple. See App.js.
  plugins: [['expo-notifications', { color: '#5005b0', defaultChannel: 'rappels' }]],
  // Last day of the test reminders (closed test opened on 20 November 2026; a margin for testers who join late).
  extra: { testRemindersUntil: '2026-12-12', appUrl: id.appUrl, eas: id.easProjectId ? { projectId: id.easProjectId } : undefined },
});
