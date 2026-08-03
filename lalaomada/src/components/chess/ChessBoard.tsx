import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { Chess, type Move, type Square } from "chess.js";

/** Wood classic chess board — tap-to-move + drag & drop, bigger 3D pieces. */

type Piece = { color: "w" | "b"; type: "p" | "n" | "b" | "r" | "q" | "k" };

const FILES = ["a", "b", "c", "d", "e", "f", "g", "h"] as const;

/* ------------------------ Piece (classic Unicode, 3D shadow) ------------------------ */
// Both colours use the FILLED glyphs; colour comes from `color` + strong outline
// so pieces stay unambiguous on any square, at any size.
const PIECE_GLYPH: Record<string, string> = {
  wK: "♚", wQ: "♛", wR: "♜", wB: "♝", wN: "♞", wP: "♟",
  bK: "♚", bQ: "♛", bR: "♜", bB: "♝", bN: "♞", bP: "♟",
};

const PieceSVG = memo(function PieceSVG({ piece, dragging = false }: { piece: Piece; dragging?: boolean }) {
  const key = (piece.color + piece.type.toUpperCase()) as keyof typeof PIECE_GLYPH;
  const isWhite = piece.color === "w";
  const glyph = PIECE_GLYPH[key];

  return (
    <span
      className="select-none pointer-events-none flex items-center justify-center w-full h-full"
      style={{
        // Scale with the cell itself (container query units) instead of parent font-size
        fontSize: "88cqmin",
        lineHeight: 1,
        color: isWhite ? "#ffffff" : "#111014",
        WebkitTextStroke: isWhite ? "1.8px #0a0a0a" : "1.2px #4a3a2a",
        textShadow: isWhite
          ? "0 2px 3px rgba(0,0,0,0.55), 0 0 1px #000, 0 -1px 0 rgba(255,255,255,0.9)"
          : "0 3px 3px rgba(0,0,0,0.6), 0 -1px 0 rgba(255,255,255,0.15)",
        transform: dragging ? "translateY(-3px) scale(1.08)" : undefined,
        filter: dragging ? "drop-shadow(0 10px 12px rgba(0,0,0,0.6))" : undefined,
        transition: "transform 80ms ease-out",
      }}
    >
      {glyph}
    </span>
  );
});

/* ------------------------ Cell ------------------------ */
type CellProps = {
  square: Square;
  piece: Piece | null;
  isLight: boolean;
  isSelected: boolean;
  isTarget: boolean;
  isCapture: boolean;
  isLastFrom: boolean;
  isLastTo: boolean;
  isCheck: boolean;
  showFile: boolean;
  showRank: boolean;
  rankLabel: string;
  fileLabel: string;
  onPointerDown: (sq: Square, e: React.PointerEvent) => void;
};

const Cell = memo(function Cell(p: CellProps) {
  const bg = p.isLight ? "#f0d9b5" : "#b58863";
  const highlight = p.isLastFrom || p.isLastTo
    ? "rgba(251,191,36,0.42)"
    : p.isSelected
    ? "rgba(251,191,36,0.60)"
    : null;
  return (
    <div
      data-square={p.square}
      onPointerDown={(e) => p.onPointerDown(p.square, e)}
      className="relative"
      style={{
        background: bg,
        touchAction: "none",
        WebkitTapHighlightColor: "transparent",
        userSelect: "none",
        containerType: "size",
      }}
    >
      {highlight && <div className="absolute inset-0 pointer-events-none" style={{ background: highlight }} />}
      {p.isCheck && (
        <div className="absolute inset-0 pointer-events-none" style={{ background: "radial-gradient(circle, rgba(220,38,38,0.55), transparent 65%)" }} />
      )}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
        {p.piece && <PieceSVG piece={p.piece} />}
      </div>
      {p.isTarget && !p.isCapture && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <div className="rounded-full" style={{ width: "32%", height: "32%", background: "rgba(30,30,30,0.32)" }} />
        </div>
      )}
      {p.isCapture && (
        <div
          className="absolute inset-0 pointer-events-none"
          style={{
            background:
              "radial-gradient(circle, transparent 55%, rgba(220,38,38,0.55) 56%, rgba(220,38,38,0.55) 63%, transparent 64%)",
          }}
        />
      )}
      {p.showFile && (
        <span className="absolute bottom-0 right-1 text-[9px] font-bold opacity-70 pointer-events-none" style={{ color: p.isLight ? "#b58863" : "#f0d9b5" }}>
          {p.fileLabel}
        </span>
      )}
      {p.showRank && (
        <span className="absolute top-0 left-1 text-[9px] font-bold opacity-70 pointer-events-none" style={{ color: p.isLight ? "#b58863" : "#f0d9b5" }}>
          {p.rankLabel}
        </span>
      )}
    </div>
  );
});

/* ------------------------ Board ------------------------ */
export type ChessBoardProps = {
  fen: string;
  myColor: "w" | "b";
  onMove: (uci: string, san: string, fenAfter: string) => void | Promise<void>;
  lastMove?: { from: string; to: string } | null;
  disabled?: boolean;
};

export function ChessBoard({ fen, myColor, onMove, lastMove, disabled }: ChessBoardProps) {
  const chess = useMemo(() => {
    try { return new Chess(fen); } catch { return new Chess(); }
  }, [fen]);

  const board = useMemo(() => chess.board(), [chess]);
  const turn = chess.turn();
  const myTurn = !disabled && turn === myColor;

  const [selected, setSelected] = useState<Square | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const lockRef = useRef(false);

  const legal = useMemo(() => {
    if (!selected) return [] as Move[];
    return chess.moves({ square: selected, verbose: true }) as Move[];
  }, [chess, selected]);
  const legalMap = useMemo(() => new Map(legal.map((m) => [m.to, m])), [legal]);

  useEffect(() => { setSelected(null); }, [fen]);

  const kingInCheck: Square | null = useMemo(() => {
    if (!chess.inCheck()) return null;
    for (let r = 0; r < 8; r++) for (let f = 0; f < 8; f++) {
      const sq = board[r][f];
      if (sq && sq.type === "k" && sq.color === turn) return (FILES[f] + (8 - r)) as Square;
    }
    return null;
  }, [chess, board, turn]);

  const commitMove = useCallback(async (from: Square, to: Square) => {
    if (lockRef.current) return;
    const before = new Chess(chess.fen());
    let move: Move | null = null;
    try { move = before.move({ from, to, promotion: "q" }) as Move; } catch { move = null; }
    if (!move) return;
    lockRef.current = true;
    setSelected(null);
    try {
      const uci = from + to + (move.promotion ? move.promotion : "");
      await onMove(uci, move.san, before.fen());
    } finally {
      setTimeout(() => { lockRef.current = false; }, 100);
    }
  }, [chess, onMove]);

  const pieceAt = useCallback((sq: Square): Piece | null => {
    const f = FILES.indexOf(sq[0] as any);
    const r = 8 - Number(sq[1]);
    const cell = board[r][f];
    return cell ? { color: cell.color, type: cell.type } : null;
  }, [board]);

  const onPointerDown = useCallback((sq: Square, _e: React.PointerEvent) => {
    if (!myTurn) return;
    if (selected && legalMap.has(sq)) {
      flushSync(() => setSelected(null));
      void commitMove(selected, sq);
      return;
    }
    const p = pieceAt(sq);
    if (p && p.color === myColor) {
      flushSync(() => setSelected(sq));
      return;
    }
    if (selected) flushSync(() => setSelected(null));
  }, [myTurn, myColor, pieceAt, selected, legalMap, commitMove]);


  // Build cells (oriented by myColor)
  const flip = myColor === "b";
  const cells: JSX.Element[] = [];
  for (let visRow = 0; visRow < 8; visRow++) {
    for (let visCol = 0; visCol < 8; visCol++) {
      const boardRow = flip ? 7 - visRow : visRow;
      const boardCol = flip ? 7 - visCol : visCol;
      const sq = (FILES[boardCol] + (8 - boardRow)) as Square;
      const cell = board[boardRow][boardCol];
      const piece: Piece | null = cell ? { color: cell.color, type: cell.type } : null;
      const isLight = (boardRow + boardCol) % 2 === 0;
      const isSelected = selected === sq;
      const isTarget = !!(selected && legalMap.has(sq));
      const isCapture = isTarget && !!piece;
      const isLastFrom = lastMove?.from === sq;
      const isLastTo = lastMove?.to === sq;
      const isCheck = kingInCheck === sq;
      cells.push(
        <Cell
          key={sq}
          square={sq}
          piece={piece}
          isLight={isLight}
          isSelected={isSelected}
          isTarget={isTarget}
          isCapture={isCapture}
          isLastFrom={isLastFrom}
          isLastTo={isLastTo}
          isCheck={isCheck}
          showFile={visRow === 7}
          showRank={visCol === 0}
          rankLabel={String(8 - boardRow)}
          fileLabel={FILES[boardCol]}
          onPointerDown={onPointerDown}
        />,
      );
    }
  }

  // Empêche le scroll de la page pendant un contact tactile sur l'échiquier
  useEffect(() => {
    const el = containerRef.current?.parentElement;
    if (!el) return;
    const prevent = (e: TouchEvent) => { e.preventDefault(); };
    el.addEventListener("touchstart", prevent, { passive: false });
    el.addEventListener("touchmove", prevent, { passive: false });
    return () => {
      el.removeEventListener("touchstart", prevent);
      el.removeEventListener("touchmove", prevent);
    };
  }, []);

  return (
    <div
      className="relative w-full mx-auto rounded-lg overflow-hidden select-none overscroll-contain"
      style={{
        maxWidth: "min(100%, calc(100dvh - 260px))",
        aspectRatio: "1 / 1",
        boxShadow: "0 6px 20px rgba(0,0,0,0.35), inset 0 0 0 6px #5a3a1a, inset 0 0 0 8px #8b5a2b",
        background: "#5a3a1a",
        touchAction: "none",
        overscrollBehavior: "contain",
      }}
    >
      <div ref={containerRef} className="absolute inset-[8px] grid grid-cols-8 grid-rows-8">
        {cells}
      </div>
    </div>
  );
}
