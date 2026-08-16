import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState, FormEvent, useEffect } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Lock, Eye, EyeOff, Loader2, CheckCircle2 } from "lucide-react";
import { Logo } from "@/components/layout/Header";

export const Route = createFileRoute("/reset-password")({
  component: ResetPasswordPage,
  head: () => ({
    meta: [
      { title: "Réinitialiser le mot de passe — Lalao MADA" },
    ],
  }),
});

function ResetPasswordPage() {
  const navigate = useNavigate();
  const [pw, setPw] = useState("");
  const [confirm, setConfirm] = useState("");
  const [showPw, setShowPw] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState(false);
  const [hasSession, setHasSession] = useState(false);

  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      if (!session) {
        navigate({ to: "/login", search: { ref: undefined }, replace: true });
      } else {
        setHasSession(true);
      }
    });
  }, [navigate]);

  const onSubmit = async (e: FormEvent) => {
    e.preventDefault();
    if (pw.length < 8) return toast.error("Mot de passe : 8 caractères minimum");
    if (pw !== confirm) return toast.error("Les mots de passe ne correspondent pas");
    setBusy(true);
    try {
      const { error } = await supabase.auth.updateUser({ password: pw });
      if (error) throw error;
      setDone(true);
      toast.success("Mot de passe réinitialisé !");
    } catch (err: any) {
      toast.error(err?.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };

  if (!hasSession && !done) return null;

  return (
    <div className="min-h-[100dvh] bg-background flex items-center justify-center px-4 py-6">
      <div className="w-full max-w-md">
        <div className="flex flex-col items-center mb-8">
          <Logo />
          <h1 className="text-xl font-bold text-foreground mt-3">Lalao MADA</h1>
        </div>

        <div className="bg-card border border-border rounded-2xl shadow-sm p-6">
          {done ? (
            <div className="text-center py-4">
              <div className="mx-auto w-16 h-16 rounded-full bg-emerald-500/15 flex items-center justify-center mb-4">
                <CheckCircle2 className="w-8 h-8 text-emerald-500" />
              </div>
              <h2 className="text-lg font-bold mb-2">Mot de passe réinitialisé !</h2>
              <p className="text-sm text-muted-foreground mb-6">
                Votre nouveau mot de passe est actif. Vous pouvez vous connecter.
              </p>
              <button
                onClick={async () => {
                  await supabase.auth.signOut();
                  navigate({ to: "/login", search: { ref: undefined }, replace: true });
                }}
                className="w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all"
                style={{ background: "var(--gradient-primary)" }}
              >
                Se connecter
              </button>
            </div>
          ) : (
            <>
              <div className="text-center mb-6">
                <div className="mx-auto w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center mb-3">
                  <Lock className="w-7 h-7 text-primary" />
                </div>
                <h2 className="text-lg font-bold">Nouveau mot de passe</h2>
                <p className="text-xs text-muted-foreground mt-1">
                  Choisissez un nouveau mot de passe (8 caractères minimum)
                </p>
              </div>

              <form onSubmit={onSubmit} className="space-y-4">
                <div>
                  <div className="relative">
                    <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" />
                    <input
                      type={showPw ? "text" : "password"}
                      value={pw}
                      onChange={e => setPw(e.target.value)}
                      placeholder="Nouveau mot de passe"
                      autoComplete="new-password"
                      autoFocus
                      className="w-full pl-10 pr-10 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors"
                    />
                    <button
                      type="button"
                      onClick={() => setShowPw(v => !v)}
                      className="absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground"
                    >
                      {showPw ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                    </button>
                  </div>
                  {pw.length > 0 && (
                    <div className="mt-1.5 px-1">
                      <div className="flex gap-1">
                        {[0,1,2,3,4,5,6,7].map(i => (
                          <div key={i} className={"h-1 flex-1 rounded-full transition-colors " + (
                            i < pw.length ? (pw.length >= 8 ? "bg-emerald-500" : "bg-amber-500") : "bg-muted"
                          )} />
                        ))}
                      </div>
                      <p className={"text-xs mt-1 " + (pw.length >= 8 ? "text-emerald-500" : "text-amber-500")}>
                        {pw.length >= 8 ? "Mot de passe valide" : `${pw.length}/8 caractères`}
                      </p>
                    </div>
                  )}
                </div>

                <div className="relative">
                  <Lock className="absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" />
                  <input
                    type={showPw ? "text" : "password"}
                    value={confirm}
                    onChange={e => setConfirm(e.target.value)}
                    placeholder="Confirmer le mot de passe"
                    autoComplete="new-password"
                    className="w-full pl-10 pr-3 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors"
                  />
                  {confirm.length > 0 && (
                    <div className="absolute right-3 top-1/2 -translate-y-1/2">
                      {confirm === pw ? (
                        <CheckCircle2 className="w-4 h-4 text-emerald-500" />
                      ) : (
                        <span className="text-xs text-destructive">✗</span>
                      )}
                    </div>
                  )}
                </div>

                <button
                  type="submit"
                  disabled={busy || pw.length < 8 || pw !== confirm}
                  className="w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all disabled:opacity-60 flex items-center justify-center gap-2"
                  style={{ background: "var(--gradient-primary)" }}
                >
                  {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <CheckCircle2 className="w-4 h-4" />}
                  Réinitialiser
                </button>
              </form>
            </>
          )}
        </div>

        <p className="text-center text-[11px] text-muted-foreground mt-6">
          © {new Date().getFullYear()} Lalao MADA · 100% Malagasy 🇲🇬
        </p>
      </div>
    </div>
  );
}
