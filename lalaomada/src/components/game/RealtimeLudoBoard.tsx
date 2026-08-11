import { serverNow } from "@/lib/server-time";
import { useEffect, useMemo, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import GameInstructionsBanner from "./GameInstructionsBanner";
import GamePauseControl from "./GamePauseControl";
import { sfx, setMuted as setSfxMuted, isMuted as isSfxMuted } from "@/lib/game-sounds";

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
  no_move_display?: { slot: number; dice: number; until: string };
  power_tiles?: { type: string; cell: number; cd?: number }[];
  shields?: Record<string, boolean>;
  double_roll_pending?: number | null;
  power_event?: { type: string; slot: number; reward?: string; dice?: number; pawn?: number; cell?: number; at: string };
  power_pending?: { tile_type: string; options: string[]; slot: number };
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
  onStateUpdate?: (newState: GameState) => void;
}


// Power tile icons for Mode Moderne
const POWER_TILE_META: Record<string, { icon: string; label: string; color: string }> = {
  boost:       { icon: "🚀", label: "Boost",      color: "#a855f7" },  // violet
  shield:      { icon: "🛡️", label: "Bouclier",   color: "#14b8a6" },  // teal
  double_roll: { icon: "⚡", label: "2e Lancer",  color: "#f472b6" },  // rose
  lucky_star:  { icon: "⭐", label: "Chance",     color: "#fbbf24" },  // or
};

// CSS animations for power tile effects
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
@keyframes diceRoll3D {
  0%   { transform: rotateX(0deg) rotateY(0deg) rotateZ(0deg) scale(1); }
  10%  { transform: rotateX(180deg) rotateY(90deg) rotateZ(45deg) scale(1.15); }
  20%  { transform: rotateX(360deg) rotateY(180deg) rotateZ(90deg) scale(1.1); }
  30%  { transform: rotateX(540deg) rotateY(270deg) rotateZ(135deg) scale(1.2); }
  40%  { transform: rotateX(720deg) rotateY(360deg) rotateZ(180deg) scale(1.05); }
  50%  { transform: rotateX(900deg) rotateY(450deg) rotateZ(225deg) scale(1.15); }
  60%  { transform: rotateX(1080deg) rotateY(540deg) rotateZ(270deg) scale(1.1); }
  70%  { transform: rotateX(1260deg) rotateY(630deg) rotateZ(315deg) scale(1.2); }
  80%  { transform: rotateX(1440deg) rotateY(720deg) rotateZ(360deg) scale(1.05); }
  90%  { transform: rotateX(1620deg) rotateY(810deg) rotateZ(405deg) scale(1.1); }
  100% { transform: rotateX(1800deg) rotateY(900deg) rotateZ(450deg) scale(1); }
}
.dice-tumbling {
  animation: diceRoll3D 0.6s ease-out infinite;
  transform-style: preserve-3d;
  perspective: 200px;
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

export default function RealtimeLudoBoard({ gameId, state, participants, myUserId, isSpectator, status, isAdmin, paused, pauseDeadline, afkWarning, afkPauseFor, matchType, onStateUpdate }: Props) {
  const [boardSize, setBoardSize] = useState(600);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(serverNow());
  const [rollingFace, setRollingFace] = useState<number | null>(null);
  const [displayedPawns, setDisplayedPawns] = useState<GameState["pawns"]>(state.pawns);
  const [animating, setAnimating] = useState(false);
  const [afkMax, setAfkMax] = useState<{t1:number;t2:number;secs:number}>({ t1: 2, t2: 2, secs: 30 });
  const [avatarMap, setAvatarMap] = useState<Record<string, string>>({});
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const [pawnPowerEffect, setPawnPowerEffect] = useState<{ slot: number; type: string; key: string; pawn?: number } | null>(null);
  const [displayedPowerTiles, setDisplayedPowerTiles] = useState(state.power_tiles);
  const [doubleRollPhase, setDoubleRollPhase] = useState<{ slot: number; phase: "2x" | "1x" } | null>(null);
  const [boardPowerEffect, setBoardPowerEffect] = useState<{ cell: number; type: string; key: string } | null>(null);
  const prevPowerTilesRef = useRef(state.power_tiles);
  const pendingPowerTilesRef = useRef<typeof state.power_tiles | null>(null);
  const powerEventCellRef = useRef<number | null>(null);
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

  // Fetch real player avatars (bots get a generated Dicebear avatar instead)
  const humanUserIds = participants.filter(p => !p.is_bot && p.user_id).map(p => p.user_id as string);
  const humanUserIdsKey = humanUserIds.slice().sort().join(",");
  useEffect(() => {
    if (humanUserIds.length === 0) return;
    supabase.from("profiles").select("id, avatar_url").in("id", humanUserIds).then(({ data }: any) => {
      if (!data) return;
      const map: Record<string, string> = {};
      data.forEach((r: any) => { if (r.avatar_url) map[r.id] = r.avatar_url; });
      setAvatarMap(map);
    });
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [humanUserIdsKey]);

  const avatarOf = (p: Participant) => {
    if (p.is_bot) return `https://api.dicebear.com/7.x/adventurer/svg?seed=joueur${botIndex.get(p.id) ?? p.slot}`;
    return p.user_id ? avatarMap[p.user_id] : undefined;
  };


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
          sfx.pawnMove();
          continue;
        }
        if (m.to.s === "finished") {
          // Walk through home stretch then mark finished
          for (let k = fromK + 1; k <= 56; k++) {
            await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k }, 35);
            sfx.pawnStep();
          }
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "finished", k: 56 }, 30);
          sfx.home();
          continue;
        }
        // Track → track: glide quickly cell by cell
        for (let k = fromK + 1; k <= toK; k++) {
          await stepAnim(setDisplayedPawns, m.slot, m.idx, { s: "track", k }, 35);
          sfx.pawnStep();
        }
      }
      // Then apply captures
      for (const c of captures) {
        sfx.capture();
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
    const t = setInterval(() => setNow(serverNow()), 1000);
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
    // Phase 1: must_move=false → roll dice ONLY (so player sees the result)
    // Phase 2: must_move=true → bot_play to choose & move pawn (dice already visible)
    const min = state.must_move ? 2500 : 1500;
    const max = state.must_move ? 4500 : 3500;
    const delay = min + Math.random() * (max - min);
    const t = setTimeout(async () => {
      try {
        if (state.must_move) {
          // Dice already rolled & visible — now move the pawn
          await supabase.rpc("ludo_bot_play" as any, { _game_id: gameId } as any);
        } else {
          // Roll first — player will see the dice, then this effect fires again
          await supabase.rpc("ludo_roll" as any, { _game_id: gameId } as any);
        }
      } catch {}
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
      // Silent — timeout failures are usually race conditions (game ended, turn already advanced)
    }, 600);
    return () => clearTimeout(t);
  }, [remaining, status, gameId, state.turn_slot, state.turn_started_at]);

  const roll = async () => {
    if (!isMyTurn || state.must_move || busy) return;
    setBusy(true);
    sfx.diceRoll();
    // Visual roll animation — keep tumbling until RPC responds
    const anim = setInterval(() => {
      setRollingFace(1 + Math.floor(Math.random() * 6));
    }, 80);
    // Safety timeout: if RPC takes > 5s, force-clear the animation
    const safety = setTimeout(() => {
      clearInterval(anim);
      setRollingFace(null);
      setBusy(false);
    }, 5000);
    try {
      const { data: rollData, error } = await supabase.rpc("ludo_roll" as any, { _game_id: gameId } as any);
      if (rollData && onStateUpdate) onStateUpdate(rollData as GameState);
      if (error) {
        const friendlyMap: Record<string, string> = {
          "Partie pas en cours": "La partie est terminée",
          "Pas votre tour": "Ce n'est pas votre tour",
          "Déjà lancé, déplacez un pion": "Vous avez déjà lancé le dé",
        };
        toast.error(friendlyMap[error.message] || error.message, { duration: 2000 });
      }
    } finally {
      clearTimeout(safety);
      clearInterval(anim);
      // Short delay so the player sees the final face before clearing
      setTimeout(() => { setRollingFace(null); setBusy(false); sfx.diceLand(); }, 300);
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
      // Reset busy state when turn changes — prevents stuck button if a
      // previous roll's RPC timed out without reaching finally
      setBusy(false);
      setRollingFace(null);
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
    try { const { data: moveData, error } = await supabase.rpc("ludo_move" as any, { _game_id: gameId, _pawn_idx: idx } as any);
        if (moveData && onStateUpdate) onStateUpdate(moveData as GameState);
        if (error) {
          const friendlyMap: Record<string, string> = {
            "Partie pas en cours": "La partie est terminée",
            "Pas votre tour": "Ce n'est pas votre tour",
            "Pion inconnu": "Pion invalide",
            "Pion deja arrive": "Ce pion est déjà arrivé",
            "Sortie possible avec un 6": "Il faut un 6 pour sortir un pion",
            "Depassement": "Déplacement impossible",
          };
          toast.error(friendlyMap[error.message] || error.message, { duration: 2000 });
          setSelectedIdx(null);
        }
      }
    finally { setBusy(false); moveLockRef.current = false; }
  };

  // No-move display: the backend already passed the turn, but includes
  // no_move_display = { slot, dice, until } so the frontend can visually
  // show the dice + previous player's frame for 1 second before updating.
  const [noMoveDisplay, setNoMoveDisplay] = useState<{ slot: number; dice: number } | null>(null);
  useEffect(() => {
    const nmd = state.no_move_display;
    if (nmd && nmd.until) {
      const untilMs = new Date(nmd.until).getTime();
      const nowMs = Date.now();
      if (untilMs > nowMs) {
        // Still within the 1-second display window — show dice + previous player frame
        setNoMoveDisplay({ slot: nmd.slot, dice: nmd.dice });
        const t = setTimeout(() => setNoMoveDisplay(null), untilMs - nowMs);
        return () => clearTimeout(t);
      }
    }
    setNoMoveDisplay(null);
  }, [state.no_move_display]);

  // When no_move_display is active, show the previous player's slot + dice
  const displaySlot = noMoveDisplay ? noMoveDisplay.slot : state.turn_slot;
  const displayDice = noMoveDisplay ? noMoveDisplay.dice : state.dice;
  const displayPart = partsBySlot.get(displaySlot) || currentPart;

  // Power event display (Mode Moderne) — sound + pawn visual effect
  const lastPowerEventRef = useRef<string>("");
  useEffect(() => {
    const pe = state.power_event;
    if (!pe || !pe.at) return;
    const key = `${pe.type}-${pe.at}-${pe.slot}`;
    if (lastPowerEventRef.current === key) return;
    lastPowerEventRef.current = key;
    const tileType = pe.reward || pe.type;
    sfx.powerTile(tileType);
    // Toast notification
    const toastMsgs: Record<string, string> = {
      boost: `🚀 Boost ! +${pe.dice || "?"} cases`,
      shield: "🛡️ Bouclier activé !",
      double_roll: "⚡ Deuxième lancer !",
      lucky_star: `⭐ Chance : ${pe.reward || "?"}`,
      reroll: "🎲 Re-lancer !",
      free_pawn: "🎁 Pion gratuit sorti !",
    };
    let msg = toastMsgs[pe.reward || pe.type] || toastMsgs[pe.type] || "Pouvoir activé";
    const isMyPowerEvent = participants.some(p => p.slot === pe.slot && p.user_id === myUserId);
    const isBotPower = participants.some(p => p.slot === pe.slot && p.is_bot);
    if (isMyPowerEvent) {
      toast.success(msg, { duration: 2500 });
    } else if (!isBotPower) {
      toast.info(msg, { duration: 1500 });
    }
    // Pawn visual effect based on power type
    const effectType = pe.reward || pe.type;
    setPawnPowerEffect({ slot: pe.slot, type: effectType, key, pawn: pe.pawn });
    setTimeout(() => setPawnPowerEffect(null), 1500);
    // Board-level effect: BUG 3 FIX — use pe.cell from backend instead of searching by type
    const eventCell = pe.cell;
    if (eventCell !== undefined && eventCell !== null) {
      setBoardPowerEffect({ cell: eventCell, type: effectType, key });
      setTimeout(() => setBoardPowerEffect(null), 1800);
    }
  }, [state.power_event]);

  // Delayed power tiles update — wait for pawn animation to ACTUALLY finish before relocating tiles
  // When a power_event fires, we store the new tiles in a ref and only apply them
  // once `animating` goes false (pawn has truly arrived on the cell).
  useEffect(() => {
    const pe = state.power_event;
    if (pe && pe.at) {
      // A power was just activated — store the new tiles for deferred application
      pendingPowerTilesRef.current = state.power_tiles;
      // If not currently animating, apply immediately
      if (!animating) {
        setDisplayedPowerTiles(state.power_tiles);
        pendingPowerTilesRef.current = null;
      }
    } else {
      // No power event — sync immediately
      setDisplayedPowerTiles(state.power_tiles);
      pendingPowerTilesRef.current = null;
    }
    prevPowerTilesRef.current = state.power_tiles;
  }, [state.power_tiles, state.power_event]);

  // When animation finishes, apply any pending power tiles
  useEffect(() => {
    if (!animating && pendingPowerTilesRef.current) {
      setDisplayedPowerTiles(pendingPowerTilesRef.current);
      pendingPowerTilesRef.current = null;
    }
  }, [animating]);

  // Double roll phase tracking: 2x → 1x → gone
  useEffect(() => {
    const drp = state.double_roll_pending;
    if (drp !== null && drp !== undefined) {
      // Player just got double_roll — show "2x"
      setDoubleRollPhase({ slot: drp, phase: "2x" });
    } else if (doubleRollPhase && doubleRollPhase.phase === "2x") {
      // double_roll_pending went from set → null while still this player's turn
      // The extra roll was consumed — show "1x" briefly
      const isStillTheirTurn = state.turn_slot === doubleRollPhase.slot;
      if (isStillTheirTurn) {
        setDoubleRollPhase({ slot: doubleRollPhase.slot, phase: "1x" });
        const t = setTimeout(() => setDoubleRollPhase(null), 2000);
        return () => clearTimeout(t);
      } else {
        setDoubleRollPhase(null);
      }
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.double_roll_pending, state.turn_slot]);



  // Sound effects for last_event changes
  const lastEventRef = useRef<string>("");
  useEffect(() => {
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

  const renderPawns: { key: string; slot: number; idx: number; color: Color; row: number; col: number; movable: boolean; hasShield: boolean }[] = [];
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
        hasShield: state.shields?.[String(part.slot)] === true,
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
      <style dangerouslySetInnerHTML={{ __html: POWER_TILE_STYLES }} />
      <div className="w-full px-2"><GameInstructionsBanner slug="ludo" /></div>
      {/* Players: 2 on a single row, 4 in a 2x2 square */}
      {(() => {
        const twoMode = participants.length === 2;
        const slotColors: Color[] = twoMode
          ? (participants.map(pp => pp.color) as Color[])
          : (["red","green","blue","yellow"] as Color[]);
        return (
          <div className={`grid w-full max-w-xs gap-1.5 justify-items-center ${twoMode ? "grid-cols-2 grid-rows-1" : "grid-cols-2 grid-rows-2"}`}>
            {slotColors.map((slotColor) => {
              const p = participants.find(pp => pp.color === slotColor);
              if (!p) return <div key={slotColor} />;
              const isCurrent = p.slot === displaySlot && status === "playing";
              const pawnArr = state.pawns?.[String(p.slot)] || [];
              const finishedCount = pawnArr.filter(pw => pw?.s === "finished").length;
              const totalPawns = pawnArr.length || 4;
              return (
                <div key={p.id}
                  className={`flex w-full items-center gap-2 rounded-xl bg-card px-3 py-1.5 shadow ring-2 transition ${
                    isCurrent ? `${COLOR_META[p.color].ring} scale-105 border-2 border-white shadow-lg shadow-white/20` : "ring-transparent opacity-70 border border-white/10"
                  } ${p.forfeited ? "line-through opacity-40" : ""}`}>
                  <div className="relative shrink-0">
                    <div className={`h-7 w-7 rounded-full overflow-hidden ring-2 ${COLOR_META[p.color].ring} ${COLOR_META[p.color].bg} `}>
                      {avatarOf(p) ? (
                        <img src={avatarOf(p)} alt={nameOf(p)} className="h-full w-full object-cover" />
                      ) : (
                        <div className="flex h-full w-full items-center justify-center text-[9px] font-bold text-white">
                          {nameOf(p).slice(0, 2).toUpperCase()}
                        </div>
                      )}
                    </div>
                    <span className="absolute -right-1 -top-1 flex h-3.5 min-w-3.5 items-center justify-center rounded-full border border-white bg-emerald-500 px-0.5 text-[8px] font-bold leading-none text-white shadow">
                      {finishedCount}
                    </span>
                  </div>
                  <div className="flex min-w-0 flex-col leading-tight">
                    <div className="flex items-center gap-1">
                      <span className={`truncate text-xs font-semibold leading-none ${COLOR_META[p.color].text}`}>{nameOf(p)}</span>
                      {doubleRollPhase && doubleRollPhase.slot === p.slot && (
                        <span
                          key={doubleRollPhase.phase}
                          className="shrink-0 rounded px-1 text-[7px] font-bold leading-tight text-white"
                          style={{
                            background: doubleRollPhase.phase === "2x" ? "#ec4899" : "#6366f1",
                            animation: doubleRollPhase.phase === "2x"
                              ? "doubleRollBadgeIn 0.3s ease-out"
                              : "doubleRollBadgeIn 0.3s ease-out",
                          }}>
                          ⚡{doubleRollPhase.phase}
                        </span>
                      )}
                      {state.shields?.[String(p.slot)] === true && (
                        <span className="shrink-0 text-[8px] leading-none">🛡️</span>
                      )}
                      {matchType === "groupe" && p.team && (
                        <span className={`shrink-0 text-[8px] leading-none ${p.team === 1 ? "text-red-600" : "text-blue-600"}`}>
                          {p.team === 1 ? "🔴" : "🔵"}
                        </span>
                      )}
                    </div>
                    <span className="truncate text-[9px] leading-none text-muted-foreground">
                      T1 {p.afk_t1 ?? 0}/{afkMax.t1} · T2 {p.afk_t2 ?? 0}/{afkMax.t2}
                    </span>
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

        {/* Power tiles (Mode Moderne) — just colored icons, no background */}
        {displayedPowerTiles && displayedPowerTiles.length > 0 && (
          <>
            {displayedPowerTiles.map((tile, ti) => {
              const [row, col] = PATH[tile.cell];
              const meta = POWER_TILE_META[tile.type] || POWER_TILE_META.lucky_star;
              return (
                <div key={`pt-${ti}`} className="absolute flex items-center justify-center"
                  style={{
                    left: col * cellPx + cellPx * 0.1,
                    top: row * cellPx + cellPx * 0.1,
                    width: cellPx * 0.8,
                    height: cellPx * 0.8,
                    zIndex: 10,
                    fontSize: cellPx * 0.52,
                    lineHeight: 1,
                    pointerEvents: "none",
                    animation: "none",
                    transition: "left 0.4s ease, top 0.4s ease",
                  }}>
                  <span style={{
                    animation: "none",
                    color: meta.color,
                    display: "inline-block",
                    filter: `drop-shadow(0 0 6px ${meta.color}) drop-shadow(0 0 2px rgba(0,0,0,0.9))`,
                    fontWeight: "bold",
                  }}>
                    {meta.icon}
                  </span>
                </div>
              );
            })}
          </>
        )}

        {/* Board-level power activation effect — distinct visual per power type */}
        {boardPowerEffect && (() => {
          const [row, col] = PATH[boardPowerEffect.cell];
          if (!row && !col) return null;
          const cx = col * cellPx + cellPx / 2;
          const cy = row * cellPx + cellPx / 2;
          const effType = boardPowerEffect.type;
          const effKey = boardPowerEffect.key;
          const colors: Record<string, string> = {
            boost: "#a855f7", shield: "#14b8a6", double_roll: "#ec4899",
            lucky_star: "#fbbf24", reroll: "#ec4899", free_pawn: "#14b8a6",
          };
          const icons: Record<string, string> = {
            boost: "🚀", shield: "🛡️", double_roll: "⚡",
            lucky_star: "⭐", reroll: "🎲", free_pawn: "🎁",
          };
          const c = colors[effType] || "#a855f7";
          const icon = icons[effType] || "✨";
          const animMap: Record<string, string> = {
            boost: "boardBoostRing", shield: "boardShieldHex",
            double_roll: "boardLightningFlash", lucky_star: "boardStarBurst",
            reroll: "boardRerollDice", free_pawn: "boardGiftPop",
          };
          const anim = animMap[effType] || "boardBoostRing";
          return (
            <div key={`bpe-${effKey}`} className="absolute pointer-events-none" style={{ left: cx, top: cy, zIndex: 50, transform: "translate(-50%, -50%)" }}>
              {/* Expanding colored ring */}
              <div className="absolute rounded-full"
                style={{
                  width: cellPx * 1.2, height: cellPx * 1.2,
                  left: -cellPx * 0.6, top: -cellPx * 0.6,
                  border: `4px solid ${c}`,
                  animation: `${anim} 1.5s ease-out forwards`,
                  borderRadius: effType === "shield" ? "30%" : "50%",
                }} />
              {/* Big icon at center */}
              <div className="absolute"
                style={{
                  fontSize: cellPx * 0.8,
                  lineHeight: 1,
                  left: -cellPx * 0.4, top: -cellPx * 0.4,
                  width: cellPx * 0.8, height: cellPx * 0.8,
                  display: "flex", alignItems: "center", justifyContent: "center",
                  animation: `${anim} 1.5s ease-out forwards`,
                  filter: `drop-shadow(0 0 8px ${c})`,
                }}>
                {icon}
              </div>
              {/* Radial glow */}
              <div className="absolute rounded-full"
                style={{
                  width: cellPx * 2, height: cellPx * 2,
                  left: -cellPx, top: -cellPx,
                  background: `radial-gradient(circle, ${c}40 0%, transparent 70%)`,
                  animation: "boardPowerGlow 1s ease-out forwards",
                }} />
              {/* Sparkle particles */}
              {[0, 1, 2, 3, 4, 5].map(i => (
                <div key={i} className="absolute rounded-full"
                  style={{
                    width: "5px", height: "5px",
                    background: c,
                    left: 0, top: 0,
                    animation: `pawnStarBurst 1s ease-out ${i * 0.08}s forwards`,
                    transform: `rotate(${i * 60}deg) translateY(-${cellPx * 0.6}px)`,
                  }} />
              ))}
            </div>
          );
        })()}

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
                {state.shields?.[String(p.slot)] === true && (
                  <div className="absolute pointer-events-none rounded-full"
                    style={{
                      inset: "-4px",
                      border: "2.5px solid rgba(20,184,166,0.9)",
                      animation: "none",
                      borderRadius: "50%",
                    }}>
                    <span className="absolute -top-2 -right-1 text-[10px]"
                      style={{}}>🛡️</span>
                  </div>
                )}
                {pawnPowerEffect && pawnPowerEffect.slot === p.slot && (pawnPowerEffect.type === "shield" || pawnPowerEffect.pawn === p.idx) && (
                  (() => {
                    const effType = pawnPowerEffect.type;
                    const effKey = pawnPowerEffect.key;
                    const effectColors: Record<string, string> = {
                      boost: "#a855f7",
                      shield: "#14b8a6",
                      double_roll: "#ec4899",
                      lucky_star: "#e2e8f0",
                      reroll: "#ec4899",
                      free_pawn: "#14b8a6",
                    };
                    const effColor = effectColors[effType] || "#a855f7";
                    const effectIcons: Record<string, string> = {
                      boost: "🚀",
                      shield: "🛡️",
                      double_roll: "⚡",
                      lucky_star: "⭐",
                      reroll: "🎲",
                      free_pawn: "🎁",
                    };
                    return (
                      <div className="absolute pointer-events-none" style={{ inset: "-8px", zIndex: 40 }}>
                        {/* Pulsing ring */}
                        <div className="absolute inset-0 rounded-full"
                          style={{
                            border: `3px solid ${effColor}`,
                            animation: "pawnBoostEffect 1.2s ease-out forwards",
                            borderRadius: "50%",
                          }} />
                        {/* Shield: extra burst ring */}
                        {effType === "shield" && (
                          <div className="absolute inset-0 rounded-full"
                            style={{
                              border: `4px solid ${effColor}`,
                              animation: "shieldBurstEffect 1.5s ease-out forwards",
                              borderRadius: "50%",
                            }} />
                        )}
                        {/* Icon badge */}
                        <div className="absolute -top-3 left-1/2 -translate-x-1/2 text-lg"
                          style={{
                            animation: "pawnSparkleEffect 1.2s ease-out forwards",
                            filter: `drop-shadow(0 0 4px ${effColor})`,
                          }}>
                          {effectIcons[effType] || "✨"}
                        </div>
                        {/* Sparkle particles */}
                        {[0, 1, 2, 3].map(i => (
                          <div key={i} className="absolute rounded-full"
                            style={{
                              width: "4px", height: "4px",
                              background: effColor,
                              top: "50%", left: "50%",
                              animation: `pawnStarBurst 1s ease-out ${i * 0.1}s forwards`,
                              transform: `rotate(${i * 90}deg) translateY(-12px)`,
                            }} />
                        ))}
                      </div>
                    );
                  })()
                )}
                <span className="absolute rounded-full pointer-events-none"
                      style={{
                        left: "18%", top: "12%", width: "38%", height: "28%",
                        background: "radial-gradient(ellipse at center, rgba(255,255,255,0.95) 0%, rgba(255,255,255,0) 70%)",
                        filter: "blur(0.5px)",
                      }} />
                {p.hasShield && (
                  <span className="absolute -top-1 -right-1 flex items-center justify-center rounded-full"
                    style={{
                      width: "42%", height: "42%",
                      background: "rgba(34,197,94,0.95)",
                      border: "2px solid white",
                      boxShadow: "0 1px 3px rgba(0,0,0,0.5)",
                      fontSize: "60%",
                      zIndex: 5,
                    }}>
                    🛡️
                  </span>
                )}
              </div>
            </button>
          );

        })}

      </div>

      {/* Sound toggle (moved to game page header) */}

      {/* Forfeit banner */}
      {(() => {
        const myPart = participants.find(p => p.user_id === myUserId);
        if (myPart?.forfeited && status !== "finished") {
          return (
            <div className="w-full rounded-2xl bg-destructive/10 border-2 border-destructive/30 p-4 text-center">
              <div className="text-2xl mb-1">🏳️</div>
              <div className="font-bold text-destructive text-sm">Vous avez abandonné</div>
              <div className="text-xs text-muted-foreground mt-1">
                Vous ne pouvez plus jouer dans cette partie. Vous pouvez regarder la suite en spectateur.
              </div>
            </div>
          );
        }
        const anyForfeited = participants.filter(p => p.forfeited);
        if (anyForfeited.length > 0 && status === "playing") {
          return (
            <div className="w-full rounded-xl bg-amber-500/10 border border-amber-500/30 px-3 py-1.5 text-center text-[11px] text-amber-600 dark:text-amber-400">
              {anyForfeited.map(p => nameOf(p)).join(", ")} {anyForfeited.length > 1 ? "ont abandonné" : "a abandonné"}
            </div>
          );
        }
        return null;
      })()}

      {/* Bottom HUD */}
      <div className="flex flex-col items-center gap-1.5">
        <div className="text-xs text-muted-foreground">
          {isSpectator ? "Mode spectateur" :
            status !== "playing" ? "En attente du démarrage…" :
            currentPart && (currentPart.is_bot ? `${nameOf(currentPart)} joue…` :
            isMyTurn ? (state.must_move ? "" : "À toi de lancer le dé") :
            `Tour de ${nameOf(currentPart)}`)}
        </div>
        {status === "playing" && (() => {
          const pct = afkMax.secs > 0 ? remaining / afkMax.secs : 0;
          const timerColor = remaining <= 5 ? "text-destructive" : remaining <= 10 ? "text-amber-500" : "text-emerald-500";
          const showAfk = currentPart && !currentPart.is_bot && ((currentPart.afk_t1 ?? 0) > 0 || (currentPart.afk_t2 ?? 0) > 0);
          return (
            <div className="flex items-center gap-2">
              <div className={`flex items-center gap-1 text-sm font-bold ${timerColor} ${remaining <= 5 ? "animate-pulse" : ""}`}>
                <svg width="20" height="20" viewBox="0 0 24 24" className={remaining <= 5 ? "animate-pulse" : ""}>
                  <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="2" opacity="0.2" />
                  <circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" strokeWidth="2"
                    strokeDasharray={`${2 * Math.PI * 9}`}
                    strokeDashoffset={`${2 * Math.PI * 9 * (1 - pct)}`}
                    strokeLinecap="round"
                    transform="rotate(-90 12 12)"
                    style={{ transition: "stroke-dashoffset 0.5s ease" }}
                  />
                </svg>
                {remaining}s
              </div>
              {showAfk && (
                <div className="flex items-center gap-1 text-[10px] text-muted-foreground">
                  {currentPart!.afk_t1! > 0 && <span className={`px-1.5 py-0.5 rounded-full ${currentPart!.afk_t1! >= afkMax.t1 ? "bg-amber-500/20 text-amber-600 font-semibold" : "bg-muted"}`}>T1 {currentPart!.afk_t1}/{afkMax.t1}</span>}
                  {currentPart!.afk_t2! > 0 && <span className={`px-1.5 py-0.5 rounded-full ${currentPart!.afk_t2! >= afkMax.t2 ? "bg-amber-500/20 text-amber-600 font-semibold" : "bg-muted"}`}>T2 {currentPart!.afk_t2}/{afkMax.t2}</span>}
                </div>
              )}
            </div>
          );
        })()}
        {isAdmin && status === "playing" && currentPart && (
          <div className="rounded-lg bg-amber-100 border border-amber-300 px-2 py-1 flex flex-wrap items-center gap-1 text-[10px]">
            <span className="font-bold text-amber-900">🎲 Dé de {currentPart.display_name} :</span>
            {[1,2,3,4,5,6].map(n => (
              <button key={n} onClick={async () => {
                const { error } = await supabase.rpc("super_player_set_dice" as any, { _game_id: gameId, _slot: state.turn_slot, _value: n } as any);
                if (error) toast.error(error.message); else toast.success(`Prochain dé: ${n}`);
              }} className="w-5 h-5 rounded bg-white text-[11px] font-bold leading-none hover:bg-amber-200">{n}</button>
            ))}
          </div>
        )}
        <div className="relative" style={{ perspective: '200px' }}>
          <button onClick={roll}
            disabled={!isMyTurn || state.must_move || busy}
            className={`group relative h-20 w-20 rounded-2xl bg-white shadow-xl ring-2 transition ${
              displayPart ? COLOR_META[displayPart.color].ring : "ring-slate-300"
            } ${isMyTurn && !state.must_move ? "hover:scale-110 active:scale-95" : "opacity-60"} ${rollingFace !== null ? "dice-tumbling" : ""}`}>
            <DiceFace value={rollingFace ?? displayDice ?? 0} />
          </button>
          {rollingFace !== null && (
            <div className="absolute -bottom-2 left-1/2 -translate-x-1/2 w-16 h-2 rounded-full bg-black/20 blur-sm animate-pulse" />
          )}
        </div>
        {displayDice != null && rollingFace === null && (
          <div className="text-lg font-extrabold text-foreground">Dé : {displayDice}</div>
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

// ═══ Power Choice Dialog — Compact Bottom Sheet (Mode Moderne v3) ═══════
