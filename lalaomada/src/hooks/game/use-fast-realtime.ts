import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";

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
  // Track the last optimistic update from an RPC call to prevent stale
  // realtime events (from intermediate UPDATEs inside the same RPC) from
  // overwriting a newer state. The ref stores the board length of the
  // last optimistic state; realtime events with a shorter board are skipped.
  const optBoardLenRef = useRef<number>(0);
  // Track the last optimistic current_turn from an RPC response.
  // Realtime events with a different current_turn are from intermediate
  // UPDATEs (before the bot played) and should be skipped.
  const optTurnRef = useRef<any>(null);
  const heartbeatRef = useRef<ReturnType<typeof setInterval> | null>(null);
  // Keep onFinished in a ref so the realtime closure never goes stale
  const onFinishedRef = useRef(onFinished);
  useEffect(() => { onFinishedRef.current = onFinished; }, [onFinished]);

  const reload = useCallback(async () => {
    try {
      // Use select("*") instead of a fixed column list — different game tables
      // have different columns (e.g. ludo has no turn_phase, domino has no joker_mode).
      // A fixed list causes the query to fail on tables missing those columns,
      // leaving the page stuck on loading and the user as a spectator.
      const { data: g, error: e1 } = await supabase.from(gameTable).select("*").eq("id", gameId).maybeSingle();
      if (e1 && !g) { console.warn("[realtime] load error:", e1); setLoading(false); return; }
      const { data: p, error: e2 } = await supabase.from(participantTable).select("*").eq("game_id", gameId).order("slot");
      if (e2 && !p) { console.warn("[realtime] parts error:", e2); }
      setGame(g as TGame);
      setParts((p as TParticipant[]) || []);
      setLoading(false);
      if ((g as any)?.status === "finished" && onFinishedRef.current) onFinishedRef.current();
    } catch (err) { console.error("[realtime] reload:", err); setLoading(false); }
  }, [gameTable, participantTable, gameId]);

  const debouncedReload = useCallback(() => {
    if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
    // Reduced to 80ms for near-instant fallback sync
    reloadTimerRef.current = setTimeout(() => reload(), 80);
  }, [reload]);

  useEffect(() => {
    if (!enabled || !gameId) return;
    reload();

    const ch: any = supabase.channel(`rt-${gameTable}-${gameId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: gameTable, filter: `id=eq.${gameId}` }, (payload: any) => {
        if (payload.eventType === "DELETE") { debouncedReload(); return; }
        if (payload.new) {
          setGame((prev: any) => {
            if (!prev) return payload.new as TGame;
            // Skip stale realtime events: if the current state has a longer
            // board than the incoming event, the event is from an intermediate
            // UPDATE (before bot moves) and should not overwrite the newer
            // optimistic state from the RPC response.
            const prevBoardLen = prev.state?.board ? (Array.isArray(prev.state.board) ? prev.state.board.length : 0) : 0;
            const newBoardLen = payload.new.state?.board ? (Array.isArray(payload.new.state.board) ? payload.new.state.board.length : 0) : 0;
            if (prevBoardLen > newBoardLen) return prev;
            // Reset the optimistic ref when we accept a realtime event
            return payload.new as TGame;
          });
          if (payload.new.status === "finished" && onFinishedRef.current) onFinishedRef.current();
        }
      })
      .on("postgres_changes", { event: "*", schema: "public", table: participantTable, filter: `game_id=eq.${gameId}` }, (payload: any) => {
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

    for (const extra of extraTables) {
      ch.on("postgres_changes", { event: extra.event || "*", schema: "public", table: extra.table, filter: extra.filter }, () => debouncedReload());
    }

    ch.subscribe((status: string) => {
      if (status === "SUBSCRIBED") {
        setConnected(true);
        // Safety-net heartbeat: periodically reload in case we missed an event
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

  return { game, parts, setGame, setParts, loading, connected, reload, optTurnRef };
}
