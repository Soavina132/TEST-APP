import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { A as ArrowLeft, x as User, a1 as Check, K as Mail, aL as Moon, aM as Sun } from "../_libs/lucide-react.mjs";
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
import "tslib";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "../_libs/supabase__functions-js.mjs";
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
function getInitialTheme() {
  if (typeof document !== "undefined") {
    const stored = localStorage.getItem("theme");
    if (stored === "dark" || stored === "light") return stored;
  }
  return "dark";
}
function useTheme() {
  const [theme, setTheme] = reactExports.useState(getInitialTheme);
  reactExports.useEffect(() => {
    const root = document.documentElement;
    if (theme === "dark") {
      root.classList.add("dark");
    } else {
      root.classList.remove("dark");
    }
    localStorage.setItem("theme", theme);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) {
      meta.setAttribute("content", theme === "dark" ? "#1a1714" : "#f97316");
    }
  }, [theme]);
  const toggle = () => setTheme((t) => t === "dark" ? "light" : "dark");
  return { theme, toggle, setTheme };
}
function Section({
  icon: Icon,
  title,
  children
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: title })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-4", children })
  ] });
}
function Field({
  label,
  value,
  onChange,
  type = "text",
  placeholder,
  disabled
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground mb-1 block", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type, value, onChange: (e) => onChange(e.target.value), placeholder, disabled, className: "w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 disabled:opacity-50" })
  ] });
}
function Toggle({
  checked,
  onChange,
  label,
  sublabel
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: onChange, className: "w-full flex items-center justify-between p-3.5 rounded-2xl bg-card border border-border/40 hover:bg-accent/30 transition-colors", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9 rounded-xl flex items-center justify-center " + (checked ? "bg-amber-100 text-amber-600" : "bg-indigo-100 text-indigo-600"), children: checked ? /* @__PURE__ */ jsxRuntimeExports.jsx(Moon, { className: "w-5 h-5" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Sun, { className: "w-5 h-5" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-left", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: label }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: sublabel })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "relative w-12 h-6 rounded-full transition-colors " + (checked ? "bg-primary" : "bg-muted"), children: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform " + (checked ? "translate-x-6" : "translate-x-0") }) })
  ] });
}
function ParametresPage() {
  const {
    user,
    profile,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const {
    theme,
    toggle
  } = useTheme();
  const isDark = theme === "dark";
  const [pseudo, setPseudo] = reactExports.useState(profile?.pseudo || "");
  const [email, setEmail] = reactExports.useState(profile?.email || user?.email || "");
  const [savingName, setSavingName] = reactExports.useState(false);
  const [savingEmail, setSavingEmail] = reactExports.useState(false);
  reactExports.useEffect(() => {
    if (profile) {
      setPseudo(profile.pseudo || "");
      setEmail(profile.email || user?.email || "");
    }
  }, [profile?.id, profile?.pseudo, profile?.email]);
  const savePseudo = async () => {
    const trimmed = pseudo.trim();
    if (!trimmed || trimmed.length < 2) return toast.error("Le nom doit faire au moins 2 caracteres");
    setSavingName(true);
    try {
      const {
        error
      } = await supabase.from("profiles").update({
        pseudo: trimmed
      }).eq("id", user.id);
      if (error) throw error;
      await refreshProfile();
      toast.success("Nom mis a jour");
    } catch (e) {
      toast.error(e?.message || "Erreur lors de la mise a jour");
    } finally {
      setSavingName(false);
    }
  };
  const saveEmail = async () => {
    const trimmed = email.trim();
    if (!trimmed || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) return toast.error("Email invalide");
    if (trimmed === (profile?.email || user?.email)) return;
    setSavingEmail(true);
    try {
      const {
        error
      } = await supabase.auth.updateUser({
        email: trimmed
      });
      if (error) throw error;
      await supabase.from("profiles").update({
        email: trimmed
      }).eq("id", user.id);
      await refreshProfile();
      toast.success("Email mis a jour — un e-mail de confirmation a ete envoye");
    } catch (e) {
      toast.error(e?.message || "Erreur lors de la mise a jour");
    } finally {
      setSavingEmail(false);
    }
  };
  const nameChanged = pseudo.trim() !== (profile?.pseudo || "") && pseudo.trim().length >= 2;
  const emailChanged = email.trim() !== (profile?.email || user?.email || "");
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "min-h-screen max-w-md mx-auto px-4 pt-16 pb-28 space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mb-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate({
        to: "/profile",
        search: {}
      }), className: "w-9 h-9 rounded-full bg-secondary/60 flex items-center justify-center active:scale-90 transition", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-5 h-5" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold", children: "Parametres" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: User, title: "Modifier le nom", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Nom affiche", value: pseudo, onChange: setPseudo, placeholder: "Votre nom" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: savePseudo, disabled: !nameChanged || savingName, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5", children: savingName ? "Enregistrement…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-4 h-4" }),
        " Enregistrer"
      ] }) })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: Mail, title: "Modifier l'email", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Adresse e-mail", value: email, onChange: setEmail, type: "email", placeholder: "votre@email.com" }),
      emailChanged && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-amber-600 dark:text-amber-400", children: "Un e-mail de confirmation sera envoye a la nouvelle adresse." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: saveEmail, disabled: !emailChanged || savingEmail, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5", children: savingEmail ? "Enregistrement…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-4 h-4" }),
        " Enregistrer"
      ] }) })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: isDark ? Moon : Sun, title: "Apparence", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Toggle, { checked: isDark, onChange: toggle, label: isDark ? "Mode sombre" : "Mode clair", sublabel: isDark ? "Tap pour passer en mode clair" : "Tap pour passer en mode sombre" }) })
  ] });
}
export {
  ParametresPage as component
};
