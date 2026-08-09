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
  Hourglass, AlertCircle, ListOrdered, CalendarClock, Settings,
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

function roundLabel(matchCount: number, phase: string): string {
  if (phase === "third_place") return "Petite finale";
  if (phase === "pool") return "Poules";
  const map: Record<number, string> = {
    128: "128ème de finale", 64: "64ème de finale", 32: "32ème de finale",
    16: "16ème de finale", 8: "8ème de finale",
    4: "Quart de finale", 2: "Demi-finale", 1: "Finale",
  };
  if (!map[matchCount]) {
    const exp = Math.log2(matchCount);
    if (Number.isInteger(exp)) {
      const p = matchCount * 2;
      return p >= 256 ? `${p}ème de finale` : map[p] ?? `Tour`;
    }
    return `Tour`;
  }
  return map[matchCount];
}

function eliminatedRoundLabel(round: number | null, format: string, totalRounds: number): string {
  if (!round) return "Éliminé";
  if (format === "pools" && round === 1) return "Élimé en poules";
  const fromEnd = totalRounds - round;
  const map: Record<number, string> = {
    0: "Finaliste", 1: "Demi-finaliste", 2: "Quart de finaliste",
    3: "8ème de finaliste", 4: "16ème de finaliste", 5: "32ème de finaliste",
  };
  return map[fromEnd] ?? `Éliminé au tour ${round}`;
}

/** Compute estimated start time for a scheduled match */
function estimateMatchStart(
  m: any,
  allMatches: any[],
  t: any,
  now: number,
): Date | null {
  // Already running or finished — no estimate needed
  if (m.status !== "scheduled") return null;

  const matchDur = (t.max_match_duration_secs ?? 1800) * 1000;
  const breakMs = (t.break_seconds ?? 600) * 1000;
  const lobbyMs = (t.lobby_minutes ?? 5) * 60 * 1000;

  // Matches in the same round
  const sameRound = allMatches.filter((mm) => mm.round === m.round && mm.phase === m.phase);
  const running = sameRound.filter((mm) => mm.status === "running");
  const maxConcurrent = t.max_concurrent_matches ?? 8;

  // If there are free slots, this match starts now
  if (running.length < maxConcurrent) return new Date(now);

  // All slots busy → estimate when the earliest running match finishes
  const earliestFinish = running
    .map((mm) => {
      const started = mm.started_at ? new Date(mm.started_at).getTime() : now;
      return started + matchDur;
    })
    .sort((a, b) => a - b)[0];

  return new Date(earliestFinish ?? now);
}

/** Estimate when the next round will start */
function estimateNextRoundStart(t: any, matches: any[], now: number): Date | null {
  const matchDur = (t.max_match_duration_secs ?? 1800) * 1000;
  const breakMs = (t.break_seconds ?? 600) * 1000;
  const lobbyMs = (t.lobby_minutes ?? 5) * 60 * 1000;

  const currentRoundMatches = matches.filter((m) => m.round === t.current_round && m.phase !== "pool");
  const running = currentRoundMatches.filter((m) => m.status === "running");
  const scheduled = currentRoundMatches.filter((m) => m.status === "scheduled");

  if (running.length === 0 && scheduled.length === 0) {
    // Round is done — next round starts after break + lobby
    return new Date(now + breakMs + lobbyMs);
  }

  // Find when all current round matches will finish
  const finishTimes: number[] = [];
  running.forEach((m) => {
    const started = m.started_at ? new Date(m.started_at).getTime() : now;
    finishTimes.push(started + matchDur);
  });
  scheduled.forEach((m) => {
    const est = estimateMatchStart(m, matches, t, now);
    if (est) finishTimes.push(est.getTime() + matchDur);
  });

  const lastFinish = Math.max(...finishTimes, now);
  return new Date(lastFinish + breakMs + lobbyMs);
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
  const [tab, setTab] = useState<"players" | "results" | "next">("players");

  const load = useCallback(async () => {
    const { data } = await (supabase.rpc as any)("tournament_state", { _tid: id });
    if (data) setSt(data as State);
    // Poll the engine to keep the tournament flowing (launch matches, check timeouts, advance phases)
    if (data?.tournament?.status === "running") {
      (supabase.rpc as any)("poll_tournament_engine", { _tid: id });
    }
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
  const isPaid = Number(t.entry_fee_ar) > 0;
  const hasMatches = matches.length > 0;
  const now = Date.now();

  // Current stage label (big subtitle)
  const stageLabel = (() => {
    if (t.status === "open") return "Inscriptions en cours";
    if (t.status === "finished") return "Tournoi terminé";
    if (t.status === "cancelled") return "Tournoi annulé";
    if (t.status === "paused") return "Tournoi en pause";
    if (t.stage === "pools") return "Phase de poules";
    if (t.stage === "finals") {
      const roundMatches = matches.filter((m) => m.round === t.current_round && m.phase !== "pool");
      return roundLabel(roundMatches.length, roundMatches[0]?.phase ?? "final");
    }
    return "En cours";
  })();

  return (
    <div className="min-h-screen flex flex-col pb-20">
      {/* ─────────────── HEADER — Tournament name + stage ─────────────── */}
      <div className="px-4 pt-4 pb-3">
        <button onClick={() => navigate({ to: "/tournaments" })}
          className="inline-flex items-center gap-1 text-sm font-semibold text-muted-foreground mb-3">
          <ArrowLeft className="w-4 h-4" /> Tournois
        </button>

        {/* Game badge + name */}
        <div className="flex items-start gap-3">
          <div className="w-12 h-12 rounded-2xl bg-secondary grid place-items-center text-2xl shrink-0">{g.emoji}</div>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <h1 className="text-xl font-extrabold truncate">{t.name}</h1>
              <StatusPill status={t.status} />
            </div>
            <div className="flex items-center gap-2 mt-1">
              <span className="text-xs text-muted-foreground">{g.label}</span>
              <span className={`text-[10px] font-bold px-2 py-0.5 rounded-full ${isPaid ? "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300" : "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"}`}>
                {isPaid ? "💰 Payant" : "🎁 Gratuit"}
              </span>
              <span className="text-xs text-muted-foreground">{t.format === "pools" ? "Poules + finale" : "Élimination directe"}</span>
            </div>
          </div>
        </div>

        {/* Big stage subtitle */}
        <div className="mt-3 rounded-2xl bg-primary/10 px-4 py-3 text-center">
          <div className="text-lg font-extrabold text-primary">{stageLabel}</div>
          {t.status === "running" && t.current_round > 0 && (
            <div className="text-[11px] text-muted-foreground mt-0.5">
              {entrants.filter((e) => e.status === "active").length} joueur(s) encore en lice
            </div>
          )}
        </div>

        {/* Quick stats row */}
        <div className="grid grid-cols-3 gap-2 mt-3">
          <Info icon={<Trophy className="w-4 h-4" />} label="Cagnotte" value={`${netPrize.toLocaleString("fr-FR")} Ar`} />
          <Info icon={<Coins className="w-4 h-4" />} label="Inscription" value={isPaid ? `${Number(t.entry_fee_ar).toLocaleString("fr-FR")} Ar` : "Gratuit"} />
          <Info icon={<Users className="w-4 h-4" />} label="Joueurs" value={`${entrants.length}/${t.max_players}`} />
        </div>
      </div>

      {/* ─────────────── TIMER PANEL ─────────────── */}
      <TimerPanel t={t} myMatch={myMatch} me={me} matches={matches} now={now} />

      {/* ─────────────── ACTION BUTTON ─────────────── */}
      <div className="px-4 py-2">
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
            <button onClick={unregister} disabled={busy}
              className="w-full py-3 rounded-2xl bg-secondary text-secondary-foreground font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-60">
              <LogOut className="w-4 h-4" /> Annuler mon inscription
            </button>
          </div>
        ) : t.status === "open" && !me ? (
          meWaitlist ? (
            <div className="w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground">
              ⏳ Liste d'attente — position {meWaitlist.position}
            </div>
          ) : (
            <button onClick={register} disabled={busy}
              className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-60">
              {entrants.length >= t.max_players ? "S'inscrire (liste d'attente)" : "S'inscrire"}
            </button>
          )
        ) : me && me.status === "active" && t.status === "running" ? (
          <div className="w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground">
            ⏳ En attente de votre prochain match…
          </div>
        ) : null}
      </div>

      {/* ─────────────── MY STATUS ─────────────── */}
      {me && me.status === "eliminated" && t.status === "running" && (
        <div className="mx-4 mb-2 rounded-2xl bg-secondary/60 p-3 text-center text-sm">
          <span className="text-destructive font-bold">Vous avez été éliminé</span>
          {me.eliminated_round && (
            <div className="text-[11px] text-muted-foreground mt-0.5">
              {eliminatedRoundLabel(me.eliminated_round, t.format, t.total_rounds ?? 0)}
              {me.final_rank ? ` — ${me.final_rank}e place` : ""}
            </div>
          )}
        </div>
      )}

      {/* Champion banner */}
      {t.status === "finished" && entrants.find((e) => e.final_rank === 1) && (
        <div className="mx-4 mb-2 rounded-2xl bg-gradient-to-r from-amber-50 to-amber-100 dark:from-amber-950/30 dark:to-amber-900/20 p-4 text-center space-y-2">
          <Crown className="w-10 h-10 text-amber-500 mx-auto" />
          <div className="text-lg font-extrabold text-amber-700 dark:text-amber-400">
            {entrants.find((e) => e.final_rank === 1)?.display_name}
          </div>
          <div className="text-xs font-bold text-amber-600 uppercase">Champion</div>
          {netPrize > 0 && <div className="text-sm font-bold text-amber-700 dark:text-amber-400">Gagne {netPrize.toLocaleString("fr-FR")} Ar</div>}
        </div>
      )}

      {/* Admin controls */}
      {isAdmin && <AdminBar t={t} busy={busy} rpc={rpc} />}

      {/* ─────────────── CONTENT AREA — 3 TABS ─────────────── */}
      <div className="flex-1 px-4 pt-2">
        {tab === "players" && <PlayersTab entrants={entrants} waitlist={waitlist} t={t} byId={byId} me={me} matches={matches} hasMatches={hasMatches} />}
        {tab === "results" && <ResultsTab matches={matches} byId={byId} me={me} t={t} />}
        {tab === "next" && <NextMatchesTab matches={matches} byId={byId} me={me} t={t} now={now} />}
      </div>

      {/* ─────────────── BOTTOM NAV — 3 TABS ─────────────── */}
      <div className="fixed bottom-0 left-0 right-0 z-50 bg-card border-t border-border">
        <div className="flex">
          <TabButton active={tab === "players"} onClick={() => setTab("players")}
            icon={<Users className="w-5 h-5" />} label="Joueurs" />
          <TabButton active={tab === "results"} onClick={() => setTab("results")}
            icon={<ListOrdered className="w-5 h-5" />} label="Résultats" />
          <TabButton active={tab === "next"} onClick={() => setTab("next")}
            icon={<CalendarClock className="w-5 h-5" />} label="Matchs suivants" />
        </div>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   BOTTOM TAB BUTTON
   ═══════════════════════════════════════════════════════════ */
function TabButton({ active, onClick, icon, label }: {
  active: boolean; onClick: () => void; icon: React.ReactNode; label: string;
}) {
  return (
    <button onClick={onClick}
      className={`flex-1 flex flex-col items-center gap-0.5 py-2.5 transition-colors ${active ? "text-primary" : "text-muted-foreground"}`}>
      {icon}
      <span className="text-[10px] font-bold">{label}</span>
    </button>
  );
}

/* ═══════════════════════════════════════════════════════════
   TIMER PANEL — all active timers
   ═══════════════════════════════════════════════════════════ */
function TimerPanel({ t, myMatch, me, matches, now }: {
  t: any; myMatch: any; me: any; matches: any[]; now: number;
}) {
  const checkInDeadline = t.check_in_opened_at
    ? new Date(new Date(t.check_in_opened_at).getTime() + (t.check_in_minutes ?? 15) * 60000).toISOString()
    : null;
  const checkInLeft = useCountdown(checkInDeadline);
  const checkInActive = t.check_in_opened_at && t.status === "open" && checkInLeft > 0;

  const breakLeft = useCountdown(t.break_until);
  const breakActive = t.break_until && breakLeft > 0;

  const matchDeadlineLeft = useCountdown(myMatch?.deadline_at);
  const matchActive = myMatch && myMatch.status === "running" && matchDeadlineLeft > 0;

  // Next round estimate
  const nextRoundStart = useMemo(() => {
    if (t.status !== "running" || breakActive || matchActive) return null;
    return estimateNextRoundStart(t, matches, now);
  }, [t, matches, now, breakActive, matchActive]);

  const nextRoundLeft = useCountdown(nextRoundStart?.toISOString());
  const nextRoundVisible = t.status === "running" && !breakActive && !matchActive && nextRoundLeft > 0 && matches.some((m) => m.status === "running" || m.status === "scheduled");

  if (!checkInActive && !breakActive && !matchActive && !nextRoundVisible) return null;

  return (
    <div className="mx-4 my-2 rounded-2xl border border-primary/30 bg-primary/5 p-3 space-y-2">
      <div className="flex items-center gap-1.5 text-[11px] font-bold text-primary uppercase">
        <Timer className="w-3.5 h-3.5" /> Chronomètres
      </div>

      {checkInActive && (
        <TimerRow icon={<UserCheck className="w-4 h-4 text-amber-600" />} label="Check-in ouvert"
          sub={`${t.check_in_minutes ?? 15} min pour confirmer`} seconds={checkInLeft} color="amber" />
      )}
      {breakActive && (
        <TimerRow icon={<Hourglass className="w-4 h-4 text-blue-600" />} label="Pause entre les phases"
          sub={`Prochaine phase dans ${fmt(breakLeft)}`} seconds={breakLeft} color="blue" />
      )}
      {matchActive && (
        <TimerRow icon={<AlertCircle className="w-4 h-4 text-red-600" />} label="Votre match est en cours !"
          sub={matchDeadlineLeft < 60 ? "⚠ Dernières secondes !" : `Temps restant : ${fmt(matchDeadlineLeft)}`}
          seconds={matchDeadlineLeft} color="red" />
      )}
      {nextRoundVisible && (
        <TimerRow icon={<CalendarClock className="w-4 h-4 text-purple-600" />} label="Prochaine phase estimée"
          sub={`Dans environ ${fmt(nextRoundLeft)}`} seconds={nextRoundLeft} color="purple" />
      )}
    </div>
  );
}

function TimerRow({ icon, label, sub, seconds, color }: {
  icon: React.ReactNode; label: string; sub: string; seconds: number;
  color: "amber" | "blue" | "red" | "purple";
}) {
  const cc: Record<string, string> = {
    amber: "bg-amber-100 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300",
    blue: "bg-blue-100 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300",
    red: "bg-red-100 dark:bg-red-950/40 text-red-700 dark:text-red-300",
    purple: "bg-purple-100 dark:bg-purple-950/40 text-purple-700 dark:text-purple-300",
  };
  const pct = Math.min(100, Math.max(5, (seconds / 1800) * 100));
  return (
    <div className={`rounded-xl ${cc[color]} p-2.5 space-y-1`}>
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
   TAB 1: JOUEURS — player list → matchups when tournament starts
   ═══════════════════════════════════════════════════════════ */
function PlayersTab({ entrants, waitlist, t, byId, me, matches, hasMatches }: {
  entrants: any[]; waitlist: any[]; t: any; byId: Record<string, any>; me: any; matches: any[]; hasMatches: boolean;
}) {
  // Before tournament starts → show full player list
  // After tournament starts → show matchups (who vs who)
  const tournamentStarted = t.status === "running" || t.status === "finished";
  const active = entrants.filter((e) => e.status === "active");
  const eliminated = entrants.filter((e) => e.status === "eliminated").sort((a, b) => (b.eliminated_round ?? 0) - (a.eliminated_round ?? 0));

  if (!tournamentStarted) {
    // ── PRE-TOURNAMENT: Full player list ──
    return (
      <div className="space-y-3">
        <div className="rounded-2xl bg-card p-4 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-muted-foreground uppercase mb-3">
            Joueurs inscrits ({entrants.length}/{t.max_players})
          </h3>
          <div className="space-y-1">
            {entrants.map((e, i) => (
              <div key={e.id} className={`flex items-center gap-2 text-sm px-2.5 py-2 rounded-xl ${me?.id === e.id ? "bg-primary/10 font-bold" : "bg-secondary/40"}`}>
                <span className="w-6 text-xs text-muted-foreground font-bold">{i + 1}</span>
                <span className="flex-1 truncate">{e.display_name}</span>
                {e.is_bot && <span className="text-[10px] text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary">bot</span>}
                {e.checked_in && <span className="text-[10px] font-bold text-emerald-600 px-1.5 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-950/40">✓</span>}
                {me?.id === e.id && <span className="text-[8px] font-bold text-primary">VOUS</span>}
              </div>
            ))}
          </div>
        </div>

        {waitlist.length > 0 && (
          <div className="rounded-2xl bg-card p-4 shadow-[var(--shadow-soft)]">
            <h3 className="text-xs font-bold text-amber-600 uppercase mb-2 flex items-center gap-1">
              <Clock className="w-3 h-3" /> Liste d'attente ({waitlist.length})
            </h3>
            <div className="space-y-1">
              {waitlist.map((w: any) => (
                <div key={w.id} className="flex items-center gap-2 text-sm px-2.5 py-2 rounded-xl bg-secondary/40">
                  <span className="w-6 text-xs font-bold text-amber-600">{w.position}</span>
                  <span className="flex-1 truncate">{w.display_name}</span>
                </div>
              ))}
            </div>
          </div>
        )}
      </div>
    );
  }

  // ── TOURNAMENT RUNNING: Show matchups ──
  const currentRoundMatches = matches.filter((m) => m.round === t.current_round && m.phase !== "pool" && m.status !== "finished");
  const poolMatches = matches.filter((m) => m.phase === "pool" && m.status !== "finished");
  const displayMatches = poolMatches.length > 0 ? poolMatches : currentRoundMatches;

  return (
    <div className="space-y-3">
      {/* Matchups for current phase */}
      {displayMatches.length > 0 && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-primary uppercase mb-3">
            {poolMatches.length > 0 ? "Matchs de poules" : "Matchs en cours"}
          </h3>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
            {displayMatches.map((m) => (
              <MatchupCard key={m.id} m={m} byId={byId} me={me} t={t} />
            ))}
          </div>
        </div>
      )}

      {/* Active players */}
      {active.length > 0 && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
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

      {/* Eliminated */}
      {eliminated.length > 0 && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-muted-foreground uppercase mb-2">
            Éliminés ({eliminated.length})
          </h3>
          <div className="space-y-1">
            {eliminated.map((e, i) => (
              <div key={e.id} className="flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl opacity-60">
                <span className="w-5 text-xs text-muted-foreground">{i + 1}</span>
                <span className="flex-1 truncate">{e.display_name}</span>
                {e.final_rank && e.final_rank <= 4 && (
                  <span className="text-[10px] font-bold text-amber-600">
                    {e.final_rank === 1 ? "🥇" : e.final_rank === 2 ? "🥈" : "🥉"}
                  </span>
                )}
                {e.eliminated_round && (
                  <span className="text-[9px] text-muted-foreground shrink-0">
                    {eliminatedRoundLabel(e.eliminated_round, t.format, t.total_rounds ?? 0)}
                  </span>
                )}
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

function MatchupCard({ m, byId, me, t }: { m: any; byId: Record<string, any>; me: any; t: any }) {
  const players = m.entrant_ids.map((eid: string) => byId[eid]);
  const isMyMatch = me && m.entrant_ids.includes(me.id);
  const isRunning = m.status === "running";

  return (
    <div className={`rounded-2xl border p-2.5 ${isMyMatch && isRunning ? "border-primary shadow-md" : "border-border"} ${isRunning ? "bg-amber-50 dark:bg-amber-950/20" : "bg-secondary/30"}`}>
      <div className="flex items-center justify-between mb-1.5">
        <span className="text-[9px] font-bold text-muted-foreground">
          {m.phase === "pool" ? "Poule" : m.phase === "third_place" ? "3e place" : `M${m.match_no ?? ""}`}
        </span>
        <MatchPill m={m} />
      </div>
      {players.map((p: any, i: number) => (
        <div key={i}>
          {i > 0 && <div className="flex items-center gap-1 py-0.5"><div className="flex-1 border-t border-dashed border-border" /><span className="text-[9px] font-bold text-muted-foreground px-1">VS</span><div className="flex-1 border-t border-dashed border-border" /></div>}
          <div className={`flex items-center gap-1.5 rounded-lg px-1.5 py-1 ${m.winner_entrant_id === p?.id ? "bg-emerald-50 dark:bg-emerald-950/30" : m.status === "finished" && m.winner_entrant_id && m.winner_entrant_id !== p?.id ? "opacity-50" : ""}`}>
            {m.winner_entrant_id === p?.id ? <Crown className="w-3 h-3 text-amber-500 shrink-0" /> : <span className="w-3 h-3 shrink-0" />}
            <span className={`text-xs truncate flex-1 ${m.winner_entrant_id === p?.id ? "font-bold text-emerald-700 dark:text-emerald-400" : m.status === "finished" && m.winner_entrant_id && m.winner_entrant_id !== p?.id ? "text-muted-foreground line-through" : "font-medium"} ${me?.id === p?.id ? "text-primary font-bold" : ""}`}>
              {p?.display_name ?? "À déterminer"}
            </span>
            {me?.id === p?.id && <span className="text-[8px] font-bold text-primary shrink-0">VOUS</span>}
          </div>
        </div>
      ))}
      {isRunning && m.game_id && me && m.entrant_ids.includes(me.id) && (
        <Link to={t.game_slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id"} params={{ id: m.game_id }}
          className="mt-2 block w-full py-1.5 rounded-xl bg-primary text-primary-foreground text-[11px] font-bold text-center">
          ▶ Rejoindre
        </Link>
      )}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   TAB 2: RÉSULTATS — all completed match results by round
   ═══════════════════════════════════════════════════════════ */
function ResultsTab({ matches, byId, me, t }: {
  matches: any[]; byId: Record<string, any>; me: any; t: any;
}) {
  const finished = matches.filter((m) => m.status === "finished");
  if (!finished.length) {
    return (
      <div className="rounded-2xl bg-card p-8 text-center shadow-[var(--shadow-soft)]">
        <Trophy className="w-10 h-10 text-muted-foreground mx-auto opacity-50" />
        <p className="text-sm text-muted-foreground mt-2">Aucun résultat pour l'instant.</p>
      </div>
    );
  }

  // Group by round
  const poolResults = finished.filter((m) => m.phase === "pool");
  const bracketResults = finished.filter((m) => m.phase !== "pool");
  const rounds = Array.from(new Set(bracketResults.map((m) => m.round))).sort((a, b) => a - b);
  const thirdPlace = bracketResults.find((m) => m.phase === "third_place");

  return (
    <div className="space-y-3">
      {/* Pool results */}
      {poolResults.length > 0 && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-muted-foreground uppercase mb-2">Phase de poules</h3>
          <div className="space-y-1.5">
            {poolResults.map((m) => <ResultRow key={m.id} m={m} byId={byId} me={me} />)}
          </div>
        </div>
      )}

      {/* Bracket results by round */}
      {rounds.map((r) => {
        const roundMatches = bracketResults.filter((m) => m.round === r && m.phase !== "third_place");
        if (!roundMatches.length) return null;
        const label = roundLabel(
          matches.filter((m) => m.round === r && m.phase !== "pool" && m.phase !== "third_place").length,
          roundMatches[0]?.phase ?? "final"
        );
        return (
          <div key={r} className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
            <h3 className="text-xs font-bold text-primary uppercase mb-2">{label}</h3>
            <div className="space-y-1.5">
              {roundMatches.map((m) => <ResultRow key={m.id} m={m} byId={byId} me={me} />)}
            </div>
          </div>
        );
      })}

      {/* Third place */}
      {thirdPlace && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-amber-600 uppercase mb-2">🥉 Petite finale</h3>
          <div className="space-y-1.5">
            <ResultRow m={thirdPlace} byId={byId} me={me} />
          </div>
        </div>
      )}
    </div>
  );
}

function ResultRow({ m, byId, me }: { m: any; byId: Record<string, any>; me: any }) {
  const winner = m.winner_entrant_id ? byId[m.winner_entrant_id] : null;
  const players = m.entrant_ids.map((eid: string) => byId[eid]).filter(Boolean);

  return (
    <div className="flex items-center gap-2 text-[11px] px-2.5 py-2 rounded-xl bg-secondary/40">
      <span className="text-[9px] font-bold text-muted-foreground w-6">M{m.match_no ?? ""}</span>
      <div className="flex-1 min-w-0">
        {players.map((p: any, i: number) => (
          <div key={i} className={`flex items-center gap-1 ${i > 0 ? "mt-0.5" : ""}`}>
            {m.winner_entrant_id === p?.id ? <Crown className="w-3 h-3 text-amber-500 shrink-0" /> : <span className="w-3 h-3 shrink-0" />}
            <span className={`truncate ${m.winner_entrant_id === p?.id ? "font-bold text-emerald-700 dark:text-emerald-400" : m.is_draw ? "" : "text-muted-foreground line-through"} ${me?.id === p?.id ? "text-primary" : ""}`}>
              {p?.display_name ?? "?"}
            </span>
            {me?.id === p?.id && <span className="text-[8px] font-bold text-primary shrink-0">VOUS</span>}
          </div>
        ))}
      </div>
      {m.is_draw ? (
        <span className="text-[9px] font-bold text-amber-600 px-1.5 py-0.5 rounded-full bg-amber-100 dark:bg-amber-950/40 shrink-0">NUL</span>
      ) : winner ? (
        <span className="text-[9px] font-bold text-emerald-600 px-1.5 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-950/40 shrink-0">GAGNÉ</span>
      ) : (
        <span className="text-[9px] font-bold text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary shrink-0">FORFAIT</span>
      )}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   TAB 3: MATCHS SUIVANTS — upcoming matches with precise times
   ═══════════════════════════════════════════════════════════ */
function NextMatchesTab({ matches, byId, me, t, now }: {
  matches: any[]; byId: Record<string, any>; me: any; t: any; now: number;
}) {
  const scheduled = matches.filter((m) => m.status === "scheduled");
  const running = matches.filter((m) => m.status === "running");
  const hasMatches = matches.length > 0;

  if (!hasMatches) {
    return (
      <div className="rounded-2xl bg-card p-8 text-center shadow-[var(--shadow-soft)]">
        <CalendarClock className="w-10 h-10 text-muted-foreground mx-auto opacity-50" />
        <p className="text-sm text-muted-foreground mt-2">Les matchs apparaîtront au démarrage du tournoi.</p>
      </div>
    );
  }

  if (!scheduled.length && !running.length) {
    return (
      <div className="rounded-2xl bg-card p-8 text-center shadow-[var(--shadow-soft)]">
        <Trophy className="w-10 h-10 text-muted-foreground mx-auto opacity-50" />
        <p className="text-sm text-muted-foreground mt-2">Tous les matchs sont terminés.</p>
      </div>
    );
  }

  // Group scheduled by round
  const bracketScheduled = scheduled.filter((m) => m.phase !== "pool");
  const poolScheduled = scheduled.filter((m) => m.phase === "pool");
  const rounds = Array.from(new Set(bracketScheduled.map((m) => m.round))).sort((a, b) => a - b);

  // Compute timing info
  const matchDurSec = t.max_match_duration_secs ?? 1800;
  const breakSec = t.break_seconds ?? 600;
  const lobbySec = (t.lobby_minutes ?? 5) * 60;

  // Next round start estimate
  const nextRoundStart = estimateNextRoundStart(t, matches, now);

  return (
    <div className="space-y-3">
      {/* Timing info banner */}
      <div className="rounded-2xl bg-secondary/40 p-3 space-y-1.5 text-[11px]">
        <div className="flex justify-between"><span className="text-muted-foreground">Durée max par match</span><span className="font-bold">{Math.floor(matchDurSec / 60)} min</span></div>
        <div className="flex justify-between"><span className="text-muted-foreground">Préparation entre phases</span><span className="font-bold">{Math.floor(breakSec / 60)} min</span></div>
        <div className="flex justify-between"><span className="text-muted-foreground">Salle d'attente (lobby)</span><span className="font-bold">{t.lobby_minutes ?? 5} min</span></div>
        {nextRoundStart && (
          <div className="flex justify-between pt-1 border-t border-border">
            <span className="font-bold text-primary">Prochaine phase estimée</span>
            <span className="font-bold text-primary">{new Date(nextRoundStart).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}</span>
          </div>
        )}
      </div>

      {/* Running matches */}
      {running.length > 0 && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-amber-600 uppercase mb-2 flex items-center gap-1">
            <span className="w-2 h-2 rounded-full bg-amber-500 animate-pulse" /> En cours ({running.length})
          </h3>
          <div className="space-y-1.5">
            {running.map((m) => <UpcomingMatchRow key={m.id} m={m} byId={byId} me={me} t={t} now={now} isRunning />)}
          </div>
        </div>
      )}

      {/* Pool scheduled */}
      {poolScheduled.length > 0 && (
        <div className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
          <h3 className="text-xs font-bold text-muted-foreground uppercase mb-2">Poules à venir</h3>
          <div className="space-y-1.5">
            {poolScheduled.map((m) => <UpcomingMatchRow key={m.id} m={m} byId={byId} me={me} t={t} now={now} />)}
          </div>
        </div>
      )}

      {/* Bracket rounds */}
      {rounds.map((r) => {
        const roundMatches = bracketScheduled.filter((m) => m.round === r);
        if (!roundMatches.length) return null;
        const allInRound = matches.filter((m) => m.round === r && m.phase !== "pool" && m.phase !== "third_place");
        const label = roundLabel(allInRound.length, roundMatches[0]?.phase ?? "final");
        return (
          <div key={r} className="rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]">
            <h3 className="text-xs font-bold text-primary uppercase mb-2">{label}</h3>
            <div className="space-y-1.5">
              {roundMatches.map((m) => <UpcomingMatchRow key={m.id} m={m} byId={byId} me={me} t={t} now={now} />)}
            </div>
          </div>
        );
      })}

      {/* Timing explanation */}
      <div className="rounded-2xl bg-secondary/40 p-3 text-[11px] text-muted-foreground space-y-1">
        <div className="font-bold text-foreground mb-1">📅 Organisation des temps</div>
        <div>• Chaque match dure au maximum {Math.floor(matchDurSec / 60)} minutes</div>
        <div>• {Math.floor(breakSec / 60)} minutes de préparation entre chaque phase</div>
        <div>• {t.lobby_minutes ?? 5} minutes en salle d'attente avant le match</div>
        <div>• Règles officielles {t.game_slug === "ludo" ? "du Ludo" : "du Domino"} — identiques au jeu normal</div>
      </div>
    </div>
  );
}

function UpcomingMatchRow({ m, byId, me, t, now, isRunning }: {
  m: any; byId: Record<string, any>; me: any; t: any; now: number; isRunning?: boolean;
}) {
  const players = m.entrant_ids.map((eid: string) => byId[eid]);
  const isMyMatch = me && m.entrant_ids.includes(me.id);
  const est = isRunning ? null : estimateMatchStart(m, m._allMatches ?? [], t, now);
  const deadlineLeft = useCountdown(isRunning ? m.deadline_at : null);

  return (
    <div className={`flex items-center gap-2 text-[11px] px-2.5 py-2 rounded-xl ${isMyMatch ? "bg-primary/10 border border-primary/30" : "bg-secondary/40"}`}>
      <span className="text-[9px] font-bold text-muted-foreground w-6">{m.match_no ?? ""}</span>
      <div className="flex-1 min-w-0">
        {players.map((p: any, i: number) => (
          <span key={i} className={`${i > 0 ? " text-muted-foreground" : ""} ${me?.id === p?.id ? "font-bold text-primary" : ""}`}>
            {i > 0 && " vs "}
            {p?.display_name ?? "À déterminer"}
          </span>
        ))}
        {!players.length && <span className="text-muted-foreground italic">En attente du tirage</span>}
      </div>
      {/* Time indicator */}
      {isRunning && deadlineLeft > 0 ? (
        <span className={`text-[10px] font-bold tabular-nums px-2 py-0.5 rounded-full ${deadlineLeft < 60 ? "bg-red-100 text-red-700 dark:bg-red-950/40 dark:text-red-300" : "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300"}`}>
          {fmt(deadlineLeft)}
        </span>
      ) : est ? (
        <span className="text-[10px] font-bold text-muted-foreground px-2 py-0.5 rounded-full bg-secondary shrink-0">
          ~{est.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}
        </span>
      ) : null}
      {isMyMatch && <span className="text-[8px] font-bold text-primary shrink-0">VOUS</span>}
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   ADMIN BAR — with timer controls
   ═══════════════════════════════════════════════════════════ */
function AdminBar({ t, busy, rpc }: { t: any; busy: boolean; rpc: (fn: string, a: any, ok: string) => void }) {
  const [showTimers, setShowTimers] = useState(false);
  const [matchMin, setMatchMin] = useState(Math.floor((t.max_match_duration_secs ?? 1800) / 60));
  const [breakMin, setBreakMin] = useState(Math.floor((t.break_seconds ?? 600) / 60));
  const [lobbyMin, setLobbyMin] = useState(t.lobby_minutes ?? 5);
  const [checkInMin, setCheckInMin] = useState(t.check_in_minutes ?? 15);
  const [concurrent, setConcurrent] = useState(t.max_concurrent_matches ?? 8);
  const [bots, setBots] = useState(4);

  const saveTimers = () => {
    rpc("admin_tournament_set_timers", {
      _tid: t.id,
      _match_duration_secs: matchMin * 60,
      _break_secs: breakMin * 60,
      _lobby_mins: lobbyMin,
      _check_in_mins: checkInMin,
      _max_concurrent: concurrent,
    }, "✅ Timers mis à jour");
  };

  return (
    <div className="mx-4 my-2 rounded-2xl border border-dashed border-border p-3 space-y-2">
      <div className="flex items-center justify-between">
        <div className="text-[11px] font-bold text-muted-foreground uppercase tracking-wide">Contrôles admin</div>
        <button onClick={() => setShowTimers(!showTimers)}
          className="text-[11px] font-bold text-primary flex items-center gap-1">
          <Settings className="w-3 h-3" /> Timers
        </button>
      </div>

      {/* Timer settings (collapsible) */}
      {showTimers && (
        <div className="rounded-xl bg-secondary/40 p-3 space-y-2">
          <div className="text-[10px] font-bold text-muted-foreground uppercase">Configuration des temps</div>
          <div className="grid grid-cols-2 gap-2">
            <TimerInput label="Match (min)" value={matchMin} onChange={setMatchMin} min={1} max={120} />
            <TimerInput label="Prépa (min)" value={breakMin} onChange={setBreakMin} min={0} max={60} />
            <TimerInput label="Lobby (min)" value={lobbyMin} onChange={setLobbyMin} min={1} max={30} />
            <TimerInput label="Check-in (min)" value={checkInMin} onChange={setCheckInMin} min={1} max={60} />
            <TimerInput label="Matchs simultanés" value={concurrent} onChange={setConcurrent} min={1} max={8} />
          </div>
          <button onClick={saveTimers} disabled={busy}
            className="w-full py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold disabled:opacity-60">
            Enregistrer les timers
          </button>
        </div>
      )}

      {/* Action buttons */}
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

function TimerInput({ label, value, onChange, min, max }: {
  label: string; value: number; onChange: (v: number) => void; min: number; max: number;
}) {
  return (
    <div>
      <label className="text-[10px] text-muted-foreground font-semibold block mb-1">{label}</label>
      <input type="number" min={min} max={max} value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full px-2 py-1.5 rounded-xl bg-card text-sm text-center" />
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════
   UTILITIES
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
