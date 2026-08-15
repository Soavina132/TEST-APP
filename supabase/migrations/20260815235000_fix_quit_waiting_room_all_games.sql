-- Fix: Quit waiting room behavior for ALL games
-- Rules:
--   1. Non-host quits waiting room → refund ONLY that player, remove them, room stays OPEN
--   2. Host quits waiting room → refund ALL players, cancel/delete game
--   3. Timer expires (_auto_cancel_open_games) → refund ALL players, cancel game (already works)
--
-- This applies to: Ludo, Domino, Chess, Fanorona, Rami, Poker

-- ════════════════════════════════════════════════════════════════════════
-- 1. LUDO
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
  v_pawns jsonb; i INT;
  v_is_host boolean; v_part record;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    v_is_host := (g.host_id = v_uid);

    IF v_is_host THEN
      -- Host quits: refund ALL participants and cancel game
      FOR v_part IN SELECT user_id FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_part.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_part.user_id, 'refund', g.stake, _game_id, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.ludo_games SET status = 'cancelled', finished_at = now(), pot = 0 WHERE id = _game_id;
      PERFORM public._ludo_purge(_game_id);
    ELSE
      -- Non-host quits: refund only this player, keep room open
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
      UPDATE public.ludo_games SET pot = pot - g.stake WHERE id = _game_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_uid, 'refund', g.stake, _game_id, 'Quitter salle d''attente');
      DELETE FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;
    END IF;
    RETURN;
  END IF;

  -- Playing status: same as before
  st := g.state;
  IF st ? 'pawns' AND (st->'pawns') ? v_slot::text THEN
    v_pawns := '[]'::jsonb;
    FOR i IN 1..4 LOOP
      v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    END LOOP;
    st := jsonb_set(st, ARRAY['pawns', v_slot::text], v_pawns);
  END IF;

  IF g.is_solo OR g.match_type = 'solo' THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    UPDATE public.ludo_games SET status='finished', finished_at=now(), state=st WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
  END IF;
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  IF public._ludo_active_humans(_game_id) > 0 THEN
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
  ELSE
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
  END IF;
END $function$;

REVOKE ALL ON FUNCTION public.ludo_quit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_quit(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 2. DOMINO — add 'open' status handling to domino_forfeit
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void AS $$
DECLARE
  _uid uuid := auth.uid();
  _game record;
  _part record;
  _is_host boolean;
  _remaining int;
  _p record;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF _game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  SELECT * INTO _part FROM public.domino_participants
    WHERE game_id = _game_id AND user_id = _uid AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- ── Waiting room handling ──
  IF _game.status = 'open' THEN
    _is_host := (_game.host_id = _uid);

    IF _is_host THEN
      -- Host quits: refund ALL participants and cancel
      FOR _p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, description)
          VALUES (_p.user_id, 'domino_refund', _game.stake, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), updated_at = now() WHERE id = _game_id;
    ELSE
      -- Non-host quits: refund only this player, keep room open
      UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, description)
        VALUES (_uid, 'domino_refund', _game.stake, 'Quitter salle d''attente');
      DELETE FROM public.domino_participants WHERE id = _part.id;
      UPDATE public.domino_games SET pot = pot - _game.stake, updated_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- ── Playing status: use internal forfeit ──
  PERFORM public.domino_forfeit_internal(_game_id, _part);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.domino_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.domino_forfeit(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 3. CHESS — fix host quit in waiting room
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.chess_forfeit(_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game public.chess_games%ROWTYPE;
  v_stake numeric;
  v_is_host boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.chess_games WHERE id = _id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  IF v_game.status = 'finished' THEN RETURN; END IF;

  IF v_game.status = 'open' THEN
    v_is_host := (v_game.host_id = v_uid);

    IF v_is_host THEN
      -- Host quits: refund ALL players and cancel
      IF v_game.stake > 0 THEN
        IF v_game.white_id IS NOT NULL THEN
          UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_game.white_id;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (v_game.white_id, 'chess_refund', v_game.stake, _id, 'Annulation salle d''attente (hôte)');
        END IF;
        IF v_game.black_id IS NOT NULL THEN
          UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_game.black_id;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (v_game.black_id, 'chess_refund', v_game.stake, _id, 'Annulation salle d''attente (hôte)');
        END IF;
      END IF;
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = _id;
    ELSE
      -- Non-host quits: refund only this player, keep room open
      IF v_game.stake > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_game.stake WHERE id = v_uid;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_uid, 'chess_refund', v_game.stake, _id, 'Quitter salle d''attente');
      END IF;
      UPDATE public.chess_games SET
        white_id = CASE WHEN white_id = v_uid THEN NULL ELSE white_id END,
        black_id = CASE WHEN black_id = v_uid THEN NULL ELSE black_id END
      WHERE id = _id;
    END IF;
    RETURN;
  END IF;

  -- Playing: treat as resignation (existing behavior)
  IF v_game.status = 'playing' THEN
    IF v_game.stake > 0 THEN
      IF v_game.white_id = v_uid THEN
        UPDATE public.profiles SET balance_ar = balance_ar + (v_game.pot * (100 - v_game.commission_pct) / 100)
          WHERE id = v_game.black_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_game.black_id, 'chess_win', v_game.pot * (100 - v_game.commission_pct) / 100, _id, 'Win by forfeit');
      ELSIF v_game.black_id = v_uid THEN
        UPDATE public.profiles SET balance_ar = balance_ar + (v_game.pot * (100 - v_game.commission_pct) / 100)
          WHERE id = v_game.white_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_game.white_id, 'chess_win', v_game.pot * (100 - v_game.commission_pct) / 100, _id, 'Win by forfeit');
      END IF;
    END IF;
    UPDATE public.chess_games SET status = 'finished', finished_at = now() WHERE id = _id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.chess_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_forfeit(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 4. FANORONA — fix: non-host should NOT close the room
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fanorona_forfeit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  my_slot int;
  v_is_host boolean;
  v_p record;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status NOT IN ('open','playing') THEN RETURN; END IF;
  SELECT slot INTO my_slot FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL THEN RETURN; END IF;

  IF g.status = 'open' THEN
    v_is_host := (g.host_id = v_uid);

    IF v_is_host THEN
      -- Host quits: refund ALL and cancel
      FOR v_p IN SELECT user_id FROM public.fanorona_participants WHERE game_id = _game_id LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_p.user_id, 'fanorona_refund', g.stake, _game_id, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.fanorona_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    ELSE
      -- Non-host quits: refund only this player, keep room open
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_uid, 'fanorona_refund', g.stake, _game_id, 'Quitter salle d''attente');
      DELETE FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid;
    END IF;
    RETURN;
  END IF;

  -- Playing: mark forfeited and finalize
  UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = v_uid;
  PERFORM public._fanorona_finalize(_game_id, 1 - my_slot);
END $$;

REVOKE ALL ON FUNCTION public.fanorona_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_forfeit(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 5. RAMI — fix: non-host should NOT finish the game
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.rami_forfeit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  _uid uuid := auth.uid();
  _g public.rami_games;
  _alive uuid[];
  _winner uuid;
  _payout numeric;
  _comm numeric;
  _parts int[];
  _next int;
  _is_host boolean;
  _p record;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting', 'playing') THEN RETURN; END IF;

  -- ── Waiting room handling ──
  IF _g.status = 'waiting' THEN
    _is_host := (_g.created_by = _uid);

    IF _is_host THEN
      -- Host quits: refund ALL and cancel
      FOR _p IN SELECT user_id FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + _g.stake WHERE id = _p.user_id;
        INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
          VALUES (_p.user_id, 'rami_refund', _g.stake, _game_id, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.rami_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    ELSE
      -- Non-host quits: refund only this player, keep room open
      UPDATE public.profiles SET balance_ar = balance_ar + _g.stake WHERE id = _uid;
      INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
        VALUES (_uid, 'rami_refund', _g.stake, _game_id, 'Quitter salle d''attente');
      DELETE FROM public.rami_participants WHERE game_id = _game_id AND user_id = _uid;
    END IF;
    RETURN;
  END IF;

  -- ── Playing status (existing behavior) ──
  UPDATE public.rami_participants SET forfeited = true WHERE game_id = _game_id AND user_id = _uid;
  SELECT array_agg(user_id) INTO _alive FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;

  IF COALESCE(array_length(_alive, 1), 0) = 1 THEN
    _winner := _alive[1];
    _comm := round(_g.pot * _g.commission_pct / 100.0, 0);
    _payout := _g.pot - _comm;
    UPDATE public.profiles SET balance_ar = balance_ar + _payout WHERE id = _winner;
    INSERT INTO public.transactions (user_id, type, amount, ref_id, note)
      VALUES (_winner, 'rami_win', _payout, _game_id, 'Win rami by forfeit');
    UPDATE public.rami_games SET status = 'finished', winner_id = _winner, finished_at = now() WHERE id = _game_id;
  ELSE
    SELECT _g.current_turn INTO _next;
    IF EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND slot = _next AND user_id = _uid) THEN
      SELECT array_agg(slot ORDER BY slot) INTO _parts
        FROM public.rami_participants WHERE game_id = _game_id AND NOT forfeited;
      LOOP
        _next := (_next + 1) % _g.max_players;
        EXIT WHEN _next = ANY(_parts);
      END LOOP;
      UPDATE public.rami_games SET current_turn = _next WHERE id = _game_id;
    END IF;
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.rami_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_forfeit(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 6. POKER — add poker_quit for leaving waiting room + auto-cancel
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.poker_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  v_is_host boolean;
  v_p record;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO g FROM public.poker_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  v_is_host := (g.created_by = v_uid);

  IF v_is_host THEN
    -- Host quits: refund ALL players and cancel
    FOR v_p IN SELECT user_id FROM public.poker_players WHERE game_id = _game_id LOOP
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_p.user_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_p.user_id, 'refund', g.stake, _game_id, 'Annulation salle d''attente (hôte)');
    END LOOP;
    UPDATE public.poker_games SET status = 'cancelled', updated_at = now() WHERE id = _game_id;
  ELSE
    -- Non-host quits: refund only this player, keep room open
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'refund', g.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid;
    UPDATE public.poker_games SET pot = pot - g.stake, updated_at = now() WHERE id = _game_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.poker_quit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.poker_quit(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════════════════
-- 7. Add Poker to _auto_cancel_open_games (timer expiry)
-- ════════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._auto_cancel_open_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE r record;
BEGIN
  -- Fanorona
  FOR r IN SELECT id, stake FROM public.fanorona_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.fanorona_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'fanorona_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.fanorona_participants WHERE game_id = r.id;
    UPDATE public.fanorona_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Chess
  FOR r IN SELECT id, stake FROM public.chess_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      WHERE p.id IN (SELECT host_id FROM public.chess_games WHERE id=r.id);
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT host_id, 'chess_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.chess_games WHERE id=r.id;
    UPDATE public.chess_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Domino
  FOR r IN SELECT id, stake FROM public.domino_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.domino_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'domino_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.domino_participants WHERE game_id = r.id;
    UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Rami
  FOR r IN SELECT id, stake FROM public.rami_games
           WHERE status='waiting' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.rami_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'rami_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.rami_participants WHERE game_id = r.id;
    UPDATE public.rami_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Ludo
  FOR r IN SELECT id, stake FROM public.ludo_games
           WHERE status='open' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.ludo_participants pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'ludo_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.ludo_participants WHERE game_id = r.id;
    UPDATE public.ludo_games SET status='cancelled', finished_at=now() WHERE id=r.id;
  END LOOP;

  -- Poker (NEW)
  FOR r IN SELECT id, stake FROM public.poker_games
           WHERE status='waiting' AND created_at < now() - interval '3 minutes'
  LOOP
    UPDATE public.profiles p SET balance_ar = balance_ar + r.stake
      FROM public.poker_players pp
      WHERE pp.game_id = r.id AND pp.user_id = p.id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      SELECT user_id, 'poker_refund', r.stake, r.id, 'Auto-cancelled (3 min)'
      FROM public.poker_players WHERE game_id = r.id;
    UPDATE public.poker_games SET status='cancelled', updated_at=now() WHERE id=r.id;
  END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public._auto_cancel_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._auto_cancel_open_games() TO authenticated, anon;
