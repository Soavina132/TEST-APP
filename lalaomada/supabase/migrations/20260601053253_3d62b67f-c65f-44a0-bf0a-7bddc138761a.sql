
-- ============ APP SETTINGS EXTENSION ============
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS download_url text DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_facebook text DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_whatsapp text DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_phone text DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_email text DEFAULT '',
  ADD COLUMN IF NOT EXISTS tutorials jsonb DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS chat_global_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS chat_room_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS live_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS max_spectators int DEFAULT 50,
  ADD COLUMN IF NOT EXISTS ready_timeout_seconds int DEFAULT 60,
  ADD COLUMN IF NOT EXISTS afk_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS afk_threshold int DEFAULT 2,
  ADD COLUMN IF NOT EXISTS turn_seconds int DEFAULT 30;

-- admin can update settings
DROP POLICY IF EXISTS settings_admin_update ON public.app_settings;
CREATE POLICY settings_admin_update ON public.app_settings FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT UPDATE ON public.app_settings TO authenticated;

-- ============ LUDO PARTICIPANTS: AFK 2 timers ============
ALTER TABLE public.ludo_participants
  ADD COLUMN IF NOT EXISTS afk_t1 int DEFAULT 0,
  ADD COLUMN IF NOT EXISTS afk_t2 int DEFAULT 0;

-- ============ LUDO GAMES: super-player + spectators ============
ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS dice_override jsonb DEFAULT '{}'::jsonb,
  ADD COLUMN IF NOT EXISTS spectator_chat_enabled boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS ready_deadline timestamptz;

-- set ready_deadline when game created (1min after creation by default)
CREATE OR REPLACE FUNCTION public._ludo_set_ready_deadline()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_sec int;
BEGIN
  SELECT COALESCE(ready_timeout_seconds,60) INTO v_sec FROM public.app_settings WHERE id=1;
  NEW.ready_deadline := now() + (v_sec || ' seconds')::interval;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_ludo_ready_deadline ON public.ludo_games;
CREATE TRIGGER trg_ludo_ready_deadline BEFORE INSERT ON public.ludo_games
FOR EACH ROW EXECUTE FUNCTION public._ludo_set_ready_deadline();

-- ============ SPECTATORS ============
CREATE TABLE IF NOT EXISTS public.game_spectators (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id uuid NOT NULL,
  user_id uuid NOT NULL,
  joined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(game_id, user_id)
);
GRANT SELECT, INSERT, DELETE ON public.game_spectators TO authenticated;
GRANT ALL ON public.game_spectators TO service_role;
ALTER TABLE public.game_spectators ENABLE ROW LEVEL SECURITY;
CREATE POLICY spectators_select ON public.game_spectators FOR SELECT TO authenticated USING (true);
CREATE POLICY spectators_insert ON public.game_spectators FOR INSERT TO authenticated WITH CHECK (auth.uid()=user_id);
CREATE POLICY spectators_delete ON public.game_spectators FOR DELETE TO authenticated USING (auth.uid()=user_id OR public.is_admin());

-- ============ CHAT ============
-- rooms: type = 'global' (community) | 'game' | 'dm'
CREATE TABLE IF NOT EXISTS public.chat_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('global','game','dm')),
  name text,
  image_url text,
  game_id uuid,
  dm_user_a uuid,
  dm_user_b uuid,
  created_by uuid,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_type ON public.chat_rooms(type);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_game ON public.chat_rooms(game_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_dm ON public.chat_rooms(LEAST(dm_user_a,dm_user_b), GREATEST(dm_user_a,dm_user_b)) WHERE type='dm';
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_rooms TO authenticated;
GRANT ALL ON public.chat_rooms TO service_role;
ALTER TABLE public.chat_rooms ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_rooms_select ON public.chat_rooms FOR SELECT TO authenticated
  USING (
    type='global'
    OR (type='dm' AND (dm_user_a=auth.uid() OR dm_user_b=auth.uid()))
    OR (type='game' AND (public._is_game_participant(game_id, auth.uid()) OR EXISTS(SELECT 1 FROM public.game_spectators s WHERE s.game_id=chat_rooms.game_id AND s.user_id=auth.uid())))
    OR public.is_admin()
  );
CREATE POLICY chat_rooms_admin_write ON public.chat_rooms FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());

-- messages
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  body text,
  attachment_url text,
  attachment_type text,
  reply_to uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  pinned boolean NOT NULL DEFAULT false,
  edited_at timestamptz,
  deleted_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_chat_messages_room ON public.chat_messages(room_id, created_at DESC);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.chat_messages TO authenticated;
GRANT ALL ON public.chat_messages TO service_role;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_messages_select ON public.chat_messages FOR SELECT TO authenticated
  USING (EXISTS(SELECT 1 FROM public.chat_rooms r WHERE r.id=room_id AND (
    r.type='global'
    OR (r.type='dm' AND (r.dm_user_a=auth.uid() OR r.dm_user_b=auth.uid()))
    OR (r.type='game' AND (public._is_game_participant(r.game_id, auth.uid()) OR EXISTS(SELECT 1 FROM public.game_spectators s WHERE s.game_id=r.game_id AND s.user_id=auth.uid())))
    OR public.is_admin()
  )));
CREATE POLICY chat_messages_insert ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (user_id=auth.uid() AND EXISTS(SELECT 1 FROM public.chat_rooms r WHERE r.id=room_id AND r.enabled=true));
CREATE POLICY chat_messages_update_own ON public.chat_messages FOR UPDATE TO authenticated
  USING (user_id=auth.uid() OR public.is_admin()) WITH CHECK (user_id=auth.uid() OR public.is_admin());
CREATE POLICY chat_messages_delete ON public.chat_messages FOR DELETE TO authenticated
  USING (user_id=auth.uid() OR public.is_admin());

-- reactions
CREATE TABLE IF NOT EXISTS public.chat_reactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  message_id uuid NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  emoji text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(message_id, user_id, emoji)
);
GRANT SELECT, INSERT, DELETE ON public.chat_reactions TO authenticated;
GRANT ALL ON public.chat_reactions TO service_role;
ALTER TABLE public.chat_reactions ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_reactions_all ON public.chat_reactions FOR SELECT TO authenticated USING (true);
CREATE POLICY chat_reactions_ins ON public.chat_reactions FOR INSERT TO authenticated WITH CHECK (user_id=auth.uid());
CREATE POLICY chat_reactions_del ON public.chat_reactions FOR DELETE TO authenticated USING (user_id=auth.uid());

-- presence/typing
CREATE TABLE IF NOT EXISTS public.chat_presence (
  user_id uuid PRIMARY KEY,
  last_seen timestamptz NOT NULL DEFAULT now(),
  current_game uuid,
  typing_room uuid,
  typing_until timestamptz
);
GRANT SELECT, INSERT, UPDATE ON public.chat_presence TO authenticated;
GRANT ALL ON public.chat_presence TO service_role;
ALTER TABLE public.chat_presence ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_presence_select ON public.chat_presence FOR SELECT TO authenticated USING (true);
CREATE POLICY chat_presence_upsert ON public.chat_presence FOR INSERT TO authenticated WITH CHECK (user_id=auth.uid());
CREATE POLICY chat_presence_update ON public.chat_presence FOR UPDATE TO authenticated USING (user_id=auth.uid()) WITH CHECK (user_id=auth.uid());

-- chat mutes/bans
CREATE TABLE IF NOT EXISTS public.chat_mutes (
  user_id uuid PRIMARY KEY,
  until timestamptz,
  banned boolean NOT NULL DEFAULT false,
  reason text,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT SELECT ON public.chat_mutes TO authenticated;
GRANT ALL ON public.chat_mutes TO service_role;
ALTER TABLE public.chat_mutes ENABLE ROW LEVEL SECURITY;
CREATE POLICY chat_mutes_read ON public.chat_mutes FOR SELECT TO authenticated USING (user_id=auth.uid() OR public.is_admin());

-- avatars bucket
INSERT INTO storage.buckets (id, name, public) VALUES ('avatars','avatars', true) ON CONFLICT DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('chat','chat', true) ON CONFLICT DO NOTHING;
DROP POLICY IF EXISTS avatars_public_read ON storage.objects;
CREATE POLICY avatars_public_read ON storage.objects FOR SELECT USING (bucket_id IN ('avatars','chat'));
DROP POLICY IF EXISTS avatars_user_write ON storage.objects;
CREATE POLICY avatars_user_write ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id IN ('avatars','chat') AND auth.role()='authenticated');
DROP POLICY IF EXISTS avatars_user_update ON storage.objects;
CREATE POLICY avatars_user_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id IN ('avatars','chat')) WITH CHECK (bucket_id IN ('avatars','chat'));
DROP POLICY IF EXISTS avatars_user_delete ON storage.objects;
CREATE POLICY avatars_user_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id IN ('avatars','chat'));

-- allow profile avatar update (broaden safe profile update to permit avatar_url)
DROP POLICY IF EXISTS profiles_self_update_safe ON public.profiles;
CREATE POLICY profiles_self_update_safe ON public.profiles FOR UPDATE TO authenticated
  USING (auth.uid()=id)
  WITH CHECK (
    auth.uid()=id
    AND balance_ar = (SELECT balance_ar FROM public.profiles WHERE id=auth.uid())
    AND banned    = (SELECT banned    FROM public.profiles WHERE id=auth.uid())
    AND status    = (SELECT status    FROM public.profiles WHERE id=auth.uid())
    AND unique_code   = (SELECT unique_code   FROM public.profiles WHERE id=auth.uid())
    AND referral_code = (SELECT referral_code FROM public.profiles WHERE id=auth.uid())
  );

-- realtime
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_reactions;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_presence;
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_rooms;
ALTER PUBLICATION supabase_realtime ADD TABLE public.game_spectators;

-- ============ RPCs ============

-- create or get DM room
CREATE OR REPLACE FUNCTION public.chat_get_or_create_dm(_other uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_me uuid:=auth.uid(); v_id uuid; v_a uuid; v_b uuid;
BEGIN
  IF v_me IS NULL OR _other IS NULL OR _other=v_me THEN RAISE EXCEPTION 'invalid'; END IF;
  v_a := LEAST(v_me,_other); v_b := GREATEST(v_me,_other);
  SELECT id INTO v_id FROM public.chat_rooms WHERE type='dm' AND dm_user_a=v_a AND dm_user_b=v_b;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO public.chat_rooms(type,dm_user_a,dm_user_b,created_by) VALUES('dm',v_a,v_b,v_me) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- get or create game chat room
CREATE OR REPLACE FUNCTION public.chat_get_or_create_game_room(_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.chat_rooms WHERE type='game' AND game_id=_game_id;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO public.chat_rooms(type,game_id,name) VALUES('game',_game_id,'Partie') RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- chat_send with anti-spam (max 5 msg / 5s)
CREATE OR REPLACE FUNCTION public.chat_send(_room_id uuid, _body text, _reply_to uuid DEFAULT NULL, _attachment_url text DEFAULT NULL, _attachment_type text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_me uuid:=auth.uid(); v_id uuid; v_count int; v_mute public.chat_mutes%ROWTYPE;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT * INTO v_mute FROM public.chat_mutes WHERE user_id=v_me;
  IF v_mute.user_id IS NOT NULL AND (v_mute.banned OR (v_mute.until IS NOT NULL AND v_mute.until>now())) THEN
    RAISE EXCEPTION 'Vous êtes muté';
  END IF;
  SELECT count(*) INTO v_count FROM public.chat_messages WHERE user_id=v_me AND created_at>now()-interval '5 seconds';
  IF v_count >= 5 THEN RAISE EXCEPTION 'Trop de messages, ralentissez'; END IF;
  INSERT INTO public.chat_messages(room_id,user_id,body,reply_to,attachment_url,attachment_type)
    VALUES (_room_id, v_me, NULLIF(_body,''), _reply_to, _attachment_url, _attachment_type) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- pin/unpin (admin or room creator)
CREATE OR REPLACE FUNCTION public.chat_pin(_message_id uuid, _pin boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE public.chat_messages SET pinned=_pin WHERE id=_message_id;
END $$;

-- admin create community
CREATE OR REPLACE FUNCTION public.admin_create_community(_name text, _image_url text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  INSERT INTO public.chat_rooms(type,name,image_url,created_by) VALUES('global',_name,_image_url,auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.admin_update_community(_room_id uuid, _name text, _image_url text, _enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE public.chat_rooms SET name=COALESCE(_name,name), image_url=COALESCE(_image_url,image_url), enabled=COALESCE(_enabled,enabled) WHERE id=_room_id AND type='global';
END $$;

CREATE OR REPLACE FUNCTION public.admin_delete_community(_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM public.chat_rooms WHERE id=_room_id AND type='global';
END $$;

CREATE OR REPLACE FUNCTION public.admin_chat_mute(_user_id uuid, _minutes int, _ban boolean, _reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  INSERT INTO public.chat_mutes(user_id, until, banned, reason)
    VALUES (_user_id, CASE WHEN _minutes>0 THEN now()+(_minutes||' minutes')::interval ELSE NULL END, COALESCE(_ban,false), _reason)
    ON CONFLICT (user_id) DO UPDATE SET until=EXCLUDED.until, banned=EXCLUDED.banned, reason=EXCLUDED.reason;
END $$;

CREATE OR REPLACE FUNCTION public.admin_chat_unmute(_user_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM public.chat_mutes WHERE user_id=_user_id;
END $$;

-- presence heartbeat
CREATE OR REPLACE FUNCTION public.chat_presence_ping(_game uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  INSERT INTO public.chat_presence(user_id,last_seen,current_game) VALUES (auth.uid(), now(), _game)
    ON CONFLICT (user_id) DO UPDATE SET last_seen=now(), current_game=_game;
END $$;

CREATE OR REPLACE FUNCTION public.chat_typing(_room_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RETURN; END IF;
  INSERT INTO public.chat_presence(user_id,last_seen,typing_room,typing_until) VALUES (auth.uid(), now(), _room_id, now()+interval '4 seconds')
    ON CONFLICT (user_id) DO UPDATE SET last_seen=now(), typing_room=_room_id, typing_until=now()+interval '4 seconds';
END $$;

-- ============ SPECTATE ============
CREATE OR REPLACE FUNCTION public.spectate_join(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_max int; v_count int; v_enabled boolean;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  SELECT live_enabled, max_spectators INTO v_enabled, v_max FROM public.app_settings WHERE id=1;
  IF NOT COALESCE(v_enabled,true) THEN RAISE EXCEPTION 'LIVE désactivé'; END IF;
  SELECT count(*) INTO v_count FROM public.game_spectators WHERE game_id=_game_id;
  IF v_count >= COALESCE(v_max,50) THEN RAISE EXCEPTION 'LIVE complet'; END IF;
  INSERT INTO public.game_spectators(game_id,user_id) VALUES(_game_id, auth.uid()) ON CONFLICT DO NOTHING;
END $$;

CREATE OR REPLACE FUNCTION public.spectate_leave(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  DELETE FROM public.game_spectators WHERE game_id=_game_id AND user_id=auth.uid();
END $$;

CREATE OR REPLACE FUNCTION public.list_live_games()
RETURNS TABLE(id uuid, max_players int, stake numeric, pot numeric, players_count int, spectators_count int, started_at timestamptz, mode text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, g.mode
  FROM public.ludo_games g WHERE g.status='playing'
  ORDER BY (SELECT count(*) FROM public.game_spectators s WHERE s.game_id=g.id) DESC, g.started_at ASC;
$$;

CREATE OR REPLACE FUNCTION public.toggle_spectator_chat(_game_id uuid, _enabled boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=auth.uid()) THEN
    RAISE EXCEPTION 'Non joueur';
  END IF;
  UPDATE public.ludo_games SET spectator_chat_enabled=_enabled WHERE id=_game_id;
END $$;

-- ============ SUPER-PLAYER ADMIN ============
-- Allow admin to join open games (override the "no admin" check)
CREATE OR REPLACE FUNCTION public.admin_join_game(_game_id uuid, _display_name text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid uuid:=auth.uid(); v_game public.ludo_games%ROWTYPE; v_count int; v_slot int; v_color text;
  v_colors text[]:=ARRAY['red','green','yellow','blue']; v_name text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot:=v_count; v_color:=v_colors[v_slot+1];
  SELECT COALESCE(NULLIF(_display_name,''), pseudo) INTO v_name FROM public.profiles WHERE id=v_uid;
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name,ready)
    VALUES (_game_id, v_uid, v_slot, v_color, v_name, true);
END $$;

-- Admin sets next dice for their slot (or any slot if super-player granted)
CREATE OR REPLACE FUNCTION public.super_player_set_dice(_game_id uuid, _dice int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_slot int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF _dice IS NOT NULL AND (_dice<1 OR _dice>6) THEN RAISE EXCEPTION 'dé invalide'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=auth.uid();
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;
  UPDATE public.ludo_games SET dice_override = jsonb_set(COALESCE(dice_override,'{}'::jsonb), ARRAY[v_slot::text],
    CASE WHEN _dice IS NULL THEN 'null'::jsonb ELSE to_jsonb(_dice) END)
    WHERE id=_game_id;
END $$;

-- Update ludo_roll to use dice_override
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT; v_override int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;

  -- dice override (super-player admin)
  v_override := NULLIF(g.dice_override->>v_slot::text,'')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id=_game_id;
  ELSE
    v_dice := 1 + (floor(random()*6))::INT;
    IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
  END IF;

  IF v_dice = 6 THEN v_consec := COALESCE(v_consec,0) + 1; ELSE v_consec := 0; END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;

  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));

  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN IF v_dice=6 THEN has_move:=TRUE; EXIT; END IF;
    ELSE IF pstep + v_dice <= 56 THEN has_move:=TRUE; EXIT; END IF; END IF;
  END LOOP;

  IF NOT has_move THEN
    -- no possible move counts as AFK timer2 (rolled but didn't move)
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    PERFORM public._ludo_check_afk(_game_id, v_slot);
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $function$;

-- AFK check (exclusion when threshold reached)
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_t1 int; v_t2 int; v_thresh int; v_enabled boolean; v_uid uuid; v_isbot boolean; v_winner uuid;
BEGIN
  SELECT afk_enabled, afk_threshold INTO v_enabled, v_thresh FROM public.app_settings WHERE id=1;
  IF NOT COALESCE(v_enabled,true) THEN RETURN; END IF;
  SELECT afk_t1, afk_t2, user_id, is_bot INTO v_t1, v_t2, v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=_slot;
  IF v_isbot THEN RETURN; END IF;
  IF v_t1 >= COALESCE(v_thresh,2) OR v_t2 >= COALESCE(v_thresh,2) THEN
    UPDATE public.ludo_participants SET forfeited=true WHERE game_id=_game_id AND slot=_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'forfeit',0,_game_id,'Exclusion AFK');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN PERFORM public.finish_game(_game_id, v_winner); END IF;
  END IF;
END $$;

-- Replace ludo_check_timeout to use afk_t1 (and turn_seconds)
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_t1 int; v_secs int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, afk_t1 INTO v_uid, v_isbot, v_t1
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;

  -- timer1 + 1
  IF NOT v_isbot THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
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

-- ============ AUTO-PURGE NON-READY ROOMS ============
CREATE OR REPLACE FUNCTION public.ludo_purge_unready_rooms()
RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g RECORD; v_count int:=0;
BEGIN
  FOR g IN SELECT * FROM public.ludo_games WHERE status='open' AND ready_deadline IS NOT NULL AND now() > ready_deadline LOOP
    -- refund stakes to participants
    FOR g IN SELECT p.user_id, g2.stake FROM public.ludo_participants p
              JOIN public.ludo_games g2 ON g2.id=p.game_id WHERE p.game_id=g.id LOOP
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=g.user_id;
      INSERT INTO public.transactions(user_id,type,amount,note) VALUES (g.user_id,'refund', g.stake, 'Partie annulée: joueurs non prêts');
    END LOOP;
  END LOOP;
  WITH del AS (
    DELETE FROM public.ludo_games WHERE status='open' AND ready_deadline IS NOT NULL AND now() > ready_deadline RETURNING 1
  ) SELECT count(*) INTO v_count FROM del;
  RETURN v_count;
END $$;

-- recreate join_game with admin allowance lifted? NO. Admins use admin_join_game.
-- 1v1 color rule (red vs yellow) handled in join_game/admin_add_bot rewrite:
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN;
  v_colors_2 TEXT[] := ARRAY['red','yellow'];
  v_colors_3 TEXT[] := ARRAY['red','green','yellow'];
  v_colors_4 TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs utilisent admin_join_game'; END IF;
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
  v_slot := v_count;
  v_color := CASE v_game.max_players
    WHEN 2 THEN v_colors_2[v_slot+1]
    WHEN 3 THEN v_colors_3[v_slot+1]
    ELSE v_colors_4[v_slot+1] END;
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (v_uid,'stake',-v_game.stake,_game_id,'Mise rejoindre partie');
END $$;

-- update display name for participant (used by admin pre-join rename)
CREATE OR REPLACE FUNCTION public.participant_rename(_game_id uuid, _name text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'auth'; END IF;
  UPDATE public.ludo_participants SET display_name=_name WHERE game_id=_game_id AND user_id=auth.uid();
END $$;
