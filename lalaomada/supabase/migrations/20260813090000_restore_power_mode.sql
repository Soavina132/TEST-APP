-- ════════════════════════════════════════════════════════════════════
-- RESTORE: Ludo Mode Moderne (Power Tiles)
-- Date: 2026-08-13
-- Problem: Power tile functions were lost when ludo functions were
--          rewritten on Aug 11-13. _ludo_init_state no longer accepts
--          _mode, and no power tile logic exists in ludo_move/roll/pass.
-- Fix: Restore all power tile helper functions + merge power tile logic
--      into current ludo_move/roll/pass (preserving tournament & team support)
-- ════════════════════════════════════════════════════════════════════

-- ═══ 1. Helper: valid cells for power tiles ═══
CREATE OR REPLACE FUNCTION public._ludo_power_valid_cells()
RETURNS int[]
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ARRAY(
    SELECT i FROM generate_series(0,51) i
    WHERE i NOT IN (0, 8, 13, 21, 26, 34, 39, 47)
  )
$$;

-- ═══ 2. Helper: place 6 power tiles on valid cells ═══
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
END $function$;

-- ═══ 3. Helper: relocate a consumed power tile to a new cell ═══
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
END $function$;

-- ═══ 4. Helper: clear shield for a slot ═══
CREATE OR REPLACE FUNCTION public._ludo_clear_shield(st jsonb, _slot int)
RETURNS jsonb
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN st ? 'shields' AND (st->'shields') ? _slot::text
    THEN jsonb_set(st, '{shields}', (st->'shields') - _slot::text, true)
    ELSE st
  END
$$;

-- ═══ 5. Helper: check game over (solo + multiplayer) ═══
CREATE OR REPLACE FUNCTION public._ludo_check_game_over(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
END $function$;

-- ═══ 6. Update _ludo_init_state: accept _mode, generate power tiles ═══
CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players INT, _mode TEXT DEFAULT 'classic')
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
END $function$;

-- ═══ 7. Update _ludo_ensure_state: pass g.mode ═══
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id UUID)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
END $function$;

-- ═══ 8. Update _ludo_advance_turn: clear shield for new player ═══
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
END $function$;

-- ═══ 9. Update ludo_set_ready: pass mode to _ludo_init_state ═══
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
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
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_set_ready(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_set_ready(uuid, boolean) TO authenticated;

-- ═══ 10. Update ludo_roll: double_roll, shield clearing, movable_pawns ═══
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
END $function$;

-- ═══ 11. Update ludo_move: power tiles + shield + tournament + team ═══
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
END $function$;

-- ═══ 12. Update ludo_pass: power mode cleanup + shield clearing ═══
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
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
END $function$;

-- ═══ 13. Update ludo_check_timeout: power mode cleanup + shield clearing ═══
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
END $function$;

-- ═══ 14. Update ludo_start_solo_bot: pass mode to _ludo_init_state ═══
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(_max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium'::text, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game_id UUID; v_code TEXT;
  v_commission NUMERIC; v_i INT; v_slot INT; v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
  v_bots TEXT[] := ARRAY['BotAlpha','BotBeta','BotGamma','BotDelta'];
  v_intel INT; v_bias INT; v_mp INT; v_mode TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  v_mp := LEAST(GREATEST(COALESCE(_max_players, 2), 2), 4);
  SELECT COALESCE(commission_pct, 10) INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := upper(substr(md5(random()::text), 1, 6));
  
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, v_mp, _stake, _stake * v_mp, v_commission, v_code, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;
  
  -- Host as slot 0
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, ready, joined_at)
  VALUES (v_game_id, v_uid, 0, v_colors[1], FALSE, TRUE, now());
  
  -- Add bots for remaining slots
  v_intel := CASE WHEN _difficulty = 'hard' THEN 85 WHEN _difficulty = 'easy' THEN 40 ELSE 65 END;
  v_bias := CASE WHEN _difficulty = 'hard' THEN 15 WHEN _difficulty = 'easy' THEN 0 ELSE 5 END;
  
  FOR v_i IN 1..v_mp-1 LOOP
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, bot_intelligence, bot_win_bias, ready, joined_at)
    VALUES (v_game_id, v_uid, v_i, v_colors[v_i+1], TRUE, v_bots[v_i], v_intel, v_bias, TRUE, now());
  END LOOP;
  
  -- Start the game immediately
  UPDATE public.ludo_games SET status='playing', started_at=now(),
    state=public._ludo_init_state(v_mp, v_mode),
    current_turn=0
  WHERE id=v_game_id;
  
  RETURN v_game_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) TO authenticated;

-- ═══ 15. _ludo_movable_pawns helper (used by ludo_roll) ═══
CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot INT, _dice INT)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
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
END $function$;
