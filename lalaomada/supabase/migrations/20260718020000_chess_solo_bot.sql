-- ============================================================
-- Chess vs Bot (solo)
-- Add a bot-account marker + RPCs to create a solo-bot game and
-- to submit the bot's moves on behalf of the human player.
-- ============================================================

ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS black_is_bot boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS white_is_bot boolean NOT NULL DEFAULT false;

-- Create a solo-bot chess game (free, private, immediately playing).
-- _color = 'white' | 'black' : the human's colour.
CREATE OR REPLACE FUNCTION public.chess_start_solo_bot(
  _difficulty text DEFAULT 'medium',
  _color      text DEFAULT 'white'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_bot_id   uuid := gen_random_uuid();
  v_bot_mail text;
  v_id       uuid;
  v_code     text;
  v_human_w  boolean := (_color IS NULL OR lower(_color) <> 'black');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  v_bot_mail := 'chessbot_' || v_bot_id::text || '@bot.lalaomada.internal';

  -- Ephemeral bot auth user
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password, email_confirmed_at,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_bot_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_bot_mail,
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(),
    jsonb_build_object('pseudo', 'Bot', 'is_bot', true),
    now(), now(),
    '', '', '', ''
  );

  -- Ensure profile exists with clean state (trigger handle_new_user typically creates it)
  UPDATE public.profiles
    SET balance_ar = 0, pseudo = 'Bot', avatar_url = NULL
    WHERE id = v_bot_id;

  DELETE FROM public.transactions WHERE user_id = v_bot_id;

  v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));

  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status,
    stake, pot, commission_pct, is_private, room_code,
    white_is_bot, black_is_bot, started_at, last_move_at
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid    ELSE v_bot_id END,
    CASE WHEN v_human_w THEN v_bot_id ELSE v_uid    END,
    'playing',
    0, 0, 0, true, v_code,
    NOT v_human_w, v_human_w,
    now(), now()
  )
  RETURNING id INTO v_id;

  RETURN v_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_start_solo_bot(text, text) TO authenticated;

-- Submit a move on behalf of the bot in a solo-bot chess game.
-- Only the human player of that game may call this.
CREATE OR REPLACE FUNCTION public.chess_bot_move(
  _game_id   uuid,
  _san       text,
  _uci       text,
  _fen_after text
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_g   chess_games%ROWTYPE;
  v_bot uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  SELECT * INTO v_g FROM chess_games WHERE id = _game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'game not found'; END IF;
  IF v_g.status <> 'playing' THEN RAISE EXCEPTION 'game not active'; END IF;

  -- Caller must be the human side, and the opposite side must be a bot
  IF v_g.white_id = v_uid AND v_g.black_is_bot THEN
    v_bot := v_g.black_id;
    IF v_g.turn <> 'b' THEN RAISE EXCEPTION 'not bot turn'; END IF;
  ELSIF v_g.black_id = v_uid AND v_g.white_is_bot THEN
    v_bot := v_g.white_id;
    IF v_g.turn <> 'w' THEN RAISE EXCEPTION 'not bot turn'; END IF;
  ELSE
    RAISE EXCEPTION 'not a solo-bot game';
  END IF;

  INSERT INTO chess_moves(game_id, ply, san, uci, fen_after, by_user)
    VALUES (_game_id, v_g.ply + 1, _san, _uci, _fen_after, v_bot);

  UPDATE chess_games
    SET fen = _fen_after,
        turn = CASE WHEN v_g.turn = 'w' THEN 'b' ELSE 'w' END,
        ply = v_g.ply + 1,
        last_move_at = now(),
        turn_deadline = NULL
    WHERE id = _game_id;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_bot_move(uuid, text, text, text) TO authenticated;
