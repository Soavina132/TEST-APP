-- Fix: "function public._fanorona_finalize(uuid, integer) is not unique"
--
-- La migration 20260818160000 a créé _fanorona_finalize avec 3 params
-- (uuid, int, text DEFAULT NULL) mais l'ancienne version à 2 params
-- (uuid, int) existe encore. Les deux matchent un appel à 2 args.
-- Solution: DROP l'ancienne signature.

DROP FUNCTION IF EXISTS public._fanorona_finalize(uuid, int) CASCADE;
