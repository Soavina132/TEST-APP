-- ═══════════════════════════════════════════════════════════════════
-- FIX: Match nul = remboursement TOTAL sans commission (0% prélevé)
-- Inverse la migration 20260819170000 qui AJOUTAIT la commission
-- sur les nuls. Règle: sur match nul, on rembourse TOUT le pot
-- sans déduire les 10%.
--
-- Jeux concernés: Échecs, Fanorona, Domino (victoire direct)
-- Domino mode "par point": match nul → continuer au prochain round
-- Domino mode "victoire direct": match nul → rembourser + finir
-- ═══════════════════════════════════════════════════════════════════

-- ── 1. Chess: _chess_payout — NO commission on draw ──────────────────
CREATE OR REPLACE FUNCTION public._chess_payout(_game_id uuid, _winner uuid, _draw boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_g chess_games%ROWTYPE; v_net numeric; v_each numeric;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  IF _draw THEN
    -- Match nul: remboursement TOTAL, SANS commission
    v_each := v_g.pot / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO transactions(user_id,type,amount,ref_id,note)
        VALUES (v_g.white_id,'chess_draw',v_each,_game_id,'Chess match nul – remboursement intégral');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO transactions(user_id,type,amount,ref_id,note)
        VALUES (v_g.black_id,'chess_draw',v_each,_game_id,'Chess match nul – remboursement intégral');
    END IF;
    UPDATE chess_games SET status='finished', draw=true, finished_at=now(), turn_deadline=NULL WHERE id=_game_id;
  ELSE
    -- Normal win: commission IS deducted (normal)
    v_net := v_g.pot * (100 - COALESCE(v_g.commission_pct, 10)) / 100.0;
    IF _winner IS NOT NULL THEN
      UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
      INSERT INTO transactions(user_id,type,amount,ref_id,note)
        VALUES (_winner,'chess_payout',v_net,_game_id,'Chess win');
    END IF;
    UPDATE chess_games SET status='finished', winner_id=_winner, finished_at=now(), turn_deadline=NULL WHERE id=_game_id;
  END IF;
END $$;

-- ── 2. Chess: _chess_settle — NO commission on draw ───────────────────
CREATE OR REPLACE FUNCTION public._chess_settle(
  _id uuid, _winner uuid, _draw boolean, _reason text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_net numeric;
  v_each numeric;
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
      -- Match nul: remboursement TOTAL, SANS commission
      v_each := v_g.pot / 2;
      IF v_g.white_id IS NOT NULL AND NOT v_white_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (v_g.white_id,'chess_draw',v_each,jsonb_build_object('game',_id,'reason','draw'));
      END IF;
      IF v_g.black_id IS NOT NULL AND NOT v_black_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (v_g.black_id,'chess_draw',v_each,jsonb_build_object('game',_id,'reason','draw'));
      END IF;
    ELSIF _winner IS NOT NULL THEN
      -- Normal win: commission IS deducted
      v_net := v_g.pot * (100 - COALESCE(v_g.commission_pct,10)) / 100.0;
      v_winner_is_bot := (_winner = v_g.white_id AND v_white_bot)
                      OR (_winner = v_g.black_id AND v_black_bot);
      IF NOT v_winner_is_bot THEN
        UPDATE profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
        INSERT INTO transactions(user_id,type,amount,meta)
          VALUES (_winner,'chess_win',v_net,jsonb_build_object('game',_id,'reason',_reason));
      END IF;
    END IF;
  END IF;

  UPDATE chess_games SET
    status='finished', winner_id=_winner, draw=_draw, end_reason=_reason,
    finished_at=now(), turn_deadline=NULL
  WHERE id = _id;
END $$;

REVOKE EXECUTE ON FUNCTION public._chess_settle(uuid, uuid, boolean, text) FROM anon, authenticated;

-- ── 3. Chess: chess_finish — NO commission on draw ───────────────────
CREATE OR REPLACE FUNCTION public.chess_finish(
  _id      uuid,
  _winner  uuid,
  _draw    boolean DEFAULT false,
  _reason  text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_net numeric;
  v_each numeric;
BEGIN
  SELECT * INTO v_g FROM public.chess_games WHERE id = _id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_g.status = 'finished' THEN RETURN; END IF;

  IF _draw THEN
    -- Match nul: remboursement TOTAL, SANS commission
    v_each := v_g.pot / 2;
    IF v_g.white_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.white_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.white_id, 'chess_draw', v_each, _id, 'Chess match nul – remboursement intégral');
    END IF;
    IF v_g.black_id IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = v_g.black_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_g.black_id, 'chess_draw', v_each, _id, 'Chess match nul – remboursement intégral');
    END IF;
    UPDATE public.chess_games
      SET status = 'finished', draw = true, end_reason = _reason, finished_at = now(), turn_deadline = NULL
      WHERE id = _id;
  ELSE
    -- Normal win: commission IS deducted
    v_net := v_g.pot * (100 - COALESCE(v_g.commission_pct, 10)) / 100.0;
    IF _winner IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + v_net WHERE id = _winner;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (_winner, 'chess_payout', v_net, _id, 'Chess win');
    END IF;
    UPDATE public.chess_games
      SET status = 'finished', winner_id = _winner, end_reason = _reason, finished_at = now(), turn_deadline = NULL
      WHERE id = _id;
  END IF;
END $$;

GRANT EXECUTE ON FUNCTION public.chess_finish(uuid, uuid, boolean, text) TO authenticated;

-- ── 4. Fanorona: _fanorona_draw_refund — NO commission on draw ────────
CREATE OR REPLACE FUNCTION public._fanorona_draw_refund(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
  p record;
  v_each numeric;
  v_active_count int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  IF g.stake > 0 AND g.pot > 0 THEN
    -- Match nul: remboursement TOTAL, SANS commission
    SELECT count(*) INTO v_active_count
      FROM public.fanorona_participants
      WHERE game_id = _game_id AND forfeited = false AND is_bot = false;

    IF v_active_count > 0 THEN
      v_each := g.pot / v_active_count;
      FOR p IN SELECT user_id FROM public.fanorona_participants
               WHERE game_id = _game_id AND forfeited = false AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + v_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'fanorona_draw', v_each, _game_id, 'Fanorona match nul – remboursement intégral');
      END LOOP;
    END IF;
  END IF;

  UPDATE public.fanorona_games
     SET status = 'finished', result = 'draw', draw_offered_by = NULL,
         winner_id = NULL, finished_at = now(), updated_at = now()
   WHERE id = _game_id;
END
$function$;

REVOKE EXECUTE ON FUNCTION public._fanorona_draw_refund(uuid) FROM anon, authenticated;

-- ── 5. Domino: _domino_finalize — NO commission on draw ───────────────
CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; winner_uid uuid; v_is_bot boolean := false;
  payout numeric; p record; n_active integer;
  refund_each numeric; st jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  IF _winner_slot IS NULL THEN
    -- Match nul: remboursement TOTAL du pot, SANS commission
    SELECT count(*) INTO n_active
      FROM public.domino_participants
      WHERE game_id = _game_id AND forfeited = false AND is_bot = false;

    IF n_active > 0 AND g.pot > 0 THEN
      refund_each := floor(g.pot / n_active);
      FOR p IN SELECT user_id FROM public.domino_participants
               WHERE game_id = _game_id AND forfeited = false AND user_id IS NOT NULL AND is_bot = false
      LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + refund_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul – remboursement intégral');
      END LOOP;
    END IF;
    st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', 'null'::jsonb, true);
    UPDATE public.domino_games
       SET status='finished', winner_id=NULL, finished_at=now(), state=st
     WHERE id=_game_id;
    RETURN;
  END IF;

  -- Normal win: commission IS deducted (normal behavior)
  SELECT user_id, COALESCE(is_bot, false) INTO winner_uid, v_is_bot
  FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL AND NOT v_is_bot THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  st := jsonb_set(COALESCE(g.state,'{}'::jsonb), '{winner_slot}', to_jsonb(_winner_slot), true);
  UPDATE public.domino_games
     SET status='finished', winner_id=winner_uid, finished_at=now(), state=st
   WHERE id=_game_id;
END
$function$;

-- ── 6. Domino: _domino_end_round — classic mode + tie → finalize ─────
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record;
  st jsonb;
  v_scores jsonb;
  v_col_scores jsonb;
  v_slot int;
  v_pts int;
  v_total int;
  v_rounds int;
  v_winner_overall int;
  v_pass_count int;
  v_target int;
  v_mode text;
  v_next_starter int := 0;
  v_reveal       interval := interval '2.5 seconds';
  v_break_total  interval := interval '7 seconds';
  v_part record;
  v_all_blocked boolean := false;
  v_lowest int;
  v_lowest_slot int;
  v_tie_count int;
  v_key text;
  v_winner_uid text := null;
  v_round_score int := 0;
  v_hand_pips jsonb := '{}'::jsonb;
  v_final_hands jsonb := '{}'::jsonb;
  v_hand jsonb;
  v_pips int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND THEN RETURN; END IF;

  st := g.state;
  v_mode := COALESCE(g.mode, 'classic');
  v_target := COALESCE(g.target_score, 0);

  v_pass_count := COALESCE(NULLIF(st->>'passes','')::int, 0);
  IF v_pass_count >= (SELECT count(*) FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false) THEN
    v_all_blocked := true;
  END IF;

  v_scores := COALESCE(st->'round_scores', '{}'::jsonb);
  v_col_scores := COALESCE(g.scores, '{}'::jsonb);

  FOR v_part IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    v_key := COALESCE(v_part.user_id::text, 'bot_'||v_part.slot::text);
    v_hand := st->'hands'->v_part.slot::text;
    IF v_hand IS NOT NULL THEN
      SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pips
        FROM jsonb_array_elements(v_hand) AS tile;
    ELSE
      v_pips := 0;
    END IF;
    v_hand_pips := v_hand_pips || jsonb_build_object(v_key, v_pips);
    v_final_hands := v_final_hands || jsonb_build_object(v_key, COALESCE(v_hand, '[]'::jsonb));
    v_total := v_total + v_pips;
  END LOOP;

  IF v_all_blocked AND _winner_slot IS NULL THEN
    v_lowest := 999999;
    v_lowest_slot := 0;
    v_tie_count := 0;
    FOR v_part IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      v_key := COALESCE(v_part.user_id::text, 'bot_'||v_part.slot::text);
      v_pips := COALESCE((v_hand_pips->>v_key)::int, 0);
      IF v_pips < v_lowest THEN
        v_lowest := v_pips;
        v_lowest_slot := v_part.slot;
        v_tie_count := 1;
      ELSIF v_pips = v_lowest THEN
        v_tie_count := v_tie_count + 1;
      END IF;
    END LOOP;

    IF v_tie_count > 1 THEN
      _winner_slot := NULL;
    ELSE
      _winner_slot := v_lowest_slot;
    END IF;
  END IF;

  IF _winner_slot IS NOT NULL THEN
    SELECT COALESCE(user_id::text, 'bot_'||slot::text) INTO v_key
      FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
    v_winner_uid := v_key;
    v_round_score := GREATEST(0, v_total - COALESCE((v_hand_pips->>v_key)::int, 0));
    SELECT COALESCE((v_scores->>_winner_slot::text)::int, 0) + v_round_score INTO v_pts;
    v_scores := jsonb_set(v_scores, ARRAY[_winner_slot::text], to_jsonb(v_pts), true);
    SELECT COALESCE((v_col_scores->>v_key)::int, 0) + v_round_score INTO v_pts;
    v_col_scores := jsonb_set(v_col_scores, ARRAY[v_key], to_jsonb(v_pts), true);
  END IF;

  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', v_winner_uid,
    'winner_slot', _winner_slot,
    'round_score', v_round_score,
    'hand_pips', v_hand_pips,
    'final_hands', v_final_hands,
    'blocked', v_all_blocked,
    'tie', (v_tie_count > 1),
    'round', COALESCE(NULLIF(st->>'round','')::int, 0)
  ), true);

  v_winner_overall := -1;
  IF v_mode = 'points' AND v_target > 0 THEN
    FOR v_slot IN SELECT DISTINCT (jsonb_object_keys(v_scores))::int LOOP
      IF (v_scores->>v_slot::text)::int >= v_target THEN
        v_winner_overall := v_slot;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_winner_overall := COALESCE(_winner_slot, -1);
  END IF;

  IF v_winner_overall >= 0 THEN
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{winner_slot}', to_jsonb(v_winner_overall), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);

    SELECT user_id INTO v_key FROM public.domino_participants
      WHERE game_id = _game_id AND slot = v_winner_overall;

    UPDATE public.domino_games
       SET state = st, status = 'finished',
           winner_id = v_key,
           scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;

    PERFORM public._domino_payout(_game_id, v_winner_overall);
    RETURN;
  END IF;

  -- ═══ FIX: Classic mode + tie → finalize with refund (not new round) ═══
  IF v_mode <> 'points' OR v_target <= 0 THEN
    -- Classic (victoire direct) with no winner (tie)
    -- → refund all bets and end game, NOT start a new round
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);
    UPDATE public.domino_games
       SET state = st, scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, NULL);
    RETURN;
  END IF;

  -- Points mode + no winner yet → start new round
  v_rounds := COALESCE(NULLIF(st->>'round','')::int, 0) + 1;
  st := jsonb_set(st, '{round}', to_jsonb(v_rounds), true);
  st := jsonb_set(st, '{round_scores}', v_scores, true);

  PERFORM public._domino_deal(_game_id, st, v_next_starter);

  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text), true);

  UPDATE public.domino_games
     SET state = st, scores = v_col_scores,
         current_turn = v_next_starter,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END $$;
