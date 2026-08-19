-- ═════════════════════════════════════════════════════════════════════════════
-- FIX: "PAS DE COUP" reste bloqué sur le jeu Ludo
--
-- Causes :
-- 1. ludo_roll passe le tour IMMÉDIATEMENT sur no_move (must_move=false,
--    dice=null, turn_slot=next). Le frontend ne voit jamais l'état
--    must_move=true + dice + movable_pawns=[] qu'il attend pour afficher
--    "PAS DE COUP" puis appeler ludo_pass après 1.5s.
-- 2. ludo_bot_play fait DEUX UPDATEs : le premier (must_move=true, dice=X)
--    déclenche le frontend qui affiche "PAS DE COUP", le second (must_move=false,
--    turn passé) devrait le nettoyer, mais les events realtime peuvent se
--    perdre/coalescer → "PAS DE COUP" reste bloqué.
--
-- Solution :
-- - ludo_roll : sur no_move, GARDER must_move=true, dice=X, movable_pawns=[].
--   Ne PAS passer le tour. Le frontend détecte noMove, affiche "PAS DE COUP"
--   1.5s, puis appelle ludo_pass qui passe le tour.
-- - ludo_bot_play : sur no_move, faire UN SEUL UPDATE avec must_move=true,
--   dice=X, movable_pawns=[]. Ne PAS passer le tour. ludo_tick_all détectera
--   must_move=true et appelera ludo_bot_move (qui passe le tour si pas de
--   candidats), ou le frontend appellera ludo_pass (1.5s).
-- ═════════════════════════════════════════════════════════════════════════════

-- ═══ 1. ludo_roll : ne plus passer le tour sur no_move ═══
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
  v_consec INT;
  v_movable jsonb;
  v_dice INT;
  v_now text;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT user_id, is_bot, consecutive_sixes
    INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot AND v_user <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;
  IF (st->>'must_move')::BOOLEAN THEN
    RAISE EXCEPTION 'Déjà lancé, déplacez un pion';
  END IF;

  -- Dé équitable: 1-6
  v_dice := 1 + (floor(random() * 6))::INT;

  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

  -- Triple six → annulation du tour
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
    st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
    st := jsonb_set(st, '{no_move_display}', 'true'::jsonb);
    st := st - 'movable_pawns';
    -- Passer le tour sur triple six (comportement spécial, pas un no_move normal)
    DECLARE v_new_slot_ts INT; v_now_ts text;
    BEGIN
      v_new_slot_ts := public._ludo_next_slot(_game_id, v_slot, g.max_players);
      st := public._ludo_clear_shield(st, v_new_slot_ts);
      st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot_ts));
      st := jsonb_set(st, '{dice}', 'null'::jsonb);
      v_now_ts := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
      st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now_ts));
      st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
      st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now_ts));
      st := jsonb_set(st, '{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
      IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
        st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
      END IF;
      UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
      PERFORM public._ludo_check_game_over(_game_id);
      RETURN st;
    END;
  END IF;

  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  v_now := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));
  st := st - 'no_move_display';

  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);

  IF jsonb_array_length(v_movable) = 0 THEN
    -- ═══ NO MOVE : garder must_move=true, dice=X, movable_pawns=[] ═══
    -- Le frontend détectera noMove, affichera "PAS DE COUP" 1.5s,
    -- puis appellera ludo_pass qui passe le tour.
    st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice || ':no_move'));
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
    END IF;
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    -- NE PAS passer le tour. Laisser must_move=true, dice=X, movable_pawns=[].
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;

  UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  RETURN st;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_roll(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_roll(uuid) TO authenticated;

-- ═══ 2. ludo_bot_play : un seul UPDATE sur no_move ═══
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  other_slot INT; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence INTO v_isbot, v_intel
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF (st->>'must_move')::BOOLEAN THEN
    -- Déjà lancé, rien à faire (ludo_bot_move gère le déplacement)
    RETURN st;
  END IF;

  -- Dé équitable
  v_dice := 1 + (floor(random()*6))::INT;

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

  -- Set dice + must_move dans tous les cas
  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));

  IF array_length(candidates,1) IS NULL THEN
    -- ═══ NO MOVE : un seul UPDATE, garder must_move=true ═══
    -- ludo_tick_all → ludo_bot_move gèrera le pass, ou le frontend
    -- appellera ludo_pass après 1.5s.
    v_movable := '[]'::jsonb;
    st := jsonb_set(st, '{movable_pawns}', v_movable);
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice||':no_move'));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
    RETURN st;
  END IF;

  -- Le bot a un coup : sauvegarder le roll et laisser ludo_bot_move jouer
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);
  st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  RETURN st;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;
