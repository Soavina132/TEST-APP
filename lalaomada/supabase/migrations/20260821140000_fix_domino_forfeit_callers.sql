-- Fix: "cannot cast type record to domino_participants"
-- domino_forfeit_internal expects public.domino_participants but callers use record

-- 1. Recréer domino_forfeit avec _part public.domino_participants
CREATE OR REPLACE FUNCTION public.domino_forfeit(_game_id uuid)
RETURNS void AS $$
DECLARE
  _uid uuid := auth.uid();
  _game record;
  _part public.domino_participants;
  _is_host boolean;
  _remaining int;
  _p record;
BEGIN
  SELECT * INTO _game FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF _game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;

  SELECT * INTO _part FROM public.domino_participants
    WHERE game_id = _game_id AND user_id = _uid AND forfeited = false;
  IF NOT FOUND THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF _game.status = 'open' THEN
    _is_host := (_game.host_id = _uid);
    IF _is_host THEN
      FOR _p IN SELECT user_id FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, description)
          VALUES (_p.user_id, 'domino_refund', _game.stake, 'Annulation salle d''attente (hote)');
      END LOOP;
      UPDATE public.domino_games SET status = 'cancelled', finished_at = now(), updated_at = now() WHERE id = _game_id;
    ELSE
      UPDATE public.profiles SET balance_ar = balance_ar + _game.stake WHERE id = _uid;
      INSERT INTO public.transactions(user_id, type, amount, description)
        VALUES (_uid, 'domino_refund', _game.stake, 'Quitter salle d''attente');
      DELETE FROM public.domino_participants WHERE id = _part.id;
      UPDATE public.domino_games SET pot = pot - _game.stake, updated_at = now() WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  PERFORM public.domino_forfeit_internal(_game_id, _part);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

REVOKE ALL ON FUNCTION public.domino_forfeit(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.domino_forfeit(uuid) TO authenticated;

-- 2. Recréer domino_auto_timeout avec le bon type
DROP FUNCTION IF EXISTS public.domino_auto_timeout(uuid, record) CASCADE;
DROP FUNCTION IF EXISTS public.domino_auto_timeout(uuid, public.domino_participants) CASCADE;

CREATE OR REPLACE FUNCTION public.domino_auto_timeout(_game_id uuid, _part public.domino_participants)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  _state jsonb; _ts jsonb; _count int; _key text;
BEGIN
  SELECT state, turn_skips INTO _state, _ts FROM public.domino_games WHERE id = _game_id;
  _key := COALESCE(_part.user_id::text, 'bot_'||_part.slot);
  _ts := jsonb_set(_ts, ARRAY[_key], to_jsonb((_ts->>_key)::int + 1));
  IF (_ts->>_key)::int >= 5 THEN PERFORM public.domino_forfeit_internal(_game_id, _part); RETURN; END IF;
  _state := _state || jsonb_build_object('passes', (_state->>'passes')::int + 1, 'last_pass_by', _part.slot);
  IF jsonb_array_length(COALESCE(_state->'board', '[]'::jsonb)) = 0 THEN
    _state := _state - 'first_move_double';
  END IF;
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  IF (_state->>'passes')::int >= _count THEN PERFORM public.domino_end_round(_game_id, null, true);
  ELSE PERFORM public.domino_advance_turn(_game_id, _state, _ts); END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.domino_auto_timeout(uuid, public.domino_participants) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.domino_auto_timeout(uuid, public.domino_participants) TO authenticated, service_role;
