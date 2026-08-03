-- ============================================================
-- Comptes fantômes (admin puppets)
-- L'admin peut créer des profils fictifs avec photo + pseudo
-- pour jouer incognito comme un vrai joueur.
-- ============================================================

-- ── Table de suivi ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_puppets (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  admin_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pseudo     TEXT NOT NULL,
  avatar_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.admin_puppets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "puppets_admin_only" ON public.admin_puppets
  USING (public.is_admin());

-- ── Créer un compte fantôme ──────────────────────────────────
-- search_path = public pour accéder aux extensions pgcrypto (crypt, gen_salt)
CREATE OR REPLACE FUNCTION public.admin_create_puppet(
  p_pseudo     TEXT,
  p_avatar_url TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_id    UUID := gen_random_uuid();
  v_email TEXT := 'puppet_' || v_id::text || '@ghost.lalaomada.internal';
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Réservé admin';
  END IF;

  -- Créer l'utilisateur dans auth.users directement
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password, email_confirmed_at,
    raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_email,
    crypt(gen_random_uuid()::text, gen_salt('bf')),
    now(),
    jsonb_build_object('pseudo', p_pseudo, 'is_puppet', true),
    now(), now(),
    '', '', '', ''
  );

  -- Le trigger handle_new_user crée automatiquement le profil.
  -- Corriger : 0 solde, appliquer l'avatar, supprimer le bonus inscription.
  UPDATE public.profiles
    SET balance_ar = 0, avatar_url = p_avatar_url
    WHERE id = v_id;

  DELETE FROM public.transactions
    WHERE user_id = v_id AND type = 'bonus';

  -- Enregistrer dans la table de suivi
  INSERT INTO public.admin_puppets (user_id, admin_id, pseudo, avatar_url)
  VALUES (v_id, auth.uid(), p_pseudo, p_avatar_url);

  RETURN json_build_object(
    'user_id',    v_id,
    'email',      v_email,
    'pseudo',     p_pseudo,
    'avatar_url', p_avatar_url
  );
END;
$$;

-- ── Mettre à jour pseudo / avatar ────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_puppet(
  p_puppet_user_id UUID,
  p_pseudo         TEXT,
  p_avatar_url     TEXT DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  -- Vérifier la possession avant toute mutation
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_puppets
    WHERE user_id = p_puppet_user_id AND admin_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Compte fantôme introuvable ou non autorisé';
  END IF;

  UPDATE public.admin_puppets
    SET pseudo = p_pseudo, avatar_url = p_avatar_url
    WHERE user_id = p_puppet_user_id AND admin_id = auth.uid();

  -- Mettre à jour le profil uniquement après confirmation de la possession
  UPDATE public.profiles
    SET pseudo = p_pseudo, avatar_url = p_avatar_url
    WHERE id = p_puppet_user_id;
END;
$$;

-- ── Supprimer un compte fantôme ──────────────────────────────
-- Vérifie la possession, retire toujours du panneau admin,
-- puis tente la suppression complète. Si des FK bloquent (parties jouées),
-- la suppression auth/profiles est annulée (subtransaction) mais l'untrack persiste.
CREATE OR REPLACE FUNCTION public.admin_delete_puppet(p_puppet_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  -- Vérifier la possession avant toute action
  IF NOT EXISTS (
    SELECT 1 FROM public.admin_puppets
    WHERE user_id = p_puppet_user_id AND admin_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Compte fantôme introuvable ou non autorisé';
  END IF;

  -- Untrack (toujours exécuté, hors subtransaction)
  DELETE FROM public.admin_puppets
    WHERE user_id = p_puppet_user_id AND admin_id = auth.uid();

  -- Tentative de suppression complète dans une subtransaction
  BEGIN
    DELETE FROM public.user_roles   WHERE user_id = p_puppet_user_id;
    DELETE FROM public.transactions WHERE user_id = p_puppet_user_id;
    DELETE FROM public.profiles     WHERE id      = p_puppet_user_id;
    DELETE FROM auth.users          WHERE id      = p_puppet_user_id;
    RETURN 'deleted';
  EXCEPTION WHEN foreign_key_violation OR restrict_violation THEN
    -- Historique de jeu détecté : le compte auth/profil reste, juste retiré du panneau
    RETURN 'untracked';
  END;
END;
$$;

-- ── Lister les comptes fantômes ──────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_puppets()
RETURNS TABLE(
  id         UUID,
  user_id    UUID,
  pseudo     TEXT,
  avatar_url TEXT,
  email      TEXT,
  balance_ar NUMERIC,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT ap.id, ap.user_id, ap.pseudo, ap.avatar_url,
           u.email::TEXT, p.balance_ar, ap.created_at
    FROM public.admin_puppets ap
    JOIN auth.users u    ON u.id = ap.user_id
    JOIN public.profiles p ON p.id = ap.user_id
    WHERE ap.admin_id = auth.uid()
    ORDER BY ap.created_at DESC;
END;
$$;
