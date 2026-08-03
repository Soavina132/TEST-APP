import { Hourglass } from "lucide-react";

type Props = {
  isMyTurn: boolean;
  opponentName?: string;
  globalTimerLabel?: string; // "MM:SS"
  globalTimerEnabled?: boolean;
  /** Optional slot rendered right next to the banner text (e.g. an inline pause button). */
  endSlot?: React.ReactNode;
};

/**
 * Big, unmistakable "À toi de jouer" / "Tour de X" banner shown at the top of
 * the active board for chess, fanorona, domino. Optionally shows the global
 * game-level timer (configured by admin via app_settings).
 */
export default function TurnBanner({
  isMyTurn,
  opponentName,
  globalTimerLabel,
  globalTimerEnabled,
  endSlot,
}: Props) {
  return (
    <div
      className={`flex items-center justify-between gap-3 px-4 py-2.5 rounded-2xl mb-3 font-bold text-sm shadow-sm ${
        isMyTurn
          ? "bg-emerald-500/15 ring-2 ring-emerald-500 text-emerald-700 dark:text-emerald-300 animate-pulse"
          : "bg-secondary text-muted-foreground"
      }`}
    >
      <span className="truncate flex-1">
        {isMyTurn ? "🎯 C'est ton tour !" : `⏳ Tour de ${opponentName || "l'adversaire"}`}
      </span>
      <div className="flex items-center gap-2 shrink-0">
        {endSlot}
        {globalTimerEnabled && globalTimerLabel ? (
          <span className="flex items-center gap-1 font-mono tabular-nums text-xs px-2 py-1 rounded-lg bg-background/60">
            <Hourglass className="w-3 h-3" />
            {globalTimerLabel}
          </span>
        ) : null}
      </div>
    </div>
  );
}
