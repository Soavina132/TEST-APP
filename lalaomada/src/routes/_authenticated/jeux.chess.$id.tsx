import { UUID_RE } from "@/lib/game-constants";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Chess } from "chess.js";
import { GameLoader } from "@/components/game/GameLoader";
import { supabase } from "@/integrations/supabase/client";
import SpectatorLeaveButton from "@/components/game/SpectatorLeaveButton";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { ArrowLeft, Flag, Handshake, Copy, RotateCw, LogOut, Plus, Pause, Volume2, VolumeX, Scale, ShieldAlert } from "lucide-react";
import { copyText } from "@/lib/clipboard";
import GameSocialFab from "@/components/game/GameSocialFab";
import { Button } from "@/components/ui/button";
import { ChessBoard } from "@/components/chess/ChessBoard";
import { PlayerBar } from "@/components/chess/PlayerBar";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import { useConfirm } from "@/components/ConfirmDialog";
import { serverNow } from "@/lib/server-time";
import { useGlobalGameTimer } from "@/hooks/game/use-global-game-timer";
import GamePauseControl from "@/components/game/GamePauseControl";
import { playChessMove, playChessCapture, playChessCastle, playChessCheck, playChessEnd, unlockAudio } from "@/lib/sounds/game-sounds";
import { setMuted as setSfxMuted, isMuted as isSfxMuted } from "@/lib/game-sounds";
import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";

/* -------- Server-side move validation via Edge Function -------- */
async function chessServerPlay(supabase: any, action: string, params: Record<string, unknown>) {
  const { data: session } = await supabase.auth.getSession();
  const token = session?.session?.access_token;
  if (!token) throw new Error("Non authentifié");
  const supabaseUrl = (import.meta as any).env?.VITE_SUPABASE_URL || "";
  const res = await fetch(`${supabaseUrl}/functions/v1/chess-validate-move`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${token}`,
    },
    body: JSON.stringify({ action, ...params }),
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : {};
  if (!res.ok || data.error) {
    throw new Error(data.error || `Erreur serveur (HTTP ${res.status})`);
  }
  return data;
}

export const Route = createFileRoute("/_authenticated/jeux/chess/$id")({
  component: ChessPage,
  head: () => ({ meta: [{ title: "Échecs — Lalao MADA" }] }),
});

type Game = {
  id: string; host_id: string;
  white_id: string | null; black_id: string | null;
  status: string; mode: string;
  fen: string; turn: string; ply: number;
  winner_id: string | null; draw: boolean; end_reason: string | null;
  stake: number; pot: number;
  is_private: boolean; room_code: string | null;
  white_is_bot: boolean; black_is_bot: boolean;
  bot_intelligence: number | null; bot_name: string | null;
  time_control_min: number;
  white_time_ms: number; black_time_ms: number;
  last_move_at: string | null; started_at: string | null; finished_at: string | null;
  draw_offered_by: string | null;
  turn_deadline: string | null;
  game_deadline: string | null;
  paused: boolean;
  pause_deadline: string | null;
  paused_turn_remaining_s: number | null;
  pause_used_deadline: string | null;
  paused_turn_holder_id: string | null;
  afk_warning: any;
  afk_pause_for: string | null;
  afk_pause_name: string | null;
  ready_white: boolean;
  ready_black: boolean;
  commission_pct: number;
  created_at: string;
};

type Profile = { id: string; pseudo: string | null; avatar_url: string | null };


const PIECE_VAL: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

/* ------------------------ Bot AI (client) ------------------------ */
function evaluate(chess: Chess): number {
  let s = 0;
  for (const row of chess.board()) for (const c of row) if (c) {
    const v = PIECE_VAL[c.type] ?? 0;
    s += c.color === "w" ? v : -v;
  }
  return s;
}

function evalDepth(chess: any, depth: number, isMax: boolean, alpha: number, beta: number): number {
  if (depth === 0 || chess.isGameOver()) {
    if (chess.isCheckmate()) return isMax ? -9999 : 9999;
    if (chess.isDraw()) return 0;
    return evaluate(chess);
  }
  const moves = chess.moves({ verbose: true }) as any[];
  if (isMax) {
    let best = -Infinity;
    for (const m of moves) {
      const c = new (chess.constructor)(chess.fen()); c.move(m);
      const s = evalDepth(c, depth - 1, false, alpha, beta);
      best = Math.max(best, s); alpha = Math.max(alpha, s);
      if (beta <= alpha) break;
    }
    return best;
  } else {
    let best = Infinity;
    for (const m of moves) {
      const c = new (chess.constructor)(chess.fen()); c.move(m);
      const s = evalDepth(c, depth - 1, true, alpha, beta);
      best = Math.min(best, s); beta = Math.min(beta, s);
      if (beta <= alpha) break;
    }
    return best;
  }
}

function pickBotMove(fen: string, level: number): { uci: string; san: string; fenAfter: string } | null {
  const chess = new Chess(fen);
  const moves = chess.moves({ verbose: true }) as any[];
  if (moves.length === 0) return null;
  const botIsWhite = chess.turn() === "w";

  let chosen: any = moves[0];

  if (level <= 1) {
    chosen = moves[Math.floor(Math.random() * moves.length)];
  } else if (level === 2) {
    if (Math.random() < 0.4) {
      chosen = moves[Math.floor(Math.random() * moves.length)];
    } else {
      const captures = moves.filter((m) => m.captured);
      if (captures.length) {
        captures.sort((a, b) => (PIECE_VAL[b.captured] ?? 0) - (PIECE_VAL[a.captured] ?? 0));
        chosen = captures[0];
      } else {
        chosen = moves[Math.floor(Math.random() * moves.length)];
      }
    }
  } else if (level === 3) {
    const scored = moves.map((m) => {
      let s = 0;
      if (m.captured) s += (PIECE_VAL[m.captured] ?? 0) * 10;
      if (m.san?.includes("+")) s += 3;
      if (m.san?.includes("#")) s += 1000;
      if (m.promotion) s += 8;
      // Vérifier si la pièce sera recapturée
      const after = new Chess(chess.fen());
      after.move(m);
      const oppMoves = after.moves({ verbose: true }) as any[];
      const myPieceVal = PIECE_VAL[m.piece] ?? 0;
      const willBeRecaptured = oppMoves.some((om: any) => om.to === m.to && om.captured === m.piece);
      if (willBeRecaptured) s -= myPieceVal * 10;
      s += Math.random() * 0.5;
      return { m, s };
    });
    scored.sort((a, b) => b.s - a.s);
    chosen = scored[0].m;
  } else if (level === 4) {
    const scored = moves.map((m) => {
      const c = new Chess(chess.fen()); c.move(m);
      const s = evalDepth(c, 1, botIsWhite ? false : true, -Infinity, Infinity);
      return { m, s: botIsWhite ? s : -s };
    });
    scored.sort((a, b) => b.s - a.s);
    const best = scored[0].s;
    const top = scored.filter((x) => x.s === best);
    chosen = top[Math.floor(Math.random() * top.length)].m;
  } else {
    const scored = moves.map((m) => {
      const c = new Chess(chess.fen()); c.move(m);
      const s = evalDepth(c, 2, botIsWhite ? false : true, -Infinity, Infinity);
      return { m, s: botIsWhite ? s : -s };
    });
    scored.sort((a, b) => b.s - a.s);
    const best = scored[0].s;
    const top = scored.filter((x) => Math.abs(x.s - best) < 5);
    chosen = top[Math.floor(Math.random() * top.length)].m;
  }

  const test = new Chess(chess.fen());
  const played = test.move(chosen);
  if (!played) return null;
  const uci = played.from + played.to + (played.promotion ?? "");
  return { uci, san: played.san, fenAfter: test.fen() };
}

/* ------------------------ Page ------------------------ */
function ChessPage() {
  const { id } = Route.useParams();
  const { profile, isAdmin, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const confirm = useConfirm();
  const [game, setGame] = useState<Game | null>(null);
  const [gameNumber, setGameNumber] = useState<string | null>(null);
  const [profiles, setProfiles] = useState<Record<string, Profile>>({});
  const [lastMove, setLastMove] = useState<{ from: string; to: string } | null>(null);
  const [moveHistory, setMoveHistory] = useState<{ san: string; ply: number }[]>([]);
  const [now, setNow] = useState(serverNow());
  const [busy, setBusy] = useState(false);
  const [showEnd, setShowEnd] = useState(false);
  const [botThinking, setBotThinking] = useState(false);
  const [canClaimDraw, setCanClaimDraw] = useState(false);
  const botTriggeredRef = useRef<number>(-1);
  const endTriggeredRef = useRef<number>(-1);
  const lastSoundPly = useRef<number>(-1);
  const isValidGameId = UUID_RE.test(id);

  const handleQuitGame = useCallback(async () => {
    const stake = Number(game?.stake) || 0;
    const ok = await confirm({
      title: "Quitter la partie ?",
      description: stake > 0
        ? <>Si tu quittes, tu perdras automatiquement et ta mise sera définitivement perdue. <b>{stake.toLocaleString("fr-FR")} Ar</b>.</>
        : "Si tu quittes, tu perdras automatiquement la partie.",
      confirmLabel: "Confirmer quitter",
      destructive: true,
    });
    if (!ok) return;
    try {
      if (game?.id) {
        const { error } = await supabase.rpc("chess_resign" as any, { _game_id: game.id } as any);
        if (error) {
          // Si la partie est déjà terminée, on navigue quand même
          if (!error.message.includes('not found') && !error.message.includes('status')) {
            toast.error(error.message);
          }
        }
      }
    } catch (e: any) {
      console.warn("chess_resign error:", e?.message);
    } finally {
      navigate({ to: "/jeux" });
    }
  }, [game, confirm, navigate]);

  /* -------- Load game -------- */
  const load = useCallback(async () => {
    if (!isValidGameId) return;
    const { data, error } = await supabase.from("chess_games").select("*").eq("id", id).maybeSingle();
    if (error) { toast.error(error.message); return; }
    if (!data) return;
    setGame(data as any);
    // Load profiles
    const ids = [data.white_id, data.black_id].filter(Boolean) as string[];
    if (ids.length) {
      const { data: pr } = await supabase.from("profiles").select("id,pseudo,avatar_url").in("id", ids);
      const map: Record<string, Profile> = {};
      (pr ?? []).forEach((p: any) => { map[p.id] = p; });
      setProfiles(map);
    }
    // Last move + history
    const { data: moves } = await supabase.from("chess_moves").select("uci,san,ply").eq("game_id", id).order("ply", { ascending: true });
    if (moves && moves.length) {
      const last = moves[moves.length - 1];
      if (last?.uci) setLastMove({ from: last.uci.slice(0, 2), to: last.uci.slice(2, 4) });
      setMoveHistory(moves.map((m: any) => ({ san: m.san, ply: m.ply })));
    }
  }, [id, isValidGameId, profile?.id]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });

  // Auto-timeout: settle les parties où le temps a expiré (même si l'utilisateur était absent)

  // Fetch game number from game_registrations
  useEffect(() => {
    if (!id) return;
    supabase.from("game_registrations")
      .select("game_number")
      .eq("game_id", id)
      .maybeSingle()
      .then(({ data }: any) => {
        if (data?.game_number) {
          setGameNumber('#' + String(data.game_number).padStart(8, '0'));
        }
      });
  }, [id]);

  useEffect(() => {
    if (!isValidGameId) return;
    void supabase.rpc("chess_auto_timeout" as any, { _game_id: id } as any).then(() => load());
  }, [id, isValidGameId]);

  useEffect(() => { void load(); }, [load]);

  /* -------- Realtime -------- */
  useEffect(() => {
    if (!isValidGameId) return;
    let debounceTimer: ReturnType<typeof setTimeout> | null = null;
  const debouncedLoad = () => {
    if (debounceTimer) clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => { void load(); }, 300);
  };
  let heartbeat: ReturnType<typeof setInterval> | null = null;
  const ch = supabase.channel(`chess-${id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "chess_games", filter: `id=eq.${id}` }, (payload: any) => {
        if (payload.new) {
          setGame(payload.new as any);
          if (payload.new.status === "finished") { void load(); }
        } else { debouncedLoad(); }
      })
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chess_moves", filter: `game_id=eq.${id}` }, (p) => {
        const u = (p.new as any).uci as string;
        if (u) setLastMove({ from: u.slice(0, 2), to: u.slice(2, 4) });
        if (p.new) {
          setMoveHistory(prev => {
            const newMove = { san: (p.new as any).san, ply: (p.new as any).ply };
            if (prev.some(m => m.ply === newMove.ply)) return prev;
            return [...prev, newMove];
          });
        }
      })
      .subscribe((status: string) => {
        if (status === "SUBSCRIBED") {
          if (heartbeat) clearInterval(heartbeat);
          heartbeat = setInterval(() => load(), 10_000);
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          if (heartbeat) { clearInterval(heartbeat); heartbeat = null; }
          setTimeout(() => load(), 300);
        }
      });
    return () => { supabase.removeChannel(ch); if (heartbeat) clearInterval(heartbeat); };
  }, [id, isValidGameId, load]);

  /* -------- Timer tick (UI) -------- */
  useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 250);
    return () => clearInterval(t);
  }, []);

  /* -------- Play sound on new move -------- */
  useEffect(() => {
    if (!game || game.ply === lastSoundPly.current) return;
    if (game.ply === 0) { lastSoundPly.current = 0; return; }
    if (lastSoundPly.current >= 0 && game.ply > lastSoundPly.current) {
      const chess = new Chess(game.fen);
      const lastSan = moveHistory[moveHistory.length - 1]?.san || "";
      if (chess.isCheckmate()) playChessCheck();
      else if (chess.inCheck()) playChessCheck();
      else if (lastSan.includes("O-O")) playChessCastle();
      else if (lastSan.includes("x")) playChessCapture();
      else playChessMove();
      if (chess.isGameOver()) playChessEnd();
    }
    lastSoundPly.current = game.ply;
  }, [game?.ply, game?.fen, moveHistory]);

  const myColor: "w" | "b" | null = useMemo(() => {
    if (!game || !profile) return null;
    if (game.white_id === profile.id) return "w";
    if (game.black_id === profile.id) return "b";
    return null;
  }, [game, profile]);

  const isActive = game?.status === "playing";

  /* -------- Check if draw is claimable (50-move or threefold) -------- */
  useEffect(() => {
    if (!game || game.status !== "playing" || !myColor) {
      setCanClaimDraw(false);
      return;
    }
    let cancelled = false;
    (async () => {
      try {
        const result = await chessServerPlay(supabase, "can_claim_draw", { game_id: game.id });
        if (!cancelled) setCanClaimDraw(!!result.can_claim);
      } catch {
        if (!cancelled) setCanClaimDraw(false);
      }
    })();
    return () => { cancelled = true; };
  }, [game?.id, game?.ply, game?.fen, game?.status, myColor]);

  /* -------- Global game timer (chess) -------- */
  const globalTimer = useGlobalGameTimer({
    game: "chess",
    gameId: id,
    status: game?.status,
    deadline: game?.game_deadline,
  });

  const isPlayer = !!(profile?.id && game && (game.white_id === profile.id || game.black_id === profile.id));

  /* -------- Time computation -------- */
  const elapsedSinceMove = useMemo(() => {
    if (!game || !isActive || game.paused) return 0;
    const base = new Date(game.last_move_at ?? game.started_at ?? new Date(serverNow()).toISOString()).getTime();
    return Math.max(0, now - base);
  }, [game, isActive, now]);

  const wTime = game ? Math.max(0, game.white_time_ms - (game.turn === "w" ? elapsedSinceMove : 0)) : 0;
  const bTime = game ? Math.max(0, game.black_time_ms - (game.turn === "b" ? elapsedSinceMove : 0)) : 0;

  /* Captured pieces + material diff — computed unconditionally (Rules of Hooks) */
  const { capturedByWhite, capturedByBlack, materialDiff } = useMemo(() => {
    const startCount: Record<string, number> = { p: 8, n: 2, b: 2, r: 2, q: 1 };
    const cur: Record<string, { w: number; b: number }> = {};
    if (game) {
      try {
        for (const row of new Chess(game.fen).board()) for (const c of row) if (c) {
          cur[c.type] ??= { w: 0, b: 0 }; cur[c.type][c.color]++;
        }
      } catch {}
    }
    const cw: string[] = [];
    const cb: string[] = [];
    let wMat = 0, bMat = 0;
    for (const t of Object.keys(startCount)) {
      const w = cur[t]?.w ?? 0;
      const b = cur[t]?.b ?? 0;
      for (let i = 0; i < startCount[t] - b; i++) cw.push(t);
      for (let i = 0; i < startCount[t] - w; i++) cb.push(t);
      wMat += (startCount[t] - b) * (PIECE_VAL[t] ?? 0);
      bMat += (startCount[t] - w) * (PIECE_VAL[t] ?? 0);
    }
    return { capturedByWhite: cw, capturedByBlack: cb, materialDiff: wMat - bMat };
  }, [game?.fen]);

  const gameChess = useMemo(() => {
    try { return new Chess(game?.fen ?? undefined); } catch { return new Chess(); }
  }, [game?.fen]);

  /* -------- Play a move (server-authoritative) -------- */
  const play = useCallback(async (uci: string, san: string, fenAfter: string) => {
    if (!game) return;
    unlockAudio();

    // ── Play sound immediately based on SAN ──
    const isCapture = san.includes("x");
    const isCastle = san === "O-O" || san === "O-O-O";
    const isCheck = san.includes("+") || san.includes("#");
    if (isCastle) playChessCastle();
    else if (isCapture) playChessCapture();
    else playChessMove();
    if (isCheck) setTimeout(() => playChessCheck(), 150);

    // ── Send to server and let load/realtime update the board ──
    try {
      await chessServerPlay(supabase, "play", {
        game_id: game.id, uci, elapsed_ms: elapsedSinceMove, is_bot: false,
      });
      setLastMove({ from: uci.slice(0, 2), to: uci.slice(2, 4) });
      void load(); // Reconcile with server (FEN should match)
    } catch (e: any) {
      console.error("chess_play error", e);
      toast.error(e.message ?? "Coup invalide");
    }
  }, [game, elapsedSinceMove, load]);

  /* -------- Bot autoplay -------- */
  useEffect(() => {
    if (!game || !isActive || game.mode !== "solo" || !myColor) return;
    const botIsWhite = game.white_is_bot;
    const botColor = botIsWhite ? "w" : "b";
    if (game.turn !== botColor) return;
    if (botTriggeredRef.current === game.ply) return;

    const plyAtSchedule = game.ply;
    const level = game.bot_intelligence ?? 2;

    // Patch FEN for 50-move rule (chess.js blocks moves when halfmove >= 100)
    const _botFenParts = game.fen.split(" ");
    if (_botFenParts.length >= 5 && (parseInt(_botFenParts[4], 10) || 0) >= 100) _botFenParts[4] = "99";
    const _botFen = _botFenParts.join(" ");
    const preChess = new Chess(_botFen);
    const preMove = preChess.isGameOver() ? null : pickBotMove(_botFen, level);
    const legalCount = preChess.isGameOver() ? 0 : preChess.moves().length;
    let complexity = 0;
    if (preMove) {
      complexity += Math.min(1, legalCount / 35);
      const san = preMove.san ?? "";
      if (san.includes("x")) complexity += 0.25;
      if (san.includes("+")) complexity += 0.2;
      if (san.includes("#")) complexity += 0.35;
      if (san.includes("=")) complexity += 0.25;
      if (san === "O-O" || san === "O-O-O") complexity += 0.15;
      complexity += (level - 1) * 0.1;
    }
    complexity = Math.max(0, Math.min(1, complexity));
    const jitter = (Math.random() - 0.5) * 200;
    const delay = Math.max(800, Math.min(2500, 1000 + complexity * 1500 + jitter));

    setBotThinking(true);
    const timer = setTimeout(async () => {
      if (botTriggeredRef.current === plyAtSchedule) { setBotThinking(false); return; }
      botTriggeredRef.current = plyAtSchedule;
      const chess = new Chess(_botFen);
      if (chess.isGameOver()) { setBotThinking(false); return; }
      const mv = preMove ?? pickBotMove(_botFen, level);
      if (!mv) { setBotThinking(false); return; }
      const gameElapsed = Math.max(0, serverNow() - new Date(game.last_move_at ?? game.started_at ?? new Date(serverNow()).toISOString()).getTime());
      try {
        await chessServerPlay(supabase, "play", {
          game_id: game.id, uci: mv.uci, elapsed_ms: gameElapsed, is_bot: true,
        });
        void load();
      } catch (e: any) {
        console.error("bot_play error", e);
        botTriggeredRef.current = -1;
        toast.error(e.message ?? "Erreur bot");
      }
      setBotThinking(false);
    }, delay);
    return () => { clearTimeout(timer); setBotThinking(false); };
  }, [game, isActive, myColor, load]);

  /* -------- End detection -------- */
  // Only detect AUTOMATIC ends (checkmate, stalemate, insufficient material, 75-move, 5x repetition)
  // Claimable draws (50-move, threefold) are NOT auto-settled here — the server handles them
  useEffect(() => {
    if (!game || !isActive) return;
    if (endTriggeredRef.current === game.ply) return;
    // Patch FEN for 50-move rule (chess.js blocks moves when halfmove >= 100)
    const fenParts = game.fen.split(" ");
    const halfmove = fenParts.length >= 5 ? (parseInt(fenParts[4], 10) || 0) : 0;
    if (halfmove >= 100) fenParts[4] = "99";
    const patchedFen = fenParts.join(" ");
    const chess = new Chess(patchedFen);
    // Only check automatic ends (not threefold/50-move which are claimable)
    const isAutoEnd = chess.isCheckmate() || chess.isStalemate() || chess.isInsufficientMaterial() || halfmove >= 150;
    if (!isAutoEnd) return;
    endTriggeredRef.current = game.ply;
    let winner: string | null = null;
    let draw = false;
    let reason = "";
    if (chess.isCheckmate()) {
      winner = chess.turn() === "w" ? game.black_id : game.white_id;
      reason = "checkmate";
    } else if (chess.isStalemate()) { draw = true; reason = "stalemate"; }
    else if (chess.isInsufficientMaterial()) { draw = true; reason = "insufficient"; }
    else if (halfmove >= 150) { draw = true; reason = "draw_75"; }
    if (!winner && !draw) return;
    (async () => {
      try {
        await chessServerPlay(supabase, "finish", {
          game_id: game.id, winner, draw, reason,
        });
        void load();
      } catch (e) {
        console.error("chess_finish error", e);
        endTriggeredRef.current = -1;
      }
    })();
  }, [game, isActive, load]);

  /* -------- Timeout to server -------- */
  const timeoutFiredRef = useRef<string | null>(null);
  const timeoutRetryRef = useRef(0);
  useEffect(() => {
    if (!game || !isActive) return;
    if (wTime > 0 && bTime > 0) return;
    const loserColor = wTime <= 0 ? "w" : "b";
    const key = `${game.id}:${game.ply}:${loserColor}`;
    if (timeoutFiredRef.current === key && timeoutRetryRef.current >= 5) return;
    if (timeoutFiredRef.current !== key) {
      timeoutFiredRef.current = key;
      timeoutRetryRef.current = 0;
    }
    (async () => {
      await supabase.rpc("chess_tick" as any, { _game_id: game.id } as any);
      timeoutRetryRef.current++;
      setTimeout(async () => {
        const { data } = await supabase
          .from("chess_games" as any)
          .select("status")
          .eq("id", game.id)
          .maybeSingle();
        if ((data as any)?.status === "playing") {
          // Don't send winner — let the server check if opponent has mating material
          try {
            await chessServerPlay(supabase, "finish", {
              game_id: game.id, reason: "timeout",
            });
          } catch (e) {
            console.error("chess_finish timeout error", e);
          }
          void load();
        }
      }, 1200);
    })();
  }, [game, isActive, wTime, bTime, load, now]);

  /* -------- Show end dialog -------- */
  useEffect(() => {
    if (game?.status === "finished") setShowEnd(true);
  }, [game?.status]);

  /* -------- Actions -------- */
  const doResign = async () => {
    if (!game) return;
    const ok = await confirm({
      title: "Abandonner la partie ?",
      description: "Vous perdrez automatiquement.",
      confirmLabel: "Abandonner",
      destructive: true,
    });
    if (!ok) return;
    setBusy(true);
    try { await supabase.rpc("chess_resign" as any, { _game_id: game.id } as any); }
    catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };
  const doOfferDraw = async () => {
    if (!game) return;
    setBusy(true);
    try {
      if (game.draw_offered_by && game.draw_offered_by !== profile?.id) {
        await supabase.rpc("chess_accept_draw" as any, { _game_id: game.id } as any);
      } else {
        await supabase.rpc("chess_offer_draw" as any, { _game_id: game.id } as any);
        toast.success("Nulle proposée");
      }
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };
  const doClaimDraw = async () => {
    if (!game) return;
    const ok = await confirm({
      title: "Réclamer la nulle ?",
      description: "Vous pouvez réclamer la nulle (règle des 50 coups ou répétition triple). L'adversaire ne peut pas refuser.",
      confirmLabel: "Réclamer la nulle",
    });
    if (!ok) return;
    setBusy(true);
    try {
      await chessServerPlay(supabase, "claim_draw", { game_id: game.id });
      toast.success("Nulle réclamée");
      void load();
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };
  const doReplay = async () => {
    if (!game) return;
    if (game.mode !== "solo") {
      setBusy(true);
      try {
        const { data, error } = await supabase.rpc("chess_create" as any, {
          _stake: Number(game.stake) || 0,
          _private: !!game.is_private,
          _commission: Number(game.commission_pct) || 10,
        } as any);
        if (error) throw error;
        if (data) { refreshProfile(); navigate({ to: "/jeux/chess/$id", params: { id: data as string } }); }
      } catch (e: any) { toast.error(e.message); }
      finally { setBusy(false); }
      return;
    }
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("chess_create_solo" as any, {
        _difficulty: game.bot_intelligence ?? 2,
        _color: myColor === "w" ? "white" : "black",
        _time_min: game.time_control_min,
      } as any);
      if (error) throw error;
      if (data) { refreshProfile(); navigate({ to: "/jeux/chess/$id", params: { id: data as string } }); }
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };

  /* -------- Waiting screen -------- */
  if (!isValidGameId) {
    return (
      <main className="min-h-screen bg-background p-6 flex flex-col items-center justify-center text-center gap-4">
        <p className="text-lg font-bold text-foreground">Lien de partie invalide</p>
        <p className="text-sm text-muted-foreground max-w-xs">Cette ancienne adresse n'est pas une vraie partie d'échecs.</p>
        <Button onClick={() => navigate({ to: "/jeux/$slug", params: { slug: "chess" } })}>Créer une partie</Button>
      </main>
    );
  }

  if (!game) return <GameLoader />;

  if (game.status === "cancelled") {
    return <GameStateMessage state="cancelled" gameLabel="Échecs" slug="chess" />;
  }

  if (game.status === "open" && !isActive) {
    const seatParts: any[] = [];
    if (game.white_id) {
      const wp = profiles[game.white_id];
      seatParts.push({
        id: `w-${game.white_id}`,
        user_id: game.white_id,
        display_name: wp?.pseudo || (game.white_is_bot ? (game.bot_name || "Bot") : "Blancs"),
        avatar_url: wp?.avatar_url ?? undefined,
        color: "white",
        slot: 0,
        ready: game.white_is_bot ? true : !!game.ready_white,
      });
    }
    if (game.black_id) {
      const bp = profiles[game.black_id];
      seatParts.push({
        id: `b-${game.black_id}`,
        user_id: game.black_id,
        display_name: bp?.pseudo || (game.black_is_bot ? (game.bot_name || "Bot") : "Noirs"),
        avatar_url: bp?.avatar_url ?? undefined,
        color: "black",
        slot: 1,
        ready: game.black_is_bot ? true : !!game.ready_black,
      });
    }
    const isParticipant = !!(profile?.id && (game.white_id === profile.id || game.black_id === profile.id));
    const canAddBot = (isAdmin || (Number(game.stake) === 0 && isParticipant)) && seatParts.length < 2;
    const forfeitChess = async () => {
      await supabase.rpc("chess_forfeit" as any, { _id: game.id } as any);
      navigate({ to: "/jeux" });
    };
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        {Number(game.stake) > 0 && profile?.phone_verified !== true ? (
          <div className="flex flex-col items-center justify-center gap-3 py-8 px-4 text-center">
            <ShieldAlert className="w-10 h-10 text-amber-500" />
            <p className="text-sm font-semibold">Numéro non vérifié</p>
            <p className="text-xs text-muted-foreground">Vérifiez votre numéro de téléphone pour rejoindre cette partie payante.</p>
            <button onClick={() => navigate({ to: "/securite" })} className="px-4 py-2 rounded-full bg-primary text-primary-foreground text-xs font-semibold">Vérifier mon numéro</button>
          </div>
        ) : (
        <GameWaitingRoom
          isTournament={false}
          slug="chess"
          gameLabel={`Échecs · 2 joueurs · ${game.time_control_min > 0 ? `${game.time_control_min} min` : "∞"}`}
          parts={seatParts}
          maxPlayers={2}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          roomCode={game.is_private ? game.room_code : null}
          shareSlug="chess"
          meUserId={profile?.id}
          isParticipant={isParticipant}
          createdAt={game.created_at}
          gameStatus={game.status}
          gameId={id}
          onQuit={forfeitChess}
          onToggleReady={async (ready) => {
            const { error } = await supabase.rpc("chess_set_ready" as any, { _game_id: game.id, _ready: ready } as any);
            if (error) toast.error(error.message);
          }}
        />

        )}
        {canAddBot && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("chess_add_bot" as any, { _game_id: game.id, _difficulty: "medium" } as any);
              if (error) toast.error(error.message); else toast.success("Bot ajouté");
            }}
            className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2"
          >
            <Plus className="w-4 h-4" /> Ajouter un bot
          </button>
        )}
      </main>
    );
  }

  const orientation: "w" | "b" = myColor ?? "w";
  const meId = profile?.id;
  const oppId = myColor === "w" ? game.black_id : game.white_id;
  const meColor: "w" | "b" = myColor ?? "w";
  const oppColor: "w" | "b" = meColor === "w" ? "b" : "w";

  const meProfile: Profile = meId
    ? profiles[meId] ?? { id: meId, pseudo: profile?.pseudo ?? "Moi", avatar_url: profile?.avatar_url ?? null }
    : { id: "", pseudo: "Moi", avatar_url: null };
  const oppProfile: Profile = oppId
    ? profiles[oppId] ?? { id: oppId, pseudo: game.mode === "solo" ? (game.bot_name ?? "Joueur") : "Adversaire", avatar_url: null }
    : { id: "", pseudo: "Adversaire", avatar_url: null };

  const meTime = meColor === "w" ? wTime : bTime;
  const oppTime = oppColor === "w" ? wTime : bTime;

  const meCaptured = meColor === "w" ? capturedByWhite : capturedByBlack;
  const oppCaptured = oppColor === "w" ? capturedByWhite : capturedByBlack;
  const meMatDiff = meColor === "w" ? Math.max(0, materialDiff) : Math.max(0, -materialDiff);
  const oppMatDiff = oppColor === "w" ? Math.max(0, materialDiff) : Math.max(0, -materialDiff);

  const drawOfferedByOpp = game.draw_offered_by && game.draw_offered_by !== profile?.id;

  const inCheck = gameChess.inCheck() && isActive;
  const isCheckmate = gameChess.isCheckmate() && isActive;


  return (
    <div className="h-full overflow-hidden flex flex-col bg-gradient-to-b from-stone-100 to-stone-200 dark:from-stone-900 dark:to-stone-950 overscroll-none">
      <PhoneVerifyBanner stake={Number(game?.stake) || 0} phoneVerified={profile?.phone_verified === true} />
      {/* Top bar */}
      <div className="px-2 pt-1">
              <div className="rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5">
        <div className="flex items-baseline gap-1 min-w-0">
          <span className="text-[8px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
          <span className="text-xs font-extrabold truncate">{Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar</span>
          {gameNumber && <span className="text-[10px] font-mono font-bold text-primary/80 ml-1">{gameNumber}</span>}
        </div>
        {!myColor ? (
          <div className="flex items-center gap-1">
            <div className="px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1">
              Spectateur
            </div>
            <SpectatorLeaveButton />
          </div>
        ) : (
          <div className="flex items-center gap-1">
            {(game.white_is_bot || game.black_is_bot) && game.status === "playing" && !game.paused && (
              <button
                onClick={async () => {
                  const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "chess", _game_id: id } as any);
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
            <button onClick={handleQuitGame} className="px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5">
              <LogOut className="w-2.5 h-2.5" /> Quitter
            </button>
          </div>
        )}
      </div>
      </div>

      {/* Opponent */}
      <div className="px-3 mt-1">
        <PlayerBar
          name={oppProfile.pseudo ?? "Adversaire"}
          avatarUrl={oppProfile.avatar_url}
          color={oppColor}
          timeMs={oppTime}
          isTurn={game.turn === oppColor && isActive}
          captured={oppCaptured}
          materialDiff={oppMatDiff}
        />
      </div>

      {/* Check/Checkmate banner + bot thinking */}
      <div className="px-3 pt-1 flex justify-center h-7 items-center">
        {isCheckmate && (
          <div className="px-3 py-1 rounded-full bg-red-600 text-white text-xs font-bold animate-pulse">
            Échec et mat !
          </div>
        )}
        {!isCheckmate && inCheck && (
          <div className="px-3 py-1 rounded-full bg-orange-500 text-white text-xs font-bold animate-pulse">
            Échec !
          </div>
        )}
        {botThinking && !inCheck && !isCheckmate && (
          <div className="inline-flex items-center gap-1.5 text-xs text-muted-foreground bg-card/70 border border-border/60 rounded-full px-2.5 py-1">
            <span className="inline-flex gap-0.5">
              <span className="w-1 h-1 rounded-full bg-current animate-bounce" style={{ animationDelay: "0ms" }} />
              <span className="w-1 h-1 rounded-full bg-current animate-bounce" style={{ animationDelay: "150ms" }} />
              <span className="w-1 h-1 rounded-full bg-current animate-bounce" style={{ animationDelay: "300ms" }} />
            </span>
            Le bot réfléchit…
          </div>
        )}
      </div>

      {/* Draw offer banner */}
      {drawOfferedByOpp && isActive && (
        <div className="px-3 pb-1">
          <div className="flex items-center gap-2 bg-amber-500/15 border border-amber-500/30 rounded-lg px-3 py-2">
            <span className="text-xs font-semibold text-amber-700 dark:text-amber-400 flex-1">
              🤝 L'adversaire propose la nulle
            </span>
            <button onClick={doOfferDraw} disabled={busy}
              className="px-3 py-1 rounded-md bg-amber-500 text-white text-xs font-bold hover:bg-amber-600">
              Accepter
            </button>
            <button onClick={async () => { await supabase.rpc("chess_decline_draw" as any, { _game_id: game.id } as any); }}
              className="px-3 py-1 rounded-md bg-secondary text-foreground text-xs font-bold">
              Refuser
            </button>
          </div>
        </div>
      )}

      {/* Board */}
      <div className="flex-1 flex items-center justify-center px-2 py-1 min-h-0">
        <ChessBoard
          fen={game.fen}
          myColor={orientation}
          onMove={play}
          lastMove={lastMove}
          disabled={!isActive || !myColor || botThinking || game.turn !== myColor}
        />
      </div>

      {/* Move history strip */}
      {moveHistory.length > 0 && (
        <div className="px-3 pb-0.5 max-h-16 overflow-y-auto">
          <div className="flex flex-wrap gap-1 text-[10px] font-mono">
            {moveHistory.map((m, i) => {
              const moveNum = Math.floor(i / 2) + 1;
              const isWhite = i % 2 === 0;
              return (
                <span key={i} className="px-1.5 py-0.5 rounded bg-card/60 border border-border/40">
                  {!isWhite && <span className="text-muted-foreground">{moveNum}… </span>}
                  {isWhite && <span className="text-muted-foreground">{moveNum}. </span>}
                  <span className="font-semibold">{m.san}</span>
                </span>
              );
            })}
          </div>
        </div>
      )}

      {/* Me */}
      <div className="px-3 mt-1">
        <PlayerBar
          name={meProfile.pseudo ?? "Moi"}
          avatarUrl={meProfile.avatar_url}
          color={meColor}
          timeMs={meTime}
          isTurn={game.turn === meColor && isActive}
          captured={meCaptured}
          materialDiff={meMatDiff}
        />
      </div>

      {/* Actions */}
      {isActive && myColor && (
        <div className="flex gap-2 px-3 py-2 flex-wrap">
          <Button variant="outline" className="flex-1" onClick={doResign} disabled={busy}>
            <Flag className="w-4 h-4 mr-1.5" /> Abandonner
          </Button>
          {game.mode !== "solo" && (
            <Button
              variant={drawOfferedByOpp ? "default" : "outline"}
              className="flex-1"
              onClick={doOfferDraw}
              disabled={busy}
            >
              <Handshake className="w-4 h-4 mr-1.5" />
              {drawOfferedByOpp ? "Accepter nulle" : "Nulle"}
            </Button>
          )}
          {canClaimDraw && (
            <Button
              variant="outline"
              className="flex-1 border-amber-500/50 text-amber-600 dark:text-amber-400"
              onClick={doClaimDraw}
              disabled={busy}
            >
              <Scale className="w-4 h-4 mr-1.5" /> Réclamer nulle
            </Button>
          )}
        </div>
      )}

      {/* Global game timer banner */}
      {isActive && globalTimer.enabled && globalTimer.remainingMs !== null && (
        <div className={`px-3 py-1 mx-2 rounded-lg text-center text-xs font-bold ${
          globalTimer.remainingMs <= 30000
            ? "bg-destructive/15 text-destructive animate-pulse"
            : "bg-amber-500/10 text-amber-600 dark:text-amber-400"
        }`}>
          ⏳ Temps global restant : {globalTimer.remainingLabel}
        </div>
      )}

      {/* Pause control (AFK vote + pause overlay) */}
      <GamePauseControl
        slug="chess"
        gameId={id}
        game={game}
        isPlayer={isPlayer}
        myUserId={profile?.id ?? null}
        simplePause={game.mode === "solo"}
      />

      {/* End screen */}
      {game.status === "finished" && (() => {
        const reasonLabel: Record<string, string> = {
          checkmate: "Échec et mat",
          stalemate: "Pat (stalemate)",
          timeout: "Temps écoulé",
          timeout_insufficient_material: "Temps écoulé — nulle (matériel insuffisant)",
          resign: "Abandon",
          forfeit: "Forfait",
          draw_agreed: "Nulle acceptée",
          repetition: "Répétition triple",
          threefold_repetition: "Répétition triple",
          fivefold_repetition: "Répétition quintuple",
          insufficient: "Matériel insuffisant",
          insufficient_material: "Matériel insuffisant",
          draw_50: "Règle des 50 coups",
          fifty_move_rule: "Règle des 50 coups",
          draw_75: "Règle des 75 coups",
          seventyfive_move_rule: "Règle des 75 coups",
        };
        const participants = [
          game.white_id ? {
            user_id: game.white_id,
            display_name: game.white_is_bot ? (game.bot_name ?? "Ordinateur") : (profiles[game.white_id]?.pseudo ?? "Blancs"),
            slot: 0,
          } : null,
          game.black_id ? {
            user_id: game.black_id,
            display_name: game.black_is_bot ? (game.bot_name ?? "Ordinateur") : (profiles[game.black_id]?.pseudo ?? "Noirs"),
            slot: 1,
          } : null,
        ].filter(Boolean) as { user_id: string; display_name: string; slot: number }[];
        return (
          <GameEndScreen
            slug="chess"
            meUserId={profile?.id}
            winnerId={game.draw ? null : game.winner_id}
            participants={participants}
            stake={Number(game.stake)}
            pot={Number(game.pot)}
            commissionPct={10}
            onReplay={doReplay}
            extra={game.end_reason ? (
              <div className="text-xs text-muted-foreground">{reasonLabel[game.end_reason] ?? game.end_reason}</div>
            ) : undefined}
          />
        );
      <GameSocialFab gameId={id} gameSlug="chess" participants={[{ user_id: game?.white_id, display_name: game?.white_is_bot ? (game?.bot_name ?? "Bot") : (profiles[game?.white_id ?? ""]?.pseudo ?? "Blancs"), slot: 0 }, { user_id: game?.black_id, display_name: game?.black_is_bot ? (game?.bot_name ?? "Bot") : (profiles[game?.black_id ?? ""]?.pseudo ?? "Noirs"), slot: 1 }].filter(p => p.user_id)} />
      })()}
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
    </div>
  );
}
