import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";

type Props = {
  gameId: string;
  game: any;
  meUserId?: string;
};

export default function FanoronaDrawDialog({ gameId, game, meUserId }: Props) {
  const [busy, setBusy] = useState(false);
  const whiteBy: string | null = game.draw_white_by ?? null;
  const blackBy: string | null = game.draw_black_by ?? null;
  const resultColor: "w" | "b" | null = game.draw_result_color ?? null;
  const revealedAt = game.draw_revealed_at ? new Date(game.draw_revealed_at).getTime() : null;
  const [spinning, setSpinning] = useState(false);

  const myPick: "w" | "b" | null =
    meUserId && whiteBy === meUserId ? "w" :
    meUserId && blackBy === meUserId ? "b" : null;
  const bothPicked = !!whiteBy && !!blackBy;

  useEffect(() => {
    if (resultColor) {
      setSpinning(true);
      const t = setTimeout(() => setSpinning(false), 900);
      return () => clearTimeout(t);
    }
  }, [resultColor]);

  useEffect(() => {
    if (!resultColor || !revealedAt) return;
    let cancelled = false;
    const fire = () => supabase.rpc("fanorona_draw_finalize" as any, { _game_id: gameId } as any);
    const startDelay = Math.max(0, revealedAt + 1200 - Date.now());
    const t1 = setTimeout(() => { if (!cancelled) fire(); }, startDelay);
    const interval = setInterval(() => { if (!cancelled) fire(); }, 900);
    return () => { cancelled = true; clearTimeout(t1); clearInterval(interval); };
  }, [resultColor, revealedAt, gameId]);

  const pickColor = async (color: "w" | "b") => {
    if (busy || myPick || resultColor) return;
    setBusy(true);
    const { error } = await supabase.rpc("fanorona_draw_pick_color" as any, {
      _game_id: gameId, _color: color,
    } as any);
    setBusy(false);
    if (error) toast.error(error.message);
  };

  const spin = async () => {
    if (busy || resultColor || !bothPicked) return;
    setBusy(true);
    const { error } = await supabase.rpc("fanorona_draw_spin" as any, { _game_id: gameId } as any);
    setBusy(false);
    if (error) toast.error(error.message);
  };

  const iStart = resultColor && myPick && resultColor === myPick;

  return (
    <div className="fixed inset-0 z-50 bg-black/80 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-sm bg-card rounded-3xl p-6 shadow-2xl border-2 border-amber-500/40">
        <div className="text-center mb-4">
          <div className="text-xs uppercase tracking-widest opacity-70">Tirage au sort</div>
          <div className="text-lg font-extrabold mt-1">Choisissez une couleur</div>
        </div>

        <div className="relative mx-auto w-44 h-44 rounded-2xl bg-gradient-to-br from-amber-700 via-amber-900 to-yellow-950 flex items-center justify-center shadow-inner overflow-hidden border-4 border-amber-600/60">
          {!resultColor && (
            <div className={`flex gap-3 ${bothPicked ? "animate-pulse" : ""}`}>
              <div className="w-12 h-12 rounded-full bg-white shadow-lg" />
              <div className="w-12 h-12 rounded-full bg-black border border-white/30 shadow-lg" />
            </div>
          )}
          {resultColor && (
            <div
              className={`w-24 h-24 rounded-full shadow-2xl border-4 ${
                resultColor === "w" ? "bg-white border-amber-200" : "bg-black border-amber-200"
              } ${spinning ? "animate-spin" : ""}`}
            />
          )}
        </div>

        <div className="mt-4 grid grid-cols-2 gap-2 text-xs">
          <div className={`p-2 rounded-xl text-center ${whiteBy ? "bg-white text-black" : "bg-secondary"}`}>
            <div className="font-bold">⚪ Blanc</div>
            <div className="opacity-80">{whiteBy ? (whiteBy === meUserId ? "Vous" : "Adversaire") : "—"}</div>
          </div>
          <div className={`p-2 rounded-xl text-center ${blackBy ? "bg-black text-white" : "bg-secondary"}`}>
            <div className="font-bold">⚫ Noir</div>
            <div className="opacity-80">{blackBy ? (blackBy === meUserId ? "Vous" : "Adversaire") : "—"}</div>
          </div>
        </div>

        <div className="mt-4 text-center text-sm">
          {!resultColor && !myPick && (
            <>
              <div className="mb-2 opacity-80">Quelle couleur prenez-vous ?</div>
              <div className="flex gap-3 justify-center">
                <button disabled={busy || !!whiteBy} onClick={() => pickColor("w")}
                  className="px-5 py-3 rounded-2xl bg-white text-black font-black shadow disabled:opacity-40">
                  ⚪ Blanc
                </button>
                <button disabled={busy || !!blackBy} onClick={() => pickColor("b")}
                  className="px-5 py-3 rounded-2xl bg-black text-white font-black shadow disabled:opacity-40">
                  ⚫ Noir
                </button>
              </div>
            </>
          )}

          {!resultColor && myPick && !bothPicked && (
            <div className="opacity-80">En attente de l'adversaire…</div>
          )}

          {!resultColor && bothPicked && (
            <button disabled={busy} onClick={spin}
              className="mt-2 w-full py-3 rounded-full bg-primary text-primary-foreground font-extrabold shadow-lg active:scale-95 transition disabled:opacity-50">
              🎲 Faire tourner la boîte
            </button>
          )}

          {resultColor && (
            <div className="space-y-1">
              <div className="opacity-70 text-xs">Boule sortie : {resultColor === "w" ? "⚪ Blanche" : "⚫ Noire"}</div>
              <div className={`font-extrabold text-lg ${iStart ? "text-emerald-500" : "text-amber-500"}`}>
                {iStart ? "🏆 Vous commencez (Blanc) !" : "L'adversaire commence (Blanc)."}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
