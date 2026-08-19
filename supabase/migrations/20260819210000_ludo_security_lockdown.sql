-- SECURITY LOCKDOWN: Ludo — suppression des failles de triche
-- 1. dice_override: n'importe quel participant peut FORCER les des
-- 2. RLS UPDATE trop permissive sur ludo_games (modification directe de state)
-- 3. RLS UPDATE trop permissive sur ludo_participants

-- 1. ludo_roll SANS dice_override
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
  v_consec INT;
  v_dice INT;
  v_movable jsonb;
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
    RAISE EXCEPTION 'Deja lance, deplacez un pion';
  END IF;

  -- De equitable: 1-6, AUCUN override
  v_dice := 1 + (floor(random() * 6))::INT;

  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

  -- Triple six -> annulation
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'movable_pawns';
    DECLARE v_new_slot_ts INT; v_now_ts text;
    BEGIN
      v_new_slot_ts := public._ludo_next_slot(_game_id, v_slot, g.max_players);
      st := public._ludo_clear_shield(st, v_new_slot_ts);
      st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot_ts));
      st := jsonb_set(st, '{dice}', 'null'::jsonb);
      v_now_ts := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
      st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now_ts));
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
    st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice || ':no_move'));
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
    END IF;
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;

  UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  RETURN st;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_roll(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_roll(uuid) TO authenticated;

-- 2. Dropper dice_override
ALTER TABLE public.ludo_games DROP COLUMN IF EXISTS dice_override;

-- 3. Trigger anti-modification directe de state sur ludo_games
CREATE OR REPLACE FUNCTION public._ludo_protect_state()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  IF current_setting('role', true) = 'authenticated' THEN
    IF NEW.state IS DISTINCT FROM OLD.state THEN
      RAISE EXCEPTION 'Modification directe de l etat du jeu interdite';
    END IF;
    IF NEW.current_turn IS DISTINCT FROM OLD.current_turn THEN
      RAISE EXCEPTION 'Modification directe du tour interdite';
    END IF;
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_ludo_protect_state ON public.ludo_games;
CREATE TRIGGER trg_ludo_protect_state
  BEFORE UPDATE ON public.ludo_games
  FOR EACH ROW
  EXECUTE FUNCTION public._ludo_protect_state();

-- 4. Trigger anti-modification colonnes sensibles sur ludo_participants
CREATE OR REPLACE FUNCTION public._ludo_protect_participants()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  IF current_setting('role', true) = 'authenticated' THEN
    IF NEW.forfeited IS DISTINCT FROM OLD.forfeited THEN
      RAISE EXCEPTION 'Modification de forfeited interdite';
    END IF;
    IF NEW.consecutive_sixes IS DISTINCT FROM OLD.consecutive_sixes THEN
      RAISE EXCEPTION 'Modification de consecutive_sixes interdite';
    END IF;
    IF NEW.missed_turns IS DISTINCT FROM OLD.missed_turns THEN
      RAISE EXCEPTION 'Modification de missed_turns interdite';
    END IF;
    IF NEW.is_bot IS DISTINCT FROM OLD.is_bot THEN
      RAISE EXCEPTION 'Modification de is_bot interdite';
    END IF;
    IF NEW.bot_intelligence IS DISTINCT FROM OLD.bot_intelligence THEN
      RAISE EXCEPTION 'Modification de bot_intelligence interdite';
    END IF;
    IF NEW.slot IS DISTINCT FROM OLD.slot THEN
      RAISE EXCEPTION 'Modification de slot interdite';
    END IF;
    IF NEW.color IS DISTINCT FROM OLD.color THEN
      RAISE EXCEPTION 'Modification de color interdite';
    END IF;
    IF NEW.team IS DISTINCT FROM OLD.team THEN
      RAISE EXCEPTION 'Modification de team interdite';
    END IF;
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS trg_ludo_protect_participants ON public.ludo_participants;
CREATE TRIGGER trg_ludo_protect_participants
  BEFORE UPDATE ON public.ludo_participants
  FOR EACH ROW
  EXECUTE FUNCTION public._ludo_protect_participants();

-- 5. bot_win_bias a 0
UPDATE public.ludo_participants SET bot_win_bias = 0 WHERE bot_win_bias IS NOT NULL AND bot_win_bias <> 0;

-- 6. Revoquer SELECT sur bot_win_bias
REVOKE SELECT (bot_win_bias) ON public.ludo_participants FROM anon, authenticated;
