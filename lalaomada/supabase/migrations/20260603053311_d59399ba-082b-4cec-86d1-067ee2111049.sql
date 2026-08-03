
-- 1. Config: T1/T2 thresholds
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS afk_t1_max int NOT NULL DEFAULT 2,
  ADD COLUMN IF NOT EXISTS afk_t2_max int NOT NULL DEFAULT 2;

-- 2. AFK check uses separate T1/T2 thresholds
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_t1 int; v_t2 int; v_max1 int; v_max2 int; v_enabled boolean;
  v_uid uuid; v_isbot boolean; v_winner uuid;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id=1;
  IF NOT COALESCE(v_enabled,true) THEN RETURN; END IF;
  SELECT afk_t1, afk_t2, user_id, is_bot INTO v_t1, v_t2, v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=_slot;
  IF v_isbot THEN RETURN; END IF;
  IF v_t1 >= COALESCE(v_max1,2) OR v_t2 >= COALESCE(v_max2,2) THEN
    UPDATE public.ludo_participants SET forfeited=true WHERE game_id=_game_id AND slot=_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Exclusion AFK (T1='||v_t1||' T2='||v_t2||')');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN PERFORM public.finish_game(_game_id, v_winner); END IF;
  END IF;
END $$;

-- 3. ludo_check_timeout: increment T1 + reset T2 when timing out without rolling
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;

  -- if must_move=true → T2 was already incremented in ludo_roll's no-move path
  -- here: must_move=false → player didn't roll within delay → T1++
  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  -- if must_move=true but timeout (player didn't pick a pawn), count T2 here only if a move was possible
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END $$;

-- 4. Allow admin to play: remove is_admin() guards from create/join/find
CREATE OR REPLACE FUNCTION public.create_game(_max_players integer, _stake numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT; v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), v_code)
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    VALUES (v_game_id, v_uid, 0, 'red', v_name);
  RETURN v_game_id;
END $$;

CREATE OR REPLACE FUNCTION public.create_private_game(_max_players integer, _stake numeric, _mode text DEFAULT 'classic'::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT; v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), v_code, TRUE, COALESCE(_mode,'classic'))
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie privée');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    VALUES (v_game_id, v_uid, 0, 'red', v_name);
  RETURN v_game_id;
END $$;

CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN; v_name text;
  v_colors_2 TEXT[] := ARRAY['red','yellow'];
  v_colors_3 TEXT[] := ARRAY['red','green','yellow'];
  v_colors_4 TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.cleanup_stale_open_games();
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, pseudo INTO v_banned, v_name FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count;
  v_color := CASE v_game.max_players
    WHEN 2 THEN v_colors_2[v_slot+1]
    WHEN 3 THEN v_colors_3[v_slot+1]
    ELSE v_colors_4[v_slot+1] END;
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    VALUES (_game_id, v_uid, v_slot, v_color, v_name);
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (v_uid,'stake',-v_game.stake,_game_id,'Mise rejoindre partie');
END $$;

-- 5. Rename participant (admin must rename before each game)
CREATE OR REPLACE FUNCTION public.ludo_set_display_name(_game_id uuid, _name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _name IS NULL OR length(trim(_name)) < 2 THEN RAISE EXCEPTION 'Nom invalide'; END IF;
  UPDATE public.ludo_participants
    SET display_name = trim(_name)
    WHERE game_id=_game_id AND user_id=v_uid;
END $$;

-- 6. Auto-cleanup stale open games (>2 min, no game started)
CREATE OR REPLACE FUNCTION public.cleanup_stale_open_games()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g RECORD; p RECORD; v_count int := 0;
BEGIN
  FOR g IN
    SELECT * FROM public.ludo_games
    WHERE status='open' AND created_at < now() - interval '2 minutes'
  LOOP
    FOR p IN SELECT user_id FROM public.ludo_participants
             WHERE game_id=g.id AND user_id IS NOT NULL
    LOOP
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (p.user_id,'refund',g.stake,g.id,'Partie expirée (>2 min sans démarrage)');
    END LOOP;
    DELETE FROM public.ludo_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;

-- Hook cleanup into list_public_open_games
CREATE OR REPLACE FUNCTION public.list_public_open_games()
RETURNS TABLE(id uuid, max_players integer, stake numeric, pot numeric, room_code text, players_count integer, created_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Note: cleanup is called from create/join paths (cleanup_stale_open_games is volatile)
  RETURN QUERY
    SELECT g.id, g.max_players, g.stake, g.pot, g.room_code,
      (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
      g.created_at
    FROM public.ludo_games g
    WHERE g.status='open' AND g.is_private=false
      AND g.created_at > now() - interval '2 minutes'
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) > 0
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players
    ORDER BY g.created_at DESC;
END $$;

-- 7. Admin actions on games
CREATE OR REPLACE FUNCTION public.admin_delete_game(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.ludo_games%ROWTYPE; p RECORD;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  -- refund all human participants their stake
  FOR p IN SELECT user_id FROM public.ludo_participants
           WHERE game_id=_game_id AND user_id IS NOT NULL AND is_bot=false
  LOOP
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (p.user_id,'refund',g.stake,g.id,'Partie supprimée par l''admin');
  END LOOP;
  INSERT INTO public.admin_logs(admin_id, action, target_user_id, old_value)
    VALUES (auth.uid(), 'admin_delete_game', g.host_id, to_jsonb(g));
  DELETE FROM public.ludo_games WHERE id=_game_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_force_finish_game(_game_id uuid, _winner_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.ludo_games%ROWTYPE; p RECORD;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status = 'finished' THEN RAISE EXCEPTION 'Déjà terminée'; END IF;

  IF _winner_id IS NOT NULL THEN
    PERFORM public.finish_game(_game_id, _winner_id);
  ELSE
    -- refund all human participants
    FOR p IN SELECT user_id FROM public.ludo_participants
             WHERE game_id=_game_id AND user_id IS NOT NULL AND is_bot=false
    LOOP
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (p.user_id,'refund',g.stake,g.id,'Partie annulée par l''admin');
    END LOOP;
    UPDATE public.ludo_games SET status='finished', finished_at=now(), winner_id=NULL WHERE id=_game_id;
  END IF;
  INSERT INTO public.admin_logs(admin_id, action, target_user_id)
    VALUES (auth.uid(), 'admin_force_finish_game', _winner_id);
END $$;

CREATE OR REPLACE FUNCTION public.admin_refund_game(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.ludo_games%ROWTYPE; p RECORD;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  FOR p IN SELECT user_id FROM public.ludo_participants
           WHERE game_id=_game_id AND user_id IS NOT NULL AND is_bot=false
  LOOP
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (p.user_id,'refund',g.stake,g.id,'Remboursement admin');
  END LOOP;
  INSERT INTO public.admin_logs(admin_id, action) VALUES (auth.uid(),'admin_refund_game');
END $$;

CREATE OR REPLACE FUNCTION public.admin_list_games()
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(jsonb_agg(jsonb_build_object(
    'id', g.id, 'status', g.status, 'stake', g.stake, 'pot', g.pot,
    'max_players', g.max_players, 'created_at', g.created_at,
    'is_private', g.is_private, 'host_id', g.host_id,
    'players', (SELECT jsonb_agg(jsonb_build_object('user_id',p.user_id,'name',p.display_name,'forfeited',p.forfeited,'is_bot',p.is_bot)) FROM public.ludo_participants p WHERE p.game_id=g.id)
  ) ORDER BY g.created_at DESC), '[]'::jsonb)
  FROM public.ludo_games g
  WHERE g.status IN ('open','playing')
    AND public.is_admin()
$$;

-- 8. Referrals list (security definer to bypass per-row RLS on profiles)
CREATE OR REPLACE FUNCTION public.get_my_referrals()
RETURNS TABLE(id uuid, pseudo text, created_at timestamptz, phone_verified boolean, referral_unlocked boolean)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.pseudo, p.created_at, p.phone_verified, p.referral_unlocked
  FROM public.profiles p
  WHERE p.referred_by = auth.uid()
  ORDER BY p.created_at DESC
$$;

-- 9. SECURITY: tighten app_settings to authenticated only (no anon read)
DROP POLICY IF EXISTS settings_read ON public.app_settings;
CREATE POLICY settings_read_auth ON public.app_settings
  FOR SELECT TO authenticated USING (true);

-- 10. SECURITY: profiles_self_update_safe — protect phone_verified, referral_unlocked, referred_by
DROP POLICY IF EXISTS profiles_self_update_safe ON public.profiles;
CREATE POLICY profiles_self_update_safe ON public.profiles
  FOR UPDATE TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND balance_ar = (SELECT balance_ar FROM public.profiles WHERE id = auth.uid())
    AND banned     = (SELECT banned     FROM public.profiles WHERE id = auth.uid())
    AND status     = (SELECT status     FROM public.profiles WHERE id = auth.uid())
    AND unique_code= (SELECT unique_code FROM public.profiles WHERE id = auth.uid())
    AND referral_code = (SELECT referral_code FROM public.profiles WHERE id = auth.uid())
    AND phone_verified = (SELECT phone_verified FROM public.profiles WHERE id = auth.uid())
    AND referral_unlocked = (SELECT referral_unlocked FROM public.profiles WHERE id = auth.uid())
    AND COALESCE(referred_by::text,'') = COALESCE((SELECT referred_by::text FROM public.profiles WHERE id = auth.uid()),'')
  );

-- 11. SECURITY: ludo_games private room code leak — restrict private game visibility
DROP POLICY IF EXISTS games_select ON public.ludo_games;
CREATE POLICY games_select ON public.ludo_games
  FOR SELECT USING (
    (status IN ('open','playing') AND is_private = false)
    OR host_id = auth.uid()
    OR public._is_game_participant(id, auth.uid())
    OR public.is_admin()
  );

-- 12. SECURITY: storage — drop broad avatars_user_update/delete policies
DROP POLICY IF EXISTS avatars_user_update ON storage.objects;
DROP POLICY IF EXISTS avatars_user_delete ON storage.objects;
DROP POLICY IF EXISTS avatars_user_write ON storage.objects;
-- recreate strict per-folder write (insert) policy for avatars + chat
CREATE POLICY avatars_chat_user_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id IN ('avatars','chat')
    AND (auth.uid())::text = (storage.foldername(name))[1]
  );
