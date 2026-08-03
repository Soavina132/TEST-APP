-- ============================================================
-- Bibliothèque d'alias admin — plusieurs alias enregistrés
-- ============================================================

-- Table de bibliothèque
CREATE TABLE IF NOT EXISTS public.admin_aliases (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pseudo      TEXT NOT NULL,
  avatar_url  TEXT,
  created_at  TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.admin_aliases ENABLE ROW LEVEL SECURITY;
CREATE POLICY "aliases_own" ON public.admin_aliases
  USING  (admin_id = auth.uid())
  WITH CHECK (admin_id = auth.uid());

-- Lier admin_persona à un alias de la bibliothèque
ALTER TABLE public.admin_persona
  ADD COLUMN IF NOT EXISTS alias_id UUID REFERENCES public.admin_aliases(id) ON DELETE SET NULL;

-- ── admin_save_alias : créer un alias dans la bibliothèque ───
CREATE OR REPLACE FUNCTION public.admin_save_alias(
  p_pseudo     TEXT,
  p_avatar_url TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  INSERT INTO public.admin_aliases (admin_id, pseudo, avatar_url)
  VALUES (auth.uid(), p_pseudo, p_avatar_url)
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

-- ── admin_list_aliases : lister les alias de l'admin ─────────
CREATE OR REPLACE FUNCTION public.admin_list_aliases()
RETURNS TABLE(
  id          UUID,
  pseudo      TEXT,
  avatar_url  TEXT,
  created_at  TIMESTAMPTZ,
  is_active   BOOLEAN
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT a.id, a.pseudo, a.avatar_url, a.created_at,
           COALESCE((
             SELECT p.is_active AND p.alias_id = a.id
             FROM public.admin_persona p
             WHERE p.admin_id = auth.uid()
           ), false) AS is_active
    FROM public.admin_aliases a
    WHERE a.admin_id = auth.uid()
    ORDER BY a.created_at DESC;
END;
$$;

-- ── admin_delete_alias ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_delete_alias(p_alias_id UUID)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  -- Si cet alias est actif, désactiver d'abord
  IF EXISTS (
    SELECT 1 FROM public.admin_persona
    WHERE admin_id = auth.uid() AND alias_id = p_alias_id AND is_active = true
  ) THEN
    PERFORM public.admin_deactivate_persona();
  END IF;
  DELETE FROM public.admin_aliases WHERE id = p_alias_id AND admin_id = auth.uid();
END;
$$;

-- ── admin_activate_alias : activer un alias depuis la bibliothèque
CREATE OR REPLACE FUNCTION public.admin_activate_alias(p_alias_id UUID)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_alias   RECORD;
  v_real_pseudo     TEXT;
  v_real_avatar_url TEXT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  SELECT pseudo, avatar_url INTO v_alias
  FROM public.admin_aliases
  WHERE id = p_alias_id AND admin_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Alias introuvable'; END IF;

  -- Récupérer le vrai profil courant
  SELECT pseudo, avatar_url INTO v_real_pseudo, v_real_avatar_url
  FROM public.profiles WHERE id = auth.uid();

  -- Upsert dans admin_persona
  INSERT INTO public.admin_persona
      (admin_id, real_pseudo, real_avatar_url, persona_pseudo, persona_avatar, alias_id, is_active, activated_at)
  VALUES
      (auth.uid(), v_real_pseudo, v_real_avatar_url, v_alias.pseudo, v_alias.avatar_url, p_alias_id, true, now())
  ON CONFLICT (admin_id) DO UPDATE
    SET persona_pseudo  = EXCLUDED.persona_pseudo,
        persona_avatar  = EXCLUDED.persona_avatar,
        alias_id        = EXCLUDED.alias_id,
        is_active       = true,
        activated_at    = now(),
        real_pseudo     = CASE WHEN admin_persona.is_active THEN admin_persona.real_pseudo
                               ELSE EXCLUDED.real_pseudo END,
        real_avatar_url = CASE WHEN admin_persona.is_active THEN admin_persona.real_avatar_url
                               ELSE EXCLUDED.real_avatar_url END;

  -- Appliquer sur le profil
  UPDATE public.profiles
    SET pseudo     = v_alias.pseudo,
        avatar_url = v_alias.avatar_url
    WHERE id = auth.uid();
END;
$$;
