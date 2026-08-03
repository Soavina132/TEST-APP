import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export function useLiveAvailable(): number {
  const [count, setCount] = useState(0);

  useEffect(() => {
    let cancelled = false;

    async function load() {
      const { data: s } = await supabase.from("app_settings").select("live_enabled").eq("id", 1).maybeSingle();
      if (s && (s as any).live_enabled === false) {
        if (!cancelled) setCount(0);
        return;
      }
      const { data } = await supabase.rpc("list_live_games" as any);
      if (!cancelled) setCount(((data as any[]) || []).filter((g: any) => g.game_type !== "rami" && g.game_type !== "fanorona").length);
    }

    load();

    // Polling only (15s) — no realtime channels
    const t = setInterval(load, 15000);

    return () => {
      cancelled = true;
      clearInterval(t);
    };
  }, []);

  return count;
}