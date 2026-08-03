DROP FUNCTION IF EXISTS public.claim_daily_bonus();
DROP FUNCTION IF EXISTS public.check_pseudo_available(TEXT);
DROP FUNCTION IF EXISTS public.list_players_for_dm();

CREATE OR REPLACE FUNCTION public.check_pseudo_available(p_pseudo TEXT)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT NOT EXISTS (SELECT 1 FROM public.profiles WHERE lower(pseudo) = lower(trim(p_pseudo))); $$;
GRANT EXECUTE ON FUNCTION public.check_pseudo_available(TEXT) TO anon, authenticated;

CREATE OR REPLACE FUNCTION public.claim_daily_bonus()
RETURNS json LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_last_date date; v_streak int; v_new_streak int; v_bonus numeric;
  v_today date := (now() at time zone 'Indian/Antananarivo')::date;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT last_daily_claim::date, coalesce(daily_streak, 0) INTO v_last_date, v_streak
    FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_last_date = v_today THEN
    RETURN json_build_object('success', false, 'already_claimed', true, 'streak', v_streak);
  END IF;
  IF v_last_date = v_today - 1 THEN v_new_streak := v_streak + 1; ELSE v_new_streak := 1; END IF;
  IF v_new_streak > 7 THEN v_new_streak := 1; END IF;
  v_bonus := 300 + (v_new_streak * 200);
  IF v_new_streak = 7 THEN v_bonus := v_bonus + 2000; END IF;
  UPDATE public.profiles SET balance_ar = balance_ar + v_bonus, daily_streak = v_new_streak, last_daily_claim = now() WHERE id = v_uid;
  RETURN json_build_object('success', true, 'already_claimed', false, 'streak', v_new_streak, 'bonus', v_bonus);
END $$;
GRANT EXECUTE ON FUNCTION public.claim_daily_bonus() TO authenticated;

ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS contact_whatsapp TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_facebook TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS contact_email TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS terms_text TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS privacy_text TEXT NOT NULL DEFAULT '',
  ADD COLUMN IF NOT EXISTS faq_text TEXT NOT NULL DEFAULT '';

ALTER TABLE public.game_configs ADD COLUMN IF NOT EXISTS badge TEXT DEFAULT NULL;
ALTER TABLE public.game_configs DROP CONSTRAINT IF EXISTS game_configs_badge_check;
ALTER TABLE public.game_configs ADD CONSTRAINT game_configs_badge_check CHECK (badge IS NULL OR badge IN ('new', 'coming_soon', 'hot'));
UPDATE public.game_configs SET cover_url = '/covers/cover_ludo.png'     WHERE slug = 'ludo'     AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_domino.png'   WHERE slug = 'domino'   AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_fanorona.png' WHERE slug = 'fanorona' AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_chess.png'    WHERE slug = 'chess'    AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_rami.png'     WHERE slug = 'rami'     AND (cover_url IS NULL OR cover_url = '');
UPDATE public.game_configs SET cover_url = '/covers/cover_poker.png'    WHERE slug = 'poker'    AND (cover_url IS NULL OR cover_url = '');

ALTER TABLE public.ludo_games     ADD COLUMN IF NOT EXISTS afk_warning JSONB, ADD COLUMN IF NOT EXISTS afk_pause_for UUID REFERENCES public.profiles(id), ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;
ALTER TABLE public.chess_games    ADD COLUMN IF NOT EXISTS afk_warning JSONB, ADD COLUMN IF NOT EXISTS afk_pause_for UUID REFERENCES public.profiles(id), ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;
ALTER TABLE public.fanorona_games ADD COLUMN IF NOT EXISTS afk_warning JSONB, ADD COLUMN IF NOT EXISTS afk_pause_for UUID REFERENCES public.profiles(id), ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;
ALTER TABLE public.domino_games   ADD COLUMN IF NOT EXISTS afk_warning JSONB, ADD COLUMN IF NOT EXISTS afk_pause_for UUID REFERENCES public.profiles(id), ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;
ALTER TABLE public.rami_games     ADD COLUMN IF NOT EXISTS afk_warning JSONB, ADD COLUMN IF NOT EXISTS afk_pause_for UUID REFERENCES public.profiles(id), ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;
ALTER TABLE public.poker_games    ADD COLUMN IF NOT EXISTS afk_warning JSONB, ADD COLUMN IF NOT EXISTS afk_pause_for UUID REFERENCES public.profiles(id), ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

UPDATE public.app_settings SET afk_t1_max = 5 WHERE id = 1 AND afk_t1_max <= 2;

CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_t1 int; v_t2 int; v_max1 int; v_max2 int; v_enabled boolean;
  v_uid uuid; v_isbot boolean; v_name text; v_winner uuid;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max INTO v_enabled, v_max1, v_max2 FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;
  SELECT afk_t1, afk_t2, user_id, is_bot, display_name INTO v_t1, v_t2, v_uid, v_isbot, v_name
    FROM public.ludo_participants WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;
  IF v_t1 >= COALESCE(v_max1, 5) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants SET forfeited = TRUE WHERE game_id = _game_id AND slot = _slot;
    UPDATE public.ludo_games SET afk_warning = NULL, afk_pause_for = NULL, afk_pause_name = NULL WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id, 'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN PERFORM public.finish_game(_game_id, v_winner); END IF;
    RETURN;
  END IF;
  IF v_t1 = COALESCE(v_max1, 5) - 1 THEN
    UPDATE public.ludo_games SET afk_warning = jsonb_build_object(
      'uid', v_uid, 'name', COALESCE(v_name, 'Joueur'), 'slot', _slot,
      't1', v_t1, 't1_max', COALESCE(v_max1, 5), 'votes', '[]'::jsonb, 'votes_needed', 0,
      'ts', extract(epoch from now())::bigint)
     WHERE id = _game_id AND paused = FALSE AND (afk_warning IS NULL OR (afk_warning->>'uid')::uuid <> v_uid);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public._trg_afk_warning_non_ludo()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_max INT; v_slug TEXT; v_key TEXT; v_count INT; v_name TEXT;
BEGIN
  IF NEW.status <> 'playing' OR COALESCE(NEW.paused, FALSE) THEN RETURN NEW; END IF;
  IF NEW.turn_skips IS NOT DISTINCT FROM OLD.turn_skips THEN RETURN NEW; END IF;
  v_slug := CASE TG_TABLE_NAME WHEN 'chess_games' THEN 'chess' WHEN 'fanorona_games' THEN 'fanorona'
    WHEN 'domino_games' THEN 'domino' WHEN 'rami_games' THEN 'rami' WHEN 'poker_games' THEN 'poker' ELSE NULL END;
  IF v_slug IS NULL THEN RETURN NEW; END IF;
  SELECT max_turn_skips INTO v_max FROM public.game_configs WHERE slug = v_slug;
  IF v_max IS NULL OR v_max <= 1 THEN RETURN NEW; END IF;
  FOR v_key, v_count IN SELECT key, value::int FROM jsonb_each_text(NEW.turn_skips) LOOP
    IF v_count = v_max - 1 THEN
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_key::uuid;
      NEW.afk_warning := jsonb_build_object('uid', v_key, 'name', COALESCE(v_name, 'Joueur'),
        'skips', v_count, 'max', v_max, 'votes', '[]'::jsonb, 'votes_needed', 0,
        'ts', extract(epoch from now())::bigint);
      RETURN NEW;
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_afk_warning ON public.chess_games;
CREATE TRIGGER trg_afk_warning BEFORE UPDATE ON public.chess_games FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();
DROP TRIGGER IF EXISTS trg_afk_warning ON public.fanorona_games;
CREATE TRIGGER trg_afk_warning BEFORE UPDATE ON public.fanorona_games FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();
DROP TRIGGER IF EXISTS trg_afk_warning ON public.domino_games;
CREATE TRIGGER trg_afk_warning BEFORE UPDATE ON public.domino_games FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();
DROP TRIGGER IF EXISTS trg_afk_warning ON public.rami_games;
CREATE TRIGGER trg_afk_warning BEFORE UPDATE ON public.rami_games FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();
DROP TRIGGER IF EXISTS trg_afk_warning ON public.poker_games;
CREATE TRIGGER trg_afk_warning BEFORE UPDATE ON public.poker_games FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();

DROP FUNCTION IF EXISTS public.game_request_afk_pause(TEXT, UUID);
CREATE OR REPLACE FUNCTION public.game_request_afk_pause(_slug TEXT, _game_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_status TEXT; v_paused BOOLEAN; v_warning JSONB; v_afk_uid UUID;
  v_is_participant BOOLEAN := FALSE; v_remaining_s INT; v_votes JSONB; v_votes_needed INT; v_active_count INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  CASE _slug
    WHEN 'ludo' THEN
      SELECT status, paused, afk_warning INTO v_status, v_paused, v_warning FROM public.ludo_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE AND forfeited = FALSE) INTO v_is_participant;
    WHEN 'chess' THEN
      SELECT status, paused, afk_warning, CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now())))) INTO v_status, v_paused, v_warning, v_remaining_s FROM public.chess_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(SELECT 1 FROM public.chess_games WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid)) INTO v_is_participant;
    WHEN 'fanorona' THEN
      SELECT status, paused, afk_warning, CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now())))) INTO v_status, v_paused, v_warning, v_remaining_s FROM public.fanorona_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = FALSE) INTO v_is_participant;
    WHEN 'domino' THEN
      SELECT status, paused, afk_warning, CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now())))) INTO v_status, v_paused, v_warning, v_remaining_s FROM public.domino_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = FALSE) INTO v_is_participant;
    WHEN 'rami' THEN
      SELECT status, paused, afk_warning, CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now())))) INTO v_status, v_paused, v_warning, v_remaining_s FROM public.rami_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND user_id = v_uid AND forfeited = FALSE) INTO v_is_participant;
    WHEN 'poker' THEN
      SELECT status, paused, afk_warning, CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now())))) INTO v_status, v_paused, v_warning, v_remaining_s FROM public.poker_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(SELECT 1 FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;
  IF v_status <> 'playing' THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;
  IF v_warning IS NULL THEN RAISE EXCEPTION 'aucun joueur en état AFK critique'; END IF;
  v_afk_uid := (v_warning->>'uid')::uuid;
  IF v_uid = v_afk_uid THEN RAISE EXCEPTION 'vous ne pouvez pas déclencher votre propre pause AFK'; END IF;
  v_votes := COALESCE(v_warning->'votes', '[]'::jsonb);
  IF v_votes @> to_jsonb(ARRAY[v_uid::text]) THEN RETURN jsonb_build_object('status', 'already_voted'); END IF;
  v_votes := v_votes || to_jsonb(ARRAY[v_uid::text]);
  CASE _slug
    WHEN 'ludo' THEN SELECT COUNT(*) INTO v_active_count FROM public.ludo_participants WHERE game_id = _game_id AND is_bot = FALSE AND forfeited = FALSE AND user_id <> v_afk_uid;
    WHEN 'chess' THEN v_active_count := 1;
    WHEN 'fanorona' THEN SELECT COUNT(*) INTO v_active_count FROM public.fanorona_participants WHERE game_id = _game_id AND forfeited = FALSE AND user_id <> v_afk_uid;
    WHEN 'domino' THEN SELECT COUNT(*) INTO v_active_count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = FALSE AND user_id <> v_afk_uid;
    WHEN 'rami' THEN SELECT COUNT(*) INTO v_active_count FROM public.rami_participants WHERE game_id = _game_id AND forfeited = FALSE AND user_id <> v_afk_uid;
    WHEN 'poker' THEN SELECT COUNT(*) INTO v_active_count FROM public.poker_players WHERE game_id = _game_id AND user_id <> v_afk_uid;
  END CASE;
  v_votes_needed := GREATEST(1, CEIL(v_active_count::numeric / 2));
  IF jsonb_array_length(v_votes) < v_votes_needed THEN
    CASE _slug
      WHEN 'ludo'     THEN UPDATE public.ludo_games     SET afk_warning = jsonb_set(jsonb_set(afk_warning, '{votes}', v_votes), '{votes_needed}', to_jsonb(v_votes_needed)) WHERE id = _game_id;
      WHEN 'chess'    THEN UPDATE public.chess_games    SET afk_warning = jsonb_set(jsonb_set(afk_warning, '{votes}', v_votes), '{votes_needed}', to_jsonb(v_votes_needed)) WHERE id = _game_id;
      WHEN 'fanorona' THEN UPDATE public.fanorona_games SET afk_warning = jsonb_set(jsonb_set(afk_warning, '{votes}', v_votes), '{votes_needed}', to_jsonb(v_votes_needed)) WHERE id = _game_id;
      WHEN 'domino'   THEN UPDATE public.domino_games   SET afk_warning = jsonb_set(jsonb_set(afk_warning, '{votes}', v_votes), '{votes_needed}', to_jsonb(v_votes_needed)) WHERE id = _game_id;
      WHEN 'rami'     THEN UPDATE public.rami_games     SET afk_warning = jsonb_set(jsonb_set(afk_warning, '{votes}', v_votes), '{votes_needed}', to_jsonb(v_votes_needed)) WHERE id = _game_id;
      WHEN 'poker'    THEN UPDATE public.poker_games    SET afk_warning = jsonb_set(jsonb_set(afk_warning, '{votes}', v_votes), '{votes_needed}', to_jsonb(v_votes_needed)) WHERE id = _game_id;
    END CASE;
    RETURN jsonb_build_object('status', 'vote_registered', 'votes', jsonb_array_length(v_votes), 'votes_needed', v_votes_needed);
  END IF;
  CASE _slug
    WHEN 'ludo' THEN UPDATE public.ludo_games SET paused = TRUE, pause_deadline = now() + interval '3 minutes', afk_pause_for = v_afk_uid, afk_pause_name = v_warning->>'name', afk_warning = NULL, state = jsonb_set(state, '{turn_started_at}', to_jsonb((now() + interval '1 hour')::text), true) WHERE id = _game_id;
    WHEN 'chess' THEN UPDATE public.chess_games SET paused = TRUE, pause_deadline = now() + interval '3 minutes', paused_turn_remaining_s = COALESCE(v_remaining_s, 30), turn_deadline = NULL, afk_pause_for = v_afk_uid, afk_pause_name = v_warning->>'name', afk_warning = NULL WHERE id = _game_id;
    WHEN 'fanorona' THEN UPDATE public.fanorona_games SET paused = TRUE, pause_deadline = now() + interval '3 minutes', paused_turn_remaining_s = COALESCE(v_remaining_s, 60), turn_deadline = NULL, afk_pause_for = v_afk_uid, afk_pause_name = v_warning->>'name', afk_warning = NULL WHERE id = _game_id;
    WHEN 'domino' THEN UPDATE public.domino_games SET paused = TRUE, pause_deadline = now() + interval '3 minutes', paused_turn_remaining_s = COALESCE(v_remaining_s, 60), turn_deadline = NULL, afk_pause_for = v_afk_uid, afk_pause_name = v_warning->>'name', afk_warning = NULL WHERE id = _game_id;
    WHEN 'rami' THEN UPDATE public.rami_games SET paused = TRUE, pause_deadline = now() + interval '3 minutes', paused_turn_remaining_s = COALESCE(v_remaining_s, 45), turn_deadline = NULL, afk_pause_for = v_afk_uid, afk_pause_name = v_warning->>'name', afk_warning = NULL WHERE id = _game_id;
    WHEN 'poker' THEN UPDATE public.poker_games SET paused = TRUE, pause_deadline = now() + interval '3 minutes', paused_turn_remaining_s = COALESCE(v_remaining_s, 30), turn_deadline = NULL, afk_pause_for = v_afk_uid, afk_pause_name = v_warning->>'name', afk_warning = NULL WHERE id = _game_id;
  END CASE;
  RETURN jsonb_build_object('status', 'paused', 'votes', jsonb_array_length(v_votes), 'votes_needed', v_votes_needed);
END $$;
GRANT EXECUTE ON FUNCTION public.game_request_afk_pause(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public._afk_forfeit_player(_slug TEXT, _game_id UUID, _uid UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_max_skips INT; v_slot INT;
BEGIN
  CASE _slug
    WHEN 'ludo' THEN
      UPDATE public.ludo_participants SET afk_t1 = 99 WHERE game_id = _game_id AND user_id = _uid;
      UPDATE public.ludo_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, state = jsonb_set(state, '{turn_started_at}', to_jsonb(now()::text), true) WHERE id = _game_id;
      SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id = _game_id AND user_id = _uid;
      IF FOUND THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
    ELSE
      SELECT max_turn_skips INTO v_max_skips FROM public.game_configs WHERE slug = _slug;
      v_max_skips := COALESCE(v_max_skips, 5);
      CASE _slug
        WHEN 'chess' THEN UPDATE public.chess_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_skips = COALESCE(turn_skips, '{}'::jsonb) || jsonb_build_object(_uid::text, v_max_skips + 1), turn_deadline = now() - interval '1 second' WHERE id = _game_id;
        WHEN 'fanorona' THEN UPDATE public.fanorona_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_skips = COALESCE(turn_skips, '{}'::jsonb) || jsonb_build_object(_uid::text, v_max_skips + 1), turn_deadline = now() - interval '1 second' WHERE id = _game_id;
        WHEN 'domino' THEN UPDATE public.domino_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_skips = COALESCE(turn_skips, '{}'::jsonb) || jsonb_build_object(_uid::text, v_max_skips + 1), turn_deadline = now() - interval '1 second' WHERE id = _game_id;
        WHEN 'rami' THEN UPDATE public.rami_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_skips = COALESCE(turn_skips, '{}'::jsonb) || jsonb_build_object(_uid::text, v_max_skips + 1), turn_deadline = now() - interval '1 second' WHERE id = _game_id;
        WHEN 'poker' THEN UPDATE public.poker_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_skips = COALESCE(turn_skips, '{}'::jsonb) || jsonb_build_object(_uid::text, v_max_skips + 1), turn_deadline = now() - interval '1 second' WHERE id = _game_id;
      END CASE;
  END CASE;
END $$;

CREATE OR REPLACE FUNCTION public.game_resume(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_status TEXT; v_paused BOOLEAN; v_remaining_s INTEGER; v_is_participant BOOLEAN := FALSE;
BEGIN
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.chess_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN SELECT EXISTS(SELECT 1 FROM public.chess_games WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid)) INTO v_is_participant; ELSE v_is_participant := TRUE; END IF;
    WHEN 'fanorona' THEN
      SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.fanorona_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN SELECT EXISTS(SELECT 1 FROM public.fanorona_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant; ELSE v_is_participant := TRUE; END IF;
    WHEN 'domino' THEN
      SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.domino_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN SELECT EXISTS(SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant; ELSE v_is_participant := TRUE; END IF;
    WHEN 'rami' THEN
      SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.rami_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN SELECT EXISTS(SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant; ELSE v_is_participant := TRUE; END IF;
    WHEN 'poker' THEN
      SELECT status, paused, paused_turn_remaining_s INTO v_status, v_paused, v_remaining_s FROM public.poker_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN SELECT EXISTS(SELECT 1 FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid) INTO v_is_participant; ELSE v_is_participant := TRUE; END IF;
    WHEN 'ludo' THEN
      SELECT status, paused INTO v_status, v_paused FROM public.ludo_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN SELECT EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE) INTO v_is_participant; ELSE v_is_participant := TRUE; END IF;
    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;
  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT v_paused THEN RETURN; END IF;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;
  CASE _slug
    WHEN 'chess' THEN UPDATE public.chess_games SET paused = FALSE, pause_deadline = NULL, paused_turn_remaining_s = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_deadline = now() + (COALESCE(v_remaining_s, 30) || ' seconds')::interval WHERE id = _game_id;
    WHEN 'fanorona' THEN UPDATE public.fanorona_games SET paused = FALSE, pause_deadline = NULL, paused_turn_remaining_s = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_deadline = now() + (COALESCE(v_remaining_s, 60) || ' seconds')::interval WHERE id = _game_id;
    WHEN 'domino' THEN UPDATE public.domino_games SET paused = FALSE, pause_deadline = NULL, paused_turn_remaining_s = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_deadline = now() + (COALESCE(v_remaining_s, 60) || ' seconds')::interval WHERE id = _game_id;
    WHEN 'rami' THEN UPDATE public.rami_games SET paused = FALSE, pause_deadline = NULL, paused_turn_remaining_s = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_deadline = now() + (COALESCE(v_remaining_s, 45) || ' seconds')::interval WHERE id = _game_id;
    WHEN 'poker' THEN UPDATE public.poker_games SET paused = FALSE, pause_deadline = NULL, paused_turn_remaining_s = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, turn_deadline = now() + (COALESCE(v_remaining_s, 30) || ' seconds')::interval WHERE id = _game_id;
    WHEN 'ludo' THEN UPDATE public.ludo_games SET paused = FALSE, pause_deadline = NULL, afk_pause_for = NULL, afk_pause_name = NULL, afk_warning = NULL, state = jsonb_set(state, '{turn_started_at}', to_jsonb(now()::text), true) WHERE id = _game_id;
  END CASE;
END $$;
GRANT EXECUTE ON FUNCTION public.game_resume(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public._auto_resume_paused_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id, afk_pause_for FROM public.chess_games WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing' LOOP
    IF r.afk_pause_for IS NOT NULL THEN PERFORM public._afk_forfeit_player('chess', r.id, r.afk_pause_for); ELSE PERFORM public.game_resume('chess', r.id); END IF;
  END LOOP;
  FOR r IN SELECT id, afk_pause_for FROM public.fanorona_games WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing' LOOP
    IF r.afk_pause_for IS NOT NULL THEN PERFORM public._afk_forfeit_player('fanorona', r.id, r.afk_pause_for); ELSE PERFORM public.game_resume('fanorona', r.id); END IF;
  END LOOP;
  FOR r IN SELECT id, afk_pause_for FROM public.domino_games WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing' LOOP
    IF r.afk_pause_for IS NOT NULL THEN PERFORM public._afk_forfeit_player('domino', r.id, r.afk_pause_for); ELSE PERFORM public.game_resume('domino', r.id); END IF;
  END LOOP;
  FOR r IN SELECT id, afk_pause_for FROM public.rami_games WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing' LOOP
    IF r.afk_pause_for IS NOT NULL THEN PERFORM public._afk_forfeit_player('rami', r.id, r.afk_pause_for); ELSE PERFORM public.game_resume('rami', r.id); END IF;
  END LOOP;
  FOR r IN SELECT id, afk_pause_for FROM public.poker_games WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing' LOOP
    IF r.afk_pause_for IS NOT NULL THEN PERFORM public._afk_forfeit_player('poker', r.id, r.afk_pause_for); ELSE PERFORM public.game_resume('poker', r.id); END IF;
  END LOOP;
  FOR r IN SELECT id, afk_pause_for FROM public.ludo_games WHERE paused = TRUE AND pause_deadline IS NOT NULL AND pause_deadline < now() AND status = 'playing' LOOP
    IF r.afk_pause_for IS NOT NULL THEN PERFORM public._afk_forfeit_player('ludo', r.id, r.afk_pause_for); ELSE PERFORM public.game_resume('ludo', r.id); END IF;
  END LOOP;
END $$;

DO $$
DECLARE v_keep uuid; v_dupe uuid;
BEGIN
  SELECT id INTO v_keep FROM public.chat_rooms WHERE type = 'global' ORDER BY created_at ASC LIMIT 1;
  IF v_keep IS NOT NULL THEN
    FOR v_dupe IN SELECT id FROM public.chat_rooms WHERE type = 'global' AND id <> v_keep LOOP
      UPDATE public.chat_messages SET room_id = v_keep WHERE room_id = v_dupe;
      DELETE FROM public.chat_members WHERE room_id = v_dupe;
      DELETE FROM public.chat_rooms WHERE id = v_dupe;
    END LOOP;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.list_players_for_dm()
RETURNS TABLE(id uuid, pseudo text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.pseudo, p.avatar_url FROM public.profiles p
  WHERE p.id <> auth.uid() ORDER BY p.pseudo ASC
$$;
GRANT EXECUTE ON FUNCTION public.list_players_for_dm() TO authenticated;

DROP FUNCTION IF EXISTS public.create_public_game(int, numeric);
DROP FUNCTION IF EXISTS public.create_public_game(int, numeric, text);
CREATE OR REPLACE FUNCTION public.create_public_game(_max_players int, _stake numeric, _mode text DEFAULT 'classic')
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid uuid := auth.uid(); v_balance numeric; v_id uuid; v_mode text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  IF _stake > 0 THEN
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note) VALUES (v_uid, 'ludo_stake', -_stake, 'Mise Ludo');
  END IF;
  INSERT INTO public.ludo_games(host_id, max_players, stake, status, is_private, pot, mode)
    VALUES (v_uid, _max_players, _stake, 'open', false, _stake, v_mode) RETURNING id INTO v_id;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    SELECT v_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.create_public_game(int, numeric, text) TO authenticated;

CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p record; cur_sum integer; best_sum integer := 2147483647; best_slot integer := NULL; tie_count integer := 0;
BEGIN
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    cur_sum := public._domino_hand_pips(COALESCE(_state -> 'hands' -> p.slot::text, '[]'::jsonb));
    IF cur_sum < best_sum THEN best_sum := cur_sum; best_slot := p.slot; tie_count := 1;
    ELSIF cur_sum = best_sum THEN tie_count := tie_count + 1; END IF;
  END LOOP;
  IF tie_count > 1 THEN RETURN NULL; END IF;
  RETURN best_slot;
END $$;

CREATE OR REPLACE FUNCTION public._domino_finalize(_game_id uuid, _winner_slot int)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE g record; winner_uid uuid; payout numeric; p record; n_active integer; refund_each numeric;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status = 'finished' THEN RETURN; END IF;
  IF _winner_slot IS NULL THEN
    SELECT count(*) INTO n_active FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF n_active > 0 AND g.pot > 0 THEN
      refund_each := floor(g.pot / n_active);
      FOR p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + refund_each WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (p.user_id, 'domino_draw', refund_each, _game_id, 'Domino match nul – remboursement');
      END LOOP;
    END IF;
    UPDATE public.domino_games SET status = 'finished', winner_id = NULL, finished_at = now() WHERE id = _game_id;
    RETURN;
  END IF;
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  payout := g.pot * (100 - g.commission_pct) / 100;
  IF winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + payout WHERE id = winner_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (winner_uid, 'domino_win', payout, _game_id, 'Domino win');
  END IF;
  UPDATE public.domino_games SET status = 'finished', winner_id = winner_uid, finished_at = now() WHERE id = _game_id;
END $$;

CREATE OR REPLACE FUNCTION public._domino_end_round(_game_id uuid, _winner_slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'extensions' AS $$
DECLARE g record; st jsonb; winner_uid uuid; round_score int := 0;
  hand_pips jsonb := '{}'::jsonb; v_final_hands jsonb := '{}'::jsonb;
  p record; pips int; v_scores jsonb; new_total int; v_blocked boolean := false;
  winner_hand jsonb; v_reveal interval := interval '3 seconds'; v_break_total interval := interval '13 seconds';
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  IF _winner_slot IS NULL THEN
    st := g.state;
    FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
      pips := public._domino_hand_pips(st->'hands'->p.slot::text);
      hand_pips := hand_pips || jsonb_build_object(p.user_id::text, pips);
      v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    END LOOP;
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
    st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
    st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', NULL::text, 'round_score', 0, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', true, 'draw', true, 'final', false));
    st := jsonb_set(st, '{scores}', COALESCE(g.scores, '{}'::jsonb));
    UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
    RETURN;
  END IF;
  SELECT user_id INTO winner_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = _winner_slot;
  st := g.state;
  winner_hand := st->'hands'->_winner_slot::text;
  v_blocked := COALESCE(jsonb_array_length(winner_hand), 0) > 0;
  FOR p IN SELECT slot, user_id FROM public.domino_participants WHERE game_id = _game_id LOOP
    pips := public._domino_hand_pips(st->'hands'->p.slot::text);
    hand_pips := hand_pips || jsonb_build_object(p.user_id::text, pips);
    v_final_hands := v_final_hands || jsonb_build_object(p.user_id::text, COALESCE(st->'hands'->p.slot::text, '[]'::jsonb));
    IF p.slot <> _winner_slot THEN round_score := round_score + pips; END IF;
  END LOOP;
  IF COALESCE(g.target_score, 0) <= 0 THEN PERFORM public._domino_finalize(_game_id, _winner_slot); RETURN; END IF;
  v_scores := COALESCE(g.scores, '{}'::jsonb);
  new_total := COALESCE((v_scores->>winner_uid::text)::int, 0) + round_score;
  v_scores := jsonb_set(v_scores, ARRAY[winner_uid::text], to_jsonb(new_total), true);
  UPDATE public.domino_games SET scores = v_scores WHERE id = _game_id;
  IF new_total >= g.target_score THEN
    st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
    st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
    st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
    st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', winner_uid::text, 'round_score', round_score, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', v_blocked, 'draw', false, 'final', true));
    st := jsonb_set(st, '{scores}', v_scores);
    UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
    PERFORM public._domino_finalize(_game_id, _winner_slot);
    RETURN;
  END IF;
  st := jsonb_set(st, '{phase}', '"reveal"'::jsonb);
  st := jsonb_set(st, '{reveal_until}', to_jsonb((now() + v_reveal)::text));
  st := jsonb_set(st, '{break_until}',  to_jsonb((now() + v_break_total)::text));
  st := jsonb_set(st, '{last_round}', jsonb_build_object('winner_uid', winner_uid::text, 'round_score', round_score, 'hand_pips', hand_pips, 'final_hands', v_final_hands, 'blocked', v_blocked, 'draw', false, 'final', false));
  st := jsonb_set(st, '{scores}', v_scores);
  UPDATE public.domino_games SET state = st, turn_deadline = NULL WHERE id = _game_id;
END $$;