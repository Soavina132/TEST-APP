CREATE OR REPLACE FUNCTION public.domino_hand_pips(_hand jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE SECURITY DEFINER
AS $function$
DECLARE _sum int := 0; _i int;
BEGIN
  IF _hand IS NULL THEN RETURN 0; END IF;
  FOR _i IN 0..jsonb_array_length(_hand)-1 LOOP
    _sum := _sum + (_hand->(_i)->>0)::int + (_hand->(_i)->>1)::int;
  END LOOP;
  RETURN _sum;
END;
$function$
