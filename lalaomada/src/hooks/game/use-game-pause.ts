import { useCallback, useEffect, useRef, useState } from "react";
import { serverNow } from "@/lib/server-time";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

type UseGamePauseOpts = {
  slug: string;
  gameId: string;
  game: any;
  /** Whether the local user is an active participant (not spectator) */
  isPlayer: boolean;
  /** The local user's id — needed for AFK pause logic */
  myUserId?: string | null;
};

export type AfkWarning = {
  uid: string;
  name: string;
  slot?: number;
  skips?: number;
  max?: number;
  t1?: number;
  t1_max?: number;
  /** UIDs des joueurs ayant voté pour la pause */
  votes?: string[];
  /** Nombre de votes requis pour déclencher la pause */
  votes_needed?: number;
  ts: number;
};

type UseGamePauseResult = {
  isPaused: boolean;
  /** Seconds until the game auto-resumes / auto-forfeits */
  pauseSecondsLeft: number;
  /** AFK warning data — non-null when a player has reached the warning threshold */
  afkWarning: AfkWarning | null;
  /** True when this pause was triggered by the AFK mechanism */
  isAfkPause: boolean;
  /** uid of the player being waited for (AFK pause only) */
  afkPauseFor: string | null;
  /** True when the local player is the one being waited for */
  isAfkPlayer: boolean;
  /** True when the local player can vote for an AFK pause (hasn't voted yet) */
  canRequestAfkPause: boolean;
  /** True when the local player has already cast their AFK-pause vote */
  hasVoted: boolean;
  requestAfkPause: () => Promise<void>;
  resumeGame: () => Promise<void>;
};

export function useGamePause({
  slug,
  gameId,
  game,
  isPlayer,
  myUserId,
}: UseGamePauseOpts): UseGamePauseResult {
  const isPaused: boolean       = !!game?.paused;
  const pauseDeadline: string | null = game?.pause_deadline ?? null;
  const afkPauseFor: string | null   = game?.afk_pause_for  ?? null;
  const isAfkPause: boolean          = !!afkPauseFor;
  const isAfkPlayer: boolean         = !!myUserId && myUserId === afkPauseFor;

  // Parse afk_warning from game object
  const afkWarning: AfkWarning | null = game?.afk_warning ?? null;

  // Whether the local player has already voted
  const hasVoted: boolean =
    !!myUserId &&
    Array.isArray(afkWarning?.votes) &&
    afkWarning.votes.includes(myUserId);

  // ── Toast when a new AFK warning appears (not our own afk)
  const lastWarnKeyRef = useRef<string>("");
  useEffect(() => {
    if (!afkWarning) return;
    const key = `${afkWarning.uid}:${afkWarning.ts}`;
    if (key === lastWarnKeyRef.current) return;
    if (myUserId && afkWarning.uid === myUserId) return;
    lastWarnKeyRef.current = key;
    toast.warning(
      `⚠️ ${afkWarning.name} est inactif — votez pour mettre la partie en pause`,
      { duration: 5000 }
    );
  }, [afkWarning, myUserId]);

  // ── Toast when AFK pause is triggered by someone else
  const wasPausedRef = useRef(isPaused);
  useEffect(() => {
    if (!isPaused || !isAfkPause) { wasPausedRef.current = isPaused; return; }
    if (wasPausedRef.current) return;
    wasPausedRef.current = true;
    if (!isAfkPlayer) {
      toast.info("⏸ Partie en pause — en attente du joueur inactif");
    }
  }, [isPaused, isAfkPause, isAfkPlayer]);

  useEffect(() => {
    if (!isPaused) wasPausedRef.current = false;
  }, [isPaused]);

  // ── Countdown to auto-resume / auto-forfeit
  const [pauseSecondsLeft, setPauseSecondsLeft] = useState(180);
  useEffect(() => {
    if (!isPaused || !pauseDeadline) { setPauseSecondsLeft(180); return; }
    const tick = () => {
      const ms = new Date(pauseDeadline).getTime() - serverNow();
      setPauseSecondsLeft(Math.max(0, Math.ceil(ms / 1000)));
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [isPaused, pauseDeadline]);

  // ── AFK pause vote: visible to every active player except the AFK player
  //    and only when they haven't voted yet
  const canRequestAfkPause =
    isPlayer &&
    !isPaused &&
    !!afkWarning &&
    game?.status === "playing" &&
    !!myUserId &&
    myUserId !== afkWarning?.uid &&
    !hasVoted;

  // ── Actions
  const requestAfkPause = useCallback(async () => {
    const { data, error } = await supabase.rpc("game_request_afk_pause" as any, {
      _slug: slug,
      _game_id: gameId,
    } as any);
    if (error) {
      toast.error(error.message || "Impossible de voter pour la pause");
      return;
    }
    const result = data as { status: string; votes?: number; votes_needed?: number } | null;
    if (!result) return;
    if (result.status === "already_voted") {
      toast.info("Vous avez déjà voté pour cette pause");
    } else if (result.status === "voted") {
      const v = result.votes ?? 1;
      const n = result.votes_needed ?? 1;
      if (v < n) {
        toast.success(`Vote enregistré (${v}/${n}) — en attente des autres joueurs`);
      }
    } else if (result.status === "paused") {
      toast.success("Partie en pause — 3 minutes pour le retour du joueur");
    }
  }, [slug, gameId]);

  const resumeGame = useCallback(async () => {
    const { error } = await supabase.rpc("game_resume" as any, {
      _slug: slug,
      _game_id: gameId,
    } as any);
    if (error) toast.error(error.message || "Impossible de reprendre");
    else if (isAfkPlayer) toast.success("Bienvenue ! La partie reprend.");
  }, [slug, gameId, isAfkPlayer]);

  return {
    isPaused,
    pauseSecondsLeft,
    afkWarning,
    isAfkPause,
    afkPauseFor,
    isAfkPlayer,
    canRequestAfkPause,
    hasVoted,
    requestAfkPause,
    resumeGame,
  };
}
