import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { D as Dialog, a as DialogContent, b as DialogHeader, c as DialogTitle } from "./dialog-BkiCxqYs.mjs";
import { ay as Crown, a1 as Check } from "../_libs/lucide-react.mjs";
const TIERS = [
  {
    id: "free",
    label: "Gratuit",
    price: 0,
    matches: 5,
    period: "jour/jeu",
    color: "#6b7280"
  },
  {
    id: "starter",
    label: "Starter",
    price: 500,
    matches: 50,
    period: "mois",
    color: "#10b981"
  },
  {
    id: "basic",
    label: "Basic",
    price: 1e3,
    matches: 100,
    period: "mois",
    color: "#3b82f6"
  },
  {
    id: "standard",
    label: "Standard",
    price: 2e3,
    matches: 200,
    period: "mois",
    color: "#8b5cf6"
  },
  {
    id: "premium",
    label: "Premium",
    price: 5e3,
    matches: 500,
    period: "mois",
    color: "#f59e0b"
  }
];
function PremiumSubscriptionModal({
  open,
  onClose
}) {
  const { profile, refreshProfile } = useAuth();
  const [loading, setLoading] = reactExports.useState(false);
  const [selectedTier, setSelectedTier] = reactExports.useState("starter");
  const tier = TIERS.find((t) => t.id === selectedTier);
  const balance = Number(profile?.balance_ar || 0);
  const canAfford = balance >= tier.price;
  const subscribe = async () => {
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc("subscribe_premium", {
        p_months: 1,
        p_tier: selectedTier
      });
      if (error) throw error;
      if (data && !data.success) {
        toast.error(data.error || "Échec de l'abonnement");
        return;
      }
      toast.success("Abonnement activé ! 🎉", {
        description: `${tier.label} - ${tier.matches} parties/${tier.period}`,
        duration: 5e3
      });
      refreshProfile();
      onClose();
    } catch (e) {
      toast.error(e.message || "Erreur lors de l'abonnement");
    } finally {
      setLoading(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Dialog, { open, onOpenChange: (v) => !v && onClose(), children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogContent, { className: "max-w-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(DialogHeader, { children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogTitle, { className: "flex items-center gap-2 justify-center", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-5 h-5 text-amber-500" }),
      " Abonnement"
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3 pt-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: TIERS.map((t) => {
        const isFree = t.id === "free";
        const selected = selectedTier === t.id;
        balance >= t.price;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => !isFree && setSelectedTier(t.id),
            className: `w-full rounded-2xl p-3.5 text-left transition-all border-2 ${isFree ? "border-border/20 opacity-70" : selected ? "border-primary shadow-md" : "border-border/40 hover:border-primary/30"}`,
            style: selected ? { background: `linear-gradient(135deg, ${t.color}15, transparent)` } : {},
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(
                    "div",
                    {
                      className: "w-8 h-8 rounded-xl flex items-center justify-center text-white text-xs font-bold",
                      style: { background: t.color },
                      children: t.label[0]
                    }
                  ),
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
                    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: t.label }),
                    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground", children: [
                      t.matches,
                      " parties / ",
                      t.period
                    ] })
                  ] })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-black text-base", children: t.price.toLocaleString("fr-FR") }),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: t.price === 0 ? "Gratuit" : "Ar/mois" })
                ] })
              ] }),
              selected && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-2 pt-2 border-t border-border/30 flex items-center gap-1.5", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3 h-3 text-emerald-500" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] text-muted-foreground", children: tier.id === "free" ? "Plan actuel par defaut" : `+ ${tier.matches} parties par ${tier.period}` })
              ] })
            ]
          },
          t.id
        );
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-xs rounded-lg bg-secondary/60 px-3 py-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground", children: "Votre solde" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `font-bold ${canAfford ? "text-emerald-600" : "text-destructive"}`, children: [
          balance.toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-xs rounded-lg bg-secondary/60 px-3 py-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground", children: "Total à payer" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-bold", children: [
          tier.price.toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: subscribe,
          disabled: loading || !canAfford,
          className: "w-full py-3.5 rounded-xl font-bold text-sm flex items-center justify-center gap-2 transition-all active:scale-[0.98] disabled:opacity-50 text-white",
          style: { background: `linear-gradient(135deg, ${tier.color}, ${tier.color}dd)` },
          children: loading ? "…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-4 h-4" }),
            canAfford ? "S'abonner maintenant" : "Solde insuffisant"
          ] })
        }
      ),
      !canAfford && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-center text-muted-foreground", children: "Rechargez votre solde pour vous abonner" })
    ] })
  ] }) });
}
export {
  PremiumSubscriptionModal as P
};
