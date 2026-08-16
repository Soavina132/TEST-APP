import { createFileRoute, Link, useRouter } from "@tanstack/react-router";
import { useState, FormEvent, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import {
  Mail, Lock, User, Gift, Eye, EyeOff, KeyRound, X, Loader2, CheckCircle2,
  Sparkles, Phone, MessageCircle, ChevronDown, ChevronUp, HelpCircle, ShieldCheck,
} from "lucide-react";
import { Logo } from "@/components/layout/Header";
import { COVER_COMPONENTS, GAME_DEFS } from "@/components/game/GameCovers";
import DOMPurify from "dompurify";

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

async function callEdgeFunction(fnName: string, payload: unknown) {
  const { data: sess } = await supabase.auth.getSession();
  const token = sess.session?.access_token || SUPABASE_ANON_KEY;
  const res = await fetch(`${SUPABASE_URL}/functions/v1/${fnName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
      apikey: SUPABASE_ANON_KEY,
    },
    body: JSON.stringify(payload),
  });
  const json = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(json?.error || "Erreur serveur");
  return json;
}

export const Route = createFileRoute("/login")({
  component: LoginPage,
  validateSearch: (search: Record<string, unknown>) => ({
    ref: (search.ref as string) || undefined,
  }),
  head: () => ({
    meta: [
      { title: "Connexion — Lalao MADA" },
      { name: "description", content: "Connectez-vous ou créez un compte sur Lalao MADA, la plateforme #1 de jeux en ligne à Madagascar." },
      { property: "og:title", content: "Connexion — Lalao MADA" },
      { property: "og:description", content: "Rejoignez Lalao MADA : Ludo, Domino, Fanorona, Échecs, Rami — mises en Ariary." },
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
  const searchParams = Route.useSearch();
  const refFromUrl = searchParams.ref || "";
  const [tab, setTab] = useState<"login" | "signup">(refFromUrl ? "signup" : "login");
  const [identifier, setIdentifier] = useState(
    typeof window !== "undefined" ? localStorage.getItem("lalaomada_remembered_identifier") || "" : ""
  );
  const [pseudo, setPseudo] = useState("");
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [referral, setReferral] = useState(refFromUrl);
  const [showPw, setShowPw] = useState(false);
  const [rememberMe, setRememberMe] = useState(true);
  const [acceptTerms, setAcceptTerms] = useState(false);
  const [acceptAge, setAcceptAge] = useState(false);
  const [showTerms, setShowTerms] = useState(false);
  const [showPrivacy, setShowPrivacy] = useState(false);
  const [termsHtml, setTermsHtml] = useState("");
  const [privacyHtml, setPrivacyHtml] = useState("");
  const [busy, setBusy] = useState(false);
  const [showForgot, setShowForgot] = useState(false);
  const [otpStep, setOtpStep] = useState(false);
  const [otpCode, setOtpCode] = useState("");
  const [otpEmail, setOtpEmail] = useState("");
  const [otpResendIn, setOtpResendIn] = useState(0);
  const [showVerifyEmail, setShowVerifyEmail] = useState(false);
  const [verifyEmailAddr, setVerifyEmailAddr] = useState("");

  // ── 2FA (Google Authenticator) ──
  const [twoFAStep, setTwoFAStep] = useState(false);
  const [authPending, setAuthPending] = useState(false);  // blocks auto-nav during 2FA check
  const [twoFACode, setTwoFACode] = useState("");
  // twoFASecret removed — verification is now server-side
  const [verifying2FA, setVerifying2FA] = useState(false);

  // ── Real-time validation (signup) ──
  const [pseudoStatus, setPseudoStatus] = useState<"idle"|"checking"|"ok"|"taken">("idle");
  const [emailStatus, setEmailStatus] = useState<"idle"|"checking"|"ok"|"taken"|"invalid">("idle");
  const [pwStrength, setPwStrength] = useState<{ len: number; ok: boolean }>({ len: 0, ok: false });
  const [pwMatch, setPwMatch] = useState<"idle"|"match"|"mismatch">("idle");

  // Debounced pseudo check
  useEffect(() => {
    if (tab !== "signup") return;
    const v = pseudo.trim();
    if (v.length < 2) { setPseudoStatus("idle"); return; }
    setPseudoStatus("checking");
    const t = setTimeout(async () => {
      const { count } = await supabase
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .ilike("pseudo", v);
      setPseudoStatus(count && count > 0 ? "taken" : "ok");
    }, 400);
    return () => clearTimeout(t);
  }, [pseudo, tab]);

  // Debounced email check
  useEffect(() => {
    if (tab !== "signup") return;
    const v = identifier.trim();
    if (v.length < 4) { setEmailStatus("idle"); return; }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) { setEmailStatus("invalid"); return; }
    setEmailStatus("checking");
    const t = setTimeout(async () => {
      const { count } = await supabase
        .from("profiles")
        .select("id", { count: "exact", head: true })
        .eq("email", v.toLowerCase());
      setEmailStatus(count && count > 0 ? "taken" : "ok");
    }, 400);
    return () => clearTimeout(t);
  }, [identifier, tab]);

  // Password strength (8 chars min)
  useEffect(() => {
    if (tab !== "signup") return;
    setPwStrength({ len: password.length, ok: password.length >= 8 });
  }, [password, tab]);

  // Password match
  useEffect(() => {
    if (tab !== "signup") return;
    if (!confirmPassword) { setPwMatch("idle"); return; }
    setPwMatch(confirmPassword === password ? "match" : "mismatch");
  }, [confirmPassword, password, tab]);

  useEffect(() => {
    if (otpResendIn <= 0) return;
    const t = setInterval(() => setOtpResendIn((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(t);
  }, [otpResendIn]);

  // Fetch CGU + confidentialité pour affichage inline
  useEffect(() => {
    supabase.from("app_settings").select("terms_html, terms_text, privacy_html").eq("id", 1).maybeSingle().then(({ data }: any) => {
      if (data) {
        setTermsHtml((data.terms_html as string) || (data.terms_text as string) || "");
        setPrivacyHtml((data.privacy_html as string) || "");
      }
    });
  }, []);

  useEffect(() => {
    if (user && !authPending) router.navigate({ to: "/lobby", replace: true });
  }, [user, router, authPending]);




  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (!identifier.trim()) return toast.error("Email requis");
    if (!password) return toast.error("Mot de passe requis");
    if (tab === "signup") {
      if (!pseudo.trim()) return toast.error("Pseudo requis");
      if (password.length < 8) return toast.error("Mot de passe : 8 caractères minimum");
      if (password !== confirmPassword) return toast.error("Les mots de passe ne correspondent pas");
      if (!acceptTerms) return toast.error("Veuillez accepter les conditions d'utilisation");
      if (!acceptAge) return toast.error("Vous devez confirmer avoir au moins 18 ans");
    }

    const email = identifier.trim().toLowerCase();
    setBusy(true);
    try {
      if (tab === "login") {
        setAuthPending(true);  // block auto-nav during 2FA check
        const { error } = await supabase.auth.signInWithPassword({ email, password });
        if (error) {
          // Fallback: ancien compte téléphone converti en faux email
          if (isPhoneLike(identifier)) {
            const phone = normalizePhone(identifier);
            const { data: lookup } = await supabase.rpc("get_email_by_phone" as any, { _phone: phone } as any);
            const legacyEmail = (lookup as string) || phoneToSyntheticEmail(phone);
            const r = await supabase.auth.signInWithPassword({ email: legacyEmail, password });
            if (r.error) throw error;
          } else {
            throw error;
          }
        }

        // ── Check 2FA: if enabled, intercept and ask for TOTP code ──
        const { data: sess } = await supabase.auth.getSession();
        const userId = sess.session?.user?.id;
        if (userId) {
          const { data: has2fa } = await supabase.rpc("check_2fa_status" as any);
          if (has2fa) {
            // Sign out temporarily — user must verify 2FA before gaining access
            await supabase.auth.signOut();
            setTwoFAStep(true);
            setAuthPending(false);  // allow the 2FA form to show (user is null now, so no nav)
            if (rememberMe) localStorage.setItem("lalaomada_remembered_identifier", identifier.trim());
            else localStorage.removeItem("lalaomada_remembered_identifier");
            return; // Don't show success yet
          }
        }

        setAuthPending(false);  // no 2FA — allow auto-nav to lobby
        if (rememberMe) localStorage.setItem("lalaomada_remembered_identifier", identifier.trim());
        else localStorage.removeItem("lalaomada_remembered_identifier");
        toast.success("Bienvenue !");
      } else {
        // Inscription e-mail — confirmation requise par email
        const { data: signUpData, error: signUpErr } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: {
              pseudo: pseudo.trim(),
              referral_code: referral.trim().toUpperCase() || null,
            },
          },
        });
        if (signUpErr) throw signUpErr;

        // Si mailer_autoconfirm est activé, Supabase crée une session immédiatement.
        // On la détruit pour empêcher la connexion automatique — l'utilisateur doit
        // cliquer sur le lien de confirmation dans l'email avant de pouvoir se connecter.
        if (signUpData.session) {
          await supabase.auth.signOut();
        }

        setVerifyEmailAddr(email);
        setShowVerifyEmail(true);
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

  // ── 2FA verification: sign in with credentials, then verify TOTP code ──
  const onVerify2FA = async (e: FormEvent) => {
    e.preventDefault();
    if (twoFACode.length !== 6) return toast.error("Entrez le code à 6 chiffres");
    setVerifying2FA(true);
    try {
      // Step 1: Sign in with credentials to get a session
      const email = identifier.trim().toLowerCase();
      let signInResult = await supabase.auth.signInWithPassword({ email, password });
      if (signInResult.error) {
        // Try phone fallback again
        if (isPhoneLike(identifier)) {
          const phone = normalizePhone(identifier);
          const { data: lookup } = await supabase.rpc("get_email_by_phone" as any, { _phone: phone } as any);
          const legacyEmail = (lookup as string) || phoneToSyntheticEmail(phone);
          signInResult = await supabase.auth.signInWithPassword({ email: legacyEmail, password });
        }
        if (signInResult.error) throw signInResult.error;
      }

      setAuthPending(true);  // block auto-nav while verifying TOTP

      // Step 2: Verify the TOTP code using the edge function
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session) throw new Error("Session invalide");

      const response = await fetch(`${SUPABASE_URL}/functions/v1/verify-totp`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${sessionData.session.access_token}`,
        },
        body: JSON.stringify({ code: twoFACode }),
      });
      const result = await response.json();

      if (!result.valid) {
        // Code is wrong — sign out and show error
        await supabase.auth.signOut();
        setAuthPending(false);  // user is null now, allow staying on 2FA form
        throw new Error("Code 2FA incorrect");
      }

      // Code is valid — user is now fully authenticated
      setAuthPending(false);  // allow auto-nav to lobby
      toast.success("Bienvenue !");
      setTwoFAStep(false);
    } catch (err: any) {
      toast.error(err?.message || "Erreur de connexion");
    } finally {
      setVerifying2FA(false);
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
          {twoFAStep ? (
            <form onSubmit={onVerify2FA} className="space-y-4">
              <div className="text-center space-y-1">
                <div className="mx-auto w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center">
                  <ShieldCheck className="w-6 h-6 text-primary" />
                </div>
                <h2 className="text-lg font-bold">Authentification à 2 facteurs</h2>
                <p className="text-xs text-muted-foreground">
                  Entrez le code à 6 chiffres de votre application Google Authenticator
                </p>
              </div>
              <input
                type="text"
                inputMode="numeric"
                autoComplete="one-time-code"
                maxLength={6}
                value={twoFACode}
                onChange={(e) => setTwoFACode(e.target.value.replace(/\D/g, "").slice(0, 6))}
                placeholder="123456"
                className="w-full text-center text-2xl font-bold tracking-[0.5em] py-3 rounded-xl border border-border bg-background focus:outline-none focus:ring-2 focus:ring-primary"
                autoFocus
              />
              <button
                type="submit"
                disabled={busy || verifying2FA || twoFACode.length !== 6}
                className="w-full py-3 rounded-xl bg-primary text-primary-foreground font-semibold disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {verifying2FA ? <Loader2 className="w-4 h-4 animate-spin" /> : <ShieldCheck className="w-4 h-4" />}
                Vérifier & se connecter
              </button>
              <button
                type="button"
                onClick={() => { setTwoFAStep(false); setTwoFACode(""); setPassword(""); }}
                className="w-full text-xs text-muted-foreground hover:text-foreground"
              >
                ← Annuler
              </button>
            </form>
          ) : otpStep ? (
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
            <div className="relative">
              <Field
                icon={Mail}
                type="text"
                placeholder="Adresse email"
                value={identifier}
                onChange={setIdentifier}
                autoComplete="email"
              />
              {tab === "signup" && emailStatus !== "idle" && (
                <div className="absolute right-3 top-1/2 -translate-y-1/2">
                  {emailStatus === "checking" && <Loader2 className="w-4 h-4 text-muted-foreground animate-spin" />}
                  {emailStatus === "ok" && <CheckCircle2 className="w-4 h-4 text-emerald-500" />}
                  {emailStatus === "taken" && <X className="w-4 h-4 text-destructive" />}
                  {emailStatus === "invalid" && <X className="w-4 h-4 text-amber-500" />}
                </div>
              )}
            </div>
            {tab === "signup" && emailStatus === "taken" && (
              <p className="text-xs text-destructive -mt-2 px-1">Cet email est déjà utilisé</p>
            )}
            {tab === "signup" && emailStatus === "invalid" && (
              <p className="text-xs text-amber-500 -mt-2 px-1">Format invalide (ex: nom@email.com ou +261340000000)</p>
            )}

            {/* Pseudo (signup only) */}
            {tab === "signup" && (
              <div>
                <div className="relative">
                  <Field
                    icon={User}
                    type="text"
                    placeholder="Pseudo"
                    value={pseudo}
                    onChange={setPseudo}
                    autoComplete="nickname"
                  />
                  <div className="absolute right-3 top-1/2 -translate-y-1/2">
                    {pseudoStatus === "checking" && <Loader2 className="w-4 h-4 text-muted-foreground animate-spin" />}
                    {pseudoStatus === "ok" && <CheckCircle2 className="w-4 h-4 text-emerald-500" />}
                    {pseudoStatus === "taken" && <X className="w-4 h-4 text-destructive" />}
                  </div>
                </div>
                {pseudoStatus === "taken" && (
                  <p className="text-xs text-destructive mt-1 px-1">Ce pseudo est déjà pris</p>
                )}
                {pseudoStatus === "ok" && pseudo.trim().length >= 2 && (
                  <p className="text-xs text-emerald-500 mt-1 px-1">Pseudo disponible</p>
                )}
              </div>
            )}

            {/* Password */}
            <div>
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
              {tab === "signup" && password.length > 0 && (
                <div className="mt-1.5 px-1 space-y-1">
                  <div className="flex gap-1">
                    {[0,1,2,3,4,5,6,7].map(i => (
                      <div key={i} className={"h-1 flex-1 rounded-full transition-colors " + (
                        i < pwStrength.len ? (pwStrength.ok ? "bg-emerald-500" : "bg-amber-500") : "bg-muted"
                      )} />
                    ))}
                  </div>
                  <p className={"text-xs " + (pwStrength.ok ? "text-emerald-500" : "text-amber-500")}>
                    {pwStrength.ok ? "Mot de passe valide (8+ caractères)" : `${pwStrength.len}/8 caractères — il faut au moins 8 caractères`}
                  </p>
                </div>
              )}
            </div>

            {/* Confirm password (signup only) */}
            {tab === "signup" && (
              <div>
                <div className="relative">
                  <Field
                    icon={Lock}
                    type={showPw ? "text" : "password"}
                    placeholder="Confirmer le mot de passe"
                    value={confirmPassword}
                    onChange={setConfirmPassword}
                    autoComplete="new-password"
                  />
                  <div className="absolute right-3 top-1/2 -translate-y-1/2">
                    {pwMatch === "match" && <CheckCircle2 className="w-4 h-4 text-emerald-500" />}
                    {pwMatch === "mismatch" && <X className="w-4 h-4 text-destructive" />}
                  </div>
                </div>
                {pwMatch === "mismatch" && (
                  <p className="text-xs text-destructive mt-1 px-1">Les mots de passe ne correspondent pas</p>
                )}
                {pwMatch === "match" && (
                  <p className="text-xs text-emerald-500 mt-1 px-1">Les mots de passe correspondent</p>
                )}
              </div>
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

            {/* CGU + Privacy + +18 (signup only) */}
            {tab === "signup" && (
              <div className="space-y-2">
                {/* Collapsible CGU */}
                <div className="rounded-lg border border-border/60 overflow-hidden">
                  <button
                    type="button"
                    onClick={() => setShowTerms(v => !v)}
                    className="w-full flex items-center justify-between px-3 py-2 text-xs font-semibold text-foreground bg-secondary/40 hover:bg-secondary/60 transition-colors"
                  >
                    <span>Conditions d'utilisation</span>
                    <ChevronDown className={`w-3.5 h-3.5 transition-transform ${showTerms ? "rotate-180" : ""}`} />
                  </button>
                  {showTerms && (
                    <div
                      className="px-3 py-2 text-[11px] text-muted-foreground max-h-32 overflow-y-auto prose prose-xs"
                      dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(termsHtml || "<p>Chargement…</p>") }}
                    />
                  )}
                </div>
                {/* Collapsible Privacy */}
                <div className="rounded-lg border border-border/60 overflow-hidden">
                  <button
                    type="button"
                    onClick={() => setShowPrivacy(v => !v)}
                    className="w-full flex items-center justify-between px-3 py-2 text-xs font-semibold text-foreground bg-secondary/40 hover:bg-secondary/60 transition-colors"
                  >
                    <span>Politique de confidentialité</span>
                    <ChevronDown className={`w-3.5 h-3.5 transition-transform ${showPrivacy ? "rotate-180" : ""}`} />
                  </button>
                  {showPrivacy && (
                    <div
                      className="px-3 py-2 text-[11px] text-muted-foreground max-h-32 overflow-y-auto prose prose-xs"
                      dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(privacyHtml || "<p>Chargement…</p>") }}
                    />
                  )}
                </div>
                {/* Accept terms */}
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
                {/* +18 confirmation */}
                <label className="flex items-start gap-2 text-xs text-muted-foreground cursor-pointer">
                  <input
                    type="checkbox"
                    checked={acceptAge}
                    onChange={e => setAcceptAge(e.target.checked)}
                    className="w-4 h-4 mt-0.5 rounded accent-primary flex-shrink-0"
                  />
                  <span>
                    Je confirme avoir au moins <strong className="text-foreground">18 ans</strong>.
                  </span>
                </label>
              </div>
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

      {showVerifyEmail && (
        <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm"
          onClick={() => { setShowVerifyEmail(false); setTab("login"); }}>
          <div className="bg-card border border-border rounded-2xl shadow-xl max-w-sm w-full p-6 text-center"
            onClick={e => e.stopPropagation()}>
            <div className="mx-auto w-16 h-16 rounded-full bg-primary/15 flex items-center justify-center mb-4">
              <Mail className="w-8 h-8 text-primary" />
            </div>
            <h2 className="text-lg font-bold mb-2">Vérifiez votre email</h2>
            <p className="text-sm text-muted-foreground mb-1">
              Un email de confirmation a été envoyé à
            </p>
            <p className="text-sm font-semibold text-foreground mb-4 break-all">{verifyEmailAddr}</p>
            <div className="bg-secondary/40 rounded-xl p-3 mb-4 text-left">
              <p className="text-xs text-muted-foreground leading-relaxed">
                <span className="font-semibold text-foreground">1.</span> Ouvrez votre boîte de réception<br />
                <span className="font-semibold text-foreground">2.</span> Cherchez l'email de Supabase<br />
                <span className="font-semibold text-foreground">3.</span> Cliquez sur le bouton « Confirm email address »<br />
                <span className="font-semibold text-foreground">4.</span> Revenez ici et connectez-vous
              </p>
            </div>
            <p className="text-[11px] text-amber-500 mb-4">
              Pensez à vérifier vos spams si vous ne recevez rien.
            </p>
            <button
              onClick={() => { setShowVerifyEmail(false); setTab("login"); setIdentifier(verifyEmailAddr); setPassword(""); setConfirmPassword(""); }}
              className="w-full py-3 rounded-xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition"
            >
              Aller à la connexion
            </button>
          </div>
        </div>
      )}
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
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) return toast.error("Email invalide");
    setBusy(true);
    try {
      const { error } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
        redirectTo: `${window.location.origin}/reset-password`,
      });
      if (error) throw error;
      setSent(true);
    } catch (err: any) {
      toast.error(err?.message || "Erreur");
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

        {sent ? (
          <div className="text-center py-4">
            <div className="mx-auto w-14 h-14 rounded-full bg-emerald-500/15 flex items-center justify-center mb-3">
              <Mail className="w-7 h-7 text-emerald-500" />
            </div>
            <h3 className="font-bold text-base mb-2">Email envoyé !</h3>
            <p className="text-sm text-muted-foreground mb-2">
              Un lien de réinitialisation a été envoyé à
            </p>
            <p className="text-sm font-semibold text-foreground mb-4 break-all">{email.trim()}</p>
            <div className="bg-secondary/40 rounded-xl p-3 mb-4 text-left">
              <p className="text-xs text-muted-foreground leading-relaxed">
                <span className="font-semibold text-foreground">1.</span> Ouvrez votre boîte de réception<br />
                <span className="font-semibold text-foreground">2.</span> Cherchez l'email "Reset your password"<br />
                <span className="font-semibold text-foreground">3.</span> Cliquez sur le bouton "Reset password"<br />
                <span className="font-semibold text-foreground">4.</span> Choisissez votre nouveau mot de passe
              </p>
            </div>
            <p className="text-[11px] text-amber-500 mb-4">
              Pensez à vérifier vos spams.
            </p>
            <button onClick={onClose}
              className="w-full py-3 rounded-xl text-white font-bold text-sm"
              style={{ background: "var(--gradient-primary)" }}>
              Fermer
            </button>
          </div>
        ) : (
          <form onSubmit={submit} className="space-y-3">
            <Field
              icon={Mail}
              type="email"
              placeholder="Votre email"
              value={email}
              onChange={setEmail}
            />
            <button type="submit" disabled={busy}
              className="w-full py-3 rounded-xl text-white font-bold text-sm disabled:opacity-60 flex items-center justify-center gap-2"
              style={{ background: "var(--gradient-primary)" }}>
              {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Mail className="w-4 h-4" />}
              {busy ? "Envoi…" : "Envoyer le lien de réinitialisation"}
            </button>
            <p className="text-[11px] text-muted-foreground text-center">
              Un email avec un lien de réinitialisation vous sera envoyé automatiquement.
            </p>
          </form>
        )}
      </div>
    </div>
  );
}
