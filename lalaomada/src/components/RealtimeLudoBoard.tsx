import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import GameChatDrawer from "./GameChatDrawer";
import GameInstructionsBanner from "./GameInstructionsBanner";
import GamePauseControl from "./GamePauseControl";
import { useGameSounds } from "@/hooks/use-game-sounds";
import { HAPTICS } from "@/lib/haptics";
import QuickReactions from "./QuickReactions";

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

// DB color names ("red","green","yellow","blue") drive server logic.
// Visual mapping: TL=red, TR=green, BR=yellow, BL=blue (standard Ludo layout).
const COLOR_META: Record<Color, { name: string; hex: string; dark: string; bg: string; text: string; soft: string; ring: string; light: string }> = {
  red:    { name: "Rouge", hex: "#CC0000", dark: "#880000", bg: "bg-red-600",    text: "text-red-700",    soft: "bg-red-100",    ring: "ring-red-600",    light: "#ffb3b3" },
  green:  { name: "Vert",  hex: "#1A9A1A", dark: "#0A5200", bg: "bg-green-600",  text: "text-green-700",  soft: "bg-green-100",  ring: "ring-green-600",  light: "#b3e6b3" },
  yellow: { name: "Jaune", hex: "#DDAA00", dark: "#7A5800", bg: "bg-yellow-500", text: "text-yellow-800", soft: "bg-yellow-100", ring: "ring-yellow-500", light: "#fff0b3" },
  blue:   { name: "Bleu",  hex: "#1155CC", dark: "#0A2E80", bg: "bg-blue-600",   text: "text-blue-700",   soft: "bg-blue-100",   ring: "ring-blue-600",   light: "#b3ccff" },
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
  red:    [[1.5,1.5],[1.5,3.5],[3.5,1.5],[3.5,3.5]],     // TL
  green:  [[1.5,10.5],[1.5,12.5],[3.5,10.5],[3.5,12.5]], // TR
  yellow: [[10.5,10.5],[10.5,12.5],[12.5,10.5],[12.5,12.5]], // BR
  blue:   [[10.5,1.5],[10.5,3.5],[12.5,1.5],[12.5,3.5]], // BL
};
// Safe cells (path indices) — stars
const SAFE_PATH_IDX = new Set<number>([0, 8, 13, 21, 26, 34, 39, 47]);

interface Participant {
  id: string; user_id: string | null; slot: number; color: Color;
  is_bot: boolean; display_name: string; forfeited: boolean; missed_turns: number;
  bot_intelligence?: number; bot_win_bias?: number;
  afk_t1?: number; afk_t2?: number;
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
}

export default function RealtimeLudoBoard({ gameId, state, participants, myUserId, isSpectator, status, isAdmin, paused, pauseDeadline, afkWarning, afkPauseFor }: Props) {
  const [boardSize, setBoardSize] = useState(600);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now());
  const [rollingFace, setRollingFace] = useState<number | null>(null);
  const [displayedPawns, setDisplayedPawns] = useState<GameState["pawns"]>(state.pawns);
  const [animating, setAnimating] = useState(false);
  // Ref mirror of animating so the bot-play effect can check it without
  // having "animating" in its dependency array (which caused the phase-2
  // timeout to be cleared whenever animation briefly toggled, leaving the
  // bot stuck forever after rolling).
  const animatingRef = useRef(false);
  animatingRef.current = animating;
  const [afkMax, setAfkMax] = useState<{t1:number;t2:number;secs:number}>({ t1: 2, t2: 2, secs: 30 });
  const lastBotKey = useRef<string>("");
  const lastPassKey = useRef<string>("");
  const lastTimeoutKey = useRef<string>("");
  const animQueueRef = useRef<Promise<void>>(Promise.resolve());
  const lastTurnSlotRef = useRef<number>(-1);
  const lastStatusRef = useRef<string>("");
  const [showVictory, setShowVictory] = useState(false);

  // Rebrand bots as "Joueur N" (cartoon-only, no "Bot" or robot emoji)
  const botIndex = new Map<string, number>();
  participants.filter(p => p.is_bot).sort((a, b) => a.slot - b.slot).forEach((b, i) => botIndex.set(b.id, i + 1));
  const nameOf = (p: Participant) => p.is_bot ? `Joueur ${botIndex.get(p.id) ?? p.slot}` : p.display_name;
  const [soundEnabled, setSoundEnabled] = useState(() => {
    try { return localStorage.getItem("ludo-sound") !== "off"; } catch { return true; }
  });
  const toggleSound = () => {
    setSoundEnabled(prev => {
      const next = !prev;
      try { localStorage.setItem("ludo-sound", next ? "on" : "off"); } catch {}
      return next;
    });
  };
  const { play: playSound, announce } = useGameSounds(!isSpectator && soundEnabled);

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
        if (!tp || typeof tp.s !== "string") return;
        const cp = cArr[i];
        if (!cp) return;
        if (cp.s === tp.s && (cp.k ?? 0) === (tp.k ?? 0)) return;
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
      try {
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
        playSound("capture");
        HAPTICS.capture();
      }
      if (moves.length > 0) { playSound("pawn-move"); HAPTICS.move(); }
      // Final sync
      setDisplayedPawns(target);
      setAnimating(false);
      } catch (e) { console.error("anim error", e); setDisplayedPawns(target); setAnimating(false); }
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.pawns]);
  

  useEffect(() => {
    const u = () => {
      const vh = window.innerHeight, vw = window.innerWidth;
      // Keep 80px top + 140px bottom HUD + 20px margin
      const reserved = 80 + 140 + 20;
      setBoardSize(Math.max(280, Math.min(vh - reserved, vw - 16, 480)));
    };
    u(); window.addEventListener("resize", u); return () => window.removeEventListener("resize", u);
  }, []);

  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 500);
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

  // Play sounds on turn change and victory
  useEffect(() => {
    if (lastTurnSlotRef.current !== -1 && lastTurnSlotRef.current !== state.turn_slot && status === "playing") {
      playSound("turn-change", 0.3);
      HAPTICS.turn();
      if (isMyTurn) announce("À ton tour");
    }
    lastTurnSlotRef.current = state.turn_slot;
  }, [state.turn_slot, status, isMyTurn, playSound, announce]);

  // Victory sound when game ends
  useEffect(() => {
    if (lastStatusRef.current === "playing" && status === "finished") {
      playSound("victory");
      HAPTICS.victory();
      const winner = participants.find(p => !p.forfeited);
      if (winner) announce(`${nameOf(winner)} gagne`);
    }
    lastStatusRef.current = status;
  }, [status, participants, playSound, announce]);


  // Bot auto-play: uses animatingRef (not the state) so that animation toggling
  // doesn't cancel the pending phase-2 timeout.  The bot waits for any active
  // Bot auto-play: call ludo_bot_play after a humanized delay.
  // The server function rolls AND moves/passes in one call (single-phase).
  useEffect(() => {
    if (status !== "playing" || !currentPart?.is_bot) return;
    if (animating) return;
    const key = `${state.turn_slot}-${state.dice}-${state.must_move}-${state.turn_started_at}`;
    if (lastBotKey.current === key) return;
    lastBotKey.current = key;
    // Humanized delay: 2-5s before rolling, 2-6s before moving after roll
    const min = state.must_move ? 2000 : 2000;
    const max = state.must_move ? 6000 : 5000;
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
    playSound("dice-roll");
    HAPTICS.dice();
    // Visual roll animation
    const start = Date.now();
    const anim = setInterval(() => {
      setRollingFace(1 + Math.floor(Math.random() * 6));
      if (Date.now() - start > 700) clearInterval(anim);
    }, 80);
    try {
      const { error } = await supabase.rpc("ludo_roll" as any, { _game_id: gameId } as any);
      if (error) toast.error(error.message);
    } catch (e) {
      console.error("roll error", e);
      toast.error("Erreur lors du lancer de dé");
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
      if (!p || typeof p.s !== "string") return;
      if (p.s === "finished") return;
      if (p.s === "yard") { if (state.dice === 6) set.add(i); }
      else if ((p.k ?? 0) + (state.dice as number) <= 56) set.add(i);
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
    catch (e) { console.error("move error", e); toast.error("Erreur lors du déplacement"); setSelectedIdx(null); }
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
      try {
        const { error } = await supabase.rpc("ludo_pass" as any, { _game_id: gameId } as any);
        if (error) console.warn("pass rpc", error);
        else toast.info(`Aucun coup possible avec ${state.dice}`);
      } catch (e) { console.error("pass error", e); }
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
    // Small delay so the player sees the dice result before auto-move
    const t = setTimeout(() => { movePawn(only); }, 700);
    return () => clearTimeout(t);
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
      if (!p || typeof p.s !== "string") return;
      let row: number, col: number;
      if (p.s === "yard") {
        const spots = YARD_SPOTS[part.color as Color];
        [row, col] = spots?.[i] ?? [7, 7];
      } else if (p.s === "finished") {
        const offsets: Record<Color, [number, number]> = {
          green:  [6.35, 7.0],
          yellow: [7.0,  7.65],
          blue:   [7.65, 7.0],
          red:    [7.0,  6.35],
        };
        [row, col] = offsets[part.color as Color] ?? [7, 7];
      } else {
        let cell: [number, number] | undefined;
        const startIdx = START_IDX[part.color as Color];
        const stretch = HOME_STRETCH[part.color as Color];
        if (startIdx !== undefined && p.k <= 50) cell = PATH[(startIdx + p.k) % 52];
        else if (stretch !== undefined && p.k >= 51 && p.k <= 56) cell = stretch[p.k - 51];
        if (!cell) { row = 7; col = 7; } else { row = cell[0]; col = cell[1]; }
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

  // Visual quadrant defs: TL=red, TR=green, BR=yellow, BL=blue
  const quadrants: { color: Color; r: number; c: number }[] = [
    { color: "red",    r: 0, c: 0  }, // TL → red
    { color: "green",  r: 0, c: 9  }, // TR → green
    { color: "yellow", r: 9, c: 9  }, // BR → yellow
    { color: "blue",   r: 9, c: 0  }, // BL → blue
  ];

  return (
    <div className="flex flex-col items-center gap-2 p-2" style={{ background: "#16163a" }}>
      <div className="w-full px-2"><GameInstructionsBanner slug="ludo" /></div>
      {/* Players HUD */}
      {(() => {
        const twoMode = participants.length === 2;
        const slotColors: Color[] = twoMode
          ? (participants.map(pp => pp.color) as Color[])
          : (["red","green","blue","yellow"] as Color[]);
        return (
          <div className={`grid w-full max-w-sm gap-2 justify-items-center ${twoMode ? "grid-cols-2 grid-rows-1" : "grid-cols-2 grid-rows-2"}`}>
            {slotColors.map((slotColor) => {
              const p = participants.find(pp => pp.color === slotColor);
              if (!p) return <div key={slotColor} />;
              const isCurrent = p.slot === state.turn_slot && status === "playing";
              const pawnArr = state.pawns?.[String(p.slot)] || [];
              const finishedCount = pawnArr.filter(pw => pw?.s === "finished").length;
              const totalPawns = pawnArr.length || 4;
              const meta = COLOR_META[p.color as Color];
              return (
                <div key={p.id}
                  className="flex w-full items-center gap-2.5 rounded-xl px-3 py-2 transition-all"
                  style={{
                    background: isCurrent ? (meta?.hex ?? "#333") + "33" : "rgba(255,255,255,0.08)",
                    border: `2px solid ${isCurrent ? (meta?.hex ?? "#333") : "transparent"}`,
                    opacity: p.forfeited ? 0.4 : 1,
                  }}>
                  <div className="relative shrink-0">
                    <div className={`h-8 w-8 rounded-full ${meta?.bg ?? "bg-slate-400"} ${isCurrent ? "turn-active-glow animate-pulse" : ""}`}
                      style={{
                        boxShadow: isCurrent
                          ? `0 0 12px ${meta?.hex ?? "#94a3b8"}99, inset 0 1px 2px rgba(255,255,255,0.3)`
                          : "inset 0 1px 2px rgba(255,255,255,0.2), 0 1px 3px rgba(0,0,0,0.15)",
                        border: `2px solid ${meta?.hex ?? "#94a3b8"}`
                      }} />
                    <span
                      title={`${finishedCount}/${totalPawns} pions arrivés`}
                      className="absolute -right-1 -top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-emerald-500 px-1 text-[9px] font-bold leading-none text-white shadow border border-white">
                      {finishedCount}
                    </span>
                  </div>
                  <div className="flex min-w-0 flex-col leading-tight">
                    <span className="truncate text-xs font-bold text-white">{nameOf(p)}</span>
                    <span className="text-[10px] font-medium text-emerald-400">🏁 {finishedCount}/{totalPawns}</span>
                    {!p.is_bot && (
                      <span className="text-[9px] text-white/50">
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
      <div className="relative overflow-hidden"
           style={{
             width: boardSize, height: boardSize,
             background: "#ffffff",
             boxShadow: "0 6px 24px rgba(0,0,0,0.6), 0 0 0 3px #111",
             borderRadius: 4,
           }}>

        {/* Quadrants — active players colored, inactive gray */}
        {quadrants.map(q => {
          const meta = COLOR_META[q.color as Color];
          const hasPlayer = participants.some(pp => pp.color === q.color);
          const bg = hasPlayer ? meta.hex : "#bbb";
          const bgDark = hasPlayer ? meta.dark : "#999";
          return (
            <div key={q.color} className="absolute"
              style={{
                left: q.c*cellPx, top: q.r*cellPx, width: 6*cellPx, height: 6*cellPx,
                background: hasPlayer
                  ? `linear-gradient(145deg, ${meta.hex}ee 0%, ${meta.hex} 60%, ${meta.dark} 100%)`
                  : `linear-gradient(145deg, #bbbbbb 0%, #cccccc 60%, #999999 100%)`,
                opacity: hasPlayer ? 1 : 0.5,
              }} />
          );
        })}

        {/* Path cells (cross arms only) */}
        <PathCells cellPx={cellPx} />

        {/* Center triangles */}
        <CenterTriangles cellPx={cellPx} />

        {/* Yard inner white rect + 4 dots per quadrant */}
        {quadrants.map(q => {
          const meta = COLOR_META[q.color as Color];
          const innerLeft = (q.c + 1) * cellPx;
          const innerTop  = (q.r + 1) * cellPx;
          const innerSize = 4 * cellPx;
          // Check if this quadrant has a participant (2-player mode: inactive corners are gray)
          const hasPlayer = participants.some(pp => pp.color === q.color);
          const cornerColor = hasPlayer ? meta.hex : "#aaa";
          const cornerDark = hasPlayer ? meta.dark : "#888";
          return (
            <div key={`yard-${q.color}`}>
              <div className="absolute"
                style={{ left: innerLeft, top: innerTop, width: innerSize, height: innerSize, background: "#ffffff", border: `2.5px solid ${cornerColor}`, borderRadius: 10, opacity: hasPlayer ? 1 : 0.4 }} />
              {(YARD_SPOTS[q.color as Color] || []).map((p, i) => (
                <div key={i} className="absolute rounded-full"
                  style={{
                    left: (p[1] + 0.5) * cellPx - cellPx * 0.35,
                    top:  (p[0] + 0.5) * cellPx - cellPx * 0.35,
                    width: cellPx * 0.7, height: cellPx * 0.7,
                    background: hasPlayer ? "rgba(255,255,255,0.85)" : "rgba(255,255,255,0.5)",
                    border: `2.5px solid ${cornerColor}`,
                    borderRadius: "50%",
                    opacity: hasPlayer ? 1 : 0.3,
                  }} />
              ))}
            </div>
          );
        })}

        {/* Move-target indicators removed — the animated pawn itself signals playability */}


        {/* Pawns */}
        {renderPawns.map(p => {
          const meta = COLOR_META[p.color as Color];
          const pc = { deep: meta.hex, dark: meta.dark };
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
              <LudoPawn color={pc} movable={p.movable} />
            </button>
          );

        })}

      </div>

      {/* Bottom HUD */}
      <div className="flex flex-col items-center gap-1.5">
        <div className="text-xs text-white/70 text-center">
          {isSpectator ? "Mode spectateur" :
            status !== "playing" ? "En attente du démarrage…" :
            currentPart && (currentPart.is_bot
              ? (state.dice != null
                ? `🎲 ${nameOf(currentPart)} a lancé: ${state.dice} — en cours de jeu…`
                : `${nameOf(currentPart)} joue…`)
              : isMyTurn
                ? (state.must_move ? `🎲 Tu as fait ${state.dice} — choisis un pion` : "À toi de lancer le dé !")
                : (state.dice != null
                  ? `🎲 ${nameOf(currentPart)} a lancé: ${state.dice} — en attente de son coup…`
                  : `Tour de ${nameOf(currentPart)}`))}
        </div>
        {status === "playing" && (
          <>
          <div className={`text-sm font-bold ${remaining <= 5 ? "text-red-400 animate-pulse" : "text-white/60"}`}>
            ⏱ {remaining}s
            {currentPart && !currentPart.is_bot && (
              <span className="ml-2 text-xs font-medium text-white/50">
                · AFK {currentPart.afk_t1 ?? 0}/{afkMax.t1} | {currentPart.afk_t2 ?? 0}/{afkMax.t2}
              </span>
            )}
          </div>
          {/* Timer bar */}
          {status === "playing" && !paused && (
            <div className="h-1.5 w-32 rounded-full bg-white/10 overflow-hidden">
              <div className="h-full rounded-full transition-all duration-500"
                style={{
                  width: `${Math.max(0, (remaining / afkMax.secs) * 100)}%`,
                  background: remaining <= 5 ? "#ef4444" : remaining <= 10 ? "#f59e0b" : "#22c55e",
                }} />
            </div>
          )}
          </>
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
        <button
          onClick={toggleSound}
          title={soundEnabled ? "Couper le son" : "Activer le son"}
          className="mb-1 flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold transition bg-white/10 text-white/70 hover:bg-white/20 border border-white/10"
        >
          {soundEnabled ? "🔊 Son" : "🔇 Muet"}
        </button>
        <button onClick={roll}
          disabled={!isMyTurn || state.must_move || busy}
          className={`group relative h-[76px] w-[76px] rounded-2xl shadow-lg ring-2 transition ${
            currentPart ? (COLOR_META[currentPart.color as Color]?.ring ?? "ring-slate-300") : "ring-slate-300"
          } ${isMyTurn && !state.must_move ? "hover:scale-110 active:scale-95" : "opacity-50"} ${rollingFace !== null ? "animate-spin" : ""}`}
          style={{
            background: "radial-gradient(circle at 35% 30%, #f8f8f8 0%, #e0e0e0 50%, #aaa 100%)",
            boxShadow: "0 4px 16px rgba(0,0,0,0.4), inset 0 1px 2px rgba(255,255,255,0.8), inset 0 -1px 2px rgba(0,0,0,0.2)",
            border: "1px solid rgba(139,94,60,0.15)",
          }}>
          <DiceFace value={rollingFace ?? state.dice ?? 0} rolling={rollingFace !== null} />
        </button>
        {state.dice != null && rollingFace === null && (
          <div className="text-base font-bold text-foreground">🎲 {state.dice}</div>
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
      <QuickReactions gameId={gameId} myUserId={myUserId} myName={participants.find(p => p.user_id === myUserId)?.display_name || "Joueur"} />
      <GameChatDrawer gameId={gameId} isAdmin={isAdmin} />
    </div>
  );
}



function LudoPawn({ color, movable }: { color: { deep: string; dark: string }; movable: boolean }) {
  const { deep, dark } = color;
  const id = `pg-${deep.replace("#","")}`;
  return (
    <svg viewBox="0 0 40 40" className={`w-full h-full ${movable ? "ludo-playable" : ""}`} style={{ overflow: "visible" }}>
      <defs>
        <radialGradient id={`${id}-g`} cx="35%" cy="30%" r="70%">
          <stop offset="0%" stopColor="#ffffff" stopOpacity="0.9" />
          <stop offset="20%" stopColor={deep} stopOpacity="0.6" />
          <stop offset="60%" stopColor={deep} />
          <stop offset="100%" stopColor={dark} />
        </radialGradient>
      </defs>
      {/* Drop shadow */}
      <ellipse cx="21" cy="38" rx="11" ry="3" fill="rgba(0,0,0,0.28)" />
      {/* Main circle */}
      <circle cx="20" cy="19" r="16"
        fill={`url(#${id}-g)`}
        stroke={dark}
        strokeWidth={movable ? "2.5" : "1.5"}
      />
      {/* Outer ring like image pions */}
      <circle cx="20" cy="19" r="16"
        fill="none"
        stroke="rgba(255,255,255,0.45)"
        strokeWidth="2"
      />
      {/* Shine */}
      <ellipse cx="13" cy="11" rx="5" ry="3.5" fill="rgba(255,255,255,0.6)" />
      {/* Movable pulse ring */}
      {movable && <circle cx="20" cy="19" r="18" fill="none" stroke="rgba(255,255,255,0.8)" strokeWidth="1.5" strokeDasharray="4 3" />}
    </svg>
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
      if (c === 7 && r >= 1 && r <= 5) fill = COLOR_META.green.hex;        // green stretch
      else if (c === 7 && r >= 9 && r <= 13) fill = COLOR_META.blue.hex;   // blue stretch
      else if (r === 7 && c >= 1 && c <= 5) fill = COLOR_META.red.hex;     // red stretch
      else if (r === 7 && c >= 9 && c <= 13) fill = COLOR_META.yellow.hex; // yellow stretch

      // Start cells
      const startCells: { rc: [number, number]; color: Color }[] = [
        { rc: PATH[START_IDX.red],    color: "red" },     // red start
        { rc: PATH[START_IDX.green],  color: "green" },   // green start
        { rc: PATH[START_IDX.yellow], color: "yellow" },  // yellow start
        { rc: PATH[START_IDX.blue],   color: "blue" },    // blue start
      ];
      const startMatch = startCells.find(s => s.rc[0] === r && s.rc[1] === c);
      if (startMatch) fill = COLOR_META[startMatch.color as Color]?.hex ?? "#94a3b8";

      // Star cells
      const pathIdx = PATH.findIndex(([pr, pc]) => pr === r && pc === c);
      const isStar = pathIdx >= 0 && SAFE_PATH_IDX.has(pathIdx);

      cells.push(
        <div key={`${r}-${c}`} className="absolute"
          style={{
            left: c*cellPx, top: r*cellPx, width: cellPx, height: cellPx,
            background: fill,
            border: "1px solid #000000",
            
          }}>
          {isStar && (
            <svg viewBox="0 0 24 24" className="absolute inset-0 m-auto" width={cellPx*0.7} height={cellPx*0.7}>
              <path d="M12 2 L14.4 8.6 L21.5 9 L16 13.5 L17.7 20.5 L12 16.5 L6.3 20.5 L8 13.5 L2.5 9 L9.6 8.6 Z"
                fill="rgba(200,200,200,0.3)" stroke="rgba(150,150,150,0.7)" strokeWidth="1.2" strokeLinejoin="round" />
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
      <path d="M12 4 L20 14 L14 14 L14 20 L10 20 L10 14 L4 14 Z" fill="rgba(255,255,255,0.9)" stroke="rgba(0,0,0,0.2)" strokeWidth="0.5" />
    </svg>
  );
}

function CenterTriangles({ cellPx }: { cellPx: number }) {
  const x = 6 * cellPx, size = 3 * cellPx;
  // Top→yellow (DB green), Right→blue (DB yellow), Bottom→red (DB blue), Left→green (DB red)
  return (
    <svg className="absolute" style={{ left: x, top: x, width: size, height: size }} viewBox="0 0 100 100">
      <defs>
        <radialGradient id="ctr-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="#fff" stopOpacity="0.35" />
          <stop offset="100%" stopColor="#fff" stopOpacity="0" />
        </radialGradient>
      </defs>
      <polygon points="0,0 100,0 50,50" fill={COLOR_META.green.hex} stroke="#000000" strokeWidth="1" />
      <polygon points="100,0 100,100 50,50" fill={COLOR_META.yellow.hex} stroke="#000000" strokeWidth="1" />
      <polygon points="100,100 0,100 50,50" fill={COLOR_META.blue.hex} stroke="#000000" strokeWidth="1" />
      <polygon points="0,100 0,0 50,50" fill={COLOR_META.red.hex} stroke="#000000" strokeWidth="1" />
      <circle cx="50" cy="50" r="22" fill="url(#ctr-glow)" />
      <path d="M50 32 L54.5 44 L67 44.5 L57 52 L60.5 64 L50 57 L39.5 64 L43 52 L33 44.5 L45.5 44 Z"
        fill="rgba(255,255,255,0.9)" stroke="rgba(0,0,0,0.2)" strokeWidth="0.8" strokeLinejoin="round" />
    </svg>
  );
}

function DiceFace({ value, rolling }: { value: number; rolling?: boolean }) {
  const dots: Record<number, number[]> = { 0: [], 1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8] };
  return (
    <div className={`grid h-full w-full grid-cols-3 grid-rows-3 gap-1 p-3 ${rolling ? "dice-3d-rolling" : ""}`}>
      {Array.from({ length: 9 }).map((_, i) => (
        <div key={i} className="flex items-center justify-center">
          {dots[value]?.includes(i) && (
            <div className="rounded-full"
              style={{
                width: "60%", height: "60%",
                background: "radial-gradient(circle at 35% 30%, #2c3e50 0%, #1a1a2e 60%, #0f0f1e 100%)",
                boxShadow: "inset 0 2px 3px rgba(255,255,255,0.15), inset -1px -2px 3px rgba(0,0,0,0.4), 0 1px 1px rgba(255,255,255,0.3)",
              }} />
          )}
        </div>
      ))}
    </div>
  );
}
