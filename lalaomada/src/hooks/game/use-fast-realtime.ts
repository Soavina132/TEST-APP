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

export function useFastRealtime<TGame = any, TParticipant = any>({
  gameTable, participantTable, gameId, enabled = true, extraTables = [], onFinished,
}: FastRealtimeOptions) {
  const [game, setGame] = useState<TGame | null>(null);
  const [parts, setParts] = useState<TParticipant[]>([]);
  const [loading, setLoading] = useState(true);
  const [connected, setConnected] = useState(false);
  const reloadTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  const reload = useCallback(async () => {
    try {
      const { data: g, error: e1 } = await supabase.from(gameTable).select("*").eq("id", gameId).maybeSingle();
      if (e1 && !g) { console.warn("[realtime] load error:", e1); return; }
      const { data: p, error: e2 } = await supabase.from(participantTable).select("*").eq("game_id", gameId).order("slot");
      if (e2 && !p) { console.warn("[realtime] parts error:", e2); }
      setGame(g as TGame);
      setParts((p as TParticipant[]) || []);
      setLoading(false);
      if ((g as any)?.status === "finished" && onFinished) onFinished();
    } catch (err) { console.error("[realtime] reload:", err); setLoading(false); }
  }, [gameTable, participantTable, gameId, onFinished]);

  const debouncedReload = useCallback(() => {
    if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
    reloadTimerRef.current = setTimeout(() => reload(), 500);
  }, [reload]);

  useEffect(() => {
    if (!enabled || !gameId) return;
    reload();
    const ch: any = supabase.channel(`rt-${gameTable}-${gameId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: gameTable, filter: `id=eq.${gameId}` }, (payload: any) => {
        if (payload.eventType === "DELETE") { debouncedReload(); return; }
        if (payload.new) { setGame(payload.new as TGame); if (payload.new.status === "finished" && onFinished) onFinished(); }
      })
      .on("postgres_changes", { event: "*", schema: "public", table: participantTable, filter: `game_id=eq.${gameId}` }, (payload: any) => {
        if (payload.eventType === "INSERT" && payload.new) { setParts(prev => prev.some(p => (p as any).id === payload.new.id) ? prev : [...prev, payload.new]); }
        else if (payload.eventType === "UPDATE" && payload.new) { setParts(prev => prev.map(p => (p as any).id === payload.new.id ? payload.new : p)); }
        else if (payload.eventType === "DELETE" && payload.old) { setParts(prev => prev.filter(p => (p as any).id !== payload.old.id)); }
        else { debouncedReload(); }
      });
    for (const extra of extraTables) {
      ch.on("postgres_changes", { event: extra.event || "*", schema: "public", table: extra.table, filter: extra.filter }, () => debouncedReload());
    }
    ch.subscribe((status: string) => {
      if (status === "SUBSCRIBED") setConnected(true);
      else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") { setConnected(false); setTimeout(() => reload(), 300); }
      else if (status === "CLOSED") setConnected(false);
    });
    return () => { supabase.removeChannel(ch); if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current); };
  }, [gameId, enabled, gameTable, participantTable]);

  return { game, parts, setGame, setParts, loading, connected, reload };
}
