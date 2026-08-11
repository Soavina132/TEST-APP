import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { A as Route$4, u as useAuth, b as useConfirm } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { u as useGameConnection, G as GameStateMessage, a as GameWaitingRoom, d as GameReconnectOverlay, c as GameEndScreen, b as GamePauseControl } from "./GameReconnectOverlay-DB4s6cH2.mjs";
import { u as useFastRealtime } from "./use-fast-realtime-B6ENk2Ox.mjs";
import { G as GameSocialFab } from "./GameSocialFab-DlZx4gfi.mjs";
import { u as useGameConfig } from "./use-game-config-DU32XRGm.mjs";
import { u as useGlobalGameTimer } from "./use-global-game-timer-B_Rb2H6C.mjs";
import { G as GameLoader } from "./GameLoader-DEMrZT6Q.mjs";
import { i as isMuted, s as setMuted } from "./game-sounds-246YZn8C.mjs";
import { P as PhoneVerifyBanner } from "./PhoneVerifyBanner-Dqrff6fy.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/canvas-confetti.mjs";
import { ag as Pause, aU as Volume2, aV as VolumeX, Q as LogOut, b0 as SkipForward } from "../_libs/lucide-react.mjs";
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
let _ctx = null;
function getCtx() {
  if (typeof window === "undefined") return null;
  try {
    if (!_ctx) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      _ctx = new AC();
    }
    if (_ctx.state === "suspended") _ctx.resume();
    return _ctx;
  } catch {
    return null;
  }
}
function unlockAudio() {
  getCtx();
}
function playFanoronaMove() {
  if (isMuted()) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(240, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(120, ctx.currentTime + 0.05);
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(0.25, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + 0.07);
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.start();
    osc.stop(ctx.currentTime + 0.07);
  } catch {
  }
}
function playFanoronaCapture() {
  if (isMuted()) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [0, 0.06].forEach((delay) => {
      const noiseBuf = ctx.createBuffer(1, ctx.sampleRate * 0.05, ctx.sampleRate);
      const ch = noiseBuf.getChannelData(0);
      for (let i = 0; i < ch.length; i++) ch[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / ch.length, 1.5);
      const noise = ctx.createBufferSource();
      noise.buffer = noiseBuf;
      const filter = ctx.createBiquadFilter();
      filter.type = "bandpass";
      filter.frequency.setValueAtTime(350, ctx.currentTime + delay);
      filter.Q.setValueAtTime(1.5, ctx.currentTime + delay);
      const noiseGain = ctx.createGain();
      noiseGain.gain.setValueAtTime(0.2, ctx.currentTime + delay);
      noiseGain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + delay + 0.05);
      noise.connect(filter);
      filter.connect(noiseGain);
      noiseGain.connect(ctx.destination);
      noise.start(ctx.currentTime + delay);
      noise.stop(ctx.currentTime + delay + 0.05);
    });
  } catch {
  }
}
function playFanoronaWin() {
  if (isMuted()) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [523, 659, 784, 1047].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.1);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.1);
      gain.gain.exponentialRampToValueAtTime(0.15, ctx.currentTime + i * 0.1 + 0.02);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.1 + 0.3);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.1);
      osc.stop(ctx.currentTime + i * 0.1 + 0.35);
    });
  } catch {
  }
}
function playFanoronaLose() {
  if (isMuted()) return;
  const ctx = getCtx();
  if (!ctx) return;
  try {
    [392, 330, 262, 196].forEach((freq, i) => {
      const osc = ctx.createOscillator();
      osc.type = "triangle";
      osc.frequency.setValueAtTime(freq, ctx.currentTime + i * 0.12);
      const gain = ctx.createGain();
      gain.gain.setValueAtTime(1e-3, ctx.currentTime + i * 0.12);
      gain.gain.exponentialRampToValueAtTime(0.12, ctx.currentTime + i * 0.12 + 0.02);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + i * 0.12 + 0.3);
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.start(ctx.currentTime + i * 0.12);
      osc.stop(ctx.currentTime + i * 0.12 + 0.35);
    });
  } catch {
  }
}
const isStrong = (r, c) => (r + c) % 2 === 0;
const DIRS_ORTHO = [[-1, 0], [1, 0], [0, -1], [0, 1]];
const DIRS_DIAG = [[-1, -1], [-1, 1], [1, -1], [1, 1]];
const ALL_DIRS = [...DIRS_ORTHO, ...DIRS_DIAG];
function axisKey(dr, dc) {
  return dr < 0 || dr === 0 && dc < 0 ? `${-dr},${-dc}` : `${dr},${dc}`;
}
function makeHelpers(COLS, ROWS) {
  const idx = (r, c) => r * COLS + c;
  const inBounds = (r, c) => r >= 0 && r < ROWS && c >= 0 && c < COLS;
  function neighbors(r, c) {
    const dirs = isStrong(r, c) ? ALL_DIRS : DIRS_ORTHO;
    return dirs.filter(([dr, dc]) => inBounds(r + dr, c + dc));
  }
  function legalTargets(board, from, myColor, chainFrom, visited, lastAxis) {
    const fr = Math.floor(from / COLS), fc = from % COLS;
    const strong = isStrong(fr, fc);
    const dirs = strong ? ALL_DIRS : DIRS_ORTHO;
    const targets = [];
    for (const [dr, dc] of dirs) {
      const nr = fr + dr, nc = fc + dc;
      if (!inBounds(nr, nc)) continue;
      const to = idx(nr, nc);
      if (board[to] !== 0) continue;
      if (chainFrom !== null) {
        if (visited.includes(to)) continue;
        const ax = axisKey(dr, dc);
        if (lastAxis && ax === lastAxis) continue;
      }
      const {
        approach,
        withdrawal
      } = computeCaptures(board, from, to, myColor);
      targets.push({
        to,
        approach,
        withdrawal
      });
    }
    return targets;
  }
  function computeCaptures(board, from, to, myColor) {
    const opp = myColor === 1 ? 2 : 1;
    const fr = Math.floor(from / COLS), fc = from % COLS;
    const tr = Math.floor(to / COLS), tc = to % COLS;
    const dr = tr - fr, dc = tc - fc;
    const approach = [];
    let r = tr + dr, c = tc + dc;
    while (inBounds(r, c) && board[idx(r, c)] === opp) {
      approach.push(idx(r, c));
      r += dr;
      c += dc;
    }
    const withdrawal = [];
    r = fr - dr;
    c = fc - dc;
    while (inBounds(r, c) && board[idx(r, c)] === opp) {
      withdrawal.push(idx(r, c));
      r -= dr;
      c -= dc;
    }
    return {
      approach,
      withdrawal
    };
  }
  return {
    idx,
    inBounds,
    neighbors,
    legalTargets,
    computeCaptures
  };
}
function countPieces(board, color) {
  return board.filter((v) => v === color).length;
}
function fmtClock(ms) {
  const s = Math.max(0, Math.floor(ms / 1e3));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r.toString().padStart(2, "0")}`;
}
function FanoronaPlayerBar({
  p,
  isCurrent,
  isMe,
  pieceCount,
  timeMs,
  avatarUrl
}) {
  const isWhite = p.color === "white";
  const low = timeMs < 3e4;
  const critical = timeMs < 1e4;
  const name = p.display_name || "Joueur";
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg transition-colors duration-300 ${isCurrent ? "bg-card shadow-md border border-amber-400/40" : "bg-card/80 backdrop-blur border border-border"}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9 rounded-md overflow-hidden flex-shrink-0 border-2", style: {
      borderColor: isWhite ? "#fafaf9" : "#1c1917"
    }, children: avatarUrl ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: avatarUrl, alt: name, className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full flex items-center justify-center bg-muted text-sm font-bold", children: name.slice(0, 1).toUpperCase() }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-semibold text-xs truncate flex items-center gap-1.5", children: [
        name,
        p.is_bot && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-violet-500 shrink-0", children: "🤖" }),
        isMe && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-primary/60 shrink-0", children: "(vous)" }),
        isCurrent && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center gap-1.5 mt-0.5", children: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-muted-foreground", children: p.forfeited ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-destructive", children: "Forfait" }) : `♟ ${pieceCount} pions` }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `shrink-0 font-mono text-base font-bold tabular-nums px-2.5 py-1 rounded-md transition-colors ${critical ? "bg-red-500 text-white animate-pulse" : low ? "text-red-600 dark:text-red-400" : ""}`, style: !critical ? {
      background: isCurrent ? "rgba(251,191,36,0.12)" : void 0
    } : void 0, children: fmtClock(timeMs) })
  ] });
}
function FanoronaWaitingBar() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-lg p-1.5 bg-card border-2 border-dashed border-white/10 text-center text-[11px] text-muted-foreground", children: "⏳ En attente adversaire…" });
}
function FanoronaPage() {
  const {
    id
  } = Route$4.useParams();
  const {
    profile,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = reactExports.useState(!isMuted());
  const {
    game,
    parts,
    loading,
    reload
  } = useFastRealtime({
    gameTable: "fanorona_games",
    participantTable: "fanorona_participants",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile
  });
  const [profiles, setProfiles] = reactExports.useState({});
  const [selected, setSelected] = reactExports.useState(null);
  const [captureChoice, setCaptureChoice] = reactExports.useState(null);
  const [busy, setBusy] = reactExports.useState(false);
  const [rotated90, setRotated90] = reactExports.useState(false);
  const [lastMove, setLastMove] = reactExports.useState(null);
  const [animatingCapture, setAnimatingCapture] = reactExports.useState([]);
  const botTriggeredRef = reactExports.useRef(-1);
  const lastBoardRef = reactExports.useRef("");
  const load = reload;
  const loaded = !loading;
  const [loadError, setLoadError] = reactExports.useState(null);
  reactExports.useEffect(() => {
    if (!parts.length) return;
    const uids = parts.map((pt) => pt.user_id).filter(Boolean);
    if (!uids.length) return;
    supabase.from("profiles").select("id,pseudo,avatar_url").in("id", uids).then(({
      data
    }) => {
      if (!data) return;
      const map = {};
      data.forEach((x) => {
        map[x.id] = {
          pseudo: x.pseudo,
          avatar_url: x.avatar_url
        };
      });
      setProfiles(map);
    });
  }, [parts]);
  reactExports.useEffect(() => {
    const check = () => {
      setRotated90(window.innerHeight > window.innerWidth && window.innerWidth < 500);
    };
    check();
    window.addEventListener("resize", check);
    window.addEventListener("orientationchange", check);
    return () => {
      window.removeEventListener("resize", check);
      window.removeEventListener("orientationchange", check);
    };
  }, []);
  const sendMoveRef = reactExports.useRef(() => {
  });
  const endTurn = reactExports.useCallback(() => sendMoveRef.current({
    pass: true
  }), []);
  const {
    isConnected,
    isReconnecting,
    retry
  } = useGameConnection({
    onReconnect: reload
  });
  const boardKey = reactExports.useMemo(() => JSON.stringify(game?.state?.board || []), [game?.state?.board]);
  reactExports.useEffect(() => {
    if (!boardKey || boardKey === "[]" || boardKey === lastBoardRef.current) return;
    const oldKey = lastBoardRef.current;
    lastBoardRef.current = boardKey;
    if (!oldKey || oldKey === "[]" || oldKey === "[]") return;
    try {
      const oldBoard = JSON.parse(oldKey);
      const newBoard = JSON.parse(boardKey);
      let fromIdx = -1, toIdx = -1;
      const captured = [];
      for (let i = 0; i < oldBoard.length; i++) {
        if (oldBoard[i] !== 0 && newBoard[i] === 0) {
          let foundElsewhere = false;
          for (let j = 0; j < newBoard.length; j++) {
            if (oldBoard[j] === 0 && newBoard[j] === oldBoard[i] && j !== i) {
              fromIdx = i;
              toIdx = j;
              foundElsewhere = true;
            }
          }
          if (!foundElsewhere) captured.push(i);
        }
      }
      if (fromIdx >= 0 && toIdx >= 0) {
        const realCaptured = [];
        for (let i = 0; i < oldBoard.length; i++) {
          if (oldBoard[i] !== 0 && newBoard[i] === 0 && i !== fromIdx) {
            realCaptured.push(i);
          }
        }
        setLastMove({
          from: fromIdx,
          to: toIdx,
          captured: realCaptured
        });
        if (realCaptured.length > 0) {
          setAnimatingCapture(realCaptured);
          setTimeout(() => setAnimatingCapture([]), 600);
          playFanoronaCapture();
        } else {
          playFanoronaMove();
        }
      }
    } catch {
    }
  }, [boardKey]);
  reactExports.useEffect(() => {
    if (game?.status === "finished" && game?.winner_id) {
      const myPart = parts.find((p) => p.user_id === profile?.id);
      if (myPart && !myPart.forfeited) {
        if (game.winner_id === profile?.id) playFanoronaWin();
        else playFanoronaLose();
      }
    }
  }, [game?.status, game?.winner_id, profile?.id]);
  const COLS = game?.cols || 9;
  const ROWS = game?.rows || 5;
  const {
    idx,
    neighbors,
    legalTargets
  } = reactExports.useMemo(() => makeHelpers(COLS, ROWS), [COLS, ROWS]);
  const me = parts.find((p) => p.user_id === profile?.id);
  const isPlayer = !!me;
  const myColor = me?.color === "white" ? 1 : me?.color === "black" ? 2 : 0;
  const isMyTurn = !!(game && me && game.current_turn === me.slot && game.status === "playing");
  const board = reactExports.useMemo(() => game?.state?.board || Array(ROWS * COLS).fill(0), [game?.state?.board, ROWS, COLS]);
  const chainFrom = game?.state?.chain_from ?? null;
  const visited = reactExports.useMemo(() => game?.state?.visited || [], [game?.state?.visited]);
  const lastAxis = game?.state?.last_axis ?? null;
  game?.mandatory_capture !== false;
  const cfg = useGameConfig("fanorona");
  const globalTimer = useGlobalGameTimer({
    game: "fanorona",
    gameId: id,
    status: game?.status,
    deadline: game?.game_deadline
  });
  const flipped = me?.color === "black";
  const [now, setNow] = reactExports.useState(serverNow());
  reactExports.useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 250);
    return () => clearInterval(t);
  }, []);
  const elapsedSinceMove = reactExports.useMemo(() => {
    if (!game || game.status !== "playing") return 0;
    const base = new Date(game.last_move_at ?? game.started_at ?? new Date(serverNow()).toISOString()).getTime();
    return Math.max(0, now - base);
  }, [game, now]);
  const wTime = game ? Math.max(0, game.white_time_ms - (game.current_turn === 0 ? elapsedSinceMove : 0)) : 0;
  const bTime = game ? Math.max(0, game.black_time_ms - (game.current_turn === 1 ? elapsedSinceMove : 0)) : 0;
  const timeoutFiredRef = reactExports.useRef(null);
  reactExports.useEffect(() => {
    if (!game || game.status !== "playing") return;
    if (wTime > 0 && bTime > 0) return;
    const loserSlot = wTime <= 0 ? 0 : 1;
    const key = `${game.id}:${game.state?.move_count ?? 0}:${loserSlot}`;
    if (timeoutFiredRef.current === key) return;
    timeoutFiredRef.current = key;
    (async () => {
      await supabase.rpc("fanorona_tick", {
        _game_id: id
      });
      setTimeout(() => load(), 1200);
    })();
  }, [game, id, wTime, bTime, load]);
  const validTargets = reactExports.useMemo(() => {
    if (!isMyTurn || selected === null && chainFrom === null) return /* @__PURE__ */ new Map();
    const from = chainFrom !== null ? chainFrom : selected;
    if (from === null || board[from] !== myColor) return /* @__PURE__ */ new Map();
    const targets = legalTargets(board, from, myColor, chainFrom, visited, lastAxis);
    const map = /* @__PURE__ */ new Map();
    for (const t of targets) {
      if (chainFrom !== null && t.approach.length === 0 && t.withdrawal.length === 0) continue;
      map.set(t.to, {
        approach: t.approach,
        withdrawal: t.withdrawal
      });
    }
    return map;
  }, [isMyTurn, selected, chainFrom, board, myColor, visited, lastAxis, legalTargets]);
  reactExports.useMemo(() => {
    if (!isMyTurn || !board || !myColor) return false;
    for (let i = 0; i < board.length; i++) {
      if (board[i] === myColor) {
        const targets = legalTargets(board, i, myColor, null, [], null);
        if (targets.some((t) => t.approach.length > 0 || t.withdrawal.length > 0)) return true;
      }
    }
    return false;
  }, [isMyTurn, board, myColor, legalTargets]);
  const whiteCount = reactExports.useMemo(() => countPieces(board, 1), [board]);
  const blackCount = reactExports.useMemo(() => countPieces(board, 2), [board]);
  const sendMove = reactExports.useCallback(async (move) => {
    setBusy(true);
    try {
      const {
        error
      } = await supabase.rpc("fanorona_play", {
        _game_id: id,
        _move: move
      });
      if (error) throw error;
      setSelected(null);
      setCaptureChoice(null);
    } catch (e) {
      const msg = e?.message || "";
      const fr = {
        "capture is mandatory when available": "Capture obligatoire — vous devez capturer un pion adverse",
        "must capture during chain": "Vous devez continuer la rafale (capture obligatoire)",
        "must continue with same piece": "Vous devez continuer avec le même pion",
        "not your turn": "Ce n'est pas votre tour",
        "game not active": "La partie n'est plus active",
        "not your piece": "Ce n'est pas votre pion",
        "target not empty": "La case de destination est occupée",
        "invalid step": "Déplacement invalide",
        "diagonal not allowed here": "Diagonale non autorisée ici",
        "cannot revisit cell": "Vous ne pouvez pas revenir sur une case déjà visitée",
        "cannot continue on same axis": "Vous ne pouvez pas continuer sur le même axe",
        "invalid capture set": "Ensemble de capture invalide",
        "not a participant": "Vous n'êtes pas participant de cette partie"
      };
      toast.error(fr[msg] || msg || "Coup invalide");
    } finally {
      setBusy(false);
    }
  }, [id]);
  sendMoveRef.current = sendMove;
  const onCellClick = reactExports.useCallback((cell) => {
    if (!isMyTurn || busy) return;
    unlockAudio();
    if (captureChoice) {
      setCaptureChoice(null);
      return;
    }
    const effectiveSelected = chainFrom !== null ? chainFrom : selected;
    if (effectiveSelected === null) {
      if (board[cell] === myColor) setSelected(cell);
      return;
    }
    if (cell === effectiveSelected) {
      if (chainFrom === null) setSelected(null);
      return;
    }
    if (board[cell] === myColor && chainFrom === null) {
      setSelected(cell);
      return;
    }
    const targetInfo = validTargets.get(cell);
    if (!targetInfo) {
      if (chainFrom === null && board[cell] === 0) toast.error("Déplacement invalide");
      return;
    }
    const {
      approach,
      withdrawal
    } = targetInfo;
    if (approach.length > 0 && withdrawal.length > 0) {
      setCaptureChoice({
        from: effectiveSelected,
        to: cell,
        approach,
        withdrawal
      });
      return;
    }
    const captured = approach.length > 0 ? approach : withdrawal;
    sendMove({
      from: effectiveSelected,
      to: cell,
      captured,
      chain: false
    });
  }, [isMyTurn, busy, captureChoice, chainFrom, selected, board, myColor, validTargets, sendMove]);
  const confirm = useConfirm();
  const forfeit = reactExports.useCallback(async () => {
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
    await supabase.rpc("fanorona_forfeit", {
      _game_id: id
    });
    navigate({
      to: "/jeux"
    });
  }, [game?.stake, game?.status, id, navigate, confirm]);
  const moveCount = game?.state?.move_count ?? 0;
  const botChainFrom = game?.state?.chain_from ?? null;
  const partsRef = reactExports.useRef(parts);
  partsRef.current = parts;
  reactExports.useEffect(() => {
    if (!game || game.status !== "playing") return;
    const botPart = partsRef.current.find((p) => p.is_bot);
    if (!botPart) return;
    if (game.current_turn !== botPart.slot) return;
    const triggerKey = `${game.current_turn}:${moveCount}:${botChainFrom}`;
    if (botTriggeredRef.current === triggerKey) return;
    botTriggeredRef.current = triggerKey;
    const timer = setTimeout(async () => {
      try {
        const {
          error
        } = await supabase.rpc("fanorona_bot_play", {
          _game_id: id
        });
        if (error) console.error("fanorona_bot_play error", error);
      } catch (e) {
        console.error("bot play failed", e);
      }
    }, 800 + Math.random() * 700);
    return () => clearTimeout(timer);
  }, [game?.status, game?.current_turn, moveCount, botChainFrom, id]);
  if (!loaded) return /* @__PURE__ */ jsxRuntimeExports.jsx(GameLoader, {});
  if (!game) return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-6 text-center space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-2xl", children: "😕" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: loadError || "Partie introuvable" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate({
      to: "/jeux"
    }), className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold", children: "Retour aux jeux" })
  ] });
  const replayFanorona = async () => {
    const isSolo = parts.some((p) => p.is_bot);
    if (isSolo) {
      const {
        data,
        error
      } = await supabase.rpc("fanorona_create_solo", {
        _stake: 0,
        _variant: game.variant || "tsivy",
        _mandatory_capture: game.mandatory_capture !== false,
        _bot_intelligence: 3
      });
      if (error) {
        toast.error(error.message);
        return;
      }
      refreshProfile();
      navigate({
        to: "/jeux/fanorona/$id",
        params: {
          id: data
        }
      });
    } else {
      const {
        data,
        error
      } = await supabase.rpc("fanorona_create", {
        _stake: Number(game.stake) || 0,
        _private: !!game.is_private,
        _commission: Number(game.commission_pct) || 10,
        _variant: game.variant || "tsivy",
        _mandatory_capture: game.mandatory_capture !== false
      });
      if (error) {
        toast.error(error.message);
        return;
      }
      refreshProfile();
      navigate({
        to: "/jeux/fanorona/$id",
        params: {
          id: data
        }
      });
    }
  };
  if (game.status === "cancelled") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx(GameStateMessage, { state: "cancelled", gameLabel: "Fanorona", slug: "fanorona" });
  }
  if (game.status === "open") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameWaitingRoom, { isTournament: !!game.tournament_match_id, slug: "fanorona", gameLabel: "Fanorona · 2 joueurs", parts, maxPlayers: 2, stake: Number(game.stake), pot: Number(game.pot), roomCode: game.room_code, meUserId: profile?.id, isParticipant: !!me, shareSlug: "fanorona", createdAt: game.created_at, onQuit: async () => {
      await supabase.rpc("fanorona_forfeit", {
        _game_id: id
      });
      navigate({
        to: "/jeux"
      });
    }, onToggleReady: async (ready) => {
      await supabase.rpc("fanorona_set_ready", {
        _game_id: id,
        _ready: ready
      });
    } }) });
  }
  const CELL_PX = 52;
  const SIZE_W = (COLS - 1) * CELL_PX;
  const SIZE_H = (ROWS - 1) * CELL_PX;
  const cx = (c) => c * CELL_PX;
  const cy = (r) => r * CELL_PX;
  let captureGeom = null;
  if (captureChoice) {
    const fr = Math.floor(captureChoice.from / COLS), fc = captureChoice.from % COLS;
    const tr = Math.floor(captureChoice.to / COLS), tc = captureChoice.to % COLS;
    const ddr = tr - fr, ddc = tc - fc;
    const angleApproach = Math.atan2(ddr, ddc) * 180 / Math.PI;
    const angleWithdrawal = angleApproach + 180;
    const midOf = (cells) => {
      const pts = cells.map((i) => ({
        x: cx(i % COLS),
        y: cy(Math.floor(i / COLS))
      }));
      return {
        x: pts.reduce((s, p) => s + p.x, 0) / pts.length,
        y: pts.reduce((s, p) => s + p.y, 0) / pts.length
      };
    };
    const perpLen = Math.hypot(ddc, ddr) || 1;
    const ux = -ddc / perpLen * 20, uy = ddr / perpLen * 20;
    const approachMid = midOf(captureChoice.approach);
    const withdrawalMid = midOf(captureChoice.withdrawal);
    captureGeom = {
      approachPos: {
        x: approachMid.x + ux,
        y: approachMid.y + uy
      },
      withdrawalPos: {
        x: withdrawalMid.x + ux,
        y: withdrawalMid.y + uy
      },
      angleApproach,
      angleWithdrawal
    };
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "h-full overflow-hidden flex flex-col bg-gradient-to-b from-stone-100 to-stone-200 dark:from-stone-900 dark:to-stone-950 overscroll-none", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyBanner, { stake: Number(game?.stake) || 0, phoneVerified: !!profile?.phone_verified }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameReconnectOverlay, { isConnected, isReconnecting, onRetry: retry }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-1.5 pt-0.5", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5", children: [
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
            _slug: "fanorona",
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
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: forfeit, className: "px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-2.5 h-2.5" }),
          " Quitter"
        ] })
      ] })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-1.5 mt-0.5", children: (() => {
      const opponent = parts.find((p) => p.user_id !== me?.user_id) ?? (me ? void 0 : parts[0]);
      if (!opponent) return /* @__PURE__ */ jsxRuntimeExports.jsx(FanoronaWaitingBar, {});
      const isCurrent = game.current_turn === opponent.slot && game.status === "playing";
      const pieceCount = opponent.color === "white" ? whiteCount : blackCount;
      return /* @__PURE__ */ jsxRuntimeExports.jsx(FanoronaPlayerBar, { p: opponent, isCurrent, isMe: false, pieceCount, timeMs: me?.color === "white" ? bTime : wTime, avatarUrl: opponent.user_id ? profiles[opponent.user_id]?.avatar_url : null });
    })() }),
    game.status === "finished" && /* @__PURE__ */ jsxRuntimeExports.jsx(GameEndScreen, { slug: "fanorona", meUserId: profile?.id, winnerId: game.winner_id, winnerSlot: game.winner_slot, participants: parts, stake: Number(game.stake), pot: Number(game.pot), commissionPct: Number(game.commission_pct) || 10, onReplay: replayFanorona }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 flex flex-col min-h-0 w-full p-1 gap-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-h-0 rounded-md overflow-hidden w-full flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("svg", { viewBox: rotated90 ? `-18 -18 ${SIZE_H + 36} ${SIZE_W + 36}` : `-18 -18 ${SIZE_W + 36} ${SIZE_H + 36}`, preserveAspectRatio: "xMidYMid meet", style: {
        width: "100%",
        height: "100%"
      }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("g", { transform: rotated90 ? `translate(${SIZE_H / 2 - SIZE_W / 2} ${SIZE_W / 2 - SIZE_H / 2}) rotate(${flipped ? 270 : 90} ${SIZE_W / 2} ${SIZE_H / 2})` : flipped ? `rotate(180 ${SIZE_W / 2} ${SIZE_H / 2})` : void 0, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("defs", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("radialGradient", { id: "wood-inner", cx: "50%", cy: "35%", r: "80%", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "0%", stopColor: "#d9a86a" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "60%", stopColor: "#a06b35" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "100%", stopColor: "#5e3618" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("radialGradient", { id: "white-stone", cx: "35%", cy: "30%", r: "70%", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "0%", stopColor: "#ffffff" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "55%", stopColor: "#ece4d2" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "100%", stopColor: "#8b806a" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("radialGradient", { id: "black-stone", cx: "35%", cy: "30%", r: "70%", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "0%", stopColor: "#5a5a5a" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "50%", stopColor: "#1d1d1d" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("stop", { offset: "100%", stopColor: "#000000" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("filter", { id: "stone-shadow", x: "-50%", y: "-50%", width: "200%", height: "200%", children: /* @__PURE__ */ jsxRuntimeExports.jsx("feDropShadow", { dx: "0", dy: "2", stdDeviation: "1.6", floodColor: "#000", floodOpacity: "0.55" }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("filter", { id: "capture-glow", x: "-50%", y: "-50%", width: "200%", height: "200%", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("feGaussianBlur", { stdDeviation: "3", result: "blur" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("feMerge", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("feMergeNode", { in: "blur" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("feMergeNode", { in: "SourceGraphic" })
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("rect", { x: -16, y: -16, width: SIZE_W + 32, height: SIZE_H + 32, rx: 8, fill: "url(#wood-inner)" }),
        Array.from({
          length: ROWS
        }).map((_, r) => Array.from({
          length: COLS
        }).map((_2, c) => {
          const here = idx(r, c);
          return neighbors(r, c).map(([dr, dc]) => {
            const r2 = r + dr, c2 = c + dc;
            if (r2 * COLS + c2 < here) return null;
            return /* @__PURE__ */ jsxRuntimeExports.jsxs("g", { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("line", { x1: cx(c), y1: cy(r) + 1, x2: cx(c2), y2: cy(r2) + 1, stroke: "rgba(0,0,0,0.55)", strokeWidth: 1.6, strokeLinecap: "round" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("line", { x1: cx(c), y1: cy(r), x2: cx(c2), y2: cy(r2), stroke: "rgba(255,225,180,0.85)", strokeWidth: 1, strokeLinecap: "round" })
            ] }, `${r}-${c}-${dr}-${dc}`);
          });
        })),
        board.map((_, i) => {
          const r = Math.floor(i / COLS), c = i % COLS;
          return /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(c), cy: cy(r), r: 4, fill: "rgba(0,0,0,0.35)" }, `s-${i}`);
        }),
        lastMove && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(lastMove.from % COLS), cy: cy(Math.floor(lastMove.from / COLS)), r: 16, fill: "rgba(255,235,59,0.25)" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(lastMove.to % COLS), cy: cy(Math.floor(lastMove.to / COLS)), r: 16, fill: "rgba(255,235,59,0.35)" })
        ] }),
        isMyTurn && !captureChoice && validTargets.size > 0 && Array.from(validTargets.entries()).map(([to, info]) => {
          const r = Math.floor(to / COLS), c = to % COLS;
          const hasCapture = info.approach.length > 0 || info.withdrawal.length > 0;
          return /* @__PURE__ */ jsxRuntimeExports.jsx("g", { children: hasCapture ? /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(c), cy: cy(r), r: 16, fill: "none", stroke: "#ef4444", strokeWidth: 2, opacity: 0.7, strokeDasharray: "4 2", children: /* @__PURE__ */ jsxRuntimeExports.jsx("animate", { attributeName: "r", values: "14;18;14", dur: "1s", repeatCount: "indefinite" }) }) : /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(c), cy: cy(r), r: 6, fill: "rgba(34,197,94,0.4)" }) }, `target-${to}`);
        }),
        board.map((v, i) => {
          const r = Math.floor(i / COLS), c = i % COLS;
          const isSel = selected === i || chainFrom === i;
          const isCaptured = animatingCapture.includes(i);
          if (v === 0) {
            return /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(c), cy: cy(r), r: 14, fill: "transparent", onClick: () => onCellClick(i), style: {
              cursor: isMyTurn && (selected !== null || chainFrom !== null) ? "pointer" : "default"
            } }, i);
          }
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("g", { onClick: () => onCellClick(i), style: {
            cursor: isMyTurn && (v === myColor || selected !== null || chainFrom !== null) ? "pointer" : "default",
            opacity: isCaptured ? 0.3 : 1,
            transition: "opacity 0.4s ease-out"
          }, children: [
            isSel && /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(c), cy: cy(r), r: 16, fill: "none", stroke: "#22c55e", strokeWidth: 2.5, opacity: 0.9, children: /* @__PURE__ */ jsxRuntimeExports.jsx("animate", { attributeName: "r", values: "14;18;14", dur: "1s", repeatCount: "indefinite" }) }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("ellipse", { cx: cx(c), cy: cy(r) + 2, rx: 11, ry: 3.5, fill: "rgba(0,0,0,0.45)" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(c), cy: cy(r), r: 11.5, fill: v === 1 ? "url(#white-stone)" : "url(#black-stone)", filter: isCaptured ? "url(#capture-glow)" : "url(#stone-shadow)" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("ellipse", { cx: cx(c) - 3.5, cy: cy(r) - 4, rx: 3.5, ry: 2, fill: v === 1 ? "rgba(255,255,255,0.85)" : "rgba(255,255,255,0.3)" })
          ] }, i);
        }),
        captureChoice && /* @__PURE__ */ jsxRuntimeExports.jsxs("g", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(captureChoice.to % COLS), cy: cy(Math.floor(captureChoice.to / COLS)), r: 13, fill: "none", stroke: "#fbbf24", strokeWidth: 2, opacity: 0.85, strokeDasharray: "3 2" }),
          captureChoice.approach.map((i) => /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(i % COLS), cy: cy(Math.floor(i / COLS)), r: 15, fill: "rgba(249,115,22,0.18)", stroke: "#f97316", strokeWidth: 3, opacity: 0.95, children: /* @__PURE__ */ jsxRuntimeExports.jsx("animate", { attributeName: "r", values: "13;17;13", dur: "0.9s", repeatCount: "indefinite" }) }, `appr-${i}`)),
          captureChoice.withdrawal.map((i) => /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: cx(i % COLS), cy: cy(Math.floor(i / COLS)), r: 15, fill: "rgba(56,189,248,0.18)", stroke: "#38bdf8", strokeWidth: 3, opacity: 0.95, children: /* @__PURE__ */ jsxRuntimeExports.jsx("animate", { attributeName: "r", values: "13;17;13", dur: "0.9s", repeatCount: "indefinite" }) }, `wd-${i}`)),
          captureGeom && /* @__PURE__ */ jsxRuntimeExports.jsxs("g", { onClick: () => sendMove({
            from: captureChoice.from,
            to: captureChoice.to,
            captured: captureChoice.approach,
            chain: false
          }), style: {
            cursor: "pointer"
          }, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: captureGeom.approachPos.x, cy: captureGeom.approachPos.y, r: 13, fill: "#f97316", stroke: "#fff", strokeWidth: 1.5 }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("path", { d: "M -4,-4.5 L 5.5,0 L -4,4.5 Z", fill: "#fff", transform: `translate(${captureGeom.approachPos.x},${captureGeom.approachPos.y}) rotate(${captureGeom.angleApproach})` })
          ] }),
          captureGeom && /* @__PURE__ */ jsxRuntimeExports.jsxs("g", { onClick: () => sendMove({
            from: captureChoice.from,
            to: captureChoice.to,
            captured: captureChoice.withdrawal,
            chain: false
          }), style: {
            cursor: "pointer"
          }, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("circle", { cx: captureGeom.withdrawalPos.x, cy: captureGeom.withdrawalPos.y, r: 13, fill: "#38bdf8", stroke: "#fff", strokeWidth: 1.5 }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("path", { d: "M -4,-4.5 L 5.5,0 L -4,4.5 Z", fill: "#fff", transform: `translate(${captureGeom.withdrawalPos.x},${captureGeom.withdrawalPos.y}) rotate(${captureGeom.angleWithdrawal})` })
          ] })
        ] })
      ] }) }) }),
      isMyTurn && chainFrom !== null && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: endTurn, className: "shrink-0 w-full py-1.5 rounded-full font-bold text-xs shadow-lg flex items-center justify-center gap-1.5 transition-all active:scale-95 bg-amber-100 text-amber-950 hover:bg-amber-200", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(SkipForward, { className: "w-3.5 h-3.5" }),
        "Arrêter la rafale"
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-1.5 pb-0.5", children: me && (() => {
      const isCurrent = game.current_turn === me.slot && game.status === "playing";
      const pieceCount = me.color === "white" ? whiteCount : blackCount;
      return /* @__PURE__ */ jsxRuntimeExports.jsx(FanoronaPlayerBar, { p: me, isCurrent, isMe: true, pieceCount, timeMs: me?.color === "white" ? wTime : bTime, avatarUrl: me.user_id ? profiles[me.user_id]?.avatar_url : null });
    })() }),
    game?.status === "playing" && globalTimer.enabled && globalTimer.remainingMs !== null && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `px-3 py-1 mx-2 rounded-lg text-center text-xs font-bold ${globalTimer.remainingMs <= 3e4 ? "bg-destructive/15 text-destructive animate-pulse" : "bg-amber-500/10 text-amber-600 dark:text-amber-400"}`, children: [
      "⏳ Temps global restant : ",
      globalTimer.remainingLabel
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GamePauseControl, { slug: "fanorona", gameId: id, game, remaining: Math.ceil((me?.color === "white" ? wTime : bTime) / 1e3), totalSeconds: cfg.turn_timer_seconds, isMyTurn: !!isMyTurn, isPlayer, myUserId: profile?.id ?? null }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(GameSocialFab, { gameId: id, gameSlug: "fanorona", participants: parts })
  ] });
}
export {
  FanoronaPage as component
};
