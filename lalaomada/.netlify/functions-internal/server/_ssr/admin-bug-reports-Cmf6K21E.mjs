import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { u as useAuth } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { A as AdminSecurityGate } from "./AdminSecurityGate-qEPUSi9Y.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { z as Bug, ab as RefreshCw, h as ChevronDown, s as CircleX, k as CircleCheck, T as TriangleAlert, l as Clock } from "../_libs/lucide-react.mjs";
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
const STATUS_CFG = {
  open: {
    label: "Ouvert",
    color: "bg-amber-100 text-amber-700",
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3.5 h-3.5" })
  },
  in_progress: {
    label: "En cours",
    color: "bg-blue-100 text-blue-700",
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(TriangleAlert, { className: "w-3.5 h-3.5" })
  },
  resolved: {
    label: "Résolu",
    color: "bg-emerald-100 text-emerald-700",
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-3.5 h-3.5" })
  },
  closed: {
    label: "Fermé",
    color: "bg-secondary text-muted-foreground",
    icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleX, { className: "w-3.5 h-3.5" })
  }
};
const CAT = {
  bug: "🐛 Tech",
  payment: "💳 Paiement",
  game: "🎮 Jeu",
  suggestion: "💡 Suggestion",
  general: "📝 Autre"
};
function StatusBadge({
  status
}) {
  const s = STATUS_CFG[status] ?? STATUS_CFG.open;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold ${s.color}`, children: [
    s.icon,
    " ",
    s.label
  ] });
}
function AdminBugReports() {
  const {
    isAdmin
  } = useAuth();
  const [reports, setReports] = reactExports.useState([]);
  const [filter, setFilter] = reactExports.useState("open");
  const [loading, setLoading] = reactExports.useState(false);
  const [updating, setUpdating] = reactExports.useState(null);
  const [noteEdits, setNoteEdits] = reactExports.useState({});
  const load = async () => {
    setLoading(true);
    const {
      data
    } = await supabase.rpc("admin_list_bug_reports", {
      _status: filter === "all" ? null : filter,
      _limit: 100
    });
    setReports(data || []);
    setLoading(false);
  };
  reactExports.useEffect(() => {
    if (isAdmin) load();
  }, [isAdmin, filter]);
  async function updateStatus(id, status, note) {
    setUpdating(id);
    await supabase.rpc("admin_update_bug_report", {
      _id: id,
      _status: status,
      _admin_note: noteEdits[id] ?? null
    });
    setUpdating(null);
    toast.success("Mis à jour");
    load();
  }
  if (!isAdmin) return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-destructive font-bold", children: "Accès refusé" });
  const openCount = reports.filter((r) => r.status === "open").length;
  return /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSecurityGate, { children: /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto px-4 py-6 space-y-5", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between flex-wrap gap-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h1", { className: "text-2xl font-extrabold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Bug, { className: "w-6 h-6 text-primary" }),
        " Signalements",
        openCount > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "ml-1 px-2 py-0.5 rounded-full bg-destructive text-white text-sm font-bold", children: openCount })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: load, title: "Rafraîchir", className: "p-2 rounded-full hover:bg-accent", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: `w-4 h-4 ${loading ? "animate-spin" : ""}` }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("a", { href: "/admin", className: "text-xs px-3 py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold", children: "← Admin" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 flex-wrap", children: ["all", "open", "in_progress", "resolved", "closed"].map((s) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setFilter(s), className: `px-3 py-1.5 rounded-full text-xs font-bold transition-colors ${filter === s ? "bg-primary text-primary-foreground" : "bg-secondary hover:bg-accent"}`, children: s === "all" ? "Tous" : STATUS_CFG[s]?.label ?? s }, s)) }),
    loading && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-10", children: "Chargement…" }),
    !loading && reports.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center py-16 text-muted-foreground", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Bug, { className: "w-10 h-10 mx-auto mb-3 opacity-30" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-medium", children: "Aucun signalement" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-3", children: reports.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-2xl border border-border/60 p-4 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2 flex-wrap", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 flex-wrap", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-sm", children: r.pseudo ?? "Joueur" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs bg-secondary px-2 py-0.5 rounded-full", children: CAT[r.category] ?? r.category }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(StatusBadge, { status: r.status })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs text-muted-foreground whitespace-nowrap", children: new Date(r.created_at).toLocaleString("fr-FR", {
          day: "2-digit",
          month: "2-digit",
          year: "2-digit",
          hour: "2-digit",
          minute: "2-digit"
        }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm bg-secondary rounded-xl px-4 py-3 whitespace-pre-wrap break-words", children: r.message }),
      r.admin_note && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300 rounded-xl px-3 py-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold", children: "Note admin : " }),
        r.admin_note
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 flex-wrap items-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "text", placeholder: "Note admin (optionnel)…", value: noteEdits[r.id] ?? r.admin_note ?? "", onChange: (e) => setNoteEdits((prev) => ({
          ...prev,
          [r.id]: e.target.value
        })), className: "flex-1 min-w-[140px] bg-secondary rounded-xl px-3 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-primary/40" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("select", { value: r.status, disabled: updating === r.id, onChange: (e) => updateStatus(r.id, e.target.value), className: "appearance-none bg-secondary rounded-xl px-3 py-1.5 text-xs font-semibold cursor-pointer pr-8 focus:outline-none focus:ring-2 focus:ring-primary/40 disabled:opacity-50", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "open", children: "Ouvert" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "in_progress", children: "En cours" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "resolved", children: "Résolu" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "closed", children: "Fermé" })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronDown, { className: "absolute right-2 top-1/2 -translate-y-1/2 w-3 h-3 pointer-events-none text-muted-foreground" })
        ] })
      ] })
    ] }, r.id)) })
  ] }) });
}
export {
  AdminBugReports as component
};
