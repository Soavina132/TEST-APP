import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { a as LinkifyWithPreview, L as LinkPreviewCard } from "./LinkPreview-BF8xLSR1.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as useT, f as facebookTargets, o as openExternal } from "./router-CRCBvenY.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/sonner.mjs";
import { o as BookOpen, aR as CirclePlay, a4 as FileText } from "../_libs/lucide-react.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "tslib";
import "../_libs/supabase__functions-js.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
import "../_libs/tanstack__react-router.mjs";
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
function TutosPage() {
  const {
    t
  } = useT();
  const [tutos, setTutos] = reactExports.useState([]);
  const [terms, setTerms] = reactExports.useState("");
  const [tutoUrl, setTutoUrl] = reactExports.useState("");
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("tutorials,terms_text,tuto_url").maybeSingle().then(({
      data
    }) => {
      setTutos(data?.tutorials || []);
      setTerms(data?.terms_text || "");
      setTutoUrl(data?.tuto_url || "");
    });
  }, []);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-2xl mx-auto px-4 py-6 space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("h1", { className: "text-2xl font-extrabold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(BookOpen, { className: "text-primary" }),
      " ",
      t("tutos_title_full")
    ] }),
    tutoUrl && (() => {
      const isFb = /facebook\.com|fb\.com/i.test(tutoUrl);
      const target = isFb ? facebookTargets(tutoUrl) : {
        webUrl: tutoUrl
      };
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("a", { href: target.appUrl || target.webUrl, target: "_top", rel: "noopener noreferrer", onClick: (e) => {
        e.preventDefault();
        openExternal(target);
      }, className: "flex items-center justify-center gap-2 w-full rounded-2xl bg-primary text-primary-foreground font-semibold py-3 shadow-sm hover:opacity-90 transition", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-5 h-5" }),
        " TUTO vidéo"
      ] });
    })(),
    tutos.length === 0 && !terms ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-8 text-center text-muted-foreground", children: t("no_content") }) : null,
    tutos.map((t2, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-lg mb-1", children: t2.title || `Tuto ${i + 1}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm whitespace-pre-wrap leading-relaxed", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LinkifyWithPreview, { text: t2.content || "" }) }),
      /https?:\/\//.test(t2.content || "") && /* @__PURE__ */ jsxRuntimeExports.jsx(LinkPreviewCard, { text: t2.content || "", className: "mt-2" })
    ] }, i)),
    terms.trim() && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-lg mb-1 flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(FileText, { className: "w-5 h-5 text-primary" }),
        " ",
        t("terms_of_use")
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm whitespace-pre-wrap leading-relaxed", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LinkifyWithPreview, { text: terms }) })
    ] })
  ] });
}
export {
  TutosPage as component
};
