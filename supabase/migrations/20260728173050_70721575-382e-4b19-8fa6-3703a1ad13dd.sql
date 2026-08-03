CREATE OR REPLACE FUNCTION public._auto_cancel_open_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  r record;
  v_min int;
  v_iv interval;
BEGIN
  SELECT COALESCE(game_invite_timeout_minutes, 6) INTO v_min FROM public.app_settings WHERE id = 1;
  IF v_min IS NULL OR v_min <= 0 THEN v_min := 6; END IF;
  v_iv := (v_min || ' minutes')::interval;

  FOR r IN SELECT id, stake FROM public.fanorona_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.fanorona_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id
        AND pp.user_id IS NOT NULL AND COALESCE(pp.is_bot,false) = false
        AND r.stake > 0;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'fanorona_refund', r.stake, r.id, 'Partie expirée (6 min)'
      FROM public.fanorona_participants
      WHERE game_id = r.id AND user_id IS NOT NULL AND COALESCE(is_bot,false) = false
        AND r.stake > 0;
    UPDATE public.fanorona_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake, host_id FROM public.chess_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    IF r.host_id IS NOT NULL AND r.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + r.stake WHERE id = r.host_id;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (r.host_id, 'chess_refund', r.stake, r.id, 'Partie expirée (6 min)');
    END IF;
    UPDATE public.chess_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.domino_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.domino_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id
        AND pp.user_id IS NOT NULL AND COALESCE(pp.is_bot,false) = false
        AND r.stake > 0;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'domino_refund', r.stake, r.id, 'Partie expirée (6 min)'
      FROM public.domino_participants
      WHERE game_id = r.id AND user_id IS NOT NULL AND COALESCE(is_bot,false) = false
        AND r.stake > 0;
    UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.rami_games WHERE status IN ('waiting','open') AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.rami_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id
        AND pp.user_id IS NOT NULL AND COALESCE(pp.is_bot,false) = false
        AND r.stake > 0;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'rami_refund', r.stake, r.id, 'Partie expirée (6 min)'
      FROM public.rami_participants
      WHERE game_id = r.id AND user_id IS NOT NULL AND COALESCE(is_bot,false) = false
        AND r.stake > 0;
    UPDATE public.rami_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.ludo_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.ludo_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id
        AND pp.user_id IS NOT NULL AND COALESCE(pp.is_bot,false) = false
        AND r.stake > 0;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'ludo_refund', r.stake, r.id, 'Partie expirée (6 min)'
      FROM public.ludo_participants
      WHERE game_id = r.id AND user_id IS NOT NULL AND COALESCE(is_bot,false) = false
        AND r.stake > 0;
    UPDATE public.ludo_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.poker_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.poker_players pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id
        AND pp.user_id IS NOT NULL AND COALESCE(pp.is_bot,false) = false
        AND r.stake > 0;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'poker_refund', r.stake, r.id, 'Partie expirée (6 min)'
      FROM public.poker_players
      WHERE game_id = r.id AND user_id IS NOT NULL AND COALESCE(is_bot,false) = false
        AND r.stake > 0;
    UPDATE public.poker_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  FOR r IN SELECT id, stake FROM public.petanque_games WHERE status='open' AND created_at < now() - v_iv
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.petanque_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id
        AND pp.user_id IS NOT NULL AND COALESCE(pp.is_bot,false) = false
        AND r.stake > 0;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'petanque_refund', r.stake, r.id, 'Partie expirée (6 min)'
      FROM public.petanque_participants
      WHERE game_id = r.id AND user_id IS NOT NULL AND COALESCE(is_bot,false) = false
        AND r.stake > 0;
    UPDATE public.petanque_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;
END $function$;

SELECT public._auto_cancel_open_games();