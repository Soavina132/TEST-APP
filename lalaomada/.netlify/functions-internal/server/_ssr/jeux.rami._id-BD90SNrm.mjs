import { r as reactExports, R as React__default, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { R as RANKS, a as SUITS, S as SUIT_COLORS } from "./game-constants-DbAkVx_H.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { u as useGameConnection, G as GameStateMessage, a as GameWaitingRoom, c as GameEndScreen, d as GameReconnectOverlay, b as GamePauseControl } from "./GameReconnectOverlay-DB4s6cH2.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { I as Route, u as useAuth, b as useConfirm } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { G as GameSocialFab } from "./GameSocialFab-DlZx4gfi.mjs";
import { u as useGameConfig } from "./use-game-config-DU32XRGm.mjs";
import { G as GameLoader } from "./GameLoader-DEMrZT6Q.mjs";
import { a as sfx, s as setMuted, i as isMuted } from "./game-sounds-246YZn8C.mjs";
import "../_libs/canvas-confetti.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { a2 as Plus, ag as Pause, b1 as Palette, aU as Volume2, aV as VolumeX, Q as LogOut, a7 as Eye, aw as Timer, b2 as Lightbulb, a$ as ChevronLeft, b as ChevronRight, ao as Trash2, a1 as Check, X } from "../_libs/lucide-react.mjs";
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
import "./game-ui-state-y34n01Z_.mjs";
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
import "./ChatRoom-DC72H67I.mjs";
import "./LinkPreview-BF8xLSR1.mjs";
import "./share-game-wrpRJpl9.mjs";
import "./image-compress-U7tauI3l.mjs";
function useLongPressDrag({ delay = 380, onDrop }) {
  const [drag, setDrag] = reactExports.useState(null);
  const dragRef = reactExports.useRef(null);
  dragRef.current = drag;
  const timerRef = reactExports.useRef(null);
  const startRef = reactExports.useRef(null);
  const clearTimer = () => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  };
  const findTarget = (x, y, sourceId) => {
    const stack = document.elementsFromPoint(x, y);
    for (const el of stack) {
      const drop = el.closest?.("[data-drop-target]");
      if (!drop) continue;
      const id = drop.getAttribute("data-drop-target");
      if (!id || id === sourceId) continue;
      const r = drop.getBoundingClientRect();
      const side = x - r.left < r.width / 2 ? "before" : "after";
      return { id, side };
    }
    return { id: null, side: null };
  };
  reactExports.useEffect(() => {
    if (!drag) return;
    let raf = 0;
    let pending = null;
    const flush = () => {
      raf = 0;
      if (!pending) return;
      const { x, y } = pending;
      pending = null;
      const src = dragRef.current?.sourceId ?? "";
      const { id, side } = findTarget(x, y, src);
      setDrag((d) => d ? { ...d, x, y, targetId: id, targetSide: side } : d);
    };
    const move = (e) => {
      pending = { x: e.clientX, y: e.clientY };
      if (!raf) raf = requestAnimationFrame(flush);
    };
    const end = () => {
      const d = dragRef.current;
      if (d && d.targetId && d.targetSide && d.targetId !== d.sourceId) {
        onDrop(d.sourceId, d.targetId, d.targetSide);
      }
      setDrag(null);
    };
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerup", end, { passive: true });
    window.addEventListener("pointercancel", end, { passive: true });
    return () => {
      if (raf) cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
    };
  }, [drag !== null, onDrop]);
  const getSourceProps = reactExports.useCallback(
    (sourceId) => ({
      onPointerDown: (e) => {
        if (e.pointerType === "mouse" && e.button !== 0) return;
        const el = e.currentTarget;
        startRef.current = { x: e.clientX, y: e.clientY, el };
        clearTimer();
        const sx = e.clientX;
        const sy = e.clientY;
        try {
          el.setPointerCapture?.(e.pointerId);
        } catch {
        }
        timerRef.current = setTimeout(() => {
          if (typeof navigator !== "undefined" && "vibrate" in navigator) {
            try {
              navigator.vibrate?.(12);
            } catch {
            }
          }
          const r = el.getBoundingClientRect();
          setDrag({
            sourceId,
            x: sx,
            y: sy,
            ox: sx - r.left,
            oy: sy - r.top,
            w: r.width,
            h: r.height,
            targetId: null,
            targetSide: null
          });
        }, delay);
      },
      onPointerMove: (e) => {
        const s = startRef.current;
        if (s && !dragRef.current) {
          const dx = e.clientX - s.x;
          const dy = e.clientY - s.y;
          if (Math.hypot(dx, dy) > 8) clearTimer();
        }
      },
      onPointerUp: () => {
        clearTimer();
        startRef.current = null;
      },
      onPointerCancel: () => {
        clearTimer();
        startRef.current = null;
      },
      "data-drag-source": sourceId
    }),
    [delay]
  );
  const isDraggingId = (id) => drag?.sourceId === id;
  const isTargetId = (id) => {
    if (drag?.targetId === id && drag?.targetSide) return drag.targetSide;
    return false;
  };
  return { drag, getSourceProps, isDraggingId, isTargetId };
}
const SUIT_CHARS = ["♠", "♥", "♦", "♣"];
const RANK_CHARS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
const SUIT_HEX = ["#1a1a2e", "#c41e3a", "#c41e3a", "#1a1a2e"];
const PIP_CSS = [
  [[50, 50, false]],
  // A
  [[50, 22, false], [50, 78, true]],
  // 2
  [[50, 22, false], [50, 50, false], [50, 78, true]],
  // 3
  [[33, 22, false], [67, 22, false], [33, 78, true], [67, 78, true]],
  // 4
  [[33, 22, false], [67, 22, false], [50, 50, false], [33, 78, true], [67, 78, true]],
  // 5
  [[33, 22, false], [67, 22, false], [33, 50, false], [67, 50, false], [33, 78, true], [67, 78, true]],
  // 6
  [[33, 20, false], [67, 20, false], [50, 36, false], [33, 50, false], [67, 50, false], [33, 80, true], [67, 80, true]],
  // 7
  [[33, 20, false], [67, 20, false], [50, 34, false], [33, 46, false], [67, 46, false], [50, 68, true], [33, 80, true], [67, 80, true]],
  // 8
  [[33, 18, false], [67, 18, false], [33, 35, false], [67, 35, false], [50, 50, false], [33, 66, true], [67, 66, true], [33, 82, true], [67, 82, true]],
  // 9
  [[33, 16, false], [67, 16, false], [50, 26, false], [33, 36, false], [67, 36, false], [33, 64, true], [67, 64, true], [50, 74, true], [33, 84, true], [67, 84, true]]
  // 10
];
const CardBackCSS = React__default.memo(function CardBackCSS2() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full rounded-md flex items-center justify-center", style: {
    background: "linear-gradient(135deg, #5a152f 0%, #7c1e3f 50%, #3d0f20 100%)",
    border: "1.5px solid rgba(201,162,39,0.3)",
    borderRadius: "5px"
  }, children: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
    fontSize: "55%",
    color: "rgba(201,162,39,0.4)",
    fontWeight: "bold",
    lineHeight: 1
  }, children: "★" }) });
});
const Card = React__default.memo(function Card2({
  c,
  selected,
  onClick,
  size = "md",
  faceDown,
  onRemove,
  highlight,
  dealDelay,
  styleOverride
}) {
  const sizeClass = styleOverride ? "" : size === "sm" ? "w-9 h-14" : size === "lg" ? "w-16 h-24" : size === "xl" ? "w-20 h-28" : "w-12 h-[72px]";
  const cardFontSize = styleOverride?.width ? typeof styleOverride.width === "number" ? styleOverride.width : parseInt(String(styleOverride.width).replace(/px$/, ""), 10) || 48 : size === "sm" ? 36 : size === "lg" ? 64 : size === "xl" ? 80 : 48;
  const dealStyle = dealDelay !== void 0 ? {
    animationDelay: `${dealDelay}ms`,
    opacity: 0,
    animation: `dealCard 0.25s ease-out ${dealDelay}ms forwards`
  } : {};
  if (faceDown || c === void 0) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `${sizeClass} rounded-md shrink-0 overflow-hidden`, style: {
      ...dealStyle,
      ...styleOverride,
      border: "1px solid rgba(100,80,40,0.25)",
      fontSize: `${cardFontSize}px`
    }, children: /* @__PURE__ */ jsxRuntimeExports.jsx(CardBackCSS, {}) });
  }
  const base = c % 56;
  const isJoker = base >= 52;
  const suit = isJoker ? 0 : Math.floor(base / 13);
  const rank = isJoker ? 0 : base % 13;
  const rankChar = isJoker ? "★" : RANK_CHARS[rank];
  const suitChar = isJoker ? "" : SUIT_CHARS[suit];
  const color = isJoker ? "#7c3aed" : SUIT_HEX[suit];
  const isFace = !isJoker && rank >= 10;
  const isAce = rank === 0 && !isJoker;
  const cardFace = (() => {
    if (isJoker) {
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full flex flex-col items-center justify-center", style: {
        background: "#fefce8",
        borderRadius: "5px",
        border: `1px solid ${color}55`
      }, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
          fontSize: "20%",
          fontWeight: "bold",
          color,
          lineHeight: 1
        }, children: "JOKER" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
          fontSize: "40%",
          color,
          opacity: 0.6,
          lineHeight: 1.5
        }, children: "★" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
          fontSize: "20%",
          fontWeight: "bold",
          color,
          lineHeight: 1
        }, children: "JOKER" })
      ] });
    }
    if (isFace) {
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full flex flex-col items-center justify-center relative", style: {
        background: "#fefefe",
        borderRadius: "5px",
        border: "0.5px solid #c8c8c8"
      }, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-[3%] left-[6%]", style: {
          fontSize: "16%",
          fontWeight: 800,
          color,
          lineHeight: 1,
          fontFamily: "Georgia, serif"
        }, children: rankChar }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-[16%] left-[6%]", style: {
          fontSize: "12%",
          color,
          lineHeight: 1
        }, children: suitChar }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-[3%] right-[6%]", style: {
          fontSize: "16%",
          fontWeight: 800,
          color,
          lineHeight: 1,
          fontFamily: "Georgia, serif",
          transform: "rotate(180deg)"
        }, children: rankChar }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-[16%] right-[6%]", style: {
          fontSize: "12%",
          color,
          lineHeight: 1,
          transform: "rotate(180deg)"
        }, children: suitChar }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
          fontSize: "40%",
          fontWeight: 800,
          color,
          opacity: 0.85,
          lineHeight: 1,
          fontFamily: "Georgia, serif"
        }, children: rankChar }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { style: {
          fontSize: "22%",
          color,
          opacity: 0.7,
          lineHeight: 1.2
        }, children: suitChar })
      ] });
    }
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full relative", style: {
      background: "#fefefe",
      borderRadius: "5px",
      border: "0.5px solid #c8c8c8"
    }, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-[3%] left-[6%]", style: {
        fontSize: "16%",
        fontWeight: 800,
        color,
        lineHeight: 1,
        fontFamily: "Georgia, serif"
      }, children: rankChar }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-[16%] left-[6%]", style: {
        fontSize: "12%",
        color,
        lineHeight: 1
      }, children: suitChar }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-[3%] right-[6%]", style: {
        fontSize: "16%",
        fontWeight: 800,
        color,
        lineHeight: 1,
        fontFamily: "Georgia, serif",
        transform: "rotate(180deg)"
      }, children: rankChar }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-[16%] right-[6%]", style: {
        fontSize: "12%",
        color,
        lineHeight: 1,
        transform: "rotate(180deg)"
      }, children: suitChar }),
      isAce ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-1/2 left-1/2 -translate-x-1/2 -translate-y-1/2", style: {
        fontSize: "55%",
        color,
        lineHeight: 1
      }, children: suitChar }) : PIP_CSS[rank].map(([px, py, flip], i) => /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute", style: {
        left: `${px}%`,
        top: `${py}%`,
        transform: `translate(-50%,-50%) ${flip ? "rotate(180deg)" : ""}`,
        fontSize: "8%",
        color,
        lineHeight: 1,
        fontWeight: 700
      }, children: suitChar }, i))
    ] });
  })();
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", style: dealStyle, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick, disabled: !onClick, style: {
      ...styleOverride,
      fontSize: `${cardFontSize}px`
    }, className: `${sizeClass} block transition-transform duration-100 ease-out contain-strict
          ${selected ? "-translate-y-3" : ""}
          ${highlight === "layoff" ? "ring-2 ring-emerald-400 ring-offset-1 scale-105" : ""}
          ${onClick ? "cursor-pointer active:scale-95" : "cursor-default"}`, children: cardFace }),
    selected && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 rounded-md ring-2 ring-emerald-400 pointer-events-none" }),
    onRemove && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onRemove, className: "absolute -top-2 -right-2 w-5 h-5 rounded-full bg-destructive text-white flex items-center justify-center z-10 shadow", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" }) })
  ] });
});
const CARD_BASE = (c) => c % 56;
const CARD_POINTS = (c) => {
  const b = CARD_BASE(c);
  if (b >= 52) return 15;
  const r = b % 13;
  if (r === 0) return 11;
  if (r >= 10) return 10;
  return r + 1;
};
function isJokerCard(c, jokerMode, randomJoker) {
  const base = CARD_BASE(c);
  if ((base === 52 || base === 53) && (jokerMode === "classique" || jokerMode === "double")) return true;
  if ((jokerMode === "aleatoire" || jokerMode === "double") && randomJoker !== null) {
    const rjBase = CARD_BASE(randomJoker);
    if (base < 52 && rjBase < 52) {
      const cardRank = base % 13;
      const jokerRank = rjBase % 13;
      const cardSuit = Math.floor(base / 13);
      const jokerSuit = Math.floor(rjBase / 13);
      if (cardRank === jokerRank && cardSuit !== jokerSuit) {
        const cardColor = cardSuit === 0 || cardSuit === 3 ? 0 : 1;
        const jokerColor = jokerSuit === 0 || jokerSuit === 3 ? 0 : 1;
        if (cardColor !== jokerColor) return true;
      }
    }
  }
  return false;
}
function computeRunGaps(ranks) {
  const calcGaps = (rs) => {
    const sorted = [...rs].sort((a, b) => a - b);
    let gaps = 0;
    for (let i = 1; i < sorted.length; i++) {
      const diff = sorted[i] - sorted[i - 1];
      if (diff === 0) return null;
      gaps += diff - 1;
    }
    return gaps;
  };
  const normal = calcGaps(ranks);
  let best = normal === null ? Infinity : normal;
  if (ranks.includes(0)) {
    const aceHigh = ranks.map((r) => r === 0 ? 13 : r);
    const aceHighGaps = calcGaps(aceHigh);
    if (aceHighGaps !== null && aceHighGaps < best) best = aceHighGaps;
  }
  return best;
}
function validateMeld(cards, jokerMode, randomJoker) {
  if (cards.length < 3) return "unknown";
  const isJoker = (c) => isJokerCard(c, jokerMode, randomJoker);
  const jokerCount = cards.filter(isJoker).length;
  const real = cards.filter((c) => !isJoker(c));
  const checkSet = () => {
    if (cards.length > 4) return false;
    if (real.length < 2) return false;
    const rank = CARD_BASE(real[0]) % 13;
    if (!real.every((c) => CARD_BASE(c) % 13 === rank)) return false;
    const suits = real.map((c) => Math.floor(CARD_BASE(c) / 13));
    return new Set(suits).size === suits.length;
  };
  const checkSequence = () => {
    if (real.length < 2) return false;
    const suit = Math.floor(CARD_BASE(real[0]) / 13);
    if (!real.every((c) => Math.floor(CARD_BASE(c) / 13) === suit)) return false;
    const ranks = real.map((c) => CARD_BASE(c) % 13);
    if (new Set(ranks).size !== ranks.length) return false;
    return computeRunGaps(ranks) <= jokerCount;
  };
  if (checkSet() || checkSequence()) return "valid";
  if (cards.length === 7 && isSevenCombo(cards, jokerMode, randomJoker)) return "valid";
  return "invalid";
}
function meldKind(cards, jokerMode, randomJoker) {
  if (cards.length < 3) return null;
  if (cards.length === 7 && isSevenCombo(cards, jokerMode, randomJoker)) return "seven";
  if (validateMeld(cards, jokerMode, randomJoker) !== "valid") return null;
  const isJoker = (c) => isJokerCard(c, jokerMode, randomJoker);
  const real = cards.filter((c) => !isJoker(c));
  const sameRank = real.length > 0 && real.every((c) => CARD_BASE(c) % 13 === CARD_BASE(real[0]) % 13);
  if (sameRank && cards.length <= 4) return cards.length === 4 ? "carre" : "trio";
  return "run";
}
const MELD_LABEL = {
  carre: "Carré",
  trio: "Trio",
  run: "Escalier",
  seven: "7 Cartes (Miverim-bola)"
};
function isSevenCombo(cards, jokerMode, randomJoker) {
  if (cards.length !== 7) return false;
  const baseValid = (sub) => {
    if (sub.length < 3) return false;
    const isJoker = (c) => isJokerCard(c, jokerMode, randomJoker);
    const jokerCount = sub.filter(isJoker).length;
    const real = sub.filter((c) => !isJoker(c));
    if (real.length < 2) return false;
    const rank = CARD_BASE(real[0]) % 13;
    const suits = real.map((c) => Math.floor(CARD_BASE(c) / 13));
    if (sub.length <= 4 && real.every((c) => CARD_BASE(c) % 13 === rank) && new Set(suits).size === suits.length) return true;
    const suit = Math.floor(CARD_BASE(real[0]) / 13);
    if (!real.every((c) => Math.floor(CARD_BASE(c) / 13) === suit)) return false;
    const ranks = real.map((c) => CARD_BASE(c) % 13);
    if (new Set(ranks).size !== ranks.length) return false;
    return computeRunGaps(ranks) <= jokerCount;
  };
  for (let i = 0; i < 4; i++) for (let j = i + 1; j < 5; j++) for (let k = j + 1; k < 6; k++) for (let l = k + 1; l < 7; l++) {
    const four = [cards[i], cards[j], cards[k], cards[l]];
    const three = cards.filter((_, idx) => idx !== i && idx !== j && idx !== k && idx !== l);
    if (baseValid(four) && baseValid(three)) return true;
  }
  return false;
}
function getSelectionFeedback(cards, jokerMode, randomJoker) {
  if (cards.length === 0) return {
    hint: "",
    severity: "info"
  };
  const isJoker = (c) => isJokerCard(c, jokerMode, randomJoker);
  const validity = validateMeld(cards, jokerMode, randomJoker);
  if (validity === "valid") return {
    hint: "✓ Combinaison valide — prête à poser",
    severity: "ok"
  };
  if (validity === "unknown") {
    if (cards.length === 1) return {
      hint: "Sélectionne 2 cartes de plus pour un trio, ou 2+ de même couleur pour un escalier",
      severity: "info"
    };
    const real2 = cards.filter((c) => !isJoker(c));
    if (real2.length >= 2) {
      const sameSuit = real2.every((c) => Math.floor(CARD_BASE(c) / 13) === Math.floor(CARD_BASE(real2[0]) / 13));
      const sameRank = real2.every((c) => CARD_BASE(c) % 13 === CARD_BASE(real2[0]) % 13);
      if (sameSuit) {
        const suitName = ["♠ Pique", "♥ Cœur", "♦ Carreau", "♣ Trèfle"][Math.floor(CARD_BASE(real2[0]) / 13)];
        return {
          hint: `Escalier ${suitName} en cours — ajoute une carte adjacente`,
          severity: "info"
        };
      }
      if (sameRank) {
        const rankName = RANKS[CARD_BASE(real2[0]) % 13];
        const missingCount = 3 - cards.length;
        return {
          hint: `Trio de ${rankName} — ajoute encore ${missingCount} carte${missingCount > 1 ? "s" : ""} de même valeur`,
          severity: "info"
        };
      }
    }
    return {
      hint: "Ajoute une carte pour compléter la combinaison",
      severity: "info"
    };
  }
  const real = cards.filter((c) => !isJoker(c));
  const jokerCount = cards.filter((c) => isJoker(c)).length;
  if (real.length === 0) return {
    hint: "Uniquement des Jokers — ajoute des cartes réelles",
    severity: "error"
  };
  const allSameSuit = real.every((c) => Math.floor(CARD_BASE(c) / 13) === Math.floor(CARD_BASE(real[0]) / 13));
  const allSameRank = real.every((c) => CARD_BASE(c) % 13 === CARD_BASE(real[0]) % 13);
  if (!allSameSuit && !allSameRank) {
    return {
      hint: "Cartes mixtes — sélectionne soit même valeur (trio), soit même couleur (escalier)",
      severity: "error"
    };
  }
  if (allSameRank) {
    const suits = real.map((c) => Math.floor(CARD_BASE(c) / 13));
    if (new Set(suits).size < suits.length) {
      return {
        hint: "Deux cartes de même couleur dans le trio — retire-en une",
        severity: "error"
      };
    }
    if (cards.length > 4) {
      return {
        hint: "Un trio/carré ne peut pas dépasser 4 cartes",
        severity: "error"
      };
    }
  }
  if (allSameSuit) {
    const ranks = real.map((c) => CARD_BASE(c) % 13);
    if (new Set(ranks).size !== ranks.length) {
      return {
        hint: "Deux cartes identiques dans l'escalier",
        severity: "error"
      };
    }
    const gaps = computeRunGaps(ranks);
    if (gaps > jokerCount) {
      return {
        hint: `Trou trop grand dans l'escalier (${gaps} manquant${gaps > 1 ? "s" : ""}, ${jokerCount} Joker${jokerCount > 1 ? "s" : ""} disponible${jokerCount > 1 ? "s" : ""})`,
        severity: "warn"
      };
    }
  }
  return {
    hint: "Combinaison invalide",
    severity: "error"
  };
}
function getLayoffCandidates(melds, selected, jokerMode, randomJoker) {
  const candidates = /* @__PURE__ */ new Set();
  melds.forEach((m, i) => {
    for (const card of selected) {
      if (validateMeld([card, ...m.cards], jokerMode, randomJoker) === "valid" || validateMeld([...m.cards, card], jokerMode, randomJoker) === "valid") {
        candidates.add(i);
        break;
      }
    }
  });
  return candidates;
}
const LB_KEY = "rami_leaderboard_v1";
function useRamiLeaderboard(gameId) {
  const storageKey = LB_KEY + "_" + gameId.slice(0, 8);
  const load = () => {
    try {
      return JSON.parse(localStorage.getItem(storageKey) || "[]");
    } catch {
      return [];
    }
  };
  const [entries, setEntries] = React__default.useState(load);
  const recordRound = React__default.useCallback((parts, hands, winnerId) => {
    setEntries((prev) => {
      const next = [...prev];
      parts.filter((p) => !p.forfeited).forEach((p) => {
        const hand = hands?.[p.user_id] ?? [];
        const pts = hand.reduce((s, c) => s + CARD_POINTS(c), 0);
        const idx = next.findIndex((e) => e.userId === p.user_id);
        if (idx >= 0) {
          next[idx] = {
            ...next[idx],
            wins: next[idx].wins + (p.user_id === winnerId ? 1 : 0),
            totalPts: next[idx].totalPts + pts,
            gamesPlayed: next[idx].gamesPlayed + 1
          };
        } else {
          next.push({
            userId: p.user_id,
            displayName: p.display_name,
            wins: p.user_id === winnerId ? 1 : 0,
            totalPts: pts,
            gamesPlayed: 1
          });
        }
      });
      try {
        localStorage.setItem(storageKey, JSON.stringify(next));
      } catch {
      }
      return next;
    });
  }, [storageKey]);
  const reset = React__default.useCallback(() => {
    localStorage.removeItem(storageKey);
    setEntries([]);
  }, [storageKey]);
  return {
    entries,
    recordRound,
    reset
  };
}
function RamiLeaderboard({
  entries,
  meUserId,
  onReset
}) {
  if (entries.length === 0) return null;
  const sorted = [...entries].sort((a, b) => b.wins !== a.wins ? b.wins - a.wins : a.totalPts - b.totalPts);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border p-4 space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase text-muted-foreground tracking-wide", children: "🏆 Classement de session" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onReset, className: "text-[10px] text-muted-foreground hover:text-destructive transition-colors px-2 py-0.5 rounded-full border border-transparent hover:border-destructive/30", children: "Réinitialiser" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: sorted.map((e, idx) => {
      const isMe = e.userId === meUserId;
      const avgPts = e.gamesPlayed > 0 ? Math.round(e.totalPts / e.gamesPlayed) : 0;
      const medals = ["🥇", "🥈", "🥉"];
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-3 rounded-xl px-3 py-2.5 border transition-all ${isMe ? "bg-primary/8 border-primary/20 ring-1 ring-primary/20" : idx === 0 ? "bg-amber-500/8 border-amber-500/20" : "bg-white/4 border-white/6"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-8 h-8 rounded-full flex items-center justify-center text-base shrink-0 font-bold ${idx === 0 ? "bg-amber-500/20" : "bg-white/8"}`, children: medals[idx] ?? idx + 1 }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm truncate", children: [
            e.displayName,
            isMe ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary/60 text-[10px] font-normal ml-1", children: "(vous)" }) : ""
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground/60", children: [
            e.gamesPlayed,
            " partie",
            e.gamesPlayed > 1 ? "s" : "",
            " · moy. ",
            avgPts,
            " pts"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right shrink-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm text-emerald-500", children: [
            e.wins,
            "V"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground/50 font-mono", children: [
            e.totalPts,
            " pts"
          ] })
        ] })
      ] }, e.userId);
    }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground border-t border-border pt-1", children: "Classement par victoires, puis total de points (moins = mieux) — sauvegardé dans ce navigateur" })
  ] });
}
function RamiScoreSummary({
  parts,
  hands,
  winnerId,
  pot,
  commissionPct,
  melds
}) {
  const commission = commissionPct ?? 10;
  const netPot = pot ? Math.round(pot * (1 - commission / 100)) : 0;
  const activeParts = parts.filter((p) => !p.forfeited);
  const stakePerPlayer = pot && activeParts.length > 0 ? Math.round(pot / activeParts.length) : 0;
  const rows = activeParts.map((p) => {
    const hand = hands?.[p.user_id] ?? [];
    const pts = hand.reduce((s, c) => s + CARD_POINTS(c), 0);
    const isWinner = p.user_id === winnerId;
    const arDelta = isWinner ? netPot - stakePerPlayer : -stakePerPlayer;
    return {
      ...p,
      hand,
      pts,
      arDelta
    };
  }).sort((a, b) => a.pts - b.pts);
  const minPts = rows[0]?.pts ?? 0;
  const cardLabel = (c) => {
    if (CARD_BASE(c) >= 52) return {
      rank: "★",
      suit: "",
      color: "#7c3aed"
    };
    const s = Math.floor(CARD_BASE(c) / 13);
    const r = CARD_BASE(c) % 13;
    return {
      rank: RANKS[r],
      suit: SUITS[s],
      color: SUIT_COLORS[s]
    };
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl border border-white/8 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 py-3 bg-gradient-to-r from-primary/10 via-primary/5 to-transparent border-b border-white/6 flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-base", children: "📊" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Bilan de la manche" }),
      pot !== void 0 && pot > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "ml-auto text-xs font-semibold text-emerald-500 bg-emerald-500/10 px-2 py-0.5 rounded-full border border-emerald-500/20", children: [
        "Pot ",
        pot.toLocaleString("fr-FR"),
        " Ar"
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-3 space-y-2 bg-card", children: rows.map((p, idx) => {
      const isWinner = p.user_id === winnerId;
      const isLowest = p.pts === minPts;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-xl p-3 space-y-2 border transition-all ${isWinner ? "bg-emerald-500/8 border-emerald-500/25 shadow-md shadow-emerald-500/10" : idx === rows.length - 1 ? "bg-destructive/5 border-destructive/15" : "bg-white/4 border-white/6"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${isWinner ? "bg-emerald-500/20 text-emerald-400 ring-1 ring-emerald-500/30" : "bg-white/8 text-muted-foreground ring-1 ring-white/10"}`, children: [
              isWinner ? "🏆" : idx === 0 ? "🥈" : "",
              !isWinner && idx > 0 ? (p.display_name || "?").slice(0, 2).toUpperCase() : ""
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: p.display_name })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-base font-extrabold ${isWinner ? "text-emerald-400" : isLowest ? "text-primary" : "text-destructive/80"}`, children: [
              p.pts,
              " pts"
            ] }),
            pot !== void 0 && pot > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-xs font-bold px-2 py-0.5 rounded-full ${p.arDelta > 0 ? "bg-emerald-500/15 text-emerald-400 border border-emerald-500/20" : "bg-destructive/10 text-destructive border border-destructive/15"}`, children: [
              p.arDelta > 0 ? "+" : "",
              p.arDelta.toLocaleString("fr-FR"),
              " Ar"
            ] })
          ] })
        ] }),
        p.hand.length > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 flex-wrap", children: p.hand.map((c, ci) => {
          const lbl = cardLabel(c);
          const pts = CARD_POINTS(c);
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative w-9 h-14 rounded-md bg-white border border-gray-300 shadow font-bold flex flex-col p-0.5 text-[10px]", style: {
            color: lbl.color
          }, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "leading-none", children: [
              lbl.rank,
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: lbl.suit })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute bottom-0.5 right-0.5 text-[9px] bg-black/10 rounded px-0.5 font-mono", children: pts })
          ] }, ci);
        }) }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-emerald-600 dark:text-emerald-400 font-semibold", children: "Main vide — a posé toutes ses cartes !" }),
        (melds || []).filter((m) => m.player === p.user_id).length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1.5 pt-1.5 border-t border-white/6", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold text-muted-foreground mb-1", children: "Combinaisons posées :" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 flex-wrap", children: (melds || []).filter((m) => m.player === p.user_id).map((m, mi) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-0.5 px-1 py-0.5 rounded bg-primary/10 border border-primary/20", children: m.cards.map((c, ci) => {
            const lbl = cardLabel(c);
            return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] font-bold", style: {
              color: lbl.color
            }, children: [
              lbl.rank,
              lbl.suit
            ] }, ci);
          }) }, mi)) })
        ] })
      ] }, p.id);
    }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-3 pt-3 border-t border-white/6 space-y-1", children: [
      pot !== void 0 && pot > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground/60 flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
          "Pot ",
          pot.toLocaleString("fr-FR"),
          " Ar"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "opacity-30", children: "·" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
          "Commission ",
          commission,
          "% = ",
          Math.round(pot * commission / 100).toLocaleString("fr-FR"),
          " Ar"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "opacity-30", children: "·" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-emerald-500 font-semibold", children: [
          "Net ",
          netPot.toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground/40", children: "A=11 · J/Q/K=10 · Joker=15 · autres=valeur" })
    ] })
  ] });
}
const DEAL_STYLE_ID = "rami-deal-keyframes";
function ensureDealKeyframes() {
  if (typeof document === "undefined" || document.getElementById(DEAL_STYLE_ID)) return;
  const style = document.createElement("style");
  style.id = DEAL_STYLE_ID;
  style.textContent = `
    @keyframes dealCard {
      0%   { opacity: 0; transform: translateY(-60px) translateX(20px) scale(0.5) rotate(-12deg); }
      60%  { opacity: 1; transform: translateY(5px) translateX(0) scale(1.05) rotate(2deg); }
      100% { opacity: 1; transform: translateY(0) translateX(0) scale(1) rotate(0deg); }
    }
    @keyframes timerUrgent {
      0%, 100% { box-shadow: 0 0 0 0 rgba(220,38,38,0.5); }
      50%       { box-shadow: 0 0 0 6px rgba(220,38,38,0); }
    }
    .timer-urgent { box-shadow: 0 0 0 2px rgba(220,38,38,0.4); }
    @keyframes flyToHand {
      0%   { opacity: 0; transform: translate(-50%, -50%) scale(0.5) rotate(-20deg); }
      15%  { opacity: 1; transform: translate(-50%, -50%) scale(1.15) rotate(0deg); }
      100% { opacity: 0; transform: translate(-50%, 60vh) scale(0.9) rotate(6deg); }
    }
    @keyframes flyToDiscard {
      0%   { opacity: 0; transform: translate(-50%, 40vh) scale(0.9) rotate(4deg); }
      20%  { opacity: 1; transform: translate(-50%, 20vh) scale(1.1) rotate(2deg); }
      100% { opacity: 0; transform: translate(-50%, -30vh) scale(0.7) rotate(-8deg); }
    }
    @keyframes cardLift {
      0%   { transform: translateY(0) rotateX(0) scale(1); }
      100% { transform: translateY(-6px) rotateX(8deg) scale(1.04); }
    }
    @keyframes meldPulse {
      0%, 100% { transform: scale(1); box-shadow: 0 0 0 0 rgba(16,185,129,0); }
      50%      { transform: scale(1.05); box-shadow: 0 0 20px 4px rgba(16,185,129,0.35); }
    }
    .meld-valid-badge { animation: meldPulse 0.8s ease-in-out 2; }
    @keyframes slideInRight {
      from { opacity: 0; transform: translateX(30px); }
      to   { opacity: 1; transform: translateX(0); }
    }
    .action-toast { animation: slideInRight 0.3s ease-out; }
    @keyframes glowPulse {
      0%, 100% { opacity: 0.4; }
      50%      { opacity: 0.8; }
    }
    .playable-glow { box-shadow: 0 0 0 2px rgba(251,191,36,0.5); }
    @keyframes cardFlip3D {
      0%   { transform: rotateY(180deg); }
      100% { transform: rotateY(0deg); }
    }
  `;
  document.head.appendChild(style);
}
function detectCombos(hand, jokerMode, randomJoker) {
  if (hand.length < 3) return [];
  const hints = [];
  const realCards = hand.filter((c) => !isJokerCard(c, jokerMode, randomJoker));
  const jokerCount = hand.length - realCards.length;
  const byRank = {};
  for (const c of realCards) {
    const r = CARD_BASE(c) % 13;
    if (!byRank[r]) byRank[r] = [];
    byRank[r].push(c);
  }
  for (const [rankStr, cards] of Object.entries(byRank)) {
    const r = Number(rankStr);
    const rankName = RANKS[r];
    if (cards.length === 2 && jokerCount > 0) {
      hints.push({
        type: "trio",
        cards,
        label: `Trio de ${rankName} (avec Joker)`
      });
    } else if (cards.length === 3) {
      hints.push({
        type: "trio",
        cards,
        label: `Trio de ${rankName}`
      });
    } else if (cards.length >= 4) {
      hints.push({
        type: "carré",
        cards: cards.slice(0, 4),
        label: `Carré de ${rankName}`
      });
    }
  }
  const bySuit = {};
  for (const c of realCards) {
    const s = Math.floor(CARD_BASE(c) / 13);
    if (!bySuit[s]) bySuit[s] = [];
    bySuit[s].push(c);
  }
  for (const [suitStr, cards] of Object.entries(bySuit)) {
    const s = Number(suitStr);
    const suitName = SUITS[s];
    const ranks = [...new Set(cards.map((c) => CARD_BASE(c) % 13))];
    if (ranks.length < 2 && jokerCount === 0) continue;
    for (let start = 0; start <= 13; start++) {
      for (let len = 3; len <= 5; len++) {
        let needed = 0;
        const have = [];
        for (let i = 0; i < len; i++) {
          const targetRank = (start + i) % 13;
          if (ranks.includes(targetRank)) {
            const card = cards.find((c) => CARD_BASE(c) % 13 === targetRank);
            have.push(card);
          } else {
            needed++;
          }
        }
        if (needed <= jokerCount && needed > 0 && needed < len && have.length >= 2) {
          if (start + len <= 14) {
            hints.push({
              type: "escalier",
              cards: have,
              label: `Escalier ${suitName} (${len} cartes, ${needed} Joker)`
            });
          }
        } else if (needed === 0 && have.length >= 3 && len >= 3) {
          if (start + len <= 14) {
            const isSubset = hints.some((h) => h.type === "escalier" && h.cards.length > have.length && h.cards.every((c) => have.includes(c) || !cards.includes(c)));
            if (!isSubset) {
              hints.push({
                type: "escalier",
                cards: have,
                label: `Escalier ${suitName} (${len} cartes)`
              });
            }
          }
        }
      }
    }
  }
  const seen = /* @__PURE__ */ new Set();
  const unique = hints.filter((h) => {
    const key = h.type + ":" + h.cards.slice().sort((a, b) => a - b).join(",");
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
  return unique.slice(0, 5);
}
function RamiPage() {
  const {
    id
  } = Route.useParams();
  const {
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = reactExports.useState(!isMuted());
  const [game, setGame] = reactExports.useState(null);
  const [parts, setParts] = reactExports.useState([]);
  const [selected, setSelected] = reactExports.useState([]);
  const [staged, setStaged] = reactExports.useState([]);
  const [stagedMoving, setStagedMoving] = reactExports.useState(null);
  const [sortMode, setSortMode] = reactExports.useState("none");
  const [boardTheme, setBoardTheme] = reactExports.useState("green");
  const [customOrder, setCustomOrder] = reactExports.useState(null);
  const [reorderMode, setReorderMode] = reactExports.useState(false);
  const [movingIdx, setMovingIdx] = reactExports.useState(null);
  const [busy, setBusy] = reactExports.useState(false);
  const [optimalPlay, setOptimalPlay] = reactExports.useState(null);
  const [showOptimal, setShowOptimal] = reactExports.useState(false);
  const deckRef = React__default.useRef(null);
  const handRef = React__default.useRef(null);
  const discardRefs = React__default.useRef({});
  const centerOf = (el) => {
    if (!el) return {
      x: window.innerWidth / 2,
      y: window.innerHeight / 2
    };
    const r = el.getBoundingClientRect();
    return {
      x: r.left + r.width / 2,
      y: r.top + r.height / 2
    };
  };
  const [intro, setIntro] = reactExports.useState(null);
  const [newCard, setNewCard] = reactExports.useState(null);
  const prevHandRef = reactExports.useRef([]);
  const {
    entries: lbEntries,
    recordRound,
    reset: resetLb
  } = useRamiLeaderboard(id);
  reactExports.useEffect(() => {
    ensureDealKeyframes();
  }, []);
  const BOARD_THEMES = {
    green: {
      border: "#0b3a1f",
      overlay: "rgba(0,0,0,0.25)",
      tint: "rgba(15,61,32,0.3)",
      feltCenter: "#1a6b3a",
      feltEdge: "#0d4525"
    },
    blue: {
      border: "#0c2742",
      overlay: "rgba(5,20,40,0.3)",
      tint: "rgba(12,39,66,0.35)",
      feltCenter: "#1a3a6b",
      feltEdge: "#0c2742"
    },
    dark: {
      border: "#1a1a1a",
      overlay: "rgba(0,0,0,0.35)",
      tint: "rgba(10,10,10,0.4)",
      feltCenter: "#2a2a2a",
      feltEdge: "#141414"
    }
  };
  const activeTheme = BOARD_THEMES[boardTheme];
  const load = reactExports.useCallback(async () => {
    const {
      data: g
    } = await supabase.from("rami_games").select("id,status,state,current_turn,turn_phase,turn_deadline,winner_id,stake,pot,commission_pct,max_players,is_private,room_code,created_by,created_at,started_at,finished_at,paused,pause_deadline,pause_used,afk_warning,afk_pause_for,afk_pause_name,afk_warnings,spectators_count,game_mode,joker_mode,random_joker,seven_cards,turn_skips,tournament_match_id,winner_name").eq("id", id).maybeSingle();
    setGame(g);
    const {
      data: p
    } = await supabase.from("rami_participants").select("*").eq("game_id", id).order("slot");
    setParts(p || []);
  }, [id, profile?.id]);
  reactExports.useEffect(() => {
    load();
    let debounceTimer = null;
    const debouncedLoad = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => load(), 300);
    };
    let heartbeat = null;
    const ch = supabase.channel("rami-" + id).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "rami_games",
      filter: `id=eq.${id}`
    }, (payload) => {
      if (payload.eventType !== "DELETE" && payload.new) {
        setGame(payload.new);
      } else {
        debouncedLoad();
      }
    }).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "rami_participants",
      filter: `game_id=eq.${id}`
    }, (payload) => {
      if (payload.eventType === "INSERT" && payload.new) {
        setParts((prev) => prev.some((p) => p.id === payload.new.id) ? prev : [...prev, payload.new]);
      } else if (payload.eventType === "UPDATE" && payload.new) {
        setParts((prev) => prev.map((p) => p.id === payload.new.id ? payload.new : p));
      } else if (payload.eventType === "DELETE" && payload.old) {
        setParts((prev) => prev.filter((p) => p.id !== payload.old.id));
      } else {
        debouncedLoad();
      }
    }).subscribe((status) => {
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
      if (debounceTimer) clearTimeout(debounceTimer);
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
  const recordedRef = React__default.useRef(false);
  reactExports.useEffect(() => {
    if (game?.status === "finished" && game.state?.hands && !recordedRef.current) {
      recordedRef.current = true;
      recordRound(parts, game.state.hands, game.winner_id);
    }
  }, [game?.status, game?.state?.hands, game?.winner_id, parts, recordRound]);
  const prevStatusRef2 = reactExports.useRef("");
  reactExports.useEffect(() => {
    if (prevStatusRef2.current !== "playing" && game?.status === "playing") {
      return;
    }
    prevStatusRef2.current = game?.status || "";
  }, [game?.status]);
  const prevTurnSlot = reactExports.useRef(null);
  reactExports.useEffect(() => {
    if (!game || game.status !== "playing") return;
    const cur = game.current_turn;
    if (prevTurnSlot.current !== null && prevTurnSlot.current !== cur) {
      sfx.ramiTurnChange();
    }
    prevTurnSlot.current = cur;
  }, [game?.current_turn, game?.status]);
  const prevStatusRef = reactExports.useRef("");
  reactExports.useEffect(() => {
    if (prevStatusRef.current === "playing" && game?.status === "finished") {
      sfx.ramiWin();
    }
    if (game?.status) prevStatusRef.current = game.status;
  }, [game?.status]);
  const botFxRef = React__default.useRef({
    meldsLen: 0,
    discardKey: "",
    discardTop: void 0,
    init: false
  });
  reactExports.useEffect(() => {
    if (!game) return;
    const currentMelds = game?.state?.melds || [];
    const currentDiscards = game?.state?.discards && typeof game.state.discards === "object" ? game.state.discards : {};
    const lastBy = game?.state?.last_discard_by || "_seed";
    const top = (currentDiscards[lastBy] || [])[(currentDiscards[lastBy] || []).length - 1];
    const prev = botFxRef.current;
    if (!prev.init) {
      botFxRef.current = {
        meldsLen: currentMelds.length,
        discardKey: lastBy,
        discardTop: top,
        init: true
      };
      return;
    }
    if (currentMelds.length > prev.meldsLen) {
      for (let i = prev.meldsLen; i < currentMelds.length; i++) {
        const m = currentMelds[i];
        const p = parts.find((pp) => pp.user_id === m.player);
        if (m.type === "seven") {
          const who = p?.display_name || "Un joueur";
          toast.success(`🎊 ${who} : 7 Cartes — Miverim-bola !`, {
            duration: 3500
          });
        }
        if (p?.is_bot && m.type !== "seven") {
          m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
        }
        if (!p?.is_bot && p && m.type !== "seven") {
          m.type === "run" ? "suite" : m.type === "set" ? "brelan/carré" : "combinaison";
        }
      }
    }
    if ((prev.discardKey !== lastBy || prev.discardTop !== top) && top !== void 0 && lastBy !== "_seed") {
      const p = parts.find((pp) => pp.user_id === lastBy);
      if (p?.is_bot) ;
    }
    botFxRef.current = {
      meldsLen: currentMelds.length,
      discardKey: lastBy,
      discardTop: top,
      init: true
    };
  }, [game?.state?.melds, game?.state?.discards, game?.state?.last_discard_by, parts]);
  const me = parts.find((p) => p.user_id === profile?.id);
  const isPlayer = !!me;
  const [isSpectating, setIsSpectating] = reactExports.useState(false);
  const [spectateData, setSpectateData] = reactExports.useState(null);
  reactExports.useEffect(() => {
    if (!isPlayer && parts.length > 0 && game?.status === "playing" && !isSpectating && profile?.id) {
      void supabase.rpc("rami_spectate", {
        _game_id: id
      }).then(({
        data
      }) => {
        if (data) {
          setIsSpectating(true);
          setSpectateData(data);
          void supabase.rpc("rami_spectate", {
            _game_id: id
          }).then(({
            data: d2
          }) => {
            if (d2) setSpectateData(d2);
          }, () => {
          });
        }
      }, () => {
      });
    }
  }, [isPlayer, game?.status, id, profile?.id, isSpectating]);
  reactExports.useEffect(() => {
    if (isPlayer && isSpectating) {
      setIsSpectating(false);
      void supabase.rpc("rami_spectate_leave", {
        _game_id: id
      }).then(() => {
      }, () => {
      });
    }
  }, [isPlayer, isSpectating, id]);
  reactExports.useEffect(() => {
    if (!isSpectating) return;
    const t = setInterval(async () => {
      const {
        data
      } = await supabase.rpc("rami_spectate", {
        _game_id: id
      });
      if (data) setSpectateData(data);
    }, 5e3);
    return () => clearInterval(t);
  }, [isSpectating, id]);
  reactExports.useEffect(() => {
    return () => {
      if (isSpectating) {
        void supabase.rpc("rami_spectate_leave", {
          _game_id: id
        }).then(() => {
        }, () => {
        });
      }
    };
  }, []);
  const isMyTurn = game?.status === "playing" && me && game.current_turn === me.slot;
  const phase = game?.turn_phase;
  const myHand = reactExports.useMemo(() => {
    const h = game?.state?.hands?.[profile?.id || ""];
    return Array.isArray(h) ? h : [];
  }, [game?.state?.hands, profile?.id]);
  const discards = reactExports.useMemo(() => {
    const d = game?.state?.discards;
    if (d && typeof d === "object") return d;
    const legacy = game?.state?.discard;
    return Array.isArray(legacy) && legacy.length > 0 ? {
      _seed: legacy
    } : {};
  }, [game?.state?.discards, game?.state?.discard]);
  const lastDiscardBy = game?.state?.last_discard_by || "_seed";
  const deckCount = (game?.state?.deck || []).length;
  const melds = game?.state?.melds || [];
  const jokerMode = game?.joker_mode || "classique";
  const gameMode = game?.game_mode || "bordel";
  const randomJoker = game?.random_joker ?? null;
  const refunded = game?.state?.refunded || {};
  !!(profile?.id && refunded[profile.id]);
  reactExports.useMemo(() => {
    const log = game?.state?.action_log;
    if (!Array.isArray(log)) return [];
    return log.slice(-6).reverse();
  }, [game?.state?.action_log]);
  const stagedFlat = reactExports.useMemo(() => staged.flat(), [staged]);
  const handCards = reactExports.useMemo(() => myHand.filter((c) => !stagedFlat.includes(c)), [myHand, stagedFlat]);
  reactExports.useMemo(() => handCards.reduce((s, card) => s + CARD_POINTS(card), 0), [handCards]);
  const orderedHandCards = reactExports.useMemo(() => {
    if (customOrder !== null) {
      const inOrder = customOrder.filter((c) => handCards.includes(c));
      const extras = handCards.filter((c) => !inOrder.includes(c));
      return [...inOrder, ...extras];
    }
    const cards = [...handCards];
    if (sortMode === "suit") {
      cards.sort((a, b) => {
        const sA = CARD_BASE(a) >= 52 ? 4 : Math.floor(CARD_BASE(a) / 13);
        const sB = CARD_BASE(b) >= 52 ? 4 : Math.floor(CARD_BASE(b) / 13);
        return sA !== sB ? sA - sB : CARD_BASE(a) % 13 - CARD_BASE(b) % 13;
      });
    } else if (sortMode === "rank") {
      cards.sort((a, b) => {
        if (CARD_BASE(a) >= 52) return 1;
        if (CARD_BASE(b) >= 52) return -1;
        const rA = CARD_BASE(a) % 13, rB = CARD_BASE(b) % 13;
        return rA !== rB ? rA - rB : Math.floor(CARD_BASE(a) / 13) - Math.floor(CARD_BASE(b) / 13);
      });
    }
    return cards;
  }, [handCards, sortMode, reorderMode, customOrder]);
  const prevHandLenRef = reactExports.useRef(0);
  reactExports.useEffect(() => {
    if (prevHandLenRef.current !== myHand.length) {
      prevHandLenRef.current = myHand.length;
      if (customOrder === null && handCards.length > 0) {
        setCustomOrder([...handCards]);
      } else if (handCards.length === 0) {
        setCustomOrder(null);
      }
    }
  }, [myHand.length, handCards, customOrder]);
  reactExports.useEffect(() => {
    const prev = prevHandRef.current;
    const added = handCards.filter((c) => !prev.includes(c));
    if (added.length === 1 && prev.length > 0 && handCards.length === prev.length + 1) {
      setNewCard(added[0]);
    }
    prevHandRef.current = handCards;
  }, [handCards]);
  reactExports.useEffect(() => {
    if (newCard !== null && (phase !== "play" || selected.length > 0)) {
      setNewCard(null);
    }
  }, [phase, selected.length, newCard]);
  const selectionValidity = reactExports.useMemo(() => validateMeld(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const playableCards = reactExports.useMemo(() => {
    if (!isMyTurn || phase !== "play" || selected.length === 0 || selected.length >= 4) return /* @__PURE__ */ new Set();
    const result = /* @__PURE__ */ new Set();
    for (const c of handCards) {
      if (selected.includes(c)) continue;
      const test = [...selected, c];
      const v = validateMeld(test, jokerMode, randomJoker);
      if (v === "valid") result.add(c);
    }
    return result;
  }, [selected, handCards, isMyTurn, phase, jokerMode, randomJoker]);
  const selectionKind = reactExports.useMemo(() => meldKind(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const availableCombos = reactExports.useMemo(() => {
    if (!isPlayer || game?.status !== "playing") return [];
    return detectCombos(handCards, jokerMode, randomJoker);
  }, [handCards, jokerMode, randomJoker, isPlayer, game?.status]);
  const selectionFeedback = reactExports.useMemo(() => getSelectionFeedback(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const stagedValidity = reactExports.useMemo(() => staged.map((g) => validateMeld(g, jokerMode, randomJoker)), [staged, jokerMode, randomJoker]);
  const isSeven = reactExports.useMemo(() => isSevenCombo(selected, jokerMode, randomJoker), [selected, jokerMode, randomJoker]);
  const layoffCandidates = reactExports.useMemo(() => {
    if (!isMyTurn || phase !== "play" || selected.length === 0) return /* @__PURE__ */ new Set();
    return getLayoffCandidates(melds, selected, jokerMode, randomJoker);
  }, [melds, selected, isMyTurn, phase, jokerMode, randomJoker]);
  const cfg = useGameConfig("rami");
  const [remaining, setRemaining] = reactExports.useState(cfg.turn_timer_seconds);
  reactExports.useEffect(() => {
    if (!game?.turn_deadline || game.status !== "playing") {
      setRemaining(cfg.turn_timer_seconds);
      return;
    }
    let fired = false;
    let lastSec = -1;
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      const s = Math.max(0, Math.ceil(ms / 1e3));
      if (s !== lastSec) {
        lastSec = s;
        setRemaining(s);
      }
      if (s === 0 && !fired) {
        fired = true;
        supabase.rpc("rami_tick", {
          _game_id: id
        });
      }
    };
    tick();
    const t = setInterval(tick, 2e3);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, id, cfg.turn_timer_seconds]);
  reactExports.useEffect(() => {
    const think = game?.state?.bot_think_until;
    if (!think || game?.status !== "playing") return;
    const ms = new Date(think).getTime() - serverNow();
    const delay = Math.max(0, ms) + 150;
    setTimeout(() => {
      supabase.rpc("rami_tick", {
        _game_id: id
      });
    }, delay);
    return;
  }, [game?.state?.bot_think_until, game?.status, id]);
  const [afkWarning, setAfkWarning] = reactExports.useState(false);
  reactExports.useEffect(() => {
    if (!isMyTurn || remaining > 10) {
      setAfkWarning(false);
      return;
    }
    if (remaining <= 10 && remaining > 0) {
      if (remaining === 10 || remaining === 5) sfx.ramiWarning();
      setAfkWarning(true);
    }
  }, [remaining, isMyTurn]);
  const toggleSel = reactExports.useCallback((c) => {
    setSelected((s) => s.includes(c) ? s.filter((x) => x !== c) : [...s, c]);
  }, []);
  const postSelection = async () => {
    const kind = meldKind(selected, jokerMode, randomJoker);
    if (!kind) return toast.error("Sélection invalide");
    const cards = [...selected];
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("rami_meld", {
        _game_id: id,
        _cards: cards
      });
      if (error) throw error;
      setSelected([]);
      sfx.ramiMeld();
      if (kind === "seven") {
        toast.success("🎊 7 cartes validées — ta mise t'est remboursée !");
      } else {
        toast.success(`✓ ${MELD_LABEL[kind]} validé`);
      }
    } catch (e) {
      toast.error(e.message || "Combinaison invalide");
    } finally {
      setBusy(false);
    }
  };
  const [pickedMelds, setPickedMelds] = reactExports.useState([]);
  const [showDiscardHistory, setShowDiscardHistory] = reactExports.useState(false);
  !!(profile?.id && (game?.state?.extra_time || {})[profile.id]);
  const alreadySeven = reactExports.useMemo(() => melds.some((m) => m.player === profile?.id && m.seven === true), [melds, profile?.id]);
  const canClaimSeven = reactExports.useMemo(() => {
    if (!profile?.id || alreadySeven) return false;
    const mine = melds.map((m, i) => ({
      m,
      i
    })).filter((x) => x.m.player === profile?.id);
    if (mine.length < 2) return false;
    for (let a = 0; a < mine.length; a++) {
      for (let b = a + 1; b < mine.length; b++) {
        const combo = [...mine[a].m.cards, ...mine[b].m.cards];
        if (combo.length === 7 && isSevenCombo(combo, jokerMode, randomJoker)) return true;
      }
    }
    return false;
  }, [melds, profile?.id, alreadySeven, jokerMode, randomJoker]);
  const claimSeven = async () => {
    setBusy(true);
    try {
      const {
        data,
        error
      } = await supabase.rpc("rami_claim_seven", {
        _game_id: id
      });
      if (error) throw error;
      if (data) {
        setPickedMelds([]);
        toast.success("🎊 7 cartes validées — ta mise t'est remboursée !");
      } else {
        toast.error("Pas de 7 cartes valide sur tes combinaisons");
      }
    } catch (e) {
      toast.error(e.message || "Action impossible");
    } finally {
      setBusy(false);
    }
  };
  const removeFromStaged = (groupIdx, card) => {
    setStaged((prev) => {
      const next = prev.map((g, i) => i === groupIdx ? g.filter((c) => c !== card) : g);
      return next.filter((g) => g.length > 0);
    });
  };
  const removeStagedGroup = (groupIdx) => {
    setStaged((prev) => prev.filter((_, i) => i !== groupIdx));
  };
  const handleStagedTap = (gi, idx) => {
    if (stagedMoving === null) {
      setStagedMoving({
        gi,
        idx
      });
    } else if (stagedMoving.gi === gi && stagedMoving.idx === idx) {
      setStagedMoving(null);
    } else if (stagedMoving.gi === gi) {
      setStaged((prev) => {
        const next = prev.map((g) => [...g]);
        const arr = next[gi];
        [arr[stagedMoving.idx], arr[idx]] = [arr[idx], arr[stagedMoving.idx]];
        return next;
      });
      setStagedMoving(null);
    } else {
      setStagedMoving({
        gi,
        idx
      });
    }
  };
  const call = async (fn, payload) => {
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc(fn, payload);
      if (error) throw error;
      setSelected([]);
      await load();
    } catch (e) {
      toast.error(e.message || "Action invalide");
    } finally {
      setBusy(false);
    }
  };
  const drawDeck = async () => {
    centerOf(deckRef.current);
    centerOf(handRef.current);
    sfx.ramiDraw();
    await call("rami_draw", {
      _game_id: id,
      _from: "deck"
    });
  };
  const drawDiscard = async () => {
    const pile = discards[lastDiscardBy] || [];
    pile[pile.length - 1];
    centerOf(discardRefs.current[lastDiscardBy]);
    centerOf(handRef.current);
    sfx.ramiDraw();
    await call("rami_draw", {
      _game_id: id,
      _from: "discard"
    });
  };
  const submitStagedMeld = async (groupIdx) => {
    const cards = staged[groupIdx];
    if (!cards || cards.length < 3) return toast.error("Il faut au moins 3 cartes");
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("rami_meld", {
        _game_id: id,
        _cards: cards
      });
      if (error) throw error;
      setStaged((prev) => prev.filter((_, i) => i !== groupIdx));
      sfx.ramiMeld();
      toast.success("Combinaison posée !");
    } catch (e) {
      toast.error(e.message || "Combinaison invalide");
    } finally {
      setBusy(false);
    }
  };
  const submitAllStaged = async () => {
    if (staged.length === 0) return;
    setBusy(true);
    let anyError = false;
    for (const cards of staged) {
      const {
        error
      } = await supabase.rpc("rami_meld", {
        _game_id: id,
        _cards: cards
      });
      if (error) {
        toast.error(error.message || "Combinaison invalide");
        anyError = true;
        break;
      }
    }
    if (!anyError) {
      setStaged([]);
      toast.success("Toutes les combinaisons posées !");
    }
    setBusy(false);
  };
  const discardOne = async () => {
    if (selected.length !== 1) return toast.error("Sélectionne exactement 1 carte à défausser");
    const card = selected[0];
    const myKey = profile?.id || "";
    centerOf(handRef.current);
    centerOf(discardRefs.current[myKey]);
    sfx.ramiDiscard();
    await call("rami_discard", {
      _game_id: id,
      _card: card
    });
  };
  const validateHand = async () => {
    if (staged.length === 0) return toast.error("Prépare tes combinaisons avant de valider");
    if (selected.length !== 1) return toast.error("Sélectionne 1 carte à défausser");
    const layout = staged.map((g) => [...g]);
    const discardCard = selected[0];
    setBusy(true);
    const {
      data,
      error
    } = await supabase.rpc("rami_validate_hand", {
      _game_id: id,
      _layout: layout,
      _discard_card: discardCard
    });
    setBusy(false);
    if (error) {
      toast.error(error.message || "Combinaisons invalides");
      return;
    }
    toast.success("🏆 Bravo, tu gagnes la partie !");
    sfx.ramiWin();
    setStaged([]);
    setSelected([]);
  };
  const hasPosedMeld = reactExports.useMemo(() => !!profile?.id && melds.some((m) => m.player === profile.id), [melds, profile?.id]);
  const layoff = (meldIdx) => {
    if (selected.length < 1) return toast.error("Sélectionne au moins 1 carte");
    if (gameMode === "naturel" && !hasPosedMeld) return toast.info("Mode Naturel : pose d'abord ta propre combinaison (brelan ou suite de 3+)");
    call("rami_layoff", {
      _game_id: id,
      _meld_index: meldIdx,
      _cards: selected
    });
  };
  const unmeld = async (meldIdx) => {
    if (!isMyTurn || phase !== "play") return toast.info("Tu ne peux modifier tes combinaisons que pendant ton tour");
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("rami_unmeld", {
        _game_id: id,
        _meld_index: meldIdx
      });
      if (error) throw error;
      setSelected([]);
      toast.success("Combinaison reprise en main");
    } catch (e) {
      toast.error(e.message || "Impossible de casser cette combinaison");
    } finally {
      setBusy(false);
    }
  };
  const confirm = useConfirm();
  const forfeit = async () => {
    const stake = Number(game?.stake) || 0;
    if (game?.status !== "waiting" && game?.status !== "open") {
      const ok = await confirm({
        title: "Quitter la partie ?",
        description: stake > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
          "Si tu quittes, tu perdras automatiquement et ta mise sera définitivement perdue. ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { children: [
            stake.toLocaleString("fr-FR"),
            " Ar"
          ] }),
          "."
        ] }) : "Si tu quittes, tu perdras automatiquement la partie.",
        confirmLabel: "Confirmer quitter",
        destructive: true
      });
      if (!ok) return;
    }
    await supabase.rpc("rami_forfeit", {
      _game_id: id
    });
    navigate({
      to: "/jeux"
    });
  };
  const moveCard = (fromIdx, toIdx) => {
    setCustomOrder((prev) => {
      const arr = prev ? [...prev] : [...orderedHandCards];
      const [item] = arr.splice(fromIdx, 1);
      arr.splice(toIdx, 0, item);
      return arr;
    });
    setMovingIdx(null);
  };
  const handleReorderTap = (cardIdx) => {
    if (movingIdx === null) {
      setMovingIdx(cardIdx);
    } else if (movingIdx === cardIdx) {
      setMovingIdx(null);
    } else {
      moveCard(movingIdx, cardIdx);
    }
  };
  const parseId = (id2) => {
    if (id2 === "hand-end") return {
      kind: "hand-end"
    };
    if (id2.startsWith("hand:")) return {
      kind: "hand",
      card: Number(id2.slice(5))
    };
    if (id2.startsWith("staged-end:")) return {
      kind: "staged-end",
      gi: Number(id2.slice(11))
    };
    if (id2.startsWith("staged:")) {
      const [, gi, card] = id2.split(":");
      return {
        kind: "staged",
        gi: Number(gi),
        card: Number(card)
      };
    }
    return {
      kind: "unknown"
    };
  };
  const insertAt = (arr, card, refCard, side) => {
    const clean = arr.filter((c) => c !== card);
    if (refCard === null) return [...clean, card];
    const idx = clean.indexOf(refCard);
    if (idx < 0) return [...clean, card];
    const pos = side === "before" ? idx : idx + 1;
    return [...clean.slice(0, pos), card, ...clean.slice(pos)];
  };
  const autoStageFromOrder = reactExports.useCallback((order) => {
    setCustomOrder(order);
  }, []);
  const handleDrop = reactExports.useCallback((sourceId, targetId, side) => {
    const src = parseId(sourceId);
    const tgt = parseId(targetId);
    if (src.kind === "unknown" || tgt.kind === "unknown") return;
    let nextHand = [...orderedHandCards];
    let nextStaged = staged.map((g) => [...g]);
    let movingCard = null;
    if (src.kind === "hand") {
      movingCard = src.card;
      nextHand = nextHand.filter((c) => c !== movingCard);
    } else if (src.kind === "staged") {
      movingCard = src.card;
      nextStaged[src.gi] = nextStaged[src.gi].filter((c) => c !== movingCard);
    }
    if (movingCard === null) return;
    if (tgt.kind === "hand") {
      nextHand = insertAt(nextHand, movingCard, tgt.card, side);
    } else if (tgt.kind === "hand-end") {
      nextHand = insertAt(nextHand, movingCard, null, "after");
    } else if (tgt.kind === "staged") {
      nextStaged[tgt.gi] = insertAt(nextStaged[tgt.gi], movingCard, tgt.card, side);
    } else if (tgt.kind === "staged-end") {
      nextStaged[tgt.gi] = insertAt(nextStaged[tgt.gi], movingCard, null, "after");
    }
    const dropped = [];
    nextStaged = nextStaged.filter((g) => {
      if (g.length < 3) {
        dropped.push(...g);
        return false;
      }
      return true;
    });
    if (dropped.length > 0) nextHand = [...nextHand, ...dropped];
    setStaged(nextStaged);
    if (tgt.kind === "hand" || tgt.kind === "hand-end" || dropped.length > 0) {
      autoStageFromOrder(nextHand);
    } else {
      setCustomOrder(nextHand);
    }
  }, [orderedHandCards, staged, autoStageFromOrder]);
  const dnd = useLongPressDrag({
    delay: 250,
    onDrop: handleDrop
  });
  const sevenCardsEnabled = game?.seven_cards !== false;
  if (!game) return /* @__PURE__ */ jsxRuntimeExports.jsx(GameLoader, {});
  const replayRami = async () => {
    const hadBots = parts.some((p) => p.is_bot);
    if (hadBots) {
      const {
        data,
        error
      } = await supabase.rpc("rami_start_solo_bot", {
        _max_players: game.max_players,
        _difficulty: "medium",
        _joker_mode: game.joker_mode || "classique",
        _game_mode: game.game_mode || "bordel"
      });
      if (error) {
        toast.error(error.message);
        return;
      }
      refreshProfile();
      navigate({
        to: "/jeux/rami/$id",
        params: {
          id: data
        }
      });
    } else {
      const {
        data,
        error
      } = await supabase.rpc("rami_create", {
        _stake: Number(game.stake) || 0,
        _max: game.max_players,
        _private: !!game.is_private,
        _commission: Number(game.commission_pct) || 10,
        _game_mode: game.game_mode || "bordel",
        _joker_mode: game.joker_mode || "classique",
        _seven_cards: game.seven_cards !== false
      });
      if (error) {
        toast.error(error.message);
        return;
      }
      refreshProfile();
      navigate({
        to: "/jeux/rami/$id",
        params: {
          id: data
        }
      });
    }
  };
  if (game.status === "cancelled") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(GameStateMessage, { state: "cancelled", gameLabel: "Rami", slug: "rami" });
  }
  if (game.status === "open" || game.status === "waiting") {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameWaitingRoom, { isTournament: !!game.tournament_match_id, slug: "rami", gameLabel: `Rami · ${game.max_players} joueurs`, parts, maxPlayers: game.max_players, stake: Number(game.stake) || 0, pot: Number(game.pot) || 0, roomCode: game.is_private ? game.room_code : null, shareSlug: "rami", meUserId: profile?.id, isParticipant: !!me, createdAt: game.created_at, onQuit: forfeit, onToggleReady: async (ready) => {
        const {
          error
        } = await supabase.rpc("rami_set_ready", {
          _game_id: id,
          _ready: ready
        });
        if (error) toast.error(error.message);
      } }),
      (isAdmin || Number(game.stake) === 0 && !!me) && parts.length < game.max_players && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
        const {
          error
        } = await supabase.rpc("rami_add_bot", {
          _game_id: id,
          _bot_name: "Bot"
        });
        if (error) toast.error(error.message);
        else toast.success("Bot ajouté");
      }, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Ajouter un bot"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "rami", participants: parts })
    ] });
  }
  if (game.status === "finished") {
    const _winnerSlot = game.winner_id ? parts.find((p) => p.user_id === game.winner_id)?.slot : parts.find((p) => !p.forfeited)?.slot ?? null;
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4 min-h-screen flex flex-col items-center justify-center", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "rami", meUserId: profile?.id, winnerId: game.winner_id, winnerSlot: _winnerSlot, participants: parts, stake: Number(game.stake) || 0, pot: Number(game.pot) || 0, commissionPct: Number(game.commission_pct) || 10, onReplay: replayRami }),
      game.state?.hands && /* @__PURE__ */ jsxRuntimeExports.jsx(RamiScoreSummary, { parts, hands: game.state.hands, winnerId: game.winner_id, pot: Number(game.pot) || 0, commissionPct: Number(game.commission_pct) || 10, melds: game.state?.melds }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "rami", participants: parts })
    ] });
  }
  const drawablePile = (discards[lastDiscardBy] || []).length > 0 ? discards[lastDiscardBy] : Object.values(discards).find((p) => Array.isArray(p) && p.length > 0) || [];
  const topDiscard = drawablePile.length > 0 ? drawablePile[drawablePile.length - 1] : void 0;
  const _discardColors = ["#ef4444", "#3b82f6", "#22c55e", "#eab308", "#a855f7", "#ec4899"];
  const discardEntries = [];
  if ((discards["_seed"] || []).length > 0) {
    discardEntries.push({
      key: "_seed",
      label: "1re",
      color: "#94a3b8",
      pile: discards["_seed"],
      isMe: false
    });
  }
  parts.slice().sort((a, b) => a.slot - b.slot).forEach((p, i) => {
    const key = p.user_id || `bot:${p.slot}`;
    const isMe = p.user_id === profile?.id;
    discardEntries.push({
      key,
      label: isMe ? "Moi" : (p.display_name || "Joueur").slice(0, 8),
      color: _discardColors[i % _discardColors.length],
      pile: discards[key] || [],
      isMe
    });
  });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-2.5 py-1.5 flex flex-col gap-1.5 h-full overflow-hidden overscroll-none rounded-xl", style: {
    background: `linear-gradient(rgba(0,0,0,0.25), rgba(0,0,0,0.35)), radial-gradient(ellipse at center, ${activeTheme.feltCenter || "#1a6b3a"} 0%, ${activeTheme.feltEdge || "#0b3a1f"} 70%, ${activeTheme.border} 100%)`,
    backgroundSize: "cover",
    backgroundPosition: "center",
    boxShadow: "inset 0 0 60px rgba(0,0,0,0.45), 0 0 0 6px #0f3d20, 0 8px 24px rgba(0,0,0,0.4)"
  }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameReconnectOverlay, { isConnected, isReconnecting, onRetry: retry }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-card/95 px-2.5 py-1 border border-border shadow-sm flex items-center justify-between gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2.5 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] font-bold text-amber-500 whitespace-nowrap", children: [
          "🏆 ",
          Math.round(Number(game.pot) * (100 - (Number(game.commission_pct) || 10)) / 100).toLocaleString("fr-FR"),
          " Ar"
        ] }),
        game?.status === "playing" && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] font-semibold text-emerald-500 whitespace-nowrap", children: [
          "🂠 ",
          deckCount
        ] }),
        game?.status === "playing" && me && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] font-semibold text-blue-500 whitespace-nowrap", children: [
          "✦ ",
          melds.filter((m) => m.player === profile?.id).length,
          " combo"
        ] }),
        sevenCardsEnabled ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold text-amber-500 whitespace-nowrap", children: "7️⃣" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold text-muted-foreground/60 whitespace-nowrap", children: "7️⃣✕" })
      ] }),
      !me ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1", children: "Spectateur" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 shrink-0", children: [
        parts.some((p) => p.is_bot) && game.status === "playing" && !game.paused && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
          const {
            error
          } = await supabase.rpc("game_request_pause", {
            _slug: "rami",
            _game_id: id
          });
          if (error) toast.error(error.message);
          else toast.success("Partie en pause");
        }, className: "px-1.5 py-0.5 rounded-full bg-amber-500/90 text-white text-[9px] font-bold flex items-center gap-0.5 active:scale-90 transition", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-2.5 h-2.5" }),
          " Pause"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setBoardTheme(boardTheme === "green" ? "blue" : boardTheme === "blue" ? "dark" : "green"), className: "w-6 h-6 rounded-full bg-secondary/80 text-secondary-foreground flex items-center justify-center active:scale-90 transition", title: "Thème", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Palette, { className: "w-3 h-3" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          const m = !soundOn;
          setSoundOn(m);
          setMuted(m);
        }, className: "w-6 h-6 rounded-full bg-secondary/80 text-secondary-foreground flex items-center justify-center active:scale-90 transition", children: soundOn ? /* @__PURE__ */ jsxRuntimeExports.jsx(Volume2, { className: "w-3 h-3" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(VolumeX, { className: "w-3 h-3" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: forfeit, className: "px-1.5 py-0.5 rounded-full bg-destructive/90 text-white text-[9px] font-bold flex items-center gap-0.5 active:scale-90 transition", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-2.5 h-2.5" }),
          " Quitter"
        ] })
      ] })
    ] }),
    isSpectating && !isPlayer && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "fixed top-14 left-1/2 -translate-x-1/2 z-[140] px-4 py-1.5 rounded-full bg-blue-500/90 text-white text-xs font-bold flex items-center gap-2 shadow-lg", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-3.5 h-3.5" }),
      " Mode spectateur"
    ] }),
    afkWarning && isMyTurn && game?.status === "playing" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "fixed top-14 left-1/2 -translate-x-1/2 z-[150] px-4 py-2 rounded-full bg-destructive text-white text-xs font-bold flex items-center gap-2 shadow-lg", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-3.5 h-3.5" }),
      " Attention ! Plus que ",
      remaining,
      "s pour jouer"
    ] }),
    game.status === "finished" && /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "rami", meUserId: profile?.id, winnerId: game.winner_id, participants: parts, stake: Number(game.stake), pot: Number(game.pot), commissionPct: Number(game.commission_pct) || 10, onReplay: replayRami }),
    game.status === "finished" && game.state?.hands && /* @__PURE__ */ jsxRuntimeExports.jsx(RamiScoreSummary, { parts, hands: game.state.hands, winnerId: game.winner_id, pot: Number(game.pot), commissionPct: Number(game.commission_pct) || 10, melds: game.state?.melds }),
    lbEntries.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx(RamiLeaderboard, { entries: lbEntries, meUserId: profile?.id, onReset: resetLb }),
    game?.status === "playing" && isPlayer && availableCombos.length > 0 && selected.length === 0 && staged.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1 flex-wrap px-2 py-1 rounded-lg bg-card/95 border border-border shadow-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] font-bold text-amber-500 flex items-center gap-0.5 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Lightbulb, { className: "w-3 h-3" }),
        " Combo",
        availableCombos.length > 1 ? "s" : "",
        " :"
      ] }),
      availableCombos.map((combo, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setSelected(combo.cards), className: "px-1.5 py-0.5 rounded-full bg-primary/15 border border-primary/25 text-[9px] font-bold text-primary hover:bg-primary/25 active:scale-95 transition-all flex items-center gap-0.5", children: [
        combo.type === "trio" && " Trio",
        combo.type === "carré" && " Carré",
        combo.type === "escalier" && " Escalier",
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex gap-0.5", children: [
          combo.cards.slice(0, 3).map((c, ci) => {
            const base = CARD_BASE(c);
            const r = base % 13;
            const s = Math.floor(base / 13);
            return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[8px]", style: {
              color: SUIT_COLORS[s]
            }, children: [
              RANKS[r],
              SUITS[s]
            ] }, ci);
          }),
          combo.cards.length > 3 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[8px]", children: [
            "+",
            combo.cards.length - 3
          ] })
        ] })
      ] }, i))
    ] }),
    game?.status === "playing" && (() => {
      const sorted = parts.slice().sort((a, b) => a.slot - b.slot);
      const meIdx = sorted.findIndex((p) => p.user_id === profile?.id);
      const others = meIdx >= 0 ? [...sorted.slice(meIdx + 1), ...sorted.slice(0, meIdx)] : sorted;
      const keyOf = (p) => p.user_id || `bot:${p.slot}`;
      const handLenOf = (uid) => Array.isArray(game?.state?.hands?.[uid]) ? game.state.hands[uid].length : 0;
      const OppBadge = React__default.memo(function OppBadge2({
        p,
        turn,
        n,
        meldCount,
        isLast
      }) {
        const name = (p.display_name || "Joueur").slice(0, 10);
        const initial = name.charAt(0).toUpperCase();
        const gradients = ["linear-gradient(145deg,#60a5fa,#2563eb)", "linear-gradient(145deg,#f87171,#dc2626)", "linear-gradient(145deg,#4ade80,#16a34a)", "linear-gradient(145deg,#fbbf24,#d97706)", "linear-gradient(145deg,#c084fc,#9333ea)", "linear-gradient(145deg,#f472b6,#db2777)"];
        const bg = gradients[name.charCodeAt(0) % gradients.length];
        const fanCount = Math.min(n, 5);
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex flex-col items-center gap-0.5 px-1.5 py-1 rounded-xl shrink-0 transition-all ${turn ? "bg-amber-500/15 ring-1 ring-amber-400/70 shadow-[0_0_10px_-2px_rgba(251,191,36,0.6)]" : ""} ${isLast ? "" : ""}`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "relative h-[20px] flex items-end justify-center", style: {
            width: 38 + fanCount * 3
          }, children: Array.from({
            length: fanCount
          }).map((_, i) => {
            const mid = (fanCount - 1) / 2;
            const rot = (i - mid) * 11;
            return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute bottom-0 rounded-[2px] border border-white/25", style: {
              width: 14,
              height: 19,
              left: `calc(50% + ${(i - mid) * 8}px - 7px)`,
              transform: `rotate(${rot}deg)`,
              background: "linear-gradient(135deg,#1e3a8a,#1e40af)",
              boxShadow: "0 1px 2px rgba(0,0,0,0.5)",
              zIndex: i
            } }, i);
          }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `rounded-full flex items-center justify-center font-bold text-white shrink-0 border-2 ${turn ? "border-yellow-300 shadow-[0_0_8px_rgba(253,224,71,0.6)]" : "border-white/20"}`, style: {
              width: 28,
              height: 28,
              fontSize: 12,
              background: bg,
              boxShadow: "inset 0 -2px 4px rgba(0,0,0,0.25)"
            }, children: p.is_bot ? "◆" : initial }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col leading-tight", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-white/95", children: name }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[9px] text-white/55 font-semibold", children: [
                  n,
                  " cartes"
                ] }),
                meldCount > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[8px] text-amber-300/90 font-bold", children: [
                  "✦",
                  meldCount
                ] })
              ] })
            ] })
          ] }),
          turn && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[8px] font-mono font-bold px-1.5 py-0.5 rounded-full bg-black/40", style: {
            color: remaining <= 5 ? "#ef4444" : remaining <= 10 ? "#f59e0b" : "#22c55e"
          }, children: [
            remaining,
            "s"
          ] })
        ] });
      });
      const meldCountOf = (uid) => melds.filter((m) => m.player === uid).length;
      const isSeven2 = (m) => m.type === "seven" || m.seven === true;
      const myMelds = melds.map((m, i) => ({
        m,
        i
      })).filter((x) => !!profile?.id && x.m.player === profile.id);
      const publicSevenMelds = melds.map((m, i) => ({
        m,
        i
      })).filter((x) => (!profile?.id || x.m.player !== profile.id) && isSeven2(x.m)).map((x) => ({
        ...x,
        name: ((p) => (p?.display_name || "Joueur").slice(0, 10))(sorted.find((s) => (s.user_id || `bot:${s.slot}`) === x.m.player))
      }));
      const MeldRow = ({
        m,
        i,
        mine
      }) => {
        const kind = m.type || meldKind(m.cards, jokerMode, randomJoker);
        const isSevenMeld = kind === "seven" || m.seven === true;
        const revealed = mine || isSevenMeld;
        const canLayoff = layoffCandidates.has(i);
        const canBreak = mine && !!isMyTurn && phase === "play" && selected.length === 0 && !busy;
        return /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          if (canLayoff) layoff(i);
          else if (canBreak) unmeld(i);
        }, onDoubleClick: () => {
          if (canBreak) unmeld(i);
        }, disabled: !canLayoff && !mine, className: `relative flex rounded-lg p-1 transition-all shrink-0 bg-black/10 ${isSevenMeld ? "ring-2 ring-amber-400 shadow-[0_0_14px_-4px_rgba(251,191,36,0.9)]" : canLayoff ? "ring-2 ring-emerald-400" : "ring-1 ring-white/10"}`, style: {
          boxShadow: "0 2px 5px rgba(0,0,0,0.3)"
        }, children: m.cards.map((c, ci) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { style: {
          marginLeft: ci > 0 ? -13 : 0,
          filter: "drop-shadow(1px 0 1.5px rgba(0,0,0,0.4))"
        }, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c: revealed ? c : void 0, faceDown: !revealed, styleOverride: {
          width: 25,
          height: 35
        } }) }, `m-${i}-${ci}`)) }, `meld-${i}`);
      };
      const oppStrip = /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-center gap-2.5 px-3 py-1.5 rounded-t-xl", style: {
        background: `linear-gradient(180deg, ${activeTheme.feltEdge || "#0b3a1f"}ee, transparent)`
      }, children: others.map((p, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(OppBadge, { p, turn: game.current_turn === p.slot, n: handLenOf(keyOf(p)), meldCount: meldCountOf(p.user_id || ""), isLast: i === others.length - 1 }, keyOf(p))) });
      const centerFelt = /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative flex-1 flex items-center justify-center gap-5 px-3 py-2 min-h-0 overflow-hidden", style: {
        background: `radial-gradient(ellipse at center, ${activeTheme.feltCenter || "#1a6b3a"} 0%, ${activeTheme.feltEdge || "#0b3a1f"} 80%)`,
        boxShadow: "inset 0 0 50px rgba(0,0,0,0.45), inset 0 0 2px rgba(255,255,255,0.06)"
      }, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute bottom-1 right-2 text-white/[0.05] select-none pointer-events-none", style: {
          fontSize: 40
        }, children: "♦" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute top-1 left-2 text-white/[0.04] select-none pointer-events-none", style: {
          fontSize: 28
        }, children: "♠" }),
        publicSevenMelds.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute top-1 left-1/2 -translate-x-1/2 flex flex-wrap justify-center gap-1 max-w-[80%]", children: publicSevenMelds.map(({
          m,
          i,
          name
        }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[7px] font-bold text-amber-300/90", children: [
            "🎊 ",
            name
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(MeldRow, { m, i, mine: false })
        ] }, `pub-${i}`)) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { ref: deckRef, disabled: !isMyTurn || phase !== "draw" || busy || deckCount === 0, onClick: drawDeck, className: `relative rounded-md disabled:opacity-50 active:scale-95 transition-transform ${isMyTurn && phase === "draw" && deckCount > 0 ? "ring-2 ring-yellow-300 shadow-lg" : ""}`, style: {
            filter: "drop-shadow(0 4px 6px rgba(0,0,0,0.45))"
          }, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { faceDown: true, styleOverride: {
            width: 60,
            height: 84
          } }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] font-semibold text-white/90 bg-black/60 px-2.5 py-1 rounded-full", children: [
            "Pioche · ",
            deckCount
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-end gap-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: !(isMyTurn && phase === "draw" && !busy && topDiscard !== void 0), onClick: drawDiscard, className: `relative rounded-md active:scale-95 transition-transform ${isMyTurn && phase === "draw" && topDiscard !== void 0 ? "ring-2 ring-emerald-300 shadow-lg" : ""} ${""}`, children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { ref: (el) => {
              discardRefs.current[lastDiscardBy] = el;
              if (profile?.id) discardRefs.current[profile.id] = el;
            }, children: topDiscard !== void 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c: topDiscard, styleOverride: {
              width: 58,
              height: 82
            } }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-md border border-dashed border-white/40", style: {
              width: 58,
              height: 82
            } }) }) }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowDiscardHistory(true), className: "w-5 h-5 rounded-full bg-black/60 text-white text-[10px] font-bold flex items-center justify-center border border-white/30", title: "Historique", children: "⋯" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-white/90 bg-black/60 px-2.5 py-1 rounded-full", children: "Défausse" })
        ] }),
        randomJoker !== null && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c: randomJoker, styleOverride: {
            width: 58,
            height: 82
          } }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-amber-300 bg-black/60 px-2.5 py-1 rounded-full", children: "Carte tirée" })
        ] })
      ] });
      const myMeldsStrip = /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-2 py-1 rounded-b-xl", style: {
        background: `linear-gradient(0deg, ${activeTheme.feltEdge || "#0b3a1f"}dd, transparent)`
      }, children: myMelds.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-white/30 text-[9px] py-0.5", children: sevenCardsEnabled ? "Aucune combinaison posée" : "Posez vos combinaisons pour gagner" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-center gap-1.5 overflow-x-auto", children: myMelds.map(({
        m,
        i
      }) => /* @__PURE__ */ jsxRuntimeExports.jsx(MeldRow, { m, i, mine: true }, i)) }) });
      return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl flex-[1.4_1_0%] min-h-[32vh] flex flex-col p-[5px]", style: {
        background: "repeating-linear-gradient(100deg, #7a4a26 0px, #8a5a34 3px, #6e4322 6px, #85532f 9px)",
        boxShadow: "0 6px 20px rgba(0,0,0,0.4), inset 0 0 0 1px rgba(0,0,0,0.3)"
      }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl overflow-hidden border flex-1 flex flex-col min-h-0", style: {
        borderColor: activeTheme.border,
        boxShadow: "inset 0 2px 6px rgba(0,0,0,0.5)"
      }, children: [
        oppStrip,
        centerFelt,
        myMeldsStrip
      ] }) });
    })(),
    showDiscardHistory && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[200] bg-black/70 flex items-end sm:items-center justify-center p-3", onClick: () => setShowDiscardHistory(false), children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full max-w-md rounded-2xl bg-card text-card-foreground p-3 max-h-[70vh] overflow-y-auto space-y-3", onClick: (e) => e.stopPropagation(), children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "font-bold text-sm", children: "Historique de la défausse" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowDiscardHistory(false), className: "text-xs font-bold px-2 py-1 rounded-lg bg-muted", children: "Fermer" })
      ] }),
      discardEntries.every((e) => e.pile.length === 0) ? /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Aucune carte défaussée pour le moment." }) : discardEntries.filter((e) => e.pile.length > 0).map((entry) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] font-bold", style: {
          color: entry.color
        }, children: [
          entry.label,
          " · ",
          entry.pile.length,
          " carte",
          entry.pile.length > 1 ? "s" : ""
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-1", children: entry.pile.map((c, ci) => /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c, styleOverride: {
          width: 28,
          height: 40
        } }, `h-${entry.key}-${ci}`)) })
      ] }, entry.key))
    ] }) }),
    !!me && sevenCardsEnabled && !alreadySeven && canClaimSeven && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: claimSeven, disabled: busy, className: "w-full rounded-xl px-3 py-2.5 font-black text-xs text-white shadow-lg active:scale-95 bg-gradient-to-r from-amber-500 to-fuchsia-600 animate-pulse", children: "🎊 Valider mes 7 cartes — mise remboursée !" }),
    me && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1 shrink-0", children: [
      handCards.length > 0 && !reorderMode && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 px-1 mb-0.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          setSortMode(sortMode === "suit" ? "none" : "suit");
          setCustomOrder(null);
        }, className: `px-1.5 py-0.5 rounded-full text-[9px] font-bold transition-all active:scale-90 ${sortMode === "suit" ? "bg-emerald-500 text-white" : "bg-white/10 text-white/50"}`, children: "♠ Couleur" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          setSortMode(sortMode === "rank" ? "none" : "rank");
          setCustomOrder(null);
        }, className: `px-1.5 py-0.5 rounded-full text-[9px] font-bold transition-all active:scale-90 ${sortMode === "rank" ? "bg-emerald-500 text-white" : "bg-white/10 text-white/50"}`, children: "7 Valeur" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          setReorderMode(true);
        }, className: "px-1.5 py-0.5 rounded-full text-[9px] font-bold bg-white/10 text-white/50 active:scale-90 ml-auto", children: "✋ Réordonner" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: reorderMode ? "overflow-x-auto" : "", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { ref: handRef, className: `${reorderMode ? "flex gap-2 min-w-max" : "flex flex-col gap-1"} px-1 py-1`, children: [
        reorderMode ? orderedHandCards.map((c, i) => {
          const isGrabbed = movingIdx === i;
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative flex flex-col items-center gap-0.5 shrink-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-0.5 mb-1 ${isGrabbed ? "opacity-100" : "opacity-0"}`, children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => i > 0 && moveCard(i, i - 1), className: "w-5 h-5 rounded-full bg-violet-600 text-white flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronLeft, { className: "w-3 h-3" }) }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => i < orderedHandCards.length - 1 && moveCard(i, i + 1), className: "w-5 h-5 rounded-full bg-violet-600 text-white flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-3 h-3" }) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c, size: "lg", selected: isGrabbed, onClick: () => handleReorderTap(i) }),
            isGrabbed && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] text-violet-600 font-bold mt-0.5", children: "saisie" })
          ] }, `ro-${c}-${i}`);
        }) : (() => {
          const n = orderedHandCards.length;
          const perRow = Math.ceil(n / 2);
          const rows = [orderedHandCards.slice(0, perRow), orderedHandCards.slice(perRow)];
          const avail = (typeof window !== "undefined" ? Math.min(window.innerWidth, 480) : 360) - 24;
          const cw = Math.max(30, Math.min(42, Math.floor((avail - (perRow - 1) * 3) / Math.max(perRow, 1))));
          const ch = Math.round(cw * 1.35);
          let globalIdx = 0;
          return rows.map((row, ri) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center items-end gap-1", "data-drop-target": "hand-end", children: row.map((c) => {
            const i = globalIdx++;
            const isSel = selected.includes(c);
            const showQuickDiscard = isSel && isMyTurn && phase === "play" && selected.length === 1 && !busy;
            const srcId = `hand:${c}`;
            const isBeingDragged = dnd.isDraggingId(srcId);
            const dropSide = dnd.isTargetId(srcId);
            return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative transition-transform duration-100 ease-out select-none", "data-drop-target": srcId, ...dnd.getSourceProps(srcId), style: {
              zIndex: isBeingDragged ? 1 : isSel ? 100 + i : i,
              transform: isBeingDragged ? void 0 : isSel ? "translateY(-14px) scale(1.05)" : void 0,
              opacity: isBeingDragged ? 0.25 : 1,
              touchAction: "none",
              boxShadow: isBeingDragged ? "0 2px 8px rgba(0,0,0,0.2)" : isSel ? "0 8px 16px rgba(0,0,0,0.45)" : "0 3px 6px rgba(0,0,0,0.35)",
              filter: isBeingDragged ? "grayscale(0.6)" : void 0
            }, children: [
              dropSide === "before" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -left-1 top-1 bottom-1 w-1 rounded-full bg-primary pointer-events-none" }),
              dropSide === "after" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -right-1 top-1 bottom-1 w-1 rounded-full bg-primary pointer-events-none" }),
              showQuickDiscard && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: (e) => {
                e.stopPropagation();
                discardOne();
              }, className: "absolute -top-8 left-1/2 -translate-x-1/2 z-[999] px-3 py-1 rounded-full bg-destructive text-white text-[11px] font-extrabold shadow-lg shadow-destructive/40 flex items-center gap-1 whitespace-nowrap animate-scale-in hover:bg-destructive/90 active:scale-95", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-3 h-3" }),
                " Défausser"
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c, selected: isSel, onClick: () => {
                if (!dnd.drag) toggleSel(c);
              }, styleOverride: {
                width: `${cw}px`,
                height: `${ch}px`,
                pointerEvents: dnd.drag ? "none" : void 0
              } }),
              playableCards.has(c) && !isSel && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 rounded-md ring-2 ring-amber-400/70 pointer-events-none", style: {
                width: `${cw}px`,
                height: `${ch}px`
              } }),
              newCard === c && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 rounded-lg ring-2 ring-amber-400 pointer-events-none" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -top-2 -right-1 z-[60] px-1.5 py-0.5 rounded-full bg-amber-400 text-black text-[9px] font-extrabold shadow-md pointer-events-none animate-scale-in", children: "NEW" })
              ] })
            ] }, `${c}-${i}`);
          }) }, `row-${ri}`));
        })(),
        handCards.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-1 p-8 self-center text-center", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-2xl", children: "🎉" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-emerald-400 font-bold", children: "Main vide !" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground/60", children: "Tu as posé toutes tes cartes" })
        ] })
      ] }) }),
      isMyTurn && phase === "play" && !reorderMode && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1", children: [
        selected.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-xl border p-2 space-y-1.5 transition-all ${selectionValidity === "valid" ? "border-emerald-500/30 bg-emerald-500/5" : selectionValidity === "invalid" ? "border-destructive/30 bg-destructive/5" : "border-primary/20 bg-primary/5"}`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-1.5 h-1.5 rounded-full shrink-0 ${selectionValidity === "valid" ? "bg-emerald-400" : selectionValidity === "invalid" ? "bg-destructive" : "bg-primary"}` }),
              selectionValidity === "valid" && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "px-1.5 py-0.5 rounded-full bg-emerald-500 text-white text-[9px] font-black shrink-0", children: [
                "✓ ",
                selectionKind ? MELD_LABEL[selectionKind] : "Valide"
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] font-bold truncate", children: [
                selected.length,
                " carte",
                selected.length > 1 ? "s" : ""
              ] }),
              isSeven && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-black text-amber-400 shrink-0", children: "🎊 7 cartes!" })
            ] }),
            selectionFeedback.hint && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[9px] font-semibold px-1.5 py-0.5 rounded-full shrink-0 ${selectionFeedback.severity === "ok" ? "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-300" : selectionFeedback.severity === "error" ? "bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300" : selectionFeedback.severity === "warn" ? "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-300" : "bg-blue-100 text-blue-700 dark:bg-blue-900/40 dark:text-blue-300"}`, children: selectionFeedback.hint })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
            selected.length >= 3 && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => postSelection(), disabled: busy, className: `flex-1 flex items-center justify-center gap-1.5 px-3 py-2 rounded-lg font-black text-xs shadow-md active:scale-95 transition-all ${selectionKind === "seven" ? "bg-gradient-to-r from-amber-500 to-fuchsia-600 text-white" : selectionKind ? "bg-emerald-600 text-white hover:bg-emerald-500" : "bg-emerald-600/80 text-white"}`, children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3.5 h-3.5" }),
              selectionKind === "seven" ? "7 cartes" : selectionKind ? `Valider ${MELD_LABEL[selectionKind]}` : "Valider"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: discardOne, disabled: busy || selected.length !== 1, className: "flex items-center justify-center gap-1 px-3 py-2 rounded-lg bg-destructive text-white font-bold text-xs disabled:opacity-30 active:scale-95 transition-all", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-3.5 h-3.5" }),
              " Défausser"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setSelected([]), className: "flex items-center justify-center gap-1 px-2.5 py-2 rounded-lg bg-white/8 text-muted-foreground font-semibold text-xs active:scale-95 transition-all", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3.5 h-3.5" }) })
          ] }),
          layoffCandidates.size > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-[10px] text-emerald-400 font-semibold px-2 py-1 rounded-lg bg-emerald-500/8 border border-emerald-500/15", children: [
            "↑ ",
            layoffCandidates.size,
            " combinaison",
            layoffCandidates.size > 1 ? "s" : "",
            " sur table accepte",
            layoffCandidates.size > 1 ? "nt" : "",
            " ces cartes"
          ] })
        ] }),
        isMyTurn && game?.turn_phase === "play" && staged.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl p-2 bg-gradient-to-r from-amber-500/15 via-yellow-500/10 to-amber-500/15 border border-amber-500/40 shadow-lg", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: validateHand, disabled: busy || staged.length === 0 || selected.length !== 1, className: "w-full flex items-center justify-center gap-2 px-3 py-2.5 rounded-xl bg-gradient-to-r from-amber-500 to-yellow-500 text-black font-black text-sm shadow-md shadow-amber-500/40 disabled:opacity-40 hover:brightness-110 active:scale-[0.98] transition-all", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-5 h-5" }),
            selected.length === 1 ? `Valider ma main (${staged.length} combo${staged.length > 1 ? "s" : ""} + 1 défausse)` : "Valider ma main — sélectionne 1 carte à défausser"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-center text-amber-200/80 mt-1.5", children: "Le serveur vérifie toutes tes combinaisons. Si tout est valide, tu gagnes." })
        ] }),
        staged.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-emerald-500/6 border border-emerald-500/20 p-2 space-y-2 shadow-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-2 h-2 rounded-full bg-emerald-400 animate-pulse" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs font-bold text-emerald-600 dark:text-emerald-400", children: [
                "Zone de pose · ",
                staged.length,
                " combinaison",
                staged.length > 1 ? "s" : ""
              ] })
            ] }),
            staged.length > 1 && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: submitAllStaged, disabled: busy, className: "flex items-center gap-1 px-3 py-1.5 rounded-lg bg-emerald-600 text-white font-bold text-xs disabled:opacity-40 shadow-sm hover:bg-emerald-500 active:scale-95 transition-all", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3.5 h-3.5" }),
              " Tout poser"
            ] })
          ] }),
          stagedMoving && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] text-violet-500 font-semibold px-1", children: "Touche une autre carte de la combo pour l'échanger de place" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: staged.map((group, gi) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-lg p-2 flex items-center gap-2 transition-all border ${stagedValidity[gi] === "valid" ? "bg-emerald-500/5 border-emerald-500/25 shadow-sm" : stagedValidity[gi] === "invalid" ? "bg-destructive/5 border-destructive/25" : "bg-white/4 border-white/8"}`, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 overflow-x-auto flex-1 pb-1", "data-drop-target": `staged-end:${gi}`, children: group.map((c, ci) => {
              const srcId = `staged:${gi}:${c}`;
              const isBeingDragged = dnd.isDraggingId(srcId);
              const dropSide = dnd.isTargetId(srcId);
              const isPicked = stagedMoving?.gi === gi && stagedMoving?.idx === ci;
              return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative select-none", "data-drop-target": srcId, ...dnd.getSourceProps(srcId), style: {
                opacity: isBeingDragged ? 0.55 : 1,
                transform: isBeingDragged ? "translateY(-10px) scale(1.06)" : isPicked ? "translateY(-6px) scale(1.08)" : void 0,
                transition: "transform 0.15s ease-out",
                touchAction: "none"
              }, children: [
                dropSide === "before" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -left-1 top-0 bottom-0 w-1 rounded-full bg-primary shadow-[0_0_10px_hsl(var(--primary))] animate-pulse pointer-events-none" }),
                dropSide === "after" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -right-1 top-0 bottom-0 w-1 rounded-full bg-primary shadow-[0_0_10px_hsl(var(--primary))] animate-pulse pointer-events-none" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c, size: "md", selected: isPicked, onClick: () => handleStagedTap(gi, ci), onRemove: () => removeFromStaged(gi, c) })
              ] }, `stage-${gi}-${ci}`);
            }) }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col gap-1.5 shrink-0 items-end", children: [
              stagedValidity[gi] !== "unknown" && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] font-bold ${stagedValidity[gi] === "valid" ? "text-emerald-600 dark:text-emerald-400" : "text-red-600 dark:text-red-400"}`, children: stagedValidity[gi] === "valid" ? "✓ Valide" : "✗ Invalide" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => submitStagedMeld(gi), disabled: busy || group.length < 3 || stagedValidity[gi] === "invalid", className: "flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-emerald-600 text-white text-xs font-bold disabled:opacity-40 hover:bg-emerald-500 active:scale-95 transition-all", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3 h-3" }),
                " Poser"
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => removeStagedGroup(gi), className: "flex items-center gap-1 px-2.5 py-1.5 rounded-lg bg-white/8 text-muted-foreground text-xs font-bold hover:bg-white/12 active:scale-95 transition-all", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" }),
                " ✕"
              ] })
            ] })
          ] }, gi)) })
        ] }),
        selected.length === 0 && staged.length === 0 && null
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GamePauseControl, { slug: "rami", gameId: id, game, remaining, totalSeconds: cfg.turn_timer_seconds, isMyTurn: !!isMyTurn, isPlayer, myUserId: profile?.id ?? null }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "rami", participants: parts }),
    dnd.drag && (() => {
      const parts2 = dnd.drag.sourceId.split(":");
      const cardNum = Number(parts2[parts2.length - 1]);
      if (!Number.isFinite(cardNum)) return null;
      return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed pointer-events-none z-[9999]", style: {
        left: dnd.drag.x - dnd.drag.ox,
        top: dnd.drag.y - dnd.drag.oy,
        width: dnd.drag.w,
        height: dnd.drag.h,
        transform: "translate3d(0,0,0) scale(1.12) rotate(-4deg)",
        transformOrigin: `${dnd.drag.ox}px ${dnd.drag.oy}px`,
        filter: "drop-shadow(0 18px 24px rgba(0,0,0,0.55)) drop-shadow(0 0 12px hsl(var(--primary)/0.55))",
        willChange: "left, top, transform",
        transition: "transform 120ms ease-out"
      }, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { c: cardNum, styleOverride: {
        width: "100%",
        height: "100%"
      } }) });
    })()
  ] });
}
export {
  RamiPage as component
};
