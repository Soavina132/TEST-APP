-- ============================================================
-- FIX: Refonte de la logique du dé Ludo (comme les vraies apps)
-- 
-- Changements:
-- 1. Dé équitable: suppression du bot_win_bias qui forçait des 6
-- 2. Auto-pass automatique pour tous (humains ET bots) quand aucun coup possible
-- 3. Triple six = tour annulé (règle standard)
-- 4. Re-roll sur 6, capture, pion arrivé (déjà géré dans ludo_move)
-- 5. Admin override conservé pour le débogage
-- 6. État "no_move" visible pour le frontend
-- ============================================================

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
  v_override INT;
  v_new_slot INT;
  v_movable jsonb;
  v_dice INT;
  v_now text;
BEGIN
  -- ── 1. Verrous & validations ──
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT user_id, is_bot, consecutive_sixes
    INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  -- Vérifier que c'est bien le tour du joueur
  IF NOT v_isbot AND v_user <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;

  -- Ne pas relancer si déjà lancé
  IF (st->>'must_move')::BOOLEAN THEN
    RAISE EXCEPTION 'Déjà lancé, déplacez un pion';
  END IF;

  -- ── 2. Lancer du dé ──
  -- Admin override (débogage/test uniquement)
  v_override := NULLIF(g.dice_override->>v_slot::text, '')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    -- RNG équitable: 1-6, aucune triche
    v_dice := 1 + (floor(random() * 6))::INT;
  END IF;

  -- ── 3. Gestion des six consécutifs ──
  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

  -- Triple six → annulation du tour (règle standard Ludo)
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
    st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
    st := jsonb_set(st, '{no_move_display}', 'true'::jsonb);
    st := st - 'movable_pawns';
    
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_now := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
    st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
    st := jsonb_set(st, '{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    
    UPDATE public.ludo_games
      SET state = st, current_turn = (st->>'turn_slot')::INT
      WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  -- ── 4. Enregistrer le résultat du dé ──
  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  v_now := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));
  st := st - 'no_move_display';

  -- ── 5. Calculer les pions jouables ──
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);

  -- ── 6. Aucun coup possible ──
  IF jsonb_array_length(v_movable) = 0 THEN
    -- Auto-pass pour TOUT LE MONDE (humains ET bots)
    -- Comme dans les vraies apps: on affiche le dé puis on passe
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{no_move_display}', 'true'::jsonb);
    st := jsonb_set(st, '{last_event}',
      to_jsonb('roll:' || v_dice || ':no_move'));
    st := st - 'movable_pawns';
    
    -- Réinitialiser les six consécutifs si pas un 6
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
    END IF;
    
    -- Consommer double_roll_pending si présent
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    
    -- Passer au joueur suivant
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_now := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
    st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
    st := jsonb_set(st, '{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    
    UPDATE public.ludo_games
      SET state = st, current_turn = (st->>'turn_slot')::INT
      WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  -- ── 7. Un ou plusieurs coups possibles ──
  UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  RETURN st;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_roll(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_roll(uuid) TO authenticated;
