import { useState, useEffect, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { X, Phone, Send, Check, Loader2, ShieldCheck, MessageSquare } from "lucide-react";
import { toast } from "sonner";

/**
 * PhoneVerifyPopup — flow simplifié de vérification téléphone.
 * 1. User entre son numéro (un seul clic)
 * 2. Le code LMxxxxxx s'affiche immédiatement
 * 3. User envoie ce code par SMS au numéro admin
 * 4. Termux auto-valide en lisant le SMS reçu
 *
 * Pas d'expiration — le code reste valide jusqu'à utilisation.
 * Accepte: +261..., 261..., 034..., 34...
 */
export default function PhoneVerifyPopup({ onClose }: { onClose: () => void }) {
  const { profile, refreshProfile } = useAuth();
  const [step, setStep] = useState<"loading" | "phone" | "code" | "done">("loading");
  const [phone, setPhone] = useState(profile?.phone || "");
  const [code, setCode] = useState("");
  const [adminPhone, setAdminPhone] = useState("");
  const [adminPhone2, setAdminPhone2] = useState("");
  const [loading, setLoading] = useState(false);
  const [polling, setPolling] = useState(false);

  // Fetch admin phone
  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from("app_settings")
        .select("admin_phone, airtel_phone")
        .limit(1)
        .single();
      if (data?.admin_phone) setAdminPhone(data.admin_phone);
      if (data?.airtel_phone) setAdminPhone2(data.airtel_phone);
    })();
  }, []);

  // ── RESTAURATION: Au montage, vérifier s'il y a un code en cours ──
  useEffect(() => {
    (async () => {
      try {
        const { data, error } = await supabase.rpc("get_pending_phone_verification");
        if (error) throw error;

        if (data?.pending && data?.code) {
          setPhone(data.phone || phone);
          setCode(data.code);
          setStep("code");
          setPolling(true);
        } else {
          setStep("phone");
        }
      } catch {
        setStep("phone");
      }
    })();
  }, []);

  // Poll for verification status
  useEffect(() => {
    if (step !== "code" || !polling) return;
    const interval = setInterval(async () => {
      const { data } = await supabase
        .from("profiles")
        .select("phone_verified")
        .eq("id", profile?.id)
        .single();
      if (data?.phone_verified === true) {
        setPolling(false);
        setStep("done");
        clearInterval(interval);
        await refreshProfile();
      }
    }, 3000);
    return () => clearInterval(interval);
  }, [step, polling, profile?.id, refreshProfile]);

  // ── Normalisation côté client (pour affichage) ──
  const normalizePhoneDisplay = (p: string): string => {
    let v = p.replace(/[\s\-().]/g, "");
    if (v.startsWith("+261")) v = "0" + v.slice(4);
    else if (v.startsWith("261") && v.length >= 11) v = "0" + v.slice(3);
    else if (v.length === 9 && /^[234]/.test(v)) v = "0" + v;
    return v;
  };

  // ── UN SEUL CLIC: générer le code ──
  const requestCode = useCallback(async () => {
    const trimmed = phone.trim();
    if (!trimmed) return toast.error("Entrez votre numéro");
    if (trimmed.replace(/[\s\-+]/g, "").length < 8) return toast.error("Numéro invalide");
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc("request_phone_verification", { _phone: trimmed });
      if (error) throw error;
      setCode(data as string);
      setStep("code");
      setPolling(true);
      toast.success("Code généré !");
    } catch (e: any) {
      toast.error(e?.message || "Erreur");
    } finally {
      setLoading(false);
    }
  }, [phone]);

  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4" onClick={onClose}>
      <div
        className="bg-card text-card-foreground rounded-2xl shadow-2xl border border-border w-full max-w-sm p-5 space-y-4 animate-pop-in"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between">
          <h3 className="font-bold text-base flex items-center gap-2">
            <ShieldCheck className="w-5 h-5 text-primary" />
            Vérification du numéro
          </h3>
          <button onClick={onClose} className="text-muted-foreground hover:text-foreground transition">
            <X className="w-5 h-5" />
          </button>
        </div>

        {step === "loading" && (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="w-6 h-6 animate-spin text-muted-foreground" />
          </div>
        )}

        {step === "phone" && (
          <div className="space-y-3">
            <p className="text-xs text-muted-foreground">
              Pour jouer avec mise, vérifiez votre numéro. Un code vous sera donné à envoyer par SMS.
            </p>
            <div className="relative">
              <Phone className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" />
              <input
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="034 12 345 67  (+261, 261, 0…)"
                className="w-full pl-10 pr-4 py-2.5 rounded-xl border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary"
                onKeyDown={(e) => e.key === "Enter" && requestCode()}
                autoFocus
              />
            </div>
            <button
              onClick={requestCode}
              disabled={loading || !phone.trim()}
              className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5"
            >
              {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <><Send className="w-4 h-4" /> Vérifier mon numéro</>}
            </button>
          </div>
        )}

        {step === "code" && (
          <div className="space-y-3">
            <div className="text-center space-y-1">
              <p className="text-xs text-muted-foreground">Votre code de vérification :</p>
              <div className="text-3xl font-mono font-extrabold text-primary tracking-wider py-2 bg-primary/10 rounded-xl">
                {code}
              </div>
            </div>
            <div className="bg-amber-500/10 border border-amber-500/30 rounded-xl p-3 space-y-1.5">
              <p className="text-xs font-semibold text-amber-600 dark:text-amber-400 flex items-center gap-1">
                <MessageSquare className="w-3.5 h-3.5" /> Envoyez ce code par SMS
              </p>
              <p className="text-xs text-muted-foreground">
                Envoyez <b className="font-mono">{code}</b> par SMS à l'un de ces numéros :
              </p>
              <div className="text-lg font-bold text-center py-1 space-y-1">
                <div>{adminPhone || "0385708218"}</div>
                {adminPhone2 && <div className="text-sm text-muted-foreground">{adminPhone2}</div>}
              </div>
              <p className="text-[10px] text-muted-foreground text-center">
                (coût d'un SMS normal, selon votre opérateur)
              </p>
            </div>
            <div className="text-center text-xs text-muted-foreground">
              {polling ? (
                <span className="flex items-center justify-center gap-1.5">
                  <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  En attente de vérification...
                </span>
              ) : (
                "En attente de validation"
              )}
            </div>
            <button
              onClick={() => { setStep("phone"); setPolling(false); }}
              className="w-full py-2 rounded-xl border border-border text-xs text-muted-foreground hover:bg-accent transition"
            >
              Changer de numéro
            </button>
          </div>
        )}

        {step === "done" && (
          <div className="text-center space-y-3 py-4">
            <div className="w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center mx-auto">
              <Check className="w-8 h-8 text-emerald-500" />
            </div>
            <p className="font-bold text-base">Numéro vérifié !</p>
            <p className="text-xs text-muted-foreground">Vous pouvez maintenant jouer avec mise.</p>
            <button
              onClick={onClose}
              className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 transition"
            >
              Continuer
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
