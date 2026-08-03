
CREATE TABLE IF NOT EXISTS public.cms_content (
  key text PRIMARY KEY,
  content jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL
);

GRANT SELECT ON public.cms_content TO anon, authenticated;
GRANT ALL ON public.cms_content TO service_role;

ALTER TABLE public.cms_content ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cms_content read all" ON public.cms_content;
CREATE POLICY "cms_content read all" ON public.cms_content FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "cms_content admin write" ON public.cms_content;
CREATE POLICY "cms_content admin write" ON public.cms_content FOR ALL TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.admin_update_cms_content(_key text, _content jsonb)
RETURNS public.cms_content
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  row public.cms_content;
BEGIN
  IF NOT public.has_role(auth.uid(), 'admin') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  INSERT INTO public.cms_content (key, content, updated_at, updated_by)
  VALUES (_key, _content, now(), auth.uid())
  ON CONFLICT (key) DO UPDATE
    SET content = EXCLUDED.content,
        updated_at = now(),
        updated_by = auth.uid()
  RETURNING * INTO row;
  RETURN row;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_update_cms_content(text, jsonb) TO authenticated;

-- Seed initial: FAQ
INSERT INTO public.cms_content (key, content) VALUES ('faq', $seed$
{
  "categories": [
    {
      "category": "💰 Dépôts & Retraits",
      "items": [
        {"q":"Comment déposer de l'argent ?","a":"Allez dans 'Mon profil' → 'Dépôt'. Entrez le montant, choisissez votre opérateur Mobile Money (MVola, Orange Money, Airtel Money), puis envoyez le transfert au numéro admin affiché. Votre solde est crédité après validation manuelle par l'admin."},
        {"q":"Comment retirer mes gains ?","a":"Dans 'Mon profil' → 'Retrait'. Entrez le montant, votre numéro Mobile Money, et validez. L'admin traite les demandes manuellement ; le solde est débité dès l'acceptation."},
        {"q":"Mon dépôt n'est pas encore validé, que faire ?","a":"Si votre dépôt n'apparaît pas après un délai raisonnable, contactez le support avec la capture d'écran de confirmation Mobile Money."},
        {"q":"Quel est le dépôt minimum ?","a":"Le montant minimum est affiché directement dans le formulaire de dépôt de votre profil."}
      ]
    },
    {
      "category": "🎮 Parties & Jeux",
      "items": [
        {"q":"Quels jeux sont disponibles ?","a":"Domino, Échecs, Fanorona, Ludo et Rami. Chaque jeu propose des parties gratuites ou avec mise."},
        {"q":"Comment créer une partie ?","a":"Allez dans 'Jeux', choisissez le jeu, définissez la mise (ou choisissez gratuit), le nombre de joueurs, et publiez. La partie apparaît dans le lobby. Elle démarre dès que la salle est complète et que tous les joueurs sont prêts."},
        {"q":"Puis-je jouer contre un bot ?","a":"Oui, sur les parties gratuites : un bouton 'Ajouter un bot' est disponible dans la salle d'attente. Les parties avec mise entre joueurs réels n'acceptent pas de bots (sauf via l'admin)."},
        {"q":"Que se passe-t-il si je quitte une partie ?","a":"Avant le début : votre mise est intégralement remboursée. En cours de partie : vous perdez par forfait et votre mise est distribuée selon les règles du jeu (généralement à l'adversaire)."},
        {"q":"Comment sont distribués les gains ?","a":"Le pot (somme des mises) est versé au gagnant, moins la commission de la plateforme (10%). Le montant net est indiqué en haut de la salle d'attente sous 'Au gagnant'."},
        {"q":"Puis-je annuler une partie en attente ?","a":"Oui, tant qu'aucun autre joueur n'a rejoint, vous pouvez la quitter et votre mise est remboursée. Les salles d'attente inactives sont également nettoyées automatiquement."}
      ]
    },
    {
      "category": "🏆 Tournois",
      "items": [
        {"q":"Comment m'inscrire à un tournoi ?","a":"Allez dans 'Tournois', choisissez un tournoi ouvert, et cliquez 'S'inscrire'. Si le tournoi est payant, la mise est débitée à l'inscription."},
        {"q":"Comment se déroule un tournoi ?","a":"Système à élimination directe. Après les inscriptions, l'admin mélange les joueurs par groupes (1v1, 3 ou 4 joueurs selon le jeu). Vous avez 10 min de préparation, puis 5 min en salle d'entente pour cliquer 'Je suis prêt'."},
        {"q":"Que se passe-t-il si je ne suis pas prêt à temps ?","a":"Si vous ne confirmez pas 'Je suis prêt' avant la fin des 5 minutes en salle d'entente, vous perdez par forfait. Si un seul joueur est prêt, il est qualifié automatiquement."},
        {"q":"Comment sont distribués les gains du tournoi ?","a":"La répartition est affichée dans la description du tournoi avant inscription. Une petite finale départage la 3ᵉ place avant la grande finale."},
        {"q":"Qu'est-ce qu'un BYE ?","a":"Il n'y a pas de qualification automatique : tout joueur inscrit doit disputer au moins un match. Si un groupe est incomplet, l'admin ajuste le format (1v1 ou groupe à 3, avec 1 seul qualifié pour un groupe à 3)."}
      ]
    },
    {
      "category": "👤 Compte & Profil",
      "items": [
        {"q":"Comment changer mon pseudo ou ma photo ?","a":"Dans 'Mon profil', appuyez sur votre avatar pour changer la photo, ou modifiez le pseudo dans le champ dédié et enregistrez."},
        {"q":"Comment parrainer un ami ?","a":"__REFERRAL_SHORT__"},
        {"q":"Mon compte a été suspendu, que faire ?","a":"Contactez le support via le chat ou le numéro admin en expliquant votre situation."}
      ]
    },
    {
      "category": "🛡️ Sécurité & Règles",
      "items": [
        {"q":"Lalao MADA est-il sécurisé ?","a":"Oui. Toutes les communications sont chiffrées (HTTPS) et les opérations sur le solde passent par des fonctions sécurisées côté serveur. Votre solde ne peut être modifié que par des actions légitimes."},
        {"q":"Est-il autorisé d'avoir plusieurs comptes ?","a":"Non. Un seul compte par joueur est autorisé. Les comptes multiples sont bannis et les soldes gelés."},
        {"q":"Où trouver les règles de chaque jeu ?","a":"Les règles sont accessibles depuis la page du jeu concerné, via l'icône d'aide."}
      ]
    }
  ]
}
$seed$::jsonb)
ON CONFLICT (key) DO NOTHING;

-- Seed initial: page Parrainage
INSERT INTO public.cms_content (key, content) VALUES ('referral', $seed$
{
  "hero_subtitle": "Gagnez {pct}% de chaque mise de vos filleuls, sur leurs {max} premières parties payantes.",
  "how_it_works": [
    {"step":"1","icon":"📤","label":"Partagez votre code","desc":"Envoyez votre lien ou votre code à vos amis"},
    {"step":"2","icon":"✍️","label":"L'ami s'inscrit","desc":"Il utilise votre code lors de son inscription"},
    {"step":"3","icon":"🎮","label":"Il joue avec une mise","desc":"Chaque partie payante compte (les parties gratuites sont ignorées)"},
    {"step":"4","icon":"💰","label":"Vous recevez une commission","desc":"{pct}% de sa mise crédités automatiquement, sur ses {max} premières parties payantes"}
  ],
  "conditions": [
    "Aucun bonus à l'inscription ni au dépôt de votre filleul.",
    "Vous recevez {pct}% de la mise de votre filleul sur chacune de ses {max} premières parties payantes.",
    "Les parties gratuites ne comptent pas.",
    "Les commissions sont créditées automatiquement sur votre solde.",
    "Toute tentative de fraude (auto-parrainage, faux comptes) entraîne la suspension immédiate des récompenses.",
    "Lalao MADA se réserve le droit de modifier ou suspendre ce programme à tout moment."
  ]
}
$seed$::jsonb)
ON CONFLICT (key) DO NOTHING;
