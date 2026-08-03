-- ============================================================
-- Migration : Système d'interventions admin + réclamations
-- ============================================================

-- 1. Table des réclamations joueurs
CREATE TABLE IF NOT EXISTS public.tournament_claims (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id   uuid        REFERENCES public.tournaments(id) ON DELETE SET NULL,
  match_id        uuid        REFERENCES public.tournament_matches(id) ON DELETE SET NULL,
  claimant_id     uuid        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category        text        NOT NULL DEFAULT 'general',
  -- 'no_show','disconnect','result_dispute','payment','cheating','technical','other'
  description     text        NOT NULL,
  status          text        NOT NULL DEFAULT 'pending',
  -- 'pending','reviewing','resolved','rejected'
  admin_comment   text,
  resolved_by     uuid        REFERENCES public.profiles(id) ON DELETE SET NULL,
  resolved_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.tournament_claims ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Players can create claims" ON public.tournament_claims
  FOR INSERT WITH CHECK (auth.uid() = claimant_id);

CREATE POLICY "Players see own claims" ON public.tournament_claims
  FOR SELECT USING (
    auth.uid() = claimant_id OR
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );

CREATE POLICY "Admins manage claims" ON public.tournament_claims
  FOR ALL USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_admin = true)
  );

-- 2. Colonne suspended_until sur profiles (si pas encore présente)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS suspended_until timestamptz,
  ADD COLUMN IF NOT EXISTS suspension_reason text,
  ADD COLUMN IF NOT EXISTS warning_count int NOT NULL DEFAULT 0;

-- 3. RPC : admin_get_intervention_dashboard
CREATE OR REPLACE FUNCTION public.admin_get_intervention_dashboard()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_result jsonb;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT jsonb_build_object(
    'open_tournaments',   (SELECT count(*) FROM public.tournaments WHERE status = 'open'),
    'running_tournaments',(SELECT count(*) FROM public.tournaments WHERE status = 'running'),
    'pending_matches',    (SELECT count(*) FROM public.tournament_matches WHERE status = 'pending'),
    'running_matches',    (SELECT count(*) FROM public.tournament_matches WHERE status = 'running'),
    'open_claims',        (SELECT count(*) FROM public.tournament_claims WHERE status IN ('pending','reviewing')),
    'suspended_players',  (SELECT count(*) FROM public.profiles WHERE suspended_until > now()),
    'banned_players',     (SELECT count(*) FROM public.profiles WHERE banned = true),
    'pending_payouts',    (SELECT COALESCE(sum(prize_pool),0) FROM public.tournaments WHERE status = 'finished' AND winner_id IS NULL),
    'recent_claims', (
      SELECT jsonb_agg(row_to_json(c) ORDER BY c.created_at DESC)
      FROM (
        SELECT tc.id, tc.category, tc.status, tc.description, tc.created_at,
               p.pseudo AS claimant_pseudo,
               t.name AS tournament_name
        FROM public.tournament_claims tc
        LEFT JOIN public.profiles p ON p.id = tc.claimant_id
        LEFT JOIN public.tournaments t ON t.id = tc.tournament_id
        WHERE tc.status IN ('pending','reviewing')
        ORDER BY tc.created_at DESC LIMIT 10
      ) c
    ),
    'stuck_matches', (
      SELECT jsonb_agg(row_to_json(m) ORDER BY m.join_deadline ASC)
      FROM (
        SELECT tm.id, tm.round, tm.status, tm.join_deadline, tm.player_ids,
               t.name AS tournament_name, t.id AS tournament_id
        FROM public.tournament_matches tm
        JOIN public.tournaments t ON t.id = tm.tournament_id
        WHERE tm.status = 'pending'
          AND tm.join_deadline IS NOT NULL
          AND tm.join_deadline < now() + interval '10 minutes'
          AND tm.is_bye = false
        ORDER BY tm.join_deadline ASC
        LIMIT 20
      ) m
    )
  ) INTO v_result;

  RETURN v_result;
END;
$$;

-- 4. RPC : admin_forfeit_match_player (victoire par forfait)
CREATE OR REPLACE FUNCTION public.admin_forfeit_match_player(
  _mid    uuid,
  _loser_id uuid,   -- joueur qui perd par forfait
  _reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m          record;
  v_winner   uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.status IN ('finished','cancelled') THEN RAISE EXCEPTION 'Match déjà terminé ou annulé'; END IF;

  SELECT u INTO v_winner FROM unnest(m.player_ids) u WHERE u <> _loser_id LIMIT 1;
  IF v_winner IS NULL THEN RAISE EXCEPTION 'Impossible de déterminer le vainqueur'; END IF;

  UPDATE public.tournament_matches
    SET status = 'forfeit', winner_id = v_winner
    WHERE id = _mid;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'forfeit_match_player', _loser_id,
      jsonb_build_object('match_id', _mid, 'winner_id', v_winner, 'reason', _reason));
END;
$$;

-- 5. RPC : admin_override_match_winner (corriger le vainqueur)
CREATE OR REPLACE FUNCTION public.admin_override_match_winner(
  _mid       uuid,
  _winner_id uuid,
  _reason    text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  m          record;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF NOT (_winner_id = ANY(m.player_ids)) THEN RAISE EXCEPTION 'Ce joueur n''est pas dans ce match'; END IF;

  UPDATE public.tournament_matches
    SET status = 'finished', winner_id = _winner_id
    WHERE id = _mid;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'override_match_winner', _winner_id,
      jsonb_build_object('match_id', _mid, 'old_winner', m.winner_id, 'new_winner', _winner_id, 'reason', _reason));
END;
$$;

-- 6. RPC : admin_cancel_tournament_match (annuler un match)
CREATE OR REPLACE FUNCTION public.admin_cancel_tournament_match(
  _mid    uuid,
  _reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  UPDATE public.tournament_matches
    SET status = 'cancelled', winner_id = NULL
    WHERE id = _mid AND status NOT IN ('cancelled');

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'cancel_match', NULL,
      jsonb_build_object('match_id', _mid, 'reason', _reason));
END;
$$;

-- 7. RPC : admin_manual_payout (envoi manuel de gains)
CREATE OR REPLACE FUNCTION public.admin_manual_payout(
  _uid    uuid,
  _amount numeric,
  _reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  IF _amount <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;

  UPDATE public.profiles SET balance_ar = balance_ar + _amount WHERE id = _uid;
  INSERT INTO public.transactions(user_id, type, amount, note)
    VALUES (_uid, 'admin_payout', _amount, _reason);
  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'manual_payout', _uid,
      jsonb_build_object('amount', _amount, 'reason', _reason));
END;
$$;

-- 8. RPC : admin_suspend_player
CREATE OR REPLACE FUNCTION public.admin_suspend_player(
  _uid          uuid,
  _hours        int,    -- 0 = lever la suspension
  _reason       text,
  _add_warning  boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
  v_until timestamptz;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  v_until := CASE WHEN _hours > 0 THEN now() + (_hours || ' hours')::interval ELSE NULL END;

  UPDATE public.profiles
    SET suspended_until    = v_until,
        suspension_reason  = CASE WHEN _hours > 0 THEN _reason ELSE NULL END,
        warning_count      = CASE WHEN _add_warning THEN warning_count + 1 ELSE warning_count END
    WHERE id = _uid;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, CASE WHEN _hours > 0 THEN 'suspend_player' ELSE 'unsuspend_player' END, _uid,
      jsonb_build_object('hours', _hours, 'reason', _reason, 'until', v_until));
END;
$$;

-- 9. RPC : admin_resolve_claim
CREATE OR REPLACE FUNCTION public.admin_resolve_claim(
  _cid      uuid,
  _status   text,   -- 'resolved' | 'rejected' | 'reviewing'
  _comment  text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  UPDATE public.tournament_claims
    SET status        = _status,
        admin_comment = _comment,
        resolved_by   = CASE WHEN _status IN ('resolved','rejected') THEN v_uid ELSE NULL END,
        resolved_at   = CASE WHEN _status IN ('resolved','rejected') THEN now() ELSE NULL END
    WHERE id = _cid;

  INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
    VALUES (v_uid, 'resolve_claim', NULL,
      jsonb_build_object('claim_id', _cid, 'status', _status, 'comment', _comment));
END;
$$;

-- 10. RPC : player_submit_claim (joueur soumet une réclamation)
CREATE OR REPLACE FUNCTION public.player_submit_claim(
  _tournament_id uuid,
  _match_id      uuid,
  _category      text,
  _description   text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
BEGIN
  IF length(trim(_description)) < 10 THEN
    RAISE EXCEPTION 'La description est trop courte';
  END IF;

  -- Anti-spam : max 3 réclamations ouvertes par joueur
  IF (SELECT count(*) FROM public.tournament_claims
      WHERE claimant_id = v_uid AND status IN ('pending','reviewing')) >= 3 THEN
    RAISE EXCEPTION 'Vous avez trop de réclamations en attente';
  END IF;

  INSERT INTO public.tournament_claims(tournament_id, match_id, claimant_id, category, description)
    VALUES (_tournament_id, _match_id, v_uid, _category, _description)
    RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- 11. Index
CREATE INDEX IF NOT EXISTS idx_claims_status ON public.tournament_claims(status);
CREATE INDEX IF NOT EXISTS idx_claims_claimant ON public.tournament_claims(claimant_id);
CREATE INDEX IF NOT EXISTS idx_profiles_suspended ON public.profiles(suspended_until) WHERE suspended_until IS NOT NULL;
