import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";

export default function TermsModal() {
  const { profile, refreshProfile, user } = useAuth();
  const [terms, setTerms] = useState<string>("");
  const [accepted, setAccepted] = useState(false);
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    supabase.from("app_settings").select("terms_text").eq("id", 1).maybeSingle().then(({ data }) => {
      setTerms((data?.terms_text as string) || "");
    });
  }, []);

  if (!user || !profile) return null;
  if (profile.terms_accepted_at) return null;
  if (!terms.trim()) return null;

  const accept = async () => {
    if (!accepted) return;
    setBusy(true);
    const { error } = await supabase.rpc("accept_terms" as any);
    setBusy(false);
    if (error) return toast.error(error.message);
    await refreshProfile();
  };

  return (
    <div className="fixed inset-0 z-[60] bg-black/70 flex items-center justify-center p-4">
      <div className="bg-card rounded-3xl w-full max-w-lg max-h-[85vh] flex flex-col">
        <div className="p-5 border-b border-border">
          <div className="text-xl font-extrabold">Conditions d'utilisation</div>
          <div className="text-xs text-muted-foreground">Veuillez lire et accepter pour continuer.</div>
        </div>
        <div className="flex-1 overflow-y-auto p-5 text-sm whitespace-pre-wrap leading-relaxed">{terms}</div>
        <div className="p-5 border-t border-border space-y-3">
          <label className="flex items-start gap-2 text-sm">
            <input type="checkbox" checked={accepted} onChange={e => setAccepted(e.target.checked)} className="mt-0.5" />
            <span>J'ai lu et j'accepte les conditions d'utilisation.</span>
          </label>
          <button onClick={accept} disabled={!accepted || busy}
            className="w-full py-3 rounded-full bg-primary text-primary-foreground font-bold disabled:opacity-50">
            {busy ? "..." : "Accepter et continuer"}
          </button>
        </div>
      </div>
    </div>
  );
}
