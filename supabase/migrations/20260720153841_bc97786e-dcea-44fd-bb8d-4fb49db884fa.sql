
-- Bye strategy: allow admin to control who receives round-1 byes (or short groups).
-- Adds an updater RPC and rewires _tournament_build_round to honor the strategy.

CREATE OR REPLACE FUNCTION public.admin_update_tournament_bye_strategy(
  _tid uuid,
  _bye_strategy text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_t public.tournaments%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF _bye_strategy NOT IN ('random','ranked') THEN
    RAISE EXCEPTION 'Stratégie invalide (random | ranked)';
  END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'open' THEN
    RAISE EXCEPTION 'La stratégie ne peut être modifiée que sur un tournoi ouvert';
  END IF;
  UPDATE public.tournaments SET bye_strategy = _bye_strategy WHERE id = _tid;
  INSERT INTO public.admin_action_logs(admin_id, action, target_id, meta)
    VALUES (auth.uid(), 'update_bye_strategy', _tid,
            jsonb_build_object('bye_strategy', _bye_strategy));
  RETURN jsonb_build_object('ok', true, 'bye_strategy', _bye_strategy);
END $$;

-- Reorder a player list according to a tournament's bye_strategy.
-- The current bracket builder groups sequentially: the tail becomes bye(s)
-- or a short group. So to give byes to top players we place them LAST.
-- For random, we just shuffle.
CREATE OR REPLACE FUNCTION public._tournament_order_players(
  _player_ids uuid[],
  _strategy text
) RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SET search_path TO 'public'
AS $$
DECLARE v_out uuid[];
BEGIN
  IF _player_ids IS NULL OR array_length(_player_ids,1) IS NULL THEN
    RETURN _player_ids;
  END IF;
  IF COALESCE(_strategy,'random') = 'ranked' THEN
    -- Weakest first, strongest at end so trailing bye/short-group goes to top seeds.
    SELECT array_agg(uid ORDER BY
             COALESCE(pr.total_wins, 0) ASC,
             COALESCE(pr.player_level, 0) ASC,
             random())
      INTO v_out
      FROM unnest(_player_ids) AS uid
      LEFT JOIN public.profiles pr ON pr.id = uid;
  ELSE
    SELECT array_agg(uid ORDER BY random()) INTO v_out FROM unnest(_player_ids) AS uid;
  END IF;
  RETURN v_out;
END $$;

-- Rewire _tournament_build_round to honor bye_strategy.
CREATE OR REPLACE FUNCTION public._tournament_build_round(_tid uuid, _round integer, _player_ids uuid[])
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_size integer;
  v_idx integer := 0;
  v_players uuid[];
  v_ordered uuid[];
  v_total integer;
  v_i integer;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  v_size := GREATEST(COALESCE(v_t.players_per_match, 2), 2);
  v_ordered := public._tournament_order_players(_player_ids, COALESCE(v_t.bye_strategy,'random'));
  v_total := COALESCE(array_length(v_ordered, 1), 0);
  v_i := 1;
  WHILE v_i <= v_total LOOP
    v_players := v_ordered[v_i : LEAST(v_i + v_size - 1, v_total)];
    IF array_length(v_players,1) = 1 THEN
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, winner_id, finished_at, is_bye)
        VALUES (_tid, _round, v_idx, v_players, 'finished', v_players[1], now(), true);
    ELSE
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false);
    END IF;
    v_idx := v_idx + 1;
    v_i := v_i + v_size;
  END LOOP;
END $$;
