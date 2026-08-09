import { useEffect, useRef } from "react";
import {
  playClack,
  playDraw,
  playPass,
  playYourTurn,
  playWin,
  playLose,
  unlockAudio,
  isSfxMuted,
} from "@/lib/sounds/game-sounds";

/**
 * Watches domino game state and plays sound effects on key events:
 * - Tile placed on board  → clack
 * - Tile drawn from stock → draw swoosh
 * - Player passes         → soft thud
 * - It becomes your turn  → gentle ping
 * - Game ends             → win / lose jingle
 */
export function useDominoSounds(opts: {
  game: any;
  parts: any[];
  myUserId: string | undefined;
}) {
  const { game, parts, myUserId } = opts;

  // ── Refs to detect changes between renders ──────────────────────────────
  const prevBoardLen = useRef(0);
  const prevStockSize = useRef(0);
  const prevPasses = useRef(0);
  const prevTurn = useRef<number | null>(null);
  const prevStatus = useRef<string>("open");
  const prevPhase = useRef<string>("");
  const started = useRef(false);

  const mySlot = parts.find((p) => p.user_id === myUserId)?.slot;

  useEffect(() => {
    if (!game) return;
    if (isSfxMuted()) {
      // Still update refs so we don't burst sounds when unmuting
      const board = game?.state?.board;
      const boardLen = Array.isArray(board) ? board.length : 0;
      const stockSize = (game?.state?.stock || []).length;
      const passes = Number(game?.state?.passes || 0);
      const currentTurn = game?.current_turn ?? null;
      const status = game?.status ?? "open";
      const phase = game?.state?.phase ?? "";
      prevBoardLen.current = boardLen;
      prevStockSize.current = stockSize;
      prevPasses.current = passes;
      prevTurn.current = currentTurn;
      prevStatus.current = status;
      prevPhase.current = phase;
      return;
    }

    // Unlock audio on first interaction
    unlockAudio();

    const board = game?.state?.board;
    const boardLen = Array.isArray(board) ? board.length : 0;
    const stockSize = (game?.state?.stock || []).length;
    const passes = Number(game?.state?.passes || 0);
    const currentTurn = game?.current_turn ?? null;
    const status = game?.status ?? "open";
    const phase = game?.state?.phase ?? "";

    // Skip the very first render (initial load) to avoid spurious sounds
    if (!started.current) {
      prevBoardLen.current = boardLen;
      prevStockSize.current = stockSize;
      prevPasses.current = passes;
      prevTurn.current = currentTurn;
      prevStatus.current = status;
      prevPhase.current = phase;
      started.current = true;
      return;
    }

    // ── Tile placed → clack ──────────────────────────────────────────────
    if (boardLen > prevBoardLen.current && phase === "play" && status === "playing") {
      playClack();
    }

    // ── Tile drawn → swoosh ──────────────────────────────────────────────
    if (stockSize < prevStockSize.current && status === "playing") {
      playDraw();
    }

    // ── Pass → thud ──────────────────────────────────────────────────────
    if (passes > prevPasses.current && status === "playing") {
      playPass();
    }

    // ── Your turn → ping ──────────────────────────────────────────────────
    if (
      currentTurn !== prevTurn.current &&
      mySlot === currentTurn &&
      status === "playing" &&
      phase === "play"
    ) {
      playYourTurn();
    }

    // ── Game ended → win or lose ─────────────────────────────────────────
    if (status === "finished" && prevStatus.current === "playing") {
      const winnerId = game?.winner;
      const winnerSlot = game?.state?.winner_slot;
      const iWon = (winnerId && winnerId === myUserId) || (winnerSlot != null && winnerSlot === mySlot);
      if (iWon) playWin();
      else playLose();
    }

    // ── Update refs ──────────────────────────────────────────────────────
    prevBoardLen.current = boardLen;
    prevStockSize.current = stockSize;
    prevPasses.current = passes;
    prevTurn.current = currentTurn;
    prevStatus.current = status;
    prevPhase.current = phase;
  }, [
    game?.state?.board,
    game?.state?.stock,
    game?.state?.passes,
    game?.current_turn,
    game?.status,
    game?.state?.phase,
    game?.winner,
    game?.state?.winner_slot,
    parts,
    myUserId,
  ]);
}
