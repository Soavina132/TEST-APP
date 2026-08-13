-- ═══════════════════════════════════════════════════════════════
-- Migration: No auto-join + 2-minute auto-cleanup with secure refunds
-- Date: 2026-08-14
-- ═══════════════════════════════════════════════════════════════
-- Changes:
-- 1. find_or_create_game: ALWAYS create a new game (no auto-join of existing open games)
-- 2. cleanup_stale_open_games: Delete games in 'open'/'waiting' status older than 2 minutes
--    - Refund stakes to real participants via credit_user_balance (secure)
--    - Skip bots (is_bot = false filter)
--    - Skip free games (stake = 0)
--    - Fallback to direct refund if credit_user_balance fails
-- 3. ludo_tick_all: Call cleanup at start of each tick
-- 4. join_game: Call cleanup before joining
-- 5. pg_cron: Schedule cleanup every minute
-- ═══════════════════════════════════════════════════════════════

-- === 1. cleanup_stale_open_games (implement the no-op stub) ===
CREATE OR REPLACE FUNCTION public.cleanup_stale_open_games()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_count INT := 0;
  g_id UUID;
  g_stake NUMERIC;
  p_uid UUID;
BEGIN
  FOR g_id, g_stake IN
    SELECT id, stake FROM public.ludo_games
    WHERE status IN ('open', 'waiting')
      AND created_at < now() - interval '2 minutes'
  LOOP
    -- Refund each real participant (skip bots, only if stake > 0)
    IF g_stake > 0 THEN
      FOR p_uid IN SELECT user_id FROM public.ludo_participants
        WHERE game_id = g_id AND user_id IS NOT NULL AND is_bot = false
      LOOP
        BEGIN
          PERFORM public.credit_user_balance(p_uid, g_stake, 'refund', g_id, 'Remboursement partie expiree');
        EXCEPTION WHEN OTHERS THEN
          -- Fallback: direct refund if credit_user_balance fails
          UPDATE public.profiles SET balance_ar = balance_ar + g_stake WHERE id = p_uid;
          INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
            VALUES (p_uid, 'refund', g_stake, g_id, 'Remboursement partie expiree (fallback)');
        END;
      END LOOP;
    END IF;
    -- Delete participants
    DELETE FROM public.ludo_participants WHERE game_id = g_id;
    -- Delete the game
    DELETE FROM public.ludo_games WHERE id = g_id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END;
$function$;

-- === 2. find_or_create_game: always create, never auto-join ===
CREATE OR REPLACE FUNCTION public.find_or_create_game(_max_players integer, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'groupe'::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_game_id UUID;
  v_balance NUMERIC;
  v_commission NUMERIC;
  v_paused BOOLEAN;
  v_banned BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  -- Always create a new game (no auto-join of existing games)
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, match_type, mode)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10),
            CASE WHEN _match_type = 'solo' THEN 'solo' ELSE 'groupe' END,
            CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END)
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise creation partie');
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_game_id;
END;
$function$;

-- === 3. ludo_tick_all: add cleanup at start ===
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  st JSONB;
  v_turn_started TIMESTAMPTZ;
  v_elapsed FLOAT;
  v_delay_until TIMESTAMPTZ;
  v_bot_delay FLOAT;
BEGIN
  PERFORM public.cleanup_stale_open_games();

  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      PERFORM public.ludo_check_timeout(g_id);
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;
      IF v_isbot THEN
        v_turn_started := (st->>'turn_started_at')::timestamptz;
        v_elapsed := EXTRACT(EPOCH FROM (now() - v_turn_started));
        IF NOT (st->>'must_move')::BOOLEAN THEN
          IF v_elapsed >= 3.0 + (random() * 2.0) THEN
            PERFORM public.ludo_bot_play(g_id);
          END IF;
        ELSE
          SELECT bot_delay_until INTO v_delay_until FROM public.ludo_games WHERE id=g_id;
          IF v_delay_until IS NULL OR v_delay_until < v_turn_started THEN
            v_bot_delay := 2.0 + (random() * 2.0);
            UPDATE public.ludo_games SET bot_delay_until = now() + make_interval(secs => v_bot_delay) WHERE id=g_id;
          ELSIF now() >= v_delay_until THEN
            PERFORM public.ludo_bot_move(g_id);
            UPDATE public.ludo_games SET bot_delay_until = NULL WHERE id=g_id;
          END IF;
        END IF;
      END IF;
      PERFORM public._ludo_check_stalemate(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$;

-- === 4. join_game: add cleanup before joining ===
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN; v_colors TEXT[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie deja commencee'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN RAISE EXCEPTION 'Deja inscrit'; END IF;
  PERFORM public._validate_stake(v_game.stake);
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count;
  v_colors := CASE v_game.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
  v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'ludo_stake', -v_game.stake, _game_id, 'Mise join partie Ludo');
  PERFORM public._ludo_maybe_auto_start(_game_id);
END; $function$;

-- === 5. pg_cron: schedule cleanup every minute ===
SELECT cron.schedule('cleanup-stale-games', '* * * * *', 'SELECT public.cleanup_stale_open_games();');
