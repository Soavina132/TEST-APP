-- ============================================================
-- MIGRATION GLOBALE: Améliorations backend Ludo
--
-- 1. Block/Barrière (2 pions same-color = capture impossible)
-- 2. Table ludo_move_history (historique complet)
-- 3. Détection stalemate (match nul après N tours sans move)
-- 4. Cron plus rapide (3s au lieu de 5s)
-- 5. Bot delay server-side dans ludo_tick_all
-- 6. max_players dans le state pour block checks
-- ============================================================

-- ═══ 1. BLOCK / BARRIÈRE ═══

CREATE OR REPLACE FUNCTION public._ludo_count_on_cell(st jsonb, _slot integer, _path_idx integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT count(*)::int
  FROM jsonb_array_elements(st->'pawns'->_slot::text) AS p
  WHERE p.value->>'s' = 'track'
    AND (public._ludo_start_idx(_slot) + (p.value->>'k')::int - 1) % 52 = _path_idx
$function$;

CREATE OR REPLACE FUNCTION public._ludo_is_blocked(st jsonb, _moving_slot integer, _path_idx integer, _max_players integer DEFAULT 4)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_slot INT;
  v_count INT;
BEGIN
  FOR v_slot IN 0..3 LOOP
    IF v_slot = _moving_slot THEN CONTINUE; END IF;
    IF v_slot >= _max_players THEN CONTINUE; END IF;
    IF st->'pawns' ? v_slot::text THEN
      v_count := public._ludo_count_on_cell(st, v_slot, _path_idx);
      IF v_count >= 2 THEN
        RETURN TRUE;
      END IF;
    END IF;
  END LOOP;
  RETURN FALSE;
END;
$function$;

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
BEGIN
  IF _dice IS NULL OR _dice < 1 OR _dice > 6 THEN RETURN '[]'::jsonb; END IF;
  IF _slot IS NULL THEN RETURN '[]'::jsonb; END IF;
  arr := st->'pawns'->_slot::text;
  IF arr IS NULL OR arr = 'null'::jsonb THEN RETURN '[]'::jsonb; END IF;
  v_max_players := COALESCE((st->>'max_players')::int, 4);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN
        v_path_idx := public._ludo_start_idx(_slot);
        IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
          result := result || to_jsonb(i);
        END IF;
      END IF;
    ELSIF pstate = 'track' THEN
      v_new_k := pstep + _dice;
      IF v_new_k <= 56 THEN
        IF v_new_k <= 50 THEN
          v_path_idx := (public._ludo_start_idx(_slot) + v_new_k - 1) % 52;
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

-- ═══ 2. TABLE ludo_move_history ═══
CREATE TABLE IF NOT EXISTS public.ludo_move_history (
  id BIGSERIAL PRIMARY KEY,
  game_id UUID NOT NULL REFERENCES public.ludo_games(id) ON DELETE CASCADE,
  slot INT NOT NULL,
  action TEXT NOT NULL,
  dice INT,
  pawn_idx INT,
  from_state JSONB,
  to_state JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ludo_move_history_game ON public.ludo_move_history(game_id, created_at);

-- ═══ 3. DÉTECTION STALEMATE ═══
CREATE OR REPLACE FUNCTION public._ludo_check_stalemate(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  st jsonb;
  v_streak INT;
  v_max_players INT;
  v_best_slot INT := 0;
  v_best_progress INT := 0;
  v_progress INT;
  v_i INT;
  v_j INT;
  v_pawns jsonb;
  v_pawn jsonb;
  v_uid UUID;
BEGIN
  SELECT state INTO st FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF st IS NULL THEN RETURN FALSE; END IF;

  v_streak := COALESCE((st->>'no_move_streak')::int, 0);
  v_max_players := COALESCE((st->>'max_players')::int, 4);

  IF v_streak >= 10 * v_max_players THEN
    FOR v_i IN 0..3 LOOP
      IF v_i >= v_max_players THEN EXIT; END IF;
      v_pawns := st->'pawns'->v_i::text;
      IF v_pawns IS NULL THEN CONTINUE; END IF;
      v_progress := 0;
      FOR v_j IN 0..3 LOOP
        v_pawn := v_pawns->v_j;
        IF v_pawn IS NULL THEN CONTINUE; END IF;
        IF v_pawn->>'s' = 'finished' THEN
          v_progress := v_progress + 56;
        ELSIF v_pawn->>'s' = 'track' THEN
          v_progress := v_progress + COALESCE((v_pawn->>'k')::int, 0);
        END IF;
      END LOOP;
      IF v_progress > v_best_progress THEN
        v_best_progress := v_progress;
        v_best_slot := v_i;
      END IF;
    END LOOP;

    SELECT user_id INTO v_uid FROM public.ludo_participants
      WHERE game_id = _game_id AND slot = v_best_slot AND is_bot = FALSE AND forfeited = FALSE
      LIMIT 1;

    IF v_uid IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_uid);
    ELSE
      UPDATE public.ludo_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$function$;

-- ═══ 4. CRON PLUS RAPIDE ═══
SELECT cron.alter_job(job_id := 51, schedule := '3 seconds');

-- ═══ 5. LUDO_TICK_ALL AMÉLIORÉ ═══
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
  st JSONB;
  v_turn_started TIMESTAMPTZ;
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
        v_turn_started := (st->>'turn_started_at')::timestamptz;
        -- Délai naturel: attendre 1.5s minimum après le début du tour
        IF now() - v_turn_started >= interval '1.5 seconds' THEN
          PERFORM public.ludo_bot_play(g_id);
          SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
          IF st IS NOT NULL AND (st->>'must_move')::BOOLEAN = false
             AND (st->>'turn_slot')::INT = v_slot THEN
            PERFORM pg_sleep(0.5);
            PERFORM public.ludo_bot_play(g_id);
          END IF;
        END IF;
      END IF;

      PERFORM public._ludo_check_stalemate(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$;

-- ═══ LUDO_CHECK_TIMEOUT avec stalemate + turn_seconds configurable ═══
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_started TIMESTAMPTZ;
  v_uid UUID;
  v_isbot BOOLEAN;
  v_missed INT;
  v_winner UUID;
  v_turn_seconds INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;

  SELECT turn_seconds INTO v_turn_seconds FROM public.app_settings WHERE id = 1;
  v_turn_seconds := COALESCE(v_turn_seconds, 30);

  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < (v_turn_seconds || ' seconds')::interval THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;

  UPDATE public.ludo_participants SET consecutive_sixes=0
    WHERE game_id=_game_id AND slot=v_slot;

  st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));

  IF v_missed >= 3 AND NOT v_isbot THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Forfait (3 timeouts)');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    ELSE
      UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN st;
  END IF;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := public._ludo_clear_shield(st, public._ludo_next_slot(_game_id, v_slot, g.max_players));
  st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ═══ LUDO_MOVE avec block mechanic + stalemate reset ═══
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_user UUID;
  v_isbot BOOLEAN;
  arr jsonb;
  pawn jsonb;
  new_k INT;
  new_state TEXT;
  v_dice INT;
  v_new_slot INT;
  v_consec INT;
  captured BOOLEAN := FALSE;
  v_arr_idx INT;
  v_target_slot INT;
  v_target_pawn jsonb;
  v_step INT;
  v_moving_path_idx INT;
  v_target_path_idx INT;
  v_movable jsonb;
  v_target_count INT;
  v_max_players INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  v_max_players := g.max_players;
  SELECT user_id, is_bot, consecutive_sixes INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  IF NOT (v_movable @> to_jsonb(_pawn_idx)) THEN
    RAISE EXCEPTION 'Pion non jouable';
  END IF;
  arr := st->'pawns'->v_slot::text;
  pawn := arr->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  IF pawn->>'s' = 'finished' THEN RAISE EXCEPTION 'Pion deja arrive'; END IF;
  IF pawn->>'s' = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track';
    new_k := 1;
  ELSE
    new_k := (pawn->>'k')::INT + v_dice;
    IF new_k > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_k = 56 THEN
      new_state := 'finished';
    ELSE
      new_state := 'track';
    END IF;
  END IF;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_k));
  st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_slot::text], arr));

  IF new_state = 'track' AND new_k <= 50 THEN
    v_moving_path_idx := (public._ludo_start_idx(v_slot) + new_k - 1) % 52;
    IF NOT public._ludo_is_safe(v_moving_path_idx) THEN
      FOR v_target_slot IN 0..3 LOOP
        IF v_target_slot = v_slot THEN CONTINUE; END IF;
        IF v_target_slot >= v_max_players THEN CONTINUE; END IF;
        IF st->'shields' ? v_target_slot::text AND (st->'shields'->>v_target_slot::text)::BOOLEAN THEN
          CONTINUE;
        END IF;
        arr := st->'pawns'->v_target_slot::text;
        IF arr IS NULL THEN CONTINUE; END IF;
        FOR v_arr_idx IN 0..3 LOOP
          v_target_pawn := arr->v_arr_idx;
          IF v_target_pawn IS NULL THEN CONTINUE; END IF;
          IF v_target_pawn->>'s' = 'track' THEN
            v_step := (v_target_pawn->>'k')::INT;
            IF v_step <= 50 THEN
              v_target_path_idx := (public._ludo_start_idx(v_target_slot) + v_step - 1) % 52;
              IF v_moving_path_idx = v_target_path_idx THEN
                v_target_count := public._ludo_count_on_cell(st, v_target_slot, v_target_path_idx);
                IF v_target_count >= 2 THEN
                  CONTINUE;
                END IF;
                arr := jsonb_set(arr, ARRAY[v_arr_idx::text], jsonb_build_object('s', 'yard', 'k', 0));
                st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_target_slot::text], arr));
                captured := TRUE;
              END IF;
            END IF;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END IF;

  st := jsonb_set(st, '{no_move_streak}', '0'::jsonb);
  st := st - 'movable_pawns';
  IF v_dice = 6 OR captured OR new_state = 'finished' THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb(CASE
      WHEN captured AND new_state = 'finished' THEN 'capture:home'
      WHEN captured THEN 'capture'
      WHEN new_state = 'finished' THEN 'home'
      ELSE 'six'
    END));
  ELSE
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
  END IF;
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ═══ LUDO_ROLL avec max_players dans state + stalemate counter ═══
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

  IF NOT (st ? 'max_players') THEN
    st := jsonb_set(st, '{max_players}', to_jsonb(g.max_players));
  END IF;

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

  v_override := NULLIF(g.dice_override->>v_slot::text, '')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    v_dice := 1 + (floor(random() * 6))::INT;
  END IF;

  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

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
    st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
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
      st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
      UPDATE public.ludo_games
        SET state = st, current_turn = (st->>'turn_slot')::INT
        WHERE id = _game_id;
      PERFORM public._ludo_check_game_over(_game_id);
      RETURN st;
    ELSE
      st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
      RETURN st;
    END IF;
  ELSE
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;
END;
$function$;

-- ═══ LUDO_PASS avec stalemate counter ═══
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_dice INT;
  v_uid UUID := auth.uid();
  v_user UUID;
  v_isbot BOOLEAN;
  arr jsonb;
  pawn jsonb;
  i INT;
  pstate TEXT;
  pstep INT;
  has_move BOOLEAN := FALSE;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSIF pstate='track' THEN
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
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'::text));
  st := st - 'no_move_display' - 'power_event' - 'movable_pawns';
  st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ═══ _LUDO_INIT_STATE avec no_move_streak et max_players ═══
CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players integer)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  st jsonb;
  i INT;
  v_pawns jsonb;
BEGIN
  st := jsonb_build_object(
    'turn_slot', 0,
    'dice', 'null'::jsonb,
    'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'last_event', 'init',
    'no_move_streak', 0,
    'max_players', _max_players,
    'pawns', '{}'::jsonb
  );
  FOR i IN 0..(_max_players - 1) LOOP
    v_pawns := '[]'::jsonb;
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    st := jsonb_set(st, ARRAY['pawns', i::text], v_pawns);
  END LOOP;
  RETURN st;
END;
$function$;
