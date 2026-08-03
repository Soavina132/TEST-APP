
-- ============ ENUMS ============
CREATE TYPE public.app_role AS ENUM ('admin','user');
CREATE TYPE public.tx_status AS ENUM ('pending','approved','rejected');
CREATE TYPE public.game_status AS ENUM ('open','playing','finished','cancelled');

-- ============ PROFILES ============
CREATE TABLE public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  pseudo TEXT NOT NULL,
  email TEXT NOT NULL,
  balance_ar NUMERIC NOT NULL DEFAULT 0,
  referral_code TEXT NOT NULL UNIQUE,
  referred_by UUID REFERENCES public.profiles(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ USER ROLES ============
CREATE TABLE public.user_roles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role public.app_role NOT NULL,
  UNIQUE (user_id, role)
);

CREATE OR REPLACE FUNCTION public.has_role(_user_id UUID, _role public.app_role)
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.user_roles WHERE user_id=_user_id AND role=_role)
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE SQL STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.has_role(auth.uid(),'admin')
$$;

-- ============ APP SETTINGS (single row id=1) ============
CREATE TABLE public.app_settings (
  id INT PRIMARY KEY DEFAULT 1 CHECK (id=1),
  admin_phone TEXT NOT NULL DEFAULT '0385708218',
  admin_label TEXT NOT NULL DEFAULT 'MVola',
  signup_bonus NUMERIC NOT NULL DEFAULT 1,
  referral_pct NUMERIC NOT NULL DEFAULT 5,
  game_commission_pct NUMERIC NOT NULL DEFAULT 10,
  min_deposit NUMERIC NOT NULL DEFAULT 500,
  min_withdraw NUMERIC NOT NULL DEFAULT 1000,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
INSERT INTO public.app_settings(id) VALUES (1);

-- ============ DEPOSITS / WITHDRAWALS ============
CREATE TABLE public.deposits (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL,
  reference TEXT NOT NULL,
  user_phone TEXT,
  status public.tx_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ
);

CREATE TABLE public.withdrawals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC NOT NULL CHECK (amount > 0),
  method TEXT NOT NULL,
  user_phone TEXT NOT NULL,
  status public.tx_status NOT NULL DEFAULT 'pending',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at TIMESTAMPTZ
);

-- ============ TRANSACTIONS LEDGER ============
CREATE TABLE public.transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  type TEXT NOT NULL,        -- deposit, withdraw, stake, win, bonus, referral, admin_adjust
  amount NUMERIC NOT NULL,   -- signed
  ref_id UUID,
  note TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ LUDO GAMES ============
CREATE TABLE public.ludo_games (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id UUID NOT NULL REFERENCES auth.users(id),
  max_players INT NOT NULL CHECK (max_players BETWEEN 2 AND 4),
  stake NUMERIC NOT NULL CHECK (stake >= 0),
  pot NUMERIC NOT NULL DEFAULT 0,
  commission_pct NUMERIC NOT NULL DEFAULT 10,
  status public.game_status NOT NULL DEFAULT 'open',
  state JSONB NOT NULL DEFAULT '{}'::jsonb,
  current_turn INT NOT NULL DEFAULT 0,
  winner_id UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at TIMESTAMPTZ,
  finished_at TIMESTAMPTZ
);

CREATE TABLE public.ludo_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id UUID NOT NULL REFERENCES public.ludo_games(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  slot INT NOT NULL,
  color TEXT NOT NULL,
  is_bot BOOLEAN NOT NULL DEFAULT FALSE,
  bot_name TEXT,
  display_name TEXT NOT NULL,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (game_id, slot),
  UNIQUE (game_id, color)
);

-- ============ SUPPORT ============
CREATE TABLE public.support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  reply TEXT,
  status TEXT NOT NULL DEFAULT 'open',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ============ ENABLE RLS ============
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.deposits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ludo_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ludo_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.support_messages ENABLE ROW LEVEL SECURITY;

-- ============ RLS POLICIES ============
-- profiles: each user reads own + admin reads all; nobody can update directly (use RPC)
CREATE POLICY "profiles_self_select" ON public.profiles FOR SELECT USING (auth.uid() = id OR public.is_admin());
CREATE POLICY "profiles_self_insert" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
CREATE POLICY "profiles_self_update_pseudo" ON public.profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id);
-- (balance can only be modified by SECURITY DEFINER fns; UPDATE via client cannot change balance because we'll guard at app layer; safer: limit which columns updatable via column privileges)
REVOKE UPDATE ON public.profiles FROM anon, authenticated;
GRANT UPDATE (pseudo) ON public.profiles TO authenticated;

-- user_roles: users can see their own roles; only admin via SECURITY DEFINER fns can modify
CREATE POLICY "roles_self_select" ON public.user_roles FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

-- app_settings: everyone authenticated can read; writes only via SECURITY DEFINER fn
CREATE POLICY "settings_read" ON public.app_settings FOR SELECT USING (true);

-- deposits/withdrawals: user sees own + admin sees all; user can insert own request; status changed only via RPC
CREATE POLICY "deposits_select" ON public.deposits FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "deposits_insert" ON public.deposits FOR INSERT WITH CHECK (auth.uid() = user_id AND status = 'pending');
CREATE POLICY "withdrawals_select" ON public.withdrawals FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "withdrawals_insert" ON public.withdrawals FOR INSERT WITH CHECK (auth.uid() = user_id AND status = 'pending');

-- transactions: read own + admin
CREATE POLICY "tx_select" ON public.transactions FOR SELECT USING (auth.uid() = user_id OR public.is_admin());

-- ludo_games: anyone authenticated can see open & playing & their finished games
CREATE POLICY "games_select" ON public.ludo_games FOR SELECT USING (
  status IN ('open','playing') OR host_id = auth.uid() OR
  EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id = ludo_games.id AND p.user_id = auth.uid())
  OR public.is_admin()
);

-- ludo_participants: visible if game visible
CREATE POLICY "parts_select" ON public.ludo_participants FOR SELECT USING (
  EXISTS (SELECT 1 FROM public.ludo_games g WHERE g.id = game_id)
);

-- support: user sees own; admin sees all
CREATE POLICY "support_select" ON public.support_messages FOR SELECT USING (auth.uid() = user_id OR public.is_admin());
CREATE POLICY "support_insert" ON public.support_messages FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============ HELPER: short referral code ============
CREATE OR REPLACE FUNCTION public.gen_referral_code()
RETURNS TEXT LANGUAGE plpgsql AS $$
DECLARE c TEXT;
BEGIN
  LOOP
    c := upper(substring(replace(gen_random_uuid()::text,'-',''),1,7));
    IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = c) THEN
      RETURN c;
    END IF;
  END LOOP;
END $$;

-- ============ HANDLE NEW USER ============
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pseudo TEXT;
  v_ref_code TEXT;
  v_referred_by UUID;
  v_input_ref TEXT;
  v_bonus NUMERIC;
BEGIN
  v_pseudo := COALESCE(NEW.raw_user_meta_data->>'pseudo', split_part(NEW.email,'@',1));
  v_input_ref := NEW.raw_user_meta_data->>'referral_code';
  v_ref_code := public.gen_referral_code();

  IF v_input_ref IS NOT NULL AND v_input_ref <> '' THEN
    SELECT id INTO v_referred_by FROM public.profiles WHERE referral_code = upper(v_input_ref);
  END IF;

  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;

  INSERT INTO public.profiles(id, pseudo, email, referral_code, referred_by, balance_ar)
  VALUES (NEW.id, v_pseudo, NEW.email, v_ref_code, v_referred_by, COALESCE(v_bonus,0));

  IF COALESCE(v_bonus,0) > 0 THEN
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES (NEW.id,'bonus',v_bonus,'Bonus inscription');
  END IF;

  -- Auto-grant admin role to the designated admin email
  IF lower(NEW.email) = 'soavinapierrit@gmail.com' THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'admin') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END $$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============ RPC: create_game ============
CREATE OR REPLACE FUNCTION public.create_game(_max_players INT, _stake NUMERIC)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game_id UUID;
  v_commission NUMERIC;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10))
  RETURNING id INTO v_game_id;

  -- deduct host stake
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie');

  -- host occupies slot 0 with red
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
  SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;

  RETURN v_game_id;
END $$;

-- ============ RPC: join_game ============
CREATE OR REPLACE FUNCTION public.join_game(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_balance NUMERIC;
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  v_color := v_colors[v_slot+1];

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
  SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id = v_uid;

  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id = v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id = _game_id;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-v_game.stake,_game_id,'Mise rejoindre partie');

  -- start game if full
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status='playing', started_at=now() WHERE id=_game_id;
  END IF;
END $$;

-- ============ RPC: admin_add_bot ============
CREATE OR REPLACE FUNCTION public.admin_add_bot(_game_id UUID, _bot_name TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count INT;
  v_slot INT;
  v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  v_color := v_colors[v_slot+1];

  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,is_bot,bot_name,display_name)
  VALUES (_game_id, NULL, v_slot, v_color, TRUE, _bot_name, _bot_name);

  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status='playing', started_at=now() WHERE id=_game_id;
  END IF;
END $$;

-- ============ RPC: update_game_state ============
-- Allow participants (or host) to push state updates during the game.
CREATE OR REPLACE FUNCTION public.update_game_state(_game_id UUID, _state JSONB, _current_turn INT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid)
     AND NOT EXISTS (SELECT 1 FROM public.ludo_games WHERE id=_game_id AND host_id=v_uid) THEN
    RAISE EXCEPTION 'Non participant';
  END IF;
  UPDATE public.ludo_games SET state = _state, current_turn = _current_turn
   WHERE id = _game_id AND status = 'playing';
END $$;

-- ============ RPC: finish_game ============
CREATE OR REPLACE FUNCTION public.finish_game(_game_id UUID, _winner_id UUID)
RETURNS NUMERIC LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout NUMERIC;
  v_referrer UUID;
  v_ref_pct NUMERIC;
  v_ref_amount NUMERIC;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status = 'finished' THEN RETURN 0; END IF;

  -- winner must be a participant (and human)
  IF _winner_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=_winner_id AND is_bot=FALSE
  ) THEN
    RAISE EXCEPTION 'Gagnant invalide';
  END IF;

  v_payout := v_game.pot * (100 - v_game.commission_pct) / 100.0;

  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now() WHERE id=_game_id;

  IF _winner_id IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (_winner_id,'win',v_payout,_game_id,'Gain partie');

    -- referral commission on win (one-time per game)
    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Commission parrainage');
      END IF;
    END IF;
  END IF;

  RETURN v_payout;
END $$;

-- ============ RPC: admin_process_deposit ============
CREATE OR REPLACE FUNCTION public.admin_process_deposit(_id UUID, _approve BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_dep public.deposits%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_dep FROM public.deposits WHERE id=_id FOR UPDATE;
  IF v_dep.id IS NULL OR v_dep.status <> 'pending' THEN RAISE EXCEPTION 'Dépôt non valide'; END IF;
  IF _approve THEN
    UPDATE public.deposits SET status='approved', processed_at=now() WHERE id=_id;
    UPDATE public.profiles SET balance_ar = balance_ar + v_dep.amount WHERE id = v_dep.user_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_dep.user_id,'deposit',v_dep.amount,_id,'Dépôt approuvé');
  ELSE
    UPDATE public.deposits SET status='rejected', processed_at=now() WHERE id=_id;
  END IF;
END $$;

-- ============ RPC: admin_process_withdrawal ============
CREATE OR REPLACE FUNCTION public.admin_process_withdrawal(_id UUID, _approve BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_w public.withdrawals%ROWTYPE; v_balance NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_w FROM public.withdrawals WHERE id=_id FOR UPDATE;
  IF v_w.id IS NULL OR v_w.status <> 'pending' THEN RAISE EXCEPTION 'Retrait non valide'; END IF;
  IF _approve THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_w.user_id FOR UPDATE;
    IF v_balance < v_w.amount THEN RAISE EXCEPTION 'Solde joueur insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - v_w.amount WHERE id=v_w.user_id;
    UPDATE public.withdrawals SET status='approved', processed_at=now() WHERE id=_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_w.user_id,'withdraw',-v_w.amount,_id,'Retrait approuvé');
  ELSE
    UPDATE public.withdrawals SET status='rejected', processed_at=now() WHERE id=_id;
  END IF;
END $$;

-- ============ RPC: admin_update_settings ============
CREATE OR REPLACE FUNCTION public.admin_update_settings(
  _admin_phone TEXT, _admin_label TEXT, _signup_bonus NUMERIC,
  _referral_pct NUMERIC, _game_commission_pct NUMERIC,
  _min_deposit NUMERIC, _min_withdraw NUMERIC
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.app_settings SET
    admin_phone=_admin_phone, admin_label=_admin_label, signup_bonus=_signup_bonus,
    referral_pct=_referral_pct, game_commission_pct=_game_commission_pct,
    min_deposit=_min_deposit, min_withdraw=_min_withdraw, updated_at=now()
  WHERE id=1;
END $$;

-- ============ RPC: admin_adjust_balance ============
CREATE OR REPLACE FUNCTION public.admin_adjust_balance(_user_id UUID, _amount NUMERIC, _note TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.profiles SET balance_ar = balance_ar + _amount WHERE id=_user_id;
  INSERT INTO public.transactions(user_id,type,amount,note) VALUES (_user_id,'admin_adjust',_amount,COALESCE(_note,'Ajustement admin'));
END $$;

-- ============ RPC: admin_reply_support ============
CREATE OR REPLACE FUNCTION public.admin_reply_support(_id UUID, _reply TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.support_messages SET reply=_reply, status='answered' WHERE id=_id;
END $$;

-- ============ RPC: admin_list_users ============
CREATE OR REPLACE FUNCTION public.admin_list_users()
RETURNS TABLE(id UUID, pseudo TEXT, email TEXT, balance_ar NUMERIC, created_at TIMESTAMPTZ, is_admin BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY SELECT p.id, p.pseudo, p.email, p.balance_ar, p.created_at,
    EXISTS(SELECT 1 FROM public.user_roles r WHERE r.user_id=p.id AND r.role='admin')
    FROM public.profiles p ORDER BY p.created_at DESC;
END $$;

-- ============ REALTIME ============
ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_participants;
ALTER TABLE public.ludo_games REPLICA IDENTITY FULL;
ALTER TABLE public.ludo_participants REPLICA IDENTITY FULL;
