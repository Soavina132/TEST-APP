import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { P as PhoneVerifyPopup } from "./PhoneVerifyPopup-CibtDuiJ.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { d, I, T } from "../_libs/otplib.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { A as ArrowLeft, P as Phone, a5 as ShieldCheck, q as LoaderCircle, l as Clock, a1 as Check, L as Lock, a6 as EyeOff, a7 as Eye, a8 as KeyRound, X } from "../_libs/lucide-react.mjs";
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
import "tslib";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "../_libs/supabase__functions-js.mjs";
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
import "../_libs/otplib__core.mjs";
import "../_libs/otplib__hotp.mjs";
import "../_libs/otplib__totp.mjs";
import "../_libs/otplib__uri.mjs";
import "../_libs/otplib__plugin-base32-scure.mjs";
import "../_libs/scure__base.mjs";
import "../_libs/otplib__plugin-crypto-noble.mjs";
import "../_libs/noble__hashes.mjs";
function Section({
  icon: Icon,
  title,
  children
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: title })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-4", children })
  ] });
}
function Field({
  label,
  value,
  onChange,
  type = "text",
  placeholder,
  disabled
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground mb-1 block", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type, value, onChange: (e) => onChange(e.target.value), placeholder, disabled, className: "w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40 disabled:opacity-50" })
  ] });
}
function SecuritePage() {
  const {
    user,
    profile,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const [phone, setPhone] = reactExports.useState(profile?.phone || "");
  const [savingPhone, setSavingPhone] = reactExports.useState(false);
  const [showPhoneVerify, setShowPhoneVerify] = reactExports.useState(false);
  const [pendingVerify, setPendingVerify] = reactExports.useState(null);
  const [verifyCountdown, setVerifyCountdown] = reactExports.useState("");
  const [oldPassword, setOldPassword] = reactExports.useState("");
  const [newPassword, setNewPassword] = reactExports.useState("");
  const [confirmPassword, setConfirmPassword] = reactExports.useState("");
  const [showOldPassword, setShowOldPassword] = reactExports.useState(false);
  const [showPassword, setShowPassword] = reactExports.useState(false);
  const [savingPassword, setSavingPassword] = reactExports.useState(false);
  const [twoFactorEnabled, setTwoFactorEnabled] = reactExports.useState(false);
  const [show2FASetup, setShow2FASetup] = reactExports.useState(false);
  const [totpSecret, setTotpSecret] = reactExports.useState("");
  const [qrUrl, setQrUrl] = reactExports.useState("");
  const [otpCode, setOtpCode] = reactExports.useState("");
  const [verifying2FA, setVerifying2FA] = reactExports.useState(false);
  const [disabling2FA, setDisabling2FA] = reactExports.useState(false);
  const [disableCode, setDisableCode] = reactExports.useState("");
  reactExports.useEffect(() => {
    if (profile) {
      setPhone(profile.phone || "");
      setTwoFactorEnabled(profile.two_factor_enabled || false);
    }
  }, [profile?.id, profile?.phone]);
  reactExports.useEffect(() => {
    (async () => {
      if (profile?.phone_verified) {
        setPendingVerify(null);
        return;
      }
      try {
        const {
          data,
          error
        } = await supabase.rpc("get_pending_phone_verification");
        if (error) throw error;
        if (data?.pending && data?.code) {
          setPendingVerify({
            phone: data.phone,
            code: data.code,
            expiresAt: data.expires_at
          });
        } else {
          setPendingVerify(null);
        }
      } catch {
        setPendingVerify(null);
      }
    })();
  }, [profile?.phone_verified, profile?.id]);
  reactExports.useEffect(() => {
    if (!pendingVerify) {
      setVerifyCountdown("");
      return;
    }
    const update = () => {
      const expiry = new Date(pendingVerify.expiresAt).getTime();
      const now = Date.now();
      const remaining = Math.max(0, Math.floor((expiry - now) / 1e3));
      if (remaining <= 0) {
        setVerifyCountdown("Expiré");
        setPendingVerify(null);
        return;
      }
      const min = Math.floor(remaining / 60);
      const sec = remaining % 60;
      setVerifyCountdown(`${min}:${sec.toString().padStart(2, "0")}`);
    };
    update();
    const interval = setInterval(update, 1e3);
    return () => clearInterval(interval);
  }, [pendingVerify]);
  const start2FASetup = async () => {
    const newSecret = I();
    setTotpSecret(newSecret);
    const otpUrl = T({
      issuer: "LalaoMADA",
      label: user?.email || profile?.email || "user",
      secret: newSecret
    });
    setQrUrl(otpUrl);
    setShow2FASetup(true);
    setOtpCode("");
  };
  const confirm2FA = async () => {
    if (otpCode.length !== 6) return toast.error("Entrez le code a 6 chiffres");
    const result = d({
      token: otpCode,
      secret: totpSecret
    });
    if (!result?.valid) {
      return toast.error("Code incorrect, reessayez");
    }
    setVerifying2FA(true);
    try {
      const {
        error
      } = await supabase.rpc("set_totp_secret", {
        _secret: totpSecret
      });
      if (error) throw error;
      await refreshProfile();
      setTwoFactorEnabled(true);
      setShow2FASetup(false);
      setOtpCode("");
      toast.success("Authentification a 2 facteurs activee !");
    } catch (e) {
      toast.error(e?.message || "Erreur");
    } finally {
      setVerifying2FA(false);
    }
  };
  const disable2FA = async () => {
    if (disableCode.length !== 6) return toast.error("Entrez le code a 6 chiffres");
    setDisabling2FA(true);
    try {
      const {
        error
      } = await supabase.rpc("disable_totp");
      if (error) throw error;
      await refreshProfile();
      setTwoFactorEnabled(false);
      setDisableCode("");
      toast.success("Authentification a 2 facteurs desactivee");
    } catch (e) {
      toast.error(e?.message || "Erreur");
    } finally {
      setDisabling2FA(false);
    }
  };
  const savePhone = async () => {
    const trimmed = phone.trim();
    if (!trimmed) return toast.error("Numero requis");
    if (!/^[0-9+\s-]{8,15}$/.test(trimmed)) return toast.error("Numero invalide");
    if (trimmed === profile?.phone) return;
    setSavingPhone(true);
    try {
      const {
        error
      } = await supabase.from("profiles").update({
        phone: trimmed,
        phone_verified: false
      }).eq("id", user.id);
      if (error) throw error;
      await refreshProfile();
      toast.success("Numero enregistre");
    } catch (e) {
      toast.error(e?.message || "Erreur");
    } finally {
      setSavingPhone(false);
    }
  };
  const savePassword = async () => {
    if (!oldPassword) return toast.error("Ancien mot de passe requis");
    if (newPassword.length < 8) return toast.error("Mot de passe : 8 caracteres minimum");
    if (newPassword !== confirmPassword) return toast.error("Les mots de passe ne correspondent pas");
    if (newPassword === oldPassword) return toast.error("Le nouveau mot de passe doit etre different de l'ancien");
    setSavingPassword(true);
    try {
      const currentEmail = user?.email || profile?.email;
      if (!currentEmail) throw new Error("Impossible de verifier votre identite");
      const {
        error: verifyError
      } = await supabase.auth.signInWithPassword({
        email: currentEmail,
        password: oldPassword
      });
      if (verifyError) throw new Error("Ancien mot de passe incorrect");
      const {
        error
      } = await supabase.auth.updateUser({
        password: newPassword
      });
      if (error) throw error;
      toast.success("Mot de passe modifie");
      setOldPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (e) {
      toast.error(e?.message || "Erreur lors du changement");
    } finally {
      setSavingPassword(false);
    }
  };
  const phoneChanged = phone.trim() !== (profile?.phone || "");
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "min-h-screen max-w-md mx-auto px-4 pt-16 pb-28 space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mb-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate({
        to: "/profile",
        search: {}
      }), className: "w-9 h-9 rounded-full bg-secondary/60 flex items-center justify-center active:scale-90 transition", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-5 h-5" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold", children: "Sécurité" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: Phone, title: "Modifier le telephone", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Numero de telephone", value: phone, onChange: setPhone, type: "tel", placeholder: "+261 34 12 345 67" }),
      profile?.phone_verified && !phoneChanged && /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[11px] text-emerald-600 dark:text-emerald-400 flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-3.5 h-3.5" }),
        " Numero verifie ✓"
      ] }),
      pendingVerify && !profile?.phone_verified && !phoneChanged && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-amber-500/10 border border-amber-500/30 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-xs font-semibold text-amber-600 dark:text-amber-400", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-3.5 h-3.5 animate-spin" }),
          "Vérification en attente"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground", children: [
          "Code: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-mono font-bold text-primary", children: pendingVerify.code })
        ] }),
        verifyCountdown && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3 h-3" }),
          "Expire dans ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-amber-600 dark:text-amber-400", children: verifyCountdown })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[10px] text-muted-foreground", children: [
          "Envoyez le code par SMS au ",
          pendingVerify.phone ? "0385708218" : "0385708218"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowPhoneVerify(true), className: "w-full py-2 rounded-xl bg-amber-500/20 text-amber-600 dark:text-amber-400 text-xs font-semibold active:scale-95 transition", children: "Voir les détails" })
      ] }),
      !profile?.phone_verified && !phoneChanged && !pendingVerify && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setShowPhoneVerify(true), className: "w-full py-2.5 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 text-sm font-semibold active:scale-95 transition flex items-center justify-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Phone, { className: "w-4 h-4" }),
        " Verifier mon numero"
      ] }),
      phoneChanged && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-amber-600 dark:text-amber-400", children: "Le numero devra etre verifie a nouveau." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: savePhone, disabled: !phoneChanged || savingPhone, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5", children: savingPhone ? "Enregistrement…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-4 h-4" }),
        " Enregistrer"
      ] }) })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: Lock, title: "Modifier le mot de passe", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground mb-1 block", children: "Ancien mot de passe" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: showOldPassword ? "text" : "password", value: oldPassword, onChange: (e) => setOldPassword(e.target.value), placeholder: "Votre mot de passe actuel", className: "w-full px-3.5 py-2.5 pr-10 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowOldPassword((s) => !s), className: "absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground", children: showOldPassword ? /* @__PURE__ */ jsxRuntimeExports.jsx(EyeOff, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-4 h-4" }) })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground mb-1 block", children: "Nouveau mot de passe" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: showPassword ? "text" : "password", value: newPassword, onChange: (e) => setNewPassword(e.target.value), placeholder: "Minimum 8 caracteres", className: "w-full px-3.5 py-2.5 pr-10 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowPassword((s) => !s), className: "absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground", children: showPassword ? /* @__PURE__ */ jsxRuntimeExports.jsx(EyeOff, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-4 h-4" }) })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Confirmer le nouveau mot de passe", value: confirmPassword, onChange: setConfirmPassword, type: showPassword ? "text" : "password", placeholder: "Repeter le nouveau mot de passe" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: savePassword, disabled: !oldPassword || newPassword.length < 8 || newPassword !== confirmPassword || savingPassword, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5", children: savingPassword ? "Enregistrement…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4" }),
        " Changer le mot de passe"
      ] }) })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: KeyRound, title: "Authentification Google", children: twoFactorEnabled ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[11px] text-emerald-600 dark:text-emerald-400 flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-3.5 h-3.5" }),
        " 2FA active ✓"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground", children: "Votre compte est protege par Google Authenticator. Un code a 6 chiffres est requis a la connexion." }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-secondary/40 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground", children: "Code a 6 chiffres pour desactiver" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "text", inputMode: "numeric", maxLength: 6, value: disableCode, onChange: (e) => setDisableCode(e.target.value.replace(/\D/g, "")), placeholder: "000000", className: "w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-mono font-bold tracking-[0.3em] text-center outline-none focus:ring-2 ring-primary/40" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: disable2FA, disabled: disableCode.length !== 6 || disabling2FA, className: "w-full py-2.5 rounded-xl bg-destructive/10 border border-destructive/30 text-destructive text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5", children: disabling2FA ? "Desactivation…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }),
          " Desactiver 2FA"
        ] }) })
      ] })
    ] }) : show2FASetup ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
        "1. Ouvrez Google Authenticator sur votre telephone",
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        "2. Scannez le QR code ci-dessous",
        /* @__PURE__ */ jsxRuntimeExports.jsx("br", {}),
        "3. Entrez le code a 6 chiffres genere"
      ] }),
      qrUrl && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center bg-white p-3 rounded-xl", children: /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: `https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(qrUrl)}`, alt: "QR Code 2FA", width: 180, height: 180 }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-secondary/40 p-2 text-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground mb-1", children: "Cle manuelle (si scan impossible)" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-mono text-[11px] font-bold break-all", children: totpSecret })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground mb-1 block", children: "Code de verification" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "text", inputMode: "numeric", maxLength: 6, value: otpCode, onChange: (e) => setOtpCode(e.target.value.replace(/\D/g, "")), placeholder: "000000", className: "w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-mono font-bold tracking-[0.3em] text-center outline-none focus:ring-2 ring-primary/40" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShow2FASetup(false), className: "flex-1 py-2.5 rounded-xl bg-secondary text-sm font-semibold active:scale-95 transition", children: "Annuler" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: confirm2FA, disabled: otpCode.length !== 6 || verifying2FA, className: "flex-1 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5", children: verifying2FA ? "Verification…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-4 h-4" }),
          " Activer"
        ] }) })
      ] })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground", children: "Ajoutez une couche de securite supplementaire. Votre mot de passe + un code genere par Google Authenticator." }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: start2FASetup, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 transition flex items-center justify-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-4 h-4" }),
        " Configurer Google Authenticator"
      ] })
    ] }) }),
    showPhoneVerify && /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyPopup, { onClose: () => setShowPhoneVerify(false) })
  ] });
}
export {
  SecuritePage as component
};
