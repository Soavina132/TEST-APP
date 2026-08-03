
CREATE OR REPLACE FUNCTION public._tournament_on_game_finished()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_match public.tournament_matches%ROWTYPE;
  v_t public.tournaments%ROWTYPE;
  v_remaining int; v_winners uuid[]; v_total int;
  v_payout numeric; v_quals uuid[];
  v_third_id uuid;
  v_first_amt numeric; v_second_amt numeric; v_third_amt numeric; v_plat_amt numeric;
  v_prize numeric; dist jsonb;
  v_first_id uuid; v_second_id uuid;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status = 'finished' THEN RETURN NEW; END IF;

  IF TG_TABLE_NAME = 'ludo_games' THEN
    SELECT COALESCE(array_agg(user_id ORDER BY finish_rank), ARRAY[]::uuid[])
      INTO v_quals
      FROM public.ludo_participants
      WHERE game_id = NEW.id AND finish_rank IS NOT NULL AND user_id IS NOT NULL
      LIMIT v_match.qualifiers_count;
  ELSE
    v_quals := CASE WHEN NEW.winner_id IS NOT NULL THEN ARRAY[NEW.winner_id] ELSE ARRAY[]::uuid[] END;
  END IF;

  IF (v_quals IS NULL OR array_length(v_quals,1) IS NULL) AND NEW.winner_id IS NOT NULL THEN
    v_quals := ARRAY[NEW.winner_id];
  END IF;

  IF array_length(v_quals,1) > v_match.qualifiers_count THEN
    v_quals := v_quals[1 : v_match.qualifiers_count];
  END IF;

  UPDATE public.tournament_matches
    SET status='finished', winner_id = COALESCE(NEW.winner_id, v_quals[1]),
        qualifiers_ids = v_quals, finished_at = now()
    WHERE id = v_match.id;

  -- Matchs de poule : gérés par le système de poules (trigger dédié + pompe)
  IF COALESCE(v_match.phase,'final') = 'pool' THEN
    RETURN NEW;
  END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;

  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND NOT (user_id = ANY(COALESCE(v_quals, ARRAY[]::uuid[])))
      AND eliminated_round IS NULL;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round
      AND COALESCE(phase,'final') <> 'pool'
      AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round
      AND COALESCE(is_third_place,false) = true
  ) AND NOT EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round
      AND COALESCE(is_third_place,false) = false
  ) THEN
    UPDATE public.tournaments SET pending_shuffle = true WHERE id = v_t.id;
    RETURN NEW;
  END IF;

  SELECT array_agg(q ORDER BY match_index, ord) INTO v_winners
    FROM (
      SELECT match_index, ord, q
      FROM public.tournament_matches tm,
           LATERAL unnest(COALESCE(tm.qualifiers_ids, CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END))
             WITH ORDINALITY AS u(q, ord)
      WHERE tm.tournament_id = v_t.id AND tm.round = v_t.current_round
        AND COALESCE(tm.is_third_place,false) = false
        AND COALESCE(tm.phase,'final') <> 'pool'
        AND (tm.winner_id IS NOT NULL OR tm.qualifiers_ids IS NOT NULL)
    ) s;
  v_total := COALESCE(array_length(v_winners,1),0);

  IF v_total <= 1 THEN
    v_first_id := v_winners[1];

    SELECT (SELECT p FROM unnest(m.player_ids) p WHERE p <> m.winner_id LIMIT 1)
      INTO v_second_id
      FROM public.tournament_matches m
     WHERE m.tournament_id = v_t.id
       AND m.round = v_t.current_round
       AND COALESCE(m.is_third_place,false) = false
       AND m.is_bye = false
     ORDER BY m.finished_at DESC NULLS LAST
     LIMIT 1;

    SELECT winner_id INTO v_third_id
      FROM public.tournament_matches
     WHERE tournament_id = v_t.id
       AND COALESCE(is_third_place,false) = true
     ORDER BY finished_at DESC NULLS LAST
     LIMIT 1;

    v_prize := COALESCE(v_t.prize_pool, 0);
    dist := COALESCE(v_t.reward_distribution, '{"first":60,"second":20,"third":10,"platform":10}'::jsonb);

    IF v_t.rewards_paid_at IS NULL AND v_prize > 0 AND (v_second_id IS NOT NULL OR v_third_id IS NOT NULL) THEN
      v_first_amt  := ROUND(v_prize * COALESCE((dist->>'first')::numeric, 60)  / 100, 0);
      v_second_amt := ROUND(v_prize * COALESCE((dist->>'second')::numeric, 20) / 100, 0);
      v_third_amt  := ROUND(v_prize * COALESCE((dist->>'third')::numeric, 10)  / 100, 0);
      v_plat_amt   := v_prize - v_first_amt - v_second_amt - v_third_amt;

      IF v_first_id IS NOT NULL AND v_first_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_first_amt WHERE id = v_first_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_first_id, 'tournament_win', v_first_amt, v_t.id, '🥇 1er — Tournoi ' || COALESCE(v_t.name,''));
      END IF;
      IF v_second_id IS NOT NULL AND v_second_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_second_amt WHERE id = v_second_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_second_id, 'tournament_win', v_second_amt, v_t.id, '🥈 2e — Tournoi ' || COALESCE(v_t.name,''));
      END IF;
      IF v_third_id IS NOT NULL AND v_third_amt > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_third_amt WHERE id = v_third_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_third_id, 'tournament_win', v_third_amt, v_t.id, '🥉 3e — Tournoi ' || COALESCE(v_t.name,''));
      END IF;

      UPDATE public.tournaments
        SET status='finished', finished_at=now(), winner_id = v_first_id,
            podium = jsonb_build_object('first', v_first_id, 'second', v_second_id, 'third', v_third_id),
            rewards_paid_at = now(), platform_cut_ar = v_plat_amt,
            pending_shuffle = false, pending_final = false
        WHERE id = v_t.id;
    ELSE
      UPDATE public.tournaments
        SET status='finished', finished_at=now(), winner_id = v_first_id,
            podium = jsonb_build_object('first', v_first_id, 'second', v_second_id, 'third', v_third_id),
            pending_shuffle = false, pending_final = false
        WHERE id = v_t.id;

      IF v_first_id IS NOT NULL AND v_t.rewards_paid_at IS NULL AND v_prize > 0 AND NOT v_t.is_free THEN
        v_payout := v_prize * (100 - COALESCE(v_t.commission_pct,0)) / 100.0;
        UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_first_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_first_id,'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name);
        UPDATE public.tournaments SET rewards_paid_at = now() WHERE id = v_t.id;
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  UPDATE public.tournaments SET pending_shuffle = true WHERE id = v_t.id;
  RETURN NEW;
END $function$;

-- L'ancien lanceur de vagues ne doit pas toucher aux tournois en mode poules
CREATE OR REPLACE FUNCTION public.tournament_launch_pending_ludo()
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  t record; cur_wave int; v_launched int := 0; m record; v_need_assign boolean;
BEGIN
  FOR t IN
    SELECT id, current_round, ludo_next_wave_at, COALESCE(ludo_wave_delay_min,10) AS delay_min
      FROM public.tournaments
     WHERE status = 'running' AND game_slug = 'ludo'
       AND COALESCE(bracket_mode,'elimination') <> 'pools'
  LOOP
    SELECT EXISTS(
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = t.id AND round = t.current_round AND wave IS NULL
    ) INTO v_need_assign;
    IF v_need_assign THEN
      PERFORM public._tourn_assign_ludo_waves(t.id, t.current_round);
    END IF;

    SELECT COALESCE(MAX(wave), 0) INTO cur_wave
      FROM public.tournament_matches
     WHERE tournament_id = t.id AND round = t.current_round
       AND game_id IS NOT NULL AND is_bye = false;

    IF cur_wave = 0 THEN
      FOR m IN
        SELECT id FROM public.tournament_matches
         WHERE tournament_id = t.id AND round = t.current_round
           AND status = 'pending' AND game_id IS NULL AND is_bye = false
           AND wave = 1
         ORDER BY match_index
      LOOP
        BEGIN
          PERFORM public._tourn_launch_ludo_match(m.id);
          v_launched := v_launched + 1;
        EXCEPTION WHEN OTHERS THEN NULL; END;
      END LOOP;
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = t.id AND round = t.current_round AND wave = cur_wave
         AND status NOT IN ('finished','forfeit','cancelled')
    ) THEN CONTINUE; END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.tournament_matches
       WHERE tournament_id = t.id AND round = t.current_round AND wave = cur_wave + 1
         AND status = 'pending' AND game_id IS NULL AND is_bye = false
    ) THEN CONTINUE; END IF;

    IF t.ludo_next_wave_at IS NULL THEN
      UPDATE public.tournaments
         SET ludo_next_wave_at = now() + (t.delay_min || ' minutes')::interval
       WHERE id = t.id;
      CONTINUE;
    END IF;

    IF t.ludo_next_wave_at > now() THEN CONTINUE; END IF;

    FOR m IN
      SELECT id FROM public.tournament_matches
       WHERE tournament_id = t.id AND round = t.current_round
         AND status = 'pending' AND game_id IS NULL AND is_bye = false
         AND wave = cur_wave + 1
       ORDER BY match_index
    LOOP
      BEGIN
        PERFORM public._tourn_launch_ludo_match(m.id);
        v_launched := v_launched + 1;
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
    UPDATE public.tournaments SET ludo_next_wave_at = NULL WHERE id = t.id;
  END LOOP;
  RETURN v_launched;
END $function$;
