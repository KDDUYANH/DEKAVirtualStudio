/**
 * DEKA BACKGROUND ENGINE - SERVICE WORKER
 * Ensures 24/7 Offline Continuity and Zero-Downtime White Screen Prevention
 */

const CACHE_NAME = 'deka-bg-engine-v1';
const STATIC_ASSETS = [
  '/output/index.html',
  '/output/engine.css',
  '/output/compositor.js',
  '/output/watchdog.js',
  '/output/wsClient.js',
  '/assets/deka-logo.svg',
  '/assets/background-studio.svg',
  '/assets/background-fallback.svg',
  '/manifest.json'
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      console.log('[ServiceWorker] Pre-caching static broadcast assets');
      return cache.addAll(STATIC_ASSETS);
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => {
      return Promise.all(
        keys.map((key) => {
          if (key !== CACHE_NAME) {
            console.log('[ServiceWorker] Removing legacy cache:', key);
            return caches.delete(key);
          }
        })
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);

  // Skip caching WebSocket, telemetry heartbeats or live dynamic widgets
  if (url.pathname.startsWith('/ws') || url.pathname.startsWith('/api/telemetry')) {
    return;
  }

  event.respondWith(
    caches.match(event.request).then((cachedResponse) => {
      if (cachedResponse) {
        // Fetch in background to update cache (Stale-While-Revalidate)
        fetch(event.request).then((networkResponse) => {
          if (networkResponse.status === 200) {
            caches.open(CACHE_NAME).then((cache) => cache.put(event.request, networkResponse));
          }
        }).catch(() => {
          // Network offline, keep using cachedResponse
        });
        return cachedResponse;
      }

      // If not in cache, try network
      return fetch(event.request).then((networkResponse) => {
        if (!networkResponse || networkResponse.status !== 200 || networkResponse.type !== 'basic') {
          return networkResponse;
        }
        const responseToCache = networkResponse.clone();
        caches.open(CACHE_NAME).then((cache) => {
          cache.put(event.request, responseToCache);
        });
        return networkResponse;
      }).catch(() => {
        // Degraded fallback for images
        if (event.request.destination === 'image') {
          return caches.match('/assets/background-fallback.svg');
        }
      });
    })
  );
});
