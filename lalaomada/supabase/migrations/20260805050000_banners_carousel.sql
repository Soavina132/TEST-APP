-- ═══════════════════════════════════════════════════════════════════════════
-- Banners carousel (home page promo slider) + admin management RPCs
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.banners (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title         text NOT NULL,
  subtitle      text,
  image_url     text,
  button_text   text,
  button_link   text,
  bg_gradient   text,
  starts_at     timestamptz,
  ends_at       timestamptz,
  active        boolean NOT NULL DEFAULT true,
  sort_order    int NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.banners ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "banners_public_read" ON public.banners;
CREATE POLICY "banners_public_read" ON public.banners FOR SELECT USING (true);

DROP POLICY IF EXISTS "banners_admin_write" ON public.banners;
CREATE POLICY "banners_admin_write" ON public.banners FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ─────────────────────────────────────────────────────────────────────────
-- admin_banner_upsert — create or update a banner
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_banner_upsert(
  _id          UUID,
  _title       TEXT,
  _subtitle    TEXT        DEFAULT NULL,
  _image_url   TEXT        DEFAULT NULL,
  _button_text TEXT        DEFAULT NULL,
  _button_link TEXT        DEFAULT NULL,
  _bg_gradient TEXT        DEFAULT NULL,
  _starts_at   TIMESTAMPTZ DEFAULT NULL,
  _ends_at     TIMESTAMPTZ DEFAULT NULL,
  _active      BOOLEAN     DEFAULT TRUE,
  _sort_order  INT         DEFAULT 0
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  IF _id IS NULL THEN
    INSERT INTO public.banners (title, subtitle, image_url, button_text, button_link, bg_gradient, starts_at, ends_at, active, sort_order)
    VALUES (trim(_title), _subtitle, _image_url, _button_text, _button_link, _bg_gradient, _starts_at, _ends_at, COALESCE(_active, TRUE), COALESCE(_sort_order, 0))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.banners SET
      title       = COALESCE(trim(_title), title),
      subtitle    = _subtitle,
      image_url   = _image_url,
      button_text = _button_text,
      button_link = _button_link,
      bg_gradient = _bg_gradient,
      starts_at   = _starts_at,
      ends_at     = _ends_at,
      active      = COALESCE(_active, active),
      sort_order  = COALESCE(_sort_order, sort_order),
      updated_at  = now()
    WHERE id = _id;
    v_id := _id;
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_banner_upsert(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,BOOLEAN,INT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_banner_upsert(UUID,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TIMESTAMPTZ,TIMESTAMPTZ,BOOLEAN,INT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- admin_banner_delete — delete a banner
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_banner_delete(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  DELETE FROM public.banners WHERE id = _id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_banner_delete(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION public.admin_banner_delete(UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────
-- Seed: 4 example banners requested by the admin
-- ─────────────────────────────────────────────────────────────────────────
INSERT INTO public.banners (title, subtitle, button_text, button_link, bg_gradient, active, sort_order)
VALUES
  ('🏆 TOURNOI LUDO', E'Commence demain à 20h\n🎁 Récompense : 50 000 Ar', 'Participer', '/tournaments', 'from-amber-500 to-orange-600', true, 0),
  ('🎁 INVITE TES AMIS', E'5 filleuls = 500 Ar\n10 filleuls = 1000 Ar', 'Partager', '/parrainage', 'from-emerald-500 to-teal-600', true, 1),
  ('🔥 NOUVEAU JEU DISPONIBLE', 'Découvrez Rami Madagascar', 'Jouer', '/jeux/rami', 'from-rose-500 to-pink-600', true, 2),
  ('💰 BONUS DU JOUR', 'Recevez une récompense après vos parties', 'Voir', '/profile', 'from-violet-500 to-indigo-600', true, 3)
ON CONFLICT DO NOTHING;

NOTIFY pgrst, 'reload schema';
