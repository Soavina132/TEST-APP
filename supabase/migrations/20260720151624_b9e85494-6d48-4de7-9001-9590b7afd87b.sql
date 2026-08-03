
CREATE TABLE IF NOT EXISTS public.tournament_payouts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id uuid NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  is_free boolean NOT NULL DEFAULT false,
  entry_fee numeric NOT NULL DEFAULT 0,
  players_count int NOT NULL DEFAULT 0,
  prize_pool numeric NOT NULL DEFAULT 0,
  commission_pct numeric NOT NULL DEFAULT 0,
  commission_amount numeric NOT NULL DEFAULT 0,
  winner_id uuid,
  winner_payout numeric NOT NULL DEFAULT 0,
  transaction_id uuid,
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(tournament_id)
);

GRANT SELECT ON public.tournament_payouts TO authenticated;
GRANT ALL ON public.tournament_payouts TO service_role;

ALTER TABLE public.tournament_payouts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins can view tournament payouts" ON public.tournament_payouts;
CREATE POLICY "Admins can view tournament payouts"
  ON public.tournament_payouts FOR SELECT TO authenticated
  USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "Winners can view their payout" ON public.tournament_payouts;
CREATE POLICY "Winners can view their payout"
  ON public.tournament_payouts FOR SELECT TO authenticated
  USING (winner_id = auth.uid());

CREATE INDEX IF NOT EXISTS idx_tournament_payouts_created ON public.tournament_payouts(created_at DESC);

CREATE OR REPLACE FUNCTION public._tournament_on_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_match public.tournament_matches%ROWTYPE;
  v_t public.tournaments%ROWTYPE;
  v_remaining int;
  v_winners uuid[];
  v_total int;
  m record;
  v_game_id uuid;
  v_first uuid;
  v_color text;
  v_slot int;
  v_name text;
  v_pid uuid;
  v_payout numeric;
  v_commission numeric;
  v_players_count int;
  v_tx_id uuid;
  v_top3 jsonb;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status = 'finished' THEN RETURN NEW; END IF;

  UPDATE public.tournament_matches
    SET status='finished', winner_id = NEW.winner_id, finished_at = now()
    WHERE id = v_match.id;

  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;
  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND user_id IS DISTINCT FROM NEW.winner_id
      AND eliminated_round IS NULL;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  SELECT array_agg(winner_id ORDER BY match_index) INTO v_winners
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND winner_id IS NOT NULL;
  v_total := COALESCE(array_length(v_winners,1),0);

  IF v_total <= 1 THEN
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
      SET status='finished', finished_at=now(), winner_id = v_winners[1], top3 = COALESCE(v_top3,'[]'::jsonb)
      WHERE id = v_t.id;

    SELECT count(*) INTO v_players_count FROM public.tournament_registrations WHERE tournament_id = v_t.id;

    v_payout := 0;
    v_commission := 0;
    v_tx_id := NULL;

    IF NOT v_t.is_free AND v_t.prize_pool > 0 THEN
      v_payout := v_t.prize_pool * (100 - v_t.commission_pct) / 100.0;
      v_commission := v_t.prize_pool - v_payout;
      UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_winners[1];
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_winners[1],'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name)
        RETURNING id INTO v_tx_id;
    END IF;

    INSERT INTO public.tournament_payouts(
      tournament_id, is_free, entry_fee, players_count,
      prize_pool, commission_pct, commission_amount,
      winner_id, winner_payout, transaction_id, note
    ) VALUES (
      v_t.id, v_t.is_free, COALESCE(v_t.entry_fee_ar,0), v_players_count,
      COALESCE(v_t.prize_pool,0), COALESCE(v_t.commission_pct,0), v_commission,
      v_winners[1], v_payout, v_tx_id,
      CASE WHEN v_t.is_free THEN 'Tournoi gratuit — aucun gain monétaire'
           WHEN v_t.prize_pool = 0 THEN 'Prize pool nul — pas de règlement'
           ELSE 'Règlement automatique' END
    )
    ON CONFLICT (tournament_id) DO NOTHING;

    RETURN NEW;
  END IF;

  UPDATE public.tournaments SET current_round = current_round + 1 WHERE id = v_t.id;
  PERFORM public._tournament_build_round(v_t.id, v_t.current_round + 1, v_winners);

  FOR m IN SELECT * FROM public.tournament_matches
           WHERE tournament_id = v_t.id AND round = v_t.current_round + 1 AND status = 'pending' ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_t.players_per_match, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
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

  RETURN NEW;
END $$;

INSERT INTO public.tournament_payouts(
  tournament_id, is_free, entry_fee, players_count,
  prize_pool, commission_pct, commission_amount,
  winner_id, winner_payout, transaction_id, note
)
SELECT
  t.id,
  t.is_free,
  COALESCE(t.entry_fee_ar,0),
  (SELECT count(*) FROM public.tournament_registrations r WHERE r.tournament_id = t.id),
  COALESCE(t.prize_pool,0),
  COALESCE(t.commission_pct,0),
  CASE WHEN t.is_free OR t.prize_pool = 0 THEN 0
       ELSE t.prize_pool - (t.prize_pool * (100 - t.commission_pct) / 100.0) END,
  t.winner_id,
  CASE WHEN t.is_free OR t.prize_pool = 0 OR t.winner_id IS NULL THEN 0
       ELSE t.prize_pool * (100 - t.commission_pct) / 100.0 END,
  (SELECT tx.id FROM public.transactions tx
     WHERE tx.ref_id = t.id AND tx.user_id = t.winner_id AND tx.type = 'win'
     ORDER BY tx.created_at DESC LIMIT 1),
  'Rétro-journalisation'
FROM public.tournaments t
WHERE t.status = 'finished' AND t.winner_id IS NOT NULL
ON CONFLICT (tournament_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_get_tournament_ledger(_tournament_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_payout public.tournament_payouts%ROWTYPE;
  v_winner_pseudo text;
  v_tx jsonb;
  v_expected_pool numeric;
  v_expected_commission numeric;
  v_expected_payout numeric;
  v_players int;
  v_consistent boolean;
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    RAISE EXCEPTION 'Accès refusé';
  END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tournament_id;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  SELECT * INTO v_payout FROM public.tournament_payouts WHERE tournament_id = _tournament_id;
  SELECT count(*) INTO v_players FROM public.tournament_registrations WHERE tournament_id = _tournament_id;
  SELECT pseudo INTO v_winner_pseudo FROM public.profiles WHERE id = v_t.winner_id;

  v_expected_pool := CASE WHEN v_t.is_free THEN 0 ELSE COALESCE(v_t.entry_fee_ar,0) * v_players END;
  v_expected_commission := CASE WHEN v_t.is_free THEN 0
                                ELSE v_expected_pool * COALESCE(v_t.commission_pct,0) / 100.0 END;
  v_expected_payout := v_expected_pool - v_expected_commission;

  SELECT jsonb_build_object(
    'id', tx.id, 'amount', tx.amount, 'type', tx.type, 'created_at', tx.created_at
  ) INTO v_tx
  FROM public.transactions tx
  WHERE tx.ref_id = _tournament_id AND tx.user_id = v_t.winner_id AND tx.type = 'win'
  ORDER BY tx.created_at DESC LIMIT 1;

  v_consistent := (
    v_payout.id IS NOT NULL
    AND ABS(COALESCE(v_payout.prize_pool,0) - COALESCE(v_t.prize_pool,0)) < 0.01
    AND ABS(COALESCE(v_payout.winner_payout,0) - v_expected_payout) < 0.01
    AND (v_t.is_free OR v_payout.transaction_id IS NOT NULL OR v_t.prize_pool = 0)
  );

  RETURN jsonb_build_object(
    'tournament', jsonb_build_object(
      'id', v_t.id, 'name', v_t.name, 'status', v_t.status,
      'is_free', v_t.is_free, 'entry_fee', v_t.entry_fee_ar,
      'commission_pct', v_t.commission_pct, 'prize_pool', v_t.prize_pool,
      'winner_id', v_t.winner_id, 'winner_pseudo', v_winner_pseudo,
      'finished_at', v_t.finished_at
    ),
    'players_count', v_players,
    'expected', jsonb_build_object(
      'prize_pool', v_expected_pool,
      'commission', v_expected_commission,
      'winner_payout', v_expected_payout
    ),
    'payout', CASE WHEN v_payout.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', v_payout.id,
      'prize_pool', v_payout.prize_pool,
      'commission_amount', v_payout.commission_amount,
      'winner_payout', v_payout.winner_payout,
      'transaction_id', v_payout.transaction_id,
      'note', v_payout.note,
      'created_at', v_payout.created_at
    ) END,
    'transaction', v_tx,
    'consistent', v_consistent
  );
END $$;

GRANT EXECUTE ON FUNCTION public.admin_get_tournament_ledger(uuid) TO authenticated;
