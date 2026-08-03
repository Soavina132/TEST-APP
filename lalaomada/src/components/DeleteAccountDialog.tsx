import { useState } from "react";
import { AlertTriangle, Eye, EyeOff, Trash2, X } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { useNavigate } from "@tanstack/react-router";

interface Props { open: boolean; onClose: () => void; }

export function DeleteAccountDialog({ open, onClose }: Props) {
  const { signOut, user } = useAuth();
  const navigate = useNavigate();
  const [step, setStep] = useState<"warn" | "password">("warn");
  const [password, setPassword] = useState("");
  const [showPwd, setShowPwd] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");

  if (!open) return null;

  const handleClose = () => { setStep("warn"); setPassword(""); setError(""); onClose(); };

  const handleDelete = async () => {
    if (!password.trim()) { setError("Veuillez saisir votre mot de passe."); return; }
    setBusy(true);
    setError("");

    // 1. Verify password by re-authenticating
    const { error: authErr } = await supabase.auth.signInWithPassword({
      email: user?.email || "",
      password,
    });

    if (authErr) {
      setBusy(false);
      setError("Mot de passe incorrect. Veuillez réessayer.");
      return;
    }

    // 2. Delete account via RPC
    const { error: delErr } = await supabase.rpc("delete_my_account" as any);
    if (delErr) {
      setBusy(false);
      setError(delErr.message);
      return;
    }

    // 3. Sign out and redirect
    await signOut();
    toast.success("Votre compte a été supprimé définitivement.");
    navigate({ to: "/login" });
  };

  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-black/60 backdrop-blur-sm" onClick={(e) => { if (e.target === e.currentTarget) handleClose(); }}>
      <div className="w-full max-w-sm rounded-3xl bg-card shadow-2xl border border-border/60 overflow-hidden">
        {/* Header */}
        <div className="bg-destructive/10 px-5 pt-5 pb-4 border-b border-destructive/20">
          <div className="flex items-start justify-between gap-3">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-2xl bg-destructive/20 flex items-center justify-center shrink-0">
                <AlertTriangle className="w-5 h-5 text-destructive" />
              </div>
              <div>
                <div className="font-extrabold text-base text-destructive">Supprimer mon compte</div>
                <div className="text-xs text-muted-foreground mt-0.5">Cette action est irréversible</div>
              </div>
            </div>
            <button onClick={handleClose} className="p-1.5 rounded-xl hover:bg-secondary mt-0.5">
              <X className="w-4 h-4 text-muted-foreground" />
            </button>
          </div>
        </div>

        <div className="p-5 space-y-4">
          {step === "warn" ? (
            <>
              {/* Warning list */}
              <div className="space-y-2 text-sm">
                <p className="font-semibold">En supprimant votre compte :</p>
                <ul className="space-y-1.5 text-muted-foreground">
                  {[
                    "Votre profil, pseudo et photo disparaîtront",
                    "Votre solde de " + "{{balance}}" + " Ar sera perdu",
                    "Votre historique de parties sera effacé",
                    "Vos parrainages et bonus seront annulés",
                    "Vous ne pourrez plus vous reconnecter",
                  ].map((item, i) => (
                    <li key={i} className="flex items-start gap-2">
                      <span className="text-destructive mt-0.5 shrink-0">✕</span>
                      <span>{item.replace("{{balance}}", "votre")}</span>
                    </li>
                  ))}
                </ul>
              </div>

              <div className="flex gap-2">
                <button onClick={handleClose} className="flex-1 py-3 rounded-full bg-secondary font-semibold text-sm">
                  Annuler
                </button>
                <button onClick={() => setStep("password")}
                  className="flex-1 py-3 rounded-full bg-destructive text-destructive-foreground font-semibold text-sm flex items-center justify-center gap-2">
                  <Trash2 className="w-4 h-4" /> Continuer
                </button>
              </div>
            </>
          ) : (
            <>
              <div className="text-sm text-muted-foreground">
                Pour confirmer la suppression de votre compte, saisissez votre <strong>mot de passe</strong> :
              </div>

              <div className="relative">
                <input
                  type={showPwd ? "text" : "password"}
                  value={password}
                  onChange={e => { setPassword(e.target.value); setError(""); }}
                  placeholder="Votre mot de passe"
                  autoFocus
                  className={`w-full px-4 py-3 rounded-2xl bg-secondary border outline-none pr-12 text-sm ${error ? "border-destructive" : "border-border"}`}
                  onKeyDown={e => e.key === "Enter" && handleDelete()}
                />
                <button type="button" onClick={() => setShowPwd(!showPwd)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground">
                  {showPwd ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>

              {error && (
                <div className="text-sm text-destructive font-medium flex items-center gap-1.5">
                  <AlertTriangle className="w-4 h-4 shrink-0" /> {error}
                </div>
              )}

              <div className="flex gap-2">
                <button onClick={() => { setStep("warn"); setPassword(""); setError(""); }}
                  className="flex-1 py-3 rounded-full bg-secondary font-semibold text-sm">
                  Retour
                </button>
                <button onClick={handleDelete} disabled={busy || !password.trim()}
                  className="flex-1 py-3 rounded-full bg-destructive text-destructive-foreground font-semibold text-sm flex items-center justify-center gap-2 disabled:opacity-50">
                  {busy ? <span className="animate-spin">⏳</span> : <><Trash2 className="w-4 h-4" /> Supprimer</>}
                </button>
              </div>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
