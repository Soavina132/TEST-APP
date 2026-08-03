import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { serverNow } from "@/lib/server-time";

export type GlobalTimerState = {
  enabled: boolean;
  totalMinutes: number;
  remainingMs: number | null; // null when no deadline
  remainingLabel: string; // "MM:SS" or ""
  expired: boolean;
};

/**
 * Reads the global game timer config (chess_global_* / fanorona_global_*)
 * from app_settings, ticks down based on the row's `game_deadline`,
 * and calls the matching `*_check_global_timeout` RPC when it hits zero.
 */
export function useGlobalGameTimer(opts: {
  game: "chess" | "fanorona";
  gameId: string;
  status: string | undefined;
  deadline: string | null | undefined;
}): GlobalTimerState {
  const { game, gameId, status, deadline } = opts;
  const [enabled, setEnabled] = useState(false);
  const [mins, setMins] = useState(10);
  const [now, setNow] = useState(() => serverNow());

  useEffect(() => {
    let cancelled = false;
    (async () => {
      const { data } = await supabase
        .from("app_settings" as any)
        .select(
          game === "chess"
            ? "chess_global_timer_enabled,chess_global_timer_minutes"
            : "fanorona_global_timer_enabled,fanorona_global_timer_minutes",
        )
        .eq("id", 1)
        .maybeSingle();
      if (cancelled || !data) return;
      const d: any = data;
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

  useEffect(() => {
    if (status !== "playing" || !deadline) return;
    const t = setInterval(() => setNow(serverNow()), 500);
    return () => clearInterval(t);
  }, [status, deadline]);

  let remainingMs: number | null = null;
  let expired = false;
  if (deadline) {
    remainingMs = Math.max(0, new Date(deadline).getTime() - now);
    expired = remainingMs === 0;
  }

  useEffect(() => {
    if (!expired || status !== "playing") return;
    supabase.rpc(
      (game === "chess"
        ? "chess_check_global_timeout"
        : "fanorona_check_global_timeout") as any,
      { _game_id: gameId } as any,
    );
  }, [expired, status, game, gameId]);

  let label = "";
  if (remainingMs != null) {
    const totalSec = Math.ceil(remainingMs / 1000);
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    label = `${m}:${String(s).padStart(2, "0")}`;
  }

  return { enabled, totalMinutes: mins, remainingMs, remainingLabel: label, expired };
}
