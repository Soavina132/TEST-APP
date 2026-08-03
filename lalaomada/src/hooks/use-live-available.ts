import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export function useLiveAvailable(): number {
  const [count, setCount] = useState(0);

  useEffect(() => {
    let cancelled = false;
    let channel: ReturnType<typeof supabase.channel> | null = null;

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

    try {
      channel = supabase
        .channel(`live-available-${Date.now()}-${Math.random().toString(36).slice(2)}`)
        .on("postgres_changes", { event: "*", schema: "public", table: "ludo_games" }, load)
        .on("postgres_changes", { event: "*", schema: "public", table: "domino_games" }, load)
        .on("postgres_changes", { event: "*", schema: "public", table: "chess_games" }, load)
        .on("postgres_changes", { event: "*", schema: "public", table: "fanorona_games" }, load)
        .on("postgres_changes", { event: "*", schema: "public", table: "rami_games" }, load)
        .on("postgres_changes", { event: "*", schema: "public", table: "game_spectators" }, load)
        .subscribe();
    } catch (error) {
      console.warn("Live realtime subscription unavailable; using polling fallback.", error);
    }

    const t = setInterval(load, 15000);

    return () => {
      cancelled = true;
      if (channel) supabase.removeChannel(channel);
      clearInterval(t);
    };
  }, []);

  return count;
}
