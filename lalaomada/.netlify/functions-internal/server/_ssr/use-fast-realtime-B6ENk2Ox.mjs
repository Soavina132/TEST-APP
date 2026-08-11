import { r as reactExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
const HEARTBEAT_INTERVAL_MS = 1e4;
function useFastRealtime({
  gameTable,
  participantTable,
  gameId,
  enabled = true,
  extraTables = [],
  onFinished
}) {
  const [game, setGame] = reactExports.useState(null);
  const [parts, setParts] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(true);
  const [connected, setConnected] = reactExports.useState(false);
  const reloadTimerRef = reactExports.useRef(null);
  const heartbeatRef = reactExports.useRef(null);
  const onFinishedRef = reactExports.useRef(onFinished);
  reactExports.useEffect(() => {
    onFinishedRef.current = onFinished;
  }, [onFinished]);
  const reload = reactExports.useCallback(async () => {
    try {
      const { data: g, error: e1 } = await supabase.from(gameTable).select("*").eq("id", gameId).maybeSingle();
      if (e1 && !g) {
        console.warn("[realtime] load error:", e1);
        setLoading(false);
        return;
      }
      const { data: p, error: e2 } = await supabase.from(participantTable).select("*").eq("game_id", gameId).order("slot");
      if (e2 && !p) {
        console.warn("[realtime] parts error:", e2);
      }
      setGame(g);
      setParts(p || []);
      setLoading(false);
      if (g?.status === "finished" && onFinishedRef.current) onFinishedRef.current();
    } catch (err) {
      console.error("[realtime] reload:", err);
      setLoading(false);
    }
  }, [gameTable, participantTable, gameId]);
  const debouncedReload = reactExports.useCallback(() => {
    if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
    reloadTimerRef.current = setTimeout(() => reload(), 200);
  }, [reload]);
  reactExports.useEffect(() => {
    if (!enabled || !gameId) return;
    reload();
    const ch = supabase.channel(`rt-${gameTable}-${gameId}`).on("postgres_changes", { event: "*", schema: "public", table: gameTable, filter: `id=eq.${gameId}` }, (payload) => {
      if (payload.eventType === "DELETE") {
        debouncedReload();
        return;
      }
      if (payload.new) {
        setGame(payload.new);
        if (payload.new.status === "finished" && onFinishedRef.current) onFinishedRef.current();
      }
    }).on("postgres_changes", { event: "*", schema: "public", table: participantTable, filter: `game_id=eq.${gameId}` }, (payload) => {
      if (payload.eventType === "INSERT" && payload.new) {
        setParts((prev) => prev.some((p) => p.id === payload.new.id) ? prev : [...prev, payload.new]);
      } else if (payload.eventType === "UPDATE" && payload.new) {
        setParts((prev) => prev.map((p) => p.id === payload.new.id ? payload.new : p));
      } else if (payload.eventType === "DELETE" && payload.old) {
        setParts((prev) => prev.filter((p) => p.id !== payload.old.id));
      } else {
        debouncedReload();
      }
    });
    for (const extra of extraTables) {
      ch.on("postgres_changes", { event: extra.event || "*", schema: "public", table: extra.table, filter: extra.filter }, () => debouncedReload());
    }
    ch.subscribe((status) => {
      if (status === "SUBSCRIBED") {
        setConnected(true);
        if (heartbeatRef.current) clearInterval(heartbeatRef.current);
        heartbeatRef.current = setInterval(() => reload(), HEARTBEAT_INTERVAL_MS);
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        setConnected(false);
        if (heartbeatRef.current) {
          clearInterval(heartbeatRef.current);
          heartbeatRef.current = null;
        }
        setTimeout(() => reload(), 300);
      } else if (status === "CLOSED") {
        setConnected(false);
        if (heartbeatRef.current) {
          clearInterval(heartbeatRef.current);
          heartbeatRef.current = null;
        }
      }
    });
    return () => {
      supabase.removeChannel(ch);
      if (reloadTimerRef.current) clearTimeout(reloadTimerRef.current);
      if (heartbeatRef.current) {
        clearInterval(heartbeatRef.current);
        heartbeatRef.current = null;
      }
    };
  }, [gameId, enabled, gameTable, participantTable, reload, debouncedReload]);
  return { game, parts, setGame, setParts, loading, connected, reload };
}
export {
  useFastRealtime as u
};
