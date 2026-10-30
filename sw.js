// Minimaler Service Worker: macht die Seite installierbar.
// Bewusst kein Offline-Cache, damit immer die aktuellen Buchungen und die neueste Version geladen werden.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', e => e.waitUntil(self.clients.claim()));
self.addEventListener('fetch', () => {});
