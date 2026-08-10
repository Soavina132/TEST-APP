import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState, useCallback, useMemo, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";
import { LogOut, Pause, Copy, Timer, RotateCw, SkipForward, Volume2, VolumeX } from "lucide-react";
import GameSocialFab from "@/components/game/GameSocialFab";
import GamePauseControl from "@/components/game/GamePauseControl";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import { useGameConfig } from "@/hooks/game/use-game-config";
import { useGlobalGameTimer } from "@/hooks/game/use-global-game-timer";
import { useConfirm } from "@/components/ConfirmDialog";
import { playFanoronaMove, playFanoronaCapture, playFanoronaWin, playFanoronaLose, unlockAudio } from "@/lib/sounds/fanorona-sounds";
import { setMuted as setSfxMuted, isMuted as isSfxMuted } from "@/lib/game-sounds";
import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";

export const Route = createFileRoute("/_authenticated/jeux/fanorona/$id")({
  component: FanoronaPage,
  head: () => ({ meta: [{ title: "Fanorona — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

const isStrong = (r: number, c: number) => (r + c) % 2 === 0;
const DIRS_ORTHO = [[-1,0],[1,0],[0,-1],[0,1]];
const DIRS_DIAG = [[-1,-1],[-1,1],[1,-1],[1,1]];
const ALL_DIRS = [...DIRS_ORTHO, ...DIRS_DIAG];

function axisKey(dr: number, dc: number): string {
  return (dr < 0 || (dr === 0 && dc < 0)) ? `${-dr},${-dc}` : `${dr},${dc}`;
}

function makeHelpers(COLS: number, ROWS: number) {
  const idx = (r: number, c: number) => r * COLS + c;
  const inBounds = (r: number, c: number) => r >= 0 && r < ROWS && c >= 0 && c < COLS;
  function neighbors(r: number, c: number): number[][] {
    const dirs = isStrong(r, c) ? ALL_DIRS : DIRS_ORTHO;
    return dirs.filter(([dr, dc]) => inBounds(r+dr, c+dc));
  }
  function legalTargets(board: number[], from: number, myColor: number, chainFrom: number | null, visited: number[], lastAxis: string | null) {
    const fr = Math.floor(from / COLS), fc = from % COLS;
    const strong = isStrong(fr, fc);
    const dirs = strong ? ALL_DIRS : DIRS_ORTHO;
    const targets: { to: number; approach: number[]; withdrawal: number[] }[] = [];
    for (const [dr, dc] of dirs) {
      const nr = fr + dr, nc = fc + dc;
      if (!inBounds(nr, nc)) continue;
      const to = idx(nr, nc);
      if (board[to] !== 0) continue;
      if (chainFrom !== null) {
        if (visited.includes(to)) continue;
        const ax = axisKey(dr, dc);
        if (lastAxis && ax === lastAxis) continue;
      }
      const opp = myColor === 1 ? 2 : 1;
      const { approach, withdrawal } = computeCaptures(board, from, to, myColor);
      targets.push({ to, approach, withdrawal });
    }
    return targets;
  }
  function computeCaptures(board: number[], from: number, to: number, myColor: number) {
    const opp = myColor === 1 ? 2 : 1;
    const fr = Math.floor(from / COLS), fc = from % COLS;
    const tr = Math.floor(to / COLS), tc = to % COLS;
    const dr = tr - fr, dc = tc - fc;
    const approach: number[] = [];
    let r = tr + dr, c = tc + dc;
    while (inBounds(r, c) && board[idx(r, c)] === opp) { approach.push(idx(r, c)); r += dr; c += dc; }
    const withdrawal: number[] = [];
    r = fr - dr; c = fc - dc;
    while (inBounds(r, c) && board[idx(r, c)] === opp) { withdrawal.push(idx(r, c)); r -= dr; c -= dc; }
    return { approach, withdrawal };
  }
  return { idx, inBounds, neighbors, legalTargets, computeCaptures };
}

function countPieces(board: number[], color: number): number {
  return board.filter(v => v === color).length;
}

/** Chess-style player bar with avatar, name, timer and piece count. */
function fmtClock(ms: number) {
  const s = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r.toString().padStart(2, "0")}`;
}

function FanoronaPlayerBar({
  p, isCurrent, isMe, pieceCount, timeMs, avatarUrl,
}: {
  p: any; isCurrent: boolean; isMe: boolean; pieceCount: number; timeMs: number; avatarUrl?: string | null;
}) {
  const isWhite = p.color === "white";
  const low = timeMs < 30_000;
  const critical = timeMs < 10_000;
  const name = p.display_name || "Joueur";
  return (
    <div className={`flex items-center gap-2.5 px-2.5 py-1.5 rounded-lg transition-colors duration-300 ${
      isCurrent ? "bg-card shadow-md border border-amber-400/40" : "bg-card/80 backdrop-blur border border-border"
    }`}>
      <div
        className="w-9 h-9 rounded-md overflow-hidden flex-shrink-0 border-2"
        style={{ borderColor: isWhite ? "#fafaf9" : "#1c1917" }}
      >
        {avatarUrl ? (
          <img src={avatarUrl} alt={name} className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-muted text-sm font-bold">
            {name.slice(0, 1).toUpperCase()}
          </div>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <div className="font-semibold text-xs truncate flex items-center gap-1.5">
          {name}
          {p.is_bot && <span className="text-[10px] text-violet-500 shrink-0">🤖</span>}
          {isMe && <span className="text-[10px] text-primary/60 shrink-0">(vous)</span>}
          {isCurrent && <span className="w-1.5 h-1.5 rounded-full bg-amber-400 animate-pulse" />}
        </div>
        <div className="flex items-center gap-1.5 mt-0.5">
          <span className="text-[10px] font-semibold text-muted-foreground">
            {p.forfeited ? <span className="text-destructive">Forfait</span> : `♟ ${pieceCount} pions`}
          </span>
        </div>
      </div>
      <div
        className={`shrink-0 font-mono text-base font-bold tabular-nums px-2.5 py-1 rounded-md transition-colors ${
          critical ? "bg-red-500 text-white animate-pulse" : low ? "text-red-600 dark:text-red-400" : ""
        }`}
        style={!critical ? { background: isCurrent ? "rgba(251,191,36,0.12)" : undefined } : undefined}
      >
        {fmtClock(timeMs)}
      </div>
    </div>
  );
}

function FanoronaWaitingBar() {
  return (
    <div className="rounded-lg p-1.5 bg-card border-2 border-dashed border-white/10 text-center text-[11px] text-muted-foreground">
      ⏳ En attente adversaire…
    </div>
  );
}

function FanoronaPage() {
  const { id } = Route.useParams();
  const { profile, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = useState(!isSfxMuted());

  // ALL HOOKS FIRST — before any early return
const { game, parts, setGame, setParts, loading, connected, reload } = useFastRealtime({
    gameTable: "fanorona_games",
    participantTable: "fanorona_participants",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile,
  }) as any;

  const [profiles, setProfiles] = useState<Record<string, { pseudo: string; avatar_url: string | null }>>({});
  const [selected, setSelected] = useState<number | null>(null);
  const [captureChoice, setCaptureChoice] = useState<{ from: number; to: number; approach: number[]; withdrawal: number[] } | null>(null);
  const [busy, setBusy] = useState(false);
  const [rotated90, setRotated90] = useState(false);
  const [lastMove, setLastMove] = useState<{ from: number; to: number; captured: number[] } | null>(null);
  const [animatingCapture, setAnimatingCapture] = useState<number[]>([]);
  const botTriggeredRef = useRef<number | string>(-1);
  const lastBoardRef = useRef<string>("");
  // load alias for use in timeout callbacks (maps to useFastRealtime reload)
  const load = reload;
  // loaded / loadError derived from hook state
  const loaded = !loading;
  const [loadError, setLoadError] = useState<string | null>(null);

  // Load player profiles for avatars
  useEffect(() => {
    if (!parts.length) return;
    const uids = parts.map(pt => pt.user_id).filter(Boolean);
    if (!uids.length) return;
    supabase.from("profiles").select("id,pseudo,avatar_url").in("id", uids).then(({ data }) => {
      if (!data) return;
      const map: Record<string, { pseudo: string; avatar_url: string | null }> = {};
      (data as any[]).forEach(x => { map[x.id] = { pseudo: x.pseudo, avatar_url: x.avatar_url }; });
      setProfiles(map);
    });
  }, [parts]);

  // Detect portrait orientation for board rotation on mobile
  useEffect(() => {
    const check = () => {
      setRotated90(window.innerHeight > window.innerWidth && window.innerWidth < 500);
    };
    check();
    window.addEventListener("resize", check);
    window.addEventListener("orientationchange", check);
    return () => {
      window.removeEventListener("resize", check);
      window.removeEventListener("orientationchange", check);
    };
  }, []);

  // Measure the actual available space for the board (instead of relying on
  // End a capture chain voluntarily (Fanorona rule: enchaînement est optionnel)
  const endTurn = useCallback(() => sendMove({ pass: true }), [sendMove]);

  // Board sizing is now pure CSS/SVG — the SVG fills its flex-1 container
  // with preserveAspectRatio="xMidYMid meet", no JavaScript measurement needed.

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: reload });

  // cancelled state handled by GameStateMessage below

  // Sound effects on board change
  const boardKey = useMemo(() => JSON.stringify(game?.state?.board || []), [game?.state?.board]);

  useEffect(() => {
    if (!boardKey || boardKey === "[]" || boardKey === lastBoardRef.current) return;
    const oldKey = lastBoardRef.current;
    lastBoardRef.current = boardKey;
    if (!oldKey || oldKey === "[]" || oldKey === "[]") return;

    // Compare boards to detect move
    try {
      const oldBoard = JSON.parse(oldKey) as number[];
      const newBoard = JSON.parse(boardKey) as number[];
      let fromIdx = -1, toIdx = -1;
      const captured: number[] = [];
      for (let i = 0; i < oldBoard.length; i++) {
        if (oldBoard[i] !== 0 && newBoard[i] === 0) {
          // Did this piece move elsewhere?
          let foundElsewhere = false;
          for (let j = 0; j < newBoard.length; j++) {
            if (oldBoard[j] === 0 && newBoard[j] === oldBoard[i] && j !== i) {
              fromIdx = i; toIdx = j; foundElsewhere = true;
            }
          }
          if (!foundElsewhere) captured.push(i);
        }
      }
      if (fromIdx >= 0 && toIdx >= 0) {
        // Recheck captured: also exclude fromIdx
        const realCaptured: number[] = [];
        for (let i = 0; i < oldBoard.length; i++) {
          if (oldBoard[i] !== 0 && newBoard[i] === 0 && i !== fromIdx) {
            realCaptured.push(i);
          }
        }
        setLastMove({ from: fromIdx, to: toIdx, captured: realCaptured });
        if (realCaptured.length > 0) {
          setAnimatingCapture(realCaptured);
          setTimeout(() => setAnimatingCapture([]), 600);
          playFanoronaCapture();
        } else {
          playFanoronaMove();
        }
      }
    } catch {}
  }, [boardKey]);

  // Win/lose sounds
  useEffect(() => {
    if (game?.status === "finished" && game?.winner_id) {
      const myPart = parts.find((p: any) => p.user_id === profile?.id);
      if (myPart && !myPart.forfeited) {
        if (game.winner_id === profile?.id) playFanoronaWin();
        else playFanoronaLose();
      }
    }
  }, [game?.status, game?.winner_id, profile?.id]);

  const COLS: number = (game?.cols as number) || 9;
  const ROWS: number = (game?.rows as number) || 5;
  const { idx, neighbors, legalTargets } = useMemo(() => makeHelpers(COLS, ROWS), [COLS, ROWS]);

  const me = parts.find((p: any) => p.user_id === profile?.id);
  const isPlayer = !!me;
  const myColor = me?.color === "white" ? 1 : me?.color === "black" ? 2 : 0;
  const isMyTurn = !!(game && me && game.current_turn === me.slot && game.status === "playing");
  const board: number[] = useMemo(
    () => (game?.state?.board as number[]) || Array(ROWS * COLS).fill(0),
    [game?.state?.board, ROWS, COLS]
  );
  const chainFrom: number | null = game?.state?.chain_from ?? null;
  const visited: number[] = useMemo(() => (game?.state?.visited as number[]) || [], [game?.state?.visited]);
  const lastAxis: string | null = game?.state?.last_axis ?? null;
  const mandatoryCapture: boolean = game?.mandatory_capture !== false;

  const cfg = useGameConfig("fanorona");
  const globalTimer = useGlobalGameTimer({
    game: "fanorona",
    gameId: id,
    status: game?.status,
    deadline: game?.game_deadline,
  });
  const flipped = me?.color === "black";

  /* -------- Cumulative clock tick (like chess) -------- */
  const [now, setNow] = useState(serverNow());
  useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 250);
    return () => clearInterval(t);
  }, []);

  const elapsedSinceMove = useMemo(() => {
    if (!game || game.status !== "playing") return 0;
    const base = new Date(game.last_move_at ?? game.started_at ?? new Date(serverNow()).toISOString()).getTime();
    return Math.max(0, now - base);
  }, [game, now]);

  const wTime = game ? Math.max(0, game.white_time_ms - (game.current_turn === 0 ? elapsedSinceMove : 0)) : 0;
  const bTime = game ? Math.max(0, game.black_time_ms - (game.current_turn === 1 ? elapsedSinceMove : 0)) : 0;

  /* -------- Flag fall timeout -------- */
  const timeoutFiredRef = useRef<string | null>(null);
  useEffect(() => {
    if (!game || game.status !== "playing") return;
    if (wTime > 0 && bTime > 0) return;
    const loserSlot = wTime <= 0 ? 0 : 1;
    const key = `${game.id}:${game.state?.move_count ?? 0}:${loserSlot}`;
    if (timeoutFiredRef.current === key) return;
    timeoutFiredRef.current = key;
    (async () => {
      await supabase.rpc("fanorona_tick" as any, { _game_id: id } as any);
      setTimeout(() => load(), 1200);
    })();
  }, [game, id, wTime, bTime, load]);


  // Valid move targets for selected piece
  const validTargets = useMemo(() => {
    if (!isMyTurn || (selected === null && chainFrom === null)) return new Map<number, { approach: number[]; withdrawal: number[] }>();
    const from = chainFrom !== null ? chainFrom : selected;
    if (from === null || board[from] !== myColor) return new Map();
    const targets = legalTargets(board, from, myColor, chainFrom, visited, lastAxis);
    const map = new Map<number, { approach: number[]; withdrawal: number[] }>();
    for (const t of targets) {
      // During a chain, continuation is mandatory-capture only (server enforces
      // "must capture during chain") — don't offer non-capturing continuations.
      if (chainFrom !== null && t.approach.length === 0 && t.withdrawal.length === 0) continue;
      map.set(t.to, { approach: t.approach, withdrawal: t.withdrawal });
    }
    return map;
  }, [isMyTurn, selected, chainFrom, board, myColor, visited, lastAxis, legalTargets]);

  // Can current player capture?
  const canCapture = useMemo(() => {
    if (!isMyTurn || !board || !myColor) return false;
    for (let i = 0; i < board.length; i++) {
      if (board[i] === myColor) {
        const targets = legalTargets(board, i, myColor, null, [], null);
        if (targets.some(t => t.approach.length > 0 || t.withdrawal.length > 0)) return true;
      }
    }
    return false;
  }, [isMyTurn, board, myColor, legalTargets]);

  const whiteCount = useMemo(() => countPieces(board, 1), [board]);
  const blackCount = useMemo(() => countPieces(board, 2), [board]);

  const sendMove = useCallback(async (move: any) => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc("fanorona_play" as any, { _game_id: id, _move: move } as any);
      if (error) throw error;
      setSelected(null); setCaptureChoice(null);
    } catch (e: any) { toast.error(e.message || "Coup invalide"); }
    finally { setBusy(false); }
  }, [id]);


  const onCellClick = useCallback((cell: number) => {
    if (!isMyTurn || busy) return;
    unlockAudio();
    if (captureChoice) {
      // A capture choice is pending — resolve it via the on-board arrows only.
      // Any board tap here just cancels back to piece selection.
      setCaptureChoice(null);
      return;
    }
    const effectiveSelected = chainFrom !== null ? chainFrom : selected;
    if (effectiveSelected === null) {
      if (board[cell] === myColor) setSelected(cell);
      return;
    }
    if (cell === effectiveSelected) { if (chainFrom === null) setSelected(null); return; }
    if (board[cell] === myColor && chainFrom === null) { setSelected(cell); return; }
    const targetInfo = validTargets.get(cell);
    if (!targetInfo) {
      if (chainFrom === null && board[cell] === 0) toast.error("Déplacement invalide");
      return;
    }
    const { approach, withdrawal } = targetInfo;
    if (approach.length > 0 && withdrawal.length > 0) {
      setCaptureChoice({ from: effectiveSelected, to: cell, approach, withdrawal });
      return;
    }
    const captured = approach.length > 0 ? approach : withdrawal;
    sendMove({ from: effectiveSelected, to: cell, captured, chain: false });
  }, [isMyTurn, busy, captureChoice, chainFrom, selected, board, myColor, validTargets, sendMove]);

  const confirm = useConfirm();
  const forfeit = useCallback(async () => {
    const stake = Number(game?.stake) || 0;
    if (game?.status !== "open") {
      const ok = await confirm({
        title: "Quitter la partie ?",
        description: stake > 0
          ? <>Si tu quittes, tu perdras automatiquement et ta mise sera définitivement perdue. <b>{stake.toLocaleString("fr-FR")} Ar</b>.</>
          : "Si tu quittes, tu perdras automatiquement la partie.",
        confirmLabel: "Confirmer quitter", destructive: true,
      });
      if (!ok) return;
    }
    await supabase.rpc("fanorona_forfeit" as any, { _game_id: id } as any);
    navigate({ to: "/jeux" });
  }, [game?.stake, game?.status, id, navigate, confirm]);

  // Bot play for solo mode.
  // IMPORTANT: a bot capture can chain (multiple sequential captures with the
  // same piece before the turn passes back). Each chain step is a *separate*
  // fanorona_bot_play call, and move_count only increments once the whole
  // chain ends — so we must key the "already triggered" guard on chain_from
  // (not just moveCount/current_turn), otherwise the bot gets stuck mid-chain
  // waiting for a re-trigger that never comes.
  const moveCount = game?.state?.move_count ?? 0;
  const botChainFrom = game?.state?.chain_from ?? null;
  // Use refs for parts/me so the effect doesn't re-fire (and clear its own timeout)
  // when setParts arrives in a different React tick than setGame.
  const partsRef = useRef(parts);
  partsRef.current = parts;
  useEffect(() => {
    if (!game || game.status !== "playing") return;
    const botPart = partsRef.current.find((p: any) => p.is_bot);
    if (!botPart) return;
    if (game.current_turn !== botPart.slot) return;
    const triggerKey = `${game.current_turn}:${moveCount}:${botChainFrom}`;
    if (botTriggeredRef.current === (triggerKey as any)) return;
    botTriggeredRef.current = triggerKey as any;
    const timer = setTimeout(async () => {
      try {
        const { error } = await supabase.rpc("fanorona_bot_play" as any, { _game_id: id } as any);
        if (error) console.error("fanorona_bot_play error", error);
      } catch (e) { console.error("bot play failed", e); }
    }, 800 + Math.random() * 700);
    return () => clearTimeout(timer);
  }, [game?.status, game?.current_turn, moveCount, botChainFrom, id]);

  // ── EARLY RETURNS AFTER ALL HOOKS ──
  if (!loaded) return <div className="p-6 text-center text-muted-foreground">Chargement…</div>;
  if (!game) return (
    <div className="p-6 text-center space-y-3">
      <div className="text-2xl">😕</div>
      <div className="font-bold">{loadError || "Partie introuvable"}</div>
      <button onClick={() => navigate({ to: "/jeux" })} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold">Retour aux jeux</button>
    </div>
  );

  const replayFanorona = async () => {
    const isSolo = parts.some((p: any) => p.is_bot);
    if (isSolo) {
      const { data, error } = await supabase.rpc("fanorona_create_solo" as any, {
        _stake: 0, _variant: game.variant || "tsivy",
        _mandatory_capture: game.mandatory_capture !== false, _bot_intelligence: 3,
      } as any);
      if (error) { toast.error(error.message); return; }
      navigate({ to: "/jeux/fanorona/$id", params: { id: data as string } });
    } else {
      const { data, error } = await supabase.rpc("fanorona_create" as any, {
        _stake: Number(game.stake) || 0, _private: !!game.is_private,
        _commission: Number(game.commission_pct) || 10, _variant: game.variant || "tsivy",
        _mandatory_capture: game.mandatory_capture !== false,
      } as any);
      if (error) { toast.error(error.message); return; }
      navigate({ to: "/jeux/fanorona/$id", params: { id: data as string } });
    }
  };

  if (game.status === "cancelled") {
    return <GameStateMessage state="cancelled" gameLabel="Fanorona" slug="fanorona" />;
  }

  if (game.status === "open") {
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="fanorona"
          gameLabel="Fanorona · 2 joueurs"
          parts={parts}
          maxPlayers={2}
          stake={Number(game.stake)}
          pot={Number(game.pot)}
          roomCode={game.room_code}
          meUserId={profile?.id}
          isParticipant={!!me}
          shareSlug="fanorona"
          createdAt={game.created_at}
          onQuit={async () => { await supabase.rpc("fanorona_forfeit" as any, { _game_id: id } as any); navigate({ to: "/jeux" }); }}
          onToggleReady={async (ready: boolean) => { await supabase.rpc("fanorona_set_ready" as any, { _game_id: id, _ready: ready } as any); }}
        />
      </main>
    );
  }

  const CELL_PX = 52;
  const SIZE_W = (COLS - 1) * CELL_PX;
  const SIZE_H = (ROWS - 1) * CELL_PX;
  const cx = (c: number) => c * CELL_PX;
  const cy = (r: number) => r * CELL_PX;

  // Geometry for the on-board capture-choice arrows (replaces the old modal).
  let captureGeom: null | {
    approachPos: { x: number; y: number }; withdrawalPos: { x: number; y: number };
    angleApproach: number; angleWithdrawal: number;
  } = null;
  if (captureChoice) {
    const fr = Math.floor(captureChoice.from / COLS), fc = captureChoice.from % COLS;
    const tr = Math.floor(captureChoice.to / COLS), tc = captureChoice.to % COLS;
    const ddr = tr - fr, ddc = tc - fc;
    const angleApproach = Math.atan2(ddr, ddc) * 180 / Math.PI;
    const angleWithdrawal = angleApproach + 180;
    const midOf = (cells: number[]) => {
      const pts = cells.map((i) => ({ x: cx(i % COLS), y: cy(Math.floor(i / COLS)) }));
      return { x: pts.reduce((s, p) => s + p.x, 0) / pts.length, y: pts.reduce((s, p) => s + p.y, 0) / pts.length };
    };
    const perpLen = Math.hypot(ddc, ddr) || 1;
    const ux = (-ddc / perpLen) * 20, uy = (ddr / perpLen) * 20;
    const approachMid = midOf(captureChoice.approach);
    const withdrawalMid = midOf(captureChoice.withdrawal);
    captureGeom = {
      approachPos: { x: approachMid.x + ux, y: approachMid.y + uy },
      withdrawalPos: { x: withdrawalMid.x + ux, y: withdrawalMid.y + uy },
      angleApproach, angleWithdrawal,
    };
  }

  return (
    <div className="h-full overflow-hidden flex flex-col bg-gradient-to-b from-stone-100 to-stone-200 dark:from-stone-900 dark:to-stone-950 overscroll-none">
      <PhoneVerifyBanner stake={Number(game?.stake) || 0} />
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />

      {/* ── Header compact (aligné sur le style Échecs) ── */}
      <div className="px-1.5 pt-0.5">
      <div className="rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5">
        <div className="flex items-baseline gap-1 min-w-0">
          <span className="text-[8px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
          <span className="text-xs font-extrabold truncate">{Math.round(Number(game.pot) * (100 - (Number(game.commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar</span>
        </div>
        {!me ? (
          <div className="px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1">
            Spectateur
          </div>
        ) : (
          <div className="flex items-center gap-1">
            {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
              <button
                onClick={async () => {
                  const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "fanorona", _game_id: id } as any);
                  if (error) toast.error(error.message);
                  else toast.success("Partie en pause");
                }}
                className="px-2 py-0.5 rounded-full bg-amber-500 text-white text-[10px] font-semibold flex items-center gap-0.5"
              >
                <Pause className="w-2.5 h-2.5" /> Pause
              </button>
            )}
            <button onClick={() => { const m = !soundOn; setSoundOn(m); setSfxMuted(m); }} className="w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition">
              {soundOn ? <Volume2 className="w-3 h-3" /> : <VolumeX className="w-3 h-3" />}
            </button>
            <button onClick={forfeit} className="px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5">
              <LogOut className="w-2.5 h-2.5" /> Quitter
            </button>
          </div>
        )}
      </div>
      </div>

      {/* ── Carte adversaire ── */}
      <div className="px-1.5 mt-0.5">
      {(() => {
        const opponent = parts.find((p: any) => p.user_id !== me?.user_id) ?? (me ? undefined : parts[0]);
        if (!opponent) return <FanoronaWaitingBar />;
        const isCurrent = game.current_turn === opponent.slot && game.status === "playing";
        const pieceCount = opponent.color === "white" ? whiteCount : blackCount;
        return (
          <FanoronaPlayerBar p={opponent} isCurrent={isCurrent} isMe={false} pieceCount={pieceCount} timeMs={me?.color === "white" ? bTime : wTime} avatarUrl={opponent.user_id ? profiles[opponent.user_id]?.avatar_url : null} />
        );
      })()}
      </div>

      {game.status === "finished" && (
        <GameEndScreen slug="fanorona" meUserId={profile?.id} winnerId={game.winner_id}
          participants={parts} stake={Number(game.stake)} pot={Number(game.pot)}
          commissionPct={Number(game.commission_pct) || 10} onReplay={replayFanorona} />
      )}

      {/* ── Board (plein écran) ── */}
      <div className="flex-1 flex flex-col min-h-0 w-full p-1 gap-1">
        <div className="flex-1 min-h-0 rounded-md overflow-hidden w-full flex items-center justify-center">
          <svg
            viewBox={rotated90
              ? `-18 -18 ${SIZE_H + 36} ${SIZE_W + 36}`
              : `-18 -18 ${SIZE_W + 36} ${SIZE_H + 36}`}
            preserveAspectRatio="xMidYMid meet"
            style={{ width: "100%", height: "100%" }}
          >
            <g transform={rotated90
              // Rotate the board about its OWN center (pivot stays fixed at
              // SIZE_W/2, SIZE_H/2), then translate that fixed center over
              // to the rotated viewBox's center (SIZE_H/2, SIZE_W/2) — this
              // is the only translation that re-centers correctly for any
              // rotation angle (previous formula was mathematically wrong
              // and pushed the board mostly out of the visible viewBox).
              ? `translate(${SIZE_H / 2 - SIZE_W / 2} ${SIZE_W / 2 - SIZE_H / 2}) rotate(${flipped ? 270 : 90} ${SIZE_W / 2} ${SIZE_H / 2})`
              : (flipped ? `rotate(180 ${SIZE_W / 2} ${SIZE_H / 2})` : undefined)}>
            <defs>
              <radialGradient id="wood-inner" cx="50%" cy="35%" r="80%">
                <stop offset="0%" stopColor="#d9a86a" /><stop offset="60%" stopColor="#a06b35" /><stop offset="100%" stopColor="#5e3618" />
              </radialGradient>
              <radialGradient id="white-stone" cx="35%" cy="30%" r="70%">
                <stop offset="0%" stopColor="#ffffff" /><stop offset="55%" stopColor="#ece4d2" /><stop offset="100%" stopColor="#8b806a" />
              </radialGradient>
              <radialGradient id="black-stone" cx="35%" cy="30%" r="70%">
                <stop offset="0%" stopColor="#5a5a5a" /><stop offset="50%" stopColor="#1d1d1d" /><stop offset="100%" stopColor="#000000" />
              </radialGradient>
              <filter id="stone-shadow" x="-50%" y="-50%" width="200%" height="200%">
                <feDropShadow dx="0" dy="2" stdDeviation="1.6" floodColor="#000" floodOpacity="0.55" />
              </filter>
              <filter id="capture-glow" x="-50%" y="-50%" width="200%" height="200%">
                <feGaussianBlur stdDeviation="3" result="blur" /><feMerge><feMergeNode in="blur" /><feMergeNode in="SourceGraphic" /></feMerge>
              </filter>
            </defs>
            <rect x={-16} y={-16} width={SIZE_W + 32} height={SIZE_H + 32} rx={8} fill="url(#wood-inner)" />
            {Array.from({ length: ROWS }).map((_, r) => Array.from({ length: COLS }).map((_, c) => {
              const here = idx(r, c);
              return neighbors(r, c).map(([dr, dc]) => {
                const r2 = r + dr, c2 = c + dc;
                if (r2 * COLS + c2 < here) return null;
                return (
                  <g key={`${r}-${c}-${dr}-${dc}`}>
                    <line x1={cx(c)} y1={cy(r) + 1} x2={cx(c2)} y2={cy(r2) + 1} stroke="rgba(0,0,0,0.55)" strokeWidth={1.6} strokeLinecap="round" />
                    <line x1={cx(c)} y1={cy(r)} x2={cx(c2)} y2={cy(r2)} stroke="rgba(255,225,180,0.85)" strokeWidth={1} strokeLinecap="round" />
                  </g>
                );
              });
            }))}
            {board.map((_, i) => {
              const r = Math.floor(i / COLS), c = i % COLS;
              return <circle key={`s-${i}`} cx={cx(c)} cy={cy(r)} r={4} fill="rgba(0,0,0,0.35)" />;
            })}
            {lastMove && (
              <>
                <circle cx={cx(lastMove.from % COLS)} cy={cy(Math.floor(lastMove.from / COLS))} r={16} fill="rgba(255,235,59,0.25)" />
                <circle cx={cx(lastMove.to % COLS)} cy={cy(Math.floor(lastMove.to / COLS))} r={16} fill="rgba(255,235,59,0.35)" />
              </>
            )}
            {isMyTurn && !captureChoice && validTargets.size > 0 && Array.from(validTargets.entries()).map(([to, info]) => {
              const r = Math.floor(to / COLS), c = to % COLS;
              const hasCapture = info.approach.length > 0 || info.withdrawal.length > 0;
              return (
                <g key={`target-${to}`}>
                  {hasCapture ? (
                    <circle cx={cx(c)} cy={cy(r)} r={16} fill="none" stroke="#ef4444" strokeWidth={2} opacity={0.7} strokeDasharray="4 2">
                      <animate attributeName="r" values="14;18;14" dur="1s" repeatCount="indefinite" />
                    </circle>
                  ) : (
                    <circle cx={cx(c)} cy={cy(r)} r={6} fill="rgba(34,197,94,0.4)" />
                  )}
                </g>
              );
            })}
            {board.map((v, i) => {
              const r = Math.floor(i / COLS), c = i % COLS;
              const isSel = selected === i || chainFrom === i;
              const isCaptured = animatingCapture.includes(i);
              if (v === 0) {
                return (
                  <circle key={i} cx={cx(c)} cy={cy(r)} r={14} fill="transparent"
                    onClick={() => onCellClick(i)}
                    style={{ cursor: isMyTurn && (selected !== null || chainFrom !== null) ? "pointer" : "default" }} />
                );
              }
              return (
                <g key={i} onClick={() => onCellClick(i)}
                   style={{ cursor: isMyTurn && (v === myColor || selected !== null || chainFrom !== null) ? "pointer" : "default", opacity: isCaptured ? 0.3 : 1, transition: "opacity 0.4s ease-out" }}>
                  {isSel && (
                    <circle cx={cx(c)} cy={cy(r)} r={16} fill="none" stroke="#22c55e" strokeWidth={2.5} opacity={0.9}>
                      <animate attributeName="r" values="14;18;14" dur="1s" repeatCount="indefinite" />
                    </circle>
                  )}
                  <ellipse cx={cx(c)} cy={cy(r) + 2} rx={11} ry={3.5} fill="rgba(0,0,0,0.45)" />
                  <circle cx={cx(c)} cy={cy(r)} r={11.5} fill={v === 1 ? "url(#white-stone)" : "url(#black-stone)"} filter={isCaptured ? "url(#capture-glow)" : "url(#stone-shadow)"} />
                  <ellipse cx={cx(c) - 3.5} cy={cy(r) - 4} rx={3.5} ry={2} fill={v === 1 ? "rgba(255,255,255,0.85)" : "rgba(255,255,255,0.3)"} />
                </g>
              );
            })}
            {captureChoice && (
              <g>
                {/* Pending destination */}
                <circle cx={cx(captureChoice.to % COLS)} cy={cy(Math.floor(captureChoice.to / COLS))} r={13} fill="none" stroke="#fbbf24" strokeWidth={2} opacity={0.85} strokeDasharray="3 2" />
                {/* Approach group highlight (orange) */}
                {captureChoice.approach.map((i) => (
                  <circle key={`appr-${i}`} cx={cx(i % COLS)} cy={cy(Math.floor(i / COLS))} r={15} fill="rgba(249,115,22,0.18)" stroke="#f97316" strokeWidth={3} opacity={0.95}>
                    <animate attributeName="r" values="13;17;13" dur="0.9s" repeatCount="indefinite" />
                  </circle>
                ))}
                {/* Withdrawal group highlight (blue) */}
                {captureChoice.withdrawal.map((i) => (
                  <circle key={`wd-${i}`} cx={cx(i % COLS)} cy={cy(Math.floor(i / COLS))} r={15} fill="rgba(56,189,248,0.18)" stroke="#38bdf8" strokeWidth={3} opacity={0.95}>
                    <animate attributeName="r" values="13;17;13" dur="0.9s" repeatCount="indefinite" />
                  </circle>
                ))}
                {/* Small clickable arrows to confirm which capture to take */}
                {captureGeom && (
                  <g onClick={() => sendMove({ from: captureChoice.from, to: captureChoice.to, captured: captureChoice.approach, chain: false })} style={{ cursor: "pointer" }}>
                    <circle cx={captureGeom.approachPos.x} cy={captureGeom.approachPos.y} r={13} fill="#f97316" stroke="#fff" strokeWidth={1.5} />
                    <path d="M -4,-4.5 L 5.5,0 L -4,4.5 Z" fill="#fff" transform={`translate(${captureGeom.approachPos.x},${captureGeom.approachPos.y}) rotate(${captureGeom.angleApproach})`} />
                  </g>
                )}
                {captureGeom && (
                  <g onClick={() => sendMove({ from: captureChoice.from, to: captureChoice.to, captured: captureChoice.withdrawal, chain: false })} style={{ cursor: "pointer" }}>
                    <circle cx={captureGeom.withdrawalPos.x} cy={captureGeom.withdrawalPos.y} r={13} fill="#38bdf8" stroke="#fff" strokeWidth={1.5} />
                    <path d="M -4,-4.5 L 5.5,0 L -4,4.5 Z" fill="#fff" transform={`translate(${captureGeom.withdrawalPos.x},${captureGeom.withdrawalPos.y}) rotate(${captureGeom.angleWithdrawal})`} />
                  </g>
                )}
              </g>
            )}
            </g>
          </svg>
        </div>
        {isMyTurn && chainFrom !== null && (
          <button onClick={endTurn}
            className="shrink-0 w-full py-1.5 rounded-full font-bold text-xs shadow-lg flex items-center justify-center gap-1.5 transition-all active:scale-95 bg-amber-100 text-amber-950 hover:bg-amber-200">
            <SkipForward className="w-3.5 h-3.5" />
            Arrêter la rafale
          </button>
        )}
      </div>

      {/* ── Carte "vous" ── */}
      <div className="px-1.5 pb-0.5">
      {me && (() => {
        const isCurrent = game.current_turn === me.slot && game.status === "playing";
        const pieceCount = me.color === "white" ? whiteCount : blackCount;
        return (
          <FanoronaPlayerBar p={me} isCurrent={isCurrent} isMe pieceCount={pieceCount} timeMs={me?.color === "white" ? wTime : bTime} avatarUrl={me.user_id ? profiles[me.user_id]?.avatar_url : null} />
        );
      })()}
      </div>

      {/* Global game timer banner */}
      {game?.status === "playing" && globalTimer.enabled && globalTimer.remainingMs !== null && (
        <div className={`px-3 py-1 mx-2 rounded-lg text-center text-xs font-bold ${
          globalTimer.remainingMs <= 30000
            ? "bg-destructive/15 text-destructive animate-pulse"
            : "bg-amber-500/10 text-amber-600 dark:text-amber-400"
        }`}>
          ⏳ Temps global restant : {globalTimer.remainingLabel}
        </div>
      )}

      <GamePauseControl slug="fanorona" gameId={id} game={game} remaining={Math.ceil((me?.color === "white" ? wTime : bTime) / 1000)} totalSeconds={cfg.turn_timer_seconds}
        isMyTurn={!!isMyTurn} isPlayer={isPlayer} myUserId={profile?.id ?? null} />
      <GameSocialFab gameId={id} gameSlug="fanorona" participants={parts} />
    </div>
  );
}
