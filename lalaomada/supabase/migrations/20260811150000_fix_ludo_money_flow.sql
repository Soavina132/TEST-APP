-- ═══════════════════════════════════════════════════════════════════════
-- FIX: Flux d'argent Ludo — aligner exactement sur Domino
--   1. Ajouter _validate_stake (min 200 Ar) sur toutes les fonctions Ludo
--   2. Standardiser le type de transaction à 'ludo_stake' (était 'stake')
--   3. Ajouter paramètre _commission (DEFAULT 10) comme domino_create
--   4. ludo_start_solo_bot: commission default 10 (était 0)
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- 1. create_public_game — ajouter _commission, _validate_stake, 'ludo_stake'
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_public_game(integer, numeric, text, text);

CREATE OR REPLACE FUNCTION public.create_public_game(
  _max_players integer,
  _stake numeric,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo',
  _commission numeric DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_id uuid;
  v_mode text;
  v_paused boolean;
  v_banned boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  INSERT INTO public.ludo_games(host_id, max_players, stake, status, is_private, pot, mode, match_type, commission_pct)
    VALUES (v_uid, _max_players, _stake, 'open', false, _stake, v_mode, COALESCE(_match_type, 'solo'), _commission)
    RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'ludo_stake', -_stake, v_id, 'Mise Ludo');

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.create_public_game(integer, numeric, text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_public_game(integer, numeric, text, text, numeric) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 2. create_private_game — ajouter _commission, _validate_stake, 'ludo_stake'
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_private_game(integer, numeric, text, text);

CREATE OR REPLACE FUNCTION public.create_private_game(
  _max_players integer,
  _stake numeric,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'groupe',
  _commission numeric DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
  v_code TEXT;
  v_is_solo BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  v_code := public._gen_room_code();
  v_is_solo := COALESCE(_match_type, 'groupe') = 'solo';

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                room_code, is_private, mode, is_solo, match_type)
    VALUES (v_uid, _max_players, _stake, _stake, _commission,
            v_code, TRUE, COALESCE(_mode,'classic'), v_is_solo, COALESCE(_match_type,'groupe'))
    RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'ludo_stake', -_stake, v_game_id, 'Mise création partie privée Ludo');

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_game_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.create_private_game(integer, numeric, text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_private_game(integer, numeric, text, text, numeric) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 3. find_or_create_game — ajouter _commission, _validate_stake, 'ludo_stake'
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.find_or_create_game(integer, numeric, text, text);

CREATE OR REPLACE FUNCTION public.find_or_create_game(
  _max_players integer,
  _stake numeric,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo',
  _commission numeric DEFAULT 10
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_game_id UUID;
  v_balance NUMERIC;
  v_count INT;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Chercher une partie publique ouverte avec les mêmes params
  SELECT id INTO v_game_id FROM public.ludo_games
    WHERE status = 'open'
      AND is_private = false
      AND max_players = _max_players
      AND stake = _stake
      AND COALESCE(mode, 'classic') = COALESCE(_mode, 'classic')
      AND COALESCE(match_type, 'solo') = COALESCE(_match_type, 'solo')
    ORDER BY created_at LIMIT 1 FOR UPDATE SKIP LOCKED;

  IF v_game_id IS NULL THEN
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, mode, match_type)
      VALUES (v_uid, _max_players, _stake, _stake, _commission, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo'))
      RETURNING id INTO v_game_id;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'ludo_stake', -_stake, v_game_id, 'Mise création partie Ludo');
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
      SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  ELSE
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_game_id;
    IF v_count >= _max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
    PERFORM public.join_game(v_game_id);
  END IF;

  RETURN v_game_id;
END $$;

REVOKE ALL ON FUNCTION public.find_or_create_game(integer, numeric, text, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.find_or_create_game(integer, numeric, text, text, numeric) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 4. join_game — _validate_stake, 'ludo_stake'
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
  v_colors TEXT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  PERFORM public._validate_stake(v_game.stake);
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'ludo_stake', -v_game.stake, _game_id, 'Mise join partie Ludo');
  PERFORM public._ludo_maybe_auto_start(_game_id);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.join_game(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.join_game(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- 5. ludo_start_solo_bot — _commission DEFAULT 10, _validate_stake, 'ludo_stake'
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.ludo_start_solo_bot(integer, numeric, text, text);

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
SET search_path = 'public'
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

  RETURN v_game_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text, numeric) TO authenticated;
