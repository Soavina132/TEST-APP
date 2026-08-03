
-- 1. Timeout 3 -> 10
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_started TIMESTAMPTZ;
  v_uid UUID; v_isbot BOOLEAN; v_missed INT; v_winner UUID;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;
  IF v_missed >= 10 AND NOT v_isbot THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Forfait (10 timeouts)');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
      RETURN (SELECT state FROM public.ludo_games WHERE id=_game_id);
    END IF;
  END IF;
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $function$;

-- 2. Bot tick: roll first, then wait 2s before moving (separate ticks)
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE g_id UUID; v_slot INT; v_isbot BOOLEAN; st JSONB; v_started TIMESTAMPTZ;
BEGIN
  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      PERFORM public.ludo_check_timeout(g_id);
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=g_id AND slot=v_slot;
      IF v_isbot THEN
        v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
        IF NOT (st->>'must_move')::BOOLEAN THEN
          -- Bot rolls the dice
          PERFORM public.ludo_bot_play(g_id);
        ELSIF now() - v_started >= interval '2 seconds' THEN
          -- Bot moves only after 2s (simulates real play)
          PERFORM public.ludo_bot_play(g_id);
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $function$;

-- 3. App pause + broadcast settings
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_message TEXT;

-- 4. Broadcasts table
CREATE TABLE IF NOT EXISTS public.admin_broadcasts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at TIMESTAMPTZ
);
ALTER TABLE public.admin_broadcasts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "broadcasts_read_active" ON public.admin_broadcasts;
CREATE POLICY "broadcasts_read_active" ON public.admin_broadcasts
  FOR SELECT TO authenticated USING (deleted_at IS NULL OR public.is_admin());

-- 5. DM table
CREATE TABLE IF NOT EXISTS public.admin_user_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  from_admin BOOLEAN NOT NULL,
  message TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  read_at TIMESTAMPTZ
);
ALTER TABLE public.admin_user_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "dm_read" ON public.admin_user_messages;
CREATE POLICY "dm_read" ON public.admin_user_messages
  FOR SELECT TO authenticated USING (auth.uid() = user_id OR public.is_admin());
DROP POLICY IF EXISTS "dm_user_insert" ON public.admin_user_messages;
CREATE POLICY "dm_user_insert" ON public.admin_user_messages
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id AND from_admin = FALSE);

-- 6. Admin messaging RPCs
CREATE OR REPLACE FUNCTION public.admin_broadcast_send(_message TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  INSERT INTO public.admin_broadcasts(message) VALUES (_message) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_broadcast_delete(_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.admin_broadcasts SET deleted_at=now() WHERE id=_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_dm_send(_user_id UUID, _message TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  INSERT INTO public.admin_user_messages(user_id,from_admin,message)
    VALUES (_user_id, TRUE, _message) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_pause(_paused BOOLEAN, _message TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.app_settings SET paused=_paused, pause_message=_message, updated_at=now() WHERE id=1;
END $$;

-- 7. Block create/join when paused
CREATE OR REPLACE FUNCTION public.create_game(_max_players integer, _stake numeric)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10))
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_game_id;
END $function$;

CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count; v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (v_uid,'stake',-v_game.stake,_game_id,'Mise rejoindre partie');
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players) WHERE id=_game_id;
  END IF;
END $function$;

-- 8. Stats RPCs
CREATE OR REPLACE FUNCTION public.admin_stats_daily(_days INT)
RETURNS TABLE(day DATE, deposits NUMERIC, withdrawals NUMERIC, wins NUMERIC)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
  WITH days AS (
    SELECT generate_series(
      (current_date - (_days-1) * interval '1 day')::date,
      current_date::date,
      interval '1 day'
    )::date AS d
  )
  SELECT d.d,
    COALESCE((SELECT SUM(amount) FROM public.deposits WHERE status='approved' AND processed_at::date = d.d),0)::numeric,
    COALESCE((SELECT SUM(amount) FROM public.withdrawals WHERE status='approved' AND processed_at::date = d.d),0)::numeric,
    COALESCE((SELECT SUM(amount) FROM public.transactions WHERE type='win' AND created_at::date = d.d),0)::numeric
  FROM days d ORDER BY d.d DESC;
END $$;

CREATE OR REPLACE FUNCTION public.admin_user_history(_user_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT jsonb_build_object(
    'profile', (SELECT to_jsonb(p) FROM public.profiles p WHERE p.id=_user_id),
    'transactions', COALESCE((SELECT jsonb_agg(to_jsonb(t) ORDER BY t.created_at DESC) FROM public.transactions t WHERE t.user_id=_user_id),'[]'::jsonb),
    'deposits', COALESCE((SELECT jsonb_agg(to_jsonb(d) ORDER BY d.created_at DESC) FROM public.deposits d WHERE d.user_id=_user_id),'[]'::jsonb),
    'withdrawals', COALESCE((SELECT jsonb_agg(to_jsonb(w) ORDER BY w.created_at DESC) FROM public.withdrawals w WHERE w.user_id=_user_id),'[]'::jsonb),
    'games', COALESCE((SELECT jsonb_agg(jsonb_build_object('game_id',g.id,'status',g.status,'stake',g.stake,'won', g.winner_id=_user_id,'finished_at',g.finished_at) ORDER BY g.created_at DESC)
       FROM public.ludo_games g JOIN public.ludo_participants pp ON pp.game_id=g.id WHERE pp.user_id=_user_id),'[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END $$;

-- 9. Realtime for new tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_broadcasts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.admin_user_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.app_settings;
