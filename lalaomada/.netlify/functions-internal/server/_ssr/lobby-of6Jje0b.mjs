import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate, L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { u as useAuth, a as useT } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { u as useLiveAvailable } from "./use-live-available-aenEXr3_.mjs";
import { u as useAppSettings, D as DepotModal, R as RetraitModal } from "./WalletButton-BwZT8Njg.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { q as LoaderCircle, a3 as Wallet, a5 as ShieldCheck, aI as ShieldAlert, a0 as ArrowDownLeft, $ as ArrowUpRight, G as Gamepad2, a as Trophy, w as History, c as Gift, Z as Zap, U as Users, f as Coins, X, Q as LogOut, E as ExternalLink, aJ as Folder, aK as RotateCw } from "../_libs/lucide-react.mjs";
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
const ROUTE$1 = {
  ludo: "/jeux/ludo/$id",
  chess: "/jeux/chess/$id",
  domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  rami: "/jeux/rami/$id",
  poker: "/jeux/poker/$id"
};
const EMOJI$1 = {
  ludo: "🎲",
  chess: "♜",
  domino: "🁣",
  fanorona: "♟",
  rami: "🂡",
  poker: "🃏"
};
const LABEL$1 = {
  ludo: "Ludo",
  chess: "Échecs",
  domino: "Domino",
  fanorona: "Fanorona",
  rami: "Rami",
  poker: "Poker"
};
const PART_TABLE$1 = {
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
function MesPartiesSheet({ open, onClose }) {
  const { profile } = useAuth();
  const navigate = useNavigate();
  const [loading, setLoading] = reactExports.useState(false);
  const [ongoing, setOngoing] = reactExports.useState([]);
  const [finished, setFinished] = reactExports.useState([]);
  const [tab, setTab] = reactExports.useState("ongoing");
  const load = reactExports.useCallback(async () => {
    if (!profile?.id) return;
    setLoading(true);
    try {
      const uid = profile.id;
      const allOngoing = [];
      const allFinished = [];
      const { data: ludoData } = await supabase.rpc("my_games");
      const ludo = ludoData || { ongoing: [], finished: [] };
      (ludo.ongoing || []).forEach((g) => allOngoing.push({ ...g, slug: "ludo" }));
      (ludo.finished || []).forEach((g) => allFinished.push({ ...g, slug: "ludo" }));
      const { data: chessRows } = await supabase.from("chess_games").select("*").or(`white_id.eq.${uid},black_id.eq.${uid}`).order("created_at", { ascending: false }).limit(50);
      (chessRows || []).forEach((g) => {
        if (g.status === "open" || g.status === "playing") {
          allOngoing.push({ ...g, slug: "chess" });
        } else if (g.status === "finished" || g.status === "cancelled") {
          allFinished.push({ ...g, slug: "chess", won: g.winner_id === uid });
        }
      });
      await Promise.all(
        Object.entries(PART_TABLE$1).map(async ([slug, partTable]) => {
          if (!partTable) return;
          const { data: parts } = await supabase.from(partTable).select(`*, game:${GAME_TABLE[slug]}(*)`).eq("user_id", uid);
          (parts || []).forEach((r) => {
            const g = r.game;
            if (!g) return;
            if (g.status === "open" || g.status === "playing") {
              allOngoing.push({ ...g, slug });
            } else if (g.status === "finished" || g.status === "cancelled") {
              allFinished.push({ ...g, slug, won: g.winner_id === uid, forfeited: r.forfeited });
            }
          });
        })
      );
      const byDate = (a, b) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime();
      setOngoing(allOngoing.sort(byDate));
      setFinished(allFinished.sort(
        (a, b) => new Date(b.finished_at || 0).getTime() - new Date(a.finished_at || 0).getTime()
      ));
    } finally {
      setLoading(false);
    }
  }, [profile?.id]);
  reactExports.useEffect(() => {
    if (open) {
      load();
      setTab("ongoing");
    }
  }, [open, load]);
  const goTo = (g) => {
    const route = ROUTE$1[g.slug];
    if (!route) return;
    onClose();
    navigate({ to: route, params: { id: g.id } });
  };
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-end justify-center bg-black/60", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative w-full max-w-md rounded-t-3xl bg-background shadow-2xl max-h-[85vh] flex flex-col",
      onClick: (e) => e.stopPropagation(),
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-1 rounded-full bg-border mx-auto mt-3 shrink-0" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-5 pt-4 pb-2 shrink-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Folder, { className: "w-5 h-5 text-primary" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-black", children: "Mes parties" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "w-9 h-9 rounded-full bg-secondary grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2 px-5 pb-3 shrink-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "button",
            {
              onClick: () => setTab("ongoing"),
              className: `py-2.5 rounded-2xl font-bold text-sm transition-all ${tab === "ongoing" ? "text-primary-foreground shadow-md" : "bg-secondary text-foreground"}`,
              style: tab === "ongoing" ? { background: "var(--gradient-primary)" } : void 0,
              children: [
                "🎮 En cours (",
                ongoing.length,
                ")"
              ]
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "button",
            {
              onClick: () => setTab("finished"),
              className: `py-2.5 rounded-2xl font-bold text-sm transition-all ${tab === "finished" ? "text-primary-foreground shadow-md" : "bg-secondary text-foreground"}`,
              style: tab === "finished" ? { background: "var(--gradient-primary)" } : void 0,
              children: [
                "🏁 Terminées (",
                finished.length,
                ")"
              ]
            }
          )
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "overflow-y-auto flex-1 px-5 pb-8 space-y-3", children: loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-10", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-primary" }) }) : tab === "ongoing" ? ongoing.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Aucune partie en cours." }) : ongoing.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${g.status === "open" ? "bg-amber-500/10 border border-amber-500/15" : "bg-primary/10 border border-primary/15"}`, children: EMOJI$1[g.slug] ?? "🎮" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm", children: [
                  LABEL$1[g.slug] ?? g.slug,
                  " · ",
                  g.status === "open" ? "En attente" : "En cours"
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-0.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] text-muted-foreground", children: [
                    "Mise ",
                    Number(g.stake || 0).toLocaleString("fr-FR"),
                    " Ar"
                  ] }),
                  g.is_private && g.room_code && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-mono text-muted-foreground/60 bg-white/5 px-1.5 py-0.5 rounded", children: g.room_code })
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs(
                "button",
                {
                  onClick: () => goTo(g),
                  className: "flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-xs shadow-md shadow-primary/20 active:scale-95 transition-all shrink-0",
                  children: [
                    /* @__PURE__ */ jsxRuntimeExports.jsx(RotateCw, { className: "w-3.5 h-3.5" }),
                    " Reprendre"
                  ]
                }
              )
            ]
          },
          `${g.slug}-${g.id}`
        )) : finished.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Aucune partie terminée." }) : finished.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0 border ${g.won ? "bg-amber-500/10 border-amber-500/20" : g.forfeited ? "bg-destructive/8 border-destructive/15" : "bg-white/5 border-white/8"}`, children: g.won ? "🏆" : g.forfeited ? "🏳️" : "💔" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `font-bold text-sm ${g.won ? "text-amber-500" : g.forfeited ? "text-destructive" : ""}`, children: [
                  LABEL$1[g.slug] ?? g.slug,
                  " · ",
                  g.won ? "Victoire" : g.forfeited ? "Forfait" : "Défaite"
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
                  Number(g.stake || 0).toLocaleString("fr-FR"),
                  " Ar · ",
                  Number(g.pot || 0).toLocaleString("fr-FR"),
                  " Ar pot"
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground/50 shrink-0 text-right", children: g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : "" })
            ]
          },
          `${g.slug}-${g.id}`
        )) })
      ]
    }
  ) });
}
const ROUTE = {
  ludo: "/jeux/ludo/$id",
  chess: "/jeux/chess/$id",
  domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  rami: "/jeux/rami/$id",
  poker: "/jeux/poker/$id"
};
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
const PART_TABLE = {
  ludo: "ludo_participants",
  chess: null,
  domino: "domino_participants",
  fanorona: "fanorona_participants",
  rami: "rami_participants",
  poker: "poker_players"
};
function OngoingGameBanner() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [games, setGames] = reactExports.useState([]);
  const [dismissed, setDismissed] = reactExports.useState(false);
  const [quitting, setQuitting] = reactExports.useState(null);
  const load = reactExports.useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.rpc("my_ongoing_all");
    const list = Array.isArray(data) ? data : [];
    const active = list.filter((g) => !g.eliminated && g.status === "playing");
    setGames(active);
  }, [user]);
  reactExports.useEffect(() => {
    load();
    if (!user) return;
    let debounce;
    const debouncedLoad = () => {
      clearTimeout(debounce);
      debounce = setTimeout(load, 500);
    };
    const ch = supabase.channel(`ongoing-banner-${user.id}`);
    ["ludo_games", "domino_games", "fanorona_games", "chess_games", "rami_games", "poker_games"].forEach((t) => {
      ch.on("postgres_changes", { event: "UPDATE", schema: "public", table: t, filter: "status=eq.playing" }, debouncedLoad);
    });
    ch.subscribe();
    return () => {
      clearTimeout(debounce);
      supabase.removeChannel(ch);
    };
  }, [user, load]);
  reactExports.useEffect(() => {
    if (games.length === 0) setDismissed(false);
  }, [games.length]);
  if (dismissed || games.length === 0) return null;
  const rejoin = (g) => {
    const route = ROUTE[g.game_type];
    if (route) navigate({ to: route, params: { id: g.id } });
  };
  const quitGame = async (g) => {
    setQuitting(g.id);
    try {
      const partTable = PART_TABLE[g.game_type];
      if (partTable && user) {
        await supabase.from(partTable).update({ forfeited: true }).eq("game_id", g.id).eq("user_id", user.id);
      }
      if (g.game_type === "chess" && user) {
        const { data: cg } = await supabase.from("chess_games").select("white_id, black_id").eq("id", g.id).single();
        if (cg) {
          const winner = cg.white_id === user.id ? cg.black_id : cg.white_id;
          await supabase.from("chess_games").update({ status: "finished", winner_id: winner, finished_at: (/* @__PURE__ */ new Date()).toISOString() }).eq("id", g.id);
        }
      }
      setGames((prev) => prev.filter((x) => x.id !== g.id));
    } catch (e) {
    } finally {
      setQuitting(null);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-amber-500/10 border border-amber-500/25 p-3 space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 text-amber-600 dark:text-amber-400", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold text-xs", children: [
          "Partie",
          games.length > 1 ? "s" : "",
          " en cours"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setDismissed(true), className: "text-muted-foreground hover:text-foreground p-1", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3.5 h-3.5" }) })
    ] }),
    games.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2.5 bg-card rounded-xl p-2.5 border border-border/40", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9 rounded-lg bg-amber-500/15 grid place-items-center text-base shrink-0", children: EMOJI[g.game_type] ?? "🎮" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: LABEL[g.game_type] ?? g.game_type }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground", children: [
          Number(g.stake || 0).toLocaleString("fr-FR"),
          " Ar · ",
          g.players_count,
          " joueurs"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => rejoin(g),
            className: "flex items-center gap-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground font-bold text-[11px] shadow-sm active:scale-95 transition",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3 h-3" }),
              " Rejoindre"
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            onClick: () => quitGame(g),
            disabled: quitting === g.id,
            className: "flex items-center gap-1 px-3 py-2 rounded-lg bg-destructive/10 text-destructive font-bold text-[11px] active:scale-95 transition disabled:opacity-50",
            children: quitting === g.id ? "…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-3 h-3" }),
              " Quitter"
            ] })
          }
        )
      ] })
    ] }, g.id))
  ] });
}
function MoneyOffersSection() {
  const { t } = useT();
  const [items, setItems] = reactExports.useState([]);
  reactExports.useEffect(() => {
    const load = async () => {
      const { data } = await supabase.from("money_offers").select("*").eq("active", true).order("created_at", { ascending: false });
      const now = Date.now();
      setItems((data || []).filter((o) => !o.expires_at || new Date(o.expires_at).getTime() > now));
    };
    load();
    const ch = supabase.channel("offers").on("postgres_changes", { event: "*", schema: "public", table: "money_offers" }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, []);
  if (!items.length) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "rounded-3xl bg-gradient-to-br from-emerald-50 to-cyan-50 dark:from-emerald-950/40 dark:to-cyan-950/40 p-4 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold flex items-center gap-2 text-emerald-700 dark:text-emerald-300", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Gift, { className: "w-5 h-5" }),
      " ",
      t("earn_money_free")
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: items.map((o) => /* @__PURE__ */ jsxRuntimeExports.jsx(
      "a",
      {
        href: o.link || "#",
        target: o.link ? "_blank" : void 0,
        rel: "noopener noreferrer",
        className: "block bg-card rounded-2xl p-3 shadow-sm hover:shadow-md transition",
        children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-3", children: [
          o.image_url && /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: o.image_url, alt: o.title, width: 64, height: 64, loading: "lazy", decoding: "async", className: "w-16 h-16 rounded-xl object-cover shrink-0" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold leading-tight", children: o.title }),
            o.description && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground line-clamp-2 mt-0.5", children: o.description }),
            o.link && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-primary font-bold flex items-center gap-1 mt-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(ExternalLink, { className: "w-3 h-3" }),
              " ",
              t("participate_btn")
            ] })
          ] })
        ] })
      },
      o.id
    )) })
  ] });
}
const AUTO_SLIDE_MS = 4500;
const DEFAULT_GRADIENT = "from-primary to-orange-600";
function isInWindow(b) {
  const now = Date.now();
  if (b.starts_at && new Date(b.starts_at).getTime() > now) return false;
  if (b.ends_at && new Date(b.ends_at).getTime() < now) return false;
  return true;
}
function BannerCarousel() {
  const [banners, setBanners] = reactExports.useState([]);
  const [index, setIndex] = reactExports.useState(0);
  const timerRef = reactExports.useRef(null);
  const touchStartX = reactExports.useRef(null);
  const touchDeltaX = reactExports.useRef(0);
  const load = reactExports.useCallback(async () => {
    const { data } = await supabase.from("banners").select("*").eq("active", true).order("sort_order", { ascending: true });
    setBanners((data || []).filter(isInWindow));
  }, []);
  reactExports.useEffect(() => {
    load();
    const ch = supabase.channel("banners-carousel").on("postgres_changes", { event: "*", schema: "public", table: "banners" }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [load]);
  reactExports.useEffect(() => {
    if (index >= banners.length) setIndex(0);
  }, [banners.length, index]);
  const startTimer = reactExports.useCallback(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (banners.length <= 1) return;
    timerRef.current = setInterval(() => {
      setIndex((i) => (i + 1) % banners.length);
    }, AUTO_SLIDE_MS);
  }, [banners.length]);
  reactExports.useEffect(() => {
    startTimer();
    return () => {
      if (timerRef.current) clearInterval(timerRef.current);
    };
  }, [startTimer]);
  const goTo = (i) => {
    setIndex((i % banners.length + banners.length) % banners.length);
    startTimer();
  };
  const onTouchStart = (e) => {
    touchStartX.current = e.touches[0].clientX;
    touchDeltaX.current = 0;
  };
  const onTouchMove = (e) => {
    if (touchStartX.current == null) return;
    touchDeltaX.current = e.touches[0].clientX - touchStartX.current;
  };
  const onTouchEnd = () => {
    if (Math.abs(touchDeltaX.current) > 50) {
      if (touchDeltaX.current < 0) goTo(index + 1);
      else goTo(index - 1);
    }
    touchStartX.current = null;
    touchDeltaX.current = 0;
  };
  if (!banners.length) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative rounded-2xl overflow-hidden shadow-md shadow-primary/10 h-40",
      onTouchStart,
      onTouchMove,
      onTouchEnd,
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "div",
          {
            className: "flex h-full transition-transform duration-500 ease-out",
            style: { transform: `translateX(-${index * 100}%)` },
            children: banners.map((b) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full shrink-0 relative", children: [
              b.image_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: b.image_url, alt: b.title, className: "absolute inset-0 w-full h-full object-cover", loading: "lazy" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `absolute inset-0 bg-gradient-to-br ${b.bg_gradient || DEFAULT_GRADIENT}` }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-black/25" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative h-full flex flex-col justify-center gap-1.5 p-4 text-white", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-base font-black leading-tight drop-shadow", children: b.title }),
                b.subtitle && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs font-medium opacity-95 whitespace-pre-line leading-snug drop-shadow", children: b.subtitle }),
                b.button_text && (b.button_link?.startsWith("http") ? /* @__PURE__ */ jsxRuntimeExports.jsx(
                  "a",
                  {
                    href: b.button_link,
                    target: "_blank",
                    rel: "noopener noreferrer",
                    className: "mt-1 self-start px-4 py-1.5 rounded-full bg-white text-neutral-900 text-xs font-bold shadow",
                    children: b.button_text
                  }
                ) : /* @__PURE__ */ jsxRuntimeExports.jsx(
                  Link,
                  {
                    to: b.button_link || "/lobby",
                    className: "mt-1 self-start px-4 py-1.5 rounded-full bg-white text-neutral-900 text-xs font-bold shadow",
                    children: b.button_text
                  }
                ))
              ] })
            ] }, b.id))
          }
        ),
        banners.length > 1 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute bottom-2 left-0 right-0 flex items-center justify-center gap-1.5", children: banners.map((b, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            "aria-label": `Slide ${i + 1}`,
            onClick: () => goTo(i),
            className: `rounded-full transition-all ${i === index ? "w-4 h-1.5 bg-white" : "w-1.5 h-1.5 bg-white/50"}`
          },
          b.id
        )) })
      ]
    }
  );
}
function useMyOngoingCount() {
  const { user } = useAuth();
  const [count, setCount] = reactExports.useState(0);
  reactExports.useEffect(() => {
    if (!user) {
      setCount(0);
      return;
    }
    let cancelled = false;
    const load = async () => {
      const { data } = await supabase.rpc("my_ongoing_all");
      if (cancelled) return;
      const arr = Array.isArray(data) ? data : [];
      setCount(arr.filter((g) => !g.eliminated).length);
    };
    load();
    const tables = [
      "ludo_games",
      "domino_games",
      "fanorona_games",
      "chess_games",
      "rami_games",
      "poker_games"
    ];
    const ch = supabase.channel(`my-ongoing-${user.id}`);
    tables.forEach((t) => {
      ch.on("postgres_changes", { event: "*", schema: "public", table: t }, load);
    });
    ch.subscribe();
    const timer = setInterval(load, 45e3);
    return () => {
      cancelled = true;
      supabase.removeChannel(ch);
      clearInterval(timer);
    };
  }, [user?.id]);
  return count;
}
const GAME_DEFS = {
  ludo: {
    emoji: "🎲",
    label: "Ludo"
  },
  domino: {
    emoji: "🁣",
    label: "Domino"
  },
  fanorona: {
    emoji: "♟",
    label: "Fanorona"
  },
  chess: {
    emoji: "♜",
    label: "Échecs"
  },
  poker: {
    emoji: "🃏",
    label: "Poker"
  },
  rami: {
    emoji: "🂡",
    label: "Rami"
  }
};
const fmtAr = (n) => Math.round(n).toLocaleString("fr-FR") + " Ar";
function LobbyPage() {
  const {
    user,
    profile,
    loading
  } = useAuth();
  const navigate = useNavigate();
  const [games, setGames] = reactExports.useState([]);
  const [tournaments, setTournaments] = reactExports.useState([]);
  const [myTrn, setMyTrn] = reactExports.useState(/* @__PURE__ */ new Set());
  const [registeringTrn, setRegisteringTrn] = reactExports.useState(null);
  const [recentTx, setRecentTx] = reactExports.useState([]);
  const [minWithdrawal] = reactExports.useState(2e3);
  const settings = useAppSettings();
  const [showDeposit, setShowDeposit] = reactExports.useState(false);
  const [showRetrait, setShowRetrait] = reactExports.useState(false);
  const [showMesParties, setShowMesParties] = reactExports.useState(false);
  useMyOngoingCount();
  useLiveAvailable();
  const [refreshKey, setRefreshKey] = reactExports.useState(0);
  const reload = reactExports.useCallback(() => setRefreshKey((k) => k + 1), []);
  const loadGames = reactExports.useCallback(async () => {
    const [openRes, liveRes] = await Promise.all([supabase.rpc("list_public_open_games"), supabase.rpc("list_live_games")]);
    const openList = (openRes.data || []).map((g) => ({
      ...g,
      player_count: g.players_count,
      _state: "open"
    }));
    const liveList = (liveRes.data || []).filter((g) => g.game_type !== "rami" && g.game_type !== "fanorona").map((g) => ({
      id: g.id,
      game_slug: g.game_type,
      stake: g.stake,
      player_count: g.players_count ?? g.player_count ?? 0,
      is_private: false,
      _state: "live"
    }));
    const seen = /* @__PURE__ */ new Set();
    const merged = [...openList, ...liveList].filter((g) => {
      if (seen.has(g.id)) return false;
      seen.add(g.id);
      return true;
    });
    setGames(merged);
  }, []);
  const loadTournaments = reactExports.useCallback(async () => {
    const {
      data
    } = await supabase.from("tournaments").select("id, name, game_slug, format, max_players, players_per_match, entry_fee_ar, prize_pool_ar, admin_prize_pool_ar, platform_pct, winners_count, prize_1_pct, prize_2_pct, prize_3_pct, status, registration_closes_at, starts_at").eq("status", "open").order("created_at", {
      ascending: false
    }).limit(5);
    const list = (data || []).map((t) => ({
      ...t,
      stake: Number(t.entry_fee_ar ?? 0),
      is_free: Number(t.entry_fee_ar ?? 0) === 0,
      reward_distribution: [Number(t.prize_1_pct ?? 100), Number(t.prize_2_pct ?? 0), Number(t.prize_3_pct ?? 0)].slice(0, Number(t.winners_count ?? 1)),
      prize_pool: Math.round(Number(t.prize_pool_ar ?? 0) * (100 - Number(t.platform_pct ?? 0)) / 100 + Number(t.admin_prize_pool_ar ?? 0))
    }));
    if (list.length) {
      const ids = list.map((t) => t.id);
      const {
        data: regs
      } = await supabase.from("tournament_entrants").select("tournament_id, user_id").in("tournament_id", ids);
      const counts = {};
      (regs || []).forEach((r) => {
        counts[r.tournament_id] = (counts[r.tournament_id] || 0) + 1;
      });
      list.forEach((t) => {
        t.registered_count = counts[t.id] || 0;
      });
      if (user) {
        setMyTrn(new Set((regs || []).filter((r) => r.user_id === user.id).map((r) => r.tournament_id)));
      } else {
        setMyTrn(/* @__PURE__ */ new Set());
      }
    } else {
      setMyTrn(/* @__PURE__ */ new Set());
    }
    const now = serverNow();
    const visible = list.filter((t) => {
      const closeIso = t.registration_closes_at ?? t.starts_at;
      if (!closeIso) return true;
      return new Date(closeIso).getTime() > now;
    });
    setTournaments(visible);
  }, [user]);
  const [detailTrn, setDetailTrn] = reactExports.useState(null);
  const openTrnDetail = (trn) => setDetailTrn(trn);
  const confirmRegister = async () => {
    const trn = detailTrn;
    if (!trn) return;
    if (registeringTrn) return;
    setRegisteringTrn(trn.id);
    const toastId = toast.loading("Inscription en cours…");
    try {
      const {
        error
      } = await supabase.rpc("tournament_register", {
        _tid: trn.id
      });
      if (error) throw error;
      toast.success("Inscription confirmée ! 🎉", {
        id: toastId
      });
      setDetailTrn(null);
      loadTournaments();
    } catch (e) {
      toast.error(e.message || "Impossible de s'inscrire", {
        id: toastId
      });
    } finally {
      setRegisteringTrn(null);
    }
  };
  const loadTx = reactExports.useCallback(async () => {
    if (!user) return;
    const {
      data
    } = await supabase.from("transactions").select("id,amount,type,created_at,status").eq("user_id", user.id).order("created_at", {
      ascending: false
    }).limit(5);
    setRecentTx(data || []);
  }, [user]);
  reactExports.useEffect(() => {
    if (!loading && !user) navigate({
      to: "/login"
    });
  }, [user, loading, navigate]);
  reactExports.useEffect(() => {
    if (!user) return;
    loadGames();
    loadTx();
    loadTournaments();
    let gamesDebounce;
    const gamesTables = ["ludo_games", "domino_games", "fanorona_games", "chess_games", "poker_games", "rami_games"];
    const gamesChannel = supabase.channel("lobby-games");
    gamesTables.forEach((table) => {
      gamesChannel.on("postgres_changes", {
        event: "INSERT",
        schema: "public",
        table,
        filter: "status=eq.open"
      }, () => {
        clearTimeout(gamesDebounce);
        gamesDebounce = setTimeout(() => loadGames(), 600);
      });
      gamesChannel.on("postgres_changes", {
        event: "UPDATE",
        schema: "public",
        table,
        filter: "status=eq.open"
      }, () => {
        clearTimeout(gamesDebounce);
        gamesDebounce = setTimeout(() => loadGames(), 600);
      });
    });
    gamesChannel.subscribe();
    const trnChannel = supabase.channel("lobby-tournaments").on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournaments"
    }, () => loadTournaments()).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "tournament_entrants"
    }, () => loadTournaments()).subscribe();
    const txChannel = supabase.channel(`lobby-tx:${user.id}`).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "transactions",
      filter: `user_id=eq.${user.id}`
    }, () => {
      loadTx();
    }).subscribe();
    return () => {
      clearTimeout(gamesDebounce);
      supabase.removeChannel(gamesChannel);
      supabase.removeChannel(trnChannel);
      supabase.removeChannel(txChannel);
    };
  }, [user, loadGames, loadTx, loadTournaments, refreshKey]);
  if (loading) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "min-h-[50vh] grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-primary" }) });
  }
  if (!profile) return null;
  const balance = profile.balance_ar ?? 0;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-md mx-auto px-3 py-2 pb-24 space-y-2.5", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-zinc-900 text-white p-4 shadow-md shadow-zinc-900/30", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 mb-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] font-semibold uppercase tracking-wide opacity-80", children: "Solde disponible" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-3xl font-black tabular-nums leading-tight truncate", children: fmtAr(balance) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "shrink-0 w-11 h-11 rounded-xl bg-white/20 grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Wallet, { className: "w-5 h-5" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center gap-1.5 mt-2 mb-1", children: profile.phone_verified ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-emerald-500/20 text-emerald-300 text-[10px] font-bold", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-3 h-3" }),
        " Numéro vérifié"
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-amber-500/20 text-amber-300 text-[10px] font-bold", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldAlert, { className: "w-3 h-3" }),
        " Numéro non vérifié"
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setShowDeposit(true), className: "flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-white/20 font-bold text-sm active:bg-white/30 transition-colors", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowDownLeft, { className: "w-4 h-4 shrink-0" }),
          " Dépôt"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setShowRetrait(true), className: "flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-white/20 font-bold text-sm active:bg-white/30 transition-colors", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowUpRight, { className: "w-4 h-4 shrink-0" }),
          " Retrait"
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(OngoingGameBanner, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-4 gap-2", children: [{
      icon: Gamepad2,
      label: "Jeux",
      to: "/jeux",
      color: "text-primary"
    }, {
      icon: Trophy,
      label: "Tournois",
      to: "/tournaments",
      color: "text-amber-500"
    }, {
      icon: History,
      label: "Historique",
      to: "/history",
      color: "text-violet-500"
    }, {
      icon: Gift,
      label: "Parrainage",
      to: "/parrainage",
      color: "text-emerald-500"
    }].map(({
      icon: Icon,
      label,
      to,
      color
    }) => /* @__PURE__ */ jsxRuntimeExports.jsxs(Link, { to, className: "flex flex-col items-center gap-1 py-2 px-1 rounded-2xl bg-card border border-border active:bg-secondary transition-colors", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-8 h-8 rounded-xl bg-secondary grid place-items-center ${color}`, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-muted-foreground leading-tight text-center", children: label })
    ] }, to)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("h2", { className: "font-extrabold text-sm flex items-center gap-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-4 h-4 text-primary shrink-0" }),
      " Informations du jour"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BannerCarousel, {}),
    tournaments.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-[minmax(0,1fr)_auto] items-center gap-2 mb-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("h2", { className: "font-extrabold text-sm flex items-center gap-1.5 min-w-0 truncate", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4 text-amber-500 shrink-0" }),
          " Tournois ouverts"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/tournaments", className: "text-[11px] font-bold text-primary shrink-0", children: "Voir tout →" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("ul", { className: "space-y-2", children: tournaments.map((trn) => {
        const def = GAME_DEFS[trn.game_slug] ?? {
          emoji: "🏆",
          label: trn.game_slug || ""
        };
        const registered = myTrn.has(trn.id);
        const full = (trn.registered_count ?? 0) >= (trn.max_players ?? 0);
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("li", { className: "grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl bg-card border border-border p-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-11 h-11 rounded-xl bg-amber-500/10 grid place-items-center text-xl shrink-0", children: def.emoji }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-sm truncate", children: trn.name }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-0.5 flex-wrap", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-0.5 text-[10px] text-muted-foreground font-medium", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3 h-3" }),
                " ",
                trn.registered_count ?? 0,
                "/",
                trn.max_players ?? 0
              ] }),
              trn.is_free ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-emerald-600", children: "🎁 Gratuit" }) : trn.stake > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-0.5 text-[10px] font-bold text-amber-500", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-3 h-3" }),
                " ",
                fmtAr(trn.stake)
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-muted-foreground", children: def.label }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(RegistrationCountdown, { closesAt: trn.registration_closes_at ?? trn.starts_at })
            ] })
          ] }),
          registered ? /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/tournaments/$id", params: {
            id: trn.id
          }, className: "shrink-0 flex items-center gap-1 px-3 py-2 rounded-xl bg-emerald-500/10 text-emerald-600 font-bold text-xs", children: "✓ Inscrit" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => openTrnDetail(trn), disabled: full || !!registeringTrn, className: "shrink-0 flex items-center gap-1 px-3 py-2 rounded-xl bg-amber-500 text-white font-bold text-xs disabled:opacity-50 disabled:cursor-not-allowed", children: registeringTrn === trn.id ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-3 h-3 animate-spin" }) : full ? "Complet" : "S'inscrire" })
        ] }, trn.id);
      }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(MoneyOffersSection, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(DepotModal, { open: showDeposit, onClose: () => setShowDeposit(false), mvolaPhone: settings.mvolaPhone, mvolaName: settings.mvolaName, orangePhone: settings.orangePhone, orangeName: settings.orangeName, airtelPhone: settings.airtelPhone, airtelName: settings.airtelName, minDeposit: settings.minDeposit, onSuccess: reload }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(RetraitModal, { open: showRetrait, onClose: () => setShowRetrait(false), balance: profile.balance_ar ?? 0, minRetrait: minWithdrawal, onSuccess: reload }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(MesPartiesSheet, { open: showMesParties, onClose: () => setShowMesParties(false) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(TournamentDetailModal, { trn: detailTrn, onClose: () => setDetailTrn(null), onConfirm: confirmRegister, busy: !!registeringTrn, alreadyRegistered: detailTrn ? myTrn.has(detailTrn.id) : false })
  ] });
}
function TournamentDetailModal({
  trn,
  onClose,
  onConfirm,
  busy,
  alreadyRegistered
}) {
  if (!trn) return null;
  const def = GAME_DEFS[trn.game_slug] ?? {
    emoji: "🏆",
    label: trn.game_slug || ""
  };
  const full = (trn.registered_count ?? 0) >= (trn.max_players ?? 0);
  const winnersCount = trn.winners_count ?? 1;
  const prizePool = Number(trn.prize_pool || 0);
  const distRaw = trn.reward_distribution;
  let dist = [];
  try {
    if (Array.isArray(distRaw)) dist = distRaw.map((n) => Number(n));
    else if (typeof distRaw === "string") dist = JSON.parse(distRaw);
    else if (distRaw && typeof distRaw === "object") dist = Object.values(distRaw).map((n) => Number(n));
  } catch {
    dist = [];
  }
  const shares = Array.from({
    length: winnersCount
  }, () => 0);
  if (dist.length) {
    dist.forEach((pct, idx) => {
      const target = Math.min(idx, winnersCount - 1);
      shares[target] += pct;
    });
  } else {
    shares[0] = 100;
  }
  const playersPerMatch = trn.players_per_match ?? 2;
  const qualifiers = playersPerMatch === 4 ? 2 : 1;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-end justify-center bg-black/60", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative w-full max-w-md rounded-t-3xl bg-background shadow-2xl max-h-[92vh] overflow-y-auto", onClick: (e) => e.stopPropagation(), children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-1 rounded-full bg-border mx-auto mt-3" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3 min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-12 h-12 rounded-xl bg-amber-500/10 grid place-items-center text-2xl shrink-0", children: def.emoji }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-black leading-tight truncate", children: trn.name }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
              def.label,
              " · Format ",
              playersPerMatch === 4 ? "4 joueurs" : "1v1"
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "shrink-0 w-9 h-9 rounded-full bg-secondary grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap gap-1.5", children: [
        trn.is_free ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2.5 py-1 rounded-full bg-emerald-500/10 text-emerald-600 text-[11px] font-bold", children: "🎁 Inscription gratuite" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "px-2.5 py-1 rounded-full bg-amber-500/10 text-amber-600 text-[11px] font-bold", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-3 h-3 inline mr-0.5" }),
          " Mise ",
          fmtAr(Number(trn.stake || 0))
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "px-2.5 py-1 rounded-full bg-secondary text-[11px] font-bold", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3 h-3 inline mr-0.5" }),
          " ",
          trn.registered_count ?? 0,
          "/",
          trn.max_players ?? 0
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "px-2.5 py-1 rounded-full bg-secondary text-[11px] font-bold", children: [
          "🏅 ",
          winnersCount,
          " vainqueur",
          winnersCount > 1 ? "s" : ""
        ] })
      ] }),
      (trn.registration_closes_at || trn.starts_at) && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/60 border border-border p-3 flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] font-bold uppercase tracking-wide text-muted-foreground", children: "Clôture des inscriptions" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(RegistrationCountdown, { closesAt: trn.registration_closes_at ?? trn.starts_at })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-amber-500/10 border border-amber-500/20 p-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] font-bold uppercase text-amber-700 dark:text-amber-400 tracking-wide", children: "Cagnotte totale" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-2xl font-black text-amber-600", children: fmtAr(prizePool) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-3 space-y-1.5", children: shares.map((pct, i) => pct > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-xs", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold", children: i === 0 ? "🥇 1er" : i === 1 ? "🥈 2ᵉ" : "🥉 3ᵉ" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-black tabular-nums", children: [
            fmtAr(prizePool * pct / 100),
            " ",
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground font-medium", children: [
              "(",
              pct,
              "%)"
            ] })
          ] })
        ] }, i)) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border p-4 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] font-bold uppercase text-muted-foreground tracking-wide", children: "Règles" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("ul", { className: "text-xs space-y-1.5 leading-relaxed", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("li", { children: [
            "• Format à élimination directe ",
            playersPerMatch === 4 ? "(groupes de 4, 2 qualifiés)" : "(1v1, vainqueur qualifié)",
            "."
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("li", { children: [
            "• ",
            qualifiers === 2 ? "2 joueurs qualifiés" : "1 seul qualifié",
            " par match vers l'étape suivante."
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("li", { children: "• 10 min de préparation puis 5 min en salle d'entente à chaque étape." }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("li", { children: "• Un joueur absent après le délai est déclaré forfait automatiquement." }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("li", { children: "• Petite finale : match pour la 3ᵉ place avant la finale." }),
          !trn.is_free && /* @__PURE__ */ jsxRuntimeExports.jsx("li", { children: "• La mise est débitée dès la validation de l'inscription." })
        ] })
      ] }),
      alreadyRegistered ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-xl bg-emerald-500/10 text-emerald-600 text-center py-3 text-sm font-bold", children: "✓ Vous êtes déjà inscrit" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "flex-1 py-3.5 rounded-xl bg-secondary font-bold text-sm", children: "Annuler" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onConfirm, disabled: busy || full, className: "flex-[2] py-3.5 rounded-xl bg-amber-500 text-white font-bold disabled:opacity-50 flex items-center justify-center gap-2", children: busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-5 h-5 animate-spin" }) : full ? "Complet" : trn.is_free ? "Confirmer l'inscription" : `S'inscrire (${fmtAr(Number(trn.stake || 0))})` })
      ] })
    ] })
  ] }) });
}
function RegistrationCountdown({
  closesAt
}) {
  const [, tick] = reactExports.useState(0);
  reactExports.useEffect(() => {
    if (!closesAt) return;
    const id = setInterval(() => tick((n) => n + 1), 1e3);
    return () => clearInterval(id);
  }, [closesAt]);
  if (!closesAt) return null;
  const remaining = new Date(closesAt).getTime() - serverNow();
  if (remaining <= 0) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex items-center gap-0.5 text-[10px] font-bold text-rose-500", children: "⏱ Clôturé" });
  }
  const s = Math.floor(remaining / 1e3);
  const d = Math.floor(s / 86400);
  const h = Math.floor(s % 86400 / 3600);
  const m = Math.floor(s % 3600 / 60);
  const sec = s % 60;
  let label = "";
  if (d > 0) label = `${d}j ${h}h`;
  else if (h > 0) label = `${h}h ${String(m).padStart(2, "0")}m`;
  else if (m > 0) label = `${m}m ${String(sec).padStart(2, "0")}s`;
  else label = `${sec}s`;
  const urgent = remaining < 60 * 60 * 1e3;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `flex items-center gap-0.5 text-[10px] font-bold ${urgent ? "text-rose-500 animate-pulse" : "text-amber-600"}`, title: "Clôture des inscriptions", children: [
    "⏱ ",
    label
  ] });
}
export {
  LobbyPage as component
};
