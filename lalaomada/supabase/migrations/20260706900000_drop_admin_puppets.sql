-- ============================================================
-- Suppression des "comptes fantômes" (admin puppets)
-- Cette fonctionnalité (créer un compte séparé avec sa propre balance
-- pour jouer incognito) n'était plus utilisée dans l'interface admin
-- (jamais reliée à un onglet) et fait doublon avec l'alias admin
-- (admin_persona), qui remplit le même besoin de façon plus simple et
-- plus sûre : pas de nouveau compte auth, même solde/historique, et
-- déjà visible dans le chat et le classement.
-- ============================================================

DROP FUNCTION IF EXISTS public.admin_list_puppets();
DROP FUNCTION IF EXISTS public.admin_delete_puppet(UUID);
DROP FUNCTION IF EXISTS public.admin_update_puppet(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public.admin_create_puppet(TEXT, TEXT);

DROP TABLE IF EXISTS public.admin_puppets;
