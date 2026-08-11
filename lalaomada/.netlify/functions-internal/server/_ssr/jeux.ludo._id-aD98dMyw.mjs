import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { D as Route$3, u as useAuth, a as useT } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { u as useGameConnection, a as GameWaitingRoom, G as GameStateMessage, c as GameEndScreen, d as GameReconnectOverlay, b as GamePauseControl } from "./GameReconnectOverlay-DB4s6cH2.mjs";
import { i as isMuted, s as setMuted, a as sfx } from "./game-sounds-246YZn8C.mjs";
import { G as GameSocialFab } from "./GameSocialFab-DlZx4gfi.mjs";
import { P as PhoneVerifyBanner } from "./PhoneVerifyBanner-Dqrff6fy.mjs";
import { u as useFastRealtime } from "./use-fast-realtime-B6ENk2Ox.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/canvas-confetti.mjs";
import { a2 as Plus, a7 as Eye, ag as Pause, aU as Volume2, aV as VolumeX, Q as LogOut, I as Info, X } from "../_libs/lucide-react.mjs";
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
function GameInstructionsBanner({ slug }) {
  const [cfg, setCfg] = reactExports.useState(null);
  const [hidden, setHidden] = reactExports.useState(false);
  const storageKey = `rules-dismissed:${slug}`;
  reactExports.useEffect(() => {
    (async () => {
      const { data } = await supabase.from("game_configs").select("rules_markdown,instructions_dismissible").eq("slug", slug).maybeSingle();
      if (data) setCfg(data);
    })();
  }, [slug]);
  reactExports.useEffect(() => {
    if (!cfg) return;
    if (cfg.instructions_dismissible && localStorage.getItem(storageKey) === "1") {
      setHidden(true);
    } else {
      setHidden(false);
    }
  }, [cfg, storageKey]);
  if (!cfg || hidden || !cfg.rules_markdown?.trim()) return null;
  const dismiss = () => {
    localStorage.setItem(storageKey, "1");
    setHidden(true);
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-primary/5 border border-primary/20 p-3 flex gap-2 text-xs text-foreground", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(Info, { className: "w-4 h-4 shrink-0 mt-0.5 text-primary" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 whitespace-pre-wrap leading-relaxed", children: cfg.rules_markdown }),
    cfg.instructions_dismissible && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: dismiss, "aria-label": "Masquer", className: "opacity-60 hover:opacity-100 shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
  ] });
}
function stepAnim(setter, slot, idx, val, ms) {
  return new Promise((resolve) => {
    setter((prev) => {
      const next = { ...prev };
      const arr = [...next[slot] || []];
      arr[idx] = val;
      next[slot] = arr;
      return next;
    });
    setTimeout(resolve, ms);
  });
}
const COLOR_META = {
  red: { name: "Vert", hex: "#16a34a", bg: "bg-green-500", text: "text-green-700", soft: "bg-green-200", ring: "ring-green-600" },
  // DB red → visual green (TL)
  green: { name: "Jaune", hex: "#eab308", bg: "bg-yellow-400", text: "text-yellow-700", soft: "bg-yellow-200", ring: "ring-yellow-500" },
  // DB green → visual yellow (TR)
  yellow: { name: "Bleu", hex: "#2563eb", bg: "bg-blue-500", text: "text-blue-700", soft: "bg-blue-200", ring: "ring-blue-600" },
  // DB yellow → visual blue (BR)
  blue: { name: "Rouge", hex: "#dc2626", bg: "bg-red-500", text: "text-red-700", soft: "bg-red-200", ring: "ring-red-600" }
  // DB blue → visual red (BL)
};
const PATH = [
  [6, 1],
  [6, 2],
  [6, 3],
  [6, 4],
  [6, 5],
  [5, 6],
  [4, 6],
  [3, 6],
  [2, 6],
  [1, 6],
  [0, 6],
  [0, 7],
  [0, 8],
  [1, 8],
  [2, 8],
  [3, 8],
  [4, 8],
  [5, 8],
  [6, 9],
  [6, 10],
  [6, 11],
  [6, 12],
  [6, 13],
  [6, 14],
  [7, 14],
  [8, 14],
  [8, 13],
  [8, 12],
  [8, 11],
  [8, 10],
  [8, 9],
  [9, 8],
  [10, 8],
  [11, 8],
  [12, 8],
  [13, 8],
  [14, 8],
  [14, 7],
  [14, 6],
  [13, 6],
  [12, 6],
  [11, 6],
  [10, 6],
  [9, 6],
  [8, 5],
  [8, 4],
  [8, 3],
  [8, 2],
  [8, 1],
  [8, 0],
  [7, 0],
  [6, 0]
];
const START_IDX = { red: 0, green: 13, yellow: 26, blue: 39 };
const HOME_STRETCH = {
  red: [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5], [7, 6]],
  green: [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7], [6, 7]],
  yellow: [[7, 13], [7, 12], [7, 11], [7, 10], [7, 9], [7, 8]],
  blue: [[13, 7], [12, 7], [11, 7], [10, 7], [9, 7], [8, 7]]
};
const YARD_SPOTS = {
  red: [[1.6, 1.6], [1.6, 3.4], [3.4, 1.6], [3.4, 3.4]],
  // TL
  green: [[1.6, 10.6], [1.6, 12.4], [3.4, 10.6], [3.4, 12.4]],
  // TR
  yellow: [[10.6, 10.6], [10.6, 12.4], [12.4, 10.6], [12.4, 12.4]],
  // BR
  blue: [[10.6, 1.6], [10.6, 3.4], [12.4, 1.6], [12.4, 3.4]]
  // BL
};
const SAFE_PATH_IDX = /* @__PURE__ */ new Set([0, 8, 13, 21, 26, 34, 39, 47]);
const POWER_TILE_META = {
  boost: { icon: "🚀", label: "Boost", color: "#a855f7" },
  // violet
  shield: { icon: "🛡️", label: "Bouclier", color: "#14b8a6" },
  // teal
  double_roll: { icon: "⚡", label: "2e Lancer", color: "#f472b6" },
  // rose
  lucky_star: { icon: "⭐", label: "Chance", color: "#fbbf24" }
  // or
};
const POWER_TILE_STYLES = `
@keyframes powerTilePulse {
  0%, 100% { transform: scale(1); box-shadow: 0 2px 6px rgba(0,0,0,0.4), inset 0 1px 2px rgba(255,255,255,0.3); }
  50% { transform: scale(1.08); box-shadow: 0 4px 12px rgba(255,255,255,0.3), 0 2px 8px rgba(0,0,0,0.3), inset 0 1px 2px rgba(255,255,255,0.4); }
}
@keyframes powerTileAppear {
  0% { transform: scale(0) rotate(180deg); opacity: 0; }
  60% { transform: scale(1.2) rotate(-10deg); opacity: 1; }
  100% { transform: scale(1) rotate(0); opacity: 1; }
}
@keyframes powerGlow {
  0%, 100% { filter: drop-shadow(0 0 4px currentColor); }
  50% { filter: drop-shadow(0 0 12px currentColor) drop-shadow(0 0 8px currentColor); }
}
@keyframes captureBurst {
  0% { transform: scale(0); opacity: 1; }
  100% { transform: scale(2.5); opacity: 0; }
}
@keyframes shieldRingPulse {
  0%, 100% { box-shadow: 0 0 6px rgba(20, 184, 166, 0.5), 0 0 3px rgba(20, 184, 166, 0.3); border-color: rgba(20, 184, 166, 0.8); }
  50% { box-shadow: 0 0 14px rgba(20, 184, 166, 0.8), 0 0 8px rgba(20, 184, 166, 0.5); border-color: rgba(20, 184, 166, 1); }
}
@keyframes shieldBadgeFloat {
  0%, 100% { transform: translateY(0); }
  50% { transform: translateY(-2px); }
}
@keyframes pawnBoostEffect {
  0% { transform: scale(1); opacity: 1; }
  30% { transform: scale(1.3); opacity: 0.9; }
  100% { transform: scale(1.8); opacity: 0; }
}
@keyframes pawnShieldEffect {
  0% { transform: scale(0.5); opacity: 0; }
  40% { transform: scale(1.2); opacity: 1; }
  100% { transform: scale(1.5); opacity: 0; }
}
@keyframes pawnSparkleEffect {
  0% { transform: scale(0) rotate(0deg); opacity: 0; }
  30% { transform: scale(1) rotate(90deg); opacity: 1; }
  100% { transform: scale(1.5) rotate(180deg); opacity: 0; }
}
@keyframes pawnStarBurst {
  0% { transform: scale(0) rotate(0deg); opacity: 0; }
  20% { transform: scale(1.2) rotate(45deg); opacity: 1; }
  100% { transform: scale(2) rotate(360deg); opacity: 0; }
}
@keyframes tileConsumedFade {
  0% { transform: scale(1); opacity: 0.8; }
  50% { transform: scale(1.3); opacity: 0.4; }
  100% { transform: scale(0); opacity: 0; }
}
@keyframes shieldAuraPulse {
  0%, 100% { box-shadow: 0 0 6px rgba(20,184,166,0.4), inset 0 0 4px rgba(20,184,166,0.2); opacity: 0.7; }
  50% { box-shadow: 0 0 14px rgba(20,184,166,0.7), inset 0 0 8px rgba(20,184,166,0.4); opacity: 1; }
}
@keyframes shieldBurstEffect {
  0% { transform: scale(0.5); opacity: 0; }
  30% { transform: scale(1.4); opacity: 1; }
  100% { transform: scale(2.2); opacity: 0; }
}
@keyframes doubleRollBadgeIn {
  0% { transform: scale(0) rotate(-15deg); opacity: 0; }
  50% { transform: scale(1.3) rotate(5deg); opacity: 1; }
  100% { transform: scale(1) rotate(0deg); opacity: 1; }
}
@keyframes doubleRollBadgePulse {
  0%, 100% { transform: scale(1); }
  50% { transform: scale(1.15); }
}
@keyframes boardBoostRing {
  0% { transform: scale(0.3); opacity: 0; border-width: 6px; }
  30% { opacity: 1; }
  100% { transform: scale(2.5); opacity: 0; border-width: 1px; }
}
@keyframes boardBoostArrow {
  0% { transform: translateY(0) scale(0.5); opacity: 0; }
  20% { opacity: 1; }
  100% { transform: translateY(-30px) scale(1.5); opacity: 0; }
}
@keyframes boardShieldHex {
  0% { transform: scale(0.3) rotate(0deg); opacity: 0; }
  30% { transform: scale(1.2) rotate(5deg); opacity: 1; }
  60% { transform: scale(1) rotate(0deg); opacity: 0.8; }
  100% { transform: scale(2) rotate(0deg); opacity: 0; }
}
@keyframes boardLightningFlash {
  0% { transform: scale(0.3); opacity: 0; }
  20% { transform: scale(1.5); opacity: 1; filter: brightness(2); }
  40% { transform: scale(0.9); opacity: 0.7; }
  100% { transform: scale(2.5); opacity: 0; }
}
@keyframes boardStarBurst {
  0% { transform: scale(0) rotate(0deg); opacity: 0; }
  25% { transform: scale(1.5) rotate(90deg); opacity: 1; }
  100% { transform: scale(2.8) rotate(180deg); opacity: 0; }
}
@keyframes boardRerollDice {
  0% { transform: scale(0.3) rotate(0deg); opacity: 0; }
  25% { transform: scale(1.3) rotate(180deg); opacity: 1; }
  50% { transform: scale(0.9) rotate(360deg); opacity: 0.8; }
  100% { transform: scale(2.2) rotate(720deg); opacity: 0; }
}
@keyframes boardGiftPop {
  0% { transform: scale(0) translateY(10px); opacity: 0; }
  30% { transform: scale(1.4) translateY(-5px); opacity: 1; }
  60% { transform: scale(1) translateY(0); opacity: 0.9; }
  100% { transform: scale(2) translateY(-20px); opacity: 0; }
}
@keyframes boardPowerGlow {
  0%, 100% { opacity: 0.3; transform: scale(1); }
  50% { opacity: 0.6; transform: scale(1.1); }
}
@keyframes bottomSheetIn {
  0% { transform: translateY(100%); opacity: 0; }
  100% { transform: translateY(0); opacity: 1; }
}
@keyframes overlayIn {
  0% { opacity: 0; }
  100% { opacity: 1; }
}
@keyframes timerRing {
  0% { stroke-dashoffset: 0; }
  100% { stroke-dashoffset: var(--ring-offset); }
}
`;
function RealtimeLudoBoard({ gameId, state, participants, myUserId, isSpectator, status, isAdmin, paused, pauseDeadline, afkWarning, afkPauseFor, matchType }) {
  const [boardSize, setBoardSize] = reactExports.useState(600);
  const [busy, setBusy] = reactExports.useState(false);
  const [now, setNow] = reactExports.useState(serverNow());
  const [rollingFace, setRollingFace] = reactExports.useState(null);
  const [displayedPawns, setDisplayedPawns] = reactExports.useState(state.pawns);
  const [animating, setAnimating] = reactExports.useState(false);
  const [afkMax, setAfkMax] = reactExports.useState({ t1: 2, t2: 2, secs: 30 });
  const [avatarMap, setAvatarMap] = reactExports.useState({});
  const [soundOn, setSoundOn] = reactExports.useState(!isMuted());
  const [pawnPowerEffect, setPawnPowerEffect] = reactExports.useState(null);
  const [displayedPowerTiles, setDisplayedPowerTiles] = reactExports.useState(state.power_tiles);
  const [doubleRollPhase, setDoubleRollPhase] = reactExports.useState(null);
  const [boardPowerEffect, setBoardPowerEffect] = reactExports.useState(null);
  const prevPowerTilesRef = reactExports.useRef(state.power_tiles);
  const pendingPowerTilesRef = reactExports.useRef(null);
  reactExports.useRef(null);
  const lastBotKey = reactExports.useRef("");
  reactExports.useRef("");
  const lastTimeoutKey = reactExports.useRef("");
  const animQueueRef = reactExports.useRef(Promise.resolve());
  const botIndex = /* @__PURE__ */ new Map();
  participants.filter((p) => p.is_bot).sort((a, b) => a.slot - b.slot).forEach((b, i) => botIndex.set(b.id, i + 1));
  const nameOf = (p) => p.is_bot ? `Joueur ${botIndex.get(p.id) ?? p.slot}` : p.display_name;
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("afk_t1_max,afk_t2_max,turn_seconds").eq("id", 1).maybeSingle().then(({ data }) => {
      if (data) setAfkMax({ t1: data.afk_t1_max ?? 2, t2: data.afk_t2_max ?? 2, secs: data.turn_seconds ?? 30 });
    });
  }, []);
  const humanUserIds = participants.filter((p) => !p.is_bot && p.user_id).map((p) => p.user_id);
  const humanUserIdsKey = humanUserIds.slice().sort().join(",");
  reactExports.useEffect(() => {
    if (humanUserIds.length === 0) return;
    supabase.from("profiles").select("id, avatar_url").in("id", humanUserIds).then(({ data }) => {
      if (!data) return;
      const map = {};
      data.forEach((r) => {
        if (r.avatar_url) map[r.id] = r.avatar_url;
      });
      setAvatarMap(map);
    });
  }, [humanUserIdsKey]);
  const avatarOf = (p) => {
    if (p.is_bot) return `https://api.dicebear.com/7.x/adventurer/svg?seed=joueur${botIndex.get(p.id) ?? p.slot}`;
    return p.user_id ? avatarMap[p.user_id] : void 0;
  };
  reactExports.useEffect(() => {
    const target = state.pawns || {};
    const current = displayedPawns || {};
    const moves = [];
    const captures = [];
    for (const slot of Object.keys(target)) {
      const tArr = target[slot] || [];
      const cArr = current[slot] || [];
      tArr.forEach((tp, i) => {
        const cp = cArr[i];
        if (!cp) return;
        if (cp.s === tp.s && cp.k === tp.k) return;
        if (tp.s === "yard" && cp.s === "track") {
          captures.push({ slot, idx: i });
        } else {
          moves.push({ slot, idx: i, from: { s: cp.s, k: cp.k }, to: { s: tp.s, k: tp.k } });
        }
      });
    }
    if (moves.length === 0 && captures.length === 0) {
      setDisplayedPawns(target);
      return;
    }
    animQueueRef.current = animQueueRef.current.then(async () => {
      setAnimating(true);
      for (const m of moves) {
        const fromK = m.from.s === "yard" ? -1 : m.from.k;
        const toK = m.to.s === "yard" ? -1 : m.to.k;
        if (m.from.s === "yard" && m.to.s === "track") {
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k: 0 }, 200);
          sfx.pawnMove();
          continue;
        }
        if (m.to.s === "finished") {
          for (let k = fromK + 1; k <= 56; k++) {
            await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k }, 35);
            sfx.pawnStep();
          }
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "finished", k: 56 }, 30);
          sfx.home();
          continue;
        }
        for (let k = fromK + 1; k <= toK; k++) {
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k }, 35);
          sfx.pawnStep();
        }
      }
      for (const c of captures) {
        sfx.capture();
        await stepAnim(setDisplayedPawns, c.slot, c.idx, { s: "yard", k: -1 }, 200);
      }
      setDisplayedPawns(target);
      setAnimating(false);
    });
  }, [state.pawns]);
  reactExports.useEffect(() => {
    const u = () => {
      const vh = window.innerHeight, vw = window.innerWidth;
      setBoardSize(Math.max(320, Math.min(vh - 320, vw - 40, 820)));
    };
    u();
    window.addEventListener("resize", u);
    return () => window.removeEventListener("resize", u);
  }, []);
  reactExports.useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 500);
    return () => clearInterval(t);
  }, []);
  const partsBySlot = reactExports.useMemo(() => {
    const m = /* @__PURE__ */ new Map();
    participants.forEach((p) => m.set(p.slot, p));
    return m;
  }, [participants]);
  const currentPart = partsBySlot.get(state.turn_slot);
  const isMyTurn = !!currentPart && !currentPart.is_bot && currentPart.user_id === myUserId && !isSpectator && status === "playing";
  const turnStartMs = state.turn_started_at ? new Date(state.turn_started_at).getTime() : now;
  const elapsed = Math.max(0, Math.floor((now - turnStartMs) / 1e3));
  const remaining = Math.max(0, afkMax.secs - elapsed);
  reactExports.useEffect(() => {
    if (status !== "playing" || !currentPart?.is_bot) return;
    if (animating) return;
    const key = `${state.turn_slot}-${state.dice}-${state.must_move}-${state.turn_started_at}`;
    if (lastBotKey.current === key) return;
    lastBotKey.current = key;
    const min = state.must_move ? 2500 : 1500;
    const max = state.must_move ? 4500 : 3500;
    const delay = min + Math.random() * (max - min);
    const t = setTimeout(async () => {
      try {
        if (state.must_move) {
          await supabase.rpc("ludo_bot_play", { _game_id: gameId });
        } else {
          await supabase.rpc("ludo_roll", { _game_id: gameId });
        }
      } catch {
      }
    }, delay);
    return () => clearTimeout(t);
  }, [currentPart?.is_bot, state.turn_slot, state.dice, state.must_move, state.turn_started_at, status, gameId, animating]);
  reactExports.useEffect(() => {
    if (status !== "playing") return;
    if (paused) return;
    if (remaining > 0) return;
    const key = `${state.turn_slot}-${state.turn_started_at}`;
    if (lastTimeoutKey.current === key) return;
    lastTimeoutKey.current = key;
    const t = setTimeout(async () => {
      const { error } = await supabase.rpc("ludo_check_timeout", { _game_id: gameId });
    }, 600);
    return () => clearTimeout(t);
  }, [remaining, status, gameId, state.turn_slot, state.turn_started_at]);
  const roll = async () => {
    if (!isMyTurn || state.must_move || busy) return;
    setBusy(true);
    sfx.diceRoll();
    const start = Date.now();
    const anim = setInterval(() => {
      setRollingFace(1 + Math.floor(Math.random() * 6));
      if (Date.now() - start > 700) clearInterval(anim);
    }, 80);
    try {
      const { error } = await supabase.rpc("ludo_roll", { _game_id: gameId });
      if (error) {
        const friendlyMap = {
          "Partie pas en cours": "La partie est terminée",
          "Pas votre tour": "Ce n'est pas votre tour",
          "Déjà lancé, déplacez un pion": "Vous avez déjà lancé le dé"
        };
        toast.error(friendlyMap[error.message] || error.message, { duration: 2e3 });
      }
    } finally {
      setTimeout(() => {
        setRollingFace(null);
        setBusy(false);
        sfx.diceLand();
      }, 750);
    }
  };
  const movablePawnIdxs = reactExports.useMemo(() => {
    if (!isMyTurn || !state.must_move || state.dice == null) return /* @__PURE__ */ new Set();
    const slot = state.turn_slot;
    const arr = state.pawns?.[String(slot)] || [];
    const set = /* @__PURE__ */ new Set();
    arr.forEach((p, i) => {
      if (p.s === "finished") return;
      if (p.s === "yard") {
        if (state.dice === 6) set.add(i);
      } else if (p.k + state.dice <= 56) set.add(i);
    });
    return set;
  }, [isMyTurn, state.must_move, state.dice, state.turn_slot, state.pawns]);
  const [selectedIdx, setSelectedIdx] = reactExports.useState(null);
  const turnKey = `${state.turn_slot}-${state.turn_started_at}-${state.dice ?? "x"}`;
  const lastTurnKeyRef = reactExports.useRef("");
  reactExports.useEffect(() => {
    if (lastTurnKeyRef.current !== turnKey) {
      lastTurnKeyRef.current = turnKey;
      setSelectedIdx(null);
    }
  }, [turnKey]);
  const moveLockRef = reactExports.useRef(false);
  const movePawn = async (idx) => {
    if (moveLockRef.current) return;
    if (!movablePawnIdxs.has(idx) || busy || animating) return;
    moveLockRef.current = true;
    setSelectedIdx(idx);
    setBusy(true);
    try {
      const { error } = await supabase.rpc("ludo_move", { _game_id: gameId, _pawn_idx: idx });
      if (error) {
        const friendlyMap = {
          "Partie pas en cours": "La partie est terminée",
          "Pas votre tour": "Ce n'est pas votre tour",
          "Pion inconnu": "Pion invalide",
          "Pion deja arrive": "Ce pion est déjà arrivé",
          "Sortie possible avec un 6": "Il faut un 6 pour sortir un pion",
          "Depassement": "Déplacement impossible"
        };
        toast.error(friendlyMap[error.message] || error.message, { duration: 2e3 });
        setSelectedIdx(null);
      }
    } finally {
      setBusy(false);
      moveLockRef.current = false;
    }
  };
  const [noMoveDisplay, setNoMoveDisplay] = reactExports.useState(null);
  reactExports.useEffect(() => {
    const nmd = state.no_move_display;
    if (nmd && nmd.until) {
      const untilMs = new Date(nmd.until).getTime();
      const nowMs = Date.now();
      if (untilMs > nowMs) {
        setNoMoveDisplay({ slot: nmd.slot, dice: nmd.dice });
        const t = setTimeout(() => setNoMoveDisplay(null), untilMs - nowMs);
        return () => clearTimeout(t);
      }
    }
    setNoMoveDisplay(null);
  }, [state.no_move_display]);
  const displaySlot = noMoveDisplay ? noMoveDisplay.slot : state.turn_slot;
  const displayDice = noMoveDisplay ? noMoveDisplay.dice : state.dice;
  const displayPart = partsBySlot.get(displaySlot) || currentPart;
  const lastPowerEventRef = reactExports.useRef("");
  reactExports.useEffect(() => {
    const pe = state.power_event;
    if (!pe || !pe.at) return;
    const key = `${pe.type}-${pe.at}-${pe.slot}`;
    if (lastPowerEventRef.current === key) return;
    lastPowerEventRef.current = key;
    const tileType = pe.reward || pe.type;
    sfx.powerTile(tileType);
    const toastMsgs = {
      boost: `🚀 Boost ! +${pe.dice || "?"} cases`,
      shield: "🛡️ Bouclier activé !",
      double_roll: "⚡ Deuxième lancer !",
      lucky_star: `⭐ Chance : ${pe.reward || "?"}`,
      reroll: "🎲 Re-lancer !",
      free_pawn: "🎁 Pion gratuit sorti !"
    };
    let msg = toastMsgs[pe.reward || pe.type] || toastMsgs[pe.type] || "Pouvoir activé";
    const isMyPowerEvent = participants.some((p) => p.slot === pe.slot && p.user_id === myUserId);
    const isBotPower = participants.some((p) => p.slot === pe.slot && p.is_bot);
    if (isMyPowerEvent) {
      toast.success(msg, { duration: 2500 });
    } else if (!isBotPower) {
      toast.info(msg, { duration: 1500 });
    }
    const effectType = pe.reward || pe.type;
    setPawnPowerEffect({ slot: pe.slot, type: effectType, key, pawn: pe.pawn });
    setTimeout(() => setPawnPowerEffect(null), 1500);
    const eventCell = pe.cell;
    if (eventCell !== void 0 && eventCell !== null) {
      setBoardPowerEffect({ cell: eventCell, type: effectType, key });
      setTimeout(() => setBoardPowerEffect(null), 1800);
    }
  }, [state.power_event]);
  reactExports.useEffect(() => {
    const pe = state.power_event;
    if (pe && pe.at) {
      pendingPowerTilesRef.current = state.power_tiles;
      if (!animating) {
        setDisplayedPowerTiles(state.power_tiles);
        pendingPowerTilesRef.current = null;
      }
    } else {
      setDisplayedPowerTiles(state.power_tiles);
      pendingPowerTilesRef.current = null;
    }
    prevPowerTilesRef.current = state.power_tiles;
  }, [state.power_tiles, state.power_event]);
  reactExports.useEffect(() => {
    if (!animating && pendingPowerTilesRef.current) {
      setDisplayedPowerTiles(pendingPowerTilesRef.current);
      pendingPowerTilesRef.current = null;
    }
  }, [animating]);
  reactExports.useEffect(() => {
    const drp = state.double_roll_pending;
    if (drp !== null && drp !== void 0) {
      setDoubleRollPhase({ slot: drp, phase: "2x" });
    } else if (doubleRollPhase && doubleRollPhase.phase === "2x") {
      const isStillTheirTurn = state.turn_slot === doubleRollPhase.slot;
      if (isStillTheirTurn) {
        setDoubleRollPhase({ slot: doubleRollPhase.slot, phase: "1x" });
        const t = setTimeout(() => setDoubleRollPhase(null), 2e3);
        return () => clearTimeout(t);
      } else {
        setDoubleRollPhase(null);
      }
    }
  }, [state.double_roll_pending, state.turn_slot]);
  const lastEventRef = reactExports.useRef("");
  reactExports.useEffect(() => {
    const ev = state.last_event;
    if (!ev || ev === lastEventRef.current) return;
    lastEventRef.current = ev;
    if (ev.startsWith("six")) sfx.six();
    else if (ev.startsWith("capture")) sfx.capture();
    else if (ev.startsWith("home")) sfx.home();
    else if (ev.startsWith("roll:") && ev.endsWith(":no_move")) sfx.noMove();
    else if (ev === "move") sfx.turnChange();
    else if (ev === "double_roll:rejoue") sfx.powerTile("double_roll");
    else if (ev === "bot:pass") sfx.noMove();
  }, [state.last_event]);
  const lastAutoMoveKey = reactExports.useRef("");
  reactExports.useEffect(() => {
    if (!isMyTurn || !state.must_move || state.dice == null) return;
    if (movablePawnIdxs.size !== 1) return;
    if (busy || animating) return;
    const key = `${gameId}-${state.turn_slot}-${state.dice}-${state.turn_started_at}`;
    if (lastAutoMoveKey.current === key) return;
    lastAutoMoveKey.current = key;
    const only = movablePawnIdxs.values().next().value;
    queueMicrotask(() => {
      movePawn(only);
    });
  }, [isMyTurn, state.must_move, state.dice, state.turn_slot, state.turn_started_at, movablePawnIdxs, gameId, busy, animating]);
  const stickyMovableRef = reactExports.useRef({ key: "", indices: /* @__PURE__ */ new Set() });
  if (isMyTurn && state.must_move && state.dice != null && movablePawnIdxs.size > 0) {
    stickyMovableRef.current = { key: turnKey, indices: new Set(movablePawnIdxs) };
  }
  const visibleMovable = (() => {
    if (selectedIdx !== null) return /* @__PURE__ */ new Set();
    if (movablePawnIdxs.size > 0) return movablePawnIdxs;
    if (stickyMovableRef.current.key === turnKey) return stickyMovableRef.current.indices;
    return /* @__PURE__ */ new Set();
  })();
  isMyTurn && state.must_move && state.dice != null && visibleMovable.size > 0;
  const cellPx = boardSize / 15;
  const renderPawns = [];
  const cellGroups = /* @__PURE__ */ new Map();
  participants.forEach((part) => {
    const arr = displayedPawns?.[String(part.slot)] || [];
    arr.forEach((p, i) => {
      let row, col;
      if (p.s === "yard") {
        [row, col] = YARD_SPOTS[part.color][i];
      } else if (p.s === "finished") {
        const offsets = {
          green: [6.35, 7],
          yellow: [7, 7.65],
          blue: [7.65, 7],
          red: [7, 6.35]
        };
        [row, col] = offsets[part.color];
      } else {
        let cell;
        if (p.k <= 50) cell = PATH[(START_IDX[part.color] + p.k) % 52];
        else cell = HOME_STRETCH[part.color][p.k - 51];
        row = cell[0];
        col = cell[1];
        const key = `${row}-${col}`;
        const n = cellGroups.get(key) || 0;
        cellGroups.set(key, n + 1);
        if (n > 0) {
          const angle = n / 4 * Math.PI * 2;
          row += Math.sin(angle) * 0.18;
          col += Math.cos(angle) * 0.18;
        }
      }
      renderPawns.push({
        key: `${part.slot}-${i}`,
        slot: part.slot,
        idx: i,
        color: part.color,
        row,
        col,
        movable: part.slot === state.turn_slot && visibleMovable.has(i),
        hasShield: state.shields?.[String(part.slot)] === true
      });
    });
  });
  const quadrants = [
    { color: "red", r: 0, c: 0 },
    // TL → green visuals
    { color: "green", r: 0, c: 9 },
    // TR → yellow visuals
    { color: "yellow", r: 9, c: 9 },
    // BR → blue visuals
    { color: "blue", r: 9, c: 0 }
    // BL → red visuals
  ];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("style", { dangerouslySetInnerHTML: { __html: POWER_TILE_STYLES } }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full px-2", children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameInstructionsBanner, { slug: "ludo" }) }),
    (() => {
      const twoMode = participants.length === 2;
      const slotColors = twoMode ? participants.map((pp) => pp.color) : ["red", "green", "blue", "yellow"];
      return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `grid w-full max-w-xs gap-1.5 justify-items-center ${twoMode ? "grid-cols-2 grid-rows-1" : "grid-cols-2 grid-rows-2"}`, children: slotColors.map((slotColor) => {
        const p = participants.find((pp) => pp.color === slotColor);
        if (!p) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", {}, slotColor);
        const isCurrent = p.slot === displaySlot && status === "playing";
        const pawnArr = state.pawns?.[String(p.slot)] || [];
        const finishedCount = pawnArr.filter((pw) => pw?.s === "finished").length;
        pawnArr.length || 4;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: `flex w-full items-center gap-2 rounded-xl bg-card px-3 py-1.5 shadow ring-2 transition ${isCurrent ? `${COLOR_META[p.color].ring} scale-105 border-2 border-white shadow-lg shadow-white/20` : "ring-transparent opacity-70 border border-white/10"} ${p.forfeited ? "line-through opacity-40" : ""}`,
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `h-7 w-7 rounded-full overflow-hidden ring-2 ${COLOR_META[p.color].ring} ${COLOR_META[p.color].bg} ${isCurrent ? "animate-pulse" : ""}`, children: avatarOf(p) ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: avatarOf(p), alt: nameOf(p), className: "h-full w-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex h-full w-full items-center justify-center text-[9px] font-bold text-white", children: nameOf(p).slice(0, 2).toUpperCase() }) }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -right-1 -top-1 flex h-3.5 min-w-3.5 items-center justify-center rounded-full border border-white bg-emerald-500 px-0.5 text-[8px] font-bold leading-none text-white shadow", children: finishedCount })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex min-w-0 flex-col leading-tight", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `truncate text-xs font-semibold leading-none ${COLOR_META[p.color].text}`, children: nameOf(p) }),
                  doubleRollPhase && doubleRollPhase.slot === p.slot && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "span",
                    {
                      className: "shrink-0 rounded px-1 text-[7px] font-bold leading-tight text-white",
                      style: {
                        background: doubleRollPhase.phase === "2x" ? "#ec4899" : "#6366f1",
                        animation: doubleRollPhase.phase === "2x" ? "doubleRollBadgeIn 0.3s ease-out, doubleRollBadgePulse 1s ease-in-out 0.3s infinite" : "doubleRollBadgeIn 0.3s ease-out"
                      },
                      children: [
                        "⚡",
                        doubleRollPhase.phase
                      ]
                    },
                    doubleRollPhase.phase
                  ),
                  state.shields?.[String(p.slot)] === true && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "shrink-0 text-[8px] leading-none", children: "🛡️" }),
                  matchType === "groupe" && p.team && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `shrink-0 text-[8px] leading-none ${p.team === 1 ? "text-red-600" : "text-blue-600"}`, children: p.team === 1 ? "🔴" : "🔵" })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "truncate text-[9px] leading-none text-muted-foreground", children: [
                  "T1 ",
                  p.afk_t1 ?? 0,
                  "/",
                  afkMax.t1,
                  " · T2 ",
                  p.afk_t2 ?? 0,
                  "/",
                  afkMax.t2
                ] })
              ] })
            ]
          },
          p.id
        );
      }) });
    })(),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "div",
      {
        className: "relative overflow-hidden rounded-xl bg-white shadow-2xl ring-2 ring-slate-800",
        style: { width: boardSize, height: boardSize },
        children: [
          quadrants.map((q) => /* @__PURE__ */ jsxRuntimeExports.jsx(
            "div",
            {
              className: "absolute",
              style: { left: q.c * cellPx, top: q.r * cellPx, width: 6 * cellPx, height: 6 * cellPx, background: COLOR_META[q.color].hex }
            },
            q.color
          )),
          /* @__PURE__ */ jsxRuntimeExports.jsx(PathCells, { cellPx }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(CenterTriangles, { cellPx }),
          displayedPowerTiles && displayedPowerTiles.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: displayedPowerTiles.map((tile, ti) => {
            const [row, col] = PATH[tile.cell];
            const meta = POWER_TILE_META[tile.type] || POWER_TILE_META.lucky_star;
            return /* @__PURE__ */ jsxRuntimeExports.jsx(
              "div",
              {
                className: "absolute flex items-center justify-center",
                style: {
                  left: col * cellPx + cellPx * 0.1,
                  top: row * cellPx + cellPx * 0.1,
                  width: cellPx * 0.8,
                  height: cellPx * 0.8,
                  zIndex: 10,
                  fontSize: cellPx * 0.52,
                  lineHeight: 1,
                  pointerEvents: "none",
                  animation: "powerTilePulse 2s ease-in-out infinite",
                  transition: "left 0.4s ease, top 0.4s ease"
                },
                children: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
                  animation: "powerGlow 1.5s ease-in-out infinite",
                  color: meta.color,
                  display: "inline-block",
                  filter: `drop-shadow(0 0 6px ${meta.color}) drop-shadow(0 0 2px rgba(0,0,0,0.9))`,
                  fontWeight: "bold"
                }, children: meta.icon })
              },
              `pt-${ti}`
            );
          }) }),
          boardPowerEffect && (() => {
            const [row, col] = PATH[boardPowerEffect.cell];
            if (!row && !col) return null;
            const cx = col * cellPx + cellPx / 2;
            const cy = row * cellPx + cellPx / 2;
            const effType = boardPowerEffect.type;
            const effKey = boardPowerEffect.key;
            const colors = {
              boost: "#a855f7",
              shield: "#14b8a6",
              double_roll: "#ec4899",
              lucky_star: "#fbbf24",
              reroll: "#ec4899",
              free_pawn: "#14b8a6"
            };
            const icons = {
              boost: "🚀",
              shield: "🛡️",
              double_roll: "⚡",
              lucky_star: "⭐",
              reroll: "🎲",
              free_pawn: "🎁"
            };
            const c = colors[effType] || "#a855f7";
            const icon = icons[effType] || "✨";
            const animMap = {
              boost: "boardBoostRing",
              shield: "boardShieldHex",
              double_roll: "boardLightningFlash",
              lucky_star: "boardStarBurst",
              reroll: "boardRerollDice",
              free_pawn: "boardGiftPop"
            };
            const anim = animMap[effType] || "boardBoostRing";
            return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute pointer-events-none", style: { left: cx, top: cy, zIndex: 50, transform: "translate(-50%, -50%)" }, children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute rounded-full",
                  style: {
                    width: cellPx * 1.2,
                    height: cellPx * 1.2,
                    left: -cellPx * 0.6,
                    top: -cellPx * 0.6,
                    border: `4px solid ${c}`,
                    animation: `${anim} 1.5s ease-out forwards`,
                    borderRadius: effType === "shield" ? "30%" : "50%"
                  }
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute",
                  style: {
                    fontSize: cellPx * 0.8,
                    lineHeight: 1,
                    left: -cellPx * 0.4,
                    top: -cellPx * 0.4,
                    width: cellPx * 0.8,
                    height: cellPx * 0.8,
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    animation: `${anim} 1.5s ease-out forwards`,
                    filter: `drop-shadow(0 0 8px ${c})`
                  },
                  children: icon
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute rounded-full",
                  style: {
                    width: cellPx * 2,
                    height: cellPx * 2,
                    left: -cellPx,
                    top: -cellPx,
                    background: `radial-gradient(circle, ${c}40 0%, transparent 70%)`,
                    animation: "boardPowerGlow 1s ease-out forwards"
                  }
                }
              ),
              [0, 1, 2, 3, 4, 5].map((i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute rounded-full",
                  style: {
                    width: "5px",
                    height: "5px",
                    background: c,
                    left: 0,
                    top: 0,
                    animation: `pawnStarBurst 1s ease-out ${i * 0.08}s forwards`,
                    transform: `rotate(${i * 60}deg) translateY(-${cellPx * 0.6}px)`
                  }
                },
                i
              ))
            ] }, `bpe-${effKey}`);
          })(),
          quadrants.map((q) => {
            const meta = COLOR_META[q.color];
            const innerLeft = (q.c + 1) * cellPx;
            const innerTop = (q.r + 1) * cellPx;
            const innerSize = 4 * cellPx;
            return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute rounded-2xl bg-white shadow-inner",
                  style: { left: innerLeft, top: innerTop, width: innerSize, height: innerSize, border: `2px solid ${meta.hex}` }
                }
              ),
              YARD_SPOTS[q.color].map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute rounded-full",
                  style: {
                    left: (p[1] + 0.5) * cellPx - cellPx * 0.45,
                    top: (p[0] + 0.5) * cellPx - cellPx * 0.45,
                    width: cellPx * 0.9,
                    height: cellPx * 0.9,
                    background: meta.hex,
                    opacity: 0.85
                  }
                },
                i
              ))
            ] }, `yard-${q.color}`);
          }),
          renderPawns.map((p) => {
            COLOR_META[p.color];
            const PAWN_HEX = {
              red: { deep: "#00A63E", dark: "#064e2b" },
              // vert
              green: { deep: "#F59E0B", dark: "#5c3a00" },
              // jaune
              yellow: { deep: "#1D4ED8", dark: "#0b1f5c" },
              // bleu
              blue: { deep: "#DC2626", dark: "#5c0a0a" }
              // rouge
            };
            const pc = PAWN_HEX[p.color];
            const hitPad = p.movable ? 0 : cellPx * 0.14;
            const hitSize = p.movable ? cellPx : cellPx * 0.72;
            const visualInset = p.movable ? cellPx * 0.14 : 0;
            return /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                onPointerDown: p.movable ? (e) => {
                  e.preventDefault();
                  movePawn(p.idx);
                } : void 0,
                onClick: p.movable ? (e) => {
                  e.preventDefault();
                } : void 0,
                disabled: !p.movable,
                className: "absolute flex items-center justify-center rounded-full p-0 outline-none border-0 bg-transparent select-none",
                style: {
                  left: p.col * cellPx + hitPad,
                  top: p.row * cellPx + hitPad,
                  width: hitSize,
                  height: hitSize,
                  transition: p.movable ? "none" : "left 0.12s linear, top 0.12s linear",
                  cursor: p.movable ? "pointer" : "default",
                  pointerEvents: p.movable ? "auto" : "none",
                  touchAction: "manipulation",
                  WebkitTapHighlightColor: "transparent",
                  zIndex: p.movable ? 30 : 20,
                  padding: visualInset
                },
                children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "div",
                  {
                    className: `relative rounded-full w-full h-full ${p.movable ? "ludo-playable" : ""}`,
                    style: {
                      background: `radial-gradient(circle at 30% 25%, #ffffff 0%, rgba(255,255,255,0.35) 6%, ${pc.deep} 20%, ${pc.deep} 60%, ${pc.dark} 100%)`,
                      boxShadow: `inset 0 0 0 1px rgba(255,255,255,0.35), inset -2px -3px 6px rgba(0,0,0,0.55), inset 2px 2px 4px rgba(255,255,255,0.3), 0 4px 8px rgba(0,0,0,0.55), 0 1px 2px rgba(0,0,0,0.4)`,
                      filter: "saturate(1.35) contrast(1.1)"
                    },
                    children: [
                      state.shields?.[String(p.slot)] === true && /* @__PURE__ */ jsxRuntimeExports.jsx(
                        "div",
                        {
                          className: "absolute pointer-events-none rounded-full",
                          style: {
                            inset: "-4px",
                            border: "2.5px solid rgba(20,184,166,0.9)",
                            animation: "shieldAuraPulse 1.5s ease-in-out infinite",
                            borderRadius: "50%"
                          },
                          children: /* @__PURE__ */ jsxRuntimeExports.jsx(
                            "span",
                            {
                              className: "absolute -top-2 -right-1 text-[10px]",
                              style: { animation: "shieldBadgeFloat 1s ease-in-out infinite" },
                              children: "🛡️"
                            }
                          )
                        }
                      ),
                      pawnPowerEffect && pawnPowerEffect.slot === p.slot && (pawnPowerEffect.type === "shield" || pawnPowerEffect.pawn === p.idx) && (() => {
                        const effType = pawnPowerEffect.type;
                        pawnPowerEffect.key;
                        const effectColors = {
                          boost: "#a855f7",
                          shield: "#14b8a6",
                          double_roll: "#ec4899",
                          lucky_star: "#e2e8f0",
                          reroll: "#ec4899",
                          free_pawn: "#14b8a6"
                        };
                        const effColor = effectColors[effType] || "#a855f7";
                        const effectIcons = {
                          boost: "🚀",
                          shield: "🛡️",
                          double_roll: "⚡",
                          lucky_star: "⭐",
                          reroll: "🎲",
                          free_pawn: "🎁"
                        };
                        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute pointer-events-none", style: { inset: "-8px", zIndex: 40 }, children: [
                          /* @__PURE__ */ jsxRuntimeExports.jsx(
                            "div",
                            {
                              className: "absolute inset-0 rounded-full",
                              style: {
                                border: `3px solid ${effColor}`,
                                animation: "pawnBoostEffect 1.2s ease-out forwards",
                                borderRadius: "50%"
                              }
                            }
                          ),
                          effType === "shield" && /* @__PURE__ */ jsxRuntimeExports.jsx(
                            "div",
                            {
                              className: "absolute inset-0 rounded-full",
                              style: {
                                border: `4px solid ${effColor}`,
                                animation: "shieldBurstEffect 1.5s ease-out forwards",
                                borderRadius: "50%"
                              }
                            }
                          ),
                          /* @__PURE__ */ jsxRuntimeExports.jsx(
                            "div",
                            {
                              className: "absolute -top-3 left-1/2 -translate-x-1/2 text-lg",
                              style: {
                                animation: "pawnSparkleEffect 1.2s ease-out forwards",
                                filter: `drop-shadow(0 0 4px ${effColor})`
                              },
                              children: effectIcons[effType] || "✨"
                            }
                          ),
                          [0, 1, 2, 3].map((i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                            "div",
                            {
                              className: "absolute rounded-full",
                              style: {
                                width: "4px",
                                height: "4px",
                                background: effColor,
                                top: "50%",
                                left: "50%",
                                animation: `pawnStarBurst 1s ease-out ${i * 0.1}s forwards`,
                                transform: `rotate(${i * 90}deg) translateY(-12px)`
                              }
                            },
                            i
                          ))
                        ] });
                      })(),
                      /* @__PURE__ */ jsxRuntimeExports.jsx(
                        "span",
                        {
                          className: "absolute rounded-full pointer-events-none",
                          style: {
                            left: "18%",
                            top: "12%",
                            width: "38%",
                            height: "28%",
                            background: "radial-gradient(ellipse at center, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0) 70%)",
                            filter: "blur(0.5px)"
                          }
                        }
                      ),
                      p.hasShield && /* @__PURE__ */ jsxRuntimeExports.jsx(
                        "span",
                        {
                          className: "absolute -top-1 -right-1 flex items-center justify-center rounded-full",
                          style: {
                            width: "42%",
                            height: "42%",
                            background: "rgba(34,197,94,0.95)",
                            border: "2px solid white",
                            boxShadow: "0 1px 3px rgba(0,0,0,0.5)",
                            fontSize: "60%",
                            zIndex: 5
                          },
                          children: "🛡️"
                        }
                      )
                    ]
                  }
                )
              },
              p.key
            );
          })
        ]
      }
    ),
    (() => {
      const myPart = participants.find((p) => p.user_id === myUserId);
      if (myPart?.forfeited && status !== "finished") {
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full rounded-2xl bg-destructive/10 border-2 border-destructive/30 p-4 text-center", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-2xl mb-1", children: "🏳️" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-destructive text-sm", children: "Vous avez abandonné" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mt-1", children: "Vous ne pouvez plus jouer dans cette partie. Vous pouvez regarder la suite en spectateur." })
        ] });
      }
      const anyForfeited = participants.filter((p) => p.forfeited);
      if (anyForfeited.length > 0 && status === "playing") {
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full rounded-xl bg-amber-500/10 border border-amber-500/30 px-3 py-1.5 text-center text-[11px] text-amber-600 dark:text-amber-400", children: [
          anyForfeited.map((p) => nameOf(p)).join(", "),
          " ",
          anyForfeited.length > 1 ? "ont abandonné" : "a abandonné"
        ] });
      }
      return null;
    })(),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: isSpectator ? "Mode spectateur" : status !== "playing" ? "En attente du démarrage…" : currentPart && (currentPart.is_bot ? `${nameOf(currentPart)} joue…` : isMyTurn ? state.must_move ? "" : "À toi de lancer le dé" : `Tour de ${nameOf(currentPart)}`) }),
      status === "playing" && (() => {
        const pct = afkMax.secs > 0 ? remaining / afkMax.secs : 0;
        const timerColor = remaining <= 5 ? "text-destructive" : remaining <= 10 ? "text-amber-500" : "text-emerald-500";
        const showAfk = currentPart && !currentPart.is_bot && ((currentPart.afk_t1 ?? 0) > 0 || (currentPart.afk_t2 ?? 0) > 0);
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1 text-sm font-bold ${timerColor} ${remaining <= 5 ? "animate-pulse" : ""}`, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("svg", { width: "20", height: "20", viewBox: "0 0 24 24", className: remaining <= 5 ? "animate-pulse" : "", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: "12", cy: "12", r: "9", fill: "none", stroke: "currentColor", strokeWidth: "2", opacity: "0.2" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "circle",
                {
                  cx: "12",
                  cy: "12",
                  r: "9",
                  fill: "none",
                  stroke: "currentColor",
                  strokeWidth: "2",
                  strokeDasharray: `${2 * Math.PI * 9}`,
                  strokeDashoffset: `${2 * Math.PI * 9 * (1 - pct)}`,
                  strokeLinecap: "round",
                  transform: "rotate(-90 12 12)",
                  style: { transition: "stroke-dashoffset 0.5s ease" }
                }
              )
            ] }),
            remaining,
            "s"
          ] }),
          showAfk && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 text-[10px] text-muted-foreground", children: [
            currentPart.afk_t1 > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `px-1.5 py-0.5 rounded-full ${currentPart.afk_t1 >= afkMax.t1 ? "bg-amber-500/20 text-amber-600 font-semibold" : "bg-muted"}`, children: [
              "T1 ",
              currentPart.afk_t1,
              "/",
              afkMax.t1
            ] }),
            currentPart.afk_t2 > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `px-1.5 py-0.5 rounded-full ${currentPart.afk_t2 >= afkMax.t2 ? "bg-amber-500/20 text-amber-600 font-semibold" : "bg-muted"}`, children: [
              "T2 ",
              currentPart.afk_t2,
              "/",
              afkMax.t2
            ] })
          ] })
        ] });
      })(),
      isAdmin && status === "playing" && currentPart && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-lg bg-amber-100 border border-amber-300 px-2 py-1 flex flex-wrap items-center gap-1 text-[10px]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold text-amber-900", children: [
          "🎲 Dé de ",
          currentPart.display_name,
          " :"
        ] }),
        [1, 2, 3, 4, 5, 6].map((n) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: async () => {
          const { error } = await supabase.rpc("super_player_set_dice", { _game_id: gameId, _slot: state.turn_slot, _value: n });
          if (error) toast.error(error.message);
          else toast.success(`Prochain dé: ${n}`);
        }, className: "w-5 h-5 rounded bg-white text-[11px] font-bold leading-none hover:bg-amber-200", children: n }, n))
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: roll,
          disabled: !isMyTurn || state.must_move || busy,
          className: `group relative h-20 w-20 rounded-2xl bg-white shadow-xl ring-2 transition ${displayPart ? COLOR_META[displayPart.color].ring : "ring-slate-300"} ${isMyTurn && !state.must_move ? "hover:scale-110 active:scale-95" : "opacity-60"} ${rollingFace !== null ? "animate-spin" : ""}`,
          children: /* @__PURE__ */ jsxRuntimeExports.jsx(DiceFace, { value: rollingFace ?? displayDice ?? 0 })
        }
      ),
      displayDice != null && rollingFace === null && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-lg font-extrabold text-foreground", children: [
        "Dé : ",
        displayDice
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      GamePauseControl,
      {
        slug: "ludo",
        gameId,
        game: {
          paused: paused ?? false,
          pause_deadline: pauseDeadline ?? null,
          afk_warning: afkWarning ?? null,
          afk_pause_for: afkPauseFor ?? null,
          status
        },
        remaining,
        totalSeconds: afkMax.secs,
        isMyTurn,
        isPlayer: !isSpectator && participants.some((p) => p.user_id === myUserId && !p.is_bot),
        myUserId,
        simplePause: participants.some((p) => p.is_bot)
      }
    )
  ] });
}
function PathCells({ cellPx }) {
  const cells = [];
  for (let r = 0; r < 15; r++) {
    for (let c = 0; c < 15; c++) {
      const inCross = r >= 6 && r <= 8 || c >= 6 && c <= 8;
      if (!inCross) continue;
      const inCenter = r >= 6 && r <= 8 && c >= 6 && c <= 8;
      if (inCenter) continue;
      let fill = "#ffffff";
      if (c === 7 && r >= 1 && r <= 5) fill = COLOR_META.green.hex;
      else if (c === 7 && r >= 9 && r <= 13) fill = COLOR_META.blue.hex;
      else if (r === 7 && c >= 1 && c <= 5) fill = COLOR_META.red.hex;
      else if (r === 7 && c >= 9 && c <= 13) fill = COLOR_META.yellow.hex;
      const startCells = [
        { rc: PATH[START_IDX.red], color: "red" },
        // green start
        { rc: PATH[START_IDX.green], color: "green" },
        // yellow start
        { rc: PATH[START_IDX.yellow], color: "yellow" },
        // blue start
        { rc: PATH[START_IDX.blue], color: "blue" }
        // red start
      ];
      const startMatch = startCells.find((s) => s.rc[0] === r && s.rc[1] === c);
      if (startMatch) fill = COLOR_META[startMatch.color].hex;
      const pathIdx = PATH.findIndex(([pr, pc]) => pr === r && pc === c);
      const isStar = pathIdx >= 0 && SAFE_PATH_IDX.has(pathIdx);
      cells.push(
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "absolute",
            style: {
              left: c * cellPx,
              top: r * cellPx,
              width: cellPx,
              height: cellPx,
              background: `linear-gradient(135deg, rgba(255,255,255,0.35) 0%, rgba(255,255,255,0) 45%, rgba(0,0,0,0.18) 100%), ${fill}`,
              border: "1px solid #1f2937",
              boxShadow: "inset 1px 1px 0 rgba(255,255,255,0.5), inset -1px -1px 0 rgba(0,0,0,0.22)"
            },
            children: [
              isStar && /* @__PURE__ */ jsxRuntimeExports.jsx("svg", { viewBox: "0 0 24 24", className: "absolute inset-0 m-auto", width: cellPx * 0.7, height: cellPx * 0.7, children: /* @__PURE__ */ jsxRuntimeExports.jsx(
                "path",
                {
                  d: "M12 2 L14.4 8.6 L21.5 9 L16 13.5 L17.7 20.5 L12 16.5 L6.3 20.5 L8 13.5 L2.5 9 L9.6 8.6 Z",
                  fill: "none",
                  stroke: "#1f2937",
                  strokeWidth: "1.5",
                  strokeLinejoin: "round"
                }
              ) }),
              startMatch && /* @__PURE__ */ jsxRuntimeExports.jsx(
                ArrowGlyph,
                {
                  color: "white",
                  cellPx,
                  dir: startMatch.color === "red" ? "right" : (
                    // green start (left arm) points right toward center
                    startMatch.color === "green" ? "down" : (
                      // yellow start (top arm) points down
                      startMatch.color === "yellow" ? "left" : (
                        // blue start (right arm) points left
                        "up"
                      )
                    )
                  )
                }
              )
            ]
          },
          `${r}-${c}`
        )
      );
    }
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: cells });
}
function ArrowGlyph({ dir, cellPx, color }) {
  const rot = { up: 0, right: 90, down: 180, left: 270 }[dir];
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "svg",
    {
      viewBox: "0 0 24 24",
      className: "absolute inset-0 m-auto",
      width: cellPx * 0.6,
      height: cellPx * 0.6,
      style: { transform: `rotate(${rot}deg)` },
      children: /* @__PURE__ */ jsxRuntimeExports.jsx("path", { d: "M12 4 L20 14 L14 14 L14 20 L10 20 L10 14 L4 14 Z", fill: color, stroke: "#1f2937", strokeWidth: "1" })
    }
  );
}
function CenterTriangles({ cellPx }) {
  const x = 6 * cellPx, size = 3 * cellPx;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("svg", { className: "absolute", style: { left: x, top: x, width: size, height: size }, viewBox: "0 0 100 100", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("polygon", { points: "0,0 100,0 50,50", fill: COLOR_META.green.hex, stroke: "#1f2937", strokeWidth: "0.5" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("polygon", { points: "100,0 100,100 50,50", fill: COLOR_META.yellow.hex, stroke: "#1f2937", strokeWidth: "0.5" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("polygon", { points: "100,100 0,100 50,50", fill: COLOR_META.blue.hex, stroke: "#1f2937", strokeWidth: "0.5" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("polygon", { points: "0,100 0,0 50,50", fill: COLOR_META.red.hex, stroke: "#1f2937", strokeWidth: "0.5" })
  ] });
}
function DiceFace({ value }) {
  const dots = { 0: [], 1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8] };
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid h-full w-full grid-cols-3 grid-rows-3 gap-1 p-3", children: Array.from({ length: 9 }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-center", children: dots[value]?.includes(i) && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-2.5 w-2.5 rounded-full bg-slate-800" }) }, i)) });
}
function GamePage() {
  const {
    id
  } = Route$3.useParams();
  const {
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const {
    t
  } = useT();
  const [confirmQuit, setConfirmQuit] = reactExports.useState(false);
  const [soundOn, setSoundOn] = reactExports.useState(!isMuted());
  const [now, setNowTick] = reactExports.useState(serverNow());
  const [loadError, setLoadError] = reactExports.useState(false);
  const [loadRetried, setLoadRetried] = reactExports.useState(0);
  const {
    game,
    parts,
    loading,
    reload
  } = useFastRealtime({
    gameTable: "ludo_games",
    participantTable: "ludo_participants",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile
  });
  reactExports.useEffect(() => {
    if (loading && !game) setLoadError(false);
    else if (!loading && !game) setLoadError(true);
    else setLoadError(false);
  }, [loading, game]);
  const {
    isConnected,
    isReconnecting,
    retry
  } = useGameConnection({
    onReconnect: reload
  });
  reactExports.useEffect(() => {
    if (profile?.id && (!game || loadError)) {
      reload();
    }
  }, [profile?.id]);
  reactExports.useEffect(() => {
    if (!profile?.id) return;
    const beat = () => {
      supabase.rpc("ludo_heartbeat", {
        _game_id: id
      });
    };
    beat();
    const timer = setInterval(beat, 15e3);
    return () => clearInterval(timer);
  }, [id, profile?.id]);
  reactExports.useEffect(() => {
    const timer = setInterval(() => setNowTick(serverNow()), 1e3);
    return () => clearInterval(timer);
  }, []);
  reactExports.useEffect(() => {
    if (!profile?.id) return;
    const beat = () => {
      supabase.rpc("ludo_heartbeat", {
        _game_id: id
      });
    };
    beat();
    const timer = setInterval(beat, 15e3);
    return () => clearInterval(timer);
  }, [id, profile?.id]);
  reactExports.useEffect(() => {
    const timer = setInterval(() => setNowTick(serverNow()), 1e3);
    return () => clearInterval(timer);
  }, []);
  const myPart = parts.find((p) => p.user_id === profile?.id);
  const isParticipant = !!myPart;
  const isSpectator = !isParticipant;
  const quit = async () => {
    const {
      error
    } = await supabase.rpc("ludo_quit", {
      _game_id: id
    });
    if (error) {
      toast.error(error.message);
      return;
    }
    toast.success(t("left_game"));
    refreshProfile();
    navigate({
      to: "/jeux"
    });
  };
  const addBot = async () => {
    if (isAdmin) {
      const name = prompt("Nom du bot:", "BotMax");
      if (!name) return;
      const intel = Number(prompt("Intelligence (0-100):", "70")) || 70;
      const bias = Number(prompt("Biais de gain (0-100, 0 = équitable):", "0")) || 0;
      const {
        error: error2
      } = await supabase.rpc("admin_add_bot", {
        _game_id: id,
        _bot_name: name,
        _intelligence: intel,
        _win_bias: bias
      });
      if (error2) toast.error(error2.message);
      else toast.success(t("bot_added"));
      return;
    }
    const {
      error
    } = await supabase.rpc("player_add_bot", {
      _game_id: id,
      _bot_name: "Bot"
    });
    if (error) toast.error(error.message);
    else toast.success(t("bot_added"));
  };
  if (!game) {
    if (loadError) {
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "p-8 text-center space-y-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-muted-foreground", children: t("loading") }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          setLoadError(false);
          setLoadRetried((r) => r + 1);
        }, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold", children: "Réessayer" })
      ] });
    }
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-muted-foreground", children: t("loading") });
  }
  if (game.status === "open") {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameWaitingRoom, { isTournament: !!game.tournament_match_id, slug: "ludo", gameLabel: `Ludo · ${game.max_players} joueurs · ${game.match_type === "groupe" ? "2v2 Groupe" : "Solo"}`, parts: (() => {
        const bots = parts.filter((p) => p.is_bot).sort((a, b) => a.slot - b.slot);
        const botIndex = /* @__PURE__ */ new Map();
        bots.forEach((b, i) => botIndex.set(b.id, i + 1));
        return parts.map((p) => {
          const idx = botIndex.get(p.id);
          return {
            user_id: p.user_id,
            display_name: p.is_bot ? `Joueur ${idx}` : p.display_name,
            slot: p.slot,
            team: p.team,
            ready: p.is_bot ? true : p.ready,
            avatar_url: p.is_bot ? `https://api.dicebear.com/7.x/adventurer/svg?seed=joueur${idx || 1}` : void 0
          };
        });
      })(), maxPlayers: game.max_players, stake: Number(game.stake), pot: Number(game.pot), roomCode: game.is_private ? game.room_code : null, shareSlug: "ludo", meUserId: profile?.id, isParticipant, createdAt: game.created_at, onQuit: quit, onToggleReady: async (ready) => {
        const {
          error
        } = await supabase.rpc("ludo_set_ready", {
          _game_id: id,
          _ready: ready
        });
        if (error) {
          void toast.error(error.message);
        }
      }, matchType: game.match_type === "groupe" ? "groupe" : "solo", onJoinTeam: async (team) => {
        const {
          error
        } = await supabase.rpc("ludo_join_team", {
          _game_id: id,
          _team: team
        });
        if (error) toast.error(error.message);
        else toast.success(team === 1 ? "Groupe 1 rejoint !" : "Groupe 2 rejoint !");
      } }),
      !game.is_private && (isAdmin || Number(game.stake) === 0 && isParticipant) && parts.length < game.max_players && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: addBot, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " ",
        t("add_bot")
      ] })
    ] });
  }
  if (game.status === "cancelled") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(GameStateMessage, { state: "cancelled", gameLabel: "Ludo", slug: "ludo" });
  }
  if (game.status === "finished") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "max-w-3xl mx-auto px-4 py-10", children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "ludo", meUserId: profile?.id, winnerId: game.winner_id, participants: parts, stake: Number(game.stake), pot: Number(game.pot), commissionPct: Number(game.commission_pct) || 10, onReplay: async () => {
      const stake = Number(game.stake) || 0;
      const maxP = Number(game.max_players) || 2;
      const mode = game.mode === "fast" ? "fast" : "classic";
      const fn = game.is_private ? "create_private_game" : "create_public_game";
      const args = {
        _max_players: maxP,
        _stake: stake,
        _mode: mode
      };
      const {
        data,
        error
      } = await supabase.rpc(fn, args);
      if (error) {
        (await import("../_libs/sonner.mjs")).toast.error(error.message);
        return;
      }
      navigate({
        to: "/jeux/ludo/$id",
        params: {
          id: data
        }
      });
    } }) });
  }
  const state = game.state || {
    pawns: {},
    turn_slot: 0,
    dice: null,
    must_move: false,
    turn_started_at: (/* @__PURE__ */ new Date()).toISOString()
  };
  const payout = Math.round(Number(game.pot) * (100 - Number(game.commission_pct)) / 100);
  const disconnectUntil = game.disconnect_until || {};
  const pausedSlots = Object.entries(disconnectUntil).map(([slot, ts]) => {
    const until = new Date(ts).getTime();
    const rem = Math.max(0, Math.floor((until - now) / 1e3));
    const p = parts.find((pp) => pp.slot === Number(slot));
    return {
      slot: Number(slot),
      remaining: rem,
      name: p?.display_name || `Slot ${slot}`
    };
  }).filter((p) => p.remaining > 0);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-5xl mx-auto px-3 py-1 h-full overflow-hidden overscroll-none", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyBanner, { stake: Number(game?.stake) || 0 }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "sr-only", children: "Partie de Ludo en cours" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-baseline gap-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] uppercase text-muted-foreground tracking-wider", children: t("prize_winner") }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-extrabold truncate", children: [
          payout.toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      isSpectator ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-3 h-3" }),
        " ",
        t("spectator_lbl")
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
        parts.some((p) => p.is_bot) && game.status === "playing" && !game.paused && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
          const {
            error
          } = await supabase.rpc("game_request_pause", {
            _slug: "ludo",
            _game_id: id
          });
          if (error) toast.error(error.message);
          else toast.success("Partie en pause");
        }, className: "px-2 py-0.5 rounded-full bg-amber-500 text-white text-[10px] font-semibold flex items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-2.5 h-2.5" }),
          " Pause"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          const m = !soundOn;
          setSoundOn(m);
          setMuted(m);
        }, className: "w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition", children: soundOn ? /* @__PURE__ */ jsxRuntimeExports.jsx(Volume2, { className: "w-3 h-3" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(VolumeX, { className: "w-3 h-3" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setConfirmQuit(true), className: "px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-2.5 h-2.5" }),
          " ",
          t("quit_refunded")
        ] })
      ] })
    ] }),
    pausedSlots.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl bg-amber-50 border border-amber-200 p-3 mb-3 text-sm text-amber-900", children: pausedSlots.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      "⏸ ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: p.name }),
      " ",
      t("is_paused_msg"),
      " ",
      Math.floor(p.remaining / 60),
      ":",
      String(p.remaining % 60).padStart(2, "0")
    ] }, p.slot)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(RealtimeLudoBoard, { gameId: id, state, participants: parts, myUserId: profile?.id || null, isSpectator, status: game.status, isAdmin, paused: game?.paused ?? false, pauseDeadline: game?.pause_deadline ?? null, afkWarning: game?.afk_warning ?? null, afkPauseFor: game?.afk_pause_for ?? null, matchType: game.match_type }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "ludo", participants: parts }),
    confirmQuit && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4", onClick: () => setConfirmQuit(false), children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-3xl p-6 max-w-md w-full space-y-4", onClick: (e) => e.stopPropagation(), children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-xl font-extrabold", children: t("quit_game_title_key") }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-sm text-muted-foreground", children: [
        t("quit_game_desc_key"),
        " ",
        /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { children: [
          Number(game.stake).toLocaleString("fr-FR"),
          " Ar"
        ] }),
        "."
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 justify-end", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setConfirmQuit(false), className: "px-4 py-2 rounded-full bg-secondary font-semibold", children: t("cancel") }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: quit, className: "px-4 py-2 rounded-full bg-destructive text-white font-semibold", children: t("confirm_quit") })
      ] })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameReconnectOverlay, { isConnected, isReconnecting, onRetry: retry })
  ] });
}
export {
  GamePage as component
};
