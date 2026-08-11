import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { U as UUID_RE } from "./game-constants-DbAkVx_H.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { C as Chess } from "../_libs/chess.js.mjs";
import { G as GameLoader } from "./GameLoader-DEMrZT6Q.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { y as Route$6, u as useAuth, b as useConfirm, B as Button } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { r as reactDomExports } from "../_libs/react-dom.mjs";
import { u as useGameConnection, G as GameStateMessage, a as GameWaitingRoom, b as GamePauseControl, c as GameEndScreen, d as GameReconnectOverlay } from "./GameReconnectOverlay-DB4s6cH2.mjs";
import { u as useGlobalGameTimer } from "./use-global-game-timer-B_Rb2H6C.mjs";
import { p as playChessCheck, a as playChessCastle, b as playChessCapture, c as playChessMove, d as playChessEnd, u as unlockAudio } from "./game-sounds-DlupBrQp.mjs";
import { i as isMuted, s as setMuted } from "./game-sounds-246YZn8C.mjs";
import { P as PhoneVerifyBanner } from "./PhoneVerifyBanner-Dqrff6fy.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/canvas-confetti.mjs";
import { a2 as Plus, ag as Pause, aU as Volume2, aV as VolumeX, Q as LogOut, aH as Flag, aW as Handshake } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
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
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "./game-ui-state-y34n01Z_.mjs";
import "./PhoneVerifyPopup-CibtDuiJ.mjs";
const FILES = ["a", "b", "c", "d", "e", "f", "g", "h"];
const PIECE_GLYPH = {
  wK: "♚",
  wQ: "♛",
  wR: "♜",
  wB: "♝",
  wN: "♞",
  wP: "♟",
  bK: "♚",
  bQ: "♛",
  bR: "♜",
  bB: "♝",
  bN: "♞",
  bP: "♟"
};
const PieceSVG = reactExports.memo(function PieceSVG2({ piece, dragging = false }) {
  const key = piece.color + piece.type.toUpperCase();
  const isWhite = piece.color === "w";
  const glyph = PIECE_GLYPH[key];
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "span",
    {
      className: "select-none pointer-events-none flex items-center justify-center w-full h-full",
      style: {
        fontSize: "88cqmin",
        lineHeight: 1,
        color: isWhite ? "#ffffff" : "#111014",
        WebkitTextStroke: isWhite ? "1.8px #0a0a0a" : "1.2px #4a3a2a",
        textShadow: isWhite ? "0 2px 3px rgba(0,0,0,0.55), 0 0 1px #000, 0 -1px 0 rgba(255,255,255,0.9)" : "0 3px 3px rgba(0,0,0,0.6), 0 -1px 0 rgba(255,255,255,0.15)",
        transform: dragging ? "translateY(-3px) scale(1.12)" : void 0,
        filter: dragging ? "drop-shadow(0 10px 14px rgba(0,0,0,0.65))" : void 0,
        transition: "transform 80ms ease-out"
      },
      children: glyph
    }
  );
});
function PromotionModal({ color, onSelect, onCancel }) {
  const pieces = ["q", "r", "b", "n"];
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm", onClick: onCancel, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-xl p-3 shadow-2xl border border-border", onClick: (e) => e.stopPropagation(), children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs font-semibold text-muted-foreground mb-2 text-center", children: "Promotion" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: pieces.map((p) => {
      const key = color + p.toUpperCase();
      return /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => onSelect(p),
          className: "w-14 h-14 rounded-lg flex items-center justify-center text-4xl hover:bg-accent transition-colors border border-border",
          style: {
            color: color === "w" ? "#ffffff" : "#111014",
            WebkitTextStroke: color === "w" ? "1.5px #0a0a0a" : "1px #4a3a2a",
            textShadow: color === "w" ? "0 2px 3px rgba(0,0,0,0.55)" : "0 2px 3px rgba(0,0,0,0.5)"
          },
          children: PIECE_GLYPH[key]
        },
        p
      );
    }) })
  ] }) });
}
const Cell = reactExports.memo(function Cell2(p) {
  const bg = p.isLight ? "#ebecd0" : "#769656";
  const dragOverBg = p.isLight ? "#f7f769" : "#bbb544";
  const highlight = p.isLastFrom || p.isLastTo ? "rgba(255, 235, 59, 0.45)" : p.isSelected ? "rgba(255, 235, 59, 0.55)" : null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      "data-square": p.square,
      onPointerDown: (e) => p.onPointerDown(p.square, e),
      onDragOver: (e) => {
        e.preventDefault();
      },
      onDragEnter: () => p.onDragEnter?.(p.square),
      onDrop: (e) => {
        e.preventDefault();
      },
      draggable: !!p.onDragStart,
      onDragStart: (e) => p.onDragStart?.(p.square, e),
      onDragEnd: p.onDragEnd,
      className: "relative",
      style: {
        background: p.isDragOver ? dragOverBg : bg,
        touchAction: "none",
        WebkitTapHighlightColor: "transparent",
        userSelect: "none",
        containerType: "size"
      },
      children: [
        highlight && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 pointer-events-none", style: { background: highlight } }),
        p.isCheck && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 pointer-events-none", style: { background: "radial-gradient(circle, rgba(220,38,38,0.65), transparent 65%)" } }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 flex items-center justify-center pointer-events-none", children: p.piece && /* @__PURE__ */ jsxRuntimeExports.jsx(PieceSVG, { piece: p.piece }) }),
        p.isTarget && !p.isCapture && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 flex items-center justify-center pointer-events-none", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-full", style: { width: "34%", height: "34%", background: "rgba(20,20,20,0.28)" } }) }),
        p.isCapture && /* @__PURE__ */ jsxRuntimeExports.jsx(
          "div",
          {
            className: "absolute inset-0 pointer-events-none",
            style: {
              background: "radial-gradient(circle, transparent 52%, rgba(20,20,20,0.35) 53%, rgba(20,20,20,0.35) 62%, transparent 63%)"
            }
          }
        ),
        p.showFile && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-0 right-1 text-[9px] font-bold opacity-70 pointer-events-none", style: { color: p.isLight ? "#769656" : "#ebecd0" }, children: p.fileLabel }),
        p.showRank && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-0 left-1 text-[9px] font-bold opacity-70 pointer-events-none", style: { color: p.isLight ? "#769656" : "#ebecd0" }, children: p.rankLabel })
      ]
    }
  );
});
function ChessBoard({ fen, myColor, onMove, lastMove, disabled }) {
  const chess = reactExports.useMemo(() => {
    try {
      return new Chess(fen);
    } catch {
      return new Chess();
    }
  }, [fen]);
  const board = reactExports.useMemo(() => chess.board(), [chess]);
  const turn = chess.turn();
  const myTurn = !disabled && turn === myColor;
  const [selected, setSelected] = reactExports.useState(null);
  const [dragOverSq, setDragOverSq] = reactExports.useState(null);
  const [pendingPromotion, setPendingPromotion] = reactExports.useState(null);
  const containerRef = reactExports.useRef(null);
  const lockRef = reactExports.useRef(false);
  const dragSqRef = reactExports.useRef(null);
  const legal = reactExports.useMemo(() => {
    if (!selected) return [];
    return chess.moves({ square: selected, verbose: true });
  }, [chess, selected]);
  const legalMap = reactExports.useMemo(() => new Map(legal.map((m) => [m.to, m])), [legal]);
  reactExports.useEffect(() => {
    setSelected(null);
    setPendingPromotion(null);
  }, [fen]);
  const kingInCheck = reactExports.useMemo(() => {
    if (!chess.inCheck()) return null;
    for (let r = 0; r < 8; r++) for (let f = 0; f < 8; f++) {
      const sq = board[r][f];
      if (sq && sq.type === "k" && sq.color === turn) return FILES[f] + (8 - r);
    }
    return null;
  }, [chess, board, turn]);
  const commitMove = reactExports.useCallback(async (from, to, promotion) => {
    if (lockRef.current) return;
    const before = new Chess(chess.fen());
    const moves = before.moves({ square: from, verbose: true });
    const targetMoves = moves.filter((m) => m.to === to);
    const needsPromotion = targetMoves.some((m) => m.promotion);
    const isPromotion = needsPromotion && !promotion;
    if (isPromotion) {
      setPendingPromotion({ from, to });
      return;
    }
    let move = null;
    try {
      move = before.move({ from, to, promotion: promotion || "q" });
    } catch {
      move = null;
    }
    if (!move) return;
    lockRef.current = true;
    setSelected(null);
    setPendingPromotion(null);
    try {
      const uci = from + to + (move.promotion ? move.promotion : "");
      await onMove(uci, move.san, before.fen());
    } finally {
      setTimeout(() => {
        lockRef.current = false;
      }, 100);
    }
  }, [chess, onMove]);
  const handlePromotionSelect = reactExports.useCallback((promotion) => {
    if (!pendingPromotion) return;
    void commitMove(pendingPromotion.from, pendingPromotion.to, promotion);
  }, [pendingPromotion, commitMove]);
  const pieceAt = reactExports.useCallback((sq) => {
    const f = FILES.indexOf(sq[0]);
    const r = 8 - Number(sq[1]);
    const cell = board[r][f];
    return cell ? { color: cell.color, type: cell.type } : null;
  }, [board]);
  const onPointerDown = reactExports.useCallback((sq, _e) => {
    if (!myTurn) return;
    if (pendingPromotion) return;
    if (selected && legalMap.has(sq)) {
      reactDomExports.flushSync(() => setSelected(null));
      void commitMove(selected, sq);
      return;
    }
    const p = pieceAt(sq);
    if (p && p.color === myColor) {
      reactDomExports.flushSync(() => setSelected(sq));
      return;
    }
    if (selected) reactDomExports.flushSync(() => setSelected(null));
  }, [myTurn, myColor, pieceAt, selected, legalMap, commitMove, pendingPromotion]);
  const onDragStart = reactExports.useCallback((sq, e) => {
    if (!myTurn) {
      e.preventDefault();
      return;
    }
    const p = pieceAt(sq);
    if (!p || p.color !== myColor) {
      e.preventDefault();
      return;
    }
    dragSqRef.current = sq;
    setSelected(sq);
    e.dataTransfer.effectAllowed = "move";
    const img = new Image();
    img.src = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxIiBoZWlnaHQ9IjEiLz4=";
    e.dataTransfer.setDragImage(img, 0, 0);
  }, [myTurn, myColor, pieceAt]);
  const onDragEnd = reactExports.useCallback((_e) => {
    dragSqRef.current = null;
    setDragOverSq(null);
  }, []);
  const onDragEnterCell = reactExports.useCallback((sq) => {
    setDragOverSq(sq);
  }, []);
  reactExports.useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const handleDrop = (e) => {
      e.preventDefault();
      const sq = e.target?.closest("[data-square]")?.getAttribute("data-square");
      setDragOverSq(null);
      if (!sq || !dragSqRef.current) return;
      if (sq === dragSqRef.current) {
        setSelected(null);
        return;
      }
      if (legalMap.has(sq)) {
        void commitMove(dragSqRef.current, sq);
      }
      setSelected(null);
      dragSqRef.current = null;
    };
    el.addEventListener("drop", handleDrop);
    return () => el.removeEventListener("drop", handleDrop);
  }, [legalMap, commitMove]);
  const flip = myColor === "b";
  const cells = [];
  for (let visRow = 0; visRow < 8; visRow++) {
    for (let visCol = 0; visCol < 8; visCol++) {
      const boardRow = flip ? 7 - visRow : visRow;
      const boardCol = flip ? 7 - visCol : visCol;
      const sq = FILES[boardCol] + (8 - boardRow);
      const cell = board[boardRow][boardCol];
      const piece = cell ? { color: cell.color, type: cell.type } : null;
      const isLight = (boardRow + boardCol) % 2 === 0;
      const isSelected = selected === sq;
      const isTarget = !!(selected && legalMap.has(sq));
      const isCapture = isTarget && !!piece;
      const isLastFrom = lastMove?.from === sq;
      const isLastTo = lastMove?.to === sq;
      const isCheck = kingInCheck === sq;
      const isDragOver = dragOverSq === sq;
      const canDrag = !!(myTurn && piece && piece.color === myColor);
      cells.push(
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          Cell,
          {
            square: sq,
            piece,
            isLight,
            isSelected,
            isTarget,
            isCapture,
            isLastFrom,
            isLastTo,
            isCheck,
            isDragOver,
            showFile: visRow === 7,
            showRank: visCol === 0,
            rankLabel: String(8 - boardRow),
            fileLabel: FILES[boardCol],
            onPointerDown,
            onDragStart: canDrag ? onDragStart : void 0,
            onDragEnd,
            onDragEnter: onDragEnterCell
          },
          sq
        )
      );
    }
  }
  reactExports.useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const prevent = (e) => {
      e.preventDefault();
    };
    el.addEventListener("touchstart", prevent, { passive: false });
    el.addEventListener("touchmove", prevent, { passive: false });
    return () => {
      el.removeEventListener("touchstart", prevent);
      el.removeEventListener("touchmove", prevent);
    };
  }, []);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "relative w-full mx-auto rounded-md overflow-hidden select-none overscroll-contain",
      style: {
        maxWidth: "min(100%, calc(100dvh - 280px))",
        aspectRatio: "1 / 1",
        boxShadow: "0 6px 20px rgba(0,0,0,0.35), inset 0 0 0 5px #3f2d1a, inset 0 0 0 7px #5a3a1a",
        background: "#5a3a1a",
        touchAction: "none",
        overscrollBehavior: "contain"
      },
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { ref: containerRef, className: "absolute inset-[7px] grid grid-cols-8 grid-rows-8", children: cells }),
        pendingPromotion && /* @__PURE__ */ jsxRuntimeExports.jsx(
          PromotionModal,
          {
            color: myColor,
            onSelect: handlePromotionSelect,
            onCancel: () => setPendingPromotion(null)
          }
        )
      ]
    }
  );
}
function fmt(ms) {
  const s = Math.max(0, Math.floor(ms / 1e3));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r.toString().padStart(2, "0")}`;
}
const PIECE_UNI = { p: "♟", n: "♞", b: "♝", r: "♜", q: "♛" };
const PlayerBar = reactExports.memo(function PlayerBar2(p) {
  const low = p.timeMs < 3e4;
  const critical = p.timeMs < 1e4;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg ${p.isTurn ? "bg-card shadow-md border border-amber-400/40" : "bg-card/80 backdrop-blur border border-border"}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "w-9 h-9 rounded-md overflow-hidden flex-shrink-0 border-2",
        style: { borderColor: p.color === "w" ? "#fafaf9" : "#1c1917" },
        children: p.avatarUrl ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: p.avatarUrl, alt: p.name, className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full flex items-center justify-center bg-muted text-sm font-bold", children: p.name.slice(0, 1).toUpperCase() })
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-semibold text-xs truncate flex items-center gap-1.5", children: [
        p.name,
        p.isTurn && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-0.5 min-h-4 flex-wrap mt-0.5", children: [
        (p.captured ?? []).slice(0, 16).map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
          "span",
          {
            className: "text-xs leading-none",
            style: {
              color: p.color === "w" ? "#1c1917" : "#f5f5f4",
              textShadow: p.color === "w" ? "0 0 1px rgba(255,255,255,0.9)" : "0 0 1px rgba(0,0,0,0.9)"
            },
            children: PIECE_UNI[c] ?? ""
          },
          i
        )),
        (p.materialDiff ?? 0) > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-1 text-[10px] font-bold text-emerald-600 dark:text-emerald-400", children: [
          "+",
          p.materialDiff
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: `font-mono text-base font-bold tabular-nums px-2.5 py-1 rounded-md transition-colors ${critical ? "bg-red-500 text-white animate-pulse" : low ? "text-red-600 dark:text-red-400" : ""}`,
        style: !critical ? { background: p.isTurn ? "rgba(251,191,36,0.12)" : void 0 } : void 0,
        children: fmt(p.timeMs)
      }
    )
  ] });
});
const PIECE_VAL = {
  p: 1,
  n: 3,
  b: 3,
  r: 5,
  q: 9,
  k: 0
};
function evaluate(chess) {
  let s = 0;
  for (const row of chess.board()) for (const c of row) if (c) {
    const v = PIECE_VAL[c.type] ?? 0;
    s += c.color === "w" ? v : -v;
  }
  return s;
}
function evalDepth(chess, depth, isMax, alpha, beta) {
  if (depth === 0 || chess.isGameOver()) {
    if (chess.isCheckmate()) return isMax ? -9999 : 9999;
    if (chess.isDraw()) return 0;
    return evaluate(chess);
  }
  const moves = chess.moves({
    verbose: true
  });
  if (isMax) {
    let best = -Infinity;
    for (const m of moves) {
      const c = new chess.constructor(chess.fen());
      c.move(m);
      const s = evalDepth(c, depth - 1, false, alpha, beta);
      best = Math.max(best, s);
      alpha = Math.max(alpha, s);
      if (beta <= alpha) break;
    }
    return best;
  } else {
    let best = Infinity;
    for (const m of moves) {
      const c = new chess.constructor(chess.fen());
      c.move(m);
      const s = evalDepth(c, depth - 1, true, alpha, beta);
      best = Math.min(best, s);
      beta = Math.min(beta, s);
      if (beta <= alpha) break;
    }
    return best;
  }
}
function pickBotMove(fen, level) {
  const chess = new Chess(fen);
  const moves = chess.moves({
    verbose: true
  });
  if (moves.length === 0) return null;
  const botIsWhite = chess.turn() === "w";
  let chosen = moves[0];
  if (level <= 1) {
    chosen = moves[Math.floor(Math.random() * moves.length)];
  } else if (level === 2) {
    if (Math.random() < 0.4) {
      chosen = moves[Math.floor(Math.random() * moves.length)];
    } else {
      const captures = moves.filter((m) => m.captured);
      if (captures.length) {
        captures.sort((a, b) => (PIECE_VAL[b.captured] ?? 0) - (PIECE_VAL[a.captured] ?? 0));
        chosen = captures[0];
      } else {
        chosen = moves[Math.floor(Math.random() * moves.length)];
      }
    }
  } else if (level === 3) {
    const scored = moves.map((m) => {
      let s = 0;
      if (m.captured) s += (PIECE_VAL[m.captured] ?? 0) * 10;
      if (m.san?.includes("+")) s += 3;
      if (m.san?.includes("#")) s += 1e3;
      if (m.promotion) s += 8;
      s += Math.random() * 0.5;
      return {
        m,
        s
      };
    });
    scored.sort((a, b) => b.s - a.s);
    chosen = scored[0].m;
  } else if (level === 4) {
    const scored = moves.map((m) => {
      const c = new Chess(chess.fen());
      c.move(m);
      const s = evalDepth(c, 1, botIsWhite ? false : true, -Infinity, Infinity);
      return {
        m,
        s: botIsWhite ? s : -s
      };
    });
    scored.sort((a, b) => b.s - a.s);
    const best = scored[0].s;
    const top = scored.filter((x) => x.s === best);
    chosen = top[Math.floor(Math.random() * top.length)].m;
  } else {
    const scored = moves.map((m) => {
      const c = new Chess(chess.fen());
      c.move(m);
      const s = evalDepth(c, 2, botIsWhite ? false : true, -Infinity, Infinity);
      return {
        m,
        s: botIsWhite ? s : -s
      };
    });
    scored.sort((a, b) => b.s - a.s);
    const best = scored[0].s;
    const top = scored.filter((x) => Math.abs(x.s - best) < 5);
    chosen = top[Math.floor(Math.random() * top.length)].m;
  }
  const test = new Chess(chess.fen());
  const played = test.move(chosen);
  if (!played) return null;
  const uci = played.from + played.to + (played.promotion ?? "");
  return {
    uci,
    san: played.san,
    fenAfter: test.fen()
  };
}
function ChessPage() {
  const {
    id
  } = Route$6.useParams();
  const {
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = reactExports.useState(!isMuted());
  const confirm = useConfirm();
  const [game, setGame] = reactExports.useState(null);
  const [profiles, setProfiles] = reactExports.useState({});
  const [lastMove, setLastMove] = reactExports.useState(null);
  const [moveHistory, setMoveHistory] = reactExports.useState([]);
  const [now, setNow] = reactExports.useState(serverNow());
  const [busy, setBusy] = reactExports.useState(false);
  const [showEnd, setShowEnd] = reactExports.useState(false);
  const [botThinking, setBotThinking] = reactExports.useState(false);
  const botTriggeredRef = reactExports.useRef(-1);
  const endTriggeredRef = reactExports.useRef(-1);
  const lastSoundPly = reactExports.useRef(-1);
  const isValidGameId = UUID_RE.test(id);
  const handleQuitGame = reactExports.useCallback(async () => {
    const stake = Number(game?.stake) || 0;
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
    if (game?.id) await supabase.rpc("chess_resign", {
      _game_id: game.id
    });
    navigate({
      to: "/jeux"
    });
  }, [game, confirm, navigate]);
  const load = reactExports.useCallback(async () => {
    if (!isValidGameId) return;
    const {
      data,
      error
    } = await supabase.from("chess_games").select("*").eq("id", id).maybeSingle();
    if (error) {
      toast.error(error.message);
      return;
    }
    if (!data) return;
    setGame(data);
    const ids = [data.white_id, data.black_id].filter(Boolean);
    if (ids.length) {
      const {
        data: pr
      } = await supabase.from("profiles").select("id,pseudo,avatar_url").in("id", ids);
      const map = {};
      (pr ?? []).forEach((p) => {
        map[p.id] = p;
      });
      setProfiles(map);
    }
    const {
      data: moves
    } = await supabase.from("chess_moves").select("uci,san,ply").eq("game_id", id).order("ply", {
      ascending: true
    });
    if (moves && moves.length) {
      const last = moves[moves.length - 1];
      if (last?.uci) setLastMove({
        from: last.uci.slice(0, 2),
        to: last.uci.slice(2, 4)
      });
      setMoveHistory(moves.map((m) => ({
        san: m.san,
        ply: m.ply
      })));
    }
  }, [id, isValidGameId, profile?.id]);
  const {
    isConnected,
    isReconnecting,
    retry
  } = useGameConnection({
    onReconnect: load
  });
  reactExports.useEffect(() => {
    void load();
  }, [load]);
  reactExports.useEffect(() => {
    if (!isValidGameId) return;
    let debounceTimer = null;
    const debouncedLoad = () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        void load();
      }, 300);
    };
    let heartbeat = null;
    const ch = supabase.channel(`chess-${id}`).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "chess_games",
      filter: `id=eq.${id}`
    }, (payload) => {
      if (payload.new) {
        setGame(payload.new);
        if (payload.new.status === "finished") {
          void load();
        }
      } else {
        debouncedLoad();
      }
    }).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "chess_moves",
      filter: `game_id=eq.${id}`
    }, (p) => {
      const u = p.new.uci;
      if (u) setLastMove({
        from: u.slice(0, 2),
        to: u.slice(2, 4)
      });
      if (p.new) {
        setMoveHistory((prev) => {
          const newMove = {
            san: p.new.san,
            ply: p.new.ply
          };
          if (prev.some((m) => m.ply === newMove.ply)) return prev;
          return [...prev, newMove];
        });
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
      if (heartbeat) clearInterval(heartbeat);
    };
  }, [id, isValidGameId, load]);
  reactExports.useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 250);
    return () => clearInterval(t);
  }, []);
  reactExports.useEffect(() => {
    if (!game || game.ply === lastSoundPly.current) return;
    if (game.ply === 0) {
      lastSoundPly.current = 0;
      return;
    }
    if (lastSoundPly.current >= 0 && game.ply > lastSoundPly.current) {
      const chess = new Chess(game.fen);
      const lastSan = moveHistory[moveHistory.length - 1]?.san || "";
      if (chess.isCheckmate()) playChessCheck();
      else if (chess.inCheck()) playChessCheck();
      else if (lastSan.includes("O-O")) playChessCastle();
      else if (lastSan.includes("x")) playChessCapture();
      else playChessMove();
      if (chess.isGameOver()) playChessEnd();
    }
    lastSoundPly.current = game.ply;
  }, [game?.ply, game?.fen, moveHistory]);
  const myColor = reactExports.useMemo(() => {
    if (!game || !profile) return null;
    if (game.white_id === profile.id) return "w";
    if (game.black_id === profile.id) return "b";
    return null;
  }, [game, profile]);
  const isActive = game?.status === "playing";
  const globalTimer = useGlobalGameTimer({
    game: "chess",
    gameId: id,
    status: game?.status,
    deadline: game?.game_deadline
  });
  const isPlayer = !!(profile?.id && game && (game.white_id === profile.id || game.black_id === profile.id));
  const elapsedSinceMove = reactExports.useMemo(() => {
    if (!game || !isActive) return 0;
    const base = new Date(game.last_move_at ?? game.started_at ?? new Date(serverNow()).toISOString()).getTime();
    return Math.max(0, now - base);
  }, [game, isActive, now]);
  const wTime = game ? Math.max(0, game.white_time_ms - (game.turn === "w" ? elapsedSinceMove : 0)) : 0;
  const bTime = game ? Math.max(0, game.black_time_ms - (game.turn === "b" ? elapsedSinceMove : 0)) : 0;
  const {
    capturedByWhite,
    capturedByBlack,
    materialDiff
  } = reactExports.useMemo(() => {
    const startCount = {
      p: 8,
      n: 2,
      b: 2,
      r: 2,
      q: 1
    };
    const cur = {};
    if (game) {
      try {
        for (const row of new Chess(game.fen).board()) for (const c of row) if (c) {
          cur[c.type] ??= {
            w: 0,
            b: 0
          };
          cur[c.type][c.color]++;
        }
      } catch {
      }
    }
    const cw = [];
    const cb = [];
    let wMat = 0, bMat = 0;
    for (const t of Object.keys(startCount)) {
      const w = cur[t]?.w ?? 0;
      const b = cur[t]?.b ?? 0;
      for (let i = 0; i < startCount[t] - b; i++) cw.push(t);
      for (let i = 0; i < startCount[t] - w; i++) cb.push(t);
      wMat += (startCount[t] - b) * (PIECE_VAL[t] ?? 0);
      bMat += (startCount[t] - w) * (PIECE_VAL[t] ?? 0);
    }
    return {
      capturedByWhite: cw,
      capturedByBlack: cb,
      materialDiff: wMat - bMat
    };
  }, [game?.fen]);
  const gameChess = reactExports.useMemo(() => {
    try {
      return new Chess(game?.fen ?? void 0);
    } catch {
      return new Chess();
    }
  }, [game?.fen]);
  const play = reactExports.useCallback(async (uci, san, fenAfter) => {
    if (!game) return;
    unlockAudio();
    const {
      error
    } = await supabase.rpc("chess_play", {
      _id: game.id,
      _uci: uci,
      _san: san,
      _fen_after: fenAfter,
      _elapsed_ms: elapsedSinceMove
    });
    if (error) {
      console.error("chess_play error", error);
      toast.error(error.message ?? "Coup invalide");
      return;
    }
    void load();
  }, [game, elapsedSinceMove, load]);
  reactExports.useEffect(() => {
    if (!game || !isActive || game.mode !== "solo" || !myColor) return;
    const botIsWhite = game.white_is_bot;
    const botColor = botIsWhite ? "w" : "b";
    if (game.turn !== botColor) return;
    if (botTriggeredRef.current === game.ply) return;
    const plyAtSchedule = game.ply;
    const level = game.bot_intelligence ?? 2;
    const preChess = new Chess(game.fen);
    const preMove = preChess.isGameOver() ? null : pickBotMove(game.fen, level);
    const legalCount = preChess.isGameOver() ? 0 : preChess.moves().length;
    let complexity = 0;
    if (preMove) {
      complexity += Math.min(1, legalCount / 35);
      const san = preMove.san ?? "";
      if (san.includes("x")) complexity += 0.25;
      if (san.includes("+")) complexity += 0.2;
      if (san.includes("#")) complexity += 0.35;
      if (san.includes("=")) complexity += 0.25;
      if (san === "O-O" || san === "O-O-O") complexity += 0.15;
      complexity += (level - 1) * 0.1;
    }
    complexity = Math.max(0, Math.min(1, complexity));
    const jitter = (Math.random() - 0.5) * 200;
    const delay = Math.max(800, Math.min(2500, 1e3 + complexity * 1500 + jitter));
    setBotThinking(true);
    const timer = setTimeout(async () => {
      if (botTriggeredRef.current === plyAtSchedule) {
        setBotThinking(false);
        return;
      }
      botTriggeredRef.current = plyAtSchedule;
      const chess = new Chess(game.fen);
      if (chess.isGameOver()) {
        setBotThinking(false);
        return;
      }
      const mv = preMove ?? pickBotMove(game.fen, level);
      if (!mv) {
        setBotThinking(false);
        return;
      }
      const gameElapsed = Math.max(0, serverNow() - new Date(game.last_move_at ?? game.started_at ?? new Date(serverNow()).toISOString()).getTime());
      const {
        error
      } = await supabase.rpc("chess_bot_play", {
        _id: game.id,
        _uci: mv.uci,
        _san: mv.san,
        _fen_after: mv.fenAfter,
        _elapsed_ms: gameElapsed
      });
      if (error) {
        console.error("bot_play error", error);
        botTriggeredRef.current = -1;
        toast.error(error.message ?? "Erreur bot");
      } else {
        void load();
      }
      setBotThinking(false);
    }, delay);
    return () => {
      clearTimeout(timer);
      setBotThinking(false);
    };
  }, [game, isActive, myColor, load]);
  reactExports.useEffect(() => {
    if (!game || !isActive) return;
    if (endTriggeredRef.current === game.ply) return;
    const chess = new Chess(game.fen);
    if (!chess.isGameOver()) return;
    endTriggeredRef.current = game.ply;
    let winner = null;
    let draw = false;
    let reason = "";
    if (chess.isCheckmate()) {
      winner = chess.turn() === "w" ? game.black_id : game.white_id;
      reason = "checkmate";
    } else if (chess.isStalemate()) {
      draw = true;
      reason = "stalemate";
    } else if (chess.isThreefoldRepetition()) {
      draw = true;
      reason = "repetition";
    } else if (chess.isInsufficientMaterial()) {
      draw = true;
      reason = "insufficient";
    } else if (chess.isDraw()) {
      draw = true;
      reason = "draw_50";
    }
    (async () => {
      const {
        error
      } = await supabase.rpc("chess_finish", {
        _id: game.id,
        _winner: winner,
        _draw: draw,
        _reason: reason
      });
      if (error) {
        console.error("chess_finish error", error);
        endTriggeredRef.current = -1;
      } else {
        void load();
      }
    })();
  }, [game, isActive, load]);
  const timeoutFiredRef = reactExports.useRef(null);
  reactExports.useEffect(() => {
    if (!game || !isActive) return;
    if (wTime > 0 && bTime > 0) return;
    const loserColor = wTime <= 0 ? "w" : "b";
    const key = `${game.id}:${game.ply}:${loserColor}`;
    if (timeoutFiredRef.current === key) return;
    timeoutFiredRef.current = key;
    (async () => {
      await supabase.rpc("chess_tick", {
        _game_id: game.id
      });
      setTimeout(async () => {
        const {
          data
        } = await supabase.from("chess_games").select("status").eq("id", game.id).maybeSingle();
        if (data?.status === "playing") {
          const winner = loserColor === "w" ? game.black_id : game.white_id;
          await supabase.rpc("chess_finish", {
            _id: game.id,
            _winner: winner,
            _draw: false,
            _reason: "timeout"
          });
          void load();
        }
      }, 1200);
    })();
  }, [game, isActive, wTime, bTime, load]);
  reactExports.useEffect(() => {
    if (game?.status === "finished") setShowEnd(true);
  }, [game?.status]);
  const doResign = async () => {
    if (!game) return;
    const ok = await confirm({
      title: "Abandonner la partie ?",
      description: "Vous perdrez automatiquement.",
      confirmLabel: "Abandonner",
      destructive: true
    });
    if (!ok) return;
    setBusy(true);
    try {
      await supabase.rpc("chess_resign", {
        _game_id: game.id
      });
    } catch (e) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  };
  const doOfferDraw = async () => {
    if (!game) return;
    setBusy(true);
    try {
      if (game.draw_offered_by && game.draw_offered_by !== profile?.id) {
        await supabase.rpc("chess_accept_draw", {
          _game_id: game.id
        });
      } else {
        await supabase.rpc("chess_offer_draw", {
          _game_id: game.id
        });
        toast.success("Nulle proposée");
      }
    } catch (e) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  };
  const doReplay = async () => {
    if (!game) return;
    if (game.mode !== "solo") {
      setBusy(true);
      try {
        const {
          data,
          error
        } = await supabase.rpc("chess_create", {
          _stake: Number(game.stake) || 0,
          _private: !!game.is_private,
          _commission: Number(game.commission_pct) || 10
        });
        if (error) throw error;
        if (data) {
          refreshProfile();
          navigate({
            to: "/jeux/chess/$id",
            params: {
              id: data
            }
          });
        }
      } catch (e) {
        toast.error(e.message);
      } finally {
        setBusy(false);
      }
      return;
    }
    setBusy(true);
    try {
      const {
        data,
        error
      } = await supabase.rpc("chess_create_solo", {
        _difficulty: game.bot_intelligence ?? 2,
        _color: myColor === "w" ? "white" : "black",
        _time_min: game.time_control_min
      });
      if (error) throw error;
      if (data) {
        refreshProfile();
        navigate({
          to: "/jeux/chess/$id",
          params: {
            id: data
          }
        });
      }
    } catch (e) {
      toast.error(e.message);
    } finally {
      setBusy(false);
    }
  };
  if (!isValidGameId) {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "min-h-screen bg-background p-6 flex flex-col items-center justify-center text-center gap-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-lg font-bold text-foreground", children: "Lien de partie invalide" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground max-w-xs", children: "Cette ancienne adresse n'est pas une vraie partie d'échecs." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Button, { onClick: () => navigate({
        to: "/jeux/$slug",
        params: {
          slug: "chess"
        }
      }), children: "Créer une partie" })
    ] });
  }
  if (!game) return /* @__PURE__ */ jsxRuntimeExports.jsx(GameLoader, {});
  if (game.status === "cancelled") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(GameStateMessage, { state: "cancelled", gameLabel: "Échecs", slug: "chess" });
  }
  if (game.status === "open" && !isActive) {
    const seatParts = [];
    if (game.white_id) {
      const wp = profiles[game.white_id];
      seatParts.push({
        id: `w-${game.white_id}`,
        user_id: game.white_id,
        display_name: wp?.pseudo || (game.white_is_bot ? game.bot_name || "Bot" : "Blancs"),
        avatar_url: wp?.avatar_url ?? void 0,
        color: "white",
        slot: 0,
        ready: game.white_is_bot ? true : !!game.ready_white
      });
    }
    if (game.black_id) {
      const bp = profiles[game.black_id];
      seatParts.push({
        id: `b-${game.black_id}`,
        user_id: game.black_id,
        display_name: bp?.pseudo || (game.black_is_bot ? game.bot_name || "Bot" : "Noirs"),
        avatar_url: bp?.avatar_url ?? void 0,
        color: "black",
        slot: 1,
        ready: game.black_is_bot ? true : !!game.ready_black
      });
    }
    const isParticipant = !!(profile?.id && (game.white_id === profile.id || game.black_id === profile.id));
    const canAddBot = (isAdmin || Number(game.stake) === 0 && isParticipant) && seatParts.length < 2;
    const forfeitChess = async () => {
      await supabase.rpc("chess_forfeit", {
        _id: game.id
      });
      navigate({
        to: "/jeux"
      });
    };
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(GameWaitingRoom, { isTournament: false, slug: "chess", gameLabel: `Échecs · 2 joueurs · ${game.time_control_min > 0 ? `${game.time_control_min} min` : "∞"}`, parts: seatParts, maxPlayers: 2, stake: Number(game.stake) || 0, pot: Number(game.pot) || 0, roomCode: game.is_private ? game.room_code : null, shareSlug: "chess", meUserId: profile?.id, isParticipant, createdAt: game.created_at, onQuit: forfeitChess, onToggleReady: async (ready) => {
        const {
          error
        } = await supabase.rpc("chess_set_ready", {
          _game_id: game.id,
          _ready: ready
        });
        if (error) toast.error(error.message);
      } }),
      canAddBot && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
        const {
          error
        } = await supabase.rpc("chess_add_bot", {
          _game_id: game.id,
          _difficulty: "medium"
        });
        if (error) toast.error(error.message);
        else toast.success("Bot ajouté");
      }, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Ajouter un bot"
      ] })
    ] });
  }
  const orientation = myColor ?? "w";
  const meId = profile?.id;
  const oppId = myColor === "w" ? game.black_id : game.white_id;
  const meColor = myColor ?? "w";
  const oppColor = meColor === "w" ? "b" : "w";
  const meProfile = meId ? profiles[meId] ?? {
    pseudo: profile?.pseudo ?? "Moi",
    avatar_url: profile?.avatar_url ?? null
  } : {
    pseudo: "Moi",
    avatar_url: null
  };
  const oppProfile = oppId ? profiles[oppId] ?? {
    pseudo: game.mode === "solo" ? game.bot_name ?? "Joueur" : "Adversaire",
    avatar_url: null
  } : {
    pseudo: "Adversaire",
    avatar_url: null
  };
  const meTime = meColor === "w" ? wTime : bTime;
  const oppTime = oppColor === "w" ? wTime : bTime;
  const meCaptured = meColor === "w" ? capturedByWhite : capturedByBlack;
  const oppCaptured = oppColor === "w" ? capturedByWhite : capturedByBlack;
  const meMatDiff = meColor === "w" ? Math.max(0, materialDiff) : Math.max(0, -materialDiff);
  const oppMatDiff = oppColor === "w" ? Math.max(0, materialDiff) : Math.max(0, -materialDiff);
  const drawOfferedByOpp = game.draw_offered_by && game.draw_offered_by !== profile?.id;
  const inCheck = gameChess.inCheck() && isActive;
  const isCheckmate = gameChess.isCheckmate() && isActive;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "h-full overflow-hidden flex flex-col bg-gradient-to-b from-stone-100 to-stone-200 dark:from-stone-900 dark:to-stone-950 overscroll-none", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyBanner, { stake: Number(game?.stake) || 0, phoneVerified: !!profile?.phone_verified }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-2 pt-1", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-baseline gap-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[8px] uppercase text-muted-foreground tracking-wider", children: "Au gagnant" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-extrabold truncate", children: [
          Math.round(Number(game.pot) * (100 - (Number(game.commission_pct) || 10)) / 100).toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      !myColor ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1", children: "Spectateur" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
        (game.white_is_bot || game.black_is_bot) && game.status === "playing" && !game.paused && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: async () => {
          const {
            error
          } = await supabase.rpc("game_request_pause", {
            _slug: "chess",
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
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: handleQuitGame, className: "px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-2.5 h-2.5" }),
          " Quitter"
        ] })
      ] })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 mt-1", children: /* @__PURE__ */ jsxRuntimeExports.jsx(PlayerBar, { name: oppProfile.pseudo ?? "Adversaire", avatarUrl: oppProfile.avatar_url, color: oppColor, timeMs: oppTime, isTurn: game.turn === oppColor && isActive, captured: oppCaptured, materialDiff: oppMatDiff }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-3 pt-1 flex justify-center h-7 items-center", children: [
      isCheckmate && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 py-1 rounded-full bg-red-600 text-white text-xs font-bold animate-pulse", children: "Échec et mat !" }),
      !isCheckmate && inCheck && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 py-1 rounded-full bg-orange-500 text-white text-xs font-bold animate-pulse", children: "Échec !" }),
      botThinking && !inCheck && !isCheckmate && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "inline-flex items-center gap-1.5 text-xs text-muted-foreground bg-card/70 border border-border/60 rounded-full px-2.5 py-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1 h-1 rounded-full bg-current animate-bounce", style: {
            animationDelay: "0ms"
          } }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1 h-1 rounded-full bg-current animate-bounce", style: {
            animationDelay: "150ms"
          } }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1 h-1 rounded-full bg-current animate-bounce", style: {
            animationDelay: "300ms"
          } })
        ] }),
        "Le bot réfléchit…"
      ] })
    ] }),
    drawOfferedByOpp && isActive && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 pb-1", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 bg-amber-500/15 border border-amber-500/30 rounded-lg px-3 py-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-semibold text-amber-700 dark:text-amber-400 flex-1", children: "🤝 L'adversaire propose la nulle" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: doOfferDraw, disabled: busy, className: "px-3 py-1 rounded-md bg-amber-500 text-white text-xs font-bold hover:bg-amber-600", children: "Accepter" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: async () => {
        await supabase.rpc("chess_decline_draw", {
          _game_id: game.id
        });
      }, className: "px-3 py-1 rounded-md bg-secondary text-foreground text-xs font-bold", children: "Refuser" })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 flex items-center justify-center px-2 py-1 min-h-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChessBoard, { fen: game.fen, myColor: orientation, onMove: play, lastMove, disabled: !isActive || !myColor || botThinking || game.turn !== myColor }) }),
    moveHistory.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 pb-0.5 max-h-16 overflow-y-auto", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-1 text-[10px] font-mono", children: moveHistory.map((m, i) => {
      const moveNum = Math.floor(i / 2) + 1;
      const isWhite = i % 2 === 0;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "px-1.5 py-0.5 rounded bg-card/60 border border-border/40", children: [
        !isWhite && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
          moveNum,
          "… "
        ] }),
        isWhite && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
          moveNum,
          ". "
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold", children: m.san })
      ] }, i);
    }) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 mt-1", children: /* @__PURE__ */ jsxRuntimeExports.jsx(PlayerBar, { name: meProfile.pseudo ?? "Moi", avatarUrl: meProfile.avatar_url, color: meColor, timeMs: meTime, isTurn: game.turn === meColor && isActive, captured: meCaptured, materialDiff: meMatDiff }) }),
    isActive && myColor && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 px-3 py-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs(Button, { variant: "outline", className: "flex-1", onClick: doResign, disabled: busy, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Flag, { className: "w-4 h-4 mr-1.5" }),
        " Abandonner"
      ] }),
      game.mode !== "solo" && /* @__PURE__ */ jsxRuntimeExports.jsxs(Button, { variant: drawOfferedByOpp ? "default" : "outline", className: "flex-1", onClick: doOfferDraw, disabled: busy, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Handshake, { className: "w-4 h-4 mr-1.5" }),
        drawOfferedByOpp ? "Accepter nulle" : "Nulle"
      ] })
    ] }),
    isActive && globalTimer.enabled && globalTimer.remainingMs !== null && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `px-3 py-1 mx-2 rounded-lg text-center text-xs font-bold ${globalTimer.remainingMs <= 3e4 ? "bg-destructive/15 text-destructive animate-pulse" : "bg-amber-500/10 text-amber-600 dark:text-amber-400"}`, children: [
      "⏳ Temps global restant : ",
      globalTimer.remainingLabel
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GamePauseControl, { slug: "chess", gameId: id, game, isPlayer, myUserId: profile?.id ?? null, simplePause: game.mode === "solo" }),
    game.status === "finished" && (() => {
      const reasonLabel = {
        checkmate: "Échec et mat",
        stalemate: "Pat",
        timeout: "Temps écoulé",
        resign: "Abandon",
        draw_agreed: "Nulle acceptée",
        repetition: "Répétition",
        insufficient: "Matériel insuffisant",
        draw_50: "Règle des 50 coups"
      };
      const participants = [game.white_id ? {
        user_id: game.white_id,
        display_name: game.white_is_bot ? game.bot_name ?? "Ordinateur" : profiles[game.white_id]?.pseudo ?? "Blancs",
        slot: 0
      } : null, game.black_id ? {
        user_id: game.black_id,
        display_name: game.black_is_bot ? game.bot_name ?? "Ordinateur" : profiles[game.black_id]?.pseudo ?? "Noirs",
        slot: 1
      } : null].filter(Boolean);
      return /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "chess", meUserId: profile?.id, winnerId: game.draw ? null : game.winner_id, participants, stake: Number(game.stake), pot: Number(game.pot), commissionPct: 10, onReplay: doReplay, extra: game.end_reason ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: reasonLabel[game.end_reason] ?? game.end_reason }) : void 0 });
    })(),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameReconnectOverlay, { isConnected, isReconnecting, onRetry: retry })
  ] });
}
export {
  ChessPage as component
};
