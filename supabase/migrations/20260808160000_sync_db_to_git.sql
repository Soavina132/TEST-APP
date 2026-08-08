-- ═══════════════════════════════════════════════════════════════════════
-- SYNC: Synchronise le code git avec l'état réel de la base de données
-- 
-- Cette migration capture toutes les modifications manuelles qui ont été
-- appliquées directement sur la base Supabase sans passer par des migrations
-- git-trackées. Inclut:
--   - _ludo_place_power_tiles: 6 tuiles au lieu de 4, avec champ cd
--   - _ludo_relocate_tile: évite les cases occupées par des pions
--   - _ludo_clear_shield: nouvelle fonction dédiée
--   - _ludo_decrement_cooldowns: scaffold pour cooldowns (no-op)
--   - ludo_move: power loop, shields booléens, finish_rank, push_move
--   - ludo_roll: gestion double_roll_pending, clear shield, clear power_event
--   - ludo_check_timeout: auto-resolve power_pending + FIX: clear shield
--   - ludo_choose_power: stub pour power tiles interactifs (futur)
--   - ludo_pass, ludo_create, ludo_quick_start, ludo_rematch, etc.
--   - _ludo_playable_pawns, _ludo_sync_turn_snapshot
-- 
-- BUG FIX: ludo_check_timeout ne clearait pas le shield du nouveau joueur
-- ═══════════════════════════════════════════════════════════════════════

-- ======================================================================
-- Function: _ludo_advance_turn
-- ======================================================================
CREATE OR REPLACE FUNCTION public._ludo_advance_turn(_game_id uuid, _new_slot integer, _last_event text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_isbot boolean;
  v_spin_ms int; v_seq int; v_now text; v_shields jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  st := g.state;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=_new_slot;
  v_spin_ms := CASE WHEN COALESCE(v_isbot, FALSE) THEN 2500 ELSE 0 END;
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  st := jsonb_set(st, '{turn_slot}', to_jsonb(_new_slot));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
  st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{spin_ms}', to_jsonb(v_spin_ms));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{last_event}', to_jsonb(_last_event));
  -- Mode Moderne: clear shields for new player (expires at owner next turn)
  IF st ? 'shields' THEN
    v_shields := st->'shields';
    IF v_shields ? _new_slot::text THEN
      v_shields := v_shields - _new_slot::text;
      st := jsonb_set(st, '{shields}', v_shields, true);
    END IF;
  END IF;
  -- FIX 5: Decrement power tile cooldowns on every turn advance
  st := public._ludo_decrement_cooldowns(st);
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=_new_slot WHERE id=_game_id;
  RETURN st;
END $function$


-- ======================================================================
-- Function: _ludo_clear_shield
-- ======================================================================
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


-- ======================================================================
-- Function: _ludo_decrement_cooldowns
-- ======================================================================
CREATE OR REPLACE FUNCTION public._ludo_decrement_cooldowns(st jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT st;
$function$


-- ======================================================================
-- Function: _ludo_place_power_tiles
-- ======================================================================
CREATE OR REPLACE FUNCTION public._ludo_place_power_tiles()
 RETURNS jsonb
 LANGUAGE plpgsql
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


-- ======================================================================
-- Function: _ludo_playable_pawns
-- ======================================================================
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


-- ======================================================================
-- Function: _ludo_relocate_tile
-- ======================================================================
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

  v_available := ARRAY(
    SELECT c FROM unnest(v_valid) c WHERE NOT (c = ANY(v_occupied))
  );

  IF array_length(v_available, 1) IS NULL OR array_length(v_available, 1) = 0 THEN
    FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
      v_result := v_result || v_tile;
    END LOOP;
    RETURN v_result;
  END IF;

  v_new_cell := v_available[1 + floor(random() * array_length(v_available, 1))::int];

  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF (v_tile->>'cell')::int = _old_cell THEN
      v_result := v_result || jsonb_build_object('type', v_tile->>'type', 'cell', v_new_cell);
    ELSE
      v_result := v_result || v_tile;
    END IF;
  END LOOP;

  RETURN v_result;
END $function$


-- ======================================================================
-- Function: _ludo_sync_turn_snapshot
-- ======================================================================
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


-- ======================================================================
-- Function: ludo_check_timeout
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int; v_choice text;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;

  -- Auto-resolve power_pending on timeout
  IF st ? 'power_pending' THEN
    IF (st->'power_pending'->>'tile_type') = 'boost' THEN
      v_choice := 'skip';
    ELSE
      v_choice := (st->'power_pending'->'options'->>0);
    END IF;
    PERFORM public.ludo_choose_power(_game_id, v_choice);
    SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
    RETURN st;
  END IF;

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
  st := public._ludo_decrement_cooldowns(st);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END $function$


-- ======================================================================
-- Function: ludo_choose_power
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_choose_power(_game_id uuid, _choice text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE st jsonb;
BEGIN
  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  RETURN st;
END $function$


-- ======================================================================
-- Function: ludo_cleanup_empty_rooms
-- ======================================================================
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


-- ======================================================================
-- Function: ludo_create
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_create(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.ludo_games (max_players, stake, created_by, pot, mode, match_type)
    VALUES (_max_players, _stake, _uid, _stake, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'ludo_stake', -_stake, _id, 'Create ludo');
  END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $function$


-- ======================================================================
-- Function: ludo_move
-- ======================================================================
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
  v_is_groupe BOOLEAN;
  v_mode TEXT; v_tile_type TEXT; v_tile jsonb;
  v_power_tiles jsonb; v_shields jsonb;
  v_has_shield BOOLEAN;
  v_power_bonus BOOLEAN := FALSE; v_now text;
  v_new_slot INT;
  v_dr_consumed BOOLEAN := FALSE;
  v_captured_list jsonb := '[]'::jsonb;
  v_seq int;
  v_qc int; v_finishers int; v_remaining int; v_next_rank int;
  v_boost_dice INT; v_boost_new_step INT; v_boost_new_state TEXT;
  v_lucky_options text[];
  v_lucky_pick TEXT;
  v_yard_idx INT;
  v_loop_count INT := 0;
  v_event_cell INT;
  v_has_yard_pawn BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  v_is_groupe := (g.match_type = 'groupe');
  v_mode := COALESCE(g.mode, 'classic');
  SELECT user_id, is_bot, team INTO v_user, v_isbot, v_team
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion deja arrive'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE;
    Else new_state := 'track'; END IF;
  END IF;
  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_dr_consumed := TRUE;
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

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
                IF st ? 'shields' AND (st->'shields') ? rec.slot::text THEN
                  v_has_shield := (st->'shields'->rec.slot::text)::boolean;
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

  <<power_loop>>
  LOOP
    v_loop_count := v_loop_count + 1;
    IF v_loop_count > 3 THEN EXIT; END IF;

    IF v_mode = 'fast' AND new_state = 'track' AND new_step <= 50 THEN
      start_idx := public._ludo_start_for(_game_id, v_slot);
      abs_cell := (start_idx + new_step) % 52;
      v_event_cell := abs_cell;

      v_power_tiles := COALESCE(st->'power_tiles', '[]'::jsonb);
      v_tile_type := NULL;
      FOR v_tile IN SELECT value FROM jsonb_array_elements(v_power_tiles) LOOP
        IF (v_tile->>'cell')::int = abs_cell THEN v_tile_type := v_tile->>'type'; EXIT; END IF;
      END LOOP;

      EXIT power_loop WHEN v_tile_type IS NULL;

      v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');

      v_power_tiles := public._ludo_relocate_tile(v_power_tiles, v_tile_type, _game_id, st, abs_cell);
      st := jsonb_set(st, '{power_tiles}', v_power_tiles, true);

      CASE v_tile_type
        WHEN 'shield' THEN
          v_shields := COALESCE(st->'shields', '{}'::jsonb);
          v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], 'true'::jsonb, true);
          st := jsonb_set(st, '{shields}', v_shields, true);
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','shield','slot',v_slot,'cell',v_event_cell,'at',v_now));

        WHEN 'double_roll' THEN
          st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','double_roll','slot',v_slot,'cell',v_event_cell,'at',v_now));
          v_power_bonus := TRUE;
          EXIT power_loop;

        WHEN 'boost' THEN
          v_boost_dice := 1 + (floor(random()*6))::INT;
          v_boost_new_step := new_step + v_boost_dice;
          IF v_boost_new_step <= 56 THEN
            IF v_boost_new_step = 56 THEN
              v_boost_new_state := 'finished';
              finished := TRUE;
              new_state := 'finished';
              new_step := 56;
            ELSE
              v_boost_new_state := 'track';
              new_step := v_boost_new_step;
            END IF;
            arr := st->'pawns'->v_slot::text;
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
            st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

            IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
              start_idx := public._ludo_start_for(_game_id, v_slot);
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
                          IF st ? 'shields' AND (st->'shields') ? rec.slot::text THEN
                            v_has_shield := (st->'shields'->rec.slot::text)::boolean;
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
          END IF;
          st := jsonb_set(st, '{power_event}', jsonb_build_object('type','boost','slot',v_slot,'dice',v_boost_dice,'cell',v_event_cell,'at',v_now));
          IF v_boost_new_state = 'finished' THEN EXIT power_loop; END IF;

        WHEN 'lucky_star' THEN
          arr := st->'pawns'->v_slot::text;
          v_has_yard_pawn := FALSE;
          FOR i IN 0..3 LOOP
            IF (arr->i->>'s') = 'yard' THEN v_has_yard_pawn := TRUE; EXIT; END IF;
          END LOOP;
          IF v_has_yard_pawn THEN
            v_lucky_options := ARRAY['boost','shield','double_roll','free_pawn','reroll'];
          ELSE
            v_lucky_options := ARRAY['boost','shield','double_roll','reroll'];
          END IF;

          v_lucky_pick := v_lucky_options[1 + floor(random()*array_length(v_lucky_options,1))::int];
          v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');

          CASE v_lucky_pick
            WHEN 'boost' THEN
              v_boost_dice := 1 + (floor(random()*6))::INT;
              v_boost_new_step := new_step + v_boost_dice;
              IF v_boost_new_step <= 56 THEN
                IF v_boost_new_step = 56 THEN
                  v_boost_new_state := 'finished'; finished := TRUE; new_state := 'finished'; new_step := 56;
                ELSE v_boost_new_state := 'track'; new_step := v_boost_new_step;
                END IF;
                arr := st->'pawns'->v_slot::text;
                arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', v_boost_new_state, 'k', v_boost_new_step));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
                IF v_boost_new_state = 'track' AND v_boost_new_step <= 50 THEN
                  start_idx := public._ludo_start_for(_game_id, v_slot);
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
                              IF st ? 'shields' AND (st->'shields') ? rec.slot::text THEN
                                v_has_shield := (st->'shields'->rec.slot::text)::boolean;
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
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','boost','dice',v_boost_dice,'cell',v_event_cell,'at',v_now));
              IF v_boost_new_state = 'finished' THEN EXIT power_loop; END IF;

            WHEN 'shield' THEN
              v_shields := COALESCE(st->'shields', '{}'::jsonb);
              v_shields := jsonb_set(v_shields, ARRAY[v_slot::text], 'true'::jsonb, true);
              st := jsonb_set(st, '{shields}', v_shields, true);
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','shield','cell',v_event_cell,'at',v_now));
              EXIT power_loop;

            WHEN 'double_roll' THEN
              st := jsonb_set(st, '{double_roll_pending}', to_jsonb(v_slot));
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','double_roll','cell',v_event_cell,'at',v_now));
              v_power_bonus := TRUE;
              EXIT power_loop;

            WHEN 'free_pawn' THEN
              arr := st->'pawns'->v_slot::text;
              v_yard_idx := -1;
              FOR i IN 0..3 LOOP
                IF (arr->i->>'s') = 'yard' THEN v_yard_idx := i; EXIT; END IF;
              END LOOP;
              IF v_yard_idx >= 0 THEN
                arr := jsonb_set(arr, ARRAY[v_yard_idx::text], jsonb_build_object('s','track','k',0));
                st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
              END IF;
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','free_pawn','cell',v_event_cell,'at',v_now));
              EXIT power_loop;

            WHEN 'reroll' THEN
              st := jsonb_set(st, '{power_event}', jsonb_build_object('type','lucky_star','slot',v_slot,'reward','reroll','cell',v_event_cell,'at',v_now));
              v_power_bonus := TRUE;
              EXIT power_loop;
          END CASE;
      END CASE;
    ELSE
      EXIT power_loop;
    END IF;
  END LOOP power_loop;

  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;

  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;

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
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;

    v_qc := 1;
    IF g.tournament_match_id IS NOT NULL THEN
      SELECT COALESCE(qualifiers_count,1) INTO v_qc
        FROM public.tournament_matches WHERE id = g.tournament_match_id;
    END IF;

    SELECT count(*) INTO v_finishers FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NOT NULL;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NULL AND forfeited=FALSE;

    IF v_finishers >= v_qc OR v_remaining <= 1 THEN
      SELECT user_id INTO winner_uid FROM public.ludo_participants
        WHERE game_id=_game_id AND finish_rank=1;
      IF v_is_groupe AND v_team IS NOT NULL THEN
        PERFORM public._ludo_finish_team(_game_id, winner_uid, v_team);
      ELSE
        PERFORM public.finish_game(_game_id, winner_uid);
      END IF;
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    ELSE
      v_new_slot := public._ludo_next_slot(_game_id, v_slot, v_max);
      st := public._ludo_clear_shield(st, v_new_slot);
      st := public._ludo_decrement_cooldowns(st);
      st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
      st := jsonb_set(st,'{last_event}', to_jsonb('home:continue'));
      st := jsonb_set(st,'{must_move}','false'::jsonb);
      st := jsonb_set(st,'{dice}','null'::jsonb);
      st := st - 'no_move_display';
      st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
      UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
      PERFORM public._ludo_check_game_over(_game_id);
      RETURN st;
    END IF;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  IF v_power_bonus THEN bonus := TRUE; END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := st - 'no_move_display';
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, v_max);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$


-- ======================================================================
-- Function: ludo_pass
-- ======================================================================
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

  -- BUG 4 FIX: Clean up power mode state
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  -- BUG 1 FIX: Clear shield for the new player
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'));
  st := st - 'no_move_display';
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  PERFORM public._ludo_check_game_over(_game_id);

  RETURN st;
END $function$


-- ======================================================================
-- Function: ludo_purge_unready_rooms
-- ======================================================================
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


-- ======================================================================
-- Function: ludo_quick_start
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_quick_start(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_game_id uuid;
  v_code text;
  v_name text;
  v_balance numeric;
  v_paused boolean;
  v_banned boolean;
  v_commission numeric;
  v_slot int;
  v_colors text[];
  v_color text;
  v_team int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, COALESCE(pseudo, 'Joueur'), balance_ar
    INTO v_banned, v_name, v_balance
    FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  v_colors := CASE _max_players
    WHEN 2 THEN ARRAY['red', 'yellow']
    WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
    ELSE ARRAY['red', 'green', 'yellow', 'blue']
  END;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  v_code := public._gen_room_code();

  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type
  ) VALUES (
    v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), v_code, TRUE, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo')
  ) RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise creation partie solo bot');
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_colors[1], v_name, TRUE, FALSE);

  FOR v_slot IN 1.._max_players - 1 LOOP
    v_color := v_colors[v_slot + 1];
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN v_slot % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, v_slot, v_color, TRUE,
      v_bot_names[v_slot], v_bot_names[v_slot],
      70, 0, TRUE, v_team
    );
  END LOOP;

  UPDATE public.ludo_games
    SET status = 'playing'::game_status, started_at = now(),
        state = public._ludo_init_state(_max_players),
        current_turn = 0
    WHERE id = v_game_id;

  RETURN v_game_id;
END $function$


-- ======================================================================
-- Function: ludo_rematch
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_rematch(_old_game_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_old public.ludo_games%ROWTYPE;
  v_new_id uuid;
  v_part public.ludo_participants%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_colors TEXT[];
  v_color TEXT;
  v_room_code TEXT;
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;

  SELECT * INTO v_old FROM public.ludo_games WHERE id = _old_game_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_old.status <> 'finished' THEN RAISE EXCEPTION 'La partie doit etre terminee'; END IF;

  v_room_code := CASE WHEN v_old.is_private THEN substr(md5(random()::text), 1, 6) ELSE NULL END;

  INSERT INTO public.ludo_games(max_players, stake, mode, is_private, room_code, commission_pct, status, pot, created_by)
  VALUES (v_old.max_players, v_old.stake, v_old.mode, v_old.is_private,
          v_room_code, v_old.commission_pct, 'open', 0, v_uid)
  RETURNING id INTO v_new_id;

  -- Copy non-forfeited real players
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND NOT is_bot ORDER BY slot
  LOOP
    IF v_old.stake > 0 THEN
      IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_part.user_id AND balance_ar >= v_old.stake) THEN
        CONTINUE;
      END IF;
    END IF;

    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    v_slot := v_count;
    v_colors := CASE v_old.max_players
      WHEN 2 THEN ARRAY['red', 'yellow']
      WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
      ELSE ARRAY['red', 'green', 'yellow', 'blue']
    END;
    v_color := v_colors[v_slot + 1];

    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_new_id, v_part.user_id, v_slot, v_color, v_part.display_name, false);

    IF v_old.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar - v_old.stake WHERE id = v_part.user_id;
      UPDATE public.ludo_games SET pot = pot + v_old.stake WHERE id = v_new_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_part.user_id, 'stake', -v_old.stake, v_new_id, 'Mise revanche');
    END IF;
  END LOOP;

  -- Copy bots
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND is_bot ORDER BY slot
  LOOP
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    IF v_count >= v_old.max_players THEN EXIT; END IF;
    v_slot := v_count;
    v_colors := CASE v_old.max_players
      WHEN 2 THEN ARRAY['red', 'yellow']
      WHEN 3 THEN ARRAY['red', 'yellow', 'blue']
      ELSE ARRAY['red', 'green', 'yellow', 'blue']
    END;
    v_color := v_colors[v_slot + 1];
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready)
    VALUES (v_new_id, NULL, v_slot, v_color, TRUE, v_part.bot_name, v_part.bot_name,
      v_part.bot_intelligence, 0, TRUE);
  END LOOP;

  -- Auto-start if full
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
  IF v_count >= v_old.max_players THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(),
      state = public._ludo_init_state(v_old.max_players) WHERE id = v_new_id;
  END IF;

  RETURN v_new_id;
END $function$


-- ======================================================================
-- Function: ludo_roll
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT; v_override int; v_display jsonb;
  v_new_slot INT; v_has_double_roll BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;
  v_override := NULLIF(g.dice_override->>v_slot::text,'')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id=_game_id;
  ELSE
    v_dice := 1 + (floor(random()*6))::INT;
    IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
  END IF;

  -- Check if player has double_roll pending
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    v_has_double_roll := TRUE;
  END IF;

  IF v_dice = 6 THEN v_consec := COALESCE(v_consec,0) + 1; ELSE v_consec := 0; END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;

  -- Triple sixes: cancel turn (but double_roll still consumed)
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    -- FIX 4: clear shield + decrement cooldowns for new player
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    IF v_has_double_roll THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display';
    st := st - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));
  st := st - 'no_move_display';

  -- Check if player can move
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice=6 THEN has_move:=TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move:=TRUE; EXIT; END IF; END IF;
  END LOOP;

  IF NOT has_move THEN
    -- FIX 2: If player has double_roll_pending, give them the second roll
    -- instead of consuming it and advancing the turn
    IF v_has_double_roll THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
      st := jsonb_set(st,'{must_move}','false'::jsonb);
      st := jsonb_set(st,'{dice}','null'::jsonb);
      st := jsonb_set(st,'{turn_slot}', to_jsonb(v_slot));
      st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
      st := jsonb_set(st,'{last_event}', to_jsonb('double_roll:rejoue'));
      st := st - 'no_move_display';
      st := st - 'power_event';
      UPDATE public.ludo_games SET state=st WHERE id=_game_id;
      RETURN st;
    END IF;

    -- Normal no-move: advance turn
    v_display := jsonb_build_object('slot', v_slot, 'dice', v_dice,
      'until', to_char((now() + interval '1.5 seconds') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    -- FIX 3: clear shield + decrement cooldowns for new player
    st := public._ludo_clear_shield(st, v_new_slot);
    st := public._ludo_decrement_cooldowns(st);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    st := jsonb_set(st,'{no_move_display}', v_display);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := st - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $function$


-- ======================================================================
-- Function: ludo_set_auto_move
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_set_auto_move(_game_id uuid, _enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE ludo_games SET state = state || jsonb_build_object('auto_move_' || v_uid::text, _enabled) WHERE id = _game_id;
END;
$function$


-- ======================================================================
-- Function: ludo_set_display_name
-- ======================================================================
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


-- ======================================================================
-- Function: ludo_set_finish_position
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_set_finish_position(_game_id uuid, _user_id uuid, _position integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentification requise'; END IF;
  -- L'appelant doit être le joueur lui-même ou un admin
  IF v_uid <> _user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Vous ne pouvez enregistrer que votre propre position';
  END IF;
  -- Vérifier que le joueur participe bien à cette partie
  IF NOT EXISTS (
    SELECT 1 FROM public.ludo_participants
    WHERE game_id = _game_id AND user_id = _user_id
  ) THEN
    RAISE EXCEPTION 'Joueur non participant à cette partie';
  END IF;

  UPDATE public.ludo_participants
    SET finish_position = _position
    WHERE game_id = _game_id
      AND user_id = _user_id
      AND finish_position IS NULL;
END $function$


-- ======================================================================
-- Function: ludo_start_solo_bot
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int := 70;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_balance numeric;
  v_commission numeric;
  v_team int;
  v_init_state jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  -- Créer directement en status='playing' — pas de salle d'attente
  v_init_state := public._ludo_init_state(_max_players, COALESCE(_mode, 'classic'));

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo,
                                started_at, state, current_turn)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,0),
          TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'), 'playing', TRUE,
          now(), v_init_state, 0)
  RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');
  END IF;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  -- Humain toujours slot 0 = 'red', team 1 in groupe mode
  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;

  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE, v_team);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team
    );
  END LOOP;

  RETURN v_game_id;
END $function$


-- ======================================================================
-- Function: ludo_tick_all
-- ======================================================================
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  v_started TIMESTAMPTZ;
  st JSONB;
  v_must_move BOOLEAN;
BEGIN
  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      PERFORM public.ludo_check_timeout(g_id);
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;
      IF v_isbot THEN
        v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
        v_must_move := COALESCE((st->>'must_move')::BOOLEAN, FALSE);
        -- Roll phase: trigger after 3s (frontend uses 1.5-3.5s humanized delay)
        -- Move phase: trigger after 5s (frontend uses 2-4.5s humanized delay)
        -- This acts as a safety net when the frontend is not loaded
        IF NOT v_must_move AND now() - v_started >= interval '3 seconds' THEN
          PERFORM public.ludo_bot_play(g_id);
        ELSIF v_must_move AND now() - v_started >= interval '5 seconds' THEN
          PERFORM public.ludo_bot_play(g_id);
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END $function$


