import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { L as Link } from "../_libs/tanstack__react-router.mjs";
import { p as purify } from "../_libs/dompurify.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { A as ArrowLeft, a5 as ShieldCheck } from "../_libs/lucide-react.mjs";
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
function ConfidentialitePage() {
  const [html, setHtml] = reactExports.useState("");
  const [loaded, setLoaded] = reactExports.useState(false);
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("privacy_html").eq("id", 1).maybeSingle().then(({
      data
    }) => {
      setHtml(data?.privacy_html || "");
      setLoaded(true);
    });
  }, []);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-2xl mx-auto px-4 py-5 space-y-4 min-h-screen", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/faq", className: "p-2 rounded-full bg-secondary/60 active:scale-90 transition-transform", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-5 h-5 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold", children: "Politique de confidentialité" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card border border-border/40 p-5", children: !loaded ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground", children: "Chargement…" }) : html.trim() ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "prose prose-sm dark:prose-invert max-w-none whitespace-pre-wrap leading-relaxed", dangerouslySetInnerHTML: {
      __html: purify.sanitize(html)
    } }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-8", children: "Le contenu de la politique de confidentialité n'est pas encore disponible." }) })
  ] });
}
export {
  ConfidentialitePage as component
};
