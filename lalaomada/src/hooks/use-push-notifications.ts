import { useEffect, useRef, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";

// ─────────────────────────────────────────────────────────────────────────────
// usePushNotifications — registers service worker, subscribes to web push,
// and stores the subscription in the push_subscriptions table.
// ─────────────────────────────────────────────────────────────────────────────

// VAPID public key (safe to expose — only used for subscription, not signing)
const VAPID_PUBLIC_KEY =
  "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEIgW5W92vNMnFgOlXsTlMnpu71kxB90jqGdzMdvUDvzUjmpytXPlhhcZfHxB7sjNnbhYjI_aoG0eTjSyMs1xHYg";

function urlBase64ToUint8Array(base64String: string): Uint8Array {
  const padding = "=".repeat((4 - (base64String.length % 4)) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}

export function usePushNotifications() {
  const { user, profile } = useAuth();
  const registered = useRef(false);

  const subscribe = useCallback(async () => {
    if (!user?.id) return;

    try {
      // Register service worker
      const reg = await navigator.serviceWorker.register("/sw.js");
      await navigator.serviceWorker.ready;

      // Check existing subscription
      let sub = await reg.pushManager.getSubscription();

      if (!sub) {
        // Request notification permission first
        const permission = await Notification.requestPermission();
        if (permission !== "granted") return;

        // Subscribe to push
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY),
        });
      }

      if (!sub) return;

      // Store/update subscription in database
      const subJson = sub.toJSON();
      const { error } = await supabase
        .from("push_subscriptions" as any)
        .upsert(
          {
            user_id: user.id,
            endpoint: subJson.endpoint,
            p256dh: subJson.keys?.p256dh,
            auth: subJson.keys?.auth,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "user_id,endpoint", ignoreDuplicates: false } as any,
        );

      if (error && !error.message.includes("duplicate")) {
        console.warn("[push] Failed to store subscription:", error.message);
      }
    } catch (e) {
      console.warn("[push] Subscription error:", e);
    }
  }, [user?.id]);

  useEffect(() => {
    if (!user?.id || registered.current) return;
    registered.current = true;

    // Register SW + subscribe after a short delay (don't block initial render)
    const timer = setTimeout(() => {
      if ("serviceWorker" in navigator && "PushManager" in window) {
        subscribe();
      }
    }, 2000);

    return () => clearTimeout(timer);
  }, [user?.id, subscribe]);

  // Also request permission proactively
  useEffect(() => {
    if (!user?.id) return;
    if ("Notification" in window && Notification.permission === "default") {
      // Don't request immediately — let the bell component handle it
    }
  }, [user?.id]);
}
