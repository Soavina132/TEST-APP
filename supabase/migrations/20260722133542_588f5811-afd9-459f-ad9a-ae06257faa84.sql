
-- 1. Poker: cartes privées inaccessibles en lecture directe
REVOKE SELECT (hole_cards) ON public.poker_players FROM anon, authenticated;

-- 2. Billiard games: restreindre visibilité
DROP POLICY IF EXISTS billiard_games_select ON public.billiard_games;
CREATE POLICY billiard_games_select ON public.billiard_games FOR SELECT TO authenticated
USING (
  (status IN ('open','playing') AND is_private = false)
  OR host_id = auth.uid()
  OR EXISTS (SELECT 1 FROM public.billiard_participants p WHERE p.game_id = billiard_games.id AND p.user_id = auth.uid())
  OR public.is_admin()
);

-- 3. Billiard participants: visibles uniquement si la partie l'est
DROP POLICY IF EXISTS billiard_participants_select ON public.billiard_participants;
CREATE POLICY billiard_participants_select ON public.billiard_participants FOR SELECT TO authenticated
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.billiard_games g
    WHERE g.id = billiard_participants.game_id
      AND (
        (g.status IN ('open','playing') AND g.is_private = false)
        OR g.host_id = auth.uid()
        OR EXISTS (SELECT 1 FROM public.billiard_participants p2 WHERE p2.game_id = g.id AND p2.user_id = auth.uid())
      )
  )
  OR public.is_admin()
);

-- 4. Poker games: restreindre aux parties publiques, participants ou admin
DROP POLICY IF EXISTS poker_games_read ON public.poker_games;
CREATE POLICY poker_games_read ON public.poker_games FOR SELECT TO authenticated
USING (
  (status IN ('open','playing') AND is_private = false)
  OR created_by = auth.uid()
  OR EXISTS (SELECT 1 FROM public.poker_players pp WHERE pp.game_id = poker_games.id AND pp.user_id = auth.uid())
  OR public.is_admin()
);

-- 5. Poker hand history: seuls les joueurs de la partie / admin
DROP POLICY IF EXISTS poker_hh_read ON public.poker_hand_history;
CREATE POLICY poker_hh_read ON public.poker_hand_history FOR SELECT TO authenticated
USING (
  EXISTS (SELECT 1 FROM public.poker_players pp WHERE pp.game_id = poker_hand_history.game_id AND pp.user_id = auth.uid())
  OR public.is_admin()
);

-- 6. player_game_stats: propriétaire ou admin
DROP POLICY IF EXISTS pgstats_select ON public.player_game_stats;
CREATE POLICY pgstats_select ON public.player_game_stats FOR SELECT TO authenticated
USING (user_id = auth.uid() OR public.is_admin());

-- 7. request_password_reset: réponse générique, aucune énumération de compte
CREATE OR REPLACE FUNCTION public.request_password_reset(_contact text, _type text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid;
  v_code text;
  v_norm text;
  v_existing public.password_reset_requests%ROWTYPE;
  v_generic jsonb := jsonb_build_object('status','pending','already',false,'message','Si un compte correspond, une demande a été créée.');
BEGIN
  IF _type NOT IN ('email','phone') THEN RETURN v_generic; END IF;
  v_norm := trim(coalesce(_contact,''));
  IF _type = 'email' THEN v_norm := lower(v_norm); END IF;
  IF length(v_norm) < 3 THEN RETURN v_generic; END IF;

  IF _type = 'email' THEN
    SELECT id INTO v_uid FROM public.profiles WHERE lower(email) = v_norm LIMIT 1;
  ELSE
    SELECT id INTO v_uid FROM public.profiles WHERE phone = v_norm LIMIT 1;
  END IF;

  IF v_uid IS NULL THEN
    RETURN v_generic;
  END IF;

  SELECT * INTO v_existing
  FROM public.password_reset_requests
  WHERE user_id = v_uid
    AND contact_type = _type
    AND status IN ('pending','sent')
    AND created_at > now() - interval '24 hours'
  ORDER BY created_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN v_generic;
  END IF;

  v_code := lpad((floor(random()*1000000))::int::text, 6, '0');

  INSERT INTO public.password_reset_requests(user_id, contact, contact_type, code, status)
  VALUES (v_uid, v_norm, _type, v_code, 'pending');

  RETURN v_generic;
END;
$function$;
