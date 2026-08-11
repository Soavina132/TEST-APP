import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as useT } from "./router-CRCBvenY.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/sonner.mjs";
import { v as Radio, U as Users, f as Coins, a7 as Eye } from "../_libs/lucide-react.mjs";
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
function LivePage() {
  const {
    t
  } = useT();
  const navigate = useNavigate();
  const [games, setGames] = reactExports.useState([]);
  const [sort, setSort] = reactExports.useState("popular");
  const [enabled, setEnabled] = reactExports.useState(true);
  const load = async () => {
    const {
      data: s
    } = await supabase.from("app_settings").select("live_enabled").eq("id", 1).maybeSingle();
    setEnabled(!!s?.live_enabled);
    const {
      data
    } = await supabase.rpc("list_live_games");
    setGames((data || []).filter((g) => g.game_type !== "rami" && g.game_type !== "fanorona"));
  };
  reactExports.useEffect(() => {
    load();
    let heartbeat = null;
    const ch = supabase.channel("live").on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "ludo_games",
      filter: "status=eq.open"
    }, load).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "ludo_games",
      filter: "status=eq.playing"
    }, load).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "domino_games",
      filter: "status=eq.open"
    }, load).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "domino_games",
      filter: "status=eq.playing"
    }, load).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "chess_games",
      filter: "status=eq.open"
    }, load).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "chess_games",
      filter: "status=eq.playing"
    }, load).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "fanorona_games",
      filter: "status=eq.open"
    }, load).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "fanorona_games",
      filter: "status=eq.playing"
    }, load).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "rami_games",
      filter: "status=eq.open"
    }, load).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "rami_games",
      filter: "status=eq.playing"
    }, load).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "poker_games",
      filter: "status=eq.open"
    }, load).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "poker_games",
      filter: "status=eq.playing"
    }, load).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "game_spectators"
    }, load).subscribe((status) => {
      if (status === "SUBSCRIBED") {
        if (heartbeat) clearInterval(heartbeat);
        heartbeat = setInterval(() => load(), 1e4);
      } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
        if (heartbeat) {
          clearInterval(heartbeat);
          heartbeat = null;
        }
        setTimeout(() => load(), 300);
      }
    });
    return () => {
      supabase.removeChannel(ch);
      if (heartbeat) clearInterval(heartbeat);
    };
  }, []);
  const routeFor = (g) => {
    const gt = g.game_type || "ludo";
    if (gt === "domino") return {
      to: "/jeux/domino/$id",
      params: {
        id: g.id
      }
    };
    if (gt === "chess") return {
      to: "/jeux/chess/$id",
      params: {
        id: g.id
      }
    };
    if (gt === "fanorona") return {
      to: "/jeux/fanorona/$id",
      params: {
        id: g.id
      }
    };
    if (gt === "rami") return {
      to: "/jeux/rami/$id",
      params: {
        id: g.id
      }
    };
    if (gt === "poker") return {
      to: "/jeux/poker/$id",
      params: {
        id: g.id
      }
    };
    return {
      to: "/jeux/ludo/$id",
      params: {
        id: g.id
      },
      search: {
        spectate: 1
      }
    };
  };
  const labelFor = (gt) => {
    switch (gt) {
      case "domino":
        return "Domino";
      case "chess":
        return "Échecs";
      case "fanorona":
        return "Fanorona";
      case "rami":
        return "Rami";
      case "poker":
        return "Poker";
      default:
        return "Ludo";
    }
  };
  const sorted = [...games].sort((a, b) => {
    if (sort === "popular") return b.spectators_count - a.spectators_count;
    if (sort === "recent") return new Date(b.started_at).getTime() - new Date(a.started_at).getTime();
    return new Date(a.started_at).getTime() - new Date(b.started_at).getTime();
  });
  if (!enabled) return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-muted-foreground", children: t("live_disabled_msg") });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("h1", { className: "text-2xl font-extrabold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Radio, { className: "text-destructive" }),
      " ",
      t("live_title_full")
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: [["popular", "popular_sort"], ["recent", "recent_sort"], ["ending", "advanced_sort"]].map(([k, lkey]) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setSort(k), className: `px-4 py-2 rounded-full text-sm font-semibold ${sort === k ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: t(lkey) }, k)) }),
    sorted.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-8 text-center text-muted-foreground", children: t("no_live_games") }),
    sorted.map((g) => {
      const r = routeFor(g);
      return /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate(r), className: "w-full rounded-3xl bg-card p-4 shadow-sm hover:bg-accent text-left", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "inline-flex w-2 h-2 rounded-full bg-destructive animate-pulse" }),
            " ",
            t("live_badge"),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2 py-0.5 rounded-full bg-primary/15 text-primary text-[10px] font-extrabold uppercase tracking-wider", children: labelFor(g.game_type) })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm text-muted-foreground flex items-center gap-3 mt-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3.5 h-3.5" }),
              " ",
              g.players_count,
              "/",
              g.max_players
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-3.5 h-3.5" }),
              " ",
              Number(g.pot).toLocaleString("fr-FR"),
              " Ar"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-3.5 h-3.5" }),
              " ",
              g.spectators_count
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground mt-1", children: [
            t("started_at_label"),
            ": ",
            g.started_at ? new Date(g.started_at).toLocaleTimeString("fr-FR") : "—",
            " · ",
            g.mode
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold text-sm", children: t("watch_btn") })
      ] }) }, `${g.game_type}-${g.id}`);
    })
  ] });
}
export {
  LivePage as component
};
