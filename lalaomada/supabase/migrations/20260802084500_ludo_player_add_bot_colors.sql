-- Fix player_add_bot: use symmetric color assignment based on max_players
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id uuid, _bot_name text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_count int;
  v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_name text;
  v_max_players int;
  v_colors text[];
  v_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  v_name := COALESCE(_bot_name, v_bot_names[1]);

  -- Try ludo_games
  PERFORM 1 FROM ludo_games WHERE id = _game_id;
  IF FOUND THEN
    SELECT count(*), max(max_players)
      INTO v_count, v_max_players
      FROM ludo_participants lp
      JOIN ludo_games lg ON lg.id = _game_id
      WHERE lp.game_id = _game_id;

    IF v_count >= 4 THEN RAISE EXCEPTION 'game full'; END IF;

    SELECT COALESCE(MAX(slot), 0) + 1 INTO v_slot
      FROM ludo_participants WHERE game_id = _game_id;

    -- Symmetric colors matching join_game logic
    v_colors := CASE COALESCE(v_max_players, 4)
      WHEN 2 THEN ARRAY['red', 'yellow']
      WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
      ELSE         ARRAY['red', 'green', 'yellow', 'blue']
    END;

    -- Safety: ensure slot is within bounds
    IF v_slot > array_length(v_colors, 1) THEN
      v_color := v_colors[array_length(v_colors, 1)];
    ELSE
      v_color := v_colors[v_slot + 1]; -- slot is 0-based, array is 1-based
    END IF;

    INSERT INTO ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      joined_at, bot_intelligence, bot_win_bias, forfeited, missed_turns,
      ready, last_seen, consecutive_sixes
    ) VALUES (
      _game_id, NULL, v_slot, v_color, true, v_name, v_name,
      now(), 5, 0, false, 0, true, now(), 0
    );

    -- Start game if full
    IF v_count + 1 = v_max_players THEN
      UPDATE ludo_games
        SET status = 'playing', started_at = now(),
            state = public._ludo_init_state(v_max_players)
        WHERE id = _game_id AND status = 'open';
    END IF;

    RETURN;
  END IF;

  -- Other game types unchanged
  PERFORM 1 FROM domino_games WHERE id = _game_id;
  IF FOUND THEN PERFORM public.domino_add_bot(_game_id, v_name); RETURN; END IF;

  PERFORM 1 FROM chess_games WHERE id = _game_id;
  IF FOUND THEN PERFORM public.chess_add_bot(_game_id); RETURN; END IF;

  PERFORM 1 FROM petanque_games WHERE id = _game_id;
  IF FOUND THEN PERFORM public.petanque_add_bot(_game_id); RETURN; END IF;

  PERFORM 1 FROM poker_games WHERE id = _game_id;
  IF FOUND THEN PERFORM public.poker_add_bot(_game_id, v_name); RETURN; END IF;

  RAISE EXCEPTION 'game not found in any table';
END $function$;
