import type React from "react";
import { memo, useCallback, useEffect, useMemo, useRef, useState } from "react";
import { flushSync } from "react-dom";
import { Chess, type Move, type Square } from "chess.js";

/** Chess.com-style board — tap-to-move + drag & drop + promotion selector + smooth slide animation. */

type Piece = { color: "w" | "b"; type: "p" | "n" | "b" | "r" | "q" | "k" };

const FILES = ["a", "b", "c", "d", "e", "f", "g", "h"] as const;

/* ------------------------ Piece (classic Unicode, 3D shadow) ------------------------ */
const PIECE_GLYPH: Record<string, string> = {
  wK: "♔", wQ: "♕", wR: "♖", wB: "♗", wN: "♘", wP: "♙",
  bK: "♚", bQ: "♛", bR: "♜", bB: "♝", bN: "♞", bP: "♟",
};

const PieceSVG = memo(function PieceSVG({ piece, dragging = false, animStyle }: { piece: Piece; dragging?: boolean; animStyle?: React.CSSProperties }) {
  const key = (piece.color + piece.type.toUpperCase()) as keyof typeof PIECE_GLYPH;
  const isWhite = piece.color === "w";
  const glyph = PIECE_GLYPH[key];

  return (
    <span
      className="select-none pointer-events-none flex items-center justify-center w-full h-full"
      style={{
        fontSize: "88cqmin",
        lineHeight: 1,
        paintOrder: "stroke fill",
        color: isWhite ? "#ffffff" : "#111014",
        WebkitTextStroke: isWhite ? "1.8px #0a0a0a" : "1.2px #4a3a2a",
        textShadow: isWhite
          ? "0 2px 3px rgba(0,0,0,0.55), 0 0 1px #000, 0 -1px 0 rgba(255,255,255,0.9)"
          : "0 3px 3px rgba(0,0,0,0.6), 0 -1px 0 rgba(255,255,255,0.15)",
        transform: dragging ? "translateY(-3px) scale(1.12)" : undefined,
        filter: dragging ? "drop-shadow(0 10px 14px rgba(0,0,0,0.65))" : undefined,
        transition: "transform 80ms ease-out",
        ...animStyle,
      }}
    >
      {glyph}
    </span>
  );
});

/* ------------------------ Promotion selector ------------------------ */
function PromotionModal({ color, onSelect, onCancel }: { color: "w" | "b"; onSelect: (p: "q" | "r" | "b" | "n") => void; onCancel: () => void }) {
  const pieces: ("q" | "r" | "b" | "n")[] = ["q", "r", "b", "n"];
  return (
    <div className="absolute inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm" onPointerDown={onCancel}>
      <div className="bg-card rounded-xl p-3 shadow-2xl border border-border" onPointerDown={(e) => e.stopPropagation()}>
        <p className="text-xs font-semibold text-muted-foreground mb-2 text-center">Promotion</p>
        <div className="flex gap-2">
          {pieces.map((p) => {
            const key = (color + p.toUpperCase()) as keyof typeof PIECE_GLYPH;
            return (
              <button
                key={p}
                onPointerDown={(e) => { e.stopPropagation(); onSelect(p); }}
                className="w-14 h-14 rounded-lg flex items-center justify-center text-4xl hover:bg-accent transition-colors border border-border"
                style={{
                  paintOrder: "stroke fill",
                  color: color === "w" ? "#ffffff" : "#111014",
                  WebkitTextStroke: color === "w" ? "1.5px #0a0a0a" : "1px #4a3a2a",
                  textShadow: color === "w"
                    ? "0 2px 3px rgba(0,0,0,0.55)"
                    : "0 2px 3px rgba(0,0,0,0.5)",
                }}
              >
                {PIECE_GLYPH[key]}
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}

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
  isDragOver: boolean;
  showFile: boolean;
  showRank: boolean;
  rankLabel: string;
  fileLabel: string;
  onPointerDown: (sq: Square, e: React.PointerEvent) => void;
  onDragStart?: (sq: Square, e: React.DragEvent) => void;
  onDragEnd?: (e: React.DragEvent) => void;
  onDragEnter?: (sq: Square) => void;
  /** Slide animation offset in cell units (e.g. dx=-1 means piece starts 1 cell to the left). */
  animOffset?: { dx: number; dy: number } | null;
  /** When true, the piece is hidden (used for the `from` square during slide animation). */
  hidePiece?: boolean;
  /** When true, the captured piece fades out. */
  fadingOut?: boolean;
};

const Cell = memo(function Cell(p: CellProps) {
  const bg = p.isLight ? "#ebecd0" : "#769656";
  const dragOverBg = p.isLight ? "#f7f769" : "#bbb544";
  const highlight = p.isLastFrom || p.isLastTo
    ? "rgba(255, 235, 59, 0.45)"
    : p.isSelected
    ? "rgba(255, 235, 59, 0.55)"
    : null;

  // Compute the slide animation style for the piece
  const animStyle: React.CSSProperties | undefined = p.animOffset
    ? {
        transform: `translate(${p.animOffset.dx * 100}%, ${p.animOffset.dy * 100}%)`,
        transition: "transform 250ms cubic-bezier(0.25, 0.46, 0.45, 0.94)",
        zIndex: 10,
      }
    : p.fadingOut
    ? {
        opacity: 0,
        transition: "opacity 250ms ease-out",
        transform: "scale(0.7)",
      }
    : undefined;

  const showPiece = p.piece && !p.hidePiece;

  return (
    <div
      data-square={p.square}
      onPointerDown={(e) => p.onPointerDown(p.square, e)}
      onDragOver={(e) => { e.preventDefault(); }}
      onDragEnter={() => p.onDragEnter?.(p.square)}
      onDrop={(e) => { e.preventDefault(); }}
      draggable={!!p.onDragStart}
      onDragStart={(e) => p.onDragStart?.(p.square, e)}
      onDragEnd={p.onDragEnd}
      className="relative"
      style={{
        background: p.isDragOver ? dragOverBg : bg,
        touchAction: "none",
        WebkitTapHighlightColor: "transparent",
        userSelect: "none",
        containerType: "size",
      }}
    >
      {highlight && <div className="absolute inset-0 pointer-events-none" style={{ background: highlight }} />}
      {p.isCheck && (
        <div className="absolute inset-0 pointer-events-none" style={{ background: "radial-gradient(circle, rgba(220,38,38,0.65), transparent 65%)" }} />
      )}
      <div className="absolute inset-0 flex items-center justify-center pointer-events-none" style={{ overflow: "visible" }}>
        {showPiece && <PieceSVG piece={p.piece} animStyle={animStyle} />}
      </div>
      {p.isTarget && !p.isCapture && (
        <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
          <div className="rounded-full" style={{ width: "34%", height: "34%", background: "rgba(20,20,20,0.28)" }} />
        </div>
      )}
      {p.isCapture && (
        <div
          className="absolute inset-0 pointer-events-none"
          style={{
            background:
              "radial-gradient(circle, transparent 52%, rgba(20,20,20,0.35) 53%, rgba(20,20,20,0.35) 62%, transparent 63%)",
          }}
        />
      )}
      {p.showFile && (
        <span className="absolute bottom-0 right-1 text-[9px] font-bold opacity-70 pointer-events-none" style={{ color: p.isLight ? "#769656" : "#ebecd0" }}>
          {p.fileLabel}
        </span>
      )}
      {p.showRank && (
        <span className="absolute top-0 left-1 text-[9px] font-bold opacity-70 pointer-events-none" style={{ color: p.isLight ? "#769656" : "#ebecd0" }}>
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

const ANIM_MS = 250;

export function ChessBoard({ fen, myColor, onMove, lastMove, disabled }: ChessBoardProps) {
  const chess = useMemo(() => {
    try { return new Chess(fen); } catch { return new Chess(); }
  }, [fen]);

  const board = useMemo(() => chess.board(), [chess]);
  const turn = chess.turn();
  const myTurn = !disabled && turn === myColor;

  const [selected, setSelected] = useState<Square | null>(null);
  const [dragOverSq, setDragOverSq] = useState<Square | null>(null);
  const [pendingPromotion, setPendingPromotion] = useState<{ from: Square; to: Square } | null>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const lockRef = useRef(false);
  const dragSqRef = useRef<Square | null>(null);

  // ── Slide animation state ──
  // When the FEN changes, we compute which piece moved (using lastMove) and
  // render it starting at the `from` position, then CSS-transition it to `to`.
  type AnimState = {
    fen: string;
    from: Square;
    to: Square;
    flip: boolean;
    // Castling: rook also slides
    rookFrom?: Square;
    rookTo?: Square;
    // Captured piece (fades out)
    capturedSq?: Square;
  };
  const [anim, setAnim] = useState<AnimState | null>(null);
  const prevFenRef = useRef(fen);

  const flip = myColor === "b";

  useEffect(() => {
    setSelected(null);
    setPendingPromotion(null);
  }, [fen]);

  // Detect move and start animation
  useEffect(() => {
    if (fen === prevFenRef.current) return;
    prevFenRef.current = fen;
    if (!lastMove) { setAnim(null); return; }

    const from = lastMove.from as Square;
    const to = lastMove.to as Square;

    // Parse the new board to find what's at `to`
    let newChess: Chess;
    try { newChess = new Chess(fen); } catch { setAnim(null); return; }
    const newBoard = newChess.board();

    const toFile = FILES.indexOf(to[0] as any);
    const toRank = 8 - Number(to[1]);
    const destPiece = newBoard[toRank]?.[toFile];
    if (!destPiece) { setAnim(null); return; }

    // Check for castling: king moves 2 files horizontally
    const fromFile = FILES.indexOf(from[0] as any);
    let rookFrom: Square | undefined;
    let rookTo: Square | undefined;
    if (destPiece.type === "k" && Math.abs(toFile - fromFile) === 2) {
      // Kingside (toFile > fromFile): rook from h to f
      // Queenside (toFile < fromFile): rook from a to d
      const rookFromFile = toFile > fromFile ? 7 : 0;
      const rookToFile = toFile > fromFile ? toFile - 1 : toFile + 1;
      const rankStr = from[1];
      rookFrom = (FILES[rookFromFile] + rankStr) as Square;
      rookTo = (FILES[rookToFile] + rankStr) as Square;
    }

    // Check for en passant: pawn captures diagonally but dest is empty in old position
    // The captured pawn is on the same file as `to` but same rank as `from`
    let capturedSq: Square | undefined;
    const fromRank = Number(from[1]);
    const toRankNum = Number(to[1]);
    if (destPiece.type === "p" && toFile !== fromFile && toRankNum !== fromRank) {
      // Diagonal pawn move — check if the dest was empty before (en passant)
      // Actually, normal captures also go diagonal. We detect en passant by
      // checking if the captured pawn square is different from `to`.
      // En passant captured pawn is at (to[0], from[1])
      const epSq = (to[0] + from[1]) as Square;
      const epFile = FILES.indexOf(to[0] as any);
      const epRank = 8 - fromRank;
      const epPiece = newBoard[epRank]?.[epFile];
      // If the to square now has a pawn but ep square is empty → en passant happened
      // We can check the old board, but simplest: en passant if fromFile≠toFile and old to was empty
      // For animation purposes, we just need to know which square had the captured piece
      // In en passant, the captured pawn is NOT on `to` — it's on epSq
      // We can detect this by checking if the old board had a piece on `to`
      let oldChess: Chess;
      try { oldChess = new Chess(lastMove.from + lastMove.to); } catch {
        try { oldChess = new Chess(fen); } catch { oldChess = newChess; }
      }
      // Simpler: if diagonal pawn move and the to-square in the OLD board was empty → en passant
      // We can't easily get the old board. Let's just check: if to[1] != from[1] and fromFile != toFile
      // and the captured piece is a pawn → it could be en passant.
      // For the fade-out animation, the captured piece is at epSq (not at `to`).
      // But in a normal capture, the captured piece IS at `to`.
      // We can detect en passant: the pawn moved diagonally to an empty square.
      // Since we don't have the old board easily, let's check the en passant square.
      if (!epPiece) {
        // The square at (to[0], from[1]) is empty in the new board → en passant capture
        capturedSq = epSq;
      } else {
        // Normal capture — the captured piece was at `to` (already replaced by the mover)
        // We can't show a fade-out for normal captures since the piece is already gone.
        // That's fine — the slide animation covers it.
      }
    }

    setAnim({ fen, from, to, flip, rookFrom, rookTo, capturedSq });

    const timer = setTimeout(() => setAnim(null), ANIM_MS + 50);
    return () => clearTimeout(timer);
  }, [fen, lastMove]);

  // Helper: compute visual grid position of a square (accounting for flip)
  const visPos = useCallback((sq: Square): { col: number; row: number } => {
    const f = FILES.indexOf(sq[0] as any);
    const r = 8 - Number(sq[1]);
    return {
      col: flip ? 7 - f : f,
      row: flip ? 7 - r : r,
    };
  }, [flip]);

  // Compute animation offset for a given from→to pair
  const animOffsetFor = useCallback((from: Square, to: Square): { dx: number; dy: number } => {
    const fp = visPos(from);
    const tp = visPos(to);
    return { dx: fp.col - tp.col, dy: fp.row - tp.row };
  }, [visPos]);

  const legal = useMemo(() => {
    if (!selected) return [] as Move[];
    return chess.moves({ square: selected, verbose: true }) as Move[];
  }, [chess, selected]);
  const legalMap = useMemo(() => new Map(legal.map((m) => [m.to, m])), [legal]);

  const kingInCheck: Square | null = useMemo(() => {
    if (!chess.inCheck()) return null;
    for (let r = 0; r < 8; r++) for (let f = 0; f < 8; f++) {
      const sq = board[r][f];
      if (sq && sq.type === "k" && sq.color === turn) return (FILES[f] + (8 - r)) as Square;
    }
    return null;
  }, [chess, board, turn]);

  const commitMove = useCallback(async (from: Square, to: Square, promotion?: string) => {
    if (lockRef.current) return;
    const before = new Chess(chess.fen());

    const moves = before.moves({ square: from, verbose: true }) as Move[];
    const targetMoves = moves.filter((m) => m.to === to);
    const needsPromotion = targetMoves.some((m) => m.promotion);
    const isPromotion = needsPromotion && !promotion;

    if (isPromotion) {
      setPendingPromotion({ from, to });
      return;
    }

    let move: Move | null = null;
    try {
      move = before.move({ from, to, promotion: promotion || "q" }) as Move;
    } catch { move = null; }
    if (!move) return;
    lockRef.current = true;
    setSelected(null);
    setPendingPromotion(null);
    try {
      const uci = from + to + (move.promotion ? move.promotion : "");
      await onMove(uci, move.san, before.fen());
    } finally {
      setTimeout(() => { lockRef.current = false; }, 100);
    }
  }, [chess, onMove]);

  const handlePromotionSelect = useCallback((promotion: "q" | "r" | "b" | "n") => {
    if (!pendingPromotion) return;
    void commitMove(pendingPromotion.from, pendingPromotion.to, promotion);
  }, [pendingPromotion, commitMove]);

  const pieceAt = useCallback((sq: Square): Piece | null => {
    const f = FILES.indexOf(sq[0] as any);
    const r = 8 - Number(sq[1]);
    const cell = board[r][f];
    return cell ? { color: cell.color, type: cell.type } : null;
  }, [board]);

  const onPointerDown = useCallback((sq: Square, _e: React.PointerEvent) => {
    if (!myTurn) return;
    if (pendingPromotion) return;
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
  }, [myTurn, myColor, pieceAt, selected, legalMap, commitMove, pendingPromotion]);

  // Drag and drop
  const onDragStart = useCallback((sq: Square, e: React.DragEvent) => {
    if (!myTurn) { e.preventDefault(); return; }
    const p = pieceAt(sq);
    if (!p || p.color !== myColor) { e.preventDefault(); return; }
    dragSqRef.current = sq;
    setSelected(sq);
    e.dataTransfer.effectAllowed = "move";
    const img = new Image();
    img.src = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxIiBoZWlnaHQ9IjEiLz4=";
    e.dataTransfer.setDragImage(img, 0, 0);
  }, [myTurn, myColor, pieceAt]);

  const onDragEnd = useCallback((_e: React.DragEvent) => {
    dragSqRef.current = null;
    setDragOverSq(null);
  }, []);

  const onDragEnterCell = useCallback((sq: Square) => {
    setDragOverSq(sq);
  }, []);

  // Handle drop via the container (delegated)
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const handleDrop = (e: DragEvent) => {
      e.preventDefault();
      const sq = (e.target as HTMLElement)?.closest("[data-square]")?.getAttribute("data-square") as Square | null;
      setDragOverSq(null);
      if (!sq || !dragSqRef.current) return;
      if (sq === dragSqRef.current) { setSelected(null); return; }
      if (legalMap.has(sq)) {
        void commitMove(dragSqRef.current, sq);
      }
      setSelected(null);
      dragSqRef.current = null;
    };
    el.addEventListener("drop", handleDrop as any);
    return () => el.removeEventListener("drop", handleDrop as any);
  }, [legalMap, commitMove]);

  // Build cells (oriented by myColor)
  const cells: React.ReactElement[] = [];
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
      const isDragOver = dragOverSq === sq;
      const canDrag = !!(myTurn && piece && piece.color === myColor);

      // ── Animation props ──
      let animOffset: { dx: number; dy: number } | null = null;
      let hidePiece = false;
      let fadingOut = false;

      if (anim && anim.fen === fen) {
        // Main piece slides from `from` to `to`
        if (sq === anim.to) {
          animOffset = animOffsetFor(anim.from, anim.to);
        } else if (sq === anim.from) {
          // Hide the piece at the `from` square (it's sliding to `to`)
          hidePiece = true;
        }

        // Castling: rook also slides
        if (anim.rookTo && sq === anim.rookTo) {
          animOffset = animOffsetFor(anim.rookFrom!, anim.rookTo);
        } else if (anim.rookFrom && sq === anim.rookFrom) {
          hidePiece = true;
        }

        // En passant: captured pawn fades out
        if (anim.capturedSq && sq === anim.capturedSq) {
          fadingOut = true;
        }
      }

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
          isDragOver={isDragOver}
          showFile={visRow === 7}
          showRank={visCol === 0}
          rankLabel={String(8 - boardRow)}
          fileLabel={FILES[boardCol]}
          onPointerDown={onPointerDown}
          onDragStart={canDrag ? onDragStart : undefined}
          onDragEnd={onDragEnd}
          onDragEnter={onDragEnterCell}
          animOffset={animOffset}
          hidePiece={hidePiece}
          fadingOut={fadingOut}
        />,
      );
    }
  }

  // Prevent page scroll on touch over the board
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
      className="relative w-full mx-auto rounded-md overflow-hidden select-none overscroll-contain"
      style={{
        maxWidth: "min(100%, calc(100dvh - 280px))",
        aspectRatio: "1 / 1",
        boxShadow: "0 6px 20px rgba(0,0,0,0.35), inset 0 0 0 5px #3f2d1a, inset 0 0 0 7px #5a3a1a",
        background: "#5a3a1a",
        touchAction: "none",
        overscrollBehavior: "contain",
      }}
    >
      <div ref={containerRef} className="absolute inset-[7px] grid grid-cols-8 grid-rows-8">
        {cells}
      </div>
      {pendingPromotion && (
        <PromotionModal
          color={myColor}
          onSelect={handlePromotionSelect}
          onCancel={() => setPendingPromotion(null)}
        />
      )}
    </div>
  );
}
