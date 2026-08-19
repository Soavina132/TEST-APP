-- ============================================================
-- Fix: Use actual color-based start indices instead of fixed slot mapping
-- 
-- Bug: _ludo_start_idx assumed slot 0=red(0), 1=green(13), 2=yellow(26), 3=blue(39)
-- But in 2-player games, colors are red+yellow: slot 1 is yellow (start=26)
-- This caused capture to check the wrong cells.
--
-- Fix: Store start_indices in game state from actual participant colors,
-- and use _ludo_start_from_state() in all capture/movement functions.
-- ============================================================

-- New helper: read start index from state
CREATE OR REPLACE FUNCTION public._ludo_start_from_state(st jsonb, _slot integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT COALESCE(
    (st->'start_indices'->_slot::text)::int,
    (ARRAY[0,13,26,39])[_slot+1]
  )
$function$;

-- _ludo_ensure_state: compute and store start_indices from participant colors
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE 
  g public.ludo_games%ROWTYPE; 
  st jsonb;
  v_slot INT;
  v_color TEXT;
  v_start INT;
  v_start_indices jsonb := '{}'::jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players, COALESCE(g.mode,'classic'));
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
  ELSE
    st := g.state;
  END IF;
  
  IF NOT (st ? 'start_indices') OR st->'start_indices' = '{}'::jsonb THEN
    FOR v_slot, v_color IN SELECT slot, color FROM public.ludo_participants WHERE game_id=_game_id ORDER BY slot LOOP
      v_start := CASE v_color
        WHEN 'red' THEN 0
        WHEN 'green' THEN 13
        WHEN 'yellow' THEN 26
        WHEN 'blue' THEN 39
        ELSE 0
      END;
      v_start_indices := v_start_indices || jsonb_build_object(v_slot::text, v_start);
    END LOOP;
    st := jsonb_set(st, '{start_indices}', v_start_indices, true);
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  
  RETURN st;
END;
$function$;

-- _ludo_movable_pawns: use _ludo_start_from_state
CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot integer, _dice integer)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT;
  result jsonb := '[]'::jsonb;
  v_new_k INT;
  v_path_idx INT;
  v_max_players INT;
  v_start INT;
BEGIN
  IF _dice IS NULL OR _dice < 1 OR _dice > 6 THEN RETURN '[]'::jsonb; END IF;
  IF _slot IS NULL THEN RETURN '[]'::jsonb; END IF;
  arr := st->'pawns'->_slot::text;
  IF arr IS NULL OR arr = 'null'::jsonb THEN RETURN '[]'::jsonb; END IF;
  v_max_players := COALESCE((st->>'max_players')::int, 4);
  v_start := public._ludo_start_from_state(st, _slot);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN
        v_path_idx := v_start;
        IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
          result := result || to_jsonb(i);
        END IF;
      END IF;
    ELSIF pstate = 'track' THEN
      v_new_k := pstep + _dice;
      IF v_new_k <= 56 THEN
        IF v_new_k <= 50 THEN
          v_path_idx := (v_start + v_new_k - 1) % 52;
          IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
            result := result || to_jsonb(i);
          END IF;
        ELSE
          result := result || to_jsonb(i);
        END IF;
      END IF;
    END IF;
  END LOOP;
  RETURN result;
END;
$function$;

-- _ludo_count_on_cell: use _ludo_start_from_state
CREATE OR REPLACE FUNCTION public._ludo_count_on_cell(st jsonb, _slot integer, _path_idx integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT count(*)::int
  FROM jsonb_array_elements(st->'pawns'->_slot::text) AS p
  WHERE p.value->>'s' = 'track'
    AND (public._ludo_start_from_state(st, _slot) + (p.value->>'k')::int - 1) % 52 = _path_idx
$function$;
