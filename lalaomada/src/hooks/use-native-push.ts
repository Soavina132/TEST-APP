import { useEffect, useRef } from "react";
import { PushNotifications, Token, PushNotificationSchema, ActionPerformed } from "@capacitor/push-notifications";
import { Capacitor } from "@capacitor/core";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";

/**
 * useNativePush — registers for Firebase Cloud Messaging (FCM) push notifications
 * on Android/iOS via Capacitor. Stores the device token in the `push_tokens` table.
 *
 * Notifications arrive in the phone's notification bar even when the app is closed.
 */
export function useNativePush() {
  const { user } = useAuth();
  const registered = useRef(false);

  useEffect(() => {
    if (!user?.id || registered.current) return;
    if (!Capacitor.isNativePlatform()) return;

    registered.current = true;

    let cleanup: (() => void) | undefined;

    (async () => {
      try {
        // ── 1. Request permission ──────────────────────────────────────────
        let permStatus = await PushNotifications.checkPermissions();
        if (permStatus.receive === "prompt") {
          permStatus = await PushNotifications.requestPermissions();
        }
        if (permStatus.receive !== "granted") {
          console.warn("[native-push] Permission not granted");
          return;
        }

        // ── 2. Register with FCM ────────────────────────────────────────────
        await PushNotifications.register();

        // ── 3. Listen for registration token ────────────────────────────────
        const tokenListener = await PushNotifications.addListener("registration", (token: Token) => {
          console.log("[native-push] FCM token:", token.value.substring(0, 20) + "...");
          storeToken(user.id, token.value);
        });

        // ── 4. Listen for registration errors ──────────────────────────────
        const errorListener = await PushNotifications.addListener("registrationError", (err) => {
          console.warn("[native-push] Registration error:", err);
        });

        // ── 5. Listen for foreground notifications ──────────────────────────
        const notifListener = await PushNotifications.addListener("pushNotificationReceived", (notif: PushNotificationSchema) => {
          console.log("[native-push] Foreground notification:", notif);
          // Show a toast for foreground notifications
          const title = notif.title || "Lalao MADA";
          const body = notif.body || "";
          toast(title, {
            description: body,
            duration: 8000,
          });
        });

        // ── 6. Listen for notification taps (background/terminated) ────────
        const actionListener = await PushNotifications.addListener("pushNotificationActionPerformed", (action: ActionPerformed) => {
          console.log("[native-push] Notification tapped:", action);
          const data = action.notification.data || {};
          // Navigate to the link if provided
          if (data.link || data.url) {
            const link = data.link || data.url;
            window.location.href = link as string;
          }
        });

        cleanup = async () => {
          await tokenListener?.remove();
          await errorListener?.remove();
          await notifListener?.remove();
          await actionListener?.remove();
        };
      } catch (e) {
        console.warn("[native-push] Setup error:", e);
      }
    })();

    return () => {
      cleanup?.();
    };
  }, [user?.id]);
}

/**
 * Store or update the FCM token in the push_tokens table.
 */
async function storeToken(userId: string, token: string) {
  try {
    const { error } = await supabase
      .from("push_tokens" as any)
      .upsert(
        {
          user_id: userId,
          token,
          platform: "android",
          updated_at: new Date().toISOString(),
        },
        { onConflict: "user_id,token", ignoreDuplicates: false } as any,
      );

    if (error && !error.message.includes("duplicate")) {
      console.warn("[native-push] Failed to store token:", error.message);
    } else {
      console.log("[native-push] Token stored successfully");
    }
  } catch (e) {
    console.warn("[native-push] Token storage error:", e);
  }
}
