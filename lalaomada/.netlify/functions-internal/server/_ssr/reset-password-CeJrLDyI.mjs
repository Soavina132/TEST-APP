import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { L as Logo } from "./Header-C01sWVFL.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { k as CircleCheck, L as Lock, a6 as EyeOff, a7 as Eye, q as LoaderCircle } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "../_libs/isbot.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "tslib";
import "../_libs/supabase__functions-js.mjs";
import "./router-CRCBvenY.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
import "../_libs/radix-ui__react-alert-dialog.mjs";
import "../_libs/radix-ui__react-context.mjs";
import "../_libs/radix-ui__react-compose-refs.mjs";
import "../_libs/radix-ui__react-dialog.mjs";
import "../_libs/radix-ui__primitive.mjs";
import "../_libs/radix-ui__react-id.mjs";
import "../_libs/@radix-ui/react-use-layout-effect+[...].mjs";
import "../_libs/@radix-ui/react-use-controllable-state+[...].mjs";
import "../_libs/@radix-ui/react-use-effect-event+[...].mjs";
import "../_libs/@radix-ui/react-dismissable-layer+[...].mjs";
import "../_libs/radix-ui__react-primitive.mjs";
import "../_libs/radix-ui__react-slot.mjs";
import "../_libs/@radix-ui/react-use-callback-ref+[...].mjs";
import "../_libs/radix-ui__react-focus-scope.mjs";
import "../_libs/radix-ui__react-portal.mjs";
import "../_libs/radix-ui__react-presence.mjs";
import "../_libs/radix-ui__react-focus-guards.mjs";
import "../_libs/react-remove-scroll.mjs";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/ai-sdk__openai-compatible.mjs";
import "../_libs/ai-sdk__provider.mjs";
import "../_libs/ai-sdk__provider-utils.mjs";
import "../_libs/eventsource-parser.mjs";
import "../_libs/zod.mjs";
import "../_libs/ai.mjs";
import "../_libs/ai-sdk__gateway.mjs";
import "../_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "../_libs/opentelemetry__api.mjs";
import "./WalletButton-BwZT8Njg.mjs";
function ResetPasswordPage() {
  const navigate = useNavigate();
  const [pw, setPw] = reactExports.useState("");
  const [confirm, setConfirm] = reactExports.useState("");
  const [showPw, setShowPw] = reactExports.useState(false);
  const [busy, setBusy] = reactExports.useState(false);
  const [done, setDone] = reactExports.useState(false);
  const [hasSession, setHasSession] = reactExports.useState(false);
  reactExports.useEffect(() => {
    supabase.auth.getSession().then(({
      data: {
        session
      }
    }) => {
      if (!session) {
        navigate({
          to: "/login",
          replace: true
        });
      } else {
        setHasSession(true);
      }
    });
  }, [navigate]);
  const onSubmit = async (e) => {
    e.preventDefault();
    if (pw.length < 8) return toast.error("Mot de passe : 8 caractères minimum");
    if (pw !== confirm) return toast.error("Les mots de passe ne correspondent pas");
    setBusy(true);
    try {
      const {
        error
      } = await supabase.auth.updateUser({
        password: pw
      });
      if (error) throw error;
      setDone(true);
      toast.success("Mot de passe réinitialisé !");
    } catch (err) {
      toast.error(err?.message || "Erreur");
    } finally {
      setBusy(false);
    }
  };
  if (!hasSession && !done) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "min-h-[100dvh] bg-background flex items-center justify-center px-4 py-6", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full max-w-md", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center mb-8", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Logo, {}),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-bold text-foreground mt-3", children: "Lalao MADA" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-card border border-border rounded-2xl shadow-sm p-6", children: done ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center py-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-auto w-16 h-16 rounded-full bg-emerald-500/15 flex items-center justify-center mb-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-8 h-8 text-emerald-500" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-bold mb-2", children: "Mot de passe réinitialisé !" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground mb-6", children: "Votre nouveau mot de passe est actif. Vous pouvez vous connecter." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: async () => {
        await supabase.auth.signOut();
        navigate({
          to: "/login",
          replace: true
        });
      }, className: "w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all", style: {
        background: "var(--gradient-primary)"
      }, children: "Se connecter" })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center mb-6", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-auto w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center mb-3", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-7 h-7 text-primary" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-lg font-bold", children: "Nouveau mot de passe" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground mt-1", children: "Choisissez un nouveau mot de passe (8 caractères minimum)" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("form", { onSubmit, className: "space-y-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: showPw ? "text" : "password", value: pw, onChange: (e) => setPw(e.target.value), placeholder: "Nouveau mot de passe", autoComplete: "new-password", autoFocus: true, className: "w-full pl-10 pr-10 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => setShowPw((v) => !v), className: "absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground", children: showPw ? /* @__PURE__ */ jsxRuntimeExports.jsx(EyeOff, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-4 h-4" }) })
          ] }),
          pw.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1.5 px-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1", children: [0, 1, 2, 3, 4, 5, 6, 7].map((i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-1 flex-1 rounded-full transition-colors " + (i < pw.length ? pw.length >= 8 ? "bg-emerald-500" : "bg-amber-500" : "bg-muted") }, i)) }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs mt-1 " + (pw.length >= 8 ? "text-emerald-500" : "text-amber-500"), children: pw.length >= 8 ? "Mot de passe valide" : `${pw.length}/8 caractères` })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "absolute left-3.5 top-1/2 -translate-y-1/2 w-4 h-4 text-muted-foreground pointer-events-none" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: showPw ? "text" : "password", value: confirm, onChange: (e) => setConfirm(e.target.value), placeholder: "Confirmer le mot de passe", autoComplete: "new-password", className: "w-full pl-10 pr-3 py-3 bg-background border border-border rounded-xl text-base sm:text-sm outline-none focus:border-primary focus:ring-2 focus:ring-primary/20 transition-colors" }),
          confirm.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute right-3 top-1/2 -translate-y-1/2", children: confirm === pw ? /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4 text-emerald-500" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs text-destructive", children: "✗" }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { type: "submit", disabled: busy || pw.length < 8 || pw !== confirm, className: "w-full py-3.5 rounded-xl text-white font-bold text-sm shadow-md active:scale-[.98] transition-all disabled:opacity-60 flex items-center justify-center gap-2", style: {
          background: "var(--gradient-primary)"
        }, children: [
          busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4" }),
          "Réinitialiser"
        ] })
      ] })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-center text-[11px] text-muted-foreground mt-6", children: [
      "© ",
      (/* @__PURE__ */ new Date()).getFullYear(),
      " Lalao MADA · 100% Malagasy 🇲🇬"
    ] })
  ] }) });
}
export {
  ResetPasswordPage as component
};
