import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { z as Route$5, u as useAuth, b as useConfirm } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { u as useGameConnection, G as GameStateMessage, a as GameWaitingRoom, d as GameReconnectOverlay, c as GameEndScreen, b as GamePauseControl } from "./GameReconnectOverlay-DB4s6cH2.mjs";
import { u as useFastRealtime } from "./use-fast-realtime-B6ENk2Ox.mjs";
import { G as GameSocialFab } from "./GameSocialFab-DlZx4gfi.mjs";
import { P as PhoneVerifyBanner } from "./PhoneVerifyBanner-Dqrff6fy.mjs";
import { G as GameLoader } from "./GameLoader-DEMrZT6Q.mjs";
import { u as useGameConfig } from "./use-game-config-DU32XRGm.mjs";
import { s as setSfxMuted, i as isSfxMuted, u as unlockAudio, e as playClack, f as playDraw, g as playPass, h as playYourTurn, j as playWin, k as playLose } from "./game-sounds-DlupBrQp.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/canvas-confetti.mjs";
import { a2 as Plus, ag as Pause, aU as Volume2, aV as VolumeX, Q as LogOut, a$ as ChevronLeft, b as ChevronRight } from "../_libs/lucide-react.mjs";
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
const PIP_LAYOUTS = [
  [],
  // 0
  [[1, 1]],
  // 1 center
  [[0, 0], [2, 2]],
  // 2 diagonal
  [[0, 0], [1, 1], [2, 2]],
  // 3 diagonal
  [[0, 0], [0, 2], [2, 0], [2, 2]],
  // 4 corners
  [[0, 0], [0, 2], [1, 1], [2, 0], [2, 2]],
  // 5 corners + center
  [[0, 0], [1, 0], [2, 0], [0, 2], [1, 2], [2, 2]]
  // 6 two columns of 3
];
function Pips({ n, dotSize }) {
  const dots = PIP_LAYOUTS[n] || [];
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "relative w-full h-full", children: dots.map(([r, c], i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      className: "absolute rounded-full bg-[#101010]",
      style: {
        width: dotSize,
        height: dotSize,
        top: `${r === 0 ? 18 : r === 1 ? 50 : 82}%`,
        left: `${c === 0 ? 22 : c === 1 ? 50 : 78}%`,
        transform: "translate(-50%, -50%)"
      }
    },
    i
  )) });
}
function DominoTile({
  t,
  onClick,
  selected,
  w = 36,
  vertical = false,
  faceDown = false,
  highlight = false,
  draggable = false,
  onDragStart,
  onDragEnd
}) {
  const longSide = w * 2;
  const W = vertical ? w : longSide;
  const H = vertical ? longSide : w;
  const dot = Math.max(3, Math.round(w / 5.5));
  if (faceDown) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        style: { width: W, height: H },
        className: "rounded-[6px] bg-gradient-to-br from-zinc-100 to-zinc-300 shadow-md"
      }
    );
  }
  const bg = selected ? "#e9e9e9" : highlight ? "#fff7c2" : "#ffffff";
  const inner = vertical ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full flex flex-col", style: { background: bg, borderRadius: 6 }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 relative", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Pips, { n: t[0], dotSize: dot }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-px bg-[#1a1a1a]" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 relative", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Pips, { n: t[1], dotSize: dot }) })
  ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full flex", style: { background: bg, borderRadius: 6 }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 relative", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Pips, { n: t[0], dotSize: dot }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-px bg-[#1a1a1a]" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 relative", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Pips, { n: t[1], dotSize: dot }) })
  ] });
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "button",
    {
      onClick,
      disabled: !onClick && !draggable,
      draggable,
      onDragStart,
      onDragEnd,
      style: { width: W, height: H, touchAction: draggable ? "none" : void 0 },
      className: `rounded-[6px] shadow-[0_2px_4px_rgba(0,0,0,0.35)] transition-transform ${selected ? "-translate-y-1" : ""} ${onClick || draggable ? "hover:-translate-y-0.5" : ""}`,
      children: inner
    }
  );
}
function initials(name) {
  return name.trim().split(/\s+/).slice(0, 2).map((w) => w[0]).join("").toUpperCase();
}
function Avatar({ seat, side, size = 28 }) {
  const ringColor = seat?.isCurrent ? "#22c55e" : "rgba(255,255,255,0.35)";
  const name = seat?.isMe ? "Vous" : seat?.display_name || (side === "left" ? "Joueur" : "Adversaire");
  const style = { width: size, height: size, border: `2px solid ${ringColor}`, boxShadow: seat?.isCurrent ? "0 0 8px rgba(34,197,94,0.75)" : void 0 };
  if (seat?.avatar_url) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(
      "img",
      {
        src: seat.avatar_url,
        alt: name,
        width: size,
        height: size,
        loading: "lazy",
        decoding: "async",
        className: "rounded-full object-cover",
        style
      }
    );
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      className: "rounded-full flex items-center justify-center font-bold text-white/90 bg-white/10",
      style: { ...style, fontSize: Math.max(9, Math.round(size / 3)) },
      children: initials(name) || "—"
    }
  );
}
function PlayerHeader({ seat, side, size = "sm" }) {
  const name = !seat ? side === "left" ? "Vous" : "Adversaire" : seat.isMe ? "Vous" : seat.display_name || "Joueur";
  const score = seat?.score ?? 0;
  const skips = seat?.skips ?? 0;
  const maxSkips = seat?.maxSkips ?? 5;
  const isLg = size === "lg";
  const avatarSize = isLg ? 52 : 44;
  const showTimer = seat?.isCurrent && typeof seat.remaining === "number";
  const timerLow = seat && seat.remaining !== void 0 && seat.remaining <= 5;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "inline-flex flex-col items-center gap-0.5 min-w-0", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Avatar, { seat, side, size: avatarSize }),
      seat && seat.handCount > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -top-1 -right-1 min-w-[16px] h-[16px] px-1 rounded-full bg-amber-500 text-black text-[9px] font-extrabold border border-white/70 flex items-center justify-center leading-none", children: seat.handCount }),
      skips > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `absolute -bottom-1 left-1/2 -translate-x-1/2 px-1 rounded-full text-white text-[8px] font-mono font-bold whitespace-nowrap ${skips >= maxSkips - 1 ? "bg-red-600 animate-pulse" : "bg-orange-600"}`, children: [
        skips,
        "/",
        maxSkips
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-white/90 text-[11px] font-semibold truncate max-w-[90px] leading-tight text-center", children: name }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-white text-lg font-black leading-none tabular-nums", children: score }),
    showTimer && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `mt-0.5 text-[10px] font-mono font-bold tabular-nums px-1.5 py-0.5 rounded leading-none ${timerLow ? "bg-red-600 text-white animate-pulse" : "bg-black/40 text-white"}`, children: [
      seat.remaining,
      "s"
    ] })
  ] });
}
function SnakeBoard({
  board,
  leftEnd,
  rightEnd,
  canDropLeft,
  canDropRight,
  onDropLeft,
  onDropRight,
  canDropAny,
  onDropAny
}) {
  const BASE_W = 22;
  const LONG = BASE_W * 2;
  const wrapRef = reactExports.useRef(null);
  const [size, setSize] = reactExports.useState({ w: 320, h: 340 });
  reactExports.useEffect(() => {
    const el = wrapRef.current;
    if (!el) return;
    const update = () => {
      const rect = el.getBoundingClientRect();
      setSize({ w: Math.max(200, rect.width), h: Math.max(200, rect.height) });
    };
    update();
    const ro = new ResizeObserver(update);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);
  const handleDragOver = (e) => e.preventDefault();
  if (board.length === 0) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { ref: wrapRef, className: "px-2 py-2 flex items-center justify-center overflow-hidden w-full h-full", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        onDragOver: handleDragOver,
        onDrop: () => (onDropAny ?? onDropRight)?.(),
        onClick: () => {
          if (canDropAny || canDropRight) (onDropAny ?? onDropRight)?.();
        },
        className: `rounded-2xl flex items-center justify-center text-white/50 text-xs transition-colors w-full h-full ${canDropAny || canDropRight ? "bg-amber-400/10 ring-2 ring-amber-400 animate-pulse text-amber-100 font-bold" : ""}`,
        children: canDropAny || canDropRight ? "Déposez ici" : ""
      }
    ) });
  }
  const MAX_HORIZONTAL = 10;
  const tiles = board.map(({ tile }) => tile);
  const GAP = 0;
  const placed = [];
  const horiz = tiles.slice(0, MAX_HORIZONTAL);
  let cursorX = 0;
  const rowY = 0;
  for (const t of horiz) {
    const isDouble = t[0] === t[1];
    const tw = isDouble ? BASE_W : LONG;
    const th = isDouble ? LONG : BASE_W;
    const y = rowY + (LONG - th) / 2;
    placed.push({ tile: t, x: cursorX, y, vertical: isDouble, w: tw, h: th });
    cursorX += tw + GAP;
  }
  const vert = tiles.slice(MAX_HORIZONTAL);
  if (vert.length > 0 && horiz.length > 0) {
    const lastH = placed[placed.length - 1];
    const anchorCenterX = lastH.x + lastH.w / 2;
    let cursorY = lastH.y + lastH.h;
    for (const t of vert) {
      const isDouble = t[0] === t[1];
      const tw = isDouble ? LONG : BASE_W;
      const th = isDouble ? BASE_W : LONG;
      const x = anchorCenterX - tw / 2;
      placed.push({ tile: t, x, y: cursorY, vertical: !isDouble, w: tw, h: th });
      cursorY += th + GAP;
    }
  }
  const minX = Math.min(0, ...placed.map((p) => p.x));
  const maxX = Math.max(...placed.map((p) => p.x + p.w));
  const minY = Math.min(0, ...placed.map((p) => p.y));
  const maxY = Math.max(...placed.map((p) => p.y + p.h));
  for (const p of placed) {
    p.x -= minX;
    p.y -= minY;
  }
  const chainW = maxX - minX;
  const chainH = maxY - minY;
  const PAD = 16;
  const availW = Math.max(120, size.w - PAD * 2);
  const availH = Math.max(120, size.h - PAD * 2);
  const scale = Math.min(1, availW / chainW, availH / chainH);
  const renderedW = chainW * scale;
  const renderedH = chainH * scale;
  const first = placed[0];
  const last = placed[placed.length - 1];
  const lastIsVertical = placed.length > MAX_HORIZONTAL;
  const BTN = 44;
  const HALF = BTN / 2;
  const clamp = (v, min, max) => Math.min(Math.max(v, min), Math.max(min, max));
  let leftBtn = null;
  if (canDropLeft && first) {
    leftBtn = {
      x: clamp(first.x * scale - HALF - 6, HALF, renderedW - HALF),
      y: clamp((first.y + first.h / 2) * scale, HALF, renderedH - HALF)
    };
  }
  let rightBtn = null;
  if (canDropRight && last) {
    rightBtn = lastIsVertical ? {
      x: clamp((last.x + last.w / 2) * scale, HALF, renderedW - HALF),
      y: clamp((last.y + last.h) * scale + HALF + 6, HALF, renderedH - HALF)
    } : {
      x: clamp((last.x + last.w) * scale + HALF + 6, HALF, renderedW - HALF),
      y: clamp((last.y + last.h / 2) * scale, HALF, renderedH - HALF)
    };
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { ref: wrapRef, className: "relative w-full h-full overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "absolute",
      style: {
        left: "50%",
        top: "50%",
        width: renderedW,
        height: renderedH,
        transform: "translate(-50%, -50%)"
      },
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "div",
          {
            className: "relative",
            style: {
              width: chainW,
              height: chainH,
              transform: `scale(${scale})`,
              transformOrigin: "top left"
            },
            children: placed.map((p, idx) => {
              const key = `${idx}-${Math.min(p.tile[0], p.tile[1])}-${Math.max(p.tile[0], p.tile[1])}`;
              return /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "absolute",
                  style: {
                    left: p.x,
                    top: p.y,
                    transition: "left 320ms cubic-bezier(0.22,1,0.36,1), top 320ms cubic-bezier(0.22,1,0.36,1)",
                    willChange: "left, top"
                  },
                  children: /* @__PURE__ */ jsxRuntimeExports.jsx(DominoTile, { t: p.tile, w: BASE_W, vertical: p.vertical })
                },
                key
              );
            })
          }
        ),
        leftBtn && /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => onDropLeft?.(),
            onDragOver: handleDragOver,
            onDrop: () => onDropLeft?.(),
            className: "absolute z-20 -translate-x-1/2 -translate-y-1/2 rounded-full bg-amber-500 shadow-lg flex items-center justify-center gap-0.5 animate-pulse ring-2 ring-white/80",
            style: { left: leftBtn.x, top: leftBtn.y, width: BTN, height: BTN },
            title: `Placer à gauche (${leftEnd})`,
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronLeft, { className: "w-4 h-4 text-white", strokeWidth: 3 }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-white text-xs font-black tabular-nums", children: leftEnd })
            ]
          }
        ),
        rightBtn && /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => onDropRight?.(),
            onDragOver: handleDragOver,
            onDrop: () => onDropRight?.(),
            className: "absolute z-20 -translate-x-1/2 -translate-y-1/2 rounded-full bg-amber-500 shadow-lg flex items-center justify-center gap-0.5 animate-pulse ring-2 ring-white/80",
            style: { left: rightBtn.x, top: rightBtn.y, width: BTN, height: BTN },
            title: `Placer à droite (${rightEnd})`,
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-white text-xs font-black tabular-nums", children: rightEnd }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-4 h-4 text-white", strokeWidth: 3 })
            ]
          }
        )
      ]
    }
  ) });
}
function DominoTable({
  seats,
  maxPlayers,
  meSlot,
  board,
  leftEnd,
  rightEnd,
  stockSize,
  targetScore,
  statusMessage,
  statusType,
  canDropLeft,
  canDropRight,
  onDropLeft,
  onDropRight,
  canDropAny,
  onDropAny,
  seed,
  noMoveSlot
}) {
  const base = meSlot ?? 0;
  const opponents = [];
  for (let i = 1; i < Math.max(maxPlayers, 1); i++) {
    const s = seats.find((x) => x.slot === (base + i) % Math.max(maxPlayers, 1));
    if (s) opponents.push(s);
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative w-full h-full flex flex-col overflow-hidden",
      style: {
        background: "linear-gradient(180deg,#0b3a86 0%,#0f4aa8 60%,#1257c2 100%)",
        minHeight: 260
      },
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "div",
          {
            className: "relative px-3 pt-2 pb-2",
            style: { background: "linear-gradient(180deg,#071634 0%,#0b214b 100%)" },
            children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-[1fr_auto_1fr] items-start gap-2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-start justify-start relative", children: opponents.length >= 2 ? /* @__PURE__ */ jsxRuntimeExports.jsx(PlayerHeader, { seat: opponents[0], side: "left", size: "lg" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", {}) }),
              targetScore ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center shrink-0 pt-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-white text-2xl font-black leading-none tabular-nums tracking-tight", children: targetScore }),
                /* @__PURE__ */ jsxRuntimeExports.jsx(
                  "div",
                  {
                    className: "mt-1 w-6 h-6 rounded-full bg-white text-[#c0392b] text-[9px] font-extrabold flex items-center justify-center shadow",
                    style: { border: "2px solid #c0392b" },
                    children: "CO"
                  }
                )
              ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", {}),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-start justify-end relative", children: (opponents.length >= 2 ? opponents.slice(1, 2) : opponents.slice(0, 1)).map((op) => /* @__PURE__ */ jsxRuntimeExports.jsx(PlayerHeader, { seat: op, side: "right", size: "lg" }, op.user_id)) })
            ] })
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-h-0 relative", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
          SnakeBoard,
          {
            board,
            leftEnd,
            rightEnd,
            canDropLeft: !!canDropLeft,
            canDropRight: !!canDropRight,
            onDropLeft,
            onDropRight,
            canDropAny,
            onDropAny,
            seed
          }
        ) }),
        statusMessage && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 pb-3 flex justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `px-5 py-3 rounded-xl text-center font-bold text-sm shadow-lg max-w-[90%] ${statusType === "blocked" ? "bg-red-600/90 text-white animate-pulse" : statusType === "pass" ? "bg-orange-500/90 text-white" : "bg-[#0a1a3e]/90 text-white"}`, children: statusMessage }) })
      ]
    }
  );
}
function ordinalFr(n) {
  if (n === 1) return "1ère";
  return `${n}ème`;
}
function DominoRoundBreak({
  lastRound,
  scores,
  targetScore,
  breakUntil,
  participants,
  roundNumber
}) {
  const endedRound = Number(
    lastRound?.round ?? (typeof roundNumber === "number" ? roundNumber : 1)
  ) || 1;
  const initialRemaining = Math.max(0, Math.round((new Date(breakUntil).getTime() - serverNow()) / 1e3));
  const [remaining, setRemaining] = reactExports.useState(initialRemaining);
  reactExports.useEffect(() => {
    const tick = () => {
      const ms = new Date(breakUntil).getTime() - serverNow();
      setRemaining(Math.max(0, Math.round(ms / 1e3)));
    };
    tick();
    const t = setInterval(tick, 250);
    return () => clearInterval(t);
  }, [breakUntil]);
  const winnerKey = lastRound.winner_uid || (lastRound.winner_slot != null ? `bot_${lastRound.winner_slot}` : null);
  const isTie = !winnerKey;
  const winnerParticipant = participants.find((p) => p.user_id === winnerKey) || (lastRound.winner_slot != null ? participants.find((p) => p.slot === lastRound.winner_slot) : null);
  const winnerName = winnerParticipant?.display_name || "Match nul";
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[70] bg-black/60 backdrop-blur-sm flex items-center justify-center p-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "w-full max-w-md rounded-3xl p-5 shadow-2xl animate-in zoom-in-95",
      style: { background: "#15448e", border: "4px solid #f5c542" },
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center text-white", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("h2", { className: "text-2xl font-extrabold tracking-wide", children: [
            ordinalFr(endedRound),
            " Manche terminée"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `mt-1 text-sm font-bold ${isTie ? "text-amber-200" : "text-emerald-200"}`, children: isTie ? "🤝 Match nul — égalité des points" : `🏆 Victoire : ${winnerName}` }),
          lastRound.blocked && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] mt-1 opacity-90", children: isTie ? "Aucun domino jouable pour personne, nouvelle manche relancée" : "Blocage : personne ne peut jouer — victoire au moins de points" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs mt-1 opacity-90", children: [
            "Note gagnante : ",
            targetScore
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `mt-4 grid gap-2 text-white text-center ${participants.length >= 3 ? "grid-cols-3" : "grid-cols-2"}`, children: participants.map((p) => {
          const total = Number(scores?.[p.user_id] || 0);
          const pips = lastRound.hand_pips?.[p.user_id] ?? 0;
          const tiles = lastRound.final_hands?.[p.user_id] || [];
          const isWinner = p.user_id === winnerKey;
          const roundScore = isWinner ? lastRound.round_score : 0;
          return /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "div",
            {
              className: "px-1 space-y-2 rounded-xl py-2",
              style: { background: isWinner ? "rgba(74,222,128,0.15)" : "rgba(0,0,0,0.15)" },
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[12px] font-extrabold truncate", children: [
                  p.display_name,
                  isWinner ? " 🏆" : ""
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-0.5 justify-center min-h-[28px]", children: tiles.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] opacity-70", children: "(vide)" }) : tiles.map((t, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(DominoTile, { t, w: 12 }, i)) }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold opacity-90 uppercase", children: "Pts main" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold leading-none", children: pips }),
                isWinner && roundScore > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-emerald-200", children: [
                  "+",
                  roundScore,
                  " ce tour"
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold opacity-90 uppercase", children: "Total" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xl font-extrabold leading-none", style: { color: isWinner ? "#4ade80" : "#fbbf24" }, children: total })
              ]
            },
            p.user_id
          );
        }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-5 flex justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "px-6 py-2.5 rounded-full text-[#7a2e0a] font-extrabold shadow-lg",
            style: { background: "linear-gradient(180deg,#fbbf24,#f59e0b)", border: "2px solid #f5c542" },
            children: [
              "Manche suivante (",
              remaining,
              "s)"
            ]
          }
        ) })
      ]
    }
  ) });
}
function useDominoSounds(opts) {
  const { game, parts, myUserId } = opts;
  const prevBoardLen = reactExports.useRef(0);
  const prevStockSize = reactExports.useRef(0);
  const prevPasses = reactExports.useRef(0);
  const prevTurn = reactExports.useRef(null);
  const prevStatus = reactExports.useRef("open");
  const prevPhase = reactExports.useRef("");
  const started = reactExports.useRef(false);
  const mySlot = parts.find((p) => p.user_id === myUserId)?.slot;
  reactExports.useEffect(() => {
    if (!game) return;
    if (isSfxMuted()) {
      const board2 = game?.state?.board;
      const boardLen2 = Array.isArray(board2) ? board2.length : 0;
      const stockSize2 = (game?.state?.stock || []).length;
      const passes2 = Number(game?.state?.passes || 0);
      const currentTurn2 = game?.current_turn ?? null;
      const status2 = game?.status ?? "open";
      const phase2 = game?.state?.phase ?? "";
      prevBoardLen.current = boardLen2;
      prevStockSize.current = stockSize2;
      prevPasses.current = passes2;
      prevTurn.current = currentTurn2;
      prevStatus.current = status2;
      prevPhase.current = phase2;
      return;
    }
    unlockAudio();
    const board = game?.state?.board;
    const boardLen = Array.isArray(board) ? board.length : 0;
    const stockSize = (game?.state?.stock || []).length;
    const passes = Number(game?.state?.passes || 0);
    const currentTurn = game?.current_turn ?? null;
    const status = game?.status ?? "open";
    const phase = game?.state?.phase ?? "";
    if (!started.current) {
      prevBoardLen.current = boardLen;
      prevStockSize.current = stockSize;
      prevPasses.current = passes;
      prevTurn.current = currentTurn;
      prevStatus.current = status;
      prevPhase.current = phase;
      started.current = true;
      return;
    }
    if (boardLen > prevBoardLen.current && phase === "play" && status === "playing") {
      playClack();
    }
    if (stockSize < prevStockSize.current && status === "playing") {
      playDraw();
    }
    if (passes > prevPasses.current && status === "playing") {
      playPass();
    }
    if (currentTurn !== prevTurn.current && mySlot === currentTurn && status === "playing" && phase === "play") {
      playYourTurn();
    }
    if (status === "finished" && prevStatus.current === "playing") {
      const winnerId = game?.winner;
      const winnerSlot = game?.state?.winner_slot;
      const iWon = winnerId && winnerId === myUserId || winnerSlot != null && winnerSlot === mySlot;
      if (iWon) playWin();
      else playLose();
    }
    prevBoardLen.current = boardLen;
    prevStockSize.current = stockSize;
    prevPasses.current = passes;
    prevTurn.current = currentTurn;
    prevStatus.current = status;
    prevPhase.current = phase;
  }, [
    game?.state?.board,
    game?.state?.stock,
    game?.state?.passes,
    game?.current_turn,
    game?.status,
    game?.state?.phase,
    game?.winner,
    game?.state?.winner_slot,
    parts,
    myUserId
  ]);
}
function readBoardTile(entry) {
  const rawTile = Array.isArray(entry) ? entry : entry?.tile;
  if (!Array.isArray(rawTile) || rawTile.length !== 2) return null;
  const a = Number(rawTile[0]);
  const b = Number(rawTile[1]);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return null;
  return [a, b];
}
function solveDominoTrail(tiles, start, end) {
  if (tiles.length === 0) return [];
  const adjacency = /* @__PURE__ */ new Map();
  const degree = /* @__PURE__ */ new Map();
  tiles.forEach(([a, b], index) => {
    adjacency.set(a, [...adjacency.get(a) ?? [], {
      to: b,
      index
    }]);
    adjacency.set(b, [...adjacency.get(b) ?? [], {
      to: a,
      index
    }]);
    degree.set(a, (degree.get(a) ?? 0) + 1);
    degree.set(b, (degree.get(b) ?? 0) + 1);
  });
  if ((degree.get(start) ?? 0) === 0) return null;
  const seen = /* @__PURE__ */ new Set();
  const pending = [start];
  while (pending.length > 0) {
    const node = pending.pop();
    if (node === void 0 || seen.has(node)) continue;
    seen.add(node);
    (adjacency.get(node) ?? []).forEach(({
      to
    }) => {
      if (!seen.has(to)) pending.push(to);
    });
  }
  if ([...degree.entries()].some(([, value]) => value > 0) && [...degree.keys()].some((node) => !seen.has(node))) return null;
  const oddNodes = [...degree.entries()].filter(([, value]) => value % 2 === 1).map(([node]) => node);
  if (end !== void 0) {
    if (start === end) {
      if (oddNodes.length !== 0) return null;
    } else if (oddNodes.length !== 2 || !oddNodes.includes(start) || !oddNodes.includes(end)) {
      return null;
    }
  } else if (oddNodes.length === 2 && !oddNodes.includes(start)) {
    return null;
  } else if (oddNodes.length !== 0 && oddNodes.length !== 2) {
    return null;
  }
  const used = /* @__PURE__ */ new Set();
  const cursors = /* @__PURE__ */ new Map();
  const stack = [{
    node: start
  }];
  const edges = [];
  while (stack.length > 0) {
    const top = stack[stack.length - 1];
    const list = adjacency.get(top.node) ?? [];
    let cursor = cursors.get(top.node) ?? 0;
    while (cursor < list.length && used.has(list[cursor].index)) cursor += 1;
    cursors.set(top.node, cursor);
    const next = list[cursor];
    if (next) {
      used.add(next.index);
      cursors.set(top.node, cursor + 1);
      stack.push({
        node: next.to,
        edge: {
          from: top.node,
          to: next.to
        }
      });
    } else {
      const done = stack.pop();
      if (done?.edge) edges.push(done.edge);
    }
  }
  edges.reverse();
  if (edges.length !== tiles.length) return null;
  if (end !== void 0 && edges[edges.length - 1]?.to !== end) return null;
  return edges.map(({
    from,
    to
  }) => [from, to]);
}
function reverseTrail(trail) {
  return [...trail].reverse().map(([a, b]) => [b, a]);
}
function fallbackNormalize(rawTiles, expectedLeft, expectedRight) {
  const chain = [];
  let leftEnd = null;
  let rightEnd = null;
  for (const tile of rawTiles) {
    const [a, b] = tile;
    if (chain.length === 0) {
      const firstTile = Number.isFinite(expectedLeft) && b === expectedLeft && a !== expectedLeft ? [b, a] : [a, b];
      chain.push(firstTile);
      leftEnd = firstTile[0];
      rightEnd = firstTile[1];
    } else if (a === rightEnd) {
      chain.push([a, b]);
      rightEnd = b;
    } else if (b === rightEnd) {
      chain.push([b, a]);
      rightEnd = a;
    } else if (b === leftEnd) {
      chain.unshift([a, b]);
      leftEnd = a;
    } else if (a === leftEnd) {
      chain.unshift([b, a]);
      leftEnd = b;
    } else {
      chain.push([a, b]);
    }
  }
  if (Number.isFinite(expectedRight) && chain.at(-1)?.[1] !== expectedRight) {
    const reversed = reverseTrail(chain);
    if ((!Number.isFinite(expectedLeft) || reversed[0]?.[0] === expectedLeft) && reversed.at(-1)?.[1] === expectedRight) {
      return reversed;
    }
  }
  return chain;
}
function normalizeDominoBoard(rawBoard, serverLeft, serverRight) {
  if (!Array.isArray(rawBoard) || rawBoard.length === 0) {
    return {
      board: [],
      leftEnd: null,
      rightEnd: null
    };
  }
  const expectedLeft = typeof serverLeft === "number" ? serverLeft : Number(serverLeft);
  const expectedRight = typeof serverRight === "number" ? serverRight : Number(serverRight);
  const hasExpectedLeft = Number.isFinite(expectedLeft);
  const hasExpectedRight = Number.isFinite(expectedRight);
  const rawTiles = rawBoard.map(readBoardTile).filter((tile) => tile !== null);
  if (rawTiles.length === 0) return {
    board: [],
    leftEnd: null,
    rightEnd: null
  };
  let trail = null;
  if (hasExpectedLeft) {
    trail = solveDominoTrail(rawTiles, expectedLeft, hasExpectedRight ? expectedRight : void 0);
  }
  if (!trail && hasExpectedRight) {
    const reversed = solveDominoTrail(rawTiles, expectedRight, hasExpectedLeft ? expectedLeft : void 0);
    if (reversed) trail = reverseTrail(reversed);
  }
  if (!trail) {
    const degree = /* @__PURE__ */ new Map();
    rawTiles.forEach(([a, b]) => {
      degree.set(a, (degree.get(a) ?? 0) + 1);
      degree.set(b, (degree.get(b) ?? 0) + 1);
    });
    const starts = [.../* @__PURE__ */ new Set([rawTiles[0][0], rawTiles[0][1], ...[...degree.entries()].filter(([, value]) => value % 2 === 1).map(([pip]) => pip), ...[...degree.keys()]])];
    for (const start of starts) {
      trail = solveDominoTrail(rawTiles, start) ?? null;
      if (trail) break;
    }
  }
  const normalized = trail && trail.length === rawTiles.length ? trail : fallbackNormalize(rawTiles, hasExpectedLeft ? expectedLeft : void 0, hasExpectedRight ? expectedRight : void 0);
  const leftEnd = normalized[0]?.[0] ?? null;
  const rightEnd = normalized[normalized.length - 1]?.[1] ?? null;
  return {
    board: normalized.map((tile) => ({
      tile,
      flipped: false
    })),
    leftEnd,
    rightEnd
  };
}
function DominoPage() {
  const {
    id
  } = Route$5.useParams();
  const {
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const [soundOn, setSoundOn] = reactExports.useState(!isSfxMuted());
  const navigate = useNavigate();
  const confirm = useConfirm();
  const {
    game,
    parts,
    reload
  } = useFastRealtime({
    gameTable: "domino_games",
    participantTable: "domino_participants",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile
  });
  const [selectedTile, setSelectedTile] = reactExports.useState(null);
  const [busy, setBusy] = reactExports.useState(false);
  const [remoteNoMoveSlot, setRemoteNoMoveSlot] = reactExports.useState(null);
  const noMoveChRef = reactExports.useRef(null);
  const passAttemptedRef = reactExports.useRef(false);
  const [handAvail, setHandAvail] = reactExports.useState(190);
  reactExports.useEffect(() => {
    const update = () => {
      const vw = typeof window !== "undefined" ? window.innerWidth : 360;
      setHandAvail(Math.max(140, vw - 170));
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("orientationchange", update);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("orientationchange", update);
    };
  }, []);
  useDominoSounds({
    game,
    parts,
    myUserId: profile?.id
  });
  const {
    isConnected,
    isReconnecting,
    retry
  } = useGameConnection({
    onReconnect: reload
  });
  const cfg = useGameConfig("domino");
  const [remaining, setRemaining] = reactExports.useState(cfg.turn_timer_seconds);
  const phase = game?.state?.phase;
  const isRoundTransition = phase === "reveal" || phase === "break";
  reactExports.useEffect(() => {
    if (!game || game.status !== "playing") {
      setRemaining(cfg.turn_timer_seconds);
      return;
    }
    if (phase === "reveal" || phase === "break") {
      const target = phase === "reveal" ? game.state?.reveal_until : game.state?.break_until;
      if (!target) return;
      const delay = Math.max(0, new Date(target).getTime() - serverNow()) + 250;
      const t2 = setTimeout(() => {
        supabase.rpc("domino_tick", {
          _game_id: id
        });
      }, delay);
      return () => clearTimeout(t2);
    }
    if (!game.turn_deadline) {
      setRemaining(cfg.turn_timer_seconds);
      return;
    }
    let fired = false;
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      const s = Math.max(0, Math.ceil(ms / 1e3));
      setRemaining(s);
      if (s === 0 && !fired) {
        fired = true;
        supabase.rpc("domino_tick", {
          _game_id: id
        });
      }
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, phase, game?.state?.reveal_until, game?.state?.break_until, id, cfg.turn_timer_seconds, game]);
  reactExports.useEffect(() => {
    const think = game?.state?.bot_think_until;
    if (!think || game?.status !== "playing") return;
    const ms = new Date(think).getTime() - serverNow();
    const delay = Math.max(0, ms) + 50;
    const t = setTimeout(() => {
      supabase.rpc("domino_tick", {
        _game_id: id
      });
    }, delay);
    return () => clearTimeout(t);
  }, [game?.state?.bot_think_until, game?.status, id]);
  const me = parts.find((p) => p.user_id === profile?.id);
  const isPlayer = !!me;
  const isMyTurn = game && me && game.current_turn === me.slot && game.status === "playing" && !isRoundTransition;
  const myHand = game?.state?.hands?.[String(me?.slot)] || [];
  const handCols = myHand.length === 0 ? 0 : Math.max(7, Math.min(myHand.length, 10));
  const handTileW = Math.max(13, Math.min(28, Math.floor(handAvail / handCols) - 4));
  const normalizedBoard = normalizeDominoBoard(game?.state?.board || [], game?.state?.left_end, game?.state?.right_end);
  const board = normalizedBoard.board;
  const leftEnd = normalizedBoard.leftEnd;
  const rightEnd = normalizedBoard.rightEnd;
  const stockSize = (game?.state?.stock || []).length;
  const firstTileRule = game?.state?.first_tile_rule === "under6" || game?.first_tile_rule === "under6" ? "under6" : "libre";
  const serverPlayableTiles = game?.state?.playable_tiles || [];
  const tileMatches = reactExports.useCallback((t) => {
    if (serverPlayableTiles.length > 0 || game?.state && "playable_tiles" in game.state) {
      const idx = myHand.indexOf(t);
      return serverPlayableTiles.includes(idx);
    }
    if (board.length === 0) {
      const fd = game?.state?.first_move_double;
      if (typeof fd === "number") return t[0] === fd && t[1] === fd;
      if (firstTileRule === "under6") return t[0] + t[1] < 6;
      return true;
    }
    return t[0] === leftEnd || t[1] === leftEnd || t[0] === rightEnd || t[1] === rightEnd;
  }, [board.length, game?.state?.first_move_double, leftEnd, rightEnd, firstTileRule, serverPlayableTiles, myHand]);
  const canPlay = myHand.some(tileMatches);
  const drawMode = game?.state?.draw_mode === "without" ? "without" : "with";
  const noMove = !!(isMyTurn && board.length > 0 && !canPlay && (drawMode === "without" || stockSize === 0));
  const passSlot = game?.state?.last_pass_by;
  const passCount = Number(game?.state?.passes) || 0;
  const activePlayers = parts.filter((p) => !p.forfeited).length;
  const isBlocked = passCount >= activePlayers && activePlayers > 0;
  const passPart = typeof passSlot === "number" ? parts.find((p) => p.slot === passSlot) : null;
  const oppNoMove = !!(!isMyTurn && passSlot !== void 0 && passSlot !== me?.slot);
  const draw = async () => {
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("domino_play_and_bot", {
        _game_id: id,
        _move: {
          action: "draw"
        }
      });
      if (error) throw error;
      playDraw();
    } catch (e) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  };
  const pass = async (opts) => {
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("domino_play_and_bot", {
        _game_id: id,
        _move: {
          action: "pass"
        }
      });
      if (error) throw error;
      playPass();
    } catch (e) {
    } finally {
      setBusy(false);
    }
  };
  reactExports.useEffect(() => {
    if (!id) return;
    const ch = supabase.channel(`domino-nomove-${id}`).on("broadcast", {
      event: "no_move"
    }, (payload) => {
      const {
        slot
      } = payload.payload || {};
      if (typeof slot === "number") setRemoteNoMoveSlot(slot);
    }).on("broadcast", {
      event: "no_move_clear"
    }, () => {
      setRemoteNoMoveSlot(null);
    }).subscribe();
    noMoveChRef.current = ch;
    return () => {
      supabase.removeChannel(ch);
      noMoveChRef.current = null;
    };
  }, [id]);
  reactExports.useEffect(() => {
    if (!noMoveChRef.current || me?.slot === void 0) return;
    if (noMove) {
      noMoveChRef.current.send({
        type: "broadcast",
        event: "no_move",
        payload: {
          slot: me.slot
        }
      });
    } else {
      noMoveChRef.current.send({
        type: "broadcast",
        event: "no_move_clear",
        payload: {
          slot: me.slot
        }
      });
    }
  }, [noMove, me?.slot]);
  reactExports.useEffect(() => {
    if (!noMove) {
      passAttemptedRef.current = false;
      return;
    }
    if (busy || passAttemptedRef.current) return;
    const t = setTimeout(() => {
      passAttemptedRef.current = true;
      pass();
    }, 2e3);
    return () => clearTimeout(t);
  }, [noMove, busy, id]);
  const forfeit = async () => {
    const stake = Number(game?.stake) || 0;
    if (game?.status !== "open") {
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
    await supabase.rpc("domino_forfeit", {
      _game_id: id
    });
    navigate({
      to: "/jeux"
    });
  };
  if (!game) return /* @__PURE__ */ jsxRuntimeExports.jsx(GameLoader, {});
  if (game.status === "cancelled") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(GameStateMessage, { state: "cancelled", gameLabel: "Domino", slug: "domino" });
  }
  if (game.status === "open") {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-3 py-3 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameWaitingRoom, { isTournament: !!game.tournament_match_id, slug: "domino", gameLabel: `Domino · ${game.max_players} joueurs`, parts, maxPlayers: game.max_players, stake: Number(game.stake) || 0, pot: Number(game.pot) || 0, roomCode: game.is_private ? game.room_code : null, shareSlug: "domino", meUserId: profile?.id, isParticipant: !!me, createdAt: game.created_at, onQuit: forfeit, onToggleReady: async (ready) => {
        const {
          error
        } = await supabase.rpc("domino_set_ready", {
          _game_id: id,
          _ready: ready
        });
        if (error) toast.error(error.message);
      } }),
      (isAdmin || Number(game.stake) === 0 && !!me) && parts.length < game.max_players && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
        const {
          error
        } = await supabase.rpc("domino_add_bot", {
          _game_id: id,
          _bot_name: "Bot"
        });
        if (error) toast.error(error.message);
        else toast.success("Bot ajouté");
      }, className: "w-full px-4 py-2.5 rounded-2xl bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 shadow-sm", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Ajouter un bot"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "domino", participants: parts })
    ] });
  }
  const draggedTile = selectedTile !== null ? myHand[selectedTile] : null;
  const canDropLeft = !!(isMyTurn && draggedTile && (board.length === 0 ? tileMatches(draggedTile) : draggedTile[0] === leftEnd || draggedTile[1] === leftEnd));
  const canDropRight = !!(isMyTurn && draggedTile && (board.length === 0 ? tileMatches(draggedTile) : draggedTile[0] === rightEnd || draggedTile[1] === rightEnd));
  const canDropAny = !!(isMyTurn && draggedTile && tileMatches(draggedTile));
  const playSide = async (side, tileIndex = selectedTile) => {
    if (tileIndex === null || busy) return;
    const tile = myHand[tileIndex];
    if (!tile || !tileMatches(tile)) return;
    setBusy(true);
    try {
      const move = side === "auto" ? {
        action: "play",
        tile
      } : {
        action: "play",
        tile,
        side
      };
      const {
        error
      } = await supabase.rpc("domino_play_and_bot", {
        _game_id: id,
        _move: move
      });
      if (error) throw error;
      playClack();
      setSelectedTile(null);
    } catch (e) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-md mx-auto px-2 py-1 flex flex-col gap-1 h-full overflow-hidden overscroll-none", style: {
    background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.05) 0%, transparent 70%)"
  }, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameReconnectOverlay, { isConnected, isReconnecting, onRetry: retry }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-baseline gap-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] uppercase text-muted-foreground tracking-wider", children: "Au gagnant" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-extrabold truncate", children: [
          Math.round(Number(game.pot) * (100 - (Number(game.commission_pct) || 10)) / 100).toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      !me ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1", children: "Spectateur" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
        parts.some((p) => p.is_bot) && game.status === "playing" && !game.paused && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
          const {
            error
          } = await supabase.rpc("game_request_pause", {
            _slug: "domino",
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
          setSfxMuted(m);
        }, className: "w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition", children: soundOn ? /* @__PURE__ */ jsxRuntimeExports.jsx(Volume2, { className: "w-3 h-3" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(VolumeX, { className: "w-3 h-3" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: forfeit, className: "px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-2.5 h-2.5" }),
          " Quitter"
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyBanner, { stake: Number(game.stake) || 0, phoneVerified: !!profile?.phone_verified }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-h-0 flex flex-col", children: /* @__PURE__ */ jsxRuntimeExports.jsx(DominoTable, { seats: parts.map((p) => ({
      user_id: p.user_id,
      display_name: p.display_name,
      avatar_url: p.avatar_url,
      slot: p.slot,
      handCount: game.state?.hands?.[String(p.slot)]?.length || 0,
      isCurrent: game.current_turn === p.slot && game.status === "playing",
      remaining: game.current_turn === p.slot ? remaining : void 0,
      isMe: p.user_id === profile?.id,
      forfeited: p.forfeited,
      score: Number(game.scores?.[p.user_id] || 0),
      skips: Number(game.turn_skips?.[p.user_id] || 0),
      maxSkips: Number(cfg.max_turn_skips) || 5
    })), maxPlayers: game.max_players, meSlot: me?.slot ?? null, board: isRoundTransition ? [] : board, leftEnd: isRoundTransition ? null : leftEnd, rightEnd: isRoundTransition ? null : rightEnd, stockSize, targetScore: Number(game.target_score) || void 0, seed: id, statusMessage: (() => {
      if (game.status !== "playing") return void 0;
      const passName = passPart ? passPart.user_id === profile?.id ? "Vous" : passPart.display_name : null;
      const currentPart = parts.find((p) => p.slot === game.current_turn);
      const currentName = currentPart ? currentPart.user_id === profile?.id ? "Vous" : currentPart.display_name : null;
      if (isBlocked) return "🚫 Domino bloqué ! Fin de la manche";
      if (noMove) return "Aucun domino jouable — vous passez votre tour";
      if (oppNoMove && passName) return `${passName} passe son tour`;
      if (isMyTurn) return canPlay ? "À vous de jouer" : drawMode === "with" && stockSize > 0 ? "Piochez pour continuer" : "Aucun domino jouable — passez";
      if (currentName) return `Tour de ${currentName}…`;
      return void 0;
    })(), statusType: (() => {
      if (game.status !== "playing") return void 0;
      if (isBlocked) return "blocked";
      if (noMove || oppNoMove && passSlot !== me?.slot) return "pass";
      return void 0;
    })(), noMoveSlot: null, canDropLeft, canDropRight, canDropAny, onDropAny: () => {
      if (canDropAny) playSide("auto");
    }, onDropLeft: () => {
      if (canDropLeft) playSide("left");
    }, onDropRight: () => {
      if (canDropRight) playSide("right");
    } }) }),
    game.status === "finished" && (() => {
      const winnerSlot = game.state?.winner_slot;
      const winnerPart = typeof winnerSlot === "number" ? parts.find((p) => p.slot === winnerSlot) : null;
      const effectiveWinnerId = game.winner_id ?? winnerPart?.user_id ?? null;
      return /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "domino", meUserId: profile?.id, winnerId: effectiveWinnerId, participants: parts, stake: Number(game.stake), pot: Number(game.pot), commissionPct: Number(game.commission_pct) || 10, onReplay: async () => {
        const hadBots = parts.some((p) => p.is_bot);
        const newId = await (async () => {
          if (hadBots) {
            const {
              data,
              error
            } = await supabase.rpc("domino_create", {
              _stake: Number(game.stake) || 0,
              _max: game.max_players,
              _private: true,
              _mode: game.state?.target_score ? "points" : "classic",
              _commission: Number(game.commission_pct) || 10,
              _target_score: Number(game.target_score) || 0,
              _draw_mode: game.state?.draw_mode === "without" ? "without" : "with",
              _first_tile_rule: game.first_tile_rule === "under6" ? "under6" : "libre"
            });
            if (error) {
              toast.error(error.message);
              return null;
            }
            const id2 = data;
            const botsNeeded = Math.max(0, Number(game.max_players) - 1);
            for (let i = 0; i < botsNeeded; i++) {
              await supabase.rpc("domino_add_bot", {
                _game_id: id2,
                _bot_name: `Bot ${i + 1}`
              });
            }
            await supabase.rpc("domino_set_ready", {
              _game_id: id2,
              _ready: true
            });
            return id2;
          } else {
            const {
              data,
              error
            } = await supabase.rpc("domino_create", {
              _stake: Number(game.stake) || 0,
              _max: game.max_players,
              _private: !!game.is_private,
              _mode: game.state?.target_score ? "points" : "classic",
              _commission: Number(game.commission_pct) || 10,
              _target_score: Number(game.target_score) || 0,
              _draw_mode: game.state?.draw_mode === "without" ? "without" : "with",
              _first_tile_rule: game.first_tile_rule === "under6" ? "under6" : "libre"
            });
            if (error) {
              toast.error(error.message);
              return null;
            }
            return data;
          }
        })();
        if (newId) {
          refreshProfile();
          navigate({
            to: "/jeux/domino/$id",
            params: {
              id: newId
            }
          });
        }
      }, extra: Number(game.target_score) > 0 && game.scores ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-left rounded-xl bg-secondary/50 p-3 space-y-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] uppercase text-muted-foreground tracking-wider font-bold", children: [
          "Scores (objectif ",
          game.target_score,
          ")"
        ] }),
        parts.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between text-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: p.display_name }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-mono font-bold", children: [
            Number(game.scores?.[p.user_id] || 0),
            " pts"
          ] })
        ] }, p.user_id))
      ] }) : void 0 });
    })(),
    game.status === "playing" && isRoundTransition && game.state?.last_round && game.state?.break_until && /* @__PURE__ */ jsxRuntimeExports.jsx(DominoRoundBreak, { lastRound: game.state.last_round, scores: game.scores || {}, targetScore: Number(game.target_score) || 0, breakUntil: game.state.break_until, participants: parts, roundNumber: Number(game.state?.round ?? 1) }),
    me && game.status === "playing" && !isRoundTransition && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1.5 shrink-0 relative", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-end gap-2 pb-1 px-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(PlayerHeader, { seat: {
          user_id: me.user_id,
          display_name: me.display_name,
          avatar_url: me.avatar_url,
          slot: me.slot,
          handCount: myHand.length,
          isCurrent: isMyTurn,
          remaining: isMyTurn ? remaining : void 0,
          isMe: true,
          score: Number(game.scores?.[me.user_id] || 0),
          skips: Number(game.turn_skips?.[me.user_id] || 0),
          maxSkips: Number(cfg.max_turn_skips) || 5
        }, side: "left", size: "lg" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid flex-1 gap-1", style: {
          gridTemplateColumns: `repeat(${handCols}, minmax(0, 1fr))`
        }, children: myHand.map((t, i) => {
          const playable = isMyTurn && tileMatches(t);
          const canL = board.length > 0 && (t[0] === leftEnd || t[1] === leftEnd);
          const canR = board.length > 0 && (t[0] === rightEnd || t[1] === rightEnd);
          const needsChoice = playable && canL && canR;
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex justify-center ${playable ? "relative p-0.5 rounded-lg bg-amber-400/15 border-2 border-amber-400 shadow-[0_0_14px_rgba(251,191,36,0.75)] animate-pulse" : "p-0.5 border-2 border-transparent opacity-70"}`, children: [
            playable && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1.5 -right-1.5 w-3 h-3 rounded-full bg-amber-400 border border-background shadow" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(DominoTile, { t, w: handTileW, vertical: true, onClick: playable ? () => {
              if (needsChoice) {
                setSelectedTile(selectedTile === i ? null : i);
              } else {
                playSide("auto", i);
              }
            } : void 0, draggable: playable, onDragStart: () => setSelectedTile(i), onDragEnd: () => {
              setTimeout(() => setSelectedTile(null), 300);
            }, selected: selectedTile === i })
          ] }, i);
        }) })
      ] }),
      isMyTurn && !canPlay && drawMode === "with" && stockSize > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { disabled: busy, onClick: draw, className: "flex-1 py-2 rounded-full bg-secondary font-bold text-sm", children: [
        "Piocher (",
        stockSize,
        ")"
      ] }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GamePauseControl, { slug: "domino", gameId: id, game, isPlayer, myUserId: profile?.id ?? null, simplePause: parts.some((p) => p.is_bot) }),
    game.status !== "open" && /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "domino", participants: parts })
  ] });
}
export {
  DominoPage as component
};
