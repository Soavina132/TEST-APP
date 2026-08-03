
-- admin_add_bot : couleurs symétriques selon max_players (comme player_add_bot)
CREATE OR REPLACE FUNCTION public.admin_add_bot(_game_id uuid, _bot_name text, _intelligence integer DEFAULT 70, _win_bias integer DEFAULT 0)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_slot int;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  v_count int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé à l''administrateur'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT s INTO v_slot
    FROM generate_series(0, g.max_players-1) AS s
   WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id=_game_id)
   ORDER BY s LIMIT 1;

  IF g.max_players = 2 THEN v_color := v_colors2[v_slot+1];
  ELSIF g.max_players = 3 THEN v_color := v_colors3[v_slot+1];
  ELSE v_color := v_colors4[v_slot+1];
  END IF;

  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, bot_win_bias, ready
  ) VALUES (
    _game_id, NULL, v_slot, v_color, TRUE,
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    GREATEST(0, LEAST(100, COALESCE(_intelligence, 70))),
    GREATEST(-100, LEAST(100, COALESCE(_win_bias, 0))),
    TRUE
  );
END $$;

-- ludo_start_solo_bot : couleurs symétriques (humain toujours face à un bot)
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;

  v_intel := CASE _difficulty WHEN 'easy' THEN 40 WHEN 'hard' THEN 90 ELSE 70 END;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, status, is_solo)
  VALUES (v_uid, _max_players, 0, 0, 0, TRUE, 'classic', 'open', TRUE)
  RETURNING id INTO v_game_id;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  -- Humain toujours slot 0 = 'red'
  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE
    );
  END LOOP;

  RETURN v_game_id;
END $$;
