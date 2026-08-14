// Supabase Edge Function: chess-validate-move
// Valide les coups d'échecs côté serveur avec chess.js
// Empêche la triche en mode argent réel

import { Chess } from "https://esm.sh/chess.js@1.4.0";
import { corsHeaders } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function sbClient(token?: string) {
  return {
    async rpc(fn: string, params: Record<string, unknown>) {
      const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "apikey": token || SERVICE_KEY,
          "Authorization": `Bearer ${token || SERVICE_KEY}`,
        },
        body: JSON.stringify(params),
      });
      return res.json();
    },
    async from(table: string) {
      return {
        async select(cols: string) {
          const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?select=${cols}`, {
            headers: {
              "apikey": token || SERVICE_KEY,
              "Authorization": `Bearer ${token || SERVICE_KEY}`,
            },
          });
          return res.json();
        },
        async update(data: Record<string, unknown>) {
          return {
            async eq(col: string, val: string) {
              const res = await fetch(`${SUPABASE_URL}/rest/v1/${table}?${col}=eq.${val}`, {
                method: "PATCH",
                headers: {
                  "Content-Type": "application/json",
                  "apikey": token || SERVICE_KEY,
                  "Authorization": `Bearer ${token || SERVICE_KEY}`,
                },
                body: JSON.stringify(data),
              });
              return res.json();
            },
          };
        },
      };
    },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization") || "";
    const token = authHeader.replace("Bearer ", "");
    if (!token) {
      return new Response(JSON.stringify({ error: "auth required" }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const { action } = body;

    if (action === "play") {
      return await handlePlay(body, token);
    } else if (action === "finish") {
      return await handleFinish(body, token);
    } else {
      return new Response(JSON.stringify({ error: "unknown action" }), {
        status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message || "server error" }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// ── Valider et jouer un coup ──
async function handlePlay(body: any, token: string) {
  const { game_id, uci, elapsed_ms, is_bot } = body;
  if (!game_id || !uci) {
    return json({ error: "missing game_id or uci" }, 400);
  }

  // 1. Récupérer la partie depuis la DB avec le token utilisateur
  const gameRes = await fetch(`${SUPABASE_URL}/rest/v1/chess_games?id=eq.${game_id}&select=*`, {
    headers: {
      "apikey": token,
      "Authorization": `Bearer ${token}`,
    },
  });
  const games = await gameRes.json();
  if (!games || games.length === 0) {
    return json({ error: "game not found" }, 404);
  }
  const game = games[0];
  if (game.status !== "playing") {
    return json({ error: "game not active" }, 400);
  }

  // 2. Vérifier l'identité du joueur
  // Récupérer l'utilisateur
  const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "apikey": token,
      "Authorization": `Bearer ${token}`,
    },
  });
  const user = await userRes.json();
  const uid = user.id;
  if (!uid) {
    return json({ error: "auth required" }, 401);
  }

  let myColor: string;
  let botId: string | null = null;
  let botColor: string | null = null;

  if (is_bot) {
    // Bot move: vérifier que c'est bien un jeu solo et que l'utilisateur est le joueur humain
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
    // Pour un bot, c'est la couleur du bot qui doit jouer
    if (game.turn !== botColor) {
      return json({ error: "not bot turn" }, 400);
    }
  } else {
    // Human move
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

  // Parser l'UCI: from + to + promotion?
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

  // 4. Le coup est valide — mettre à jour la DB via RPC (service role)
  const fenAfter = chess.fen();
  const newTurn = game.turn === "w" ? "b" : "w";
  const moverId = is_bot ? botId : uid;
  const moverColor = is_bot ? botColor! : myColor;

  // Insérer le coup
  const insertRes = await fetch(`${SUPABASE_URL}/rest/v1/chess_moves`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify({
      game_id,
      ply: game.ply + 1,
      san: move.san,
      uci,
      fen_after: fenAfter,
      by_user: moverId,
    }),
  });

  // Mettre à jour la partie
  await fetch(`${SUPABASE_URL}/rest/v1/chess_games?id=eq.${game_id}`, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify({
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
    }),
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
    // Settle la partie via RPC
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/_chess_settle`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": SERVICE_KEY,
        "Authorization": `Bearer ${SERVICE_KEY}`,
      },
      body: JSON.stringify({ _id: game_id, _winner: winner, _draw: draw, _reason: reason }),
    });
    gameEnd = { winner, draw, reason };
  } else {
    // Vérifier règles officielles (50 coups, répétition, matériel insuffisant)
    await fetch(`${SUPABASE_URL}/rest/v1/rpc/_chess_check_game_end`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "apikey": SERVICE_KEY,
        "Authorization": `Bearer ${SERVICE_KEY}`,
      },
      body: JSON.stringify({ _game_id: game_id, _fen_after: fenAfter }),
    });
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

// ── Valider la fin de partie (checkmate/stalemate/draw) ──
async function handleFinish(body: any, token: string) {
  const { game_id, winner, draw, reason } = body;
  if (!game_id) {
    return json({ error: "missing game_id" }, 400);
  }

  // Récupérer la partie
  const gameRes = await fetch(`${SUPABASE_URL}/rest/v1/chess_games?id=eq.${game_id}&select=*`, {
    headers: {
      "apikey": token,
      "Authorization": `Bearer ${token}`,
    },
  });
  const games = await gameRes.json();
  if (!games || games.length === 0) {
    return json({ error: "game not found" }, 404);
  }
  const game = games[0];
  if (game.status !== "playing") {
    return json({ error: "game not active" }, 400);
  }

  // Vérifier l'utilisateur
  const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      "apikey": token,
      "Authorization": `Bearer ${token}`,
    },
  });
  const user = await userRes.json();
  const uid = user.id;
  if (!uid) {
    return json({ error: "auth required" }, 401);
  }
  if (uid !== game.white_id && uid !== game.black_id) {
    return json({ error: "not a participant" }, 403);
  }

  // Valider avec chess.js que la partie est réellement terminée
  const chess = new Chess(game.fen);
  if (!chess.isGameOver()) {
    return json({ error: "game not over" }, 400);
  }

  // Déterminer le vrai gagnant selon l'état du plateau
  let realWinner: string | null = null;
  let realDraw = false;
  let realReason = reason || "unknown";

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
    // Timeout ou autre raison manuelle — accepter mais valider
    if (reason === "timeout") {
      // Vérifier le timeout côté serveur
      const elapsedMs = Math.max(0, Date.now() - new Date(game.last_move_at || game.started_at).getTime());
      const remaining = game.turn === "w"
        ? game.white_time_ms - elapsedMs
        : game.black_time_ms - elapsedMs;
      if (remaining > 0 && game.time_control_min > 0) {
        return json({ error: "time not expired" }, 400);
      }
      realWinner = winner;
      realReason = "timeout";
    } else if (reason === "resign") {
      // L'abandon est accepté tel quel
      realWinner = winner;
      realReason = "resign";
    } else {
      return json({ error: "cannot finish: game not over and no valid reason" }, 400);
    }
  }

  // Settle la partie
  await fetch(`${SUPABASE_URL}/rest/v1/rpc/_chess_settle`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SERVICE_KEY,
      "Authorization": `Bearer ${SERVICE_KEY}`,
    },
    body: JSON.stringify({
      _id: game_id,
      _winner: realWinner,
      _draw: realDraw,
      _reason: realReason,
    }),
  });

  return json({ ok: true, winner: realWinner, draw: realDraw, reason: realReason });
}

function json(data: any, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
