import { useCallback, useEffect, useId, useMemo, useRef, useState } from "react";
import type { Validator } from "@/lib/admin-validators";

type Props = {
  label: string;
  value: string | number | null | undefined;
  onChange: (v: string) => void;
  type?: string;
  hint?: string;
  min?: number;
  max?: number;
  placeholder?: string;
  validate?: Validator;
  /** Signale l'erreur au parent (message ou null). Appelé à chaque changement de statut. */
  onValidityChange?: (error: string | null) => void;
  /** Style : "pill" (arrondi cf. SettingsForm) ou "soft" (cf. AppConfigForm) */
  variant?: "pill" | "soft";
  className?: string;
};

/**
 * Champ contrôlé avec validation en temps réel.
 * L'erreur s'affiche dès que l'utilisateur touche le champ (blur ou saisie après 1er blur).
 */
export function ValidatedField({
  label, value, onChange, type = "text", hint, min, max, placeholder,
  validate, onValidityChange, variant = "soft", className,
}: Props) {
  const id = useId();
  const [touched, setTouched] = useState(false);
  const raw = value == null ? "" : String(value);
  const error = validate ? validate(raw) : null;

  // Keep the latest callback in a ref so effect deps don't include it
  // (parents often pass a new function on every render).
  const cbRef = useRef(onValidityChange);
  useEffect(() => { cbRef.current = onValidityChange; });
  useEffect(() => { cbRef.current?.(error); }, [error]);

  const showError = touched && error;
  const base = variant === "pill"
    ? "w-full px-4 py-3 rounded-full bg-card border shadow-inner outline-none"
    : "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm border";
  const borderCls = showError
    ? "border-destructive focus:ring-2 focus:ring-destructive/30"
    : "border-border focus:ring-2 focus:ring-primary/30";

  return (
    <label htmlFor={id} className={`block ${className ?? ""}`}>
      <div className={variant === "pill" ? "text-sm font-semibold mb-1" : "text-xs font-semibold mb-1"}>{label}</div>
      {hint && !showError && (
        <div className="text-[10px] text-muted-foreground mb-1">{hint}</div>
      )}
      <input
        id={id}
        type={type}
        value={raw}
        min={min}
        max={max}
        placeholder={placeholder}
        onChange={(e) => { onChange(e.target.value); if (!touched) setTouched(true); }}
        onBlur={() => setTouched(true)}
        aria-invalid={!!showError}
        aria-describedby={showError ? `${id}-err` : undefined}
        className={`${base} ${borderCls} transition-colors`}
      />
      {showError && (
        <div id={`${id}-err`} role="alert" className="mt-1 text-[11px] font-medium text-destructive flex items-center gap-1">
          <span aria-hidden>⚠️</span>{error}
        </div>
      )}
    </label>
  );
}

/** Hook utilitaire pour agréger les erreurs d'un formulaire. */
export function useFormErrors() {
  const [errors, setErrors] = useState<Record<string, string | null>>({});
  // Cache stable des callbacks par clé pour éviter les nouvelles refs à chaque render
  // (source d'une boucle infinie quand ValidatedField les met en deps d'un useEffect).
  const cache = useRef<Record<string, (err: string | null) => void>>({});
  const setError = useCallback((key: string) => {
    if (!cache.current[key]) {
      cache.current[key] = (err: string | null) =>
        setErrors((prev) => (prev[key] === err ? prev : { ...prev, [key]: err }));
    }
    return cache.current[key];
  }, []);
  const hasErrors = useMemo(() => Object.values(errors).some(Boolean), [errors]);
  const firstError = useMemo(() => Object.values(errors).find(Boolean) || null, [errors]);
  return { errors, setError, hasErrors, firstError };
}
