import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as useT, u as useAuth } from "./router-CRCBvenY.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/sonner.mjs";
import { y as Shield, F as Flame, Z as Zap, ay as Crown, a as Trophy, aN as Star, aO as Medal } from "../_libs/lucide-react.mjs";
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
const LEVELS = [{
  min: 0,
  max: 0,
  labelKey: "level_beginner",
  color: "text-slate-400",
  bg: "bg-slate-100 dark:bg-slate-800",
  icon: "⚪"
}, {
  min: 1,
  max: 2,
  labelKey: "level_novice",
  color: "text-green-500",
  bg: "bg-green-100 dark:bg-green-900/30",
  icon: "🟢"
}, {
  min: 3,
  max: 6,
  labelKey: "level_intermediate",
  color: "text-blue-500",
  bg: "bg-blue-100 dark:bg-blue-900/30",
  icon: "🔵"
}, {
  min: 7,
  max: 11,
  labelKey: "level_advanced",
  color: "text-violet-500",
  bg: "bg-violet-100 dark:bg-violet-900/30",
  icon: "🟣"
}, {
  min: 12,
  max: 19,
  labelKey: "level_expert",
  color: "text-amber-500",
  bg: "bg-amber-100 dark:bg-amber-900/30",
  icon: "🟡"
}, {
  min: 20,
  max: 34,
  labelKey: "level_master",
  color: "text-orange-500",
  bg: "bg-orange-100 dark:bg-orange-900/30",
  icon: "🟠"
}, {
  min: 35,
  max: 59,
  labelKey: "level_grandmaster",
  color: "text-red-500",
  bg: "bg-red-100 dark:bg-red-900/30",
  icon: "🔴"
}, {
  min: 60,
  max: 99,
  labelKey: "level_champion",
  color: "text-rose-600",
  bg: "bg-rose-100 dark:bg-rose-900/30",
  icon: "🏅"
}, {
  min: 100,
  max: 199,
  labelKey: "level_elite",
  color: "text-fuchsia-600",
  bg: "bg-fuchsia-100 dark:bg-fuchsia-900/30",
  icon: "💎"
}, {
  min: 200,
  max: Infinity,
  labelKey: "level_legend",
  color: "text-yellow-500",
  bg: "bg-yellow-50 dark:bg-yellow-900/20",
  icon: "👑"
}];
function getLevel(wins) {
  return LEVELS.find((l) => wins >= l.min && wins <= l.max) ?? LEVELS[0];
}
function LevelBadge({
  wins,
  compact = false
}) {
  const {
    t
  } = useT();
  const lvl = getLevel(wins);
  if (compact) return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-[10px] font-bold px-1.5 py-0.5 rounded-full ${lvl.bg} ${lvl.color}`, children: [
    lvl.icon,
    " ",
    t(lvl.labelKey)
  ] });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-xs font-bold px-2.5 py-1 rounded-full ${lvl.bg} ${lvl.color} flex items-center gap-1`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: lvl.icon }),
    " ",
    t(lvl.labelKey)
  ] });
}
function RankIcon({
  rank
}) {
  if (rank === 1) return /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-5 h-5 text-amber-400" });
  if (rank === 2) return /* @__PURE__ */ jsxRuntimeExports.jsx(Medal, { className: "w-5 h-5 text-slate-400" });
  if (rank === 3) return /* @__PURE__ */ jsxRuntimeExports.jsx(Medal, { className: "w-5 h-5 text-orange-400" });
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-full bg-secondary flex items-center justify-center font-bold text-xs text-muted-foreground", children: rank });
}
function PodiumRow({
  player,
  rank,
  myId
}) {
  const {
    t
  } = useT();
  const wins = Number(player.wins ?? 0);
  const isMe = player.id === myId || player.user_id === myId;
  const podiumBg = rank === 1 ? "bg-gradient-to-r from-amber-500/8 to-transparent border-l-4 border-amber-400" : rank === 2 ? "bg-gradient-to-r from-slate-400/6 to-transparent border-l-4 border-slate-400/50" : rank === 3 ? "bg-gradient-to-r from-orange-500/6 to-transparent border-l-4 border-orange-400/50" : "";
  const inner = /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 flex items-center justify-center shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RankIcon, { rank }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-full bg-secondary overflow-hidden grid place-items-center font-bold text-sm ring-2 ${rank === 1 ? "ring-amber-400/60" : rank === 2 ? "ring-slate-400/40" : rank === 3 ? "ring-orange-400/40" : "ring-transparent"}`, children: player.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: player.avatar_url, alt: player.name ?? player.pseudo, width: 40, height: 40, loading: "lazy", decoding: "async", className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: (player.name ?? player.pseudo ?? "?").slice(0, 2).toUpperCase() }) }),
      rank <= 3 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -top-1 -right-1 text-xs", children: rank === 1 ? "👑" : rank === 2 ? "🥈" : "🥉" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0 space-y-0.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center gap-1.5 flex-wrap", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `font-bold text-sm truncate ${isMe ? "text-primary" : ""}`, children: [
        player.name ?? player.pseudo ?? t("player_fallback"),
        isMe && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-primary ml-1", children: t("you_suffix") })
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(LevelBadge, { wins, compact: true })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm tabular-nums flex items-center gap-1 justify-end", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3.5 h-3.5 text-amber-500" }),
        " ",
        wins
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: wins !== 1 ? t("win_plural") : t("win_singular") })
    ] })
  ] });
  const rowClass = `flex items-center gap-3 px-4 py-3 border-b border-border/40 last:border-0 transition-colors hover:bg-accent/30 ${podiumBg} ${isMe ? "ring-2 ring-primary/30 ring-inset" : ""}`;
  if (player.id) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/joueur/$id", params: {
      id: player.id
    }, className: rowClass, children: inner });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: rowClass, children: inner });
}
function LevelGuide() {
  const {
    t
  } = useT();
  const [open, setOpen] = reactExports.useState(false);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card shadow-sm border border-border/40 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setOpen(!open), className: "w-full flex items-center justify-between px-5 py-4 font-bold text-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Star, { className: "w-4 h-4 text-amber-500" }),
        " ",
        t("level_guide_title")
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground", children: open ? "▲" : "▼" })
    ] }),
    open && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 pb-4 grid grid-cols-2 sm:grid-cols-3 gap-2", children: LEVELS.map((l) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-xl p-2.5 ${l.bg} flex items-center gap-2`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-lg", children: l.icon }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-xs font-bold ${l.color}`, children: t(l.labelKey) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: l.max === Infinity ? `≥ ${l.min} ${t("win_plural")}` : l.min === 0 ? `0 ${t("win_singular")}` : `${l.min}–${l.max} ${t("win_plural")}` })
      ] })
    ] }, l.labelKey)) })
  ] });
}
function RankingsPage() {
  const {
    t
  } = useT();
  const {
    user
  } = useAuth();
  const [period, setPeriod] = reactExports.useState("all");
  const [gameSlug, setGameSlug] = reactExports.useState("all");
  const [items, setItems] = reactExports.useState([]);
  const [seasons, setSeasons] = reactExports.useState([]);
  const [myRank, setMyRank] = reactExports.useState(null);
  const [loading, setLoading] = reactExports.useState(false);
  reactExports.useEffect(() => {
    setLoading(true);
    (async () => {
      const {
        data
      } = await supabase.rpc("leaderboard_winners", {
        _period: period,
        _limit: 100,
        _slug: gameSlug === "all" ? null : gameSlug
      });
      const list = data || [];
      setItems(list);
      if (user) {
        const myIdx = list.findIndex((p) => p.id === user.id || p.user_id === user.id);
        setMyRank(myIdx >= 0 ? myIdx + 1 : null);
      }
      setLoading(false);
    })();
    supabase.from("seasons").select("*").order("starts_at", {
      ascending: false
    }).limit(5).then(({
      data
    }) => setSeasons(data || []));
  }, [period, gameSlug, user?.id]);
  const periods = [{
    id: "all",
    label: t("period_all"),
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Shield, { className: "w-3.5 h-3.5" })
  }, {
    id: "month",
    label: t("period_month"),
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Flame, { className: "w-3.5 h-3.5" })
  }, {
    id: "week",
    label: t("period_week"),
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-3.5 h-3.5" })
  }];
  const top3 = items.slice(0, 3);
  const rest = items.slice(3);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-2xl mx-auto px-4 py-5 space-y-4", style: {
    background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.04) 0%, transparent 60%)"
  }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between pt-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h1", { className: "text-2xl font-extrabold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-2xl", children: "🏆" }),
        " ",
        t("rankings")
      ] }),
      myRank && myRank <= 3 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-amber-500/15 border border-amber-500/25", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-3.5 h-3.5 text-amber-500" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-amber-500 font-bold text-xs", children: [
          "#",
          myRank,
          " Vous"
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 bg-card/80 p-1 rounded-2xl shadow-sm border border-white/8 backdrop-blur", children: periods.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setPeriod(p.id), className: `flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-xl text-xs sm:text-sm font-bold transition-all ${period === p.id ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "text-muted-foreground hover:text-foreground"}`, children: [
      p.icon,
      " ",
      p.label
    ] }, p.id)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 overflow-x-auto pb-1 -mt-1 scrollbar-none", children: [{
      slug: "all",
      label: "Tous",
      icon: "🎮"
    }, {
      slug: "ludo",
      label: "Ludo",
      icon: "🎲"
    }, {
      slug: "domino",
      label: "Domino",
      icon: "🁫"
    }, {
      slug: "fanorona",
      label: "Fanorona",
      icon: "🔴"
    }, {
      slug: "chess",
      label: "Échecs",
      icon: "♟️"
    }, {
      slug: "rami",
      label: "Rami",
      icon: "🃏"
    }, {
      slug: "poker",
      label: "Poker",
      icon: "♠️"
    }].map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setGameSlug(g.slug), className: `flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-bold whitespace-nowrap transition-all ${gameSlug === g.slug ? "bg-primary text-primary-foreground shadow-sm" : "bg-card border border-border/40 text-muted-foreground hover:text-foreground"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: g.icon }),
      " ",
      g.label
    ] }, g.slug)) }),
    myRank && myRank > 3 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-primary/8 border border-primary/20 px-4 py-3 flex items-center justify-between shadow-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-sm font-semibold text-primary", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }),
        " ",
        t("your_ranking")
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-primary text-xl", children: [
        "#",
        myRank
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card overflow-hidden shadow-md border border-white/8", children: loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-12", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" }) }) : items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-8 text-center text-muted-foreground text-sm", children: t("no_data") }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
      top3.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(PodiumRow, { player: p, rank: i + 1, myId: user?.id }, p.id ?? `top-${i}`)),
      rest.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 py-2 bg-white/3 border-y border-white/6 text-[10px] font-bold text-muted-foreground/50 uppercase tracking-[0.2em] flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 h-px bg-white/6" }),
        t("general_rank"),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 h-px bg-white/6" })
      ] }),
      rest.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(PodiumRow, { player: p, rank: i + 4, myId: user?.id }, p.id ?? `rest-${i}`))
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(LevelGuide, {}),
    seasons.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-md border border-white/8 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "text-amber-500 w-4 h-4" }),
        " ",
        t("ballon_dor")
      ] }),
      seasons.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/40 pt-3 space-y-0.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: s.name }),
          s.closed ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] bg-secondary px-2 py-0.5 rounded-full text-muted-foreground", children: t("season_ended") }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] bg-emerald-100 dark:bg-emerald-900/30 text-emerald-700 px-2 py-0.5 rounded-full font-bold animate-pulse", children: t("season_ongoing") })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground", children: [
          new Date(s.starts_at).toLocaleDateString("fr-FR"),
          " → ",
          new Date(s.ends_at).toLocaleDateString("fr-FR")
        ] }),
        s.reward_text && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-amber-600 font-semibold flex items-center gap-1 mt-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3 h-3" }),
          " ",
          s.reward_text
        ] }),
        s.closed && s.winner_id && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-amber-600 font-bold flex items-center gap-1 mt-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-3 h-3" }),
          " ",
          t("champion_designated"),
          " 🏆"
        ] })
      ] }, s.id))
    ] })
  ] });
}
export {
  RankingsPage as component
};
