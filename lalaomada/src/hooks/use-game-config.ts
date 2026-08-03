import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type GameConfig = {
  turn_timer_seconds: number;
  max_turn_skips: number;
};

const cache: Record<string, GameConfig> = {};

export function useGameConfig(slug: string): GameConfig {
  const [cfg, setCfg] = useState<GameConfig>(
    cache[slug] || { turn_timer_seconds: 30, max_turn_skips: 5 }
  );
  useEffect(() => {
    let cancelled = false;
    (async () => {
      if (cache[slug]) { setCfg(cache[slug]); return; }
      const { data } = await supabase
        .from("game_configs" as any)
        .select("turn_timer_seconds,max_turn_skips")
        .eq("slug", slug)
        .maybeSingle();
      if (data && !cancelled) {
        cache[slug] = data as unknown as GameConfig;
        setCfg(data as unknown as GameConfig);
      }
    })();
    return () => { cancelled = true; };
  }, [slug]);
  return cfg;
}
