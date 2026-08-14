-- ============================================================
-- FIX: _chess_insufficient_material crash "invalid input syntax for type integer: 3P4"
--
-- Bug 1: Erreur "invalid input syntax for type integer: 3P4" à chaque coup
-- Bug 2: Le match ne se termine jamais (_chess_check_game_end crash)
--
-- Problème:
-- La fonction parcourait les rangées du FEN (splittées par '/') et pour
-- chaque rangée, vérifiait `IF c ~ '[0-9]' THEN i := i + c::int`.
-- Mais une rangée comme "3P4" (3 cases vides + Pion + 4 cases vides)
-- contient des chiffres ET des lettres. Le regex matche, mais c::int
-- échoue car "3P4" n'est pas un entier valide.
--
-- Conséquence:
-- _chess_check_game_end appelle _chess_insufficient_material après chaque
-- coup. Le crash faisait que l'edge function retournait une erreur 500
-- sur chaque coup, et la détection des règles de fin (50 coups, répétition
-- triple, matériel insuffisant) était cassée.
--
-- Solution:
-- 1. Parcourir caractère par caractère avec substring() au lieu de caster
--    la rangée entière
-- 2. Ignorer les rois (K/k) au lieu de RETURN false (les rois sont toujours
--    présents et ne comptent pas pour le matériel insuffisant)
-- ============================================================

CREATE OR REPLACE FUNCTION public._chess_insufficient_material(_fen text)
RETURNS boolean LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  placement text;
  white_pieces text := '';
  black_pieces text := '';
  white_bishop_color text := '';
  black_bishop_color text := '';
  rows text[];
  row_str text;
  ch text;
  i int;
  j int;
  row int;
  col int;
BEGIN
  placement := split_part(_fen, ' ', 1);
  i := 0;
  rows := string_to_array(placement, '/');

  FOREACH row_str IN ARRAY rows LOOP
    FOR j IN 1..length(row_str) LOOP
      ch := substring(row_str, j, 1);
      IF ch ~ '[1-8]' THEN
        i := i + ch::int;
      ELSIF ch IN ('K', 'k') THEN
        i := i + 1;
      ELSIF ch IN ('Q', 'R', 'P', 'q', 'r', 'p') THEN
        RETURN false;
      ELSIF ch IN ('B', 'b', 'N', 'n') THEN
        IF ch = 'B' THEN
          white_pieces := white_pieces || 'B';
          row := i / 8; col := i % 8;
          white_bishop_color := CASE WHEN (row + col) % 2 = 0 THEN 'light' ELSE 'dark' END;
        ELSIF ch = 'b' THEN
          black_pieces := black_pieces || 'b';
          row := i / 8; col := i % 8;
          black_bishop_color := CASE WHEN (row + col) % 2 = 0 THEN 'light' ELSE 'dark' END;
        ELSIF ch = 'N' THEN
          white_pieces := white_pieces || 'N';
        ELSIF ch = 'n' THEN
          black_pieces := black_pieces || 'n';
        END IF;
        i := i + 1;
      END IF;
    END LOOP;
  END LOOP;

  IF white_pieces = '' AND black_pieces = '' THEN RETURN true; END IF;
  IF white_pieces IN ('N', 'NN') AND black_pieces = '' THEN RETURN true; END IF;
  IF black_pieces IN ('n', 'nn') AND white_pieces = '' THEN RETURN true; END IF;
  IF white_pieces = 'B' AND black_pieces = '' THEN RETURN true; END IF;
  IF black_pieces = 'b' AND white_pieces = '' THEN RETURN true; END IF;
  IF white_pieces = 'B' AND black_pieces = 'b' AND white_bishop_color = black_bishop_color THEN
    RETURN true;
  END IF;
  RETURN false;
END $$;

-- Tests de validation
SELECT public._chess_insufficient_material('rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR w KQkq - 0 1') AS should_be_false;
SELECT public._chess_insufficient_material('8/8/8/8/4k3/8/4K3/8 w - - 0 1') AS should_be_true;
SELECT public._chess_insufficient_material('8/8/8/8/4k3/8/4K3/7B w - - 0 1') AS should_be_true;
SELECT public._chess_insufficient_material('8/8/8/8/4k3/8/4K3/7N w - - 0 1') AS should_be_true;
