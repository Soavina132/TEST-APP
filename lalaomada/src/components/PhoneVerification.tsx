import { useState, useEffect, useRef, FormEvent } from "react";
import { supabase } from "@/integrations/supabase/client";
import { getFirebase } from "@/integrations/firebase/client";
import { toast } from "sonner";
import { Phone, Loader2, CheckCircle2, Shield, X, RefreshCw } from "lucide-react";
import {
  RecaptchaVerifier,
  signInWithPhoneNumber,
  PhoneAuthProvider,
  signOut,
} from "firebase/auth";

type Props = {
  onClose?: () => void;
  onVerified?: (phone: string) => void;
  currentPhone?: string | null;
  embedded?: boolean; // if true, no modal wrapper
};

export default function PhoneVerification({ onClose, onVerified, currentPhone, embedded }: Props) {
  const [step, setStep] = useState<"phone" | "code" | "done">("phone");
  const [phone, setPhone] = useState("");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [resendIn, setResendIn] = useState(0);
  const [recaptchaReady, setRecaptchaReady] = useState(false);
  const verifierRef = useRef<RecaptchaVerifier | null>(null);
  const confirmRef = useRef<{ confirm: (code: string) => Promise<any> } | null>(null);

  // Pre-fill current phone
  useEffect(() => {
    if (currentPhone) {
      setPhone(currentPhone.startsWith("+261") ? currentPhone : `+261${currentPhone.replace(/^\+261/, "")}`);
    }
  }, [currentPhone]);

  // Resend countdown
  useEffect(() => {
    if (resendIn <= 0) return;
    const t = setInterval(() => setResendIn(s => Math.max(0, s - 1)), 1000);
    return () => clearInterval(t);
  }, [resendIn]);

  // Setup reCAPTCHA
  useEffect(() => {
    if (step !== "phone") return;
    try {
      const { auth } = getFirebase();
      if (!verifierRef.current) {
        // Create invisible reCAPTCHA
        const verifier = new RecaptchaVerifier(auth, "phone-verify-btn", {
          size: "invisible",
          callback: () => { setRecaptchaReady(true); },
          "expired-callback": () => { setRecaptchaReady(false); toast.error("reCAPTCHA expiré, réessayez"); },
        });
        verifierRef.current = verifier;
        // Render and verify
        verifier.render().then(() => {
          setRecaptchaReady(true);
        }).catch(() => {});
      }
    } catch (e) {
      console.error("reCAPTCHA setup error:", e);
    }
  }, [step]);

  const normalizePhone = (raw: string) => {
    let p = raw.trim().replace(/\s/g, "");
    if (!p.startsWith("+")) p = "+" + p;
    if (p.startsWith("+261")) {
      // +261 34XXXXXXXX or +261 340000000
      const digits = p.replace(/^\+261/, "");
      if (digits.length === 9) return `+261${digits}`;
      if (digits.length === 10 && digits.startsWith("0")) return `+261${digits.slice(1)}`;
    }
    return p;
  };

  const sendCode = async (e: FormEvent) => {
    e.preventDefault();
    const normalized = normalizePhone(phone);
    if (!/^\+261\d{9}$/.test(normalized)) {
      return toast.error("Format: +261 suivi de 9 chiffres (ex: +261340000000)");
    }

    setBusy(true);
    try {
      const { auth } = getFirebase();
      const verifier = verifierRef.current;
      if (!verifier) throw new Error("reCAPTCHA non initialisé");

      // Force re-render if needed
      await verifier.render();

      const result = await signInWithPhoneNumber(auth, normalized, verifier);
      confirmRef.current = result;
      setStep("code");
      setResendIn(60);
      toast.success("SMS envoyé !");
    } catch (err: any) {
      console.error("Phone auth error:", err);
      const msg = err?.message || "Erreur lors de l'envoi du SMS";
      if (msg.includes("TOO_SHORT") || msg.includes("invalid")) {
        toast.error("Numéro invalide. Format: +261 34 XX XXX XX");
      } else if (msg.includes("CONFIGURATION_NOT_FOUND")) {
        toast.error("Firebase Authentication n'est pas encore activé. Voir la console Firebase.");
      } else if (msg.includes("quota")) {
        toast.error("Quota SMS dépassé, réessayez plus tard");
      } else {
        toast.error(msg);
      }
      // Reset reCAPTCHA
      verifierRef.current?.clear();
      verifierRef.current = null;
    } finally {
      setBusy(false);
    }
  };

  const resendCode = async () => {
    if (resendIn > 0) return;
    setBusy(true);
    try {
      const { auth } = getFirebase();
      verifierRef.current?.clear();
      const verifier = new RecaptchaVerifier(auth, "resend-btn", { size: "invisible" });
      verifierRef.current = verifier;
      await verifier.render();
      const normalized = normalizePhone(phone);
      const result = await signInWithPhoneNumber(auth, normalized, verifier);
      confirmRef.current = result;
      setResendIn(60);
      toast.success("Nouveau SMS envoyé !");
    } catch (err: any) {
      toast.error(err?.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };

  const verifyCode = async (e: FormEvent) => {
    e.preventDefault();
    if (code.length < 4) return toast.error("Entrez le code reçu par SMS");
    setBusy(true);
    try {
      if (!confirmRef.current) throw new Error("Session expirée, renvoyez le code");
      const result = await confirmRef.current.confirm(code);
      // Get the Firebase ID token
      const firebaseToken = await result.user.getIdToken();

      // Send to backend for verification and profile update
      const { data: sess } = await supabase.auth.getSession();
      const authToken = sess.session?.access_token;
      const supabaseUrl = (import.meta as any).env.VITE_SUPABASE_URL;
      const supabaseKey = (import.meta as any).env.VITE_SUPABASE_PUBLISHABLE_KEY;

      const resp = await fetch(`${supabaseUrl}/functions/v1/verify-phone`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${authToken}`,
          apikey: supabaseKey,
        },
        body: JSON.stringify({ firebaseToken }),
      });
      const data = await resp.json().catch(() => ({}));
      if (!resp.ok) throw new Error(data?.error || "Erreur de vérification");

      // Sign out from Firebase (we only used it for phone verification)
      const { auth } = getFirebase();
      await signOut(auth);

      setStep("done");
      toast.success("Numéro vérifié !");
      onVerified?.(normalizePhone(phone));
    } catch (err: any) {
      const msg = err?.message || "Code invalide ou expiré";
      if (msg.includes("invalid-verification-code") || msg.includes("code")) {
        toast.error("Code incorrect, vérifiez le SMS reçu");
      } else {
        toast.error(msg);
      }
    } finally {
      setBusy(false);
    }
  };

  const content = (
    <>
      {step === "phone" && (
        <form onSubmit={sendCode} className="space-y-4">
          <div>
            <p className="text-sm text-muted-foreground mb-3">
              Entrez votre numéro de téléphone. Un code de vérification sera envoyé par SMS.
            </p>
            <div className="relative">
              <Phone className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" />
              <input
                type="tel"
                value={phone}
                onChange={e => setPhone(e.target.value)}
                placeholder="+261 34 XX XXX XX"
                autoComplete="tel"
                autoFocus
                className="w-full pl-10 pr-3 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors"
              />
            </div>
            <p className="text-xs text-muted-foreground mt-2">
              Format: +261 suivi de 9 chiffres (ex: +261340000000)
            </p>
          </div>
          <button
            id="phone-verify-btn"
            type="submit"
            disabled={busy || !phone}
            className="w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all disabled:opacity-60 flex items-center justify-center gap-2"
            style={{ background: "var(--gradient-primary)" }}
          >
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Phone className="w-4 h-4" />}
            {busy ? "Envoi…" : "Envoyer le code SMS"}
          </button>
        </form>
      )}

      {step === "code" && (
        <form onSubmit={verifyCode} className="space-y-4">
          <div className="text-center">
            <div className="mx-auto w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center mb-3">
              <Shield className="w-7 h-7 text-primary" />
            </div>
            <h3 className="font-bold text-base mb-1">Entrez le code SMS</h3>
            <p className="text-sm text-muted-foreground">
              Code envoyé au <span className="font-semibold text-foreground">{normalizePhone(phone)}</span>
            </p>
          </div>
          <input
            type="text"
            inputMode="numeric"
            autoComplete="one-time-code"
            value={code}
            onChange={e => setCode(e.target.value.replace(/\D/g, "").slice(0, 6))}
            placeholder="------"
            autoFocus
            className="w-full text-center text-2xl font-bold tracking-[0.5em] py-3 rounded-xl border border-border bg-background focus:outline-none focus:ring-2 focus:ring-primary"
          />
          <button
            type="submit"
            disabled={busy || code.length < 4}
            className="w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all disabled:opacity-60 flex items-center justify-center gap-2"
            style={{ background: "var(--gradient-primary)" }}
          >
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
            {busy ? "Vérification…" : "Vérifier"}
          </button>
          <div className="flex items-center justify-between">
            <button
              type="button"
              onClick={() => { setStep("phone"); setCode(""); confirmRef.current = null; }}
              className="text-xs text-muted-foreground hover:text-foreground"
            >
              ← Changer de numéro
            </button>
            <button
              id="resend-btn"
              type="button"
              onClick={resendCode}
              disabled={resendIn > 0 || busy}
              className="text-xs text-primary font-semibold disabled:opacity-50 flex items-center gap-1"
            >
              {resendIn > 0 ? `Renvoyer (${resendIn}s)` : "Renvoyer le code"}
            </button>
          </div>
        </form>
      )}

      {step === "done" && (
        <div className="text-center py-4">
          <div className="mx-auto w-16 h-16 rounded-full bg-emerald-500/15 flex items-center justify-center mb-3">
            <CheckCircle2 className="w-8 h-8 text-emerald-500" />
          </div>
          <h3 className="font-bold text-lg mb-1">Numéro vérifié !</h3>
          <p className="text-sm text-muted-foreground mb-4">
            Votre numéro <span className="font-semibold text-foreground">{normalizePhone(phone)}</span> a été vérifié avec succès.
          </p>
          {onClose && (
            <button
              onClick={onClose}
              className="w-full py-3.5 rounded-xl text-white font-bold text-sm"
              style={{ background: "var(--gradient-primary)" }}
            >
              Terminé
            </button>
          )}
        </div>
      )}
    </>
  );

  if (embedded) return content;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4" onClick={onClose}>
      <div className="bg-card rounded-2xl max-w-md w-full p-6 shadow-2xl border border-border" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-5">
          <div className="font-bold flex items-center gap-2">
            <Shield className="w-4 h-4 text-primary" /> Vérification du numéro
          </div>
          {onClose && (
            <button onClick={onClose} className="p-1.5 rounded-full hover:bg-secondary" aria-label="Fermer">
              <X className="w-4 h-4" />
            </button>
          )}
        </div>
        {content}
      </div>
    </div>
  );
}
