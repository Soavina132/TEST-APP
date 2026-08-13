import { useRef, useEffect, useState, useLayoutEffect } from "react";

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

// ── Board: authentic snake path with real corner turns ─────────────────────
// Walks the chain like a physical domino line: goes right, and when it would
// run off the right/left edge it turns 90° and continues down for a short
// connector run, then resumes horizontal in the opposite direction — forming
// the classic winding "S" path seen in real domino apps. Doubles are drawn
// perpendicular to the direction of travel (standard domino convention).

type Dir = "R" | "L" | "D" | "U";
type Placed = { tile: Tile; x: number; y: number; w: number; h: number; vertical: boolean };

const VERTICAL_RUN = 3; // tiles used to bridge between horizontal rows

function layoutSnake(
  board: { tile: Tile }[],
  containerW: number,
  BW: number,
): { placed: Placed[]; totalH: number; startDir: Dir; endDir: Dir } {
  const placed: Placed[] = [];
  let dir: Dir = "R" as Dir;
  let x = 0, y = 0;
  let vRunCount = 0;
  const margin = BW * 0.5;

  for (let i = 0; i < board.length; i++) {
    const tile = board[i].tile;
    const isDouble = tile[0] === tile[1];
    const remaining = board.length - i;

    let vertical = dir === "R" || dir === "L" ? isDouble : !isDouble;
    let w = vertical ? BW : BW * 2;

    // Decide if we need to turn before placing this tile (only when heading horizontally)
    if (dir === "R" && x + w > containerW - margin && remaining > 1) {
      dir = "D";
      vRunCount = 0;
    } else if (dir === "L" && x - w < margin && remaining > 1) {
      dir = "D";
      vRunCount = 0;
    }

    vertical = dir === "R" || dir === "L" ? isDouble : !isDouble;
    w = vertical ? BW : BW * 2;
    const h = vertical ? BW * 2 : BW;

    let px = x, py = y;
    if (dir === "L") px = x - w;
    if (dir === "U") py = y - h;

    placed.push({ tile, x: px, y: py, w, h, vertical });

    if (dir === "R") x += w;
    else if (dir === "L") x -= w;
    else if (dir === "D") y += h;
    else if (dir === "U") y -= h;

    if (dir === "D" || dir === "U") {
      vRunCount++;
      if (vRunCount >= VERTICAL_RUN && remaining > 1) {
        // resume horizontal, heading toward whichever side has more room
        dir = x < containerW / 2 ? "R" : "L";
        vRunCount = 0;
      }
    }
  }

  const totalH = placed.length
    ? Math.max(...placed.map(p => p.y + p.h)) - Math.min(0, ...placed.map(p => p.y))
    : 0;
  const minY = placed.length ? Math.min(0, ...placed.map(p => p.y)) : 0;
  if (minY < 0) for (const p of placed) p.y -= minY;

  return { placed, totalH, startDir: "R", endDir: dir };
}

export function DominoBoard({
  board, canDropLeft, canDropRight, canDropAny,
  onDropLeft, onDropRight, onDropAny,
}: {
  board: { tile: Tile; flipped: boolean }[];
  leftEnd: number | null; rightEnd: number | null;
  canDropLeft: boolean; canDropRight: boolean; canDropAny?: boolean;
  onDropLeft?: () => void; onDropRight?: () => void; onDropAny?: () => void;
}) {
  const outerRef = useRef<HTMLDivElement | null>(null);
  const [size, setSize] = useState({ w: 400, h: 200 });
  const dOver = (e: React.DragEvent) => e.preventDefault();

  useLayoutEffect(() => {
    if (!outerRef.current) return;
    const el = outerRef.current;
    const measure = () => setSize({ w: Math.max(50, el.clientWidth - 16), h: Math.max(50, el.clientHeight - 8) });
    measure();
    const ro = new ResizeObserver(measure);
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  if (board.length === 0) {
    return (
      <div ref={outerRef} className="flex items-center justify-center w-full h-full">
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

  // Pick the largest tile unit (BW) that keeps the whole chain within the
  // available height; shrink progressively for long chains.
  const candidates = [22, 20, 18, 16, 14, 12, 10];
  let BW = candidates[candidates.length - 1];
  let layout = layoutSnake(board, size.w, BW);
  for (const c of candidates) {
    const l = layoutSnake(board, size.w, c);
    if (l.totalH <= size.h) { BW = c; layout = l; break; }
    BW = c; layout = l;
  }

  const { placed, totalH, endDir } = layout;
  const first = placed[0];
  const last = placed[placed.length - 1];

  // Open-end button positions
  const leftBtn = first ? { x: first.x - BW * 0.9, y: first.y + first.h / 2 - BW * 0.45 } : null;
  let rightBtn: { x: number; y: number; rotate: number } | null = null;
  if (last) {
    if (endDir === "R") rightBtn = { x: last.x + last.w + BW * 0.1, y: last.y + last.h / 2 - BW * 0.45, rotate: 0 };
    else if (endDir === "L") rightBtn = { x: last.x - BW * 0.9, y: last.y + last.h / 2 - BW * 0.45, rotate: 180 };
    else if (endDir === "D") rightBtn = { x: last.x + last.w / 2 - BW * 0.45, y: last.y + last.h + BW * 0.1, rotate: 90 };
    else rightBtn = { x: last.x + last.w / 2 - BW * 0.45, y: last.y - BW * 0.9, rotate: -90 };
  }

  return (
    <div ref={outerRef} className="w-full h-full overflow-y-auto overflow-x-hidden flex items-center justify-center"
      style={{ scrollbarWidth: "thin" }}>
      <div className="relative" style={{ width: size.w, height: Math.max(totalH, size.h) }}>
        <div className="absolute" style={{
          left: "50%", top: totalH <= size.h ? "50%" : 0,
          transform: totalH <= size.h ? `translate(-50%, -50%)` : "translateX(-50%)",
          width: size.w, height: totalH,
        }}>
          {placed.map((p, i) => (
            <div key={i} className="absolute" style={{ left: p.x, top: p.y }}>
              <DominoTile t={p.tile} w={BW} vertical={p.vertical} />
            </div>
          ))}
          {canDropLeft && leftBtn && (
            <button onDragOver={dOver} onDrop={(e) => { e.preventDefault(); onDropLeft?.(); }}
              onClick={() => onDropLeft?.()}
              className="absolute rounded-lg bg-amber-400/25 ring-2 ring-amber-400
                animate-pulse flex items-center justify-center text-amber-200 text-xs font-bold"
              style={{ left: leftBtn.x, top: leftBtn.y, width: BW * 0.8, height: BW * 0.9 }}>←</button>
          )}
          {canDropRight && rightBtn && (
            <button onDragOver={dOver} onDrop={(e) => { e.preventDefault(); onDropRight?.(); }}
              onClick={() => onDropRight?.()}
              className="absolute rounded-lg bg-amber-400/25 ring-2 ring-amber-400
                animate-pulse flex items-center justify-center text-amber-200 text-xs font-bold"
              style={{ left: rightBtn.x, top: rightBtn.y, width: BW * 0.8, height: BW * 0.9,
                transform: `rotate(${rightBtn.rotate}deg)` }}>→</button>
          )}
        </div>
      </div>
    </div>
  );
}
