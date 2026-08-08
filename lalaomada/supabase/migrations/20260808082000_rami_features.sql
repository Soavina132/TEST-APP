-- 20260808082000_rami_features.sql
-- Features: Showdown melds reveal, AFK warning system, Spectator support

-- ── 1. AFK WARNINGS column ─────────────────────────────────────────
ALTER TABLE public.rami_games ADD COLUMN IF NOT EXISTS afk_warnings int DEFAULT 0;

-- ── 2. rami_reveal_hands: return all hands + melds for a finished game ──
CREATE OR REPLACE FUNCTION public.rami_reveal_hands(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _g public.rami_games;
  _is_participant boolean;
  _is_spectator boolean;
  _result jsonb;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF _g.status NOT IN ('finished', 'cancelled') THEN
    RAISE EXCEPTION 'Game not finished yet';
  END IF;
  SELECT EXISTS(
    SELECT 1 FROM public.rami_participants WHERE game_id = _game_id AND user_id = auth.uid()
  ) INTO _is_participant;
  SELECT EXISTS(
    SELECT 1 FROM public.game_spectators WHERE game_id = _game_id AND user_id = auth.uid()
  ) INTO _is_spectator;
  IF NOT (_is_participant OR _is_spectator OR public.is_admin()) THEN
    RAISE EXCEPTION 'Not authorized to view this game';
  END IF;
  _result := jsonb_build_object(
    'hands', COALESCE(_g.state->'hands', '{}'::jsonb),
    'melds', COALESCE(_g.state->'melds', '[]'::jsonb),
    'winner_id', _g.winner_id,
    'status', _g.status
  );
  RETURN _result;
END;
$$;
REVOKE ALL ON FUNCTION public.rami_reveal_hands(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_reveal_hands(uuid) TO authenticated;

-- ── 3. rami_spectate: join as spectator ──
CREATE OR REPLACE FUNCTION public.rami_spectate(_game_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
DECLARE
  _g public.rami_games;
  _state jsonb;
  _sanitized jsonb;
  _participants jsonb;
  _count int;
  _max int;
BEGIN
  SELECT * INTO _g FROM public.rami_games WHERE id = _game_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Game not found'; END IF;
  IF _g.status NOT IN ('playing', 'paused') THEN
    RAISE EXCEPTION 'Game not in progress';
  END IF;
  SELECT COALESCE(max_spectators, 50) INTO _max FROM public.app_settings WHERE id = 1;
  SELECT count(*) INTO _count FROM public.game_spectators WHERE game_id = _game_id;
  IF _count >= _max THEN
    RAISE EXCEPTION 'Spectator limit reached';
  END IF;
  INSERT INTO public.game_spectators(game_id, user_id)
    VALUES (_game_id, auth.uid()) ON CONFLICT DO NOTHING;
  _state := _g.state;
  _sanitized := jsonb_build_object(
    'deck_count', jsonb_array_length(COALESCE(_state->'deck', '[]'::jsonb)),
    'melds', COALESCE(_state->'melds', '[]'::jsonb),
    'discards', COALESCE(_state->'discards', '{}'::jsonb),
    'last_discard_by', COALESCE(_state->'last_discard_by', ''::text),
    'action_log', COALESCE(_state->'action_log', '[]'::jsonb)
  );
  SELECT jsonb_agg(jsonb_build_object(
    'user_id', p.user_id, 'display_name', p.display_name, 'slot', p.slot,
    'hand_count', p.hand_count, 'is_bot', p.is_bot, 'forfeited', p.forfeited
  )) INTO _participants
  FROM public.rami_participants p WHERE p.game_id = _game_id ORDER BY p.slot;
  RETURN jsonb_build_object(
    'game', jsonb_build_object(
      'id', _g.id, 'status', _g.status, 'current_turn', _g.current_turn,
      'turn_phase', _g.turn_phase, 'stake', _g.stake, 'pot', _g.pot,
      'joker_mode', _g.joker_mode, 'game_mode', _g.game_mode,
      'winner_id', _g.winner_id, 'state', _sanitized
    ),
    'participants', COALESCE(_participants, '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.rami_spectate(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_spectate(uuid) TO authenticated;

-- ── 4. rami_spectate_leave ──
CREATE OR REPLACE FUNCTION public.rami_spectate_leave(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO public AS $$
BEGIN
  DELETE FROM public.game_spectators WHERE game_id = _game_id AND user_id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.rami_spectate_leave(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_spectate_leave(uuid) TO authenticated;

-- ── 5. Add spectators_count column ──
ALTER TABLE public.rami_games ADD COLUMN IF NOT EXISTS spectators_count int DEFAULT 0;
