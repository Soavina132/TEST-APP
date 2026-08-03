-- =====================================================================
-- Direct join by game ID for chess and rami (no room code needed)
-- Allows public chess/rami games to be joined directly from the listing
-- =====================================================================

-- ===================== chess_join =====================
CREATE OR REPLACE FUNCTION public.chess_join(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_g    chess_games%ROWTYPE;
  v_bal  numeric;
  v_flip boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND          THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'partie déjà commencée ou terminée'; END IF;
  IF v_g.host_id = v_uid  THEN RAISE EXCEPTION 'tu es déjà dans cette partie'; END IF;
  IF v_g.is_private       THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;

  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Random colour assignment (same logic as chess_join_code)
  v_flip := (random() < 0.5);
  IF v_flip THEN
    UPDATE chess_games
      SET black_id = v_uid, status = 'playing', started_at = now(), pot = pot + v_g.stake
      WHERE id = v_g.id;
  ELSE
    UPDATE chess_games
      SET white_id = v_uid, black_id = v_g.host_id, status = 'playing', started_at = now(), pot = pot + v_g.stake
      WHERE id = v_g.id;
  END IF;

  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'chess_stake', -v_g.stake, v_g.id, 'Rejoindre partie chess publique');

  RETURN v_g.id;
END $$;

REVOKE ALL ON FUNCTION public.chess_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_join(uuid) TO authenticated;


-- ===================== rami_join =====================
CREATE OR REPLACE FUNCTION public.rami_join(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _uid   uuid := auth.uid();
  _g     rami_games%ROWTYPE;
  _slot  int;
  _bal   numeric;
  _name  text;
  _count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT * INTO _g FROM rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.id IS NULL           THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting'  THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF _g.is_private            THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;

  IF EXISTS (SELECT 1 FROM rami_participants WHERE game_id = _g.id AND user_id = _uid) THEN
    RETURN _g.id;
  END IF;

  SELECT count(*) INTO _count FROM rami_participants WHERE game_id = _g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;

  SELECT balance, COALESCE(display_name, pseudo, 'Joueur') INTO _bal, _name
    FROM profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  _slot := _count;

  IF _g.stake > 0 THEN
    UPDATE profiles SET balance = balance - _g.stake WHERE id = _uid;
    UPDATE rami_games  SET pot = pot + _g.stake         WHERE id = _g.id;
    INSERT INTO transactions(user_id, type, amount, status, metadata)
      VALUES (_uid, 'game_stake', -_g.stake, 'completed',
              jsonb_build_object('game', 'rami', 'game_id', _g.id));
  END IF;

  INSERT INTO rami_participants(game_id, user_id, slot, display_name)
    VALUES (_g.id, _uid, _slot, _name);

  RETURN _g.id;
END $$;

REVOKE ALL ON FUNCTION public.rami_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join(uuid) TO authenticated;
