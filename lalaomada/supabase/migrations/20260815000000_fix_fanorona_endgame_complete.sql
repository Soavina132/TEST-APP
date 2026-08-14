-- ═════════════════════════════════════════════════════════════════
-- FIX: Fanorona endgame — tous les cas de fin de partie
-- Date: 2026-08-15
--
-- 1. Timeout pour parties en 'drawing' (color selection)
-- 2. Timeout pour parties en 'open' (stake bloqué)
-- 3. Bot pass quand pas de mouvement légal (hors chaîne)
-- 4. Expiration automatique du draw offer
-- ═════════════════════════════════════════════════════════════════

-- =========================================================
-- FIX 1: fanorona_tick_all — gérer 'drawing' et 'open'
-- =========================================================
CREATE OR REPLACE FUNCTION public.fanorona_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
  cur_uid uuid;
  winner_slot int;
  v_total int;
  v_ready int;
  v_stake numeric;
BEGIN
  FOR g IN SELECT id, current_turn, turn_deadline, game_deadline, status,
                  created_at, started_at, stake, draw_white_by, draw_black_by
           FROM public.fanorona_games
           WHERE status IN ('playing', 'drawing', 'open')
  LOOP
    -- ── STATUT 'open' : timeout si > 5 minutes sans les 2 joueurs ready ──
    IF g.status = 'open' THEN
      -- Si la partie est ouverte depuis plus de 10 minutes, rembourser et annuler
      IF g.created_at < now() - interval '10 minutes' THEN
        -- Rembourser le stake à tous les participants
        FOR cur_uid IN SELECT user_id FROM public.fanorona_participants WHERE game_id = g.id AND user_id IS NOT NULL LOOP
          UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = cur_uid;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (cur_uid, 'fanorona_refund', g.stake, g.id, 'Game timeout (open too long)');
        END LOOP;
        UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
      END IF;
      CONTINUE;
    END IF;

    -- ── STATUT 'drawing' : timeout si > 2 minutes sans spin ──
    IF g.status = 'drawing' THEN
      -- Si les couleurs sont choisies mais personne n'a spin après 2 min
      IF g.draw_white_by IS NOT NULL AND g.draw_black_by IS NOT NULL THEN
        IF g.started_at IS NOT NULL AND g.started_at < now() - interval '2 minutes' THEN
          -- Auto-spin: choisir une couleur aléatoirement
          UPDATE public.fanorona_games
             SET draw_result_color = CASE WHEN (extract(epoch FROM now())::int % 2) = 0 THEN 'w' ELSE 'b' END,
                 draw_revealed_at = now()
           WHERE id = g.id AND draw_result_color IS NULL;
          -- Finaliser le drawing
          PERFORM public.fanorona_draw_finalize(g.id);
        END IF;
      ELSE
        -- Si les couleurs ne sont pas choisies après 5 min, annuler
        IF g.started_at IS NOT NULL AND g.started_at < now() - interval '5 minutes' THEN
          FOR cur_uid IN SELECT user_id FROM public.fanorona_participants WHERE game_id = g.id AND user_id IS NOT NULL LOOP
            UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = cur_uid;
            INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
              VALUES (cur_uid, 'fanorona_refund', g.stake, g.id, 'Game timeout (drawing)');
          END LOOP;
          UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
        END IF;
      END IF;
      CONTINUE;
    END IF;

    -- ── STATUT 'playing' ──

    -- 1. Turn timeout
    IF g.turn_deadline IS NOT NULL AND g.turn_deadline <= now() THEN
      SELECT user_id INTO cur_uid FROM public.fanorona_participants
        WHERE game_id = g.id AND slot = g.current_turn;
      -- Forfeit le joueur (humain seulement — bots user_id IS NULL)
      IF cur_uid IS NOT NULL THEN
        UPDATE public.fanorona_participants SET forfeited = true
          WHERE game_id = g.id AND user_id = cur_uid;
      END IF;
      -- L'adversaire gagne
      winner_slot := 1 - g.current_turn;
      PERFORM public._fanorona_finalize(g.id, winner_slot);
      CONTINUE;
    END IF;

    -- 2. Global timeout
    IF g.game_deadline IS NOT NULL AND g.game_deadline <= now() THEN
      winner_slot := 1 - g.current_turn;
      PERFORM public._fanorona_finalize(g.id, winner_slot);
      CONTINUE;
    END IF;

    -- 3. Bot bloqué (tour du bot mais le frontend n'est pas là)
    IF g.turn_deadline IS NOT NULL AND g.turn_deadline > now() THEN
      BEGIN
        PERFORM public.fanorona_bot_play(g.id);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END LOOP;
END $function$;

-- =========================================================
-- FIX 2: fanorona_play_as_bot — gérer le pass hors chaîne
-- Le bot peut passer quand il n'a aucun mouvement légal, même hors chaîne
-- =========================================================
CREATE OR REPLACE FUNCTION public.fanorona_play_as_bot(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; bot_exists boolean;
  my_slot int; my_color int; opp_color int;
  st jsonb; board jsonb;
  from_idx int; to_idx int;
  fr int; fc int; tr int; tc int; dr int; dc int;
  cap jsonb;
  opp_left int; next_turn int;
  is_pass boolean;
  move_count int;
  visited jsonb; last_axis text; axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
  no_cap int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  my_slot := g.current_turn;

  SELECT COALESCE(fp.is_bot, false) INTO bot_exists
    FROM public.fanorona_participants fp
    WHERE fp.game_id = _game_id AND fp.slot = my_slot;
  IF NOT bot_exists THEN RETURN; END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN my_slot = 0 THEN 2 ELSE 1 END;
  st := g.state; board := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited := COALESCE(st->'visited', '[]'::jsonb);
  last_axis := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  no_cap := COALESCE((st->>'no_capture_moves')::int, 0);

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  IF is_pass THEN
    -- FIX: Allow pass even outside chain when bot has no legal moves
    IF chain_from_v IS NULL THEN
      -- Check if bot genuinely has no legal moves
      IF public._fanorona_player_has_move(board, my_color, v_cols, v_rows) THEN
        RETURN; -- Bot has moves, don't pass
      END IF;
      -- Bot has no moves: pass to opponent (stalemate)
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}', '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap + 1), true);
      UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
        turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
        WHERE id = _game_id;
      -- If opponent also has no moves, bot wins (stalemate)
      IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
        PERFORM public._fanorona_finalize(_game_id, my_slot);
      END IF;
      -- Draw by 20 moves without capture
      IF (no_cap + 1) >= 20
         AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
         AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
        PERFORM public._fanorona_draw_refund(_game_id);
      END IF;
      RETURN;
    END IF;
    -- Normal chain-ending pass
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}', '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap + 1), true);
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot);
    END IF;
    IF (no_cap + 1) >= 20
       AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
       AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_draw_refund(_game_id);
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
  IF ((fr + fc) % 2 <> 0) AND (dr <> 0 AND dc <> 0) THEN
    RAISE EXCEPTION 'diagonal not allowed here';
  END IF;
  axis := public._fanorona_axis(dr, dc);
  IF chain_from_v IS NOT NULL THEN
    IF visited @> to_jsonb(to_idx) THEN RAISE EXCEPTION 'cannot revisit cell'; END IF;
    IF last_axis IS NOT NULL AND axis = last_axis THEN
      RAISE EXCEPTION 'cannot continue on same axis';
    END IF;
  END IF;

  -- Validation capture
  DECLARE lists jsonb; BEGIN
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
  END;

  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  IF jsonb_array_length(cap) > 0 THEN no_cap := 0; ELSE no_cap := no_cap + 1; END IF;
  st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap), true);

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}', '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}', '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}', 'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}',    visited);
        st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
      ELSE
        next_turn := 1 - my_slot;
        st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
        st := jsonb_set(st, '{visited}',    '[]'::jsonb);
        st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
        st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      END IF;
    END IF;
  END IF;

  UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot); RETURN;
  END IF;

  IF no_cap >= 20
     AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
     AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_draw_refund(_game_id); RETURN;
  END IF;

  IF next_turn = my_slot THEN
    PERFORM public.fanorona_bot_play(_game_id);
  END IF;
END $function$;

-- =========================================================
-- FIX 3: Expiration automatique du draw offer
-- Le draw offer expire après 30 secondes s'il n'est pas accepté
-- =========================================================

-- Ajouter une colonne pour tracker quand le draw a été offert
ALTER TABLE public.fanorona_games ADD COLUMN IF NOT EXISTS draw_offered_at timestamp with time zone;

-- Mettre à jour fanorona_request_or_accept_draw pour tracker le timestamp
CREATE OR REPLACE FUNCTION public.fanorona_request_or_accept_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_status text; v_offered uuid; v_offered_at timestamp with time zone;
BEGIN
  SELECT status, draw_offered_by, draw_offered_at INTO v_status, v_offered, v_offered_at
    FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) THEN RETURN; END IF;

  -- Vérifier si le draw offer a expiré (> 30 secondes)
  IF v_offered IS NOT NULL AND v_offered_at IS NOT NULL
     AND v_offered_at < now() - interval '30 seconds' THEN
    -- Le draw offer a expiré, le réinitialiser
    v_offered := NULL;
    UPDATE public.fanorona_games SET draw_offered_by = NULL, draw_offered_at = NULL WHERE id = _game_id;
  END IF;

  IF v_offered IS NULL THEN
    -- Première demande de nulle
    UPDATE public.fanorona_games
      SET draw_offered_by = v_uid, draw_offered_at = now(), updated_at = now()
      WHERE id = _game_id;
  ELSIF v_offered <> v_uid THEN
    -- L'adversaire accepte → remboursement et fin
    PERFORM public._fanorona_draw_refund(_game_id);
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fanorona_request_or_accept_draw(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fanorona_request_or_accept_draw(uuid) TO authenticated;

-- =========================================================
-- FIX 4: Expiration du draw offer dans fanorona_tick_all
-- (déjà géré dans la fonction ci-dessus via le check au moment
--  de l'acceptation, mais on ajoute aussi un nettoyage dans
--  fanorona_play pour que l'expiration soit visible côté frontend)
-- =========================================================

-- Mettre à jour fanorona_play pour nettoyer le draw offer expiré
-- quand un joueur joue un coup
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int; my_color int; opp_color int;
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
  no_cap int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  -- Clear expired draw offer when a player plays
  IF g.draw_offered_by IS NOT NULL AND g.draw_offered_at IS NOT NULL
     AND g.draw_offered_at < now() - interval '30 seconds' THEN
    UPDATE public.fanorona_games SET draw_offered_by = NULL, draw_offered_at = NULL WHERE id = _game_id;
  ELSIF g.draw_offered_by IS NOT NULL AND g.draw_offered_by <> v_uid THEN
    -- Clear draw offer when the non-offering player plays
    UPDATE public.fanorona_games SET draw_offered_by = NULL, draw_offered_at = NULL WHERE id = _game_id;
  END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN my_slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN my_slot = 0 THEN 2 ELSE 1 END;
  st        := g.state;
  board     := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited    := COALESCE(st->'visited', '[]'::jsonb);
  last_axis  := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;
  no_cap := COALESCE((st->>'no_capture_moves')::int, 0);

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  IF is_pass THEN
    IF chain_from_v IS NULL
       AND public._fanorona_player_has_move(board, my_color, v_cols, v_rows) THEN
      RAISE EXCEPTION 'cannot pass when you have legal moves';
    END IF;
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap + 1), true);
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize(_game_id, my_slot);
    END IF;
    IF (no_cap + 1) >= 20
       AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
       AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_draw_refund(_game_id);
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

  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  IF jsonb_array_length(cap) > 0 THEN no_cap := 0; ELSE no_cap := no_cap + 1; END IF;
  st := jsonb_set(st, '{no_capture_moves}', to_jsonb(no_cap), true);

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}',    visited);
        st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
      ELSE
        next_turn := 1 - my_slot;
        st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
        st := jsonb_set(st, '{visited}',    '[]'::jsonb);
        st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
        st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      END IF;
    END IF;
  END IF;

  UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
    WHERE id = _game_id;

  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  IF no_cap >= 20
     AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
     AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_draw_refund(_game_id);
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public.fanorona_play(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.fanorona_play(uuid, jsonb) TO authenticated;
