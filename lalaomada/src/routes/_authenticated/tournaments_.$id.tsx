import { createFileRoute, useParams, useNavigate, Link } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { serverNow } from "@/lib/server-time";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useConfirm } from "@/components/ConfirmDialog";
import { toast } from "sonner";
import {
  ArrowLeft, Trophy, Users, Coins, Loader2, Play, LogOut, Swords, Crown, Medal,
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
        <ArrowLeft className="w-4 h-4" /> Tournois
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
        {myMatch ? (
          <Link
            to={t.game_slug === "ludo" ? "/game/$id" : "/domino/$id"}
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
      <div className="text-xs font-bold truncate">{value}</div>
    </div>
  );
}

function useCountdown(target?: string | null) {
  const [left, setLeft] = useState(0);
  useEffect(() => {
    if (!target) { setLeft(0); return; }
    const tick = () => setLeft(Math.max(0, Math.round((new Date(target).getTime() - serverNow()) / 1000)));
    tick();
    const iv = setInterval(tick, 1000);
    return () => clearInterval(iv);
  }, [target]);
  return left;
}

function fmt(s: number) {
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
}

function PhaseBanner({ t, matches, entrants }: { t: any; matches: any[]; entrants: any[] }) {
  const left = useCountdown(t.break_until);
  const active = entrants.filter((e) => e.status === "active").length;
  const round = matches.filter((m) => m.round === t.current_round && m.phase !== "pool");
  const done = round.filter((m) => m.status === "finished").length;
  const live = round.filter((m) => m.status === "running").length;
  const isThird = round.some((m) => m.phase === "third_place");
  const isFinal = round.length === 1 && !isThird;
  const title = t.stage === "pools"
    ? "Phase de poules"
    : isThird
      ? "🥉 Petite finale"
      : isFinal
        ? "🏆 Finale"
        : `Phase ${t.current_round}${t.total_rounds ? ` / ${t.total_rounds}` : ""}`;

  return (
    <div className="rounded-2xl bg-secondary/60 p-3 space-y-1.5">
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-bold">{title}</span>
        <span className="text-[11px] font-semibold text-muted-foreground">
          {active} joueur{active > 1 ? "s" : ""} en lice
        </span>
      </div>
      {round.length > 0 && (
        <div className="text-xs text-muted-foreground">
          {round.length} match{round.length > 1 ? "s" : ""} · {done} terminé{done > 1 ? "s" : ""} · {live} en cours
          <span className="opacity-70"> (8 simultanés max)</span>
        </div>
      )}
      {left > 0 && (
        <div className="rounded-xl bg-amber-100 dark:bg-amber-950/40 px-3 py-2 text-xs font-bold text-amber-700 dark:text-amber-300">
          ⏸ Pause — phase suivante dans {fmt(left)}. Préparez-vous !
        </div>
      )}
    </div>
  );
}

function AdminBar({ t, busy, rpc }: { t: any; busy: boolean; rpc: (fn: string, a: any, ok: string) => void }) {
  const [bots, setBots] = useState(4);
  const [brk, setBrk] = useState(Math.round((t.break_seconds ?? 180) / 60));
  return (

    <div className="rounded-2xl border border-dashed border-border p-3 space-y-2">
      <div className="text-[11px] font-bold text-muted-foreground">Contrôles admin</div>
      <div className="flex flex-wrap gap-2">
        {t.status === "open" && (
          <>
            <div className="flex items-center gap-1">
              <input type="number" min={1} max={64} value={bots} onChange={(e) => setBots(Number(e.target.value))}
                className="w-16 px-2 py-1.5 rounded-xl bg-secondary text-sm" />
              <button disabled={busy} onClick={() => rpc("admin_tournament_add_bots", { _tid: t.id, _count: bots }, "Bots ajoutés")}
                className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">+ Bots</button>
            </div>
            <button disabled={busy} onClick={() => rpc("admin_tournament_start", { _tid: t.id }, "Tournoi démarré")}
              className="px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold">▶ Démarrer</button>
          </>
        )}
        {t.status === "running" && (
          <>
            <button disabled={busy} onClick={() => rpc("admin_tournament_next_stage", { _tid: t.id }, "Phase suivante lancée")}
              className="px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold">⏭ Phase suivante</button>
            <button disabled={busy} onClick={() => rpc("admin_tournament_delay", { _tid: t.id, _minutes: 5 }, "Phase retardée de 5 min")}
              className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">⏳ +5 min</button>
            <button disabled={busy} onClick={() => rpc("admin_tournament_set_status", { _tid: t.id, _status: "paused" }, "Tournoi en pause")}
              className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">⏸ Pause</button>
            <button disabled={busy} onClick={() => rpc("admin_tournament_set_auto", { _tid: t.id, _auto: !t.auto_advance }, "Mode mis à jour")}
              className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">
              {t.auto_advance ? "🤖 Auto ON" : "✋ Auto OFF"}
            </button>
            <div className="flex items-center gap-1">
              <input type="number" min={0} max={60} value={brk} onChange={(e) => setBrk(Number(e.target.value))}
                className="w-14 px-2 py-1.5 rounded-xl bg-secondary text-sm" />
              <button disabled={busy} onClick={() => rpc("admin_tournament_set_break", { _tid: t.id, _seconds: brk * 60 }, "Durée de pause mise à jour")}
                className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">Pause (min)</button>
            </div>
          </>
        )}

        {t.status === "paused" && (
          <button disabled={busy} onClick={() => rpc("admin_tournament_set_status", { _tid: t.id, _status: "running" }, "Tournoi repris")}
            className="px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold">▶ Reprendre</button>
        )}
        {!["finished", "cancelled"].includes(t.status) && (
          <button disabled={busy} onClick={() => rpc("admin_tournament_cancel", { _tid: t.id, _reason: null }, "Tournoi annulé")}
            className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold text-destructive">✕ Annuler</button>
        )}
      </div>
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
              {m.status === "running" && m.game_id && me && m.entrant_ids.includes(me.id) && (
                <Link to={slug === "ludo" ? "/game/$id" : "/domino/$id"} params={{ id: m.game_id }}
                  className="mt-2 block w-full py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold text-center">
                  Rejoindre
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
        <div key={pool.id} className="rounded-3xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <div className="flex items-center justify-between mb-2">
            <h3 className="font-bold text-sm">{pool.label}</h3>
            <span className="text-[10px] font-bold text-muted-foreground">
              {pool.status === "finished" ? "Terminée" : pool.status === "running" ? "En cours" : "À venir"}
            </span>
          </div>
          <div className="space-y-1">
            {players.map((p, i) => (
              <div key={p.id} className={`flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl ${
                me && p.entrant_id === me.id ? "bg-primary/10 font-bold" : ""
              }`}>
                <span className="w-5 text-xs text-muted-foreground">{i + 1}</span>
                <span className="flex-1 truncate">{byId[p.entrant_id]?.display_name ?? "?"}</span>
                {p.qualified && <span className="text-[10px] font-bold text-emerald-600">Qualifié</span>}
                <span className="text-xs text-muted-foreground">{p.played} j.</span>
                <span className="text-xs font-bold w-8 text-right">{p.points} pts</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function PlayersView({ entrants }: { entrants: any[] }) {
  if (!entrants.length) return <Empty text="Aucun inscrit pour l'instant." />;
  return (
    <div className="rounded-3xl bg-card p-3 shadow-[var(--shadow-soft)] space-y-1">
      {entrants.map((e, i) => (
        <div key={e.id} className="flex items-center gap-2 text-sm px-2 py-1.5">
          <span className="w-5 text-xs text-muted-foreground">{i + 1}</span>
          <span className="flex-1 truncate">{e.display_name}{e.is_bot && <span className="text-[10px] text-muted-foreground"> · bot</span>}</span>
          {e.final_rank === 1 && <Crown className="w-4 h-4 text-amber-500" />}
          {e.status === "eliminated" && <span className="text-[10px] text-muted-foreground">Éliminé</span>}
        </div>
      ))}
    </div>
  );
}

function RewardsView({ t, net, byId }: { t: any; net: number; byId: Record<string, any> }) {
  const pcts = [t.prize_1_pct, t.prize_2_pct, t.prize_3_pct].slice(0, t.winners_count);
  const icons = [<Crown key="1" className="w-4 h-4 text-amber-500" />, <Medal key="2" className="w-4 h-4 text-slate-400" />, <Medal key="3" className="w-4 h-4 text-orange-500" />];
  return (
    <div className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2">
      <div className="text-sm font-bold">Cagnotte : {net.toLocaleString("fr-FR")} Ar</div>
      {pcts.map((p: number, i: number) => (
        <div key={i} className="flex items-center gap-2 text-sm">
          {icons[i]}
          <span className="flex-1">{i + 1}{i === 0 ? "er" : "e"} place</span>
          <span className="font-bold">{Math.round(net * Number(p) / 100).toLocaleString("fr-FR")} Ar</span>
        </div>
      ))}
      {t.champion_entrant_id && (
        <div className="mt-2 rounded-2xl bg-amber-100 dark:bg-amber-950/40 p-3 text-center text-sm font-bold text-amber-700 dark:text-amber-300">
          🏆 Champion : {byId[t.champion_entrant_id]?.display_name ?? "—"}
        </div>
      )}
    </div>
  );
}

function Empty({ text }: { text: string }) {
  return <div className="rounded-3xl bg-card p-8 text-center text-sm text-muted-foreground shadow-[var(--shadow-soft)]">{text}</div>;
}
