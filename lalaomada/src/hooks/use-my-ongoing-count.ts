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

    // Polling only (20s) — no realtime channel
    const timer = setInterval(load, 20000);

    return () => {
      cancelled = true;
      clearInterval(timer);
    };
  }, [user?.id]);

  return count;
}