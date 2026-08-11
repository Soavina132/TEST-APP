-- ═══════════════════════════════════════════════════════════════════════
-- FIX v9 — _domino_bot_loop simplifiée et robuste
--
-- Problème: _domino_bot_loop ne jouait qu'un bot par appel.
-- Cause: domino_tick ne fait rien si bot_think_until est dans le futur.
-- Le sleep ne suffisait pas pour faire expirer le timer.
--
-- Solution: boucle simple — tick → sleep 1s → tick → repeat.
-- Pas de lecture de bot_think_until, pas d'armement explicite.
-- domino_tick gère tout (arm ou play selon l'état).
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._domino_bot_loop(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_is_bot    boolean;
  v_max_loops int := 30;
  g_status    text;
  g_phase     text;
BEGIN
  LOOP
    EXIT WHEN v_max_loops <= 0;
    v_max_loops := v_max_loops - 1;

    -- Vérifier le statut
    SELECT status::text, state->>'phase' INTO g_status, g_phase
      FROM public.domino_games WHERE id = _game_id;
    EXIT WHEN g_status IS NULL OR g_status <> 'playing';
    EXIT WHEN g_phase NOT IN ('play', 'playing');
    EXIT WHEN g_phase IN ('reveal', 'break', 'dealing');

    -- Est-ce un bot?
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot
      FROM public.domino_participants dp
      JOIN public.domino_games g ON g.id = dp.game_id
     WHERE dp.game_id = _game_id
       AND dp.slot = g.current_turn
       AND dp.forfeited = false;

    EXIT WHEN NOT COALESCE(v_is_bot, false);

    -- Tick (arme ou fait jouer le bot selon l'état)
    PERFORM public.domino_tick(_game_id);

    -- Petit délai pour laisser le think timer expirer
    PERFORM pg_sleep(1);

    -- Tick encore (le bot devrait jouer maintenant)
    PERFORM public.domino_tick(_game_id);

    -- Petit délai avant de revérifier
    PERFORM pg_sleep(0.1);
  END LOOP;
END;
$function$;
