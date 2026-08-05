-- ============================================================
-- FIX: Ludo solo game doesn't end when human is auto-forfeited via AFK
--
-- PROBLEM: When a human player in a solo game is auto-forfeited via
-- the AFK timeout system (_ludo_check_afk), the game continues with
-- only bots playing. This happens because:
--   1. _ludo_check_afk calls _ludo_check_last_standing which returns NULL
--      when multiple bots are still non-forfeited
--   2. _ludo_check_game_over only checks v_count <= 1 (total non-forfeited)
--      but doesn't check if 0 humans remain in a solo game
--   3. ludo_check_timeout doesn't call _ludo_check_game_over after AFK forfeit
--
-- FIX:
--   A. _ludo_check_afk: after forfeiting, if solo game with 0 active humans,
--      end the game immediately (same as ludo_quit does for solo)
--   B. _ludo_check_game_over: also end if solo game with 0 active humans
--   C. ludo_check_timeout: call _ludo_check_game_over after _ludo_check_afk
-- ============================================================

-- ── FIX A: _ludo_check_afk — end solo game when human forfeits ──
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t1      int;
  v_t2      int;
  v_max1    int;
  v_max2    int;
  v_enabled boolean;
  v_uid     uuid;
  v_isbot   boolean;
  v_name    text;
  v_winner  uuid;
  v_is_solo boolean;
  v_humans  int;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max
    INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;

  SELECT afk_t1, afk_t2, user_id, is_bot, display_name
    INTO v_t1, v_t2, v_uid, v_isbot, v_name
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  -- ── Seuil forfait : T1 >= max OU T2 >= max ──
  IF v_t1 >= COALESCE(v_max1, 5) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants
       SET forfeited = TRUE
     WHERE game_id = _game_id AND slot = _slot;
    UPDATE public.ludo_games
       SET afk_warning   = NULL,
           afk_pause_for  = NULL,
           afk_pause_name = NULL
     WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
              'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');

    -- Check if this is a solo game with no more active humans
    SELECT is_solo, match_type INTO v_is_solo FROM public.ludo_games WHERE id = _game_id;
    v_is_solo := COALESCE(v_is_solo, FALSE) OR COALESCE((SELECT match_type FROM public.ludo_games WHERE id = _game_id), 'groupe') = 'solo';

    IF v_is_solo THEN
      v_humans := public._ludo_active_humans(_game_id);
      IF v_humans = 0 THEN
        -- Solo game: no humans left → end immediately
        UPDATE public.ludo_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
        PERFORM public._ludo_purge(_game_id);
        RETURN;
      END IF;
    END IF;

    -- Non-solo or still has humans: check last standing
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
    RETURN;
  END IF;

  -- ── Seuil avertissement : UNIQUEMENT T1 = max-1 ──
  IF v_t1 = COALESCE(v_max1, 5) - 1 THEN
    UPDATE public.ludo_games
       SET afk_warning = jsonb_build_object(
             'uid',    v_uid,
             'name',   COALESCE(v_name, 'Joueur'),
             'slot',   _slot,
             't1',     v_t1,
             't1_max', COALESCE(v_max1, 5),
             'ts',     extract(epoch from now())::bigint
           )
     WHERE id = _game_id
       AND paused = FALSE
       AND (afk_warning IS NULL
            OR (afk_warning->>'uid')::uuid <> v_uid);
  END IF;
END $$;

-- ── FIX B: _ludo_check_game_over — handle solo mode ──
CREATE OR REPLACE FUNCTION public._ludo_check_game_over(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_count INT; v_humans INT; v_winner UUID; g public.ludo_games%ROWTYPE;
  v_is_solo BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN FALSE; END IF;

  SELECT count(*) INTO v_count
    FROM public.ludo_participants WHERE game_id=_game_id AND forfeited=FALSE;
  SELECT count(*) INTO v_humans
    FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE;

  v_is_solo := COALESCE(g.is_solo, FALSE) OR g.match_type = 'solo';

  -- Solo game: end when no humans remain
  IF v_is_solo AND v_humans = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN TRUE;
  END IF;

  IF v_count <= 1 THEN
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL AND v_humans > 0 THEN
      PERFORM public.finish_game(_game_id, v_winner);
    ELSE
      UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END $function$;

-- ── FIX C: ludo_check_timeout — call _ludo_check_game_over after AFK ──
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;

  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  -- Reset consecutive_sixes on timeout
  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN
    PERFORM public._ludo_check_afk(_game_id, v_slot);
    -- FIX: also check if the game should end (solo mode with 0 humans, etc.)
    PERFORM public._ludo_check_game_over(_game_id);
  END IF;
  RETURN st;
END $$;

-- ── END STUCK GAME: be53927e-be46-4f42-9557-8f478ebc7b5c ──
-- The human (ADMIN) was auto-forfeited via AFK but the game continued
-- with bots. Mark it as finished now.
UPDATE public.ludo_games
   SET status = 'finished', finished_at = now()
 WHERE id = 'be53927e-be46-4f42-9557-8f478ebc7b5c'
   AND status = 'playing';
