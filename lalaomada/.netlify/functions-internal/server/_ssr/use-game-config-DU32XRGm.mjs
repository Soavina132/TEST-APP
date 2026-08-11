import { r as reactExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
const cache = {};
function useGameConfig(slug) {
  const [cfg, setCfg] = reactExports.useState(
    cache[slug] || { turn_timer_seconds: 90, max_turn_skips: 5 }
  );
  reactExports.useEffect(() => {
    let cancelled = false;
    (async () => {
      if (cache[slug]) {
        setCfg(cache[slug]);
        return;
      }
      const { data } = await supabase.from("game_configs").select("turn_timer_seconds,max_turn_skips").eq("slug", slug).maybeSingle();
      if (data && !cancelled) {
        cache[slug] = data;
        setCfg(data);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, [slug]);
  return cfg;
}
export {
  useGameConfig as u
};
