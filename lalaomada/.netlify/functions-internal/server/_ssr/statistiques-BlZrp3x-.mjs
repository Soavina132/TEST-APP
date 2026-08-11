import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { D as Dialog, a as DialogContent, b as DialogHeader, c as DialogTitle } from "./dialog-BkiCxqYs.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/sonner.mjs";
import { A as ArrowLeft, a as Trophy, G as Gamepad2, b as ChevronRight, F as Flame, aP as Calendar, l as Clock, q as LoaderCircle } from "../_libs/lucide-react.mjs";
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
import "tslib";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "../_libs/supabase__functions-js.mjs";
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
const BADGES = [{
  min: 1,
  label: "Bronze",
  color: "from-amber-700 to-amber-500",
  icon: "🥉"
}, {
  min: 2,
  label: "Bronze",
  color: "from-amber-700 to-amber-500",
  icon: "🥉"
}, {
  min: 3,
  label: "Argent",
  color: "from-slate-400 to-slate-300",
  icon: "🥈"
}, {
  min: 4,
  label: "Argent+",
  color: "from-slate-400 to-slate-300",
  icon: "🥈"
}, {
  min: 5,
  label: "Or",
  color: "from-yellow-500 to-amber-400",
  icon: "🥇"
}, {
  min: 6,
  label: "Or+",
  color: "from-yellow-500 to-amber-400",
  icon: "🥇"
}, {
  min: 7,
  label: "Diamant",
  color: "from-cyan-400 to-blue-500",
  icon: "💎"
}, {
  min: 8,
  label: "Diamant+",
  color: "from-cyan-400 to-blue-500",
  icon: "💎"
}, {
  min: 9,
  label: "Platine",
  color: "from-violet-500 to-fuchsia-500",
  icon: "👑"
}, {
  min: 10,
  label: "Platine Max",
  color: "from-violet-500 to-fuchsia-500",
  icon: "👑"
}];
const LEVEL_THRESHOLDS = [0, 1, 3, 7, 12, 20, 35, 60, 100, 200];
function getBadge(level) {
  return BADGES[Math.min(Math.max(level, 1), BADGES.length) - 1] || BADGES[0];
}
const EMOJI = {
  ludo: "🎲",
  chess: "♜",
  domino: "🁣",
  fanorona: "♟",
  rami: "🂡",
  poker: "🃏"
};
const LABEL = {
  ludo: "Ludo",
  chess: "Échecs",
  domino: "Domino",
  fanorona: "Fanorona",
  rami: "Rami",
  poker: "Poker"
};
const ROUTE = {
  ludo: "/jeux/ludo/$id",
  chess: "/jeux/chess/$id",
  domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  rami: "/jeux/rami/$id",
  poker: "/jeux/poker/$id"
};
const PART_TABLE = {
  domino: "domino_participants",
  fanorona: "fanorona_participants",
  rami: "rami_participants",
  poker: "poker_players"
};
const GAME_TABLE = {
  domino: "domino_games",
  fanorona: "fanorona_games",
  rami: "rami_games",
  poker: "poker_games"
};
function fmtDate(d) {
  if (!d) return "—";
  return new Date(d).toLocaleDateString("fr-FR", {
    day: "2-digit",
    month: "short",
    year: "2-digit"
  });
}
function fmtAr(n) {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-MG").format(Math.round(Number(n) || 0)) + " Ar";
}
function MatchListDialog({
  open,
  onClose,
  title,
  icon,
  matches,
  loading,
  onOpen
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Dialog, { open, onOpenChange: (o) => {
    if (!o) onClose();
  }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogContent, { className: "max-w-md max-h-[80vh] flex flex-col p-0 gap-0", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(DialogHeader, { className: "px-4 pt-4 pb-2 border-b border-border/30 shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogTitle, { className: "flex items-center gap-2 text-base font-extrabold", children: [
      icon,
      " ",
      title,
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground font-normal text-sm", children: [
        "(",
        matches.length,
        ")"
      ] })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "overflow-y-auto flex-1 px-4 py-3 space-y-2", children: loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-8", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-primary" }) }) : matches.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center py-8 text-sm text-muted-foreground", children: "Aucune partie." }) : matches.map((g) => {
      const isWin = g.won === true;
      const isLoss = g.status === "finished" && !isWin;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onOpen(g), className: "w-full rounded-xl bg-secondary/40 border border-border/30 p-3 flex items-center gap-3 active:scale-[0.98] transition-transform text-left", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${isWin ? "bg-emerald-500/10 border border-emerald-500/20" : isLoss ? "bg-destructive/10 border border-destructive/20" : "bg-secondary border border-border/40"}`, children: EMOJI[g.slug] ?? "🎮" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm flex items-center gap-1.5", children: [
            LABEL[g.slug] ?? g.slug,
            isWin && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-emerald-500", children: "VICTOIRE" }),
            isLoss && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-destructive", children: "DÉFAITE" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-0.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] text-muted-foreground", children: [
              "Mise ",
              fmtAr(g.stake)
            ] }),
            g.winner_name && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] text-muted-foreground/70", children: [
              "Gagnant: ",
              g.winner_name
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right shrink-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: fmtDate(g.finished_at || g.created_at) }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-4 h-4 text-muted-foreground mt-0.5 ml-auto" })
        ] })
      ] }, `${g.slug}-${g.id}`);
    }) })
  ] }) });
}
function StatistiquesPage() {
  const {
    user,
    profile
  } = useAuth();
  const navigate = useNavigate();
  const [playerStats, setPlayerStats] = reactExports.useState(null);
  const [myRank, setMyRank] = reactExports.useState(null);
  const [rankLoaded, setRankLoaded] = reactExports.useState(false);
  const [loaded, setLoaded] = reactExports.useState(false);
  const [allMatches, setAllMatches] = reactExports.useState([]);
  const [matchesLoaded, setMatchesLoaded] = reactExports.useState(false);
  const [matchesLoading, setMatchesLoading] = reactExports.useState(false);
  const [dialogType, setDialogType] = reactExports.useState(null);
  reactExports.useEffect(() => {
    if (!user) return;
    const uid = user.id;
    const currentPseudo = profile?.pseudo;
    supabase.from("v_player_stats").select("*").eq("id", uid).maybeSingle().then(({
      data
    }) => {
      if (data) setPlayerStats(data);
      setLoaded(true);
    });
    supabase.rpc("leaderboard_winners", {
      _limit: 200
    }).then(({
      data
    }) => {
      setRankLoaded(true);
      if (!data) return;
      const idx = data.findIndex((r) => r.id === uid || currentPseudo && r.name === currentPseudo);
      if (idx >= 0) setMyRank(data[idx].rank);
    });
  }, [user?.id, profile?.pseudo]);
  const loadMatches = reactExports.useCallback(async () => {
    if (!user) return;
    setMatchesLoading(true);
    try {
      const uid = user.id;
      const all = [];
      const {
        data: ludoData
      } = await supabase.rpc("my_games");
      const ludo = ludoData || {
        ongoing: [],
        finished: []
      };
      (ludo.finished || []).forEach((g) => all.push({
        ...g,
        slug: "ludo"
      }));
      const {
        data: chessRows
      } = await supabase.from("chess_games").select("*").or(`white_id.eq.${uid},black_id.eq.${uid}`).order("created_at", {
        ascending: false
      }).limit(100);
      (chessRows || []).forEach((g) => {
        if (g.status === "finished") {
          all.push({
            ...g,
            slug: "chess",
            won: g.winner_id === uid
          });
        }
      });
      await Promise.all(Object.entries(PART_TABLE).map(async ([slug, partTable]) => {
        if (!partTable) return;
        const {
          data: parts
        } = await supabase.from(partTable).select(`*, game:${GAME_TABLE[slug]}(*)`).eq("user_id", uid);
        (parts || []).forEach((r) => {
          const g = r.game;
          if (!g) return;
          if (g.status === "finished") {
            all.push({
              ...g,
              slug,
              won: g.winner_id === uid,
              forfeited: r.forfeited
            });
          }
        });
      }));
      all.sort((a, b) => new Date(b.finished_at || b.created_at || 0).getTime() - new Date(a.finished_at || a.created_at || 0).getTime());
      setAllMatches(all);
    } finally {
      setMatchesLoading(false);
      setMatchesLoaded(true);
    }
  }, [user]);
  const openDialog = (type) => {
    setDialogType(type);
    if (!matchesLoaded) loadMatches();
  };
  const goToGame = (g) => {
    const route = ROUTE[g.slug];
    if (!route) return;
    setDialogType(null);
    navigate({
      to: route,
      params: {
        id: g.id
      }
    });
  };
  const p = profile || {};
  const ps = playerStats || {};
  const totalWins = ps.total_wins ?? p.total_wins ?? 0;
  const totalGames = ps.total_games ?? p.total_games ?? 0;
  const totalLosses = Math.max(totalGames - totalWins, 0);
  const level = ps.player_level ?? p.player_level ?? 1;
  const dailyStreak = ps.daily_streak ?? p.daily_streak ?? 0;
  const badge = getBadge(level);
  const memberSince = p.created_at ? new Date(p.created_at) : null;
  const nextThreshold = LEVEL_THRESHOLDS[level] ?? null;
  const prevThreshold = LEVEL_THRESHOLDS[level - 1] ?? 0;
  const progressPct = nextThreshold ? Math.min(100, Math.round((totalWins - prevThreshold) / (nextThreshold - prevThreshold) * 100)) : 100;
  const winsToNext = nextThreshold ? Math.max(nextThreshold - totalWins, 0) : 0;
  const dialogMatches = dialogType === "wins" ? allMatches.filter((m) => m.won === true) : dialogType === "losses" ? allMatches.filter((m) => m.status === "finished" && m.won !== true) : allMatches;
  const dialogTitle = dialogType === "wins" ? "Victoires" : dialogType === "losses" ? "Défaites" : "Toutes les parties";
  const dialogIcon = dialogType === "wins" ? /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-5 h-5 text-emerald-500" }) : dialogType === "losses" ? /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-5 h-5 rotate-90 text-destructive" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-5 h-5 text-primary" });
  if (!loaded) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-muted-foreground", children: "Chargement…" });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "mx-auto max-w-md flex flex-col gap-3 p-3 pb-20 min-h-screen", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate({
        to: "/profile",
        search: {}
      }), className: "p-2 rounded-full bg-secondary/60 active:scale-90 transition-transform", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-5 h-5 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold", children: "Statistiques" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 p-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-12 h-12 rounded-full flex items-center justify-center text-xl bg-gradient-to-br ${badge.color}`, children: badge.icon }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-sm", children: badge.label }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3 mt-0.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] text-muted-foreground flex items-center gap-0.5", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold text-foreground", children: [
              "Niv. ",
              level
            ] }) }),
            rankLoaded && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] text-muted-foreground flex items-center gap-0.5", children: [
              "Rang ",
              /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold text-amber-500", children: [
                "#",
                myRank ?? "—"
              ] })
            ] })
          ] })
        ] })
      ] }),
      nextThreshold ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-[10px] text-muted-foreground mb-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Progression niveau suivant" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-semibold", children: [
            winsToNext,
            " vict. restantes"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-1.5 rounded-full bg-secondary/60 overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-full rounded-full bg-primary transition-all", style: {
          width: `${progressPct}%`
        } }) })
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-3 text-[10px] text-center text-primary font-semibold", children: "🏆 Niveau maximum atteint !" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openDialog("all"), className: "rounded-2xl bg-card border border-border/40 p-3 flex flex-col items-center justify-center gap-1 active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-5 h-5 text-muted-foreground" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xl font-black tabular-nums leading-none", children: totalGames }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold uppercase tracking-wide text-muted-foreground", children: "Parties" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openDialog("wins"), className: "rounded-2xl bg-card border border-border/40 p-3 flex flex-col items-center justify-center gap-1 active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-5 h-5 text-emerald-500" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xl font-black tabular-nums leading-none text-emerald-500", children: totalWins }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold uppercase tracking-wide text-muted-foreground", children: "Victoires" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openDialog("losses"), className: "rounded-2xl bg-card border border-border/40 p-3 flex flex-col items-center justify-center gap-1 active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-5 h-5 rotate-90 text-destructive" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xl font-black tabular-nums leading-none text-destructive", children: totalLosses }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold uppercase tracking-wide text-muted-foreground", children: "Défaites" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 divide-y divide-border/30", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-4 py-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Flame, { className: "w-4 h-4 text-orange-500" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Série quotidienne" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold text-sm", children: [
          dailyStreak,
          " jour",
          dailyStreak > 1 ? "s" : ""
        ] })
      ] }),
      memberSince && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-4 py-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Calendar, { className: "w-4 h-4 text-sky-500" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Membre depuis" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: memberSince.toLocaleDateString("fr-FR", {
          day: "2-digit",
          month: "long",
          year: "numeric"
        }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-4 py-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-4 h-4 text-primary" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Objectif niveau suivant" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: nextThreshold ? `${nextThreshold} victoires` : "Niveau max" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(MatchListDialog, { open: dialogType !== null, onClose: () => setDialogType(null), title: dialogTitle, icon: dialogIcon, matches: dialogMatches, loading: matchesLoading, onOpen: goToGame })
  ] });
}
export {
  StatistiquesPage as component
};
