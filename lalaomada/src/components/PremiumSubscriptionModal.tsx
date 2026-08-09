import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { Crown, Check, Gamepad2 } from "lucide-react";

const TIERS = [
  {
    id: "basic",
    label: "Basic",
    price: 1000,
    matches: 10,
    color: "#3b82f6",
    gradient: "from-blue-500 to-blue-600",
  },
  {
    id: "standard",
    label: "Standard",
    price: 2000,
    matches: 200,
    color: "#8b5cf6",
    gradient: "from-violet-500 to-violet-600",
  },
  {
    id: "premium",
    label: "Premium",
    price: 5000,
    matches: 500,
    color: "#f59e0b",
    gradient: "from-amber-500 to-orange-600",
  },
] as const;

export default function PremiumSubscriptionModal({
  open, onClose,
}: { open: boolean; onClose: () => void }) {
  const { profile, refreshProfile } = useAuth();
  const [loading, setLoading] = useState(false);
  const [selectedTier, setSelectedTier] = useState<string>("basic");

  const tier = TIERS.find((t) => t.id === selectedTier)!;
  const balance = Number(profile?.balance_ar || 0);
  const canAfford = balance >= tier.price;

  const subscribe = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc("subscribe_premium" as any, {
        p_months: 1, p_tier: selectedTier,
      } as any);
      if (error) throw error;
      if (data && !data.success) {
        toast.error(data.error || "Échec de l'abonnement");
        return;
      }
      toast.success("Abonnement activé ! 🎉", {
        description: `${tier.label} — ${tier.matches} parties ce mois`,
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
            <Crown className="w-5 h-5 text-amber-500" /> Abonnement
          </DialogTitle>
        </DialogHeader>

        <div className="space-y-3 pt-2">
          {/* Tier selector */}
          <div className="space-y-2">
            {TIERS.map((t) => {
              const selected = selectedTier === t.id;
              const affordable = balance >= t.price;
              return (
                <button
                  key={t.id}
                  onClick={() => setSelectedTier(t.id)}
                  className={`w-full rounded-2xl p-3.5 text-left transition-all border-2 ${
                    selected
                      ? "border-primary shadow-md"
                      : "border-border/40 hover:border-primary/30"
                  }`}
                  style={selected ? { background: `linear-gradient(135deg, ${t.color}15, transparent)` } : {}}
                >
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2">
                      <div
                        className="w-8 h-8 rounded-xl flex items-center justify-center text-white text-xs font-bold"
                        style={{ background: t.color }}
                      >
                        {t.label[0]}
                      </div>
                      <div>
                        <div className="font-bold text-sm">{t.label}</div>
                        <div className="text-[10px] text-muted-foreground">
                          {t.matches} parties / mois
                        </div>
                      </div>
                    </div>
                    <div className="text-right">
                      <div className="font-black text-base">{t.price.toLocaleString("fr-FR")}</div>
                      <div className="text-[10px] text-muted-foreground">Ar/mois</div>
                    </div>
                  </div>
                  {selected && (
                    <div className="mt-2 pt-2 border-t border-border/30 flex items-center gap-1.5">
                      <Check className="w-3 h-3 text-emerald-500" />
                      <span className="text-[11px] text-muted-foreground">
                        + toutes les fonctionnalités gratuites incluses
                      </span>
                    </div>
                  )}
                </button>
              );
            })}
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
            <span className="font-bold">{tier.price.toLocaleString("fr-FR")} Ar</span>
          </div>

          {/* CTA */}
          <button onClick={subscribe} disabled={loading || !canAfford}
            className="w-full py-3.5 rounded-xl font-bold text-sm flex items-center justify-center gap-2 transition-all active:scale-[0.98] disabled:opacity-50 text-white"
            style={{ background: `linear-gradient(135deg, ${tier.color}, ${tier.color}dd)` }}>
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
