import { useEffect, useRef } from "react";
import { playClack, playDraw, playPass, playWin } from "@/lib/sounds/game-sounds";

export function useDominoSounds({ game, parts, myUserId }: {
  game: any; parts: any[]; myUserId?: string;
}) {
  const prevBoard = useRef(0);
  const prevTurn = useRef<number | null>(null);
  const prevStatus = useRef<string>("");

  useEffect(() => {
    if (!game) return;
    const bl = Array.isArray(game?.state?.board) ? game.state.board.length : 0;
    const turn = game?.current_turn ?? null;
    const status = game?.status ?? "";

    if (bl > prevBoard.current) playClack();
    if (prevTurn.current !== null && turn !== prevTurn.current && status === "playing") {
      if (bl === prevBoard.current) playDraw();
    }
    if (status === "finished" && prevStatus.current !== "finished") {
      const ws = game?.state?.winner_slot;
      const me = parts.find(p => p.user_id === myUserId);
      if (me && typeof ws === "number" && ws === me.slot) playWin();
    }
    prevBoard.current = bl; prevTurn.current = turn; prevStatus.current = status;
  }, [game?.state?.board, game?.current_turn, game?.status, game, parts, myUserId]);
}
