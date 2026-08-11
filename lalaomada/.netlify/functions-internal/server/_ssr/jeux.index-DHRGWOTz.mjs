import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { G as GAME_TABLE } from "./game-constants-DbAkVx_H.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { u as useAuth, p as pokerImg, j as ramiImg, k as chessImg, m as fanoronaImg, n as dominoImg, q as ludoImg } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { P as PhoneVerifyPopup } from "./PhoneVerifyPopup-CibtDuiJ.mjs";
import { u as useAppSettings, D as DepotModal } from "./WalletButton-BwZT8Njg.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { a8 as KeyRound, ab as RefreshCw, U as Users, a2 as Plus } from "../_libs/lucide-react.mjs";
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
const COVER_IMAGES = {
  ludo: ludoImg,
  domino: dominoImg,
  fanorona: fanoronaImg,
  chess: chessImg,
  rami: ramiImg,
  poker: pokerImg
};
function GameCover({
  slug,
  label
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: COVER_IMAGES[slug], alt: label, loading: "eager", decoding: "async", fetchPriority: "high", width: 512, height: 512, className: "w-full h-full object-cover", draggable: false });
}
const COVER_COMPONENTS = {
  ludo: () => /* @__PURE__ */ jsxRuntimeExports.jsx(GameCover, { slug: "ludo", label: "Ludo" }),
  domino: () => /* @__PURE__ */ jsxRuntimeExports.jsx(GameCover, { slug: "domino", label: "Domino" }),
  fanorona: () => /* @__PURE__ */ jsxRuntimeExports.jsx(GameCover, { slug: "fanorona", label: "Fanorona" }),
  chess: () => /* @__PURE__ */ jsxRuntimeExports.jsx(GameCover, { slug: "chess", label: "Échecs" }),
  rami: () => /* @__PURE__ */ jsxRuntimeExports.jsx(GameCover, { slug: "rami", label: "Rami" }),
  poker: () => /* @__PURE__ */ jsxRuntimeExports.jsx(GameCover, { slug: "poker", label: "Poker" })
};
const GAMES = [{
  slug: "ludo",
  label: "Ludo",
  desc: "2-4 joueurs",
  emoji: "🎲"
}, {
  slug: "domino",
  label: "Domino",
  desc: "2-4 joueurs",
  emoji: "🁣"
}, {
  slug: "fanorona",
  label: "Fanorona",
  desc: "2 joueurs",
  emoji: "⚫"
}, {
  slug: "chess",
  label: "Échecs",
  desc: "2 joueurs",
  emoji: "♟️"
}, {
  slug: "rami",
  label: "Rami",
  desc: "2-4 joueurs",
  emoji: "🃏"
}, {
  slug: "poker",
  label: "Poker",
  desc: "2-9 joueurs",
  emoji: "🂡"
}];
const ALL_DISPLAYED_SLUGS = ["ludo", "domino", "fanorona", "chess", "rami", "poker"];
const DIRECT_JOIN_SLUGS = ["ludo", "domino", "fanorona", "chess", "rami", "poker"];
const ROUTE = {
  ludo: "/jeux/ludo/$id",
  domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  chess: "/jeux/chess/$id",
  rami: "/jeux/rami/$id",
  poker: "/jeux/poker/$id"
};
const JOIN_CODE_RPC = {
  ludo: "join_game_by_code",
  domino: "domino_join_code",
  fanorona: "fanorona_join_code",
  chess: "chess_join_code",
  rami: "rami_join_code",
  poker: "poker_join_code"
};
const JOIN_RPC = {
  ludo: "join_game",
  domino: "domino_join",
  fanorona: "fanorona_join",
  chess: "chess_join",
  rami: "rami_join",
  poker: "poker_join"
};
function JeuxPage() {
  const navigate = useNavigate();
  const {
    profile,
    refreshProfile,
    isAdmin
  } = useAuth();
  const [showPhoneVerify, setShowPhoneVerify] = reactExports.useState(false);
  const [showDepositPopup, setShowDepositPopup] = reactExports.useState(false);
  const walletSettings = useAppSettings();
  const [onlineCounts, setOnlineCounts] = reactExports.useState({});
  const [disabled, setDisabled] = reactExports.useState([]);
  const getGameStatus = (slug) => {
    if (isAdmin) return "active";
    if (disabled.includes(slug)) return "hidden";
    if (disabled.includes(slug + ":dev")) return "dev";
    if (disabled.includes(slug + ":paused")) return "paused";
    return "active";
  };
  const [openGames, setOpenGames] = reactExports.useState([]);
  const [loadingGames, setLoadingGames] = reactExports.useState(false);
  const [filterSlug, setFilterSlug] = reactExports.useState("all");
  const [filterStake, setFilterStake] = reactExports.useState("all");
  const [code, setCode] = reactExports.useState("");
  const [codeSlug, setCodeSlug] = reactExports.useState("ludo");
  const [busyCode, setBusyCode] = reactExports.useState(false);
  const [joiningId, setJoiningId] = reactExports.useState(null);
  reactExports.useEffect(() => {
    const load = async () => {
      const {
        data
      } = await supabase.from("app_settings").select("games_disabled").eq("id", 1).maybeSingle();
      setDisabled(data?.games_disabled || []);
    };
    load();
    const ch = supabase.channel("jeux-settings-v2").on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "app_settings"
    }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, []);
  reactExports.useEffect(() => {
    const active = GAMES.filter((g) => getGameStatus(g.slug) === "active");
    if (!active.length) return;
    const load = async () => {
      const {
        data
      } = await supabase.rpc("game_online_counts_all");
      if (data) setOnlineCounts(Object.fromEntries(data.map((r) => [r.slug, r.online_count])));
    };
    load();
    const t = setInterval(load, 3e4);
    return () => clearInterval(t);
  }, [disabled.join(",")]);
  const loadOpenGames = reactExports.useCallback(async (opts = {}) => {
    if (!opts.silent) setLoadingGames(true);
    const {
      data,
      error
    } = await supabase.rpc("list_all_open_games");
    if (error) {
      setLoadingGames(false);
      return;
    }
    const rows = data || [];
    const flat = rows.filter((r) => getGameStatus(r.slug) === "active").map((r) => ({
      id: r.game_id,
      slug: r.slug,
      stake: r.stake,
      pot: r.pot,
      created_at: r.created_at,
      is_private: false,
      max_players: r.max_players ?? 2,
      players_count: r.players_count ?? 0,
      host_id: r.host_id || null,
      host_name: r.host_name || "Joueur",
      target_score: r.target_score ?? null
    }));
    setOpenGames(flat);
    setLoadingGames(false);
  }, [disabled.join(",")]);
  reactExports.useEffect(() => {
    loadOpenGames();
  }, [loadOpenGames]);
  reactExports.useEffect(() => {
    let debounceTimer;
    const refresh = () => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => loadOpenGames({
        silent: true
      }), 800);
    };
    const ch = supabase.channel("open-games-all");
    ALL_DISPLAYED_SLUGS.forEach((slug) => ch.on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: GAME_TABLE[slug],
      filter: "status=eq.open"
    }, refresh));
    ch.subscribe();
    return () => {
      clearTimeout(debounceTimer);
      supabase.removeChannel(ch);
    };
  }, [loadOpenGames]);
  const joinByCode = async () => {
    const trimmed = code.trim().toUpperCase();
    if (!trimmed) return;
    setBusyCode(true);
    try {
      const {
        data: resolved,
        error: resolveErr
      } = await supabase.rpc("resolve_room_code", {
        _code: trimmed
      });
      if (resolveErr) throw resolveErr;
      const row = resolved?.[0];
      if (!row) throw new Error("Code introuvable ou partie déjà commencée.");
      const detectedSlug = row.slug;
      const gameId = row.game_id;
      const fn = JOIN_CODE_RPC[detectedSlug];
      const {
        error: joinErr
      } = await supabase.rpc(fn, {
        _code: trimmed
      });
      if (joinErr) throw joinErr;
      refreshProfile();
      navigate({
        to: ROUTE[detectedSlug],
        params: {
          id: gameId
        }
      });
    } catch (e) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient") || msg.includes("solde")) {
        toast.error("Solde insuffisant", {
          action: {
            label: "Déposer",
            onClick: () => setShowDepositPopup(true)
          }
        });
      } else {
        toast.error(e.message || "Code invalide");
      }
    } finally {
      setBusyCode(false);
    }
  };
  const joinGame = async (game) => {
    if (game.is_private) {
      toast.error("Cette partie est privée — rejoins par code.");
      return;
    }
    const fn = JOIN_RPC[game.slug];
    if (!fn) {
      toast.error("Rejoins par code pour ce jeu.");
      return;
    }
    const bal = Number(profile?.balance_ar || 0);
    if (game.stake > 0 && bal < game.stake) {
      toast.error("Solde insuffisant", {
        action: {
          label: "Déposer",
          onClick: () => setShowDepositPopup(true)
        }
      });
      return;
    }
    setJoiningId(game.id);
    try {
      const {
        error
      } = await supabase.rpc(fn, {
        _game_id: game.id
      });
      if (error) throw error;
      refreshProfile();
      navigate({
        to: ROUTE[game.slug],
        params: {
          id: game.id
        }
      });
    } catch (e) {
      toast.error(e.message || "Erreur lors de la connexion");
    } finally {
      setJoiningId(null);
    }
  };
  const visibleGames = GAMES.filter((g) => getGameStatus(g.slug) !== "hidden");
  const filteredGames = openGames.filter((g) => filterSlug === "all" || g.slug === filterSlug).filter((g) => filterStake === "all" || (filterStake === "free" ? g.stake === 0 : g.stake > 0));
  const filterOptions = [{
    slug: "all",
    label: "Tous",
    count: openGames.length
  }, ...ALL_DISPLAYED_SLUGS.filter((s) => getGameStatus(s) === "active").map((s) => ({
    slug: s,
    label: GAMES.find((g) => g.slug === s)?.label ?? s,
    count: openGames.filter((g) => g.slug === s).length
  }))];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-3 pt-2 pb-20 md:pb-4 flex flex-col gap-3 md:h-[calc(100vh-3.5rem)] md:overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-2 flex-shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-base font-extrabold leading-tight bg-gradient-to-r from-primary via-orange-500 to-primary bg-[length:200%_100%] bg-clip-text text-transparent animate-[shimmer_3s_linear_infinite]", children: "Créer une partie" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-6 gap-1.5", children: visibleGames.map((g) => {
        const CoverArt = COVER_COMPONENTS[g.slug];
        const status = getGameStatus(g.slug);
        const badge = status === "dev" ? {
          text: "En dev",
          cls: "bg-amber-500/90 text-white"
        } : status === "paused" ? {
          text: "En pause",
          cls: "bg-sky-500/90 text-white"
        } : null;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-0.5 min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-3 flex items-center justify-center w-full", children: badge && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[8px] font-bold leading-none px-1.5 py-0.5 rounded-full whitespace-nowrap ${badge.cls}`, children: badge.text }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => status === "active" && navigate({
            to: "/jeux/$slug",
            params: {
              slug: g.slug
            }
          }), className: `relative w-full aspect-square rounded-[22%] overflow-hidden group transition-all shadow border border-white/8 ${status === "active" ? "active:scale-[0.93] cursor-pointer" : "cursor-not-allowed opacity-70"}`, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(CoverArt, {}) }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent" }),
            status === "active" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute top-[6%] right-[6%] flex items-center gap-0.5 bg-black/60 backdrop-blur-sm rounded-full px-1.5 py-0.5 border border-white/10", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1 h-1 rounded-full bg-emerald-400 animate-pulse" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-white text-[8px] font-bold tabular-nums leading-none", children: onlineCounts[g.slug] ?? 0 })
            ] })
          ] })
        ] }, g.slug);
      }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "flex flex-col gap-2 flex-1 min-h-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-2xl px-3 py-2 shadow-sm border border-white/8 flex items-center gap-2 flex-shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-lg bg-primary/15 flex items-center justify-center flex-shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-3.5 h-3.5 text-primary" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: code, onChange: (e) => setCode(e.target.value.toUpperCase()), onKeyDown: (e) => e.key === "Enter" && joinByCode(), placeholder: "Code ABC123", maxLength: 6, autoCapitalize: "characters", className: "flex-1 min-w-0 px-2 py-1.5 rounded-lg bg-secondary border border-border outline-none uppercase tracking-[0.25em] font-mono text-center text-sm focus:ring-2 focus:ring-primary/40 transition" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: joinByCode, disabled: busyCode || code.trim().length < 4, className: "flex-shrink-0 px-3 py-1.5 rounded-lg bg-primary text-primary-foreground font-bold text-xs disabled:opacity-50 active:scale-95 transition-transform", children: busyCode ? "…" : "OK" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2 flex-shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-primary animate-pulse" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-extrabold text-[15px] tracking-tight bg-gradient-to-r from-primary to-orange-500 bg-clip-text text-transparent", children: "Parties ouvertes" }),
          openGames.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "bg-primary text-primary-foreground text-[10px] font-bold px-2 py-0.5 rounded-full shadow-sm", children: openGames.length })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => loadOpenGames(), disabled: loadingGames, title: "Rafraîchir", className: "p-1.5 rounded-full hover:bg-accent transition-colors disabled:opacity-50", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: `w-3.5 h-3.5 ${loadingGames ? "animate-spin" : ""}` }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1 overflow-x-auto -mx-1 px-1 no-scrollbar flex-shrink-0", children: [
        filterOptions.map((f) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setFilterSlug(f.slug), className: `flex-shrink-0 px-2.5 py-1 rounded-full text-[11px] font-bold transition-colors ${filterSlug === f.slug ? "bg-primary text-primary-foreground shadow-sm" : "bg-secondary hover:bg-accent"}`, children: [
          f.label,
          f.count > 0 ? ` ${f.count}` : ""
        ] }, f.slug)),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-px bg-border mx-1 flex-shrink-0" }),
        ["all", "free", "paid"].map((v) => {
          const labels = {
            all: "💰",
            free: "🎉",
            paid: "💵"
          };
          return /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setFilterStake(v), className: `flex-shrink-0 px-2.5 py-1 rounded-full text-[11px] font-bold transition-colors ${filterStake === v ? "bg-amber-500 text-white shadow-sm" : "bg-secondary hover:bg-accent text-muted-foreground"}`, children: labels[v] }, v);
        })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-h-0 overflow-y-auto space-y-2 pr-0.5", children: [
        loadingGames && filteredGames.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center py-6 text-muted-foreground text-xs", children: "Chargement…" }),
        !loadingGames && filteredGames.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/8 p-4 text-center space-y-1 shadow-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-2xl", children: "🎲" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Aucune partie ouverte" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground", children: "Crée une partie ci-dessus." })
        ] }),
        filteredGames.map((game) => {
          const def = GAMES.find((g) => g.slug === game.slug);
          const CoverMini = COVER_COMPONENTS[game.slug];
          game.stake > 0 ? `${Number(game.stake).toLocaleString("fr-FR")} Ar` : "Gratuit";
          const isFull = game.players_count >= game.max_players;
          const isBusy = joiningId === game.id;
          const dominoChips = [];
          if (game.slug === "domino") {
            dominoChips.push(game.draw_mode === "without" ? "sans pioche" : "avec pioche");
            if (game.target_score && game.target_score > 0) dominoChips.push(`${game.target_score} pts`);
            else dominoChips.push("1 manche");
          }
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative bg-gradient-to-br from-card to-card/60 rounded-2xl border border-white/10 p-2.5 flex items-center gap-2.5 hover:border-primary/40 hover:shadow-lg hover:shadow-primary/10 transition-all shadow-sm overflow-hidden", children: [
            game.stake > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute top-0 right-0 bg-amber-500/95 text-white text-[9px] font-black px-1.5 py-0.5 rounded-bl-lg shadow", children: [
              Number(game.stake).toLocaleString("fr-FR"),
              " Ar"
            ] }),
            game.stake === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute top-0 right-0 bg-emerald-500/95 text-white text-[9px] font-black px-1.5 py-0.5 rounded-bl-lg shadow", children: "GRATUIT" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-14 h-14 rounded-xl overflow-hidden flex-shrink-0 shadow-md ring-1 ring-white/15 relative", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(CoverMini, {}),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-0.5 left-0.5 text-[11px] leading-none", children: def.emoji })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-black text-sm truncate", children: def.label }),
                game.is_private && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px]", children: "🔒" }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `ml-auto mr-14 text-[10px] font-bold px-1.5 py-0.5 rounded-md ${isFull ? "bg-red-500/20 text-red-400" : game.max_players - game.players_count === 1 ? "bg-amber-500/20 text-amber-400" : "bg-primary/15 text-primary"}`, children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "inline w-2.5 h-2.5 -mt-0.5 mr-0.5" }),
                  game.players_count,
                  "/",
                  game.max_players
                ] })
              ] }),
              game.host_name && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground truncate mt-0.5", children: [
                "par ",
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground/80", children: game.host_name })
              ] }),
              dominoChips.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-1 mt-1", children: dominoChips.map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold px-1.5 py-0.5 rounded bg-white/5 border border-white/10 text-muted-foreground", children: c }, i)) })
            ] }),
            game.is_private || !DIRECT_JOIN_SLUGS.includes(game.slug) ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-shrink-0 self-end px-2 py-1.5 rounded-lg bg-secondary border border-white/10 text-muted-foreground font-semibold text-[10px]", children: "🔒 Code" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => joinGame(game), disabled: isBusy || isFull, className: "flex-shrink-0 self-end flex items-center gap-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground font-black text-xs disabled:opacity-60 active:scale-95 transition-all shadow-md shadow-primary/30", children: [
              isBusy ? /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: "w-3 h-3 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-3 h-3" }),
              isBusy ? "Connexion…" : isFull ? "Complet" : "Rejoindre"
            ] })
          ] }, game.id);
        })
      ] })
    ] }),
    showPhoneVerify && /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyPopup, { onClose: () => setShowPhoneVerify(false) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(DepotModal, { open: showDepositPopup, onClose: () => setShowDepositPopup(false), mvolaPhone: walletSettings.mvolaPhone, mvolaName: walletSettings.mvolaName, orangePhone: walletSettings.orangePhone, orangeName: walletSettings.orangeName, airtelPhone: walletSettings.airtelPhone, airtelName: walletSettings.airtelName, minDeposit: walletSettings.minDeposit, onSuccess: () => {
      refreshProfile();
    } })
  ] });
}
export {
  JeuxPage as component
};
