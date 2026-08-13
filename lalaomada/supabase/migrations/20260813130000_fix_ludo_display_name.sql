-- ============================================================
-- FIX: ludo_start_solo_bot missing display_name in INSERTs
-- The 20260813090000 migration created ludo_start_solo_bot without display_name,
-- causing "null value in column display_name violates not-null constraint"
-- ============================================================

CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium'::text,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic'::text,
  _match_type text DEFAULT 'solo'::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        UUID := auth.uid();
  v_game_id    UUID;
  v_code       TEXT;
  v_commission NUMERIC;
  v_i          INT;
  v_slot       INT;
  v_color      TEXT;
  v_colors     TEXT[] := ARRAY['red','green','yellow','blue'];
  v_bots       TEXT[] := ARRAY['BotAlpha','BotBeta','BotGamma','BotDelta'];
  v_intel      INT;
  v_bias       INT;
  v_mp         INT;
  v_mode       TEXT;
  v_pseudo     TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  v_mp := LEAST(GREATEST(COALESCE(_max_players, 2), 2), 4);

  SELECT COALESCE(game_commission_pct, 10) INTO v_commission FROM public.app_settings WHERE id = 1;
  SELECT COALESCE(pseudo, '') INTO v_pseudo FROM public.profiles WHERE id = v_uid;

  v_code := upper(substr(md5(random()::text), 1, 6));

  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct,
    room_code, is_private, mode, match_type, status, is_solo
  ) VALUES (
    v_uid, v_mp, _stake, _stake * v_mp, v_commission,
    v_code, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE
  ) RETURNING id INTO v_game_id;

  -- Host (human) — include display_name
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, ready, display_name, joined_at)
  VALUES (v_game_id, v_uid, 0, v_colors[1], FALSE, TRUE, v_pseudo, now());

  v_intel := CASE WHEN _difficulty = 'hard' THEN 85 WHEN _difficulty = 'easy' THEN 40 ELSE 65 END;
  v_bias  := CASE WHEN _difficulty = 'hard' THEN 15 WHEN _difficulty = 'easy' THEN 0 ELSE 5 END;

  FOR v_i IN 1..v_mp - 1 LOOP
    -- Bots — use bot_name as display_name
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot,
      bot_name, bot_intelligence, bot_win_bias, ready, display_name, joined_at
    ) VALUES (
      v_game_id, v_uid, v_i, v_colors[v_i+1], TRUE,
      v_bots[v_i], v_intel, v_bias, TRUE, v_bots[v_i], now()
    );
  END LOOP;

  UPDATE public.ludo_games SET
    status = 'playing',
    started_at = now(),
    state = public._ludo_init_state(v_mp, v_mode),
    current_turn = 0
  WHERE id = v_game_id;

  RETURN v_game_id;
END $function$;

-- Also backfill any existing ludo_participants with NULL display_name
UPDATE public.ludo_participants
SET display_name = COALESCE(
  (SELECT pseudo FROM public.profiles WHERE id = ludo_participants.user_id),
  bot_name,
  'Player'
)
WHERE display_name IS NULL;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) TO authenticated;
