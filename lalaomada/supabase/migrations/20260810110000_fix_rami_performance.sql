-- ═══ Rami performance fixes ═══

-- 1. Bot think timer (like Domino): 800-2000ms delay before playing
CREATE OR REPLACE FUNCTION public._rami_arm_bot_think(_game_id uuid, _slot integer, _state jsonb)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_is_bot boolean := false; v_delay_ms int;
BEGIN
  SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
    FROM public.rami_participants dp
   WHERE dp.game_id = _game_id AND dp.slot = _slot AND dp.forfeited = false;
  IF v_is_bot THEN
    v_delay_ms := 800 + (floor(random() * 1200))::int;
    _state := jsonb_set(_state, '{bot_think_until}',
             to_jsonb((now() + make_interval(secs => v_delay_ms / 1000.0))::text), true);
  ELSE
    _state := _state - 'bot_think_until';
  END IF;
  RETURN _state;
END;
$$;

-- 2. rami_tick: bot uses think timer instead of playing immediately
-- 3. rami_bot_play: arms think timer for next bot player
-- 4. _rami_autoplay_bots + rami_bot_tick_all: simplified to delegate to rami_tick
-- 5. Turn timer: 120s → 30s (UPDATE game_configs)
