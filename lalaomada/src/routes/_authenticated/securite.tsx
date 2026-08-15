import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import PhoneVerifyPopup from "@/components/PhoneVerifyPopup";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  ArrowLeft, Phone, Lock, Check, Eye, EyeOff, Clock, Loader2, ShieldCheck, KeyRound, X,
} from "lucide-react";
import { generateSecret, generateURI, verifySync } from "otplib";


export const Route = createFileRoute("/_authenticated/securite")({
  component: SecuritePage,
  head: () => ({ meta: [
    { title: "Sécurité — Lalao MADA" },
    { name: "description", content: "Sécurité du compte : vérification du téléphone et mot de passe." },
  ] }),
});

/* Section wrapper */
function Section({ icon: Icon, title, children }: {
  icon: any; title: string; children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl bg-card border border-border/40 overflow-hidden">
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30">
        <Icon className="w-4 h-4 text-primary" />
        <span className="font-bold text-sm">{title}</span>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

/* Input field */
function Field({ label, value, onChange, type = "text", placeholder, disabled }: {
  label: string; value: string; onChange: (v: string) => void;
  type?: string; placeholder?: string; disabled?: boolean;
}) {
  return (
    <div>
      <label className="text-xs font-semibold text-muted-foreground mb-1 block">{label}</label>
      <input
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        className="w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40 disabled:opacity-50"
      />
    </div>
  );
}

/* Securite Page — téléphone (vérification) + mot de passe.
   (Le volet infos générales — nom/email/apparence — vit dans /parametres) */
function SecuritePage() {
  const { user, profile, refreshProfile } = useAuth();
  const navigate = useNavigate();

  const [phone, setPhone] = useState(profile?.phone || "");
  const [savingPhone, setSavingPhone] = useState(false);
  const [showPhoneVerify, setShowPhoneVerify] = useState(false);

  // ── État de vérification en attente (persistant) ──
  const [pendingVerify, setPendingVerify] = useState<{ phone: string; code: string; expiresAt: string } | null>(null);
  const [verifyCountdown, setVerifyCountdown] = useState("");

  const [oldPassword, setOldPassword] = useState("");
  const [newPassword, setNewPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [showOldPassword, setShowOldPassword] = useState(false);
  const [showPassword, setShowPassword] = useState(false);
  const [savingPassword, setSavingPassword] = useState(false);

  // ── 2FA (Google Authenticator) ──
  const [twoFactorEnabled, setTwoFactorEnabled] = useState(false);
  const [show2FASetup, setShow2FASetup] = useState(false);
  const [totpSecret, setTotpSecret] = useState("");
  const [qrUrl, setQrUrl] = useState("");
  const [otpCode, setOtpCode] = useState("");
  const [verifying2FA, setVerifying2FA] = useState(false);
  const [disabling2FA, setDisabling2FA] = useState(false);
  const [disableCode, setDisableCode] = useState("");

  useEffect(() => {
    if (profile) {
      setPhone(profile.phone || "");
      setTwoFactorEnabled((profile as any).two_factor_enabled || false);
    }
  }, [profile?.id, profile?.phone]);

  // ── Vérifier s'il y a une demande de vérification en attente ──
  useEffect(() => {
    (async () => {
      if (profile?.phone_verified) {
        setPendingVerify(null);
        return;
      }
      try {
        const { data, error } = await supabase.rpc("get_pending_phone_verification");
        if (error) throw error;
        if (data?.pending && data?.code) {
          setPendingVerify({
            phone: data.phone,
            code: data.code,
            expiresAt: data.expires_at,
          });
        } else {
          setPendingVerify(null);
        }
      } catch {
        setPendingVerify(null);
      }
    })();
  }, [profile?.phone_verified, profile?.id]);

  // ── Countdown pour la vérification en attente ──
  useEffect(() => {
    if (!pendingVerify) {
      setVerifyCountdown("");
      return;
    }
    const update = () => {
      const expiry = new Date(pendingVerify.expiresAt).getTime();
      const now = Date.now();
      const remaining = Math.max(0, Math.floor((expiry - now) / 1000));
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
    const interval = setInterval(update, 1000);
    return () => clearInterval(interval);
  }, [pendingVerify]);

  // ── 2FA: Generate secret + QR ──
  const start2FASetup = async () => {
    const newSecret = generateSecret();
    setTotpSecret(newSecret);
    const otpUrl = generateURI({
      issuer: "LalaoMADA",
      label: user?.email || profile?.email || "user",
      secret: newSecret,
    });
    setQrUrl(otpUrl);
    setShow2FASetup(true);
    setOtpCode("");
  };

  // ── 2FA: Verify code and enable ──
  const confirm2FA = async () => {
    if (otpCode.length !== 6) return toast.error("Entrez le code a 6 chiffres");
    const result = verifySync({ token: otpCode, secret: totpSecret });
    if (!result?.valid) {
      return toast.error("Code incorrect, reessayez");
    }
    setVerifying2FA(true);
    try {
      // Store secret server-side via RPC (never in profiles table directly)
      const { error } = await supabase.rpc("set_totp_secret" as any, { _secret: totpSecret } as any);
      if (error) throw error;
      await refreshProfile();
      setTwoFactorEnabled(true);
      setShow2FASetup(false);
      setOtpCode("");
      toast.success("Authentification a 2 facteurs activee !");
    } catch (e: any) {
      toast.error(e?.message || "Erreur");
    } finally {
      setVerifying2FA(false);
    }
  };

  // ── 2FA: Disable (verify code before disabling) ──
  const disable2FA = async () => {
    if (disableCode.length !== 6) return toast.error("Entrez le code a 6 chiffres");
    setDisabling2FA(true);
    try {
      const { data: sessionData } = await supabase.auth.getSession();
      if (!sessionData.session) throw new Error("Session invalide");

      // Secure disable: verify code AND disable 2FA in one atomic edge function call
      const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
      const response = await fetch(`${SUPABASE_URL}/functions/v1/disable-2fa`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${sessionData.session.access_token}`,
        },
        body: JSON.stringify({ code: disableCode }),
      });
      const result = await response.json();

      if (!result.success) {
        throw new Error(result.error || "Code 2FA incorrect");
      }

      await refreshProfile();
      setTwoFactorEnabled(false);
      setDisableCode("");
      toast.success("Authentification a 2 facteurs desactivee");
    } catch (e: any) {
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
      const { error } = await supabase.from("profiles").update({
        phone: trimmed,
        phone_verified: false,
      }).eq("id", user!.id);
      if (error) throw error;
      await refreshProfile();
      toast.success("Numero enregistre");
    } catch (e: any) {
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
      // Verifie l'ancien mot de passe avant tout changement
      const currentEmail = user?.email || profile?.email;
      if (!currentEmail) throw new Error("Impossible de verifier votre identite");
      const { error: verifyError } = await supabase.auth.signInWithPassword({
        email: currentEmail, password: oldPassword,
      });
      if (verifyError) throw new Error("Ancien mot de passe incorrect");

      const { error } = await supabase.auth.updateUser({ password: newPassword });
      if (error) throw error;
      toast.success("Mot de passe modifie");
      setOldPassword("");
      setNewPassword("");
      setConfirmPassword("");
    } catch (e: any) {
      toast.error(e?.message || "Erreur lors du changement");
    } finally {
      setSavingPassword(false);
    }
  };

  const phoneChanged = phone.trim() !== (profile?.phone || "");

  return (
    <main className="min-h-screen max-w-md mx-auto px-4 pt-16 pb-28 space-y-4">
      <div className="flex items-center gap-2 mb-2">
        <button onClick={() => navigate({ to: "/profile", search: {} })}
          className="w-9 h-9 rounded-full bg-secondary/60 flex items-center justify-center active:scale-90 transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-xl font-extrabold">Sécurité</h1>
      </div>

      {/* Telephone */}
      <Section icon={Phone} title="Modifier le telephone">
        <div className="space-y-3">
          <Field label="Numero de telephone" value={phone} onChange={setPhone} type="tel" placeholder="+261 34 12 345 67" />

          {/* Statut: Vérifié */}
          {profile?.phone_verified && !phoneChanged && (
            <p className="text-[11px] text-emerald-600 dark:text-emerald-400 flex items-center gap-1">
              <ShieldCheck className="w-3.5 h-3.5" /> Numero verifie ✓
            </p>
          )}

          {/* Statut: En attente de vérification */}
          {pendingVerify && !profile?.phone_verified && !phoneChanged && (
            <div className="rounded-xl bg-amber-500/10 border border-amber-500/30 p-3 space-y-2">
              <div className="flex items-center gap-1.5 text-xs font-semibold text-amber-600 dark:text-amber-400">
                <Loader2 className="w-3.5 h-3.5 animate-spin" />
                Vérification en attente
              </div>
              <div className="text-xs text-muted-foreground">
                Code: <span className="font-mono font-bold text-primary">{pendingVerify.code}</span>
              </div>
              {verifyCountdown && (
                <div className="text-xs text-muted-foreground flex items-center gap-1">
                  <Clock className="w-3 h-3" />
                  Expire dans <span className="font-semibold text-amber-600 dark:text-amber-400">{verifyCountdown}</span>
                </div>
              )}
              <p className="text-[10px] text-muted-foreground">
                Envoyez le code par SMS au {pendingVerify.phone ? "0385708218" : "0385708218"}
              </p>
              <button onClick={() => setShowPhoneVerify(true)}
                className="w-full py-2 rounded-xl bg-amber-500/20 text-amber-600 dark:text-amber-400 text-xs font-semibold active:scale-95 transition">
                Voir les détails
              </button>
            </div>
          )}

          {/* Statut: Non vérifié, pas en attente */}
          {!profile?.phone_verified && !phoneChanged && !pendingVerify && (
            <button onClick={() => setShowPhoneVerify(true)}
              className="w-full py-2.5 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 text-sm font-semibold active:scale-95 transition flex items-center justify-center gap-1.5">
              <Phone className="w-4 h-4" /> Verifier mon numero
            </button>
          )}

          {phoneChanged && (
            <p className="text-[11px] text-amber-600 dark:text-amber-400">
              Le numero devra etre verifie a nouveau.
            </p>
          )}
          <button onClick={savePhone} disabled={!phoneChanged || savingPhone}
            className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5">
            {savingPhone ? "Enregistrement…" : (<><Check className="w-4 h-4" /> Enregistrer</>)}
          </button>
        </div>
      </Section>

      {/* Mot de passe */}
      <Section icon={Lock} title="Modifier le mot de passe">
        <div className="space-y-3">
          <div>
            <label className="text-xs font-semibold text-muted-foreground mb-1 block">Ancien mot de passe</label>
            <div className="relative">
              <input
                type={showOldPassword ? "text" : "password"}
                value={oldPassword}
                onChange={e => setOldPassword(e.target.value)}
                placeholder="Votre mot de passe actuel"
                className="w-full px-3.5 py-2.5 pr-10 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40"
              />
              <button onClick={() => setShowOldPassword(s => !s)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                {showOldPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>
          <div>
            <label className="text-xs font-semibold text-muted-foreground mb-1 block">Nouveau mot de passe</label>
            <div className="relative">
              <input
                type={showPassword ? "text" : "password"}
                value={newPassword}
                onChange={e => setNewPassword(e.target.value)}
                placeholder="Minimum 8 caracteres"
                className="w-full px-3.5 py-2.5 pr-10 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40"
              />
              <button onClick={() => setShowPassword(s => !s)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground">
                {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
              </button>
            </div>
          </div>
          <Field label="Confirmer le nouveau mot de passe" value={confirmPassword} onChange={setConfirmPassword} type={showPassword ? "text" : "password"} placeholder="Repeter le nouveau mot de passe" />
          <button onClick={savePassword}
            disabled={!oldPassword || newPassword.length < 8 || newPassword !== confirmPassword || savingPassword}
            className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5">
            {savingPassword ? "Enregistrement…" : (<><Lock className="w-4 h-4" /> Changer le mot de passe</>)}
          </button>
        </div>
      </Section>

      {/* Google Authenticator (2FA) */}
      <Section icon={KeyRound} title="Authentification Google">
        {twoFactorEnabled ? (
          <div className="space-y-3">
            <p className="text-[11px] text-emerald-600 dark:text-emerald-400 flex items-center gap-1">
              <ShieldCheck className="w-3.5 h-3.5" /> 2FA active ✓
            </p>
            <p className="text-[11px] text-muted-foreground">
              Votre compte est protege par Google Authenticator. Un code a 6 chiffres est requis a la connexion.
            </p>
            <div className="rounded-xl bg-secondary/40 p-3 space-y-2">
              <label className="text-xs font-semibold text-muted-foreground">Code a 6 chiffres pour desactiver</label>
              <input
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={disableCode}
                onChange={e => setDisableCode(e.target.value.replace(/\D/g, ""))}
                placeholder="000000"
                className="w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-mono font-bold tracking-[0.3em] text-center outline-none focus:ring-2 ring-primary/40"
              />
              <button onClick={disable2FA} disabled={disableCode.length !== 6 || disabling2FA}
                className="w-full py-2.5 rounded-xl bg-destructive/10 border border-destructive/30 text-destructive text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5">
                {disabling2FA ? "Desactivation…" : (<><X className="w-4 h-4" /> Desactiver 2FA</>)}
              </button>
            </div>
          </div>
        ) : show2FASetup ? (
          <div className="space-y-3">
            <p className="text-xs text-muted-foreground">
              1. Ouvrez Google Authenticator sur votre telephone<br />
              2. Scannez le QR code ci-dessous<br />
              3. Entrez le code a 6 chiffres genere
            </p>
            {qrUrl && (
              <div className="flex justify-center bg-white p-3 rounded-xl">
                <img src={`https://api.qrserver.com/v1/create-qr-code/?size=180x180&data=${encodeURIComponent(qrUrl)}`}
                  alt="QR Code 2FA" width={180} height={180} />
              </div>
            )}
            <div className="rounded-xl bg-secondary/40 p-2 text-center">
              <p className="text-[10px] text-muted-foreground mb-1">Cle manuelle (si scan impossible)</p>
              <p className="font-mono text-[11px] font-bold break-all">{totpSecret}</p>
            </div>
            <div>
              <label className="text-xs font-semibold text-muted-foreground mb-1 block">Code de verification</label>
              <input
                type="text"
                inputMode="numeric"
                maxLength={6}
                value={otpCode}
                onChange={e => setOtpCode(e.target.value.replace(/\D/g, ""))}
                placeholder="000000"
                className="w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-mono font-bold tracking-[0.3em] text-center outline-none focus:ring-2 ring-primary/40"
              />
            </div>
            <div className="flex gap-2">
              <button onClick={() => setShow2FASetup(false)}
                className="flex-1 py-2.5 rounded-xl bg-secondary text-sm font-semibold active:scale-95 transition">
                Annuler
              </button>
              <button onClick={confirm2FA} disabled={otpCode.length !== 6 || verifying2FA}
                className="flex-1 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5">
                {verifying2FA ? "Verification…" : (<><Check className="w-4 h-4" /> Activer</>)}
              </button>
            </div>
          </div>
        ) : (
          <div className="space-y-3">
            <p className="text-[11px] text-muted-foreground">
              Ajoutez une couche de securite supplementaire. Votre mot de passe + un code genere par Google Authenticator.
            </p>
            <button onClick={start2FASetup}
              className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 transition flex items-center justify-center gap-1.5">
              <KeyRound className="w-4 h-4" /> Configurer Google Authenticator
            </button>
          </div>
        )}
      </Section>

      {showPhoneVerify && <PhoneVerifyPopup onClose={() => setShowPhoneVerify(false)} />}
    </main>
  );
}
