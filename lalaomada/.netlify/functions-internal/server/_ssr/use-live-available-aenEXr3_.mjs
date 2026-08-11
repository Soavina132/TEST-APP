import { r as reactExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
function useLiveAvailable() {
  const [count, setCount] = reactExports.useState(0);
  reactExports.useEffect(() => {
    let cancelled = false;
    let channel = null;
    async function load() {
      const { data: s } = await supabase.from("app_settings").select("live_enabled").eq("id", 1).maybeSingle();
      if (s && s.live_enabled === false) {
        if (!cancelled) setCount(0);
        return;
      }
      const { data } = await supabase.rpc("list_live_games");
      if (!cancelled) setCount((data || []).filter((g) => g.game_type !== "rami" && g.game_type !== "fanorona").length);
    }
    load();
    try {
      channel = supabase.channel("live-available").on("postgres_changes", { event: "*", schema: "public", table: "ludo_games" }, load).on("postgres_changes", { event: "*", schema: "public", table: "domino_games" }, load).on("postgres_changes", { event: "*", schema: "public", table: "chess_games" }, load).on("postgres_changes", { event: "*", schema: "public", table: "fanorona_games" }, load).on("postgres_changes", { event: "*", schema: "public", table: "rami_games" }, load).on("postgres_changes", { event: "*", schema: "public", table: "poker_games" }, load).on("postgres_changes", { event: "*", schema: "public", table: "game_spectators" }, load).subscribe();
    } catch (error) {
      console.warn("Live realtime subscription unavailable; using polling fallback.", error);
    }
    const t = setInterval(load, 3e4);
    return () => {
      cancelled = true;
      if (channel) supabase.removeChannel(channel);
      clearInterval(t);
    };
  }, []);
  return count;
}
export {
  useLiveAvailable as u
};
