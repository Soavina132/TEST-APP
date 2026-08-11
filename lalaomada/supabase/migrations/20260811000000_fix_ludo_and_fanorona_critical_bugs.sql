-- ═══════════════════════════════════════════════════════════════════════
-- MIGRATION: Correction globale des bugs critiques Ludo + Fanorona
-- Date: 2026-08-11
--
-- BUGS CORRIGÉS:
--
-- LUDO:
--   1. ludo_start_solo_bot ne démarrait pas la partie (restait 'open')
--   2. ludo_set_ready exigeait téléphone vérifié → bloquait le solo bot
--   3. ludo_roll appelait _ludo_movable_pawns (fonction inexistante) → jeu bloqué
--   4. _ludo_init_state appelée sans le paramètre _mode → pas de power tiles en fast
--
-- FANORONA:
--   5. Règle 8: chaînage autorisé au premier coup (move_count=0)
--   6. Règle 6: pass autorisé hors rafale
--   7. Règle 10: pat = victoire au lieu de match nul
--   8. Pas de système de draw offer (colonnes result, draw_offered_by manquantes)
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- LUDO BUG 1: ludo_start_solo_bot — démarrer la partie automatiquement
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int := 70;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_balance numeric;
  v_commission numeric;
  v_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,0),
          TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');
  END IF;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;

  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE, v_team);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team
    );
  END LOOP;

  -- BUG 1 FIX: Démarrer la partie immédiatement (tous les participants sont prêts)
  UPDATE public.ludo_games
    SET status = 'playing',
        started_at = now(),
        state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic'))
    WHERE id = v_game_id;

  RETURN v_game_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- LUDO BUG 2: ludo_set_ready — skip phone verification for solo games
-- LUDO BUG 4: _ludo_init_state appelée avec le paramètre _mode
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;

  -- BUG 2 FIX: Skip phone verification for solo bot games
  IF _ready AND NOT COALESCE(v_game.is_solo, false) THEN
    SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
    IF NOT COALESCE(v_verified,false) THEN
      RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
    END IF;
  END IF;

  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    -- BUG 4 FIX: Pass mode to _ludo_init_state
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic'))
      WHERE id=_game_id;
  END IF;
END $function$;

-- ═══════════════════════════════════════════════════════════════════════
-- LUDO BUG 3: Redéfinir ludo_roll SANS _ludo_movable_pawns
-- (Version complète issue de la migration 20260806170000 avec power mode)
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT; v_override int; v_display jsonb;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;
  v_override := NULLIF(g.dice_override->>v_slot::text,'')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id=_game_id;
  ELSE
    v_dice := 1 + (floor(random()*6))::INT;
    IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
  END IF;
  IF v_dice = 6 THEN v_consec := COALESCE(v_consec,0) + 1; ELSE v_consec := 0; END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;
  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));
  st := st - 'no_move_display';
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice=6 THEN has_move:=TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move:=TRUE; EXIT; END IF; END IF;
  END LOOP;
  IF NOT has_move Then
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    v_display := jsonb_build_object('slot', v_slot, 'dice', v_dice,
      'until', to_char((now() + interval '1.5 seconds') AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    st := jsonb_set(st,'{no_move_display}', v_display);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_game_over(_game_id);
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- FANORONA: Appliquer les corrections des règles (3 bugs + draw offer)
-- ═══════════════════════════════════════════════════════════════════════

ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS result text,
  ADD COLUMN IF NOT EXISTS draw_offered_by uuid;

CREATE OR REPLACE FUNCTION public._fanorona_finalize_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  g record;
  p1_uid uuid; p2_uid uuid;
  payout numeric;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  payout := g.pot / 2;
  SELECT user_id INTO p1_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = 0;
  SELECT user_id INTO p2_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = 1;

  IF p1_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = p1_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (p1_uid, 'fanorona_draw', payout, _game_id, 'Fanorona draw refund');
  END IF;
  IF p2_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = p2_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (p2_uid, 'fanorona_draw', payout, _game_id, 'Fanorona draw refund');
  END IF;

  UPDATE public.fanorona_games
    SET status = 'finished', result = 'draw', draw_offered_by = NULL,
        finished_at = now(), updated_at = now()
    WHERE id = _game_id;
END $$;

GRANT EXECUTE ON FUNCTION public._fanorona_finalize_draw(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.fanorona_request_or_accept_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_status text; v_offered uuid;
  v_is_bot boolean;
BEGIN
  SELECT status, draw_offered_by INTO v_status, v_offered
    FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;

  SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND is_bot = true) INTO v_is_bot;
  IF v_is_bot THEN RETURN; END IF;

  IF v_offered IS NULL THEN
    UPDATE public.fanorona_games SET draw_offered_by = v_uid, updated_at = now() WHERE id = _game_id;
  ELSIF v_offered <> v_uid THEN
    PERFORM public._fanorona_finalize_draw(_game_id);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fanorona_decline_draw(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.fanorona_participants
    WHERE game_id = _game_id AND user_id = v_uid) THEN RETURN; END IF;
  UPDATE public.fanorona_games
    SET draw_offered_by = NULL, updated_at = now()
    WHERE id = _game_id AND draw_offered_by IS NOT NULL AND draw_offered_by <> v_uid;
END $$;

GRANT EXECUTE ON FUNCTION public.fanorona_request_or_accept_draw(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_decline_draw(uuid) TO authenticated;

-- Corriger _fanorona_play_by_slot avec les 3 fixes de règles
CREATE OR REPLACE FUNCTION public._fanorona_play_by_slot(_game_id uuid, _move jsonb, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  g record;
  my_color int; opp_color int;
  st jsonb; board jsonb;
  from_idx int; to_idx int;
  fr int; fc int; tr int; tc int; dr int; dc int;
  is_strong boolean;
  cap jsonb; lists jsonb;
  opp_left int; next_turn int;
  is_pass boolean;
  move_count int;
  visited jsonb;
  last_axis text;
  axis text;
  chain_from_v int;
  i int;
  v_cols int; v_rows int;
  v_elapsed_ms int;
  v_new_time_ms int;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF g.current_turn <> _slot THEN RAISE EXCEPTION 'not your turn'; END IF;

  IF g.draw_offered_by IS NOT NULL THEN
    UPDATE public.fanorona_games SET draw_offered_by = NULL WHERE id = _game_id;
  END IF;

  v_cols := COALESCE(g.cols, 9); v_rows := COALESCE(g.rows, 5);
  my_color  := CASE WHEN _slot = 0 THEN 1 ELSE 2 END;
  opp_color := CASE WHEN _slot = 0 THEN 2 ELSE 1 END;

  v_elapsed_ms := GREATEST(0, EXTRACT(EPOCH FROM (now() - COALESCE(g.last_move_at, g.started_at, now())))::int * 1000);

  IF _slot = 0 THEN
    v_new_time_ms := GREATEST(0, g.white_time_ms - v_elapsed_ms);
  ELSE
    v_new_time_ms := GREATEST(0, g.black_time_ms - v_elapsed_ms);
  END IF;

  IF v_new_time_ms <= 0 THEN
    PERFORM public._fanorona_finalize(_game_id, 1 - _slot);
    RETURN;
  END IF;

  st        := g.state;
  board     := st -> 'board';
  move_count := COALESCE((st->>'move_count')::int, 0);
  visited    := COALESCE(st->'visited', '[]'::jsonb);
  last_axis  := NULLIF(st->>'last_axis', '');
  chain_from_v := CASE WHEN st->'chain_from' IS NULL OR st->'chain_from' = 'null'::jsonb
                       THEN NULL ELSE (st->>'chain_from')::int END;

  is_pass := COALESCE((_move->>'pass')::boolean, false);

  -- BUG FIX 2: Pass autorisé UNIQUEMENT pendant une rafale (chain_from non null)
  IF is_pass THEN
    IF chain_from_v IS NULL THEN
      RAISE EXCEPTION 'can only end turn during a capture chain';
    END IF;
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    UPDATE public.fanorona_games SET
      state = st,
      current_turn = next_turn,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
      turn_deadline = now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval
      WHERE id = _game_id;
    -- BUG FIX 3: Pat = match nul, pas victoire
    IF NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) THEN
      PERFORM public._fanorona_finalize_draw(_game_id);
    END IF;
    RETURN;
  END IF;

  from_idx := (_move->>'from')::int;
  to_idx   := (_move->>'to')::int;
  cap      := COALESCE(_move->'captured', '[]'::jsonb);

  IF chain_from_v IS NOT NULL AND from_idx <> chain_from_v THEN
    RAISE EXCEPTION 'must continue with same piece';
  END IF;

  IF (board->from_idx)::int <> my_color THEN RAISE EXCEPTION 'not your piece'; END IF;
  IF (board->to_idx)::int <> 0 THEN RAISE EXCEPTION 'target not empty'; END IF;

  fr := from_idx / v_cols; fc := from_idx % v_cols;
  tr := to_idx   / v_cols; tc := to_idx   % v_cols;
  dr := tr - fr;           dc := tc - fc;
  IF abs(dr) > 1 OR abs(dc) > 1 OR (dr = 0 AND dc = 0) THEN
    RAISE EXCEPTION 'invalid step';
  END IF;
  is_strong := ((fr + fc) % 2 = 0);
  IF NOT is_strong AND (dr <> 0 AND dc <> 0) THEN
    RAISE EXCEPTION 'diagonal not allowed here';
  END IF;
  axis := public._fanorona_axis(dr, dc);

  IF chain_from_v IS NOT NULL THEN
    IF visited @> to_jsonb(to_idx) THEN RAISE EXCEPTION 'cannot revisit cell'; END IF;
    IF last_axis IS NOT NULL AND axis = last_axis THEN
      RAISE EXCEPTION 'cannot continue on same axis';
    END IF;
  END IF;

  lists := public._fanorona_capture_lists(board, my_color, from_idx, to_idx, v_cols, v_rows);
  IF jsonb_array_length(cap) > 0 THEN
    IF NOT (cap = (lists->'approach') OR cap = (lists->'withdrawal')) THEN
      RAISE EXCEPTION 'invalid capture set';
    END IF;
  END IF;

  IF jsonb_array_length(cap) = 0 THEN
    IF chain_from_v IS NOT NULL THEN
      RAISE EXCEPTION 'must capture during chain';
    END IF;
    IF COALESCE(g.mandatory_capture, true)
       AND public._fanorona_player_can_capture(board, my_color, v_cols, v_rows) Then
      RAISE EXCEPTION 'capture is mandatory when available';
    END IF;
  END IF;

  board := jsonb_set(board, ARRAY[from_idx::text], '0'::jsonb);
  board := jsonb_set(board, ARRAY[to_idx::text],   to_jsonb(my_color));
  IF jsonb_array_length(cap) > 0 THEN
    FOR i IN 0..jsonb_array_length(cap) - 1 LOOP
      board := jsonb_set(board, ARRAY[((cap->i)::int)::text], '0'::jsonb);
    END LOOP;
  END IF;
  st := jsonb_set(st, '{board}', board);

  SELECT count(*) INTO opp_left FROM jsonb_array_elements(board) v
    WHERE (v::text)::int = opp_color;
  IF opp_left = 0 THEN
    UPDATE public.fanorona_games SET
      state = st,
      last_move_at = now(),
      white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
      black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END
      WHERE id = _game_id;
    PERFORM public._fanorona_finalize(_game_id, _slot);
    RETURN;
  END IF;

  IF jsonb_array_length(cap) = 0 Then
    next_turn := 1 - _slot;
    st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
    st := jsonb_set(st, '{visited}',    '[]'::jsonb);
    st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
    st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
  Else
    visited := visited || to_jsonb(from_idx) || to_jsonb(to_idx);

    -- BUG FIX 1: Au premier coup du jeu (move_count = 0), une seule capture autorisée
    IF move_count = 0 Then
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    ELSIF public._fanorona_piece_can_capture(board, my_color, to_idx, visited, axis, v_cols, v_rows) Then
      next_turn := _slot;
      st := jsonb_set(st, '{chain_from}', to_jsonb(to_idx));
      st := jsonb_set(st, '{visited}',    visited);
      st := jsonb_set(st, '{last_axis}',  to_jsonb(axis));
    Else
      next_turn := 1 - _slot;
      st := jsonb_set(st, '{chain_from}', 'null'::jsonb);
      st := jsonb_set(st, '{visited}',    '[]'::jsonb);
      st := jsonb_set(st, '{last_axis}',  'null'::jsonb);
      st := jsonb_set(st, '{move_count}', to_jsonb(move_count + 1));
    END IF;
  END IF;

  UPDATE public.fanorona_games SET
    state = st,
    current_turn = next_turn,
    last_move_at = now(),
    white_time_ms = CASE WHEN _slot = 0 THEN v_new_time_ms ELSE white_time_ms END,
    black_time_ms = CASE WHEN _slot = 1 THEN v_new_time_ms ELSE black_time_ms END,
    turn_deadline = CASE WHEN next_turn = _slot THEN turn_deadline ELSE
      now() + (COALESCE((SELECT turn_timer_seconds FROM public._game_cfg('fanorona')),60) || ' seconds')::interval END
    WHERE id = _game_id;

  -- BUG FIX 3: Vérifier le pat après CHAQUE changement de tour
  IF next_turn <> _slot AND NOT public._fanorona_player_has_move(board, opp_color, v_cols, v_rows) Then
    PERFORM public._fanorona_finalize_draw(_game_id);
  END IF;
END $function$;

-- Nettoyer les fonctions obsolètes
DROP FUNCTION IF EXISTS public._ludo_movable_pawns(jsonb, integer, integer);
