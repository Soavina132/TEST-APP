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
  const optBoardLenRef = useRef<number>(0);
  const optTurnRef = useRef<any>(null);
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
        if (!prev) return g as TGame;
        if (optTurnRef.current !== null && (g as any).current_turn !== optTurnRef.current) {
          return prev;
        }
        optTurnRef.current = null;
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
            const prevUpdated = (prev as any).updated_at;
            const newUpdated = (payload.new as any).updated_at;
            if (prevUpdated && newUpdated && newUpdated < prevUpdated) return prev;
            if (optTurnRef.current !== null && (payload.new as any).current_turn !== optTurnRef.current) {
              return prev;
            }
            const prevBoardLen = prev.state?.board ? (Array.isArray(prev.state.board) ? prev.state.board.length : 0) : 0;
            const newBoardLen = payload.new.state?.board ? (Array.isArray(payload.new.state.board) ? payload.new.state.board.length : 0) : 0;
            if (prevBoardLen > newBoardLen) return prev;
            optTurnRef.current = null;
            return payload.new as TGame;
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

  return { game, parts, setGame, setParts, loading, connected, reload, optTurnRef };
}
