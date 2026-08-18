-- ════════════════════════════════════════════════════════════════════
-- Système de timer compétitif pour Échecs et Fanorona
--
-- Principes :
-- 1. Serveur = source de vérité du temps (calcul via last_move_at et now())
-- 2. Le timer du joueur actif diminue pendant son tour
-- 3. À la fin du tour, le timer s'arrête et celui de l'adversaire démarre
-- 4. Si timer = 0 → défaite automatique, résultat "Victoire au temps"
-- 5. Aucun coup accepté après expiration
-- 6. Fanorona : le timer reste actif pendant les séquences de capture
--    (ne s'arrête pas entre deux captures, seulement à la fin du tour)
-- ════════════════════════════════════════════════════════════════════

-- ── 1. _fanorona_finalize : ajouter paramètre _reason ──────────────
CREATE OR REPLACE FUNCTION public._fanorona_finalize(
  _game_id uuid,
  _winner_slot int,
  _reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g record; winner_uid uuid; payout numeric;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;
  SELECT user_id INTO winner_uid FROM public.fanorona_participants
    WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'fanorona_win', payout, _game_id, 'Fanorona win');
  END IF;
  UPDATE public.fanorona_games
    SET status = 'finished',
        winner_id = winner_uid,
        winner_slot = _winner_slot,
        result = COALESCE(_reason, 'win'),
        finished_at = now(),
        turn_deadline = NULL
    WHERE id = _game_id;
END
$function$;

-- ── 2. fanorona_play : timer compétitif server-side ─────────────────
CREATE OR REPLACE FUNCTION public.fanorona_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
  -- Timer variables
  v_elapsed_ms int;
  v_remaining_ms int;
  v_time_ms int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  -- ── TIMEOUT CHECK : refuser le coup si le temps est écoulé ──
  IF g.time_control_min > 0 THEN
    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
    IF g.current_turn = 0 THEN
      v_remaining_ms := g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining_ms := g.black_time_ms - v_elapsed_ms;
    END IF;
    IF v_remaining_ms <= 0 THEN
      -- Le joueur a écoulé son temps → défaite par timeout
      PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
      RAISE EXCEPTION 'temps éculé';
    END IF;
  END IF;

  -- Clear expired draw offer
  IF g.draw_offered_by IS NOT NULL AND g.draw_offered_at IS NOT NULL
     AND g.draw_offered_at < now() - interval '30 seconds' THEN
    UPDATE public.fanorona_games SET draw_offered_by = NULL, draw_offered_at = NULL WHERE id = _game_id;
  ELSIF g.draw_offered_by IS NOT NULL AND g.draw_offered_by <> v_uid THEN
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

  -- ═══ PASS : terminer le tour ═══
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

    -- ── Timer : soustraire le temps écoulé et switcher ──
    IF g.time_control_min > 0 THEN
      v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
      IF my_slot = 0 THEN
        v_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          white_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
          WHERE id = _game_id;
      ELSE
        v_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          black_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
          WHERE id = _game_id;
      END IF;
    ELSE
      UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
        turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
        WHERE id = _game_id;
    END IF;

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

  -- ═══ MOVE : traitement normal ═══
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

  -- Apply move
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

  -- Check if opponent has no pieces left
  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET state = st WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, my_slot, 'capture_all');
    RETURN;
  END IF;

  -- Determine next turn
  IF jsonb_array_length(cap) = 0 THEN
    -- No capture → turn ends
    next_turn := 1 - my_slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  ELSE
    IF move_count = 0 THEN
      -- First move capture → turn ends (no chain on first move)
      next_turn := 1 - my_slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSE
      -- Check if chain can continue
      visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);
      IF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) THEN
        -- Chain continues → SAME player keeps the turn
        next_turn := my_slot;
        st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
        st := jsonb_set(st, '{visited}',    visited);
        st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
      ELSE
        -- Chain ends → turn switches
        next_turn := 1 - my_slot;
        st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
        st := jsonb_set(st, '{visited}',    '[]'::jsonb);
        st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
        st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
      END IF;
    END IF;
  END IF;

  -- ═══ Timer : gérer selon que le tour continue ou switch ═══
  IF next_turn = my_slot AND g.time_control_min > 0 THEN
    -- ── CHAIN CONTINUE : le timer reste actif, NE PAS toucher au clock ──
    -- last_move_at reste inchangé → le temps continue à s'écouler pour le même joueur
    UPDATE public.fanorona_games SET state = st, current_turn = next_turn
      WHERE id = _game_id;
  ELSE
    -- ── TOUR TERMINE : soustraire le temps écoulé, switcher le timer ──
    IF g.time_control_min > 0 THEN
      v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
      IF my_slot = 0 THEN
        v_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          white_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
          WHERE id = _game_id;
      ELSE
        v_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
        UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
          black_time_ms = v_time_ms,
          last_move_at = now(),
          turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
          WHERE id = _game_id;
      END IF;
    ELSE
      UPDATE public.fanorona_games SET state = st, current_turn = next_turn,
        turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
        WHERE id = _game_id;
    END IF;
  END IF;

  -- Check if opponent has no moves
  IF next_turn = 1 - my_slot
     AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_finalize(_game_id, my_slot);
    RETURN;
  END IF;

  -- Draw check
  IF no_cap >= 20
     AND NOT public._fanorona_player_can_capture(board, my_color, v_cols, v_rows)
     AND NOT public._fanorona_player_can_capture(board, opp_color, v_cols, v_rows) THEN
    PERFORM public._fanorona_draw_refund(_game_id);
  END IF;
END
$function$;
REVOKE ALL ON FUNCTION public.fanorona_play(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_play(uuid, jsonb) TO authenticated;

-- ── 3. fanorona_tick : passer 'timeout' comme raison ────────────────
CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record;
  cur_uid uuid;
  v_elapsed_ms int;
  v_remaining int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(g.paused, false) THEN RETURN; END IF;

  -- ── A. Turn deadline expiré (timer par tour) ──
  IF g.turn_deadline IS NOT NULL AND g.turn_deadline <= now() THEN
    SELECT user_id INTO cur_uid FROM public.fanorona_participants
      WHERE game_id = _game_id AND slot = g.current_turn;
    IF cur_uid IS NOT NULL THEN
      UPDATE public.fanorona_participants SET forfeited = true
        WHERE game_id = _game_id AND user_id = cur_uid;
    END IF;
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
    RETURN;
  END IF;

  -- ── B. Horloge cumulative expirée (white_time_ms / black_time_ms) ──
  IF g.time_control_min > 0 THEN
    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
    IF g.current_turn = 0 THEN
      v_remaining := g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining := g.black_time_ms - v_elapsed_ms;
    END IF;
    IF v_remaining <= 0 THEN
      PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
      RETURN;
    END IF;
  END IF;

  -- ── C. Global game deadline expiré ──
  IF g.game_deadline IS NOT NULL AND g.game_deadline <= now() THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn, 'timeout');
    RETURN;
  END IF;
END
$function$;

-- ── 4. fanorona_create : ajouter paramètre _time_min ────────────────
CREATE OR REPLACE FUNCTION public.fanorona_create(
  _stake numeric DEFAULT 0,
  _private boolean DEFAULT false,
  _commission numeric DEFAULT 10,
  _variant text DEFAULT 'tsivy',
  _mandatory_capture boolean DEFAULT true,
  _time_min integer DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
  v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _commission IS NULL OR _commission < 0 OR _commission > 50 THEN
    RAISE EXCEPTION 'invalid commission';
  END IF;
  -- Valider le time control : 1, 3, 5, 7, 10, 15 min ou 0 (illimité)
  IF _time_min NOT IN (0, 1, 3, 5, 7, 10, 15) THEN
    _time_min := 10;
  END IF;
  v_time_ms := _time_min * 60 * 1000;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  IF _private THEN v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6)); END IF;

  INSERT INTO public.fanorona_games(
    host_id, stake, pot, commission_pct, is_private, room_code, state,
    time_control_min, white_time_ms, black_time_ms
  ) VALUES (
    v_uid, _stake, _stake, _commission, _private, v_code,
    jsonb_build_object('phase','waiting','board', public._fanorona_init_board(), 'chain_from', null, 'chain_dirs', '[]'::jsonb),
    _time_min, v_time_ms, v_time_ms
  ) RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'fanorona_stake', -_stake, v_id, 'Create fanorona');
  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name) VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Player'));
  RETURN v_id;
END
$function$;
REVOKE ALL ON FUNCTION public.fanorona_create(numeric, boolean, numeric, text, boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_create(numeric, boolean, numeric, text, boolean, integer) TO authenticated;

-- ── 5. fanorona_start_solo_bot : ajouter _time_min + last_move_at ───
CREATE OR REPLACE FUNCTION public.fanorona_start_solo_bot(
  _variant text DEFAULT 'tsivy',
  _difficulty text DEFAULT 'medium',
  _mandatory_capture boolean DEFAULT true,
  _time_min integer DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_name text; v_id uuid;
  v_cols int; v_rows int;
  v_intel int;
  v_bot_name text;
  v_time_ms int;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  -- Valider le time control
  IF _time_min NOT IN (0, 1, 3, 5, 7, 10, 15) THEN
    _time_min := 10;
  END IF;
  v_time_ms := _time_min * 60 * 1000;

  CASE _variant
    WHEN 'telo'  THEN v_cols := 3; v_rows := 3;
    WHEN 'dimy'  THEN v_cols := 5; v_rows := 5;
    WHEN 'tsivy' THEN v_cols := 9; v_rows := 5;
    ELSE v_cols := 9; v_rows := 5; _variant := 'tsivy';
  END CASE;
  v_intel := CASE lower(COALESCE(_difficulty,'medium'))
                WHEN 'easy' THEN 1 WHEN 'hard' THEN 3 ELSE 2 END;
  v_bot_name := CASE v_intel WHEN 1 THEN 'Bot Facile'
                             WHEN 3 THEN 'Bot Difficile'
                             ELSE 'Bot Moyen' END;

  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.fanorona_games(
    host_id, stake, pot, commission_pct, is_private, room_code, state,
    cols, rows, variant, mandatory_capture,
    time_control_min, white_time_ms, black_time_ms,
    status, current_turn, started_at, last_move_at, turn_deadline
  ) VALUES (
    v_uid, 0, 0, 0, false, NULL,
    jsonb_build_object('phase','playing','board', public._fanorona_init_board(v_cols, v_rows),
                       'chain_from', null, 'visited', '[]'::jsonb,
                       'last_axis', null, 'move_count', 0),
    v_cols, v_rows, _variant, COALESCE(_mandatory_capture, true),
    _time_min, v_time_ms, v_time_ms,
    'playing', 0, now(), now(),
    now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
  ) RETURNING id INTO v_id;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Vous'), true);
  INSERT INTO public.fanorona_participants(
    game_id, user_id, slot, color, display_name, ready, is_bot, bot_intelligence, bot_name
  ) VALUES (
    v_id, NULL, 1, 'black', v_bot_name, true, true, v_intel, v_bot_name
  );

  RETURN v_id;
END
$function$;
REVOKE ALL ON FUNCTION public.fanorona_start_solo_bot(text, text, boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_start_solo_bot(text, text, boolean, integer) TO authenticated;

-- ── 6. fanorona_create_solo : ajouter _time_min ──────────────────────
CREATE OR REPLACE FUNCTION public.fanorona_create_solo(
  _variant text DEFAULT 'tsivy',
  _mandatory_capture boolean DEFAULT true,
  _bot_intelligence integer DEFAULT 2,
  _time_min integer DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_name text; v_id uuid;
  v_bot_name text;
  v_time_ms int;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _time_min NOT IN (0, 1, 3, 5, 7, 10, 15) THEN
    _time_min := 10;
  END IF;
  v_time_ms := _time_min * 60 * 1000;

  v_bot_name := CASE _bot_intelligence WHEN 1 THEN 'Bot Facile'
                                        WHEN 3 THEN 'Bot Difficile'
                                        ELSE 'Bot Moyen' END;
  SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.fanorona_games(
    host_id, stake, pot, commission_pct, is_private, room_code, state,
    time_control_min, white_time_ms, black_time_ms,
    status, current_turn, started_at, last_move_at, turn_deadline
  ) VALUES (
    v_uid, 0, 0, 0, false, NULL,
    jsonb_build_object('phase','playing','board', public._fanorona_init_board(),
                       'chain_from', null, 'visited', '[]'::jsonb,
                       'last_axis', null, 'move_count', 0),
    _time_min, v_time_ms, v_time_ms,
    'playing', 0, now(), now(),
    now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')), 60) || ' seconds')::interval
  ) RETURNING id INTO v_id;

  INSERT INTO public.fanorona_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_id, v_uid, 0, 'white', COALESCE(v_name,'Vous'), true);
  INSERT INTO public.fanorona_participants(
    game_id, user_id, slot, color, display_name, ready, is_bot, bot_intelligence, bot_name
  ) VALUES (
    v_id, NULL, 1, 'black', v_bot_name, true, true, _bot_intelligence, v_bot_name
  );

  RETURN v_id;
END
$function$;
REVOKE ALL ON FUNCTION public.fanorona_create_solo(text, boolean, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_create_solo(text, boolean, integer, integer) TO authenticated;

-- ── 7. _chess_apply_move : timer server-side (source de vérité) ─────
CREATE OR REPLACE FUNCTION public._chess_apply_move(
  _game_id uuid,
  _san text,
  _uci text,
  _fen_after text,
  _turn text,
  _by_user uuid,
  _mover_color text,
  _elapsed_ms integer DEFAULT NULL,
  _clear_draw_offer uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g record;
  new_ply int;
  v_elapsed_ms int;
  v_remaining_ms int;
BEGIN
  -- Lock the game row
  SELECT * INTO g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  -- ── TIMEOUT CHECK : refuser si le temps est écoulé ──
  IF g.time_control_min > 0 THEN
    v_elapsed_ms := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now()))) * 1000)::int);
    IF _mover_color = 'w' THEN
      v_remaining_ms := g.white_time_ms - v_elapsed_ms;
    ELSE
      v_remaining_ms := g.black_time_ms - v_elapsed_ms;
    END IF;
    IF v_remaining_ms <= 0 THEN
      -- Le joueur a écoulé son temps → défaite par timeout
      PERFORM public.chess_auto_timeout(_game_id);
      RAISE EXCEPTION 'temps écoulé';
    END IF;
  END IF;

  new_ply := g.ply + 1;

  -- Insert the move
  INSERT INTO chess_moves (game_id, ply, san, uci, fen_after, by_user)
  VALUES (_game_id, new_ply, _san, _uci, _fen_after, _by_user);

  -- ── Timer : soustraire le temps écoulé calculé PAR LE SERVEUR ──
  -- v_elapsed_ms est déjà calculé ci-dessus depuis last_move_at
  UPDATE chess_games SET
    fen = _fen_after,
    turn = _turn,
    ply = new_ply,
    last_move_at = now(),
    white_time_ms = CASE WHEN _mover_color = 'w' THEN GREATEST(0, g.white_time_ms - v_elapsed_ms) ELSE g.white_time_ms END,
    black_time_ms = CASE WHEN _mover_color = 'b' THEN GREATEST(0, g.black_time_ms - v_elapsed_ms) ELSE g.black_time_ms END,
    draw_offered_by = CASE WHEN _clear_draw_offer IS NOT NULL AND _clear_draw_offer = g.draw_offered_by THEN NULL ELSE g.draw_offered_by END
  WHERE id = _game_id;

  RETURN jsonb_build_object('ply', new_ply);
END
$function$;

-- ── 8. chess_set_ready : set last_move_at + initialize clocks ──────
CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean DEFAULT true)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.chess_games%ROWTYPE;
  v_cfg record;
  v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;

  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready, false) WHERE id = _game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready, false) WHERE id = _game_id;
  ELSE
    RAISE EXCEPTION 'not a player';
  END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    SELECT * INTO v_cfg FROM public._game_cfg('chess');
    v_time_ms := COALESCE(v_g.time_control_min, 10) * 60 * 1000;
    UPDATE public.chess_games
       SET status = 'playing',
           started_at = now(),
           last_move_at = now(),
           white_time_ms = v_time_ms,
           black_time_ms = v_time_ms,
           turn_deadline = now() + (COALESCE(v_cfg.turn_timer_seconds, 60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END
$function$;

-- ── 9. chess_join_stake : set last_move_at + initialize clocks ─────
CREATE OR REPLACE FUNCTION public.chess_join_stake(_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_bal numeric;
  v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id AND status='open' AND mode='stake' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF v_g.white_id = v_uid OR v_g.black_id = v_uid THEN RETURN _id; END IF;
  IF v_g.stake > 0 THEN
    SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid FOR UPDATE;
    IF coalesce(v_bal,0) < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
    UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
    INSERT INTO transactions(user_id, type, amount, meta) VALUES (v_uid, 'chess_stake', -v_g.stake, jsonb_build_object('kind','hold','game',_id));
  END IF;
  v_time_ms := COALESCE(v_g.time_control_min, 10) * 60 * 1000;
  IF v_g.white_id IS NULL THEN
    UPDATE chess_games SET white_id=v_uid, pot=pot+v_g.stake, status='playing',
      started_at=now(), last_move_at=now(),
      white_time_ms=v_time_ms, black_time_ms=v_time_ms
      WHERE id=_id;
  ELSE
    UPDATE chess_games SET black_id=v_uid, pot=pot+v_g.stake, status='playing',
      started_at=now(), last_move_at=now(),
      white_time_ms=v_time_ms, black_time_ms=v_time_ms
      WHERE id=_id;
  END IF;
  RETURN _id;
END
$function$;

-- ── 10. chess_auto_timeout : ajouter end_reason = 'timeout' (déjà OK) ─
-- La fonction existe déjà et fonctionne correctement avec _chess_settle(..., 'timeout')
-- On s'assure juste que le résultat est bien "Victoire au temps"
CREATE OR REPLACE FUNCTION public.chess_auto_timeout(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
  v_winner uuid;
  v_loser_color text;
  v_winner_color text;
  v_winner_has_material boolean;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR v_g.status <> 'playing' THEN RETURN; END IF;
  IF coalesce(v_g.paused, false) THEN RETURN; END IF;
  IF v_g.time_control_min <= 0 THEN RETURN; END IF;

  v_elapsed_ms := greatest(0, floor(extract(epoch FROM (now() - coalesce(v_g.last_move_at, v_g.started_at, now())))*1000)::int);

  IF v_g.turn = 'w' THEN
    v_remaining := v_g.white_time_ms - v_elapsed_ms;
    v_winner := v_g.black_id;
    v_loser_color := 'w';
    v_winner_color := 'b';
  ELSE
    v_remaining := v_g.black_time_ms - v_elapsed_ms;
    v_winner := v_g.white_id;
    v_loser_color := 'b';
    v_winner_color := 'w';
  END IF;

  IF v_remaining <= 0 THEN
    -- Vérifier si l'adversaire (le gagnant) a assez de matériel pour mater
    v_winner_has_material := public._chess_has_mating_material(v_g.fen, v_winner_color);

    IF v_winner_has_material THEN
      PERFORM public._chess_settle(_game_id, v_winner, false, 'timeout');
    ELSE
      PERFORM public._chess_settle(_game_id, NULL, true, 'timeout_insufficient_material');
    END IF;
  END IF;
END
$function$;

-- ── 11. _auto_advance_overdue_turns : inchangé (utilise les fonctions mises à jour) ─
-- La fonction existante appelle déjà fanorona_tick et chess_auto_timeout
-- qui utilisent maintenant les horloges mises à jour.
-- Pas de changement nécessaire.

