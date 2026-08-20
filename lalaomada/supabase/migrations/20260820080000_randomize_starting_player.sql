-- ============================================================
-- Migration: Randomiser le premier joueur pour tous les jeux
-- Date: 2026-08-20
-- Description: Le créateur ne doit pas toujours commencer
-- Jeux concernés: Ludo (current_turn aléatoire), Chess (couleurs aléatoires)
-- Jeux déjà équitables: Domino (plus gros double), Fanorona (gen_random_bytes), Rami (_crypto_rand_int)
-- ============================================================

CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
  v_slots int[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
  IF _ready AND NOT COALESCE(v_verified,false) THEN
    RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
  END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    SELECT array_agg(slot) INTO v_slots FROM public.ludo_participants WHERE game_id=_game_id;
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode,'classic')),
      current_turn = v_slots[1 + public._crypto_rand_int(array_length(v_slots,1))]
      WHERE id=_game_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_quick_start(
  _max_players integer DEFAULT 2,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
  v_slots int[];
  v_start int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, match_type)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), false, _mode, _match_type)
  RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
  SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot)
  SELECT v_game_id, NULL, s, c, 'Bot '||s, true
  FROM (VALUES (1,'blue','Bot 1'),(2,'green','Bot 2'),(3,'yellow','Bot 3')) AS t(s,c)
  WHERE s < _max_players;

  SELECT array_agg(slot) INTO v_slots FROM public.ludo_participants WHERE game_id=v_game_id;
  v_start := v_slots[1 + public._crypto_rand_int(array_length(v_slots,1))];

  UPDATE public.ludo_games SET status = 'playing'::game_status, started_at = now(),
    state = public._ludo_init_state(_max_players, _mode), current_turn = v_start
    WHERE id = v_game_id;

  RETURN v_game_id;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium',
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
  v_slots int[];
  v_start int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), true, _mode, _match_type, 'playing', true)
  RETURNING id INTO v_game_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot)
  SELECT v_game_id, v_uid, 0, 'red', pseudo, false FROM public.profiles WHERE id = v_uid;

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,is_bot,difficulty)
  SELECT v_game_id, NULL, s, c, 'Bot '||s, true, _difficulty
  FROM (VALUES (1,'blue','Bot 1'),(2,'green','Bot 2'),(3,'yellow','Bot 3')) AS t(s,c,n)
  WHERE s < _max_players;

  SELECT array_agg(slot) INTO v_slots FROM public.ludo_participants WHERE game_id=v_game_id;
  v_start := v_slots[1 + public._crypto_rand_int(array_length(v_slots,1))];

  UPDATE public.ludo_games SET status = 'playing', started_at = now(),
    state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')),
    current_turn = v_start
    WHERE id = v_game_id;

  IF v_start <> 0 THEN
    PERFORM public.ludo_bot_move(v_game_id);
  END IF;

  RETURN v_game_id;
END $$;
DROP FUNCTION IF EXISTS public.chess_set_ready(uuid, boolean);

CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g public.chess_games%ROWTYPE;
  v_cfg record;
  v_time_ms int;
  v_swap boolean;
  v_w uuid; v_b uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;

  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready, false) WHERE id = _game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready, false) WHERE id = _game_id;
  ELSE
    RAISE EXCEPTION 'not a player';
  END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    -- Randomiser les couleurs: 50% de chance de swap
    v_swap := (get_byte(extensions.gen_random_bytes(1),0) % 2) = 1;
    IF v_swap THEN
      v_w := v_g.black_id; v_b := v_g.white_id;
      UPDATE public.chess_games
        SET white_id = v_w, black_id = v_b,
            white_ready = ready_black, black_ready = ready_white
        WHERE id = _game_id;
    END IF;

    SELECT * INTO v_cfg FROM public._game_cfg('chess');
    v_time_ms := COALESCE(v_g.time_control_min, 10) * 60 * 1000;
    UPDATE public.chess_games
       SET status = 'playing',
           started_at = now(),
           last_move_at = now(),
           white_time_ms = v_time_ms,
           black_time_ms = v_time_ms,
           turn_deadline = now() + (COALESCE(v_cfg.turn_timer_seconds, 60) || ' seconds')::interval
     WHERE id = _game_id AND status = 'open';
  END IF;
END $$;
