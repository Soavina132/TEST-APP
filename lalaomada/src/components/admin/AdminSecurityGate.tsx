import { ReactNode, useState, useEffect } from "react";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { Shield, Lock, Loader2 } from "lucide-react";
import { toast } from "sonner";

/**
 * AdminSecurityGate — sécurité admin avec PIN + lockout.
 * L'admin doit saisir un PIN vérifié côté serveur (admin_verify_pin).
 * 5 tentatives échouées → verrouillage 15 minutes.
 */
export default function AdminSecurityGate({ children }: { children: ReactNode }) {
  const { isAdmin, loading } = useAuth();
  const [verified, setVerified] = useState(false);
  const [pin, setPin] = useState("");
  const [checking, setChecking] = useState(false);
  const [attempts, setAttempts] = useState(0);
  const [lockedUntil, setLockedUntil] = useState<Date | null>(null);
  const [needsPin, setNeedsPin] = useState<boolean | null>(null);

  // Vérifier si un PIN est configuré
  useEffect(() => {
    if (!isAdmin || loading) return;
    (async () => {
      const { data } = await supabase.rpc("admin_verify_pin" as any, { _pin: "" } as any).catch(() => ({ data: null }));
      if (data?.reason === "no_pin_set") {
        // Premier accès: pas de PIN → accès direct (l'admin devrait en définir un)
        setNeedsPin(false);
        setVerified(true);
      } else {
        setNeedsPin(true);
      }
    })();
  }, [isAdmin, loading]);

  const submitPin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (pin.length < 4) return toast.error("PIN trop court (min 4 caractères)");
    if (lockedUntil && lockedUntil > new Date()) {
      return toast.error(`Compte verrouillé jusqu'à ${lockedUntil.toLocaleTimeString("fr-FR")}`);
    }
    setChecking(true);
    try {
      const { data, error } = await supabase.rpc("admin_verify_pin" as any, { _pin: pin } as any);
      if (error) throw error;
      const result = data as any;
      if (result?.ok) {
        setVerified(true);
        setAttempts(0);
        toast.success("Accès admin autorisé");
      } else if (result?.reason === "locked") {
        const until = new Date(result.locked_until);
        setLockedUntil(until);
        toast.error(`Compte verrouillé jusqu'à ${until.toLocaleTimeString("fr-FR")}`);
      } else if (result?.reason === "wrong_pin") {
        setAttempts(result.attempts);
        setPin("");
        toast.error(`PIN incorrect — ${result.remaining} tentative(s) restante(s)`);
      }
    } catch (err: any) {
      toast.error(err.message || "Erreur de vérification");
    } finally {
      setChecking(false);
    }
  };

  if (loading) return null;

  if (!isAdmin) {
    return (
      <main className="min-h-screen flex items-center justify-center p-6">
        <div className="text-center space-y-2">
          <Shield className="w-10 h-10 mx-auto text-muted-foreground" />
          <p className="font-semibold">Accès réservé aux administrateurs</p>
        </div>
      </main>
    );
  }

  if (needsPin && !verified) {
    return (
      <main className="min-h-screen flex items-center justify-center p-6">
        <div className="w-full max-w-sm space-y-6">
          <div className="text-center space-y-3">
            <div className="w-16 h-16 rounded-2xl bg-primary/10 grid place-items-center mx-auto">
              <Lock className="w-8 h-8 text-primary" />
            </div>
            <div>
              <h1 className="text-xl font-bold">Sécurité Admin</h1>
              <p className="text-sm text-muted-foreground">Saisissez votre PIN pour accéder au panneau d'administration</p>
            </div>
          </div>

          {lockedUntil && lockedUntil > new Date() ? (
            <div className="rounded-2xl bg-destructive/10 border border-destructive/20 p-4 text-center space-y-2">
              <Lock className="w-6 h-6 mx-auto text-destructive" />
              <p className="text-sm font-semibold text-destructive">Compte verrouillé</p>
              <p className="text-xs text-muted-foreground">
                Réessayez après {lockedUntil.toLocaleTimeString("fr-FR")}
              </p>
            </div>
          ) : (
            <form onSubmit={submitPin} className="space-y-4">
              <input
                type="password"
                inputMode="numeric"
                value={pin}
                onChange={(e) => setPin(e.target.value)}
                placeholder="••••"
                maxLength={12}
                autoFocus
                className="w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-center text-2xl tracking-[0.5em] font-bold"
              />
              {attempts > 0 && (
                <p className="text-xs text-center text-destructive">
                  {5 - attempts} tentative(s) restante(s) avant verrouillage
                </p>
              )}
              <button
                type="submit"
                disabled={checking || pin.length < 4}
                className="w-full py-3.5 rounded-xl bg-primary text-primary-foreground font-bold disabled:opacity-50 flex items-center justify-center gap-2"
              >
                {checking ? <Loader2 className="w-4 h-4 animate-spin" /> : <Lock className="w-4 h-4" />}
                {checking ? "Vérification…" : "Déverrouiller"}
              </button>
            </form>
          )}
        </div>
      </main>
    );
  }

  return <>{children}</>;
}
