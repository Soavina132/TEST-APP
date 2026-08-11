-- Fix: ludo_start_solo_bot ne démarrant jamais la partie
-- La fonction crée la game en statut 'open' avec tous les participants
-- (humain + bots, tous ready=TRUE) mais n'appelle pas _ludo_maybe_auto_start.
-- Le fallback frontend (ludo_set_ready) peut échouer si le téléphone
-- n'est pas vérifié, laissant la partie bloquée en 'open'.
-- Solution: auto-start immédiat dans ludo_start_solo_bot.

CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo',
  _commission numeric DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int := 70;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_balance numeric;
  v_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  PERFORM public._validate_stake(_stake);
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, _commission,
          TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'ludo_stake', -_stake, v_game_id, 'Mise création partie solo bot Ludo');
  END IF;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  -- Humain toujours slot 0 = 'red', team 1 in groupe mode
  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;

  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE, v_team);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    -- In groupe mode: even slots = team 1, odd slots = team 2
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team
    );
  END LOOP;

  -- AUTO-START: tous les participants sont présents et prêts → démarrer immédiatement
  UPDATE public.ludo_games
    SET status = 'playing',
        started_at = now(),
        state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')),
        current_turn = 0
    WHERE id = v_game_id;

  RETURN v_game_id;
END
$$;
