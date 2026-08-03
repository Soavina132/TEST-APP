import { createFileRoute, Link } from "@tanstack/react-router";
import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Trophy, Users, Coins, Loader2, CalendarClock } from "lucide-react";

export const Route = createFileRoute("/_authenticated/tournaments")({
  component: TournamentsPage,
  head: () => ({
    meta: [
      { title: "Tournois — Lalao MADA" },
      { name: "description", content: "Inscrivez-vous aux tournois Ludo et Domino de Lalao MADA et gagnez des récompenses." },
      { property: "og:title", content: "Tournois — Lalao MADA" },
      { property: "og:description", content: "Tournois Ludo et Domino avec cagnotte à gagner." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

const GAMES: Record<string, { emoji: string; label: string }> = {
  ludo: { emoji: "🎲", label: "Ludo" },
  domino: { emoji: "🁣", label: "Domino" },
};

type Tab = "open" | "running" | "finished";

function TournamentsPage() {
  const [tab, setTab] = useState<Tab>("open");
  const [rows, setRows] = useState<any[]>([]);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const statuses = tab === "open" ? ["open"] : tab === "running" ? ["running", "paused"] : ["finished", "cancelled"];
    const { data } = await (supabase.from("tournaments" as any) as any)
      .select("*")
      .in("status", statuses)
      .order("created_at", { ascending: false })
      .limit(50);
    const list = (data as any[]) || [];
    setRows(list);
    if (list.length) {
      const { data: ents } = await (supabase.from("tournament_entrants" as any) as any)
        .select("tournament_id")
        .in("tournament_id", list.map((r) => r.id));
      const c: Record<string, number> = {};
      ((ents as any[]) || []).forEach((e) => { c[e.tournament_id] = (c[e.tournament_id] || 0) + 1; });
      setCounts(c);
    }
    setLoading(false);
  }, [tab]);

  useEffect(() => {
    setLoading(true);
    load();
    const ch = supabase
      .channel("tournaments-list")
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournaments" }, () => load())
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournament_entrants" }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [load]);

  return (
    <div className="p-4 space-y-4 pb-24">
      <header className="flex items-center gap-2">
        <Trophy className="w-6 h-6 text-amber-500" />
        <h1 className="text-xl font-extrabold">Tournois</h1>
      </header>

      <div className="flex gap-2">
        {([["open", "Ouverts"], ["running", "En cours"], ["finished", "Terminés"]] as [Tab, string][]).map(([k, l]) => (
          <button
            key={k}
            onClick={() => setTab(k)}
            className={`px-4 py-2 rounded-full text-sm font-semibold transition-colors ${
              tab === k ? "bg-primary text-primary-foreground" : "bg-secondary text-secondary-foreground"
            }`}
          >
            {l}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="flex justify-center py-16"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>
      ) : rows.length === 0 ? (
        <div className="rounded-3xl bg-card p-8 text-center text-sm text-muted-foreground shadow-[var(--shadow-soft)]">
          Aucun tournoi pour le moment.
        </div>
      ) : (
        <div className="space-y-3">
          {rows.map((t) => {
            const g = GAMES[t.game_slug] ?? { emoji: "🏆", label: t.game_slug };
            const n = counts[t.id] ?? 0;
            return (
              <Link
                key={t.id}
                to="/tournaments/$id"
                params={{ id: t.id }}
                className="block rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] active:scale-[0.99] transition-transform"
              >
                <div className="flex items-start gap-3">
                  <div className="w-12 h-12 rounded-2xl bg-secondary grid place-items-center text-2xl shrink-0">{g.emoji}</div>
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <h2 className="font-bold truncate">{t.name}</h2>
                      <StatusPill status={t.status} />
                    </div>
                    <p className="text-xs text-muted-foreground mt-0.5">
                      {g.label} · {t.format === "pools" ? "Poules + finale" : "Élimination directe"} · {t.players_per_match} joueurs/match
                    </p>
                    <div className="flex flex-wrap items-center gap-3 mt-2 text-xs font-semibold">
                      <span className="inline-flex items-center gap-1 text-muted-foreground">
                        <Users className="w-3.5 h-3.5" /> {n}/{t.max_players}
                      </span>
                      <span className="inline-flex items-center gap-1 text-amber-600">
                        <Trophy className="w-3.5 h-3.5" />
                        {Math.round(Number(t.prize_pool_ar) * (100 - Number(t.platform_pct)) / 100 + Number(t.admin_prize_pool_ar)).toLocaleString("fr-FR")} Ar
                      </span>
                      <span className="inline-flex items-center gap-1 text-muted-foreground">
                        <Coins className="w-3.5 h-3.5" />
                        {Number(t.entry_fee_ar) > 0 ? `${Number(t.entry_fee_ar).toLocaleString("fr-FR")} Ar` : "Gratuit"}
                      </span>
                      {t.starts_at && (
                        <span className="inline-flex items-center gap-1 text-muted-foreground">
                          <CalendarClock className="w-3.5 h-3.5" />
                          {new Date(t.starts_at).toLocaleString("fr-FR", { day: "2-digit", month: "short", hour: "2-digit", minute: "2-digit" })}
                        </span>
                      )}
                    </div>
                  </div>
                </div>
              </Link>
            );
          })}
        </div>
      )}
    </div>
  );
}

export function StatusPill({ status }: { status: string }) {
  const map: Record<string, { l: string; c: string }> = {
    draft: { l: "Brouillon", c: "bg-secondary text-muted-foreground" },
    open: { l: "Inscriptions", c: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300" },
    running: { l: "En cours", c: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300" },
    paused: { l: "En pause", c: "bg-secondary text-muted-foreground" },
    finished: { l: "Terminé", c: "bg-secondary text-muted-foreground" },
    cancelled: { l: "Annulé", c: "bg-secondary text-muted-foreground" },
  };
  const s = map[status] ?? map.draft;
  return <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold shrink-0 ${s.c}`}>{s.l}</span>;
}
