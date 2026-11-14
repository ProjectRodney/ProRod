// UPZONE for iPhone: a native shell around the web app (first step, for TestFlight).
// The four identity values live in identity.json. They are not secrets, but they are permanent once a build
// is uploaded to Apple, so they are filled in once, by the operator, and never guessed.
const id = require('./identity.json');

module.exports = () => ({
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
  extra: { appUrl: id.appUrl, eas: id.easProjectId ? { projectId: id.easProjectId } : undefined },
});
