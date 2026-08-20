-- ═════════════════════════════════════════════════════════════════
-- FIX: ludo_check_timeout saute un joueur quand no_move_display
-- est présent mais le tour a déjà été passé par ludo_roll auto-pass.
--
-- ludo_roll auto-passe maintenant le tour quand aucun pion n'est
-- jouable, mais garde no_move_display dans le state pour le visuel.
-- ludo_check_timeout voyait no_move_display et passait le tour
-- ENCORE → le joueur suivant était sauté.
--
-- Solution: si no_move_display.slot !== turn_slot, le tour a déjà
-- été passé → on nettoie no_move_display et on continue vers le
-- check de timeout normal.
-- ═════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_started TIMESTAMPTZ;
  v_uid UUID;
  v_isbot BOOLEAN;
  v_turn_seconds INT;
  v_new_slot INT;
  v_missed INT;
  v_no_move_until TIMESTAMPTZ;
  v_dice INT;
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;

  -- Skip if game is paused
  IF COALESCE(g.paused, false) THEN RETURN st; END IF;

  SELECT turn_seconds INTO v_turn_seconds FROM public.app_settings WHERE id = 1;
  v_turn_seconds := COALESCE(v_turn_seconds, 30);

  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  v_slot := (st->>'turn_slot')::INT;

  -- ── NO_MOVE_DISPLAY handling ──
  IF st ? 'no_move_display' THEN
    BEGIN
      -- Si le tour a déjà été passé par ludo_roll (auto-pass),
      -- no_move_display.slot !== turn_slot → nettoyer et continuer
      IF (st->'no_move_display'->>'slot')::INT <> v_slot THEN
        st := st - 'no_move_display';
        UPDATE public.ludo_games SET state = st WHERE id = _game_id;
        -- Fall through vers le check de timeout normal
      ELSE
        -- Ancien comportement: auto-pass après le délai d'affichage
        -- (pour compatibilité si ludo_roll n'a pas auto-passé)
        v_no_move_until := (st->'no_move_display'->>'until')::TIMESTAMPTZ;
        IF now() >= v_no_move_until THEN
          v_dice := (st->>'dice')::INT;
          UPDATE public.ludo_participants SET consecutive_sixes = 0
            WHERE game_id = _game_id AND slot = v_slot;
          IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
            st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
          END IF;
          st := jsonb_set(st, '{must_move}', 'false'::jsonb);
          st := jsonb_set(st, '{dice}', 'null'::jsonb);
          v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
          st := public._ludo_clear_shield(st, v_new_slot);
          st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
          st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
          st := jsonb_set(st, '{last_event}', to_jsonb('pass'::text));
          st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
          UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
          PERFORM public._ludo_check_game_over(_game_id);
          RETURN st;
        ELSE
          RETURN st;
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  IF now() - v_started < (v_turn_seconds || ' seconds')::interval THEN RETURN st; END IF;

  -- Get current player info
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants
    WHERE game_id=_game_id AND slot=v_slot AND NOT forfeited;

  -- If current player forfeited or not found, advance turn
  IF NOT FOUND THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('skip_forfeit'::text));
    st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  -- Skip bots — they're auto-played by ludo_tick_all
  IF v_isbot THEN RETURN st; END IF;

  -- Try auto_move if enabled before counting T2
  IF COALESCE((st->>'must_move')::boolean, false) AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;

  -- Increment T1 or T2
  IF NOT COALESCE((st->>'must_move')::boolean, false) THEN
    UPDATE public.ludo_participants
      SET afk_t1 = COALESCE(afk_t1, 0) + 1, consecutive_sixes = 0
      WHERE game_id=_game_id AND slot=v_slot;
  ELSE
    UPDATE public.ludo_participants
      SET afk_t2 = COALESCE(afk_t2, 0) + 1, consecutive_sixes = 0
      WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  -- Clear double_roll_pending if applicable
  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  -- Advance turn
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := public._ludo_decrement_cooldowns(st);
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display' - 'movable_pawns' - 'power_event';

  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  -- Check AFK thresholds (T1/T2 → warning or forfeit)
  PERFORM public._ludo_check_afk(_game_id, v_slot);

  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

REVOKE ALL ON FUNCTION public.ludo_check_timeout(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_check_timeout(uuid) TO authenticated;
