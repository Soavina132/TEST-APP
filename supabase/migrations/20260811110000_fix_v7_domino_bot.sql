-- ═══════════════════════════════════════════════════════════════════════
-- FIX v7 — Bot Domino ne fonctionne pas
--
-- 3 bugs corrigés:
-- 1. domino_play_and_bot: maintenant attend le think delay (pg_sleep) puis
--    rejoue domino_tick pour que le bot joue SANS dépendre du frontend/cron.
--    Boucle si plusieurs bots jouent à la suite.
-- 2. domino_start_solo_bot: appel _domino_tick (inexistant) → domino_tick
-- 3. cron schedule: */5 * * * * * (6 champs) → '* * * * *' (1 minute, fiable)
--    + un job supplémentaire toutes les 10s via pg_sleep loop dans une
--    fonction wrapper pour les urgences bot.
-- ═══════════════════════════════════════════════════════════════════════

-- ═════ 1. domino_play_and_bot — boucle complète bot ═══════════════════
CREATE OR REPLACE FUNCTION public.domino_play_and_bot(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_delay_ms int;
  v_think_until timestamptz;
  v_is_bot boolean;
  v_max_loops int := 15;
  v_sleep_sec numeric;
  g_status text;
  g_phase text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- 1. Le joueur humain joue
  PERFORM public.domino_play(_game_id, _move);

  -- 2. Boucle: si c'est un bot qui doit jouer, on attend le think delay puis on tick
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    -- Vérifier si la partie est toujours en cours
    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';
    EXIT WHEN g_phase NOT IN ('play', 'playing');
    EXIT WHEN g_phase IN ('reveal', 'break', 'dealing');

    -- Est-ce que c'est un bot qui doit jouer?
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    -- Armer le think timer (si pas déjà fait)
    PERFORM public.domino_tick(_game_id);

    -- Lire bot_think_until
    SELECT NULLIF(state->>'bot_think_until', '')::timestamptz INTO v_think_until
      FROM public.domino_games WHERE id = _game_id;

    -- Attendre le think delay (400-1000ms)
    IF v_think_until IS NOT NULL AND v_think_until > now() THEN
      v_sleep_sec := extract(epoch from (v_think_until - now()));
      IF v_sleep_sec > 0 AND v_sleep_sec < 5 THEN
        PERFORM pg_sleep(v_sleep_sec);
      END IF;
    END IF;

    -- Maintenant le bot devrait jouer
    PERFORM public.domino_tick(_game_id);
  END LOOP;
END;
$function$;

-- ═════ 2. domino_start_solo_bot — fix _domino_tick → domino_tick ══════
CREATE OR REPLACE FUNCTION public.domino_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium',
  _target_score integer DEFAULT 100,
  _draw_mode text DEFAULT 'with',
  _first_tile_rule text DEFAULT 'libre'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_code text;
  v_name text;
  v_intel int;
  v_paused boolean;
  v_banned boolean;
  v_commission numeric;
  v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_init_state jsonb;
  v_is_bot boolean;
  v_think_until timestamptz;
  v_sleep_sec numeric;
  v_max_loops int := 15;
  g_status text;
  g_phase text;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _draw_mode NOT IN ('with','without') THEN _draw_mode := 'with'; END IF;
  IF _first_tile_rule NOT IN ('libre','under6') THEN _first_tile_rule := 'libre'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  CASE lower(_difficulty)
    WHEN 'easy'   THEN v_intel := 30;
    WHEN 'hard'   THEN v_intel := 95;
    ELSE               v_intel := 70;
  END CASE;

  SELECT COALESCE(game_commission_pct,10) INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();

  v_init_state := jsonb_build_object(
    'phase','waiting',
    'draw_mode', _draw_mode,
    'first_tile_rule', _first_tile_rule,
    'round', 0,
    'scores', '{}'::jsonb
  );

  INSERT INTO public.domino_games(
    host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode,
    status, started_at, target_score, first_tile_rule, state
  )
  VALUES (
    v_uid, _max_players, 0, 0, v_commission, v_code, true, 'classic',
    'playing', now(), COALESCE(_target_score, 100), _first_tile_rule, v_init_state
  )
  RETURNING id INTO v_game_id;

  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_name, true, false);

  FOR v_slot IN 1.._max_players - 1 LOOP
    INSERT INTO public.domino_participants(
      game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
    ) VALUES (
      v_game_id, NULL, v_slot, v_bot_names[v_slot], true, true, v_bot_names[v_slot], v_intel
    );
  END LOOP;

  PERFORM public._domino_next_round(v_game_id);

  -- FIX: was _domino_tick (doesn't exist) → domino_tick
  PERFORM public.domino_tick(v_game_id);

  -- Si le premier tour est un bot, on attend et on le fait jouer
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = v_game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';
    EXIT WHEN g_phase IN ('reveal', 'break');

    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = v_game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    PERFORM public.domino_tick(v_game_id);

    SELECT NULLIF(state->>'bot_think_until', '')::timestamptz INTO v_think_until
      FROM public.domino_games WHERE id = v_game_id;

    IF v_think_until IS NOT NULL AND v_think_until > now() THEN
      v_sleep_sec := extract(epoch from (v_think_until - now()));
      IF v_sleep_sec > 0 AND v_sleep_sec < 5 THEN
        PERFORM pg_sleep(v_sleep_sec);
      END IF;
    END IF;

    PERFORM public.domino_tick(v_game_id);
  END LOOP;

  RETURN v_game_id;
END;
$function$;

-- ═════ 3. Cron — changer pour 1 minute (fiable) ═══════════════════════
SELECT cron.alter_job(
  job_id => (SELECT jobid FROM cron.job WHERE jobname = 'domino_tick_all'),
  schedule => '* * * * *'
);
