import { j as jsxRuntimeExports, r as reactExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { E as ExternalLink } from "../_libs/lucide-react.mjs";
const cache = /* @__PURE__ */ new Map();
function extractUrl(text) {
  const m = text.match(/https?:\/\/[^\s"'<>]+/);
  return m ? m[0] : null;
}
const SUPABASE_URL = "https://gifwfjgciwbsottztzoc.supabase.co";
const SUPABASE_ANON_KEY = "sb_publishable_hXK7wUdP8YiU7qFKh7_Cmg_Os0-QzAj";
function usePreview(url) {
  const [meta, setMeta] = reactExports.useState("loading");
  reactExports.useEffect(() => {
    if (!url) {
      setMeta(null);
      return;
    }
    if (cache.has(url)) {
      setMeta(cache.get(url));
      return;
    }
    const ctrl = new AbortController();
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token;
      if (!token) {
        cache.set(url, null);
        setMeta(null);
        return;
      }
      try {
        const r = await fetch(
          `${SUPABASE_URL}/functions/v1/link-preview?url=${encodeURIComponent(url)}`,
          {
            signal: ctrl.signal,
            headers: { Authorization: `Bearer ${token}`, apikey: SUPABASE_ANON_KEY }
          }
        );
        const d = r.ok ? await r.json() : null;
        cache.set(url, d?.title ? d : null);
        setMeta(d?.title ? d : null);
      } catch {
        cache.set(url, null);
        setMeta(null);
      }
    })();
    return () => ctrl.abort();
  }, [url]);
  return meta;
}
function LinkPreviewCard({ text, className = "" }) {
  const url = extractUrl(text);
  const meta = usePreview(url || "");
  if (!url || meta === "loading" || !meta) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "a",
    {
      href: url,
      target: "_blank",
      rel: "noopener noreferrer",
      className: `mt-2 flex gap-3 rounded-xl overflow-hidden border border-white/10 bg-black/20 hover:bg-black/30 transition-colors group no-underline ${className}`,
      onClick: (e) => e.stopPropagation(),
      children: [
        meta.image && /* @__PURE__ */ jsxRuntimeExports.jsx(
          "img",
          {
            src: meta.image,
            alt: "",
            className: "w-20 h-20 object-cover shrink-0",
            onError: (e) => {
              e.currentTarget.style.display = "none";
            }
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col justify-center py-2 pr-3 min-w-0 gap-0.5", children: [
          meta.siteName && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-primary/70 uppercase tracking-wide truncate", children: meta.siteName }),
          meta.title && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-semibold text-foreground truncate leading-snug", children: meta.title }),
          meta.description && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground line-clamp-2 leading-snug", children: meta.description }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1 text-[10px] text-muted-foreground/60 mt-0.5 truncate", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(ExternalLink, { className: "w-2.5 h-2.5 shrink-0" }),
            new URL(url).hostname.replace(/^www\./, "")
          ] })
        ] })
      ]
    }
  );
}
function LinkifyWithPreview({ text, className = "" }) {
  const parts = text.split(/(https?:\/\/[^\s]+)/g);
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className, children: parts.map(
    (p, i) => /^https?:\/\//.test(p) ? /* @__PURE__ */ jsxRuntimeExports.jsx(
      "a",
      {
        href: p,
        target: "_blank",
        rel: "noopener noreferrer",
        className: "underline text-primary break-all",
        children: p
      },
      i
    ) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: p }, i)
  ) });
}
export {
  LinkPreviewCard as L,
  LinkifyWithPreview as a
};
