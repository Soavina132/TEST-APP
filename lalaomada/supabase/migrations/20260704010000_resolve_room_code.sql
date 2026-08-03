-- resolve_room_code: cherche un code dans toutes les tables de jeux
-- Retourne slug + game_id si trouvé, sinon lève une exception.
CREATE OR REPLACE FUNCTION public.resolve_room_code(_code text)
RETURNS TABLE(slug text, game_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_code text := upper(trim(_code));
  v_id   uuid;
BEGIN
  SELECT id INTO v_id FROM public.ludo_games     WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'ludo'::text, v_id; RETURN; END IF;

  SELECT id INTO v_id FROM public.domino_games   WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'domino'::text, v_id; RETURN; END IF;

  SELECT id INTO v_id FROM public.fanorona_games WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'fanorona'::text, v_id; RETURN; END IF;

  SELECT id INTO v_id FROM public.chess_games    WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'chess'::text, v_id; RETURN; END IF;

  SELECT id INTO v_id FROM public.rami_games     WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'rami'::text, v_id; RETURN; END IF;

  SELECT id INTO v_id FROM public.poker_games    WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'poker'::text, v_id; RETURN; END IF;

  RAISE EXCEPTION 'Code introuvable ou partie déjà commencée : %', v_code;
END $$;

REVOKE ALL ON FUNCTION public.resolve_room_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_room_code(text) TO authenticated;
