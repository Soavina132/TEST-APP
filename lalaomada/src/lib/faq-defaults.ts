import { referralShortAnswer } from "./referral-rules";
import type { CmsFaqContent } from "@/hooks/use-cms-content";

/**
 * FAQ par défaut. Utilisée comme fallback si `cms_content.faq` est vide.
 * Le marqueur `__REFERRAL_SHORT__` (dans le contenu servi par la base)
 * est remplacé au rendu par le texte partagé avec la page Parrainage.
 */
export const DEFAULT_FAQ: CmsFaqContent = {
  categories: [
    {
      category: "💰 Dépôts & Retraits",
      items: [
        { q: "Comment déposer de l'argent ?", a: "Allez dans 'Mon profil' → 'Dépôt'. Entrez le montant, choisissez votre opérateur Mobile Money (MVola, Orange Money, Airtel Money), puis envoyez le transfert au numéro admin affiché. Votre solde est crédité après validation manuelle par l'admin." },
        { q: "Comment retirer mes gains ?", a: "Dans 'Mon profil' → 'Retrait'. Entrez le montant, votre numéro Mobile Money, et validez. L'admin traite les demandes manuellement ; le solde est débité dès l'acceptation." },
      ],
    },
    {
      category: "👤 Compte & Profil",
      items: [
        { q: "Comment parrainer un ami ?", a: "__REFERRAL_SHORT__" },
      ],
    },
  ],
};

/** Remplace les marqueurs dynamiques dans une réponse FAQ. */
export function resolveFaqAnswer(a: string): string {
  if (a.includes("__REFERRAL_SHORT__")) {
    return a.replace(/__REFERRAL_SHORT__/g, referralShortAnswer());
  }
  return a;
}
