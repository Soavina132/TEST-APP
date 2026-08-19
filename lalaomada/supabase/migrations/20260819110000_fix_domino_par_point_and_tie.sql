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
--   nombre de pips restants le plus bas, le code actuel choisit le premier
--   trouvé avec `<` au lieu de détecter l'égalité.
--   → Il faut qu'en cas d'égalité, personne ne gagne de points (match nul).
--
-- Fix :
--   1. Lire mode et target_score depuis g.mode et g.target_score (colonnes)
--   2. Détecter les égalités dans le deadlock — si égalité, _winner_slot = NULL
--   3. Quand _winner_slot est NULL, ne pas attribuer de points et recommencer
--      un nouveau round
-- ═════════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot int DEFAULT NULL)
RETURNS void AS $$
DECLARE
  g record;
  st jsonb;
  v_scores jsonb;
  v_slot int;
  v_pts int;
  v_remaining jsonb;
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
  v_hands jsonb := '{}'::jsonb;
  v_hand jsonb;
  v_all_blocked boolean := false;
  v_lowest int;
  v_lowest_slot int;
  v_tie_count int;
  v_deadlock_slots int[];
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND THEN RETURN; END IF;

  st := g.state;
  -- FIX 1: lire mode et target_score depuis les colonnes de la table, pas le state JSONB
  v_mode := COALESCE(g.mode, 'classic');
  v_target := COALESCE(g.target_score, 0);

  -- Determine if all players are blocked (deadlock)
  v_pass_count := COALESCE(NULLIF(st->>'passes','')::int, 0);
  IF v_pass_count >= (SELECT count(*) FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false) THEN
    v_all_blocked := true;
  END IF;

  -- Calculate round scores
  v_scores := COALESCE(st->'round_scores', '{}'::jsonb);

  IF v_all_blocked AND _winner_slot IS NULL THEN
    -- Deadlock: find lowest pip count
    v_lowest := 999999;
    v_lowest_slot := 0;
    v_tie_count := 0;
    FOR v_slot IN SELECT unnest(array(SELECT DISTINCT (jsonb_object_keys(st->'hands'))::int ORDER BY 1)) LOOP
      v_hand := st->'hands'->v_slot::text;
      IF v_hand IS NOT NULL THEN
        SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pts
          FROM jsonb_array_elements(v_hand) AS tile;
        IF v_pts < v_lowest THEN
          v_lowest := v_pts;
          v_lowest_slot := v_slot;
          v_tie_count := 1;
        ELSIF v_pts = v_lowest THEN
          -- FIX 2: tie detected — same lowest pip count
          v_tie_count := v_tie_count + 1;
        END IF;
      END IF;
    END LOOP;

    -- FIX 2: if there's a tie, nobody wins (match nul)
    IF v_tie_count > 1 THEN
      _winner_slot := NULL;  -- match nul, personne ne gagne de points
    ELSE
      _winner_slot := v_lowest_slot;
    END IF;
  END IF;

  -- Award points to winner (sum of all opponents' remaining pips)
  IF _winner_slot IS NOT NULL THEN
    v_remaining := '{}'::jsonb;
    v_total := 0;
    FOR v_slot IN SELECT unnest(array(SELECT DISTINCT (jsonb_object_keys(st->'hands'))::int ORDER BY 1)) LOOP
      IF v_slot <> _winner_slot THEN
        v_hand := st->'hands'->v_slot::text;
        IF v_hand IS NOT NULL THEN
          SELECT COALESCE(sum((tile->>0)::int + (tile->>1)::int), 0) INTO v_pts
            FROM jsonb_array_elements(v_hand) AS tile;
          v_remaining := v_remaining || jsonb_build_object(v_slot::text, v_pts);
          v_total := v_total + v_pts;
        END IF;
      END IF;
    END LOOP;

    -- Update cumulative scores
    SELECT COALESCE((v_scores->>_winner_slot::text)::int, 0) + v_total INTO v_pts;
    v_scores := jsonb_set(v_scores, ARRAY[_winner_slot::text], to_jsonb(v_pts), true);
  END IF;

  -- Store last round info
  st := jsonb_set(st, '{last_round}', jsonb_build_object(
    'winner_slot', _winner_slot,
    'scores', v_scores,
    'remaining', v_remaining,
    'blocked', v_all_blocked,
    'tie', (v_tie_count > 1)
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

    UPDATE public.domino_games
       SET state = st, status = 'finished',
           winner_id = (SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND slot = v_winner_overall),
           current_turn = -1, turn_deadline = NULL
     WHERE id = _game_id;

    -- Award pot to winner
    PERFORM public._domino_payout(_game_id, v_winner_overall);
    RETURN;
  END IF;

  -- Start new round (works for both: match nul and points mode without winner yet)
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
     SET state = st, current_turn = v_next_starter,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public._domino_end_round(uuid, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._domino_end_round(uuid, integer) TO authenticated, service_role;
