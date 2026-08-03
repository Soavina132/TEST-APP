-- ============================================================
-- Alias temporaire pour l'admin
-- Permet de jouer sous un faux nom/photo sans créer un nouveau compte.
-- Le solde et l'historique restent ceux du compte admin.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_persona (
  admin_id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  -- Sauvegarde du vrai profil (pour restauration)
  real_pseudo      TEXT NOT NULL DEFAULT '',
  real_avatar_url  TEXT,
  -- Alias actif
  persona_pseudo   TEXT,
  persona_avatar   TEXT,
  is_active        BOOLEAN NOT NULL DEFAULT false,
  activated_at     TIMESTAMPTZ
);

ALTER TABLE public.admin_persona ENABLE ROW LEVEL SECURITY;
-- L'admin ne peut voir/modifier que sa propre ligne
CREATE POLICY "persona_own" ON public.admin_persona
  USING (admin_id = auth.uid())
  WITH CHECK (admin_id = auth.uid());

-- ── Activer l'alias ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_activate_persona(
  p_pseudo     TEXT,
  p_avatar_url TEXT DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_real_pseudo     TEXT;
  v_real_avatar_url TEXT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  -- Récupérer le vrai profil actuel
  SELECT pseudo, avatar_url
    INTO v_real_pseudo, v_real_avatar_url
    FROM public.profiles WHERE id = auth.uid();

  -- Sauvegarder le vrai profil (seulement si aucun alias n'est déjà actif)
  INSERT INTO public.admin_persona
      (admin_id, real_pseudo, real_avatar_url, persona_pseudo, persona_avatar, is_active, activated_at)
  VALUES
      (auth.uid(), v_real_pseudo, v_real_avatar_url, p_pseudo, p_avatar_url, true, now())
  ON CONFLICT (admin_id) DO UPDATE
    SET persona_pseudo  = EXCLUDED.persona_pseudo,
        persona_avatar  = EXCLUDED.persona_avatar,
        is_active       = true,
        activated_at    = now(),
        -- Ne pas écraser real_* si un alias était déjà actif (pour conserver la vraie sauvegarde)
        real_pseudo     = CASE WHEN admin_persona.is_active THEN admin_persona.real_pseudo
                               ELSE EXCLUDED.real_pseudo END,
        real_avatar_url = CASE WHEN admin_persona.is_active THEN admin_persona.real_avatar_url
                               ELSE EXCLUDED.real_avatar_url END;

  -- Appliquer l'alias sur le profil
  UPDATE public.profiles
    SET pseudo     = p_pseudo,
        avatar_url = p_avatar_url
    WHERE id = auth.uid();
END;
$$;

-- ── Désactiver l'alias (restaurer le vrai profil) ────────────
CREATE OR REPLACE FUNCTION public.admin_deactivate_persona()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_real_pseudo     TEXT;
  v_real_avatar_url TEXT;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  SELECT real_pseudo, real_avatar_url
    INTO v_real_pseudo, v_real_avatar_url
    FROM public.admin_persona WHERE admin_id = auth.uid();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Aucun alias actif trouvé';
  END IF;

  -- Restaurer le vrai profil
  UPDATE public.profiles
    SET pseudo     = v_real_pseudo,
        avatar_url = v_real_avatar_url
    WHERE id = auth.uid();

  -- Marquer comme inactif
  UPDATE public.admin_persona
    SET is_active = false
    WHERE admin_id = auth.uid();
END;
$$;

-- ── Lire l'état courant ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_persona()
RETURNS TABLE(
  is_active        BOOLEAN,
  real_pseudo      TEXT,
  real_avatar_url  TEXT,
  persona_pseudo   TEXT,
  persona_avatar   TEXT,
  activated_at     TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT ap.is_active, ap.real_pseudo, ap.real_avatar_url,
           ap.persona_pseudo, ap.persona_avatar, ap.activated_at
    FROM public.admin_persona ap
    WHERE ap.admin_id = auth.uid();
END;
$$;
