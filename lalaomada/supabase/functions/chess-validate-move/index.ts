// Supabase Edge Function: chess-validate-move
// Valide les coups d'échecs côté serveur avec chess.js
// Empêche la triche en mode argent réel
//
// Règles officielles FIDE:
// - Échec, échec et mat, pat → détectés par chess.js
// - Roque, prise en passant, promotion (4 choix) → validés par chess.js
// - Règle des 50 coups → RÉCLAMABLE (ne termine pas automatiquement)
// - Règle des 75 coups → AUTOMATIQUE (halfmove >= 150)
// - Répétition triple → RÉCLAMABLE (ne termine pas automatiquement)
// - Répétition quintuple → AUTOMATIQUE (count >= 5)
// - Matériel insuffisant / position morte → AUTOMATIQUE
// - Timeout → vérifie si l'adversaire a le matériel pour mater

import { Chess } from "https://esm.sh/chess.js@1.4.0";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") || SERVICE_KEY;

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const userToken = authHeader.replace("Bearer ", "");
    if (!userToken) {
      return json({ error: "auth required" }, 401);
    }

    const reqText = await req.text();
    const body = reqText ? JSON.parse(reqText) : {};
    const { action } = body;

    if (action === "play") {
      return await handlePlay(body, userToken);
    } else if (action === "finish") {
      return await handleFinish(body, userToken);
    } else if (action === "claim_draw") {
      return await handleClaimDraw(body, userToken);
    } else if (action === "can_claim_draw") {
      return await handleCanClaimDraw(body, userToken);
    } else {
      return json({ error: "unknown action" }, 400);
    }
  } catch (err: any) {
    return json({ error: err.message || "server error" }, 500);
  }
});

// ── Headers pour requêtes authentifiées (user JWT) ──
function userHeaders(token: string): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "apikey": ANON_KEY,
    "Authorization": `Bearer ${token}`,
  };
}

// ── Headers pour requêtes service role ──
function serviceHeaders(): Record<string, string> {
  return {
    "Content-Type": "application/json",
    "apikey": SERVICE_KEY,
    "Authorization": `Bearer ${SERVICE_KEY}`,
  };
}

// ── Récupérer l'utilisateur ──
async function getUser(token: string): Promise<string> {
  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "apikey": ANON_KEY,
      "Authorization": `Bearer ${token}`,
    },
  });
  if (!res.ok) {
    throw new Error("Token invalide ou expiré");
  }
  const userText = await res.text();
  const user = userText ? JSON.parse(userText) : {};
  if (!user?.id) {
    throw new Error("Utilisateur non trouvé");
  }
  return user.id;
}

// ── Récupérer une partie (avec token utilisateur) ──
async function getGame(gameId: string, token: string) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/chess_games?id=eq.${gameId}&select=*`, {
    headers: userHeaders(token),
  });
  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    throw new Error(errData?.message || `Erreur ${res.status} lors de la récupération de la partie`);
  }
  const gamesText = await res.text();
  const games = gamesText ? JSON.parse(gamesText) : [];
  if (!Array.isArray(games) || games.length === 0) {
    throw new Error("Partie introuvable");
  }
  return games[0];
}

// ── Service role RPC ──
async function serviceRpc(fn: string, params: Record<string, unknown>) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: serviceHeaders(),
    body: JSON.stringify(params),
  });
  if (!res.ok) {
    const errData = await res.json().catch(() => ({}));
    throw new Error(errData?.message || `RPC ${fn} failed: HTTP ${res.status}`);
  }
  const rpcText = await res.text();
  return rpcText ? JSON.parse(rpcText) : {};
}

// ── Extraire le halfmove clock du FEN ──
function getHalfmoveClock(fen: string): number {
  const parts = fen.split(" ");
  return parts.length >= 5 ? (parseInt(parts[4], 10) || 0) : 0;
}

// ── Patcher le FEN pour contourner le blocage de chess.js ──
// chess.js considère isGameOver() = true quand halfmove >= 100 (50-move rule)
// On remet le halfmove clock à 99 pour permettre de continuer à jouer
// puisque la règle des 50 coups est RÉCLAMABLE (pas automatique)
function patchFenFor50Move(fen: string): string {
  const parts = fen.split(" ");
  if (parts.length >= 5) {
    const halfmove = parseInt(parts[4], 10) || 0;
    if (halfmove >= 100) {
      parts[4] = "99";
      return parts.join(" ");
    }
  }
  return fen;
}

// ── Vérifier si une nulle est réclamable ──
async function handleCanClaimDraw(body: any, token: string) {
  const { game_id } = body;
  if (!game_id) {
    return json({ error: "missing game_id" }, 400);
  }

  const game = await getGame(game_id, token);
  if (game.status !== "playing") {
    return json({ can_claim: false });
  }

  const result = await serviceRpc("_chess_can_claim_draw", { _game_id: game_id });
  return json({ ok: true, ...result });
}

// ── Réclamer la nulle (50 coups ou triple répétition) ──
async function handleClaimDraw(body: any, token: string) {
  const { game_id } = body;
  if (!game_id) {
    return json({ error: "missing game_id" }, 400);
  }

  const game = await getGame(game_id, token);
  if (game.status !== "playing") {
    return json({ error: "game not active" }, 400);
  }

  const uid = await getUser(token);
  if (uid !== game.white_id && uid !== game.black_id) {
    return json({ error: "not a participant" }, 403);
  }

  // Appeler la fonction SQL qui vérifie et settle
  await serviceRpc("chess_claim_draw", { _game_id: game_id });

  return json({ ok: true, draw: true, reason: "claimed" });
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
  // Patch le FEN si halfmove clock >= 100 pour contourner le blocage isGameOver()
  // (la règle des 50 coups est réclamable, pas automatique)
  const patchedFen = patchFenFor50Move(game.fen);
  const chess = new Chess(patchedFen);

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

  // 4. Le coup est valide — appliquer atomiquement via _chess_apply_move
  const fenAfter = chess.fen();
  const newTurn = game.turn === "w" ? "b" : "w";
  const moverId = is_bot ? botId : uid;
  const moverColor = is_bot ? botColor! : myColor;

  // Appel atomique: lock la partie, insère le coup, update la partie
  const applyResult = await serviceRpc("_chess_apply_move", {
    _game_id: game_id,
    _fen_after: fenAfter,
    _turn: newTurn,
    _san: move.san,
    _uci: uci,
    _by_user: moverId,
    _elapsed_ms: elapsed_ms || 0,
    _mover_color: moverColor,
    _clear_draw_offer: game.draw_offered_by === uid ? uid : null,
  });

  const newPly = applyResult?.ply || game.ply + 1;

  // 5. Vérifier la fin de partie
  // On ne utilise PAS chess.isGameOver() car il inclut 50-move et threefold
  // qui sont RÉCLAMABLES (pas automatiques)
  let gameEnd = null;

  // Échec et mat → AUTOMATIQUE
  if (chess.isCheckmate()) {
    const winner = chess.turn() === "w" ? game.black_id : game.white_id;
    await serviceRpc("_chess_settle", { _id: game_id, _winner: winner, _draw: false, _reason: "checkmate" });
    gameEnd = { winner, draw: false, reason: "checkmate" };
  }
  // Pat → AUTOMATIQUE
  else if (chess.isStalemate()) {
    await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "stalemate" });
    gameEnd = { winner: null, draw: true, reason: "stalemate" };
  }
  // Matériel insuffisant / position morte → AUTOMATIQUE
  else if (chess.isInsufficientMaterial()) {
    await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "insufficient_material" });
    gameEnd = { winner: null, draw: true, reason: "insufficient_material" };
  }
  // Vérifier les règles automatiques restantes (75 coups, 5x répétition)
  // ET enregistrer la position dans l'historique (pour répétition)
  else {
    const halfmoveAfter = getHalfmoveClock(fenAfter);

    // Règle des 75 coups (halfmove >= 150) → AUTOMATIQUE
    if (halfmoveAfter >= 150) {
      await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "seventyfive_move_rule" });
      gameEnd = { winner: null, draw: true, reason: "seventyfive_move_rule" };
    } else {
      // _chess_check_game_end va:
      // - vérifier le matériel insuffisant (recheck côté SQL)
      // - enregistrer la position dans l'historique
      // - vérifier la répétition quintuple (auto) vs triple (réclamable)
      // - vérifier la règle des 75 coups
      await serviceRpc("_chess_check_game_end", { _game_id: game_id, _fen_after: fenAfter });
    }
  }

  // 6. Vérifier si une nulle est réclamable (pour info du frontend)
  let canClaimDraw = false;
  let drawClaimInfo: any = null;
  if (!gameEnd) {
    try {
      drawClaimInfo = await serviceRpc("_chess_can_claim_draw", { _game_id: game_id });
      canClaimDraw = drawClaimInfo?.can_claim || false;
    } catch { /* ignore */ }
  }

  // 7. Vérifier l'état du roi (échec)
  const inCheck = chess.inCheck();
  const opponentInCheck = chess.inCheck();

  return json({
    ok: true,
    fen: fenAfter,
    san: move.san,
    turn: newTurn,
    ply: newPly,
    in_check: opponentInCheck,
    game_end: gameEnd,
    can_claim_draw: canClaimDraw,
    draw_info: drawClaimInfo,
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

  if (reason === "timeout") {
    // Vérifier le timeout côté serveur
    const now = Date.now();
    const lastMove = game.last_move_at || game.started_at;
    const elapsed = now - new Date(lastMove).getTime();
    const moverTime = game.turn === "w" ? game.white_time_ms : game.black_time_ms;
    const moverColor = game.turn;
    const winnerColor = moverColor === "w" ? "b" : "w";
    const realWinner = winnerColor === "w" ? game.white_id : game.black_id;

    if (moverTime > 0 && elapsed < moverTime) {
      // Le joueur a encore du temps — vérifier le temps global
      if (game.game_deadline && now < new Date(game.game_deadline).getTime()) {
        return json({ error: "timeout not reached yet" }, 400);
      }
    }

    // Vérifier si l'adversaire a assez de matériel pour mater
    // via la fonction SQL _chess_has_mating_material
    const gameFen = game.fen;
    let winnerHasMaterial = true;
    try {
      const matResult = await serviceRpc("_chess_has_mating_material", { _fen: gameFen, _color: winnerColor });
      winnerHasMaterial = matResult === true || matResult?.result === true || matResult === true;
    } catch { /* default to true if check fails */ }

    if (winnerHasMaterial) {
      await serviceRpc("_chess_settle", { _id: game_id, _winner: realWinner, _draw: false, _reason: "timeout" });
      return json({ ok: true, winner: realWinner, draw: false, reason: "timeout" });
    } else {
      // L'adversaire ne peut pas mater → nulle
      await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "timeout_insufficient_material" });
      return json({ ok: true, winner: null, draw: true, reason: "timeout_insufficient_material" });
    }
  }

  // Pour checkmate/stalemate/draw — valider avec chess.js
  const patchedFen = patchFenFor50Move(game.fen);
  const chess = new Chess(patchedFen);

  // Ne pas utiliser isGameOver() car il inclut 50-move et threefold (réclamables)
  // Vérifier uniquement les fins automatiques
  if (chess.isCheckmate()) {
    const realWinner = chess.turn() === "w" ? game.black_id : game.white_id;
    if (!realWinner || winner !== realWinner) {
      return json({ error: "winner mismatch" }, 400);
    }
    await serviceRpc("_chess_settle", { _id: game_id, _winner: realWinner, _draw: false, _reason: "checkmate" });
    return json({ ok: true, winner: realWinner, draw: false, reason: "checkmate" });
  }

  if (chess.isStalemate()) {
    await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "stalemate" });
    return json({ ok: true, winner: null, draw: true, reason: "stalemate" });
  }

  if (chess.isInsufficientMaterial()) {
    await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "insufficient_material" });
    return json({ ok: true, winner: null, draw: true, reason: "insufficient_material" });
  }

  // Vérifier 75 coups et 5x répétition (automatiques)
  const halfmove = getHalfmoveClock(game.fen);
  if (halfmove >= 150) {
    await serviceRpc("_chess_settle", { _id: game_id, _winner: null, _draw: true, _reason: "seventyfive_move_rule" });
    return json({ ok: true, winner: null, draw: true, reason: "seventyfive_move_rule" });
  }

  // Pour les fins réclamables (50 coups, triple répétition), utiliser claim_draw
  return json({ error: "game not over (use claim_draw for claimable draws)" }, 400);
}
