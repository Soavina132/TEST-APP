// Service Worker for Lalao MADA - Push Notifications
const CACHE_NAME = "lalaomada-v1";

// Install event
self.addEventListener("install", (event) => {
  (self as any).skipWaiting();
});

// Activate event
self.addEventListener("activate", (event) => {
  event.waitUntil((self as any).clients.claim());
});

// Push event - received from server
self.addEventListener("push", (event) => {
  if (!event.data) return;

  try {
    const payload = event.data.json().catch(() => ({
      title: "Lalao MADA",
      body: event.data.text() || "Nouvelle notification",
    }));

    event.waitUntil(
      Promise.resolve(payload).then((data) => {
        const title = data.title || "Lalao MADA";
        const options = {
          body: data.body || "",
          icon: "/favicon.ico",
          badge: "/favicon.ico",
          tag: data.tag || "default",
          data: {
            url: data.url || data.link || "/",
          },
          vibrate: [200, 100, 200],
          requireInteraction: data.requireInteraction || false,
          actions: data.actions || [],
        };

        return (self as any).registration.showNotification(title, options);
      })
    );
  } catch (e) {
    // Plain text fallback
    event.waitUntil(
      (self as any).registration.showNotification("Lalao MADA", {
        body: event.data.text(),
        icon: "/favicon.ico",
      })
    );
  }
});

// Notification click
self.addEventListener("notificationclick", (event) => {
  event.notification.close();

  const url = event.notification.data?.url || "/";

  event.waitUntil(
    (async () => {
      const allClients = await (self as any).clients.matchAll({ type: "window" });

      if (allClients.length > 0) {
        // Focus existing tab and navigate
        const client = allClients[0];
        await client.focus();
        client.navigate(url);
      } else {
        // Open new window
        await (self as any).clients.openWindow(url);
      }
    })()
  );
});

// Push subscription change
self.addEventListener("pushsubscriptionchange", (event) => {
  event.waitUntil(
    (self as any).registration.pushManager
      .subscribe({
        userVisibleOnly: true,
        applicationServerKey: urlBase64ToUint8Array(
          (self as any).VAPID_PUBLIC_KEY || ""
        ),
      })
      .then((newSub: any) => {
        // TODO: send new subscription to server
        return fetch("/api/push-subscription", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(newSub),
        });
      })
  );
});

// Helper
function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding)
    .replace(/-/g, "+")
    .replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}
