// Validateurs partagés pour les formulaires admin.
// Chaque validateur renvoie null si OK, sinon un message d'erreur clair (FR).

export type Validator = (raw: string) => string | null;

const isEmpty = (v: string) => v == null || String(v).trim() === "";

export const required = (label = "Ce champ"): Validator => (v) =>
  isEmpty(v) ? `${label} est requis.` : null;

export const optional = (v: Validator): Validator => (raw) =>
  isEmpty(raw) ? null : v(raw);

export const number = (opts: { min?: number; max?: number; integer?: boolean; label?: string } = {}): Validator => (raw) => {
  if (isEmpty(raw)) return null;
  const n = Number(raw);
  if (!Number.isFinite(n)) return "Doit être un nombre valide.";
  if (opts.integer && !Number.isInteger(n)) return "Doit être un nombre entier.";
  if (opts.min !== undefined && n < opts.min) return `Doit être ≥ ${opts.min}.`;
  if (opts.max !== undefined && n > opts.max) return `Doit être ≤ ${opts.max}.`;
  return null;
};

export const percent: Validator = number({ min: 0, max: 100 });

// Numéro malgache : +261 XX XX XXX XX ou 03X XX XXX XX (10 chiffres)
export const malagasyPhone: Validator = (raw) => {
  if (isEmpty(raw)) return null;
  const digits = raw.replace(/\s|-|\./g, "");
  if (/^\+261[0-9]{9}$/.test(digits)) return null;
  if (/^0[23][0-9]{8}$/.test(digits)) return null;
  return "Format invalide (ex : +261 34 12 345 67 ou 034 12 345 67).";
};

export const email: Validator = (raw) => {
  if (isEmpty(raw)) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw.trim())
    ? null
    : "Adresse email invalide.";
};

export const url: Validator = (raw) => {
  if (isEmpty(raw)) return null;
  try { new URL(raw.trim()); return null; } catch { return "URL invalide (doit commencer par https://)."; }
};

export const minLen = (n: number): Validator => (raw) =>
  isEmpty(raw) || raw.trim().length >= n ? null : `Minimum ${n} caractères.`;

export const maxLen = (n: number): Validator => (raw) =>
  raw && raw.length > n ? `Maximum ${n} caractères.` : null;

// Combine plusieurs validateurs, renvoie la 1ère erreur.
export const combine = (...vs: Validator[]): Validator => (raw) => {
  for (const v of vs) { const err = v(raw); if (err) return err; }
  return null;
};
