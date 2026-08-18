-- ════════════════════════════════════════════════════════════════════
-- Règle "7 Cartes - Miverim-bola" : implémentation PUR (sans Joker)
--
-- 3 compositions autorisées :
--  1. Tri (3 même valeur) + Escalier (4 consécutives, même couleur)
--  2. Tri (3 même valeur) + Carré (4 même valeur, couleurs différentes)
--  3. Escalier (3 consécutives, même couleur) + Carré (4 même valeur)
--
-- Règle essentielle : 100% PUR — aucun Joker n'est accepté dans les 7 cartes.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._rami_is_seven(_cards integer[], _mode text, _rj integer)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $$
DECLARE
  _n int := COALESCE(array_length(_cards, 1), 0);
  i int; j int; k int; m int;
  _three int[]; _four int[]; _t3 text; _t4 text;
  _c int;
BEGIN
  IF _n <> 7 THEN RETURN false; END IF;

  -- PUR : rejeter tout groupe contenant un Joker
  FOREACH _c IN ARRAY _cards LOOP
    IF public._rami_is_joker(_c, _mode, _rj) THEN RETURN false; END IF;
  END LOOP;

  -- Toutes les partitions 3+4 des 7 cartes
  FOR i IN 1..5 LOOP
  FOR j IN i+1..6 LOOP
  FOR k IN j+1..7 LOOP
    _three := ARRAY[_cards[i], _cards[j], _cards[k]];
    _four  := ARRAY[]::int[];
    FOR m IN 1..7 LOOP
      IF m <> i AND m <> j AND m <> k THEN
        _four := _four || _cards[m];
      END IF;
    END LOOP;

    _t3 := public._rami_meld_type(_three, _mode, _rj);
    _t4 := public._rami_meld_type(_four,  _mode, _rj);

    -- Comp. 1 : Tri + Escalier de 4
    IF _t3 = 'trio' AND _t4 = 'run'   THEN RETURN true; END IF;
    -- Comp. 2 : Tri + Carré
    IF _t3 = 'trio' AND _t4 = 'carre' THEN RETURN true; END IF;
    -- Comp. 3 : Escalier de 3 + Carré
    IF _t3 = 'run'  AND _t4 = 'carre' THEN RETURN true; END IF;
  END LOOP; END LOOP; END LOOP;

  RETURN false;
END $$;
