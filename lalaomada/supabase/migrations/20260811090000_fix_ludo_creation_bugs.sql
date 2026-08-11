-- ═══════════════════════════════════════════════════════════════════════
-- FIX: 2 bugs critiques création partie Ludo
--   A. _ludo_maybe_auto_start n'existe pas → join_game plante quand un
--      2ème joueur rejoint une partie publique via find_or_create_game
--   B. create_public_game n'accepte pas _match_type → le replay crée des
--      parties avec match_type='groupe' par défaut au lieu de 'solo'
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG A: Créer _ludo_maybe_auto_start
-- Appelée par join_game quand un joueur rejoint une partie publique.
-- Démarre automatiquement la partie si elle est pleine.
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._ludo_maybe_auto_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count int;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RETURN; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;

  IF v_count >= v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic')),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

REVOKE EXECUTE ON FUNCTION public._ludo_maybe_auto_start(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._ludo_maybe_auto_start(uuid) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG B: create_public_game — ajouter _match_type
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_public_game(integer, numeric, text);

CREATE OR REPLACE FUNCTION public.create_public_game(
  _max_players integer,
  _stake numeric,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
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
  v_commission numeric;
  v_paused boolean;
  v_banned boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;

  IF _stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note)
      VALUES (v_uid, 'ludo_stake', -_stake, 'Mise Ludo');
  END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, status, is_private, pot, mode, match_type, commission_pct)
    VALUES (v_uid, _max_players, _stake, 'open', false, _stake, v_mode, COALESCE(_match_type, 'solo'), COALESCE(v_commission, 10))
    RETURNING id INTO v_id;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.create_public_game(integer, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_public_game(integer, numeric, text, text) TO authenticated;
