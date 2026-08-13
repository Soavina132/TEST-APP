================================================================================
-- _ludo_active_humans
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_active_humans(_game_id uuid)
 RETURNS integer
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$
  SELECT count(*)::INT FROM public.ludo_participants
  WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE
$function$


================================================================================
-- _ludo_advance_turn
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_advance_turn(_game_id uuid, _new_slot integer, _last_event text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_isbot boolean;
  v_spin_ms int;
  v_seq int;
  v_now text;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  st := g.state;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=_new_slot;
  v_spin_ms := CASE WHEN COALESCE(v_isbot, FALSE) THEN 2500 ELSE 0 END;
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  st := public._ludo_clear_shield(st, _new_slot);
  st := jsonb_set(st, '{turn_slot}',        to_jsonb(_new_slot));
  st := jsonb_set(st, '{turn_started_at}',  to_jsonb(v_now));
  st := jsonb_set(st, '{turn_seq}',         to_jsonb(v_seq));
  st := jsonb_set(st, '{phase}',            to_jsonb('spinning'::text));
  st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{spin_ms}',           to_jsonb(v_spin_ms));
  st := jsonb_set(st, '{dice}',              'null'::jsonb);
  st := jsonb_set(st, '{must_move}',         'false'::jsonb);
  st := jsonb_set(st, '{last_event}',        to_jsonb(_last_event));
  st := st - 'movable_pawns' - 'no_move_display';
  UPDATE public.ludo_games SET state=st, current_turn=_new_slot WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$


================================================================================
-- _ludo_auto_move
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_auto_move(_game_id uuid, _slot integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_dice int; v_playable jsonb; v_count int; v_pawn int;
  ii int; idx int; pawn jsonb; best_step int := -1;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN false; END IF;
  IF NOT COALESCE(g.auto_move, false) THEN RETURN false; END IF;
  IF NOT COALESCE((g.state->>'must_move')::boolean, false) THEN RETURN false; END IF;
  v_dice := NULLIF(g.state->>'dice','null')::int;
  IF v_dice IS NULL THEN RETURN false; END IF;

  v_playable := public._ludo_playable_pawns(g.state->'pawns', _slot, v_dice);
  v_count := jsonb_array_length(COALESCE(v_playable, '[]'::jsonb));
  IF v_count = 0 THEN RETURN false; END IF;

  v_pawn := (v_playable->0)::int;
  IF v_dice = 6 THEN
    FOR ii IN 0..(v_count-1) LOOP
      idx := (v_playable->ii)::int;
      pawn := g.state->'pawns'->_slot::text->idx;
      IF pawn->>'s' = 'yard' THEN v_pawn := idx; EXIT; END IF;
    END LOOP;
  END IF;
  IF v_pawn = (v_playable->0)::int THEN
    FOR ii IN 0..(v_count-1) LOOP
      idx := (v_playable->ii)::int;
      pawn := g.state->'pawns'->_slot::text->idx;
      IF pawn->>'s' = 'track' AND (pawn->>'k')::int > best_step THEN
        best_step := (pawn->>'k')::int; v_pawn := idx;
      END IF;
    END LOOP;
  END IF;

  PERFORM set_config('app.ludo_auto', 'on', true);
  PERFORM public.ludo_move(_game_id, v_pawn);
  PERFORM set_config('app.ludo_auto', 'off', true);
  RETURN true;
END $function$


================================================================================
-- _ludo_check_afk
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t1 int; v_t2 int; v_max1 int; v_max2 int;
  v_enabled boolean; v_uid uuid; v_isbot boolean; v_winner uuid;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max
    INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;

  SELECT afk_t1, afk_t2, user_id, is_bot
    INTO v_t1, v_t2, v_uid, v_isbot
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  IF v_t1 >= COALESCE(v_max1, 2) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants
       SET forfeited = TRUE
     WHERE game_id = _game_id AND slot = _slot;
    UPDATE public.ludo_games
       SET afk_warning = NULL, afk_pause_for = NULL, afk_pause_name = NULL
     WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
              'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
  END IF;
END $function$


================================================================================
-- _ludo_check_game_over
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_check_game_over(_game_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
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
END $function$


================================================================================
-- _ludo_check_last_standing
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_check_last_standing(_game_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_count INT; v_uid UUID;
BEGIN
  SELECT count(*) INTO v_count FROM public.ludo_participants
   WHERE game_id=_game_id AND forfeited=FALSE;
  IF v_count <= 1 THEN
    SELECT user_id INTO v_uid FROM public.ludo_participants
     WHERE game_id=_game_id AND forfeited=FALSE AND is_bot=FALSE LIMIT 1;
    RETURN v_uid;
  END IF;
  RETURN NULL;
END $function$


================================================================================
-- _ludo_clear_shield
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_clear_shield(st jsonb, _slot integer)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN st ? 'shields' AND (st->'shields') ? _slot::text
    THEN jsonb_set(st, '{shields}', (st->'shields') - _slot::text, true)
    ELSE st
  END
$function$


================================================================================
-- _ludo_ensure_state
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players, COALESCE(g.mode, 'classic'));
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END $function$


================================================================================
-- _ludo_init_state
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players integer, _mode text DEFAULT 'classic'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE p jsonb := '{}'::jsonb; i INT; v_st jsonb; v_mp INT;
BEGIN
  v_mp := COALESCE(_max_players, 2);
  IF v_mp < 2 THEN v_mp := 2; END IF;
  IF v_mp > 4 THEN v_mp := 4; END IF;
  
  FOR i IN 0..v_mp-1 LOOP
    p := p || jsonb_build_object(i::text,
      jsonb_build_array(
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1)
      ));
  END LOOP;
  
  v_st := jsonb_build_object(
    'pawns', p, 'turn_slot', 0, 'dice', NULL, 'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'turn_seq', 0, 'phase', 'spinning',
    'phase_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'spin_ms', 0, 'last_event', 'start');
  
  IF _mode = 'fast' THEN
    v_st := v_st || jsonb_build_object(
      'power_tiles', public._ludo_place_power_tiles(),
      'shields', '{}'::jsonb,
      'double_roll_pending', 'null'::jsonb
    );
  END IF;
  RETURN v_st;
END $function$


================================================================================
-- _ludo_is_safe
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_is_safe(_idx integer)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ SELECT _idx IN (0,8,13,21,26,34,39,47) $function$


================================================================================
-- _ludo_movable_pawns
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot integer, _dice integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT;
  result jsonb := '[]'::jsonb;
BEGIN
  IF _dice IS NULL OR _dice < 1 OR _dice > 6 THEN RETURN '[]'::jsonb; END IF;
  IF _slot IS NULL THEN RETURN '[]'::jsonb; END IF;
  arr := st->'pawns'->_slot::text;
  IF arr IS NULL OR arr = 'null'::jsonb THEN RETURN '[]'::jsonb; END IF;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN result := result || to_jsonb(i); END IF;
    ELSIF pstate = 'track' THEN
      IF pstep + _dice <= 56 THEN result := result || to_jsonb(i); END IF;
    END IF;
  END LOOP;
  RETURN result;
END $function$


================================================================================
-- _ludo_next_slot
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id uuid, _from integer, _max integer)
 RETURNS integer
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'public'
AS $function$
DECLARE v_cur_start INT; v_next_slot INT;
BEGIN
  SELECT public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END)
    INTO v_cur_start FROM public.ludo_participants WHERE game_id = _game_id AND slot = _from;
  IF v_cur_start IS NULL THEN v_cur_start := 0; END IF;

  SELECT slot INTO v_next_slot FROM public.ludo_participants
   WHERE game_id = _game_id AND forfeited = FALSE AND finish_rank IS NULL
     AND public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END) > v_cur_start
   ORDER BY public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END) ASC
   LIMIT 1;

  IF v_next_slot IS NULL THEN
    SELECT slot INTO v_next_slot FROM public.ludo_participants
     WHERE game_id = _game_id AND forfeited = FALSE AND finish_rank IS NULL
     ORDER BY public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END) ASC
     LIMIT 1;
  END IF;

  RETURN COALESCE(v_next_slot, _from);
END $function$


================================================================================
-- _ludo_place_power_tiles
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_place_power_tiles()
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_shuffled int[];
  v_types text[] := ARRAY['boost','boost','lucky_star','lucky_star','shield','double_roll'];
  v_tiles jsonb := '[]'::jsonb;
  v_cell int;
  i int;
  v_j int;
  v_tmp int;
BEGIN
  v_shuffled := v_valid;
  FOR i IN REVERSE array_length(v_shuffled,1)..2 LOOP
    v_j := 1 + floor(random()*i)::int;
    v_tmp := v_shuffled[i]; v_shuffled[i] := v_shuffled[v_j]; v_shuffled[v_j] := v_tmp;
  END LOOP;
  FOR i IN 1..6 LOOP
    IF i > array_length(v_shuffled,1) THEN EXIT; END IF;
    v_cell := v_shuffled[i];
    v_tiles := v_tiles || jsonb_build_object('type', v_types[i], 'cell', v_cell, 'cd', 0);
  END LOOP;
  RETURN v_tiles;
END $function$


================================================================================
-- _ludo_playable_pawns
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_playable_pawns(_pawns jsonb, _slot integer, _dice integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  arr jsonb; pawn jsonb; i int; pstate text; pstep int;
  out jsonb := '[]'::jsonb;
BEGIN
  IF _dice IS NULL OR _slot IS NULL OR _pawns IS NULL THEN RETURN out; END IF;
  arr := _pawns -> _slot::text;
  IF arr IS NULL THEN RETURN out; END IF;
  FOR i IN 0..3 LOOP
    pawn := arr -> i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep  := COALESCE((pawn->>'k')::int, 0);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN out := out || to_jsonb(i); END IF;
    ELSE
      IF pstep + _dice <= 56 THEN out := out || to_jsonb(i); END IF;
    END IF;
  END LOOP;
  RETURN out;
END $function$


================================================================================
-- _ludo_power_valid_cells
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_power_valid_cells()
 RETURNS integer[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY(
    SELECT i FROM generate_series(0,51) i
    WHERE i NOT IN (0, 8, 13, 21, 26, 34, 39, 47)
  )
$function$


================================================================================
-- _ludo_purge
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_purge(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  DELETE FROM public.chat_rooms WHERE game_id = _game_id;
  DELETE FROM public.game_spectators WHERE game_id = _game_id;
  DELETE FROM public.game_invitations WHERE game_id = _game_id;
  DELETE FROM public.ludo_participants WHERE game_id = _game_id;
  DELETE FROM public.ludo_games WHERE id = _game_id;
END $function$


================================================================================
-- _ludo_push_move
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_push_move(_game_id uuid, _entry jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE st jsonb; arr jsonb; len int;
BEGIN
  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  arr := COALESCE(st->'moves', '[]'::jsonb) || _entry;
  len := jsonb_array_length(arr);
  IF len > 20 THEN
    arr := (SELECT jsonb_agg(v) FROM (
      SELECT value AS v FROM jsonb_array_elements(arr) WITH ORDINALITY t(value, ord)
       ORDER BY ord OFFSET (len - 20)
    ) s);
  END IF;
  st := jsonb_set(st, '{moves}', arr);
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
END $function$


================================================================================
-- _ludo_relocate_tile
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_relocate_tile(_power_tiles jsonb, _type text, _game_id uuid DEFAULT NULL::uuid, _state jsonb DEFAULT NULL::jsonb, _old_cell integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_occupied int[] := ARRAY[]::int[];
  v_tile jsonb;
  v_available int[];
  v_new_cell int;
  v_result jsonb := '[]'::jsonb;
  v_relocated boolean := false;
  v_pawns jsonb;
  v_start int;
  v_step int;
  v_slot int;
  v_count int;
  v_pawn jsonb;
BEGIN
  IF _old_cell IS NULL THEN
    FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
      IF v_tile->>'type' = _type AND NOT v_relocated THEN
        _old_cell := (v_tile->>'cell')::int;
        v_relocated := true;
      END IF;
    END LOOP;
  END IF;

  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF (v_tile->>'cell')::int <> _old_cell THEN
      v_occupied := v_occupied || (v_tile->>'cell')::int;
    END IF;
  END LOOP;

  IF _game_id IS NOT NULL AND _state IS NOT NULL THEN
    FOR v_slot IN 0..3 LOOP
      v_pawns := _state->'pawns'->v_slot::text;
      IF v_pawns IS NULL THEN CONTINUE; END IF;
      v_start := public._ludo_start_for(_game_id, v_slot);
      FOR v_count IN 0..3 LOOP
        v_pawn := v_pawns->v_count;
        IF v_pawn IS NOT NULL AND v_pawn->>'s' = 'track' THEN
          v_step := (v_pawn->>'k')::int;
          IF v_step <= 50 THEN
            v_occupied := v_occupied || ((v_start + v_step) % 52);
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  v_available := ARRAY(SELECT v FROM unnest(v_valid) v WHERE NOT (v = ANY(v_occupied)));
  IF array_length(v_available,1) IS NULL OR array_length(v_available,1) = 0 THEN
    RETURN _power_tiles;
  END IF;

  v_new_cell := v_available[1 + floor(random()*array_length(v_available,1))::int];

  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF (v_tile->>'cell')::int = _old_cell AND v_tile->>'type' = _type AND NOT v_relocated THEN
      v_result := v_result || jsonb_build_object('type', _type, 'cell', v_new_cell, 'cd', 0);
      v_relocated := true;
    ELSE
      v_result := v_result || v_tile;
    END IF;
  END LOOP;

  IF NOT v_relocated THEN
    v_result := v_result || jsonb_build_object('type', _type, 'cell', v_new_cell, 'cd', 0);
  END IF;

  RETURN v_result;
END $function$


================================================================================
-- _ludo_set_ready_deadline
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_set_ready_deadline()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE v_sec int;
BEGIN
  SELECT COALESCE(ready_timeout_seconds,60) INTO v_sec FROM public.app_settings WHERE id=1;
  NEW.ready_deadline := now() + (v_sec || ' seconds')::interval;
  RETURN NEW;
END $function$


================================================================================
-- _ludo_start_for
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_start_for(_game_id uuid, _slot integer)
 RETURNS integer
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT CASE color
    WHEN 'red'    THEN 0
    WHEN 'green'  THEN 13
    WHEN 'yellow' THEN 26
    WHEN 'blue'   THEN 39
    ELSE 0
  END
  FROM public.ludo_participants
  WHERE game_id=_game_id AND slot=_slot;
$function$


================================================================================
-- _ludo_start_idx
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_start_idx(_slot integer)
 RETURNS integer
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$ SELECT (ARRAY[0,13,26,39])[_slot+1] $function$


================================================================================
-- _ludo_sync_turn_snapshot
================================================================================
CREATE OR REPLACE FUNCTION public._ludo_sync_turn_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  st jsonb; v_slot int; v_dice int; v_must boolean; v_playable jsonb;
BEGIN
  st := NEW.state;
  IF st IS NULL OR jsonb_typeof(st) <> 'object' THEN RETURN NEW; END IF;
  v_slot := NULLIF(st->>'turn_slot','')::int;
  v_dice := NULLIF(st->>'dice','null')::int;
  v_must := COALESCE((st->>'must_move')::boolean, false);
  IF v_must AND v_dice IS NOT NULL AND v_slot IS NOT NULL THEN
    v_playable := public._ludo_playable_pawns(st->'pawns', v_slot, v_dice);
  ELSE
    v_playable := '[]'::jsonb;
  END IF;
  st := jsonb_set(st, '{playable_pawns}', v_playable, true);
  IF v_slot IS NOT NULL THEN
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_slot), true);
    NEW.current_turn := v_slot;
  END IF;
  st := jsonb_set(st, '{dice}', COALESCE(to_jsonb(v_dice), 'null'::jsonb), true);
  NEW.state := st;
  RETURN NEW;
END $function$


================================================================================
-- ludo_bot_play
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_bias INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  other_slot INT; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence, bot_win_bias INTO v_isbot, v_intel, v_bias
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random()*6))::INT;
    IF COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_idx(v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
      IF pstate='yard' THEN sc := 60;
      ELSIF pstep + v_dice = 56 THEN sc := 80;
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR other_slot IN 0..g.max_players-1 LOOP
              IF other_slot <> v_slot THEN
                op_start := public._ludo_start_idx(other_slot);
                FOR k IN 0..3 LOOP
                  op := st->'pawns'->other_slot::text->k;
                  IF op->>'s' = 'track' THEN
                    op_step := (op->>'k')::INT;
                    IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                      would_capture := TRUE;
                    END IF;
                  END IF;
                END LOOP;
              END IF;
            END LOOP;
          END IF;
        END IF;
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$


================================================================================
-- ludo_bot_step
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_bot_step(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_slot int; v_isbot boolean; v_dice int; v_playable jsonb;
  v_pawn_idx int; v_count int;
  v_phase text; v_phase_at timestamptz; v_spin_ms int; v_elapsed_ms int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  IF COALESCE(g.paused, FALSE) THEN RETURN g.state; END IF;
  v_slot := COALESCE((g.state->>'turn_slot')::int, 0);
  SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT COALESCE(v_isbot, FALSE) THEN RETURN g.state; END IF;
  IF NOT COALESCE((g.state->>'must_move')::boolean, FALSE) THEN
    v_phase   := g.state->>'phase';
    v_spin_ms := COALESCE((g.state->>'spin_ms')::int, 0);
    IF v_phase = 'spinning' AND v_spin_ms > 0 THEN
      v_phase_at := NULLIF(g.state->>'phase_started_at','')::timestamptz;
      IF v_phase_at IS NOT NULL THEN
        v_elapsed_ms := (EXTRACT(EPOCH FROM (now() - v_phase_at)) * 1000)::int;
        IF v_elapsed_ms < v_spin_ms THEN RETURN g.state; END IF;
      END IF;
    END IF;
    RETURN public.ludo_roll(_game_id);
  END IF;
  v_dice := (g.state->>'dice')::int;
  v_playable := public._ludo_playable_pawns(g.state->'pawns', v_slot, v_dice);
  v_count := jsonb_array_length(COALESCE(v_playable, '[]'::jsonb));
  IF v_count = 0 THEN
    PERFORM public.ludo_pass(_game_id);
    SELECT state INTO g.state FROM public.ludo_games WHERE id=_game_id;
    RETURN g.state;
  END IF;
  v_pawn_idx := (v_playable->0)::int;
  DECLARE
    ii int; idx int; pawn jsonb; best_step int := -1;
  BEGIN
    IF v_dice = 6 THEN
      FOR ii IN 0..(v_count-1) LOOP
        idx := (v_playable->ii)::int;
        pawn := g.state->'pawns'->v_slot::text->idx;
        IF pawn->>'s' = 'yard' THEN v_pawn_idx := idx; EXIT; END IF;
      END LOOP;
    END IF;
    IF v_pawn_idx = (v_playable->0)::int THEN
      FOR ii IN 0..(v_count-1) LOOP
        idx := (v_playable->ii)::int;
        pawn := g.state->'pawns'->v_slot::text->idx;
        IF pawn->>'s' = 'track' THEN
          IF (pawn->>'k')::int > best_step THEN
            best_step := (pawn->>'k')::int; v_pawn_idx := idx;
          END IF;
        END IF;
      END LOOP;
    END IF;
  END;
  RETURN public.ludo_move(_game_id, v_pawn_idx);
END $function$


================================================================================
-- ludo_check_timeout
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int;
  v_new_slot int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;
  IF NOT COALESCE(v_isbot,false) AND COALESCE((st->>'must_move')::boolean, false) AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;
  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display' - 'movable_pawns';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$


================================================================================
-- ludo_cleanup_empty_rooms
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_cleanup_empty_rooms()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int;
BEGIN
  WITH d AS (
    DELETE FROM public.ludo_games g
    WHERE g.status='open' AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id)
    RETURNING 1
  ) SELECT count(*) INTO v_count FROM d;
  RETURN v_count;
END $function$


================================================================================
-- ludo_create_friends_game
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_create_friends_game(_max_players integer, _stake numeric, _mode text DEFAULT 'classic'::text, _is_public boolean DEFAULT false)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_id uuid;
  v_mode text;
  v_code text;
  v_commission numeric;
  v_paused boolean;
  v_banned boolean;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned, FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;

  IF _stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note)
      VALUES (v_uid, 'ludo_stake', -_stake, 'Mise Ludo (amis)');
  END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, status)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), v_code, NOT COALESCE(_is_public, false), v_mode, 'open')
    RETURNING id INTO v_id;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    VALUES (v_id, v_uid, 0, 'red', v_name);

  RETURN v_id;
END $function$


================================================================================
-- ludo_heartbeat
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_heartbeat(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_slot int;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  UPDATE public.ludo_participants SET last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid
    RETURNING slot INTO v_slot;
  IF v_slot IS NOT NULL THEN
    UPDATE public.ludo_games SET disconnect_until = disconnect_until - v_slot::text
      WHERE id=_game_id AND disconnect_until ? v_slot::text;
  END IF;
END $function$


================================================================================
-- ludo_join
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_join(_game_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g public.ludo_games%ROWTYPE;
  v_balance numeric;
  v_name text;
  v_count int;
  v_slot int;
  v_color text;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'Partie non disponible'; END IF;

  IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid) THEN
    RETURN _game_id;
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF COALESCE(g.stake,0) > 0 AND COALESCE(v_balance,0) < g.stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;

  SELECT s INTO v_slot FROM generate_series(0, g.max_players-1) s
    WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id = _game_id)
    ORDER BY s LIMIT 1;

  IF g.max_players = 2 THEN v_color := v_colors2[v_slot + 1];
  ELSIF g.max_players = 3 THEN v_color := v_colors3[v_slot + 1];
  ELSE v_color := v_colors4[v_slot + 1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    VALUES (_game_id, v_uid, v_slot, v_color, COALESCE(v_name, 'Joueur'));

  IF COALESCE(g.stake,0) > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'ludo_stake', -g.stake, _game_id, 'Rejoindre partie Ludo');
    UPDATE public.ludo_games SET pot = pot + g.stake WHERE id = _game_id;
  END IF;

  RETURN _game_id;
END $function$


================================================================================
-- ludo_join_team
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_join_team(_game_id uuid, _team integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game public.ludo_games%ROWTYPE;
  v_count int;
  v_existing_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _team NOT IN (1, 2) THEN RAISE EXCEPTION 'Équipe invalide (1 ou 2)'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status NOT IN ('open', 'waiting') THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF v_game.match_type <> 'groupe' THEN RAISE EXCEPTION 'Cette partie n''est pas en mode groupe'; END IF;

  -- Check player is a participant
  SELECT team INTO v_existing_team FROM public.ludo_participants
    WHERE game_id=_game_id AND user_id=v_uid;
  IF v_existing_team IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- Check team isn't full (max 2 per team)
  SELECT count(*) INTO v_count FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team;
  IF v_count >= 2 AND v_existing_team <> _team THEN
    RAISE EXCEPTION 'Groupe % complet', _team;
  END IF;

  -- Update team
  UPDATE public.ludo_participants SET team=_team
    WHERE game_id=_game_id AND user_id=v_uid;
END $function$


================================================================================
-- ludo_move
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  v_team INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
  v_captured_list jsonb := '[]'::jsonb; v_now text; v_seq int;
  v_qc int; v_finishers int; v_remaining int; v_next_rank int;
  v_is_groupe BOOLEAN;
  v_mode TEXT; v_tile_type TEXT; v_tile jsonb;
  v_power_tiles jsonb; v_shields jsonb; v_shield_arr jsonb;
  v_boost_dice INT; v_boost_new_step INT; v_boost_new_state TEXT;
  v_lucky_reward INT; v_yard_idx INT;
  v_power_bonus BOOLEAN := FALSE; v_has_shield BOOLEAN;
  v_new_slot INT;
  v_dr_consumed BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  v_is_groupe := (g.match_type = 'groupe');
  v_mode := COALESCE(g.mode, 'classic');
  SELECT user_id, is_bot, team INTO v_user, v_isbot, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion déjà arrivé'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Dépassement — chiffre exact requis pour entrer à l''arrivée'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE; ELSE new_state := 'track'; END IF;
  END IF;
  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  -- Consume double_roll_pending BEFORE power tile activation
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_dr_consumed := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  -- Capture check (with shield protection in fast mode)
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR rec IN SELECT slot, team FROM public.ludo_participants
                  WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
        IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
        op_start := public._ludo_start_for(_game_id, rec.slot);
        other_pawns := st->'pawns'->rec.slot::text;
        same_slot_count := 0;
        FOR j IN 0..3 LOOP
          op := other_pawns->j;
          IF op->>'s' = 'track' THEN
            op_step := (op->>'k')::INT;
            IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
              same_slot_count := same_slot_count + 1;
            END IF;
          END IF;
        END LOOP;
        IF same_slot_count = 1 THEN
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                v_has_shield := FALSE;
                IF st ? 'shields' THEN
                  v_shields := st->'shields';
                  IF v_shields ? rec.slot::text THEN
                    v_shield_arr := v_shields->rec.slot::text;
                    FOR i IN 0..jsonb_array_length(v_shield_arr)-1 LOOP
                      IF (v_shield_arr->i)::int = j THEN v_has_shield := TRUE; EXIT; END IF;
                    END LOOP;
                  END IF;
                END IF;
                IF NOT v_has_shield THEN
                  other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                  captured := TRUE;
                  v_captured_list := v_captured_list || jsonb_build_object('slot', rec.slot, 'pawn', j);
                END IF;
              END IF;
            END IF;
          END LOOP;
          st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
        END IF;
      END LOOP;
    END IF;
  END IF;

  -- Power tile activation (Mode Moderne only)
  IF v_mode = 'fast' AND new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    v_power_tiles := COALESCE(st->'power_tiles', '[]'::jsonb);
    v_tile_type := NULL;
    FOR v_tile IN SELECT value FROM jsonb_array_elements(v_power_tiles) LOOP
      IF (v_tile->>'cell')::int = abs_cell THEN v_tile_type := v_tile->>'type'; EXIT; END IF;
    END LOOP;
    IF v_tile_type IS NOT NULL THEN
      v_power_tiles := (
        SELECT COALESCE(jsonb_agg(value), '[]'::jsonb)
        FROM jsonb_array_elements(v_power_tiles)
        WHERE (value->>'cell')::int <> abs_cell OR value->>'type' <> v_tile_type
      );
      v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
      CASE v_tile_type
        WHEN 'boost' THEN
          v_boost_dice := 1 + (floor(random()*6))::INT;
          v_boost_new_step := new_step + v_boost_dice;
          IF v_boost_new_step <= 56 THEN
            IF v_boost_new_step = 56 THEN v_boost_new_state := 'finished'; finished := TRUE;
            ELSE v_boost_new_state := 'track'; END IF;
            arr := st->'pawns'->v_slot::text;
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
            st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
            IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
              abs_cell := (start_idx + v_boost_new_step) % 52;
              IF NOT public._ludo_is_safe(abs_cell) THEN
                FOR rec IN SELECT slot, team FROM public.ludo_participants
                            WHERE game_id=_game_id AND slot <> v_slot AND forfeited=FALSE LOOP
                  IF v_is_groupe AND rec.team IS NOT NULL AND rec.team = v_team THEN CONTINUE; END IF;
                  op_start := public._ludo_start_for(_game_id, rec.slot);
                  other_pawns := st->'pawns'->rec.slot::text;
                  same_slot_count := 0;
                  FOR j IN 0..3 LOOP
                    op := other_pawns->j;
                    IF op->>'s' = 'track' THEN
                      op_step := (op->>'k')::INT;
                      IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                        same_slot_count := same_slot_count + 1;
                      END IF;
                    END IF;
                  END LOOP;
                  IF same_slot_count = 1 THEN
                    FOR j IN 0..3 LOOP
                      op := other_pawns->j;
                      IF op->>'s' = 'track' THEN
                        op_step := (op->>'k')::INT;
                        IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                          v_has_shield := FALSE;
                          IF st ? 'shields' THEN
                            v_shields := st->'shields';
                            IF v_shields ? rec.slot::text THEN
                              v_shield_arr := v_shields->rec.slot::text;
                              FOR i IN 0..jsonb_array_length(v_shield_arr)-1 LOOP
                                IF (v_shield_arr->i)::int = j THEN v_has_shield := TRUE; EXIT; END IF;
                              END LOOP;
                            END IF;
                          END IF;
                          IF NOT v_has_shield THEN
                            other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                            captured := TRUE;
                          END IF;
                        END IF;
                      END IF;
                    END LOOP;
                    st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
                  END IF;
                END LOOP;
              END IF;
            END IF;
          END IF;
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','boost','slot',v_slot,'pawn',_pawn_idx,'dice',v_boost_dice,'at',v_now));
        WHEN 'shield' THEN
          v_shields := COALESCE(st->'shields', '{}'::jsonb);
          v_shield_arr := COALESCE(v_shields->v_slot::text, '[]'::jsonb) || to_jsonb(_pawn_idx);
          v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], v_shield_arr, true);
          st := jsonb_set(st, '{shields}', v_shields, true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','shield','slot',v_slot,'pawn',_pawn_idx,'at',v_now));
        WHEN 'double_roll' THEN
          st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','double_roll','slot',v_slot,'at',v_now));
        WHEN 'lucky_star' THEN
          v_lucky_reward := 1 + (floor(random()*5))::INT;
          CASE v_lucky_reward
            WHEN 1 THEN
              v_boost_dice := 1 + (floor(random()*6))::INT;
              v_boost_new_step := new_step + v_boost_dice;
              IF v_boost_new_step <= 56 THEN
                IF v_boost_new_step = 56 THEN v_boost_new_state := 'finished'; finished := TRUE;
                ELSE v_boost_new_state := 'track'; END IF;
                arr := st->'pawns'->v_slot::text;
                arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','boost','dice',v_boost_dice,'slot',v_slot,'at',v_now));
            WHEN 2 THEN
              v_shields := COALESCE(st->'shields', '{}'::jsonb);
              v_shield_arr := COALESCE(v_shields->v_slot::text, '[]'::jsonb) || to_jsonb(_pawn_idx);
              v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], v_shield_arr, true);
              st := jsonb_set(st, '{shields}', v_shields, true);
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','shield','slot',v_slot,'at',v_now));
            WHEN 3 THEN
              st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','double_roll','slot',v_slot,'at',v_now));
            WHEN 4 THEN
              v_power_bonus := TRUE;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','reroll','slot',v_slot,'at',v_now));
            WHEN 5 THEN
              arr := st->'pawns'->v_slot::text;
              v_yard_idx := -1;
              FOR i IN 0..3 LOOP
                IF (arr->i->>'s') = 'yard' AND i <> _pawn_idx THEN v_yard_idx := i; EXIT; END IF;
              END LOOP;
              IF v_yard_idx >= 0 THEN
                arr := jsonb_set(arr, ARRAY[v_yard_idx::text], jsonb_build_object('s','track','k',0));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','reward','free_pawn','slot',v_slot,'pawn',v_yard_idx,'at',v_now));
          END CASE;
      END CASE;
      v_power_tiles := public._ludo_relocate_tile(v_power_tiles, v_tile_type, _game_id, st, abs_cell);
      st := jsonb_set(st, '{power_tiles}', v_power_tiles, true);
    END IF;
  END IF;

  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;
  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_seq := COALESCE((st->>'turn_seq')::int, 0);
  PERFORM public._ludo_push_move(_game_id, jsonb_build_object(
    'seq', v_seq, 'slot', v_slot, 'pawn', _pawn_idx, 'dice', v_dice,
    'captured', v_captured_list, 'finished', finished, 'at', v_now
  ));

  IF all_done THEN
    SELECT COALESCE(MAX(finish_rank),0)+1 INTO v_next_rank
      FROM public.ludo_participants WHERE game_id=_game_id;
    UPDATE public.ludo_participants SET finish_rank = v_next_rank
      WHERE game_id=_game_id AND slot=v_slot;
    v_qc := 1;
    IF g.tournament_match_id IS NOT NULL THEN
      SELECT COALESCE(qualifiers_count,1) INTO v_qc FROM public.tournament_matches WHERE id = g.tournament_match_id;
    END IF;
    SELECT count(*) INTO v_finishers FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NOT NULL;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NULL AND forfeited=FALSE;
    IF v_finishers >= v_qc OR v_remaining <= 1 THEN
      SELECT user_id INTO winner_uid FROM public.ludo_participants
        WHERE game_id=_game_id AND finish_rank=1;
      PERFORM public.finish_game(_game_id, winner_uid);
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    ELSE
      RETURN public._ludo_advance_turn(
        _game_id, public._ludo_next_slot(_game_id, v_slot, v_max), 'home:continue'
      );
    END IF;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  IF v_dr_consumed THEN bonus := TRUE; END IF;
  IF v_power_bonus THEN bonus := TRUE; END IF;
  IF NOT bonus THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  RETURN public._ludo_advance_turn(
    _game_id,
    CASE WHEN bonus THEN v_slot ELSE public._ludo_next_slot(_game_id, v_slot, v_max) END,
    CASE WHEN bonus THEN (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue') ELSE 'move' END
  );
END $function$


================================================================================
-- ludo_pass
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_dice INT;
  v_uid UUID := auth.uid(); v_user UUID; v_isbot BOOLEAN; arr jsonb;
  pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;
  IF has_move THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;

  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'));
  st := st - 'no_move_display' - 'power_event' - 'movable_pawns';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$


================================================================================
-- ludo_purge_unready_rooms
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_purge_unready_rooms()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g RECORD;
  p RECORD;
  v_count int := 0;
BEGIN
  FOR g IN
    SELECT * FROM public.ludo_games
    WHERE status='open'
      AND ready_deadline IS NOT NULL
      AND now() > ready_deadline
  LOOP
    -- rembourse uniquement les humains (pas les bots), montant = mise du jeu
    FOR p IN
      SELECT user_id
      FROM public.ludo_participants
      WHERE game_id = g.id
        AND user_id IS NOT NULL
        AND COALESCE(is_bot,false) = false
    LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles
          SET balance_ar = balance_ar + g.stake
          WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', g.stake, g.id, 'Salle Ludo expirée (non prêts)');
      END IF;
    END LOOP;
    PERFORM public._ludo_purge(g.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$


================================================================================
-- ludo_quit
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id=_game_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'refund',g.stake,_game_id,'Annulation avant départ');
    DELETE FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=false;
    IF v_remaining = 0 THEN PERFORM public._ludo_purge(_game_id); END IF;
    RETURN;
  END IF;

  IF g.is_solo THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  st := g.state;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  END IF;
  v_winner := public._ludo_check_last_standing(_game_id);
  IF v_winner IS NOT NULL THEN
    PERFORM public.finish_game(_game_id, v_winner);
  ELSIF public._ludo_active_humans(_game_id) = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
  END IF;
END $function$


================================================================================
-- ludo_roll
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  st jsonb;
  g public.ludo_games%ROWTYPE;
  v_uid UUID := auth.uid();
  v_slot INT;
  v_user UUID;
  v_isbot BOOLEAN;
  v_bias INT;
  v_dice INT;
  v_consec INT;
  v_override INT;
  v_new_slot INT;
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes
    INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot AND v_user <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;
  IF (st->>'must_move')::BOOLEAN THEN
    RAISE EXCEPTION 'Déjà lancé, déplacez un pion';
  END IF;

  v_override := NULLIF(g.dice_override->>v_slot::text, '')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    v_dice := 1 + (floor(random() * 6))::INT;
    IF v_isbot AND COALESCE(v_bias, 0) > 0 AND (random() * 100) < v_bias THEN
      v_dice := 6;
    END IF;
  END IF;

  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

  -- Triple six → cancel turn
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st, '{turn_started_at}',
      to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display' - 'movable_pawns';
    UPDATE public.ludo_games
      SET state = st, current_turn = (st->>'turn_slot')::INT
      WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  st := jsonb_set(st, '{turn_started_at}',
    to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));
  st := st - 'no_move_display';

  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);

  IF jsonb_array_length(v_movable) = 0 THEN
    IF v_isbot THEN
      IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
        st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
      END IF;
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{must_move}', 'false'::jsonb);
      v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
      st := public._ludo_clear_shield(st, v_new_slot);
      st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
      st := jsonb_set(st, '{turn_started_at}',
        to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
      st := jsonb_set(st, '{last_event}',
        to_jsonb('roll:' || v_dice || ':no_move'));
      st := jsonb_set(st, '{dice}', 'null'::jsonb);
      st := st - 'movable_pawns';
      UPDATE public.ludo_games
        SET state = st, current_turn = (st->>'turn_slot')::INT
        WHERE id = _game_id;
      PERFORM public._ludo_check_game_over(_game_id);
      RETURN st;
    ELSE
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
      RETURN st;
    END IF;
  ELSE
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;
END $function$


================================================================================
-- ludo_set_auto_move
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_set_auto_move(_game_id uuid, _enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.host_id <> auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Réservé au créateur de la partie';
  END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;
  UPDATE public.ludo_games SET auto_move = COALESCE(_enabled, false) WHERE id = _game_id;
END $function$


================================================================================
-- ludo_set_display_name
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_set_display_name(_game_id uuid, _name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _name IS NULL OR length(trim(_name)) < 2 THEN RAISE EXCEPTION 'Nom invalide'; END IF;
  UPDATE public.ludo_participants
    SET display_name = trim(_name)
    WHERE game_id=_game_id AND user_id=v_uid;
END $function$


================================================================================
-- ludo_set_ready
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  IF _ready AND NOT v_game.is_solo AND COALESCE(v_game.stake, 0) > 0 THEN
    SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
    IF NOT COALESCE(v_verified,false) THEN
      RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
    END IF;
  END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic')),
      current_turn = 0
    WHERE id=_game_id;
  END IF;
END $function$


================================================================================
-- ludo_start_solo_bot
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        UUID := auth.uid();
  v_game_id    UUID;
  v_code       TEXT;
  v_commission NUMERIC;
  v_i          INT;
  v_slot       INT;
  v_color      TEXT;
  v_colors     TEXT[] := ARRAY['red','green','yellow','blue'];
  v_bots       TEXT[] := ARRAY['BotAlpha','BotBeta','BotGamma','BotDelta'];
  v_intel      INT;
  v_bias       INT;
  v_mp         INT;
  v_mode       TEXT;
  v_pseudo     TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  v_mp := LEAST(GREATEST(COALESCE(_max_players, 2), 2), 4);

  SELECT COALESCE(game_commission_pct, 10) INTO v_commission FROM public.app_settings WHERE id = 1;
  SELECT COALESCE(pseudo, '') INTO v_pseudo FROM public.profiles WHERE id = v_uid;

  v_code := upper(substr(md5(random()::text), 1, 6));

  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct,
    room_code, is_private, mode, match_type, status, is_solo
  ) VALUES (
    v_uid, v_mp, _stake, _stake * v_mp, v_commission,
    v_code, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE
  ) RETURNING id INTO v_game_id;

  -- Host (human) — include display_name
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, ready, display_name, joined_at)
  VALUES (v_game_id, v_uid, 0, v_colors[1], FALSE, TRUE, v_pseudo, now());

  v_intel := CASE WHEN _difficulty = 'hard' THEN 85 WHEN _difficulty = 'easy' THEN 40 ELSE 65 END;
  v_bias  := CASE WHEN _difficulty = 'hard' THEN 15 WHEN _difficulty = 'easy' THEN 0 ELSE 5 END;

  FOR v_i IN 1..v_mp - 1 LOOP
    -- Bots — use bot_name as display_name
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot,
      bot_name, bot_intelligence, bot_win_bias, ready, display_name, joined_at
    ) VALUES (
      v_game_id, v_uid, v_i, v_colors[v_i+1], TRUE,
      v_bots[v_i], v_intel, v_bias, TRUE, v_bots[v_i], now()
    );
  END LOOP;

  UPDATE public.ludo_games SET
    status = 'playing',
    started_at = now(),
    state = public._ludo_init_state(v_mp, v_mode),
    current_turn = 0
  WHERE id = v_game_id;

  RETURN v_game_id;
END $function$


================================================================================
-- ludo_tick_all
================================================================================
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g_id uuid;
  st jsonb;
  v_slot int;
  v_isbot boolean;
  v_started timestamptz;
BEGIN
  PERFORM public.ludo_cleanup_empty_rooms();

  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      PERFORM public.ludo_check_timeout(g_id);
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::int;
      SELECT is_bot INTO v_isbot
        FROM public.ludo_participants
       WHERE game_id=g_id AND slot=v_slot;
      IF COALESCE(v_isbot, false) THEN
        v_started := (st->>'turn_started_at')::timestamptz;
        IF v_started IS NULL OR now() - v_started >= interval '3 seconds' THEN
          PERFORM public.ludo_bot_step(g_id);
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $function$


