import { r as reactExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
function useGlobalGameTimer(opts) {
  const { game, gameId, status, deadline } = opts;
  const [enabled, setEnabled] = reactExports.useState(false);
  const [mins, setMins] = reactExports.useState(10);
  const [now, setNow] = reactExports.useState(() => serverNow());
  reactExports.useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase.from("app_settings").select(
        game === "chess" ? "chess_global_timer_enabled,chess_global_timer_minutes" : "fanorona_global_timer_enabled,fanorona_global_timer_minutes"
      ).eq("id", 1).maybeSingle();
      if (cancelled || !data) return;
      const d = data;
      if (game === "chess") {
        setEnabled(!!d.chess_global_timer_enabled);
        setMins(Number(d.chess_global_timer_minutes) || 10);
      } else {
        setEnabled(!!d.fanorona_global_timer_enabled);
        setMins(Number(d.fanorona_global_timer_minutes) || 10);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [game]);
  reactExports.useEffect(() => {
    if (status !== "playing" || !deadline) return;
    const t = setInterval(() => setNow(serverNow()), 500);
    return () => clearInterval(t);
  }, [status, deadline]);
  let remainingMs = null;
  let expired = false;
  if (deadline) {
    remainingMs = Math.max(0, new Date(deadline).getTime() - now);
    expired = remainingMs === 0;
  }
  reactExports.useEffect(() => {
    if (!expired || status !== "playing") return;
    supabase.rpc(
      game === "chess" ? "chess_check_global_timeout" : "fanorona_check_global_timeout",
      { _game_id: gameId }
    );
  }, [expired, status, game, gameId]);
  let label = "";
  if (remainingMs != null) {
    const totalSec = Math.ceil(remainingMs / 1e3);
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    label = `${m}:${String(s).padStart(2, "0")}`;
  }
  return { enabled, totalMinutes: mins, remainingMs, remainingLabel: label, expired };
}
export {
  useGlobalGameTimer as u
};
