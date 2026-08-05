import { serverNow } from "@/lib/server-time";
import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import GameChatDrawer from "./GameChatDrawer";
import GameInstructionsBanner from "./GameInstructionsBanner";
import GamePauseControl from "./GamePauseControl";

type Color = "red" | "green" | "yellow" | "blue";
const COLORS: Color[] = ["red", "green", "yellow", "blue"];

function stepAnim(
  setter: React.Dispatch<React.SetStateAction<Record<string, { s: "yard"|"track"|"finished"; k: number }[]>>>,
  slot: string, idx: number, val: { s: "yard"|"track"|"finished"; k: number }, ms: number
): Promise<void> {
  return new Promise((resolve) => {
    setter(prev => {
      const next = { ...prev };
      const arr = [...(next[slot] || [])];
      arr[idx] = val;
      next[slot] = arr;
      return next;
    });
    setTimeout(resolve, ms);
  });
}

// ═══ VISUAL COLOR REMAPPING ══════════════════════════════════════════
// DB stores colors as "red","green","yellow","blue" for slot ordering.
// The board visually remaps them to match the classic Ludo layout:
//   DB red    → Visual Green  (top-left quadrant)
//   DB green  → Visual Yellow (top-right quadrant)
//   DB yellow → Visual Blue   (bottom-right quadrant)
//   DB blue   → Visual Red    (bottom-left quadrant)
// `name` is the DISPLAY name shown to users (matches the visual color).
// `hex/bg/text/soft/ring` all use the VISUAL color, not the DB color.
// ════════════════════════════════════════════════════════════════════
const COLOR_META: Record<Color, { name: string; hex: string; bg: string; text: string; soft: string; ring: string }> = {
  red:    { name: "Vert",  hex: "#16a34a", bg: "bg-green-500",  text: "text-green-700",  soft: "bg-green-200",  ring: "ring-green-600" },  // DB red → visual green (TL)
  green:  { name: "Jaune", hex: "#eab308", bg: "bg-yellow-400", text: "text-yellow-700", soft: "bg-yellow-200", ring: "ring-yellow-500" }, // DB green → visual yellow (TR)
  yellow: { name: "Bleu",  hex: "#2563eb", bg: "bg-blue-500",   text: "text-blue-700",   soft: "bg-blue-200",   ring: "ring-blue-600" },   // DB yellow → visual blue (BR)
  blue:   { name: "Rouge", hex: "#dc2626", bg: "bg-red-500",    text: "text-red-700",    soft: "bg-red-200",    ring: "ring-red-600" },    // DB blue → visual red (BL)
};

const PATH: [number, number][] = [
  [6,1],[6,2],[6,3],[6,4],[6,5],[5,6],[4,6],[3,6],[2,6],[1,6],[0,6],[0,7],[0,8],
  [1,8],[2,8],[3,8],[4,8],[5,8],[6,9],[6,10],[6,11],[6,12],[6,13],[6,14],[7,14],[8,14],
  [8,13],[8,12],[8,11],[8,10],[8,9],[9,8],[10,8],[11,8],[12,8],[13,8],[14,8],[14,7],[14,6],
  [13,6],[12,6],[11,6],[10,6],[9,6],[8,5],[8,4],[8,3],[8,2],[8,1],[8,0],[7,0],[6,0],
];
const START_IDX: Record<Color, number> = { red: 0, green: 13, yellow: 26, blue: 39 };
const HOME_STRETCH: Record<Color, [number, number][]> = {
  red:    [[7,1],[7,2],[7,3],[7,4],[7,5],[7,6]],
  green:  [[1,7],[2,7],[3,7],[4,7],[5,7],[6,7]],
  yellow: [[7,13],[7,12],[7,11],[7,10],[7,9],[7,8]],
  blue:   [[13,7],[12,7],[11,7],[10,7],[9,7],[8,7]],
};
const YARD_SPOTS: Record<Color, [number, number][]> = {
  red:    [[1.6,1.6],[1.6,3.4],[3.4,1.6],[3.4,3.4]],     // TL
  green:  [[1.6,10.6],[1.6,12.4],[3.4,10.6],[3.4,12.4]], // TR
  yellow: [[10.6,10.6],[10.6,12.4],[12.4,10.6],[12.4,12.4]], // BR
  blue:   [[10.6,1.6],[10.6,3.4],[12.4,1.6],[12.4,3.4]], // BL
};
// Safe cells (path indices) — stars
const SAFE_PATH_IDX = new Set<number>([0, 8, 13, 21, 26, 34, 39, 47]);

interface Participant {
  id: string; user_id: string | null; slot: number; color: Color;
  is_bot: boolean; display_name: string; forfeited: boolean; missed_turns: number;
  bot_intelligence?: number; bot_win_bias?: number;
  afk_t1?: number; afk_t2?: number;
  team?: number | null;
}
interface GameState {
  pawns: Record<string, { s: "yard"|"track"|"finished"; k: number }[]>;
  turn_slot: number;
  dice: number | null;
  must_move: boolean;
  turn_started_at: string;
  last_event?: string;
}

interface Props {
  gameId: string;
  state: GameState;
  participants: Participant[];
  myUserId: string | null;
  isSpectator: boolean;
  status: string;
  isAdmin?: boolean;
  paused?: boolean;
  pauseDeadline?: string | null;
  afkWarning?: any | null;
  afkPauseFor?: string | null;
  matchType?: string;
}

export default function RealtimeLudoBoard({ gameId, state, participants, myUserId, isSpectator, status, isAdmin, paused, pauseDeadline, afkWarning, afkPauseFor, matchType }: Props) {
  const [boardSize, setBoardSize] = useState(600);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(serverNow());
  const [rollingFace, setRollingFace] = useState<number | null>(null);
  const [displayedPawns, setDisplayedPawns] = useState<GameState["pawns"]>(state.pawns);
  const [animating, setAnimating] = useState(false);
  const [afkMax, setAfkMax] = useState<{t1:number;t2:number;secs:number}>({ t1: 2, t2: 2, secs: 30 });
  const lastBotKey = useRef<string>("");
  const lastPassKey = useRef<string>("");
  const lastTimeoutKey = useRef<string>("");
  const animQueueRef = useRef<Promise<void>>(Promise.resolve());

  // Rebrand bots as "Joueur N" (cartoon-only, no "Bot" or robot emoji)
  const botIndex = new Map<string, number>();
  participants.filter(p => p.is_bot).sort((a, b) => a.slot - b.slot).forEach((b, i) => botIndex.set(b.id, i + 1));
  const nameOf = (p: Participant) => p.is_bot ? `Joueur ${botIndex.get(p.id) ?? p.slot}` : p.display_name;

  useEffect(() => {
    supabase.from("app_settings").select("afk_t1_max,afk_t2_max,turn_seconds").eq("id",1).maybeSingle().then(({ data }: any) => {
      if (data) setAfkMax({ t1: data.afk_t1_max ?? 2, t2: data.afk_t2_max ?? 2, secs: data.turn_seconds ?? 30 });
    });
  }, []);


  // Animate pawn movement step-by-step when state.pawns changes
  useEffect(() => {
    const target = state.pawns || {};
    const current = displayedPawns || {};
    // Find diffs
    const moves: Array<{ slot: string; idx: number; from: { s: string; k: number }; to: { s: string; k: number } }> = [];
    const captures: Array<{ slot: string; idx: number }> = [];
    for (const slot of Object.keys(target)) {
      const tArr = target[slot] || [];
      const cArr = current[slot] || [];
      tArr.forEach((tp, i) => {
        const cp = cArr[i];
        if (!cp) return;
        if (cp.s === tp.s && cp.k === tp.k) return;
        // Capture: target is yard from track
        if (tp.s === "yard" && cp.s === "track") {
          captures.push({ slot, idx: i });
        } else {
          moves.push({ slot, idx: i, from: { s: cp.s, k: cp.k }, to: { s: tp.s, k: tp.k } });
        }
      });
    }
    if (moves.length === 0 && captures.length === 0) {
      // Sync silently (e.g. initial load, turn changes only)
      setDisplayedPawns(target);
      return;
    }
    // Animate sequentially
    animQueueRef.current = animQueueRef.current.then(async () => {
      setAnimating(true);
      for (const m of moves) {
        const fromK = m.from.s === "yard" ? -1 : m.from.k;
        const toK = m.to.s === "yard" ? -1 : m.to.k;
        if (m.from.s === "yard" && m.to.s === "track") {
          // Pop out to k=0 in one step
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k: 0 }, 200);
          continue;
        }
        if (m.to.s === "finished") {
          // Walk through home stretch then mark finished
          for (let k = fromK + 1; k <= 56; k++) {
            await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k }, 35);
          }
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "finished", k: 56 }, 30);
          continue;
        }
        // Track → track: glide quickly cell by cell
        for (let k = fromK + 1; k <= toK; k++) {
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k }, 35);
        }
      }
      // Then apply captures
      for (const c of captures) {
        await stepAnim(setDisplayedPawns, c.slot, c.idx, { s: "yard", k: -1 }, 200);
      }
      // Final sync
      setDisplayedPawns(target);
      setAnimating(false);
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.pawns]);
  

  useEffect(() => {
    const u = () => {
      const vh = window.innerHeight, vw = window.innerWidth;
      setBoardSize(Math.max(320, Math.min(vh - 320, vw - 40, 820)));
    };
    u(); window.addEventListener("resize", u); return () => window.removeEventListener("resize", u);
  }, []);

  useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 500);
    return () => clearInterval(t);
  }, []);

  const partsBySlot = useMemo(() => {
    const m = new Map<number, Participant>();
    participants.forEach(p => m.set(p.slot, p));
    return m;
  }, [participants]);

  const currentPart = partsBySlot.get(state.turn_slot);
  const isMyTurn = !!currentPart && !currentPart.is_bot && currentPart.user_id === myUserId && !isSpectator && status === "playing";
  const turnStartMs = state.turn_started_at ? new Date(state.turn_started_at).getTime() : now;
  const elapsed = Math.max(0, Math.floor((now - turnStartMs) / 1000));
  const remaining = Math.max(0, afkMax.secs - elapsed);

  useEffect(() => {
    if (status !== "playing" || !currentPart?.is_bot) return;
    if (animating) return;
    const key = `${state.turn_slot}-${state.dice}-${state.must_move}-${state.turn_started_at}`;
    if (lastBotKey.current === key) return;
    lastBotKey.current = key;
    // Humanized delay: 1.5-3.5s before rolling, 2-4.5s to see dice before moving
    const min = state.must_move ? 2000 : 1500;
    const max = state.must_move ? 4500 : 3500;
    const delay = min + Math.random() * (max - min);
    const t = setTimeout(async () => {
      try { await supabase.rpc("ludo_bot_play" as any, { _game_id: gameId } as any); } catch {}
    }, delay);
    return () => clearTimeout(t);
  }, [currentPart?.is_bot, state.turn_slot, state.dice, state.must_move, state.turn_started_at, status, gameId, animating]);

  useEffect(() => {
    if (status !== "playing") return;
    if (paused) return; // game is paused — don't auto-advance turn
    if (remaining > 0) return;
    const key = `${state.turn_slot}-${state.turn_started_at}`;
    if (lastTimeoutKey.current === key) return;
    lastTimeoutKey.current = key;
    const t = setTimeout(async () => {
      const { error } = await supabase.rpc("ludo_check_timeout" as any, { _game_id: gameId } as any);
      if (error) toast.error("Le changement de tour automatique a échoué");
    }, 600);
    return () => clearTimeout(t);
  }, [remaining, status, gameId, state.turn_slot, state.turn_started_at]);

  const roll = async () => {
    if (!isMyTurn || state.must_move || busy) return;
    setBusy(true);
    // Visual roll animation
    const start = Date.now();
    const anim = setInterval(() => {
      setRollingFace(1 + Math.floor(Math.random() * 6));
      if (Date.now() - start > 700) clearInterval(anim);
    }, 80);
    try {
      const { error } = await supabase.rpc("ludo_roll" as any, { _game_id: gameId } as any);
      if (error) toast.error(error.message);
    } finally {
      setTimeout(() => { setRollingFace(null); setBusy(false); }, 750);
    }
  };

  const movablePawnIdxs = useMemo(() => {
    if (!isMyTurn || !state.must_move || state.dice == null) return new Set<number>();
    const slot = state.turn_slot;
    const arr = state.pawns?.[String(slot)] || [];
    const set = new Set<number>();
    arr.forEach((p, i) => {
      if (p.s === "finished") return;
      if (p.s === "yard") { if (state.dice === 6) set.add(i); }
      else if (p.k + (state.dice as number) <= 56) set.add(i);
    });
    return set;
  }, [isMyTurn, state.must_move, state.dice, state.turn_slot, state.pawns]);

  // Selection state: hides indicators immediately once the user picks a pawn,
  // and is reset only when the turn key actually changes.
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const turnKey = `${state.turn_slot}-${state.turn_started_at}-${state.dice ?? "x"}`;
  const lastTurnKeyRef = useRef<string>("");
  useEffect(() => {
    if (lastTurnKeyRef.current !== turnKey) {
      lastTurnKeyRef.current = turnKey;
      setSelectedIdx(null);
    }
  }, [turnKey]);

  // Use a ref-based guard so a second pointer event can't slip through
  // between setBusy() scheduling and the next render.
  const moveLockRef = useRef(false);
  const movePawn = async (idx: number) => {
    if (moveLockRef.current) return;
    if (!movablePawnIdxs.has(idx) || busy || animating) return;
    moveLockRef.current = true;
    setSelectedIdx(idx);
    setBusy(true);
    try { const { error } = await supabase.rpc("ludo_move" as any, { _game_id: gameId, _pawn_idx: idx } as any); if (error) { toast.error(error.message); setSelectedIdx(null); } }
    finally { setBusy(false); moveLockRef.current = false; }
  };

  // Auto-pass: if it's my turn and I rolled but no pawn can move, skip after a short delay
  useEffect(() => {
    if (!isMyTurn || !state.must_move || state.dice == null) return;
    if (movablePawnIdxs.size > 0) return;
    const key = `${state.turn_slot}-${state.dice}-${state.turn_started_at}`;
    if (lastPassKey.current === key) return;
    lastPassKey.current = key;
    const t = setTimeout(async () => {
      const { error } = await supabase.rpc("ludo_pass" as any, { _game_id: gameId } as any);
      if (error) console.warn("pass rpc", error);
      else toast.info(`Aucun coup possible avec ${state.dice}`);
    }, 1200);
    return () => clearTimeout(t);
  }, [isMyTurn, state.must_move, state.dice, state.turn_slot, state.turn_started_at, movablePawnIdxs, gameId]);

  // Auto-move: if only one pawn can move, play it immediately (no artificial delay).
  // Keyed on turn_started_at (server timestamp) so it fires exactly once per turn,
  // même après reconnexion / re-render causés par la latence réseau.
  const lastAutoMoveKey = useRef<string>("");
  useEffect(() => {
    if (!isMyTurn || !state.must_move || state.dice == null) return;
    if (movablePawnIdxs.size !== 1) return;
    if (busy || animating) return;
    const key = `${gameId}-${state.turn_slot}-${state.dice}-${state.turn_started_at}`;
    if (lastAutoMoveKey.current === key) return;
    lastAutoMoveKey.current = key;
    const only = movablePawnIdxs.values().next().value as number;
    // Micro-tâche: laisse React committer, puis déclenche sans délai perceptible.
    queueMicrotask(() => { movePawn(only); });
  }, [isMyTurn, state.must_move, state.dice, state.turn_slot, state.turn_started_at, movablePawnIdxs, gameId, busy, animating]);

  // Persist last movable set so indicators stay visible across brief RPC/animation gaps.
  // Cleared only when the turn key changes or when the user selects a pawn.
  const stickyMovableRef = useRef<{ key: string; indices: Set<number> }>({ key: "", indices: new Set() });
  if (isMyTurn && state.must_move && state.dice != null && movablePawnIdxs.size > 0) {
    stickyMovableRef.current = { key: turnKey, indices: new Set(movablePawnIdxs) };
  }
  const visibleMovable: Set<number> = (() => {
    if (selectedIdx !== null) return new Set<number>();
    if (movablePawnIdxs.size > 0) return movablePawnIdxs;
    if (stickyMovableRef.current.key === turnKey) return stickyMovableRef.current.indices;
    return new Set<number>();
  })();
  const showMarkers = isMyTurn && state.must_move && state.dice != null && visibleMovable.size > 0;



  const cellPx = boardSize / 15;

  const renderPawns: { key: string; slot: number; idx: number; color: Color; row: number; col: number; movable: boolean }[] = [];
  const cellGroups = new Map<string, number>();
  participants.forEach(part => {
    const arr = displayedPawns?.[String(part.slot)] || [];
    arr.forEach((p, i) => {
      let row: number, col: number;
      if (p.s === "yard") {
        [row, col] = YARD_SPOTS[part.color][i];
      } else if (p.s === "finished") {
        // Each color lands on its own center triangle:
        // top→green, right→yellow, bottom→blue, left→red
        const offsets: Record<Color, [number, number]> = {
          green:  [6.35, 7.0],
          yellow: [7.0,  7.65],
          blue:   [7.65, 7.0],
          red:    [7.0,  6.35],
        };
        [row, col] = offsets[part.color];
      } else {
        let cell: [number, number];
        if (p.k <= 50) cell = PATH[(START_IDX[part.color] + p.k) % 52];
        else cell = HOME_STRETCH[part.color][p.k - 51];
        row = cell[0]; col = cell[1];
        const key = `${row}-${col}`;
        const n = cellGroups.get(key) || 0;
        cellGroups.set(key, n + 1);
        if (n > 0) {
          const angle = (n / 4) * Math.PI * 2;
          row += Math.sin(angle) * 0.18;
          col += Math.cos(angle) * 0.18;
        }
      }
      renderPawns.push({
        key: `${part.slot}-${i}`,
        slot: part.slot, idx: i, color: part.color, row, col,
        movable: part.slot === state.turn_slot && visibleMovable.has(i),
      });
    });
  });

  // Visual quadrant defs (matching image): TL=green, TR=yellow, BR=blue, BL=red
  const quadrants: { color: Color; r: number; c: number }[] = [
    { color: "red",    r: 0, c: 0  }, // TL → green visuals
    { color: "green",  r: 0, c: 9  }, // TR → yellow visuals
    { color: "yellow", r: 9, c: 9  }, // BR → blue visuals
    { color: "blue",   r: 9, c: 0  }, // BL → red visuals
  ];

  return (
    <div className="flex flex-col items-center gap-3">
      <div className="w-full px-2"><GameInstructionsBanner slug="ludo" /></div>
      {/* Players: 2 on a single row, 4 in a 2x2 square */}
      {(() => {
        const twoMode = participants.length === 2;
        const slotColors: Color[] = twoMode
          ? (participants.map(pp => pp.color) as Color[])
          : (["red","green","blue","yellow"] as Color[]);
        return (
          <div className={`grid w-full max-w-xs gap-2 justify-items-center ${twoMode ? "grid-cols-2 grid-rows-1" : "grid-cols-2 grid-rows-2"}`}>
            {slotColors.map((slotColor) => {
              const p = participants.find(pp => pp.color === slotColor);
              if (!p) return <div key={slotColor} />;
              const isCurrent = p.slot === state.turn_slot && status === "playing";
              const pawnArr = state.pawns?.[String(p.slot)] || [];
              const finishedCount = pawnArr.filter(pw => pw?.s === "finished").length;
              const totalPawns = pawnArr.length || 4;
              return (
                <div key={p.id}
                  className={`flex w-full items-center gap-2 rounded-xl bg-card px-3 py-1.5 shadow ring-2 transition ${
                    isCurrent ? `${COLOR_META[p.color].ring} scale-105` : "ring-transparent opacity-70"
                  } ${p.forfeited ? "line-through opacity-40" : ""}`}>
                  <div className="relative shrink-0">
                    <div className={`h-5 w-5 rounded-full ${COLOR_META[p.color].bg} ${isCurrent ? "animate-pulse" : ""}`} />
                    <span
                      title={`${finishedCount}/${totalPawns} pions arrivés`}
                      className={`absolute -right-1.5 -top-1.5 flex h-4 min-w-4 items-center justify-center rounded-full border border-white bg-emerald-500 px-1 text-[9px] font-bold leading-none text-white shadow`}
                    >
                      {finishedCount}
                    </span>
                  </div>
                  <div className="flex min-w-0 flex-col leading-tight">
                    <div className="flex items-center gap-1.5">
                      <span className={`truncate text-sm font-semibold ${COLOR_META[p.color].text}`}>{nameOf(p)}</span>
                      {matchType === "groupe" && p.team && (
                        <span className={`text-[9px] px-1.5 py-0.5 rounded-full font-bold shrink-0 ${p.team === 1 ? "bg-red-500/15 text-red-600" : "bg-blue-500/15 text-blue-600"}`}>
                          {p.team === 1 ? "🔴 G1" : "🔵 G2"}
                        </span>
                      )}
                    </div>
                    <span className="text-[10px] font-medium text-emerald-600">🏁 {finishedCount}/{totalPawns}</span>
                    {!p.is_bot && (
                      <span className="text-[10px] text-muted-foreground">
                        T1 {p.afk_t1 ?? 0}/{afkMax.t1} · T2 {p.afk_t2 ?? 0}/{afkMax.t2}
                      </span>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        );
      })()}

      {/* Board */}
      <div className="relative overflow-hidden rounded-xl bg-white shadow-2xl ring-2 ring-slate-800"
           style={{ width: boardSize, height: boardSize }}>

        {/* Quadrants (full color background) */}
        {quadrants.map(q => (
          <div key={q.color} className="absolute"
            style={{ left: q.c*cellPx, top: q.r*cellPx, width: 6*cellPx, height: 6*cellPx, background: COLOR_META[q.color].hex }} />
        ))}

        {/* Path cells (cross arms only) */}
        <PathCells cellPx={cellPx} />

        {/* Center triangles */}
        <CenterTriangles cellPx={cellPx} />

        {/* Yard inner white rect + 4 dots per quadrant */}
        {quadrants.map(q => {
          const meta = COLOR_META[q.color];
          const innerLeft = (q.c + 1) * cellPx;
          const innerTop  = (q.r + 1) * cellPx;
          const innerSize = 4 * cellPx;
          return (
            <div key={`yard-${q.color}`}>
              <div className="absolute rounded-2xl bg-white shadow-inner"
                style={{ left: innerLeft, top: innerTop, width: innerSize, height: innerSize, border: `2px solid ${meta.hex}` }} />
              {YARD_SPOTS[q.color].map((p, i) => (
                <div key={i} className="absolute rounded-full"
                  style={{
                    left: (p[1] + 0.5) * cellPx - cellPx * 0.45,
                    top:  (p[0] + 0.5) * cellPx - cellPx * 0.45,
                    width: cellPx * 0.9, height: cellPx * 0.9,
                    background: meta.hex, opacity: 0.85,
                  }} />
              ))}
            </div>
          );
        })}

        {/* Move-target indicators removed — the animated pawn itself signals playability */}


        {/* Pawns */}
        {renderPawns.map(p => {
          const meta = COLOR_META[p.color];
          // Deep, saturated pawn colors + dark tint to stay legible on same-color cells
          const PAWN_HEX: Record<Color, { deep: string; dark: string }> = {
            red:    { deep: "#00A63E", dark: "#064e2b" }, // vert
            green:  { deep: "#F59E0B", dark: "#5c3a00" }, // jaune
            yellow: { deep: "#1D4ED8", dark: "#0b1f5c" }, // bleu
            blue:   { deep: "#DC2626", dark: "#5c0a0a" }, // rouge
          };
          const pc = PAWN_HEX[p.color];
          // Movable pawns get a full-cell hit area (with visible pawn centered
          // inside via padding). Non-movable pawns render at the visual size only.
          const hitPad = p.movable ? 0 : cellPx * 0.14;
          const hitSize = p.movable ? cellPx : cellPx * 0.72;
          const visualInset = p.movable ? cellPx * 0.14 : 0;
          return (
            <button key={p.key}
              onPointerDown={p.movable ? (e) => { e.preventDefault(); movePawn(p.idx); } : undefined}
              onClick={p.movable ? (e) => { e.preventDefault(); } : undefined}
              disabled={!p.movable}
              className="absolute flex items-center justify-center rounded-full p-0 outline-none border-0 bg-transparent select-none"
              style={{
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
                padding: visualInset,
              }}>
              <div
                className={`relative rounded-full w-full h-full ${p.movable ? "ludo-playable" : ""}`}
                style={{
                  background: `radial-gradient(circle at 30% 25%, #ffffff 0%, rgba(255,255,255,0.35) 6%, ${pc.deep} 20%, ${pc.deep} 60%, ${pc.dark} 100%)`,
                  boxShadow: `inset 0 0 0 1px rgba(255,255,255,0.35), inset -2px -3px 6px rgba(0,0,0,0.55), inset 2px 2px 4px rgba(255,255,255,0.3), 0 4px 8px rgba(0,0,0,0.55), 0 1px 2px rgba(0,0,0,0.4)`,
                  filter: "saturate(1.35) contrast(1.1)",
                }}>
                <span className="absolute rounded-full pointer-events-none"
                      style={{
                        left: "18%", top: "12%", width: "38%", height: "28%",
                        background: "radial-gradient(ellipse at center, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0) 70%)",
                        filter: "blur(0.5px)",
                      }} />
              </div>
            </button>
          );

        })}

      </div>

      {/* Bottom HUD */}
      <div className="flex flex-col items-center gap-1.5">
        <div className="text-xs text-muted-foreground">
          {isSpectator ? "Mode spectateur" :
            status !== "playing" ? "En attente du démarrage…" :
            currentPart && (currentPart.is_bot ? `${nameOf(currentPart)} joue…` :
            isMyTurn ? (state.must_move ? `Tu as fait ${state.dice}, choisis un pion` : "À toi de lancer le dé") :
            `Tour de ${nameOf(currentPart)}`)}
        </div>
        {status === "playing" && (
          <div className={`text-sm font-bold ${remaining <= 5 ? "text-destructive animate-pulse" : "text-muted-foreground"}`}>
            ⏱ {remaining}s
            {currentPart && !currentPart.is_bot && (
              <> · T1 {currentPart.afk_t1 ?? 0}/{afkMax.t1} · T2 {currentPart.afk_t2 ?? 0}/{afkMax.t2}</>
            )}
          </div>
        )}
        {isAdmin && status === "playing" && currentPart && (
          <div className="rounded-2xl bg-amber-100 border border-amber-300 px-3 py-2 flex flex-wrap items-center gap-2 text-xs">
            <span className="font-bold text-amber-900">🎲 Admin — forcer le dé de {currentPart.display_name} :</span>
            {[1,2,3,4,5,6].map(n => (
              <button key={n} onClick={async () => {
                const { error } = await supabase.rpc("super_player_set_dice" as any, { _game_id: gameId, _slot: state.turn_slot, _value: n } as any);
                if (error) toast.error(error.message); else toast.success(`Prochain dé: ${n}`);
              }} className="w-7 h-7 rounded-lg bg-white font-bold hover:bg-amber-200">{n}</button>
            ))}
          </div>
        )}
        <button onClick={roll}
          disabled={!isMyTurn || state.must_move || busy}
          className={`group relative h-20 w-20 rounded-2xl bg-card shadow-xl ring-2 transition ${
            currentPart ? COLOR_META[currentPart.color].ring : "ring-slate-300"
          } ${isMyTurn && !state.must_move ? "hover:scale-110 active:scale-95" : "opacity-60"} ${rollingFace !== null ? "animate-spin" : ""}`}>
          <DiceFace value={rollingFace ?? state.dice ?? 0} />
        </button>
        {state.dice != null && rollingFace === null && (
          <div className="text-lg font-extrabold text-foreground">Dé : {state.dice}</div>
        )}

      </div>
      <GamePauseControl
        slug="ludo"
        gameId={gameId}
        game={{
          paused: paused ?? false,
          pause_deadline: pauseDeadline ?? null,
          afk_warning: afkWarning ?? null,
          afk_pause_for: afkPauseFor ?? null,
          status,
        }}
        remaining={remaining}
        totalSeconds={afkMax.secs}
        isMyTurn={isMyTurn}
        isPlayer={!isSpectator && participants.some(p => p.user_id === myUserId && !p.is_bot)}
        myUserId={myUserId}
        simplePause={participants.some(p => p.is_bot)}
      />
      <GameChatDrawer gameId={gameId} isAdmin={isAdmin} />
    </div>
  );
}


function PathCells({ cellPx }: { cellPx: number }) {
  const cells: React.ReactNode[] = [];
  // Cross strip cells: rows 6-8 all cols, plus cols 6-8 all rows (except center 3x3 handled separately)
  for (let r = 0; r < 15; r++) {
    for (let c = 0; c < 15; c++) {
      const inCross = (r >= 6 && r <= 8) || (c >= 6 && c <= 8);
      if (!inCross) continue;
      const inCenter = r >= 6 && r <= 8 && c >= 6 && c <= 8;
      if (inCenter) continue;

      // Determine fill: home stretch or start cell
      let fill = "#ffffff";
      // Home stretch (visual mapping):
      // top vertical (col 7, rows 1..6) → yellow (DB green)
      // bottom vertical (col 7, rows 8..13) → red (DB blue)
      // left horizontal (row 7, cols 1..6) → green (DB red)
      // right horizontal (row 7, cols 8..13) → blue (DB yellow)
      if (c === 7 && r >= 1 && r <= 5) fill = COLOR_META.green.hex;        // yellow stretch
      else if (c === 7 && r >= 9 && r <= 13) fill = COLOR_META.blue.hex;   // red stretch
      else if (r === 7 && c >= 1 && c <= 5) fill = COLOR_META.red.hex;     // green stretch
      else if (r === 7 && c >= 9 && c <= 13) fill = COLOR_META.yellow.hex; // blue stretch

      // Start cells
      const startCells: { rc: [number, number]; color: Color }[] = [
        { rc: PATH[START_IDX.red],    color: "red" },     // green start
        { rc: PATH[START_IDX.green],  color: "green" },   // yellow start
        { rc: PATH[START_IDX.yellow], color: "yellow" },  // blue start
        { rc: PATH[START_IDX.blue],   color: "blue" },    // red start
      ];
      const startMatch = startCells.find(s => s.rc[0] === r && s.rc[1] === c);
      if (startMatch) fill = COLOR_META[startMatch.color].hex;

      // Star cells
      const pathIdx = PATH.findIndex(([pr, pc]) => pr === r && pc === c);
      const isStar = pathIdx >= 0 && SAFE_PATH_IDX.has(pathIdx);

      cells.push(
        <div key={`${r}-${c}`} className="absolute"
          style={{
            left: c*cellPx, top: r*cellPx, width: cellPx, height: cellPx,
            background: `linear-gradient(135deg, rgba(255,255,255,0.35) 0%, rgba(255,255,255,0) 45%, rgba(0,0,0,0.18) 100%), ${fill}`,
            border: "1px solid #1f2937",
            boxShadow: "inset 1px 1px 0 rgba(255,255,255,0.5), inset -1px -1px 0 rgba(0,0,0,0.22)",
          }}>
          {isStar && (
            <svg viewBox="0 0 24 24" className="absolute inset-0 m-auto" width={cellPx*0.7} height={cellPx*0.7}>
              <path d="M12 2 L14.4 8.6 L21.5 9 L16 13.5 L17.7 20.5 L12 16.5 L6.3 20.5 L8 13.5 L2.5 9 L9.6 8.6 Z"
                fill="none" stroke="#1f2937" strokeWidth="1.5" strokeLinejoin="round" />
            </svg>
          )}
          {startMatch && (
            <ArrowGlyph color="white" cellPx={cellPx}
              dir={
                startMatch.color === "red"    ? "right" :  // green start (left arm) points right toward center
                startMatch.color === "green"  ? "down"  :  // yellow start (top arm) points down
                startMatch.color === "yellow" ? "left"  :  // blue start (right arm) points left
                                                 "up"      // red start (bottom arm) points up
              } />
          )}
        </div>
      );
    }
  }
  return <>{cells}</>;
}

function ArrowGlyph({ dir, cellPx, color }: { dir: "up"|"down"|"left"|"right"; cellPx: number; color: string }) {
  const rot = { up: 0, right: 90, down: 180, left: 270 }[dir];
  return (
    <svg viewBox="0 0 24 24" className="absolute inset-0 m-auto" width={cellPx*0.6} height={cellPx*0.6}
      style={{ transform: `rotate(${rot}deg)` }}>
      <path d="M12 4 L20 14 L14 14 L14 20 L10 20 L10 14 L4 14 Z" fill={color} stroke="#1f2937" strokeWidth="1" />
    </svg>
  );
}

function CenterTriangles({ cellPx }: { cellPx: number }) {
  const x = 6 * cellPx, size = 3 * cellPx;
  // Top→yellow (DB green), Right→blue (DB yellow), Bottom→red (DB blue), Left→green (DB red)
  return (
    <svg className="absolute" style={{ left: x, top: x, width: size, height: size }} viewBox="0 0 100 100">
      <polygon points="0,0 100,0 50,50" fill={COLOR_META.green.hex} stroke="#1f2937" strokeWidth="0.5" />
      <polygon points="100,0 100,100 50,50" fill={COLOR_META.yellow.hex} stroke="#1f2937" strokeWidth="0.5" />
      <polygon points="100,100 0,100 50,50" fill={COLOR_META.blue.hex} stroke="#1f2937" strokeWidth="0.5" />
      <polygon points="0,100 0,0 50,50" fill={COLOR_META.red.hex} stroke="#1f2937" strokeWidth="0.5" />
    </svg>
  );
}

function DiceFace({ value }: { value: number }) {
  const dots: Record<number, number[]> = { 0: [], 1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8] };
  return (
    <div className="grid h-full w-full grid-cols-3 grid-rows-3 gap-1 p-3">
      {Array.from({ length: 9 }).map((_, i) => (
        <div key={i} className="flex items-center justify-center">
          {dots[value]?.includes(i) && <div className="h-2.5 w-2.5 rounded-full bg-slate-800" />}
        </div>
      ))}
    </div>
  );
}
