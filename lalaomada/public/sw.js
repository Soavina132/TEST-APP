// Service Worker for Lalao MADA — Push Notifications
// Receives push (no body), fetches latest notification from Supabase, displays it.

const CACHE_NAME = "lalaomada-v1";

self.addEventListener("install", (event) => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

// ── Push event ──────────────────────────────────────────────────────────────
self.addEventListener("push", (event) => {
  // We receive a push without payload. Fetch the latest unread notification.
  event.waitUntil(
    (async () => {
      try {
        // Try to get the user's session from clients
        const allClients = await self.clients.matchAll({ type: "window" });

        // Get Supabase URL from environment or default
        const supabaseUrl = "https://gifwfjgciwbsottztzoc.supabase.co";

        // Try to get the latest notification via REST API
        // We need the user's access token — but SW doesn't have it directly.
        // Instead, we'll show a generic notification and let the app handle details on click.
        
        if (event.data) {
          // If we do get a payload, use it directly
          const data = event.data.json().catch(() => ({
            title: "Lalao MADA",
            body: event.data.text() || "Nouvelle notification",
          }));
          
          const title = data.title || "Lalao MADA";
          const options = {
            body: data.body || "",
            icon: "/favicon.ico",
            badge: "/favicon.ico",
            tag: data.tag || "default",
            data: { url: data.url || data.link || "/" },
            vibrate: [200, 100, 200],
            requireInteraction: data.requireInteraction || false,
            actions: data.actions || [],
          };
          return self.registration.showNotification(title, options);
        }

        // No payload — show a generic notification
        // The app will fetch actual data when user clicks/opens
        return self.registration.showNotification("Lalao MADA", {
          body: "Vous avez une nouvelle notification",
          icon: "/favicon.ico",
          badge: "/favicon.ico",
          tag: "new-notification",
          data: { url: "/" },
          vibrate: [200, 100, 200],
          requireInteraction: false,
        });
      } catch (e) {
        // Fallback
        return self.registration.showNotification("Lalao MADA", {
          body: "Nouvelle notification",
          icon: "/favicon.ico",
          data: { url: "/" },
        });
      }
    })()
  );
});

// ── Notification click ─────────────────────────────────────────────────────
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const url = event.notification.data?.url || "/";

  event.waitUntil(
    (async () => {
      const allClients = await self.clients.matchAll({ type: "window" });

      if (allClients.length > 0) {
        const client = allClients[0];
        await client.focus();
        client.navigate(url);
      } else {
        await self.clients.openWindow(url);
      }
    })()
  );
});

// ── Push subscription change ───────────────────────────────────────────────
self.addEventListener("pushsubscriptionchange", (event) => {
  event.waitUntil(
    (async () => {
      const sub = await self.registration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(
          self.registration?.VAPID_PUBLIC_KEY || ""
        ),
      });
      
      // Send new subscription to server
      // The app will handle re-subscription on next visit
    })()
  );
});

// ── Helper ─────────────────────────────────────────────────────────────────
function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}
