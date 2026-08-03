
-- =========================================================
-- CHESS RESET + NEW SCHEMA
-- =========================================================

-- 1) Drop old cron job
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT jobid, jobname FROM cron.job WHERE jobname LIKE 'chess%' LOOP
    PERFORM cron.unschedule(r.jobid);
  END LOOP;
END $$;

-- 2) Drop old RPCs
DROP FUNCTION IF EXISTS public.chess_start_solo_bot(text, text) CASCADE;
DROP FUNCTION IF EXISTS public.chess_bot_move(uuid, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.chess_move(uuid, text, text, text) CASCADE;
DROP FUNCTION IF EXISTS public.chess_tick(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.chess_tick_all() CASCADE;
DROP FUNCTION IF EXISTS public.chess_auto_end(uuid, uuid, boolean, text) CASCADE;
DROP FUNCTION IF EXISTS public.chess_create(numeric, boolean, integer) CASCADE;
DROP FUNCTION IF EXISTS public.chess_join(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.chess_join_code(text) CASCADE;
DROP FUNCTION IF EXISTS public.chess_ready(uuid, boolean) CASCADE;
DROP FUNCTION IF EXISTS public.chess_resign(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.chess_offer_draw(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.chess_accept_draw(uuid) CASCADE;
DROP FUNCTION IF EXISTS public.chess_draw_pick(uuid, integer) CASCADE;
DROP FUNCTION IF EXISTS public.chess_draw_spin(uuid) CASCADE;

-- 3) Wipe existing games (fresh start)
TRUNCATE TABLE public.chess_moves CASCADE;
DELETE FROM public.chess_games;

-- 4) Drop obsolete columns
ALTER TABLE public.chess_games
  DROP COLUMN IF EXISTS draw_pick_value,
  DROP COLUMN IF EXISTS draw_result,
  DROP COLUMN IF EXISTS draw_picker_id,
  DROP COLUMN IF EXISTS draw_revealed_at,
  DROP COLUMN IF EXISTS draw_offered_by,
  DROP COLUMN IF EXISTS draw_white_by,
  DROP COLUMN IF EXISTS draw_black_by,
  DROP COLUMN IF EXISTS draw_result_color,
  DROP COLUMN IF EXISTS draw_spun_by,
  DROP COLUMN IF EXISTS ready_white,
  DROP COLUMN IF EXISTS ready_black,
  DROP COLUMN IF EXISTS turn_skips,
  DROP COLUMN IF EXISTS afk_warning,
  DROP COLUMN IF EXISTS afk_pause_for,
  DROP COLUMN IF EXISTS afk_pause_name,
  DROP COLUMN IF EXISTS pause_used,
  DROP COLUMN IF EXISTS paused_turn_remaining_s,
  DROP COLUMN IF EXISTS game_deadline,
  DROP COLUMN IF EXISTS pause_deadline;

-- 5) Add new columns
ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'solo',
  ADD COLUMN IF NOT EXISTS time_control_min int NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS white_time_ms int NOT NULL DEFAULT 600000,
  ADD COLUMN IF NOT EXISTS black_time_ms int NOT NULL DEFAULT 600000,
  ADD COLUMN IF NOT EXISTS end_reason text,
  ADD COLUMN IF NOT EXISTS draw_offered_by uuid,
  ADD COLUMN IF NOT EXISTS resign_offered_by uuid;

-- Normalise status enum values used going forward: waiting/active/finished/cancelled
-- Existing enum keeps 'open'/'playing' aliases; we treat 'waiting'~'open', 'active'~'playing' in RPCs.

-- =========================================================
-- HELPERS
-- =========================================================

CREATE OR REPLACE FUNCTION public._chess_gen_code() RETURNS text
LANGUAGE plpgsql AS $$
DECLARE v text; BEGIN
  v := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  RETURN v;
END $$;

CREATE OR REPLACE FUNCTION public._chess_ephemeral_bot(_pseudo text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password, email_confirmed_at,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    'chessbot_' || v_id::text || '@bot.lalaomada.internal',
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(),
    jsonb_build_object('pseudo', _pseudo, 'is_bot', true),
    now(), now(),
    '', '', '', ''
  );
  UPDATE public.profiles SET balance_ar = 0, pseudo = _pseudo, avatar_url = NULL WHERE id = v_id;
  DELETE FROM public.transactions WHERE user_id = v_id;
  RETURN v_id;
END $$;

-- =========================================================
-- CREATE RPCs
-- =========================================================

-- Solo vs bot
CREATE OR REPLACE FUNCTION public.chess_create_solo(
  _difficulty int DEFAULT 2,   -- 1=easy, 2=medium, 3=hard
  _color      text DEFAULT 'white',
  _time_min   int DEFAULT 10
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_bot uuid;
  v_id  uuid;
  v_human_w boolean := (lower(coalesce(_color,'white')) <> 'black');
  v_ms int := greatest(60000, coalesce(_time_min,10) * 60000);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  v_bot := public._chess_ephemeral_bot('Joueur');

  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status, mode,
    stake, pot, commission_pct, is_private, room_code,
    white_is_bot, black_is_bot,
    time_control_min, white_time_ms, black_time_ms,
    bot_intelligence, bot_name,
    started_at, last_move_at,
    fen, turn, ply
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid ELSE v_bot END,
    CASE WHEN v_human_w THEN v_bot ELSE v_uid END,
    'playing', 'solo',
    0, 0, 0, true, public._chess_gen_code(),
    NOT v_human_w, v_human_w,
    coalesce(_time_min,10), v_ms, v_ms,
    coalesce(_difficulty,2), 'Joueur',
    now(), now(),
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_create_solo(int, text, int) TO authenticated;

-- Friends (private, code)
CREATE OR REPLACE FUNCTION public.chess_create_friends(
  _color    text DEFAULT 'white',
  _time_min int DEFAULT 10
) RETURNS TABLE(id uuid, code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_code text := public._chess_gen_code();
  v_human_w boolean := (lower(coalesce(_color,'white')) <> 'black');
  v_ms int := greatest(60000, coalesce(_time_min,10) * 60000);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status, mode,
    stake, pot, commission_pct, is_private, room_code,
    time_control_min, white_time_ms, black_time_ms,
    fen, turn, ply
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid ELSE NULL END,
    CASE WHEN v_human_w THEN NULL ELSE v_uid END,
    'open', 'friends',
    0, 0, 0, true, v_code,
    coalesce(_time_min,10), v_ms, v_ms,
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0
  ) RETURNING chess_games.id INTO v_id;
  RETURN QUERY SELECT v_id, v_code;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_create_friends(text, int) TO authenticated;

-- Join by code
CREATE OR REPLACE FUNCTION public.chess_join_friends(_code text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g   chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games
    WHERE upper(room_code) = upper(_code) AND status = 'open'
    ORDER BY created_at DESC LIMIT 1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.white_id = v_uid OR v_g.black_id = v_uid THEN RETURN v_g.id; END IF;
  IF v_g.white_id IS NULL THEN
    UPDATE chess_games SET white_id = v_uid, status='playing', started_at=now(), last_move_at=now() WHERE id = v_g.id;
  ELSIF v_g.black_id IS NULL THEN
    UPDATE chess_games SET black_id = v_uid, status='playing', started_at=now(), last_move_at=now() WHERE id = v_g.id;
  ELSE
    RAISE EXCEPTION 'game full';
  END IF;
  RETURN v_g.id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_join_friends(text) TO authenticated;

-- Public stake game
CREATE OR REPLACE FUNCTION public.chess_create_stake(
  _stake    numeric,
  _color    text DEFAULT 'white',
  _time_min int  DEFAULT 10
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_human_w boolean := (lower(coalesce(_color,'white')) <> 'black');
  v_ms int := greatest(60000, coalesce(_time_min,10) * 60000);
  v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake <= 0 THEN RAISE EXCEPTION 'stake must be positive'; END IF;
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid FOR UPDATE;
  IF coalesce(v_bal,0) < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, meta) VALUES (v_uid, 'chess_stake', -_stake, jsonb_build_object('kind','hold'));

  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status, mode,
    stake, pot, commission_pct, is_private, room_code,
    time_control_min, white_time_ms, black_time_ms,
    fen, turn, ply
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid ELSE NULL END,
    CASE WHEN v_human_w THEN NULL ELSE v_uid END,
    'open', 'stake',
    _stake, _stake, 10, false, public._chess_gen_code(),
    coalesce(_time_min,10), v_ms, v_ms,
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_create_stake(numeric, text, int) TO authenticated;

-- Join stake
CREATE OR REPLACE FUNCTION public.chess_join_stake(_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id AND status='open' AND mode='stake' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not joinable'; END IF;
  IF v_g.white_id = v_uid OR v_g.black_id = v_uid THEN RETURN _id; END IF;
  IF v_g.stake > 0 THEN
    SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid FOR UPDATE;
    IF coalesce(v_bal,0) < v_g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
    UPDATE profiles SET balance_ar = balance_ar - v_g.stake WHERE id = v_uid;
    INSERT INTO transactions(user_id, type, amount, meta) VALUES (v_uid, 'chess_stake', -v_g.stake, jsonb_build_object('kind','hold','game',_id));
  END IF;
  IF v_g.white_id IS NULL THEN
    UPDATE chess_games SET white_id=v_uid, pot=pot+v_g.stake, status='playing', started_at=now(), last_move_at=now() WHERE id=_id;
  ELSE
    UPDATE chess_games SET black_id=v_uid, pot=pot+v_g.stake, status='playing', started_at=now(), last_move_at=now() WHERE id=_id;
  END IF;
  RETURN _id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_join_stake(uuid) TO authenticated;

-- =========================================================
-- PLAY
-- =========================================================

CREATE OR REPLACE FUNCTION public.chess_play(
  _id        uuid,
  _uci       text,
  _san       text,
  _fen_after text,
  _elapsed_ms int DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_new_turn text;
  v_my_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status NOT IN ('playing','active') THEN RAISE EXCEPTION 'game not active'; END IF;

  IF v_g.white_id = v_uid THEN v_my_color := 'w';
  ELSIF v_g.black_id = v_uid THEN v_my_color := 'b';
  ELSE RAISE EXCEPTION 'not a participant'; END IF;

  IF v_g.turn <> v_my_color THEN RAISE EXCEPTION 'not your turn'; END IF;

  v_new_turn := CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END;

  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_g.ply+1, _san, _uci, _fen_after, v_uid);

  UPDATE chess_games SET
    fen = _fen_after,
    turn = v_new_turn,
    ply = v_g.ply + 1,
    last_move_at = now(),
    white_time_ms = CASE WHEN v_my_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_my_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END,
    draw_offered_by = CASE WHEN draw_offered_by IS NOT NULL AND draw_offered_by = v_uid THEN NULL ELSE draw_offered_by END
  WHERE id=_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_play(uuid, text, text, text, int) TO authenticated;

-- Bot play (called by human on bot's behalf, solo mode only)
CREATE OR REPLACE FUNCTION public.chess_bot_play(
  _id uuid, _uci text, _san text, _fen_after text, _elapsed_ms int DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_bot uuid;
  v_bot_color text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.mode <> 'solo' THEN RAISE EXCEPTION 'not a solo game'; END IF;
  IF v_g.status NOT IN ('playing','active') THEN RAISE EXCEPTION 'game not active'; END IF;

  IF v_g.white_id = v_uid AND v_g.black_is_bot THEN v_bot := v_g.black_id; v_bot_color := 'b';
  ELSIF v_g.black_id = v_uid AND v_g.white_is_bot THEN v_bot := v_g.white_id; v_bot_color := 'w';
  ELSE RAISE EXCEPTION 'not a solo-bot game'; END IF;

  IF v_g.turn <> v_bot_color THEN RAISE EXCEPTION 'not bot turn'; END IF;

  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_id, v_g.ply+1, _san, _uci, _fen_after, v_bot);

  UPDATE chess_games SET
    fen = _fen_after,
    turn = CASE WHEN v_g.turn='w' THEN 'b' ELSE 'w' END,
    ply = v_g.ply + 1,
    last_move_at = now(),
    white_time_ms = CASE WHEN v_bot_color='w' THEN greatest(0, white_time_ms - coalesce(_elapsed_ms,0)) ELSE white_time_ms END,
    black_time_ms = CASE WHEN v_bot_color='b' THEN greatest(0, black_time_ms - coalesce(_elapsed_ms,0)) ELSE black_time_ms END
  WHERE id=_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_bot_play(uuid, text, text, text, int) TO authenticated;

-- =========================================================
-- FINISH / RESIGN / DRAW / TICK
-- =========================================================

CREATE OR REPLACE FUNCTION public._chess_settle(_id uuid, _winner uuid, _draw boolean, _reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_prize numeric;
  v_commission numeric;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND THEN RETURN; END IF;
  IF v_g.status = 'finished' OR v_g.status = 'cancelled' THEN RETURN; END IF;

  IF v_g.mode = 'stake' AND v_g.pot > 0 THEN
    IF _draw THEN
      -- Refund both stakes, no commission
      IF v_g.white_id IS NOT NULL THEN
        UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.white_id;
        INSERT INTO transactions(user_id,type,amount,meta) VALUES (v_g.white_id,'chess_refund',v_g.stake,jsonb_build_object('game',_id,'reason','draw'));
      END IF;
      IF v_g.black_id IS NOT NULL THEN
        UPDATE profiles SET balance_ar = balance_ar + v_g.stake WHERE id = v_g.black_id;
        INSERT INTO transactions(user_id,type,amount,meta) VALUES (v_g.black_id,'chess_refund',v_g.stake,jsonb_build_object('game',_id,'reason','draw'));
      END IF;
    ELSIF _winner IS NOT NULL THEN
      v_commission := round(v_g.pot * (coalesce(v_g.commission_pct,10)/100.0));
      v_prize := v_g.pot - v_commission;
      UPDATE profiles SET balance_ar = balance_ar + v_prize WHERE id = _winner;
      INSERT INTO transactions(user_id,type,amount,meta) VALUES (_winner,'chess_win',v_prize,jsonb_build_object('game',_id,'reason',_reason,'commission',v_commission));
    END IF;
  END IF;

  UPDATE chess_games SET
    status='finished', winner_id=_winner, draw=_draw, end_reason=_reason,
    finished_at=now(), turn_deadline=NULL
  WHERE id=_id;
END $$;

-- Client-detected end
CREATE OR REPLACE FUNCTION public.chess_finish(_id uuid, _winner uuid, _draw boolean, _reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id;
  IF v_uid NOT IN (coalesce(v_g.white_id, v_uid), coalesce(v_g.black_id, v_uid)) THEN
    -- ensure at least one side matches
    IF v_g.white_id <> v_uid AND v_g.black_id <> v_uid THEN
      RAISE EXCEPTION 'not a participant';
    END IF;
  END IF;
  PERFORM public._chess_settle(_id, _winner, coalesce(_draw,false), _reason);
END $$;
GRANT EXECUTE ON FUNCTION public.chess_finish(uuid, uuid, boolean, text) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_resign(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
  v_winner uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.white_id = v_uid THEN v_winner := v_g.black_id;
  ELSIF v_g.black_id = v_uid THEN v_winner := v_g.white_id;
  ELSE RAISE EXCEPTION 'not a participant'; END IF;
  PERFORM public._chess_settle(_id, v_winner, false, 'resign');
END $$;
GRANT EXECUTE ON FUNCTION public.chess_resign(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_offer_draw(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF v_g.white_id <> v_uid AND v_g.black_id <> v_uid THEN RAISE EXCEPTION 'not a participant'; END IF;
  UPDATE chess_games SET draw_offered_by = v_uid WHERE id=_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_offer_draw(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.chess_accept_draw(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g chess_games%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF v_g.draw_offered_by IS NULL OR v_g.draw_offered_by = v_uid THEN RAISE EXCEPTION 'no draw offer'; END IF;
  IF v_g.white_id <> v_uid AND v_g.black_id <> v_uid THEN RAISE EXCEPTION 'not a participant'; END IF;
  PERFORM public._chess_settle(_id, NULL, true, 'draw_agreed');
END $$;
GRANT EXECUTE ON FUNCTION public.chess_accept_draw(uuid) TO authenticated;

-- Tick (timeout check) — safe to call by anyone; only settles if time is out
CREATE OR REPLACE FUNCTION public.chess_tick(_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_g chess_games%ROWTYPE;
  v_elapsed_ms int;
  v_remaining int;
  v_loser uuid;
  v_winner uuid;
BEGIN
  SELECT * INTO v_g FROM chess_games WHERE id=_id FOR UPDATE;
  IF NOT FOUND OR v_g.status NOT IN ('playing','active') THEN RETURN; END IF;
  v_elapsed_ms := greatest(0, floor(extract(epoch FROM (now() - coalesce(v_g.last_move_at, v_g.started_at, now())))*1000)::int);
  IF v_g.turn = 'w' THEN
    v_remaining := v_g.white_time_ms - v_elapsed_ms;
    v_loser := v_g.white_id; v_winner := v_g.black_id;
  ELSE
    v_remaining := v_g.black_time_ms - v_elapsed_ms;
    v_loser := v_g.black_id; v_winner := v_g.white_id;
  END IF;
  IF v_remaining <= 0 THEN
    PERFORM public._chess_settle(_id, v_winner, false, 'timeout');
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_tick(uuid) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.chess_tick_all() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  r record; n int := 0;
BEGIN
  FOR r IN SELECT id FROM chess_games WHERE status IN ('playing','active') AND NOT coalesce(paused,false) LOOP
    PERFORM public.chess_tick(r.id);
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_tick_all() TO service_role;

-- =========================================================
-- RLS (idempotent — table already has it enabled)
-- =========================================================
ALTER TABLE public.chess_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chess_moves ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "chess_games_select" ON public.chess_games;
CREATE POLICY "chess_games_select" ON public.chess_games FOR SELECT TO authenticated, anon
  USING (
    NOT is_private
    OR auth.uid() = white_id OR auth.uid() = black_id OR auth.uid() = host_id
  );

DROP POLICY IF EXISTS "chess_moves_select" ON public.chess_moves;
CREATE POLICY "chess_moves_select" ON public.chess_moves FOR SELECT TO authenticated, anon
  USING (
    EXISTS (SELECT 1 FROM chess_games g WHERE g.id = chess_moves.game_id
      AND (NOT g.is_private OR auth.uid() = g.white_id OR auth.uid() = g.black_id OR auth.uid() = g.host_id))
  );

-- Realtime
DO $$ BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_games;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.chess_moves;
  EXCEPTION WHEN duplicate_object THEN NULL; END;
END $$;

-- Cron: tick every 5 seconds
SELECT cron.schedule('chess_tick_all_5s', '5 seconds', $$SELECT public.chess_tick_all();$$);
