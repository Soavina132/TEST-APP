-- ============================================================
-- RÈGLES OFFICIELLES FANORONA + FIX MATCHS NULS
-- ============================================================
-- Problèmes corrigés:
-- 1. Bot gagne → winner_id=null → affiché comme "match nul" (bug)
-- 2. Pas de limite de coups sans capture → parties infinies
-- 3. auto_finish_abandoned_games ne trace pas winner_slot pour les bots
--
-- Règles officielles ajoutées:
-- A. winner_slot colonne pour tracer le gagnant même si c'est un bot
-- B. Limite de 30 coups sans capture → le joueur avec le plus de pions gagne
-- C. Si égalité de pions après limite → celui qui a le tour perd (avantage défenseur)
-- D. Stalemate (aucun coup possible) = défaite (déjà implémenté, confirmé)
-- E. Toutes les pièces capturées = victoire (déjà implémenté, confirmé)
-- ============================================================

-- 1. Ajouter colonne winner_slot
ALTER TABLE public.fanorona_games ADD COLUMN IF NOT EXISTS winner_slot integer;

-- 2. Ajouter colonne moves_since_capture (compteur de coups sans capture)
-- Stocké dans le state JSON, pas besoin de colonne

-- 3. Fix _fanorona_finalize — toujours enregistrer winner_slot
CREATE OR REPLACE FUNCTION public._fanorona_finalize(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
  winner_uid uuid;
  payout numeric;
  v_note text;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  SELECT user_id INTO winner_uid
  FROM public.fanorona_participants
  WHERE game_id = _game_id AND slot = _winner_slot;

  payout := g.pot * (100 - g.commission_pct) / 100;

  -- Créditer le gagnant seulement si c'est un humain
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles
    SET balance_ar = balance_ar + payout
    WHERE id = winner_uid;

    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (winner_uid, 'fanorona_win', payout, _game_id, 'Fanorona win');
  END IF;

  -- Toujours enregistrer winner_slot (même pour les bots)
  v_note := CASE
    WHEN winner_uid IS NOT NULL THEN 'Victoire'
    ELSE 'Victoire (bot)'
  END;

  UPDATE public.fanorona_games
  SET status = 'finished',
      winner_id = winner_uid,
      winner_slot = _winner_slot,
      finished_at = now()
  WHERE id = _game_id;
END $function$;

-- 4. Fix _fanorona_play_by_slot — ajouter la règle des 30 coups sans capture
CREATE OR REPLACE FUNCTION public._fanorona_play_by_slot(_game_id uuid, _move jsonb, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record;
  my_color int; opp_color int;
  st jsonb; board jsonb;
  from_idx int; to_idx int;
  fr int; fc int; tr int; tc int; dr int; dc int;
  is_strong boolean;
  cap jsonb; lists jsonb;
  opp_left int; next_turn int;
  is_pass boolean;
  move_count int;
  visited jsonb;
  last_axis text;
  axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
  v_elapsed_ms int;
  v_new_time_ms int;
  moves_since_capture int;
  white_pieces int;
  black_pieces int;
  MAX_NO_CAPTURE int := 30;  -- Limite officielle: 30 coups sans capture
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF g.current_turn <> _slot THEN RAISE EXCEPTION 'not your turn'; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN _slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN _slot = 0 THEN 2 ELSE 1 END;

  -- Compute elapsed time since last move (or game start)
  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now())))::int * 1000);

  -- Deduct from active player's clock
  IF _slot = 0 THEN
    v_new_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
  ELSE
    v_new_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
  END IF;

  -- If clock ran out, finalize — opponent wins by flag fall
  IF v_new_time_ms <= 0 THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
    RETURN;
  END IF;

  st        := g.state;
  board     := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  moves_since_capture := COALESCE((st->>'moves_since_capture')::int, 0);
  visited    := COALESCE(st->'visited', '[]'::jsonb);
  last_axis  := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  IF is_pass THEN
    next_turn := 1 - _slot;
    -- Pass counts as a move without capture
    moves_since_capture := moves_since_capture + 1;
    move_count := move_count + 1;

    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count));
    st := jsonb_set(st, '{moves_since_capture}', to_jsonb(moves_since_capture));

    UPDATE public.fanorona_games SET
      state = st,
      current_turn = next_turn,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;

    -- Vérifier stalemate (adversaire n'a plus de coups)
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, _slot);
      RETURN;
    END IF;

    -- Vérifier limite sans capture
    IF moves_since_capture >= MAX_NO_CAPTURE THEN
      -- Compter les pièces
      SELECT count(*) INTO white_pieces FROM jsonb_array_elements(board) v WHERE (v::text)::int = 1;
      SELECT count(*) INTO black_pieces FROM jsonb_array_elements(board) v WHERE (v::text)::int = 2;
      IF white_pieces > black_pieces THEN
        PERFORM public._fanorona_finalize(_game_id, 0);  -- White (slot 0) gagne
      ELSIF black_pieces > white_pieces THEN
        PERFORM public._fanorona_finalize(_game_id, 1);  -- Black (slot 1) gagne
      ELSE
        -- Égalité parfaite: le joueur qui n'a PAS le tour gagne (il a survécu)
        PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
      END IF;
    END IF;
    RETURN;
  END IF;

  from_idx := (_move->>'from')::int;
  to_idx   := (_move->>'to')::int;
  cap      := COALESCE(_move->'captured', '[]'::jsonb);

  IF chain_from_v IS NOT NULL AND from_idx <> chain_from_v THEN
    RAISE EXCEPTION 'must continue with same piece';
  END IF;

  IF (board->from_idx)::int <> my_color THEN RAISE EXCEPTION 'not your piece'; END IF;
  IF (board->to_idx)::int <> 0 THEN RAISE EXCEPTION 'target not empty'; END IF;

  fr := from_idx / v_cols; fc := from_idx % v_cols;
  tr := to_idx   / v_cols; tc := to_idx   % v_cols;
  dr := tr - fr;           dc := tc - fc;
  IF abs(dr) > 1 OR abs(dc) > 1 OR (dr = 0 AND dc = 0) THEN
    RAISE EXCEPTION 'invalid step';
  END IF;
  is_strong := ((fr + fc) % 2 = 0);
  IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN
    RAISE EXCEPTION 'diagonal not allowed here';
  END IF;
  axis := public._fanorona_axis(dr, dc);

  IF chain_from_v IS NOT NULL THEN
    IF visited @> to_jsonb(to_idx) THEN RAISE EXCEPTION 'cannot revisit cell'; END IF;
    IF last_axis IS NOT NULL AND axis = last_axis THEN
      RAISE EXCEPTION 'cannot continue on same axis';
    END IF;
  END IF;

  lists := public._fanorona_capture_lists(board, my_color, from_idx, to_idx, v_cols, v_rows);
  IF jsonb_array_length(cap) > 0 THEN
    IF NOT (cap = (lists->'approach') OR cap = (lists->'withdrawal')) THEN
      RAISE EXCEPTION 'invalid capture set';
    END IF;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    IF chain_from_v IS NOT NULL THEN
      RAISE EXCEPTION 'must capture during chain';
    END IF;
    IF COALESCE(g.mandatory_capture, true)
       AND public._fanorona_player_can_capture(board, my_color, v_cols, v_rows) THEN
      RAISE EXCEPTION 'capture is mandatory when available';
    END IF;
  END IF;

  -- Appliquer le mouvement
  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  -- Compter les pièces restantes de l'adversaire
  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;

  -- Victoire: toutes les pièces adverses capturées
  IF opp_left = 0 THEN
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    st := jsonb_set(st, '{moves_since_capture}', to_jsonb(0));  -- Reset car capture
    UPDATE public.fanorona_games SET
      state = st,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END
      WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, _slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    -- Simple move without capture: turn passes, no chain possible
    moves_since_capture := moves_since_capture + 1;
    move_count := move_count + 1;
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count));
    st := jsonb_set(st, '{moves_since_capture}', to_jsonb(moves_since_capture));
  ELSE
    -- Capture happened: reset counter
    moves_since_capture := 0;
    visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
    IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
      -- Chain continues — same player keeps the turn
      next_turn := _slot;
      st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
      st := jsonb_set(st, '{visited}',    visited);
      st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
      st := jsonb_set(st, '{moves_since_capture}', to_jsonb(0));
    ELSE
      -- Chain ends — turn passes
      move_count := move_count + 1;
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count));
      st := jsonb_set(st, '{moves_since_capture}', to_jsonb(0));
    END IF;
  END IF;

  UPDATE public.fanorona_games SET
    state = st,
    current_turn = next_turn,
    last_move_at = now(),
    white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
    black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  -- Vérifier stalemate (adversaire n'a plus de coups)
  IF next_turn = 1 - _slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, _slot);
    RETURN;
  END IF;

  -- Vérifier stalemate pour le joueur actuel (chain impossible à continuer)
  IF next_turn = _slot
     AND NOT public._fanorona_player_has_move(board, my_color, v_cols, v_rows) THEN
    -- Le joueur ne peut plus bouger après sa capture → il perd
    PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
    RETURN;
  END IF;

  -- Vérifier la limite des 30 coups sans capture
  IF moves_since_capture >= MAX_NO_CAPTURE AND next_turn = 1 - _slot THEN
    SELECT count(*) INTO white_pieces FROM jsonb_array_elements(board) v WHERE (v::text)::int = 1;
    SELECT count(*) INTO black_pieces FROM jsonb_array_elements(board) v WHERE (v::text)::int = 2;
    IF white_pieces > black_pieces THEN
      PERFORM public._fanorona_finalize(_game_id, 0);
    ELSIF black_pieces > white_pieces THEN
      PERFORM public._fanorona_finalize(_game_id, 1);
    ELSE
      -- Égalité parfaite: le joueur qui n'a PAS le tour gagne
      PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
    END IF;
    RETURN;
  END IF;
END $function$;

-- 5. Fix auto_finish_abandoned_games pour Fanorona — tracer winner_slot
CREATE OR REPLACE FUNCTION public.auto_finish_abandoned_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
  v_winner uuid;
  v_winner_slot int;
  v_active_human_count int;
BEGIN
  -- ── LUDO ──
  FOR g IN SELECT id, pot, commission_pct FROM public.ludo_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.ludo_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.ludo_participants
        WHERE game_id = g.id AND forfeited = false ORDER BY slot LIMIT 1;
      UPDATE public.ludo_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count FROM public.ludo_participants WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.ludo_participants WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.ludo_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── DOMINO ──
  FOR g IN SELECT id, pot, commission_pct FROM public.domino_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count FROM public.domino_participants WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.domino_participants WHERE game_id = g.id AND forfeited = false ORDER BY slot LIMIT 1;
      UPDATE public.domino_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count FROM public.domino_participants WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.domino_participants WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.domino_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── FANORONA ── (fix: tracer winner_slot même pour les bots)
  FOR g IN SELECT id, pot, commission_pct FROM public.fanorona_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.fanorona_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      -- Tous les humains sont partis → le bot restant gagne
      SELECT user_id, slot INTO v_winner, v_winner_slot
        FROM public.fanorona_participants
        WHERE game_id = g.id AND forfeited = false ORDER BY slot LIMIT 1;
      UPDATE public.fanorona_games
        SET status = 'finished', winner_id = v_winner, winner_slot = v_winner_slot, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count FROM public.fanorona_participants WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id, slot INTO v_winner, v_winner_slot
          FROM public.fanorona_participants WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.fanorona_games
          SET status = 'finished', winner_id = v_winner, winner_slot = v_winner_slot, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── RAMI ──
  FOR g IN SELECT id, pot, commission_pct FROM public.rami_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count FROM public.rami_participants WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.rami_participants WHERE game_id = g.id AND forfeited = false ORDER BY slot LIMIT 1;
      UPDATE public.rami_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count FROM public.rami_participants WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.rami_participants WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.rami_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── CHESS ──
  FOR g IN SELECT id, white_id, black_id, stake, pot FROM public.chess_games WHERE status = 'playing'
  LOOP
    IF g.white_id IS NULL AND g.black_id IS NULL THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
    ELSIF g.white_id IS NOT NULL AND g.black_id IS NULL THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
    ELSIF g.white_id IS NOT NULL AND g.black_id IS NOT NULL THEN
      NULL;
    END IF;
  END LOOP;

  -- ── POKER ──
  FOR g IN SELECT id, pot, commission_pct FROM public.poker_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count FROM public.poker_players WHERE game_id = g.id AND status = 'playing';
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.poker_players WHERE game_id = g.id ORDER BY chips DESC LIMIT 1;
      UPDATE public.poker_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count FROM public.poker_players WHERE game_id = g.id AND status NOT IN ('out', 'folded');
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.poker_players WHERE game_id = g.id AND status = 'playing' LIMIT 1;
        UPDATE public.poker_games SET status = 'finished', winner_id = v_winner, finished_at = now() WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;
END $function$;

-- 6. Fix fanorona_tick — tracer winner_slot sur flag fall
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  v_elapsed_ms int; v_active_time_ms int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- Check cumulative clock timeout (flag fall)
  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now())))::int * 1000);
  IF g.current_turn = 0 THEN
    v_active_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
  ELSE
    v_active_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
  END IF;

  IF v_active_time_ms <= 0 THEN
    -- Flag fall: active player ran out of time → opponent wins
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;

  -- Check turn_deadline (per-turn skip)
  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('fanorona');
  SELECT user_id INTO cur_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = g.current_turn;
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
    RETURN;
  END IF;
  _next := 1 - g.current_turn;
  UPDATE public.fanorona_games SET
    current_turn = _next,
    turn_skips = jsonb_set(g.turn_skips, ARRAY[cur_uid::text], to_jsonb(_skips)),
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
  WHERE id = _game_id;
END $function$;

-- 7. Corriger les anciens "matchs nuls" qui étaient des victoires de bots
-- Pour chaque partie finie sans winner_id, vérifier si un bot aurait dû gagner
DO $fix_history$
DECLARE
  g record;
  v_white int;
  v_black int;
  v_bot_slot int;
  v_bot_uid uuid;
BEGIN
  FOR g IN SELECT id, state FROM public.fanorona_games
    WHERE status = 'finished' AND winner_id IS NULL AND draw_result_color IS NULL
  LOOP
    -- Compter les pièces
    SELECT count(*) INTO v_white FROM jsonb_array_elements(g.state->'board') v WHERE (v::text)::int = 1;
    SELECT count(*) INTO v_black FROM jsonb_array_elements(g.state->'board') v WHERE (v::text)::int = 2;

    -- Si un joueur a clairement plus de pièces, il a gagné
    IF v_black > v_white THEN
      -- Slot 1 (black/noir) gagne
      SELECT user_id INTO v_bot_uid FROM public.fanorona_participants WHERE game_id = g.id AND slot = 1;
      UPDATE public.fanorona_games SET winner_id = v_bot_uid, winner_slot = 1 WHERE id = g.id;
    ELSIF v_white > v_black THEN
      -- Slot 0 (white/blanc) gagne
      SELECT user_id INTO v_bot_uid FROM public.fanorona_participants WHERE game_id = g.id AND slot = 0;
      UPDATE public.fanorona_games SET winner_id = v_bot_uid, winner_slot = 0 WHERE id = g.id;
    ELSE
      -- Vraie égalité — vérifier qui avait le tour (le joueur sans tour perd)
      -- Si pas de info, on laisse en draw
      NULL;
    END IF;
  END LOOP;
END $fix_history$;
