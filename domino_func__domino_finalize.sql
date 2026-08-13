CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g record; winner_uid uuid; payout numeric; p record; n_active integer; refund_each numeric;
  st jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  IF _winner_slot IS NULL THEN
    SELECT count(*) INTO n_active FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF n_active > 0 AND g.pot > 0 THEN
      refund_each := floor(g.pot / n_active);
      FOR p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false AND user_id IS NOT NULL LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + refund_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul – remboursement');
      END LOOP;
    END IF;
    st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', 'null'::jsonb, true);
    UPDATE public.domino_games
       SET status='finished', winner_id=NULL, finished_at=now(), state=st
     WHERE id=_game_id;
    RETURN;
  END IF;

  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', to_jsonb(_winner_slot), true);
  UPDATE public.domino_games
     SET status='finished', winner_id=winner_uid, finished_at=now(), state=st
   WHERE id=_game_id;
END $function$
