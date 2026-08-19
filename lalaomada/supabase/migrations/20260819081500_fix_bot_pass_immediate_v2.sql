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
  v_new_slot INT;
  v_now text;
  v_consec INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence, consecutive_sixes INTO v_isbot, v_intel, v_consec
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

  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');

  IF array_length(candidates,1) IS NULL THEN
    -- ═══ NO MOVE : passer le tour IMMÉDIATEMENT ═══
    -- Avant, on mettait must_move=true et on attendait ludo_tick_all → ludo_bot_move
    -- ce qui prenait 5-10s. Maintenant on passe tout de suite.
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
    END IF;
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{dice}', 'null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'::text));
    st := st - 'movable_pawns';
    st := st - 'no_move_display';
    -- Clean up power mode state
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    UPDATE public.ludo_games SET state=st, current_turn=v_new_slot WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  -- Le bot a un coup : sauvegarder le roll et laisser ludo_bot_move jouer
  st := jsonb_set(st,'{dice}', 'null'::jsonb);
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(v_now));
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);
  st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  RETURN st;
END $function$;
