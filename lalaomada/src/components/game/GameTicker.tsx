import { useEffect, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";

/**
 * Global ticker: calls `tick_all_games` every 3s to check for timeouts
 * and advance bot turns. No pg_cron on Supabase, so we use a client-side interval.
 * Only runs when the tab is visible.
 */
export function GameTicker() {
  const tickerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  useEffect(() => {
    const tick = async () => {
      if (document.hidden) return;
      try {
        await supabase.rpc("tick_all_games" as any);
      } catch {}
    };
    tick();
    tickerRef.current = setInterval(tick, 3000);
    return () => { if (tickerRef.current) clearInterval(tickerRef.current); };
  }, []);
  return null;
}
