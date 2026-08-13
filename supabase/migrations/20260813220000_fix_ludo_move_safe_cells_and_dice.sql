-- ============================================================
-- FIX: ludo_move v_path_idx overwrite bug + safe cells mismatch
--
-- Bug 1: v_path_idx ecrase dans la boucle interne
--   La variable v_path_idx est utilisee pour (a) verifier si la cellule
--   d'arrivee est safe, et (b) calculer la position du pion cible.
--   Dans la boucle externe, apres la 1ere iteration, v_path_idx contient
--   la position du pion cible precedent, pas la position d'arrivee.
--   Le is_safe() check est donc FAUX pour les slots 2+.
--
-- Bug 2: Frontend a 8 safe cells, backend n'en a que 4
--   Frontend: [0, 8, 13, 21, 26, 34, 39, 47]
--   Backend:  [0, 13, 26, 39]  (manque les etoiles)
--   => captures possibles sur des cells "safe" cote frontend
--
-- Bug 3: bot_win_bias encore present dans ludo_roll (DB)
--   La migration 20260813140000 n'a pas ete appliquee
-- ============================================================

-- Fix 1: _ludo_is_safe - ajouter les 4 etoiles manquantes
CREATE OR REPLACE FUNCTION public._ludo_is_safe(_idx integer)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT _idx IN (0, 8, 13, 21, 26, 34, 39, 47)
$function$;

-- Fix 2: ludo_move - variable separee pour le path_idx du pion qui bouge
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
  v_moving_path_idx INT;  -- FIX: variable dediee pour la position d'arrivee
  v_target_path_idx INT;  -- FIX: variable dediee pour la position cible
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
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
  -- FIX: calculer UNE FOIS la position d'arrivee et la stocker separement
  IF new_state = 'track' AND new_k <= 50 THEN
    v_moving_path_idx := (public._ludo_start_idx(v_slot) + new_k - 1) % 52;
    IF NOT public._ludo_is_safe(v_moving_path_idx) THEN
      FOR v_target_slot IN 0..3 LOOP
        IF v_target_slot = v_slot THEN CONTINUE; END IF;
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

-- Fix 3: ludo_roll - supprimer bot_win_bias (RNG equitable)
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

  -- Dice roll: admin override for debugging, otherwise fair RNG
  v_override := NULLIF(g.dice_override->>v_slot::text, '')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    v_dice := 1 + (floor(random() * 6))::INT;
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

  -- Triple six -> cancel turn
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
END;
$function$;
