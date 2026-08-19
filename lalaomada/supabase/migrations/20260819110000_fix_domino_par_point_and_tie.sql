-- ═════════════════════════════════════════════════════════════════════════════
-- FIX: Domino "par point" (points mode) ne fonctionne pas + gestion du match nul
--
-- Problème 1 : _domino_end_round lit `mode` et `target_score` depuis le state
--   JSONB (st->>'mode', st->>'target_score'), mais ces valeurs sont stockées
--   dans les COLONNES de la table domino_games, pas dans le state.
--   → v_mode reste toujours 'classic', v_target reste toujours 0
--   → Le mode points ne fonctionne jamais (le jeu s'arrête après 1 round)
--
-- Problème 2 : En cas de blocage (deadlock), si deux joueurs ont le même
--   nombre de pips restants le plus bas, le code choisit le premier trouvé.
--   → En cas d'égalité, personne ne gagne de points (match nul).
--
-- Problème 3 : Les scores sont stockés dans state->'round_scores' (clé = slot)
--   mais le frontend lit game.scores (colonne table, clé = user_id).
--   → Les scores ne s'affichent jamais en mode points.
--   Fix: mettre à jour la colonne `scores` avec les clés user_id.
--
-- Problème 4 : last_round ne contient pas les bons champs pour le frontend.
--   DominoRoundBreak attend: winner_uid, hand_pips, final_hands, round_score
--   mais _domino_end_round stockait: winner_slot, scores, remaining
--   Fix: stocker last_round dans le format attendu par le frontend.
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void AS $$
DECLARE
  g record;
  st jsonb;
  v_scores jsonb;        -- round_scores dans state (clé = slot)
  v_col_scores jsonb;    -- colonne scores (clé = user_id ou bot_N)
  v_slot int;
  v_pts int;
  v_total int;
  v_rounds int;
  v_winner_overall int;
  v_pass_count int;
  v_target int;
  v_mode text;
  v_next_starter int := 0;
  v_reveal       interval := interval '2.5 seconds';
  v_break_total  interval := interval '7 seconds';
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
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND THEN RETURN; END IF;

  st := g.state;
  -- FIX 1: lire mode et target_score depuis les colonnes de la table
  v_mode := COALESCE(g.mode, 'classic');
  v_target := COALESCE(g.target_score, 0);

  -- Determine if all players are blocked (deadlock)
  v_pass_count := COALESCE(NULLIF(st->>'passes','')::int, 0);
  IF v_pass_count >= (SELECT count(*) FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false) THEN
    v_all_blocked := true;
  END IF;

  -- Calculate round scores
  v_scores := COALESCE(st->'round_scores', '{}'::jsonb);
  -- FIX 3: also maintain the `scores` column (keyed by user_id or bot_N)
  v_col_scores := COALESCE(g.scores, '{}'::jsonb);

  -- Build hand_pips and final_hands for ALL participants (for frontend)
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
    -- Deadlock: find lowest pip count
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

    -- FIX 2: if there's a tie, nobody wins (match nul)
    IF v_tie_count > 1 THEN
      _winner_slot := NULL;
    ELSE
      _winner_slot := v_lowest_slot;
    END IF;
  END IF;

  -- Award points to winner (sum of all opponents' remaining pips)
  IF _winner_slot IS NOT NULL THEN
    -- Get winner key (user_id or bot_N)
    SELECT COALESCE(user_id::text, 'bot_'||slot::text) INTO v_key
      FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
    v_winner_uid := v_key;

    -- Round score = total pips minus winner's own pips
    v_round_score := GREATEST(0, v_total - COALESCE((v_hand_pips->>v_key)::int, 0));

    -- Update cumulative scores in state (keyed by slot)
    SELECT COALESCE((v_scores->>_winner_slot::text)::int, 0) + v_round_score INTO v_pts;
    v_scores := jsonb_set(v_scores, ARRAY[_winner_slot::text], to_jsonb(v_pts), true);

    -- FIX 3: also update the `scores` column (keyed by user_id or bot_N)
    SELECT COALESCE((v_col_scores->>v_key)::int, 0) + v_round_score INTO v_pts;
    v_col_scores := jsonb_set(v_col_scores, ARRAY[v_key], to_jsonb(v_pts), true);
  END IF;

  -- FIX 4: Store last_round in the format expected by DominoRoundBreak frontend
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

  -- Check if we have an overall winner
  v_winner_overall := -1;
  IF v_mode = 'points' AND v_target > 0 THEN
    FOR v_slot IN SELECT DISTINCT (jsonb_object_keys(v_scores))::int LOOP
      IF (v_scores->>v_slot::text)::int >= v_target THEN
        v_winner_overall := v_slot;
        EXIT;
      END IF;
    END LOOP;
  ELSE
    -- Classic mode: first round win = game win
    v_winner_overall := COALESCE(_winner_slot, -1);
  END IF;

  IF v_winner_overall >= 0 THEN
    -- Game over
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
    st := jsonb_set(st, '{winner_slot}', to_jsonb(v_winner_overall), true);
    st := jsonb_set(st, '{round_scores}', v_scores, true);

    -- Get winner user_id
    SELECT user_id INTO v_key FROM public.domino_participants
      WHERE game_id = _game_id AND slot = v_winner_overall;

    UPDATE public.domino_games
       SET state = st, status = 'finished',
           winner_id = v_key::uuid,
           scores = v_col_scores,
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;

    -- Award pot to winner
    PERFORM public._domino_payout(_game_id, v_winner_overall);
    RETURN;
  END IF;

  -- Start new round (works for: match nul, points mode without winner yet, classic new round)
  v_rounds := COALESCE(NULLIF(st->>'round','')::int, 0) + 1;
  st := jsonb_set(st, '{round}', to_jsonb(v_rounds), true);
  st := jsonb_set(st, '{round_scores}', v_scores, true);

  -- Re-deal tiles
  PERFORM public._domino_deal(_game_id, st, v_next_starter);

  -- Set reveal then break phase
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text), true);
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text), true);

  UPDATE public.domino_games
     SET state = st, scores = v_col_scores,
         current_turn = v_next_starter,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public._domino_end_round(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._domino_end_round(uuid, integer) TO authenticated, service_role;
