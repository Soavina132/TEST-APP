import { useNavigate } from "@tanstack/react-router";
import { Trophy, RotateCw, LogOut, Crown, Sparkles } from "lucide-react";
import { useEffect, useState } from "react";
import confetti from "canvas-confetti";
import { useConfirm } from "@/components/ConfirmDialog";

export type GameSlug = "ludo" | "domino" | "fanorona" | "chess" | "rami" | "poker" | "petanque";

type Participant = { user_id: string; display_name: string; slot?: number };

export default function GameEndScreen({
  slug,
  meUserId,
  winnerId,
  participants,
  stake,
  pot,
  commissionPct = 10,
  extra,
  onReplay,
}: {
  slug: GameSlug;
  meUserId?: string;
  winnerId?: string | null;
  participants: Participant[];
  stake: number;
  pot: number;
  commissionPct?: number;
  extra?: React.ReactNode;
  onReplay?: () => void | Promise<void>;
}) {
  const [busy, setBusy] = useState<null | "replay" | "quit">(null);
  const confirm = useConfirm();
  const navigate = useNavigate();
  const winner = participants.find((p) => p.user_id === winnerId);
  const iWon = !!meUserId && winnerId === meUserId;
  const isDraw = !winnerId;
  const payout = Math.round((pot * (100 - commissionPct)) / 100);

  const handleQuit = async () => {
    if (busy) return;
    setBusy("quit");
    try {
      await navigate({ to: "/jeux" });
    } finally {
      setBusy(null);
    }
  };

  const handleReplay = async () => {
    if (busy) return;
    if (onReplay) {
      const ok = await confirm({
        title: "Rejouer une partie ?",
        description:
          stake > 0 ? (
            <>
              Une nouvelle partie sera créée avec les mêmes paramètres. Mise :{" "}
              <b>{Number(stake).toLocaleString("fr-FR")} Ar</b>.
            </>
          ) : (
            "Une nouvelle partie sera créée avec les mêmes paramètres."
          ),
        confirmLabel: "Rejouer",
      });
      if (!ok) return;
      setBusy("replay");
      try {
        await onReplay();
      } finally {
        setBusy(null);
      }
    } else {
      setBusy("replay");
      try {
        await navigate({ to: "/jeux/nouveau/$slug", params: { slug } });
      } finally {
        setBusy(null);
      }
    }
  };

  useEffect(() => {
    if (!iWon) return;
    const colors = ["#f59e0b", "#fbbf24", "#f97316", "#ef4444", "#10b981", "#3b82f6"];
    const fire = (opts: confetti.Options) =>
      confetti({ zIndex: 200, disableForReducedMotion: true, colors, ...opts });
    fire({ particleCount: 90, spread: 70, startVelocity: 55, origin: { y: 0.6 } });
    const t1 = setTimeout(() => {
      fire({ particleCount: 60, angle: 60, spread: 55, origin: { x: 0, y: 0.7 } });
      fire({ particleCount: 60, angle: 120, spread: 55, origin: { x: 1, y: 0.7 } });
    }, 250);
    const t2 = setTimeout(() => {
      fire({ particleCount: 120, spread: 100, startVelocity: 45, origin: { y: 0.5 }, scalar: 1.1 });
    }, 600);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [iWon]);

  const title = iWon ? "Victoire !" : isDraw ? "Match nul" : "Partie terminée";
  const emoji = iWon ? "🏆" : isDraw ? "🤝" : "🎯";

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-[90] flex items-center justify-center p-4 animate-in fade-in duration-300"
      style={{
        background:
          "radial-gradient(ellipse at center, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.85) 100%)",
        backdropFilter: "blur(10px)",
        WebkitBackdropFilter: "blur(10px)",
      }}
    >
      <div
        className={`relative w-full max-w-md rounded-[28px] overflow-hidden shadow-2xl ${
          iWon
            ? "animate-in zoom-in-95 duration-500"
            : "animate-in fade-in slide-in-from-bottom-4 duration-500"
        }`}
      >
        {/* Glow border */}
        {iWon && (
          <div
            aria-hidden
            className="pointer-events-none absolute -inset-1 rounded-[32px] opacity-70 blur-xl"
            style={{
              background:
                "conic-gradient(from 0deg, #fbbf24, #f97316, #ef4444, #f59e0b, #fbbf24)",
            }}
          />
        )}

        <div className="relative rounded-[28px] bg-card">
          {/* Header banner */}
          <div
            className="relative px-6 pt-8 pb-6 text-center overflow-hidden"
            style={{
              background: iWon
                ? "linear-gradient(135deg, rgba(251,191,36,0.18), rgba(249,115,22,0.12) 60%, transparent)"
                : isDraw
                ? "linear-gradient(135deg, rgba(59,130,246,0.12), transparent)"
                : "linear-gradient(135deg, rgba(148,163,184,0.14), transparent)",
            }}
          >
            {iWon && (
              <>
                <Sparkles className="absolute top-3 left-4 w-4 h-4 text-amber-400/70 animate-pulse" />
                <Sparkles className="absolute top-6 right-6 w-3 h-3 text-amber-300/70 animate-pulse" />
                <Sparkles className="absolute bottom-2 left-8 w-3 h-3 text-amber-400/60 animate-pulse" />
              </>
            )}
            <div
              className={`mx-auto mb-3 w-20 h-20 rounded-full flex items-center justify-center text-5xl shadow-lg ${
                iWon ? "animate-bounce" : ""
              }`}
              style={{
                background: iWon
                  ? "linear-gradient(135deg, #fde68a, #f59e0b)"
                  : isDraw
                  ? "linear-gradient(135deg, #dbeafe, #93c5fd)"
                  : "linear-gradient(135deg, hsl(var(--secondary)), hsl(var(--muted)))",
              }}
            >
              {emoji}
            </div>
            <h2
              className={`text-2xl font-extrabold tracking-tight ${
                iWon
                  ? "bg-gradient-to-r from-amber-500 via-orange-500 to-amber-600 bg-clip-text text-transparent"
                  : ""
              }`}
            >
              {title}
            </h2>
            {winner && !iWon && (
              <div className="mt-1 text-sm text-muted-foreground flex items-center justify-center gap-1.5">
                <Crown className="w-3.5 h-3.5 text-amber-500" />
                <b className="text-foreground">{winner.display_name}</b>
              </div>
            )}
          </div>

          <div className="px-6 pb-6 space-y-4 -mt-2">
            {/* Money card */}
            <div
              className="rounded-2xl p-4 flex items-center justify-between shadow-sm"
              style={{
                background: iWon
                  ? "linear-gradient(135deg, rgba(16,185,129,0.10), rgba(16,185,129,0.02))"
                  : "hsl(var(--secondary))",
                border: iWon
                  ? "1px solid rgba(16,185,129,0.35)"
                  : "1px solid hsl(var(--border))",
              }}
            >
              <div>
                <div className="text-[10px] uppercase tracking-widest text-muted-foreground font-bold">
                  Mise
                </div>
                <div className="text-base font-bold mt-0.5">
                  {Number(stake).toLocaleString("fr-FR")} Ar
                </div>
              </div>
              <div className="h-10 w-px bg-border/60" />
              <div className="text-right">
                <div className="text-[10px] uppercase tracking-widest text-muted-foreground font-bold">
                  {iWon ? "Vous gagnez" : "Au gagnant"}
                </div>
                <div
                  className={`text-lg font-extrabold mt-0.5 ${
                    iWon ? "text-emerald-600" : ""
                  }`}
                >
                  {payout.toLocaleString("fr-FR")} Ar
                </div>
              </div>
            </div>

            {participants.length > 0 && (
              <div className="rounded-2xl border border-border/60 divide-y divide-border/40 overflow-hidden">
                {participants.map((p) => {
                  const isWin = p.user_id === winnerId;
                  const isMe = p.user_id === meUserId;
                  return (
                    <div
                      key={p.user_id}
                      className={`flex items-center justify-between px-3 py-2.5 text-sm ${
                        isWin ? "bg-amber-500/5" : ""
                      }`}
                    >
                      <div className="flex items-center gap-2 min-w-0">
                        <div
                          className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${
                            isWin
                              ? "bg-gradient-to-br from-amber-400 to-orange-500 text-white"
                              : "bg-secondary text-muted-foreground"
                          }`}
                        >
                          {p.display_name?.[0]?.toUpperCase() ?? "?"}
                        </div>
                        <span className="truncate font-medium">
                          {p.display_name}
                          {isMe && (
                            <span className="ml-1 text-xs text-muted-foreground">(vous)</span>
                          )}
                        </span>
                      </div>
                      {isWin && (
                        <div className="flex items-center gap-1 text-xs font-bold text-amber-600 shrink-0">
                          <Trophy className="w-3.5 h-3.5" />
                          Gagnant
                        </div>
                      )}
                    </div>
                  );
                })}
              </div>
            )}

            {extra}

            <div className="grid grid-cols-2 gap-2 pt-1">
              <button
                type="button"
                onClick={handleQuit}
                disabled={!!busy}
                className="py-3 rounded-full bg-secondary hover:bg-secondary/80 font-bold flex items-center justify-center gap-1.5 transition-colors disabled:opacity-60 active:scale-[0.98]"
              >
                <LogOut className="w-4 h-4" /> Quitter
              </button>
              <button
                type="button"
                onClick={handleReplay}
                disabled={!!busy}
                className="py-3 rounded-full text-white font-bold flex items-center justify-center gap-1.5 shadow-lg disabled:opacity-60 active:scale-[0.98] transition-transform"
                style={{ background: "var(--gradient-primary)" }}
              >
                <RotateCw
                  className={`w-4 h-4 ${busy === "replay" ? "animate-spin" : ""}`}
                />
                {busy === "replay" ? "…" : "Rejouer"}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
