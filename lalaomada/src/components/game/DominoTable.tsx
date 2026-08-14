import { useRef, useEffect } from "react";

export type Tile = [number, number];

// ── Pip positions on 3×3 grid ──────────────────────────────────────────────
// NEVER change these — they define which dots appear for each value 0-6
const PIPS: Record<number, [number, number][]> = {
  0: [],
  1: [[1,1]],
  2: [[0,0],[2,2]],
  3: [[0,0],[1,1],[2,2]],
  4: [[0,0],[0,2],[2,0],[2,2]],
  5: [[0,0],[0,2],[1,1],[2,0],[2,2]],
  6: [[0,0],[1,0],[2,0],[0,2],[1,2],[2,2]],
};

// PIPS for HORIZONTAL tiles: values 0-5 are rotation-symmetric, only 6 changes.
// 6 horizontal = 3 columns × 2 rows (transposed from 2 columns × 3 rows)
const PIPS_HORIZONTAL: Record<number, [number, number][]> = {
  0: [],
  1: [[1,1]],
  2: [[0,0],[2,2]],
  3: [[0,0],[1,1],[2,2]],
  4: [[0,0],[0,2],[2,0],[2,2]],
  5: [[0,0],[0,2],[1,1],[2,0],[2,2]],
  6: [[0,0],[0,1],[0,2],[2,0],[2,1],[2,2]],
};

// ── Premium ivory pip face ─────────────────────────────────────────────────
function PipFace({ n, size, vertical }: { n: number; size: number; vertical: boolean }) {
  const dot = Math.max(2.5, size * 0.17);
  const pos = (vertical ? PIPS : PIPS_HORIZONTAL)[n] || [];
  return (
    <div className="relative w-full h-full">
      {pos.map(([r, c], i) => (
        <div key={i} className="absolute rounded-full"
          style={{
            width: dot, height: dot,
            background: "radial-gradient(circle at 35% 35%, #1a1a1a 0%, #000000 60%, #000000 100%)",
            top: `${r * 36 + 14}%`, left: `${c * 36 + 14}%`,
            transform: "translate(-50%, -50%)",
            boxShadow: [
              "inset 0 1px 2px rgba(0,0,0,0.7)",
              "inset 0 -1px 1px rgba(255,255,255,0.15)",
              "0 0.5px 0.5px rgba(255,255,255,0.5)",
            ].join(", "),
          }}
        />
      ))}
    </div>
  );
}

// ── Domino Tile — premium ivory ceramic casino look ─────────────────────────
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

  // ── Face-down: premium dark green back ──
  if (faceDown) {
    return (
      <div style={{ width: W, height: H }}
        className="rounded-[5px] shrink-0">
        <div className="w-full h-full rounded-[5px] relative overflow-hidden"
          style={{
            background: "linear-gradient(135deg, #0a3820 0%, #15643a 50%, #0a3820 100%)",
            border: "1px solid rgba(20,80,45,0.7)",
            boxShadow: "inset 0 1px 2px rgba(255,255,255,0.08), 0 2px 5px rgba(0,0,0,0.4)",
          }}>
          {/* subtle diamond pattern */}
          <div className="absolute inset-0 flex items-center justify-center">
            <div className="rounded-[3px] border border-emerald-300/15"
              style={{ width: "60%", height: "45%", transform: "rotate(45deg)" }} />
          </div>
          {/* top gloss */}
          <div className="absolute inset-x-0 top-0 h-1/3 rounded-t-[5px]"
            style={{ background: "linear-gradient(180deg, rgba(255,255,255,0.06) 0%, transparent 100%)" }} />
        </div>
      </div>
    );
  }

  // ── Tile body colors ──
  const bodyGradient = selected
    ? "linear-gradient(145deg, #f0f9ff 0%, #e0f2fe 50%, #d0ecfa 100%)"
    : highlight
    ? "linear-gradient(145deg, #fefce8 0%, #fef9c3 50%, #fdf3a8 100%)"
    : "linear-gradient(145deg, #ffffff 0%, #fefcf7 50%, #f5f0e6 100%)";

  const borderColor = selected ? "#38bdf8" : highlight ? "#facc15" : "#b0a280";

  // Each half is always w × w, so use w for pip sizing in both orientations
  const pipSize = w;

  const Half = ({ v }: { v: number }) => (
    <div className="flex-1 relative" style={{ padding: w * 0.04 }}>
      <PipFace n={v} size={pipSize} vertical={vertical} />
    </div>
  );

  // Gold divider line
  const divider = vertical
    ? <div className="w-[80%] mx-auto rounded-full"
        style={{
          height: "1.5px",
          background: "linear-gradient(90deg, transparent, #c9b87a 15%, #d4c48a 50%, #c9b87a 85%, transparent)",
          boxShadow: "0 0.5px 0 rgba(255,255,255,0.4)",
        }} />
    : <div className="h-[80%] my-auto rounded-full"
        style={{
          width: "1.5px",
          background: "linear-gradient(180deg, transparent, #c9b87a 15%, #d4c48a 50%, #c9b87a 85%, transparent)",
          boxShadow: "0.5px 0 0 rgba(255,255,255,0.4)",
        }} />;

  const inner = vertical ? (
    <div className="w-full h-full flex flex-col rounded-[5px] relative overflow-hidden"
      style={{ background: bodyGradient }}>
      {/* top gloss highlight */}
      <div className="absolute inset-x-0 top-0 h-1/3 rounded-t-[5px] pointer-events-none"
        style={{ background: "linear-gradient(180deg, rgba(255,255,255,0.25) 0%, transparent 100%)" }} />
      <Half v={t![0]} />
      {divider}
      <Half v={t![1]} />
    </div>
  ) : (
    <div className="w-full h-full flex rounded-[5px] relative overflow-hidden"
      style={{ background: bodyGradient }}>
      <div className="absolute inset-x-0 top-0 h-1/3 rounded-t-[5px] pointer-events-none"
        style={{ background: "linear-gradient(180deg, rgba(255,255,255,0.25) 0%, transparent 100%)" }} />
      <Half v={t![0]} />
      {divider}
      <Half v={t![1]} />
    </div>
  );

  return (
    <button onClick={onClick} disabled={!onClick && !draggable}
      draggable={draggable} onDragStart={onDragStart} onDragEnd={onDragEnd}
      style={{ width: W, height: H, touchAction: draggable ? "none" : undefined }}
      className={`shrink-0 rounded-[5px] transition-all duration-150 ${
        selected
          ? "-translate-y-2 ring-2 ring-sky-400 shadow-[0_6px_14px_rgba(0,0,0,0.35),0_2px_4px_rgba(0,0,0,0.2)]"
          : "shadow-[0_2px_6px_rgba(0,0,0,0.3),0_1px_2px_rgba(0,0,0,0.15)]"
      } ${onClick || draggable ? "hover:-translate-y-0.5 active:scale-95 cursor-pointer" : "cursor-default"
      }`}>
      <div className="w-full h-full rounded-[5px] relative"
        style={{
          border: `1px solid ${borderColor}`,
          boxShadow: "inset 0 1px 1.5px rgba(255,255,255,0.5), inset 0 -1px 1px rgba(0,0,0,0.06)",
        }}>
        {inner}
      </div>
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

// ── Layout: 7 horizontal → reste vertical vers le bas ──
// ── Snake layout constants ──────────────────────────────────────────────────
const SNAKE_W = 22;     // tile short side (px)
const SNAKE_L = 44;     // tile long side = 2 * SNAKE_W
const MAX_H_TILES = 7;  // max horizontal tiles per row
const SAFETY_MARGIN = 76; // ≈ 2cm à 96 DPI — espace de sécurité entre le bord de la table et les dominos
const DOUBLE_EXT = (SNAKE_L - SNAKE_W) / 2; // de combien un double dépasse de la rangée/colonne

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

function computeCenterLayout(
  board: { tile: Tile; flipped: boolean }[],
  firstTileIdx: number
): SnakeLayout {
  const positions: BoardPos[] = new Array(board.length);
  let minX = 0, maxX = 0, minY = 0, maxY = 0;

  const track = (px: number, py: number, pw: number, ph: number) => {
    if (px < minX) minX = px;
    if (px + pw > maxX) maxX = px + pw;
    if (py < minY) minY = py;
    if (py + ph > maxY) maxY = py + ph;
  };

  // ── Tuile centrale (1er domino) fixée à (0, 0) ──
  {
    const idx = firstTileIdx;
    const isDouble = board[idx].tile[0] === board[idx].tile[1];
    if (isDouble) {
      positions[idx] = { x: 0, y: -DOUBLE_EXT, dir: "h", isDouble };
      track(0, -DOUBLE_EXT, SNAKE_W, SNAKE_L);
    } else {
      positions[idx] = { x: 0, y: 0, dir: "h", isDouble };
      track(0, 0, SNAKE_L, SNAKE_W);
    }
  }

  // ── Côté DROITE: jusqu'à 3 tuiles horizontales, puis débordement vertical vers le BAS ──
  const rightTotal = board.length - firstTileIdx - 1;
  const rightH = Math.min(rightTotal, MAX_H_TILES - 1); // 3 max (with center = 7 total)

  // Calculer la position de départ (bord droit du domino central)
  const centerIsDouble = board[firstTileIdx].tile[0] === board[firstTileIdx].tile[1];
  let rightChainX = centerIsDouble ? SNAKE_W : SNAKE_L;
  let rightChainY = 0;

  // Tuiles horizontales vers la droite
  for (let i = 1; i <= rightH; i++) {
    const idx = firstTileIdx + i;
    const isDouble = board[idx].tile[0] === board[idx].tile[1];
    const advance = isDouble ? SNAKE_W : SNAKE_L;
    if (isDouble) {
      positions[idx] = { x: rightChainX, y: rightChainY - DOUBLE_EXT, dir: "h", isDouble };
      track(rightChainX, rightChainY - DOUBLE_EXT, SNAKE_W, SNAKE_L);
    } else {
      positions[idx] = { x: rightChainX, y: rightChainY, dir: "h", isDouble };
      track(rightChainX, rightChainY, SNAKE_L, SNAKE_W);
    }
    rightChainX += advance;
  }

  // Débordement droite vers le BAS
  if (rightTotal > MAX_H_TILES - 1) {
    // Coin: centrer la colonne verticale sur le bord droit de la dernière tuile horizontale
    rightChainX = rightChainX - SNAKE_W / 2;
    rightChainY += SNAKE_W; // passer sous la rangée horizontale

    for (let i = MAX_H_TILES; i <= rightTotal; i++) {
      const idx = firstTileIdx + i;
      const isDouble = board[idx].tile[0] === board[idx].tile[1];
      const advance = isDouble ? SNAKE_W : SNAKE_L;
      if (isDouble) {
        positions[idx] = { x: rightChainX - DOUBLE_EXT, y: rightChainY, dir: "v", isDouble };
        track(rightChainX - DOUBLE_EXT, rightChainY, SNAKE_L, SNAKE_W);
      } else {
        positions[idx] = { x: rightChainX, y: rightChainY, dir: "v", isDouble };
        track(rightChainX, rightChainY, SNAKE_W, SNAKE_L);
      }
      rightChainY += advance;
    }
  }

  // ── Côté GAUCHE: jusqu'à 3 tuiles horizontales, puis débordement vertical vers le HAUT ──
  const leftTotal = firstTileIdx;
  const leftH = Math.min(leftTotal, MAX_H_TILES - 1); // 3 max

  // Partir du bord gauche du domino central (x = 0)
  let leftChainX = 0;
  let leftChainY = 0;

  // Tuiles horizontales vers la gauche
  for (let i = 1; i <= leftH; i++) {
    const idx = firstTileIdx - i;
    const isDouble = board[idx].tile[0] === board[idx].tile[1];
    const advance = isDouble ? SNAKE_W : SNAKE_L;
    leftChainX -= advance;
    if (isDouble) {
      positions[idx] = { x: leftChainX, y: leftChainY - DOUBLE_EXT, dir: "h", isDouble };
      track(leftChainX, leftChainY - DOUBLE_EXT, SNAKE_W, SNAKE_L);
    } else {
      positions[idx] = { x: leftChainX, y: leftChainY, dir: "h", isDouble };
      track(leftChainX, leftChainY, SNAKE_L, SNAKE_W);
    }
  }

  // Débordement gauche vers le HAUT
  if (leftTotal > MAX_H_TILES - 1) {
    // Coin: centrer la colonne verticale sur le bord gauche de la dernière tuile horizontale
    leftChainX = leftChainX - SNAKE_W / 2;
    leftChainY -= SNAKE_L; // passer au-dessus de la rangée horizontale

    for (let i = MAX_H_TILES; i <= leftTotal; i++) {
      const idx = firstTileIdx - i;
      const isDouble = board[idx].tile[0] === board[idx].tile[1];
      const advance = isDouble ? SNAKE_W : SNAKE_L;
      if (isDouble) {
        positions[idx] = { x: leftChainX - DOUBLE_EXT, y: leftChainY, dir: "v", isDouble };
        track(leftChainX - DOUBLE_EXT, leftChainY, SNAKE_L, SNAKE_W);
      } else {
        positions[idx] = { x: leftChainX, y: leftChainY, dir: "v", isDouble };
        track(leftChainX, leftChainY, SNAKE_W, SNAKE_L);
      }
      leftChainY -= advance;
    }
  }

  // Normaliser avec l'espace de sécurité (≈2cm)
  const ox = -minX + SAFETY_MARGIN;
  const oy = -minY + SAFETY_MARGIN;
  return {
    positions: positions.map((p) => ({ ...p, x: p.x + ox, y: p.y + oy })),
    width: (maxX - minX) + SAFETY_MARGIN * 2,
    height: (maxY - minY) + SAFETY_MARGIN * 2,
    lastHDir: 1 as 1 | -1,
    lastDir: (positions.length > 0 ? positions[positions.length - 1].dir : "h") as "h" | "v",
  };
}

// ── Calculer l'orientation visuelle d'une tuile (doubles = perpendiculaire) ──
function tileVisualVertical(pos: BoardPos): boolean {
  // Double en segment horizontal → rendu vertical (perpendiculaire)
  // Double en segment vertical → rendu horizontal (perpendiculaire)
  // Tuile normale → suit la direction du segment
  return pos.isDouble ? pos.dir === "h" : pos.dir === "v";
}

function tileVisualSize(pos: BoardPos): { w: number; h: number } {
  const vertical = tileVisualVertical(pos);
  return {
    w: vertical ? SNAKE_W : SNAKE_L,
    h: vertical ? SNAKE_L : SNAKE_W,
  };
}

// ── Board: 7 horizontal → reste vertical vers le bas ────────────────────────
export function DominoBoard({
  board, canDropLeft, canDropRight, canDropAny,
  onDropLeft, onDropRight, onDropAny, firstTileIdx = 0,
}: {
  board: { tile: Tile; flipped: boolean }[];
  leftEnd: number | null; rightEnd: number | null;
  canDropLeft: boolean; canDropRight: boolean; canDropAny?: boolean;
  onDropLeft?: () => void; onDropRight?: () => void; onDropAny?: () => void;
  firstTileIdx?: number;
}) {
  const ref = useRef<HTMLDivElement | null>(null);
  const dOver = (e: React.DragEvent) => e.preventDefault();

  // Auto-scroll: toujours centrer sur le domino central (le 1er joué)
  useEffect(() => {
    if (!ref.current) return;
    const el = ref.current;
    // Centrer sur le domino central
    el.scrollTo({
      left: (el.scrollWidth - el.clientWidth) / 2,
      top: (el.scrollHeight - el.clientHeight) / 2,
      behavior: "smooth",
    });
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

  const { positions, width, height } = computeCenterLayout(board, firstTileIdx);

  // ── Positions des zones de dépôt ──
  // L'extrémité gauche = board[0] (premier élément du tableau)
  // L'extrémité droite = board[board.length-1] (dernier élément)
  const leftEndPos = positions[0];
  const rightEndPos = positions[positions.length - 1];
  const dropSize = SNAKE_W + 8;

  const leftSize = tileVisualSize(leftEndPos);
  const rightSize = tileVisualSize(rightEndPos);

  // Zone de dépôt gauche:
  // - Si board[0] est dans la section horizontale (leftTileIdx < 4): à gauche
  // - Si board[0] est dans la section verticale haute: au-dessus
  const leftIsVertical = leftEndPos.dir === "v";
  let leftDropX: number, leftDropY: number;
  if (leftIsVertical) {
    // Section verticale (vers le haut): zone au-dessus
    leftDropX = leftEndPos.x + leftSize.w / 2 - dropSize / 2;
    leftDropY = leftEndPos.y - dropSize - 4;
  } else {
    // Section horizontale: zone à gauche
    leftDropX = leftEndPos.x - dropSize - 4;
    leftDropY = leftEndPos.y + leftSize.h / 2 - dropSize / 2;
  }

  // Zone de dépôt droite:
  // - Si dernière tuile est horizontale: à droite
  // - Si dernière tuile est verticale (vers le bas): en dessous
  let rightDropX: number, rightDropY: number;
  if (rightEndPos.dir === "v") {
    // Section verticale (vers le bas): zone en dessous
    rightDropX = rightEndPos.x + rightSize.w / 2 - dropSize / 2;
    rightDropY = rightEndPos.y + rightSize.h + 4;
  } else {
    // Section horizontale: zone à droite
    rightDropX = rightEndPos.x + rightSize.w + 4;
    rightDropY = rightEndPos.y + rightSize.h / 2 - dropSize / 2;
  }

  return (
    <div ref={ref} className="w-full h-full overflow-auto" style={{ scrollbarWidth: "thin" }}>
      {/* grid place-items-center centre le 1er domino quand peu de tuiles,
          et gère correctement l'overflow quand la chaîne grandit */}
      <div style={{ minWidth: "100%", minHeight: "100%", display: "grid", placeItems: "center" }}>
        <div className="relative" style={{ width, height }}>
          {/* Tuiles de domino */}
          {positions.map((pos, i) => {
            const { tile } = board[i];
            return (
              <div key={i} className="absolute" style={{ left: pos.x, top: pos.y }}>
                <DominoTile
                  t={tile}
                  w={SNAKE_W}
                  vertical={tileVisualVertical(pos)}
                />
              </div>
            );
          })}

          {/* Zone de dépôt gauche */}
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

          {/* Zone de dépôt droite */}
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
    </div>
  );
}
