import { referralShortAnswer } from "./referral-rules";
import type { CmsFaqContent } from "@/hooks/use-cms-content";

/**
 * FAQ par défaut. Utilisée comme fallback si `cms_content.faq` est vide.
 * Le marqueur `__REFERRAL_SHORT__` (dans le contenu servi par la base)
 * est remplacé au rendu par le texte partagé avec la page Parrainage.
 */
export const DEFAULT_FAQ: CmsFaqContent = {
  categories: [
    /* ─────────────────────────────────────────── */
    {
      category: "💰 Dépôts & Retraits",
      items: [
        {
          q: "Comment déposer de l'argent ?",
          a: "Allez dans « Mon profil » → « Dépôts ». Entrez le montant, choisissez votre opérateur Mobile Money (MVola, Orange Money, Airtel Money), puis envoyez le transfert au numéro admin affiché. Votre solde est crédité après validation manuelle par l'admin (généralement quelques minutes).",
        },
        {
          q: "Combien de temps prend la validation d'un dépôt ?",
          a: "La validation est manuelle. En général, votre solde est crédité en quelques minutes après l'envoi du Mobile Money. Si votre dépôt n'est pas validé après 1 heure, contactez le support via le chat.",
        },
        {
          q: "Comment retirer mes gains ?",
          a: "Allez dans « Mon profil » → « Retraits ». Entrez le montant, votre numéro Mobile Money, et validez. L'admin traite les demandes manuellement ; le solde est débité dès l'acceptation et le transfert envoyé à votre numéro.",
        },
        {
          q: "Y a-t-il un montant minimum pour déposer ou retirer ?",
          a: "Le montant minimum de dépôt est de 500 Ar. Le montant minimum de retrait est de 1 000 Ar. Il n'y a pas de maximum, mais les gros retraits peuvent nécessiter une vérification supplémentaire.",
        },
        {
          q: "Quels opérateurs Mobile Money sont acceptés ?",
          a: "Nous acceptons MVola, Orange Money et Airtel Money. Assurez-vous d'utiliser un numéro enregistré à votre nom pour éviter les retards de validation.",
        },
        {
          q: "Mon dépôt n'est pas validé, que faire ?",
          a: "Vérifiez d'abord que vous avez bien envoyé le transfert au bon numéro admin. Si tout est correct, contactez le support via le chat en indiquant le montant, l'heure du transfert et la référence Mobile Money. Un admin vérifiera et créditera votre solde.",
        },
      ],
    },

    /* ─────────────────────────────────────────── */
    {
      category: "🎮 Jeux & Matchs",
      items: [
        {
          q: "Quels jeux sont disponibles ?",
          a: "Lalao MADA propose 5 jeux : Ludo, Domino, Fanorona, Rami (jeux de cartes) et Échecs. De nouveaux jeux seront ajoutés régulièrement.",
        },
        {
          q: "Comment créer une partie ?",
          a: "Allez dans la section « Jeux », choisissez le jeu, puis « Nouvelle partie ». Vous pouvez définir la mise (stake) et inviter des joueurs ou ouvrir la partie au public.",
        },
        {
          q: "Comment rejoindre une partie ?",
          a: "Allez dans « Jeux », choisissez un jeu, puis parcourez la liste des parties ouvertes. Touchez une partie pour la rejoindre si elle a de la place et que vous avez suffisamment de solde pour la mise.",
        },
        {
          q: "Que se passe-t-il si je quitte une partie en cours ?",
          a: "Si vous quitte une partie en cours, vous perdez automatiquement votre mise. La partie continue avec les autres joueurs. En cas de déconnexion involontaire (réseau), vous avez un court délai pour vous reconnecter avant d'être éliminé.",
        },
        {
          q: "Puis-je jouer contre des bots ?",
          a: "Oui, le Ludo propose des parties contre des bots. Les autres jeux sont actuellement en joueur contre joueur uniquement.",
        },
        {
          q: "Comment fonctionnent les tournois ?",
          a: "Les tournois sont organisés par l'admin. Consultez la section « Tournois » pour voir les tournois à venir et en cours. Les inscriptions peuvent être limitées selon le nombre de participants et le niveau.",
        },
      ],
    },

    /* ─────────────────────────────────────────── */
    {
      category: "👤 Compte & Profil",
      items: [
        {
          q: "Comment parrainer un ami ?",
          a: "__REFERRAL_SHORT__",
        },
        {
          q: "Comment changer mon pseudo ?",
          a: "Allez sur votre profil, touchez votre pseudo en haut de la page. Vous pouvez le modifier et valider. Le pseudo doit être unique.",
        },
        {
          q: "Comment changer ma photo de profil ?",
          a: "Sur votre profil, touchez l'icône appareil photo en bas à droite de votre avatar. Choisissez une image depuis votre téléphone. Elle est automatiquement compressée et uploadée.",
        },
        {
          q: "Comment vérifier mon numéro de téléphone ?",
          a: "La vérification se fait lors de l'inscription par code OTP (6 chiffres envoyés par SMS). Si vous n'avez pas vérifié votre numéro, le statut « Non vérifié » s'affiche sur votre profil.",
        },
        {
          q: "Comment supprimer mon compte ?",
          a: "Allez sur votre profil → « Sécurité » → « Supprimer ». La suppression est définitive : vous perdez votre solde, votre historique et vos statistiques. Cette action est irréversible.",
        },
        {
          q: "Que signifient les badges (Bronze, Or, Diamant…) ?",
          a: "Les badges représentent votre niveau de joueur. Ils sont basés sur votre niveau (déterminé par vos parties et victoires). Bronze (niveau 1), Argent (2), Or (3), Diamant (4), Platine (5+).",
        },
        {
          q: "C'est quoi la série quotidienne (streak) ?",
          a: "La série quotidienne (flame 🔥) compte le nombre de jours consécutifs où vous êtes actif sur l'app. Jouez au moins une partie par jour pour maintenir votre série !",
        },
      ],
    },

    /* ─────────────────────────────────────────── */
    {
      category: "🏆 Classement & Succès",
      items: [
        {
          q: "Comment fonctionne le classement ?",
          a: "Le classement est basé sur le nombre total de victoires. Plus vous gagnez, plus vous montez. Consultez la section « Classement » pour voir votre rang et les meilleurs joueurs.",
        },
        {
          q: "Comment débloquer des succès ?",
          a: "Les succès se débloquent automatiquement : 🏎️ 1er dépôt (effectuer un premier dépôt), 🔥 10 victoires (remporter 10 matchs), 👑 100 parties (jouer 100 matchs), ⭐ Parrain (parrainer un ami actif). D'autres succès seront ajoutés.",
        },
        {
          q: "Où voir mes statistiques de jeu ?",
          a: "Sur votre profil, la section « Stats » affiche votre nombre de parties, victoires, défaites, taux de victoire et votre rang. La section « Jeux favoris » montre combien de parties vous avez joué pour chaque jeu.",
        },
      ],
    },

    /* ─────────────────────────────────────────── */
    {
      category: "🔒 Sécurité & Rèles",
      items: [
        {
          q: "Mes données sont-elles en sécurité ?",
          a: "Vos données sont stockées de manière sécurisée. Votre numéro de téléphone n'est visible que par vous et l'admin. Vos transactions sont privées. Nous ne partageons jamais vos informations avec des tiers.",
        },
        {
          q: "Puis-je avoir plusieurs comptes ?",
          a: "Non. Un numéro de téléphone ne peut être lié qu'à un seul compte. Toute tentative de créer plusieurs comptes entraîne la suspension de tous les comptes associés.",
        },
        {
          q: "Que se passe-t-il en cas de triche ou de fraude ?",
          a: "Toute triche, exploitation de bugs, ou fraude (y compris l'auto-parrainage) entraîne la suspension immédiate du compte et la confiscation des gains. Les matchs suspects sont annulés et les mises remboursées aux joueurs légitimes.",
        },
        {
          q: "Que faire si quelqu'un triche dans une partie ?",
          a: "Signalez-le immédiatement au support via le chat avec le maximum de détails (jeu, adversaire, description du problème). Notre équipe vérifiera et prendra les mesures nécessaires.",
        },
        {
          q: "Comment sont calculées les mises ?",
          a: "Chaque partie a une mise fixée par le créateur. Les gagnants reçoivent les mises des perdants (déduction faite des frais éventuels). Le solde est mis à jour automatiquement à la fin de la partie.",
        },
        {
          q: "L'application est-elle gratuite ?",
          a: "L'inscription et la navigation sont gratuites. Vous jouez avec votre solde (alimenté par dépôts Mobile Money ou récompenses de parrainage). Aucun abonnement n'est requis.",
        },
      ],
    },

    /* ─────────────────────────────────────────── */
    {
      category: "💬 Chat & Support",
      items: [
        {
          q: "Comment contacter le support ?",
          a: "Touchez le bouton de contact flottant (en bas à droite) pour accéder au WhatsApp, Facebook, email et téléphone admin. Vous pouvez aussi ouvrir le chat intégré depuis le menu.",
        },
        {
          q: "Comment signaler un bug ?",
          a: "Utilisez le bouton « Signaler un bug » (icône insecte 🐛) disponible dans l'app. Décrivez le problème avec le maximum de détails pour aider notre équipe à le corriger rapidement.",
        },
        {
          q: "Où trouver les tutoriels ?",
          a: "Allez dans la section « Tutoriels » du menu. Des guides sont disponibles pour chaque jeu (Ludo, Domino, Fanorona, Rami, Échecs) pour apprendre les règles et stratégies.",
        },
        {
          q: "Comment changer la langue de l'application ?",
          a: "Allez sur votre profil → « Paramètres ». Vous pouvez choisir entre Français 🇫🇷, Malagasy 🇲🇬 et English 🇬🇧.",
        },
        {
          q: "Comment changer le thème (clair/sombre) ?",
          a: "Allez sur votre profil → « Paramètres ». Touchez le toggle pour passer du mode clair au mode sombre et inversement.",
        },
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
