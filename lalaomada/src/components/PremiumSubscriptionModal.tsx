import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Crown, Check, Gamepad2, Trophy } from "lucide-react";

export default function PremiumSubscriptionModal({
  open, onClose,
}: { open: boolean; onClose: () => void }) {
  const { profile, refreshProfile } = useAuth();
  const [loading, setLoading] = useState(false);
  const [months, setMonths] = useState(1);

  const PRICE = 10000;
  const total = PRICE * months;
  const balance = Number(profile?.balance_ar || 0);
  const canAfford = balance >= total;

  const subscribe = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc("subscribe_premium" as any, {
        p_months: months, p_tier: "premium",
      } as any);
      if (error) throw error;
      if (data && !data.success) {
        toast.error(data.error || "Échec de l'abonnement");
        return;
      }
      toast.success("Abonnement activé ! 🎉", {
        description: `Premium — ${months} mois — ${data?.tournament_passes || 2} accès tournoi offerts`,
        duration: 5000,
      });
      refreshProfile();
      onClose();
    } catch (e: any) {
      toast.error(e.message || "Erreur lors de l'abonnement");
    } finally {
      setLoading(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2 justify-center">
            <Crown className="w-5 h-5 text-amber-500" /> Abonnement Premium
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-4 pt-2">
          {/* Price card */}
          <div className="rounded-2xl p-4 text-center border-2 border-amber-500/40 bg-gradient-to-br from-amber-500/10 via-card to-primary/10">
            <Crown className="w-8 h-8 mx-auto text-amber-500 mb-2" />
            <div className="text-lg font-extrabold">Premium</div>
            <div className="text-3xl font-black text-amber-500 mt-1">
              {PRICE.toLocaleString("fr-FR")} <span className="text-base font-bold">Ar/mois</span>
            </div>
          </div>

          {/* Benefits */}
          <div className="space-y-2 rounded-xl bg-amber-500/10 border border-amber-500/20 p-3">
            <div className="text-sm font-bold text-amber-600">Avantages Premium</div>
            <div className="space-y-1.5">
              <div className="flex items-start gap-2 text-xs">
                <Gamepad2 className="w-3.5 h-3.5 text-emerald-500 shrink-0 mt-0.5" />
                <span>100 matchs par jeu par mois (Ludo, Domino, Échecs, Fanorona, Rami, Poker)</span>
              </div>
              <div className="flex items-start gap-2 text-xs">
                <Trophy className="w-3.5 h-3.5 text-emerald-500 shrink-0 mt-0.5" />
                <span>2 accès gratuits aux tournois par mois</span>
              </div>
              <div className="flex items-start gap-2 text-xs">
                <Check className="w-3.5 h-3.5 text-emerald-500 shrink-0 mt-0.5" />
                <span>Badge Premium exclusif 👑</span>
              </div>
              <div className="flex items-start gap-2 text-xs">
                <Check className="w-3.5 h-3.5 text-emerald-500 shrink-0 mt-0.5" />
                <span>Plus de limite quotidienne de 5 parties gratuites</span>
              </div>
            </div>
          </div>

          {/* Duration selector */}
          <div className="grid grid-cols-3 gap-2">
            {[1, 3, 6].map(m => (
              <button key={m} onClick={() => setMonths(m)}
                className={`rounded-xl py-2.5 text-center transition-all border ${
                  months === m
                    ? "bg-primary text-primary-foreground border-primary shadow-md shadow-primary/20"
                    : "bg-secondary border-border/40 hover:bg-accent/30"
                }`}>
                <div className="text-sm font-bold">{m} mois</div>
                <div className="text-[10px] opacity-80">{(PRICE * m).toLocaleString("fr-FR")} Ar</div>
              </button>
            ))}
          </div>

          {/* Balance + total */}
          <div className="flex items-center justify-between text-xs rounded-lg bg-secondary/60 px-3 py-2">
            <span className="text-muted-foreground">Votre solde</span>
            <span className={`font-bold ${canAfford ? "text-emerald-600" : "text-destructive"}`}>
              {balance.toLocaleString("fr-FR")} Ar
            </span>
          </div>
          <div className="flex items-center justify-between text-xs rounded-lg bg-secondary/60 px-3 py-2">
            <span className="text-muted-foreground">Total à payer</span>
            <span className="font-bold">{total.toLocaleString("fr-FR")} Ar</span>
          </div>

          {/* CTA */}
          <button onClick={subscribe} disabled={loading || !canAfford}
            className="w-full py-3.5 rounded-xl font-bold text-sm flex items-center justify-center gap-2 transition-all active:scale-[0.98] disabled:opacity-50 text-white"
            style={{ background: "linear-gradient(135deg, #f59e0b, #d97706)" }}>
            {loading ? "…" : (
              <>
                <Crown className="w-4 h-4" />
                {canAfford ? "S'abonner maintenant" : "Solde insuffisant"}
              </>
            )}
          </button>
          {!canAfford && (
            <p className="text-[11px] text-center text-muted-foreground">
              Rechargez votre solde pour vous abonner
            </p>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}
