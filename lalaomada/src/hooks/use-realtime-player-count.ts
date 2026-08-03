import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

/**
 * Subscribes to a single game row via Supabase Realtime and returns a live
 * `players_count` value.  Each game card mounts its own channel so the counter
 * updates immediately (without reloading the whole list) and can animate.
 *
 * @param gameId       - UUID of the game row
 * @param table        - e.g. "ludo_games", "chess_games"
 * @param initialCount - snapshot count from the last list-fetch (avoids flash)
 * @returns { liveCount, flash } — flash is true for ~600 ms after a change
 */
export function useRealtimePlayerCount(
  gameId: string,
  table: string,
  initialCount: number,
) {
  const [liveCount, setLiveCount] = useState(initialCount);
  const [flash, setFlash]         = useState(false);
  const prevRef                   = useRef(initialCount);

  // Keep in sync when the parent list refreshes (e.g. a game is re-fetched)
  useEffect(() => {
    if (initialCount !== prevRef.current) {
      prevRef.current = initialCount;
      setLiveCount(initialCount);
    }
  }, [initialCount]);

  useEffect(() => {
    const channel = supabase
      .channel(`player-count-${table}-${gameId}`)
      .on(
        "postgres_changes",
        {
          event:  "UPDATE",
          schema: "public",
          table,
          filter: `id=eq.${gameId}`,
        },
        (payload) => {
          const newCount = (payload.new as Record<string, unknown>)
            ?.players_count as number | undefined;
          if (newCount !== undefined && newCount !== prevRef.current) {
            prevRef.current = newCount;
            setLiveCount(newCount);
            setFlash(true);
            const t = setTimeout(() => setFlash(false), 600);
            return () => clearTimeout(t);
          }
        },
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [gameId, table]);

  return { liveCount, flash };
}
