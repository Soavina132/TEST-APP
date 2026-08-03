
-- ============= A. STAR CELLS & BLOCKS (server-side) =============
CREATE OR REPLACE FUNCTION public._ludo_is_safe(_idx integer)
RETURNS boolean LANGUAGE sql IMMUTABLE
AS $$ SELECT _idx IN (0,8,13,21,26,34,39,47) $$;

CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  other_slot INT; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion déjà arrivé'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Dépassement'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE;
    ELSE new_state := 'track'; END IF;
  END IF;

  -- BLOCK CHECK: cannot land on a cell with 2+ opponent pawns of same slot
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_idx(v_slot);
    abs_cell := (start_idx + new_step) % 52;
    FOR other_slot IN 0..v_max-1 LOOP
      IF other_slot <> v_slot THEN
        op_start := public._ludo_start_idx(other_slot);
        same_slot_count := 0;
        FOR j IN 0..3 LOOP
          op := st->'pawns'->other_slot::text->j;
          IF op->>'s' = 'track' THEN
            op_step := (op->>'k')::INT;
            IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
              same_slot_count := same_slot_count + 1;
            END IF;
          END IF;
        END LOOP;
        IF same_slot_count >= 2 THEN
          RAISE EXCEPTION 'Case bloquée par un mur adverse';
        END IF;
      END IF;
    END LOOP;
  END IF;

  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text],
    jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  -- CAPTURE: only if cell not safe AND opponent has exactly 1 pawn there
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_idx(v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR other_slot IN 0..v_max-1 LOOP
        IF other_slot <> v_slot THEN
          op_start := public._ludo_start_idx(other_slot);
          other_pawns := st->'pawns'->other_slot::text;
          same_slot_count := 0;
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                same_slot_count := same_slot_count + 1;
              END IF;
            END IF;
          END LOOP;
          IF same_slot_count = 1 THEN
            FOR j IN 0..3 LOOP
              op := other_pawns->j;
              IF op->>'s' = 'track' THEN
                op_step := (op->>'k')::INT;
                IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                  other_pawns := jsonb_set(other_pawns, ARRAY[j::text],
                    jsonb_build_object('s','yard','k',-1));
                  captured := TRUE;
                END IF;
              END IF;
            END LOOP;
            st := jsonb_set(st, ARRAY['pawns', other_slot::text], other_pawns);
          END IF;
        END IF;
      END LOOP;
    END IF;
  END IF;

  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;

  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;

  IF all_done THEN
    SELECT user_id INTO winner_uid FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
    PERFORM public.finish_game(_game_id, winner_uid);
    RETURN st;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    st := jsonb_set(st,'{turn_slot}',
      to_jsonb(public._ludo_next_slot(_game_id, v_slot, v_max)));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $$;

-- ============= B. PROFILE EXTENSIONS =============
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS avatar_url text,
  ADD COLUMN IF NOT EXISTS unique_code text UNIQUE,
  ADD COLUMN IF NOT EXISTS banned boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS status text NOT NULL DEFAULT 'active';

CREATE OR REPLACE FUNCTION public.gen_unique_code()
RETURNS text LANGUAGE plpgsql SET search_path = public
AS $$
DECLARE c TEXT;
BEGIN
  LOOP
    c := 'LD' || upper(substring(replace(gen_random_uuid()::text,'-',''),1,5));
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE unique_code = c) THEN RETURN c; END IF;
  END LOOP;
END $$;

-- Backfill
UPDATE public.profiles SET unique_code = public.gen_unique_code() WHERE unique_code IS NULL;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_pseudo TEXT; v_ref_code TEXT; v_referred_by UUID; v_input_ref TEXT; v_bonus NUMERIC; v_unique TEXT;
BEGIN
  v_pseudo := COALESCE(NEW.raw_user_meta_data->>'pseudo', split_part(NEW.email,'@',1));
  v_input_ref := NEW.raw_user_meta_data->>'referral_code';
  v_ref_code := public.gen_referral_code();
  v_unique := public.gen_unique_code();
  IF v_input_ref IS NOT NULL AND v_input_ref <> '' THEN
    SELECT id INTO v_referred_by FROM public.profiles WHERE referral_code = upper(v_input_ref);
  END IF;
  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;
  INSERT INTO public.profiles(id, pseudo, email, referral_code, referred_by, balance_ar, unique_code)
  VALUES (NEW.id, v_pseudo, NEW.email, v_ref_code, v_referred_by, COALESCE(v_bonus,0), v_unique);
  IF COALESCE(v_bonus,0) > 0 THEN
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES (NEW.id,'bonus',v_bonus,'Bonus inscription');
  END IF;
  IF lower(NEW.email) = 'soavinapierrit@gmail.com' THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'admin') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

-- Restrict self-update to safe columns
DROP POLICY IF EXISTS profiles_self_update_pseudo ON public.profiles;
CREATE POLICY profiles_self_update_safe ON public.profiles
  FOR UPDATE USING (auth.uid() = id)
  WITH CHECK (
    auth.uid() = id
    AND balance_ar = (SELECT balance_ar FROM public.profiles WHERE id = auth.uid())
    AND banned = (SELECT banned FROM public.profiles WHERE id = auth.uid())
    AND status = (SELECT status FROM public.profiles WHERE id = auth.uid())
    AND unique_code = (SELECT unique_code FROM public.profiles WHERE id = auth.uid())
    AND referral_code = (SELECT referral_code FROM public.profiles WHERE id = auth.uid())
  );

-- Avatars bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars','avatars',true) ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "Avatars are publicly readable" ON storage.objects;
CREATE POLICY "Avatars are publicly readable" ON storage.objects FOR SELECT USING (bucket_id='avatars');

DROP POLICY IF EXISTS "Users upload own avatar" ON storage.objects;
CREATE POLICY "Users upload own avatar" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id='avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Users update own avatar" ON storage.objects;
CREATE POLICY "Users update own avatar" ON storage.objects FOR UPDATE
  USING (bucket_id='avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

DROP POLICY IF EXISTS "Users delete own avatar" ON storage.objects;
CREATE POLICY "Users delete own avatar" ON storage.objects FOR DELETE
  USING (bucket_id='avatars' AND auth.uid()::text = (storage.foldername(name))[1]);

-- ============= B6. ADMIN LOGS =============
CREATE TABLE IF NOT EXISTS public.admin_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id uuid NOT NULL,
  target_user_id uuid,
  action text NOT NULL,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.admin_logs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS admin_logs_read ON public.admin_logs;
CREATE POLICY admin_logs_read ON public.admin_logs FOR SELECT
  TO authenticated USING (public.is_admin());

CREATE OR REPLACE FUNCTION public._admin_log(_target uuid, _action text, _old jsonb, _new jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  INSERT INTO public.admin_logs(admin_id,target_user_id,action,old_value,new_value)
  VALUES (auth.uid(), _target, _action, _old, _new);
$$;

-- ============= B5. ADMIN USER MANAGEMENT =============
CREATE OR REPLACE FUNCTION public.admin_set_user_banned(_user_id uuid, _banned boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old boolean;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT banned INTO v_old FROM public.profiles WHERE id=_user_id;
  UPDATE public.profiles SET banned=_banned WHERE id=_user_id;
  PERFORM public._admin_log(_user_id,'set_banned',to_jsonb(v_old),to_jsonb(_banned));
END $$;

CREATE OR REPLACE FUNCTION public.admin_set_user_status(_user_id uuid, _status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT status INTO v_old FROM public.profiles WHERE id=_user_id;
  UPDATE public.profiles SET status=_status WHERE id=_user_id;
  PERFORM public._admin_log(_user_id,'set_status',to_jsonb(v_old),to_jsonb(_status));
END $$;

-- Override admin_adjust_balance to log
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(_user_id uuid, _amount numeric, _note text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_old numeric; v_new numeric;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT balance_ar INTO v_old FROM public.profiles WHERE id=_user_id FOR UPDATE;
  UPDATE public.profiles SET balance_ar = balance_ar + _amount WHERE id=_user_id RETURNING balance_ar INTO v_new;
  INSERT INTO public.transactions(user_id,type,amount,note) VALUES (_user_id,'admin_adjust',_amount,COALESCE(_note,'Ajustement admin'));
  PERFORM public._admin_log(_user_id,'adjust_balance',
    jsonb_build_object('balance',v_old),
    jsonb_build_object('balance',v_new,'amount',_amount,'note',_note));
END $$;

-- Search users (pseudo / email / unique_code)
CREATE OR REPLACE FUNCTION public.admin_search_users(_q text)
RETURNS TABLE(id uuid, pseudo text, email text, balance_ar numeric, unique_code text, banned boolean, status text, created_at timestamptz, is_admin boolean)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT p.id, p.pseudo, p.email, p.balance_ar, p.unique_code, p.banned, p.status, p.created_at,
      EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=p.id AND r.role='admin')
    FROM public.profiles p
    WHERE _q IS NULL OR _q = '' OR
      p.pseudo ILIKE '%'||_q||'%' OR p.email ILIKE '%'||_q||'%' OR p.unique_code ILIKE '%'||_q||'%' OR p.id::text = _q
    ORDER BY p.created_at DESC LIMIT 100;
END $$;

-- Dashboard totals
CREATE OR REPLACE FUNCTION public.admin_dashboard_totals()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT jsonb_build_object(
    'total_deposits', COALESCE((SELECT SUM(amount) FROM public.deposits WHERE status='approved'),0),
    'total_withdrawals', COALESCE((SELECT SUM(amount) FROM public.withdrawals WHERE status='approved'),0),
    'total_commission', COALESCE((SELECT SUM(pot * commission_pct / 100.0) FROM public.ludo_games WHERE status='finished' AND winner_id IS NOT NULL),0),
    'total_users', (SELECT count(*) FROM public.profiles),
    'total_games', (SELECT count(*) FROM public.ludo_games WHERE status='finished'),
    'open_games', (SELECT count(*) FROM public.ludo_games WHERE status='open'),
    'playing_games', (SELECT count(*) FROM public.ludo_games WHERE status='playing')
  ) INTO v;
  RETURN v;
END $$;

-- Games history
CREATE OR REPLACE FUNCTION public.admin_games_history(_limit int DEFAULT 50)
RETURNS TABLE(id uuid, status game_status, stake numeric, pot numeric, commission_pct numeric, max_players int, winner_pseudo text, players jsonb, created_at timestamptz, finished_at timestamptz, duration_sec int)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT g.id, g.status, g.stake, g.pot, g.commission_pct, g.max_players,
      (SELECT pseudo FROM public.profiles WHERE id=g.winner_id),
      COALESCE((SELECT jsonb_agg(jsonb_build_object('name',pp.display_name,'is_bot',pp.is_bot)) FROM public.ludo_participants pp WHERE pp.game_id=g.id),'[]'::jsonb),
      g.created_at, g.finished_at,
      CASE WHEN g.finished_at IS NOT NULL AND g.started_at IS NOT NULL
        THEN EXTRACT(EPOCH FROM (g.finished_at - g.started_at))::int ELSE NULL END
    FROM public.ludo_games g ORDER BY g.created_at DESC LIMIT _limit;
END $$;

-- ============= C. ROOM CLEANUP + MATCHMAKING =============
ALTER TABLE public.ludo_games ADD COLUMN IF NOT EXISTS room_code text UNIQUE;

CREATE OR REPLACE FUNCTION public._gen_room_code()
RETURNS text LANGUAGE plpgsql SET search_path = public
AS $$
DECLARE c TEXT;
BEGIN
  LOOP
    c := upper(substring(replace(gen_random_uuid()::text,'-',''),1,6));
    IF NOT EXISTS (SELECT 1 FROM public.ludo_games WHERE room_code = c) THEN RETURN c; END IF;
  END LOOP;
END $$;

UPDATE public.ludo_games SET room_code = public._gen_room_code() WHERE room_code IS NULL;

-- Patch create_game to assign room_code + check ban
CREATE OR REPLACE FUNCTION public.create_game(_max_players integer, _stake numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
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
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_game_id;
END $$;

-- Patch join_game to check ban
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
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
END $$;

-- Cleanup empty rooms
CREATE OR REPLACE FUNCTION public.ludo_cleanup_empty_rooms()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_count int;
BEGIN
  WITH d AS (
    DELETE FROM public.ludo_games g
    WHERE g.status='open' AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id)
    RETURNING 1
  ) SELECT count(*) INTO v_count FROM d;
  RETURN v_count;
END $$;

-- Patch ludo_quit to delete room if last participant left
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;
  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id=_game_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'refund',g.stake,_game_id,'Annulation avant départ');
    DELETE FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants WHERE game_id=_game_id;
    IF v_remaining = 0 THEN DELETE FROM public.ludo_games WHERE id=_game_id; END IF;
    RETURN;
  END IF;
  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid;
  st := g.state;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  END IF;
  v_winner := public._ludo_check_last_standing(_game_id);
  IF v_winner IS NOT NULL THEN
    PERFORM public.finish_game(_game_id, v_winner);
  ELSIF public._ludo_active_humans(_game_id) = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
  END IF;
END $$;

-- Patch ludo_tick_all to cleanup empty rooms periodically
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE g_id UUID; v_slot INT; v_isbot BOOLEAN; st JSONB; v_started TIMESTAMPTZ;
BEGIN
  PERFORM public.ludo_cleanup_empty_rooms();
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
          PERFORM public.ludo_bot_play(g_id);
        ELSIF now() - v_started >= interval '2 seconds' THEN
          PERFORM public.ludo_bot_play(g_id);
        END IF;
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END LOOP;
END $$;

-- Matchmaking: find compatible open game, else create
CREATE OR REPLACE FUNCTION public.find_or_create_game(_max_players int, _stake numeric)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); v_target UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.ludo_cleanup_empty_rooms();
  SELECT g.id INTO v_target
    FROM public.ludo_games g
    WHERE g.status='open' AND g.max_players=_max_players AND g.stake=_stake
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) > 0
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players
      AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id AND p.user_id=v_uid)
    ORDER BY (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) DESC, g.created_at ASC
    LIMIT 1;
  IF v_target IS NOT NULL THEN
    PERFORM public.join_game(v_target);
    RETURN v_target;
  END IF;
  RETURN public.create_game(_max_players, _stake);
END $$;

-- Join by code
CREATE OR REPLACE FUNCTION public.join_game_by_code(_code text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  SELECT id INTO v_id FROM public.ludo_games WHERE room_code = upper(_code) AND status='open';
  IF v_id IS NULL THEN RAISE EXCEPTION 'Code invalide ou partie fermée'; END IF;
  PERFORM public.join_game(v_id);
  RETURN v_id;
END $$;

-- ============= D. NOTIFICATIONS =============
CREATE OR REPLACE FUNCTION public.mark_messages_read()
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$
  UPDATE public.admin_user_messages SET read_at = now()
  WHERE user_id = auth.uid() AND from_admin = true AND read_at IS NULL;
$$;

-- Allow admin_user_messages updates (for read_at)
DROP POLICY IF EXISTS dm_user_update ON public.admin_user_messages;
CREATE POLICY dm_user_update ON public.admin_user_messages FOR UPDATE
  TO authenticated USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
