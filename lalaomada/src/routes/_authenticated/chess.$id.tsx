import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { Chess } from "chess.js";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { ArrowLeft, Flag, Handshake, Copy, RotateCw, LogOut, Plus } from "lucide-react";
import { copyText } from "@/lib/clipboard";
import { Button } from "@/components/ui/button";
import { ChessBoard } from "@/components/chess/ChessBoard";
import { PlayerBar } from "@/components/chess/PlayerBar";
import GameEndScreen from "@/components/GameEndScreen";
import GameWaitingRoom from "@/components/GameWaitingRoom";
import { useConfirm } from "@/components/ConfirmDialog";

export const Route = createFileRoute("/_authenticated/chess/$id")({
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
};

type Profile = { id: string; pseudo: string | null; avatar_url: string | null };

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

const PIECE_VAL: Record<string, number> = { p: 1, n: 3, b: 3, r: 5, q: 9, k: 0 };

/* ------------------------ Bot AI (client) ------------------------ */
function evaluate(chess: Chess): number {
  // Positive = white advantage
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
    // Niveau 1 - Très facile : coups aléatoires purs
    chosen = moves[Math.floor(Math.random() * moves.length)];
  } else if (level === 2) {
    // Niveau 2 - Facile : évite les gaffes évidentes, capture parfois
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
    // Niveau 3 - Moyen : capture greedy + priorité aux échecs et promotions
    const scored = moves.map((m) => {
      let s = 0;
      if (m.captured) s += (PIECE_VAL[m.captured] ?? 0) * 10;
      if (m.san?.includes("+")) s += 3;
      if (m.san?.includes("#")) s += 1000;
      if (m.promotion) s += 8;
      s += Math.random() * 0.5;
      return { m, s };
    });
    scored.sort((a, b) => b.s - a.s);
    chosen = scored[0].m;
  } else if (level === 4) {
    // Niveau 4 - Difficile : minimax profondeur 2 avec élagage alpha-beta
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
    // Niveau 5 - Expert : minimax profondeur 3 avec élagage alpha-beta
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
  const { profile, isAdmin } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();
  const [game, setGame] = useState<Game | null>(null);
  const [profiles, setProfiles] = useState<Record<string, Profile>>({});
  const [lastMove, setLastMove] = useState<{ from: string; to: string } | null>(null);
  const [now, setNow] = useState(Date.now());
  const [busy, setBusy] = useState(false);
  const [showEnd, setShowEnd] = useState(false);
  const [botThinking, setBotThinking] = useState(false);
  const botTriggeredRef = useRef<number>(-1);
  const endTriggeredRef = useRef<number>(-1);
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
    if (game?.id) await supabase.rpc("chess_resign" as any, { _id: game.id } as any);
    navigate({ to: "/jeux" });
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
    // Last move
    const { data: mv } = await supabase.from("chess_moves").select("uci").eq("game_id", id).order("ply", { ascending: false }).limit(1);
    if (mv && mv[0]?.uci) {
      const u = mv[0].uci as string;
      setLastMove({ from: u.slice(0, 2), to: u.slice(2, 4) });
    }
  }, [id, isValidGameId]);

  useEffect(() => { void load(); }, [load]);

  /* -------- Realtime -------- */
  useEffect(() => {
    if (!isValidGameId) return;
    const ch = supabase.channel(`chess-${id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "chess_games", filter: `id=eq.${id}` }, () => { void load(); })
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chess_moves", filter: `game_id=eq.${id}` }, (p) => {
        const u = (p.new as any).uci as string;
        if (u) setLastMove({ from: u.slice(0, 2), to: u.slice(2, 4) });
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, isValidGameId, load]);

  /* -------- Timer tick (UI) -------- */
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(t);
  }, []);

  const myColor: "w" | "b" | null = useMemo(() => {
    if (!game || !profile) return null;
    if (game.white_id === profile.id) return "w";
    if (game.black_id === profile.id) return "b";
    return null;
  }, [game, profile]);

  const isActive = game?.status === "playing" || game?.status === "active";

  /* -------- Time computation -------- */
  const elapsedSinceMove = useMemo(() => {
    if (!game || !isActive) return 0;
    const base = new Date(game.last_move_at ?? game.started_at ?? Date.now()).getTime();
    return Math.max(0, now - base);
  }, [game, isActive, now]);

  const wTime = game ? Math.max(0, game.white_time_ms - (game.turn === "w" ? elapsedSinceMove : 0)) : 0;
  const bTime = game ? Math.max(0, game.black_time_ms - (game.turn === "b" ? elapsedSinceMove : 0)) : 0;

  /* -------- Play a move -------- */
  const play = useCallback(async (uci: string, san: string, fenAfter: string) => {
    if (!game) return;
    const { error } = await supabase.rpc("chess_play" as any, {
      _id: game.id, _uci: uci, _san: san, _fen_after: fenAfter, _elapsed_ms: elapsedSinceMove,
    } as any);
    if (error) {
      console.error("chess_play error", error);
      toast.error(error.message ?? "Coup invalide");
      return;
    }
    // Optimistic refresh — realtime will follow
    void load();
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

    // Précalcul du coup + estimation de complexité pour un délai adaptatif (2000–3000 ms)
    const preChess = new Chess(game.fen);
    const preMove = preChess.isGameOver() ? null : pickBotMove(game.fen, level);
    const legalCount = preChess.isGameOver() ? 0 : preChess.moves().length;
    let complexity = 0;
    if (preMove) {
      complexity += Math.min(1, legalCount / 35); // + de coups légaux => + de réflexion
      const san = preMove.san ?? "";
      if (san.includes("x")) complexity += 0.25;      // capture
      if (san.includes("+")) complexity += 0.2;       // échec
      if (san.includes("#")) complexity += 0.35;      // mat
      if (san.includes("=")) complexity += 0.25;      // promotion
      if (san === "O-O" || san === "O-O-O") complexity += 0.15;
      complexity += (level - 1) * 0.1;                // niveau plus élevé = réfléchit un peu plus
    }
    complexity = Math.max(0, Math.min(1, complexity));
    const jitter = (Math.random() - 0.5) * 200;
    const delay = Math.max(2000, Math.min(3000, 2000 + complexity * 1000 + jitter));

    setBotThinking(true);
    const timer = setTimeout(async () => {
      if (botTriggeredRef.current === plyAtSchedule) { setBotThinking(false); return; }
      botTriggeredRef.current = plyAtSchedule;
      const chess = new Chess(game.fen);
      if (chess.isGameOver()) { setBotThinking(false); return; }
      const mv = preMove ?? pickBotMove(game.fen, level);
      if (!mv) { setBotThinking(false); return; }
      const gameElapsed = Math.max(0, Date.now() - new Date(game.last_move_at ?? game.started_at ?? Date.now()).getTime());
      const { error } = await supabase.rpc("chess_bot_play" as any, {
        _id: game.id, _uci: mv.uci, _san: mv.san, _fen_after: mv.fenAfter, _elapsed_ms: gameElapsed,
      } as any);
      if (error) {
        console.error("bot_play error", error);
        botTriggeredRef.current = -1;
        toast.error(error.message ?? "Erreur bot");
      } else {
        void load();
      }
      setBotThinking(false);
    }, delay);
    return () => { clearTimeout(timer); setBotThinking(false); };
  }, [game, isActive, myColor, load]);




  /* -------- End detection (any observer reports; server dedupes) -------- */
  useEffect(() => {
    if (!game || !isActive) return;
    if (endTriggeredRef.current === game.ply) return;
    const chess = new Chess(game.fen);
    if (!chess.isGameOver()) return;
    endTriggeredRef.current = game.ply;
    let winner: string | null = null;
    let draw = false;
    let reason = "";
    if (chess.isCheckmate()) {
      winner = chess.turn() === "w" ? game.black_id : game.white_id;
      reason = "checkmate";
    } else if (chess.isStalemate()) { draw = true; reason = "stalemate"; }
    else if (chess.isThreefoldRepetition()) { draw = true; reason = "repetition"; }
    else if (chess.isInsufficientMaterial()) { draw = true; reason = "insufficient"; }
    else if (chess.isDraw()) { draw = true; reason = "draw_50"; }
    (async () => {
      const { error } = await supabase.rpc("chess_finish" as any, {
        _id: game.id, _winner: winner, _draw: draw, _reason: reason,
      } as any);
      if (error) {
        console.error("chess_finish error", error);
        endTriggeredRef.current = -1; // allow retry
        toast.error(error.message ?? "Impossible de terminer la partie");
      } else {
        void load();
      }
    })();
  }, [game, isActive, load]);

  /* -------- Timeout to server (with fallback) -------- */
  const timeoutFiredRef = useRef<string | null>(null);
  useEffect(() => {
    if (!game || !isActive) return;
    if (wTime > 0 && bTime > 0) return;
    const loserColor = wTime <= 0 ? "w" : "b";
    const key = `${game.id}:${game.ply}:${loserColor}`;
    if (timeoutFiredRef.current === key) return;
    timeoutFiredRef.current = key;
    (async () => {
      // 1) primary: server-side tick
      await supabase.rpc("chess_tick" as any, { _id: game.id } as any);
      // 2) fallback after 1.2s: force finish if still playing
      setTimeout(async () => {
        const { data } = await supabase
          .from("chess_games" as any)
          .select("status")
          .eq("id", game.id)
          .maybeSingle();
        if ((data as any)?.status === "playing") {
          const winner = loserColor === "w" ? game.black_id : game.white_id;
          await supabase.rpc("chess_finish" as any, {
            _id: game.id, _winner: winner, _draw: false, _reason: "timeout",
          } as any);
          void load();
        }
      }, 1200);
    })();
  }, [game, isActive, wTime, bTime, load]);

  /* -------- Show end dialog once finished -------- */
  useEffect(() => {
    if (game?.status === "finished") setShowEnd(true);
  }, [game?.status]);

  /* -------- Actions -------- */
  const doResign = async () => {
    if (!game) return;
    if (!confirm("Abandonner cette partie ?")) return;
    setBusy(true);
    try { await supabase.rpc("chess_resign" as any, { _id: game.id } as any); }
    catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };
  const doOfferDraw = async () => {
    if (!game) return;
    setBusy(true);
    try {
      if (game.draw_offered_by && game.draw_offered_by !== profile?.id) {
        await supabase.rpc("chess_accept_draw" as any, { _id: game.id } as any);
      } else {
        await supabase.rpc("chess_offer_draw" as any, { _id: game.id } as any);
        toast.success("Nulle proposée");
      }
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };
  const doReplay = async () => {
    if (!game) return;
    if (game.mode !== "solo") { navigate({ to: "/jeux/nouveau/$slug", params: { slug: "chess" } }); return; }
    setBusy(true);
    try {
      const { data, error } = await supabase.rpc("chess_create_solo" as any, {
        _difficulty: game.bot_intelligence ?? 2,
        _color: myColor === "w" ? "white" : "black",
        _time_min: game.time_control_min,
      } as any);
      if (error) throw error;
      if (data) navigate({ to: "/chess/$id", params: { id: data as string } });
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };

  /* -------- Waiting screen -------- */
  if (!isValidGameId) {
    return (
      <main className="min-h-screen bg-background p-6 flex flex-col items-center justify-center text-center gap-4">
        <p className="text-lg font-bold text-foreground">Lien de partie invalide</p>
        <p className="text-sm text-muted-foreground max-w-xs">Cette ancienne adresse n'est pas une vraie partie d'échecs.</p>
        <Button onClick={() => navigate({ to: "/jeux/nouveau/$slug", params: { slug: "chess" } })}>Créer une partie</Button>
      </main>
    );
  }

  if (!game) return <div className="p-4">Chargement…</div>;

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
          onQuit={forfeitChess}
          onToggleReady={async (ready) => {
            const { error } = await supabase.rpc("chess_set_ready" as any, { _game_id: game.id, _ready: ready } as any);
            if (error) toast.error(error.message);
          }}
        />

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

  /* Captured pieces per side (from FEN diff vs starting) */
  const missing = (() => {
    const startCount: Record<string, number> = { p: 8, n: 2, b: 2, r: 2, q: 1 };
    const cur: Record<string, { w: number; b: number }> = {};
    for (const row of new Chess(game.fen).board()) for (const c of row) if (c) {
      cur[c.type] ??= { w: 0, b: 0 }; cur[c.type][c.color]++;
    }
    const capturedByWhite: string[] = []; const capturedByBlack: string[] = [];
    for (const t of Object.keys(startCount)) {
      const w = cur[t]?.w ?? 0; const b = cur[t]?.b ?? 0;
      for (let i = 0; i < startCount[t] - b; i++) capturedByWhite.push(t);
      for (let i = 0; i < startCount[t] - w; i++) capturedByBlack.push(t);
    }
    return { capturedByWhite, capturedByBlack };
  })();
  const meCaptured = meColor === "w" ? missing.capturedByWhite : missing.capturedByBlack;
  const oppCaptured = oppColor === "w" ? missing.capturedByWhite : missing.capturedByBlack;

  const drawOfferedByOpp = game.draw_offered_by && game.draw_offered_by !== profile?.id;

  return (
    <div className="h-[100dvh] overflow-hidden flex flex-col bg-gradient-to-b from-stone-100 to-stone-200 dark:from-stone-900 dark:to-stone-950">
      {/* Top bar — style aligné sur Domino */}
      <div className="px-2 pt-1">
        <div className="rounded-md bg-card/70 border border-white/8 px-2 py-1 flex items-center gap-2 text-xs">
          <span className="font-bold text-sm">♛</span>
          {Number(game.pot) > 0 ? (
            <span className="flex items-baseline gap-1">
              <span className="text-[9px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
              <span className="font-extrabold text-sm text-emerald-500">
                {Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar
              </span>
            </span>
          ) : (
            <span className="font-bold text-sm">
              {game.mode === "solo" && "Vs Ordinateur"}
              {game.mode === "friends" && "Partie privée"}
              {game.mode === "tournament" && "Tournoi"}
            </span>
          )}

          {myColor ? (
            <button onClick={handleQuitGame}
              className="ml-auto flex items-center gap-1 px-2 py-1 rounded bg-destructive/10 text-destructive hover:bg-destructive/20 text-xs font-semibold border border-destructive/20">
              <LogOut className="w-3.5 h-3.5" /> Quitter
            </button>
          ) : (
            <button onClick={() => navigate({ to: "/live" })}
              className="ml-auto flex items-center gap-1 px-2 py-1 rounded bg-secondary text-foreground hover:bg-secondary/80 text-xs font-semibold border border-white/10">
              <LogOut className="w-3.5 h-3.5" /> Sortir du live
            </button>
          )}
        </div>
      </div>


      {/* Opponent */}
      <div className="px-3">
        <PlayerBar
          name={oppProfile.pseudo ?? "Adversaire"}
          avatarUrl={oppProfile.avatar_url}
          color={oppColor}
          timeMs={oppTime}
          isTurn={game.turn === oppColor && isActive}
          captured={oppCaptured}
        />
      </div>

      <div className="px-3 pt-1 flex justify-center h-6">
        {botThinking && (
          <div className="inline-flex items-center gap-2 text-xs text-muted-foreground bg-card/70 border border-border/60 rounded-full px-3 py-1 animate-fade-in">
            <span className="inline-flex gap-0.5">
              <span className="w-1 h-1 rounded-full bg-current animate-bounce" style={{ animationDelay: "0ms" }} />
              <span className="w-1 h-1 rounded-full bg-current animate-bounce" style={{ animationDelay: "150ms" }} />
              <span className="w-1 h-1 rounded-full bg-current animate-bounce" style={{ animationDelay: "300ms" }} />
            </span>
            Le bot réfléchit…
          </div>
        )}
      </div>


      {/* Board */}
      <div className="flex-1 flex items-center justify-center px-2 py-2">
        <ChessBoard
          fen={game.fen}
          myColor={orientation}
          onMove={play}
          lastMove={lastMove}
          disabled={!isActive || !myColor || botThinking || game.turn !== myColor}
        />
      </div>

      {/* Me */}
      <div className="px-3">
        <PlayerBar
          name={meProfile.pseudo ?? "Moi"}
          avatarUrl={meProfile.avatar_url}
          color={meColor}
          timeMs={meTime}
          isTurn={game.turn === meColor && isActive}
          captured={meCaptured}
        />
      </div>

      {/* Actions */}
      {isActive && myColor && (
        <div className="flex gap-2 p-3">
          <Button variant="outline" className="flex-1" onClick={doResign} disabled={busy}>
            <Flag className="w-4 h-4 mr-2" /> Abandonner
          </Button>
          {game.mode !== "solo" && (
            <Button
              variant={drawOfferedByOpp ? "default" : "outline"}
              className="flex-1"
              onClick={doOfferDraw}
              disabled={busy}
            >
              <Handshake className="w-4 h-4 mr-2" />
              {drawOfferedByOpp ? "Accepter nulle" : "Nulle"}
            </Button>
          )}
        </div>
      )}

      {/* End screen — aligné sur le style Domino */}
      {game.status === "finished" && (() => {
        const reasonLabel: Record<string, string> = {
          checkmate: "Échec et mat",
          stalemate: "Pat",
          timeout: "Temps écoulé",
          resign: "Abandon",
          draw_agreed: "Nulle acceptée",
          repetition: "Répétition",
          insufficient: "Matériel insuffisant",
          draw_50: "Règle des 50 coups",
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
      })()}
    </div>
  );
}
