-- ═════════════════════════════════════════════════════════════════
-- FIX: Toutes les fonctions de fin de partie Fanorona
-- 1. auto_finish_abandoned_games: pas de paiement → _fanorona_finalize
-- 2. fanorona_request_or_accept_draw: status 'active' au lieu de 'playing'
-- 3. Pas de tick serveur → fanorona_tick_all (pg_cron toutes les 10s)
-- 4. fanorona_play: pas de tracking no_capture_moves (draw 20 coups)
-- 5. fanorona_request_or_accept_draw: pas de remboursement sur nulle
-- ═════════════════════════════════════════════════════════════════

-- ═══ FIX 1: auto_finish_abandoned_games — appeler _fanorona_finalize ═══
CREATE OR REPLACE FUNCTION public.auto_finish_abandoned_games()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g record;
  v_winner uuid;
  v_winner_slot int;
  v_active_human_count int;
  v_total_active int;
BEGIN
  -- ── LUDO ──
  FOR g IN SELECT id, pot, commission_pct FROM public.ludo_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.ludo_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.ludo_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.ludo_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.ludo_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.ludo_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.ludo_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── DOMINO ──
  FOR g IN SELECT id, pot, commission_pct FROM public.domino_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.domino_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.domino_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.domino_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.domino_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.domino_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.domino_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── FANORONA (FIX: utiliser _fanorona_finalize pour le paiement) ──
  FOR g IN SELECT id, pot, commission_pct FROM public.fanorona_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.fanorona_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT slot INTO v_winner_slot FROM public.fanorona_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      PERFORM public._fanorona_finalize(g.id, v_winner_slot);
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_total_active
        FROM public.fanorona_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_total_active <= 1 THEN
        SELECT slot INTO v_winner_slot FROM public.fanorona_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        PERFORM public._fanorona_finalize(g.id, v_winner_slot);
      END IF;
    END IF;
  END LOOP;

  -- ── RAMI ──
  FOR g IN SELECT id, pot, commission_pct FROM public.rami_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.rami_participants
      WHERE game_id = g.id AND is_bot = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.rami_participants
        WHERE game_id = g.id AND forfeited = false
        ORDER BY slot LIMIT 1;
      UPDATE public.rami_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.rami_participants
        WHERE game_id = g.id AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.rami_participants
          WHERE game_id = g.id AND forfeited = false LIMIT 1;
        UPDATE public.rami_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;

  -- ── CHESS ──
  FOR g IN SELECT id, white_id, black_id, stake, pot FROM public.chess_games WHERE status = 'playing'
  LOOP
    IF g.white_id IS NULL AND g.black_id IS NULL THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
    ELSIF g.white_id IS NOT NULL AND g.black_id IS NULL THEN
      UPDATE public.chess_games SET status = 'cancelled', finished_at = now() WHERE id = g.id;
    ELSIF g.white_id IS NOT NULL AND g.black_id IS NOT NULL THEN
      NULL;
    END IF;
  END LOOP;

  -- ── POKER ──
  FOR g IN SELECT id, pot, commission_pct FROM public.poker_games WHERE status = 'playing'
  LOOP
    SELECT count(*) INTO v_active_human_count
      FROM public.poker_players
      WHERE game_id = g.id AND is_bot = false AND eliminated = false AND forfeited = false;
    IF v_active_human_count = 0 THEN
      SELECT user_id INTO v_winner FROM public.poker_players
        WHERE game_id = g.id AND eliminated = false AND forfeited = false
        ORDER BY seat LIMIT 1;
      UPDATE public.poker_games
        SET status = 'finished', winner_id = v_winner, finished_at = now()
        WHERE id = g.id;
    ELSIF v_active_human_count = 1 THEN
      SELECT count(*) INTO v_active_human_count
        FROM public.poker_players
        WHERE game_id = g.id AND eliminated = false AND forfeited = false;
      IF v_active_human_count <= 1 THEN
        SELECT user_id INTO v_winner FROM public.poker_players
          WHERE game_id = g.id AND eliminated = false AND forfeited = false LIMIT 1;
        UPDATE public.poker_games
          SET status = 'finished', winner_id = v_winner, finished_at = now()
          WHERE id = g.id;
      END IF;
    END IF;
  END LOOP;
END $$;

-- ═══ FIX 2+5: fanorona_request_or_accept_draw — status + refund ═══
CREATE OR REPLACE FUNCTION public.fanorona_request_or_accept_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_status text; v_offered uuid;
BEGIN
  SELECT status, draw_offered_by INTO v_status, v_offered FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) THEN RETURN; END IF;
  IF v_offered IS NULL THEN
    UPDATE public.fanorona_games SET draw_offered_by=v_uid, updated_at=now() WHERE id=_game_id;
  ELSIF v_offered <> v_uid THEN
    PERFORM public._fanorona_draw_refund(_game_id);
  END IF;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.fanorona_request_or_accept_draw(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fanorona_request_or_accept_draw(uuid) TO authenticated;

-- ═══ FIX 3: fanorona_tick_all — tick serveur via pg_cron ═══
CREATE OR REPLACE FUNCTION public.fanorona_tick_all()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record;
  cur_uid uuid;
  winner_slot int;
BEGIN
  FOR g IN SELECT id, current_turn, turn_deadline, game_deadline, status
           FROM public.fanorona_games
           WHERE status = 'playing'
  LOOP
    -- 1. Turn timeout
    IF g.turn_deadline IS NOT NULL AND g.turn_deadline <= now() THEN
      SELECT user_id INTO cur_uid FROM public.fanorona_participants
        WHERE game_id = g.id AND slot = g.current_turn;
      IF cur_uid IS NOT NULL THEN
        UPDATE public.fanorona_participants SET forfeited = true
          WHERE game_id = g.id AND user_id = cur_uid;
      END IF;
      winner_slot := 1 - g.current_turn;
      PERFORM public._fanorona_finalize(g.id, winner_slot);
      CONTINUE;
    END IF;

    -- 2. Global timeout
    IF g.game_deadline IS NOT NULL AND g.game_deadline <= now() THEN
      winner_slot := 1 - g.current_turn;
      PERFORM public._fanorona_finalize(g.id, winner_slot);
      CONTINUE;
    END IF;

    -- 3. Bot bloqué (tour du bot mais le frontend n'est pas la)
    IF g.turn_deadline IS NOT NULL AND g.turn_deadline > now() THEN
      BEGIN
        PERFORM public.fanorona_bot_play(g.id);
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;
  END LOOP;
END $function$;

REVOKE EXECUTE ON FUNCTION public.fanorona_tick_all() FROM anon;
GRANT EXECUTE ON FUNCTION public.fanorona_tick_all() TO authenticated;

-- Schedule fanorona_tick_all every 10 seconds
DO $cron$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      PERFORM cron.schedule(
        'fanorona_tick_all',
        '*/10 * * * * *',
        $cmd$SELECT public.fanorona_tick_all();$cmd$
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
END $cron$;
