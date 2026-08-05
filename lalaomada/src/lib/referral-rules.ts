/**
 * Source unique de vérité pour les règles du programme de parrainage V3.
 *
 * Modèle à récompense fixe : 100 Ar par filleul actif.
 * Un filleul est actif quand :
 *   - Son téléphone est vérifié (OTP)
 *   - Il a effectué un dépôt ≥ 500 Ar
 *   - Il a joué ≥ 10 matchs avec une mise ≥ 200 Ar
 *   - Les matchs annulés ou suspects ne comptent pas
 *
 * Paliers d'affichage :
 *   5 filleuls  = 500 Ar
 *  10 filleuls  = 1 000 Ar
 *  20 filleuls  = 2 000 Ar
 *  50 filleuls  = 5 000 Ar
 */

// ─────────────────────────────────────────────────────────────────────────────
// Constantes
// ─────────────────────────────────────────────────────────────────────────────

export const REWARD_PER_ACTIVE_AR = 100;
export const MIN_DEPOSIT_AR = 500;
export const MIN_MATCHES = 10;
export const MIN_STAKE_AR = 200;

export const REFERRAL_TIERS = [
  { count: 5,  reward: 500,  label: "Bronze",   icon: "🥉" },
  { count: 10, reward: 1000, label: "Argent",   icon: "🥈" },
  { count: 20, reward: 2000, label: "Or",       icon: "🥇" },
  { count: 50, reward: 5000, label: "Diamant",  icon: "💎" },
] as const;

// ─────────────────────────────────────────────────────────────────────────────
// Textes
// ─────────────────────────────────────────────────────────────────────────────

export const REFERRAL_HERO_SUBTITLE_TEMPLATE =
  "{reward} Ar pour chaque filleul actif. Invitez vos amis et gagnez ensemble !";

export const REFERRAL_META_DESCRIPTION_TEMPLATE =
  "Invitez vos amis sur Lalao MADA : {reward} Ar pour chaque filleul actif (téléphone vérifié, dépôt ≥ {min_deposit} Ar, 10 matchs avec mise ≥ {min_stake} Ar).";

export function referralHeroSubtitle(): string {
  return REFERRAL_HERO_SUBTITLE_TEMPLATE.replace("{reward}", String(REWARD_PER_ACTIVE_AR));
}

export function referralMetaDescription(): string {
  return REFERRAL_META_DESCRIPTION_TEMPLATE
    .replace("{reward}", String(REWARD_PER_ACTIVE_AR))
    .replace("{min_deposit}", String(MIN_DEPOSIT_AR))
    .replace("{min_stake}", String(MIN_STAKE_AR));
}

export function referralConditions(): readonly string[] {
  return [
    `Le filleul doit vérifier son numéro de téléphone par OTP.`,
    `Le filleul doit effectuer un dépôt minimum de ${MIN_DEPOSIT_AR} Ar.`,
    `Le filleul doit jouer au moins ${MIN_MATCHES} matchs avec une mise réelle (minimum ${MIN_STAKE_AR} Ar par match).`,
    `Les matchs annulés ou suspects ne sont pas comptabilisés.`,
    `La récompense de ${REWARD_PER_ACTIVE_AR} Ar est crédité automatiquement dès que toutes les conditions sont remplies.`,
    `Un numéro de téléphone ne peut être lié qu'à un seul compte.`,
    `L'auto-parrainage est strictement interdit.`,
    `Toute tentative de fraude entraîne la suspension immédiate des récompenses.`,
    `Lalao MADA se réserve le droit de modifier ou suspendre ce programme à tout moment.`,
  ];
}

export type ReferralHowItWorksStep = Readonly<{
  step: string;
  icon: string;
  label: string;
  desc: string;
}>;

export function referralHowItWorks(): readonly ReferralHowItWorksStep[] {
  return [
    { step: "1", icon: "📲", label: "Partagez votre lien", desc: "Envoyez le lien de l'app et votre code de parrainage à vos amis" },
    { step: "2", icon: "✍️", label: "L'ami s'inscrit", desc: "Il utilise votre code lors de son inscription" },
    { step: "3", icon: "📱", label: "Il vérifie son téléphone", desc: "Il confirme son numéro par OTP" },
    { step: "4", icon: "💵", label: "Il dépose ≥ 500 Ar", desc: "Il effectue un premier dépôt d'au moins 500 Ar" },
    { step: "5", icon: "🎮", label: "Il joue 10 matchs", desc: "Il joue 10 matchs avec une mise d'au moins 200 Ar" },
    { step: "6", icon: "💰", label: "Vous gagnez 100 Ar", desc: "Vous recevez 100 Ar automatiquement sur votre solde" },
  ];
}

export function referralShortAnswer(): string {
  return (
    `Partagez le lien de l'application et votre code depuis la page 'Parrainage'. ` +
    `Vous recevez ${REWARD_PER_ACTIVE_AR} Ar dès que votre filleul a vérifié son téléphone, ` +
    `effectué un dépôt ≥ ${MIN_DEPOSIT_AR} Ar et joué ${MIN_MATCHES} matchs avec une mise ≥ ${MIN_STAKE_AR} Ar.`
  );
}

// ── Legacy compat (still imported by some pages) ────────────────────────────
export const DEFAULT_COMMISSION_PCT = 0;
export const DEFAULT_MAX_STAKES = MIN_MATCHES;

export type CommissionPct = number;
export type MaxStakes = number;

export type ReferralRules = Readonly<{
  commissionPct: CommissionPct;
  maxStakes: MaxStakes;
}>;

export const DEFAULT_REFERRAL_RULES: ReferralRules = Object.freeze({
  commissionPct: DEFAULT_COMMISSION_PCT,
  maxStakes: DEFAULT_MAX_STAKES,
});

export function resolveReferralRules(input?: Partial<ReferralRules> | null): ReferralRules {
  return DEFAULT_REFERRAL_RULES;
}

export function fillReferralTokens(template: string, _rules?: Partial<ReferralRules>): string {
  return template
    .replace(/\{reward\}/g, String(REWARD_PER_ACTIVE_AR))
    .replace(/\{min_deposit\}/g, String(MIN_DEPOSIT_AR))
    .replace(/\{min_stake\}/g, String(MIN_STAKE_AR))
    .replace(/\{pct\}/g, "0")
    .replace(/\{max\}/g, String(MIN_MATCHES));
}
