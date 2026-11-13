const CACHE = 'prorod-shell-v11';
const ASSETS = ['./index.html', './demo.html', './pwa-install.js', './install.css', './app.css', './app.js', './install.js', './manifest.webmanifest', './assets/upzone-icon-192.png', './assets/upzone-icon-512.png', './assets/apple-touch-icon.png', './assets/maya.jpg', './assets/adam.jpg', './account.html', './account.css', './member-design.css', './welcome.js', './account.bundle.js'];
const allowed = new Set(ASSETS.map(path => new URL(path, self.registration.scope).href));
self.addEventListener('install', event => event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(ASSETS)).then(() => self.skipWaiting())));
self.addEventListener('activate', event => event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('prorod-shell-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim())));
self.addEventListener('fetch', event => {
  const request = event.request, url = new URL(request.url);
  if (request.method !== 'GET' || url.origin !== self.location.origin) return;
  const home = new URL('./', self.registration.scope).pathname;
  if (request.mode === 'navigate' && [home, home + 'index.html', home + 'demo.html', home + 'account.html'].includes(url.pathname)) {
    const fallback = url.pathname.endsWith('demo.html') ? './demo.html' : './account.html';
    // 'no-cache' = always ask the server whether the file changed (GitHub Pages lets browsers keep files 10 minutes otherwise).
    event.respondWith(fetch(request.url, { cache: 'no-cache', credentials: 'same-origin' }).catch(() => caches.match(new URL(fallback, self.registration.scope).href)));
    return;
  }
  // Explicit public shell allowlist: never cache auth, APIs, messages or reports.
  if (!allowed.has(url.href)) return;
  event.respondWith(fetch(request.url, { cache: 'no-cache', credentials: 'same-origin' }).catch(() => caches.match(request)));
});
// Push notifications: the payload only carries a generic sentence and the unread count (never a name or a message),
// so nothing private is handled or stored here.
self.addEventListener('push', event => {
  let data = {};
  try { data = event.data ? event.data.json() : {}; } catch { data = {}; }
  const badge = Number.isFinite(data.badge) ? data.badge : 0;
  const jobs = [self.registration.showNotification(String(data.title || 'UPZONE'), {
    body: String(data.body || ''),
    icon: './assets/upzone-icon-192.png',
    badge: './assets/upzone-icon-192.png',
    tag: String(data.tag || 'upzone'),
    renotify: true,
    data: { url: new URL(String(data.url || './account.html'), self.registration.scope).href }
  })];
  if ('setAppBadge' in self.navigator) jobs.push((badge > 0 ? self.navigator.setAppBadge(badge) : self.navigator.clearAppBadge()).catch(() => {}));
  event.waitUntil(Promise.all(jobs));
});
self.addEventListener('notificationclick', event => {
  event.notification.close();
  const target = event.notification.data && event.notification.data.url ? event.notification.data.url : new URL('./account.html', self.registration.scope).href;
  // Only ever open pages of this app.
  const safe = target.startsWith(self.registration.scope) ? target : new URL('./account.html', self.registration.scope).href;
  event.waitUntil(self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then(list => {
    for (const client of list) if (client.url.startsWith(self.registration.scope) && 'focus' in client) { client.navigate(safe).catch(() => {}); return client.focus(); }
    return self.clients.openWindow(safe);
  }));
});
