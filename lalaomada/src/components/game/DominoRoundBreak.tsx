import { useEffect, useState } from "react";
import { serverNow } from "@/lib/server-time";
import { DominoTile, Tile } from "@/components/game/DominoTable";

type LastRound = {
  winner_uid: string | null; winner_slot?: number | null;
  round_score: number; hand_pips: Record<string, number>;
  final_hands?: Record<string, Tile[]>; blocked?: boolean; round?: number;
};

function ordinalFr(n: number) { return n === 1 ? "1ère" : `${n}ème`; }

export default function DominoRoundBreak({
  lastRound, scores, targetScore, breakUntil, participants, roundNumber,
}: {
  lastRound: LastRound; scores: Record<string, number>; targetScore: number;
  breakUntil: string; participants: { user_id: string; display_name: string }[];
  roundNumber?: number;
}) {
  const endedRound = Number(lastRound?.round ?? roundNumber ?? 1) || 1;
  const [remaining, setRemaining] = useState(7);

  useEffect(() => {
    const tick = () => {
      const ms = new Date(breakUntil).getTime() - serverNow();
      setRemaining(Math.max(0, Math.round(ms / 1000)));
    };
    tick();
    const t = setInterval(tick, 250);
    return () => clearInterval(t);
  }, [breakUntil]);

  const winnerKey = lastRound.winner_uid || (lastRound.winner_slot != null ? `bot_${lastRound.winner_slot}` : null);
  const isTie = !winnerKey;
  const winnerName = participants.find(p => p.user_id === winnerKey)?.display_name || "Match nul";

  return (
    <div className="fixed inset-0 z-[70] bg-black/65 backdrop-blur-sm flex items-center justify-center p-3">
      <div className="w-full max-w-md rounded-3xl p-5 shadow-2xl animate-in zoom-in-95"
        style={{ background: "linear-gradient(135deg, #0c3460, #15448e)", border: "3px solid #f5c542" }}>
        <div className="text-center text-white">
          <h2 className="text-xl font-extrabold tracking-wide">{ordinalFr(endedRound)} manche terminée</h2>
          <div className={`mt-1 text-sm font-bold ${isTie ? "text-amber-200" : "text-emerald-300"}`}>
            {isTie ? "🤝 Match nul" : `🏆 ${winnerName}`}
          </div>
          {lastRound.blocked && <div className="text-[11px] mt-1 opacity-70">Blocage — plus personne ne peut jouer</div>}
        </div>
        <div className={`mt-4 grid gap-2 text-white text-center ${participants.length >= 3 ? "grid-cols-3" : "grid-cols-2"}`}>
          {participants.map(p => {
            const total = Number(scores?.[p.user_id] || 0);
            const pips = lastRound.hand_pips?.[p.user_id] ?? 0;
            const tiles = lastRound.final_hands?.[p.user_id] || [];
            const isWinner = p.user_id === winnerKey;
            return (
              <div key={p.user_id} className="px-1 py-2 rounded-xl space-y-1"
                style={{ background: isWinner ? "rgba(74,222,128,0.12)" : "rgba(0,0,0,0.2)" }}>
                <div className="text-[12px] font-extrabold truncate">{p.display_name}{isWinner ? " 🏆" : ""}</div>
                <div className="flex flex-wrap gap-0.5 justify-center min-h-[24px]">
                  {tiles.length === 0 ? <span className="text-[10px] opacity-50">(vide)</span>
                    : tiles.map((t, i) => <DominoTile key={i} t={t} w={11} />)}
                </div>
                <div className="text-[9px] font-bold opacity-60 uppercase">Main</div>
                <div className="text-base font-extrabold leading-none">{pips} pts</div>
                {targetScore > 0 && (<>
                <div className="text-[9px] font-bold opacity-60 uppercase">Total</div>
                <div className="text-xl font-extrabold leading-none" style={{ color: isWinner ? "#4ade80" : "#fbbf24" }}>{total}</div>
                </>)}
              </div>
            );
          })}
        </div>
        <div className="mt-5 flex justify-center">
          <div className="px-6 py-2.5 rounded-full text-[#7a2e0a] font-extrabold shadow-lg"
            style={{ background: "linear-gradient(180deg,#fbbf24,#f59e0b)", border: "2px solid #f5c542" }}>
            Prochaine manche ({remaining}s)
          </div>
        </div>
      </div>
    </div>
  );
}
