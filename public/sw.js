// Minimal service worker: makes the app installable. Pages are NOT cached on purpose,
// because attendance data must always be live and behind login.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));
self.addEventListener("fetch", () => {});
