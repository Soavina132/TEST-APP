-- Migration: Fix domino_tick stuck when a forfeited player's slot is current_turn
--
-- Root cause: In domino_tick (20260814170000), the check was:
--   SELECT user_id INTO cur_uid FROM domino_participants
--   WHERE slot = current_turn AND forfeited = false;
--   IF cur_uid IS NULL THEN PERFORM _domino_bot_step(); RETURN; END IF;
--
-- Problem: cur_uid is NULL for BOTH bots (user_id is NULL) AND forfeited players
-- (no row returned). When a human forfeits and current_turn stays on their slot,
-- _domino_bot_step is called but does nothing (slot is not a bot), so the game
-- stays stuck forever.
--
-- Fix: Use COALESCE(dp.is_bot, false) + FOUND to distinguish:
--   - Bot (is_bot=true, user_id=NULL) → call _domino_bot_step
--   - Forfeited/empty slot (no row) → advance to next playable slot,
--     or end the round if no one can play (blocked game / forfeited starter)
--
-- Also adds: cleanup_stale_games() to cancel stale 'open' and 'playing' games

-- ═══════════════════════════════════════════════════════════════════
-- 1. Fixed domino_tick
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  _bot_think timestamptz;
  v_is_bot boolean := false;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  -- Phase: dealing
  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  -- Phase: reveal
  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games
         SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb)
       WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- Phase: break
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
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- Bot think delay expired → trigger bot play
  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  -- ── Check who is at the current slot ──
  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  -- Case 1: No non-forfeited player at this slot (forfeited/empty)
  IF NOT FOUND THEN
    -- Forfeited human slot — advance to next playable player
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games
         SET current_turn = _next,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
    ELSE
      -- No one can play — game is blocked (empty board + forfeited starter,
      -- or all remaining players blocked with empty stock)
      _next := public._domino_lowest_pip_slot(_game_id, g.state);
      IF _next IS NOT NULL THEN
        PERFORM public._domino_end_round(_game_id, _next);
      ELSE
        -- Complete tie or no non-forfeited players — end round with NULL
        PERFORM public._domino_end_round(_game_id, NULL);
      END IF;
    END IF;
    RETURN;
  END IF;

  -- Case 2: It's a bot's turn and deadline expired → let bot play
  IF v_is_bot THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  -- Case 3: Human player — apply skip/forfeit logic
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    -- Forfeit the player
    UPDATE public.domino_participants
       SET forfeited = true
     WHERE game_id = _game_id AND user_id = cur_uid;

    SELECT count(*) INTO remaining
      FROM public.domino_participants
     WHERE game_id = _game_id AND forfeited = false;

    IF remaining <= 1 THEN
      SELECT slot INTO last_slot
        FROM public.domino_participants
       WHERE game_id = _game_id AND forfeited = false
       LIMIT 1;
      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;

    g.turn_skips := jsonb_set(
      COALESCE(g.turn_skips, '{}'::jsonb),
      ARRAY[cur_uid::text], to_jsonb(_skips), true
    );
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET state = g.state, turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(
      COALESCE(g.turn_skips, '{}'::jsonb),
      ARRAY[cur_uid::text], to_jsonb(_skips), true
    );
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      RETURN;
    END IF;
    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  -- Advance to next playable slot
  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    -- Blocked game — end the round
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    ELSE
      PERFORM public._domino_end_round(_game_id, NULL);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET current_turn = _next,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════
-- 2. Stale game cleanup — cancels abandoned games across all game types
-- ═══════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.cleanup_stale_games()
RETURNS TABLE(game_type text, game_id uuid, reason text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_timeout_min int := 5;  -- cancel games inactive for 5+ minutes
  v_cutoff timestamptz := now() - (v_timeout_min || ' minutes')::interval;
BEGIN
  -- Domino: stale 'open' or 'playing' games
  FOR game_id IN
    SELECT id FROM public.domino_games
    WHERE status = 'open' AND created_at < v_cutoff
  LOOP
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'domino open > ' || v_timeout_min || 'min';
    game_type := 'domino';
    RETURN NEXT;
  END LOOP;

  FOR game_id IN
    SELECT id FROM public.domino_games
    WHERE status = 'playing'
      AND turn_deadline IS NOT NULL
      AND turn_deadline < v_cutoff
      AND COALESCE(state->>'phase', 'play') NOT IN ('reveal', 'break', 'dealing')
  LOOP
    -- Try to tick the game first (may resolve via forfeit/advance)
    PERFORM public.domino_tick(game_id);
    -- If still playing after tick, cancel it
    PERFORM 1 FROM public.domino_games WHERE id = game_id AND status = 'playing';
    IF FOUND THEN
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
      reason := 'domino stuck playing > ' || v_timeout_min || 'min';
      game_type := 'domino';
      RETURN NEXT;
    END IF;
  END LOOP;

  -- Ludo: stale 'open' or 'playing' games
  FOR game_id IN
    SELECT id FROM public.ludo_games
    WHERE status = 'open' AND created_at < v_cutoff
  LOOP
    UPDATE public.ludo_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'ludo open > ' || v_timeout_min || 'min';
    game_type := 'ludo';
    RETURN NEXT;
  END LOOP;

  FOR game_id IN
    SELECT id FROM public.ludo_games
    WHERE status = 'playing'
      AND updated_at < v_cutoff
  LOOP
    UPDATE public.ludo_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'ludo stuck playing > ' || v_timeout_min || 'min';
    game_type := 'ludo';
    RETURN NEXT;
  END LOOP;

  -- Fanorona: stale 'open' or 'playing'
  FOR game_id IN
    SELECT id FROM public.fanorona_games
    WHERE status = 'open' AND created_at < v_cutoff
  LOOP
    UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'fanorona open > ' || v_timeout_min || 'min';
    game_type := 'fanorona';
    RETURN NEXT;
  END LOOP;

  FOR game_id IN
    SELECT id FROM public.fanorona_games
    WHERE status = 'playing' AND updated_at < v_cutoff
  LOOP
    UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'fanorona stuck playing > ' || v_timeout_min || 'min';
    game_type := 'fanorona';
    RETURN NEXT;
  END LOOP;

  -- Chess: stale 'open' or 'playing'
  FOR game_id IN
    SELECT id FROM public.chess_games
    WHERE status = 'open' AND created_at < v_cutoff
  LOOP
    UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'chess open > ' || v_timeout_min || 'min';
    game_type := 'chess';
    RETURN NEXT;
  END LOOP;

  FOR game_id IN
    SELECT id FROM public.chess_games
    WHERE status = 'playing' AND updated_at < v_cutoff
  LOOP
    UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'chess stuck playing > ' || v_timeout_min || 'min';
    game_type := 'chess';
    RETURN NEXT;
  END LOOP;

  -- Rami: stale 'open' or 'playing'
  FOR game_id IN
    SELECT id FROM public.rami_games
    WHERE status = 'open' AND created_at < v_cutoff
  LOOP
    UPDATE public.rami_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'rami open > ' || v_timeout_min || 'min';
    game_type := 'rami';
    RETURN NEXT;
  END LOOP;

  FOR game_id IN
    SELECT id FROM public.rami_games
    WHERE status = 'playing' AND updated_at < v_cutoff
  LOOP
    UPDATE public.rami_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'rami stuck playing > ' || v_timeout_min || 'min';
    game_type := 'rami';
    RETURN NEXT;
  END LOOP;

  -- Poker: stale 'open' or 'playing'
  FOR game_id IN
    SELECT id FROM public.poker_games
    WHERE status = 'open' AND created_at < v_cutoff
  LOOP
    UPDATE public.poker_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'poker open > ' || v_timeout_min || 'min';
    game_type := 'poker';
    RETURN NEXT;
  END LOOP;

  FOR game_id IN
    SELECT id FROM public.poker_games
    WHERE status = 'playing' AND updated_at < v_cutoff
  LOOP
    UPDATE public.poker_games SET status = 'cancelled', finished_at = now() WHERE id = game_id;
    reason := 'poker stuck playing > ' || v_timeout_min || 'min';
    game_type := 'poker';
    RETURN NEXT;
  END LOOP;

  RETURN;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.cleanup_stale_games() TO authenticated;
GRANT EXECUTE ON FUNCTION public.cleanup_stale_games() TO service_role;

-- ═══════════════════════════════════════════════════════════════════
-- 3. Run cleanup immediately on the currently stuck games
-- ═══════════════════════════════════════════════════════════════════
SELECT public.cleanup_stale_games();
