import { createFileRoute, useParams, useNavigate, Link } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useState } from "react";
import { serverNow } from "@/lib/server-time";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useConfirm } from "@/components/ConfirmDialog";
import { toast } from "sonner";
import {
  ArrowLeft, Trophy, Users, Coins, Loader2, Play, LogOut, Crown,
  ChevronRight, Clock, Calendar, BarChart3, Timer, UserCheck,
  Hourglass, AlertCircle,
} from "lucide-react";
import { StatusPill } from "./tournaments";

export const Route = createFileRoute("/_authenticated/tournaments_/$id")({
  component: TournamentDetail,
  head: () => ({
    meta: [
      { title: "Détail du tournoi — Lalao MADA" },
      { name: "description", content: "Suivez votre tournoi Lalao MADA : bracket, matchs, classement et récompenses en direct." },
      { property: "og:title", content: "Détail du tournoi — Lalao MADA" },
      { property: "og:description", content: "Bracket, matchs et récompenses en direct." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
});

const GAMES: Record<string, { emoji: string; label: string }> = {
  ludo: { emoji: "🎲", label: "Ludo" },
  domino: { emoji: "🁣", label: "Domino" },
};

/** Label lisible pour un round de phase finale, basé sur le nombre de matchs. */
function roundLabel(matchCount: number, phase: string): string {
  if (phase === "third_place") return "Petite finale";
  if (phase === "pool") return "Poules";
  const map: Record<number, string> = {
    128: "128ème de finale",
    64: "64ème de finale",
    32: "32ème de finale",
    16: "16ème de finale",
    8: "8ème de finale",
    4: "Quart de finale",
    2: "Demi-finale",
    1: "Finale",
  };
  if (!map[matchCount]) {
    const exp = Math.log2(matchCount);
    if (Number.isInteger(exp)) {
      const playersInRound = matchCount * 2;
      return playersInRound >= 256 ? `${playersInRound}ème de finale` : map[playersInRound] ?? `Tour`;
    }
    return `Tour`;
  }
  return map[matchCount];
}

/** Label for elimination round */
function eliminatedRoundLabel(round: number | null, format: string, totalRounds: number): string {
  if (!round) return "Éliminé";
  if (format === "pools" && round === 1) return "Élimé en poules";
  const fromEnd = totalRounds - round;
  const map: Record<number, string> = {
    0: "Finaliste",
    1: "Demi-finaliste",
    2: "Quart de finaliste",
    3: "8ème de finaliste",
    4: "16ème de finaliste",
    5: "32ème de finaliste",
  };
  return map[fromEnd] ?? `Éliminé au tour ${round}`;
}

type State = {
  tournament: any;
  entrants: any[];
  waitlist: any[];
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
    const iv = setInterval(load, 10000);
    return () => { supabase.removeChannel(ch); clearInterval(iv); };
  }, [id, load]);

  const t = st?.tournament;
  const entrants = st?.entrants ?? [];
  const matches = st?.matches ?? [];
  const byId = useMemo(() => Object.fromEntries(entrants.map((e) => [e.id, e])), [entrants]);
  const me = useMemo(() => entrants.find((e) => e.user_id === user?.id), [entrants, user?.id]);
  const waitlist = st?.waitlist ?? [];
  const meWaitlist = useMemo(() => waitlist.find((w: any) => w.user_id === user?.id), [waitlist, user?.id]);
  const myMatch = useMemo(
    () => matches.find((m) => m.status === "running" && me && m.entrant_ids.includes(me.id)),
    [matches, me],
  );

  useEffect(() => {
    if (myMatch && myMatch.game_id) {
      const target = t?.game_slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id";
      navigate({ to: target, params: { id: myMatch.game_id } });
    }
  }, [myMatch?.id]);

  const netPrize = t
    ? Number(t.entry_fee_ar) > 0
      ? Math.round(Number(t.prize_pool_ar) * (100 - Number(t.platform_pct)) / 100 + Number(t.admin_prize_pool_ar))
      : Number(t.admin_prize_pool_ar)
    : 0;

  const myNextMatch = useMemo(
    () => matches.find((m) => m.status === "scheduled" && me && m.entrant_ids.includes(me.id)),
    [matches, me],
  );

  const myStats = useMemo(() => {
    if (!me || !matches.length) return null;
    const myMatches = matches.filter((m) => me && m.entrant_ids.includes(me.id) && m.status === "finished");
    const wins = myMatches.filter((m) => m.winner_id === me.id).length;
    const losses = myMatches.filter((m) => m.loser_id === me.id).length;
    const draws = myMatches.filter((m) => m.is_draw && m.entrant_ids.includes(me.id)).length;
    return { played: myMatches.length, wins, losses, draws, rank: me.final_rank };
  }, [me, matches]);

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
  const isKnockout = t.format !== "pools";
  const hasMatches = matches.length > 0;
  const isPaid = Number(t.entry_fee_ar) > 0;

  return (
    <div className="p-4 space-y-4 pb-24">
      <button onClick={() => navigate({ to: "/tournaments" })} className="inline-flex items-center gap-1 text-sm font-semibold text-muted-foreground">
        <ArrowLeft className="w-4 h-4" /> Tournois
      </button>

      {/* ─────────────── Carte principale ─────────────── */}
      <section className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3">
        {/* En-tête */}
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
            <div className="flex items-center gap-2 mt-1">
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${isPaid ? "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300" : "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"}`}>
                {isPaid ? "💰 Payant" : "🎁 Gratuit"}
              </span>
            </div>
          </div>
        </div>

        {t.description && <p className="text-sm text-muted-foreground">{t.description}</p>}

        {/* Stats */}
        <div className="grid grid-cols-3 gap-2">
          <Info icon={<Trophy className="w-4 h-4" />} label="Cagnotte" value={`${netPrize.toLocaleString("fr-FR")} Ar`} />
          <Info icon={<Coins className="w-4 h-4" />} label="Inscription" value={isPaid ? `${Number(t.entry_fee_ar).toLocaleString("fr-FR")} Ar` : "Gratuit"} />
          <Info icon={<Users className="w-4 h-4" />} label="Joueurs" value={`${entrants.length}/${t.max_players}`} />
        </div>

        {/* Barre de progression */}
        <div className="flex items-center gap-1">
          {visibleSteps.map(([label, done, current]) => (
            <div key={label} className="flex-1 text-center">
              <div className={`h-2 rounded-full transition-colors ${done ? "bg-emerald-500" : current ? "bg-amber-500" : "bg-secondary"}`} />
              <span className={`text-[10px] font-semibold mt-1 block ${current ? "text-amber-600" : done ? "text-emerald-600" : "text-muted-foreground"}`}>{label}</span>
            </div>
          ))}
        </div>

        {/* ─────────────── TIMER PANEL ─────────────── */}
        <TimerPanel t={t} myMatch={myMatch} me={me} />

        {/* Étape actuelle */}
        {t.status === "running" && (
          <div className="rounded-2xl bg-primary/10 p-3 space-y-1">
            <div className="flex items-center gap-2">
              <Calendar className="w-4 h-4 text-primary" />
              <span className="text-xs font-bold text-primary">
                {t.stage === "pools" ? "Phase de poules" : t.stage === "finals" ? "Phase finale" : t.stage === "done" ? "Terminé" : `Étape : ${t.stage}`}
              </span>
            </div>
            {t.current_round > 0 && (
              <div className="text-[11px] text-muted-foreground">
                {t.format === "pools" && t.stage === "pools" ? `Poule en cours` : roundLabel(matches.filter((m) => m.round === t.current_round && m.phase !== "pool").length, "final")}
              </div>
            )}
          </div>
        )}

        {/* Champion (si terminé) */}
        {t.status === "finished" && entrants.find((e) => e.final_rank === 1) && (
          <div className="rounded-2xl bg-gradient-to-r from-amber-50 to-amber-100 dark:from-amber-950/30 dark:to-amber-900/20 p-4 space-y-2 text-center">
            <Crown className="w-10 h-10 text-amber-500 mx-auto" />
            <div>
              <div className="text-lg font-extrabold text-amber-700 dark:text-amber-400">
                {entrants.find((e) => e.final_rank === 1)?.display_name}
              </div>
              <div className="text-xs font-bold text-amber-600 uppercase">Champion du tournoi</div>
            </div>
            {netPrize > 0 && (
              <div className="text-sm font-bold text-amber-700 dark:text-amber-400">
                Gagne {netPrize.toLocaleString("fr-FR")} Ar
              </div>
            )}
          </div>
        )}

        {/* Mon statut (éliminé) */}
        {me && me.status === "eliminated" && t.status === "running" && (
          <div className="rounded-2xl bg-secondary/60 p-3 text-center text-sm space-y-1">
            <span className="text-destructive font-bold">Vous avez été éliminé</span>
            {me.eliminated_round && (
              <div className="text-[11px] text-muted-foreground">
                {eliminatedRoundLabel(me.eliminated_round, t.format, t.total_rounds ?? 0)}
                {me.final_rank ? ` — ${me.final_rank}e place` : ""}
              </div>
            )}
            <div className="text-[11px] text-muted-foreground">Vous pouvez continuer à suivre le tournoi en spectateur.</div>
          </div>
        )}

        {/* Mon résultat final */}
        {me && t.status === "finished" && me.final_rank && (
          <div className={`rounded-2xl p-3 text-center text-sm space-y-1 ${me.final_rank === 1 ? "bg-amber-100 dark:bg-amber-950/40" : "bg-secondary/60"}`}>
            <span className="font-bold">
              {me.final_rank === 1 ? "🏆 Vous avez gagné le tournoi !" : `Vous terminez ${me.final_rank}e`}
            </span>
            {netPrize > 0 && me.final_rank <= t.winners_count && (
              <div className="text-[11px] text-amber-600 font-semibold">
                Gain : {Math.round(netPrize * (me.final_rank === 1 ? t.prize_1_pct : me.final_rank === 2 ? t.prize_2_pct : me.final_rank === 3 ? t.prize_3_pct : t.prize_4_pct ?? 0) / 100).toLocaleString("fr-FR")} Ar
              </div>
            )}
          </div>
        )}

        {/* Mon prochain match */}
        {myNextMatch && !myMatch && t.status === "running" && (
          <div className="rounded-2xl bg-amber-100 dark:bg-amber-950/30 p-3 space-y-2">
            <div className="flex items-center gap-2">
              <Clock className="w-4 h-4 text-amber-600" />
              <span className="text-xs font-bold text-amber-700 dark:text-amber-300">Votre prochain match</span>
            </div>
            <div className="text-[11px] text-muted-foreground">
              {myNextMatch.phase === "pool" ? "Match de poule" : myNextMatch.phase === "third_place" ? "Petite finale" : roundLabel(matches.filter((m) => m.round === myNextMatch.round && m.phase !== "pool").length, myNextMatch.phase)}
            </div>
            <div className="text-[11px] font-semibold">
              Adversaire : {myNextMatch.entrant_ids.filter((eid: string) => eid !== me.id).map((eid: string) => byId[eid]?.display_name ?? "En attente").join(" vs ")}
            </div>
          </div>
        )}

        {/* Mes résultats */}
        {me && myStats && myStats.played > 0 && (
          <div className="rounded-2xl bg-secondary/40 p-3">
            <div className="flex items-center gap-2 mb-1.5">
              <BarChart3 className="w-4 h-4 text-muted-foreground" />
              <span className="text-[11px] font-bold text-muted-foreground uppercase">Mes résultats</span>
            </div>
            <div className="grid grid-cols-4 gap-2 text-center">
              <Stat n={myStats.played} label="Matchs" />
              <Stat n={myStats.wins} label="Victoires" color="text-emerald-600" />
              <Stat n={myStats.losses} label="Défaites" color="text-destructive" />
              <Stat n={myStats.rank ?? "-"} label="Rang" color="text-amber-600" />
            </div>
          </div>
        )}

        {/* Phase en cours */}
        {t.status === "running" && <PhaseBanner t={t} matches={matches} entrants={entrants} />}

        {/* Bouton d'action principal */}
        {myMatch ? (
          <Link to={t.game_slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id"}
            params={{ id: myMatch.game_id }}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-2 animate-pulse">
            <Play className="w-4 h-4" /> Rejoindre mon match
          </Link>
        ) : t.status === "open" && me ? (
          <div className="space-y-2">
            {t.check_in_opened_at && !me.checked_in && me.status === "active" && (
              <button onClick={() => rpc("tournament_check_in", { _tid: id }, "✅ Check-in confirmé !")} disabled={busy}
                className="w-full py-3 rounded-2xl bg-amber-500 text-white font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-60">
                ✋ Je suis prêt !
              </button>
            )}
            {t.check_in_opened_at && me.checked_in && me.status === "active" && (
              <div className="w-full py-3 rounded-2xl bg-emerald-100 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300 text-center text-sm font-bold">
                ✅ Check-in confirmé — en attente du début
              </div>
            )}
            <button onClick={unregister} disabled={busy} className="w-full py-3 rounded-2xl bg-secondary text-secondary-foreground font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-60">
              <LogOut className="w-4 h-4" /> Annuler mon inscription
            </button>
          </div>
        ) : t.status === "open" && !me ? (
          meWaitlist ? (
            <div className="w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground">
              ⏳ Liste d'attente — position {meWaitlist.position}
            </div>
          ) : (
            <button onClick={register} disabled={busy} className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-60">
              {entrants.length >= t.max_players ? "S'inscrire (liste d'attente)" : "S'inscrire"}
            </button>
          )
        ) : me && me.status === "active" && t.status === "running" ? (
          <div className="w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground">
            ⏳ En attente de votre prochain match…
          </div>
        ) : null}

        {waitlist.length > 0 && t.status === "open" && (
          <div className="rounded-2xl bg-secondary/40 p-2.5 text-[11px] text-muted-foreground">
            📋 {waitlist.length} joueur(s) en liste d'attente
          </div>
        )}

        {isAdmin && <AdminBar t={t} busy={busy} rpc={rpc} />}
      </section>

      {/* ═══════════════════════════════════════════════════
          VUE UNIFIÉE — TOUT SUR UNE SEULE PAGE
          Bracket + Poules + Joueurs + Récompenses + Stats
          ═══════════════════════════════════════════════════ */}
      <div className="space-y-4">
        {/* POULES (si format pools) */}
        {t.format === "pools" && st?.pools && st.pools.length > 0 && (
          <UnifiedSection title="🏊 Poules" icon={<span className="text-base">🏊</span>}>
            <PoolsView pools={st.pools} byId={byId} me={me} matches={matches} />
          </UnifiedSection>
        )}

        {/* BRACKET — TOUS LES TOURS EN UNE VUE */}
        {hasMatches && (
          <UnifiedSection title="🏆 Tableau des tours" icon={<Trophy className="w-4 h-4" />}>
            <BracketView matches={matches} byId={byId} me={me} slug={t.game_slug} currentRound={t.current_round} />
          </UnifiedSection>
        )}

        {/* JOUEURS — QUALIFIÉS / ÉLIMINÉS / LISTE D'ATTENTE */}
        <UnifiedSection title="👥 Participants" icon={<Users className="w-4 h-4" />}>
          <PlayersView entrants={entrants} waitlist={waitlist} t={t} />
        </UnifiedSection>

        {/* RÉCOMPENSES */}
        <UnifiedSection title="💰 Récompenses" icon={<Trophy className="w-4 h-4" />}>
          <RewardsView t={t} net={netPrize} byId={byId} />
        </UnifiedSection>

        {/* STATS */}
        <UnifiedSection title="📊 Statistiques" icon={<BarChart3 className="w-4 h-4" />}>
          <StatsView t={t} entrants={entrants} matches={matches} me={me} byId={byId} />
        </UnifiedSection>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   UNIFIED SECTION — carte repliable pour la vue une-page
   ═══════════════════════════════════════════════════════════ */
function UnifiedSection({ title, icon, children }: { title: string; icon: React.ReactNode; children: React.ReactNode }) {
  const [open, setOpen] = useState(true);
  return (
    <div className="rounded-3xl bg-card shadow-[var(--shadow-soft)] overflow-hidden">
      <button onClick={() => setOpen(!open)}
        className="w-full flex items-center gap-2 px-4 py-3 text-left">
        <span className="text-muted-foreground">{icon}</span>
        <span className="text-sm font-bold flex-1">{title}</span>
        <ChevronRight className={`w-4 h-4 text-muted-foreground transition-transform ${open ? "rotate-90" : ""}`} />
      </button>
      {open && <div className="px-4 pb-4">{children}</div>}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   TIMER PANEL — tous les timers du tournoi en un seul panneau
   ═══════════════════════════════════════════════════════════ */
function TimerPanel({ t, myMatch, me }: { t: any; myMatch: any; me: any }) {
  // 1. Check-in timer
  const checkInLeft = useCountdown(
    t.check_in_opened_at
      ? new Date(new Date(t.check_in_opened_at).getTime() + t.check_in_minutes * 60000).toISOString()
      : null
  );
  const checkInActive = t.check_in_opened_at && t.status === "open" && checkInLeft > 0;

  // 2. Break timer
  const breakLeft = useCountdown(t.break_until);
  const breakActive = t.break_until && breakLeft > 0;

  // 3. My match lobby/deadline timer
  const matchDeadlineLeft = useCountdown(myMatch?.deadline_at);
  const matchActive = myMatch && myMatch.status === "running" && matchDeadlineLeft > 0;

  // 4. Next round start (if break is active, show when next round starts)
  const anyTimers = checkInActive || breakActive || matchActive;
  if (!anyTimers) return null;

  return (
    <div className="rounded-2xl border border-primary/30 bg-primary/5 p-3 space-y-2">
      <div className="flex items-center gap-1.5 text-[11px] font-bold text-primary uppercase">
        <Timer className="w-3.5 h-3.5" /> Chronomètres en cours
      </div>

      {/* Check-in countdown */}
      {checkInActive && (
        <TimerRow
          icon={<UserCheck className="w-4 h-4 text-amber-600" />}
          label="Check-in ouvert"
          sub={`${t.check_in_minutes} min pour confirmer`}
          seconds={checkInLeft}
          color="amber"
        />
      )}

      {/* Break countdown */}
      {breakActive && (
        <TimerRow
          icon={<Hourglass className="w-4 h-4 text-blue-600" />}
          label="Pause entre les phases"
          sub={`Prochaine phase dans ${fmt(breakLeft)}`}
          seconds={breakLeft}
          color="blue"
        />
      )}

      {/* My match lobby countdown */}
      {matchActive && (
        <TimerRow
          icon={<AlertCircle className="w-4 h-4 text-red-600" />}
          label="Votre match est en cours !"
          sub={matchDeadlineLeft < 60 ? "⚠ Dernières secondes !" : `Temps restant : ${fmt(matchDeadlineLeft)}`}
          seconds={matchDeadlineLeft}
          color="red"
        />
      )}
    </div>
  );
}

function TimerRow({ icon, label, sub, seconds, color }: {
  icon: React.ReactNode; label: string; sub: string; seconds: number; color: "amber" | "blue" | "red";
}) {
  const colorClasses = {
    amber: "bg-amber-100 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300",
    blue: "bg-blue-100 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300",
    red: "bg-red-100 dark:bg-red-950/40 text-red-700 dark:text-red-300",
  };
  const pct = Math.min(100, (seconds / 600) * 100); // assume max 10 min for visual

  return (
    <div className={`rounded-xl ${colorClasses[color]} p-2.5 space-y-1`}>
      <div className="flex items-center gap-2">
        {icon}
        <span className="text-xs font-bold flex-1">{label}</span>
        <span className="text-sm font-bold tabular-nums">{fmt(seconds)}</span>
      </div>
      <div className="text-[10px] opacity-80">{sub}</div>
      <div className="h-1 rounded-full bg-black/10 overflow-hidden">
        <div className="h-full rounded-full bg-current opacity-60 transition-all" style={{ width: `${pct}%` }} />
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   BRACKET — TOUS LES TOURS EN UNE SEULE VUE
   ═══════════════════════════════════════════════════════════ */
function BracketView({ matches, byId, me, slug, currentRound }: {
  matches: any[]; byId: Record<string, any>; me: any; slug: string; currentRound: number;
}) {
  if (!matches.length) {
    return (
      <div className="rounded-3xl bg-card p-8 text-center space-y-2">
        <Trophy className="w-10 h-10 text-muted-foreground mx-auto opacity-50" />
        <p className="text-sm text-muted-foreground">Le tableau apparaîtra dès le démarrage du tournoi.</p>
      </div>
    );
  }

  const bracketMatches = matches.filter((m) => m.phase !== "pool");
  const poolMatches = matches.filter((m) => m.phase === "pool");
  const rounds = Array.from(new Set(bracketMatches.map((m) => m.round))).sort((a, b) => a - b);
  const thirdPlaceMatch = bracketMatches.find((m) => m.phase === "third_place");

  return (
    <div className="space-y-4">
      {/* Matchs de poule */}
      {poolMatches.length > 0 && (
        <div className="rounded-2xl bg-secondary/40 p-3 space-y-2">
          <h3 className="text-xs font-bold text-muted-foreground uppercase">Phase de poules</h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {poolMatches.map((m) => (
              <MatchCard key={m.id} m={m} byId={byId} me={me} slug={slug} compact />
            ))}
          </div>
        </div>
      )}

      {/* TOUS LES TOURS — un par un, en vertical */}
      {rounds.map((r) => {
        const roundMatches = bracketMatches.filter((m) => m.round === r && m.phase !== "third_place");
        if (roundMatches.length === 0) return null;
        const label = roundLabel(roundMatches.length, roundMatches[0]?.phase ?? "final");
        const isCurrent = r === currentRound;
        const finished = roundMatches.filter((m) => m.status === "finished").length;
        const live = roundMatches.filter((m) => m.status === "running").length;
        const waiting = roundMatches.filter((m) => m.status === "scheduled").length;

        return (
          <div key={r} className="space-y-2">
            {/* En-tête du round */}
            <div className={`rounded-2xl px-3 py-2 flex items-center justify-between ${isCurrent ? "bg-amber-100 dark:bg-amber-950/40" : "bg-secondary/60"}`}>
              <span className={`text-sm font-bold ${isCurrent ? "text-amber-700 dark:text-amber-300" : "text-muted-foreground"}`}>
                {isCurrent && <span className="inline-block w-2 h-2 rounded-full bg-amber-500 animate-pulse mr-1.5" />}
                {label}
              </span>
              <span className="text-[10px] font-semibold text-muted-foreground">
                {finished > 0 && <span className="text-emerald-600">{finished} fini{finished > 1 ? "s" : ""} · </span>}
                {live > 0 && <span className="text-amber-600">{live} live · </span>}
                {waiting > 0 && <span>{waiting} en attente</span>}
                {finished === roundMatches.length && <span className="text-emerald-600">✓ Terminé</span>}
              </span>
            </div>

            {/* Matchs du round — en grille */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
              {roundMatches.map((m) => (
                <MatchCard key={m.id} m={m} byId={byId} me={me} slug={slug} />
              ))}
            </div>
          </div>
        );
      })}

      {/* Petite finale */}
      {thirdPlaceMatch && (
        <div className="space-y-2">
          <div className="rounded-2xl px-3 py-2 text-center bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-900/30">
            <span className="text-sm font-bold text-amber-700 dark:text-amber-400">🥉 Petite finale</span>
          </div>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            <MatchCard m={thirdPlaceMatch} byId={byId} me={me} slug={slug} />
          </div>
        </div>
      )}

      {/* Légende */}
      <div className="flex flex-wrap gap-3 px-1 text-[10px] text-muted-foreground">
        <LegendDot color="bg-emerald-500" label="Gagnant" />
        <LegendDot color="bg-amber-500" label="En cours" />
        <LegendDot color="bg-secondary" label="À venir" />
        <LegendDot color="bg-red-400" label="Perdant" />
      </div>
    </div>
  );
}

function MatchCard({ m, byId, me, slug, compact }: {
  m: any; byId: Record<string, any>; me: any; slug: string; compact?: boolean;
}) {
  const players = m.entrant_ids.map((eid: string) => byId[eid]);
  const winnerId = m.winner_entrant_id;
  const isRunning = m.status === "running";
  const isFinished = m.status === "finished";
  const isMyMatch = me && m.entrant_ids.includes(me.id);

  // Deadline countdown for running matches
  const deadlineLeft = useCountdown(m.status === "running" ? m.deadline_at : null);

  return (
    <div className={`rounded-2xl border p-2.5 transition-all ${
      isMyMatch && isRunning ? "border-primary shadow-md scale-[1.02]" :
      isRunning ? "border-amber-300 dark:border-amber-700" :
      "border-border"
    } ${compact ? "" : "shadow-[var(--shadow-soft)]"}`}>
      {/* N° match + statut */}
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-[9px] font-bold text-muted-foreground">
          {m.phase === "third_place" ? "3e place" : `M${m.match_no ?? ""}`}
        </span>
        <MatchPill m={m} />
      </div>

      {/* Joueurs */}
      {players.map((p: any, i: number) => (
        <div key={i}>
          {i > 0 && (
            <div className="flex items-center gap-1 py-0.5">
              <div className="flex-1 border-t border-dashed border-border" />
              <span className="text-[9px] font-bold text-muted-foreground px-1">VS</span>
              <div className="flex-1 border-t border-dashed border-border" />
            </div>
          )}
          <PlayerRow
            name={p?.display_name ?? "À déterminer"}
            isWinner={winnerId && winnerId === p?.id}
            isLoser={isFinished && winnerId && winnerId !== p?.id && p}
            isMyRow={me?.id === p?.id}
          />
        </div>
      ))}

      {m.entrant_ids.length < 2 && (
        <div className="text-[11px] text-muted-foreground italic px-1.5 py-1">
          En attente du tirage...
        </div>
      )}

      {/* Deadline countdown for running matches */}
      {isRunning && deadlineLeft > 0 && (
        <div className={`mt-1.5 flex items-center justify-center gap-1 text-[10px] font-bold rounded-lg py-1 ${
          deadlineLeft < 60 ? "bg-red-100 text-red-700 dark:bg-red-950/40 dark:text-red-300" :
          "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300"
        }`}>
          <Clock className="w-3 h-3" />
          <span className="tabular-nums">{fmt(deadlineLeft)}</span>
        </div>
      )}

      {/* Forfait / timeout */}
      {isFinished && !winnerId && (
        <div className="mt-1 text-[9px] text-muted-foreground italic text-center">
          Match résolu (forfait/timeout)
        </div>
      )}

      {/* Lien rejoindre */}
      {isRunning && m.game_id && me && m.entrant_ids.includes(me.id) && (
        <Link to={slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id"} params={{ id: m.game_id }}
          className="mt-2 block w-full py-1.5 rounded-xl bg-primary text-primary-foreground text-[11px] font-bold text-center">
          ▶ Rejoindre
        </Link>
      )}
    </div>
  );
}

function PlayerRow({ name, isWinner, isLoser, isMyRow }: {
  name: string; isWinner?: boolean | "" | 0 | null; isLoser?: boolean | "" | 0 | null; isMyRow?: boolean;
}) {
  return (
    <div className={`flex items-center gap-1.5 rounded-lg px-1.5 py-1 ${
      isWinner ? "bg-emerald-50 dark:bg-emerald-950/30" : isLoser ? "opacity-50" : ""
    }`}>
      {isWinner ? <Crown className="w-3 h-3 text-amber-500 shrink-0" /> : <span className="w-3 h-3 shrink-0" />}
      <span className={`text-xs truncate flex-1 ${
        isWinner ? "font-bold text-emerald-700 dark:text-emerald-400" :
        isLoser ? "text-muted-foreground line-through" : "font-medium"
      } ${isMyRow ? "text-primary font-bold" : ""}`}>
        {name}
      </span>
      {isMyRow && <span className="text-[8px] font-bold text-primary shrink-0">VOUS</span>}
    </div>
  );
}

function LegendDot({ color, label }: { color: string; label: string }) {
  return (
    <div className="flex items-center gap-1">
      <span className={`w-2.5 h-2.5 rounded-full ${color}`} />
      <span>{label}</span>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   PHASE BANNER — résumé de la phase en cours
   ═══════════════════════════════════════════════════════════ */
function PhaseBanner({ t, matches, entrants }: { t: any; matches: any[]; entrants: any[] }) {
  const breakLeft = useCountdown(t.break_until);
  const active = entrants.filter((e) => e.status === "active").length;
  const round = matches.filter((m) => m.round === t.current_round && m.phase !== "pool");
  const done = round.filter((m) => m.status === "finished").length;
  const live = round.filter((m) => m.status === "running").length;
  const waiting = round.filter((m) => m.status === "scheduled").length;
  const matchCount = round.length;
  const firstPhase = round[0]?.phase ?? "final";
  const title = t.stage === "pools" ? "Phase de poules" : roundLabel(matchCount, firstPhase);

  return (
    <div className="rounded-2xl bg-secondary/60 p-3 space-y-2">
      <div className="flex items-center justify-between gap-2">
        <span className="text-sm font-bold flex items-center gap-1.5">
          <span className={`w-2 h-2 rounded-full ${live > 0 ? "bg-amber-500 animate-pulse" : "bg-muted-foreground"}`} />
          {title}
        </span>
        <span className="text-[11px] font-semibold text-muted-foreground">{active} en lice</span>
      </div>
      {round.length > 0 && (
        <>
          <div className="flex items-center gap-1.5 text-[11px] font-semibold">
            <span className="text-emerald-600">{done} fini{done > 1 ? "s" : ""}</span>
            <ChevronRight className="w-3 h-3 text-muted-foreground" />
            <span className="text-amber-600">{live} en cours</span>
            {waiting > 0 && (<>
              <ChevronRight className="w-3 h-3 text-muted-foreground" />
              <span className="text-muted-foreground">{waiting} en attente</span>
            </>)}
            <span className="ml-auto text-muted-foreground">{t.max_concurrent_matches ?? 8} max simultanés</span>
          </div>
          <div className="flex gap-0.5 h-1.5">
            {round.map((m, i) => (
              <div key={i} className={`flex-1 rounded-full ${
                m.status === "finished" ? "bg-emerald-500" : m.status === "running" ? "bg-amber-500" : "bg-secondary"
              }`} />
            ))}
          </div>
        </>
      )}
      {breakLeft > 0 && (
        <div className="rounded-xl bg-amber-100 dark:bg-amber-950/40 px-3 py-2 text-xs font-bold text-amber-700 dark:text-amber-300 flex items-center justify-between">
          <span>⏸ Pause avant la phase suivante</span>
          <span className="tabular-nums">{fmt(breakLeft)}</span>
        </div>
      )}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   ADMIN BAR
   ═══════════════════════════════════════════════════════════ */
function AdminBar({ t, busy, rpc }: { t: any; busy: boolean; rpc: (fn: string, a: any, ok: string) => void }) {
  const [bots, setBots] = useState(4);
  const [brk, setBrk] = useState(Math.round((t.break_seconds ?? 180) / 60));

  return (
    <div className="rounded-2xl border border-dashed border-border p-3 space-y-2">
      <div className="text-[11px] font-bold text-muted-foreground uppercase tracking-wide">Contrôles admin</div>
      <div className="flex flex-wrap gap-2">
        {t.status === "open" && (
          <>
            {Number(t.entry_fee_ar) === 0 && (
              <div className="flex items-center gap-1">
                <input type="number" min={1} max={64} value={bots} onChange={(e) => setBots(Number(e.target.value))}
                  className="w-14 px-2 py-1.5 rounded-xl bg-secondary text-sm text-center" />
                <button disabled={busy} onClick={() => rpc("admin_tournament_add_bots", { _tid: t.id, _count: bots }, `${bots} bots ajoutés`)}
                  className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">+ Bots</button>
              </div>
            )}
            <button disabled={busy} onClick={() => rpc("admin_tournament_open_check_in", { _tid: t.id }, "Check-in ouvert")}
              className="px-3 py-1.5 rounded-xl bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300 text-xs font-bold">✋ Check-in</button>
            <button disabled={busy} onClick={() => rpc("admin_tournament_start", { _tid: t.id }, "Tournoi démarré !")}
              className="px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold">▶ Démarrer</button>
          </>
        )}
        {t.status === "running" && (
          <>
            <button disabled={busy} onClick={() => rpc("admin_tournament_next_stage", { _tid: t.id }, "Phase suivante lancée")}
              className="px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold">⏭ Phase suivante</button>
            <button disabled={busy} onClick={() => rpc("admin_tournament_set_auto", { _tid: t.id, _auto: !t.auto_advance }, "Mode mis à jour")}
              className={`px-3 py-1.5 rounded-xl text-xs font-bold ${t.auto_advance ? "bg-primary/15 text-primary" : "bg-secondary"}`}>
              {t.auto_advance ? "⚡ Auto" : "✋ Manuel"}
            </button>
            <button disabled={busy} onClick={() => rpc("admin_tournament_set_status", { _tid: t.id, _status: "paused" }, "Tournoi en pause")}
              className="px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold">⏸ Pause</button>
            <div className="flex items-center gap-1">
              <input type="number" min={0} max={60} value={brk} onChange={(e) => setBrk(Number(e.target.value))}
                className="w-12 px-2 py-1.5 rounded-xl bg-secondary text-sm text-center" />
              <button disabled={busy} onClick={() => rpc("admin_tournament_set_break", { _tid: t.id, _seconds: brk * 60 }, "Pause mise à jour")}
                className="px-2.5 py-1.5 rounded-xl bg-secondary text-[11px] font-bold">min</button>
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

/* ═══════════════════════════════════════════════════════════
   POULES
   ═══════════════════════════════════════════════════════════ */
function PoolsView({ pools, byId, me, matches }: { pools: { pool: any; players: any[] }[]; byId: Record<string, any>; me: any; matches: any[] }) {
  if (!pools.length) return <p className="text-sm text-muted-foreground text-center py-4">Le tirage des poules aura lieu au démarrage.</p>;
  return (
    <div className="space-y-3">
      {pools.map(({ pool, players }) => {
        const poolMatches = matches.filter((m) => m.pool_id === pool.id);
        return (
          <div key={pool.id} className="rounded-2xl bg-secondary/40 p-3">
            <div className="flex items-center justify-between mb-3">
              <h3 className="font-bold text-sm flex items-center gap-2">
                <span className="w-7 h-7 rounded-lg bg-primary/15 text-primary grid place-items-center text-xs font-extrabold">{pool.label}</span>
                Poule {pool.label}
              </h3>
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${
                pool.status === "finished" ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300" :
                pool.status === "running" ? "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300" :
                "bg-secondary text-muted-foreground"
              }`}>
                {pool.status === "finished" ? "Terminée" : pool.status === "running" ? "En cours" : "À venir"}
              </span>
            </div>
            {/* Classement */}
            <div className="space-y-1 mb-3">
              {players.map((p, i) => (
                <div key={p.id} className={`flex items-center gap-2 text-sm px-2.5 py-2 rounded-xl ${
                  me && p.entrant_id === me.id ? "bg-primary/10 font-bold" : "bg-secondary/40"
                }`}>
                  <span className="w-5 text-xs text-muted-foreground font-bold">{i + 1}.</span>
                  <span className="flex-1 truncate">{byId[p.entrant_id]?.display_name ?? "?"}</span>
                  {p.qualified && <span className="text-[10px] font-bold text-emerald-600 px-1.5 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-950/40">Qualifié</span>}
                  <span className="text-xs text-muted-foreground">{p.played}j · {p.wins}V</span>
                  <span className="text-xs font-bold w-10 text-right">{p.points} pts</span>
                </div>
              ))}
            </div>
            {/* Matchs */}
            {poolMatches.length > 0 && (
              <div className="border-t border-border pt-2 space-y-1">
                <div className="text-[10px] font-bold text-muted-foreground uppercase mb-1">Matchs</div>
                {poolMatches.map((m) => (
                  <div key={m.id} className="flex items-center gap-1.5 text-[11px] px-2 py-1 rounded-lg bg-secondary/30">
                    {m.entrant_ids.map((eid: string, i: number) => {
                      const p = byId[eid];
                      const won = m.winner_entrant_id === eid;
                      return (
                        <span key={eid} className={`flex-1 truncate ${won ? "font-bold text-emerald-600" : m.status === "finished" ? "text-muted-foreground" : ""}`}>
                          {p?.display_name ?? "?"}
                        </span>
                      );
                    }).reduce((acc: any[], el: any, i: number) => {
                      if (i > 0) acc.push(<span key={`sep-${i}`} className="text-[9px] text-muted-foreground font-bold">vs</span>);
                      acc.push(el);
                      return acc;
                    }, [])}
                    <span className="shrink-0"><MatchPill m={m} /></span>
                  </div>
                ))}
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   PARTICIPANTS
   ═══════════════════════════════════════════════════════════ */
function PlayersView({ entrants, waitlist, t }: { entrants: any[]; waitlist: any[]; t: any }) {
  if (!entrants.length && (!waitlist || !waitlist.length)) return <p className="text-sm text-muted-foreground text-center py-4">Aucun inscrit.</p>;

  const active = entrants.filter((e) => e.status === "active");
  const eliminated = entrants.filter((e) => e.status === "eliminated").sort((a, b) => (b.eliminated_round ?? 0) - (a.eliminated_round ?? 0));

  return (
    <div className="space-y-3">
      {/* Champion */}
      {t.status === "finished" && (() => {
        const champ = entrants.find((e) => e.final_rank === 1);
        if (!champ) return null;
        return (
          <div className="rounded-2xl bg-gradient-to-r from-amber-50 to-amber-100 dark:from-amber-950/30 dark:to-amber-900/20 p-4 text-center space-y-2">
            <Crown className="w-8 h-8 text-amber-500 mx-auto" />
            <div className="text-base font-extrabold text-amber-700 dark:text-amber-400">{champ.display_name}</div>
            <div className="text-[10px] font-bold text-amber-600 uppercase">🏆 Champion du tournoi</div>
          </div>
        );
      })()}

      {/* En lice */}
      {active.length > 0 && (
        <div>
          <h3 className="text-xs font-bold text-emerald-600 uppercase mb-2 flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-emerald-500" /> En lice ({active.length})
          </h3>
          <div className="space-y-1">
            {active.map((e, i) => (
              <div key={e.id} className="flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl bg-secondary/40">
                <span className="w-5 text-xs text-muted-foreground">{i + 1}</span>
                <span className="flex-1 truncate font-medium">{e.display_name}</span>
                {e.is_bot && <span className="text-[10px] text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary">bot</span>}
                {e.final_rank === 1 && <Crown className="w-4 h-4 text-amber-500" />}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Éliminés */}
      {eliminated.length > 0 && (
        <div>
          <h3 className="text-xs font-bold text-muted-foreground uppercase mb-2 flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-muted-foreground" /> Éliminés ({eliminated.length})
          </h3>
          <div className="space-y-1">
            {eliminated.map((e, i) => (
              <div key={e.id} className="flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl opacity-60">
                <span className="w-5 text-xs text-muted-foreground">{i + 1}</span>
                <span className="flex-1 truncate">{e.display_name}</span>
                {e.is_bot && <span className="text-[10px] text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary">bot</span>}
                {e.final_rank && e.final_rank <= 4 && (
                  <span className="text-[10px] font-bold text-amber-600">{e.final_rank === 1 ? "🥇" : e.final_rank === 2 ? "🥈" : "🥉"}</span>
                )}
                {e.eliminated_round && (
                  <span className="text-[9px] text-muted-foreground shrink-0">{eliminatedRoundLabel(e.eliminated_round, t.format, t.total_rounds ?? 0)}</span>
                )}
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Liste d'attente */}
      {waitlist && waitlist.length > 0 && (
        <div>
          <h3 className="text-xs font-bold text-amber-600 uppercase mb-2 flex items-center gap-1">
            <Clock className="w-3 h-3" /> Liste d'attente ({waitlist.length})
          </h3>
          <div className="space-y-1">
            {waitlist.map((w) => (
              <div key={w.id} className="flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl bg-secondary/40">
                <span className="w-5 text-xs font-bold text-amber-600">{w.position}</span>
                <span className="flex-1 truncate">{w.display_name}</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   RÉCOMPENSES
   ═══════════════════════════════════════════════════════════ */
function RewardsView({ t, net }: { t: any; net: number; byId: Record<string, any> }) {
  const pcts = [t.prize_1_pct, t.prize_2_pct, t.prize_3_pct].slice(0, t.winners_count);
  const medals = ["🥇", "🥈", "🥉"];
  const labels = ["1er", "2e", "3e"];
  const isPaid = Number(t.entry_fee_ar) > 0;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-center gap-2">
        <span className={`text-[10px] font-bold px-2.5 py-1 rounded-full ${isPaid ? "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300" : "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"}`}>
          {isPaid ? "💰 Mode payant" : "🎁 Mode gratuit"}
        </span>
      </div>
      <div className="text-center py-2">
        <div className="text-3xl font-extrabold text-amber-600">{net.toLocaleString("fr-FR")} Ar</div>
        <div className="text-xs text-muted-foreground mt-1">{isPaid ? "Cagnotte nette (après commission)" : "Récompense offerte par l'organisateur"}</div>
      </div>
      <div className="space-y-2">
        {pcts.map((pct, i) => (
          <div key={i} className="flex items-center gap-3 rounded-2xl bg-secondary/60 px-4 py-3">
            <span className="text-2xl">{medals[i]}</span>
            <div className="flex-1">
              <div className="text-sm font-bold">{labels[i]} place</div>
              <div className="text-[11px] text-muted-foreground">{pct}% de la cagnotte</div>
            </div>
            <div className="text-lg font-bold text-amber-600">{Math.round(net * pct / 100).toLocaleString("fr-FR")} Ar</div>
          </div>
        ))}
      </div>
      <div className="rounded-2xl bg-secondary/40 p-3 space-y-1.5 text-[11px] text-muted-foreground">
        {isPaid && <Row label="Frais collectés" value={`${Number(t.prize_pool_ar).toLocaleString("fr-FR")} Ar`} />}
        {!isPaid && <Row label="Inscription" value="Gratuite" valueClass="text-emerald-600" />}
        <Row label="Cagnotte admin" value={`${Number(t.admin_prize_pool_ar).toLocaleString("fr-FR")} Ar`} />
        {isPaid && <Row label={`Commission (${t.platform_pct}%)`} value={`-${Math.round(Number(t.prize_pool_ar) * Number(t.platform_pct) / 100).toLocaleString("fr-FR")} Ar`} valueClass="text-destructive" />}
        <div className="flex justify-between pt-1 border-t border-border">
          <span className="font-bold">Net à distribuer</span>
          <span className="font-bold text-amber-600">{net.toLocaleString("fr-FR")} Ar</span>
        </div>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   STATS
   ═══════════════════════════════════════════════════════════ */
function StatsView({ t, entrants, matches, me, byId }: {
  t: any; entrants: any[]; matches: any[]; me: any; byId: Record<string, any>;
}) {
  const poolMatches = matches.filter((m) => m.phase === "pool" && m.status === "finished");
  const myMatches = me ? matches.filter((m) => m.entrant_ids.includes(me.id) && m.status === "finished") : [];
  const scorerMap: Record<string, { name: string; w: number; l: number; d: number; pts: number }> = {};
  poolMatches.forEach((m) => {
    m.entrant_ids.forEach((id: string) => {
      if (!scorerMap[id]) scorerMap[id] = { name: byId[id]?.display_name ?? "?", w: 0, l: 0, d: 0, pts: 0 };
      if (m.winner_id === id) scorerMap[id].w++;
      else if (m.loser_id === id) scorerMap[id].l++;
      else if (m.is_draw) scorerMap[id].d++;
    });
  });
  Object.values(scorerMap).forEach((s) => { s.pts = s.w * 3 + s.d * 1; });
  const topScorers = Object.entries(scorerMap).sort(([,a],[,b]) => b.pts - a.pts).slice(0, 10);
  const np = Number(t.entry_fee_ar) > 0
    ? Math.round(Number(t.prize_pool_ar || 0) * (100 - t.platform_pct) / 100 + Number(t.admin_prize_pool_ar || 0))
    : Number(t.admin_prize_pool_ar || 0);

  return (
    <div className="space-y-3">
      {/* Règles */}
      <div className="rounded-2xl bg-secondary/40 p-3 space-y-2">
        <h3 className="text-xs font-bold text-muted-foreground uppercase">Règles du tournoi</h3>
        <div className="grid grid-cols-2 gap-2 text-[11px]">
          <Row label="Commission" value={`${t.platform_pct}%`} />
          <Row label="Net distribué" value={`${np.toLocaleString("fr-FR")} Ar`} valueClass="text-emerald-600" />
          <Row label="Vainqueurs" value={`${t.winners_count}`} />
          <Row label="Matchs simultanés" value={`${t.max_concurrent_matches}`} />
          {t.game_slug === "domino" && <Row label="Mode domino" value={t.domino_scoring === "points" ? `Points (${t.target_score})` : "Élimination"} />}
          <Row label="Durée max match" value={`${Math.floor(t.max_match_duration_secs / 60)} min`} />
        </div>
      </div>

      {/* Répartition */}
      <div className="rounded-2xl bg-secondary/40 p-3 space-y-2">
        <h3 className="text-xs font-bold text-muted-foreground uppercase">Répartition des gains</h3>
        {[1, 2, 3].filter((r) => t.winners_count >= r).map((rank) => {
          const pct = rank === 1 ? t.prize_1_pct : rank === 2 ? t.prize_2_pct : t.prize_3_pct;
          const amount = Math.round(np * pct / 100);
          const medals = ["🥇", "🥈", "🥉"];
          return (
            <div key={rank} className="flex items-center justify-between text-sm">
              <span className="flex items-center gap-2">
                <span>{medals[rank - 1]}</span>
                <span className="font-semibold">{rank === 1 ? "Champion" : rank === 2 ? "Finaliste" : "3e place"}</span>
              </span>
              <span className="font-bold text-amber-600">{pct}% · {amount.toLocaleString("fr-FR")} Ar</span>
            </div>
          );
        })}
      </div>

      {/* Mes matchs */}
      {me && myMatches.length > 0 && (
        <div className="rounded-2xl bg-secondary/40 p-3 space-y-2">
          <h3 className="text-xs font-bold text-primary uppercase">Mes matchs ({myMatches.length})</h3>
          <div className="space-y-1.5">
            {myMatches.map((m) => {
              const won = m.winner_id === me.id;
              const opp = m.entrant_ids.filter((id: string) => id !== me.id).map((id: string) => byId[id]?.display_name ?? "?").join(" / ");
              return (
                <div key={m.id} className="flex items-center gap-2 text-[11px] px-2 py-1.5 rounded-xl bg-secondary/40">
                  <span className={`px-1.5 py-0.5 rounded-full font-bold ${won ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300" : m.is_draw ? "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300" : "bg-red-100 text-red-700 dark:bg-red-950/40 dark:text-red-300"}`}>
                    {won ? "GAGNÉ" : m.is_draw ? "NUL" : "PERDU"}
                  </span>
                  <span className="flex-1 truncate">vs {opp}</span>
                  <span className="text-muted-foreground">{m.phase === "pool" ? "Poule" : m.phase === "third_place" ? "3e pl." : roundLabel(matches.filter((mm) => mm.round === m.round && mm.phase !== "pool").length, "final")}</span>
                </div>
              );
            })}
          </div>
        </div>
      )}

      {/* Top scorers */}
      {topScorers.length > 0 && (
        <div className="rounded-2xl bg-secondary/40 p-3 space-y-2">
          <h3 className="text-xs font-bold text-muted-foreground uppercase">Classement (poules)</h3>
          <div className="space-y-1">
            {topScorers.map(([id, s], i) => (
              <div key={id} className="flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl bg-secondary/40">
                <span className={`w-5 text-xs font-bold ${i < 3 ? "text-amber-600" : "text-muted-foreground"}`}>{i + 1}</span>
                <span className="flex-1 truncate font-medium">{s.name}</span>
                <span className="text-[11px] text-emerald-600 font-bold">{s.w}V</span>
                <span className="text-[11px] text-destructive">{s.l}D</span>
                {s.d > 0 && <span className="text-[11px] text-amber-600">{s.d}N</span>}
                <span className="text-[11px] font-bold text-primary">{s.pts} pts</span>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   UTILITAIRES
   ═══════════════════════════════════════════════════════════ */
function Info({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) {
  return (
    <div className="rounded-2xl bg-secondary/60 p-2.5 text-center">
      <div className="flex justify-center text-muted-foreground mb-1">{icon}</div>
      <div className="text-[10px] text-muted-foreground">{label}</div>
      <div className="text-xs font-bold truncate">{value}</div>
    </div>
  );
}

function Stat({ n, label, color }: { n: number | string; label: string; color?: string }) {
  return (
    <div>
      <div className={`text-lg font-bold ${color ?? "text-foreground"}`}>{n}</div>
      <div className="text-[9px] text-muted-foreground">{label}</div>
    </div>
  );
}

function Row({ label, value, valueClass }: { label: string; value: string; valueClass?: string }) {
  return (
    <div className="flex justify-between">
      <span className="text-muted-foreground">{label}</span>
      <span className={`font-semibold ${valueClass ?? "text-foreground"}`}>{value}</span>
    </div>
  );
}

function MatchPill({ m }: { m: any }) {
  const map: Record<string, { l: string; c: string }> = {
    scheduled: { l: "À venir", c: "bg-secondary text-muted-foreground" },
    running: { l: "Live", c: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300" },
    finished: { l: "Fini", c: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300" },
    cancelled: { l: "Annulé", c: "bg-secondary text-muted-foreground" },
  };
  const s = map[m.status] ?? map.scheduled;
  return <span className={`px-1.5 py-0.5 rounded-full text-[9px] font-bold shrink-0 ${s.c}`}>{s.l}</span>;
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
  const m = Math.floor(s / 60);
  const sec = s % 60;
  if (m >= 60) return `${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}`;
  return `${m}:${String(sec).padStart(2, "0")}`;
}
