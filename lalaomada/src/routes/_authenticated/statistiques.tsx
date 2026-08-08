import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  ArrowLeft, Gamepad2, Trophy, ChevronRight, Calendar, Flame, Loader2,
  X, Clock,
} from "lucide-react";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";

export const Route = createFileRoute("/_authenticated/statistiques")({
  component: StatistiquesPage,
  head: () => ({
    meta: [
      { title: "Statistiques — Lalao MADA" },
      { name: "description", content: "Détail de vos statistiques de jeu : parties, victoires et défaites." },
    ],
  }),
});

const BADGES = [
  { min: 1, label: "Bronze", color: "from-amber-700 to-amber-500", icon: "🥉" },
  { min: 2, label: "Bronze", color: "from-amber-700 to-amber-500", icon: "🥉" },
  { min: 3, label: "Argent", color: "from-slate-400 to-slate-300", icon: "🥈" },
  { min: 4, label: "Argent+", color: "from-slate-400 to-slate-300", icon: "🥈" },
  { min: 5, label: "Or", color: "from-yellow-500 to-amber-400", icon: "🥇" },
  { min: 6, label: "Or+", color: "from-yellow-500 to-amber-400", icon: "🥇" },
  { min: 7, label: "Diamant", color: "from-cyan-400 to-blue-500", icon: "💎" },
  { min: 8, label: "Diamant+", color: "from-cyan-400 to-blue-500", icon: "💎" },
  { min: 9, label: "Platine", color: "from-violet-500 to-fuchsia-500", icon: "👑" },
  { min: 10, label: "Platine Max", color: "from-violet-500 to-fuchsia-500", icon: "👑" },
];
const LEVEL_THRESHOLDS = [0, 1, 3, 7, 12, 20, 35, 60, 100, 200];
function getBadge(level: number) {
  return BADGES[Math.min(Math.max(level, 1), BADGES.length) - 1] || BADGES[0];
}

// ── Game types metadata ─────────────────────────────────────────────────────
const EMOJI: Record<string, string> = {
  ludo: "🎲", chess: "♜", domino: "🁣", fanorona: "♟", rami: "🂡", poker: "🃏",
};
const LABEL: Record<string, string> = {
  ludo: "Ludo", chess: "Échecs", domino: "Domino", fanorona: "Fanorona", rami: "Rami", poker: "Poker",
};
const ROUTE: Record<string, string> = {
  ludo: "/jeux/ludo/$id", chess: "/jeux/chess/$id", domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id", rami: "/jeux/rami/$id", poker: "/jeux/poker/$id",
};
const PART_TABLE: Record<string, string | null> = {
  domino: "domino_participants", fanorona: "fanorona_participants",
  rami: "rami_participants", poker: "poker_players",
};
const GAME_TABLE: Record<string, string> = {
  domino: "domino_games", fanorona: "fanorona_games", rami: "rami_games", poker: "poker_games",
};

type MatchItem = {
  id: string; slug: string; status: string; stake: number; pot: number;
  won?: boolean; forfeited?: boolean; finished_at?: string; created_at?: string;
  winner_name?: string; max_players?: number;
};

// ── Helpers ─────────────────────────────────────────────────────────────────
function fmtDate(d?: string) {
  if (!d) return "—";
  return new Date(d).toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "2-digit" });
}
function fmtAr(n: number | null | undefined) {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-MG").format(Math.round(Number(n) || 0)) + " Ar";
}

// ════════════════════════════════════════════════════════════════════════════
// Match list dialog
// ════════════════════════════════════════════════════════════════════════════
function MatchListDialog({
  open, onClose, title, icon, matches, loading, onOpen,
}: {
  open: boolean; onClose: () => void; title: string; icon: React.ReactNode;
  matches: MatchItem[]; loading: boolean; onOpen: (g: MatchItem) => void;
}) {
  return (
    <Dialog open={open} onOpenChange={(o) => { if (!o) onClose(); }}>
      <DialogContent className="max-w-md max-h-[80vh] flex flex-col p-0 gap-0">
        <DialogHeader className="px-4 pt-4 pb-2 border-b border-border/30 shrink-0">
          <DialogTitle className="flex items-center gap-2 text-base font-extrabold">
            {icon} {title}
            <span className="text-muted-foreground font-normal text-sm">({matches.length})</span>
          </DialogTitle>
        </DialogHeader>
        <div className="overflow-y-auto flex-1 px-4 py-3 space-y-2">
          {loading ? (
            <div className="flex justify-center py-8">
              <Loader2 className="w-6 h-6 animate-spin text-primary" />
            </div>
          ) : matches.length === 0 ? (
            <div className="text-center py-8 text-sm text-muted-foreground">Aucune partie.</div>
          ) : (
            matches.map((g) => {
              const isWin = g.won === true;
              const isLoss = g.status === "finished" && !isWin;
              return (
                <button key={`${g.slug}-${g.id}`} onClick={() => onOpen(g)}
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

// ════════════════════════════════════════════════════════════════════════════
// Main page
// ════════════════════════════════════════════════════════════════════════════
function StatistiquesPage() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [playerStats, setPlayerStats] = useState<any>(null);
  const [myRank, setMyRank] = useState<number | null>(null);
  const [rankLoaded, setRankLoaded] = useState(false);
  const [loaded, setLoaded] = useState(false);

  // Match data
  const [allMatches, setAllMatches] = useState<MatchItem[]>([]);
  const [matchesLoaded, setMatchesLoaded] = useState(false);
  const [matchesLoading, setMatchesLoading] = useState(false);

  // Dialog state
  const [dialogType, setDialogType] = useState<"all" | "wins" | "losses" | null>(null);

  // ── Load stats ────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!user) return;
    const uid = user.id;
    const currentPseudo = profile?.pseudo;

    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => {
      if (data) setPlayerStats(data);
      setLoaded(true);
    });

    supabase.rpc("leaderboard_winners" as any, { _limit: 200 } as any).then(({ data }: any) => {
      setRankLoaded(true);
      if (!data) return;
      const idx = (data as any[]).findIndex((r: any) => r.id === uid || (currentPseudo && r.name === currentPseudo));
      if (idx >= 0) setMyRank((data[idx] as any).rank);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id, profile?.pseudo]);

  // ── Load all matches ─────────────────────────────────────────────────────
  const loadMatches = useCallback(async () => {
    if (!user) return;
    setMatchesLoading(true);
    try {
      const uid = user.id;
      const all: MatchItem[] = [];

      // Ludo via RPC
      const { data: ludoData } = await supabase.rpc("my_games" as any);
      const ludo = (ludoData as any) || { ongoing: [], finished: [] };
      (ludo.finished || []).forEach((g: any) => all.push({ ...g, slug: "ludo" }));

      // Chess
      const { data: chessRows } = await supabase.from("chess_games" as any)
        .select("*").or(`white_id.eq.${uid},black_id.eq.${uid}`)
        .order("created_at", { ascending: false }).limit(100);
      (chessRows as any[] || []).forEach((g: any) => {
        if (g.status === "finished") {
          all.push({ ...g, slug: "chess", won: g.winner_id === uid });
        }
      });

      // Domino / Fanorona / Rami / Poker
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

      // Sort by finished_at descending
      all.sort((a, b) =>
        new Date(b.finished_at || b.created_at || 0).getTime() -
        new Date(a.finished_at || a.created_at || 0).getTime()
      );
      setAllMatches(all);
    } finally {
      setMatchesLoading(false);
      setMatchesLoaded(true);
    }
  }, [user]);

  // Load matches on first tile click
  const openDialog = (type: "all" | "wins" | "losses") => {
    setDialogType(type);
    if (!matchesLoaded) loadMatches();
  };

  // Navigate to a game
  const goToGame = (g: MatchItem) => {
    const route = ROUTE[g.slug];
    if (!route) return;
    setDialogType(null);
    navigate({ to: route as any, params: { id: g.id } as any });
  };

  // ── Derived data ──────────────────────────────────────────────────────────
  const p: any = profile || {};
  const ps: any = playerStats || {};
  const totalWins = ps.total_wins ?? p.total_wins ?? 0;
  const totalGames = ps.total_games ?? p.total_games ?? 0;
  const totalLosses = Math.max(totalGames - totalWins, 0);
  const level = ps.player_level ?? p.player_level ?? 1;
  const dailyStreak = ps.daily_streak ?? p.daily_streak ?? 0;
  const badge = getBadge(level);
  const memberSince = p.created_at ? new Date(p.created_at) : null;

  // Progression
  const nextThreshold = LEVEL_THRESHOLDS[level] ?? null;
  const prevThreshold = LEVEL_THRESHOLDS[level - 1] ?? 0;
  const progressPct = nextThreshold
    ? Math.min(100, Math.round(((totalWins - prevThreshold) / (nextThreshold - prevThreshold)) * 100))
    : 100;
  const winsToNext = nextThreshold ? Math.max(nextThreshold - totalWins, 0) : 0;

  // Filtered matches for dialog
  const dialogMatches = dialogType === "wins"
    ? allMatches.filter(m => m.won === true)
    : dialogType === "losses"
    ? allMatches.filter(m => m.status === "finished" && m.won !== true)
    : allMatches;

  const dialogTitle = dialogType === "wins" ? "Victoires" : dialogType === "losses" ? "Défaites" : "Toutes les parties";
  const dialogIcon = dialogType === "wins"
    ? <Trophy className="w-5 h-5 text-emerald-500" />
    : dialogType === "losses"
    ? <ChevronRight className="w-5 h-5 rotate-90 text-destructive" />
    : <Gamepad2 className="w-5 h-5 text-primary" />;

  if (!loaded) {
    return <main className="p-8 text-center text-muted-foreground">Chargement…</main>;
  }

  return (
    <main className="mx-auto max-w-md flex flex-col gap-3 p-3 pb-20 min-h-screen">
      {/* Header */}
      <div className="flex items-center gap-2">
        <button onClick={() => navigate({ to: "/profile", search: {} })}
          className="p-2 rounded-full bg-secondary/60 active:scale-90 transition-transform">
          <ArrowLeft className="w-4 h-4" />
        </button>
        <Trophy className="w-5 h-5 text-primary" />
        <h1 className="text-xl font-extrabold">Statistiques</h1>
      </div>

      {/* Niveau + rang — compact */}
      <div className="rounded-2xl bg-card border border-border/40 p-4">
        <div className="flex items-center gap-3">
          <div className={`w-12 h-12 rounded-full flex items-center justify-center text-xl bg-gradient-to-br ${badge.color}`}>
            {badge.icon}
          </div>
          <div className="flex-1">
            <div className="font-extrabold text-sm">{badge.label}</div>
            <div className="flex items-center gap-3 mt-0.5">
              <span className="text-[11px] text-muted-foreground flex items-center gap-0.5">
                <span className="font-bold text-foreground">Niv. {level}</span>
              </span>
              {rankLoaded && (
                <span className="text-[11px] text-muted-foreground flex items-center gap-0.5">
                  Rang <span className="font-bold text-amber-500">#{myRank ?? "—"}</span>
                </span>
              )}
            </div>
          </div>
        </div>
        {nextThreshold ? (
          <div className="mt-3">
            <div className="flex items-center justify-between text-[10px] text-muted-foreground mb-1">
              <span>Progression niveau suivant</span>
              <span className="font-semibold">{winsToNext} vict. restantes</span>
            </div>
            <div className="h-1.5 rounded-full bg-secondary/60 overflow-hidden">
              <div className="h-full rounded-full bg-primary transition-all" style={{ width: `${progressPct}%` }} />
            </div>
          </div>
        ) : (
          <div className="mt-3 text-[10px] text-center text-primary font-semibold">🏆 Niveau maximum atteint !</div>
        )}
      </div>

      {/* Tuiles cliquables — Parties / Victoires / Défaites */}
      <div className="grid grid-cols-3 gap-2">
        <button onClick={() => openDialog("all")}
          className="rounded-2xl bg-card border border-border/40 p-3 flex flex-col items-center justify-center gap-1 active:scale-95 transition-transform">
          <Gamepad2 className="w-5 h-5 text-muted-foreground" />
          <span className="text-xl font-black tabular-nums leading-none">{totalGames}</span>
          <span className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Parties</span>
        </button>
        <button onClick={() => openDialog("wins")}
          className="rounded-2xl bg-card border border-border/40 p-3 flex flex-col items-center justify-center gap-1 active:scale-95 transition-transform">
          <Trophy className="w-5 h-5 text-emerald-500" />
          <span className="text-xl font-black tabular-nums leading-none text-emerald-500">{totalWins}</span>
          <span className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Victoires</span>
        </button>
        <button onClick={() => openDialog("losses")}
          className="rounded-2xl bg-card border border-border/40 p-3 flex flex-col items-center justify-center gap-1 active:scale-95 transition-transform">
          <ChevronRight className="w-5 h-5 rotate-90 text-destructive" />
          <span className="text-xl font-black tabular-nums leading-none text-destructive">{totalLosses}</span>
          <span className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Défaites</span>
        </button>
      </div>

      {/* Infos complémentaires */}
      <div className="rounded-2xl bg-card border border-border/40 divide-y divide-border/30">
        <div className="flex items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2 text-sm">
            <Flame className="w-4 h-4 text-orange-500" />
            <span>Série quotidienne</span>
          </div>
          <span className="font-bold text-sm">{dailyStreak} jour{dailyStreak > 1 ? "s" : ""}</span>
        </div>
        {memberSince && (
          <div className="flex items-center justify-between px-4 py-3">
            <div className="flex items-center gap-2 text-sm">
              <Calendar className="w-4 h-4 text-sky-500" />
              <span>Membre depuis</span>
            </div>
            <span className="font-bold text-sm">
              {memberSince.toLocaleDateString("fr-FR", { day: "2-digit", month: "long", year: "numeric" })}
            </span>
          </div>
        )}
        <div className="flex items-center justify-between px-4 py-3">
          <div className="flex items-center gap-2 text-sm">
            <Clock className="w-4 h-4 text-primary" />
            <span>Objectif niveau suivant</span>
          </div>
          <span className="font-bold text-sm">
            {nextThreshold ? `${nextThreshold} victoires` : "Niveau max"}
          </span>
        </div>
      </div>

      {/* Match list dialog */}
      <MatchListDialog
        open={dialogType !== null}
        onClose={() => setDialogType(null)}
        title={dialogTitle}
        icon={dialogIcon}
        matches={dialogMatches}
        loading={matchesLoading}
        onOpen={goToGame}
      />
    </main>
  );
}
