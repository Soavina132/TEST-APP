import { ChevronLeft, ChevronRight, Ban } from "lucide-react";

// Inject fadeInUp keyframe once
if (typeof document !== "undefined" && !document.getElementById("domino-fade-keyframe")) {
  const style = document.createElement("style");
  style.id = "domino-fade-keyframe";
  style.textContent = `@keyframes fadeInUp { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }`;
  document.head.appendChild(style);
}
import { useEffect, useRef, useState } from "react";

export type Tile = [number, number];

/** Pip layouts on a 3×3 grid (row, col). 0=top/left. */
const PIP_LAYOUTS: number[][][] = [
  [],                                                                       // 0
  [[1, 1]],                                                                 // 1 center
  [[0, 0], [2, 2]],                                                         // 2 diagonal
  [[0, 0], [1, 1], [2, 2]],                                                 // 3 diagonal
  [[0, 0], [0, 2], [2, 0], [2, 2]],                                         // 4 corners
  [[0, 0], [0, 2], [1, 1], [2, 0], [2, 2]],                                 // 5 corners + center
  [[0, 0], [1, 0], [2, 0], [0, 2], [1, 2], [2, 2]],                         // 6 two columns of 3
];

function Pips({ n, dotSize }: { n: number; dotSize: number }) {
  const dots = PIP_LAYOUTS[n] || [];
  return (
    <div className="relative w-full h-full">
      {dots.map(([r, c], i) => (
        <div
          key={i}
          className="absolute rounded-full bg-[#101010]"
          style={{
            width: dotSize,
            height: dotSize,
            top: `${(r === 0 ? 18 : r === 1 ? 50 : 82)}%`,
            left: `${(c === 0 ? 22 : c === 1 ? 50 : 78)}%`,
            transform: "translate(-50%, -50%)",
          }}
        />
      ))}
    </div>
  );
}

/**
 * Domino tile. Horizontal by default (long side = 2w, short side = w).
 * vertical=true rotates the layout (doubles).
 */
export function DominoTile({
  t, onClick, selected, w = 36, vertical = false, faceDown = false, highlight = false,
  draggable = false, onDragStart, onDragEnd,
}: {
  t?: Tile;
  onClick?: () => void;
  selected?: boolean;
  w?: number;
  vertical?: boolean;
  faceDown?: boolean;
  highlight?: boolean;
  draggable?: boolean;
  onDragStart?: (e: React.DragEvent) => void;
  onDragEnd?: (e: React.DragEvent) => void;
}) {
  const longSide = w * 2;
  const W = vertical ? w : longSide;
  const H = vertical ? longSide : w;
  const dot = Math.max(3, Math.round(w / 5.5));

  if (faceDown) {
    return (
      <div style={{ width: W, height: H }}
        className="rounded-[6px] bg-gradient-to-br from-zinc-100 to-zinc-300 shadow-md" />
    );
  }

  const bg = selected ? "#e9e9e9" : highlight ? "#fff7c2" : "#ffffff";

  const inner = vertical ? (
    <div className="w-full h-full flex flex-col" style={{ background: bg, borderRadius: 6 }}>
      <div className="flex-1 relative"><Pips n={t![0]} dotSize={dot} /></div>
      <div className="h-px bg-[#1a1a1a]" />
      <div className="flex-1 relative"><Pips n={t![1]} dotSize={dot} /></div>
    </div>
  ) : (
    <div className="w-full h-full flex" style={{ background: bg, borderRadius: 6 }}>
      <div className="flex-1 relative"><Pips n={t![0]} dotSize={dot} /></div>
      <div className="w-px bg-[#1a1a1a]" />
      <div className="flex-1 relative"><Pips n={t![1]} dotSize={dot} /></div>
    </div>
  );

  return (
    <button
      onClick={onClick} disabled={!onClick && !draggable}
      draggable={draggable}
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      style={{ width: W, height: H, touchAction: draggable ? "none" : undefined }}
      className={`rounded-[6px] shadow-[0_2px_4px_rgba(0,0,0,0.35)] transition-transform duration-200 ${selected ? "-translate-y-1" : ""} ${onClick || draggable ? "hover:-translate-y-0.5" : ""}`}>
      {inner}
    </button>
  );
}

type Seat = {
  user_id: string;
  display_name?: string | null;
  avatar_url?: string | null;
  slot: number;
  handCount: number;
  isCurrent: boolean;
  remaining?: number;
  isMe?: boolean;
  forfeited?: boolean;
  score?: number;
  skips?: number;
  maxSkips?: number;
};

function initials(name?: string | null) {
  if (!name) return "";
  return name.trim().split(/\s+/).slice(0, 2).map(w => w[0]).join("").toUpperCase();
}

function Avatar({ seat, side, size = 28 }: { seat?: Seat; side: "left" | "right"; size?: number }) {
  const ringColor = seat?.isCurrent ? "#22c55e" : "rgba(255,255,255,0.35)";
  const name = seat?.isMe ? "Vous" : (seat?.display_name || (side === "left" ? "Joueur" : "Adversaire"));
  const style = { width: size, height: size, border: `2px solid ${ringColor}`, boxShadow: seat?.isCurrent ? "0 0 8px rgba(34,197,94,0.75)" : undefined, transition: "border-color 0.3s ease, box-shadow 0.3s ease" } as const;
  if (seat?.avatar_url) {
    return (
      <img src={seat.avatar_url} alt={name}
        width={size} height={size} loading="lazy" decoding="async"
        className="rounded-full object-cover"
        style={style} />
    );
  }
  return (
    <div className="rounded-full flex items-center justify-center font-bold text-white/90 bg-white/10"
      style={{ ...style, fontSize: Math.max(9, Math.round(size / 3)) }}>
      {initials(name) || "—"}
    </div>
  );
}

export function PlayerHeader({ seat, side, size = "sm" }: { seat?: Seat; side: "left" | "right"; size?: "sm" | "lg" }) {
  const name = !seat ? (side === "left" ? "Vous" : "Adversaire") : (seat.isMe ? "Vous" : (seat.display_name || "Joueur"));
  const score = seat?.score ?? 0;
  const skips = seat?.skips ?? 0;
  const maxSkips = seat?.maxSkips ?? 5;
  const isLg = size === "lg";
  const avatarSize = isLg ? 52 : 44;


  return (
    <div className="inline-flex flex-col items-center gap-0.5 min-w-0">
      <div className="relative shrink-0">
        <Avatar seat={seat} side={side} size={avatarSize} />
        {seat && seat.handCount > 0 && (
          <div className="absolute -top-1 -right-1 min-w-[16px] h-[16px] px-1 rounded-full bg-amber-500 text-black text-[9px] font-extrabold border border-white/70 flex items-center justify-center leading-none transition-all duration-300">
            {seat.handCount}
          </div>
        )}
        {skips > 0 && (
          <div className={`absolute -bottom-1 left-1/2 -translate-x-1/2 px-1 rounded-full text-white text-[8px] font-mono font-bold whitespace-nowrap ${skips >= maxSkips - 1 ? "bg-red-600 animate-pulse" : "bg-orange-600"}`}>
            {skips}/{maxSkips}
          </div>
        )}
      </div>
      <div className="text-white/90 text-[11px] font-semibold truncate max-w-[90px] leading-tight text-center">{name}</div>
      <div className="text-white text-lg font-black leading-none tabular-nums">{score}</div>

    </div>
  );
}


/**
 * Snake layout: tiles flow horizontally then bend 90° upward when reaching the right edge.
 * Doubles render perpendicular to the chain direction.
 * `seed` makes the bend point and bend direction vary per game so games don't all look the same.
 */
function SnakeBoard({
  board, leftEnd, rightEnd, canDropLeft, canDropRight, onDropLeft, onDropRight, canDropAny, onDropAny,
}: {
  board: { tile: Tile; flipped: boolean }[];
  leftEnd: number | null;
  rightEnd: number | null;
  canDropLeft: boolean;
  canDropRight: boolean;
  onDropLeft?: () => void;
  onDropRight?: () => void;
  canDropAny?: boolean;
  onDropAny?: () => void;
  seed?: string;
}) {
  const BASE_W = 22; // half-tile short side at scale 1
  const LONG = BASE_W * 2;
  const wrapRef = useRef<HTMLDivElement | null>(null);
  const [size, setSize] = useState<{ w: number; h: number }>({ w: 320, h: 340 });

  useEffect(() => {
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

  const handleDragOver = (e: React.DragEvent) => e.preventDefault();

  if (board.length === 0) {
    return (
      <div ref={wrapRef} className="px-2 py-2 flex items-center justify-center overflow-hidden w-full h-full">
        <div
          onDragOver={handleDragOver}
          onDrop={() => (onDropAny ?? onDropRight)?.()}
          onClick={() => { if (canDropAny || canDropRight) (onDropAny ?? onDropRight)?.(); }}
          className={`rounded-2xl flex items-center justify-center text-white/50 text-xs transition-colors w-full h-full ${canDropAny || canDropRight ? "bg-amber-400/10 ring-2 ring-amber-400 animate-pulse text-amber-100 font-bold" : ""}`}
        >
          {canDropAny || canDropRight ? "Déposez ici" : ""}
        </div>
      </div>
    );
  }

  // L-shape layout: up to MAX_HORIZONTAL tiles laid horizontally, then the
  // chain turns 90° downward and continues vertically below the last tile.
  // Doubles stay perpendicular to their segment's direction.
  const MAX_HORIZONTAL = 10;
  const tiles: Tile[] = board.map(({ tile }) => tile);

  type Placed = { tile: Tile; x: number; y: number; vertical: boolean; w: number; h: number };
  const GAP = 0;
  const placed: Placed[] = [];

  // Horizontal segment (row 0)
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

  // Vertical segment going DOWN from the right end.
  // Start FLUSH under the last horizontal tile (no visual gap when the last
  // horizontal is a non-double, whose height is smaller than LONG).
  const vert = tiles.slice(MAX_HORIZONTAL);
  if (vert.length > 0 && horiz.length > 0) {
    const lastH = placed[placed.length - 1];
    const anchorCenterX = lastH.x + lastH.w / 2;
    let cursorY = lastH.y + lastH.h;
    for (const t of vert) {
      const isDouble = t[0] === t[1];
      // In vertical chain, non-doubles are vertical, doubles are horizontal
      const tw = isDouble ? LONG : BASE_W;
      const th = isDouble ? BASE_W : LONG;
      const x = anchorCenterX - tw / 2;
      placed.push({ tile: t, x, y: cursorY, vertical: !isDouble, w: tw, h: th });
      cursorY += th + GAP;
    }
  }

  const minX = Math.min(0, ...placed.map(p => p.x));
  const maxX = Math.max(...placed.map(p => p.x + p.w));
  const minY = Math.min(0, ...placed.map(p => p.y));
  const maxY = Math.max(...placed.map(p => p.y + p.h));
  // Normalize to origin
  for (const p of placed) { p.x -= minX; p.y -= minY; }
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

  // ── Drop-zone buttons: always stay fully reachable/tappable ────────────
  // Their "natural" position sits just OUTSIDE the tile chain's bounding
  // box. When the chain fills most of the board (scale ≈ 1, e.g. a long
  // horizontal run of 9-10 tiles), that natural position can land outside
  // the visible, clipped container — making the button unreachable on
  // mobile. We compute the natural center point, then CLAMP it inside the
  // rendered box (with margin for the button's own half-size) so the full
  // 44×44 touch target is always visible and tappable, however long the
  // chain gets.
  const BTN = 44; // Apple/Google-recommended minimum touch target
  const HALF = BTN / 2;
  const clamp = (v: number, min: number, max: number) => Math.min(Math.max(v, min), Math.max(min, max));

  let leftBtn: { x: number; y: number } | null = null;
  if (canDropLeft && first) {
    leftBtn = {
      x: clamp(first.x * scale - HALF - 6, HALF, renderedW - HALF),
      y: clamp((first.y + first.h / 2) * scale, HALF, renderedH - HALF),
    };
  }

  let rightBtn: { x: number; y: number } | null = null;
  if (canDropRight && last) {
    rightBtn = lastIsVertical
      ? {
          x: clamp((last.x + last.w / 2) * scale, HALF, renderedW - HALF),
          y: clamp((last.y + last.h) * scale + HALF + 6, HALF, renderedH - HALF),
        }
      : {
          x: clamp((last.x + last.w) * scale + HALF + 6, HALF, renderedW - HALF),
          y: clamp((last.y + last.h / 2) * scale, HALF, renderedH - HALF),
        };
  }

  return (
    <div ref={wrapRef} className="relative w-full h-full overflow-hidden">
      <div
        className="absolute"
        style={{
          left: "50%",
          top: "50%",
          width: renderedW,
          height: renderedH,
          transform: "translate(-50%, -50%)",
        }}
      >
        <div
          className="relative"
          style={{
            width: chainW,
            height: chainH,
            transform: `scale(${scale})`,
            transformOrigin: "top left",
            transition: "transform 320ms cubic-bezier(0.22,1,0.36,1)",
          }}
        >
          {placed.map((p, idx) => {
            const key = `${idx}-${Math.min(p.tile[0], p.tile[1])}-${Math.max(p.tile[0], p.tile[1])}`;
            return (
              <div
                key={key}
                className="absolute"
                style={{
                  left: p.x,
                  top: p.y,
                  transition: "left 320ms cubic-bezier(0.22,1,0.36,1), top 320ms cubic-bezier(0.22,1,0.36,1)",
                  willChange: "left, top",
                }}
              >
                <DominoTile t={p.tile} w={BASE_W} vertical={p.vertical} />
              </div>
            );
          })}
        </div>

        {leftBtn && (
          <button
            onClick={() => onDropLeft?.()}
            onDragOver={handleDragOver}
            onDrop={() => onDropLeft?.()}
            className="absolute z-20 -translate-x-1/2 -translate-y-1/2 rounded-full bg-amber-500 shadow-lg flex items-center justify-center gap-0.5 animate-pulse ring-2 ring-white/80"
            style={{ left: leftBtn.x, top: leftBtn.y, width: BTN, height: BTN }}
            title={`Placer à gauche (${leftEnd})`}
          >
            <ChevronLeft className="w-4 h-4 text-white" strokeWidth={3} />
            <span className="text-white text-xs font-black tabular-nums">{leftEnd}</span>
          </button>
        )}
        {rightBtn && (
          <button
            onClick={() => onDropRight?.()}
            onDragOver={handleDragOver}
            onDrop={() => onDropRight?.()}
            className="absolute z-20 -translate-x-1/2 -translate-y-1/2 rounded-full bg-amber-500 shadow-lg flex items-center justify-center gap-0.5 animate-pulse ring-2 ring-white/80"
            style={{ left: rightBtn.x, top: rightBtn.y, width: BTN, height: BTN }}
            title={`Placer à droite (${rightEnd})`}
          >
            <span className="text-white text-xs font-black tabular-nums">{rightEnd}</span>
            <ChevronRight className="w-4 h-4 text-white" strokeWidth={3} />
          </button>
        )}

      </div>
    </div>
  );
}




export default function DominoTable({
  seats, maxPlayers, meSlot, board, leftEnd, rightEnd, stockSize, targetScore, statusMessage, statusType,
  canDropLeft, canDropRight, onDropLeft, onDropRight, canDropAny, onDropAny, seed,
  noMoveSlot,
}: {
  seats: Seat[];
  maxPlayers: number;
  meSlot: number | null;
  board: { tile: Tile; flipped: boolean }[];
  leftEnd: number | null;
  rightEnd: number | null;
  stockSize: number;
  targetScore?: number;
  statusMessage?: string;
  statusType?: "blocked" | "pass" | undefined;
  canDropLeft?: boolean;
  canDropRight?: boolean;
  onDropLeft?: () => void;
  onDropRight?: () => void;
  canDropAny?: boolean;
  onDropAny?: () => void;
  seed?: string;
  noMoveSlot?: number | null;
}) {
  const base = meSlot ?? 0;
  // All non-me players ordered by slot starting after me.
  const opponents: Seat[] = [];
  for (let i = 1; i < Math.max(maxPlayers, 1); i++) {
    const s = seats.find(x => x.slot === ((base + i) % Math.max(maxPlayers, 1)));
    if (s) opponents.push(s);
  }

  return (
    <div className="relative w-full h-full flex flex-col overflow-hidden"
      style={{
        background: "linear-gradient(180deg,#0b3a86 0%,#0f4aa8 60%,#1257c2 100%)",
        minHeight: 260,
      }}>
      {/* Top header: opponents in the two corners, target score centered. */}
      <div className="relative px-3 pt-2 pb-2"
        style={{ background: "linear-gradient(180deg,#071634 0%,#0b214b 100%)" }}>
        <div className="grid grid-cols-[1fr_auto_1fr] items-start gap-2">
          <div className="flex items-start justify-start relative">
            {opponents.length >= 2 ? (
              <PlayerHeader seat={opponents[0]} side="left" size="lg" />
            ) : <div />}
          </div>
          {targetScore ? (
            <div className="flex flex-col items-center shrink-0 pt-1">
              <div className="text-white text-2xl font-black leading-none tabular-nums tracking-tight">{targetScore}</div>
              <div className="mt-1 w-6 h-6 rounded-full bg-white text-[#c0392b] text-[9px] font-extrabold flex items-center justify-center shadow"
                style={{ border: "2px solid #c0392b" }}>CO</div>
            </div>
          ) : <div />}
          <div className="flex items-start justify-end relative">
            {(opponents.length >= 2 ? opponents.slice(1, 2) : opponents.slice(0, 1)).map(op => (
              <PlayerHeader key={op.user_id} seat={op} side="right" size="lg" />
            ))}
          </div>
        </div>
      </div>


      {/* Opponents' face-down hand counts are shown next to their avatars in the header above. */}

      {/* Play field — snake layout */}
      <div className="flex-1 min-h-0 relative">
        <SnakeBoard
          board={board}
          leftEnd={leftEnd}
          rightEnd={rightEnd}
          canDropLeft={!!canDropLeft}
          canDropRight={!!canDropRight}
          onDropLeft={onDropLeft}
          onDropRight={onDropRight}
          canDropAny={canDropAny}
          onDropAny={onDropAny}
          seed={seed}
        />
      </div>

      {statusMessage && (
        <div className="absolute bottom-2 left-0 right-0 px-4 flex justify-center pointer-events-none z-30">
          <div key={statusMessage} className={`px-5 py-2.5 rounded-xl text-center font-bold text-sm shadow-lg max-w-[90%] ${statusType === "blocked" ? "bg-red-600/90 text-white" : statusType === "pass" ? "bg-orange-500/90 text-white" : "bg-[#0a1a3e]/90 text-white"}`}>
            {statusMessage}
          </div>
        </div>
      )}

      {/* Stock (pioche) is rendered outside the plateau by the parent route. */}
    </div>
  );
}
