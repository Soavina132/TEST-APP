CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  remaining int;
  last_slot int;
  humans_left int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;

  IF g.status = 'open' THEN
    UPDATE public.profiles p SET balance_ar = balance_ar + g.stake
      FROM public.domino_participants pp
     WHERE pp.game_id = _game_id AND pp.user_id = p.id AND COALESCE(pp.is_bot,false) = false;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      SELECT user_id, 'domino_refund', g.stake, _game_id, 'Game cancelled'
        FROM public.domino_participants
       WHERE game_id = _game_id AND COALESCE(is_bot,false) = false;
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    humans_left := public._domino_active_humans(_game_id);
    IF humans_left = 0 THEN PERFORM public._domino_purge(_game_id); END IF;
    RETURN;
  END IF;

  humans_left := public._domino_active_humans(_game_id);
  IF humans_left = 0 THEN
    UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    PERFORM public._domino_purge(_game_id);
    RETURN;
  END IF;

  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining <= 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      PERFORM public._domino_purge(_game_id);
    END IF;
  END IF;
END $function$
