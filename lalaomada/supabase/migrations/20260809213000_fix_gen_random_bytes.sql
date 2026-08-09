-- Fix: gen_random_bytes(integer) does not exist
-- pgcrypto is in the `extensions` schema, but these 5 functions use bare gen_random_bytes
-- with search_path = public only. Fix: add 'extensions' to search_path AND qualify the call.

-- 1) chess_draw_spin
CREATE OR REPLACE FUNCTION public.chess_draw_spin(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE; v_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RETURN; END IF;
  IF v_uid <> v_g.white_id AND v_uid <> v_g.black_id THEN RAISE EXCEPTION 'not a player'; END IF;
  IF v_g.draw_white_by IS NULL OR v_g.draw_black_by IS NULL THEN RAISE EXCEPTION 'colors not chosen yet'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  v_color := CASE WHEN (get_byte(extensions.gen_random_bytes(1),0) % 2) = 0 THEN 'w' ELSE 'b' END;
  UPDATE public.chess_games
     SET draw_result_color = v_color,
         draw_revealed_at = now(),
         draw_spun_by = v_uid
   WHERE id=_game_id AND draw_result_color IS NULL;
END; $function$;

-- 2) chess_set_ready
CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE; _cfg record;
        v_w uuid; v_b uuid; v_swap boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;
  IF v_uid = v_g.white_id THEN
    UPDATE public.chess_games SET ready_white = COALESCE(_ready,false) WHERE id=_game_id;
  ELSIF v_uid = v_g.black_id THEN
    UPDATE public.chess_games SET ready_black = COALESCE(_ready,false) WHERE id=_game_id;
  ELSE RAISE EXCEPTION 'not a player'; END IF;

  SELECT * INTO v_g FROM public.chess_games WHERE id=_game_id;
  IF v_g.white_id IS NOT NULL AND v_g.black_id IS NOT NULL AND v_g.ready_white AND v_g.ready_black THEN
    SELECT * INTO _cfg FROM public._game_cfg('chess');
    v_swap := (get_byte(extensions.gen_random_bytes(1),0) % 2) = 1;
    IF v_swap THEN
      v_w := v_g.black_id; v_b := v_g.white_id;
    ELSE
      v_w := v_g.white_id; v_b := v_g.black_id;
    END IF;
    UPDATE public.chess_games
       SET status='playing',
           white_id = v_w,
           black_id = v_b,
           started_at = now(),
           turn_deadline = now() + (COALESCE(_cfg.turn_timer_seconds,60) || ' seconds')::interval
     WHERE id=_game_id AND status='open';
  END IF;
END; $function$;

-- 3) fanorona_draw_spin
CREATE OR REPLACE FUNCTION public.fanorona_draw_spin(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_g public.fanorona_games%ROWTYPE; v_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.fanorona_games WHERE id=_game_id FOR UPDATE;
  IF v_g.id IS NULL OR v_g.status <> 'drawing' THEN RETURN; END IF;
  IF v_g.draw_white_by IS NULL OR v_g.draw_black_by IS NULL THEN RAISE EXCEPTION 'colors not chosen yet'; END IF;
  IF v_g.draw_result_color IS NOT NULL THEN RETURN; END IF;
  v_color := CASE WHEN (get_byte(extensions.gen_random_bytes(1),0) % 2) = 0 THEN 'w' ELSE 'b' END;
  UPDATE public.fanorona_games
     SET draw_result_color = v_color,
         draw_revealed_at = now(),
         draw_spun_by = v_uid
   WHERE id=_game_id AND draw_result_color IS NULL;
END; $function$;

-- 4) fanorona_set_ready
CREATE OR REPLACE FUNCTION public.fanorona_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_total int; v_ready int; v_status text;
        v_starter uuid; v_other uuid; v_swap boolean;
        v_p1 uuid; v_p2 uuid;
        v_time_ms int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE public.fanorona_participants SET ready = COALESCE(_ready, false)
    WHERE game_id = _game_id AND user_id = v_uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'not a participant'; END IF;
  SELECT status INTO v_status FROM public.fanorona_games WHERE id = _game_id;
  IF v_status <> 'open' THEN RETURN; END IF;
  SELECT count(*), count(*) FILTER (WHERE ready) INTO v_total, v_ready
    FROM public.fanorona_participants WHERE game_id = _game_id;
  IF v_total = 2 AND v_ready = 2 THEN
    SELECT user_id INTO v_p1 FROM public.fanorona_participants WHERE game_id=_game_id ORDER BY joined_at LIMIT 1;
    SELECT user_id INTO v_p2 FROM public.fanorona_participants WHERE game_id=_game_id AND user_id <> v_p1 LIMIT 1;
    v_swap := (get_byte(extensions.gen_random_bytes(1),0) % 2) = 1;
    IF v_swap THEN v_starter := v_p2; v_other := v_p1;
    ELSE v_starter := v_p1; v_other := v_p2; END IF;

    UPDATE public.fanorona_participants SET slot = 0, color = 'white'
      WHERE game_id=_game_id AND user_id = v_starter;
    UPDATE public.fanorona_participants SET slot = 1, color = 'black'
      WHERE game_id=_game_id AND user_id = v_other;

    v_time_ms := COALESCE(
      (SELECT time_control_min FROM public.fanorona_games WHERE id = _game_id),
      10
    ) * 60 * 1000;

    UPDATE public.fanorona_games
       SET status = 'playing',
           started_at = now(),
           current_turn = 0,
           last_move_at = now(),
           white_time_ms = v_time_ms,
           black_time_ms = v_time_ms,
           state = jsonb_set(state, '{phase}', '"playing"'::jsonb)
     WHERE id = _game_id AND status = 'open';
  END IF;
END $function$;

-- 5) handle_new_user (trigger function)
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  v_pseudo TEXT;
  v_ref_code TEXT;
  v_referred_by UUID;
  v_input_ref TEXT;
  v_bonus NUMERIC;
  v_unique TEXT;
  v_email TEXT;
  v_provider TEXT;
BEGIN
  v_email := COALESCE(NEW.email, '');
  v_provider := COALESCE(NEW.raw_app_meta_data->>'provider', NEW.raw_user_meta_data->>'provider', '');

  IF v_provider = 'google' THEN
    v_pseudo := COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      split_part(v_email, '@', 1)
    );
  ELSE
    v_pseudo := COALESCE(NEW.raw_user_meta_data->>'pseudo', split_part(v_email, '@', 1));
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(pseudo) = lower(v_pseudo)) THEN
    v_pseudo := v_pseudo || '_' || substr(encode(extensions.gen_random_bytes(3), 'hex'), 1, 6);
  END IF;

  v_input_ref := NEW.raw_user_meta_data->>'referral_code';
  v_ref_code := public.gen_referral_code();
  v_unique := public.gen_unique_code();

  IF v_input_ref IS NOT NULL AND v_input_ref <> '' THEN
    SELECT id INTO v_referred_by FROM public.profiles WHERE referral_code = upper(v_input_ref);
  END IF;

  SELECT signup_bonus INTO v_bonus FROM public.app_settings WHERE id = 1;

  INSERT INTO public.profiles(id, pseudo, email, referral_code, referred_by, balance_ar, unique_code)
  VALUES (NEW.id, v_pseudo, v_email, v_ref_code, v_referred_by, COALESCE(v_bonus,0), v_unique);

  IF COALESCE(v_bonus,0) > 0 THEN
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES (NEW.id,'bonus',v_bonus,'Bonus inscription');
  END IF;

  IF lower(v_email) = 'soavinapierrit@gmail.com' THEN
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'admin') ON CONFLICT DO NOTHING;
  ELSE
    INSERT INTO public.user_roles(user_id, role) VALUES (NEW.id, 'user') ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END $function$;

-- Re-attach trigger (DROP + CREATE to be safe)
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.chess_draw_spin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.chess_set_ready(uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_draw_spin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_set_ready(uuid, boolean) TO authenticated;
