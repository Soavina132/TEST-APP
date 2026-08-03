
-- Add winners_count and allow admin-funded prize pool for free tournaments
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS winners_count integer NOT NULL DEFAULT 3
    CHECK (winners_count BETWEEN 1 AND 3);

-- Recreate admin_create_game_tournament with new parameters
CREATE OR REPLACE FUNCTION public.admin_create_game_tournament(
  _name text,
  _game_slug text,
  _max_players integer DEFAULT 8,
  _stake numeric DEFAULT 0,
  _is_free boolean DEFAULT true,
  _total_rounds integer DEFAULT 3,
  _description text DEFAULT NULL,
  _rewards_text text DEFAULT NULL,
  _registration_opens_at timestamptz DEFAULT NULL,
  _registration_closes_at timestamptz DEFAULT NULL,
  _bye_strategy text DEFAULT 'random',
  _move_timer_secs integer DEFAULT 25,
  _join_timeout_secs integer DEFAULT 240,
  _disconnect_grace_secs integer DEFAULT 120,
  _format text DEFAULT 'elimination',
  _players_per_table integer DEFAULT 2,
  _qualifiers_per_table integer DEFAULT 1,
  _grace_period_secs integer DEFAULT 300,
  _auto_start_mins integer DEFAULT 10,
  _reward_first_pct numeric DEFAULT 60,
  _reward_second_pct numeric DEFAULT 20,
  _reward_third_pct numeric DEFAULT 10,
  _reward_platform_pct numeric DEFAULT 10,
  _game_rules jsonb DEFAULT '{}'::jsonb,
  _winners_count integer DEFAULT 3,
  _admin_prize_pool_ar numeric DEFAULT 0
) RETURNS uuid
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public','extensions'
AS $function$
DECLARE
  v_uid        uuid := auth.uid();
  v_is_admin   boolean;
  v_season     int;
  v_tid        uuid;
  v_stake      numeric;
  v_ppt        int;
  v_qpt        int;
  v_format     text := _format;
  v_wc         int  := GREATEST(1, LEAST(3, COALESCE(_winners_count, 3)));
  v_p1         numeric := COALESCE(_reward_first_pct, 60);
  v_p2         numeric := COALESCE(_reward_second_pct, 20);
  v_p3         numeric := COALESCE(_reward_third_pct, 10);
  v_pp         numeric := COALESCE(_reward_platform_pct, 10);
  v_prize      numeric;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  IF _name IS NULL OR trim(_name) = '' THEN RAISE EXCEPTION 'Nom requis'; END IF;
  IF _max_players < 2 THEN RAISE EXCEPTION 'Minimum 2 joueurs'; END IF;
  IF _game_slug IS NULL OR _game_slug NOT IN ('chess','fanorona','ludo','poker','rami','domino','all')
    THEN RAISE EXCEPTION 'Jeu invalide'; END IF;

  -- Force distribution based on winners_count : les places non payées sont fusionnées dans 1er
  IF v_wc < 3 THEN v_p1 := v_p1 + v_p3; v_p3 := 0; END IF;
  IF v_wc < 2 THEN v_p1 := v_p1 + v_p2; v_p2 := 0; END IF;

  IF ABS((v_p1 + v_p2 + v_p3 + v_pp) - 100) > 0.01 THEN
    RAISE EXCEPTION 'La répartition doit totaliser 100%% (actuellement %)', (v_p1 + v_p2 + v_p3 + v_pp);
  END IF;

  IF _game_slug IN ('chess','domino') THEN v_format := 'elimination'; END IF;

  SELECT COALESCE(MAX(season), 0) + 1 INTO v_season FROM public.tournaments;
  v_stake := CASE WHEN _is_free THEN 0 ELSE _stake END;

  v_ppt := CASE WHEN v_format = 'tables' THEN COALESCE(_players_per_table, 4) ELSE 2 END;
  v_qpt := CASE WHEN v_format = 'tables' THEN COALESCE(_qualifiers_per_table, 2) ELSE 1 END;

  -- Cagnotte : payante = mises*joueurs*(1-platform%). Gratuit = montant admin (0 par défaut).
  v_prize := CASE
    WHEN _is_free THEN GREATEST(0, COALESCE(_admin_prize_pool_ar, 0))
    ELSE v_stake * _max_players * (1 - v_pp/100.0)
  END;

  IF _game_slug = 'domino' THEN
    SELECT public.admin_create_domino_tournament(
      _name, _max_players, v_stake, _is_free, _description, _rewards_text,
      _registration_opens_at, _registration_closes_at,
      _bye_strategy, _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
      COALESCE(_game_rules->>'mode','classic'),
      COALESCE(_game_rules->>'draw_mode','with'),
      COALESCE(_game_rules->>'first_tile_rule','libre'),
      COALESCE((_game_rules->>'target_score')::int, 100)
    ) INTO v_tid;

    IF v_tid IS NULL THEN
      SELECT id INTO v_tid FROM public.tournaments WHERE name = _name ORDER BY created_at DESC LIMIT 1;
    END IF;

    UPDATE public.tournaments SET
      reward_distribution = jsonb_build_object('first',v_p1,'second',v_p2,'third',v_p3,'platform',v_pp),
      prize_pool = v_prize,
      winners_count = v_wc,
      format='elimination', mode='1v1',
      players_per_table=2, qualifiers_per_table=1, players_per_match=2,
      grace_period_secs=_grace_period_secs, auto_start_mins=_auto_start_mins
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
    players_per_match, grace_period_secs, auto_start_mins,
    game_rules, winners_count
  ) VALUES (
    trim(_name), _game_slug,
    CASE WHEN v_format='tables' THEN 'tables' ELSE '1v1' END,
    _max_players, v_stake, v_prize,
    _is_free, _total_rounds, 0, 'open', v_season,
    _description, _rewards_text, _registration_opens_at, _registration_closes_at,
    _move_timer_secs, _join_timeout_secs, _disconnect_grace_secs,
    jsonb_build_object('first',v_p1,'second',v_p2,'third',v_p3,'platform',v_pp),
    v_format, v_ppt, v_qpt, v_ppt,
    _grace_period_secs, _auto_start_mins,
    COALESCE(_game_rules,'{}'), v_wc
  ) RETURNING id INTO v_tid;

  BEGIN
    INSERT INTO public.admin_action_logs(admin_id, action, target_id, note)
      VALUES (v_uid, 'create_tournament', v_tid,
              _game_slug || ' · winners=' || v_wc || ' · pool=' || v_prize::text)
    ON CONFLICT DO NOTHING;
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN v_tid;
END;
$function$;

-- RPC to update winners_count / prize_pool on an existing tournament (admin-only)
CREATE OR REPLACE FUNCTION public.admin_set_tournament_winners(
  _tid uuid,
  _winners_count integer,
  _admin_prize_pool_ar numeric DEFAULT NULL
) RETURNS void
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $$
DECLARE
  v_is_admin boolean;
  v_wc int := GREATEST(1, LEAST(3, COALESCE(_winners_count, 3)));
  v_dist jsonb;
  v_p1 numeric; v_p2 numeric; v_p3 numeric; v_pp numeric;
  v_is_free boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin,false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT reward_distribution, is_free INTO v_dist, v_is_free
  FROM public.tournaments WHERE id = _tid;
  IF v_dist IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  v_p1 := COALESCE((v_dist->>'first')::numeric, 60);
  v_p2 := COALESCE((v_dist->>'second')::numeric, 20);
  v_p3 := COALESCE((v_dist->>'third')::numeric, 10);
  v_pp := COALESCE((v_dist->>'platform')::numeric, 10);

  IF v_wc < 3 THEN v_p1 := v_p1 + v_p3; v_p3 := 0; END IF;
  IF v_wc < 2 THEN v_p1 := v_p1 + v_p2; v_p2 := 0; END IF;

  UPDATE public.tournaments SET
    winners_count = v_wc,
    reward_distribution = jsonb_build_object('first',v_p1,'second',v_p2,'third',v_p3,'platform',v_pp),
    prize_pool = CASE
      WHEN v_is_free AND _admin_prize_pool_ar IS NOT NULL
        THEN GREATEST(0, _admin_prize_pool_ar)
      ELSE prize_pool
    END,
    updated_at = now()
  WHERE id = _tid;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_set_tournament_winners(uuid,integer,numeric) TO authenticated;
