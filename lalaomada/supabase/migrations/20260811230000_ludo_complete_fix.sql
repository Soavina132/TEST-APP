-- ════════════════════════════════════════════════════════════════════
-- FIX COMPLET LUDO — Aucune erreur sur le jeu
-- Corrige: permissions, phone_verified, FOR loop null, bot autoplay
-- ════════════════════════════════════════════════════════════════════

-- ═══ 1. FIX _ludo_init_state: COALESCE max_players pour éviter FOR loop null ═══
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
END
$function$;

-- ═══ 2. FIX _ludo_ensure_state: vérifier g.id IS NULL ═══
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id UUID) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
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
END $$;

-- ═══ 3. FIX ludo_set_ready: pas de phone_verified pour solo/bot ═══
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  
  -- Phone verification only for multiplayer (non-solo) games with stakes
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

-- ═══ 4. FIX _ludo_movable_pawns: COALESCE et guards ═══
CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot INT, _dice INT)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE
AS $$
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
END $$;

-- ═══ 5. FIX ludo_roll: guard g.id IS NULL + utiliser la dernière version ═══
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

  -- Roll the dice
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

  -- Track consecutive sixes
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

  -- Set dice + must_move
  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  st := jsonb_set(st, '{turn_started_at}',
    to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));
  st := st - 'no_move_display';

  -- Compute movable pawns
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);

  -- Handle no-move case
  IF jsonb_array_length(v_movable) = 0 THEN
    IF v_isbot THEN
      -- Bot: auto-advance turn immediately
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
      -- Human: keep dice visible, frontend shows "PAS DE COUP" then calls ludo_pass
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
      RETURN st;
    END IF;
  ELSE
    -- Move available: save and return
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_roll(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_roll(uuid) TO authenticated;

-- ═══ 6. FIX ludo_check_timeout: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) TO authenticated;

-- ═══ 7. FIX ludo_bot_play: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;

-- ═══ 8. FIX ludo_move: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_move(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_move(uuid, integer) TO authenticated;

-- ═══ 9. FIX ludo_pass: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_pass(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_pass(uuid) TO authenticated;

-- ═══ 10. FIX ludo_start_solo_bot: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) TO authenticated;

-- ═══ 11. FIX ludo_quit: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_quit(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_quit(uuid) TO authenticated;

-- ═══ 12. FIX ludo_pause: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_pause(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_pause(uuid) TO authenticated;

-- ═══ 13. FIX ludo_choose_power: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_choose_power(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_choose_power(uuid, text) TO authenticated;

-- ═══ 14. FIX ludo_join_team: ensure permissions ═══
REVOKE EXECUTE ON FUNCTION public.ludo_join_team(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_join_team(uuid, integer) TO authenticated;
