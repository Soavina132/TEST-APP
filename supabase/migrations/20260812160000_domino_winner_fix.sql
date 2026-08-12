-- Fix: Domino ne désignait jamais de gagnant quand un humain quitte une partie solo bot
-- 3 bugs corrigés :
-- 1. _maybe_end_bot_only_domino terminait la partie sans déterminer de gagnant
-- 2. domino_tick n'appelait pas _maybe_end_bot_only_domino après un forfait
-- 3. domino_forfeit annulait et purgeait la partie au lieu de désigner un gagnant
-- + Fix frontend: winnerSlot non transmis à GameEndScreen (bot gagnant = "Match nul")

-- ═══ 1. _maybe_end_bot_only_domino : déterminer un vrai gagnant ═══
CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_domino(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$

DECLARE
  g record;
  v_winner_slot int;
  v_scores jsonb;
  v_best_score int := -1;
  v_slot int;
  v_hand jsonb;
  v_pips int;
  v_lowest_pips int := 999999;
  v_mode text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND OR g.status <> 'playing' THEN RETURN; END IF;

  IF EXISTS (SELECT 1 FROM public.domino_participants p
             WHERE p.game_id = _game_id AND p.is_bot = false
               AND COALESCE(p.forfeited, false) = false) THEN
    RETURN;  -- Still has active humans
  END IF;

  -- No active humans left — determine the winner among remaining (bot) players
  v_mode := COALESCE(g.mode, 'classic');
  v_scores := COALESCE(g.state->'round_scores', '{}'::jsonb);

  IF v_mode = 'points' AND COALESCE(g.target_score, 0) > 0 THEN
    -- Points mode: highest score wins
    FOR v_slot IN SELECT slot FROM public.domino_participants
                   WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      IF COALESCE((v_scores->>v_slot::text)::int, 0) > v_best_score THEN
        v_best_score := COALESCE((v_scores->>v_slot::text)::int, 0);
        v_winner_slot := v_slot;
      END IF;
    END LOOP;
  ELSE
    -- Classic mode: lowest pip count in hand wins (empty hand = domino = instant win)
    FOR v_slot IN SELECT slot FROM public.domino_participants
                   WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      v_hand := g.state->'hands'->v_slot::text;
      IF v_hand IS NOT NULL AND jsonb_array_length(v_hand) = 0 THEN
        v_winner_slot := v_slot;
        EXIT;  -- Domino! Empty hand = instant winner
      END IF;
      SELECT COALESCE(sum((t->>0)::int + (t->>1)::int), 0) INTO v_pips
        FROM jsonb_array_elements(COALESCE(v_hand, '[]'::jsonb)) t;
      IF v_pips < v_lowest_pips THEN
        v_lowest_pips := v_pips;
        v_winner_slot := v_slot;
      END IF;
    END LOOP;
  END IF;

  IF v_winner_slot IS NOT NULL THEN
    PERFORM public._domino_finalize(_game_id, v_winner_slot);
  ELSE
    UPDATE public.domino_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
  END IF;
END;


$$;

-- ═══ 2. domino_tick : appeler _maybe_end_bot_only_domino après forfait ═══
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$

DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  _blocked_until timestamptz;
  required_slot int; board_empty boolean;
  v_is_bot boolean := false;
  v_think_until timestamptz;
  v_bot_pass_until timestamptz;
  v_draw_mode text;
  v_stock_len int;
  v_drew_playable boolean;
  v_state jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- ── Phase "blocked": afficher "Domino bloqué" 3s puis terminer ──
  IF (g.state->>'phase') = 'blocked' THEN
    _blocked_until := NULLIF(g.state->>'blocked_until','')::timestamptz;
    IF _blocked_until IS NOT NULL AND _blocked_until <= now() THEN
      -- Délai expiré — terminer le round
      PERFORM public._domino_end_round(_game_id, public._domino_lowest_pip_slot(_game_id, g.state));
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb) WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    g.state := public._domino_arm_bot_think(_game_id, required_slot, g.state);
    v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot), true);
    UPDATE public.domino_games
       SET state = v_state, current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  IF COALESCE(v_is_bot, false) THEN
    -- Vérifier d'abord le pass en attente
    v_bot_pass_until := NULLIF(g.state->>'bot_pass_until', '')::timestamptz;
    IF v_bot_pass_until IS NOT NULL AND v_bot_pass_until <= now() THEN
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
    v_think_until := NULLIF(g.state->>'bot_think_until','')::timestamptz;
    IF v_think_until IS NOT NULL AND v_think_until <= now() THEN
      PERFORM public._domino_bot_step(_game_id);
    ELSIF v_think_until IS NULL THEN
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      g.state := public._domino_arm_bot_think(_game_id, _next, g.state);
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(_next), true);
      UPDATE public.domino_games SET state = v_state, current_turn = _next,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF NOT public._domino_slot_has_playable(g.state, g.current_turn) THEN
    v_draw_mode := COALESCE(g.state->>'draw_mode', 'with');
    v_stock_len := jsonb_array_length(COALESCE(g.state->'stock', '[]'::jsonb));
    v_drew_playable := false;

    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      v_drew_playable := public._domino_auto_draw(_game_id);
    END IF;

    IF v_drew_playable THEN
      RETURN;
    END IF;

    PERFORM public._domino_force_pass(_game_id, g.current_turn);
    RETURN;
  END IF;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    -- Check if no humans remain — finalize with a proper winner
    PERFORM public._maybe_end_bot_only_domino(_game_id);
    IF (SELECT status FROM public.domino_games WHERE id = _game_id) <> 'playing' THEN RETURN; END IF;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);
    IF board_empty AND required_slot IS NOT NULL THEN
      g.state := public._domino_arm_bot_think(_game_id, required_slot, g.state);
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot), true);
      UPDATE public.domino_games SET state = v_state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      g.state := public._domino_arm_bot_think(_game_id, required_slot, g.state);
      v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(required_slot), true);
      UPDATE public.domino_games SET state = v_state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    END IF;
    RETURN;
  END IF;

  g.state := public._domino_arm_bot_think(_game_id, _next, g.state);
  v_state := jsonb_set(g.state, ARRAY['turn_slot'], to_jsonb(_next), true);
  UPDATE public.domino_games SET state = v_state, current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END


$$;

-- ═══ 3. domino_forfeit : désigner un gagnant au lieu d'annuler ═══
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$

DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  remaining int;
  last_slot int;
  humans_left int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.domino_participants pp
     WHERE pp.game_id = _game_id AND pp.user_id = p.id AND COALESCE(pp.is_bot,false) = false;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'domino_refund', g.stake, _game_id, 'Game cancelled'
        FROM public.domino_participants
       WHERE game_id = _game_id AND COALESCE(is_bot,false) = false;
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    humans_left := public._domino_active_humans(_game_id);
    IF humans_left = 0 THEN PERFORM public._domino_purge(_game_id); END IF;
    RETURN;
  END IF;

  humans_left := public._domino_active_humans(_game_id);
  IF humans_left = 0 THEN
    -- No humans left: finalize with a proper winner instead of cancelling
    PERFORM public._maybe_end_bot_only_domino(_game_id);
    IF (SELECT status FROM public.domino_games WHERE id = _game_id) = 'finished' THEN RETURN; END IF;
    -- Fallback: cancel and purge if no winner could be determined
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    PERFORM public._domino_purge(_game_id);
    RETURN;
  END IF;

  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining <= 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      PERFORM public._domino_purge(_game_id);
    END IF;
  END IF;
END 

$$;
