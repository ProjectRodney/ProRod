const CACHE = 'prorod-shell-v3';
const ASSETS = ['./index.html', './app.css', './app.js', './install.js', './manifest.webmanifest', './assets/prod-logo.png', './assets/maya.jpg', './assets/adam.jpg', './account.html', './account.css', './account.bundle.js'];
const allowed = new Set(ASSETS.map(path => new URL(path, self.registration.scope).href));
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS))));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('prorod-shell-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())));
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  const home = new URL('./', self.registration.scope).pathname;
  if (request.mode === 'navigate' && [home, home + 'index.html', home + 'account.html'].includes(url.pathname)) {
    const fallback = url.pathname.endsWith('account.html') ? './account.html' : './index.html';
    event.respondWith(fetch(request).catch(() => caches.match(new URL(fallback, self.registration.scope).href)));
    return;
  }
  // Explicit public shell allowlist: never cache auth, APIs, messages or reports.
  if (!allowed.has(url.href)) return;
  event.respondWith(fetch(request).catch(() => caches.match(request)));
});
