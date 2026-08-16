import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { X, RotateCw, Loader2, Folder } from "lucide-react";

type MyGame = {
  id: string;
  slug: string;
  status: string;
  stake: number;
  pot: number;
  is_private?: boolean;
  room_code?: string;
  won?: boolean;
  forfeited?: boolean;
  finished_at?: string;
};

const ROUTE: Record<string, string> = {
  ludo:     "/jeux/ludo/$id",
  chess:    "/jeux/chess/$id",
  domino:   "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  rami:     "/jeux/rami/$id",
};

const EMOJI: Record<string, string> = {
  ludo:     "🎲",
  chess:    "♜",
  domino:   "🁣",
  fanorona: "♟",
  rami:     "🂡",
};

const LABEL: Record<string, string> = {
  ludo:     "Ludo",
  chess:    "Échecs",
  domino:   "Domino",
  fanorona: "Fanorona",
  rami:     "Rami",
};

const PART_TABLE: Record<string, string | null> = {
  domino:   "domino_participants",
  fanorona: "fanorona_participants",
  rami:     "rami_participants",
};

const GAME_TABLE: Record<string, string> = {
  domino:   "domino_games",
  fanorona: "fanorona_games",
  rami:     "rami_games",
};

export default function MesPartiesSheet({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { profile } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = useState(false);
  const [ongoing, setOngoing] = useState<MyGame[]>([]);
  const [finished, setFinished] = useState<MyGame[]>([]);
  const [tab, setTab] = useState<"ongoing" | "finished">("ongoing");

  const load = useCallback(async () => {
    if (!profile?.id) return;
    setLoading(true);
    try {
      const uid = profile.id;
      const allOngoing: MyGame[] = [];
      const allFinished: MyGame[] = [];

      // ── Ludo ──────────────────────────────────────────────
      const { data: ludoData } = await supabase.rpc("my_games" as any);
      const ludo = (ludoData as any) || { ongoing: [], finished: [] };
      (ludo.ongoing || []).forEach((g: any) => allOngoing.push({ ...g, slug: "ludo" }));
      (ludo.finished || []).forEach((g: any) => allFinished.push({ ...g, slug: "ludo" }));

      // ── Chess ─────────────────────────────────────────────
      const { data: chessRows } = await supabase.from("chess_games" as any)
        .select("*").or(`white_id.eq.${uid},black_id.eq.${uid}`)
        .order("created_at", { ascending: false }).limit(50);
      (chessRows as any[] || []).forEach((g: any) => {
        if (g.status === "open" || g.status === "playing") {
          allOngoing.push({ ...g, slug: "chess" });
        } else if (g.status === "finished" || g.status === "cancelled") {
          allFinished.push({ ...g, slug: "chess", won: g.winner_id === uid });
        }
      });

      // ── Domino / Fanorona / Rami ─────────────────
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
            if (g.status === "open" || g.status === "playing") {
              allOngoing.push({ ...g, slug });
            } else if (g.status === "finished" || g.status === "cancelled") {
              allFinished.push({ ...g, slug, won: g.winner_id === uid, forfeited: r.forfeited });
            }
          });
        })
      );

      // Trier par date décroissante
      const byDate = (a: MyGame, b: MyGame) =>
        new Date((b as any).created_at || 0).getTime() - new Date((a as any).created_at || 0).getTime();

      setOngoing(allOngoing.sort(byDate));
      setFinished(allFinished.sort((a, b) =>
        new Date(b.finished_at || 0).getTime() - new Date(a.finished_at || 0).getTime()
      ));
    } finally {
      setLoading(false);
    }
  }, [profile?.id]);

  useEffect(() => {
    if (open) { load(); setTab("ongoing"); }
  }, [open, load]);

  const goTo = (g: MyGame) => {
    const route = ROUTE[g.slug];
    if (!route) return;
    onClose();
    navigate({ to: route as any, params: { id: g.id } as any });
  };

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60" onClick={onClose}>
      <div
        className="relative w-full max-w-md rounded-t-3xl bg-background shadow-2xl max-h-[85vh] flex flex-col"
        onClick={e => e.stopPropagation()}
      >
        {/* Handle */}
        <div className="w-10 h-1 rounded-full bg-border mx-auto mt-3 shrink-0" />

        {/* Header */}
        <div className="flex items-center justify-between px-5 pt-4 pb-2 shrink-0">
          <div className="flex items-center gap-2">
            <Folder className="w-5 h-5 text-primary" />
            <h2 className="text-lg font-black">Mes parties</h2>
          </div>
          <button onClick={onClose} className="w-9 h-9 rounded-full bg-secondary grid place-items-center">
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Tabs */}
        <div className="grid grid-cols-2 gap-2 px-5 pb-3 shrink-0">
          <button
            onClick={() => setTab("ongoing")}
            className={`py-2.5 rounded-2xl font-bold text-sm transition-all ${tab === "ongoing" ? "text-primary-foreground shadow-md" : "bg-secondary text-foreground"}`}
            style={tab === "ongoing" ? { background: "var(--gradient-primary)" } : undefined}
          >
            🎮 En cours ({ongoing.length})
          </button>
          <button
            onClick={() => setTab("finished")}
            className={`py-2.5 rounded-2xl font-bold text-sm transition-all ${tab === "finished" ? "text-primary-foreground shadow-md" : "bg-secondary text-foreground"}`}
            style={tab === "finished" ? { background: "var(--gradient-primary)" } : undefined}
          >
            🏁 Terminées ({finished.length})
          </button>
        </div>

        {/* Content */}
        <div className="overflow-y-auto flex-1 px-5 pb-8 space-y-3">
          {loading ? (
            <div className="flex justify-center py-10">
              <Loader2 className="w-6 h-6 animate-spin text-primary" />
            </div>
          ) : tab === "ongoing" ? (
            ongoing.length === 0 ? (
              <div className="rounded-3xl bg-card p-6 text-center text-muted-foreground">
                Aucune partie en cours.
              </div>
            ) : (
              ongoing.map(g => (
                <div key={`${g.slug}-${g.id}`}
                  className="rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${g.status === "open" ? "bg-amber-500/10 border border-amber-500/15" : "bg-primary/10 border border-primary/15"}`}>
                    {EMOJI[g.slug] ?? "🎮"}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="font-bold text-sm">{LABEL[g.slug] ?? g.slug} · {g.status === "open" ? "En attente" : "En cours"}</div>
                    <div className="flex items-center gap-2 mt-0.5">
                      <span className="text-[11px] text-muted-foreground">Mise {Number(g.stake || 0).toLocaleString("fr-FR")} Ar</span>
                      {g.is_private && g.room_code && (
                        <span className="text-[10px] font-mono text-muted-foreground/60 bg-white/5 px-1.5 py-0.5 rounded">{g.room_code}</span>
                      )}
                    </div>
                  </div>
                  <button onClick={() => goTo(g)}
                    className="flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-xs shadow-md shadow-primary/20 active:scale-95 transition-all shrink-0">
                    <RotateCw className="w-3.5 h-3.5" /> Reprendre
                  </button>
                </div>
              ))
            )
          ) : (
            finished.length === 0 ? (
              <div className="rounded-3xl bg-card p-6 text-center text-muted-foreground">
                Aucune partie terminée.
              </div>
            ) : (
              finished.map(g => (
                <div key={`${g.slug}-${g.id}`}
                  className="rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0 border ${g.won ? "bg-amber-500/10 border-amber-500/20" : g.forfeited ? "bg-destructive/8 border-destructive/15" : "bg-white/5 border-white/8"}`}>
                    {g.won ? "🏆" : g.forfeited ? "🏳️" : "💔"}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className={`font-bold text-sm ${g.won ? "text-amber-500" : g.forfeited ? "text-destructive" : ""}`}>
                      {LABEL[g.slug] ?? g.slug} · {g.won ? "Victoire" : g.forfeited ? "Forfait" : "Défaite"}
                    </div>
                    <div className="text-[11px] text-muted-foreground mt-0.5">
                      {Number(g.stake || 0).toLocaleString("fr-FR")} Ar · {Number(g.pot || 0).toLocaleString("fr-FR")} Ar pot
                    </div>
                  </div>
                  <div className="text-[10px] text-muted-foreground/50 shrink-0 text-right">
                    {g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : ""}
                  </div>
                </div>
              ))
            )
          )}
        </div>
      </div>
    </div>
  );
}
