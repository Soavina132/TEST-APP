import { useEffect, useRef, useState, useCallback } from "react";
import { toast } from "sonner";

/**
 * Handles automatic reconnection during a game session.
 *
 * - Monitors browser online/offline events.
 * - Detects slow connections via periodic latency pings.
 * - When back online: waits 1.5 s for Supabase to re-establish its WS,
 *   then calls `onReconnect()` to refresh game state.
 * - Auto-reconnects when connection drops or becomes very slow.
 * - Exposes `isConnected`, `isReconnecting`, and `isSlow` for the UI overlay.
 * - `retry()` lets the user manually trigger a reconnection attempt.
 *
 * Toasts are kept minimal — the reconnect overlay handles the visual feedback.
 */

const PING_INTERVAL_MS = 15_000; // check every 15s
const SLOW_THRESHOLD_MS = 3000;  // >3s = slow
const OFFLINE_TIMEOUT_MS = 8000; // no response in 8s = consider offline

export function useGameConnection({ onReconnect }: { onReconnect: () => void }) {
  const [isConnected, setIsConnected] = useState(
    typeof navigator !== "undefined" ? navigator.onLine : true,
  );
  const [isReconnecting, setIsReconnecting] = useState(false);
  const [isSlow, setIsSlow] = useState(false);

  // Keep callback ref stable so the effect closure never goes stale
  const callbackRef = useRef(onReconnect);
  useEffect(() => {
    callbackRef.current = onReconnect;
  }, [onReconnect]);

  // Track whether we've shown the "lost" state so we don't spam
  const wasOfflineRef = useRef(false);

  const doReconnect = useCallback(() => {
    setIsReconnecting(true);
    const t = setTimeout(() => {
      callbackRef.current();
      const online = typeof navigator !== "undefined" ? navigator.onLine : true;
      setIsConnected(online);
      setIsReconnecting(false);
      setIsSlow(false);
      if (online && wasOfflineRef.current) {
        wasOfflineRef.current = false;
        toast.success("Reconnecté", { duration: 1500 });
      }
    }, 1500);
    return t;
  }, []);

  // ── Periodic latency ping ──────────────────────────────────────────
  useEffect(() => {
    let cancelled = false;

    const ping = async () => {
      if (cancelled) return;
      if (typeof navigator !== "undefined" && !navigator.onLine) {
        if (!wasOfflineRef.current) {
          wasOfflineRef.current = true;
          setIsConnected(false);
        }
        return;
      }

      try {
        const url = (import.meta.env.VITE_SUPABASE_URL as string) + "/rest/v1/";
        const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;
        const t0 = performance.now();
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), OFFLINE_TIMEOUT_MS);

        await fetch(url, {
          method: "HEAD",
          cache: "no-store",
          headers: { apikey: key },
          signal: controller.signal,
        });
        clearTimeout(timeoutId);

        if (cancelled) return;
        const latency = performance.now() - t0;

        if (latency > SLOW_THRESHOLD_MS) {
          if (!wasOfflineRef.current) {
            wasOfflineRef.current = true;
            setIsConnected(false);
            setIsSlow(true);
            const t = doReconnect();
            return () => clearTimeout(t);
          }
        } else {
          if (wasOfflineRef.current) {
            wasOfflineRef.current = false;
            setIsConnected(true);
            setIsSlow(false);
          } else {
            setIsConnected(true);
            setIsSlow(false);
          }
        }
      } catch {
        if (cancelled) return;
        if (!wasOfflineRef.current) {
          wasOfflineRef.current = true;
          setIsConnected(false);
        }
      }
    };

    ping();
    const id = setInterval(ping, PING_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [doReconnect]);

  // ── Browser online/offline events ─────────────────────────────────
  useEffect(() => {
    const handleOffline = () => {
      if (!wasOfflineRef.current) {
        wasOfflineRef.current = true;
      }
      setIsConnected(false);
    };

    const handleOnline = () => {
      doReconnect();
    };

    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);

    return () => {
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("online", handleOnline);
    };
  }, [doReconnect]);

  /** Manual retry triggered from the overlay button */
  const retry = useCallback(() => {
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      toast.error("Hors ligne", { duration: 1500 });
      return;
    }
    doReconnect();
  }, [doReconnect]);

  return { isConnected, isReconnecting, isSlow, retry };
}
