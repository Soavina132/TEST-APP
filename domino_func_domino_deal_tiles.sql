CREATE OR REPLACE FUNCTION public.domino_deal_tiles(_game_id uuid, _tiles jsonb, _ppp integer DEFAULT 7)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  _hands jsonb := '{}'::jsonb; _stock jsonb; _p record; _count int; _offset int;
BEGIN
  SELECT count(*) INTO _count FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
  FOR _p IN SELECT * FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false ORDER BY slot LOOP
    _offset := _p.slot * _ppp;
    _hands := _hands || jsonb_build_object(_p.slot::text,
      (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(_tiles) WITH ORDINALITY AS ord(x, rn) WHERE rn > _offset AND rn <= _offset + _ppp ORDER BY rn) s));
  END LOOP;
  _stock := (SELECT jsonb_agg(x) FROM (SELECT x FROM jsonb_array_elements(_tiles) WITH ORDINALITY AS ord(x, rn) WHERE rn > _count * _ppp ORDER BY rn) s);
  RETURN jsonb_build_object('hands', _hands, 'stock', COALESCE(_stock, '[]'::jsonb));
END;
$function$
