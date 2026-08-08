-- ═══════════════════════════════════════════════════════════════════════
-- FIX: rami_create + rami_join_code — colonnes profiles/transactions
-- inexistantes causaient une erreur "column does not exist" à la création
-- et à la jonction par code de partie Rami.
--
-- Bug: référence à profiles.balance / profiles.display_name (n'existent
-- pas — seules balance_ar et pseudo existent) et à transactions.status /
-- transactions.metadata (n'existent pas — seules ref_id / note existent).
-- ═══════════════════════════════════════════════════════════════════════

-- 1. rami_create: fix balance_ar / pseudo -----------------------------
CREATE OR REPLACE FUNCTION public.rami_create(
  _stake numeric, _max int, _private boolean, _commission int,
  _game_mode text DEFAULT 'bordel', _joker_mode text DEFAULT 'classique'
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _id uuid; _code text; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _code := public._rami_gen_code();
  INSERT INTO public.rami_games (room_code, is_private, stake, max_players, commission_pct, created_by, pot, game_mode, joker_mode)
    VALUES (_code, COALESCE(_private, true), _stake, _max, COALESCE(_commission,10), _uid, _stake, COALESCE(_game_mode, 'bordel'), COALESCE(_joker_mode, 'classique'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;
  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $$;
REVOKE ALL ON FUNCTION public.rami_create(numeric,int,boolean,int,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric,int,boolean,int,text,text) TO authenticated;

-- 2. rami_join_code: fix balance_ar / pseudo / transactions cols ------
CREATE OR REPLACE FUNCTION public.rami_join_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE _uid uuid := auth.uid(); _g rami_games; _slot int; _bal numeric; _name text; _count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM rami_games WHERE room_code = upper(_code) FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM rami_participants WHERE game_id=_g.id AND user_id=_uid) THEN RETURN _g.id; END IF;
  SELECT count(*) INTO _count FROM rami_participants WHERE game_id=_g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;
  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name FROM profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  _slot := _count;
  IF _g.stake > 0 THEN
    UPDATE profiles SET balance_ar = balance_ar - _g.stake WHERE id = _uid;
    UPDATE rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO transactions (user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami via code');
  END IF;
  INSERT INTO rami_participants (game_id, user_id, slot, display_name) VALUES (_g.id, _uid, _slot, _name);
  RETURN _g.id;
END $$;
REVOKE ALL ON FUNCTION public.rami_join_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join_code(text) TO authenticated;
