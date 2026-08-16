-- Fix: Anciennes parties démarrées avec _seed sur la défausse
-- avant la migration 20260816140000.
-- Le 1er joueur est bloqué en phase 'play' avec une carte _seed visible.

DO $$
DECLARE
  _g record;
  _state jsonb;
  _seed_card int;
  _deck int[];
  _discards jsonb;
  _seed_arr int[];
  _k text;
  _v jsonb;
  _flat int[];
BEGIN
  FOR _g IN
    SELECT id, state FROM public.rami_games
    WHERE status = 'playing'
      AND current_turn = 0
      AND turn_phase = 'play'
  LOOP
    _state := _g.state;
    _discards := COALESCE(_state->'discards', '{}'::jsonb);

    IF (_discards ? '_seed')
       AND COALESCE(_state->>'last_discard_by', '') = '_seed'
    THEN
      _seed_arr := public._rami_jarr(_discards->'_seed');
      _seed_card := _seed_arr[1];

      _discards := _discards - '_seed';

      _deck := COALESCE(public._rami_jarr(_state->'deck'), ARRAY[]::int[]);
      _deck := array_append(_deck, _seed_card);

      _flat := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        _flat := _flat || public._rami_jarr(_v);
      END LOOP;

      _state := jsonb_set(_state, '{deck}', to_jsonb(_deck));
      _state := jsonb_set(_state, '{discards}', _discards);
      _state := jsonb_set(_state, '{discard}', to_jsonb(_flat), true);
      _state := jsonb_set(_state, '{last_discard_by}', 'null'::jsonb, true);

      UPDATE public.rami_games
        SET state = _state, updated_at = now()
        WHERE id = _g.id;

      RAISE NOTICE 'Fixed stuck game: %', _g.id;
    END IF;
  END LOOP;
END $$;
