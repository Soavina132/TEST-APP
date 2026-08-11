import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { y as Shield, L as Lock, q as LoaderCircle } from "../_libs/lucide-react.mjs";
function AdminSecurityGate({ children }) {
  const { isAdmin, loading } = useAuth();
  const [verified, setVerified] = reactExports.useState(false);
  const [pin, setPin] = reactExports.useState("");
  const [checking, setChecking] = reactExports.useState(false);
  const [attempts, setAttempts] = reactExports.useState(0);
  const [lockedUntil, setLockedUntil] = reactExports.useState(null);
  const [needsPin, setNeedsPin] = reactExports.useState(null);
  reactExports.useEffect(() => {
    if (!isAdmin || loading) return;
    (async () => {
      let data = null;
      try {
        const res = await supabase.rpc("admin_verify_pin", { _pin: "" });
        data = res.data;
      } catch {
        data = null;
      }
      if (data?.reason === "no_pin_set") {
        setNeedsPin(false);
        setVerified(true);
      } else {
        setNeedsPin(true);
      }
    })();
  }, [isAdmin, loading]);
  const submitPin = async (e) => {
    e.preventDefault();
    if (pin.length < 4) return toast.error("PIN trop court (min 4 caractères)");
    if (lockedUntil && lockedUntil > /* @__PURE__ */ new Date()) {
      return toast.error(`Compte verrouillé jusqu'à ${lockedUntil.toLocaleTimeString("fr-FR")}`);
    }
    setChecking(true);
    try {
      const { data, error } = await supabase.rpc("admin_verify_pin", { _pin: pin });
      if (error) throw error;
      const result = data;
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
    } catch (err) {
      toast.error(err.message || "Erreur de vérification");
    } finally {
      setChecking(false);
    }
  };
  if (loading) return null;
  if (!isAdmin) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "min-h-screen flex items-center justify-center p-6", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Shield, { className: "w-10 h-10 mx-auto text-muted-foreground" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-semibold", children: "Accès réservé aux administrateurs" })
    ] }) });
  }
  if (needsPin && !verified) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "min-h-screen flex items-center justify-center p-6", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full max-w-sm space-y-6", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-16 h-16 rounded-2xl bg-primary/10 grid place-items-center mx-auto", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-8 h-8 text-primary" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-bold", children: "Sécurité Admin" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: "Saisissez votre PIN pour accéder au panneau d'administration" })
        ] })
      ] }),
      lockedUntil && lockedUntil > /* @__PURE__ */ new Date() ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-destructive/10 border border-destructive/20 p-4 text-center space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-6 h-6 mx-auto text-destructive" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm font-semibold text-destructive", children: "Compte verrouillé" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
          "Réessayez après ",
          lockedUntil.toLocaleTimeString("fr-FR")
        ] })
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit: submitPin, className: "space-y-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "input",
          {
            type: "password",
            inputMode: "numeric",
            value: pin,
            onChange: (e) => setPin(e.target.value),
            placeholder: "••••",
            maxLength: 12,
            autoFocus: true,
            className: "w-full px-4 py-3.5 rounded-xl bg-secondary outline-none text-center text-2xl tracking-[0.5em] font-bold"
          }
        ),
        attempts > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-center text-destructive", children: [
          5 - attempts,
          " tentative(s) restante(s) avant verrouillage"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            type: "submit",
            disabled: checking || pin.length < 4,
            className: "w-full py-3.5 rounded-xl bg-primary text-primary-foreground font-bold disabled:opacity-50 flex items-center justify-center gap-2",
            children: [
              checking ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4" }),
              checking ? "Vérification…" : "Déverrouiller"
            ]
          }
        )
      ] })
    ] }) });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children });
}
export {
  AdminSecurityGate as A
};
