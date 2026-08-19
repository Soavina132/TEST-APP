import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";

// Robust date parsing — server sends "2026-08-13 22:19:51.286929+00"
// (PostgreSQL format with space instead of T), while client optimistic
// uses ISO "2026-08-19T10:50:30.123Z". String comparison fails across
// these formats. Parse to epoch ms for correct comparison.
function parseDateMs(s: any): number {
  if (!s) return 0;
  // Replace space with T to make it ISO-compatible
  const str = typeof s === 'string' ? s.replace(' ', 'T') : String(s);
  const d = new Date(str);
  return isNaN(d.getTime()) ? 0 : d.getTime();
}

interface FastRealtimeOptions {
  gameTable: string;
  participantTable: string;
  gameId: string;
  enabled?: boolean;
  extraTables?: { table: string; filter: string; event?: string }[];
  onFinished?: () => void;
}

const HEARTBEAT_INTERVAL_MS = 10_000; // safety-net reload every 10s

export function useFastRealtime<TGame = any, TParticipant = any>({
  gameTable, participantTable, gameId, enabled = true, extraTables = [], onFinished,
}: FastRealtimeOptions) {
  const [game, setGame] = useState<TGame | null>(null);
  const [parts, setParts] = useState<TParticipant[]>([]);
  const [loading, setLoading] = useState(true);
  const [connected, setConnected] = useState(false);
  const reloadTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const heartbeatRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const onFinishedRef = useRef(onFinished);
  useEffect(() => { onFinishedRef.current = onFinished; }, [onFinished]);

  const reload = useCallback(async () => {
    try {
      const { data: g, error: e1 } = await supabase.from(gameTable).select("*").eq("id", gameId).maybeSingle();
      if (e1 && !g) { console.warn("[realtime] load error:", e1); setLoading(false); return; }
      let p: any = null;
      if (participantTable) {
        const res = await supabase.from(participantTable).select("*").eq("game_id", gameId).order("slot");
        p = res.data;
        if (res.error && !res.data) { console.warn("[realtime] parts error:", res.error); }
      }
      setGame((prev: any) => {
        // Guard: if the query returned null (game deleted or RLS blocked),
        // keep the previous state instead of crashing on .updated_at access.
        if (!g) return prev;
        if (!prev) return g as TGame;
        // Only accept newer state (updated_at guard)
        // Parse dates properly — server uses "2026-08-13 22:19:51.286929+00"
        // while client optimistic uses ISO "2026-08-19T10:50:30.123Z".
        // String comparison would always reject server events (space < T).
        const prevUpdated = (prev as any).updated_at;
        const newUpdated = (g as any).updated_at;
        if (prevUpdated && newUpdated) {
          const pt = parseDateMs(prevUpdated);
          const nt = parseDateMs(newUpdated);
          if (pt && nt && nt < pt) return prev;
        }
        return g as TGame;
      });
      setParts((p as TParticipant[]) || []);
      setLoading(false);
      if ((g as any)?.status === "finished" && onFinishedRef.current) onFinishedRef.current();
    } catch (err) { console.error("[realtime] reload:", err); setLoading(false); }
  }, [gameTable, participantTable, gameId]);

  const debouncedReload = useCallback(() => {
    if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
    reloadTimerRef.current = setTimeout(() => reload(), 80);
  }, [reload]);

  useEffect(() => {
    if (!enabled || !gameId) return;
    reload();

    let ch: any = supabase.channel(`rt-${gameTable}-${gameId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: gameTable, filter: `id=eq.${gameId}` }, (payload: any) => {
        if (payload.eventType === "DELETE") { debouncedReload(); return; }
        if (payload.new) {
          setGame((prev: any) => {
            if (!prev) return payload.new as TGame;
            const newGame = payload.new as any;
            const prevUpdated = (prev as any).updated_at;
            const newUpdated = newGame.updated_at;
            if (prevUpdated && newUpdated) {
              const pt = parseDateMs(prevUpdated);
              const nt = parseDateMs(newUpdated);
              if (pt && nt && nt < pt) return prev;
            }
            return newGame as TGame;
          });
          if (payload.new.status === "finished" && onFinishedRef.current) onFinishedRef.current();
        }
      });

    if (participantTable) {
      ch = ch.on("postgres_changes", { event: "*", schema: "public", table: participantTable, filter: `game_id=eq.${gameId}` }, (payload: any) => {
        if (payload.eventType === "INSERT" && payload.new) {
          setParts(prev => prev.some(p => (p as any).id === payload.new.id) ? prev : [...prev, payload.new]);
        } else if (payload.eventType === "UPDATE" && payload.new) {
          setParts(prev => prev.map(p => (p as any).id === payload.new.id ? payload.new : p));
        } else if (payload.eventType === "DELETE" && payload.old) {
          setParts(prev => prev.filter(p => (p as any).id !== payload.old.id));
        } else {
          debouncedReload();
        }
      });
    }

    for (const extra of extraTables) {
      ch.on("postgres_changes", { event: extra.event || "*", schema: "public", table: extra.table, filter: extra.filter }, () => debouncedReload());
    }

    ch.subscribe((status: string) => {
      if (status === "SUBSCRIBED") {
        setConnected(true);
        if (heartbeatRef.current) clearInterval(heartbeatRef.current);
        heartbeatRef.current = setInterval(() => reload(), HEARTBEAT_INTERVAL_MS);
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        setConnected(false);
        if (heartbeatRef.current) { clearInterval(heartbeatRef.current); heartbeatRef.current = null; }
        setTimeout(() => reload(), 300);
      } else if (status === "CLOSED") {
        setConnected(false);
        if (heartbeatRef.current) { clearInterval(heartbeatRef.current); heartbeatRef.current = null; }
      }
    });

    return () => {
      supabase.removeChannel(ch);
      if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
      if (heartbeatRef.current) { clearInterval(heartbeatRef.current); heartbeatRef.current = null; }
    };
  }, [gameId, enabled, gameTable, participantTable, reload, debouncedReload]);

  return { game, parts, setGame, setParts, loading, connected, reload };
}
