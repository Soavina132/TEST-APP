-- ═══════════════════════════════════════════════════════════════
-- Fix: Domino — égalité de points non gérée
--
-- Bugs corrigés :
-- 1. _domino_lowest_pip_slot ne détectait pas les égalités → retournait
--    toujours le premier joueur (slot 0, généralement le créateur)
-- 2. _domino_end_round ne gérait pas un winner_slot NULL (égalité)
-- 3. domino_play n'appelait pas _domino_end_round si winner_slot était NULL
--    → la partie restait bloquée sans fin de manche
--
-- Comportement attendu :
-- - Égalité de points → nouvelle manche automatique, aucun point attribué,
--   aucun remboursement, la partie continue
-- - Valable en mode "Victoire directe" ET "Par points"
-- ═══════════════════════════════════════════════════════════════

-- ── 1. _domino_lowest_pip_slot : retourner NULL en cas d'égalité ──
CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  p record;
  cur_sum integer;
  best_sum integer := 2147483647;
  best_slot integer := NULL;
  tie_count integer := 0;
BEGIN
  FOR p IN
    SELECT slot FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false
    ORDER BY slot
  LOOP
    cur_sum := public._domino_hand_pips(
      COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb)
    );
    IF cur_sum < best_sum THEN
      best_sum  := cur_sum;
      best_slot := p.slot;
      tie_count := 1;
    ELSIF cur_sum = best_sum THEN
      tie_count := tie_count + 1;   -- égalité détectée
    END IF;
  END LOOP;

  -- Si plusieurs joueurs partagent le minimum → match nul (NULL)
  IF tie_count > 1 THEN
    RETURN NULL;
  END IF;
  RETURN best_slot;
END;
$$;

-- ── 2. _domino_end_round : gérer l'égalité (winner_slot NULL) ──
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g              record;
  st             jsonb;
  winner_uid     uuid;
  winner_key     text;
  round_score    int   := 0;
  hand_pips      jsonb := '{}'::jsonb;
  v_final_hands  jsonb := '{}'::jsonb;
  p              record;
  pips           int;
  v_scores       jsonb;
  new_total      int;
  v_blocked      boolean := false;
  winner_hand    jsonb;
  v_reveal       interval := interval '3 seconds';
  v_break_total  interval := interval '10 seconds';
  p_key          text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  st := g.state;

  -- ── Match nul : aucun gagnant → nouvelle manche sans points ──
  IF _winner_slot IS NULL THEN
    FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
      p_key := COALESCE(p.user_id::text, 'bot_' || p.slot::text);
      pips := public._domino_hand_pips(st->'hands'->p.slot::text);
      hand_pips := hand_pips || jsonb_build_object(p_key, pips);
      v_final_hands := v_final_hands || jsonb_build_object(p_key, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    END LOOP;

    st := jsonb_set(st, '{winner_slot}', 'null'::jsonb, true);
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  NULL::text, 'winner_slot', NULL,
      'round_score', 0, 'hand_pips', hand_pips,
      'final_hands', v_final_hands, 'blocked', true, 'draw', true, 'final', false
    ), true);
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
    st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
    st := jsonb_set(st, '{scores}', COALESCE(g.scores, '{}'::jsonb));
    UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Victoire normale ──
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  winner_key := COALESCE(winner_uid::text, 'bot_' || _winner_slot::text);
  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  st := jsonb_set(st, '{winner_slot}', to_jsonb(_winner_slot), true);

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    p_key := COALESCE(p.user_id::text, 'bot_' || p.slot::text);
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips := hand_pips || jsonb_build_object(p_key, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p_key, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  -- Mode Victoroire directe : fin directe
  IF COALESCE(g.target_score, 0) <= 0 THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'winner_slot', _winner_slot,
      'round_score', round_score, 'hand_pips', hand_pips,
      'final_hands', v_final_hands, 'blocked', v_blocked, 'draw', false, 'final', true
    ), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Mode Par points : cumul du score
  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_key)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_key], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  -- Objectif atteint → fin de partie
  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid', winner_uid, 'winner_slot', _winner_slot,
      'round_score', round_score, 'hand_pips', hand_pips,
      'final_hands', v_final_hands, 'blocked', v_blocked, 'draw', false, 'final', true
    ), true);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Objectif pas atteint → reveal + nouvelle manche
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', winner_uid, 'winner_slot', _winner_slot,
    'round_score', round_score, 'hand_pips', hand_pips,
    'final_hands', v_final_hands, 'blocked', v_blocked, 'draw', false, 'final', false
  ), true);
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END;
$$;

-- ── 3. domino_play : appeler _domino_end_round même en cas d'égalité ──
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  g           record;
  my_slot     int;
  st          jsonb;
  hand        jsonb;
  tile        jsonb;
  a int; b int;
  le int; re int;
  side        text;
  new_left    int; new_right int;
  action      text;
  n_players   int;
  next_turn   int;
  drawn       jsonb;
  stock       jsonb;
  found       boolean := false;
  new_hand    jsonb;
  i           int;
  winner_slot int;
  draw_mode   text;
  first_dbl   int;
  stock_len   int;
  _cfg        record;
  p_key       text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st        := g.state;
  action    := _move->>'action';
  hand      := st -> 'hands' -> my_slot::text;
  stock     := st -> 'stock';
  le        := NULLIF(st->>'left_end',  'null')::int;
  re        := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  stock_len := jsonb_array_length(COALESCE(stock, '[]'::jsonb));
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;
  SELECT * INTO _cfg FROM public._game_cfg('domino');

  -- ── Draw tile ──
  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Pass ──
  IF action = 'pass' THEN
    -- Vérifier qu'on ne peut vraiment pas jouer
    DECLARE has_playable boolean; BEGIN
      has_playable := false;
      FOR i IN 0..jsonb_array_length(hand)-1 LOOP
        tile := hand -> i;
        a := (tile->>0)::int; b := (tile->>1)::int;
        IF le IS NULL OR a = le OR b = le OR a = re OR b = re THEN
          has_playable := true; EXIT;
        END IF;
      END LOOP;
      IF has_playable THEN RAISE EXCEPTION 'you must play'; END IF;
      IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    END;
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      -- Toujours appeler _domino_end_round, même si winner_slot IS NULL (égalité)
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Play tile ──
  tile := _move -> 'tile'; side := _move->>'side'; a := (tile->>0)::int; b := (tile->>1)::int;

  -- Vérifier que le tile est dans la main
  found := false;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF (hand->i->>0)::int = a AND (hand->i->>1)::int = b THEN
      found := true; EXIT;
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  -- Retirer le tile de la main
  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN
      new_hand := new_hand || jsonb_build_array(hand->i);
    END IF;
  END LOOP;

  -- Placer le tile
  IF le IS NULL THEN
    le := a; re := b;
  ELSIF side = 'left' THEN
    IF a = le THEN le := b;
    ELSIF b = le THEN le := a;
    ELSE RAISE EXCEPTION 'cannot connect left';
    END IF;
  ELSIF side = 'right' THEN
    IF a = re THEN re := b;
    ELSIF b = re THEN re := a;
    ELSE RAISE EXCEPTION 'cannot connect right';
    END IF;
  ELSE
    IF a = le THEN le := b; side := 'left';
    ELSIF b = le THEN le := a; side := 'left';
    ELSIF a = re THEN re := b; side := 'right';
    ELSIF b = re THEN re := a; side := 'right';
    ELSE RAISE EXCEPTION 'cannot connect tile';
    END IF;
  END IF;

  st := jsonb_set(st, '{left_end}',  to_jsonb(le));
  st := jsonb_set(st, '{right_end}', to_jsonb(re));
  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{passes}', to_jsonb(0));

  -- Main vide → gagnant de la manche
  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  -- Vérifier deadlock (tous bloqués)
  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    -- Toujours appeler _domino_end_round, même si winner_slot IS NULL (égalité)
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END;
$$;

REVOKE ALL ON FUNCTION public.domino_play(uuid, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) TO authenticated;
