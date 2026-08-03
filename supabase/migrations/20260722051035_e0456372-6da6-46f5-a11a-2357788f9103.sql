
-- Force Chess & Domino tournaments to 1v1 in the creation RPC
CREATE OR REPLACE FUNCTION public.admin_create_game_tournament(
  _name                    text,
  _game_slug               text,
  _max_players             int      DEFAULT 8,
  _stake                   numeric  DEFAULT 0,
  _is_free                 boolean  DEFAULT true,
  _total_rounds            int      DEFAULT 3,
  _description             text     DEFAULT NULL,
  _rewards_text            text     DEFAULT NULL,
  _registration_opens_at   timestamptz DEFAULT NULL,
  _registration_closes_at  timestamptz DEFAULT NULL,
  _bye_strategy            text     DEFAULT 'random',
  _move_timer_secs         int      DEFAULT 25,
  _join_timeout_secs       int      DEFAULT 240,
  _disconnect_grace_secs   int      DEFAULT 120,
  _format                  text     DEFAULT 'elimination',
  _players_per_table       int      DEFAULT 2,
  _qualifiers_per_table    int      DEFAULT 1,
  _grace_period_secs       int      DEFAULT 300,
  _auto_start_mins         int      DEFAULT 10,
  _reward_first_pct        numeric  DEFAULT 60,
  _reward_second_pct       numeric  DEFAULT 20,
  _reward_third_pct        numeric  DEFAULT 10,
  _reward_platform_pct     numeric  DEFAULT 10,
  _game_rules              jsonb    DEFAULT '{}'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  v_season     int;
  v_tid        uuid;
  v_stake      numeric;
  v_ppt        int;
  v_qpt        int;
  v_format     text := _format;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  IF _name IS NULL OR trim(_name) = '' THEN RAISE EXCEPTION 'Nom requis'; END IF;
  IF _max_players < 2 THEN RAISE EXCEPTION 'Minimum 2 joueurs'; END IF;
  IF _game_slug IS NULL OR _game_slug NOT IN ('chess','fanorona','ludo','poker','rami','domino','all')
    THEN RAISE EXCEPTION 'Jeu invalide'; END IF;

  IF ABS((_reward_first_pct + _reward_second_pct + _reward_third_pct + _reward_platform_pct) - 100) > 0.01 THEN
    RAISE EXCEPTION 'La répartition doit totaliser 100%%';
  END IF;

  -- 🔒 Chess & Domino tournaments are ALWAYS 1v1 elimination (same rule as Ludo 1v1)
  IF _game_slug IN ('chess','domino') THEN
    v_format := 'elimination';
  END IF;

  SELECT COALESCE(MAX(season), 0) + 1 INTO v_season FROM public.tournaments;
  v_stake := CASE WHEN _is_free THEN 0 ELSE _stake END;

  v_ppt := CASE WHEN v_format = 'tables' THEN COALESCE(_players_per_table, 4) ELSE 2 END;
  v_qpt := CASE WHEN v_format = 'tables' THEN COALESCE(_qualifiers_per_table, 2) ELSE 1 END;

  IF _game_slug = 'domino' THEN
    SELECT public.admin_create_domino_tournament(
      _name, _max_players, v_stake, _is_free, _description, _rewards_text,
      _registration_opens_at, _registration_closes_at,
      _bye_strategy, _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
      COALESCE(_game_rules->>'mode', 'classic'),
      COALESCE(_game_rules->>'draw_mode', 'with'),
      COALESCE(_game_rules->>'first_tile_rule', 'libre'),
      COALESCE((_game_rules->>'target_score')::int, 100)
    ) INTO v_tid;

    IF v_tid IS NULL THEN
      SELECT id INTO v_tid FROM public.tournaments WHERE name = _name ORDER BY created_at DESC LIMIT 1;
    END IF;

    UPDATE public.tournaments
      SET reward_distribution = jsonb_build_object(
            'first', _reward_first_pct, 'second', _reward_second_pct,
            'third', _reward_third_pct, 'platform', _reward_platform_pct),
          format = 'elimination',
          mode = '1v1',
          players_per_table = 2,
          qualifiers_per_table = 1,
          players_per_match = 2,
          grace_period_secs = _grace_period_secs,
          auto_start_mins = _auto_start_mins
      WHERE id = v_tid;

    RETURN v_tid;
  END IF;

  INSERT INTO public.tournaments(
    name, game_slug, mode, max_players, stake, prize_pool, is_free,
    total_rounds, current_round, status, season,
    description, rewards_text,
    registration_opens_at, registration_closes_at,
    move_timer_secs, join_timeout_secs, disconnect_grace_secs,
    reward_distribution, format, players_per_table, qualifiers_per_table,
    players_per_match,
    grace_period_secs, auto_start_mins,
    game_rules
  ) VALUES (
    trim(_name), _game_slug,
    CASE WHEN v_format = 'tables' THEN 'tables' ELSE '1v1' END,
    _max_players, v_stake,
    CASE WHEN _is_free THEN 0 ELSE v_stake * _max_players * (1 - _reward_platform_pct/100.0) END,
    _is_free, _total_rounds, 0, 'open', v_season,
    _description, _rewards_text, _registration_opens_at, _registration_closes_at,
    _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
    jsonb_build_object(
      'first', _reward_first_pct, 'second', _reward_second_pct,
      'third', _reward_third_pct, 'platform', _reward_platform_pct),
    v_format, v_ppt, v_qpt,
    v_ppt,
    _grace_period_secs, _auto_start_mins,
    COALESCE(_game_rules, '{}')
  ) RETURNING id INTO v_tid;

  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'create_tournament', v_tid,
              _game_slug || ' · format=' || v_format || ' · ' || _max_players || ' joueurs')
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_game_tournament(
  text,text,int,numeric,boolean,int,text,text,timestamptz,timestamptz,
  text,int,int,int,text,int,int,int,int,numeric,numeric,numeric,numeric,jsonb
) TO authenticated;

-- Normalize existing open Chess/Domino tournaments to 1v1
UPDATE public.tournaments
   SET format = 'elimination',
       mode = '1v1',
       players_per_table = 2,
       qualifiers_per_table = 1,
       players_per_match = 2
 WHERE game_slug IN ('chess','domino')
   AND status = 'open';
