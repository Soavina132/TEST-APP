-- Ludo rematch: create a new game with same config and auto-invite same players + bots
CREATE OR REPLACE FUNCTION public.ludo_rematch(_old_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_old public.ludo_games%ROWTYPE;
  v_new_id uuid;
  v_part public.ludo_participants%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_colors TEXT[];
  v_color TEXT;
  v_room_code TEXT;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  SELECT * INTO v_old FROM public.ludo_games WHERE id = _old_game_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_old.status <> 'finished' THEN RAISE EXCEPTION 'La partie doit etre terminee'; END IF;

  v_room_code := CASE WHEN v_old.is_private THEN substr(md5(random()::text), 1, 6) ELSE NULL END;

  INSERT INTO public.ludo_games(max_players, stake, mode, is_private, room_code, commission_pct, status, pot, created_by)
  VALUES (v_old.max_players, v_old.stake, v_old.mode, v_old.is_private,
          v_room_code, v_old.commission_pct, 'open', 0, v_uid)
  RETURNING id INTO v_new_id;

  -- Copy non-forfeited real players
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND NOT is_bot ORDER BY slot
  LOOP
    IF v_old.stake > 0 THEN
      IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_part.user_id AND balance_ar >= v_old.stake) THEN
        CONTINUE;
      END IF;
    END IF;

    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    v_slot := v_count;
    v_colors := CASE v_old.max_players
      WHEN 2 THEN ARRAY['red', 'yellow']
      WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
      ELSE ARRAY['red', 'green', 'yellow', 'blue']
    END;
    v_color := v_colors[v_slot + 1];

    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_new_id, v_part.user_id, v_slot, v_color, v_part.display_name, false);

    IF v_old.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar - v_old.stake WHERE id = v_part.user_id;
      UPDATE public.ludo_games SET pot = pot + v_old.stake WHERE id = v_new_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_part.user_id, 'stake', -v_old.stake, v_new_id, 'Mise revanche');
    END IF;
  END LOOP;

  -- Copy bots
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND is_bot ORDER BY slot
  LOOP
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    IF v_count >= v_old.max_players THEN EXIT; END IF;
    v_slot := v_count;
    v_colors := CASE v_old.max_players
      WHEN 2 THEN ARRAY['red', 'yellow']
      WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
      ELSE ARRAY['red', 'green', 'yellow', 'blue']
    END;
    v_color := v_colors[v_slot + 1];
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready)
    VALUES (v_new_id, NULL, v_slot, v_color, TRUE, v_part.bot_name, v_part.bot_name,
      v_part.bot_intelligence, 0, TRUE);
  END LOOP;

  -- Auto-start if full
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
  IF v_count >= v_old.max_players THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(),
      state = public._ludo_init_state(v_old.max_players) WHERE id = v_new_id;
  END IF;

  RETURN v_new_id;
END $function$;
