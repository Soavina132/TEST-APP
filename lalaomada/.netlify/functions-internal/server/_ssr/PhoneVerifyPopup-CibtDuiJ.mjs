import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { a5 as ShieldCheck, X, q as LoaderCircle, P as Phone, r as Send, l as Clock, n as MessageSquare, a1 as Check } from "../_libs/lucide-react.mjs";
function PhoneVerifyPopup({ onClose }) {
  const { profile, refreshProfile } = useAuth();
  const [step, setStep] = reactExports.useState("loading");
  const [phone, setPhone] = reactExports.useState(profile?.phone || "");
  const [code, setCode] = reactExports.useState("");
  const [expiresAt, setExpiresAt] = reactExports.useState(null);
  const [adminPhone, setAdminPhone] = reactExports.useState("");
  const [loading, setLoading] = reactExports.useState(false);
  const [polling, setPolling] = reactExports.useState(false);
  const [countdown, setCountdown] = reactExports.useState("");
  reactExports.useEffect(() => {
    (async () => {
      const { data } = await supabase.from("app_settings").select("admin_phone").limit(1).single();
      if (data?.admin_phone) setAdminPhone(data.admin_phone);
    })();
  }, []);
  reactExports.useEffect(() => {
    (async () => {
      try {
        const { data, error } = await supabase.rpc("get_pending_phone_verification");
        if (error) throw error;
        if (data?.pending && data?.code) {
          setPhone(data.phone || phone);
          setCode(data.code);
          setExpiresAt(data.expires_at);
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
  reactExports.useEffect(() => {
    if (!expiresAt) return;
    const update = () => {
      const expiry = new Date(expiresAt).getTime();
      const now = Date.now();
      const remaining = Math.max(0, Math.floor((expiry - now) / 1e3));
      if (remaining <= 0) {
        setCountdown("Expiré");
        setPolling(false);
        setStep("phone");
        toast.info("Le code a expiré. Veuillez en générer un nouveau.");
        return;
      }
      const min = Math.floor(remaining / 60);
      const sec = remaining % 60;
      setCountdown(`${min}:${sec.toString().padStart(2, "0")}`);
    };
    update();
    const interval = setInterval(update, 1e3);
    return () => clearInterval(interval);
  }, [expiresAt]);
  reactExports.useEffect(() => {
    if (step !== "code" || !polling) return;
    const interval = setInterval(async () => {
      const { data } = await supabase.from("profiles").select("phone_verified").eq("id", profile?.id).single();
      if (data?.phone_verified) {
        setPolling(false);
        setStep("done");
        clearInterval(interval);
        await refreshProfile();
      }
    }, 3e3);
    return () => clearInterval(interval);
  }, [step, polling, profile?.id, refreshProfile]);
  const requestCode = reactExports.useCallback(async () => {
    const trimmed = phone.trim();
    if (!trimmed) return toast.error("Entrez votre numéro");
    if (!/^[0-9+\s-]{8,15}$/.test(trimmed)) return toast.error("Numéro invalide");
    setLoading(true);
    try {
      const { data, error } = await supabase.rpc("request_phone_verification", { _phone: trimmed });
      if (error) throw error;
      const newCode = data;
      setCode(newCode);
      setStep("code");
      setPolling(true);
      const expiry = new Date(Date.now() + 10 * 60 * 1e3);
      setExpiresAt(expiry.toISOString());
      toast.success("Code généré !");
    } catch (e) {
      toast.error(e?.message || "Erreur");
    } finally {
      setLoading(false);
    }
  }, [phone]);
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[60] flex items-center justify-center bg-black/50 backdrop-blur-sm p-4", onClick: onClose, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "bg-card text-card-foreground rounded-2xl shadow-2xl border border-border w-full max-w-sm p-5 space-y-4 animate-pop-in",
      onClick: (e) => e.stopPropagation(),
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "font-bold text-base flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-5 h-5 text-primary" }),
            "Vérification du numéro"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "text-muted-foreground hover:text-foreground transition", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-5 h-5" }) })
        ] }),
        step === "loading" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-center py-8", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-muted-foreground" }) }),
        step === "phone" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Pour jouer avec mise, vous devez vérifier votre numéro de téléphone." }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Phone, { className: "absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "tel",
                value: phone,
                onChange: (e) => setPhone(e.target.value),
                placeholder: "034 12 345 67",
                className: "w-full pl-10 pr-4 py-2.5 rounded-xl border border-border bg-background text-sm focus:outline-none focus:ring-2 focus:ring-primary",
                onKeyDown: (e) => e.key === "Enter" && requestCode()
              }
            )
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              onClick: requestCode,
              disabled: loading || !phone.trim(),
              className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5",
              children: loading ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4" }),
                " Générer le code"
              ] })
            }
          )
        ] }),
        step === "code" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center space-y-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Votre code de vérification :" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-3xl font-mono font-extrabold text-primary tracking-wider py-2 bg-primary/10 rounded-xl", children: code }),
            countdown && /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground flex items-center justify-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3 h-3" }),
              "Code valable encore ",
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-amber-600 dark:text-amber-400", children: countdown })
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-amber-500/10 border border-amber-500/30 rounded-xl p-3 space-y-1.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs font-semibold text-amber-600 dark:text-amber-400 flex items-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-3.5 h-3.5" }),
              " Envoyez ce code par SMS"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground", children: [
              "Envoyez le code ",
              /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "font-mono", children: code }),
              " par SMS au :"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-bold text-center py-1", children: adminPhone || "0385708218" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground text-center", children: "(coût d'un SMS normal, selon votre opérateur)" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-xs text-muted-foreground", children: polling ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center justify-center gap-1.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-3.5 h-3.5 animate-spin" }),
            "En attente de vérification..."
          ] }) : "En attente de validation par l'admin" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              onClick: () => {
                setStep("phone");
                setPolling(false);
              },
              className: "w-full py-2 rounded-xl border border-border text-xs text-muted-foreground hover:bg-accent transition",
              children: "Changer de numéro"
            }
          )
        ] }),
        step === "done" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center space-y-3 py-4", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-16 h-16 rounded-full bg-emerald-500/10 flex items-center justify-center mx-auto", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-8 h-8 text-emerald-500" }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-bold text-base", children: "Numéro vérifié !" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Vous pouvez maintenant jouer avec mise." }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              onClick: onClose,
              className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 transition",
              children: "Continuer"
            }
          )
        ] })
      ]
    }
  ) });
}
export {
  PhoneVerifyPopup as P
};
