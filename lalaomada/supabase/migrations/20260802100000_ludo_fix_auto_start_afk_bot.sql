-- ========================================
-- Fix 3 bugs Ludo critiques:
-- 1. Le jeu démarre tout seul sans que le joueur soit prêt
-- 2. Le "filet de sécurité" à 3 tours ratés écrase le seuil AFK (afk_t1_max=5)
-- 3. (frontend) Bot bloqué en phase 2 — nécessite reload après bot_play
-- ========================================

-- ═══════════════════════════════════════════════════════
-- FIX 1: Retirer l'auto-start de player_add_bot et join_game
-- Le jeu ne démarre QUE quand tous les joueurs humains sont prêts
-- via ludo_set_ready
-- ═══════════════════════════════════════════════════════

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

    v_colors := CASE COALESCE(v_max_players, 4)
      WHEN 2 THEN ARRAY['red', 'yellow']
      WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
      ELSE         ARRAY['red', 'green', 'yellow', 'blue']
    END;

    IF v_slot > array_length(v_colors, 1) THEN
      v_color := v_colors[array_length(v_colors, 1)];
    ELSE
      v_color := v_colors[v_slot + 1];
    END IF;

    INSERT INTO ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      joined_at, bot_intelligence, bot_win_bias, forfeited, missed_turns,
      ready, last_seen, consecutive_sixes
    ) VALUES (
      _game_id, NULL, v_slot, v_color, true, v_name, v_name,
      now(), 5, 0, false, 0, true, now(), 0
    );

    -- NE PAS auto-start. Le jeu démarre via ludo_set_ready
    -- quand tous les joueurs (humains ET bots) sont prêts.
    -- Le créateur de la partie doit cliquer "Prêt" pour lancer.

    RETURN;
  END IF;

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


-- join_game: retirer l'auto-start, garder le démarrage via ludo_set_ready
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  
  v_colors := CASE v_game.max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;
  v_color := v_colors[v_slot + 1];

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
  SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id = v_uid;

  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id = v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id = _game_id;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'stake', -v_game.stake, _game_id, 'Mise rejoindre partie');

  -- NE PAS auto-start. Le jeu démarre via ludo_set_ready.
END $function$;


-- ludo_set_ready: démarrer le jeu quand TOUS sont prêts (humains + bots)
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players) WHERE id=_game_id;
  END IF;
END $function$;


-- ═══════════════════════════════════════════════════════
-- FIX 2: Retirer le "filet de sécurité" à 3 tours ratés
-- Laisser _ludo_check_afk gérer le forfait avec afk_t1_max=5
-- ═══════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_started TIMESTAMPTZ;
  v_uid UUID;
  v_isbot BOOLEAN;
  v_missed INT;
  v_winner UUID;
  v_status TEXT;
  v_must_move BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  IF st IS NULL THEN RETURN st; END IF;
  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF v_started > now() + interval '1 minute' THEN
    v_started := now() - interval '60 seconds';
  END IF;
  -- 30 secondes par tour
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;
  v_must_move := (st->>'must_move')::BOOLEAN;

  SELECT user_id, is_bot, missed_turns
    INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  -- Les bots n'ont pas de pénalité AFK, juste avancer le tour
  IF v_isbot THEN
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot_timeout'::text));
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  -- Incrémenter le compteur AFK approprié
  v_missed := COALESCE(v_missed, 0) + 1;

  IF v_must_move THEN
    -- T2: a lancé le dé mais n'a pas bougé
    UPDATE public.ludo_participants
      SET missed_turns = v_missed, afk_t2 = COALESCE(afk_t2, 0) + 1
      WHERE game_id = _game_id AND slot = v_slot;
  ELSE
    -- T1: n'a même pas lancé le dé
    UPDATE public.ludo_participants
      SET missed_turns = v_missed, afk_t1 = COALESCE(afk_t1, 0) + 1
      WHERE game_id = _game_id AND slot = v_slot;
  END IF;

  -- Vérifier si le joueur doit être forfeit via le système AFK
  -- (afk_t1_max=5, afk_t2_max=2 dans app_settings)
  PERFORM public._ludo_check_afk(_game_id, v_slot);

  -- Vérifier si la partie est terminée
  SELECT status INTO v_status FROM public.ludo_games WHERE id = _game_id;
  IF v_status = 'finished' THEN
    RETURN (SELECT state FROM public.ludo_games WHERE id = _game_id);
  END IF;

  -- Avancer le tour
  st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb(
    CASE WHEN v_must_move THEN 'timeout_t2' ELSE 'timeout_t1' END
  ));
  UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
  RETURN st;
END $function$;
