-- FIX: ludo_quit — column 'finished' doesn't exist, it's 'forfeited'
-- Date: 2026-08-22 00:08

CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid UUID := auth.uid();
  g public.ludo_games%ROWTYPE;
  v_slot INT;
  v_winner UUID;
  v_remaining INT;
  v_pawns jsonb;
  i INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;

  SELECT slot INTO v_slot FROM public.ludo_participants
    WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- Si partie en attente (open), remboursement simple
  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'refund', g.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  -- Partie en cours : forfait
  v_pawns := g.state->'pawns';

  IF v_pawns IS NOT NULL AND jsonb_typeof(v_pawns) = 'array' THEN
    FOR i IN 0..jsonb_array_length(v_pawns)-1 LOOP
      IF (v_pawns->i->>'player')::int = v_slot THEN
        v_pawns := jsonb_set(v_pawns, ARRAY[i::text, 'finished'], 'true'::jsonb);
      END IF;
    END LOOP;
    UPDATE public.ludo_games
      SET state = jsonb_set(g.state, ARRAY['pawns'], v_pawns)
      WHERE id = _game_id;
  ELSE
    RAISE NOTICE 'ludo_quit: pawns is not an array (%)', jsonb_typeof(v_pawns);
  END IF;

  -- ✅ Use 'forfeited' (actual column name), not 'finished'
  UPDATE public.ludo_participants SET forfeited = true
    WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;

  -- Count remaining non-forfeited human players
  SELECT count(*) INTO v_remaining FROM public.ludo_participants
    WHERE game_id = _game_id AND is_bot = false AND forfeited = false;

  IF v_remaining <= 1 THEN
    SELECT user_id INTO v_winner FROM public.ludo_participants
      WHERE game_id = _game_id AND is_bot = false AND forfeited = false LIMIT 1;
    PERFORM public._ludo_finalize(_game_id, v_winner, 'quit');
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.ludo_quit(_game_id uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_quit(_game_id uuid) TO authenticated;
