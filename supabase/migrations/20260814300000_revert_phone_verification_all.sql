-- Migration: REVERT all phone verification changes
-- Date: 2026-08-14
-- Restores original functions that were modified by migrations:
--   20260814190001_domino_add_phone_verification.sql
--   20260814200000_add_phone_verification_all_games.sql
-- ═══════════════════════════════════════════════════════════════════

-- ═══ 1. DOMINO: restore original domino_set_ready ═══
CREATE OR REPLACE FUNCTION public.domino_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _g record; _all boolean; _count int; _tiles jsonb; _dealt jsonb; _info jsonb;
  _state jsonb; _scores jsonb := '{}'::jsonb; _ts jsonb := '{}'::jsonb; _p record;
  _key text; _draw text; _delay interval;
BEGIN
  SELECT * INTO _g FROM public.domino_games WHERE id = _game_id;
  IF NOT FOUND OR _g.status != 'open' THEN RETURN; END IF;
  UPDATE public.domino_participants SET ready = _ready WHERE game_id = _game_id AND user_id = auth.uid() AND forfeited = false;
  SELECT bool_and(ready), count(*) INTO _all, _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF _count < 2 THEN _all := false; END IF;

  IF _all THEN
    _tiles := public.domino_generate_tiles();
    _dealt := public.domino_deal_tiles(_game_id, _tiles);
    _info := public.domino_find_first_player(_game_id, _dealt->'hands');
    _draw := COALESCE(_g.state->>'draw_mode', 'with');
    FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
      _key := COALESCE(_p.user_id::text, 'bot_'||_p.slot);
      _scores := _scores || jsonb_build_object(COALESCE(_p.user_id::text, _key), 0);
      _ts := _ts || jsonb_build_object(_key, 0);
    END LOOP;
    _state := jsonb_build_object(
      'phase','playing','round',1,'board','[]'::jsonb,'left_end',null,'right_end',null,
      'first_tile_idx',0,
      'hands',_dealt->'hands','stock',CASE WHEN _draw='without' THEN '[]'::jsonb ELSE _dealt->'stock' END,
      'passes',0,'last_pass_by',null,'draw_mode',_draw,
      'first_tile_rule',COALESCE(_g.state->>'first_tile_rule','libre'),
      'first_move_double',_info->>'double',
      'last_round',null,'break_until',null,'reveal_until',null);

    _delay := public._domino_turn_delay(_game_id, (_info->>'slot')::int);

    UPDATE public.domino_games SET
      status='playing', state=_state, current_turn=(_info->>'slot')::int,
      scores=_scores, turn_skips=_ts, started_at=now(),
      turn_deadline=now() + _delay,
      pot=_g.stake*_count, updated_at=now()
    WHERE id=_game_id;
  END IF;
  UPDATE public.domino_games SET updated_at = now() WHERE id = _game_id;
END;
$function$;

-- ═══ 2. CHESS: restore original chess_set_ready ═══
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

-- ═══ 3. FANORONA: restore original fanorona_set_ready ═══
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

-- ═══ 4. POKER: restore original poker_set_ready ═══
CREATE OR REPLACE FUNCTION public.poker_set_ready(_game_id uuid, _ready boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  all_ready boolean;
  player_cnt int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  UPDATE public.poker_players SET is_ready=_ready WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), bool_and(is_ready) INTO player_cnt, all_ready FROM public.poker_players WHERE game_id=_game_id;
  IF all_ready AND player_cnt >= 2 THEN
    UPDATE public.poker_games SET status='playing', started_at=now(), updated_at=now() WHERE id=_game_id;
    UPDATE public.poker_players SET status='playing' WHERE game_id=_game_id;
    PERFORM public._poker_deal_hand(_game_id);
  END IF;
END;
$$;

-- ═══ 5. RAMI: restore original rami_set_ready ═══
CREATE OR REPLACE FUNCTION public.rami_set_ready(_game_id uuid, _ready boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _uid uuid := auth.uid(); _g public.rami_games; _count int; _ready_count int;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO _g FROM public.rami_games WHERE id=_game_id FOR UPDATE;
  IF _g.status NOT IN ('waiting','open') THEN RAISE EXCEPTION 'partie déjà commencée'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.rami_participants WHERE game_id=_game_id AND user_id=_uid) THEN
    RAISE EXCEPTION 'non participant';
  END IF;
  UPDATE public.rami_participants SET ready=_ready WHERE game_id=_game_id AND user_id=_uid;
  -- Auto-start when all ready
  SELECT count(*), count(CASE WHEN ready THEN 1 END) INTO _count, _ready_count
    FROM public.rami_participants WHERE game_id=_game_id;
  IF _count >= 2 AND _count = _ready_count THEN
    PERFORM public.rami_start(_game_id);
  END IF;
END $$;
