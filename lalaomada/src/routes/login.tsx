import { createFileRoute, Link, useRouter } from "@tanstack/react-router";
import { useState, FormEvent, useEffect } from "react";
import { useServerFn } from "@tanstack/react-start";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import {
  Mail, Lock, User, Gift, Eye, EyeOff, KeyRound, X, Loader2, CheckCircle2,
  Sparkles, Phone, MessageCircle, ChevronDown, ChevronUp, HelpCircle,
} from "lucide-react";
import { Logo } from "@/components/Header";
import { completePasswordReset } from "@/lib/password-reset.functions";
import { signupWithPhone } from "@/lib/signup.functions";
import { COVER_COMPONENTS, GAME_DEFS } from "@/components/GameCovers";
import DOMPurify from "dompurify";

export const Route = createFileRoute("/login")({
  component: LoginPage,
  head: () => ({
    meta: [
      { title: "Connexion — Lalao MADA" },
      { name: "description", content: "Connectez-vous ou créez un compte sur Lalao MADA, la plateforme #1 de jeux en ligne à Madagascar." },
      { property: "og:title", content: "Connexion — Lalao MADA" },
      { property: "og:description", content: "Rejoignez Lalao MADA : Ludo, Domino, Fanorona, Échecs, Poker, Rami — mises en Ariary." },
    ],
  }),
});

// ── Helpers ─────────────────────────────────────────────────────────────────
function isPhoneLike(v: string) {
  const cleaned = v.trim().replace(/[\s.-]/g, "");
  return /^[+]?\d{7,15}$/.test(cleaned);
}
function normalizePhone(v: string) {
  let s = v.trim().replace(/[\s.-]/g, "");
  if (/^00261\d+$/.test(s)) s = "+" + s.slice(2);
  else if (/^261\d+$/.test(s)) s = "+" + s;
  else if (/^0\d{9}$/.test(s)) s = "+261" + s.slice(1);
  return s;
}
function isValidMgPhone(v: string) {
  // Doit commencer par +261 suivi de 9 chiffres (format Madagascar)
  return /^\+261\d{9}$/.test(normalizePhone(v));
}
function phoneToSyntheticEmail(phone: string) {
  return `phone${normalizePhone(phone).replace(/^\+/, "")}@phone.lalaomada.local`;
}

// ── Page ────────────────────────────────────────────────────────────────────
function LoginPage() {
  const { user } = useAuth();
  const router = useRouter();
  const [tab, setTab] = useState<"login" | "signup">("login");
  const [identifier, setIdentifier] = useState(
    typeof window !== "undefined" ? localStorage.getItem("lalaomada_remembered_identifier") || "" : ""
  );
  const [pseudo, setPseudo] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [referral, setReferral] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [rememberMe, setRememberMe] = useState(true);
  const [acceptTerms, setAcceptTerms] = useState(false);
  const [busy, setBusy] = useState(false);
  const doPhoneSignup = useServerFn(signupWithPhone);
  const [showForgot, setShowForgot] = useState(false);
  const [otpStep, setOtpStep] = useState(false);
  const [otpCode, setOtpCode] = useState("");
  const [otpEmail, setOtpEmail] = useState("");
  const [otpResendIn, setOtpResendIn] = useState(0);

  useEffect(() => {
    if (otpResendIn <= 0) return;
    const t = setInterval(() => setOtpResendIn((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(t);
  }, [otpResendIn]);

  useEffect(() => {
    if (user) router.navigate({ to: "/lobby", replace: true });
  }, [user, router]);


  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!identifier.trim()) return toast.error("Identifiant requis");
    if (!password) return toast.error("Mot de passe requis");
    if (tab === "signup") {
      if (!pseudo.trim()) return toast.error("Pseudo requis");
      if (password.length < 6) return toast.error("Mot de passe : 6 caractères minimum");
      if (password !== confirmPassword) return toast.error("Les mots de passe ne correspondent pas");
      if (!acceptTerms) return toast.error("Veuillez accepter les conditions");
    }

    setBusy(true);
    try {
      const isPhone = isPhoneLike(identifier);
      let email = identifier.trim();
      let phone: string | null = null;

      if (isPhone) {
        if (!isValidMgPhone(identifier)) {
          setBusy(false);
          return toast.error("Le numéro doit commencer par +261 et contenir 9 chiffres après (ex : +261340000000)");
        }
        phone = normalizePhone(identifier);
      }

      if (tab === "login") {
        if (isPhone) {
          let { error } = await supabase.auth.signInWithPassword({ phone: phone!, password });
          if (error) {
            // Compte ancien (créé avec faux e-mail téléphone) : fallback
            const { data: lookup } = await supabase.rpc("get_email_by_phone" as any, { _phone: phone } as any);
            const legacyEmail = (lookup as string) || phoneToSyntheticEmail(phone!);
            const r = await supabase.auth.signInWithPassword({ email: legacyEmail, password });
            if (r.error) throw error;
          }
        } else {
          const { error } = await supabase.auth.signInWithPassword({ email, password });
          if (error) throw error;
        }
        if (rememberMe) localStorage.setItem("lalaomada_remembered_identifier", identifier.trim());
        else localStorage.removeItem("lalaomada_remembered_identifier");
        toast.success("Bienvenue !");
      } else {
        if (isPhone) {
          // Inscription téléphone directe (sans OTP, sans faux e-mail)
          const signup = doPhoneSignup;
          await signup({
            data: {
              phone: phone!,
              password,
              pseudo: pseudo.trim(),
              referral_code: referral.trim().toUpperCase() || null,
            },
          } as any);
          const { error: sErr } = await supabase.auth.signInWithPassword({ phone: phone!, password });
          if (sErr) throw sErr;
          toast.success("Compte créé !");
        } else {
          // Inscription e-mail directe (sans vérification OTP)
          const { error } = await supabase.auth.signUp({
            email,
            password,
            options: {
              data: {
                pseudo: pseudo.trim(),
                referral_code: referral.trim().toUpperCase() || null,
              },
            },
          });
          if (error) throw error;
          // Connexion immédiate (auto-confirm activé côté serveur)
          const { error: sErr } = await supabase.auth.signInWithPassword({ email, password });
          if (sErr) throw sErr;
          toast.success("Compte créé !");
        }
      }
    } catch (err: any) {
      toast.error(err?.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const onVerifyOtp = async (e: FormEvent) => {
    e.preventDefault();
    if (otpCode.length !== 6) return toast.error("Entrez le code à 6 chiffres");
    setBusy(true);
    try {
      const { error } = await supabase.auth.verifyOtp({
        email: otpEmail,
        token: otpCode,
        type: "email",
      });
      if (error) throw error;
      // Set the password now that the email is verified
      const { error: upErr } = await supabase.auth.updateUser({ password });
      if (upErr) throw upErr;
      toast.success("E-mail vérifié — compte créé !");
      setOtpStep(false);
    } catch (err: any) {
      toast.error(err?.message || "Code invalide ou expiré");
    } finally {
      setBusy(false);
    }
  };

  const onResendOtp = async () => {
    if (otpResendIn > 0 || !otpEmail) return;
    setBusy(true);
    try {
      const { error } = await supabase.auth.signInWithOtp({
        email: otpEmail,
        options: { shouldCreateUser: true },
      });
      if (error) throw error;
      setOtpResendIn(60);
      toast.success("Nouveau code envoyé");
    } catch (err: any) {
      toast.error(err?.message || "Erreur d'envoi");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="min-h-[100dvh] bg-background flex items-center justify-center px-4 py-6 sm:py-8">
      <div className="w-full max-w-md">

        {/* Logo */}
        <div className="flex flex-col items-center mb-8">
          <Link to="/" aria-label="Accueil" className="mb-3">
            <Logo />
          </Link>
          <h1 className="text-xl font-bold text-foreground">Lalao MADA</h1>
          <p className="text-xs text-muted-foreground mt-0.5">
            Jouez. Gagnez. Retirez en Ariary.
          </p>
        </div>

        {/* Card */}
        <div className="bg-card border border-border rounded-2xl shadow-sm p-6">
          {otpStep ? (
            <form onSubmit={onVerifyOtp} className="space-y-4">
              <div className="text-center space-y-1">
                <div className="mx-auto w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                  <Mail className="w-6 h-6 text-primary" />
                </div>
                <h2 className="text-lg font-bold">Vérification de l'e-mail</h2>
                <p className="text-xs text-muted-foreground">
                  Un code à 6 chiffres a été envoyé à<br /><span className="font-semibold text-foreground">{otpEmail}</span>
                </p>
              </div>
              <input
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                value={otpCode}
                onChange={(e) => setOtpCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                placeholder="123456"
                className="w-full text-center text-2xl font-bold tracking-[0.5em] py-3 rounded-xl border border-border bg-background focus:outline-none focus:ring-2 focus:ring-primary"
                autoFocus
              />
              <button
                type="submit"
                disabled={busy || otpCode.length !== 6}
                className="w-full py-3 rounded-xl bg-primary text-primary-foreground font-semibold disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
                Vérifier & créer le compte
              </button>
              <div className="flex items-center justify-between text-xs">
                <button type="button" onClick={() => { setOtpStep(false); setOtpCode(""); }} className="text-muted-foreground hover:text-foreground">
                  ← Retour
                </button>
                <button
                  type="button"
                  onClick={onResendOtp}
                  disabled={otpResendIn > 0 || busy}
                  className="text-primary font-semibold disabled:text-muted-foreground disabled:cursor-not-allowed"
                >
                  {otpResendIn > 0 ? `Renvoyer (${otpResendIn}s)` : "Renvoyer le code"}
                </button>
              </div>
            </form>
          ) : (
          <>

          <div className="flex bg-secondary rounded-xl p-1 mb-6">
            <button
              type="button"
              onClick={() => setTab("login")}
              className={`flex-1 py-2.5 text-sm font-semibold rounded-lg transition-all ${
                tab === "login" ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"
              }`}
            >
              Connexion
            </button>
            <button
              type="button"
              onClick={() => setTab("signup")}
              className={`flex-1 py-2.5 text-sm font-semibold rounded-lg transition-all ${
                tab === "signup" ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"
              }`}
            >
              Inscription
            </button>
          </div>

          <form onSubmit={onSubmit} className="space-y-4">
            {/* Identifiant */}
            <Field
              icon={Mail}
              type="text"
              placeholder="Email ou numéro"
              value={identifier}
              onChange={setIdentifier}
              autoComplete={tab === "login" ? "username" : "email"}
            />

            {/* Pseudo (signup only) */}
            {tab === "signup" && (
              <Field
                icon={User}
                type="text"
                placeholder="Pseudo"
                value={pseudo}
                onChange={setPseudo}
                autoComplete="nickname"
              />
            )}

            {/* Password */}
            <div className="relative">
              <Field
                icon={Lock}
                type={showPw ? "text" : "password"}
                placeholder="Mot de passe"
                value={password}
                onChange={setPassword}
                autoComplete={tab === "login" ? "current-password" : "new-password"}
              />
              <button
                type="button"
                onClick={() => setShowPw(v => !v)}
                aria-label={showPw ? "Masquer le mot de passe" : "Afficher le mot de passe"}
                className="absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground"
              >
                {showPw ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>

            {/* Confirm password (signup only) */}
            {tab === "signup" && (
              <Field
                icon={Lock}
                type={showPw ? "text" : "password"}
                placeholder="Confirmer le mot de passe"
                value={confirmPassword}
                onChange={setConfirmPassword}
                autoComplete="new-password"
              />
            )}

            {/* Referral (signup only, optional) */}
            {tab === "signup" && (
              <Field
                icon={Gift}
                type="text"
                placeholder="Code de parrainage (optionnel)"
                value={referral}
                onChange={v => setReferral(v.toUpperCase())}
              />
            )}

            {/* Remember me / Forgot */}
            {tab === "login" && (
              <div className="flex items-center justify-between text-xs">
                <label className="flex items-center gap-2 cursor-pointer text-muted-foreground">
                  <input
                    type="checkbox"
                    checked={rememberMe}
                    onChange={e => setRememberMe(e.target.checked)}
                    className="w-4 h-4 rounded accent-primary"
                  />
                  Se souvenir de moi
                </label>
                <button
                  type="button"
                  onClick={() => setShowForgot(true)}
                  className="text-primary font-semibold hover:underline"
                >
                  Mot de passe oublié ?
                </button>
              </div>
            )}

            {/* Terms (signup only) */}
            {tab === "signup" && (
              <label className="flex items-start gap-2 text-xs text-muted-foreground cursor-pointer">
                <input
                  type="checkbox"
                  checked={acceptTerms}
                  onChange={e => setAcceptTerms(e.target.checked)}
                  className="w-4 h-4 mt-0.5 rounded accent-primary flex-shrink-0"
                />
                <span>
                  J'accepte les{" "}
                  <a href="/cgu" target="_blank" rel="noreferrer" className="text-primary hover:underline">
                    conditions d'utilisation
                  </a>{" "}
                  et la{" "}
                  <a href="/confidentialite" target="_blank" rel="noreferrer" className="text-primary hover:underline">
                    politique de confidentialité
                  </a>
                  .
                </span>
              </label>
            )}

            {/* Submit */}
            <button
              type="submit"
              disabled={busy}
              className="w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all disabled:opacity-60"
              style={{ background: "var(--gradient-primary)" }}
            >
              {busy ? (
                <span className="inline-flex items-center gap-2 justify-center">
                  <Loader2 className="w-4 h-4 animate-spin" />
                  {tab === "login" ? "Connexion…" : "Création…"}
                </span>
              ) : tab === "login" ? "Se connecter" : "Créer mon compte"}
            </button>
          </form>
          </>
          )}
        </div>

        {/* Footer */}
        <p className="text-center text-[11px] text-muted-foreground mt-6">
          © {new Date().getFullYear()} Lalao MADA · 100% Malagasy 🇲🇬
        </p>
      </div>

      {showForgot && <ForgotPasswordModal onClose={() => setShowForgot(false)} />}
    </div>
  );
}

// ── Reusable field ──────────────────────────────────────────────────────────
function Field({
  icon: Icon, type, placeholder, value, onChange, autoComplete,
}: {
  icon: any; type: string; placeholder: string; value: string;
  onChange: (v: string) => void; autoComplete?: string;
}) {
  const inputMode =
    type === "tel" ? "tel" : type === "email" ? "email" : undefined;
  return (
    <div className="relative">
      <Icon className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" />
      <input
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        autoComplete={autoComplete}
        inputMode={inputMode as any}
        className="w-full pl-10 pr-3 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors"
      />
    </div>
  );
}


// ── Forgot password modal ───────────────────────────────────────────────────
function ForgotPasswordModal({ onClose }: { onClose: () => void }) {
  const [step, setStep] = useState<"request" | "code" | "done">("request");
  const [type, setType] = useState<"email" | "phone">("phone");
  const [contact, setContact] = useState("");
  const [code, setCode] = useState("");
  const [pw1, setPw1] = useState("");
  const [pw2, setPw2] = useState("");
  const [busy, setBusy] = useState(false);
  const finishReset = useServerFn(completePasswordReset);

  const normContact = () =>
    type === "phone" ? normalizePhone(contact) : contact.trim().toLowerCase();

  const submitRequest = async (e: FormEvent) => {
    e.preventDefault();
    if (contact.trim().length < 3) return toast.error("Contact invalide");
    if (type === "phone" && !isValidMgPhone(contact)) {
      return toast.error("Le numéro doit commencer par +261 et contenir 9 chiffres après (ex : +261340000000)");
    }
    setBusy(true);
    const { error } = await supabase.rpc("request_password_reset" as any, {
      _contact: normContact(), _type: type,
    } as any);
    setBusy(false);
    if (error) return toast.error(error.message);
    setStep("code");
    toast.success("Demande envoyée. Contactez l'administrateur pour recevoir votre code.");
  };

  const submitNewPassword = async (e: FormEvent) => {
    e.preventDefault();
    if (pw1.length < 6) return toast.error("Mot de passe trop court");
    if (pw1 !== pw2) return toast.error("Les mots de passe ne correspondent pas");
    if (!/^\d{4,8}$/.test(code)) return toast.error("Code invalide");
    setBusy(true);
    try {
      await finishReset({ data: { contact: normContact(), contactType: type, code, newPassword: pw1 } });
      setStep("done");
    } catch (err: any) {
      toast.error(err?.message || "Échec de la réinitialisation");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onClick={onClose}>
      <div className="bg-card rounded-2xl max-w-md w-full p-6 shadow-2xl border border-border" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <div className="font-bold flex items-center gap-2">
            <KeyRound className="w-4 h-4 text-primary" /> Mot de passe oublié
          </div>
          <button onClick={onClose} className="p-1.5 rounded-full hover:bg-secondary" aria-label="Fermer">
            <X className="w-4 h-4" />
          </button>
        </div>

        {step === "request" && (
          <form onSubmit={submitRequest} className="space-y-3">
            <div className="flex bg-secondary rounded-lg p-0.5 text-xs">
              <button type="button" onClick={() => setType("phone")}
                className={`flex-1 py-2 rounded ${type === "phone" ? "bg-card font-semibold" : "text-muted-foreground"}`}>
                Téléphone
              </button>
              <button type="button" onClick={() => setType("email")}
                className={`flex-1 py-2 rounded ${type === "email" ? "bg-card font-semibold" : "text-muted-foreground"}`}>
                Email
              </button>
            </div>
            <Field
              icon={type === "phone" ? User : Mail}
              type={type === "phone" ? "tel" : "email"}
              placeholder={type === "phone" ? "Votre numéro" : "Votre email"}
              value={contact}
              onChange={setContact}
            />
            <button type="submit" disabled={busy}
              className="w-full py-3 rounded-xl text-white font-bold text-sm disabled:opacity-60"
              style={{ background: "var(--gradient-primary)" }}>
              {busy ? "Envoi…" : "Demander un code"}
            </button>
            <p className="text-[11px] text-muted-foreground text-center">
              Un administrateur vous transmettra le code par WhatsApp/SMS.
            </p>
          </form>
        )}

        {step === "code" && (
          <form onSubmit={submitNewPassword} className="space-y-3">
            <Field icon={KeyRound} type="text" placeholder="Code reçu" value={code} onChange={setCode} />
            <Field icon={Lock} type="password" placeholder="Nouveau mot de passe" value={pw1} onChange={setPw1} />
            <Field icon={Lock} type="password" placeholder="Confirmer" value={pw2} onChange={setPw2} />
            <button type="submit" disabled={busy}
              className="w-full py-3 rounded-xl text-white font-bold text-sm disabled:opacity-60"
              style={{ background: "var(--gradient-primary)" }}>
              {busy ? "Enregistrement…" : "Valider"}
            </button>
          </form>
        )}

        {step === "done" && (
          <div className="text-center py-4">
            <CheckCircle2 className="w-12 h-12 text-emerald-500 mx-auto mb-3" />
            <p className="font-semibold mb-4">Mot de passe réinitialisé</p>
            <button onClick={onClose}
              className="w-full py-3 rounded-xl text-white font-bold text-sm"
              style={{ background: "var(--gradient-primary)" }}>
              Se connecter
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
