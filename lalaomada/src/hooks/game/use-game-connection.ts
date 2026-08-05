import { useEffect, useRef, useState, useCallback } from "react";
import { toast } from "sonner";

/**
 * Handles automatic reconnection during a game session.
 *
 * - Monitors browser online/offline events.
 * - When back online: waits 1.5 s for Supabase to re-establish its WS,
 *   then calls `onReconnect()` to refresh game state.
 * - Exposes `isConnected` and `isReconnecting` for the UI overlay.
 * - `retry()` lets the user manually trigger a reconnection attempt.
 */
export function useGameConnection({ onReconnect }: { onReconnect: () => void }) {
  const [isConnected, setIsConnected] = useState(
    typeof navigator !== "undefined" ? navigator.onLine : true,
  );
  const [isReconnecting, setIsReconnecting] = useState(false);

  // Keep callback ref stable so the effect closure never goes stale
  const callbackRef = useRef(onReconnect);
  useEffect(() => {
    callbackRef.current = onReconnect;
  }, [onReconnect]);

  const doReconnect = useCallback(() => {
    setIsReconnecting(true);
    // Give Supabase Realtime ~1.5 s to re-subscribe before reloading state
    const t = setTimeout(() => {
      callbackRef.current();
      setIsConnected(typeof navigator !== "undefined" ? navigator.onLine : true);
      setIsReconnecting(false);
      toast.success("Connexion rétablie ✓");
    }, 1500);
    return t;
  }, []);

  useEffect(() => {
    const handleOffline = () => {
      setIsConnected(false);
      toast.warning("Connexion perdue — votre partie est en pause");
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
    if (!navigator.onLine) {
      toast.error("Toujours hors ligne — vérifiez votre réseau");
      return;
    }
    doReconnect();
  }, [doReconnect]);

  return { isConnected, isReconnecting, retry };
}
