
CREATE OR REPLACE FUNCTION public._tournament_advance_round_core(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  trn            record;
  rec            record;
  v_qual_per     int;
  v_qc_match     int;
  v_next_round   int;
  v_count        int;
  v_ids          uuid[] := '{}';
  v_src          uuid[] := '{}';
  v_ordered_ids  uuid[];
  v_ordered_src  uuid[];
  i              int;
  j              int;
  tmp_uid        uuid;
  tmp_src        uuid;
  v_final        record;
  v_third_match  record;
  v_first_id     uuid;
  v_second_id    uuid;
  v_third_id     uuid;
  v_prize        numeric;
  dist           jsonb;
  v_first_amt    numeric;
  v_second_amt   numeric;
  v_third_amt    numeric;
  v_plat_amt     numeric;
  v_pair_end     int;
  v_tail_start   int;
  v_tail_len     int;
  v_losers       uuid[];
  lm             record;
  lp             uuid;
BEGIN
  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid
      AND round = trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled')
      AND is_bye = false
  ) THEN
    RAISE EXCEPTION 'Des matchs du round actuel ne sont pas encore terminés';
  END IF;

  v_qual_per := GREATEST(COALESCE(trn.qualifiers_per_table, 2), 1);

  FOR rec IN
    SELECT m.id AS mid, m.player_ids, m.winner_id, m.match_rankings, m.is_bye,
           m.qualifiers_count,
           array_length(m.player_ids, 1) AS n
    FROM public.tournament_matches m
    WHERE m.tournament_id = _tid
      AND m.round = trn.current_round
      AND m.status IN ('finished','forfeit')
      AND COALESCE(m.is_third_place, false) = false
  LOOP
    IF rec.is_bye OR COALESCE(rec.n, 2) <= 2 THEN
      IF rec.winner_id IS NOT NULL THEN
        v_ids := v_ids || rec.winner_id;
        v_src := v_src || rec.mid;
      END IF;
    ELSE
      v_qc_match := GREATEST(LEAST(COALESCE(rec.qualifiers_count, v_qual_per), rec.n - 1), 1);
      IF rec.match_rankings IS NOT NULL AND rec.match_rankings <> '{}'::jsonb THEN
        FOR i IN 1..v_qc_match LOOP
          IF rec.match_rankings ? i::text THEN
            v_ids := v_ids || (rec.match_rankings ->> i::text)::uuid;
            v_src := v_src || rec.mid;
          END IF;
        END LOOP;
      ELSIF rec.winner_id IS NOT NULL THEN
        v_ids := v_ids || rec.winner_id;
        v_src := v_src || rec.mid;
      END IF;
    END IF;
  END LOOP;

  v_count := COALESCE(array_length(v_ids, 1), 0);

  IF v_count <= 1 THEN
    v_first_id := v_ids[1];
    SELECT * INTO v_final
      FROM public.tournament_matches
     WHERE tournament_id = _tid
       AND round = trn.current_round
       AND COALESCE(is_third_place, false) = false
       AND is_bye = false
     ORDER BY finished_at DESC NULLS LAST
     LIMIT 1;
    IF v_final.id IS NOT NULL AND v_first_id IS NOT NULL THEN
      SELECT p INTO v_second_id
        FROM unnest(v_final.player_ids) p
       WHERE p <> v_first_id
       LIMIT 1;
    END IF;
    SELECT * INTO v_third_match
      FROM public.tournament_matches
     WHERE tournament_id = _tid
       AND COALESCE(is_third_place, false) = true
     ORDER BY finished_at DESC NULLS LAST
     LIMIT 1;
    IF v_third_match.id IS NOT NULL THEN
      v_third_id := v_third_match.winner_id;
    END IF;

    v_prize := COALESCE(trn.prize_pool, 0);
    dist    := COALESCE(trn.reward_distribution,
                        '{"first":60,"second":20,"third":10,"platform":10}'::jsonb);

    IF trn.rewards_paid_at IS NULL AND v_prize > 0 AND
       (v_second_id IS NOT NULL OR v_third_id IS NOT NULL) THEN
      v_first_amt  := ROUND(v_prize * COALESCE((dist->>'first')::numeric, 60)  / 100, 0);
      v_second_amt := ROUND(v_prize * COALESCE((dist->>'second')::numeric, 20) / 100, 0);
      v_third_amt  := ROUND(v_prize * COALESCE((dist->>'third')::numeric, 10)  / 100, 0);
      v_plat_amt   := v_prize - v_first_amt - v_second_amt - v_third_amt;

      IF v_first_id IS NOT NULL AND v_first_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_first_amt WHERE id = v_first_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_first_id, 'tournament_win', v_first_amt, _tid, '🥇 1er — Tournoi ' || COALESCE(trn.name,''));
      END IF;
      IF v_second_id IS NOT NULL AND v_second_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_second_amt WHERE id = v_second_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_second_id, 'tournament_win', v_second_amt, _tid, '🥈 2e — Tournoi ' || COALESCE(trn.name,''));
      END IF;
      IF v_third_id IS NOT NULL AND v_third_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_third_amt WHERE id = v_third_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_third_id, 'tournament_win', v_third_amt, _tid, '🥉 3e — Tournoi ' || COALESCE(trn.name,''));
      END IF;
    END IF;

    UPDATE public.tournaments
      SET status         = 'finished',
          winner_id      = v_first_id,
          runner_up_id   = v_second_id,
          third_place_id = v_third_id,
          finished_at    = now(),
          rewards_paid_at = COALESCE(rewards_paid_at, now())
      WHERE id = _tid;

    RETURN jsonb_build_object('ok', true, 'finished', true,
      'winner_id', v_first_id, 'runner_up_id', v_second_id, 'third_place_id', v_third_id);
  END IF;

  WITH shuffled AS (
    SELECT unnest(v_ids) AS uid, unnest(v_src) AS src, random() AS r
  ),
  grouped AS (
    SELECT uid, src, row_number() OVER (PARTITION BY src ORDER BY r) AS grp
    FROM shuffled
  )
  SELECT array_agg(uid ORDER BY grp, r), array_agg(src ORDER BY grp, r)
    INTO v_ordered_ids, v_ordered_src
    FROM grouped;

  i := 1;
  WHILE i < v_count LOOP
    IF v_ordered_src[i] = v_ordered_src[i + 1] THEN
      j := i + 2;
      WHILE j <= v_count LOOP
        IF v_ordered_src[j] <> v_ordered_src[i] THEN
          tmp_uid := v_ordered_ids[i + 1]; tmp_src := v_ordered_src[i + 1];
          v_ordered_ids[i + 1] := v_ordered_ids[j]; v_ordered_src[i + 1] := v_ordered_src[j];
          v_ordered_ids[j] := tmp_uid; v_ordered_src[j] := tmp_src;
          EXIT;
        END IF;
        j := j + 1;
      END LOOP;
    END IF;
    i := i + 2;
  END LOOP;

  v_next_round := trn.current_round + 1;
  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;

  IF v_count % 2 = 1 AND v_count >= 3 THEN
    v_pair_end   := v_count - 3;
    v_tail_start := v_count - 2;
    v_tail_len   := 3;
  ELSE
    v_pair_end   := v_count;
    v_tail_start := 0;
    v_tail_len   := 0;
  END IF;

  i := 1;
  WHILE i + 1 <= v_pair_end LOOP
    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, qualifiers_count)
      VALUES (_tid, v_next_round, ARRAY[v_ordered_ids[i], v_ordered_ids[i + 1]], 'pending', false, 1);
    i := i + 2;
  END LOOP;

  IF v_tail_len = 3 THEN
    INSERT INTO public.tournament_matches(tournament_id, round, player_ids, status, is_bye, qualifiers_count)
      VALUES (
        _tid, v_next_round,
        ARRAY[v_ordered_ids[v_tail_start], v_ordered_ids[v_tail_start + 1], v_ordered_ids[v_tail_start + 2]],
        'pending', false, 1
      );
  END IF;

  -- ═══════════════════════════════════════════════════════════════════════
  -- Petite finale — gère aussi les forfaits en demi-finale
  --   • 2 perdants réels → match is_third_place à jouer
  --   • 1 seul perdant   → 3e place attribuée automatiquement (walkover)
  --   • 0 perdant         → pas de 3e place
  -- Un perdant "réel" = joueur du player_ids qui n'est pas le winner_id.
  -- Fonctionne pour finished ET forfeit tant que winner_id est renseigné.
  -- ═══════════════════════════════════════════════════════════════════════
  IF v_count = 2 AND COALESCE(trn.players_per_match, 2) = 2 THEN
    v_losers := '{}';
    FOR lm IN
      SELECT player_ids, winner_id, array_length(player_ids,1) AS n, status
        FROM public.tournament_matches
       WHERE tournament_id = _tid
         AND round = trn.current_round
         AND status IN ('finished','forfeit')
         AND COALESCE(is_bye,false) = false
         AND COALESCE(is_third_place,false) = false
    LOOP
      -- On a besoin d'un vainqueur ET d'au moins 2 joueurs pour extraire un perdant
      IF COALESCE(lm.n,0) >= 2 AND lm.winner_id IS NOT NULL THEN
        FOREACH lp IN ARRAY lm.player_ids LOOP
          IF lp IS NOT NULL AND lp <> lm.winner_id THEN
            v_losers := v_losers || lp;
          END IF;
        END LOOP;
      END IF;
    END LOOP;

    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = _tid
         AND round = v_next_round
         AND COALESCE(is_third_place,false) = true
    ) THEN
      IF COALESCE(array_length(v_losers,1),0) >= 2 THEN
        -- Petite finale normale
        INSERT INTO public.tournament_matches(
          tournament_id, round, player_ids, status, is_bye,
          qualifiers_count, is_third_place
        ) VALUES (
          _tid, v_next_round, ARRAY[v_losers[1], v_losers[2]],
          'pending', false, 1, true
        );
      ELSIF COALESCE(array_length(v_losers,1),0) = 1 THEN
        -- Un seul perdant : 3e place attribuée par walkover
        INSERT INTO public.tournament_matches(
          tournament_id, round, player_ids, status, is_bye,
          qualifiers_count, is_third_place, winner_id, finished_at,
          winner_source, admin_notes
        ) VALUES (
          _tid, v_next_round, ARRAY[v_losers[1]],
          'finished', false, 1, true, v_losers[1], now(),
          'walkover', 'Petite finale attribuée automatiquement (adversaire manquant)'
        );
      END IF;
    END IF;
  END IF;

  IF trn.game_slug = 'ludo' THEN
    BEGIN
      PERFORM public._tourn_assign_ludo_waves(_tid, v_next_round);
      PERFORM public.tournament_launch_pending_ludo();
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  RETURN jsonb_build_object(
    'ok', true, 'finished', false,
    'next_round', v_next_round,
    'qualifiers', v_count,
    'triple_table', v_tail_len = 3,
    'third_place_created', v_count = 2 AND COALESCE(trn.players_per_match,2) = 2
  );
END;
$function$;
