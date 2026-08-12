import { useRef, useEffect, useState } from "react";

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

// ── Board: horizontal scrollable chain ──────────────────────────────────────
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

  useEffect(() => {
    if (ref.current) ref.current.scrollLeft = ref.current.scrollWidth;
  }, [board.length]);

  const BW = 20;
  const dOver = (e: React.DragEvent) => e.preventDefault();

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

  return (
    <div className="flex items-center w-full h-full overflow-hidden">
      {canDropLeft && (
        <button onDragOver={dOver} onDrop={(e) => { e.preventDefault(); onDropLeft?.(); }}
          onClick={() => onDropLeft?.()}
          className="shrink-0 mx-1 w-7 h-10 rounded-lg bg-amber-400/20 ring-2 ring-amber-400
            animate-pulse flex items-center justify-center text-amber-200 text-xs font-bold">←</button>
      )}
      <div ref={ref}
        className="flex items-center gap-0 overflow-x-auto overflow-y-hidden flex-1 py-2"
        style={{ scrollbarWidth: "thin" }}>
        {board.map(({ tile }, i) => {
          const isDouble = tile[0] === tile[1];
          return (
            <div key={i} className="shrink-0" style={{ marginRight: -1 }}>
              <DominoTile t={tile} w={BW} vertical={isDouble} />
            </div>
          );
        })}
      </div>
      {canDropRight && (
        <button onDragOver={dOver} onDrop={(e) => { e.preventDefault(); onDropRight?.(); }}
          onClick={() => onDropRight?.()}
          className="shrink-0 mx-1 w-7 h-10 rounded-lg bg-amber-400/20 ring-2 ring-amber-400
            animate-pulse flex items-center justify-center text-amber-200 text-xs font-bold">→</button>
      )}
    </div>
  );
}
