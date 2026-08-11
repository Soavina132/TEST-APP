import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { u as useRouter, L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { L as Logo } from "./Header-C01sWVFL.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { a5 as ShieldCheck, q as LoaderCircle, K as Mail, k as CircleCheck, X, x as User, L as Lock, a6 as EyeOff, a7 as Eye, c as Gift, a8 as KeyRound } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "../_libs/isbot.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "tslib";
import "../_libs/supabase__functions-js.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
import "../_libs/radix-ui__react-alert-dialog.mjs";
import "../_libs/radix-ui__react-context.mjs";
import "../_libs/radix-ui__react-compose-refs.mjs";
import "../_libs/radix-ui__react-dialog.mjs";
import "../_libs/radix-ui__primitive.mjs";
import "../_libs/radix-ui__react-id.mjs";
import "../_libs/@radix-ui/react-use-layout-effect+[...].mjs";
import "../_libs/@radix-ui/react-use-controllable-state+[...].mjs";
import "../_libs/@radix-ui/react-use-effect-event+[...].mjs";
import "../_libs/@radix-ui/react-dismissable-layer+[...].mjs";
import "../_libs/radix-ui__react-primitive.mjs";
import "../_libs/radix-ui__react-slot.mjs";
import "../_libs/@radix-ui/react-use-callback-ref+[...].mjs";
import "../_libs/radix-ui__react-focus-scope.mjs";
import "../_libs/radix-ui__react-portal.mjs";
import "../_libs/radix-ui__react-presence.mjs";
import "../_libs/radix-ui__react-focus-guards.mjs";
import "../_libs/react-remove-scroll.mjs";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/ai-sdk__openai-compatible.mjs";
import "../_libs/ai-sdk__provider.mjs";
import "../_libs/ai-sdk__provider-utils.mjs";
import "../_libs/eventsource-parser.mjs";
import "../_libs/zod.mjs";
import "../_libs/ai.mjs";
import "../_libs/ai-sdk__gateway.mjs";
import "../_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "../_libs/opentelemetry__api.mjs";
import "./WalletButton-BwZT8Njg.mjs";
function isPhoneLike(v) {
  const cleaned = v.trim().replace(/[\s.-]/g, "");
  return /^[+]?\d{7,15}$/.test(cleaned);
}
function normalizePhone(v) {
  let s = v.trim().replace(/[\s.-]/g, "");
  if (/^00261\d+$/.test(s)) s = "+" + s.slice(2);
  else if (/^261\d+$/.test(s)) s = "+" + s;
  else if (/^0\d{9}$/.test(s)) s = "+261" + s.slice(1);
  return s;
}
function phoneToSyntheticEmail(phone) {
  return `phone${normalizePhone(phone).replace(/^\+/, "")}@phone.lalaomada.local`;
}
function LoginPage() {
  const {
    user
  } = useAuth();
  const router = useRouter();
  const [tab, setTab] = reactExports.useState("login");
  const [identifier, setIdentifier] = reactExports.useState(typeof window !== "undefined" ? localStorage.getItem("lalaomada_remembered_identifier") || "" : "");
  const [pseudo, setPseudo] = reactExports.useState("");
  const [password, setPassword] = reactExports.useState("");
  const [confirmPassword, setConfirmPassword] = reactExports.useState("");
  const [referral, setReferral] = reactExports.useState("");
  const [showPw, setShowPw] = reactExports.useState(false);
  const [rememberMe, setRememberMe] = reactExports.useState(true);
  const [acceptTerms, setAcceptTerms] = reactExports.useState(false);
  const [busy, setBusy] = reactExports.useState(false);
  const [showForgot, setShowForgot] = reactExports.useState(false);
  const [otpStep, setOtpStep] = reactExports.useState(false);
  const [otpCode, setOtpCode] = reactExports.useState("");
  const [otpEmail, setOtpEmail] = reactExports.useState("");
  const [otpResendIn, setOtpResendIn] = reactExports.useState(0);
  const [showVerifyEmail, setShowVerifyEmail] = reactExports.useState(false);
  const [verifyEmailAddr, setVerifyEmailAddr] = reactExports.useState("");
  const [twoFAStep, setTwoFAStep] = reactExports.useState(false);
  const [twoFACode, setTwoFACode] = reactExports.useState("");
  const [verifying2FA, setVerifying2FA] = reactExports.useState(false);
  const [pseudoStatus, setPseudoStatus] = reactExports.useState("idle");
  const [emailStatus, setEmailStatus] = reactExports.useState("idle");
  const [pwStrength, setPwStrength] = reactExports.useState({
    len: 0,
    ok: false
  });
  const [pwMatch, setPwMatch] = reactExports.useState("idle");
  reactExports.useEffect(() => {
    if (tab !== "signup") return;
    const v = pseudo.trim();
    if (v.length < 2) {
      setPseudoStatus("idle");
      return;
    }
    setPseudoStatus("checking");
    const t = setTimeout(async () => {
      const {
        count
      } = await supabase.from("profiles").select("id", {
        count: "exact",
        head: true
      }).ilike("pseudo", v);
      setPseudoStatus(count && count > 0 ? "taken" : "ok");
    }, 400);
    return () => clearTimeout(t);
  }, [pseudo, tab]);
  reactExports.useEffect(() => {
    if (tab !== "signup") return;
    const v = identifier.trim();
    if (v.length < 4) {
      setEmailStatus("idle");
      return;
    }
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v)) {
      setEmailStatus("invalid");
      return;
    }
    setEmailStatus("checking");
    const t = setTimeout(async () => {
      const {
        count
      } = await supabase.from("profiles").select("id", {
        count: "exact",
        head: true
      }).eq("email", v.toLowerCase());
      setEmailStatus(count && count > 0 ? "taken" : "ok");
    }, 400);
    return () => clearTimeout(t);
  }, [identifier, tab]);
  reactExports.useEffect(() => {
    if (tab !== "signup") return;
    setPwStrength({
      len: password.length,
      ok: password.length >= 8
    });
  }, [password, tab]);
  reactExports.useEffect(() => {
    if (tab !== "signup") return;
    if (!confirmPassword) {
      setPwMatch("idle");
      return;
    }
    setPwMatch(confirmPassword === password ? "match" : "mismatch");
  }, [confirmPassword, password, tab]);
  reactExports.useEffect(() => {
    if (otpResendIn <= 0) return;
    const t = setInterval(() => setOtpResendIn((s) => Math.max(0, s - 1)), 1e3);
    return () => clearInterval(t);
  }, [otpResendIn]);
  reactExports.useEffect(() => {
    if (user) router.navigate({
      to: "/lobby",
      replace: true
    });
  }, [user, router]);
  const onSubmit = async (e) => {
    e.preventDefault();
    if (!identifier.trim()) return toast.error("Email requis");
    if (!password) return toast.error("Mot de passe requis");
    if (tab === "signup") {
      if (!pseudo.trim()) return toast.error("Pseudo requis");
      if (password.length < 8) return toast.error("Mot de passe : 8 caractères minimum");
      if (password !== confirmPassword) return toast.error("Les mots de passe ne correspondent pas");
      if (!acceptTerms) return toast.error("Veuillez accepter les conditions");
    }
    const email = identifier.trim().toLowerCase();
    setBusy(true);
    try {
      if (tab === "login") {
        const {
          error
        } = await supabase.auth.signInWithPassword({
          email,
          password
        });
        if (error) {
          if (isPhoneLike(identifier)) {
            const phone = normalizePhone(identifier);
            const {
              data: lookup
            } = await supabase.rpc("get_email_by_phone", {
              _phone: phone
            });
            const legacyEmail = lookup || phoneToSyntheticEmail(phone);
            const r = await supabase.auth.signInWithPassword({
              email: legacyEmail,
              password
            });
            if (r.error) throw error;
          } else {
            throw error;
          }
        }
        const {
          data: sess
        } = await supabase.auth.getSession();
        const userId = sess.session?.user?.id;
        if (userId) {
          const {
            data: has2fa
          } = await supabase.rpc("check_2fa_status");
          if (has2fa) {
            await supabase.auth.signOut();
            setTwoFAStep(true);
            if (rememberMe) localStorage.setItem("lalaomada_remembered_identifier", identifier.trim());
            else localStorage.removeItem("lalaomada_remembered_identifier");
            return;
          }
        }
        if (rememberMe) localStorage.setItem("lalaomada_remembered_identifier", identifier.trim());
        else localStorage.removeItem("lalaomada_remembered_identifier");
        toast.success("Bienvenue !");
      } else {
        const {
          error
        } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: {
              pseudo: pseudo.trim(),
              referral_code: referral.trim().toUpperCase() || null
            }
          }
        });
        if (error) throw error;
        setVerifyEmailAddr(email);
        setShowVerifyEmail(true);
      }
    } catch (err) {
      toast.error(err?.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };
  const onVerifyOtp = async (e) => {
    e.preventDefault();
    if (otpCode.length !== 6) return toast.error("Entrez le code à 6 chiffres");
    setBusy(true);
    try {
      const {
        error
      } = await supabase.auth.verifyOtp({
        email: otpEmail,
        token: otpCode,
        type: "email"
      });
      if (error) throw error;
      const {
        error: upErr
      } = await supabase.auth.updateUser({
        password
      });
      if (upErr) throw upErr;
      toast.success("E-mail vérifié — compte créé !");
      setOtpStep(false);
    } catch (err) {
      toast.error(err?.message || "Code invalide ou expiré");
    } finally {
      setBusy(false);
    }
  };
  const onResendOtp = async () => {
    if (otpResendIn > 0 || !otpEmail) return;
    setBusy(true);
    try {
      const {
        error
      } = await supabase.auth.signInWithOtp({
        email: otpEmail,
        options: {
          shouldCreateUser: true
        }
      });
      if (error) throw error;
      setOtpResendIn(60);
      toast.success("Nouveau code envoyé");
    } catch (err) {
      toast.error(err?.message || "Erreur d'envoi");
    } finally {
      setBusy(false);
    }
  };
  const onVerify2FA = async (e) => {
    e.preventDefault();
    if (twoFACode.length !== 6) return toast.error("Entrez le code à 6 chiffres");
    setVerifying2FA(true);
    try {
      const email = identifier.trim().toLowerCase();
      const {
        error
      } = await supabase.auth.signInWithPassword({
        email,
        password
      });
      if (error) {
        if (isPhoneLike(identifier)) {
          const phone = normalizePhone(identifier);
          const {
            data: lookup
          } = await supabase.rpc("get_email_by_phone", {
            _phone: phone
          });
          const legacyEmail = lookup || phoneToSyntheticEmail(phone);
          const r = await supabase.auth.signInWithPassword({
            email: legacyEmail,
            password
          });
          if (r.error) throw error;
        } else {
          throw error;
        }
      }
      toast.success("Bienvenue !");
      setTwoFAStep(false);
    } catch (err) {
      toast.error(err?.message || "Erreur de connexion");
    } finally {
      setVerifying2FA(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-h-[100dvh] bg-background flex items-center justify-center px-4 py-6 sm:py-8", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full max-w-md", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center mb-8", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/", "aria-label": "Accueil", className: "mb-3", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Logo, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-bold text-foreground", children: "Lalao MADA" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground mt-0.5", children: "Jouez. Gagnez. Retirez en Ariary." })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-card border border-border rounded-2xl shadow-sm p-6", children: twoFAStep ? /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit: onVerify2FA, className: "space-y-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center space-y-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-auto w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-6 h-6 text-primary" }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-bold", children: "Authentification à 2 facteurs" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Entrez le code à 6 chiffres de votre application Google Authenticator" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "text", inputMode: "numeric", autoComplete: "one-time-code", maxLength: 6, value: twoFACode, onChange: (e) => setTwoFACode(e.target.value.replace(/\D/g, "").slice(0, 6)), placeholder: "123456", className: "w-full text-center text-2xl font-bold tracking-[0.5em] py-3 rounded-xl border border-border bg-background focus:outline-none focus:ring-2 focus:ring-primary", autoFocus: true }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { type: "submit", disabled: busy || verifying2FA || twoFACode.length !== 6, className: "w-full py-3 rounded-xl bg-primary text-primary-foreground font-semibold disabled:opacity-50 flex items-center justify-center gap-2", children: [
          verifying2FA ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-4 h-4" }),
          "Vérifier & se connecter"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => {
          setTwoFAStep(false);
          setTwoFACode("");
          setPassword("");
        }, className: "w-full text-xs text-muted-foreground hover:text-foreground", children: "← Annuler" })
      ] }) : otpStep ? /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit: onVerifyOtp, className: "space-y-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center space-y-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-auto w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Mail, { className: "w-6 h-6 text-primary" }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-bold", children: "Vérification de l'e-mail" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
            "Un code à 6 chiffres a été envoyé à",
            /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: otpEmail })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "text", inputMode: "numeric", autoComplete: "one-time-code", maxLength: 6, value: otpCode, onChange: (e) => setOtpCode(e.target.value.replace(/\D/g, "").slice(0, 6)), placeholder: "123456", className: "w-full text-center text-2xl font-bold tracking-[0.5em] py-3 rounded-xl border border-border bg-background focus:outline-none focus:ring-2 focus:ring-primary", autoFocus: true }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { type: "submit", disabled: busy || otpCode.length !== 6, className: "w-full py-3 rounded-xl bg-primary text-primary-foreground font-semibold disabled:opacity-50 flex items-center justify-center gap-2", children: [
          busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4" }),
          "Vérifier & créer le compte"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-xs", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => {
            setOtpStep(false);
            setOtpCode("");
          }, className: "text-muted-foreground hover:text-foreground", children: "← Retour" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: onResendOtp, disabled: otpResendIn > 0 || busy, className: "text-primary font-semibold disabled:text-muted-foreground disabled:cursor-not-allowed", children: otpResendIn > 0 ? `Renvoyer (${otpResendIn}s)` : "Renvoyer le code" })
        ] })
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex bg-secondary rounded-xl p-1 mb-6", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => setTab("login"), className: `flex-1 py-2.5 text-sm font-semibold rounded-lg transition-all ${tab === "login" ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"}`, children: "Connexion" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => setTab("signup"), className: `flex-1 py-2.5 text-sm font-semibold rounded-lg transition-all ${tab === "signup" ? "bg-card text-foreground shadow-sm" : "text-muted-foreground"}`, children: "Inscription" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit, className: "space-y-4", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { icon: Mail, type: "text", placeholder: "Adresse email", value: identifier, onChange: setIdentifier, autoComplete: "email" }),
            tab === "signup" && emailStatus !== "idle" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute right-3 top-1/2 -translate-y-1/2", children: [
              emailStatus === "checking" && /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 text-muted-foreground animate-spin" }),
              emailStatus === "ok" && /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4 text-emerald-500" }),
              emailStatus === "taken" && /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4 text-destructive" }),
              emailStatus === "invalid" && /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4 text-amber-500" })
            ] })
          ] }),
          tab === "signup" && emailStatus === "taken" && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-destructive -mt-2 px-1", children: "Cet email est déjà utilisé" }),
          tab === "signup" && emailStatus === "invalid" && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-amber-500 -mt-2 px-1", children: "Format invalide (ex: nom@email.com ou +261340000000)" }),
          tab === "signup" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { icon: User, type: "text", placeholder: "Pseudo", value: pseudo, onChange: setPseudo, autoComplete: "nickname" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute right-3 top-1/2 -translate-y-1/2", children: [
                pseudoStatus === "checking" && /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 text-muted-foreground animate-spin" }),
                pseudoStatus === "ok" && /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4 text-emerald-500" }),
                pseudoStatus === "taken" && /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4 text-destructive" })
              ] })
            ] }),
            pseudoStatus === "taken" && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-destructive mt-1 px-1", children: "Ce pseudo est déjà pris" }),
            pseudoStatus === "ok" && pseudo.trim().length >= 2 && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-emerald-500 mt-1 px-1", children: "Pseudo disponible" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { icon: Lock, type: showPw ? "text" : "password", placeholder: "Mot de passe", value: password, onChange: setPassword, autoComplete: tab === "login" ? "current-password" : "new-password" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => setShowPw((v) => !v), "aria-label": showPw ? "Masquer le mot de passe" : "Afficher le mot de passe", className: "absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground", children: showPw ? /* @__PURE__ */ jsxRuntimeExports.jsx(EyeOff, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-4 h-4" }) })
            ] }),
            tab === "signup" && password.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1.5 px-1 space-y-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1", children: [0, 1, 2, 3, 4, 5, 6, 7].map((i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-1 flex-1 rounded-full transition-colors " + (i < pwStrength.len ? pwStrength.ok ? "bg-emerald-500" : "bg-amber-500" : "bg-muted") }, i)) }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs " + (pwStrength.ok ? "text-emerald-500" : "text-amber-500"), children: pwStrength.ok ? "Mot de passe valide (8+ caractères)" : `${pwStrength.len}/8 caractères — il faut au moins 8 caractères` })
            ] })
          ] }),
          tab === "signup" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { icon: Lock, type: showPw ? "text" : "password", placeholder: "Confirmer le mot de passe", value: confirmPassword, onChange: setConfirmPassword, autoComplete: "new-password" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute right-3 top-1/2 -translate-y-1/2", children: [
                pwMatch === "match" && /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4 text-emerald-500" }),
                pwMatch === "mismatch" && /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4 text-destructive" })
              ] })
            ] }),
            pwMatch === "mismatch" && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-destructive mt-1 px-1", children: "Les mots de passe ne correspondent pas" }),
            pwMatch === "match" && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-emerald-500 mt-1 px-1", children: "Les mots de passe correspondent" })
          ] }),
          tab === "signup" && /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { icon: Gift, type: "text", placeholder: "Code de parrainage (optionnel)", value: referral, onChange: (v) => setReferral(v.toUpperCase()) }),
          tab === "login" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-xs", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "flex items-center gap-2 cursor-pointer text-muted-foreground", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: rememberMe, onChange: (e) => setRememberMe(e.target.checked), className: "w-4 h-4 rounded accent-primary" }),
              "Se souvenir de moi"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => setShowForgot(true), className: "text-primary font-semibold hover:underline", children: "Mot de passe oublié ?" })
          ] }),
          tab === "signup" && /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "flex items-start gap-2 text-xs text-muted-foreground cursor-pointer", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: acceptTerms, onChange: (e) => setAcceptTerms(e.target.checked), className: "w-4 h-4 mt-0.5 rounded accent-primary flex-shrink-0" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
              "J'accepte les",
              " ",
              /* @__PURE__ */ jsxRuntimeExports.jsx("a", { href: "/cgu", target: "_blank", rel: "noreferrer", className: "text-primary hover:underline", children: "conditions d'utilisation" }),
              " ",
              "et la",
              " ",
              /* @__PURE__ */ jsxRuntimeExports.jsx("a", { href: "/confidentialite", target: "_blank", rel: "noreferrer", className: "text-primary hover:underline", children: "politique de confidentialité" }),
              "."
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "submit", disabled: busy, className: "w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all disabled:opacity-60", style: {
            background: "var(--gradient-primary)"
          }, children: busy ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-2 justify-center", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }),
            tab === "login" ? "Connexion…" : "Création…"
          ] }) : tab === "login" ? "Se connecter" : "Créer mon compte" })
        ] })
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-center text-[11px] text-muted-foreground mt-6", children: [
        "© ",
        (/* @__PURE__ */ new Date()).getFullYear(),
        " Lalao MADA · 100% Malagasy 🇲🇬"
      ] })
    ] }),
    showForgot && /* @__PURE__ */ jsxRuntimeExports.jsx(ForgotPasswordModal, { onClose: () => setShowForgot(false) }),
    showVerifyEmail && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-center justify-center p-4 bg-black/60 backdrop-blur-sm", onClick: () => {
      setShowVerifyEmail(false);
      setTab("login");
    }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card border border-border rounded-2xl shadow-xl max-w-sm w-full p-6 text-center", onClick: (e) => e.stopPropagation(), children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-auto w-16 h-16 rounded-full bg-primary/15 flex items-center justify-center mb-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Mail, { className: "w-8 h-8 text-primary" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-bold mb-2", children: "Vérifiez votre email" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground mb-1", children: "Un email de confirmation a été envoyé à" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm font-semibold text-foreground mb-4 break-all", children: verifyEmailAddr }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-secondary/40 rounded-xl p-3 mb-4 text-left", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground leading-relaxed", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "1." }),
        " Ouvrez votre boîte de réception",
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "2." }),
        " Cherchez l'email de Supabase",
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "3." }),
        " Cliquez sur le bouton « Confirm email address »",
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "4." }),
        " Revenez ici et connectez-vous"
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-amber-500 mb-4", children: "Pensez à vérifier vos spams si vous ne recevez rien." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
        setShowVerifyEmail(false);
        setTab("login");
        setIdentifier(verifyEmailAddr);
        setPassword("");
        setConfirmPassword("");
      }, className: "w-full py-3 rounded-xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition", children: "Aller à la connexion" })
    ] }) })
  ] });
}
function Field({
  icon: Icon,
  type,
  placeholder,
  value,
  onChange,
  autoComplete
}) {
  const inputMode = type === "tel" ? "tel" : type === "email" ? "email" : void 0;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type, value, onChange: (e) => onChange(e.target.value), placeholder, autoComplete, inputMode, className: "w-full pl-10 pr-3 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors" })
  ] });
}
function ForgotPasswordModal({
  onClose
}) {
  const [email, setEmail] = reactExports.useState("");
  const [busy, setBusy] = reactExports.useState(false);
  const [sent, setSent] = reactExports.useState(false);
  const submit = async (e) => {
    e.preventDefault();
    if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email.trim())) return toast.error("Email invalide");
    setBusy(true);
    try {
      const {
        error
      } = await supabase.auth.resetPasswordForEmail(email.trim().toLowerCase(), {
        redirectTo: `${window.location.origin}/reset-password`
      });
      if (error) throw error;
      setSent(true);
    } catch (err) {
      toast.error(err?.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-2xl max-w-md w-full p-6 shadow-2xl border border-border", onClick: (e) => e.stopPropagation(), children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-4 h-4 text-primary" }),
        " Mot de passe oublié"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "p-1.5 rounded-full hover:bg-secondary", "aria-label": "Fermer", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
    ] }),
    sent ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center py-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-auto w-14 h-14 rounded-full bg-emerald-500/15 flex items-center justify-center mb-3", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Mail, { className: "w-7 h-7 text-emerald-500" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h3", { className: "font-bold text-base mb-2", children: "Email envoyé !" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground mb-2", children: "Un lien de réinitialisation a été envoyé à" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm font-semibold text-foreground mb-4 break-all", children: email.trim() }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-secondary/40 rounded-xl p-3 mb-4 text-left", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground leading-relaxed", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "1." }),
        " Ouvrez votre boîte de réception",
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "2." }),
        ` Cherchez l'email "Reset your password"`,
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "3." }),
        ' Cliquez sur le bouton "Reset password"',
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-foreground", children: "4." }),
        " Choisissez votre nouveau mot de passe"
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-amber-500 mb-4", children: "Pensez à vérifier vos spams." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "w-full py-3 rounded-xl text-white font-bold text-sm", style: {
        background: "var(--gradient-primary)"
      }, children: "Fermer" })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit: submit, className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { icon: Mail, type: "email", placeholder: "Votre email", value: email, onChange: setEmail }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { type: "submit", disabled: busy, className: "w-full py-3 rounded-xl text-white font-bold text-sm disabled:opacity-60 flex items-center justify-center gap-2", style: {
        background: "var(--gradient-primary)"
      }, children: [
        busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Mail, { className: "w-4 h-4" }),
        busy ? "Envoi…" : "Envoyer le lien de réinitialisation"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground text-center", children: "Un email avec un lien de réinitialisation vous sera envoyé automatiquement." })
    ] })
  ] }) });
}
export {
  LoginPage as component
};
