-- ═══ Fix: reconstruire le tableau plat discard dans le bon ordre ═══
-- La migration précédente a reconstruit le tableau plat à partir de la multi-pile
-- dans l'ordre de jsonb_each (non-chronologique). Il faut que la dernière carte
-- du tableau plat soit la carte du dessus de la pile last_discard_by.

DO $$
DECLARE
  _g RECORD; _state jsonb; _discards jsonb; _flat int[];
  _last_by text; _last_pile int[]; _other_pile int[];
  _k text; _v jsonb; _needs_fix boolean;
BEGIN
  FOR _g IN SELECT id, state FROM public.rami_games WHERE status = 'playing' LOOP
    _state := _g.state;
    _flat := public._rami_jarr(_state->'discard');
    _discards := public._rami_discards_map(_state);
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _last_pile := public._rami_jarr(_discards->_last_by);
    _needs_fix := false;
    
    -- Vérifier si la dernière carte du flat array correspond au sommet de last_discard_by
    IF array_length(_flat, 1) IS NOT NULL AND array_length(_last_pile, 1) IS NOT NULL THEN
      IF _flat[array_length(_flat, 1)] <> _last_pile[array_length(_last_pile, 1)] THEN
        _needs_fix := true;
      END IF;
    END IF;
    
    IF _needs_fix THEN
      -- Reconstruire: autres piles d'abord, puis la pile last_discard_by à la fin
      _flat := ARRAY[]::int[];
      FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
        IF _k <> _last_by THEN
          _flat := _flat || public._rami_jarr(_v);
        END IF;
      END LOOP;
      -- Ajouter la pile last_discard_by à la fin
      _flat := _flat || _last_pile;
      
      _state := jsonb_set(_state, '{discard}', to_jsonb(_flat), true);
      UPDATE public.rami_games SET state = _state, updated_at = now() WHERE id = _g.id;
      RAISE NOTICE 'Fix ordre discard pour jeu %', _g.id;
    END IF;
  END LOOP;
END $$;
