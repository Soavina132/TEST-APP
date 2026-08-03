
-- =========================================================
-- Tour 2/3: timers + domino target score / scores
-- =========================================================
ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS turn_deadline timestamptz,
  ADD COLUMN IF NOT EXISTS target_score integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS scores jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS turn_deadline timestamptz;

-- Recreate domino_create with optional _target_score
CREATE OR REPLACE FUNCTION public.domino_create(
  _stake numeric, _max integer, _private boolean,
  _mode text DEFAULT 'classic', _commission numeric DEFAULT 10,
  _target_score integer DEFAULT 0
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_balance numeric;
  v_code text;
  v_id uuid;
  v_name text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'invalid max_players'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF _target_score < 0 OR _target_score > 1000 THEN RAISE EXCEPTION 'invalid target_score'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF v_balance IS NULL OR v_balance < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;

  IF _private THEN
    v_code := upper(substring(md5(random()::text||clock_timestamp()::text) from 1 for 6));
  END IF;

  INSERT INTO public.domino_games(host_id, max_players, stake, pot, commission_pct, is_private, room_code, mode, target_score, state)
  VALUES (v_uid, _max, _stake, _stake, _commission, _private, v_code, _mode, _target_score, public._domino_init_state())
  RETURNING id INTO v_id;

  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'domino_stake', -_stake, v_id, 'Create domino game');
  INSERT INTO public.domino_participants(game_id, user_id, slot, display_name) VALUES (v_id, v_uid, 0, COALESCE(v_name,'Player'));
  RETURN v_id;
END $$;

-- Trigger: set turn_deadline when current_turn changes or game starts playing
CREATE OR REPLACE FUNCTION public._set_turn_deadline()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'playing' AND (TG_OP = 'INSERT' OR OLD.status <> 'playing' OR OLD.current_turn IS DISTINCT FROM NEW.current_turn) THEN
    NEW.turn_deadline := now() + interval '30 seconds';
  ELSIF NEW.status <> 'playing' THEN
    NEW.turn_deadline := NULL;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_domino_deadline ON public.domino_games;
CREATE TRIGGER trg_domino_deadline BEFORE INSERT OR UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._set_turn_deadline();

DROP TRIGGER IF EXISTS trg_fanorona_deadline ON public.fanorona_games;
CREATE TRIGGER trg_fanorona_deadline BEFORE INSERT OR UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._set_turn_deadline();

-- Tick functions: callable by anyone, only acts if deadline expired
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  g record;
  cur_uid uuid;
  remaining int;
  last_slot int;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' OR g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    RETURN;
  END IF;
  SELECT user_id INTO cur_uid FROM public.domino_participants WHERE game_id = _game_id AND slot = g.current_turn;
  -- Auto-forfeit current player on timeout
  UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
  SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF remaining <= 1 THEN
    SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
    IF last_slot IS NOT NULL THEN
      PERFORM public._domino_finalize(_game_id, last_slot);
    ELSE
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id;
    END IF;
  ELSE
    -- advance turn to next non-forfeited player
    UPDATE public.domino_games SET current_turn = (
      SELECT slot FROM public.domino_participants
      WHERE game_id = _game_id AND forfeited = false AND slot > g.current_turn
      ORDER BY slot LIMIT 1
    )
    WHERE id = _game_id;
    -- if none above, wrap
    UPDATE public.domino_games SET current_turn = (
      SELECT slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LIMIT 1
    ) WHERE id = _game_id AND current_turn = g.current_turn;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.fanorona_tick(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  g record;
  cur_uid uuid;
BEGIN
  SELECT * INTO g FROM public.fanorona_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' OR g.turn_deadline IS NULL OR g.turn_deadline > now() THEN
    RETURN;
  END IF;
  SELECT user_id INTO cur_uid FROM public.fanorona_participants WHERE game_id = _game_id AND slot = g.current_turn;
  UPDATE public.fanorona_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
  PERFORM public._fanorona_finalize(_game_id, 1 - g.current_turn);
END $$;

GRANT EXECUTE ON FUNCTION public.domino_tick(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fanorona_tick(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.domino_create(numeric,integer,boolean,text,numeric,integer) TO authenticated;
