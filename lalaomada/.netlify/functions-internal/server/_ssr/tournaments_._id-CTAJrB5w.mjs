import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { g as useParams, e as useNavigate, L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { u as useAuth, b as useConfirm, S as StatusPill } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { q as LoaderCircle, A as ArrowLeft, U as Users, aT as ListOrdered, aQ as CalendarClock, a as Trophy, f as Coins, av as Play, Q as LogOut, ay as Crown, aw as Timer, aa as UserCheck, H as Hourglass, _ as CircleAlert, ad as Settings, l as Clock } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "../_libs/isbot.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "tslib";
import "../_libs/supabase__functions-js.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
import "../_libs/radix-ui__react-alert-dialog.mjs";
import "../_libs/radix-ui__react-context.mjs";
import "../_libs/radix-ui__react-compose-refs.mjs";
import "../_libs/radix-ui__react-dialog.mjs";
import "../_libs/radix-ui__primitive.mjs";
import "../_libs/radix-ui__react-id.mjs";
import "../_libs/@radix-ui/react-use-layout-effect+[...].mjs";
import "../_libs/@radix-ui/react-use-controllable-state+[...].mjs";
import "../_libs/@radix-ui/react-use-effect-event+[...].mjs";
import "../_libs/@radix-ui/react-dismissable-layer+[...].mjs";
import "../_libs/radix-ui__react-primitive.mjs";
import "../_libs/radix-ui__react-slot.mjs";
import "../_libs/@radix-ui/react-use-callback-ref+[...].mjs";
import "../_libs/radix-ui__react-focus-scope.mjs";
import "../_libs/radix-ui__react-portal.mjs";
import "../_libs/radix-ui__react-presence.mjs";
import "../_libs/radix-ui__react-focus-guards.mjs";
import "../_libs/react-remove-scroll.mjs";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/ai-sdk__openai-compatible.mjs";
import "../_libs/ai-sdk__provider.mjs";
import "../_libs/ai-sdk__provider-utils.mjs";
import "../_libs/eventsource-parser.mjs";
import "../_libs/zod.mjs";
import "../_libs/ai.mjs";
import "../_libs/ai-sdk__gateway.mjs";
import "../_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "../_libs/opentelemetry__api.mjs";
const GAMES = {
  ludo: {
    emoji: "🎲",
    label: "Ludo"
  },
  domino: {
    emoji: "🁣",
    label: "Domino"
  }
};
function roundLabel(matchCount, phase) {
  if (phase === "third_place") return "Petite finale";
  if (phase === "pool") return "Poules";
  const map = {
    128: "128ème de finale",
    64: "64ème de finale",
    32: "32ème de finale",
    16: "16ème de finale",
    8: "8ème de finale",
    4: "Quart de finale",
    2: "Demi-finale",
    1: "Finale"
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
function eliminatedRoundLabel(round, format, totalRounds) {
  if (!round) return "Éliminé";
  if (format === "pools" && round === 1) return "Élimé en poules";
  const fromEnd = totalRounds - round;
  const map = {
    0: "Finaliste",
    1: "Demi-finaliste",
    2: "Quart de finaliste",
    3: "8ème de finaliste",
    4: "16ème de finaliste",
    5: "32ème de finaliste"
  };
  return map[fromEnd] ?? `Éliminé au tour ${round}`;
}
function estimateMatchStart(m, allMatches, t, now) {
  if (m.status !== "scheduled") return null;
  const matchDur = (t.max_match_duration_secs ?? 1800) * 1e3;
  (t.break_seconds ?? 600) * 1e3;
  (t.lobby_minutes ?? 5) * 60 * 1e3;
  const sameRound = allMatches.filter((mm) => mm.round === m.round && mm.phase === m.phase);
  const running = sameRound.filter((mm) => mm.status === "running");
  const maxConcurrent = t.max_concurrent_matches ?? 8;
  if (running.length < maxConcurrent) return new Date(now);
  const earliestFinish = running.map((mm) => {
    const started = mm.started_at ? new Date(mm.started_at).getTime() : now;
    return started + matchDur;
  }).sort((a, b) => a - b)[0];
  return new Date(earliestFinish ?? now);
}
function estimateNextRoundStart(t, matches, now) {
  const matchDur = (t.max_match_duration_secs ?? 1800) * 1e3;
  const breakMs = (t.break_seconds ?? 600) * 1e3;
  const lobbyMs = (t.lobby_minutes ?? 5) * 60 * 1e3;
  const currentRoundMatches = matches.filter((m) => m.round === t.current_round && m.phase !== "pool");
  const running = currentRoundMatches.filter((m) => m.status === "running");
  const scheduled = currentRoundMatches.filter((m) => m.status === "scheduled");
  if (running.length === 0 && scheduled.length === 0) {
    return new Date(now + breakMs + lobbyMs);
  }
  const finishTimes = [];
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
function TournamentDetail() {
  const {
    id
  } = useParams({
    from: "/_authenticated/tournaments_/$id"
  });
  const navigate = useNavigate();
  const {
    user,
    isAdmin
  } = useAuth();
  const confirm = useConfirm();
  const [st, setSt] = reactExports.useState(null);
  const [busy, setBusy] = reactExports.useState(false);
  const [tab, setTab] = reactExports.useState("players");
  const load = reactExports.useCallback(async () => {
    const {
      data
    } = await supabase.rpc("tournament_state", {
      _tid: id
    });
    if (data) setSt(data);
    if (data?.tournament?.status === "running") {
      supabase.rpc("poll_tournament_engine", {
        _tid: id
      });
    }
  }, [id]);
  reactExports.useEffect(() => {
    let dt;
    const debouncedLoad = () => {
      clearTimeout(dt);
      dt = setTimeout(load, 800);
    };
    load();
    const ch = supabase.channel(`tournament-${id}`).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournaments",
      filter: `id=eq.${id}`
    }, debouncedLoad).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournament_entrants",
      filter: `tournament_id=eq.${id}`
    }, debouncedLoad).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournament_matches",
      filter: `tournament_id=eq.${id}`
    }, debouncedLoad).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournament_pool_entrants"
    }, debouncedLoad).subscribe();
    const iv = setInterval(load, 3e4);
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
      clearInterval(iv);
    };
  }, [id, load]);
  const t = st?.tournament;
  const entrants = st?.entrants ?? [];
  const matches = st?.matches ?? [];
  const byId = reactExports.useMemo(() => Object.fromEntries(entrants.map((e) => [e.id, e])), [entrants]);
  const me = reactExports.useMemo(() => entrants.find((e) => e.user_id === user?.id), [entrants, user?.id]);
  const waitlist = st?.waitlist ?? [];
  const meWaitlist = reactExports.useMemo(() => waitlist.find((w) => w.user_id === user?.id), [waitlist, user?.id]);
  const myMatch = reactExports.useMemo(() => matches.find((m) => m.status === "running" && me && m.entrant_ids.includes(me.id)), [matches, me]);
  reactExports.useEffect(() => {
    if (myMatch && myMatch.game_id) {
      const target = t?.game_slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id";
      navigate({
        to: target,
        params: {
          id: myMatch.game_id
        }
      });
    }
  }, [myMatch?.id]);
  const netPrize = t ? Number(t.entry_fee_ar) > 0 ? Math.round(Number(t.prize_pool_ar) * (100 - Number(t.platform_pct)) / 100 + Number(t.admin_prize_pool_ar)) : Number(t.admin_prize_pool_ar) : 0;
  reactExports.useMemo(() => matches.find((m) => m.status === "scheduled" && me && m.entrant_ids.includes(me.id)), [matches, me]);
  const rpc = async (fn, args, ok) => {
    setBusy(true);
    const {
      error
    } = await supabase.rpc(fn, args);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(ok);
    load();
  };
  const register = async () => {
    const fee = Number(t.entry_fee_ar);
    const okGo = await confirm({
      title: "Confirmer votre inscription",
      description: fee > 0 ? `${fee.toLocaleString("fr-FR")} Ar seront débités de votre solde. Cagnotte à gagner : ${netPrize.toLocaleString("fr-FR")} Ar.` : "Inscription gratuite à ce tournoi."
    });
    if (!okGo) return;
    rpc("tournament_register", {
      _tid: id
    }, "✅ Inscription confirmée !");
  };
  const unregister = async () => {
    const okGo = await confirm({
      title: "Annuler votre inscription ?",
      description: Number(t.entry_fee_ar) > 0 ? "Vos frais d'inscription seront remboursés." : "Vous quitterez ce tournoi.",
      destructive: true
    });
    if (!okGo) return;
    rpc("tournament_unregister", {
      _tid: id
    }, "Inscription annulée.");
  };
  if (!t) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-24", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-muted-foreground" }) });
  }
  const g = GAMES[t.game_slug] ?? {
    emoji: "🏆",
    label: t.game_slug
  };
  const isPaid = Number(t.entry_fee_ar) > 0;
  const hasMatches = matches.length > 0;
  const now = Date.now();
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
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-h-screen flex flex-col", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 pt-4 pb-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => navigate({
        to: "/tournaments"
      }), className: "inline-flex items-center gap-1 text-sm font-semibold text-muted-foreground mb-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-4 h-4" }),
        " Tournois"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-12 h-12 rounded-2xl bg-secondary grid place-items-center text-2xl shrink-0", children: g.emoji }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold truncate", children: t.name }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(StatusPill, { status: t.status })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs text-muted-foreground", children: g.label }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] font-bold px-2 py-0.5 rounded-full ${isPaid ? "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300" : "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"}`, children: isPaid ? "💰 Payant" : "🎁 Gratuit" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs text-muted-foreground", children: t.format === "pools" ? "Poules + finale" : "Élimination directe" })
          ] })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-3 rounded-2xl bg-primary/10 px-4 py-3 text-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold text-primary", children: stageLabel }),
        t.status === "running" && t.current_round > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
          entrants.filter((e) => e.status === "active").length,
          " joueur(s) encore en lice"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-3 flex gap-1 rounded-2xl bg-secondary p-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabButton, { active: tab === "players", onClick: () => setTab("players"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), label: "Joueurs" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabButton, { active: tab === "results", onClick: () => setTab("results"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ListOrdered, { className: "w-4 h-4" }), label: "Résultats" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabButton, { active: tab === "next", onClick: () => setTab("next"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CalendarClock, { className: "w-4 h-4" }), label: "Matchs suivants" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-2 mt-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Info, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), label: "Cagnotte", value: `${netPrize.toLocaleString("fr-FR")} Ar` }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Info, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-4 h-4" }), label: "Inscription", value: isPaid ? `${Number(t.entry_fee_ar).toLocaleString("fr-FR")} Ar` : "Gratuit" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Info, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), label: "Joueurs", value: `${entrants.length}/${t.max_players}` })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(TimerPanel, { t, myMatch, me, matches, now }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 py-2", children: myMatch ? /* @__PURE__ */ jsxRuntimeExports.jsxs(Link, { to: t.game_slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id", params: {
      id: myMatch.game_id
    }, className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-2 animate-pulse", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-4 h-4" }),
      " Rejoindre mon match"
    ] }) : t.status === "open" && me ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      t.check_in_opened_at && !me.checked_in && me.status === "active" && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => rpc("tournament_check_in", {
        _tid: id
      }, "✅ Check-in confirmé !"), disabled: busy, className: "w-full py-3 rounded-2xl bg-amber-500 text-white font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-60", children: "✋ Je suis prêt !" }),
      t.check_in_opened_at && me.checked_in && me.status === "active" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full py-3 rounded-2xl bg-emerald-100 dark:bg-emerald-950/40 text-emerald-700 dark:text-emerald-300 text-center text-sm font-bold", children: "✅ Check-in confirmé — en attente du début" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: unregister, disabled: busy, className: "w-full py-3 rounded-2xl bg-secondary text-secondary-foreground font-bold text-sm flex items-center justify-center gap-2 disabled:opacity-60", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-4 h-4" }),
        " Annuler mon inscription"
      ] })
    ] }) : t.status === "open" && !me ? meWaitlist ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground", children: [
      "⏳ Liste d'attente — position ",
      meWaitlist.position
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: register, disabled: busy, className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-60", children: entrants.length >= t.max_players ? "S'inscrire (liste d'attente)" : "S'inscrire" }) : me && me.status === "active" && t.status === "running" ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full py-3 rounded-2xl bg-secondary text-center text-sm font-semibold text-muted-foreground", children: "⏳ En attente de votre prochain match…" }) : null }),
    me && me.status === "eliminated" && t.status === "running" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mx-4 mb-2 rounded-2xl bg-secondary/60 p-3 text-center text-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-destructive font-bold", children: "Vous avez été éliminé" }),
      me.eliminated_round && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
        eliminatedRoundLabel(me.eliminated_round, t.format, t.total_rounds ?? 0),
        me.final_rank ? ` — ${me.final_rank}e place` : ""
      ] })
    ] }),
    t.status === "finished" && entrants.find((e) => e.final_rank === 1) && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mx-4 mb-2 rounded-2xl bg-gradient-to-r from-amber-50 to-amber-100 dark:from-amber-950/30 dark:to-amber-900/20 p-4 text-center space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-10 h-10 text-amber-500 mx-auto" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold text-amber-700 dark:text-amber-400", children: entrants.find((e) => e.final_rank === 1)?.display_name }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold text-amber-600 uppercase", children: "Champion" }),
      netPrize > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm font-bold text-amber-700 dark:text-amber-400", children: [
        "Gagne ",
        netPrize.toLocaleString("fr-FR"),
        " Ar"
      ] })
    ] }),
    isAdmin && /* @__PURE__ */ jsxRuntimeExports.jsx(AdminBar, { t, busy, rpc }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 px-4 pt-2", children: [
      tab === "players" && /* @__PURE__ */ jsxRuntimeExports.jsx(PlayersTab, { entrants, waitlist, t, byId, me, matches, hasMatches }),
      tab === "results" && /* @__PURE__ */ jsxRuntimeExports.jsx(ResultsTab, { matches, byId, me, t }),
      tab === "next" && /* @__PURE__ */ jsxRuntimeExports.jsx(NextMatchesTab, { matches, byId, me, t, now })
    ] })
  ] });
}
function TabButton({
  active,
  onClick,
  icon,
  label
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: `flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-xl transition-all ${active ? "bg-card text-primary font-bold shadow-sm" : "text-muted-foreground"}`, children: [
    icon,
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-semibold", children: label })
  ] });
}
function TimerPanel({
  t,
  myMatch,
  me,
  matches,
  now
}) {
  const checkInDeadline = t.check_in_opened_at ? new Date(new Date(t.check_in_opened_at).getTime() + (t.check_in_minutes ?? 15) * 6e4).toISOString() : null;
  const checkInLeft = useCountdown(checkInDeadline);
  const checkInActive = t.check_in_opened_at && t.status === "open" && checkInLeft > 0;
  const breakLeft = useCountdown(t.break_until);
  const breakActive = t.break_until && breakLeft > 0;
  const matchDeadlineLeft = useCountdown(myMatch?.deadline_at);
  const matchActive = myMatch && myMatch.status === "running" && matchDeadlineLeft > 0;
  const nextRoundStart = reactExports.useMemo(() => {
    if (t.status !== "running" || breakActive || matchActive) return null;
    return estimateNextRoundStart(t, matches, now);
  }, [t, matches, now, breakActive, matchActive]);
  const nextRoundLeft = useCountdown(nextRoundStart?.toISOString());
  const nextRoundVisible = t.status === "running" && !breakActive && !matchActive && nextRoundLeft > 0 && matches.some((m) => m.status === "running" || m.status === "scheduled");
  if (!checkInActive && !breakActive && !matchActive && !nextRoundVisible) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mx-4 my-2 rounded-2xl border border-primary/30 bg-primary/5 p-3 space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-[11px] font-bold text-primary uppercase", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-3.5 h-3.5" }),
      " Chronomètres"
    ] }),
    checkInActive && /* @__PURE__ */ jsxRuntimeExports.jsx(TimerRow, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(UserCheck, { className: "w-4 h-4 text-amber-600" }), label: "Check-in ouvert", sub: `${t.check_in_minutes ?? 15} min pour confirmer`, seconds: checkInLeft, color: "amber" }),
    breakActive && /* @__PURE__ */ jsxRuntimeExports.jsx(TimerRow, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-4 h-4 text-blue-600" }), label: "Pause entre les phases", sub: `Prochaine phase dans ${fmt(breakLeft)}`, seconds: breakLeft, color: "blue" }),
    matchActive && /* @__PURE__ */ jsxRuntimeExports.jsx(TimerRow, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleAlert, { className: "w-4 h-4 text-red-600" }), label: "Votre match est en cours !", sub: matchDeadlineLeft < 60 ? "⚠ Dernières secondes !" : `Temps restant : ${fmt(matchDeadlineLeft)}`, seconds: matchDeadlineLeft, color: "red" }),
    nextRoundVisible && /* @__PURE__ */ jsxRuntimeExports.jsx(TimerRow, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CalendarClock, { className: "w-4 h-4 text-purple-600" }), label: "Prochaine phase estimée", sub: `Dans environ ${fmt(nextRoundLeft)}`, seconds: nextRoundLeft, color: "purple" })
  ] });
}
function TimerRow({
  icon,
  label,
  sub,
  seconds,
  color
}) {
  const cc = {
    amber: "bg-amber-100 dark:bg-amber-950/40 text-amber-700 dark:text-amber-300",
    blue: "bg-blue-100 dark:bg-blue-950/40 text-blue-700 dark:text-blue-300",
    red: "bg-red-100 dark:bg-red-950/40 text-red-700 dark:text-red-300",
    purple: "bg-purple-100 dark:bg-purple-950/40 text-purple-700 dark:text-purple-300"
  };
  const pct = Math.min(100, Math.max(5, seconds / 1800 * 100));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-xl ${cc[color]} p-2.5 space-y-1`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
      icon,
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-bold flex-1", children: label }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm font-bold tabular-nums", children: fmt(seconds) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] opacity-80", children: sub }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-1 rounded-full bg-black/10 overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-full rounded-full bg-current opacity-60 transition-all", style: {
      width: `${pct}%`
    } }) })
  ] });
}
function PlayersTab({
  entrants,
  waitlist,
  t,
  byId,
  me,
  matches,
  hasMatches
}) {
  const tournamentStarted = t.status === "running" || t.status === "finished";
  const active = entrants.filter((e) => e.status === "active");
  const eliminated = entrants.filter((e) => e.status === "eliminated").sort((a, b) => (b.eliminated_round ?? 0) - (a.eliminated_round ?? 0));
  if (!tournamentStarted) {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 shadow-[var(--shadow-soft)]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "text-xs font-bold text-muted-foreground uppercase mb-3", children: [
          "Joueurs inscrits (",
          entrants.length,
          "/",
          t.max_players,
          ")"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1", children: entrants.map((e, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2 text-sm px-2.5 py-2 rounded-xl ${me?.id === e.id ? "bg-primary/10 font-bold" : "bg-secondary/40"}`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-6 text-xs text-muted-foreground font-bold", children: i + 1 }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 truncate", children: e.display_name }),
          e.is_bot && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary", children: "bot" }),
          e.checked_in && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-emerald-600 px-1.5 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-950/40", children: "✓" }),
          me?.id === e.id && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] font-bold text-primary", children: "VOUS" })
        ] }, e.id)) })
      ] }),
      waitlist.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 shadow-[var(--shadow-soft)]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "text-xs font-bold text-amber-600 uppercase mb-2 flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3 h-3" }),
          " Liste d'attente (",
          waitlist.length,
          ")"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1", children: waitlist.map((w) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm px-2.5 py-2 rounded-xl bg-secondary/40", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-6 text-xs font-bold text-amber-600", children: w.position }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 truncate", children: w.display_name })
        ] }, w.id)) })
      ] })
    ] });
  }
  const currentRoundMatches = matches.filter((m) => m.round === t.current_round && m.phase !== "pool" && m.status !== "finished");
  const poolMatches = matches.filter((m) => m.phase === "pool" && m.status !== "finished");
  const displayMatches = poolMatches.length > 0 ? poolMatches : currentRoundMatches;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    displayMatches.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "text-xs font-bold text-primary uppercase mb-3", children: poolMatches.length > 0 ? "Matchs de poules" : "Matchs en cours" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-1 sm:grid-cols-2 gap-2", children: displayMatches.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsx(MatchupCard, { m, byId, me, t }, m.id)) })
    ] }),
    active.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "text-xs font-bold text-emerald-600 uppercase mb-2 flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-2 h-2 rounded-full bg-emerald-500" }),
        " En lice (",
        active.length,
        ")"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1", children: active.map((e, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl bg-secondary/40", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-5 text-xs text-muted-foreground", children: i + 1 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 truncate font-medium", children: e.display_name }),
        e.is_bot && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary", children: "bot" }),
        e.final_rank === 1 && /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-4 h-4 text-amber-500" })
      ] }, e.id)) })
    ] }),
    eliminated.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "text-xs font-bold text-muted-foreground uppercase mb-2", children: [
        "Éliminés (",
        eliminated.length,
        ")"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1", children: eliminated.map((e, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm px-2 py-1.5 rounded-xl opacity-60", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-5 text-xs text-muted-foreground", children: i + 1 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 truncate", children: e.display_name }),
        e.final_rank && e.final_rank <= 4 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-amber-600", children: e.final_rank === 1 ? "🥇" : e.final_rank === 2 ? "🥈" : "🥉" }),
        e.eliminated_round && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] text-muted-foreground shrink-0", children: eliminatedRoundLabel(e.eliminated_round, t.format, t.total_rounds ?? 0) })
      ] }, e.id)) })
    ] })
  ] });
}
function MatchupCard({
  m,
  byId,
  me,
  t
}) {
  const players = m.entrant_ids.map((eid) => byId[eid]);
  const isMyMatch = me && m.entrant_ids.includes(me.id);
  const isRunning = m.status === "running";
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-2xl border p-2.5 ${isMyMatch && isRunning ? "border-primary shadow-md" : "border-border"} ${isRunning ? "bg-amber-50 dark:bg-amber-950/20" : "bg-secondary/30"}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-bold text-muted-foreground", children: m.phase === "pool" ? "Poule" : m.phase === "third_place" ? "3e place" : `M${m.match_no ?? ""}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(MatchPill, { m })
    ] }),
    players.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      i > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 py-0.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 border-t border-dashed border-border" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-bold text-muted-foreground px-1", children: "VS" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 border-t border-dashed border-border" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1.5 rounded-lg px-1.5 py-1 ${m.winner_entrant_id === p?.id ? "bg-emerald-50 dark:bg-emerald-950/30" : m.status === "finished" && m.winner_entrant_id && m.winner_entrant_id !== p?.id ? "opacity-50" : ""}`, children: [
        m.winner_entrant_id === p?.id ? /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-3 h-3 text-amber-500 shrink-0" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-3 h-3 shrink-0" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-xs truncate flex-1 ${m.winner_entrant_id === p?.id ? "font-bold text-emerald-700 dark:text-emerald-400" : m.status === "finished" && m.winner_entrant_id && m.winner_entrant_id !== p?.id ? "text-muted-foreground line-through" : "font-medium"} ${me?.id === p?.id ? "text-primary font-bold" : ""}`, children: p?.display_name ?? "À déterminer" }),
        me?.id === p?.id && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] font-bold text-primary shrink-0", children: "VOUS" })
      ] })
    ] }, i)),
    isRunning && m.game_id && me && m.entrant_ids.includes(me.id) && /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: t.game_slug === "ludo" ? "/jeux/ludo/$id" : "/jeux/domino/$id", params: {
      id: m.game_id
    }, className: "mt-2 block w-full py-1.5 rounded-xl bg-primary text-primary-foreground text-[11px] font-bold text-center", children: "▶ Rejoindre" })
  ] });
}
function ResultsTab({
  matches,
  byId,
  me,
  t
}) {
  const finished = matches.filter((m) => m.status === "finished");
  if (!finished.length) {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-8 text-center shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-10 h-10 text-muted-foreground mx-auto opacity-50" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground mt-2", children: "Aucun résultat pour l'instant." })
    ] });
  }
  const poolResults = finished.filter((m) => m.phase === "pool");
  const bracketResults = finished.filter((m) => m.phase !== "pool");
  const rounds = Array.from(new Set(bracketResults.map((m) => m.round))).sort((a, b) => a - b);
  const thirdPlace = bracketResults.find((m) => m.phase === "third_place");
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    poolResults.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "text-xs font-bold text-muted-foreground uppercase mb-2", children: "Phase de poules" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: poolResults.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsx(ResultRow, { m, byId, me }, m.id)) })
    ] }),
    rounds.map((r) => {
      const roundMatches = bracketResults.filter((m) => m.round === r && m.phase !== "third_place");
      if (!roundMatches.length) return null;
      const label = roundLabel(matches.filter((m) => m.round === r && m.phase !== "pool" && m.phase !== "third_place").length, roundMatches[0]?.phase ?? "final");
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "text-xs font-bold text-primary uppercase mb-2", children: label }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: roundMatches.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsx(ResultRow, { m, byId, me }, m.id)) })
      ] }, r);
    }),
    thirdPlace && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "text-xs font-bold text-amber-600 uppercase mb-2", children: "🥉 Petite finale" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ResultRow, { m: thirdPlace, byId, me }) })
    ] })
  ] });
}
function ResultRow({
  m,
  byId,
  me
}) {
  const winner = m.winner_entrant_id ? byId[m.winner_entrant_id] : null;
  const players = m.entrant_ids.map((eid) => byId[eid]).filter(Boolean);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-[11px] px-2.5 py-2 rounded-xl bg-secondary/40", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] font-bold text-muted-foreground w-6", children: [
      "M",
      m.match_no ?? ""
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-w-0", children: players.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1 ${i > 0 ? "mt-0.5" : ""}`, children: [
      m.winner_entrant_id === p?.id ? /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-3 h-3 text-amber-500 shrink-0" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-3 h-3 shrink-0" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `truncate ${m.winner_entrant_id === p?.id ? "font-bold text-emerald-700 dark:text-emerald-400" : m.is_draw ? "" : "text-muted-foreground line-through"} ${me?.id === p?.id ? "text-primary" : ""}`, children: p?.display_name ?? "?" }),
      me?.id === p?.id && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] font-bold text-primary shrink-0", children: "VOUS" })
    ] }, i)) }),
    m.is_draw ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-bold text-amber-600 px-1.5 py-0.5 rounded-full bg-amber-100 dark:bg-amber-950/40 shrink-0", children: "NUL" }) : winner ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-bold text-emerald-600 px-1.5 py-0.5 rounded-full bg-emerald-100 dark:bg-emerald-950/40 shrink-0", children: "GAGNÉ" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-bold text-muted-foreground px-1.5 py-0.5 rounded-full bg-secondary shrink-0", children: "FORFAIT" })
  ] });
}
function NextMatchesTab({
  matches,
  byId,
  me,
  t,
  now
}) {
  const scheduled = matches.filter((m) => m.status === "scheduled");
  const running = matches.filter((m) => m.status === "running");
  const hasMatches = matches.length > 0;
  if (!hasMatches) {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-8 text-center shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(CalendarClock, { className: "w-10 h-10 text-muted-foreground mx-auto opacity-50" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground mt-2", children: "Les matchs apparaîtront au démarrage du tournoi." })
    ] });
  }
  if (!scheduled.length && !running.length) {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-8 text-center shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-10 h-10 text-muted-foreground mx-auto opacity-50" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground mt-2", children: "Tous les matchs sont terminés." })
    ] });
  }
  const bracketScheduled = scheduled.filter((m) => m.phase !== "pool");
  const poolScheduled = scheduled.filter((m) => m.phase === "pool");
  const rounds = Array.from(new Set(bracketScheduled.map((m) => m.round))).sort((a, b) => a - b);
  const matchDurSec = t.max_match_duration_secs ?? 1800;
  const breakSec = t.break_seconds ?? 600;
  (t.lobby_minutes ?? 5) * 60;
  const nextRoundStart = estimateNextRoundStart(t, matches, now);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/40 p-3 space-y-1.5 text-[11px]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground", children: "Durée max par match" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold", children: [
          Math.floor(matchDurSec / 60),
          " min"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground", children: "Préparation entre phases" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold", children: [
          Math.floor(breakSec / 60),
          " min"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground", children: "Salle d'attente (lobby)" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold", children: [
          t.lobby_minutes ?? 5,
          " min"
        ] })
      ] }),
      nextRoundStart && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between pt-1 border-t border-border", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-primary", children: "Prochaine phase estimée" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-primary", children: new Date(nextRoundStart).toLocaleTimeString("fr-FR", {
          hour: "2-digit",
          minute: "2-digit"
        }) })
      ] })
    ] }),
    running.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "text-xs font-bold text-amber-600 uppercase mb-2 flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-2 h-2 rounded-full bg-amber-500 animate-pulse" }),
        " En cours (",
        running.length,
        ")"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: running.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsx(UpcomingMatchRow, { m, byId, me, t, now, isRunning: true }, m.id)) })
    ] }),
    poolScheduled.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "text-xs font-bold text-muted-foreground uppercase mb-2", children: "Poules à venir" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: poolScheduled.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsx(UpcomingMatchRow, { m, byId, me, t, now }, m.id)) })
    ] }),
    rounds.map((r) => {
      const roundMatches = bracketScheduled.filter((m) => m.round === r);
      if (!roundMatches.length) return null;
      const allInRound = matches.filter((m) => m.round === r && m.phase !== "pool" && m.phase !== "third_place");
      const label = roundLabel(allInRound.length, roundMatches[0]?.phase ?? "final");
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-3 shadow-[var(--shadow-soft)]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "text-xs font-bold text-primary uppercase mb-2", children: label }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: roundMatches.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsx(UpcomingMatchRow, { m, byId, me, t, now }, m.id)) })
      ] }, r);
    }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/40 p-3 text-[11px] text-muted-foreground space-y-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-foreground mb-1", children: "📅 Organisation des temps" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        "• Chaque match dure au maximum ",
        Math.floor(matchDurSec / 60),
        " minutes"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        "• ",
        Math.floor(breakSec / 60),
        " minutes de préparation entre chaque phase"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        "• ",
        t.lobby_minutes ?? 5,
        " minutes en salle d'attente avant le match"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        "• Règles officielles ",
        t.game_slug === "ludo" ? "du Ludo" : "du Domino",
        " — identiques au jeu normal"
      ] })
    ] })
  ] });
}
function UpcomingMatchRow({
  m,
  byId,
  me,
  t,
  now,
  isRunning
}) {
  const players = m.entrant_ids.map((eid) => byId[eid]);
  const isMyMatch = me && m.entrant_ids.includes(me.id);
  const est = isRunning ? null : estimateMatchStart(m, m._allMatches ?? [], t, now);
  const deadlineLeft = useCountdown(isRunning ? m.deadline_at : null);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2 text-[11px] px-2.5 py-2 rounded-xl ${isMyMatch ? "bg-primary/10 border border-primary/30" : "bg-secondary/40"}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-bold text-muted-foreground w-6", children: m.match_no ?? "" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
      players.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `${i > 0 ? " text-muted-foreground" : ""} ${me?.id === p?.id ? "font-bold text-primary" : ""}`, children: [
        i > 0 && " vs ",
        p?.display_name ?? "À déterminer"
      ] }, i)),
      !players.length && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground italic", children: "En attente du tirage" })
    ] }),
    isRunning && deadlineLeft > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] font-bold tabular-nums px-2 py-0.5 rounded-full ${deadlineLeft < 60 ? "bg-red-100 text-red-700 dark:bg-red-950/40 dark:text-red-300" : "bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300"}`, children: fmt(deadlineLeft) }) : est ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] font-bold text-muted-foreground px-2 py-0.5 rounded-full bg-secondary shrink-0", children: [
      "~",
      est.toLocaleTimeString("fr-FR", {
        hour: "2-digit",
        minute: "2-digit"
      })
    ] }) : null,
    isMyMatch && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] font-bold text-primary shrink-0", children: "VOUS" })
  ] });
}
function AdminBar({
  t,
  busy,
  rpc
}) {
  const [showTimers, setShowTimers] = reactExports.useState(false);
  const [matchMin, setMatchMin] = reactExports.useState(Math.floor((t.max_match_duration_secs ?? 1800) / 60));
  const [breakMin, setBreakMin] = reactExports.useState(Math.floor((t.break_seconds ?? 600) / 60));
  const [lobbyMin, setLobbyMin] = reactExports.useState(t.lobby_minutes ?? 5);
  const [checkInMin, setCheckInMin] = reactExports.useState(t.check_in_minutes ?? 15);
  const [concurrent, setConcurrent] = reactExports.useState(t.max_concurrent_matches ?? 8);
  const [bots, setBots] = reactExports.useState(4);
  const saveTimers = () => {
    rpc("admin_tournament_set_timers", {
      _tid: t.id,
      _match_duration_secs: matchMin * 60,
      _break_secs: breakMin * 60,
      _lobby_mins: lobbyMin,
      _check_in_mins: checkInMin,
      _max_concurrent: concurrent
    }, "✅ Timers mis à jour");
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mx-4 my-2 rounded-2xl border border-dashed border-border p-3 space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] font-bold text-muted-foreground uppercase tracking-wide", children: "Contrôles admin" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setShowTimers(!showTimers), className: "text-[11px] font-bold text-primary flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-3 h-3" }),
        " Timers"
      ] })
    ] }),
    showTimers && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-secondary/40 p-3 space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold text-muted-foreground uppercase", children: "Configuration des temps" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(TimerInput, { label: "Match (min)", value: matchMin, onChange: setMatchMin, min: 1, max: 120 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TimerInput, { label: "Prépa (min)", value: breakMin, onChange: setBreakMin, min: 0, max: 60 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TimerInput, { label: "Lobby (min)", value: lobbyMin, onChange: setLobbyMin, min: 1, max: 30 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TimerInput, { label: "Check-in (min)", value: checkInMin, onChange: setCheckInMin, min: 1, max: 60 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TimerInput, { label: "Matchs simultanés", value: concurrent, onChange: setConcurrent, min: 1, max: 8 })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: saveTimers, disabled: busy, className: "w-full py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold disabled:opacity-60", children: "Enregistrer les timers" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap gap-2", children: [
      t.status === "open" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        Number(t.entry_fee_ar) === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 1, max: 64, value: bots, onChange: (e) => setBots(Number(e.target.value)), className: "w-14 px-2 py-1.5 rounded-xl bg-secondary text-sm text-center" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_add_bots", {
            _tid: t.id,
            _count: bots
          }, `${bots} bots ajoutés`), className: "px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold", children: "+ Bots" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_open_check_in", {
          _tid: t.id
        }, "Check-in ouvert"), className: "px-3 py-1.5 rounded-xl bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300 text-xs font-bold", children: "✋ Check-in" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_start", {
          _tid: t.id
        }, "Tournoi démarré !"), className: "px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold", children: "▶ Démarrer" })
      ] }),
      t.status === "running" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_next_stage", {
          _tid: t.id
        }, "Phase suivante lancée"), className: "px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold", children: "⏭ Phase suivante" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_set_auto", {
          _tid: t.id,
          _auto: !t.auto_advance
        }, "Mode mis à jour"), className: `px-3 py-1.5 rounded-xl text-xs font-bold ${t.auto_advance ? "bg-primary/15 text-primary" : "bg-secondary"}`, children: t.auto_advance ? "⚡ Auto" : "✋ Manuel" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_set_status", {
          _tid: t.id,
          _status: "paused"
        }, "Tournoi en pause"), className: "px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold", children: "⏸ Pause" })
      ] }),
      t.status === "paused" && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_set_status", {
        _tid: t.id,
        _status: "running"
      }, "Tournoi repris"), className: "px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-xs font-bold", children: "▶ Reprendre" }),
      !["finished", "cancelled"].includes(t.status) && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => rpc("admin_tournament_cancel", {
        _tid: t.id,
        _reason: null
      }, "Tournoi annulé"), className: "px-3 py-1.5 rounded-xl bg-secondary text-xs font-bold text-destructive", children: "✕ Annuler" })
    ] })
  ] });
}
function TimerInput({
  label,
  value,
  onChange,
  min,
  max
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-[10px] text-muted-foreground font-semibold block mb-1", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min, max, value, onChange: (e) => onChange(Number(e.target.value)), className: "w-full px-2 py-1.5 rounded-xl bg-card text-sm text-center" })
  ] });
}
function Info({
  icon,
  label,
  value
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/60 p-2.5 text-center", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center text-muted-foreground mb-1", children: icon }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold truncate", children: value })
  ] });
}
function MatchPill({
  m
}) {
  const map = {
    scheduled: {
      l: "À venir",
      c: "bg-secondary text-muted-foreground"
    },
    running: {
      l: "Live",
      c: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300"
    },
    finished: {
      l: "Fini",
      c: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300"
    },
    cancelled: {
      l: "Annulé",
      c: "bg-secondary text-muted-foreground"
    }
  };
  const s = map[m.status] ?? map.scheduled;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `px-1.5 py-0.5 rounded-full text-[9px] font-bold shrink-0 ${s.c}`, children: s.l });
}
function useCountdown(target) {
  const [left, setLeft] = reactExports.useState(0);
  reactExports.useEffect(() => {
    if (!target) {
      setLeft(0);
      return;
    }
    const tick = () => setLeft(Math.max(0, Math.round((new Date(target).getTime() - serverNow()) / 1e3)));
    tick();
    const iv = setInterval(tick, 1e3);
    return () => clearInterval(iv);
  }, [target]);
  return left;
}
function fmt(s) {
  const m = Math.floor(s / 60);
  const sec = s % 60;
  if (m >= 60) return `${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}`;
  return `${m}:${String(sec).padStart(2, "0")}`;
}
export {
  TournamentDetail as component
};
