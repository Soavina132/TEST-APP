import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useConfirm } from "@/components/ConfirmDialog";
import { toast } from "sonner";
import {
  ArrowLeft, Trophy, Users, Coins, Loader2, Play, LogOut, Swords, Crown, Medal, Eye,
} from "lucide-react";
import { StatusPill } from "./tournaments";

export const Route = createFileRoute("/_authenticated/tournaments_/$id")({
  component: TournamentDetail,
  head: () => ({
    meta: [
      { title: "Détail du tournoi — Lalao MADA" },
      { name: "description", content: "Suivez votre tournoi Lalao MADA : poules, matchs, classement et récompenses en direct." },
      { property: "og:title", content: "Détail du tournoi — Lalao MADA" },
      { property: "og:description", content: "Poules, matchs et récompenses en direct." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

const GAMES: Record<string, { emoji: string; label: string }> = {
  ludo: { emoji: "🎲", label: "Ludo" },
  domino: { emoji: "🁣", label: "Domino" },
};

type State = {
  tournament: any;
  entrants: any[];
  pools: { pool: any; players: any[] }[];
  matches: any[];
};

function TournamentDetail() {
  const { id } = useParams({ from: "/_authenticated/tournaments_/$id" });
  const navigate = useNavigate();
  const { user, isAdmin } = useAuth();
  const confirm = useConfirm();
  const [st, setSt] = useState<State | null>(null);
  const [busy, setBusy] = useState(false);
  const [tab, setTab] = useState<"matches" | "pools" | "players" | "rewards">("matches");

  const load = useCallback(async () => {
    const { data } = await (supabase.rpc as any)("tournament_state", { _tid: id });
    if (data) setSt(data as State);
  }, [id]);

  useEffect(() => {
    load();
    const ch = supabase
      .channel(`tournament-${id}`)
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournaments", filter: `id=eq.${id}` }, () => load())
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournament_entrants", filter: `tournament_id=eq.${id}` }, () => load())
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournament_matches", filter: `tournament_id=eq.${id}` }, () => load())
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournament_pool_entrants" }, () => load())
      .subscribe();
    const iv = setInterval(load, 15000);
    return () => { supabase.removeChannel(ch); clearInterval(iv); };
  }, [id, load]);

  const t = st?.tournament;
  const entrants = st?.entrants ?? [];
  const matches = st?.matches ?? [];
  const byId = useMemo(() => Object.fromEntries(entrants.map((e) => [e.id, e])), [entrants]);
  const me = useMemo(() => entrants.find((e) => e.user_id === user?.id), [entrants, user?.id]);
  const myMatch = useMemo(
    () => matches.find((m) => m.status === "running" && me && m.entrant_ids.includes(me.id)),
    [matches, me],
  );
  const netPrize = t
    ? Math.round(Number(t.prize_pool_ar) * (100 - Number(t.platform_pct)) / 100 + Number(t.admin_prize_pool_ar))
    : 0;

  const rpc = async (fn: string, args: any, ok: string) => {
    setBusy(true);
    const { error } = await (supabase.rpc as any)(fn, args);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(ok);
    load();
  };

  const register = async () => {
    const fee = Number(t.entry_fee_ar);
    const okGo = await confirm({
      title: "Confirmer votre inscription",
      description: fee > 0
        ? `${fee.toLocaleString("fr-FR")} Ar seront débités de votre solde. Cagnotte à gagner : ${netPrize.toLocaleString("fr-FR")} Ar.`
        : "Inscription gratuite à ce tournoi.",
    });
    if (!okGo) return;
    rpc("tournament_register", { _tid: id }, "✅ Inscription confirmée !");
  };

  const unregister = async () => {
    const okGo = await confirm({
      title: "Annuler votre inscription ?",
      description: Number(t.entry_fee_ar) > 0 ? "Vos frais d'inscription seront remboursés." : "Vous quitterez ce tournoi.",
      destructive: true,
    });
    if (!okGo) return;
    rpc("tournament_unregister", { _tid: id }, "Inscription annulée.");
  };

  if (!t) {
    return <div className="flex justify-center py-24"><Loader2 className="w-6 h-6 animate-spin text-muted-foreground" /></div>;
  }

  const g = GAMES[t.game_slug] ?? { emoji: "🏆", label: t.game_slug };
  const steps: [string, boolean, boolean][] = [
    ["Inscriptions", t.stage !== "registration", t.stage === "registration"],
    ["Poules", ["finals", "done"].includes(t.stage), t.stage === "pools"],
    ["Phase finale", t.stage === "done", t.stage === "finals"],
    ["Terminé", t.stage === "done", false],
  ];
  const visibleSteps = t.format === "pools" ? steps : steps.filter((s) => s[0] !== "Poules");

  return (
    <div className="p-4 space-y-4 pb-24">
      <button onClick={() => navigate({ to: "/tournaments" })} className="inline-flex items-center gap-1 text-sm font-semibold text-muted-foreground">
        <ArrowBack className="w-4 h-4" /> Tournois
      </button>

      {/* Hero */}
      <section className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3">
        <div className="flex items-start gap-3">
          <div className="w-14 h-14 rounded-2xl bg-secondary grid place-items-center text-3xl shrink-0">{g.emoji}</div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <h1 className="text-lg font-extrabold truncate">{t.name}</h1>
              <StatusPill status={t.status} />
            </div>
            <p className="text-xs text-muted-foreground mt-0.5">
              {g.label} · {t.format === "pools" ? "Poules + phase finale" : "Élimination directe"} · {t.players_per_match} joueurs/match
            </p>
          </div>
        </div>
        {t.description && <p className="text-sm text-muted-foreground">{t.description}</p>}

        <div className="grid grid-cols-3 gap-2">
          <Info icon={<Trophy className="w-4 h-4" />} label="Cagnotte" value={`${netPrize.toLocaleString("fr-FR")} Ar`} />
          <Info icon={<Coins className="w-4 h-4" />} label="Inscription" value={Number(t.entry_fee_ar) > 0 ? `${Number(t.entry_fee_ar).toLocaleString("fr-FR")} Ar` : "Gratuit"} />
          <Info icon={<Users className="w-4 h-4" />} label="Joueurs" value={`${entrants.length}/${t.max_players}`} />
        </div>

        {/* Progression */}
        <div className="flex items-center gap-1">
          {visibleSteps.map(([label, done, current]) => (
            <div key={label} className="flex-1 text-center">
              <div className={`h-1.5 rounded-full ${done ? "bg-emerald-500" : current ? "bg-amber-500" : "bg-secondary"}`} />
              <span className={`text-[10px] font-semibold ${current ? "text-amber-600" : "text-muted-foreground"}`}>{label}</span>
            </div>
          ))}
        </div>

        {/* Phase en cours + pause */}
        {t.status === "running" && <PhaseBanner t={t} matches={matches} entrants={entrants} />}

        {/* Action principale */}
        {myMatch && myMatch.game_id ? (
          <Link
            to={t.game_slug === "ludo" ? "/ludo/$id" : "/domino/$id"}
            params={{ id: myMatch.game_id }}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-2 animate-pulse"
          >
            <Play className="w-4 h-4" /> Rejoindre mon match
          </Link>
        ) : t.status === "open" ? (
          me ? (
            <button onClick={unregister} disabled={busy} className="w-full py-3 rounded-2xl bg-secondary text-secondary-foreground font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-60">
              <LogOut className="w-4 h-4" /> Annuler mon inscription
            </button>
          ) : (
            <button onClick={register} disabled={busy || entrants.length >= t.max_players} className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-60">
              {entrants.length >= t.max_players ? "Tournoi complet" : "S'inscrire"}
            </button>
          )
        ) : me && me.status === "active" && t.status === "running" ? (
          <div className="w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground">
            ⏳ En attente de votre prochain match…
          </div>
        ) : null}

        {isAdmin && <AdminBar t={t} busy={busy} rpc={rpc} />}
      </section>

      {/* Onglets */}
      <div className="flex gap-2 overflow-x-auto">
        {([["matches", "Matchs"], ...(t.format === "pools" ? [["pools", "Poules"]] : []), ["players", "Participants"], ["rewards", "Récompenses"]] as [any, string][]).map(([k, l]) => (
          <button key={k} onClick={() => setTab(k)}
            className={`px-4 py-2 rounded-full text-sm font-semibold shrink-0 ${tab === k ? "bg-primary text-primary-foreground" : "bg-secondary text-secondary-foreground"}`}>
            {l}
          </button>
        ))}
      </div>

      {tab === "matches" && <MatchesView matches={matches} byId={byId} me={me} slug={t.game_slug} />}
      {tab === "pools" && <PoolsView pools={st!.pools} byId={byId} me={me} />}
      {tab === "players" && <PlayersView entrants={entrants} />}
      {tab === "rewards" && <RewardsView t={t} net={netPrize} byId={byId} />}
    </div>
  );
}

function Info({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-secondary/60 p-2 text-center">
      <div className="flex justify-center text-muted-foreground">{icon}</div>
      <div className="text-[10px] text-muted-foreground">{label}</div>
      <div className="text-sm font-bold">{value}</div>
    </div>
  );
}

function ArrowBack({ className }: { className?: string }) {
  return (
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className={className}>
      <path d="m12 19-7-7 7-7" /><path d="M19 12H5" />
    </svg>
  );
}

function PhaseBanner({ t, matches, entrants }: { t: any; matches: any[]; entrants: any[] }) {
  const running = matches.filter((m) => m.status === "running");
  if (!running.length) return null;
  return (
    <div className="flex items-center gap-2 text-xs font-semibold text-amber-600 bg-amber-50 dark:bg-amber-950/30 rounded-xl px-3 py-2">
      <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" />
      {running.length} match{running.length > 1 ? "s" : ""} en cours
    </div>
  );
}

function AdminBar({ t, busy, rpc }: { t: any; busy: boolean; rpc: (fn: string, args: any, ok: string) => void }) {
  return (
    <div className="flex gap-2">
      {t.status === "open" && (
        <button onClick={() => rpc("admin_tournament_start", { _tid: t.id }, "Tournoi démarré !")} disabled={busy}
          className="flex-1 py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold disabled:opacity-60">
          Démarrer
        </button>
      )}
      {t.status === "running" && (
        <>
          <button onClick={() => rpc("admin_tournament_next_stage", { _tid: t.id }, "Étape suivante !")} disabled={busy}
            className="flex-1 py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold disabled:opacity-60">
            Étape suivante
          </button>
          <button onClick={() => rpc("admin_tournament_set_status", { _tid: t.id, _status: "cancelled" }, "Tournoi annulé")} disabled={busy}
            className="px-3 py-2 rounded-xl bg-destructive text-destructive-foreground text-xs font-bold disabled:opacity-60">
            Annuler
          </button>
        </>
      )}
    </div>
  );
}

function MatchesView({ matches, byId, me, slug }: { matches: any[]; byId: Record<string, any>; me: any; slug: string }) {
  if (!matches.length) {
    return <Empty text="Les matchs apparaîtront dès le démarrage du tournoi." />;
  }
  const rounds = Array.from(new Set(matches.map((m) => m.round))).sort((a, b) => a - b);
  return (
    <div className="space-y-4">
      {rounds.map((r) => (
        <div key={r} className="space-y-2">
          <h3 className="text-xs font-bold text-muted-foreground uppercase">
            {matches.some((m) => m.round === r && m.phase === "pool") ? "Phase de poules" : `Tour ${r}`}
          </h3>
          {matches.filter((m) => m.round === r).map((m) => (
            <div key={m.id} className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
              <div className="flex items-center justify-between gap-2">
                <div className="flex items-center gap-2 text-sm min-w-0">
                  <Swords className="w-4 h-4 text-muted-foreground shrink-0" />
                  <span className="truncate">
                    {m.entrant_ids.map((e: string) => byId[e]?.display_name ?? "?").join("  vs  ")}
                  </span>
                </div>
                <MatchPill m={m} />
              </div>
              {m.status === "finished" && m.winner_entrant_id && (
                <div className="text-xs font-semibold text-emerald-600 mt-1 flex items-center gap-1">
                  <Crown className="w-3.5 h-3.5" /> {byId[m.winner_entrant_id]?.display_name}
                </div>
              )}
              {/* Bouton "Rejoindre" pour participants */}
              {m.status === "running" && m.game_id && me && m.entrant_ids.includes(me.id) && (
                <Link to={slug === "ludo" ? "/ludo/$id" : "/domino/$id"} params={{ id: m.game_id }}
                  className="mt-2 block w-full py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold text-center">
                  Rejoindre
                </Link>
              )}
              {/* Bouton "Voir le live" pour spectateurs (tous les matchs en cours avec game_id) */}
              {m.status === "running" && m.game_id && (!me || !m.entrant_ids.includes(me.id)) && (
                <Link to={slug === "ludo" ? "/ludo/$id" : "/domino/$id"} params={{ id: m.game_id }}
                  className="mt-2 flex items-center justify-center gap-1 w-full py-2 rounded-xl bg-secondary text-secondary-foreground text-xs font-bold text-center">
                  <Eye className="w-3.5 h-3.5" /> Voir le live
                </Link>
              )}
              {m.phase === "third_place" && <div className="text-[10px] font-bold text-amber-600 mt-1">🥉 Petite finale</div>}
            </div>
          ))}
        </div>
      ))}
    </div>
  );
}

function MatchPill({ m }: { m: any }) {
  const map: Record<string, { l: string; c: string }> = {
    scheduled: { l: "À venir", c: "bg-secondary text-muted-foreground" },
    running: { l: "En cours", c: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300" },
    finished: { l: "Terminé", c: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300" },
    cancelled: { l: "Annulé", c: "bg-secondary text-muted-foreground" },
  };
  const s = map[m.status] ?? map.scheduled;
  return <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold shrink-0 ${s.c}`}>{s.l}</span>;
}

function PoolsView({ pools, byId, me }: { pools: { pool: any; players: any[] }[]; byId: Record<string, any>; me: any }) {
  if (!pools.length) return <Empty text="Le tirage des poules aura lieu au démarrage." />;
  return (
    <div className="space-y-3">
      {pools.map(({ pool, players }) => (
        <div key={pool.id} className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-muted-foreground uppercase mb-2">Poule {pool.label ?? pool.id.slice(0, 4)}</h3>
          <div className="space-y-1">
            {players.map((p) => (
              <div key={p.id} className="flex items-center justify-between text-sm">
                <span className={me?.id === p.id ? "font-bold" : ""}>
                  {byId[p.entrant_id]?.display_name ?? "?"}
                  {byId[p.entrant_id]?.is_bot ? " 🤖" : " 👤"}
                </span>
                <span className="text-xs text-muted-foreground">{p.wins ?? 0}V · {p.losses ?? 0}D</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function PlayersView({ entrants }: { entrants: any[] }) {
  const sorted = [...entrants].sort((a, b) => (a.final_rank ?? 99) - (b.final_rank ?? 99));
  return (
    <div className="space-y-1">
      {sorted.map((e) => (
        <div key={e.id} className="flex items-center justify-between rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <div className="flex items-center gap-2 text-sm">
            {e.final_rank <= 3 && <Medal className="w-4 h-4 text-amber-500" />}
            <span className="font-semibold">{e.display_name}</span>
            {e.is_bot ? <span className="text-xs text-muted-foreground">🤖</span> : <span className="text-xs text-muted-foreground">👤</span>}
          </div>
          <span className="text-xs font-bold text-muted-foreground">
            {e.final_rank ? `#${e.final_rank}` : e.status === "active" ? "En jeu" : "Éliminé"}
          </span>
        </div>
      ))}
    </div>
  );
}

function RewardsView({ t, net, byId }: { t: any; net: number; byId: Record<string, any> }) {
  const prizes = [
    { rank: 1, pct: t.prize_1_pct, label: "🥇 1er" },
    { rank: 2, pct: t.prize_2_pct, label: "🥈 2e" },
    { rank: 3, pct: t.prize_3_pct, label: "🥉 3e" },
  ].filter((p) => p.rank <= t.winners_count);

  return (
    <div className="space-y-2">
      {prizes.map((p) => {
        const amount = Math.round(net * p.pct / 100);
        const winner = Object.values(byId).find((e: any) => e.final_rank === p.rank);
        return (
          <div key={p.rank} className="flex items-center justify-between rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
            <span className="text-sm font-semibold">{p.label}</span>
            <div className="text-right">
              <div className="text-sm font-bold">{amount.toLocaleString("fr-FR")} Ar</div>
              {winner && <div className="text-xs text-muted-foreground">{(winner as any).display_name}</div>}
            </div>
          </div>
        );
      })}
      <div className="text-xs text-muted-foreground text-center pt-2">
        Commission plateforme : {t.platform_pct}% · Cagnotte nette : {net.toLocaleString("fr-FR")} Ar
      </div>
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return <div className="text-center text-sm text-muted-foreground py-8">{text}</div>;
}

export default TournamentDetail;
