import { AlertTriangle, CheckCircle2, Pause, Play, UserX, Vote } from "lucide-react";
import { useGamePause } from "@/hooks/use-game-pause";

type Props = {
  slug: string;
  gameId: string;
  game: any;
  isPlayer: boolean;
  myUserId?: string | null;
  /** Display name of the current local player (shown in overlay messages) */
  myName?: string;
  /**
   * Kept for backward compatibility with existing call sites. No longer used:
   * pausing is triggered exclusively by the AFK-warning vote mechanism, not
   * by turn time remaining, so there is no button left to portal.
   */
  remaining?: number;
  totalSeconds?: number;
  isMyTurn?: boolean;
  pauseButtonPortalTarget?: HTMLElement | null;
  /** Simplified pause mode (vs-bot): no timer, no auto-forfeit, just a Continue button. */
  simplePause?: boolean;
};

function fmt(secs: number): string {
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}

/**
 * Renders:
 * 1. An AFK warning banner when a player reaches the warning threshold
 *    (i.e. their absence counter hits max-1, e.g. 4/5 — configurable from
 *    admin settings). Visible to all active players except the AFK player.
 *    Shows vote progress + "Pause" vote button (one vote per player).
 *    This is the ONLY way to trigger a pause — there is no time-based
 *    pause button anymore; pausing is tied exclusively to the absence
 *    counter reaching its warning threshold.
 * 2. A full-screen overlay when the game is paused.
 */
export default function GamePauseControl({
  slug,
  gameId,
  game,
  isPlayer,
  myUserId,
  simplePause,
}: Props) {
  const {
    isPaused,
    pauseSecondsLeft,
    afkWarning,
    isAfkPause,
    isAfkPlayer,
    canRequestAfkPause,
    hasVoted,
    requestAfkPause,
    resumeGame,
  } = useGamePause({
    slug,
    gameId,
    game,
    isPlayer,
    myUserId,
  });

  // Compteurs de vote (disponibles via realtime après le premier vote)
  const votesCount  = afkWarning?.votes?.length ?? 0;
  const votesNeeded = afkWarning?.votes_needed ?? 0;
  const showVoteCount = votesNeeded > 0;

  // Texte du sous-titre du banner AFK
  function afkSubtitle(): string {
    if (afkWarning?.t1 !== undefined) {
      return `${afkWarning.t1}/${afkWarning.t1_max} timeouts sans lancer`;
    }
    if (afkWarning?.skips !== undefined) {
      return `${afkWarning.skips + 1}/${afkWarning.max} tours ratés`;
    }
    return "Seuil AFK atteint";
  }

  return (
    <>
      {/* ── AFK Warning Banner */}
      {afkWarning && !isPaused && isPlayer && myUserId !== afkWarning.uid && (
        <div
          className="fixed top-16 left-1/2 -translate-x-1/2 z-40 w-[calc(100%-2rem)] max-w-sm
                     bg-amber-50 dark:bg-amber-950/60 border border-amber-400/60
                     rounded-2xl px-4 py-3 shadow-xl flex items-start gap-3 animate-in
                     slide-in-from-top-4 fade-in duration-300"
        >
          <AlertTriangle className="w-5 h-5 text-amber-500 shrink-0 mt-0.5" />
          <div className="flex-1 min-w-0">
            <p className="text-sm font-semibold text-amber-800 dark:text-amber-200 truncate">
              Voulez-vous attendre le joueur {afkWarning.name} absent ?
            </p>
            <p className="text-xs text-amber-600 dark:text-amber-400">
              {afkSubtitle()}
            </p>

            {/* Barre de progression des votes */}
            {showVoteCount && (
              <div className="mt-1.5 flex items-center gap-2">
                <div className="flex gap-1">
                  {Array.from({ length: votesNeeded }).map((_, i) => (
                    <div
                      key={i}
                      className={`w-2 h-2 rounded-full transition-colors ${
                        i < votesCount
                          ? "bg-amber-500"
                          : "bg-amber-200 dark:bg-amber-800"
                      }`}
                    />
                  ))}
                </div>
                <span className="text-[10px] font-semibold text-amber-600 dark:text-amber-400">
                  {votesCount}/{votesNeeded} vote{votesNeeded > 1 ? "s" : ""}
                </span>
              </div>
            )}
          </div>

          {/* Bouton voter / déjà voté */}
          {canRequestAfkPause && (
            <button
              onClick={requestAfkPause}
              className="shrink-0 px-3 py-1.5 rounded-full bg-amber-500 hover:bg-amber-600
                         active:scale-95 text-white text-xs font-bold flex items-center gap-1.5
                         transition-all shadow-md shadow-amber-500/30"
            >
              <Vote className="w-3.5 h-3.5" />
              {votesNeeded <= 1 ? "Pause" : "Voter"}
            </button>
          )}
          {hasVoted && !canRequestAfkPause && (
            <div className="shrink-0 flex items-center gap-1 text-xs font-semibold text-amber-600 dark:text-amber-400">
              <CheckCircle2 className="w-4 h-4 text-emerald-500" />
              Voté
            </div>
          )}
        </div>
      )}

      {/* ── Simplified vs-bot pause overlay: no timer, just Continue */}
      {isPaused && simplePause && (
        <div className="fixed inset-0 z-50 bg-slate-900/85 backdrop-blur-sm flex items-center justify-center p-6">
          <div className="bg-card max-w-sm w-full rounded-3xl p-7 shadow-2xl text-center space-y-5">
            <div className="w-16 h-16 mx-auto rounded-full flex items-center justify-center bg-amber-100 dark:bg-amber-900/40">
              <Pause className="w-8 h-8 text-amber-600" />
            </div>
            <div className="text-xl font-extrabold">⏸ Partie en pause</div>
            <p className="text-sm text-muted-foreground">
              Reprenez la partie quand vous êtes prêt.
            </p>
            {isPlayer && (
              <button
                onClick={resumeGame}
                className="w-full py-3.5 rounded-full bg-emerald-500 hover:bg-emerald-600
                           active:scale-95 text-white font-bold flex items-center justify-center
                           gap-2 transition-all text-sm"
              >
                <Play className="w-4 h-4" />
                Continuer
              </button>
            )}
          </div>
        </div>
      )}

      {/* ── Full-screen pause overlay */}
      {isPaused && !simplePause && (
        <div className="fixed inset-0 z-50 bg-slate-900/85 backdrop-blur-sm flex items-center justify-center p-6">
          <div className="bg-card max-w-sm w-full rounded-3xl p-7 shadow-2xl text-center space-y-4">

            {/* Icon */}
            <div
              className={`w-16 h-16 mx-auto rounded-full flex items-center justify-center ${
                isAfkPause
                  ? "bg-orange-100 dark:bg-orange-900/40"
                  : "bg-amber-100 dark:bg-amber-900/40"
              }`}
            >
              {isAfkPause
                ? <UserX className="w-8 h-8 text-orange-500" />
                : <Pause  className="w-8 h-8 text-amber-600" />
              }
            </div>

            {/* Title */}
            <div className="text-xl font-extrabold">
              {isAfkPause ? "⏸ En attente d'un joueur" : "⏸ Partie en pause"}
            </div>

            {/* Context message */}
            {isAfkPause && !isAfkPlayer && (
              <p className="text-sm text-muted-foreground">
                {`En attente du retour de ${game?.afk_pause_name ?? "ce joueur"}. S'il ne revient pas à temps, il sera déclaré forfait.`}
              </p>
            )}
            {isAfkPause && isAfkPlayer && (
              <p className="text-sm text-muted-foreground">
                Vos coéquipiers vous attendent. Appuyez sur Reprendre pour continuer.
              </p>
            )}

            {/* Countdown */}
            <div className="space-y-1">
              <p className="text-xs text-muted-foreground">
                {isAfkPause ? "Forfait automatique dans" : "Reprise automatique dans"}
              </p>
              <span
                className={`text-4xl font-black font-mono tabular-nums ${
                  pauseSecondsLeft <= 30
                    ? "text-destructive animate-pulse"
                    : isAfkPause ? "text-orange-500" : "text-primary"
                }`}
              >
                {fmt(pauseSecondsLeft)}
              </span>
            </div>

            {/* AFK player: "Je suis là" button */}
            {isAfkPlayer && (
              <button
                onClick={resumeGame}
                className="w-full py-3.5 rounded-full bg-emerald-500 hover:bg-emerald-600
                           active:scale-95 text-white font-bold flex items-center justify-center
                           gap-2 transition-all text-sm"
              >
                <Play className="w-4 h-4" />
                Je suis là — Reprendre
              </button>
            )}

            {/* Other active players: "Reprendre maintenant" */}
            {!isAfkPlayer && isPlayer && (
              <button
                onClick={resumeGame}
                className="w-full py-3.5 rounded-full bg-emerald-500 hover:bg-emerald-600
                           active:scale-95 text-white font-bold flex items-center justify-center
                           gap-2 transition-all text-sm"
              >
                <Play className="w-4 h-4" />
                Reprendre maintenant
              </button>
            )}

            {/* Spectator */}
            {!isPlayer && (
              <p className="text-xs text-muted-foreground italic">
                Mode spectateur — la reprise est réservée aux joueurs
              </p>
            )}
          </div>
        </div>
      )}
    </>
  );
}
