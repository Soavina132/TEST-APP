import { useEffect, useRef, useState, useCallback } from "react";
import { toast } from "sonner";

/**
 * Handles automatic reconnexion during a game session.
 *
 * - Monitors browser online/offline events.
 * - Detects slow connections via periodic latency pings.
 * - When back online: waits 1.5 s for Supabase to re-establish its WS,
 *   then calls `onReconnect()` to refresh game state.
 * - Auto-reconnects when connection drops or becomes very slow.
 * - Uses exponential backoff for repeated reconnection attempts
 *   (1s -> 2s -> 4s -> 8s -> 16s, capped at 30s) to avoid hammering the
 *   server on persistently unstable networks.
 * - Cancels any in-flight reconnect timer when a new one starts
 *   (prevents race condition on rapid offline/online toggles).
 * - Exposes `isConnected`, `isReconnecting`, and `isSlow` for the UI overlay.
 * - `retry()` lets the user manually trigger a reconnection attempt
 *   (also resets the backoff counter).
 *
 * Toasts are kept minimal -- the reconnect overlay handles the visual feedback.
 */

const PING_INTERVAL_MS = 10_000; // check every 10s
const SLOW_THRESHOLD_MS = 3000;  // >3s = slow
const OFFLINE_TIMEOUT_MS = 5000; // no response in 5s = consider offline

// Exponential backoff: 1s, 2s, 4s, 8s, 16s, capped at 30s
const BACKOFF_BASE_MS = 1000;
const BACKOFF_MAX_MS = 30_000;
const BACKOFF_MAX_ATTEMPTS = 6; // gives up after ~60s of retries

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

  // ── Backoff state ─────────────────────────────────────────────────
  const reconnectTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const backoffAttemptRef = useRef(0); // 0 = first attempt, increments on failure

  /** Clear any pending reconnect timer (prevents overlapping reconnects) */
  const clearReconnectTimer = useCallback(() => {
    if (reconnectTimerRef.current !== null) {
      clearTimeout(reconnectTimerRef.current);
      reconnectTimerRef.current = null;
    }
  }, []);

  /**
   * Attempt reconnection with exponential backoff.
   * - Clears any existing timer first (race-condition guard).
   * - Calls onReconnect(), then checks if we're truly online.
   * - If still offline, schedules the next attempt with increasing delay.
   * - Gives up after BACKOFF_MAX_ATTEMPTS; user can retry manually.
   */
  const doReconnect = useCallback(() => {
    // Cancel any previous reconnect timer (race-condition fix)
    clearReconnectTimer();

    const attempt = backoffAttemptRef.current;
    const delay = Math.min(BACKOFF_BASE_MS * 2 ** attempt, BACKOFF_MAX_MS);

    setIsReconnecting(true);

    reconnectTimerRef.current = setTimeout(async () => {
      reconnectTimerRef.current = null;

      // If still offline, schedule next attempt with backoff
      const online = typeof navigator !== "undefined" ? navigator.onLine : true;
      if (!online) {
        backoffAttemptRef.current += 1;
        if (backoffAttemptRef.current < BACKOFF_MAX_ATTEMPTS) {
          // Still offline -- try again after backoff delay
          doReconnect();
        } else {
          // Max attempts reached -- show offline state, wait for manual retry
          setIsReconnecting(false);
          setIsConnected(false);
        }
        return;
      }

      // We're online -- call the reconnect callback
      try {
        await callbackRef.current();
      } catch {
        // Callback failed (e.g. fetch error) -- retry with backoff
        backoffAttemptRef.current += 1;
        if (backoffAttemptRef.current < BACKOFF_MAX_ATTEMPTS) {
          doReconnect();
          return;
        }
      }

      // Success -- reset everything
      backoffAttemptRef.current = 0;
      setIsConnected(true);
      setIsReconnecting(false);
      setIsSlow(false);
      if (wasOfflineRef.current) {
        wasOfflineRef.current = false;
        toast.success("Reconnecte", { duration: 1500 });
      }
    }, delay);
  }, [clearReconnectTimer]);

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
        const url = (import.meta.env.VITE_SUPABASE_URL as string) + "/rest/v1/profiles?select=id&limit=1";
        const key = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;
        const t0 = performance.now();
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), OFFLINE_TIMEOUT_MS);

        await fetch(url, {
          method: "GET",
          cache: "no-store",
          headers: { apikey: key, Authorization: `Bearer ${key}` },
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
            doReconnect();
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
      // Reset backoff on genuine online event -- network just came back
      backoffAttemptRef.current = 0;
      doReconnect();
    };

    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);

    return () => {
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("online", handleOnline);
    };
  }, [doReconnect]);

  // ── Cleanup on unmount ─────────────────────────────────────────────
  useEffect(() => {
    return () => clearReconnectTimer();
  }, [clearReconnectTimer]);

  /** Manual retry triggered from the overlay button -- resets backoff */
  const retry = useCallback(() => {
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      toast.error("Hors ligne", { duration: 1500 });
      return;
    }
    // Reset backoff counter on manual retry
    backoffAttemptRef.current = 0;
    doReconnect();
  }, [doReconnect]);

  return { isConnected, isReconnecting, isSlow, retry };
}
