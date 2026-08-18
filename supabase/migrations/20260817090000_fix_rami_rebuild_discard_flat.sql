-- ═══════════════════════════════════════════════════════════════════
-- FIX: Reconstruire le tableau plat discard pour les parties existantes
--
-- Problème: Certaines parties en cours ont state.discard = NULL alors
-- que state.discards (multi-pile) contient des cartes. Le frontend ne
-- peut pas piocher sur la défausse car flatDiscard est vide.
--
-- Solution: Reconstruire discard à partir de discards, en mettant la
-- pile last_discard_by à la fin (carte du dessus).
-- ═══════════════════════════════════════════════════════════════════

DO $$
DECLARE
  _g RECORD;
  _state jsonb;
  _discards jsonb;
  _flat int[];
  _last_by text;
  _k text;
  _v jsonb;
  _last_pile int[];
  _other_pile int[];
BEGIN
  FOR _g IN SELECT id, state FROM public.rami_games WHERE status = 'playing' LOOP
    _state := _g.state;
    
    -- Si discard est déjà un array non-vide, skip
    IF _state->'discard' IS NOT NULL 
       AND jsonb_typeof(_state->'discard') = 'array' 
       AND jsonb_array_length(_state->'discard') > 0 THEN
      CONTINUE;
    END IF;
    
    -- Récupérer la multi-pile
    _discards := public._rami_discards_map(_state);
    IF _discards IS NULL OR jsonb_typeof(_discards) = 'null' OR _discards = '{}'::jsonb THEN
      CONTINUE;
    END IF;
    
    -- Reconstruire: autres piles d'abord, puis last_discard_by à la fin
    _last_by := COALESCE(_state->>'last_discard_by', '_seed');
    _flat := ARRAY[]::int[];
    _last_pile := ARRAY[]::int[];
    
    FOR _k, _v IN SELECT * FROM jsonb_each(_discards) LOOP
      IF _k = _last_by THEN
        _last_pile := public._rami_jarr(_v);
      ELSE
        _other_pile := public._rami_jarr(_v);
        IF array_length(_other_pile, 1) IS NOT NULL THEN
          _flat := _flat || _other_pile;
        END IF;
      END IF;
    END LOOP;
    
    -- Ajouter la pile last_discard_by à la fin
    IF array_length(_last_pile, 1) IS NOT NULL THEN
      _flat := _flat || _last_pile;
    END IF;
    
    -- Sauvegarder seulement si on a trouvé des cartes
    IF array_length(_flat, 1) IS NOT NULL THEN
      _state := jsonb_set(_state, '{discard}', to_jsonb(_flat), true);
      UPDATE public.rami_games 
        SET state = _state, updated_at = now() 
        WHERE id = _g.id;
      RAISE NOTICE 'Fix discard reconstruit pour jeu % (% cartes)', _g.id, array_length(_flat, 1);
    END IF;
  END LOOP;
END $$;
