CREATE OR REPLACE FUNCTION public.admin_create_game_tournament(
  _name text,
  _game_slug text,
  _max_players integer DEFAULT 8,
  _stake numeric DEFAULT 0,
  _is_free boolean DEFAULT true,
  _total_rounds integer DEFAULT 3,
  _description text DEFAULT NULL::text,
  _rewards_text text DEFAULT NULL::text,
  _registration_opens_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  _registration_closes_at timestamp with time zone DEFAULT NULL::timestamp with time zone,
  _bye_strategy text DEFAULT 'random'::text,
  _move_timer_secs integer DEFAULT 25,
  _join_timeout_secs integer DEFAULT 240,
  _disconnect_grace_secs integer DEFAULT 120,
  _format text DEFAULT 'elimination'::text,
  _players_per_table integer DEFAULT 2,
  _qualifiers_per_table integer DEFAULT 1,
  _grace_period_secs integer DEFAULT 300,
  _auto_start_mins integer DEFAULT 10,
  _reward_first_pct numeric DEFAULT 60,
  _reward_second_pct numeric DEFAULT 20,
  _reward_third_pct numeric DEFAULT 10,
  _reward_platform_pct numeric DEFAULT 10,
  _game_rules jsonb DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_season int;
  v_tid    uuid;
  v_stake  numeric;
  v_ppt    int;
  v_qpt    int;
BEGIN
  IF public.is_admin() IS NOT TRUE THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Session admin introuvable'; END IF;

  IF _name IS NULL OR trim(_name) = '' THEN RAISE EXCEPTION 'Nom requis'; END IF;
  IF _max_players < 2 THEN RAISE EXCEPTION 'Minimum 2 joueurs'; END IF;
  IF _game_slug IS NULL OR _game_slug NOT IN ('chess','fanorona','ludo','poker','rami','domino','all')
    THEN RAISE EXCEPTION 'Jeu invalide'; END IF;

  IF ABS((_reward_first_pct + _reward_second_pct + _reward_third_pct + _reward_platform_pct) - 100) > 0.01 THEN
    RAISE EXCEPTION 'La répartition doit totaliser 100%%';
  END IF;

  SELECT COALESCE(MAX(season), 0) + 1 INTO v_season FROM public.tournaments;
  v_stake := CASE WHEN _is_free THEN 0 ELSE _stake END;
  v_ppt := CASE WHEN _format = 'tables' THEN COALESCE(_players_per_table, 4) ELSE 2 END;
  v_qpt := CASE WHEN _format = 'tables' THEN COALESCE(_qualifiers_per_table, 2) ELSE 1 END;

  IF _game_slug = 'domino' AND _format = 'elimination'
     AND EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'admin_create_domino_tournament') THEN
    BEGIN
      SELECT public.admin_create_domino_tournament(
        _name, _max_players, v_stake, _is_free, _description, _rewards_text,
        _registration_opens_at, _registration_closes_at,
        _bye_strategy, _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
        COALESCE(_game_rules->>'mode', 'classic'),
        COALESCE(_game_rules->>'draw_mode', 'with'),
        COALESCE(_game_rules->>'first_tile_rule', 'libre'),
        COALESCE((_game_rules->>'target_score')::int, 100)
      ) INTO v_tid;
    EXCEPTION WHEN undefined_function OR datatype_mismatch OR invalid_parameter_value THEN
      v_tid := NULL;
    END;

    IF v_tid IS NOT NULL THEN
      UPDATE public.tournaments
        SET reward_distribution = jsonb_build_object(
              'first', _reward_first_pct, 'second', _reward_second_pct,
              'third', _reward_third_pct, 'platform', _reward_platform_pct),
            format = _format,
            players_per_table = v_ppt,
            qualifiers_per_table = v_qpt,
            grace_period_secs = _grace_period_secs,
            auto_start_mins = _auto_start_mins,
            created_by = COALESCE(created_by, v_uid)
        WHERE id = v_tid;
      RETURN v_tid;
    END IF;
  END IF;

  INSERT INTO public.tournaments(
    name, game_slug, mode, players_per_match, max_players, stake, prize_pool, is_free,
    total_rounds, current_round, status, season, created_by,
    description, rewards_text,
    registration_opens_at, registration_closes_at,
    move_timer_secs, join_timeout_secs, disconnect_grace_secs,
    reward_distribution, format, players_per_table, qualifiers_per_table,
    grace_period_secs, auto_start_mins,
    game_rules
  ) VALUES (
    trim(_name), _game_slug,
    CASE WHEN _format = 'tables' THEN 'tables' ELSE '1v1' END,
    v_ppt,
    _max_players, v_stake,
    CASE WHEN _is_free THEN 0 ELSE v_stake * _max_players * (1 - _reward_platform_pct/100.0) END,
    _is_free, _total_rounds, 0, 'open', v_season, v_uid,
    _description, _rewards_text, _registration_opens_at, _registration_closes_at,
    _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
    jsonb_build_object(
      'first', _reward_first_pct, 'second', _reward_second_pct,
      'third', _reward_third_pct, 'platform', _reward_platform_pct),
    _format, v_ppt, v_qpt, _grace_period_secs, _auto_start_mins,
    COALESCE(_game_rules, '{}'::jsonb)
  ) RETURNING id INTO v_tid;

  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'create_tournament', v_tid,
              _game_slug || ' · format=' || _format || ' · ' || _max_players || ' joueurs');
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tid;
END;
$function$;