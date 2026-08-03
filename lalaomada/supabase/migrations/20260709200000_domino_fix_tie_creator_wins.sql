-- ─────────────────────────────────────────────────────────────────────────────
-- Fix consolidé : Domino — égalité de points (partie bloquée)
--
-- Problème corrigé : quand les deux joueurs ont le même total de points
-- (pips) dans une partie bloquée, le système désignait le créateur de la
-- partie (premier slot) comme gagnant au lieu de faire un match nul.
-- De plus, en mode "Victoire directe", la partie se terminait au lieu de
-- relancer automatiquement une nouvelle manche.
--
-- Ce fichier regroupe l'état final correct de toutes les fonctions
-- concernées (à coller tel quel dans l'éditeur SQL Supabase) :
--   1. _domino_lowest_pip_slot → retourne NULL en cas d'égalité de points
--   2. _domino_finalize        → gère un gagnant NULL (remboursement du pot)
--   3. _domino_end_round       → égalité = toujours nouvelle manche
--                                 automatique, aucun point, aucun gagnant
--   4. domino_play             → propage correctement le NULL renvoyé par
--                                 _domino_lowest_pip_slot
-- ─────────────────────────────────────────────────────────────────────────────

-- ① _domino_lowest_pip_slot : retourne NULL si ≥ 2 joueurs sont à égalité
CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  p record;
  cur_sum integer;
  best_sum integer := 2147483647;
  best_slot integer := NULL;
  tie_count integer := 0;
BEGIN
  FOR p IN
    SELECT slot FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false
    ORDER BY slot
  LOOP
    cur_sum := public._domino_hand_pips(
      COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb)
    );
    IF cur_sum < best_sum THEN
      best_sum  := cur_sum;
      best_slot := p.slot;
      tie_count := 1;
    ELSIF cur_sum = best_sum THEN
      tie_count := tie_count + 1;   -- égalité détectée
    END IF;
  END LOOP;

  -- Si plusieurs joueurs partagent le minimum → match nul (NULL)
  IF tie_count > 1 THEN
    RETURN NULL;
  END IF;
  RETURN best_slot;
END;
$$;

-- ② _domino_finalize : gère un gagnant NULL (match nul → remboursement du pot)
CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g            record;
  winner_uid   uuid;
  payout       numeric;
  p            record;
  n_active     integer;
  refund_each  numeric;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;

  -- ── Match nul : aucun gagnant ─────────────────────────────────────────────
  IF _winner_slot IS NULL THEN
    SELECT count(*) INTO n_active
    FROM public.domino_participants
    WHERE game_id = _game_id AND forfeited = false;

    IF n_active > 0 AND g.pot > 0 THEN
      refund_each := floor(g.pot / n_active);
      FOR p IN
        SELECT user_id FROM public.domino_participants
        WHERE game_id = _game_id AND forfeited = false
      LOOP
        UPDATE public.profiles
          SET balance_ar = balance_ar + refund_each
          WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul – remboursement');
      END LOOP;
    END IF;

    UPDATE public.domino_games
      SET status = 'finished', winner_id = NULL, finished_at = now()
      WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Victoire normale ──────────────────────────────────────────────────────
  SELECT user_id INTO winner_uid
  FROM public.domino_participants
  WHERE game_id = _game_id AND slot = _winner_slot;

  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  UPDATE public.domino_games
    SET status = 'finished', winner_id = winner_uid, finished_at = now()
    WHERE id = _game_id;
END;
$$;

-- ③ _domino_end_round : égalité = toujours nouvelle manche automatique,
--    dans tous les modes (Victoire directe ET Par points), sans point ni
--    remboursement immédiat. La partie ne se termine jamais sur un nul.
CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  g              record;
  st             jsonb;
  winner_uid     uuid;
  round_score    int   := 0;
  hand_pips      jsonb := '{}'::jsonb;
  v_final_hands  jsonb := '{}'::jsonb;
  p              record;
  pips           int;
  v_scores       jsonb;
  new_total      int;
  v_blocked      boolean := false;
  winner_hand    jsonb;
  v_reveal       interval := interval '3 seconds';
  v_break_total  interval := interval '13 seconds';
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;

  -- ── Match nul : aucun gagnant ─────────────────────────────────────────────
  IF _winner_slot IS NULL THEN
    st := g.state;
    FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
      pips          := public._domino_hand_pips(st->'hands'->p.slot::text);
      hand_pips     := hand_pips     || jsonb_build_object(p.user_id::text, pips);
      v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    END LOOP;

    -- Dans tous les cas (Victoire directe ET Par points) : nouvelle manche
    -- automatique, aucun point, aucun remboursement, la partie continue.
    st := jsonb_set(st, '{phase}',        '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
    st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  NULL::text,
      'round_score', 0,
      'hand_pips',   hand_pips,
      'final_hands', v_final_hands,
      'blocked',     true,
      'draw',        true,
      'final',       false    -- la partie continue toujours
    ));
    st := jsonb_set(st, '{scores}', COALESCE(g.scores, '{}'::jsonb));
    UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Victoire normale ──────────────────────────────────────────────────────
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;

  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked   := COALESCE(jsonb_array_length(winner_hand), 0) > 0;

  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips          := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips     := hand_pips     || jsonb_build_object(p.user_id::text, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;

  -- Jeu sans points (Victoire directe) : fin directe sur victoire
  IF COALESCE(g.target_score, 0) <= 0 THEN
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Jeu à points : cumul du score du gagnant de la manche
  v_scores  := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_uid::text)::int, 0) + round_score;
  v_scores  := jsonb_set(v_scores, ARRAY[winner_uid::text], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;

  -- Objectif atteint → fin de partie
  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{last_round}', jsonb_build_object(
      'winner_uid',  winner_uid,
      'round_score', round_score,
      'hand_pips',   hand_pips,
      'final_hands', v_final_hands,
      'blocked',     v_blocked,
      'final',       true
    ));
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;

  -- Objectif pas encore atteint → nouvelle manche
  st := jsonb_set(st, '{phase}',        '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_uid',  winner_uid,
    'round_score', round_score,
    'hand_pips',   hand_pips,
    'final_hands', v_final_hands,
    'blocked',     v_blocked,
    'final',       false
  ));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END;
$$;

-- ④ domino_play : propage correctement le NULL de _domino_lowest_pip_slot
--    (blocage après un "pass" en chaîne, blocage après un "play", et
--    partie totalement bloquée) vers _domino_end_round.
CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  g           record;
  my_slot     int;
  st          jsonb;
  hand        jsonb;
  tile        jsonb;
  a int; b int;
  le int; re int;
  side        text;
  new_left    int; new_right int;
  action      text;
  n_players   int;
  next_turn   int;
  drawn       jsonb;
  stock       jsonb;
  found       boolean := false;
  new_hand    jsonb;
  i           int;
  winner_slot int;
  draw_mode   text;
  first_dbl   int;
  stock_len   int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;
  SELECT slot INTO my_slot FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid;
  IF my_slot IS NULL OR my_slot <> g.current_turn THEN RAISE EXCEPTION 'not your turn'; END IF;

  st        := g.state;
  action    := _move->>'action';
  hand      := st -> 'hands' -> my_slot::text;
  stock     := st -> 'stock';
  le        := NULLIF(st->>'left_end',  'null')::int;
  re        := NULLIF(st->>'right_end', 'null')::int;
  draw_mode := COALESCE(st->>'draw_mode', 'with');
  stock_len := jsonb_array_length(COALESCE(stock, '[]'::jsonb));
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  -- ── Draw tile ──────────────────────────────────────────────────────────────
  IF action = 'draw' THEN
    IF draw_mode = 'without' THEN RAISE EXCEPTION 'draw disabled in this game'; END IF;
    IF stock_len = 0 THEN RAISE EXCEPTION 'stock empty'; END IF;
    drawn := stock -> 0; stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    st := jsonb_set(st, ARRAY['hands', my_slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Pass ───────────────────────────────────────────────────────────────────
  IF action = 'pass' THEN
    IF draw_mode = 'with' AND stock_len > 0 THEN RAISE EXCEPTION 'you must draw first'; END IF;
    st        := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
    next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
    IF (st->>'passes')::int >= n_players THEN
      -- Tout le monde a passé → partie bloquée
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      -- winner_slot IS NULL → égalité de points → match nul
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    IF next_turn IS NULL THEN
      -- Personne ne peut jouer → bloqué
      winner_slot := public._domino_lowest_pip_slot(_game_id, st);
      PERFORM public._domino_end_round(_game_id, winner_slot);
      RETURN;
    END IF;
    st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
    UPDATE public.domino_games SET state = st, current_turn = next_turn, turn_deadline = now() + interval '30 seconds' WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Play tile ──────────────────────────────────────────────────────────────
  IF action <> 'play' THEN RAISE EXCEPTION 'unknown action'; END IF;

  tile := _move -> 'tile';
  IF tile IS NULL THEN RAISE EXCEPTION 'tile required'; END IF;
  a := (tile->>0)::int; b := (tile->>1)::int;
  side := _move->>'side';

  -- Validate the player has this tile
  found := false;
  FOR i IN 0 .. jsonb_array_length(hand) - 1 LOOP
    IF (hand->i->>0)::int = a AND (hand->i->>1)::int = b THEN
      found := true;
      new_hand := hand - i;
      EXIT;
    END IF;
    IF (hand->i->>0)::int = b AND (hand->i->>1)::int = a THEN
      found := true;
      a := b; b := (hand->i->>0)::int;
      new_hand := hand - i;
      EXIT;
    END IF;
  END LOOP;
  IF NOT found THEN RAISE EXCEPTION 'tile not in hand'; END IF;

  -- First move: must be on empty board
  first_dbl := NULLIF(st->>'first_move_double', 'null')::int;
  IF le IS NULL THEN
    IF first_dbl IS NOT NULL AND a <> b THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    IF first_dbl IS NOT NULL AND a <> first_dbl THEN RAISE EXCEPTION 'first move must be the highest double'; END IF;
    new_left  := b; new_right := a;
    st := jsonb_set(st, '{board}', jsonb_build_array(tile));
  ELSE
    -- Determine side
    IF side = 'left' OR side IS NULL THEN
      IF a = le THEN new_left := b;
      ELSIF b = le THEN new_left := a; a := b; b := (tile->>0)::int;
      ELSIF side = 'left' THEN RAISE EXCEPTION 'tile does not fit left';
      ELSE side := 'right'; END IF;
    END IF;
    IF side = 'right' THEN
      IF a = re THEN new_right := b;
      ELSIF b = re THEN new_right := a;
      ELSE RAISE EXCEPTION 'tile does not fit'; END IF;
    END IF;
    new_left  := CASE WHEN side = 'left'  THEN new_left  ELSE le END;
    new_right := CASE WHEN side = 'right' THEN new_right ELSE re END;
    st := jsonb_set(st, '{board}', (st->'board') || jsonb_build_array(tile));
  END IF;

  st := jsonb_set(st, ARRAY['hands', my_slot::text], new_hand);
  st := jsonb_set(st, '{left_end}',  to_jsonb(new_left));
  st := jsonb_set(st, '{right_end}', to_jsonb(new_right));
  st := jsonb_set(st, '{passes}',    to_jsonb(0));
  st := jsonb_set(st, '{first_move_double}', 'null'::jsonb);

  -- Win: player emptied their hand
  IF jsonb_array_length(new_hand) = 0 THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    PERFORM public._domino_end_round(_game_id, my_slot);
    RETURN;
  END IF;

  -- Advance turn
  next_turn := public._domino_next_playable_slot(_game_id, my_slot, st);
  IF next_turn IS NULL THEN
    -- Board is blocked
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    -- winner_slot IS NULL → égalité de points → match nul
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
  UPDATE public.domino_games
    SET state = st, current_turn = next_turn,
        turn_deadline = now() + interval '30 seconds'
    WHERE id = _game_id;
END;
$$;
