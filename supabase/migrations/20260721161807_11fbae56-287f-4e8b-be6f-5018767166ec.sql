
-- Colonne d'attente de mélange
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS pending_shuffle boolean NOT NULL DEFAULT false;

-- ── get_tournament_detail enrichi ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_tournament_detail(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t),
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', r.user_id, 'pseudo', p.pseudo, 'avatar_url', p.avatar_url,
        'eliminated_round', r.eliminated_round, 'final_position', r.final_position
      ) ORDER BY r.registered_at)
      FROM public.tournament_registrations r
      LEFT JOIN public.profiles p ON p.id = r.user_id
      WHERE r.tournament_id = t.id
    ), '[]'::jsonb),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'round', m.round, 'match_index', m.match_index,
        'player_ids', m.player_ids, 'status', m.status,
        'game_id', m.game_id, 'winner_id', m.winner_id, 'finished_at', m.finished_at,
        'is_bye', m.is_bye, 'qualifiers_count', m.qualifiers_count,
        'qualifiers_ids', m.qualifiers_ids, 'admin_notes', m.admin_notes,
        'auto_start_at', m.auto_start_at
      ) ORDER BY m.round, m.match_index)
      FROM public.tournament_matches m WHERE m.tournament_id = t.id
    ), '[]'::jsonb)
  ) INTO v
  FROM public.tournaments t WHERE t.id = _tid;
  RETURN v;
END $$;

-- ── Trigger modifié : plus d'enchainement automatique ────────────────
CREATE OR REPLACE FUNCTION public._tournament_on_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_match public.tournament_matches%ROWTYPE;
  v_t public.tournaments%ROWTYPE;
  v_remaining int; v_winners uuid[]; v_total int;
  v_payout numeric; v_top3 jsonb; v_quals uuid[];
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

  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;

  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND NOT (user_id = ANY(COALESCE(v_quals, ARRAY[]::uuid[])))
      AND eliminated_round IS NULL;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  -- Collecte des qualifiés
  SELECT array_agg(q ORDER BY match_index, ord) INTO v_winners
    FROM (
      SELECT match_index, ord, q
      FROM public.tournament_matches tm,
           LATERAL unnest(COALESCE(tm.qualifiers_ids, CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END))
             WITH ORDINALITY AS u(q, ord)
      WHERE tm.tournament_id = v_t.id AND tm.round = v_t.current_round
        AND (tm.winner_id IS NOT NULL OR tm.qualifiers_ids IS NOT NULL)
    ) s;
  v_total := COALESCE(array_length(v_winners,1),0);

  IF v_total <= 1 THEN
    -- Finaliser le tournoi
    v_top3 := '[]'::jsonb;
    SELECT jsonb_agg(jsonb_build_object('user_id', user_id, 'eliminated_round', eliminated_round)
                     ORDER BY (CASE WHEN user_id = v_winners[1] THEN 999999 ELSE eliminated_round END) DESC) INTO v_top3
      FROM (
        SELECT user_id, COALESCE(eliminated_round, 999999) as eliminated_round
          FROM public.tournament_registrations
          WHERE tournament_id = v_t.id
          ORDER BY (CASE WHEN user_id = v_winners[1] THEN 999999 ELSE eliminated_round END) DESC NULLS LAST
          LIMIT 3
      ) s;

    UPDATE public.tournaments
      SET status='finished', finished_at=now(), winner_id = v_winners[1],
          top3 = COALESCE(v_top3,'[]'::jsonb), pending_shuffle = false
      WHERE id = v_t.id;

    IF NOT v_t.is_free AND v_t.prize_pool > 0 THEN
      v_payout := v_t.prize_pool * (100 - v_t.commission_pct) / 100.0;
      UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_winners[1];
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_winners[1],'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name);
    END IF;
    RETURN NEW;
  END IF;

  -- Sinon : on attend le mélange admin
  UPDATE public.tournaments SET pending_shuffle = true WHERE id = v_t.id;
  RETURN NEW;
END $$;

-- ── RPC : admin mélange et lance le round suivant ────────────────────
CREATE OR REPLACE FUNCTION public.admin_tournament_shuffle_next_round(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_winners uuid[]; v_shuffled uuid[]; v_total int;
  v_next_round int;
  m record; v_game_id uuid; v_first uuid; v_color text;
  v_slot int; v_name text; v_pid uuid; v_size int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;
  IF NOT v_t.pending_shuffle THEN RAISE EXCEPTION 'Aucun round en attente de mélange'; END IF;

  -- Vérif: tous les matchs du round courant sont finis
  IF EXISTS (
    SELECT 1 FROM public.tournament_matches
    WHERE tournament_id = _tid AND round = v_t.current_round
      AND status NOT IN ('finished','bye')
  ) THEN
    RAISE EXCEPTION 'Certains matchs du round ne sont pas terminés';
  END IF;

  -- Récupère les qualifiés du round courant
  SELECT array_agg(q) INTO v_winners
    FROM public.tournament_matches tm,
         LATERAL unnest(COALESCE(tm.qualifiers_ids,
                                 CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END)) AS q
    WHERE tm.tournament_id = _tid AND tm.round = v_t.current_round;

  v_total := COALESCE(array_length(v_winners,1),0);
  IF v_total <= 1 THEN RAISE EXCEPTION 'Pas assez de qualifiés pour un round suivant'; END IF;

  -- Mélange aléatoire
  SELECT array_agg(uid ORDER BY random()) INTO v_shuffled FROM unnest(v_winners) AS uid;

  v_next_round := v_t.current_round + 1;

  -- Passe au round suivant et lève le flag
  UPDATE public.tournaments
    SET current_round = v_next_round, pending_shuffle = false
    WHERE id = _tid;

  -- Construit les groupes du round suivant
  PERFORM public._tournament_build_round(_tid, v_next_round, v_shuffled);

  -- Crée les parties Ludo pour chaque match pending
  FOR m IN SELECT * FROM public.tournament_matches
           WHERE tournament_id = _tid AND round = v_next_round AND status = 'pending'
           ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    v_size := GREATEST(array_length(m.player_ids,1), 2);
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_size, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
      RETURNING id INTO v_game_id;
    v_slot := 0;
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
        VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
      v_slot := v_slot + 1;
    END LOOP;
    UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = m.id;
  END LOOP;

  -- Log admin (si table présente)
  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_id, new_value)
      VALUES (auth.uid(), 'tournament_shuffle_round', _tid,
              jsonb_build_object('round', v_next_round, 'players', v_shuffled));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'round', v_next_round, 'players', v_shuffled);
END $$;

GRANT EXECUTE ON FUNCTION public.admin_tournament_shuffle_next_round(uuid) TO authenticated;
