import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";

/**
 * Nombre de parties (waiting/ongoing) dans lesquelles l'utilisateur est engagé.
 * Sert à afficher un badge sur le bouton "Mes parties".
 */
export function useMyOngoingCount(): number {
  const { user } = useAuth();
  const [count, setCount] = useState(0);

  useEffect(() => {
    if (!user) { setCount(0); return; }
    let cancelled = false;

    const load = async () => {
      const { data } = await supabase.rpc("my_ongoing_all" as any);
      if (cancelled) return;
      const arr = Array.isArray(data) ? (data as any[]) : [];
      // Ne compte que les parties où l'utilisateur est actif (pas éliminé)
      setCount(arr.filter(g => !g.eliminated).length);
    };
    load();

    const tables = [
      "ludo_games", "domino_games", "fanorona_games",
      "chess_games", "rami_games", "poker_games",
    ];
    const ch = supabase.channel(`my-ongoing-${user.id}`);
    tables.forEach(t => {
      ch.on("postgres_changes" as any, { event: "*", schema: "public", table: t }, load);
    });
    ch.subscribe();

    const timer = setInterval(load, 45000);

    return () => {
      cancelled = true;
      supabase.removeChannel(ch);
      clearInterval(timer);
    };
  }, [user?.id]);

  return count;
}
