import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { R as RANKS, S as SUIT_COLORS, a as SUITS } from "./game-constants-DbAkVx_H.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { H as Route$1, u as useAuth, b as useConfirm, c as copyText } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { u as useGameConnection, G as GameStateMessage, a as GameWaitingRoom, c as GameEndScreen, d as GameReconnectOverlay, b as GamePauseControl } from "./GameReconnectOverlay-DB4s6cH2.mjs";
import { G as GameSocialFab } from "./GameSocialFab-DlZx4gfi.mjs";
import { G as GameLoader } from "./GameLoader-DEMrZT6Q.mjs";
import { P as PhoneVerifyBanner } from "./PhoneVerifyBanner-Dqrff6fy.mjs";
import { i as isMuted, s as setMuted } from "./game-sounds-246YZn8C.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/canvas-confetti.mjs";
import { a2 as Plus, A as ArrowLeft, a1 as Check, d as Copy, aU as Volume2, aV as VolumeX, aw as Timer } from "../_libs/lucide-react.mjs";
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
import "./game-ui-state-y34n01Z_.mjs";
import "./ChatRoom-DC72H67I.mjs";
import "./LinkPreview-BF8xLSR1.mjs";
import "./share-game-wrpRJpl9.mjs";
import "./image-compress-U7tauI3l.mjs";
import "./PhoneVerifyPopup-CibtDuiJ.mjs";
const HAND_LABELS = {
  "Quinte Royale": "Quinte Royale 👑",
  "Quinte Flush": "Quinte Flush",
  "Carré": "Carré",
  "Full House": "Full House",
  "Couleur": "Couleur (Flush)",
  "Suite": "Suite",
  "Brelan": "Brelan",
  "Double Paire": "Double Paire",
  "Paire": "Paire",
  "Hauteur": "Hauteur"
};
function CardBack({
  w = 56,
  h = 84
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("svg", { width: w, height: h, viewBox: "0 0 56 84", style: {
    borderRadius: 6
  }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("rect", { x: "0", y: "0", width: "56", height: "84", rx: "6", fill: "#1e40af" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("rect", { x: "3", y: "3", width: "50", height: "78", rx: "5", fill: "none", stroke: "#3b82f6", strokeWidth: "1.5" }),
    Array.from({
      length: 8
    }, (_, r) => Array.from({
      length: 6
    }, (_2, c) => /* @__PURE__ */ jsxRuntimeExports.jsx("text", { x: 4 + c * 8, y: 10 + r * 10, fontSize: "8", fill: "#3b82f680", fontFamily: "serif", children: "♦" }, `${r}-${c}`)))
  ] });
}
function PlayingCard({
  c,
  w = 56,
  h = 84,
  faceDown
}) {
  if (faceDown) return /* @__PURE__ */ jsxRuntimeExports.jsx(CardBack, { w, h });
  const s = Math.floor(c / 13);
  const r = c % 13;
  const rank = RANKS[r];
  const suit = SUITS[s];
  const color = SUIT_COLORS[s];
  const fs = Math.round(w * 0.22);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("svg", { width: w, height: h, viewBox: "0 0 56 84", style: {
    borderRadius: 6,
    filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.3))"
  }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("rect", { x: "0", y: "0", width: "56", height: "84", rx: "6", fill: "white", stroke: "#e2e8f0", strokeWidth: "1" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("text", { x: "4", y: fs + 3, fontSize: fs, fontWeight: "bold", fontFamily: "Arial,sans-serif", fill: color, children: rank }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("text", { x: "4", y: fs * 2 + 4, fontSize: fs * 0.85, fontFamily: "Arial,sans-serif", fill: color, children: suit }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("text", { x: "28", y: "48", fontSize: Math.round(w * 0.52), fontFamily: "Arial,sans-serif", fill: color, textAnchor: "middle", dominantBaseline: "middle", children: suit }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("text", { x: "52", y: h - 3, fontSize: fs, fontWeight: "bold", fontFamily: "Arial,sans-serif", fill: color, textAnchor: "end", transform: "rotate(180,52,75)", children: rank })
  ] });
}
function Chips({
  amount,
  size = "sm"
}) {
  const fmt = (n) => n >= 1e3 ? `${(n / 1e3).toFixed(n % 1e3 === 0 ? 0 : 1)}k` : String(n);
  const cls = size === "xs" ? "text-[9px] px-1.5 py-0.5" : "text-xs px-2 py-1";
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `font-mono font-extrabold rounded-full bg-black/60 text-amber-400 ${cls}`, children: fmt(amount) });
}
function seatPos(idx, myIdx, total, rx, ry, cx, cy) {
  const angleDeg = 90 + 360 * ((idx - myIdx + total) % total) / total;
  const a = angleDeg * Math.PI / 180;
  return {
    x: cx + rx * Math.cos(a),
    y: cy + ry * Math.sin(a)
  };
}
function PlayerSeat({
  player,
  idx,
  myIdx,
  total,
  cx,
  cy,
  rx,
  ry,
  isActive,
  dealerSeat,
  sbSeat,
  bbSeat,
  commCards
}) {
  const {
    x,
    y
  } = seatPos(idx, myIdx, total, rx, ry, cx, cy);
  const seat = player.seat;
  const isMe = idx === 0;
  const folded = player.status === "folded";
  const allIn = player.status === "all_in";
  const finished = player.result;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute", style: {
    left: x - 50,
    top: y - 52,
    width: 100,
    zIndex: isMe ? 10 : 5
  }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex flex-col items-center gap-0.5 transition-all duration-300 ${folded ? "opacity-40 grayscale" : ""}`, children: [
    player.hole_cards?.length > 0 && !isMe && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-0.5 mb-1", children: player.hole_cards.map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(PlayingCard, { c, w: 24, h: 36, faceDown: !finished }, i)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `relative w-14 h-14 rounded-full border-2 flex items-center justify-center font-bold text-sm shadow-xl
          ${isActive ? "border-amber-400 shadow-amber-500/60" : isMe ? "border-emerald-400" : "border-white/30"}
          bg-gradient-to-br from-slate-600 to-slate-900 text-white`, style: isActive ? {
      animation: "pulse 1.5s ease-in-out infinite",
      boxShadow: "0 0 20px rgba(251,191,36,0.5)"
    } : {}, children: [
      player.pseudo?.slice(0, 2)?.toUpperCase() || "??",
      seat === dealerSeat && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1 -right-1 w-5 h-5 bg-white text-black text-[9px] font-extrabold rounded-full flex items-center justify-center shadow border border-gray-300", children: "D" }),
      seat === sbSeat && seat !== dealerSeat && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1 -left-1 bg-blue-500 text-white text-[8px] font-bold rounded-full px-1 leading-5", children: "SB" }),
      seat === bbSeat && seat !== dealerSeat && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1 -left-1 bg-red-500 text-white text-[8px] font-bold rounded-full px-1 leading-5", children: "BB" }),
      allIn && !finished && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -bottom-1 left-1/2 -translate-x-1/2 bg-amber-500 text-black text-[8px] font-extrabold rounded px-1 whitespace-nowrap", children: "ALL IN" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-center rounded-xl px-2 py-0.5 max-w-full ${isMe ? "bg-emerald-900/80" : "bg-black/70"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold text-white truncate max-w-[80px]", children: player.pseudo || "Joueur" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Chips, { amount: player.chips, size: "xs" })
    ] }),
    player.bet_round > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-0.5 bg-amber-500 text-black text-[8px] font-extrabold rounded-full px-2 py-0.5 shadow-md", children: player.bet_round.toLocaleString("fr-FR") }),
    finished && player.hole_cards?.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] bg-emerald-600 text-white px-1 rounded font-bold mt-0.5", children: HAND_LABELS[finished.label] || finished.label })
  ] }) });
}
function PokerPage() {
  const {
    id
  } = Route$1.useParams();
  const {
    user,
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();
  const [soundOn, setSoundOn] = reactExports.useState(!isMuted());
  const [game, setGame] = reactExports.useState(null);
  const [players, setPlayers] = reactExports.useState([]);
  const [profilesMap, setProfilesMap] = reactExports.useState({});
  const [copied, setCopied] = reactExports.useState(false);
  const [raiseAmt, setRaiseAmt] = reactExports.useState(0);
  const [busy, setBusy] = reactExports.useState(false);
  const [timeLeft, setTimeLeft] = reactExports.useState(30);
  const [betweenHands, setBetweenHands] = reactExports.useState(false);
  const [countdown, setCountdown] = reactExports.useState(5);
  const load = reactExports.useCallback(async () => {
    const {
      data: g
    } = await supabase.from("poker_games").select("*").eq("id", id).maybeSingle();
    setGame(g);
    const {
      data: ps
    } = await supabase.from("poker_players").select("id,game_id,user_id,seat,chips,bet_round,total_bet,status,is_ready,last_action,hand_result,joined_at").eq("game_id", id).order("seat");
    let playersArr = (ps || []).map((p) => ({
      ...p,
      hole_cards: []
    }));
    const {
      data: hc
    } = await supabase.rpc("poker_my_hole_cards", {
      _game_id: id
    });
    if (Array.isArray(hc)) {
      const byUser = {};
      hc.forEach((r) => {
        byUser[r.user_id] = r.hole_cards || [];
      });
      playersArr = playersArr.map((p) => byUser[p.user_id] ? {
        ...p,
        hole_cards: byUser[p.user_id]
      } : p);
    }
    setPlayers(playersArr);
    const ids = playersArr.map((p) => p.user_id).filter(Boolean);
    if (ids.length) {
      const {
        data: profs
      } = await supabase.from("profiles").select("id,pseudo,avatar_url").in("id", ids);
      const m = {};
      (profs || []).forEach((p) => {
        m[p.id] = p;
      });
      setProfilesMap((prev) => ({
        ...prev,
        ...m
      }));
    }
  }, [id, profile?.id]);
  reactExports.useEffect(() => {
    load();
  }, [load]);
  reactExports.useEffect(() => {
    let heartbeat = null;
    const ch = supabase.channel(`poker-${id}`).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "poker_games",
      filter: `id=eq.${id}`
    }, load).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "poker_players",
      filter: `game_id=eq.${id}`
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
  }, [id, load]);
  const {
    isConnected,
    isReconnecting,
    retry
  } = useGameConnection({
    onReconnect: load
  });
  reactExports.useEffect(() => {
    if (!game?.turn_deadline || game.status !== "playing") {
      setTimeLeft(30);
      return;
    }
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      setTimeLeft(Math.max(0, Math.ceil(ms / 1e3)));
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status]);
  reactExports.useEffect(() => {
    if (game?.phase !== "between_hands") {
      setBetweenHands(false);
      return;
    }
    setBetweenHands(true);
    setCountdown(5);
    const t = setInterval(() => {
      setCountdown((c) => {
        if (c <= 1) {
          clearInterval(t);
          supabase.rpc("poker_start_next_hand", {
            _game_id: id
          }).then(load);
          return 0;
        }
        return c - 1;
      });
    }, 1e3);
    return () => clearInterval(t);
  }, [game?.phase, id, load]);
  if (!game) return /* @__PURE__ */ jsxRuntimeExports.jsx(GameLoader, {});
  const me = players.find((p) => p.user_id === user?.id);
  const isPlayer = !!me;
  const myIdx = me ? players.findIndex((p) => p.user_id === user?.id) : 0;
  const isMyTurn = game.current_player === user?.id;
  const state = game.state || {};
  const curBet = Number(state.current_bet || 0);
  const callAmt = Math.max(0, curBet - Number(me?.bet_round || 0));
  const canCheck = callAmt === 0;
  const community = game.community_cards || [];
  const dealerSeat = state.dealer_seat ?? -1;
  const sbSeat = state.sb_seat ?? -1;
  const bbSeat = state.bb_seat ?? -1;
  const myChips = Number(me?.chips || 0);
  const bigBlind = Number(state.big_blind || game.big_blind || 20);
  const lastRaise = Math.max(Number(state.last_raise || 0), bigBlind);
  const maxTotal = myChips + Number(me?.bet_round || 0);
  const minRaise = Math.min(curBet + lastRaise, maxTotal);
  const canRaise = maxTotal > curBet;
  const W = 680;
  const H = 620;
  const cx = W / 2;
  const cy = H / 2 - 20;
  const rx = Math.min(W * 0.38, 240);
  const ry = Math.min(H * 0.33, 190);
  const enriched = players.map((p) => ({
    ...p,
    pseudo: profilesMap[p.user_id]?.pseudo || "?",
    result: p.hand_result
  }));
  const phaseLabelMap = {
    waiting: "En attente",
    preflop: "Pré-Flop",
    flop: "Flop",
    turn: "Turn",
    river: "River",
    showdown: "Abattage",
    between_hands: "Prochaine main…",
    finished: "Terminé"
  };
  const doAction = async (action, amount) => {
    if (busy) return;
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("poker_action", {
        _game_id: id,
        _action: action,
        _amount: amount ?? 0
      });
      if (error) toast.error(error.message);
      else await load();
    } finally {
      setBusy(false);
    }
  };
  const setReady = async (ready) => {
    const {
      error
    } = await supabase.rpc("poker_set_ready", {
      _game_id: id,
      _ready: ready
    });
    if (error) toast.error(error.message);
  };
  const copyCode = () => {
    if (game.room_code) {
      copyText(game.room_code).then((ok) => {
        if (ok) {
          setCopied(true);
          setTimeout(() => setCopied(false), 2e3);
        } else toast.error("Impossible de copier");
      });
    }
  };
  const refund = async () => {
    const ok = await confirm({
      title: "Annuler la partie ?",
      description: "Votre mise sera remboursée.",
      confirmLabel: "Annuler",
      destructive: true
    });
    if (!ok) return;
    const {
      error
    } = await supabase.rpc("poker_request_refund", {
      _game_id: id
    });
    if (error) toast.error(error.message);
    else {
      toast.success("Mise remboursée");
      refreshProfile();
      navigate({
        to: "/jeux/$slug",
        params: {
          slug: "poker"
        },
        search: {}
      });
    }
  };
  if (game.status === "cancelled") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(GameStateMessage, { state: "cancelled", gameLabel: "Poker", slug: "poker" });
  }
  if (game.status === "waiting") {
    const seatParts = enriched.map((p) => ({
      id: p.id,
      user_id: p.user_id,
      display_name: p.pseudo || "Joueur",
      avatar_url: profilesMap[p.user_id]?.avatar_url,
      slot: p.seat,
      ready: !!p.is_ready
    }));
    const canAddBot = (isAdmin || Number(game.stake) === 0 && isPlayer) && players.length < game.max_players;
    const quitPoker = async () => {
      if (game.created_by === user?.id && players.length === 1) {
        await refund();
        return;
      }
      navigate({
        to: "/jeux/$slug",
        params: {
          slug: "poker"
        },
        search: {}
      });
    };
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameWaitingRoom, { isTournament: !!game.tournament_match_id, slug: "poker", gameLabel: `Poker · ${game.max_players} joueurs`, parts: seatParts, maxPlayers: game.max_players, stake: Number(game.stake) || 0, pot: Number(game.pot) || 0, roomCode: game.is_private ? game.room_code : null, shareSlug: "poker", meUserId: user?.id, isParticipant: isPlayer, createdAt: game.created_at, onQuit: quitPoker, onToggleReady: async (ready) => {
        await setReady(ready);
      } }),
      canAddBot && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
        const {
          error
        } = await supabase.rpc("poker_add_bot", {
          _game_id: id,
          _bot_name: "Bot"
        });
        if (error) toast.error(error.message);
        else toast.success("Bot ajouté");
      }, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Ajouter un bot"
      ] })
    ] });
  }
  if (game.status === "finished") {
    enriched.find((p) => p.user_id === game.winner_id);
    game.pot + game.stake * players.length;
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "max-w-3xl mx-auto px-4 py-10", children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "poker", meUserId: user?.id, winnerId: game.winner_id, participants: enriched, stake: Number(game.stake) || 0, pot: Number(game.pot) || 0, commissionPct: Number(game.commission_pct) || 10, onReplay: async () => {
      const hadBots = enriched.some((p) => p.is_bot);
      const {
        data,
        error
      } = await supabase.rpc("poker_create", {
        _stake: Number(game.stake) || 0,
        _max: game.max_players,
        _private: !!game.is_private,
        _commission: Number(game.commission_pct) || 10
      });
      if (error) {
        toast.error(error.message);
        return;
      }
      const id2 = String(data);
      if (hadBots) {
        const botsNeeded = Math.max(0, Number(game.max_players) - 1);
        for (let i = 0; i < botsNeeded; i++) {
          await supabase.rpc("poker_add_bot", {
            _game_id: id2
          });
        }
      }
      refreshProfile();
      navigate({
        to: "/jeux/poker/$id",
        params: {
          id: id2
        }
      });
    } }) });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "flex flex-col h-full overflow-hidden overscroll-none", style: {
    background: "radial-gradient(ellipse at 50% 30%, #166534 0%, #14532d 50%, #052e16 100%)"
  }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyBanner, { stake: Number(game?.stake) || 0, phoneVerified: !!profile?.phone_verified }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameReconnectOverlay, { isConnected, isReconnecting, onRetry: retry }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-4 py-2 bg-black/40 backdrop-blur z-20", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate({
        to: "/jeux/$slug",
        params: {
          slug: "poker"
        },
        search: {}
      }), className: "p-1.5 rounded-lg hover:bg-white/10 text-white", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-5 h-5" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-white font-bold text-sm", children: phaseLabelMap[game.phase] || game.phase }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-white/60 text-xs", children: [
          "Main #",
          game.hand_number,
          " · Pot ",
          game.pot?.toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        game.room_code && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: copyCode, className: "flex items-center gap-1 px-2 py-1 rounded-lg bg-white/10 text-white text-xs", children: [
          copied ? /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3 h-3" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-3 h-3" }),
          " ",
          game.room_code
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          const m = !soundOn;
          setSoundOn(m);
          setMuted(m);
        }, className: "w-6 h-6 rounded-full bg-white/10 text-white flex items-center justify-center active:scale-90 transition", children: soundOn ? /* @__PURE__ */ jsxRuntimeExports.jsx(Volume2, { className: "w-3 h-3" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(VolumeX, { className: "w-3 h-3" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "poker", participants: enriched })
      ] })
    ] }),
    betweenHands && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 pointer-events-none", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-black/80 text-white rounded-3xl px-10 py-8 text-center space-y-2 shadow-2xl", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-2xl font-extrabold", children: "Prochaine main" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-6xl font-extrabold text-amber-400", children: countdown }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-white/60 text-sm", children: "Préparation en cours…" })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 relative overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", style: {
      width: W,
      height: H
    }, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute rounded-[50%] shadow-2xl", style: {
        left: cx - rx - 28,
        top: cy - ry - 28,
        width: (rx + 28) * 2,
        height: (ry + 28) * 2,
        background: "radial-gradient(ellipse at 40% 35%, #22c55e 0%, #16a34a 40%, #15803d 70%, #166534 100%)",
        boxShadow: "0 0 0 14px #7c3f00, 0 0 0 24px #5c2d00, 0 30px 80px rgba(0,0,0,0.6)",
        border: "4px solid #a16207"
      } }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute flex gap-1.5 items-center", style: {
        left: cx - 150,
        top: cy - 42
      }, children: [...Array(5)].map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { style: {
        transform: `rotate(${(i - 2) * 2}deg)`
      }, children: i < community.length ? /* @__PURE__ */ jsxRuntimeExports.jsx(PlayingCard, { c: community[i], w: 52, h: 78 }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-lg border-2 border-white/20 bg-white/5", style: {
        width: 52,
        height: 78
      } }) }, i)) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute", style: {
        left: cx - 60,
        top: cy + 45,
        width: 120
      }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-white/50 text-[9px] uppercase tracking-widest", children: "Pot" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-amber-400 font-extrabold text-xl leading-none", children: Number(game.pot || 0).toLocaleString("fr-FR") })
      ] }) }),
      game.phase !== "between_hands" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute", style: {
        left: cx - 50,
        top: cy - 70,
        width: 100
      }, children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center bg-black/50 rounded-full px-3 py-1", children: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-white/80 text-[10px] font-bold uppercase tracking-wider", children: phaseLabelMap[game.phase] }) }) }),
      enriched.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(PlayerSeat, { player: p, idx: (i - myIdx + enriched.length) % enriched.length, myIdx: 0, total: enriched.length, cx, cy, rx, ry, isActive: game.current_player === p.user_id, dealerSeat, sbSeat, bbSeat, commCards: community }, p.id))
    ] }) }) }),
    me?.hole_cards?.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center gap-4 py-2", children: me.hole_cards.map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { style: {
      transform: `rotate(${i === 0 ? -8 : 8}deg)`,
      marginTop: i === 0 ? 0 : -4
    }, children: /* @__PURE__ */ jsxRuntimeExports.jsx(PlayingCard, { c, w: 64, h: 96 }) }, i)) }),
    isMyTurn && game.status === "playing" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 pb-1", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-4 h-4 text-amber-400 flex-shrink-0" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 h-2 bg-white/10 rounded-full overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-full bg-amber-400 transition-all duration-500 rounded-full", style: {
        width: `${timeLeft / 30 * 100}%`
      } }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-sm font-mono font-bold ${timeLeft <= 5 ? "text-red-400 animate-pulse" : "text-white"}`, children: [
        timeLeft,
        "s"
      ] })
    ] }) }),
    isPlayer && isMyTurn && game.status === "playing" && me?.status === "playing" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-3 pb-4 space-y-2", children: [
      canRaise && maxTotal > minRaise && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-black/70 backdrop-blur px-4 py-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between items-center text-xs", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-white/60", children: "Relance" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-extrabold text-amber-400", children: [
            raiseAmt.toLocaleString("fr-FR"),
            " jetons"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "range", min: minRaise, max: maxTotal, step: bigBlind, value: raiseAmt || minRaise, onChange: (e) => setRaiseAmt(Number(e.target.value)), className: "w-full accent-amber-400" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-4 gap-1", children: [{
          l: "½ Pot",
          v: Math.round((game.pot || 0) / 2)
        }, {
          l: "Pot",
          v: game.pot || 0
        }, {
          l: "2×Pot",
          v: (game.pot || 0) * 2
        }, {
          l: "Tapis",
          v: maxTotal
        }].map(({
          l,
          v
        }) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setRaiseAmt(Math.min(Math.max(v, minRaise), maxTotal)), className: "py-1.5 rounded-xl text-[10px] font-bold bg-white/10 text-white hover:bg-amber-500/30 transition-colors", children: l }, l)) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid gap-2", style: {
        gridTemplateColumns: myChips > 0 ? "1fr 1fr 1fr" : "1fr 1fr"
      }, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => doAction("fold"), className: "py-4 rounded-2xl bg-rose-700/90 hover:bg-rose-600 active:scale-95 text-white font-extrabold text-sm transition-all shadow-lg disabled:opacity-50", children: "🃏 Passer" }),
        canCheck ? /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: () => doAction("check"), className: "py-4 rounded-2xl bg-slate-600/90 hover:bg-slate-500 active:scale-95 text-white font-extrabold text-sm transition-all shadow-lg disabled:opacity-50", children: "✓ Checker" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { disabled: busy, onClick: () => doAction("call"), className: "py-4 rounded-2xl bg-blue-600/90 hover:bg-blue-500 active:scale-95 text-white font-extrabold text-sm transition-all shadow-lg disabled:opacity-50", children: [
          "📞 Suivre",
          /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-normal opacity-80", children: Math.min(callAmt, myChips).toLocaleString() })
        ] }),
        canRaise && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { disabled: busy, onClick: () => {
          const amt = Math.min(Math.max(raiseAmt || minRaise, minRaise), maxTotal);
          if (amt >= maxTotal) return doAction("allin");
          doAction(curBet === 0 ? "bet" : "raise", amt);
        }, className: "py-4 rounded-2xl font-extrabold text-sm transition-all shadow-lg active:scale-95 text-black disabled:opacity-50", style: {
          background: "linear-gradient(135deg,#f59e0b,#d97706)"
        }, children: [
          "↑ ",
          curBet === 0 ? "Miser" : "Relancer",
          /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-normal opacity-80", children: Math.min(Math.max(raiseAmt || minRaise, minRaise), maxTotal).toLocaleString() })
        ] })
      ] }),
      myChips > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { disabled: busy, onClick: () => doAction("allin"), className: "w-full py-3.5 rounded-2xl font-extrabold text-sm shadow-xl active:scale-95 transition-all text-white disabled:opacity-50", style: {
        background: "linear-gradient(135deg,#7f1d1d,#dc2626)"
      }, children: [
        "🔥 TAPIS — ",
        myChips.toLocaleString("fr-FR"),
        " jetons"
      ] })
    ] }),
    isPlayer && !isMyTurn && game.status === "playing" && me?.status === "playing" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 pb-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl bg-black/50 text-white/60 text-center py-4 text-sm font-medium", children: "En attente de votre tour…" }) }),
    isPlayer && me?.status === "folded" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 pb-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl bg-black/50 text-rose-400 text-center py-4 text-sm font-medium", children: "Vous avez passé cette main." }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GamePauseControl, { slug: "poker", gameId: id, game, remaining: timeLeft, totalSeconds: 30, isMyTurn, isPlayer, myUserId: user?.id ?? null })
  ] });
}
export {
  PokerPage as component
};
