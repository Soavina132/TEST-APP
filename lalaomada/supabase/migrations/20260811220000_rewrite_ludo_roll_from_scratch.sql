-- ════════════════════════════════════════════════════════════════════
-- REWRITE: ludo_roll from scratch
-- Design nouveau: le dé est TOUJOURS dans l'état (always visible)
--   - must_move=true + dice=value + movable_pawns=[...] TOUJOURS
--   - Bot sans coup → serveur avance le tour immédiatement
--   - Humain sans coup → frontend voit movable_pawns=[], affiche
--     "PAS DE COUP" 1.5s puis appelle ludo_pass lui-même
--   - Supprime no_move_display (fragile, basé sur timestamp)
-- ════════════════════════════════════════════════════════════════════

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
  -- ── 1. Lock & validate ──────────────────────────────────────────
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN
    RAISE EXCEPTION 'Partie pas en cours';
  END IF;

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

  -- ── 2. Roll the dice ────────────────────────────────────────────
  v_override := NULLIF(g.dice_override->>v_slot::text, '')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    v_dice := 1 + (floor(random() * 6))::INT;
    -- Bot win bias: force a 6 with probability = bias%
    IF v_isbot AND COALESCE(v_bias, 0) > 0 AND (random() * 100) < v_bias THEN
      v_dice := 6;
    END IF;
  END IF;

  -- ── 3. Track consecutive sixes ─────────────────────────────────
  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

  -- ── 4. Triple six → cancel turn ────────────────────────────────
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

  -- ── 5. Set dice + must_move (ALWAYS, regardless of move availability)
  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  st := jsonb_set(st, '{turn_started_at}',
    to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));
  st := st - 'no_move_display';

  -- ── 6. Compute movable pawns ───────────────────────────────────
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);

  -- ── 7. Handle no-move case ─────────────────────────────────────
  IF jsonb_array_length(v_movable) = 0 THEN
    -- No move available
    IF v_isbot THEN
      -- Bot: auto-advance turn immediately (server-side)
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
      -- Human: keep dice visible in state.
      -- Frontend sees movable_pawns=[] → shows "PAS DE COUP" 1.5s
      -- then calls ludo_pass to advance the turn.
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
      RETURN st;
    END IF;
  ELSE
    -- Move available: save and return
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;
END $function$;
