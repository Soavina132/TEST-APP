/**
 * Source unique de vérité pour les règles du programme de parrainage.
 *
 * Toute page ou composant qui parle du programme (Parrainage, FAQ, méta SEO,
 * emails, notifications) DOIT consommer ce module. Aucun chiffre ni texte
 * de règle ne doit être codé en dur ailleurs — sinon les incohérences
 * reviennent dès qu'un admin change les réglages.
 *
 * Les valeurs par défaut (DEFAULT_*) ne servent qu'en tout dernier recours,
 * quand `app_settings` n'a pas encore renvoyé de valeur. Les vraies valeurs
 * viennent toujours de la base via `get_referral_dashboard`
 * (`settings.stake_commission_pct`, `settings.referral_stake_max`).
 */

// ─────────────────────────────────────────────────────────────────────────────
// Modèle typé
// ─────────────────────────────────────────────────────────────────────────────

/** Pourcentage de commission (0–100), toujours un nombre fini positif. */
export type CommissionPct = number;
/** Nombre maximum de parties payantes du filleul qui rémunèrent le parrain. */
export type MaxStakes = number;

export type ReferralRules = Readonly<{
  /** Ex: 5 pour 5 %. */
  commissionPct: CommissionPct;
  /** Ex: 10 pour les 10 premières parties payantes. */
  maxStakes: MaxStakes;
}>;

export type ReferralHowItWorksStep = Readonly<{
  step: string;
  icon: string;
  /** Peut contenir les jetons `{pct}` et `{max}`. */
  label: string;
  /** Peut contenir les jetons `{pct}` et `{max}`. */
  desc: string;
}>;

// ─────────────────────────────────────────────────────────────────────────────
// Constantes de secours
// ─────────────────────────────────────────────────────────────────────────────

export const DEFAULT_COMMISSION_PCT: CommissionPct = 5;
export const DEFAULT_MAX_STAKES: MaxStakes = 10;

export const DEFAULT_REFERRAL_RULES: ReferralRules = Object.freeze({
  commissionPct: DEFAULT_COMMISSION_PCT,
  maxStakes: DEFAULT_MAX_STAKES,
});

/** Gabarits texte partagés — utilisent les jetons `{pct}` et `{max}`. */
export const REFERRAL_HERO_SUBTITLE_TEMPLATE =
  "25 Ar au 1er dépôt de votre filleul, puis {pct}% de chaque mise sur ses {max} premières parties payantes.";

export const REFERRAL_META_DESCRIPTION_TEMPLATE =
  "Invitez vos amis : 25 Ar au premier dépôt puis {pct}% de leurs mises sur {max} parties payantes.";

// ─────────────────────────────────────────────────────────────────────────────
// Utilitaires
// ─────────────────────────────────────────────────────────────────────────────

/** Normalise un input partiel en règles complètes (défauts appliqués). */
export function resolveReferralRules(input?: Partial<ReferralRules> | null): ReferralRules {
  const pct = Number(input?.commissionPct);
  const max = Number(input?.maxStakes);
  return {
    commissionPct: Number.isFinite(pct) && pct >= 0 ? pct : DEFAULT_COMMISSION_PCT,
    maxStakes: Number.isFinite(max) && max >= 0 ? Math.floor(max) : DEFAULT_MAX_STAKES,
  };
}

/** Remplace `{pct}` / `{max}` dans une chaîne. */
export function fillReferralTokens(template: string, rules?: Partial<ReferralRules>): string {
  const { commissionPct, maxStakes } = resolveReferralRules(rules);
  return template
    .replace(/\{pct\}/g, String(commissionPct))
    .replace(/\{max\}/g, String(maxStakes));
}

// ─────────────────────────────────────────────────────────────────────────────
// Textes générés
// ─────────────────────────────────────────────────────────────────────────────

/** Sous-titre affiché en tête de la page Parrainage. */
export function referralHeroSubtitle(rules?: Partial<ReferralRules>): string {
  return fillReferralTokens(REFERRAL_HERO_SUBTITLE_TEMPLATE, rules);
}

/** Meta description SEO (< 160 caractères). */
export function referralMetaDescription(rules?: Partial<ReferralRules>): string {
  return fillReferralTokens(REFERRAL_META_DESCRIPTION_TEMPLATE, rules);
}

/** Résumé court, utilisé dans la FAQ. */
export function referralShortAnswer(rules?: Partial<ReferralRules>): string {
  const { commissionPct, maxStakes } = resolveReferralRules(rules);
  return (
    `Partagez le lien de l'application et votre code depuis la page 'Parrainage'. ` +
    `Vous recevez 25 Ar au premier dépôt validé de votre filleul, puis ${commissionPct}% de chaque mise ` +
    `sur ses ${maxStakes} premières parties payantes.`
  );
}

/** Puces des conditions officielles, utilisées sur la page Parrainage. */
export function referralConditions(rules?: Partial<ReferralRules>): readonly string[] {
  const { commissionPct, maxStakes } = resolveReferralRules(rules);
  return [
    "25 Ar crédités au parrain lors du premier dépôt validé du filleul.",
    `Vous recevez ${commissionPct}% de la mise de votre filleul sur chacune de ses ${maxStakes} premières parties payantes.`,
    "Les parties gratuites ne comptent pas.",
    "Les commissions sont créditées automatiquement sur votre solde.",
    "Toute tentative de fraude (auto-parrainage, faux comptes) entraîne la suspension immédiate des récompenses.",
    "Lalao MADA se réserve le droit de modifier ou suspendre ce programme à tout moment.",
  ];
}

/** Étapes « Comment ça marche ». */
export function referralHowItWorks(rules?: Partial<ReferralRules>): readonly ReferralHowItWorksStep[] {
  const { commissionPct, maxStakes } = resolveReferralRules(rules);
  return [
    { step: "1", icon: "📲", label: "Partagez le lien de l'app", desc: "Envoyez le lien de téléchargement et votre code de parrainage" },
    { step: "2", icon: "✍️", label: "L'ami s'inscrit", desc: "Il utilise votre code lors de son inscription" },
    { step: "3", icon: "💵", label: "Il fait son 1er dépôt", desc: "Vous recevez 25 Ar dès que son premier dépôt est validé" },
    {
      step: "4",
      icon: "💰",
      label: "Il joue avec une mise",
      desc: `${commissionPct}% de sa mise crédités automatiquement, sur ses ${maxStakes} premières parties payantes`,
    },
  ];
}
