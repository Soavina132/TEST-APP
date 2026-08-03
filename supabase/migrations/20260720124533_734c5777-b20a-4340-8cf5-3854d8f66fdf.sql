
-- 1) Unify auto-end through _chess_settle so commission always applies
CREATE OR REPLACE FUNCTION public.chess_auto_end(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.status <> 'playing' THEN RETURN; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF NOT _draw AND _winner IS NOT NULL
     AND _winner <> v_g.white_id AND _winner <> v_g.black_id THEN
    RAISE EXCEPTION 'invalid winner';
  END IF;
  PERFORM public._chess_settle(_game_id, _winner, coalesce(_draw,false),
                               CASE WHEN _draw THEN 'draw' ELSE 'auto' END);
END $$;

-- 2) _chess_settle: skip payout when winner is a bot; skip refund side for bot on draws
CREATE OR REPLACE FUNCTION public._chess_settle(_id uuid, _winner uuid, _draw boolean, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_prize numeric;
  v_commission numeric;
  v_white_bot boolean;
  v_black_bot boolean;
  v_winner_is_bot boolean;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_g.status IN ('finished','cancelled') THEN RETURN; END IF;

  v_white_bot := coalesce(v_g.white_is_bot,false);
  v_black_bot := coalesce(v_g.black_is_bot,false);

  IF v_g.mode = 'stake' AND v_g.pot > 0 THEN
    IF _draw THEN
      IF v_g.white_id IS NOT NULL AND NOT v_white_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.white_id;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (v_g.white_id,'chess_refund',v_g.stake,jsonb_build_object('game',_id,'reason','draw'));
      END IF;
      IF v_g.black_id IS NOT NULL AND NOT v_black_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.black_id;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (v_g.black_id,'chess_refund',v_g.stake,jsonb_build_object('game',_id,'reason','draw'));
      END IF;
    ELSIF _winner IS NOT NULL THEN
      v_winner_is_bot := (_winner = v_g.white_id AND v_white_bot)
                      OR (_winner = v_g.black_id AND v_black_bot);
      v_commission := round(v_g.pot * (coalesce(v_g.commission_pct,10)/100.0));
      v_prize := v_g.pot - v_commission;
      IF NOT v_winner_is_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_prize WHERE id = _winner;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (_winner,'chess_win',v_prize,jsonb_build_object('game',_id,'reason',_reason,'commission',v_commission));
      END IF;
      -- If bot wins: real player's stake stays with the house (no credit).
    END IF;
  END IF;

  UPDATE chess_games SET
    status='finished', winner_id=_winner, draw=_draw, end_reason=_reason,
    finished_at=now(), turn_deadline=NULL
  WHERE id = _id;
END $$;

-- 3) chess_add_bot: allow bots on stake games for admin only; bot deposits virtual matching stake
CREATE OR REPLACE FUNCTION public.chess_add_bot(_game_id uuid, _difficulty text DEFAULT 'medium'::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.chess_games%ROWTYPE;
  v_bot_id uuid := gen_random_uuid();
  v_bot_mail text;
  v_intel int;
  v_bot_name text;
  v_is_stake boolean;
  v_add_pot numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;
  IF g.white_id IS NOT NULL AND g.black_id IS NOT NULL THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_is_stake := COALESCE(g.stake,0) > 0;

  IF v_is_stake AND NOT v_is_admin THEN
    RAISE EXCEPTION 'Bots avec mise réservés à l''administrateur';
  END IF;
  IF NOT v_is_admin AND g.host_id <> v_uid AND g.white_id <> v_uid AND g.black_id <> v_uid THEN
    RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
  END IF;

  v_intel := CASE lower(COALESCE(_difficulty,'medium'))
    WHEN 'easy' THEN 30 WHEN 'hard' THEN 95 WHEN 'expert' THEN 100 ELSE 70 END;
  v_bot_name := CASE v_intel WHEN 30 THEN 'Bot Facile'
                             WHEN 95 THEN 'Bot Fort'
                             WHEN 100 THEN 'Bot Expert'
                             ELSE 'Bot Moyen' END;

  v_bot_mail := 'chessbot_' || v_bot_id::text || '@bot.lalaomada.internal';
  INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_user_meta_data, created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_bot_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    v_bot_mail, crypt(gen_random_uuid()::text, gen_salt('bf')), now(),
    jsonb_build_object('pseudo', v_bot_name, 'is_bot', true),
    now(), now(), '', '', '', ''
  );
  UPDATE public.profiles SET balance_ar=0, pseudo=v_bot_name, avatar_url=NULL, is_bot=true WHERE id = v_bot_id;
  DELETE FROM public.transactions WHERE user_id = v_bot_id;

  v_add_pot := CASE WHEN v_is_stake THEN g.stake ELSE 0 END;

  IF g.white_id IS NULL THEN
    UPDATE public.chess_games
       SET white_id=v_bot_id, white_is_bot=true, bot_intelligence=v_intel, bot_name=v_bot_name,
           pot = pot + v_add_pot,
           status='playing', started_at=now(), last_move_at=now()
     WHERE id = _game_id;
  ELSE
    UPDATE public.chess_games
       SET black_id=v_bot_id, black_is_bot=true, bot_intelligence=v_intel, bot_name=v_bot_name,
           pot = pot + v_add_pot,
           status='playing', started_at=now(), last_move_at=now()
     WHERE id = _game_id;
  END IF;
END $$;
