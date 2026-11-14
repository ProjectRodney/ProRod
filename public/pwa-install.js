/* Installation helper shared by the welcome page and the app. No camera, no tracking: it only asks the
   browser to install the app (Android/desktop) or explains the Home Screen steps (iPhone). */
(function () {
  var fr = (document.documentElement.lang || 'fr').startsWith('fr');
  var T = function (en, f) { return fr ? f : en; };
  // Inside the iPhone app (its browser signs as UPZONEApp) there is nothing to install.
  var standalone = window.matchMedia('(display-mode: standalone)').matches || window.navigator.standalone === true || /UPZONEApp/.test(navigator.userAgent);
  var ios = /iphone|ipad|ipod/i.test(navigator.userAgent) && !window.MSStream;
  var deferred = null;
  window.addEventListener('beforeinstallprompt', function (e) { e.preventDefault(); deferred = e; render(); });
  window.addEventListener('appinstalled', function () { deferred = null; standalone = true; try { localStorage.setItem('prorod-installed', '1'); } catch (_) {} render(); });
  function dismissedRecently() { try { return Date.now() - Number(localStorage.getItem('prorod-install-dismissed') || 0) < 24 * 3600 * 1000; } catch (_) { return false; } }
  function iosSteps() {
    var d = document.createElement('dialog'); d.className = 'install-dialog';
    d.innerHTML = '<h2>' + T('Add UPZONE to your Home Screen', 'Ajoute UPZONE à ton écran d’accueil') + '</h2>' +
      '<ol><li>' + T('Tap the <b>Share</b> button at the bottom of Safari (the square with an arrow).', 'Touche le bouton <b>Partager</b> en bas de Safari (le carré avec une flèche).') + '</li>' +
      '<li>' + T('Choose <b>Add to Home Screen</b>.', 'Choisis <b>Sur l’écran d’accueil</b>.') + '</li>' +
      '<li>' + T('Tap <b>Add</b>. UPZONE opens like an app, full screen.', 'Touche <b>Ajouter</b>. UPZONE s’ouvre comme une application, en plein écran.') + '</li></ol>' +
      '<p class="quiet">' + T('If you are not in Safari, open this link in Safari first.', 'Si tu n’es pas dans Safari, ouvre d’abord ce lien dans Safari.') + '</p>' +
      '<button class="button" type="button">' + T('Got it', 'Compris') + '</button>';
    d.querySelector('button').onclick = function () { d.close(); };
    d.addEventListener('close', function () { d.remove(); });
    document.body.appendChild(d); d.showModal();
  }
  async function install() {
    if (deferred) { deferred.prompt(); try { await deferred.userChoice; } catch (_) {} deferred = null; render(); return; }
    if (ios) { iosSteps(); return; }
    var d = document.createElement('dialog'); d.className = 'install-dialog';
    d.innerHTML = '<h2>' + T('Install UPZONE', 'Installer UPZONE') + '</h2><p>' + T('Open your browser menu (⋮) and choose <b>Install app</b> or <b>Add to Home screen</b>.', 'Ouvre le menu du navigateur (⋮) et choisis <b>Installer l’application</b> ou <b>Ajouter à l’écran d’accueil</b>.') + '</p><button class="button" type="button">' + T('Got it', 'Compris') + '</button>';
    d.querySelector('button').onclick = function () { d.close(); }; d.addEventListener('close', function () { d.remove(); });
    document.body.appendChild(d); d.showModal();
  }
  function render() {
    document.querySelectorAll('[data-install]').forEach(function (node) {
      var mode = node.getAttribute('data-install');
      if (standalone) { node.hidden = true; return; }
      if (mode === 'banner' && dismissedRecently()) { node.hidden = true; return; }
      node.hidden = false;
      if (node.dataset.ready) return; node.dataset.ready = '1';
      if (mode === 'banner') {
        node.innerHTML = '<span>' + T('Install UPZONE on your phone for a full-screen, app-like experience.', 'Installe UPZONE sur ton téléphone : plein écran, comme une application.') + '</span><button type="button" class="button small" data-install-go>' + T('Install', 'Installer') + '</button><button type="button" class="link" data-install-dismiss aria-label="' + T('Not now', 'Pas maintenant') + '">✕</button>';
        node.querySelector('[data-install-dismiss]').onclick = function () { try { localStorage.setItem('prorod-install-dismissed', String(Date.now())); } catch (_) {} node.hidden = true; };
      }
      var go = node.querySelector('[data-install-go]') || node;
      go.addEventListener('click', function (e) { e.preventDefault(); install(); });
    });
  }
  window.PRodInstall = { install: install, isStandalone: function () { return standalone; } };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', render); else render();
})();
