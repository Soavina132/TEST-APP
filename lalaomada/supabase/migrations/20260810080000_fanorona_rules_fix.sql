-- ============================================================
-- Migration: Fanorona — Corrections des règles + draw offer
--
-- Bugs corrigés:
-- 1. Règle "premier coup = une seule capture" (move_count=0) perdue
-- 2. Pass autorisé hors rafale (permet de zapper son tour)
-- 3. Pat (adversaire ne peut plus bouger) = VICTOIRE au lieu de MATCH NUL
--
-- Nouvelles fonctionnalités:
-- 4. Colonne draw_offered_by + result sur fanorona_games
-- 5. Fonction fanorona_request_or_accept_draw corrigée
-- 6. Fonction fanorona_decline_draw ajoutée
-- ============================================================

-- 1) Ajouter les colonnes manquantes pour le draw offer et le result
ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS result text,
  ADD COLUMN IF NOT EXISTS draw_offered_by uuid;

-- 2) Fonction de finalisation par match nul (pat)
CREATE OR REPLACE FUNCTION public._fanorona_finalize_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g record;
  p1_uid uuid; p2_uid uuid;
  payout numeric;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  -- Remboursement: chaque joueur récupère sa mise (pot / 2)
  payout := g.pot / 2;
  SELECT user_id INTO p1_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = 0;
  SELECT user_id INTO p2_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = 1;

  IF p1_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = p1_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (p1_uid, 'fanorona_draw', payout, _game_id, 'Fanorona draw refund');
  END IF;
  IF p2_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = p2_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (p2_uid, 'fanorona_draw', payout, _game_id, 'Fanorona draw refund');
  END IF;

  UPDATE public.fanorona_games
    SET status = 'finished', result = 'draw', draw_offered_by = NULL,
        finished_at = now(), updated_at = now()
    WHERE id = _game_id;
END $$;

-- 3) Corriger fanorona_request_or_accept_draw (status = 'playing' et non 'active')
CREATE OR REPLACE FUNCTION public.fanorona_request_or_accept_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text; v_offered uuid;
  v_is_bot boolean;
BEGIN
  SELECT status, draw_offered_by INTO v_status, v_offered
    FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;

  -- Pas de draw offer contre un bot
  SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND is_bot = true) INTO v_is_bot;
  IF v_is_bot THEN RETURN; END IF;

  IF v_offered IS NULL THEN
    UPDATE public.fanorona_games SET draw_offered_by = v_uid, updated_at = now() WHERE id = _game_id;
  ELSIF v_offered <> v_uid THEN
    -- L'adversaire accepte → match nul
    PERFORM public._fanorona_finalize_draw(_game_id);
  END IF;
END $$;

-- 4) Fonction pour refuser le draw
CREATE OR REPLACE FUNCTION public.fanorona_decline_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  UPDATE public.fanorona_games
    SET draw_offered_by = NULL, updated_at = now()
    WHERE id = _game_id AND draw_offered_by IS NOT NULL AND draw_offered_by <> v_uid;
END $$;

GRANT EXECUTE ON FUNCTION public._fanorona_finalize_draw(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_request_or_accept_draw(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_decline_draw(uuid) TO authenticated;

-- 5) Corriger _fanorona_play_by_slot avec les 3 bugs
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
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF g.current_turn <> _slot THEN RAISE EXCEPTION 'not your turn'; END IF;

  -- Annuler un draw offer en cours quand un coup est joué
  IF g.draw_offered_by IS NOT NULL THEN
    UPDATE public.fanorona_games SET draw_offered_by = NULL WHERE id = _game_id;
  END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN _slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN _slot = 0 THEN 2 ELSE 1 END;

  -- Calculer le temps écoulé
  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now())))::int * 1000);

  IF _slot = 0 THEN
    v_new_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
  ELSE
    v_new_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
  END IF;

  -- Flag fall
  IF v_new_time_ms <= 0 THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
    RETURN;
  END IF;

  st        := g.state;
  board     := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited    := COALESCE(st->'visited', '[]'::jsonb);
  last_axis  := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  -- BUG FIX 2: Pass autorisé UNIQUEMENT pendant une rafale (chain_from non null)
  IF is_pass THEN
    IF chain_from_v IS NULL THEN
      RAISE EXCEPTION 'can only end turn during a capture chain';
    END IF;
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    UPDATE public.fanorona_games SET
      state = st,
      current_turn = next_turn,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    -- BUG FIX 3: Pat = match nul, pas victoire
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize_draw(_game_id);
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

  -- Appliquer le coup
  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  -- Victoire par capture totale
  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
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
    -- Coup simple sans capture: le tour passe
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    -- Capture: vérifier si on peut enchaîner
    visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);

    -- BUG FIX 1: Au premier coup du jeu (move_count = 0), une seule capture autorisée
    IF move_count = 0 THEN
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSIF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
      next_turn := _slot;
      st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
      st := jsonb_set(st, '{visited}',    visited);
      st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
    ELSE
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    END IF;
  END IF;

  UPDATE public.fanorona_games SET
    state = st,
    current_turn = next_turn,
    last_move_at = now(),
    white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
    black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
    turn_deadline = CASE WHEN next_turn = _slot THEN turn_deadline ELSE
      now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval END
    WHERE id = _game_id;

  -- BUG FIX 3: Vérifier le pat (adversaire ne peut plus bouger) après CHAQUE changement de tour
  IF next_turn <> _slot AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize_draw(_game_id);
  END IF;
END $function$;
