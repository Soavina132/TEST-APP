import { useRef, useEffect } from "react";

export type Tile = [number, number];

// ── Pip positions on 3×3 grid ──────────────────────────────────────────────
const PIPS: Record<number, [number, number][]> = {
  0: [],
  1: [[1,1]],
  2: [[0,0],[2,2]],
  3: [[0,0],[1,1],[2,2]],
  4: [[0,0],[0,2],[2,0],[2,2]],
  5: [[0,0],[0,2],[1,1],[2,0],[2,2]],
  6: [[0,0],[1,0],[2,0],[0,2],[1,2],[2,2]],
};

function PipFace({ n, size }: { n: number; size: number }) {
  const dot = Math.max(2.5, size * 0.16);
  const pos = PIPS[n] || [];
  return (
    <div className="relative w-full h-full">
      {pos.map(([r, c], i) => (
        <div key={i} className="absolute rounded-full"
          style={{
            width: dot, height: dot,
            background: "#1a1a2e",
            top: `${r * 36 + 14}%`, left: `${c * 36 + 14}%`,
            transform: "translate(-50%, -50%)",
            boxShadow: "inset 0 1px 1.5px rgba(0,0,0,0.35), 0 0.5px 0.5px rgba(255,255,255,0.4)",
          }}
        />
      ))}
    </div>
  );
}

// ── Domino Tile — realistic ivory look ─────────────────────────────────────
export function DominoTile({
  t, onClick, selected, w = 36, vertical = false, faceDown = false,
  highlight = false, draggable, onDragStart, onDragEnd,
}: {
  t?: Tile; onClick?: () => void; selected?: boolean; w?: number;
  vertical?: boolean; faceDown?: boolean; highlight?: boolean;
  draggable?: boolean;
  onDragStart?: (e: React.DragEvent) => void;
  onDragEnd?: (e: React.DragEvent) => void;
}) {
  const long = w * 2;
  const W = vertical ? w : long;
  const H = vertical ? long : w;

  // Face-down: dark green back
  if (faceDown) {
    return (
      <div style={{ width: W, height: H }}
        className="rounded-[4px] shrink-0 shadow-md">
        <div className="w-full h-full rounded-[4px] border border-emerald-900/40"
          style={{ background: "linear-gradient(135deg, #0d4525 0%, #1a6b3a 50%, #0d4525 100%)" }}>
          <div className="w-full h-full flex items-center justify-center">
            <div className="w-2/3 h-1/3 rounded-full border border-emerald-400/20" />
          </div>
        </div>
      </div>
    );
  }

  const bg = selected ? "#e0f2fe" : highlight ? "#fef9c3" : "#f5f0e6";

  const Half = ({ v }: { v: number }) => (
    <div className="flex-1 relative" style={{ padding: w * 0.04 }}>
      <PipFace n={v} size={vertical ? w : w * 0.5} />
    </div>
  );

  const divider = vertical
    ? <div className="w-[80%] mx-auto h-[1.5px] bg-stone-400/40 rounded-full" />
    : <div className="h-[80%] my-auto w-[1.5px] bg-stone-400/40 rounded-full" />;

  const inner = vertical ? (
    <div className="w-full h-full flex flex-col rounded-[4px]" style={{ background: bg }}>
      <Half v={t![0]} />
      {divider}
      <Half v={t![1]} />
    </div>
  ) : (
    <div className="w-full h-full flex rounded-[4px]" style={{ background: bg }}>
      <Half v={t![0]} />
      {divider}
      <Half v={t![1]} />
    </div>
  );

  return (
    <button onClick={onClick} disabled={!onClick && !draggable}
      draggable={draggable} onDragStart={onDragStart} onDragEnd={onDragEnd}
      style={{ width: W, height: H, touchAction: draggable ? "none" : undefined }}
      className={`shrink-0 rounded-[4px] transition-all duration-150 ${
        selected ? "-translate-y-2 ring-2 ring-sky-400 shadow-lg" : "shadow-[0_2px_5px_rgba(0,0,0,0.3)]"
      } ${onClick || draggable ? "hover:-translate-y-0.5 active:scale-95 cursor-pointer" : "cursor-default"
      } border border-stone-300/50`}>
      {inner}
    </button>
  );
}

// ── Player Card ─────────────────────────────────────────────────────────────
type Seat = {
  user_id: string; display_name?: string | null; avatar_url?: string | null;
  slot: number; handCount: number; isCurrent: boolean; remaining?: number;
  isMe?: boolean; score?: number; skips?: number; maxSkips?: number;
};

function initials(n?: string | null) {
  if (!n) return "?";
  return n.trim().split(/\s+/).slice(0, 2).map(w => w[0]).join("").toUpperCase();
}

export function PlayerHeader({ seat, side, size = "sm" }: {
  seat?: Seat; side: "left" | "right"; size?: "sm" | "lg";
}) {
  const name = !seat ? (side === "left" ? "Vous" : "Adversaire")
    : seat.isMe ? "Vous" : (seat.display_name || "Joueur");
  const score = seat?.score ?? 0;
  const skips = seat?.skips ?? 0;
  const maxSkips = seat?.maxSkips ?? 5;
  const avSize = size === "lg" ? 44 : 36;
  const ring = seat?.isCurrent ? "#22c55e" : "rgba(255,255,255,0.25)";

  return (
    <div className="inline-flex flex-col items-center gap-0.5 min-w-0">
      <div className="relative shrink-0">
        {seat?.avatar_url ? (
          <img src={seat.avatar_url} alt={name} width={avSize} height={avSize}
            className="rounded-full object-cover"
            style={{ width: avSize, height: avSize, border: `2px solid ${ring}`,
              boxShadow: seat?.isCurrent ? "0 0 12px rgba(34,197,94,0.5)" : undefined }}
            loading="lazy" />
        ) : (
          <div className="rounded-full flex items-center justify-center font-bold text-white bg-white/10"
            style={{ width: avSize, height: avSize, border: `2px solid ${ring}`,
              boxShadow: seat?.isCurrent ? "0 0 12px rgba(34,197,94,0.5)" : undefined,
              fontSize: Math.max(9, Math.round(avSize / 3)) }}>
            {initials(name)}
          </div>
        )}
        {seat && seat.handCount > 0 && (
          <div className="absolute -top-1 -right-1 min-w-[16px] h-[16px] px-1 rounded-full
            bg-amber-400 text-black text-[9px] font-extrabold flex items-center justify-center
            border border-white/80 leading-none shadow-sm">{seat.handCount}</div>
        )}
        {skips > 0 && (
          <div className={`absolute -bottom-1 left-1/2 -translate-x-1/2 px-1 rounded-full
            text-white text-[8px] font-bold whitespace-nowrap
            ${skips >= maxSkips - 1 ? "bg-red-600 animate-pulse" : "bg-orange-500"}`}>
            {skips}/{maxSkips}
          </div>
        )}
      </div>
      <div className="text-white/85 text-[11px] font-semibold truncate max-w-[90px] text-center leading-tight">{name}</div>
      <div className="text-white text-lg font-black leading-none tabular-nums">{score}</div>
      {seat?.isCurrent && typeof seat.remaining === "number" && (
        <div className={`mt-0.5 text-[10px] font-bold tabular-nums px-1.5 py-0.5 rounded leading-none
          ${seat.remaining <= 5 ? "bg-red-600 text-white animate-pulse" : "bg-black/40 text-white/90"}`}>
          {seat.remaining}s
        </div>
      )}
    </div>
  );
}

// ── Snake layout: 7 horizontal → 4 down → zigzag → repeat ──
// ── Snake layout constants ──────────────────────────────────────────────────
const SNAKE_W = 22;   // tile short side (px)
const SNAKE_L = 44;   // tile long side = 2 * SNAKE_W
const MAX_H_TILES = 7; // max horizontal tiles per row
const MAX_V_TILES = 4; // max vertical tiles per column

interface BoardPos {
  x: number;
  y: number;
  dir: "h" | "v";
  isDouble: boolean;
}

interface SnakeLayout {
  positions: BoardPos[];
  width: number;
  height: number;
  lastHDir: 1 | -1;
  lastDir: "h" | "v";
}

function computeSnakeLayout(
  board: { tile: Tile; flipped: boolean }[]
): SnakeLayout {
  const positions: BoardPos[] = [];
  let x = 0, y = 0;
  let idx = 0;
  let hDir: 1 | -1 = 1; // right first, then alternate (zigzag)

  let minX = 0, maxX = 0, minY = 0, maxY = 0;

  const track = (px: number, py: number, pw: number, ph: number) => {
    if (px < minX) minX = px;
    if (px + pw > maxX) maxX = px + pw;
    if (py < minY) minY = py;
    if (py + ph > maxY) maxY = py + ph;
  };

  while (idx < board.length) {
    // ── Horizontal segment (max 7 tiles) ──
    const hCount = Math.min(MAX_H_TILES, board.length - idx);
    for (let i = 0; i < hCount; i++) {
      const isDouble = board[idx].tile[0] === board[idx].tile[1];
      positions.push({ x, y, dir: "h" as const, isDouble });
      track(x, y, SNAKE_L, SNAKE_W);
      x += SNAKE_L * hDir;
      idx++;
    }

    if (idx >= board.length) break;

    // ── Corner H → V: center vertical column on the chain end ──
    if (hDir > 0) {
      // going right: x is past the last tile's right edge → center V tile on it
      x = x - SNAKE_W / 2;
    } else {
      // going left: x is at the last tile's left edge → center V tile on it
      x = x - SNAKE_W / 2;
    }
    y += SNAKE_W; // move below the horizontal row

    // ── Vertical segment (4 tiles going down) ──
    const vCount = Math.min(MAX_V_TILES, board.length - idx);
    for (let i = 0; i < vCount; i++) {
      const isDouble = board[idx].tile[0] === board[idx].tile[1];
      positions.push({ x, y, dir: "v" as const, isDouble });
      track(x, y, SNAKE_W, SNAKE_L);
      y += SNAKE_L;
      idx++;
    }

    if (idx >= board.length) break;

    // ── Corner V → H: start horizontal from center of V column bottom ──
    if (hDir > 0) {
      // was right → now go left; tile right edge at center of V column
      x = x + SNAKE_W / 2 - SNAKE_L;
      hDir = -1;
    } else {
      // was left → now go right; tile left edge at center of V column
      x = x + SNAKE_W / 2;
      hDir = 1;
    }
    // y stays at bottom of V column — H row starts here
  }

  // Normalize so minX/minY = 0, then add padding for drop zones
  const PAD = SNAKE_W * 2;
  const ox = -minX + PAD;
  const oy = -minY + PAD;
  return {
    positions: positions.map((p) => ({ ...p, x: p.x + ox, y: p.y + oy })),
    width: (maxX - minX) + PAD * 2,
    height: (maxY - minY) + PAD * 2,
    lastHDir: hDir as 1 | -1,
    lastDir: (positions.length > 0 ? positions[positions.length - 1].dir : "h") as "h" | "v",
  };
}

// ── Board: snake layout — 7 horizontal, 4 down, zigzag ────────────────────
export function DominoBoard({
  board, canDropLeft, canDropRight, canDropAny,
  onDropLeft, onDropRight, onDropAny,
}: {
  board: { tile: Tile; flipped: boolean }[];
  leftEnd: number | null; rightEnd: number | null;
  canDropLeft: boolean; canDropRight: boolean; canDropAny?: boolean;
  onDropLeft?: () => void; onDropRight?: () => void; onDropAny?: () => void;
}) {
  const ref = useRef<HTMLDivElement | null>(null);
  const dOver = (e: React.DragEvent) => e.preventDefault();

  // Auto-scroll to show the last placed tile
  useEffect(() => {
    if (ref.current) {
      const el = ref.current;
      el.scrollTo({ left: (el.scrollWidth - el.clientWidth) / 2, top: el.scrollHeight - el.clientHeight, behavior: "smooth" });
    }
  }, [board.length]);

  if (board.length === 0) {
    return (
      <div className="flex items-center justify-center w-full h-full">
        <div onDragOver={dOver}
          onDrop={() => (onDropAny ?? onDropRight)?.()}
          onClick={() => { if (canDropAny || canDropRight) (onDropAny ?? onDropRight)?.(); }}
          className={`rounded-2xl flex items-center justify-center w-full h-full text-xs transition-all
            ${canDropAny || canDropRight
              ? "bg-amber-400/15 ring-2 ring-amber-400 animate-pulse text-amber-100 font-bold"
              : "text-white/25"}`}>
          {canDropAny || canDropRight ? "Déposez votre tuile" : ""}
        </div>
      </div>
    );
  }

  const { positions, width, height, lastHDir, lastDir } = computeSnakeLayout(board);

  // Determine where the "left" and "right" ends are for drop zones
  const firstPos = positions[0];
  const lastPos = positions[positions.length - 1];

  // Left drop zone: to the left of the first tile
  const leftDropX = firstPos.x - SNAKE_W - 4;
  const leftDropY = firstPos.y - 4;

  // Right drop zone: after the last tile, in the direction of growth
  let rightDropX = lastPos.x;
  let rightDropY = lastPos.y;
  if (lastDir === "h") {
    if (lastHDir > 0) {
      // going right
      rightDropX = lastPos.x + SNAKE_L + 4;
      rightDropY = lastPos.y - 4;
    } else {
      // going left
      rightDropX = lastPos.x - SNAKE_W - 4;
      rightDropY = lastPos.y - 4;
    }
  } else {
    // Vertical segment: drop zone is below the last tile
    rightDropX = lastPos.x - 4;
    rightDropY = lastPos.y + SNAKE_L + 4;
  }

  const dropSize = SNAKE_W + 8;

  return (
    <div ref={ref} className="w-full h-full overflow-auto flex items-center justify-center"
      style={{ scrollbarWidth: "thin" }}>
      <div className="relative" style={{ width, height, minWidth: "100%" }}>
        {/* Domino tiles */}
        {positions.map((pos, i) => {
          const { tile } = board[i];
          return (
            <div key={i} className="absolute" style={{ left: pos.x, top: pos.y }}>
              <DominoTile
                t={tile}
                w={SNAKE_W}
                vertical={pos.dir === "v"}
              />
            </div>
          );
        })}

        {/* Left drop zone */}
        {canDropLeft && (
          <button
            onDragOver={dOver}
            onDrop={(e) => { e.preventDefault(); onDropLeft?.(); }}
            onClick={() => onDropLeft?.()}
            className="absolute rounded-lg bg-amber-400/20 ring-2 ring-amber-400 animate-pulse
              flex items-center justify-center text-amber-200 text-xs font-bold hover:bg-amber-400/30"
            style={{ left: leftDropX, top: leftDropY, width: dropSize, height: dropSize }}
          >←</button>
        )}

        {/* Right drop zone */}
        {canDropRight && (
          <button
            onDragOver={dOver}
            onDrop={(e) => { e.preventDefault(); onDropRight?.(); }}
            onClick={() => onDropRight?.()}
            className="absolute rounded-lg bg-amber-400/20 ring-2 ring-amber-400 animate-pulse
              flex items-center justify-center text-amber-200 text-xs font-bold hover:bg-amber-400/30"
            style={{ left: rightDropX, top: rightDropY, width: dropSize, height: dropSize }}
          >→</button>
        )}
      </div>
    </div>
  );
}
