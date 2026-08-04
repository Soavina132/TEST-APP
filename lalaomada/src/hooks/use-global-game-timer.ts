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

type GameSlug = "chess" | "fanorona" | "domino" | "rami" | "poker";

const CONFIG_COLUMNS: Record<GameSlug, { enabled: string; minutes: string }> = {
  chess:    { enabled: "chess_global_timer_enabled",    minutes: "chess_global_timer_minutes" },
  fanorona: { enabled: "fanorona_global_timer_enabled", minutes: "fanorona_global_timer_minutes" },
  domino:   { enabled: "domino_global_timer_enabled",   minutes: "domino_global_timer_minutes" },
  rami:     { enabled: "rami_global_timer_enabled",      minutes: "rami_global_timer_minutes" },
  poker:    { enabled: "poker_global_timer_enabled",    minutes: "poker_global_timer_minutes" },
};

const TIMEOUT_RPC: Record<GameSlug, string> = {
  chess:    "chess_check_global_timeout",
  fanorona: "fanorona_check_global_timeout",
  domino:   "domino_check_global_timeout",
  rami:     "rami_check_global_timeout",
  poker:    "poker_check_global_timeout",
};

/**
 * Reads the global game timer config from app_settings,
 * ticks down based on the row's `game_deadline`,
 * and calls the matching `*_check_global_timeout` RPC when it hits zero.
 */
export function useGlobalGameTimer(opts: {
  game: GameSlug;
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
      const cols = CONFIG_COLUMNS[game];
      const { data } = await supabase
        .from("app_settings" as any)
        .select(`${cols.enabled}, ${cols.minutes}`)
        .eq("id", 1)
        .maybeSingle();
      if (cancelled || !data) return;
      const d: any = data;
      setEnabled(!!d[cols.enabled]);
      setMins(Number(d[cols.minutes]) || 10);
    })();
    return () => { cancelled = true; };
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
    supabase.rpc(TIMEOUT_RPC[game] as any, { _game_id: gameId } as any);
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
