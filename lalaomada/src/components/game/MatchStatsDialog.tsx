import { useState, useCallback } from "react";
import { useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { Gamepad2, Trophy, ChevronRight, Loader2 } from "lucide-react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";

// ── Game types metadata ─────────────────────────────────────────────────────
export const EMOJI: Record<string, string> = {
  ludo: "🎲", chess: "♜", domino: "🁣", fanorona: "♟", rami: "🂡",
};
export const LABEL: Record<string, string> = {
  ludo: "Ludo", chess: "Échecs", domino: "Domino", fanorona: "Fanorona", rami: "Rami",
};
const ROUTE: Record<string, string> = {
  ludo: "/jeux/ludo/$id", chess: "/jeux/chess/$id", domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id", rami: "/jeux/rami/$id",
};
const PART_TABLE: Record<string, string | null> = {
  domino: "domino_participants", fanorona: "fanorona_participants",
  rami: "rami_participants",
};
const GAME_TABLE: Record<string, string> = {
  domino: "domino_games", fanorona: "fanorona_games", rami: "rami_games",
};

export type MatchItem = {
  id: string; slug: string; status: string; stake: number; pot: number;
  won?: boolean; forfeited?: boolean; finished_at?: string; created_at?: string;
  winner_name?: string; max_players?: number;
};

function fmtDate(d?: string) {
  if (!d) return "—";
  return new Date(d).toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "2-digit" });
}
function fmtAr(n: number | null | undefined) {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-MG").format(Math.round(Number(n) || 0)) + " Ar";
}

/* ────────────────────────────────────────────────────────────────────────────
   Hook: load all finished matches for the current user (lazy, cached)
─────────────────────────────────────────────────────────────────────────────── */
export function useAllMatches(userId?: string | null) {
  const [matches, setMatches] = useState<MatchItem[]>([]);
  const [loaded, setLoaded] = useState(false);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    if (!userId) return;
    setLoading(true);
    try {
      const uid = userId;
      const all: MatchItem[] = [];

      const { data: ludoData } = await supabase.rpc("my_games" as any);
      const ludo = (ludoData as any) || { ongoing: [], finished: [] };
      (ludo.finished || []).forEach((g: any) => all.push({ ...g, slug: "ludo" }));

      const { data: chessRows } = await supabase.from("chess_games" as any)
        .select("*").or(`white_id.eq.${uid},black_id.eq.${uid}`)
        .order("created_at", { ascending: false }).limit(100);
      (chessRows as any[] || []).forEach((g: any) => {
        if (g.status === "finished") {
          all.push({ ...g, slug: "chess", won: g.winner_id === uid });
        }
      });

      await Promise.all(
        Object.entries(PART_TABLE).map(async ([slug, partTable]) => {
          if (!partTable) return;
          const { data: parts } = await supabase
            .from(partTable as any)
            .select(`*, game:${GAME_TABLE[slug]}(*)`)
            .eq("user_id", uid);
          (parts as any[] || []).forEach((r: any) => {
            const g = r.game;
            if (!g) return;
            if (g.status === "finished") {
              all.push({ ...g, slug, won: g.winner_id === uid, forfeited: r.forfeited });
            }
          });
        })
      );

      all.sort((a, b) =>
        new Date(b.finished_at || b.created_at || 0).getTime() -
        new Date(a.finished_at || a.created_at || 0).getTime()
      );
      setMatches(all);
    } finally {
      setLoading(false);
      setLoaded(true);
    }
  }, [userId]);

  return { matches, loaded, loading, load };
}

/* ────────────────────────────────────────────────────────────────────────────
   Match list dialog — reusable across profile & statistiques pages
─────────────────────────────────────────────────────────────────────────────── */
export function MatchListDialog({
  open, onClose, dialogType, matches, loading,
}: {
  open: boolean; onClose: () => void; dialogType: "all" | "wins" | "losses" | null;
  matches: MatchItem[]; loading: boolean;
}) {
  const navigate = useNavigate();

  const filtered = dialogType === "wins"
    ? matches.filter(m => m.won === true)
    : dialogType === "losses"
    ? matches.filter(m => m.status === "finished" && m.won !== true)
    : matches;

  const title = dialogType === "wins" ? "Victoires" : dialogType === "losses" ? "Défaites" : "Toutes les parties";
  const icon = dialogType === "wins"
    ? <Trophy className="w-5 h-5 text-emerald-500" />
    : dialogType === "losses"
    ? <ChevronRight className="w-5 h-5 rotate-90 text-destructive" />
    : <Gamepad2 className="w-5 h-5 text-primary" />;

  const goToGame = (g: MatchItem) => {
    const route = ROUTE[g.slug];
    if (!route) return;
    onClose();
    navigate({ to: route as any, params: { id: g.id } as any });
  };

  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-md max-h-[80vh] flex flex-col p-0 gap-0">
        <DialogHeader className="px-4 pt-4 pb-2 border-b border-border/30 shrink-0">
          <DialogTitle className="flex items-center gap-2 text-base font-extrabold">
            {icon} {title}
            <span className="text-muted-foreground font-normal text-sm">({filtered.length})</span>
          </DialogTitle>
        </DialogHeader>
        <div className="overflow-y-auto flex-1 px-4 py-3 space-y-2">
          {loading ? (
            <div className="flex justify-center py-8">
              <Loader2 className="w-6 h-6 animate-spin text-primary" />
            </div>
          ) : filtered.length === 0 ? (
            <div className="text-center py-8 text-sm text-muted-foreground">Aucune partie.</div>
          ) : (
            filtered.map((g) => {
              const isWin = g.won === true;
              const isLoss = g.status === "finished" && !isWin;
              return (
                <button key={`${g.slug}-${g.id}`} onClick={() => goToGame(g)}
                  className="w-full rounded-xl bg-secondary/40 border border-border/30 p-3 flex items-center gap-3 active:scale-[0.98] transition-transform text-left">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${
                    isWin ? "bg-emerald-500/10 border border-emerald-500/20" :
                    isLoss ? "bg-destructive/10 border border-destructive/20" :
                    "bg-secondary border border-border/40"
                  }`}>
                    {EMOJI[g.slug] ?? "🎮"}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="font-bold text-sm flex items-center gap-1.5">
                      {LABEL[g.slug] ?? g.slug}
                      {isWin && <span className="text-[10px] font-bold text-emerald-500">VICTOIRE</span>}
                      {isLoss && <span className="text-[10px] font-bold text-destructive">DÉFAITE</span>}
                    </div>
                    <div className="flex items-center gap-2 mt-0.5">
                      <span className="text-[11px] text-muted-foreground">Mise {fmtAr(g.stake)}</span>
                      {g.winner_name && <span className="text-[10px] text-muted-foreground/70">Gagnant: {g.winner_name}</span>}
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="text-[10px] text-muted-foreground">
                      {fmtDate(g.finished_at || g.created_at)}
                    </div>
                    <ChevronRight className="w-4 h-4 text-muted-foreground mt-0.5 ml-auto" />
                  </div>
                </button>
              );
            })
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
