CREATE OR REPLACE FUNCTION public._rami_is_seven(_cards integer[], _mode text, _rj integer)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO 'public'
AS $function$
DECLARE
  _n int := COALESCE(array_length(_cards,1),0);
  i int; j int; k int; l int; m int;
  _four int[]; _three int[]; _t4 text; _t3 text;
BEGIN
  IF _n <> 7 THEN RETURN false; END IF;
  FOR i IN 1..4 LOOP
  FOR j IN i+1..5 LOOP
  FOR k IN j+1..6 LOOP
  FOR l IN k+1..7 LOOP
    _four  := ARRAY[_cards[i],_cards[j],_cards[k],_cards[l]];
    _three := ARRAY[]::int[];
    FOR m IN 1..7 LOOP
      IF m <> i AND m <> j AND m <> k AND m <> l THEN
        _three := _three || _cards[m];
      END IF;
    END LOOP;
    _t4 := public._rami_meld_type(_four,  _mode, _rj);
    _t3 := public._rami_meld_type(_three, _mode, _rj);
    IF _t4 IN ('carre','run') AND _t3 IN ('trio','run') THEN RETURN true; END IF;
  END LOOP; END LOOP; END LOOP; END LOOP;
  RETURN false;
END
$function$;