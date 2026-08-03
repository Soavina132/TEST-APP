-- ============================================================
-- 1) GAME PAUSE SYSTEM
-- ============================================================
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;
ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;
ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;
ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;
ALTER TABLE public.poker_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS paused_turn_remaining_s INTEGER;
ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS paused BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pause_deadline TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public._game_resume_internal(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status TEXT; v_paused BOOLEAN; v_remaining_s INTEGER;
BEGIN
  CASE _slug
    WHEN 'chess' THEN SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.chess_games WHERE id = _game_id;
    WHEN 'fanorona' THEN SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.fanorona_games WHERE id = _game_id;
    WHEN 'domino' THEN SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.domino_games WHERE id = _game_id;
    WHEN 'rami' THEN SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.rami_games WHERE id = _game_id;
    WHEN 'poker' THEN SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.poker_games WHERE id = _game_id;
    WHEN 'ludo' THEN SELECT status, paused INTO v_status, v_paused FROM public.ludo_games WHERE id = _game_id;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_status <> 'playing' OR NOT v_paused THEN RETURN; END IF;
  CASE _slug
    WHEN 'chess' THEN UPDATE public.chess_games SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL, turn_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval WHERE id = _game_id AND paused = TRUE AND status = 'playing';
    WHEN 'fanorona' THEN UPDATE public.fanorona_games SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL, turn_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval WHERE id = _game_id AND paused = TRUE AND status = 'playing';
    WHEN 'domino' THEN UPDATE public.domino_games SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL, turn_deadline = now() + (COALESCE(v_remaining_s,60) || ' seconds')::interval WHERE id = _game_id AND paused = TRUE AND status = 'playing';
    WHEN 'rami' THEN UPDATE public.rami_games SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL, turn_deadline = now() + (COALESCE(v_remaining_s,45) || ' seconds')::interval WHERE id = _game_id AND paused = TRUE AND status = 'playing';
    WHEN 'poker' THEN UPDATE public.poker_games SET paused=FALSE, pause_deadline=NULL, paused_turn_remaining_s=NULL, turn_deadline = now() + (COALESCE(v_remaining_s,30) || ' seconds')::interval WHERE id = _game_id AND paused = TRUE AND status = 'playing';
    WHEN 'ludo' THEN UPDATE public.ludo_games SET paused=FALSE, pause_deadline=NULL, state = jsonb_set(state, '{turn_started_at}', to_jsonb(now()::text), true) WHERE id = _game_id AND paused = TRUE AND status = 'playing';
  END CASE;
END $$;

CREATE OR REPLACE FUNCTION public.game_request_pause(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid(); v_status TEXT; v_paused BOOLEAN;
  v_turn_deadline TIMESTAMPTZ; v_turn_timer INT; v_remaining FLOAT;
  v_is_participant BOOLEAN := FALSE;
  v_turn_started_at TIMESTAMPTZ; v_elapsed FLOAT; v_ludo_turn_secs INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.chess_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.chess_games WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid)) INTO v_is_participant;
    WHEN 'fanorona' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.fanorona_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    WHEN 'domino' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.domino_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    WHEN 'rami' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.rami_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    WHEN 'poker' THEN
      SELECT status, paused, turn_deadline INTO v_status, v_paused, v_turn_deadline FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    WHEN 'ludo' THEN
      SELECT status, paused, (state->>'turn_started_at')::timestamptz INTO v_status, v_paused, v_turn_started_at FROM public.ludo_games WHERE id = _game_id;
      v_turn_deadline := NULL;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE) INTO v_is_participant;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;
  IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF v_paused THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;
  IF _slug = 'ludo' THEN
    IF v_turn_started_at IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_elapsed := GREATEST(0, EXTRACT(EPOCH FROM (now() - v_turn_started_at)));
    SELECT COALESCE((SELECT turn_seconds FROM public.app_settings WHERE id = 1), 30) INTO v_ludo_turn_secs;
    IF v_elapsed < (v_ludo_turn_secs * 3.0 / 5.0) THEN RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour'; END IF;
  ELSE
    IF v_turn_deadline IS NULL THEN RAISE EXCEPTION 'pas de tour actif'; END IF;
    v_turn_timer := COALESCE((SELECT turn_timer_seconds FROM public._game_cfg(_slug)), 30);
    v_remaining := GREATEST(0, EXTRACT(EPOCH FROM (v_turn_deadline - now())));
    IF v_remaining > (v_turn_timer * 2.0 / 5.0) THEN RAISE EXCEPTION 'pause disponible seulement après 3/5 du temps de tour'; END IF;
  END IF;
  CASE _slug
    WHEN 'chess' THEN UPDATE public.chess_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'fanorona' THEN UPDATE public.fanorona_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'domino' THEN UPDATE public.domino_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'rami' THEN UPDATE public.rami_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'poker' THEN UPDATE public.poker_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', paused_turn_remaining_s=CEIL(GREATEST(0,EXTRACT(EPOCH FROM (v_turn_deadline-now())))), turn_deadline=NULL WHERE id=_game_id AND status='playing' AND paused=FALSE;
    WHEN 'ludo' THEN UPDATE public.ludo_games SET paused=TRUE, pause_deadline=now()+interval '5 minutes', state=jsonb_set(state,'{turn_started_at}',to_jsonb((now()+interval '1 hour')::text), true) WHERE id=_game_id AND status='playing' AND paused=FALSE;
  END CASE;
END $$;
GRANT EXECUTE ON FUNCTION public.game_request_pause(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.game_resume(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_is_participant BOOLEAN := FALSE; v_status TEXT; v_paused BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.chess_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.chess_games WHERE id=_game_id AND (white_id=v_uid OR black_id=v_uid)) INTO v_is_participant;
    WHEN 'fanorona' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.fanorona_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;
    WHEN 'domino' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.domino_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;
    WHEN 'rami' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.rami_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;
    WHEN 'poker' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.poker_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.poker_players WHERE game_id=_game_id AND user_id=v_uid) INTO v_is_participant;
    WHEN 'ludo' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.ludo_games WHERE id = _game_id;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=FALSE) INTO v_is_participant;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;
  IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT v_paused THEN RETURN; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;
  PERFORM public._game_resume_internal(_slug, _game_id);
END $$;
GRANT EXECUTE ON FUNCTION public.game_resume(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public._auto_resume_paused_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.chess_games WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('chess', r.id); END LOOP;
  FOR r IN SELECT id FROM public.fanorona_games WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('fanorona', r.id); END LOOP;
  FOR r IN SELECT id FROM public.domino_games WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('domino', r.id); END LOOP;
  FOR r IN SELECT id FROM public.rami_games WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('rami', r.id); END LOOP;
  FOR r IN SELECT id FROM public.poker_games WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('poker', r.id); END LOOP;
  FOR r IN SELECT id FROM public.ludo_games WHERE paused=TRUE AND pause_deadline IS NOT NULL AND pause_deadline<now() AND status='playing'
  LOOP PERFORM public._game_resume_internal('ludo', r.id); END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public._auto_advance_overdue_turns()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM public.fanorona_games WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.fanorona_tick(r.id); END LOOP;
  FOR r IN SELECT id FROM public.chess_games WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.chess_tick(r.id); END LOOP;
  FOR r IN SELECT id FROM public.domino_games WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.domino_tick(r.id); END LOOP;
  FOR r IN SELECT id FROM public.rami_games WHERE status='playing' AND paused = FALSE AND turn_deadline IS NOT NULL AND turn_deadline < now()
  LOOP PERFORM public.rami_tick(r.id); END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.tick_all_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._auto_resume_paused_games();
  PERFORM public._auto_cancel_open_games();
  PERFORM public._auto_advance_overdue_turns();
END $$;

-- ============================================================
-- 2) resolve_room_code
-- ============================================================
CREATE OR REPLACE FUNCTION public.resolve_room_code(_code text)
RETURNS TABLE(slug text, game_id uuid)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_code text := upper(trim(_code)); v_id uuid;
BEGIN
  SELECT id INTO v_id FROM public.ludo_games     WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'ludo'::text, v_id; RETURN; END IF;
  SELECT id INTO v_id FROM public.domino_games   WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'domino'::text, v_id; RETURN; END IF;
  SELECT id INTO v_id FROM public.fanorona_games WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'fanorona'::text, v_id; RETURN; END IF;
  SELECT id INTO v_id FROM public.chess_games    WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'chess'::text, v_id; RETURN; END IF;
  SELECT id INTO v_id FROM public.rami_games     WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'rami'::text, v_id; RETURN; END IF;
  SELECT id INTO v_id FROM public.poker_games    WHERE room_code = v_code AND status = 'open' LIMIT 1;
  IF FOUND THEN RETURN QUERY SELECT 'poker'::text, v_id; RETURN; END IF;
  RAISE EXCEPTION 'Code introuvable ou partie déjà commencée : %', v_code;
END $$;
REVOKE ALL ON FUNCTION public.resolve_room_code(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.resolve_room_code(text) TO authenticated;

-- ============================================================
-- 3) withdrawals.recipient_name
-- ============================================================
ALTER TABLE public.withdrawals ADD COLUMN IF NOT EXISTS recipient_name text;
COMMENT ON COLUMN public.withdrawals.recipient_name IS 'Nom complet du destinataire Mobile Money';

-- ============================================================
-- 4) Direct join by ID (chess + rami)
-- ============================================================
CREATE OR REPLACE FUNCTION public.chess_join(_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_g chess_games%ROWTYPE; v_bal numeric; v_flip boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF v_g.status <> 'open' THEN RAISE EXCEPTION 'partie déjà commencée ou terminée'; END IF;
  IF v_g.host_id = v_uid THEN RAISE EXCEPTION 'tu es déjà dans cette partie'; END IF;
  IF v_g.is_private THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid;
  IF v_bal < v_g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  v_flip := (random() < 0.5);
  IF v_flip THEN
    UPDATE chess_games SET black_id = v_uid, status = 'playing', started_at = now(), pot = pot + v_g.stake WHERE id = v_g.id;
  ELSE
    UPDATE chess_games SET white_id = v_uid, black_id = v_g.host_id, status = 'playing', started_at = now(), pot = pot + v_g.stake WHERE id = v_g.id;
  END IF;
  UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, ref_id, note)
    VALUES (v_uid, 'chess_stake', -v_g.stake, v_g.id, 'Rejoindre partie chess publique');
  RETURN v_g.id;
END $$;
REVOKE ALL ON FUNCTION public.chess_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_join(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.rami_join(_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _uid uuid := auth.uid(); _g rami_games%ROWTYPE;
  _slot int; _bal numeric; _name text; _count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM rami_games WHERE id = _game_id FOR UPDATE;
  IF _g.id IS NULL THEN RAISE EXCEPTION 'partie introuvable'; END IF;
  IF _g.status <> 'waiting' THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF _g.is_private THEN RAISE EXCEPTION 'partie privée — utilise le code pour rejoindre'; END IF;
  IF EXISTS (SELECT 1 FROM rami_participants WHERE game_id = _g.id AND user_id = _uid) THEN RETURN _g.id; END IF;
  SELECT count(*) INTO _count FROM rami_participants WHERE game_id = _g.id;
  IF _count >= _g.max_players THEN RAISE EXCEPTION 'partie pleine'; END IF;
  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO _bal, _name FROM profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  _slot := _count;
  IF _g.stake > 0 THEN
    UPDATE profiles SET balance_ar = balance_ar - _g.stake WHERE id = _uid;
    UPDATE rami_games SET pot = pot + _g.stake WHERE id = _g.id;
    INSERT INTO transactions (user_id, type, amount, ref_id, note)
      VALUES (_uid, 'rami_stake', -_g.stake, _g.id, 'Join rami');
  END IF;
  INSERT INTO rami_participants(game_id, user_id, slot, display_name) VALUES (_g.id, _uid, _slot, _name);
  RETURN _g.id;
END $$;
REVOKE ALL ON FUNCTION public.rami_join(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_join(uuid) TO authenticated;

-- ============================================================
-- 5) app_settings.referral_enabled
-- ============================================================
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS referral_enabled BOOLEAN NOT NULL DEFAULT true;

-- ============================================================
-- 6) Admin persona
-- ============================================================
CREATE TABLE IF NOT EXISTS public.admin_persona (
  admin_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  real_pseudo TEXT NOT NULL DEFAULT '',
  real_avatar_url TEXT,
  persona_pseudo TEXT,
  persona_avatar TEXT,
  is_active BOOLEAN NOT NULL DEFAULT false,
  activated_at TIMESTAMPTZ
);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.admin_persona TO authenticated;
GRANT ALL ON public.admin_persona TO service_role;
ALTER TABLE public.admin_persona ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "persona_own" ON public.admin_persona;
CREATE POLICY "persona_own" ON public.admin_persona
  USING (admin_id = auth.uid()) WITH CHECK (admin_id = auth.uid());

CREATE OR REPLACE FUNCTION public.admin_activate_persona(p_pseudo TEXT, p_avatar_url TEXT DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_real_pseudo TEXT; v_real_avatar_url TEXT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT pseudo, avatar_url INTO v_real_pseudo, v_real_avatar_url FROM public.profiles WHERE id = auth.uid();
  INSERT INTO public.admin_persona (admin_id, real_pseudo, real_avatar_url, persona_pseudo, persona_avatar, is_active, activated_at)
  VALUES (auth.uid(), v_real_pseudo, v_real_avatar_url, p_pseudo, p_avatar_url, true, now())
  ON CONFLICT (admin_id) DO UPDATE
    SET persona_pseudo = EXCLUDED.persona_pseudo,
        persona_avatar = EXCLUDED.persona_avatar,
        is_active = true, activated_at = now(),
        real_pseudo = CASE WHEN admin_persona.is_active THEN admin_persona.real_pseudo ELSE EXCLUDED.real_pseudo END,
        real_avatar_url = CASE WHEN admin_persona.is_active THEN admin_persona.real_avatar_url ELSE EXCLUDED.real_avatar_url END;
  UPDATE public.profiles SET pseudo = p_pseudo, avatar_url = p_avatar_url WHERE id = auth.uid();
END $$;

CREATE OR REPLACE FUNCTION public.admin_deactivate_persona()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_real_pseudo TEXT; v_real_avatar_url TEXT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT real_pseudo, real_avatar_url INTO v_real_pseudo, v_real_avatar_url FROM public.admin_persona WHERE admin_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Aucun alias actif trouvé'; END IF;
  UPDATE public.profiles SET pseudo = v_real_pseudo, avatar_url = v_real_avatar_url WHERE id = auth.uid();
  UPDATE public.admin_persona SET is_active = false WHERE admin_id = auth.uid();
END $$;

CREATE OR REPLACE FUNCTION public.admin_get_persona()
RETURNS TABLE(is_active BOOLEAN, real_pseudo TEXT, real_avatar_url TEXT, persona_pseudo TEXT, persona_avatar TEXT, activated_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY SELECT ap.is_active, ap.real_pseudo, ap.real_avatar_url, ap.persona_pseudo, ap.persona_avatar, ap.activated_at
    FROM public.admin_persona ap WHERE ap.admin_id = auth.uid();
END $$;

-- ============================================================
-- 7) leaderboard_winners (persona-aware, deduped, slug filter)
--    poker_players has no display_name → use NULL for poker
-- ============================================================
DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int);
DROP FUNCTION IF EXISTS public.leaderboard_winners(text, int, text);

CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all', _limit int DEFAULT 20, _slug text DEFAULT NULL
)
RETURNS TABLE(rank int, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH bound AS (
    SELECT CASE _period WHEN 'week' THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days' ELSE 'epoch'::timestamptz END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won,
           COALESCE(g.finished_at, g.created_at) AS at
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug='all' OR _slug='ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug='all' OR _slug='domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug='all' OR _slug='fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug='all' OR _slug='rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug='all' OR _slug='chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0),
           COALESCE(g.finished_at, g.created_at)
      FROM poker_games g, bound
      WHERE (_slug IS NULL OR _slug='all' OR _slug='poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    SELECT r.uid, r.dn, r.won, r.at FROM raw r
    WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
       OR EXISTS (SELECT 1 FROM public.admin_persona ap WHERE ap.admin_id = r.uid AND ap.is_active)
  ),
  named AS (
    SELECT f.uid, f.won, f.at,
           COALESCE(p.pseudo, f.dn, 'Joueur') AS name, p.avatar_url
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT uid, count(*)::bigint AS wins, COALESCE(sum(won),0)::numeric AS total_won
    FROM named GROUP BY uid
  ),
  latest_name AS (
    SELECT DISTINCT ON (uid) uid, name, avatar_url
    FROM named ORDER BY uid, at DESC
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, ln.name ASC))::int AS rank,
         a.uid AS user_id, ln.name, ln.avatar_url, a.wins, a.total_won
  FROM agg a JOIN latest_name ln ON ln.uid = a.uid
  ORDER BY a.wins DESC, ln.name ASC LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text, int, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, int, text) TO authenticated, anon;
