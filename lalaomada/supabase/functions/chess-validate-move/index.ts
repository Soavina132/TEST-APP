// Supabase Edge Function: chess-validate-move
// Valide les coups d'échecs côté serveur avec chess.js
// Empêche la triche en mode argent réel

import { Chess } from "https://esm.sh/chess.js@1.4.0";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Helper: fetch JSON avec gestion d'erreur
async function sbFetch(url: string, opts: RequestInit, token: string) {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "apikey": token,
    "Authorization": `Bearer ${token}`,
    ...(opts.headers as Record<string, string> || {}),
  };
  const res = await fetch(url, { ...opts, headers });
  const data = await res.json();
  if (!res.ok) {
    throw new Error(data?.message || data?.error || `HTTP ${res.status}`);
  }
  return data;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return json({ error: "auth required" }, 401);
    }

    const body = await req.json();
    const { action } = body;

    if (action === "play") {
      return await handlePlay(body, token);
    } else if (action === "finish") {
      return await handleFinish(body, token);
    } else {
      return json({ error: "unknown action" }, 400);
    }
  } catch (err: any) {
    return json({ error: err.message || "server error" }, 500);
  }
});

// ── Récupérer l'utilisateur ──
async function getUser(token: string): Promise<string> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "apikey": token,
      "Authorization": `Bearer ${token}`,
    },
  });
  if (!res.ok) {
    throw new Error("Token invalide ou expiré");
  }
  const user = await res.json();
  if (!user?.id) {
    throw new Error("Utilisateur non trouvé");
  }
  return user.id;
}

// ── Récupérer une partie ──
async function getGame(gameId: string, token: string) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/chess_games?id=eq.${gameId}&select=*`, {
    headers: {
      "apikey": token,
      "Authorization": `Bearer ${token}`,
    },
  });
  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    throw new Error(errData?.message || `Erreur ${res.status} lors de la récupération de la partie`);
  }
  const games = await res.json();
  if (!Array.isArray(games) || games.length === 0) {
    throw new Error("Partie introuvable");
  }
  return games[0];
}

// ── Service role RPC ──
async function serviceRpc(fn: string, params: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(params),
  });
  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    throw new Error(errData?.message || `RPC ${fn} failed: HTTP ${res.status}`);
  }
  return res.json();
}

// ── Service role PATCH ──
async function servicePatch(table: string, filter: string, data: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${filter}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    throw new Error(errData?.message || `PATCH ${table} failed: HTTP ${res.status}`);
  }
  return res.json();
}

// ── Service role INSERT ──
async function serviceInsert(table: string, data: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify(data),
  });
  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    throw new Error(errData?.message || `INSERT ${table} failed: HTTP ${res.status}`);
  }
  return res.json();
}

// ── Valider et jouer un coup ──
async function handlePlay(body: any, token: string) {
  const { game_id, uci, elapsed_ms, is_bot } = body;
  if (!game_id || !uci) {
    return json({ error: "missing game_id or uci" }, 400);
  }

  // 1. Récupérer la partie
  const game = await getGame(game_id, token);
  if (game.status !== "playing") {
    return json({ error: "game not active" }, 400);
  }

  // 2. Vérifier l'identité du joueur
  const uid = await getUser(token);

  let myColor: string;
  let botId: string | null = null;
  let botColor: string | null = null;

  if (is_bot) {
    if (game.mode !== "solo") {
      return json({ error: "not a solo game" }, 400);
    }
    if (game.white_id === uid && game.black_is_bot) {
      myColor = "w";
      botId = game.black_id;
      botColor = "b";
    } else if (game.black_id === uid && game.white_is_bot) {
      myColor = "b";
      botId = game.white_id;
      botColor = "w";
    } else {
      return json({ error: "not a solo-bot game" }, 403);
    }
    if (game.turn !== botColor) {
      return json({ error: "not bot turn" }, 400);
    }
  } else {
    if (game.white_id === uid) myColor = "w";
    else if (game.black_id === uid) myColor = "b";
    else return json({ error: "not a participant" }, 403);
    if (game.turn !== myColor) {
      return json({ error: "not your turn" }, 400);
    }
  }

  // 3. Valider le coup avec chess.js
  const chess = new Chess(game.fen);
  if (chess.isGameOver()) {
    return json({ error: "game already over" }, 400);
  }

  const from = uci.slice(0, 2);
  const to = uci.slice(2, 4);
  const promotion = uci.length > 4 ? uci.slice(4) : undefined;

  let move;
  try {
    move = chess.move({ from, to, promotion: promotion || "q" });
  } catch {
    return json({ error: "illegal move" }, 400);
  }
  if (!move) {
    return json({ error: "illegal move" }, 400);
  }

  // 4. Le coup est valide — mettre à jour la DB
  const fenAfter = chess.fen();
  const newTurn = game.turn === "w" ? "b" : "w";
  const moverId = is_bot ? botId : uid;
  const moverColor = is_bot ? botColor! : myColor;

  // Insérer le coup
  await serviceInsert("chess_moves", {
    game_id,
    ply: game.ply + 1,
    san: move.san,
    uci,
    fen_after: fenAfter,
    by_user: moverId,
  });

  // Mettre à jour la partie
  await servicePatch("chess_games", `id=eq.${game_id}`, {
    fen: fenAfter,
    turn: newTurn,
    ply: game.ply + 1,
    last_move_at: new Date().toISOString(),
    white_time_ms: moverColor === "w"
      ? Math.max(0, game.white_time_ms - (elapsed_ms || 0))
      : game.white_time_ms,
    black_time_ms: moverColor === "b"
      ? Math.max(0, game.black_time_ms - (elapsed_ms || 0))
      : game.black_time_ms,
    draw_offered_by: game.draw_offered_by === uid ? null : game.draw_offered_by,
  });

  // 5. Vérifier la fin de partie
  let gameEnd = null;
  if (chess.isGameOver()) {
    let winner: string | null = null;
    let draw = false;
    let reason = "";
    if (chess.isCheckmate()) {
      winner = chess.turn() === "w" ? game.black_id : game.white_id;
      reason = "checkmate";
    } else if (chess.isStalemate()) {
      draw = true; reason = "stalemate";
    } else if (chess.isThreefoldRepetition()) {
      draw = true; reason = "repetition";
    } else if (chess.isInsufficientMaterial()) {
      draw = true; reason = "insufficient";
    } else if (chess.isDraw()) {
      draw = true; reason = "draw_50";
    }
    await serviceRpc("_chess_settle", { _id: game_id, _winner: winner, _draw: draw, _reason: reason });
    gameEnd = { winner, draw, reason };
  } else {
    // Vérifier règles officielles (50 coups, répétition, matériel insuffisant)
    await serviceRpc("_chess_check_game_end", { _game_id: game_id, _fen_after: fenAfter });
  }

  return json({
    ok: true,
    fen: fenAfter,
    san: move.san,
    turn: newTurn,
    ply: game.ply + 1,
    game_end: gameEnd,
  });
}

// ── Valider la fin de partie (checkmate/stalemate/draw/timeout) ──
async function handleFinish(body: any, token: string) {
  const { game_id, winner, draw, reason } = body;
  if (!game_id) {
    return json({ error: "missing game_id" }, 400);
  }

  // Récupérer la partie
  const game = await getGame(game_id, token);
  if (game.status !== "playing") {
    return json({ error: "game not active" }, 400);
  }

  // Vérifier l'utilisateur
  const uid = await getUser(token);
  if (uid !== game.white_id && uid !== game.black_id) {
    return json({ error: "not a participant" }, 403);
  }

  // Valider avec chess.js
  const chess = new Chess(game.fen);

  if (reason === "timeout") {
    // Vérifier le timeout côté serveur
    const now = Date.now();
    const lastMove = game.last_move_at || game.started_at;
    const elapsed = now - new Date(lastMove).getTime();
    const moverTime = game.turn === "w" ? game.white_time_ms : game.black_time_ms;
    
    if (moverTime > 0 && elapsed < moverTime) {
      // Le joueur a encore du temps — vérifier le temps global
      if (game.game_deadline && now < new Date(game.game_deadline).getTime()) {
        return json({ error: "timeout not reached yet" }, 400);
      }
    }
    // Timeout confirmé — le perdant est celui dont c'est le tour
    const realWinner = game.turn === "w" ? game.black_id : game.white_id;
    await serviceRpc("_chess_settle", { _id: game_id, _winner: realWinner, _draw: false, _reason: "timeout" });
    return json({ ok: true, winner: realWinner, draw: false, reason: "timeout" });
  }

  // Pour checkmate/stalemate/draw — valider avec chess.js
  if (!chess.isGameOver()) {
    return json({ error: "game not over" }, 400);
  }

  let realWinner: string | null = null;
  let realDraw = false;
  let realReason = "";

  if (chess.isCheckmate()) {
    realWinner = chess.turn() === "w" ? game.black_id : game.white_id;
    realReason = "checkmate";
  } else if (chess.isStalemate()) {
    realDraw = true; realReason = "stalemate";
  } else if (chess.isThreefoldRepetition()) {
    realDraw = true; realReason = "repetition";
  } else if (chess.isInsufficientMaterial()) {
    realDraw = true; realReason = "insufficient";
  } else if (chess.isDraw()) {
    realDraw = true; realReason = "draw_50";
  } else {
    return json({ error: "unknown game end state" }, 400);
  }

  // Vérifier que le gagnant envoyé par le client correspond
  if (!realDraw && winner !== realWinner) {
    return json({ error: "winner mismatch" }, 400);
  }

  await serviceRpc("_chess_settle", {
    _id: game_id,
    _winner: realWinner,
    _draw: realDraw,
    _reason: realReason,
  });

  return json({ ok: true, winner: realWinner, draw: realDraw, reason: realReason });
}
