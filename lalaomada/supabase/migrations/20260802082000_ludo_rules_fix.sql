-- ========================================
-- Fix Ludo official rules & gameplay bugs
-- ========================================

-- 1. Update rules text to match official Ludo rules
UPDATE public.game_configs
SET rules_markdown = '🎲 RÈGLES DU LUDO

• Lance le dé. Tu as besoin d''un 6 pour sortir un pion du yard.
• Avance tes pions sur le plateau en faisant le tour dans le sens horaire.
• Si tu tombes sur un pion adverse (hors case sûre ★), tu le renvoies au yard — c''est une capture !
• Cases sûres (★) : tes pions ne peuvent pas être capturés dessus.
• Rejoue un tour si : tu fais un 6, tu captures un pion adverse, ou un de tes pions arrive à la maison.
• 3 six consécutifs = ton tour est annulé (les 3 six sont perdus).
• Tu dois faire le chiffre exact pour rentrer un pion à la maison (case 56).
• Le premier à rentrer ses 4 pions gagne la partie.'
WHERE slug = 'ludo';

-- 2. Fix ludo_roll: don't reset consecutive_sixes when no valid move on a 6
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
  arr jsonb;
  pawn jsonb;
  i INT;
  pstate TEXT;
  pstep INT;
  has_move BOOLEAN := FALSE;
  v_consec INT;
  v_override INT;
  v_state_consec INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes
    INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;

  -- Sync the state counter with the column counter
  v_state_consec := COALESCE((st->>'consecutive_sixes')::INT, 0);
  IF v_state_consec <> v_consec THEN
    v_consec := v_state_consec;
  END IF;

  -- Dice override (super-player admin)
  v_override := NULLIF(g.dice_override->>v_slot::text, '')::INT;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    v_dice := 1 + (floor(random() * 6))::INT;
    IF v_isbot AND COALESCE(v_bias, 0) > 0 AND (random() * 100) < v_bias THEN
      v_dice := 6;
    END IF;
  END IF;

  -- Track consecutive sixes (in BOTH column and state)
  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants SET consecutive_sixes = v_consec WHERE game_id = _game_id AND slot = v_slot;

  -- Triple six → cancel turn
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  st := jsonb_set(st, '{consecutive_sixes}', to_jsonb(v_consec));
  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));

  -- Check if any valid move exists
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, 0);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;

  IF NOT has_move THEN
    -- No legal move: skip turn but KEEP consecutive_sixes counting
    -- (a 6 you can't play still counts toward triple-six)
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice || ':no_move'));
    -- Only reset consecutive_sixes if dice was NOT 6
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    END IF;
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
  ELSE
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  END IF;
  RETURN st;
END $function$;

-- 3. Fix ludo_bot_play: track consecutive_sixes properly
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_isbot BOOLEAN;
  v_intel INT;
  v_bias INT;
  v_dice INT;
  v_consec INT;
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
  rec RECORD;
  op jsonb;
  op_step INT;
  op_start INT;
  op_abs INT;
  would_capture BOOLEAN;
  would_be_danger BOOLEAN;
  danger_dist INT;
  candidates INT[] := ARRAY[]::INT[];
  has_move BOOLEAN := FALSE;
  SCORE_WIN        INT := 1000;
  SCORE_CAPTURE    INT := 500;
  SCORE_EXIT_YARD  INT := 200;
  SCORE_HOME_STRETCH INT := 150;
  SCORE_DANGER_BONUS INT := 80;
  SCORE_ADVANCE    INT := 10;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  SELECT is_bot, bot_intelligence, bot_win_bias, consecutive_sixes
    INTO v_isbot, v_intel, v_bias, v_consec
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot THEN RETURN st; END IF;

  -- ── Roll if needed ──
  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random() * 6))::INT;
    IF COALESCE(v_bias, 0) > 0 AND (random() * 100) < v_bias THEN
      v_dice := 6;
    END IF;

    -- Track consecutive sixes (column + state)
    IF v_dice = 6 THEN
      v_consec := COALESCE(v_consec, 0) + 1;
    ELSE
      v_consec := 0;
    END IF;
    UPDATE public.ludo_participants SET consecutive_sixes = v_consec WHERE game_id = _game_id AND slot = v_slot;

    -- Triple six → cancel turn
    IF v_consec >= 3 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
      st := jsonb_set(st, '{must_move}', 'false'::jsonb);
      st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
      st := jsonb_set(st, '{dice}', 'null'::jsonb);
      st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
      st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
      UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
      RETURN st;
    END IF;

    st := jsonb_set(st, '{consecutive_sixes}', to_jsonb(v_consec));
    st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
    st := jsonb_set(st, '{must_move}', 'true'::jsonb);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot_roll:' || v_dice));
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  -- ── Find all playable pawns ──
  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_for(_game_id, v_slot);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, 0);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  -- No valid move → pass (keep consecutive_sixes if 6)
  IF array_length(candidates, 1) IS NULL THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('bot:pass'));
    -- Reset consecutive_sixes only if dice was NOT 6
    IF v_dice <> 6 THEN
      UPDATE public.ludo_participants SET consecutive_sixes = 0 WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{consecutive_sixes}', '0'::jsonb);
    END IF;
    UPDATE public.ludo_games SET state = st, current_turn = (st->>'turn_slot')::INT WHERE id = _game_id;
    RETURN st;
  END IF;

  -- ── Intelligence check ──
  IF (random() * 100) < COALESCE(v_intel, 75) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i;
      pstate := pawn->>'s';
      pstep := COALESCE((pawn->>'k')::INT, 0);
      sc := 0;

      -- Priority 1: WIN
      IF pstate = 'track' AND pstep + v_dice = 56 THEN
        sc := SCORE_WIN;
      -- Priority 2: CAPTURE
      ELSIF pstate = 'track' AND pstep + v_dice <= 50 THEN
        abs_cell := (start_idx + pstep + v_dice) % 52;
        would_capture := FALSE;
        IF NOT public._ludo_is_safe(abs_cell) THEN
          FOR rec IN SELECT slot FROM public.ludo_participants
                      WHERE game_id = _game_id AND slot <> v_slot LOOP
            op_start := public._ludo_start_for(_game_id, rec.slot);
            FOR k IN 0..3 LOOP
              op := st->'pawns'->rec.slot::text->k;
              IF op->>'s' = 'track' THEN
                op_step := COALESCE((op->>'k')::INT, 0);
                IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                  would_capture := TRUE;
                END IF;
              END IF;
            END LOOP;
          END LOOP;
        END IF;
        sc := SCORE_CAPTURE * CASE WHEN would_capture THEN 1 ELSE 0 END;
        sc := sc + pstep * SCORE_ADVANCE;
        -- Priority 5: DANGER AVOIDANCE
        IF pstep <= 50 THEN
          abs_cell := (start_idx + pstep) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            would_be_danger := FALSE;
            FOR rec IN SELECT slot FROM public.ludo_participants
                        WHERE game_id = _game_id AND slot <> v_slot LOOP
              op_start := public._ludo_start_for(_game_id, rec.slot);
              FOR k IN 0..3 LOOP
                op := st->'pawns'->rec.slot::text->k;
                IF op->>'s' = 'track' THEN
                  op_step := COALESCE((op->>'k')::INT, 0);
                  op_abs := (op_start + op_step) % 52;
                  danger_dist := (abs_cell - op_abs + 52) % 52;
                  IF danger_dist >= 1 AND danger_dist <= 6 THEN
                    would_be_danger := TRUE;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
            IF would_be_danger THEN
              sc := sc + SCORE_DANGER_BONUS;
            END IF;
          END IF;
        END IF;
      -- Priority 3: EXIT YARD
      ELSIF pstate = 'yard' THEN
        sc := SCORE_EXIT_YARD;
      -- Priority 4: HOME STRETCH
      ELSIF pstate = 'track' AND pstep >= 51 THEN
        sc := SCORE_HOME_STRETCH + pstep * SCORE_ADVANCE;
      ELSE
        sc := pstep * SCORE_ADVANCE;
      END IF;

      IF sc > best_score THEN
        best_score := sc;
        best := i;
      END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random() * array_length(candidates, 1)))::INT];
  END IF;

  -- Safety fallback
  IF best < 0 AND array_length(candidates, 1) >= 1 THEN
    best := candidates[1];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $function$;

-- 4. Fix ludo_pass: sync consecutive_sixes with state
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
  start_idx INT;
  v_next_slot INT;
  v_isbot_next BOOLEAN;
  v_now TEXT;
  v_seq INT;
  v_consec_six INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status IS NULL OR g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  IF st IS NULL THEN RAISE EXCEPTION 'État de partie manquant'; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot FROM public.ludo_participants WHERE game_id = _game_id AND slot = v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  start_idx := public._ludo_start_for(_game_id, v_slot);
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, 0);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;
  IF has_move THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;

  v_now := to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_seq := COALESCE((st->>'turn_seq')::INT, 0) + 1;
  v_next_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);

  -- Sync consecutive_sixes from state
  v_consec_six := COALESCE((st->>'consecutive_sixes')::INT, 0);
  IF v_dice = 6 THEN
    v_consec_six := v_consec_six + 1;
    -- Check triple six
    IF v_consec_six >= 3 THEN
      v_consec_six := 0;
    END IF;
  ELSE
    v_consec_six := 0;
  END IF;

  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{consecutive_sixes}', to_jsonb(v_consec_six));
  st := jsonb_set(st, '{turn_slot}', to_jsonb(v_next_slot));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{last_event}', to_jsonb('pass'::text));
  st := jsonb_set(st, '{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
  st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
  SELECT is_bot INTO v_isbot_next FROM public.ludo_participants WHERE game_id = _game_id AND slot = v_next_slot;
  st := jsonb_set(st, '{spin_ms}', to_jsonb(CASE WHEN COALESCE(v_isbot_next, FALSE) THEN 2500 ELSE 0 END));

  -- Update column to match state
  UPDATE public.ludo_participants SET consecutive_sixes = v_consec_six WHERE game_id = _game_id AND slot = v_slot;
  UPDATE public.ludo_games SET state = st, current_turn = v_next_slot WHERE id = _game_id;
  RETURN st;
END $function$;
