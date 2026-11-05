/* No native installer or camera permission is needed to install the PWA. */
let installPrompt;
const language = () => document.documentElement.lang === 'fr';
const copy = (en, fr) => language() ? fr : en;
window.addEventListener('beforeinstallprompt', event => { event.preventDefault(); installPrompt = event; });
document.getElementById('install-app').addEventListener('click', async () => {
  if (installPrompt) {
    await installPrompt.prompt();
    await installPrompt.userChoice;
    installPrompt = null;
    return;
  }
  const installed = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone;
  const dialog = document.createElement('dialog');
  dialog.innerHTML = `<h2>${copy('Keep PRod on your Home Screen','Gardez PRod sur votre écran d’accueil')}</h2><p>${installed ? copy('The app is already open in standalone mode.','L’application est déjà ouverte en mode autonome.') : copy('On iPhone, open this HTTPS link in Safari. Tap Share, then Add to Home Screen. Enable “Open as Web App” if shown, then tap Add.','Sur iPhone, ouvrez ce lien HTTPS dans Safari. Touchez Partager, puis Sur l’écran d’accueil. Activez « Ouvrir comme app web » si proposé, puis Ajouter.')}</p><p>${copy('On Android, use your browser’s Install app or Add to Home screen menu. Installation availability depends on the browser.','Sur Android, utilisez Installer l’application ou Ajouter à l’écran d’accueil dans le menu du navigateur. La disponibilité dépend du navigateur.')}</p><p class="notice">${copy('Test build: fictional profiles and simulated payments. No selfies, real messages or live safety alerts.','Version de test : profils fictifs et paiements simulés. Aucun selfie, message réel ni alerte de sécurité réelle.')}</p><button class="button">${copy('Got it','Compris')}</button>`;
  dialog.querySelector('button').onclick = () => dialog.close();
  dialog.addEventListener('close', () => dialog.remove());
  document.body.appendChild(dialog);
  dialog.showModal();
});
function connectionStatus() {
  const banner = document.getElementById('connection');
  banner.hidden = navigator.onLine;
  banner.textContent = copy('Offline demo — no messages or alerts can be sent.','Démo hors ligne — aucun message ni alerte ne peut être envoyé.');
}
window.addEventListener('online', connectionStatus);
window.addEventListener('offline', connectionStatus);
connectionStatus();
if ('serviceWorker' in navigator && window.isSecureContext) {
  window.addEventListener('load', () => navigator.serviceWorker.register('./sw.js').catch(() => {
    // The online demo remains usable even if offline installation is unavailable.
    console.info('Offline support is unavailable in this browser.');
  }));
}
