-- Fix: domino_play_and_bot retournait void → le frontend attendait jsonb
-- PostgREST ne savait pas sérialiser la réponse → "could not determine polymorphic type"
-- Maintenant retourne l'état du jeu via _domino_visible après que les bots aient joué.

DROP FUNCTION IF EXISTS public.domino_play_and_bot(uuid, jsonb);

CREATE OR REPLACE FUNCTION public.domino_play_and_bot(_game_id uuid, _move jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public', 'extensions'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- 1. Le joueur humain joue
  v_result := public.domino_play(_game_id, _move);

  -- 2. Faire jouer les bots (gere aussi reveal/break/dealing)
  PERFORM public._domino_bot_loop(_game_id);

  -- 3. Retourner l'état final du jeu (après que les bots aient joué)
  v_result := public._domino_visible(_game_id);
  RETURN v_result;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.domino_play_and_bot(uuid, jsonb) FROM anon;
GRANT EXECUTE ON FUNCTION public.domino_play_and_bot(uuid, jsonb) TO authenticated;
