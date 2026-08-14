-- Migration: Add phone verification check to chess, fanorona, poker, rami
-- Date: 2026-08-14
-- ═══════════════════════════════════════════════════════════════════
-- Games already with phone_verified: ludo, domino
-- When stake > 0 and there are human opponents, require phone_verified.
-- Solo/bot-only games are exempt.
-- ═══════════════════════════════════════════════════════════════════

-- ═══ 1. CHESS: chess_set_ready ═══
CREATE OR REPLACE FUNCTION public.chess_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE v_uid uuid := auth.uid(); v_g public.chess_games%ROWTYPE; _cfg record;
        v_w uuid; v_b uuid; v_swap boolean;
        v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM public.chess_games WHERE id = _game_id FOR UPDATE;
  IF v_g.id IS NULL THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'open' THEN RETURN; END IF;

  -- Phone verification check when stake > 0
  IF _ready AND COALESCE(v_g.stake, 0) > 0 THEN
    SELECT phone_verified INTO v_verified FROM public.profiles WHERE id = v_uid;
    IF NOT COALESCE(v_verified, false) THEN
      RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
    END IF;
  END IF;

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

REVOKE EXECUTE ON FUNCTION public.chess_set_ready(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_set_ready(uuid, boolean) TO authenticated;

-- ═══ 2. FANORONA: fanorona_set_ready ═══
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
        v_verified boolean;
        v_g public.fanorona_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- Phone verification check when stake > 0
  SELECT * INTO v_g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF _ready AND COALESCE(v_g.stake, 0) > 0 THEN
    SELECT phone_verified INTO v_verified FROM public.profiles WHERE id = v_uid;
    IF NOT COALESCE(v_verified, false) THEN
      RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
    END IF;
  END IF;

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

REVOKE EXECUTE ON FUNCTION public.fanorona_set_ready(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fanorona_set_ready(uuid, boolean) TO authenticated;

-- ═══ 3. POKER: poker_set_ready ═══
CREATE OR REPLACE FUNCTION public.poker_set_ready(_game_id uuid, _ready boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  all_ready boolean;
  player_cnt int;
  v_verified boolean;
  v_human_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  -- Phone verification check when stake > 0 and there are other human players
  IF _ready AND COALESCE(g.stake, 0) > 0 THEN
    SELECT count(*) INTO v_human_count
    FROM public.poker_players
    WHERE game_id=_game_id AND user_id != v_uid AND is_bot = false;
    IF v_human_count > 0 THEN
      SELECT phone_verified INTO v_verified FROM public.profiles WHERE id = v_uid;
      IF NOT COALESCE(v_verified, false) THEN
        RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
      END IF;
    END IF;
  END IF;

  UPDATE public.poker_players SET is_ready=_ready WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), bool_and(is_ready) INTO player_cnt, all_ready FROM public.poker_players WHERE game_id=_game_id;
  IF all_ready AND player_cnt >= 2 THEN
    UPDATE public.poker_games SET status='playing', started_at=now(), updated_at=now() WHERE id=_game_id;
    UPDATE public.poker_players SET status='playing' WHERE game_id=_game_id;
    PERFORM public._poker_deal_hand(_game_id);
  END IF;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.poker_set_ready FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.poker_set_ready TO authenticated;

-- ═══ 4. RAMI: rami_set_ready ═══
CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _count int; _ready_count int;
  _v_verified boolean; _v_human_count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'non participant';
  END IF;

  -- Phone verification check when stake > 0 and there are other human players
  IF _ready AND COALESCE(_g.stake, 0) > 0 THEN
    SELECT count(*) INTO _v_human_count
    FROM public.rami_participants
    WHERE game_id=_game_id AND user_id != _uid AND is_bot = false;
    IF _v_human_count > 0 THEN
      SELECT phone_verified INTO _v_verified FROM public.profiles WHERE id = _uid;
      IF NOT COALESCE(_v_verified, false) THEN
        RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
      END IF;
    END IF;
  END IF;

  UPDATE public.rami_participants SET ready=_ready WHERE game_id=_game_id AND user_id=_uid;
  -- Auto-start when all ready
  SELECT count(*), count(CASE WHEN ready THEN 1 END) INTO _count, _ready_count
    FROM public.rami_participants WHERE game_id=_game_id;
  IF _count >= 2 AND _count = _ready_count THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.rami_set_ready(uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_set_ready(uuid,boolean) TO authenticated;
