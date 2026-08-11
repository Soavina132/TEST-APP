import { j as jsxRuntimeExports, r as reactExports } from "../_libs/react.mjs";
import { L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as Trophy, q as LoaderCircle, U as Users, f as Coins, aQ as CalendarClock, Z as Zap } from "../_libs/lucide-react.mjs";
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
function TournamentsPage() {
  const [tab, setTab] = reactExports.useState("open");
  const [rows, setRows] = reactExports.useState([]);
  const [counts, setCounts] = reactExports.useState({});
  const [loading, setLoading] = reactExports.useState(true);
  const load = reactExports.useCallback(async () => {
    const statuses = tab === "open" ? ["open"] : tab === "running" ? ["running", "paused"] : ["finished", "cancelled"];
    const {
      data
    } = await supabase.from("tournaments").select("*").in("status", statuses).order("created_at", {
      ascending: false
    }).limit(50);
    const list = data || [];
    setRows(list);
    if (list.length) {
      const {
        data: ents
      } = await supabase.from("tournament_entrants").select("tournament_id").in("tournament_id", list.map((r) => r.id));
      const c = {};
      (ents || []).forEach((e) => {
        c[e.tournament_id] = (c[e.tournament_id] || 0) + 1;
      });
      setCounts(c);
    }
    setLoading(false);
  }, [tab]);
  reactExports.useEffect(() => {
    let dt;
    const debouncedLoad = () => {
      clearTimeout(dt);
      dt = setTimeout(load, 800);
    };
    setLoading(true);
    load();
    const ch = supabase.channel("tournaments-list").on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournaments"
    }, debouncedLoad).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournament_entrants"
    }, debouncedLoad).subscribe();
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
    };
  }, [load]);
  const tabConfig = [["open", "Ouverts", "bg-emerald-500"], ["running", "En cours", "bg-amber-500"], ["finished", "Terminés", "bg-secondary"]];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-4 space-y-4 pb-24", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("header", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-10 rounded-2xl bg-primary/15 grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-5 h-5 text-primary" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold", children: "Tournois" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground", children: "Affrontez d'autres joueurs et gagnez des récompenses" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: tabConfig.map(([k, l, dot]) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setTab(k), className: `flex items-center gap-1.5 px-4 py-2 rounded-full text-sm font-semibold transition-colors ${tab === k ? "bg-primary text-primary-foreground" : "bg-secondary text-secondary-foreground"}`, children: [
      tab === k && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `w-1.5 h-1.5 rounded-full ${dot} ${k === "running" ? "animate-pulse" : ""}` }),
      l
    ] }, k)) }),
    loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-16", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-muted-foreground" }) }) : rows.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-10 text-center space-y-2 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-10 h-10 text-muted-foreground mx-auto opacity-40" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: tab === "open" ? "Aucun tournoi ouvert pour le moment." : tab === "running" ? "Aucun tournoi en cours." : "Aucun tournoi terminé." })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-3", children: rows.map((t) => {
      const g = GAMES[t.game_slug] ?? {
        emoji: "🏆",
        label: t.game_slug
      };
      const n = counts[t.id] ?? 0;
      const netPrize = Math.round(Number(t.prize_pool_ar) * (100 - Number(t.platform_pct)) / 100 + Number(t.admin_prize_pool_ar));
      const isFull = n >= t.max_players;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs(Link, { to: "/tournaments/$id", params: {
        id: t.id
      }, className: "block rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] active:scale-[0.99] transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start gap-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-12 h-12 rounded-2xl bg-secondary grid place-items-center text-2xl shrink-0", children: g.emoji }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "font-bold truncate text-sm", children: t.name }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(StatusPill, { status: t.status })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
              g.label,
              " · ",
              t.format === "pools" ? "Poules + finale" : "Élimination",
              " · ",
              t.players_per_match,
              "j/match"
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap items-center gap-3 mt-3 text-xs font-semibold", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `inline-flex items-center gap-1 ${isFull ? "text-destructive" : "text-muted-foreground"}`, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3.5 h-3.5" }),
            n,
            "/",
            t.max_players,
            isFull && " · complet"
          ] }),
          netPrize > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 text-amber-600", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3.5 h-3.5" }),
            netPrize.toLocaleString("fr-FR"),
            " Ar"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 text-muted-foreground", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-3.5 h-3.5" }),
            Number(t.entry_fee_ar) > 0 ? `${Number(t.entry_fee_ar).toLocaleString("fr-FR")} Ar` : "Gratuit"
          ] }),
          t.starts_at && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 text-muted-foreground", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CalendarClock, { className: "w-3.5 h-3.5" }),
            new Date(t.starts_at).toLocaleString("fr-FR", {
              day: "2-digit",
              month: "short",
              hour: "2-digit",
              minute: "2-digit"
            })
          ] }),
          t.status === "running" && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 text-primary", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-3.5 h-3.5" }),
            t.auto_advance ? "Auto" : "Manuel"
          ] })
        ] }),
        t.status === "open" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-2.5 h-1.5 rounded-full bg-secondary overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `h-full rounded-full transition-all ${isFull ? "bg-destructive" : "bg-primary"}`, style: {
          width: `${Math.min(100, n / t.max_players * 100)}%`
        } }) })
      ] }, t.id);
    }) })
  ] });
}
function StatusPill({
  status
}) {
  const map = {
    draft: {
      l: "Brouillon",
      c: "bg-secondary text-muted-foreground"
    },
    open: {
      l: "Inscriptions",
      c: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300"
    },
    running: {
      l: "En cours",
      c: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300"
    },
    paused: {
      l: "En pause",
      c: "bg-secondary text-muted-foreground"
    },
    finished: {
      l: "Terminé",
      c: "bg-secondary text-muted-foreground"
    },
    cancelled: {
      l: "Annulé",
      c: "bg-secondary text-muted-foreground"
    }
  };
  const s = map[status] ?? map.draft;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `px-2 py-0.5 rounded-full text-[10px] font-bold shrink-0 ${s.c}`, children: s.l });
}
export {
  StatusPill,
  TournamentsPage as component
};
