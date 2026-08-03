
CREATE OR REPLACE FUNCTION public.admin_announcement_create(
  _title text,
  _body text DEFAULT NULL,
  _image_url text DEFAULT NULL,
  _link text DEFAULT NULL,
  _link_label text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden';
  END IF;
  INSERT INTO public.announcements(title, body, image_url, link, link_label, active)
  VALUES (_title, NULLIF(_body,''), NULLIF(_image_url,''), NULLIF(_link,''), NULLIF(_link_label,''), true)
  RETURNING id INTO _id;
  RETURN _id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_announcement_create(text, text, text, text, text) TO authenticated;
NOTIFY pgrst, 'reload schema';
