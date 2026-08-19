-- ═════════════════════════════════════════════════════════════════════════════
-- FIX: Créer la fonction ludo_bot_move manquante
--
-- Problème :
-- - ludo_bot_play (depuis 20260819100000) ne fait que lancer le dé
--   (must_move=true, dice=X). Elle ne déplace PLUS le pion.
-- - ludo_tick_all ET le frontend (RealtimeLudoBoard.tsx) appellent
--   ludo_bot_move pour le déplacement, mais cette fonction N'EXISTAIT PAS.
-- - Le bot restait bloqué : il lance le dé mais ne joue jamais son coup.
-- - Avant, ludo_bot_play faisait roll+move en une seule opération (déplacement
--   simultané). Maintenant les deux phases sont séparées :
--     Phase 1 : ludo_bot_play → lance le dé
--     (délai 2-4s via ludo_tick_all / 3s via frontend)
--     Phase 2 : ludo_bot_move  → choisit le meilleur pion + ludo_move
--
-- Solution :
-- Créer ludo_bot_move qui :
-- 1. Vérifie que c'est un bot avec must_move=true
-- 2. Calcule les pions jouables via _ludo_movable_pawns
-- 3. Si aucun coup possible → passe le tour (comme ludo_pass)
-- 4. Si coup possible → choisit le meilleur pion (intelligence) + appelle ludo_move
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_bot_move(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_isbot BOOLEAN;
  v_intel INT;
  v_dice INT;
  v_movable jsonb;
  v_count INT;
  arr jsonb;
  pawn jsonb;
  i INT;
  k INT;
  best INT := -1;
  best_score INT := -1;
  sc INT;
  pstate TEXT;
  pstep INT;
  abs_cell INT;
  start_idx INT;
  other_slot INT;
  op jsonb;
  op_step INT;
  op_start INT;
  would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN NULL; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT is_bot, bot_intelligence INTO v_isbot, v_intel
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RETURN st; END IF;

  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RETURN st; END IF;

  -- Calculer les pions jouables (même logique que ludo_roll / ludo_pass)
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  v_count := jsonb_array_length(COALESCE(v_movable, '[]'::jsonb));

  -- ═══ Aucun coup possible : passer le tour ═══
  IF v_count = 0 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;

    -- Nettoyer power mode
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;

    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot:pass'));
    st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;

    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  -- ═══ Construire la liste des candidats ═══
  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_idx(v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := (pawn->>'k')::INT;
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates, 1) IS NULL THEN
    -- Sécurité : ne devrait pas arriver car v_count > 0, mais au cas où
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot:pass'));
    st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  -- ═══ Choisir le meilleur pion (intelligence du bot) ═══
  -- L'intelligence ne concerne QUE le choix du pion, JAMAIS le dé
  IF (random() * 100) < COALESCE(v_intel, 70) THEN
    -- Mode intelligent : évaluer chaque candidat
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := (pawn->>'k')::INT;

      IF pstate = 'yard' THEN
        sc := 60;  -- Sortir un pion du yard est bien
      ELSIF pstep + v_dice = 56 THEN
        sc := 80;  -- Finir un pion est encore mieux
      ELSE
        -- Vérifier si on capture un pion adverse
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR other_slot IN 0..g.max_players - 1 LOOP
              IF other_slot <> v_slot THEN
                op_start := public._ludo_start_idx(other_slot);
                FOR k IN 0..3 LOOP
                  op := st->'pawns'->other_slot::text->k;
                  IF op->>'s' = 'track' THEN
                    op_step := (op->>'k')::INT;
                    IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                      would_capture := TRUE;
                    END IF;
                  END IF;
                END LOOP;
              END IF;
            END LOOP;
          END IF;
        END IF;
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;

      IF sc > best_score THEN
        best_score := sc;
        best := i;
      END IF;
    END LOOP;
  ELSE
    -- Mode aléatoire : choisir un pion au hasard
    best := candidates[1 + (floor(random() * array_length(candidates, 1)))::INT];
  END IF;

  -- ═══ Déplacer le pion via ludo_move ═══
  RETURN public.ludo_move(_game_id, best);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.ludo_bot_move(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_bot_move(uuid) TO authenticated;
