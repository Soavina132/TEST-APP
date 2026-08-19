-- ═════════════════════════════════════════════════════════════════
-- FIX: Domino "par point" — 3 bugs
-- 1. domino_play: toujours appeler _domino_end_round (même si égalité)
-- 2. _domino_start_round: préserver round_scores entre rounds
-- 3. _domino_end_round: synchroniser colonne scores correctement
-- ═════════════════════════════════════════════════════════════════

-- ── FIX 2: _domino_start_round — préserver round_scores ──────────
CREATE OR REPLACE FUNCTION public._domino_start_round(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record; n int; tiles jsonb; hands jsonb := '{}'::jsonb; stock jsonb;
  per_hand int := 7; p record; idx int := 0; hand jsonb;
  starter int := 0; best int := -1; cur_dbl int; t jsonb;
  starter_double int := -1;
  prev_draw_mode text;
  _cfg record; new_round int; v_next_delay interval; v_playable jsonb;
  st jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF COALESCE(g.state->>'phase','') NOT IN ('reveal','break') THEN RETURN; END IF;

  SELECT count(*) INTO n FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false;
  IF n < 1 THEN RETURN; END IF;

  tiles := public._domino_deal(n);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    SELECT jsonb_agg(value) INTO hand FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
      WHERE ord > idx*per_hand AND ord <= (idx+1)*per_hand;
    hands := hands || jsonb_build_object(p.slot::text, COALESCE(hand,'[]'::jsonb));
    idx := idx + 1;
  END LOOP;

  SELECT jsonb_agg(value) INTO stock FROM jsonb_array_elements(tiles) WITH ORDINALITY t(value, ord)
    WHERE ord > n*per_hand;
  stock := COALESCE(stock, '[]'::jsonb);

  FOR p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    cur_dbl := -1;
    FOR t IN SELECT * FROM jsonb_array_elements(hands -> p.slot::text) LOOP
      IF (t->>0)::int = (t->>1)::int AND (t->>0)::int > cur_dbl THEN cur_dbl := (t->>0)::int; END IF;
    END LOOP;
    IF cur_dbl > best THEN best := cur_dbl; starter := p.slot; starter_double := cur_dbl; END IF;
  END LOOP;

  prev_draw_mode := COALESCE(g.state->>'draw_mode','with');
  IF jsonb_array_length(stock) = 0 THEN prev_draw_mode := 'without'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  new_round := COALESCE((g.state->>'round')::int, 1) + 1;

  st := jsonb_build_object(
    'phase','play',
    'round', new_round,
    'hands', hands,
    'stock', stock,
    'board', '[]'::jsonb,
    'left_end', 'null'::jsonb,
    'right_end', 'null'::jsonb,
    'passes', 0,
    'scores', COALESCE(g.state->'scores', '{}'::jsonb),
    'round_scores', COALESCE(g.state->'round_scores', '{}'::jsonb),
    'draw_mode', prev_draw_mode,
    'first_move_double', CASE WHEN starter_double >= 0 THEN to_jsonb(starter_double) ELSE 'null'::jsonb END,
    'first_tile_idx', 0,
    'first_tile_rule', COALESCE(g.state->>'first_tile_rule', g.first_tile_rule, 'libre'),
    'dead_tiles', '{}'::jsonb,
    'last_round', g.state->'last_round'
  );

  st := public._domino_arm_bot_think(_game_id, starter, st);
  v_playable := public._domino_playable_tiles(st, starter);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);

  UPDATE public.domino_games SET
    state = st,
    current_turn = starter,
    turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds, 30) || ' seconds')::interval
  WHERE id = _game_id;
END $$;

REVOKE ALL ON FUNCTION public._domino_start_round(uuid) FROM anon, authenticated;

-- ── FIX 3: _domino_end_round — synchroniser scores correctement ───
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record;
  st jsonb;
  v_scores jsonb;
  v_col_scores jsonb;
  v_slot int;
  v_pts int;
  v_total int;
  v_rounds int;
  v_winner_overall int;
  v_pass_count int;
  v_target int;
  v_mode text;
  v_reveal      interval := interval '2.5 seconds';
  v_break_total interval := interval '7 seconds';
  v_part record;
  v_all_blocked boolean := false;
  v_lowest int;
  v_lowest_slot int;
  v_tie_count int;
  v_key text;
  v_winner_uid text := null;
  v_round_score int := 0;
  v_hand_pips jsonb := '{}'::jsonb;
  v_final_hands jsonb := '{}'::jsonb;
  v_hand jsonb;
  v_pips int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;

  st := g.state;
  v_mode := COALESCE(g.mode, 'classic');
  v_target := COALESCE(g.target_score, 0);

  v_pass_count := COALESCE(NULLIF(st->>'passes','')::int, 0);
  IF v_pass_count >= (SELECT count(*) FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false) THEN
    v_all_blocked := true;
  END IF;

  v_scores := COALESCE(st->'round_scores', '{}'::jsonb);
  v_col_scores := COALESCE(g.scores, '{}'::jsonb);

  FOR v_part IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    v_key := COALESCE(v_part.user_id::text, 'bot_'||v_part.slot::text);
    v_hand := st->'hands'->v_part.slot::text;
    IF v_hand IS NOT NULL THEN
      SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pips
        FROM jsonb_array_elements(v_hand) AS tile;
    ELSE
      v_pips := 0;
    END IF;
    v_hand_pips := v_hand_pips || jsonb_build_object(v_key, v_pips);
    v_final_hands := v_final_hands || jsonb_build_object(v_key, COALESCE(v_hand, '[]'::jsonb));
    v_total := v_total + v_pips;
  END LOOP;

  IF v_all_blocked AND _winner_slot IS NULL THEN
    v_lowest := 999999;
    v_lowest_slot := 0;
    v_tie_count := 0;
    FOR v_part IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      v_key := COALESCE(v_part.user_id::text, 'bot_'||v_part.slot::text);
      v_pips := COALESCE((v_hand_pips->>v_key)::int, 0);
      IF v_pips < v_lowest THEN
        v_lowest := v_pips;
        v_lowest_slot := v_part.slot;
        v_tie_count := 1;
      ELSIF v_pips = v_lowest THEN
        v_tie_count := v_tie_count + 1;
      END IF;
    END LOOP;
    IF v_tie_count > 1 THEN
      _winner_slot := NULL;
    ELSE
      _winner_slot := v_lowest_slot;
    END IF;
  END IF;

  IF _winner_slot IS NOT NULL THEN
    SELECT COALESCE(user_id::text, 'bot_'||slot::text) INTO v_key
      FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
    v_winner_uid := v_key;
    v_round_score := GREATEST(0, v_total - COALESCE((v_hand_pips->>v_key)::int, 0));
    SELECT COALESCE((v_scores->>_winner_slot::text)::int, 0) + v_round_score INTO v_pts;
    v_scores := jsonb_set(v_scores, ARRAY[_winner_slot::text], to_jsonb(v_pts), true);
    SELECT COALESCE((v_col_scores->>v_key)::int, 0) + v_round_score INTO v_pts;
    v_col_scores := jsonb_set(v_col_scores, ARRAY[v_key], to_jsonb(v_pts), true);
  END IF;

  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid', v_winner_uid,
    'winner_slot', _winner_slot,
    'round_score', v_round_score,
    'hand_pips', v_hand_pips,
    'final_hands', v_final_hands,
    'blocked', v_all_blocked,
    'tie', (v_tie_count > 1),
    'round', COALESCE(NULLIF(st->>'round','')::int, 0)
  ), true);

  v_winner_overall := -1;
  IF v_mode = 'points' AND v_target > 0 THEN
    FOR v_slot IN SELECT DISTINCT (jsonb_object_keys(v_scores))::int LOOP
      IF (v_scores->>v_slot::text)::int >= v_target THEN
        v_winner_overall := v_slot;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    v_winner_overall := COALESCE(_winner_slot, -1);
  END IF;

  IF v_winner_overall >= 0 THEN
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{winner_slot}', to_jsonb(v_winner_overall), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);
    SELECT user_id INTO v_key FROM public.domino_participants
      WHERE game_id = _game_id AND slot = v_winner_overall;
    UPDATE public.domino_games
       SET state = st, status = 'finished',
           winner_id = v_key::uuid,
           scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;
    PERFORM public._domino_payout(_game_id, v_winner_overall);
    RETURN;
  END IF;

  IF v_mode <> 'points' OR v_target <= 0 THEN
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);
    UPDATE public.domino_games
       SET state = st, scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, NULL);
    RETURN;
  END IF;

  v_rounds := COALESCE(NULLIF(st->>'round','')::int, 0) + 1;
  st := jsonb_set(st, '{round}', to_jsonb(v_rounds), true);
  st := jsonb_set(st, '{round_scores}', v_scores, true);
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text), true);
  UPDATE public.domino_games
     SET state = st, scores = v_col_scores,
         current_turn = -1, turn_deadline = NULL
   WHERE id = _game_id;
END $$;

REVOKE ALL ON FUNCTION public._domino_end_round(uuid, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public._domino_end_round(uuid, integer) TO authenticated, service_role;

-- ── FIX 1: domino_play — toujours appeler _domino_end_round ────────
-- On ne fait qu'un patch ciblé : remplacer le IF guard par un appel direct.
-- Pour cela on recrée la fonction avec le fix.
CREATE OR REPLACE FUNCTION public.domino_play(
  _game_id uuid,
  _tile jsonb,
  _side text DEFAULT NULL,
  _tile_idx int DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  g record; st jsonb; my_slot int; my_uid uuid := auth.uid();
  _cfg record; hand jsonb; tile_val jsonb; new_hand jsonb;
  left_end int; right_end int; new_left int; new_right int;
  board jsonb; new_board jsonb; next_turn int; winner_slot int;
  v_playable jsonb; v_name text; _fti int;
  v_tile_idx int := _tile_idx; i int; v_found boolean := false;
BEGIN
  IF my_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie non en cours'; END IF;
  IF COALESCE(g.state->>'phase','') <> 'play' THEN RAISE EXCEPTION 'Phase de jeu incorrecte'; END IF;

  SELECT slot INTO my_slot FROM public.domino_participants dp
   WHERE dp.game_id = _game_id AND dp.user_id = my_uid AND dp.forfeited = false;
  IF my_slot IS NULL THEN RAISE EXCEPTION 'Tu n''es pas dans cette partie'; END IF;
  IF g.current_turn <> my_slot THEN RAISE EXCEPTION 'Ce n''est pas ton tour'; END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  st := g.state;
  hand := COALESCE(st->'hands'->my_slot::text, '[]'::jsonb);

  IF v_tile_idx IS NOT NULL THEN
    IF v_tile_idx < 0 OR v_tile_idx >= jsonb_array_length(hand) THEN
      RAISE EXCEPTION 'Index de tuile invalide';
    END IF;
    tile_val := hand->v_tile_idx;
  ELSE
    FOR i IN 0..jsonb_array_length(hand)-1 LOOP
      IF (hand->i->>0)::int = (_tile->>0)::int AND (hand->i->>1)::int = (_tile->>1)::int THEN
        v_tile_idx := i; tile_val := hand->i; EXIT;
      ELSIF (hand->i->>0)::int = (_tile->>1)::int AND (hand->i->>1)::int = (_tile->>0)::int THEN
        v_tile_idx := i; tile_val := jsonb_build_array((hand->i->>1)::int, (hand->i->>0)::int); EXIT;
      END IF;
    END LOOP;
  END IF;
  IF tile_val IS NULL THEN RAISE EXCEPTION 'Tuile non trouvee dans ta main'; END IF;

  board := COALESCE(st->'board', '[]'::jsonb);
  left_end := COALESCE(NULLIF(st->>'left_end','')::int, -1);
  right_end := COALESCE(NULLIF(st->>'right_end','')::int, -1);

  IF jsonb_array_length(board) = 0 THEN
    new_board := jsonb_build_array(jsonb_build_array(tile_val, 'r'));
    new_left := (tile_val->>0)::int;
    new_right := (tile_val->>1)::int;
    st := jsonb_set(st, '{first_move_double}', 'null'::jsonb, true);
    _fti := COALESCE(NULLIF(st->>'first_tile_idx','')::int, 0);
    st := jsonb_set(st, '{first_tile_idx}', to_jsonb(_fti + 1), true);
  ELSE
    DECLARE v_l int; v_r int; placed boolean := false;
    BEGIN
      v_l := (tile_val->>0)::int; v_r := (tile_val->>1)::int;
      IF _side = 'l' OR (_side IS NULL AND (v_l = left_end OR v_r = left_end)) THEN
        IF v_r = left_end THEN
          new_board := jsonb_build_array(jsonb_build_array(tile_val, 'l')) || board;
          new_left := v_l;
        ELSIF v_l = left_end THEN
          new_board := jsonb_build_array(jsonb_build_array(jsonb_build_array(v_r, v_l), 'l')) || board;
          new_left := v_r;
        ELSE
          RAISE EXCEPTION 'Tuile ne correspond pas au cote gauche (%)', left_end;
        END IF;
        placed := true;
      ELSIF _side = 'r' OR (_side IS NULL AND (v_l = right_end OR v_r = right_end)) THEN
        IF v_l = right_end THEN
          new_board := board || jsonb_build_array(jsonb_build_array(tile_val, 'r'));
          new_right := v_r;
        ELSIF v_r = right_end THEN
          new_board := board || jsonb_build_array(jsonb_build_array(jsonb_build_array(v_r, v_l), 'r'));
          new_right := v_l;
        ELSE
          RAISE EXCEPTION 'Tuile ne correspond pas au cote droit (%)', right_end;
        END IF;
        placed := true;
      END IF;
      IF NOT placed THEN
        RAISE EXCEPTION 'Tuile non jouable (extremites % / %)', left_end, right_end;
      END IF;
      new_left := COALESCE(new_left, left_end);
      new_right := COALESCE(new_right, right_end);
    END;
  END IF;

  SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO new_hand
    FROM jsonb_array_elements(hand) WITH ORDINALITY t(elem, ord)
    WHERE ord - 1 <> v_tile_idx;

  st := jsonb_set(st, '{board}', new_board, true);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left), true);
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right), true);
  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand, true);
  st := jsonb_set(st, '{passes}', to_jsonb(0), true);

  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN jsonb_build_object('ok', true, 'win', true);
  END IF;

  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    -- FIX: toujours appeler _domino_end_round, meme si winner_slot IS NULL (egalite)
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN jsonb_build_object('ok', true, 'blocked', true);
  END IF;

  v_playable := public._domino_playable_tiles(st, next_turn);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
  st := public._domino_arm_bot_think(_game_id, next_turn, st);

  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;
  RETURN jsonb_build_object('ok', true, 'next_turn', next_turn);
END $$;

REVOKE ALL ON FUNCTION public.domino_play(uuid, jsonb, text, integer) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb, text, integer) TO authenticated;

-- ── FIX 1b: domino_play(_game_id, _move) — la VRAIE fonction utilisée ──
-- Remplace les 2 gardes "IF winner_slot IS NOT NULL THEN PERFORM ... END IF"
-- par un appel direct "PERFORM public._domino_end_round(_game_id, winner_slot)"
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  g record; my_slot int; st jsonb; hand jsonb; tile jsonb;
  a int; b int; le int; re int; side text;
  new_left int; new_right int; action text; next_turn int;
  drawn jsonb; stock jsonb; found boolean := false; new_hand jsonb; i int;
  _cfg record; has_playable boolean := false; draw_mode text;
  is_first_move boolean; first_dbl int;
  matches_left boolean; matches_right boolean; winner_slot int;
  v_rule text; _fti int; v_dead_tiles jsonb; is_dead boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  IF (g.state->>'phase') IN ('break','reveal') THEN RAISE EXCEPTION 'round break'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = false;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;
  st := g.state; action := _move->>'action';
  hand := COALESCE(st -> 'hands' -> my_slot::text, '[]'::jsonb);
  stock := COALESCE(st -> 'stock','[]'::jsonb);
  le := NULLIF(st->>'left_end','null')::int; re := NULLIF(st->>'right_end','null')::int;
  draw_mode := COALESCE(st->>'draw_mode','with'); v_rule := COALESCE(st->>'first_tile_rule','libre');
  _fti := COALESCE((st->>'first_tile_idx')::int, 0);
  SELECT * INTO _cfg FROM public._game_cfg('domino');
  is_first_move := jsonb_array_length(COALESCE(st->'board','[]'::jsonb)) = 0;
  has_playable := public._domino_slot_has_playable(st, my_slot);
  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled'; END IF;
    IF has_playable THEN RAISE EXCEPTION 'you have a playable tile'; END IF;
    IF jsonb_array_length(stock) = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0; hand := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand); st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id; RETURN;
  END IF;
  IF action = 'pass' THEN
    IF has_playable THEN RAISE EXCEPTION 'you must play'; END IF;
    IF draw_mode = 'with' AND jsonb_array_length(stock) > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
    IF next_turn IS NULL THEN
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      UPDATE public.domino_games SET state = st WHERE id = _game_id;
      -- FIX: toujours appeler _domino_end_round, meme si egalite (winner_slot NULL)
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    UPDATE public.domino_games SET state = st, current_turn = next_turn,
      turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; RETURN;
  END IF;
  tile := _move -> 'tile'; side := _move->>'side'; a := (tile->>0)::int; b := (tile->>1)::int;
  v_dead_tiles := COALESCE(st->'dead_tiles'->my_slot::text, '[]'::jsonb);
  is_dead := false;
  IF jsonb_array_length(v_dead_tiles) > 0 THEN
    FOR i IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
      IF ((v_dead_tiles->i->>0)::int = a AND (v_dead_tiles->i->>1)::int = b)
      OR ((v_dead_tiles->i->>0)::int = b AND (v_dead_tiles->i->>1)::int = a) THEN is_dead := true; EXIT; END IF;
    END LOOP;
  END IF;
  IF is_dead THEN RAISE EXCEPTION 'Vato maty: ce domino est mort'; END IF;
  new_hand := '[]'::jsonb;
  FOR i IN 0..jsonb_array_length(hand)-1 LOOP
    IF NOT found AND ((hand->i->>0)::int = a AND (hand->i->>1)::int = b) THEN found := true;
    ELSE new_hand := new_hand || jsonb_build_array(hand->i); END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;
  IF is_first_move THEN
    first_dbl := NULLIF(st->>'first_move_double','null')::int;
    IF first_dbl IS NOT NULL THEN
      IF NOT (a = first_dbl AND b = first_dbl) THEN RAISE EXCEPTION 'first move must be the highest double (%-%)', first_dbl, first_dbl; END IF;
    ELSIF v_rule = 'under6' THEN
      IF (a + b) >= 6 THEN RAISE EXCEPTION '1er domino doit avoir un total < 6'; END IF;
    END IF;
    st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', false)));
    new_left := a; new_right := b; _fti := 0;
  ELSE
    matches_left := (a = le OR b = le); matches_right := (a = re OR b = re);
    IF side IS NULL OR side NOT IN ('left','right') OR (side = 'left' AND NOT matches_left) OR (side = 'right' AND NOT matches_right) THEN
      IF matches_right THEN side := 'right'; ELSIF matches_left THEN side := 'left';
      ELSE RAISE EXCEPTION 'tile does not match either end'; END IF;
    END IF;
    IF side = 'left' THEN
      IF a = le THEN new_left := b; ELSE new_left := a; END IF;
      st := jsonb_set(st, '{board}', jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a<>le)) || (st->'board'));
      new_right := re; _fti := _fti + 1;
    ELSE
      IF a = re THEN new_right := b; ELSE new_right := a; END IF;
      st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(jsonb_build_object('tile', tile, 'flipped', a=re AND a<>b)));
      new_left := le;
    END IF;
  END IF;
  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}', to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}', to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);
  st := jsonb_set(st, '{first_tile_idx}', to_jsonb(_fti));
  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot); RETURN;
  END IF;
  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    -- FIX: toujours appeler _domino_end_round, meme si egalite (winner_slot NULL)
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;
  UPDATE public.domino_games SET state = st, current_turn = next_turn,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END $$;

REVOKE ALL ON FUNCTION public.domino_play(uuid, jsonb) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) TO authenticated;

-- Drop the unused overload to avoid confusion
DROP FUNCTION IF EXISTS public.domino_play(uuid, jsonb, text, integer);
