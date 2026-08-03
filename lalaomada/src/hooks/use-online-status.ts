import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type NetworkQuality = "excellent" | "good" | "fair" | "poor" | "offline" | "unknown";

export interface OnlineStatusResult {
  /** Number of users currently tracked via Supabase Presence */
  onlineCount: number;
  /** Round-trip time to Supabase in milliseconds (null = not measured yet) */
  latencyMs: number | null;
  /** Network type from browser API: '4g' | '3g' | '2g' | 'slow-2g' | null */
  effectiveType: string | null;
  /** Derived quality rating */
  quality: NetworkQuality;
  /** Whether the browser reports an internet connection at all */
  isOnline: boolean;
}

/**
 * Tracks:
 * 1. Global online player count via Supabase Realtime Presence
 * 2. Network type via navigator.connection (Chrome / Android)
 * 3. Real latency via periodic HEAD ping to Supabase REST endpoint
 */
export function useOnlineStatus(userId?: string): OnlineStatusResult {
  const [onlineCount, setOnlineCount]     = useState(0);
  const [latencyMs, setLatencyMs]         = useState<number | null>(null);
  const [effectiveType, setEffectiveType] = useState<string | null>(null);
  const [isOnline, setIsOnline]           = useState(typeof navigator !== "undefined" ? navigator.onLine : true);

  // ── 1. Browser online / offline events ──────────────────────────────
  useEffect(() => {
    const onOnline  = () => setIsOnline(true);
    const onOffline = () => setIsOnline(false);
    window.addEventListener("online",  onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.removeEventListener("online",  onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, []);

  // ── 2. Network Information API (Chrome / Android) ────────────────────
  useEffect(() => {
    const conn: any = (navigator as any).connection
      || (navigator as any).mozConnection
      || (navigator as any).webkitConnection;
    if (!conn) return;

    const update = () => setEffectiveType(conn.effectiveType ?? null);
    update();
    conn.addEventListener("change", update);
    return () => conn.removeEventListener("change", update);
  }, []);

  // ── 3. Supabase Presence — global player count ───────────────────────
  useEffect(() => {
    if (!userId) return;

    // One shared channel for the whole app — keyed by userId so each
    // browser tab counts as one presence entry even if the user has the
    // app open in two tabs.
    const channel = supabase.channel("global-presence", {
      config: { presence: { key: userId } },
    });

    channel
      .on("presence", { event: "sync" }, () => {
        setOnlineCount(Object.keys(channel.presenceState()).length);
      })
      .subscribe(async (status) => {
        if (status === "SUBSCRIBED") {
          await channel.track({ user_id: userId, at: Date.now() });
        }
      });

    return () => { supabase.removeChannel(channel); };
  }, [userId]);

  // ── 4. Latency ping — HEAD to Supabase REST every 30 s ──────────────
  useEffect(() => {
    let cancelled = false;

    const ping = async () => {
      if (cancelled || !navigator.onLine) return;
      try {
        const url = (import.meta.env.VITE_SUPABASE_URL as string) + "/rest/v1/";
        const key =  import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string;
        const t0 = performance.now();
        await fetch(url, { method: "HEAD", cache: "no-store", headers: { apikey: key } });
        if (!cancelled) setLatencyMs(Math.round(performance.now() - t0));
      } catch {
        if (!cancelled) setLatencyMs(null);
      }
    };

    ping();
    const id = setInterval(ping, 30_000);
    return () => { cancelled = true; clearInterval(id); };
  }, []);

  // ── Derive quality ───────────────────────────────────────────────────
  const quality: NetworkQuality = !isOnline       ? "offline"
    : latencyMs === null                           ? "unknown"
    : latencyMs < 100                              ? "excellent"
    : latencyMs < 250                              ? "good"
    : latencyMs < 600                              ? "fair"
    :                                                "poor";

  return { onlineCount, latencyMs, effectiveType, quality, isOnline };
}
