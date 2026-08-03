
-- ============ ludo_join ============
CREATE OR REPLACE FUNCTION public.ludo_join(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.ludo_games%ROWTYPE;
  v_balance numeric;
  v_name text;
  v_count int;
  v_slot int;
  v_color text;
  v_colors text[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'Partie non disponible'; END IF;

  -- Déjà participant → simplement renvoyer
  IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid) THEN
    RETURN _game_id;
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF COALESCE(g.stake,0) > 0 AND COALESCE(v_balance,0) < g.stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;

  -- Prochain slot libre
  SELECT s INTO v_slot FROM generate_series(0, g.max_players-1) s
    WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id = _game_id)
    ORDER BY s LIMIT 1;
  v_color := v_colors[v_slot + 1];

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    VALUES (_game_id, v_uid, v_slot, v_color, COALESCE(v_name, 'Joueur'));

  IF COALESCE(g.stake,0) > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'ludo_stake', -g.stake, _game_id, 'Rejoindre partie Ludo');
    UPDATE public.ludo_games SET pot = pot + g.stake WHERE id = _game_id;
  END IF;

  RETURN _game_id;
END $$;

GRANT EXECUTE ON FUNCTION public.ludo_join(uuid) TO authenticated;

-- ============ poker_join ============
CREATE OR REPLACE FUNCTION public.poker_join(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  v_balance numeric;
  v_count int;
  v_seat int;
  v_chips numeric := 10000;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.poker_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'waiting' AND g.status <> 'open' THEN RAISE EXCEPTION 'Partie non disponible'; END IF;

  IF EXISTS(SELECT 1 FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid) THEN
    RETURN _game_id;
  END IF;

  SELECT count(*) INTO v_count FROM public.poker_players WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Table pleine'; END IF;

  IF COALESCE(g.stake,0) > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF COALESCE(v_balance,0) < g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'poker_stake', -g.stake, _game_id, 'Rejoindre table poker');
    UPDATE public.poker_games SET pot = pot + g.stake WHERE id = _game_id;
  END IF;

  SELECT s INTO v_seat FROM generate_series(0, g.max_players-1) s
    WHERE s NOT IN (SELECT seat FROM public.poker_players WHERE game_id = _game_id)
    ORDER BY s LIMIT 1;

  INSERT INTO public.poker_players(game_id, user_id, seat, chips, status, is_ready, is_bot)
    VALUES (_game_id, v_uid, v_seat, v_chips, 'waiting', FALSE, FALSE);

  RETURN _game_id;
END $$;

GRANT EXECUTE ON FUNCTION public.poker_join(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
