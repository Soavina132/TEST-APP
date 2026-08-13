-- ============================================================
-- SUPPRESSION COMPLÈTE DE TOUTES LES TRACES DE TRICHE
-- 
-- 1. ludo_roll: suppression de dice_override (admin peut forcer les dés)
-- 2. ludo_bot_play: suppression du bot_win_bias (force des 6)
-- 3. ludo_start_solo_bot: bot_win_bias toujours à 0
-- 4. admin_add_bot: suppression du paramètre _win_bias
-- 5. admin_update_bot: suppression du paramètre _win_bias
-- 6. admin_get_bot_config: ne retourne plus win_bias
-- 7. Nettoyage des données existantes
-- ============================================================

-- ── 1. ludo_roll SANS dice_override ──
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
  v_new_slot INT;
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

  -- Dé équitable: 1-6, aucune triche, aucun override
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
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
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
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{no_move_display}', 'true'::jsonb);
    st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice || ':no_move'));
    st := st - 'movable_pawns';
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
    END IF;
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    v_now := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"');
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
    st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
    st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
    st := jsonb_set(st, '{turn_seq}', to_jsonb(COALESCE((st->>'turn_seq')::int, 0) + 1));
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  RETURN st;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_roll(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_roll(uuid) TO authenticated;

-- ── 2. ludo_bot_play SANS bot_win_bias ──
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
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence INTO v_isbot, v_intel
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    -- Dé équitable, aucune triche
    v_dice := 1 + (floor(random()*6))::INT;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

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

  IF array_length(candidates,1) IS NULL THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  -- L'intelligence du bot ne concerne QUE le choix du pion, JAMAIS le dé
  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
      IF pstate='yard' THEN sc := 60;
      ELSIF pstep + v_dice = 56 THEN sc := 80;
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR other_slot IN 0..g.max_players-1 LOOP
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
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_bot_play(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_bot_play(uuid) TO authenticated;

-- ── 3. ludo_start_solo_bot SANS bot_win_bias ──
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty text DEFAULT 'medium'::text,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic'::text,
  _match_type text DEFAULT 'solo'::text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid        UUID := auth.uid();
  v_game_id    UUID;
  v_code       TEXT;
  v_commission NUMERIC;
  v_i          INT;
  v_colors     TEXT[] := ARRAY['red','green','yellow','blue'];
  v_bots       TEXT[] := ARRAY['BotAlpha','BotBeta','BotGamma','BotDelta'];
  v_intel      INT;
  v_mp         INT;
  v_mode       TEXT;
  v_pseudo     TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  v_mp := LEAST(GREATEST(COALESCE(_max_players, 2), 2), 4);

  SELECT COALESCE(game_commission_pct, 10) INTO v_commission FROM public.app_settings WHERE id = 1;
  SELECT COALESCE(pseudo, '') INTO v_pseudo FROM public.profiles WHERE id = v_uid;

  v_code := upper(substr(md5(random()::text), 1, 6));

  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct,
    room_code, is_private, mode, match_type, status, is_solo
  ) VALUES (
    v_uid, v_mp, _stake, _stake * v_mp, v_commission,
    v_code, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE
  ) RETURNING id INTO v_game_id;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, ready, display_name, joined_at)
  VALUES (v_game_id, v_uid, 0, v_colors[1], FALSE, TRUE, v_pseudo, now());

  -- L'intelligence du bot ne concerne QUE le choix du pion, pas le dé
  v_intel := CASE WHEN _difficulty = 'hard' THEN 85 WHEN _difficulty = 'easy' THEN 40 ELSE 65 END;

  FOR v_i IN 1..v_mp - 1 LOOP
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot,
      bot_name, bot_intelligence, ready, display_name, joined_at
    ) VALUES (
      v_game_id, v_uid, v_i, v_colors[v_i+1], TRUE,
      v_bots[v_i], v_intel, TRUE, v_bots[v_i], now()
    );
  END LOOP;

  UPDATE public.ludo_games SET
    status = 'playing', started_at = now(),
    state = public._ludo_init_state(v_mp, v_mode),
    current_turn = 0
  WHERE id = v_game_id;

  RETURN v_game_id;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) TO authenticated;

-- ── 4. admin_add_bot SANS _win_bias ──
CREATE OR REPLACE FUNCTION public.admin_add_bot(
  _game_id uuid,
  _bot_name text,
  _intelligence integer DEFAULT 70
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_slot int;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  v_count int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé à l''administrateur'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT s INTO v_slot
    FROM generate_series(0, g.max_players-1) AS s
   WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id=_game_id)
   ORDER BY s LIMIT 1;

  IF g.max_players = 2 THEN v_color := v_colors2[v_slot+1];
  ELSIF g.max_players = 3 THEN v_color := v_colors3[v_slot+1];
  ELSE v_color := v_colors4[v_slot+1];
  END IF;

  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, ready
  ) VALUES (
    _game_id, NULL, v_slot, v_color, TRUE,
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    GREATEST(0, LEAST(100, COALESCE(_intelligence, 70))),
    TRUE
  );
END $function$;

REVOKE EXECUTE ON FUNCTION public.admin_add_bot(uuid, text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_add_bot(uuid, text, integer) TO authenticated;

-- ── 5. admin_update_bot SANS _win_bias ──
CREATE OR REPLACE FUNCTION public.admin_update_bot(_participant_id uuid, _intelligence integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.ludo_participants SET
    bot_intelligence = GREATEST(0, LEAST(100, _intelligence))
    WHERE id = _participant_id AND is_bot = TRUE;
END $function$;

REVOKE EXECUTE ON FUNCTION public.admin_update_bot(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_bot(uuid, integer) TO authenticated;

-- ── 6. admin_get_bot_config SANS win_bias ──
CREATE OR REPLACE FUNCTION public.admin_get_bot_config(_participant_id uuid)
RETURNS TABLE(intelligence integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  RETURN QUERY
    SELECT bot_intelligence
    FROM public.ludo_participants
    WHERE id = _participant_id AND is_bot = true;
END $function$;

REVOKE EXECUTE ON FUNCTION public.admin_get_bot_config(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_bot_config(uuid) TO authenticated;

-- ── 7. Nettoyage des données existantes ──
-- Mettre tous les bot_win_bias à 0
UPDATE public.ludo_participants SET bot_win_bias = 0 WHERE bot_win_bias <> 0;
-- Vider tous les dice_override
UPDATE public.ludo_games SET dice_override = NULL WHERE dice_override IS NOT NULL;

-- ── 8. Masquer les colonnes de triche au frontend ──
-- Les colonnes existent encore (pour ne pas casser les INSERTs) mais sont inutilisées
REVOKE SELECT (bot_win_bias) ON public.ludo_participants FROM anon, authenticated;
REVOKE SELECT (dice_override) ON public.ludo_games FROM anon, authenticated;

-- ── 9. Supprimer l'ancienne version d'admin_add_bot avec _win_bias ──
DROP FUNCTION IF EXISTS public.admin_add_bot(uuid, text, integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.admin_update_bot(uuid, integer, integer) CASCADE;
DROP FUNCTION IF EXISTS public.admin_get_bot_config_old(uuid) CASCADE;
