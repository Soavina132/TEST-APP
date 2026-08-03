
CREATE OR REPLACE FUNCTION public.admin_broadcast_tournament_notification(
  _tid uuid,
  _title text,
  _body text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _sent int := 0;
  _r record;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  IF _tid IS NULL OR coalesce(trim(_title),'') = '' THEN
    RAISE EXCEPTION 'invalid_arguments';
  END IF;

  FOR _r IN
    SELECT DISTINCT user_id
      FROM public.tournament_registrations
     WHERE tournament_id = _tid
       AND user_id IS NOT NULL
  LOOP
    INSERT INTO public.notifications (user_id, type, title, body, data)
    VALUES (
      _r.user_id,
      'tournament_broadcast',
      _title,
      coalesce(_body, ''),
      jsonb_build_object('tournament_id', _tid)
    );
    _sent := _sent + 1;
  END LOOP;

  RETURN jsonb_build_object('sent', _sent);
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_broadcast_tournament_notification(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
