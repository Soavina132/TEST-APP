
ALTER TABLE public.money_offers
  ADD COLUMN IF NOT EXISTS link TEXT,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.admin_offer_upsert(
  _id UUID,
  _title TEXT,
  _description TEXT,
  _image_url TEXT,
  _link TEXT,
  _expires_at TIMESTAMPTZ,
  _active BOOLEAN
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;

  IF _id IS NULL THEN
    INSERT INTO public.money_offers (title, description, image_url, link, expires_at, active)
    VALUES (_title, _description, _image_url, _link, _expires_at, COALESCE(_active, true))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.money_offers
       SET title = _title,
           description = _description,
           image_url = _image_url,
           link = _link,
           expires_at = _expires_at,
           active = COALESCE(_active, active),
           updated_at = now()
     WHERE id = _id
    RETURNING id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_offer_delete(_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin'::public.app_role) THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  DELETE FROM public.money_offers WHERE id = _id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_offer_upsert(UUID, TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_offer_delete(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';
