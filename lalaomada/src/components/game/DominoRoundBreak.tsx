import { useEffect, useState } from "react";
import { serverNow } from "@/lib/server-time";
import { DominoTile, Tile } from "@/components/game/DominoTable";

type LastRound = {
  winner_uid: string | null;
  winner_slot?: number | null;
  round_score: number;
  hand_pips: Record<string, number>;
  final_hands?: Record<string, Tile[]>;
  blocked?: boolean;
  round?: number;
};

function ordinalFr(n: number): string {
  if (n === 1) return "1ère";
  return `${n}ème`;
}

export default function DominoRoundBreak({
  lastRound,
  scores,
  targetScore,
  breakUntil,
  participants,
  roundNumber,
}: {
  lastRound: LastRound;
  scores: Record<string, number>;
  targetScore: number;
  breakUntil: string;
  participants: { user_id: string; display_name: string }[];
  roundNumber?: number;
}) {
  // Prefer server-provided round (round that just ended) over client fallback.
  const endedRound = Number(
    lastRound?.round ?? (typeof roundNumber === "number" ? roundNumber : 1),
  ) || 1;
  const initialRemaining = Math.max(0, Math.round((new Date(breakUntil).getTime() - serverNow()) / 1000));
  const [remaining, setRemaining] = useState(initialRemaining);
  useEffect(() => {
    const tick = () => {
      const ms = new Date(breakUntil).getTime() - serverNow();
      setRemaining(Math.max(0, Math.round(ms / 1000)));
    };
    tick();
    const t = setInterval(tick, 250);
    return () => clearInterval(t);
  }, [breakUntil]);

  // Bots have no real user_id in the DB (winner_uid is null for them) — the
  // participants list upstream already remaps bot user_id to "bot_<slot>",
  // so we do the same fallback here to correctly match the actual winner.
  const winnerKey = lastRound.winner_uid || (lastRound.winner_slot != null ? `bot_${lastRound.winner_slot}` : null);
  const isTie = !winnerKey;
  // Try matching by user_id first, then by slot (for bots whose user_id may not match "bot_X")
  const winnerParticipant = participants.find(p => p.user_id === winnerKey)
    || (lastRound.winner_slot != null ? participants.find(p => (p as any).slot === lastRound.winner_slot) : null);
  const winnerName = winnerParticipant?.display_name || "Match nul";

  return (
    <div className="fixed inset-0 z-[70] bg-black/60 backdrop-blur-sm flex items-center justify-center p-3">
      <div className="w-full max-w-md rounded-3xl p-5 shadow-2xl animate-in zoom-in-95"
        style={{ background: "#15448e", border: "4px solid #f5c542" }}>
        <div className="text-center text-white">
          <h2 className="text-2xl font-extrabold tracking-wide">
            {ordinalFr(endedRound)} Manche terminée
          </h2>
          <div className={`mt-1 text-sm font-bold ${isTie ? "text-amber-200" : "text-emerald-200"}`}>
            {isTie ? "🤝 Match nul — égalité des points" : `🏆 Victoire : ${winnerName}`}
          </div>
          {lastRound.blocked && (
            <div className="text-[11px] mt-1 opacity-90">
              {isTie ? "Aucun domino jouable pour personne, nouvelle manche relancée" : "Blocage : personne ne peut jouer — victoire au moins de points"}
            </div>
          )}
          <div className="text-xs mt-1 opacity-90">Note gagnante : {targetScore}</div>
        </div>

        <div className={`mt-4 grid gap-2 text-white text-center ${participants.length >= 3 ? "grid-cols-3" : "grid-cols-2"}`}>
          {participants.map(p => {
            const total = Number(scores?.[String(p.slot)] || 0);
            const pips = lastRound.hand_pips?.[String(p.slot)] ?? 0;
            const tiles = (lastRound.final_hands?.[String(p.slot)] || []) || [];
            const isWinner = (lastRound.winner_slot != null && p.slot === lastRound.winner_slot) || p.user_id === winnerKey;
            const roundScore = isWinner ? lastRound.round_score : 0;
            return (
              <div key={p.user_id} className="px-1 space-y-2 rounded-xl py-2"
                style={{ background: isWinner ? "rgba(74,222,128,0.15)" : "rgba(0,0,0,0.15)" }}>
                <div className="text-[12px] font-extrabold truncate">{p.display_name}{isWinner ? " 🏆" : ""}</div>
                <div className="flex flex-wrap gap-0.5 justify-center min-h-[28px]">
                  {tiles.length === 0 ? (
                    <span className="text-[10px] opacity-70">(vide)</span>
                  ) : (
                    tiles.map((t, i) => <DominoTile key={i} t={t} w={12} />)
                  )}
                </div>
                <div className="text-[10px] font-bold opacity-90 uppercase">Pts main</div>
                <div className="text-lg font-extrabold leading-none">{pips}</div>
                {isWinner && roundScore > 0 && (
                  <div className="text-[10px] text-emerald-200">+{roundScore} ce tour</div>
                )}
                <div className="text-[10px] font-bold opacity-90 uppercase">Total</div>
                <div className="text-xl font-extrabold leading-none" style={{ color: isWinner ? "#4ade80" : "#fbbf24" }}>{total}</div>
              </div>
            );
          })}
        </div>

        <div className="mt-5 flex justify-center">
          <div className="px-6 py-2.5 rounded-full text-[#7a2e0a] font-extrabold shadow-lg"
            style={{ background: "linear-gradient(180deg,#fbbf24,#f59e0b)", border: "2px solid #f5c542" }}>
            Manche suivante ({remaining}s)
          </div>
        </div>
      </div>
    </div>
  );
}
