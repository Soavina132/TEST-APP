CREATE OR REPLACE FUNCTION public.domino_find_first_player(_game_id uuid, _hands jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE _p record; _i int; _ta int; _tb int; _best int := -1; _slot int := 0;
BEGIN
  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    FOR _i IN 0..jsonb_array_length(_hands->(_p.slot::text))-1 LOOP
      _ta := (_hands->(_p.slot::text)->(_i)->>0)::int;
      _tb := (_hands->(_p.slot::text)->(_i)->>1)::int;
      IF _ta = _tb AND _ta > _best THEN _best := _ta; _slot := _p.slot; END IF;
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('slot', _slot, 'double', CASE WHEN _best >= 0 THEN _best ELSE null END);
END;
$function$
