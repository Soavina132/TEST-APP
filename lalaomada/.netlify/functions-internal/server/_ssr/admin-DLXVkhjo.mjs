import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { N as Navigate, L as Link } from "../_libs/tanstack__react-router.mjs";
import { p as purify } from "../_libs/dompurify.mjs";
import { u as useAuth, b as useConfirm, i as invalidateCmsCache } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { compressImageToWebp } from "./image-compress-U7tauI3l.mjs";
import { A as AdminSecurityGate } from "./AdminSecurityGate-qEPUSi9Y.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { y as Shield, a9 as CloudDownload, aa as UserCheck, ab as RefreshCw, ac as LayoutDashboard, a3 as Wallet, U as Users, G as Gamepad2, n as MessageSquare, ad as Settings, ae as SlidersVertical, w as History, a as Trophy, af as ChartColumn, ag as Pause, r as Send, ah as ImagePlus, I as Info, L as Lock, l as Clock, ai as Monitor, aj as ShieldOff, x as User, Q as LogOut, ak as Search, X, _ as CircleAlert, al as ArrowRight, am as TrendingUp, h as ChevronDown, an as Camera, ao as Trash2, ap as Save, aq as Tag, ar as Image, a2 as Plus, as as ArrowUp, at as ArrowDown, au as RotateCcw, a7 as Eye, a6 as EyeOff, av as Play, k as CircleCheck, H as Hourglass, aw as Timer, S as Swords, q as LoaderCircle, E as ExternalLink, p as ChevronUp } from "../_libs/lucide-react.mjs";
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
function RichTextEditor({
  value,
  onChange,
  placeholder = "Écrivez ici…",
  minHeight = "160px"
}) {
  const ref = reactExports.useRef(null);
  const sanitize = reactExports.useCallback((html) => {
    return purify.sanitize(html || "", {
      ALLOWED_TAGS: ["b", "i", "u", "strong", "em", "br", "ul", "ol", "li", "a", "h2", "h3", "p", "span"],
      ALLOWED_ATTR: ["href", "target", "rel"]
    });
  }, []);
  reactExports.useEffect(() => {
    if (ref.current) {
      const sanitized = sanitize(value);
      if (ref.current.innerHTML !== sanitized) {
        ref.current.innerHTML = sanitized;
      }
    }
  }, [value, sanitize]);
  const exec = (cmd, arg) => {
    document.execCommand(cmd, false, arg);
    if (ref.current) {
      const raw = ref.current.innerHTML;
      const clean = sanitize(raw);
      if (ref.current.innerHTML !== clean) {
        ref.current.innerHTML = clean;
      }
      onChange(clean);
    }
  };
  const addLink = () => {
    const url2 = prompt("URL du lien :", "https://");
    if (url2) exec("createLink", url2);
  };
  const handlePaste = (e) => {
    e.preventDefault();
    const text = e.clipboardData.getData("text/html") || e.clipboardData.getData("text/plain");
    document.execCommand("insertHTML", false, sanitize(text));
    if (ref.current) onChange(sanitize(ref.current.innerHTML));
  };
  const Btn = ({ cmd, label, arg, title }) => /* @__PURE__ */ jsxRuntimeExports.jsx(
    "button",
    {
      type: "button",
      title,
      onClick: () => cmd ? exec(cmd, arg) : addLink(),
      className: "px-2 py-1 rounded text-sm font-semibold hover:bg-accent text-foreground",
      children: label
    }
  );
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-lg border border-border bg-background", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap gap-1 p-1.5 border-b border-border bg-muted/40", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "bold", label: "B", title: "Gras" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "italic", label: "I", title: "Italique" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "underline", label: "U", title: "Souligné" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "formatBlock", arg: "h2", label: "H2", title: "Titre" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "formatBlock", arg: "h3", label: "H3", title: "Sous-titre" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "insertUnorderedList", label: "• Liste", title: "Liste à puces" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "insertOrderedList", label: "1. Liste", title: "Liste numérotée" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { label: "🔗 Lien", title: "Insérer un lien" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Btn, { cmd: "removeFormat", label: "✕ Format", title: "Supprimer le format" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        ref,
        contentEditable: true,
        suppressContentEditableWarning: true,
        "data-placeholder": placeholder,
        onInput: (e) => onChange(sanitize(e.currentTarget.innerHTML)),
        onPaste: handlePaste,
        className: "prose prose-sm max-w-none p-3 focus:outline-none [&[data-placeholder]:empty:before]:content-[attr(data-placeholder)] [&[data-placeholder]:empty:before]:text-muted-foreground",
        style: { minHeight }
      }
    )
  ] });
}
const BADGE_OPTIONS = [
  { value: null, label: "Aucun badge", color: "" },
  { value: "new", label: "🆕 Nouveau", color: "bg-emerald-500/15 text-emerald-700 border-emerald-500/30" },
  { value: "coming_soon", label: "🔜 Bientôt", color: "bg-amber-500/15 text-amber-700 border-amber-500/30" },
  { value: "hot", label: "🔥 Populaire", color: "bg-red-500/15 text-red-700 border-red-500/30" }
];
const BADGE_PILL = {
  new: "bg-emerald-500 text-white",
  coming_soon: "bg-amber-500 text-white",
  hot: "bg-red-500 text-white"
};
const BADGE_LABEL = {
  new: "🆕 Nouveau",
  coming_soon: "🔜 Bientôt",
  hot: "🔥 Populaire"
};
function GameConfigsSection() {
  const [rows, setRows] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(true);
  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase.from("game_configs").select("*").order("display_name");
    if (error) toast.error(error.message);
    setRows(data || []);
    setLoading(false);
  };
  reactExports.useEffect(() => {
    load();
  }, []);
  const update = (slug, patch) => {
    setRows((rs) => rs.map((r) => r.slug === slug ? { ...r, ...patch } : r));
  };
  const save = async (row) => {
    const { error } = await supabase.from("game_configs").update({
      max_turn_skips: row.max_turn_skips,
      rules_markdown: row.rules_markdown,
      cover_url: row.cover_url,
      max_online_capacity: row.max_online_capacity,
      instructions_dismissible: row.instructions_dismissible,
      badge: row.badge
    }).eq("slug", row.slug);
    if (error) return toast.error(error.message);
    toast.success(`${row.display_name} mis à jour`);
  };
  if (loading) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-6 text-center text-muted-foreground", children: "Chargement…" });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 text-sm text-muted-foreground", children: [
      "Configure ici le ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "nombre maximum de tours sautés" }),
      ", le ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "texte des règles" }),
      ", l'",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "image de couverture" }),
      ", la ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "capacité affichée" }),
      " et le ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "badge" }),
      ". Les ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "timers" }),
      " sont centralisés dans l'onglet ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "Config → Timers" }),
      "."
    ] }),
    rows.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3 border border-border/60", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "font-extrabold text-lg", children: [
          r.display_name,
          " ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs text-muted-foreground font-mono", children: [
            "(",
            r.slug,
            ")"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => save(r),
            className: "px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-sm font-bold flex items-center gap-1",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-4 h-4" }),
              " Enregistrer"
            ]
          }
        )
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs font-semibold col-span-2", children: [
          "Tours sautés max (forfait)",
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              type: "number",
              min: 1,
              max: 20,
              value: r.max_turn_skips,
              onChange: (e) => update(r.slug, { max_turn_skips: Number(e.target.value) }),
              className: "mt-1 w-full px-3 py-2 rounded-xl bg-background border border-border"
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground mt-1", children: [
            "⏱️ Les timers (tour + salle d'attente tournoi) sont centralisés dans l'onglet ",
            /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "Config → Timers" }),
            "."
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs font-semibold col-span-2", children: [
          "Capacité affichée (en ligne max)",
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              type: "number",
              min: 1,
              value: r.max_online_capacity,
              onChange: (e) => update(r.slug, { max_online_capacity: Number(e.target.value) }),
              className: "mt-1 w-full px-3 py-2 rounded-xl bg-background border border-border"
            }
          )
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "col-span-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs font-semibold mb-1.5 flex items-center gap-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Tag, { className: "w-3.5 h-3.5" }),
            " Badge affiché sur la page d'accueil"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-2", children: BADGE_OPTIONS.map((opt) => {
            const isActive = r.badge === opt.value;
            const baseClass = "px-3 py-1 rounded-full border text-xs font-bold transition-all";
            const activeClass = isActive ? (opt.color || "bg-muted border-border text-foreground") + " ring-2 ring-offset-1 ring-primary/40" : "bg-muted/50 border-border/40 text-muted-foreground hover:bg-muted";
            return /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                onClick: () => update(r.slug, { badge: opt.value }),
                className: `${baseClass} ${activeClass}`,
                children: opt.label
              },
              String(opt.value)
            );
          }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs font-semibold col-span-2 flex items-center gap-2 mt-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              type: "checkbox",
              checked: r.instructions_dismissible,
              onChange: (e) => update(r.slug, { instructions_dismissible: e.target.checked })
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Instructions masquables par l'utilisateur (le bouton ✕ supprime définitivement le bandeau)" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs font-semibold col-span-2", children: [
          "URL image de couverture",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1 flex gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Image, { className: "w-4 h-4 mt-2.5 text-muted-foreground" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "text",
                value: r.cover_url,
                onChange: (e) => update(r.slug, { cover_url: e.target.value }),
                placeholder: "/covers/cover_ludo.png ou https://…",
                className: "flex-1 px-3 py-2 rounded-xl bg-background border border-border"
              }
            )
          ] }),
          r.cover_url && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-2 relative w-28 rounded-xl overflow-hidden shadow-md border border-border/40", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "img",
              {
                src: r.cover_url,
                alt: "",
                loading: "lazy",
                decoding: "async",
                className: "w-full aspect-[3/4] object-cover"
              }
            ),
            r.badge && BADGE_LABEL[r.badge] && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `absolute top-1.5 right-1.5 text-[9px] font-black px-1.5 py-0.5 rounded-full ${BADGE_PILL[r.badge]}`, children: BADGE_LABEL[r.badge] })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs font-semibold col-span-2", children: [
          "Règles / Instructions (Markdown)",
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "textarea",
            {
              value: r.rules_markdown,
              onChange: (e) => update(r.slug, { rules_markdown: e.target.value }),
              rows: 5,
              className: "mt-1 w-full px-3 py-2 rounded-xl bg-background border border-border font-mono text-xs"
            }
          )
        ] })
      ] })
    ] }, r.slug))
  ] });
}
const PRESETS = [15, 30, 45, 60, 90, 120, 180];
function GameTimersQuick() {
  const [rows, setRows] = reactExports.useState([]);
  const [app, setApp] = reactExports.useState(null);
  const [loading, setLoading] = reactExports.useState(true);
  const [savingSlug, setSavingSlug] = reactExports.useState(null);
  const [savingApp, setSavingApp] = reactExports.useState(false);
  const load = async () => {
    setLoading(true);
    const [{ data: gc, error: e1 }, { data: s, error: e2 }] = await Promise.all([
      supabase.from("game_configs").select("slug,display_name,turn_timer_seconds,tournament_join_timeout_secs").order("display_name"),
      supabase.from("app_settings").select("*").eq("id", 1).maybeSingle()
    ]);
    if (e1) toast.error(e1.message);
    if (e2) toast.error(e2.message);
    setRows(gc || []);
    if (s) {
      setApp({
        ready_timeout_seconds: Number(s.ready_timeout_seconds) || 60,
        turn_seconds: Number(s.turn_seconds) || 30,
        game_invite_timeout_minutes: Number(s.game_invite_timeout_minutes) || 6,
        chess_global_timer_enabled: !!s.chess_global_timer_enabled,
        chess_global_timer_minutes: Number(s.chess_global_timer_minutes) || 10,
        fanorona_global_timer_enabled: !!s.fanorona_global_timer_enabled,
        fanorona_global_timer_minutes: Number(s.fanorona_global_timer_minutes) || 10
      });
    }
    setLoading(false);
  };
  reactExports.useEffect(() => {
    load();
  }, []);
  const setValue = (slug, patch) => setRows((rs) => rs.map((r) => r.slug === slug ? { ...r, ...patch } : r));
  const save = async (row) => {
    setSavingSlug(row.slug);
    const v = Math.max(5, Math.min(600, Math.round(row.turn_timer_seconds || 0)));
    const jt = Math.max(60, Math.min(1800, Math.round(row.tournament_join_timeout_secs || 240)));
    const { error } = await supabase.from("game_configs").update({ turn_timer_seconds: v, tournament_join_timeout_secs: jt }).eq("slug", row.slug);
    setSavingSlug(null);
    if (error) return toast.error(error.message);
    toast.success(`⏱️ ${row.display_name} : ${v}s / tour • ${Math.round(jt / 60)} min salle`);
  };
  const saveApp = async () => {
    if (!app) return;
    setSavingApp(true);
    const { error } = await supabase.from("app_settings").update({
      ready_timeout_seconds: app.ready_timeout_seconds,
      turn_seconds: app.turn_seconds,
      game_invite_timeout_minutes: app.game_invite_timeout_minutes,
      chess_global_timer_enabled: app.chess_global_timer_enabled,
      chess_global_timer_minutes: app.chess_global_timer_minutes,
      fanorona_global_timer_enabled: app.fanorona_global_timer_enabled,
      fanorona_global_timer_minutes: app.fanorona_global_timer_minutes
    }).eq("id", 1);
    setSavingApp(false);
    if (error) return toast.error(error.message);
    toast.success("⏱️ Timers globaux enregistrés");
  };
  if (loading) {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Chargement…" });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    app && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] border border-border/60 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-4 h-4 text-primary" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "🌐 Timers globaux (toutes les parties)" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: saveApp,
            disabled: savingApp,
            className: "px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-bold flex items-center gap-1 disabled:opacity-50",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-3.5 h-3.5" }),
              " ",
              savingApp ? "…" : "Enregistrer"
            ]
          }
        )
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold", children: [
          "Salle d'attente (min)",
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              type: "number",
              min: 1,
              max: 30,
              value: app.game_invite_timeout_minutes,
              onChange: (e) => setApp({ ...app, game_invite_timeout_minutes: Number(e.target.value) }),
              className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono"
            }
          )
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold", children: [
          'Délai "Prêt" (s)',
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              type: "number",
              min: 10,
              max: 600,
              value: app.ready_timeout_seconds,
              onChange: (e) => setApp({ ...app, ready_timeout_seconds: Number(e.target.value) }),
              className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono"
            }
          )
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold col-span-2", children: [
          "Durée d'un tour par défaut (s)",
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              type: "number",
              min: 5,
              max: 600,
              value: app.turn_seconds,
              onChange: (e) => setApp({ ...app, turn_seconds: Number(e.target.value) }),
              className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono"
            }
          )
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "pt-3 border-t border-border/60 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] font-bold uppercase tracking-wide flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-3.5 h-3.5" }),
          " Minuteur global de partie"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "flex items-center gap-2 text-xs", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "checkbox",
                checked: app.chess_global_timer_enabled,
                onChange: (e) => setApp({ ...app, chess_global_timer_enabled: e.target.checked })
              }
            ),
            "Échecs : actif"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold", children: [
            "Échecs : durée (min)",
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "number",
                min: 1,
                max: 180,
                value: app.chess_global_timer_minutes,
                onChange: (e) => setApp({ ...app, chess_global_timer_minutes: Number(e.target.value) }),
                className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono"
              }
            )
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "flex items-center gap-2 text-xs", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "checkbox",
                checked: app.fanorona_global_timer_enabled,
                onChange: (e) => setApp({ ...app, fanorona_global_timer_enabled: e.target.checked })
              }
            ),
            "Fanorona : actif"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold", children: [
            "Fanorona : durée (min)",
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "number",
                min: 1,
                max: 180,
                value: app.fanorona_global_timer_minutes,
                onChange: (e) => setApp({ ...app, fanorona_global_timer_minutes: Number(e.target.value) }),
                className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono"
              }
            )
          ] })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] border border-border/60 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-4 h-4 text-primary" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "⏱️ Timers par jeu" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground", children: "Durée d'un tour et délai en salle d'attente de tournoi (avant forfait automatique)." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-3", children: rows.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-background/60 border border-border/40 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-semibold text-sm flex items-center gap-1.5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Swords, { className: "w-3.5 h-3.5 text-primary/70" }),
            r.display_name
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "button",
            {
              onClick: () => save(r),
              disabled: savingSlug === r.slug,
              className: "px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-bold flex items-center gap-1 disabled:opacity-50",
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-3.5 h-3.5" }),
                " ",
                savingSlug === r.slug ? "…" : "OK"
              ]
            }
          )
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold", children: [
            "Timer / tour (s)",
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "number",
                min: 5,
                max: 600,
                value: r.turn_timer_seconds,
                onChange: (e) => setValue(r.slug, { turn_timer_seconds: Number(e.target.value) }),
                className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-card border border-border text-sm text-center font-mono"
              }
            )
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-[11px] font-semibold", children: [
            "Salle tournoi (min)",
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "input",
              {
                type: "number",
                min: 1,
                max: 30,
                value: Math.round((r.tournament_join_timeout_secs ?? 240) / 60),
                onChange: (e) => setValue(r.slug, { tournament_join_timeout_secs: Number(e.target.value) * 60 }),
                className: "mt-1 w-full px-2 py-1.5 rounded-lg bg-card border border-border text-sm text-center font-mono"
              }
            )
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-1.5", children: PRESETS.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => setValue(r.slug, { turn_timer_seconds: p }),
            className: `px-2.5 py-1 rounded-full text-[11px] font-bold border transition-all ${r.turn_timer_seconds === p ? "bg-primary text-primary-foreground border-primary" : "bg-muted/40 border-border/40 text-muted-foreground hover:bg-muted"}`,
            children: [
              p,
              "s"
            ]
          },
          p
        )) })
      ] }, r.slug)) })
    ] })
  ] });
}
function ValidatedField({
  label,
  value,
  onChange,
  type = "text",
  hint,
  min,
  max,
  placeholder,
  validate,
  onValidityChange,
  variant = "soft",
  className
}) {
  const id = reactExports.useId();
  const [touched, setTouched] = reactExports.useState(false);
  const raw = value == null ? "" : String(value);
  const error = validate ? validate(raw) : null;
  const cbRef = reactExports.useRef(onValidityChange);
  reactExports.useEffect(() => {
    cbRef.current = onValidityChange;
  });
  reactExports.useEffect(() => {
    cbRef.current?.(error);
  }, [error]);
  const showError = touched && error;
  const base = variant === "pill" ? "w-full px-4 py-3 rounded-full bg-card border shadow-inner outline-none" : "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm border";
  const borderCls = showError ? "border-destructive focus:ring-2 focus:ring-destructive/30" : "border-border focus:ring-2 focus:ring-primary/30";
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { htmlFor: id, className: `block ${className ?? ""}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: variant === "pill" ? "text-sm font-semibold mb-1" : "text-xs font-semibold mb-1", children: label }),
    hint && !showError && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground mb-1", children: hint }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "input",
      {
        id,
        type,
        value: raw,
        min,
        max,
        placeholder,
        onChange: (e) => {
          onChange(e.target.value);
          if (!touched) setTouched(true);
        },
        onBlur: () => setTouched(true),
        "aria-invalid": !!showError,
        "aria-describedby": showError ? `${id}-err` : void 0,
        className: `${base} ${borderCls} transition-colors`
      }
    ),
    showError && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { id: `${id}-err`, role: "alert", className: "mt-1 text-[11px] font-medium text-destructive flex items-center gap-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { "aria-hidden": true, children: "⚠️" }),
      error
    ] })
  ] });
}
function useFormErrors() {
  const [errors, setErrors] = reactExports.useState({});
  const cache = reactExports.useRef({});
  const setError = reactExports.useCallback((key) => {
    if (!cache.current[key]) {
      cache.current[key] = (err) => setErrors((prev) => prev[key] === err ? prev : { ...prev, [key]: err });
    }
    return cache.current[key];
  }, []);
  const hasErrors = reactExports.useMemo(() => Object.values(errors).some(Boolean), [errors]);
  const firstError = reactExports.useMemo(() => Object.values(errors).find(Boolean) || null, [errors]);
  return { errors, setError, hasErrors, firstError };
}
const isEmpty = (v) => v == null || String(v).trim() === "";
const required = (label = "Ce champ") => (v) => isEmpty(v) ? `${label} est requis.` : null;
const optional = (v) => (raw) => isEmpty(raw) ? null : v(raw);
const number = (opts = {}) => (raw) => {
  if (isEmpty(raw)) return null;
  const n = Number(raw);
  if (!Number.isFinite(n)) return "Doit être un nombre valide.";
  if (opts.integer && !Number.isInteger(n)) return "Doit être un nombre entier.";
  if (opts.min !== void 0 && n < opts.min) return `Doit être ≥ ${opts.min}.`;
  if (opts.max !== void 0 && n > opts.max) return `Doit être ≤ ${opts.max}.`;
  return null;
};
const percent = number({ min: 0, max: 100 });
const malagasyPhone = (raw) => {
  if (isEmpty(raw)) return null;
  const digits = raw.replace(/\s|-|\./g, "");
  if (/^\+261[0-9]{9}$/.test(digits)) return null;
  if (/^0[23][0-9]{8}$/.test(digits)) return null;
  return "Format invalide (ex : +261 34 12 345 67 ou 034 12 345 67).";
};
const email = (raw) => {
  if (isEmpty(raw)) return null;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw.trim()) ? null : "Adresse email invalide.";
};
const url = (raw) => {
  if (isEmpty(raw)) return null;
  try {
    new URL(raw.trim());
    return null;
  } catch {
    return "URL invalide (doit commencer par https://).";
  }
};
const minLen = (n) => (raw) => isEmpty(raw) || raw.trim().length >= n ? null : `Minimum ${n} caractères.`;
const maxLen = (n) => (raw) => raw && raw.length > n ? `Maximum ${n} caractères.` : null;
const combine = (...vs) => (raw) => {
  for (const v of vs) {
    const err = v(raw);
    if (err) return err;
  }
  return null;
};
async function saveWithToast(run, opts = { label: "Modifications" }) {
  const id = toast.loading(`💾 Enregistrement — ${opts.label}…`);
  try {
    const res = await run();
    if (res.error) {
      toast.error(`❌ Impossible d'enregistrer — ${opts.label}`, {
        id,
        description: res.error.message,
        duration: 8e3
      });
      return false;
    }
    toast.success(`✅ ${opts.label} enregistré${opts.label.endsWith("s") ? "s" : ""}`, {
      id,
      description: "Les modifications sont actives immédiatement.",
      duration: 3500
    });
    opts.onSuccess?.(res);
    return true;
  } catch (e) {
    toast.error(`❌ Erreur inattendue — ${opts.label}`, {
      id,
      description: e?.message ?? String(e),
      duration: 8e3
    });
    return false;
  }
}
const ACCENTS = {
  primary: "from-primary/15 to-primary/5 text-primary",
  emerald: "from-emerald-500/15 to-emerald-500/5 text-emerald-600",
  amber: "from-amber-500/15 to-amber-500/5 text-amber-600",
  sky: "from-sky-500/15 to-sky-500/5 text-sky-600",
  rose: "from-rose-500/15 to-rose-500/5 text-rose-600",
  violet: "from-violet-500/15 to-violet-500/5 text-violet-600"
};
function AdminSection({
  id,
  title,
  icon,
  description,
  defaultOpen = false,
  accent = "primary",
  children
}) {
  const [open, setOpen] = reactExports.useState(defaultOpen);
  const [flash, setFlash] = reactExports.useState(false);
  const ref = reactExports.useRef(null);
  reactExports.useEffect(() => {
    if (!id) return;
    const handler = (e) => {
      const detail = e.detail;
      if (detail?.id !== id) return;
      setOpen(true);
      setFlash(true);
      setTimeout(() => {
        ref.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 60);
      setTimeout(() => setFlash(false), 1600);
    };
    window.addEventListener("admin-section-open", handler);
    return () => window.removeEventListener("admin-section-open", handler);
  }, [id]);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "section",
    {
      ref,
      id: id ? `admin-section-${id}` : void 0,
      className: `rounded-3xl bg-card border shadow-[var(--shadow-soft)] overflow-hidden transition-all ${flash ? "border-primary ring-2 ring-primary/30" : "border-border/60"}`,
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            type: "button",
            onClick: () => setOpen((o) => !o),
            className: `w-full flex items-center gap-3 px-4 py-3 bg-gradient-to-r ${ACCENTS[accent]} hover:brightness-105 transition-all`,
            children: [
              icon && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "shrink-0", children: icon }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 text-left min-w-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-sm truncate", children: title }),
                description && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] opacity-70 truncate", children: description })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                ChevronDown,
                {
                  className: `w-4 h-4 shrink-0 transition-transform ${open ? "rotate-180" : ""}`
                }
              )
            ]
          }
        ),
        open && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-3 sm:p-4 space-y-4 bg-background/40", children })
      ]
    }
  );
}
function norm(s) {
  return s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
}
function AdminSearchBar({ index, onGo }) {
  const [q, setQ] = reactExports.useState("");
  const [open, setOpen] = reactExports.useState(false);
  const [activeIdx, setActiveIdx] = reactExports.useState(0);
  const wrapRef = reactExports.useRef(null);
  const results = reactExports.useMemo(() => {
    const query = norm(q.trim());
    if (!query) return [];
    const tokens = query.split(/\s+/).filter(Boolean);
    return index.map((e) => {
      const hay = norm([e.title, e.description ?? "", e.keywords ?? "", e.tabLabel].join(" "));
      const score = tokens.every((t) => hay.includes(t)) ? tokens.reduce((s, t) => s + (hay.indexOf(t) >= 0 ? 1 : 0), 0) : 0;
      return { e, score };
    }).filter((x) => x.score > 0).slice(0, 10).map((x) => x.e);
  }, [q, index]);
  reactExports.useEffect(() => setActiveIdx(0), [q]);
  reactExports.useEffect(() => {
    const onClick = (e) => {
      if (!wrapRef.current?.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);
  const go = (entry) => {
    onGo(entry);
    setOpen(false);
    setQ("");
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { ref: wrapRef, className: "relative", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 px-3 py-2 rounded-2xl bg-card border border-border/60 shadow-sm focus-within:border-primary focus-within:ring-2 focus-within:ring-primary/20 transition-all", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Search, { className: "w-4 h-4 text-muted-foreground shrink-0" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "input",
        {
          value: q,
          onChange: (e) => {
            setQ(e.target.value);
            setOpen(true);
          },
          onFocus: () => setOpen(true),
          onKeyDown: (e) => {
            if (e.key === "ArrowDown") {
              e.preventDefault();
              setActiveIdx((i) => Math.min(i + 1, results.length - 1));
            } else if (e.key === "ArrowUp") {
              e.preventDefault();
              setActiveIdx((i) => Math.max(0, i - 1));
            } else if (e.key === "Enter" && results[activeIdx]) {
              e.preventDefault();
              go(results[activeIdx]);
            } else if (e.key === "Escape") {
              setOpen(false);
            }
          },
          placeholder: "Rechercher un paramètre (timer, parrainage, chat, tournoi…)",
          className: "flex-1 bg-transparent outline-none text-sm min-w-0"
        }
      ),
      q && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
        setQ("");
        setOpen(false);
      }, className: "text-muted-foreground hover:text-foreground", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
    ] }),
    open && q && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute z-30 left-0 right-0 mt-1 max-h-[60vh] overflow-y-auto rounded-2xl bg-card border border-border/60 shadow-lg", children: results.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 py-6 text-center text-sm text-muted-foreground", children: [
      "Aucun paramètre trouvé pour « ",
      q,
      " »"
    ] }) : results.map((r, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onMouseEnter: () => setActiveIdx(i),
        onClick: () => go(r),
        className: `w-full text-left px-3 py-2.5 flex items-center gap-3 border-b border-border/40 last:border-0 transition-colors ${i === activeIdx ? "bg-primary/10" : "hover:bg-accent"}`,
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm truncate", children: r.title }),
            r.description && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground truncate", children: r.description })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full bg-primary/10 text-primary uppercase tracking-wide", children: r.tabLabel })
        ]
      },
      r.id
    )) })
  ] });
}
function CmsEditor() {
  const [section, setSection] = reactExports.useState("faq");
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-between gap-2", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "📝 Contenus éditables" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Modifiez les textes de la FAQ et de la page Parrainage. Les changements sont visibles immédiatement." })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setSection("faq"),
          className: `flex-1 py-2 rounded-full text-sm font-semibold ${section === "faq" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: "❓ FAQ"
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setSection("referral"),
          className: `flex-1 py-2 rounded-full text-sm font-semibold ${section === "referral" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: "🎁 Parrainage"
        }
      )
    ] }),
    section === "faq" ? /* @__PURE__ */ jsxRuntimeExports.jsx(FaqEditor, {}) : /* @__PURE__ */ jsxRuntimeExports.jsx(ReferralEditor, {})
  ] });
}
function FaqEditor() {
  const [content, setContent] = reactExports.useState(null);
  const [meta, setMeta] = reactExports.useState(null);
  const [saving, setSaving] = reactExports.useState(false);
  reactExports.useEffect(() => {
    load();
  }, []);
  async function load() {
    const { data } = await supabase.from("cms_content").select("content, updated_at").eq("key", "faq").maybeSingle();
    const c = data?.content || { categories: [] };
    setContent(c);
    setMeta({ updated_at: data?.updated_at });
  }
  async function save() {
    if (!content) return;
    setSaving(true);
    const { error } = await supabase.rpc("admin_update_cms_content", { _key: "faq", _content: content });
    setSaving(false);
    if (error) return toast.error(error.message);
    invalidateCmsCache("faq");
    toast.success("FAQ enregistrée");
    load();
  }
  function updateCat(idx, next) {
    if (!content) return;
    const cats = [...content.categories];
    cats[idx] = { ...cats[idx], ...next };
    setContent({ categories: cats });
  }
  function moveCat(idx, dir) {
    if (!content) return;
    const cats = [...content.categories];
    const j = idx + dir;
    if (j < 0 || j >= cats.length) return;
    [cats[idx], cats[j]] = [cats[j], cats[idx]];
    setContent({ categories: cats });
  }
  function removeCat(idx) {
    if (!content) return;
    setContent({ categories: content.categories.filter((_, i) => i !== idx) });
  }
  function addCat() {
    if (!content) return;
    setContent({ categories: [...content.categories, { category: "📌 Nouvelle catégorie", items: [] }] });
  }
  if (!content) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground py-4", children: "Chargement…" });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    meta?.updated_at && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground", children: [
      "Dernière modification : ",
      new Date(meta.updated_at).toLocaleString("fr-FR")
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-900 rounded-lg px-3 py-2", children: [
      "💡 Astuce : dans une réponse, écrivez ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("code", { className: "font-mono", children: "__REFERRAL_SHORT__" }),
      " pour insérer automatiquement le résumé du parrainage."
    ] }),
    content.categories.map((cat, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
      FaqCategoryCard,
      {
        cat,
        onChange: (next) => updateCat(i, next),
        onRemove: () => removeCat(i),
        onMoveUp: () => moveCat(i, -1),
        onMoveDown: () => moveCat(i, 1)
      },
      i
    )),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: addCat, className: "w-full py-2 rounded-full bg-secondary hover:bg-accent font-semibold text-sm flex items-center justify-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
      " Ajouter une catégorie"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: save, disabled: saving, className: "w-full py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 disabled:opacity-50", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-4 h-4" }),
      " ",
      saving ? "Enregistrement…" : "Enregistrer la FAQ"
    ] })
  ] });
}
function FaqCategoryCard({
  cat,
  onChange,
  onRemove,
  onMoveUp,
  onMoveDown
}) {
  const [open, setOpen] = reactExports.useState(false);
  function updateItem(idx, next) {
    const items = [...cat.items];
    items[idx] = { ...items[idx], ...next };
    onChange({ items });
  }
  function removeItem(idx) {
    onChange({ items: cat.items.filter((_, i) => i !== idx) });
  }
  function addItem() {
    onChange({ items: [...cat.items, { q: "Nouvelle question ?", a: "Nouvelle réponse." }] });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl border border-border/50 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 p-3 bg-secondary/40", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "input",
        {
          value: cat.category,
          onChange: (e) => onChange({ category: e.target.value }),
          className: "flex-1 px-3 py-1.5 rounded-lg bg-card outline-none text-sm font-semibold"
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onMoveUp, className: "p-1.5 rounded hover:bg-accent", title: "Monter", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronUp, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onMoveDown, className: "p-1.5 rounded hover:bg-accent", title: "Descendre", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronDown, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setOpen(!open), className: "px-2 py-1 rounded bg-card text-xs font-semibold", children: open ? "Replier" : `Ouvrir (${cat.items.length})` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onRemove, className: "p-1.5 rounded bg-destructive/10 text-destructive hover:bg-destructive/20", title: "Supprimer", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
    ] }),
    open && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-3 space-y-2", children: [
      cat.items.map((it, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl border border-border/40 p-2 space-y-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "input",
            {
              value: it.q,
              onChange: (e) => updateItem(i, { q: e.target.value }),
              placeholder: "Question",
              className: "flex-1 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm font-semibold"
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => removeItem(i), className: "p-1.5 rounded bg-destructive/10 text-destructive hover:bg-destructive/20", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-3.5 h-3.5" }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "textarea",
          {
            value: it.a,
            onChange: (e) => updateItem(i, { a: e.target.value }),
            placeholder: "Réponse",
            rows: 3,
            className: "w-full px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm"
          }
        )
      ] }, i)),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: addItem, className: "w-full py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold text-xs flex items-center justify-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-3.5 h-3.5" }),
        " Ajouter une question"
      ] })
    ] })
  ] });
}
function ReferralEditor() {
  const [content, setContent] = reactExports.useState(null);
  const [meta, setMeta] = reactExports.useState(null);
  const [saving, setSaving] = reactExports.useState(false);
  reactExports.useEffect(() => {
    load();
  }, []);
  async function load() {
    const { data } = await supabase.from("cms_content").select("content, updated_at").eq("key", "referral").maybeSingle();
    const c = data?.content || { hero_subtitle: "", how_it_works: [], conditions: [] };
    setContent(c);
    setMeta({ updated_at: data?.updated_at });
  }
  async function save() {
    if (!content) return;
    setSaving(true);
    const { error } = await supabase.rpc("admin_update_cms_content", { _key: "referral", _content: content });
    setSaving(false);
    if (error) return toast.error(error.message);
    invalidateCmsCache("referral");
    toast.success("Page Parrainage enregistrée");
    load();
  }
  function updateStep(idx, next) {
    if (!content) return;
    const steps = [...content.how_it_works];
    steps[idx] = { ...steps[idx], ...next };
    setContent({ ...content, how_it_works: steps });
  }
  function addStep() {
    if (!content) return;
    setContent({
      ...content,
      how_it_works: [...content.how_it_works, { step: String(content.how_it_works.length + 1), icon: "✨", label: "Nouvelle étape", desc: "" }]
    });
  }
  function removeStep(idx) {
    if (!content) return;
    setContent({ ...content, how_it_works: content.how_it_works.filter((_, i) => i !== idx) });
  }
  if (!content) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground py-4", children: "Chargement…" });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    meta?.updated_at && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground", children: [
      "Dernière modification : ",
      new Date(meta.updated_at).toLocaleString("fr-FR")
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-900 rounded-lg px-3 py-2", children: [
      "💡 Utilisez ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("code", { className: "font-mono", children: "{pct}" }),
      " pour le pourcentage de commission et ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("code", { className: "font-mono", children: "{max}" }),
      " pour le nombre max de parties. Les vraies valeurs sont remplacées automatiquement."
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-sm font-semibold block mb-1", children: "Sous-titre du bandeau" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "textarea",
        {
          value: content.hero_subtitle,
          onChange: (e) => setContent({ ...content, hero_subtitle: e.target.value }),
          rows: 2,
          className: "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm",
          placeholder: "Gagnez {pct}% de chaque mise…"
        }
      )
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-sm font-semibold", children: "Comment ça marche ?" }),
      content.how_it_works.map((s, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl border border-border/40 p-2 space-y-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: s.step, onChange: (e) => updateStep(i, { step: e.target.value }), placeholder: "#", className: "w-12 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm text-center font-bold" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: s.icon, onChange: (e) => updateStep(i, { icon: e.target.value }), placeholder: "🎯", className: "w-14 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm text-center" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: s.label, onChange: (e) => updateStep(i, { label: e.target.value }), placeholder: "Titre", className: "flex-1 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm font-semibold" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => removeStep(i), className: "p-1.5 rounded bg-destructive/10 text-destructive hover:bg-destructive/20", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-3.5 h-3.5" }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: s.desc, onChange: (e) => updateStep(i, { desc: e.target.value }), placeholder: "Description", rows: 2, className: "w-full px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm" })
      ] }, i)),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: addStep, className: "w-full py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold text-xs flex items-center justify-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-3.5 h-3.5" }),
        " Ajouter une étape"
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-sm font-semibold", children: "Conditions du programme (une par ligne)" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "textarea",
        {
          value: content.conditions.join("\n"),
          onChange: (e) => setContent({ ...content, conditions: e.target.value.split("\n").map((s) => s.trim()).filter(Boolean) }),
          rows: 7,
          className: "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm",
          placeholder: "Aucun bonus…\nVous recevez {pct}%…"
        }
      )
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: save, disabled: saving, className: "w-full py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 disabled:opacity-50", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-4 h-4" }),
      " ",
      saving ? "Enregistrement…" : "Enregistrer la page Parrainage"
    ] })
  ] });
}
function AdminSessionsPanel() {
  const [sessions, setSessions] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(false);
  const load = reactExports.useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc("admin_list_all_active_sessions");
    if (!error) setSessions(data || []);
    setLoading(false);
  }, []);
  reactExports.useEffect(() => {
    load();
    const t = setInterval(load, 3e4);
    return () => clearInterval(t);
  }, [load]);
  async function revoke(s) {
    const who = s.is_me ? "ma session" : `la session de ${s.admin_name}`;
    if (!confirm(`Révoquer ${who} ?`)) return;
    const rpc = s.is_me ? "admin_revoke_session" : "admin_revoke_any_session";
    const params = s.is_me ? { _session_id: s.id, _reason: "manual" } : { _session_id: s.id, _reason: "révoquée par un autre admin" };
    const { error } = await supabase.rpc(rpc, params);
    if (error) return toast.error(error.message);
    toast.success("Session révoquée");
    load();
  }
  async function revokeAllOthers() {
    if (!confirm("Déconnecter toutes les AUTRES sessions de mon compte ?")) return;
    const { data, error } = await supabase.rpc("admin_revoke_all_other_sessions");
    if (error) return toast.error(error.message);
    toast.success(`${data ?? 0} session(s) révoquée(s)`);
    load();
  }
  const fmt = (d) => new Date(d).toLocaleString();
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 space-y-3 border border-border", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h3", { className: "font-bold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Monitor, { className: "w-4 h-4" }),
        " Sessions admin actives",
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-normal text-muted-foreground", children: [
          "(",
          sessions.length,
          ")"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: load, disabled: loading, className: "p-2 rounded-lg bg-muted", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: `w-4 h-4 ${loading ? "animate-spin" : ""}` }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: revokeAllOthers,
            className: "px-3 py-2 rounded-lg bg-destructive text-destructive-foreground text-xs font-semibold flex items-center gap-1",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldOff, { className: "w-3 h-3" }),
              " Mes autres"
            ]
          }
        )
      ] })
    ] }),
    sessions.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-4", children: "Aucune session active" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: sessions.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: `p-3 rounded-xl border text-xs ${s.is_me ? "border-primary/50 bg-primary/5" : "border-green-500/30 bg-green-500/5"}`,
        children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 font-semibold", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(User, { className: "w-3 h-3" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: s.admin_name }),
              s.is_me && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2 py-0.5 rounded bg-primary/20 text-primary text-[10px]", children: "MOI" }),
              s.override_reason && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2 py-0.5 rounded bg-amber-500/20 text-amber-500 text-[10px]", children: "OVERRIDE" })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-muted-foreground truncate", children: [
              "🖥 ",
              s.user_agent || "—"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-muted-foreground", children: [
              "📍 ",
              s.ip || "—",
              " · Créée ",
              fmt(s.created_at)
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-muted-foreground", children: [
              "⏱ Expire ",
              fmt(s.expires_at),
              " · Vue ",
              fmt(s.last_seen_at)
            ] }),
            s.override_reason && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-amber-500 mt-1", children: [
              "Motif urgence : ",
              s.override_reason
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              onClick: () => revoke(s),
              className: "p-2 rounded-lg bg-destructive/10 text-destructive shrink-0",
              title: s.is_me ? "Me déconnecter" : "Déconnecter cet admin",
              children: /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-4 h-4" })
            }
          )
        ] })
      },
      s.id
    )) })
  ] });
}
const GAMES = [
  { slug: "ludo", emoji: "🎲", label: "Ludo" },
  { slug: "domino", emoji: "🁣", label: "Domino" }
];
const SPLITS = {
  1: [100, 0, 0, 0],
  2: [70, 30, 0, 0],
  3: [60, 25, 15, 0],
  // sum=100 (platform takes 10% of entry fees separately)
  4: [50, 25, 15, 10]
  // sum=100
};
function TournamentAdminPanel() {
  const confirm2 = useConfirm();
  const [tab, setTab] = reactExports.useState("list");
  const [rows, setRows] = reactExports.useState([]);
  const [counts, setCounts] = reactExports.useState({});
  const [busy, setBusy] = reactExports.useState(false);
  const [loading, setLoading] = reactExports.useState(true);
  const load = reactExports.useCallback(async () => {
    const { data } = await supabase.from("tournaments").select("*").order("created_at", { ascending: false }).limit(40);
    const list = data || [];
    setRows(list);
    if (list.length) {
      const { data: ents } = await supabase.from("tournament_entrants").select("tournament_id").in("tournament_id", list.map((r) => r.id));
      const c = {};
      (ents || []).forEach((e) => {
        c[e.tournament_id] = (c[e.tournament_id] || 0) + 1;
      });
      setCounts(c);
    }
    setLoading(false);
  }, []);
  reactExports.useEffect(() => {
    load();
  }, [load]);
  const run = async (fn, args, ok) => {
    setBusy(true);
    const { error } = await supabase.rpc(fn, args);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(ok);
    load();
  };
  const [f, setF] = reactExports.useState({
    name: "",
    game_slug: "ludo",
    format: "knockout",
    players_per_match: 4,
    max_players: 16,
    mode: "free",
    entry_fee_ar: 0,
    admin_prize_pool_ar: 1e4,
    winners_count: 1,
    pool_size: 4,
    qualifiers_per_pool: 2,
    max_concurrent: 8,
    lobby_minutes: 5,
    break_minutes: 3,
    batch_gap_minutes: 0,
    max_match_duration_secs: 600,
    check_in_minutes: 15,
    domino_scoring: "elimination",
    target_score: 100,
    description: ""
  });
  const set = (k, v) => setF((p) => ({ ...p, [k]: v }));
  const create = async () => {
    if (!f.name.trim()) return toast.error("Le nom du tournoi est requis.");
    if (f.mode === "free" && f.admin_prize_pool_ar <= 0) {
      const okGo = await confirm2({ title: "Tournoi sans récompense ?", description: "Aucune récompense n'est offerte. Les gagnants ne recevront rien." });
      if (!okGo) return;
    }
    if (f.mode === "paid" && f.entry_fee_ar < 100) {
      return toast.error("Frais d'inscription minimum : 100 Ar");
    }
    const [p1, p2, p3, p4] = SPLITS[f.winners_count];
    const ppm = f.game_slug === "domino" ? 2 : Math.max(f.players_per_match, f.game_slug === "ludo" ? 4 : 2);
    setBusy(true);
    const { error } = await supabase.rpc("admin_tournament_create", {
      _name: f.name.trim(),
      _game_slug: f.game_slug,
      _format: f.format,
      _players_per_match: ppm,
      _max_players: f.max_players,
      _entry_fee_ar: f.entry_fee_ar,
      _admin_prize_pool_ar: f.admin_prize_pool_ar,
      _winners_count: f.winners_count,
      _p1: p1,
      _p2: p2,
      _p3: p3,
      _pool_size: f.pool_size,
      _qualifiers_per_pool: f.qualifiers_per_pool,
      _max_concurrent: f.max_concurrent,
      _lobby_minutes: f.lobby_minutes,
      _description: f.description || null,
      _registration_closes_at: null,
      _starts_at: null,
      _break_seconds: f.break_minutes * 60,
      _batch_gap_seconds: f.batch_gap_minutes * 60,
      _max_match_duration_secs: f.max_match_duration_secs,
      _check_in_minutes: f.check_in_minutes,
      _prize_4_pct: p4,
      _domino_scoring: f.domino_scoring,
      _target_score: f.target_score
    });
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success("🏆 Tournoi créé — inscriptions ouvertes !");
    setF((p) => ({ ...p, name: "", description: "" }));
    setTab("list");
    load();
  };
  const [sim, setSim] = reactExports.useState({ game_slug: "domino", format: "pools", players: 16, pool_size: 4, qualifiers_per_pool: 2 });
  const [simReport, setSimReport] = reactExports.useState(null);
  const runSim = async () => {
    setBusy(true);
    setSimReport(null);
    const { data, error } = await supabase.rpc("admin_tournament_simulate_new", {
      _game_slug: sim.game_slug,
      _format: sim.format,
      _players: sim.players,
      _players_per_match: sim.game_slug === "ludo" ? 4 : 2,
      _pool_size: sim.pool_size,
      _qualifiers_per_pool: sim.qualifiers_per_pool
    });
    setBusy(false);
    if (error) return toast.error(error.message);
    setSimReport(data);
    if (data?.ok) toast.success("✅ Simulation terminée : poules, classement et bracket cohérents");
    else toast.error("⚠️ Anomalies détectées, voir le rapport");
    load();
  };
  const simulateExisting = async (id) => {
    setBusy(true);
    const { data, error } = await supabase.rpc("admin_tournament_simulate", { _tid: id, _max_steps: 300 });
    setBusy(false);
    if (error) return toast.error(error.message);
    setSimReport(data);
    setTab("sim");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => setTab("list"),
          className: `px-4 py-2 rounded-full text-sm font-semibold ${tab === "list" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: [
            "📋 Tournois (",
            rows.length,
            ")"
          ]
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setTab("create"),
          className: `px-4 py-2 rounded-full text-sm font-semibold ${tab === "create" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: "➕ Créer"
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setTab("sim"),
          className: `px-4 py-2 rounded-full text-sm font-semibold ${tab === "sim" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: "🧪 Simulation"
        }
      )
    ] }),
    tab === "list" && (loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-10", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-5 h-5 animate-spin text-muted-foreground" }) }) : rows.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-8", children: "Aucun tournoi." }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: rows.map((t) => {
      const g = GAMES.find((x) => x.slug === t.game_slug);
      const n = counts[t.id] ?? 0;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/50 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xl", children: g?.emoji ?? "🏆" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm truncate", children: [
              t.is_simulation && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "mr-1 text-[10px] px-1.5 py-0.5 rounded bg-primary/15 text-primary align-middle", children: "SIMU" }),
              t.name
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground", children: [
              g?.label,
              " · ",
              t.format === "pools" ? "Poules" : "Élimination",
              " · ",
              n,
              "/",
              t.max_players,
              " joueurs · ",
              t.status,
              t.status === "running" && ` · étape : ${t.stage}`,
              t.check_in_opened_at && !t.started_at && " · check-in ouvert"
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/tournaments/$id", params: { id: t.id }, className: "text-primary shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ExternalLink, { className: "w-4 h-4" }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap gap-1.5", children: [
          t.is_simulation && !["finished", "cancelled"].includes(t.status) && /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              disabled: busy,
              onClick: () => simulateExisting(t.id),
              className: "px-2.5 py-1 rounded-lg bg-primary/15 text-primary text-[11px] font-bold",
              children: "🧪 Simuler jusqu'à la fin"
            }
          ),
          t.status === "open" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            Number(t.entry_fee_ar) === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_add_bots", { _tid: t.id, _count: 4 }, "4 bots ajoutés"),
                className: "px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold",
                children: "+4 bots"
              }
            ),
            !t.check_in_opened_at && /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_open_check_in", { _tid: t.id }, "Check-in ouvert"),
                className: "px-2.5 py-1 rounded-lg bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300 text-[11px] font-bold",
                children: "✋ Ouvrir check-in"
              }
            ),
            t.check_in_opened_at && /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_close_check_in", { _tid: t.id }, "Check-in clôturé"),
                className: "px-2.5 py-1 rounded-lg bg-orange-100 text-orange-700 dark:bg-orange-950/40 dark:text-orange-300 text-[11px] font-bold",
                children: "🔒 Fermer check-in"
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_start", { _tid: t.id }, "Tournoi démarré"),
                className: "px-2.5 py-1 rounded-lg bg-primary text-primary-foreground text-[11px] font-bold",
                children: "▶ Démarrer"
              }
            )
          ] }),
          t.status === "running" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_next_stage", { _tid: t.id }, "Étape suivante"),
                className: "px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold",
                children: "⏭ Étape suivante"
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_set_status", { _tid: t.id, _status: "paused" }, "En pause"),
                className: "px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold",
                children: "⏸ Pause"
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                disabled: busy,
                onClick: () => run("admin_tournament_set_auto", { _tid: t.id, _auto: !t.auto_advance }, "Mode mis à jour"),
                className: "px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold",
                children: t.auto_advance ? "⚡ Auto ON" : "✋ Auto OFF"
              }
            )
          ] }),
          t.status === "paused" && /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              disabled: busy,
              onClick: () => run("admin_tournament_set_status", { _tid: t.id, _status: "running" }, "Repris"),
              className: "px-2.5 py-1 rounded-lg bg-primary text-primary-foreground text-[11px] font-bold",
              children: "▶ Reprendre"
            }
          ),
          !["finished", "cancelled"].includes(t.status) && /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              disabled: busy,
              onClick: async () => {
                if (!await confirm2({ title: "Annuler ce tournoi ?", description: "Les inscriptions payantes seront remboursées.", destructive: true })) return;
                run("admin_tournament_cancel", { _tid: t.id, _reason: null }, "Tournoi annulé");
              },
              className: "px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold text-destructive",
              children: "✕ Annuler"
            }
          )
        ] })
      ] }, t.id);
    }) })),
    tab === "sim" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl bg-secondary/50 p-3 text-[12px] text-muted-foreground", children: "Lance un tournoi complet avec des bots et des résultats aléatoires (aucune vraie partie, aucun gain réel) puis vérifie automatiquement les poules, le classement et le bracket jusqu'au champion." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: GAMES.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => setSim((p) => ({ ...p, game_slug: g.slug })),
          className: `flex-1 py-3 rounded-2xl text-sm font-bold ${sim.game_slug === g.slug ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: [
            g.emoji,
            " ",
            g.label
          ]
        },
        g.slug
      )) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: ["pools", "knockout"].map((fm) => /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setSim((p) => ({ ...p, format: fm })),
          className: `flex-1 py-2.5 rounded-2xl text-sm font-bold ${sim.format === fm ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: fm === "pools" ? "Poules + finales" : "Élimination directe"
        },
        fm
      )) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-2", children: [8, 11, 16, 24, 32].map((n) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => setSim((p) => ({ ...p, players: n })),
          className: `px-3 py-2 rounded-xl text-[12px] font-bold ${sim.players === n ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: [
            n,
            " bots"
          ]
        },
        n
      )) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          disabled: busy,
          onClick: runSim,
          className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-2",
          children: [
            busy ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }),
            "Lancer l'auto-simulation"
          ]
        }
      ),
      simReport && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/50 p-3 space-y-2 text-[12px]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `font-bold ${simReport.ok ? "text-primary" : "text-destructive"}`, children: simReport.ok ? "✅ Tournoi cohérent de bout en bout" : "⚠️ Anomalies détectées" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-muted-foreground", children: [
          simReport.entrants,
          " joueurs · ",
          simReport.matches,
          " matchs · ",
          simReport.pools,
          " poule(s) · ",
          simReport.rounds,
          " tour(s) · statut : ",
          simReport.status
        ] }),
        simReport.champion && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          "🏆 Champion : ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: simReport.champion })
        ] }),
        Array.isArray(simReport.podium) && simReport.podium.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-1.5", children: simReport.podium.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "px-2 py-0.5 rounded-lg bg-card text-[11px] font-semibold", children: [
          p.rank,
          ". ",
          p.name
        ] }, p.rank)) }),
        Array.isArray(simReport.issues) && simReport.issues.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("ul", { className: "list-disc pl-4 text-destructive space-y-0.5", children: simReport.issues.map((it, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("li", { children: it }, i)) }),
        Array.isArray(simReport.standings) && simReport.standings.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-card p-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-1", children: p.pool }),
          (p.rows || []).map((r, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between text-[11px] text-muted-foreground", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
              r.qualifie ? "✅" : "•",
              " ",
              r.name
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
              r.pts,
              " pts · ",
              r.v,
              "V / ",
              r.j,
              "J"
            ] })
          ] }, i))
        ] }, p.pool))
      ] })
    ] }),
    tab === "create" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-2", children: GAMES.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => {
            set("game_slug", g.slug);
            set("players_per_match", g.slug === "ludo" ? 4 : 2);
          },
          className: `flex-1 py-3 rounded-2xl text-sm font-bold ${f.game_slug === g.slug ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
          children: [
            g.emoji,
            " ",
            g.label
          ]
        },
        g.slug
      )) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Nom du tournoi", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
        "input",
        {
          value: f.name,
          onChange: (e) => set("name", e.target.value),
          placeholder: "ex : Coupe Ludo — Août 2026",
          className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm"
        }
      ) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Description (optionnel)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
        "textarea",
        {
          value: f.description,
          onChange: (e) => set("description", e.target.value),
          rows: 2,
          className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm"
        }
      ) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Format", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "select",
          {
            value: f.format,
            onChange: (e) => set("format", e.target.value),
            className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "knockout", children: "Élimination directe" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "pools", children: "Poules + phase finale" })
            ]
          }
        ) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Joueurs par match", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "select",
          {
            value: f.players_per_match,
            disabled: f.game_slug === "domino",
            onChange: (e) => set("players_per_match", Number(e.target.value)),
            className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm disabled:opacity-60",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 2, children: "1 vs 1" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 3, children: "3 joueurs" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 4, children: "4 joueurs" })
            ]
          }
        ) })
      ] }),
      f.format === "pools" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Taille des poules", value: f.pool_size, onChange: (v) => set("pool_size", v), min: 2, max: 6 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Qualifiés / poule", value: f.qualifiers_per_pool, onChange: (v) => set("qualifiers_per_pool", v), min: 1, max: 3 })
      ] }),
      f.game_slug === "domino" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/30 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] font-bold text-muted-foreground uppercase", children: "Mode de jeu Domino" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              type: "button",
              onClick: () => set("domino_scoring", "elimination"),
              className: `flex-1 py-2.5 rounded-xl text-sm font-bold ${f.domino_scoring === "elimination" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
              children: "Élimination"
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              type: "button",
              onClick: () => set("domino_scoring", "points"),
              className: `flex-1 py-2.5 rounded-xl text-sm font-bold ${f.domino_scoring === "points" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
              children: "Par points"
            }
          )
        ] }),
        f.domino_scoring === "points" && /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Score cible (points)", value: f.target_score, onChange: (v) => set("target_score", v), min: 50, max: 500 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground leading-relaxed", children: f.domino_scoring === "elimination" ? "Le perdant de chaque match est éliminé. Le gagnant passe au tour suivant." : `Les joueurs accumulent des points. Le premier à atteindre ${f.target_score} pts remporte le match. Idéal pour les parties longues.` })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/30 p-3 space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] font-bold text-muted-foreground uppercase", children: "Mode du tournoi" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              type: "button",
              onClick: () => {
                set("mode", "free");
                set("entry_fee_ar", 0);
                set("winners_count", 1);
                set("admin_prize_pool_ar", Math.max(f.admin_prize_pool_ar, 1e3));
              },
              className: `py-3 rounded-xl text-sm font-bold ${f.mode === "free" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
              children: "🎁 Gratuit"
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              type: "button",
              onClick: () => {
                set("mode", "paid");
                set("entry_fee_ar", Math.max(f.entry_fee_ar, 500));
                set("admin_prize_pool_ar", 0);
                set("winners_count", 3);
              },
              className: `py-3 rounded-xl text-sm font-bold ${f.mode === "paid" ? "bg-primary text-primary-foreground" : "bg-secondary"}`,
              children: "💰 Payant"
            }
          )
        ] }),
        f.mode === "free" ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground leading-relaxed", children: "Inscription gratuite pour les joueurs. L'admin offre une récompense unique au gagnant (ou aux 3 premiers). Pas de commission plateforme. Pas de bots." }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Récompense offerte par l'admin (Ar)", value: f.admin_prize_pool_ar, onChange: (v) => set("admin_prize_pool_ar", v), min: 0 }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Nombre de vainqueurs", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "select",
            {
              value: f.winners_count,
              onChange: (e) => set("winners_count", Number(e.target.value)),
              className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm",
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 1, children: "1 vainqueur (100%)" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 2, children: "2 vainqueurs (70/30)" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 3, children: "3 vainqueurs (60/20/10)" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 4, children: "4 vainqueurs (50/25/10/5)" })
              ]
            }
          ) })
        ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground leading-relaxed", children: "Les joueurs paient pour s'inscrire. La cagnotte grandit avec chaque inscription. Commission plateforme : 10% sur les frais collectés. Pas de bots." }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Frais d'inscription par joueur (Ar)", value: f.entry_fee_ar, onChange: (v) => set("entry_fee_ar", v), min: 100 }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label: "Nombre de vainqueurs", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "select",
            {
              value: f.winners_count,
              onChange: (e) => set("winners_count", Number(e.target.value)),
              className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm",
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 1, children: "1 vainqueur (100%)" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 2, children: "2 vainqueurs (70/30)" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 3, children: "3 vainqueurs (60/20/10) — + match 3e place" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 4, children: "4 vainqueurs (50/25/10/5)" })
              ]
            }
          ) })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Joueurs max", value: f.max_players, onChange: (v) => set("max_players", v), min: 2, max: 256 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Matchs simultanés", value: f.max_concurrent, onChange: (v) => set("max_concurrent", v), min: 1, max: f.game_slug === "ludo" ? 8 : 8 }),
        f.game_slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-amber-600 mt-0.5", children: "Ludo : max 8 matchs simultanés" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Salle d'attente (min)", value: f.lobby_minutes, onChange: (v) => set("lobby_minutes", v), min: 1, max: 10 })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/30 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] font-bold text-muted-foreground uppercase", children: "Timing des phases" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Pause entre phases (min)", value: f.break_minutes, onChange: (v) => set("break_minutes", v), min: 0, max: 60 }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Délai entre lots (min)", value: f.batch_gap_minutes, onChange: (v) => set("batch_gap_minutes", v), min: 0, max: 60 }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Durée max match (sec)", value: f.max_match_duration_secs, onChange: (v) => set("max_match_duration_secs", v), min: 60, max: 3600 }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Num, { label: "Check-in avant début (min)", value: f.check_in_minutes, onChange: (v) => set("check_in_minutes", v), min: 1, max: 60 })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground leading-relaxed", children: f.batch_gap_minutes > 0 ? `Les ${f.max_concurrent} matchs simultanés max sont lancés par lots. Entre chaque lot, le moteur attend ${f.batch_gap_minutes} min avant de lancer le suivant.` : "Délai entre lots = 0 → lancement au fil de l'eau (dès qu'une place se libère). Mettez > 0 pour lancer par lots espacés." }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground leading-relaxed", children: "⏱ Durée max match : un match qui dépasse cette limite est résolu automatiquement. Check-in : temps accordé aux joueurs pour confirmer leur présence avant le début." })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: create,
          disabled: busy,
          className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-60 flex items-center justify-center gap-2",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }),
            " Créer le tournoi"
          ]
        }
      )
    ] })
  ] });
}
function Field({ label, children }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "block space-y-1", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] font-bold text-muted-foreground", children: label }),
    children
  ] });
}
function Num({ label, value, onChange, min, max }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Field, { label, children: /* @__PURE__ */ jsxRuntimeExports.jsx(
    "input",
    {
      type: "number",
      value,
      min,
      max,
      onChange: (e) => onChange(Number(e.target.value)),
      className: "w-full px-3 py-2 rounded-xl bg-secondary text-sm"
    }
  ) });
}
function SupportMessagesAdmin() {
  const [rows, setRows] = reactExports.useState([]);
  const [filter, setFilter] = reactExports.useState("open");
  const [loading, setLoading] = reactExports.useState(false);
  const [replyEdits, setReplyEdits] = reactExports.useState({});
  const [sending, setSending] = reactExports.useState(null);
  const load = async () => {
    setLoading(true);
    const { data } = await supabase.rpc("admin_list_support_messages", {
      _status: filter === "all" ? null : filter,
      _limit: 100
    });
    setRows(data || []);
    setLoading(false);
  };
  reactExports.useEffect(() => {
    load();
  }, [filter]);
  async function sendReply(id) {
    const text = (replyEdits[id] || "").trim();
    if (text.length < 2) return toast.error("Réponse trop courte");
    setSending(id);
    try {
      const { error } = await supabase.rpc("admin_reply_support", { _id: id, _reply: text });
      if (error) throw error;
      toast.success("Réponse envoyée");
      load();
    } catch (e) {
      toast.error(e?.message || "Erreur");
    } finally {
      setSending(null);
    }
  }
  rows.filter((r) => r.status === "open").length;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between flex-wrap gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 flex-wrap", children: ["open", "answered", "all"].map((s) => /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setFilter(s),
          className: `px-3 py-1.5 rounded-full text-xs font-bold transition-colors ${filter === s ? "bg-primary text-primary-foreground" : "bg-secondary hover:bg-accent"}`,
          children: s === "all" ? "Tous" : s === "open" ? "Ouverts" : "Répondus"
        },
        s
      )) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: load, title: "Rafraîchir", className: "p-2 rounded-full hover:bg-accent", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: `w-4 h-4 ${loading ? "animate-spin" : ""}` }) })
    ] }),
    loading && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-6 text-sm", children: "Chargement…" }),
    !loading && rows.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center py-10 text-muted-foreground", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-8 h-8 mx-auto mb-2 opacity-30" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm font-medium", children: "Aucun message" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-3", children: rows.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-secondary/40 rounded-2xl border border-border/50 p-4 space-y-2.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2 flex-wrap", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-sm", children: r.pseudo }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1 text-xs text-muted-foreground", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3 h-3" }),
          new Date(r.created_at).toLocaleString("fr-FR", {
            day: "2-digit",
            month: "2-digit",
            year: "2-digit",
            hour: "2-digit",
            minute: "2-digit"
          })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm bg-card rounded-xl px-3.5 py-2.5 whitespace-pre-wrap break-words", children: r.message }),
      r.reply && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm bg-primary/10 border border-primary/20 rounded-xl px-3.5 py-2.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 text-xs font-bold text-primary mb-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-3 h-3" }),
          " Réponse envoyée"
        ] }),
        r.reply
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "input",
          {
            type: "text",
            placeholder: r.reply ? "Modifier la réponse…" : "Écrire une réponse…",
            value: replyEdits[r.id] ?? r.reply ?? "",
            onChange: (e) => setReplyEdits((prev) => ({ ...prev, [r.id]: e.target.value })),
            className: "flex-1 bg-card rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => sendReply(r.id),
            disabled: sending === r.id,
            className: "px-4 py-2 rounded-xl bg-primary text-primary-foreground font-semibold text-sm disabled:opacity-50 flex items-center gap-1.5 shrink-0",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-3.5 h-3.5" }),
              " Répondre"
            ]
          }
        )
      ] })
    ] }, r.id)) })
  ] });
}
function DashboardSection({
  onGoToTab
}) {
  const [d, setD] = reactExports.useState({
    deposits: 0,
    withdrawals: 0,
    phoneRequests: 0,
    passwordResets: 0,
    runningTournaments: 0,
    bugReports: 0,
    supportMessages: 0,
    totalUsers: 0,
    activeUsersToday: 0,
    totalGames: 0,
    totalCommission: 0,
    loading: true
  });
  const [days] = reactExports.useState(7);
  const [stats, setStats] = reactExports.useState([]);
  const [statsLoading, setStatsLoading] = reactExports.useState(false);
  const load = async () => {
    setD((prev) => ({ ...prev, loading: true }));
    try {
      const [
        depRes,
        wdRes,
        phoneRes,
        resetRes,
        tRunRes,
        bugRes,
        supportRes,
        usersRes
      ] = await Promise.all([
        supabase.from("deposits").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.from("withdrawals").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.rpc("admin_list_phone_requests"),
        supabase.from("password_reset_requests").select("*", { count: "exact", head: true }).in("status", ["pending", "sent"]),
        supabase.from("tournaments").select("*", { count: "exact", head: true }).eq("status", "running"),
        supabase.from("bug_reports").select("*", { count: "exact", head: true }).eq("status", "open"),
        supabase.from("support_messages").select("*", { count: "exact", head: true }).is("reply", null),
        supabase.from("profiles").select("*", { count: "exact", head: true })
      ]);
      setD({
        deposits: depRes.count ?? 0,
        withdrawals: wdRes.count ?? 0,
        phoneRequests: Array.isArray(phoneRes.data) ? phoneRes.data.length : 0,
        passwordResets: resetRes.count ?? 0,
        runningTournaments: tRunRes.count ?? 0,
        bugReports: bugRes.count ?? 0,
        supportMessages: supportRes.count ?? 0,
        totalUsers: usersRes.count ?? 0,
        activeUsersToday: 0,
        totalGames: 0,
        totalCommission: 0,
        loading: false
      });
    } catch {
      setD((prev) => ({ ...prev, loading: false }));
    }
    setStatsLoading(true);
    try {
      const { data } = await supabase.rpc("admin_stats_daily", { _days: days });
      setStats(data || []);
    } finally {
      setStatsLoading(false);
    }
  };
  reactExports.useEffect(() => {
    load();
  }, []);
  const totals = stats.reduce((acc, r) => ({
    deposits: acc.deposits + Number(r.deposits || 0),
    withdrawals: acc.withdrawals + Number(r.withdrawals || 0),
    commission: acc.commission + Number(r.commission || 0),
    games: acc.games + Number(r.games_finished || 0),
    new_users: acc.new_users + Number(r.new_users || 0),
    active_users: Math.max(acc.active_users, Number(r.active_users || 0))
  }), { deposits: 0, withdrawals: 0, commission: 0, games: 0, new_users: 0, active_users: 0 });
  const netProfit = totals.commission - Math.max(0, totals.withdrawals - totals.deposits);
  const pendingFinance = d.deposits + d.withdrawals;
  const pendingJoueurs = d.phoneRequests + d.passwordResets;
  const pendingContenu = d.bugReports + d.supportMessages;
  const maxCommission = Math.max(1, ...stats.map((r) => Number(r.commission || 0)));
  const cards = [
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Wallet, { className: "w-5 h-5" }), label: "Dépôts en attente", count: d.deposits, tab: "finance", accent: "emerald" },
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Wallet, { className: "w-5 h-5" }), label: "Retraits en attente", count: d.withdrawals, tab: "finance", accent: "rose" },
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-5 h-5" }), label: "Messages support", count: d.supportMessages, tab: "contenu", sectionId: "content-support", accent: "primary" },
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleAlert, { className: "w-5 h-5" }), label: "Signalements", count: d.bugReports, tab: "contenu", accent: "amber" },
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-5 h-5" }), label: "Vérif. téléphone", count: d.phoneRequests, tab: "joueurs", sectionId: "players-security", accent: "sky" },
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-5 h-5" }), label: "Reset mots de passe", count: d.passwordResets, tab: "joueurs", sectionId: "players-security", accent: "violet" },
    { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-5 h-5" }), label: "Tournois en cours", count: d.runningTournaments, tab: "jeux", sectionId: "tournaments-main", accent: "amber" }
  ];
  const ACCENT_CLASSES = {
    emerald: "from-emerald-500/15 to-emerald-500/5 text-emerald-600 border-emerald-500/20",
    rose: "from-rose-500/15 to-rose-500/5 text-rose-600 border-rose-500/20",
    primary: "from-primary/15 to-primary/5 text-primary border-primary/20",
    amber: "from-amber-500/15 to-amber-500/5 text-amber-600 border-amber-500/20",
    sky: "from-sky-500/15 to-sky-500/5 text-sky-600 border-sky-500/20",
    violet: "from-violet-500/15 to-violet-500/5 text-violet-600 border-violet-500/20"
  };
  const totalPending = pendingFinance + pendingJoueurs + pendingContenu + d.runningTournaments;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `rounded-3xl border p-5 ${totalPending > 0 ? "bg-gradient-to-br from-amber-500/10 to-rose-500/5 border-amber-500/30" : "bg-gradient-to-br from-emerald-500/10 to-emerald-500/5 border-emerald-500/20"}`, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] uppercase tracking-wide font-semibold text-muted-foreground", children: totalPending > 0 ? "⏰ En attente d'action" : "✅ Tout est à jour" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-3xl font-extrabold mt-1 ${totalPending > 0 ? "text-amber-600" : "text-emerald-600"}`, children: totalPending }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mt-0.5", children: totalPending > 0 ? "éléments nécessitent votre attention" : "aucune action requise" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: load, className: "p-3 rounded-2xl bg-card hover:bg-accent transition-colors", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: `w-5 h-5 ${d.loading ? "animate-spin" : ""}` }) })
    ] }) }),
    totalPending > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-2 sm:grid-cols-3 gap-2.5", children: cards.filter((c) => c.count > 0).map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => onGoToTab(c.tab, c.sectionId),
        className: `text-left rounded-2xl border p-4 bg-gradient-to-br ${ACCENT_CLASSES[c.accent]} active:scale-95 transition-transform`,
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
            c.icon,
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-2xl font-extrabold", children: c.count })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs font-semibold mt-2 flex items-center gap-1", children: [
            c.label,
            /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowRight, { className: "w-3 h-3" })
          ] })
        ]
      },
      i
    )) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card border border-border/50 p-5 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(TrendingUp, { className: "w-4 h-4 text-primary" }),
          " 7 derniers jours"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => onGoToTab("stats"),
            className: "text-xs text-primary font-semibold flex items-center gap-1 hover:underline",
            children: [
              "Voir détails ",
              /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowRight, { className: "w-3 h-3" })
            ]
          }
        )
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-gradient-to-br from-primary/15 to-primary/5 border border-primary/20 p-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] uppercase tracking-wide text-muted-foreground font-semibold", children: "Bénéfice net estimé" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-2xl font-extrabold ${netProfit >= 0 ? "text-emerald-600" : "text-destructive"}`, children: [
          netProfit >= 0 ? "+" : "",
          Math.round(netProfit).toLocaleString("fr-FR"),
          " Ar"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: "Commission − (retraits − dépôts) sur 7j" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-2 sm:grid-cols-4 gap-2", children: [
        { label: "💰 Commission", value: totals.commission, suffix: "Ar", color: "text-primary" },
        { label: "📥 Dépôts", value: totals.deposits, suffix: "Ar", color: "text-emerald-600" },
        { label: "📤 Retraits", value: totals.withdrawals, suffix: "Ar", color: "text-destructive" },
        { label: "🎮 Parties", value: totals.games, color: "text-sky-600" },
        { label: "👥 Nouveaux", value: totals.new_users, color: "text-fuchsia-600" },
        { label: "⚡ Actifs (pic)", value: totals.active_users, color: "text-teal-600" },
        { label: "📊 Total joueurs", value: d.totalUsers, color: "text-indigo-600" },
        { label: "🏆 Tournois actifs", value: d.runningTournaments, color: "text-amber-600" }
      ].map((s, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary p-3 text-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase text-muted-foreground font-semibold", children: s.label }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-base font-extrabold ${s.color} leading-tight mt-0.5`, children: [
          Math.round(s.value).toLocaleString("fr-FR"),
          s.suffix ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-muted-foreground ml-0.5", children: s.suffix }) : null
        ] })
      ] }, i)) }),
      stats.length > 0 && !statsLoading && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-xs uppercase text-muted-foreground mb-2", children: "Commission par jour" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-end gap-1 h-16", children: [...stats].reverse().map((r) => {
          const v = Number(r.commission || 0);
          const h = Math.max(2, Math.round(v / maxCommission * 100));
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 flex flex-col items-center gap-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(
              "div",
              {
                className: "w-full bg-primary/70 rounded-t",
                style: { height: `${h}%` },
                title: `${new Date(r.day).toLocaleDateString("fr-FR")} · ${Math.round(v).toLocaleString("fr-FR")} Ar`
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[8px] text-muted-foreground", children: new Date(r.day).getDate() })
          ] }, r.day);
        }) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onGoToTab("finance"), className: "rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Wallet, { className: "w-5 h-5 text-emerald-600 mb-2" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Finance" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Dépôts, retraits, transactions" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onGoToTab("joueurs"), className: "rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-5 h-5 text-sky-600 mb-2" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Joueurs" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Comptes, sécurité, modération" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onGoToTab("jeux"), className: "rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-5 h-5 text-amber-600 mb-2" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Jeux & Compétition" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Parties, tournois, classement" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onGoToTab("contenu"), className: "rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-5 h-5 text-violet-600 mb-2" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Contenu" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Support, annonces, bannières" })
      ] })
    ] })
  ] });
}
function AdminPage() {
  const {
    isAdmin,
    loading
  } = useAuth();
  const [tab, setTab] = reactExports.useState("dashboard");
  const [v, setV] = reactExports.useState(0);
  const [pendingFinance, setPendingFinance] = reactExports.useState(null);
  const [pendingJoueurs, setPendingJoueurs] = reactExports.useState(null);
  const [pendingTournois, setPendingTournois] = reactExports.useState(null);
  const [pendingContenu, setPendingContenu] = reactExports.useState(null);
  const refresh = () => setV((x) => x + 1);
  const goToTab = (t, sectionId) => {
    setTab(t);
    if (sectionId) {
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent("admin-section-open", {
          detail: {
            id: sectionId
          }
        }));
      }, 80);
    }
  };
  async function downloadCloudData() {
    toast.info("Export cloud en cours…");
    try {
      const TABLES = ["profiles", "deposits", "withdrawals", "transactions", "admin_logs", "admin_broadcasts", "chess_games", "chess_moves", "domino_games", "domino_participants", "fanorona_games", "fanorona_participants", "ludo_games", "ludo_participants", "rami_games", "rami_participants", "poker_games", "poker_players", "tournament_matches", "tournament_entrants", "referral_events", "referral_settings", "notifications", "chat_rooms", "chat_members", "chat_messages", "chat_mutes", "bug_reports", "support_messages", "money_offers", "password_reset_requests", "achievements", "player_achievements", "game_configs", "app_settings", "user_roles"];
      const tablesData = {};
      const meta = {};
      const BATCH = 8;
      for (let i = 0; i < TABLES.length; i += BATCH) {
        await Promise.all(TABLES.slice(i, i + BATCH).map(async (table) => {
          const {
            data,
            error
          } = await supabase.from(table).select("*").limit(1e3);
          if (error) {
            meta[table] = {
              count: 0,
              error: error.message
            };
            tablesData[table] = [];
          } else {
            meta[table] = {
              count: (data ?? []).length
            };
            tablesData[table] = data ?? [];
          }
        }));
      }
      const ok = Object.values(meta).filter((m) => !m.error);
      const blocked = Object.values(meta).filter((m) => m.error);
      const total = ok.reduce((s, m) => s + m.count, 0);
      const blob = new Blob([JSON.stringify({
        exported_at: (/* @__PURE__ */ new Date()).toISOString(),
        project: "lalaomada",
        tables: tablesData,
        meta
      }, null, 2)], {
        type: "application/json"
      });
      const url2 = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url2;
      a.download = `lalaomada_cloud_export_${(/* @__PURE__ */ new Date()).toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url2);
      toast.success(`Export: ${ok.length} tables (${total} lignes)${blocked.length ? ` · ${blocked.length} bloquées par RLS` : ""}`);
    } catch {
      toast.error("Erreur lors de l'export cloud");
    }
  }
  async function downloadPlayers() {
    toast.info("Collecte des données joueurs en cours…");
    try {
      const {
        data,
        error
      } = await supabase.from("profiles").select("id,pseudo,email,phone,phone_number,balance_ar,player_level,total_games,total_wins,is_banned,banned,status,suspended_until,suspension_reason,warning_count,is_premium,referral_code,referral_unlocked,referred_by,unique_code,created_at,first_deposit_at,first_deposit_amount,first_game_at,terms_accepted_at,phone_verified").order("created_at", {
        ascending: false
      });
      if (error) throw error;
      const rows = data ?? [];
      if (rows.length === 0) {
        toast.warning("Aucun joueur trouvé");
        return;
      }
      const headers = Object.keys(rows[0]);
      const escape = (v2) => {
        if (v2 === null || v2 === void 0) return "";
        const s = String(v2);
        return s.includes(",") || s.includes('"') || s.includes("\n") ? `"${s.replace(/"/g, '""')}"` : s;
      };
      const csv = [headers.join(","), ...rows.map((r) => headers.map((h) => escape(r[h])).join(","))].join("\n");
      const blob = new Blob(["\uFEFF" + csv], {
        type: "text/csv;charset=utf-8;"
      });
      const url2 = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url2;
      a.download = `lalaomada_joueurs_${(/* @__PURE__ */ new Date()).toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(url2);
      toast.success(`${rows.length} joueurs exportés en CSV !`);
    } catch (e) {
      toast.error("Erreur lors de l'export joueurs");
    }
  }
  reactExports.useEffect(() => {
    async function fetchPending() {
      const [{
        count: d
      }, {
        count: w
      }, phoneRes, resetRes, tRunRes, bugRes, supportRes] = await Promise.all([supabase.from("deposits").select("*", {
        count: "exact",
        head: true
      }).eq("status", "pending"), supabase.from("withdrawals").select("*", {
        count: "exact",
        head: true
      }).eq("status", "pending"), supabase.rpc("admin_list_phone_requests"), supabase.from("password_reset_requests").select("*", {
        count: "exact",
        head: true
      }).in("status", ["pending", "sent"]), supabase.from("tournaments").select("*", {
        count: "exact",
        head: true
      }).eq("status", "running"), supabase.from("bug_reports").select("*", {
        count: "exact",
        head: true
      }).eq("status", "open"), supabase.from("support_messages").select("*", {
        count: "exact",
        head: true
      }).is("reply", null)]);
      setPendingFinance((d ?? 0) + (w ?? 0));
      const phoneCount = Array.isArray(phoneRes.data) ? phoneRes.data.length : 0;
      const resetCount = resetRes.count ?? 0;
      setPendingJoueurs(phoneCount + resetCount);
      setPendingTournois(tRunRes.count ?? 0);
      setPendingContenu((bugRes.count ?? 0) + (supportRes.count ?? 0));
    }
    fetchPending();
  }, [v]);
  if (loading) return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center animate-pulse text-muted-foreground", children: "Chargement…" });
  if (!isAdmin) return /* @__PURE__ */ jsxRuntimeExports.jsx(Navigate, { to: "/" });
  return /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSecurityGate, { children: /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-4xl mx-auto px-4 py-6 space-y-5", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSessionsPanel, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("h1", { className: "text-2xl font-extrabold flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Shield, { className: "w-6 h-6 text-primary" }),
        " Panneau Admin"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: downloadCloudData, className: "flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-blue-600 hover:bg-blue-700 text-white text-xs font-semibold transition-colors shadow-sm", title: "Télécharger toutes les données cloud", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(CloudDownload, { className: "w-3.5 h-3.5" }),
          "Cloud"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: downloadPlayers, className: "flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold transition-colors shadow-sm", title: "Télécharger les données de tous les joueurs", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(UserCheck, { className: "w-3.5 h-3.5" }),
          "Joueurs"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: refresh, className: "p-2 rounded-xl hover:bg-accent text-muted-foreground", title: "Actualiser", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: "w-4 h-4" }) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSearchBar, { index: SEARCH_INDEX, onGo: (entry) => {
      setTab(entry.tab);
      setTimeout(() => {
        window.dispatchEvent(new CustomEvent("admin-section-open", {
          detail: {
            id: entry.id
          }
        }));
      }, 80);
    } }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "overflow-x-auto -mx-4 px-4", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1.5 bg-card rounded-2xl p-1.5 shadow-sm border border-border/60 w-max min-w-full", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(T, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(LayoutDashboard, { className: "w-4 h-4" }), active: tab === "dashboard", onClick: () => setTab("dashboard"), label: "Accueil", badge: (pendingFinance ?? 0) + (pendingJoueurs ?? 0) + (pendingContenu ?? 0) + (pendingTournois ?? 0) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(T, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Wallet, { className: "w-4 h-4" }), active: tab === "finance", onClick: () => setTab("finance"), label: "Finance", badge: pendingFinance }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(T, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), active: tab === "joueurs", onClick: () => setTab("joueurs"), label: "Joueurs", badge: pendingJoueurs }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(T, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-4 h-4" }), active: tab === "jeux", onClick: () => setTab("jeux"), label: "Jeux", badge: pendingTournois }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(T, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }), active: tab === "contenu", onClick: () => setTab("contenu"), label: "Contenu", badge: pendingContenu }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(T, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-4 h-4" }), active: tab === "config", onClick: () => setTab("config"), label: "Config" })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      tab === "dashboard" && /* @__PURE__ */ jsxRuntimeExports.jsx(DashboardSection, { onGoToTab: goToTab }),
      tab === "finance" && /* @__PURE__ */ jsxRuntimeExports.jsx(FinanceSection, {}),
      tab === "stats" && /* @__PURE__ */ jsxRuntimeExports.jsx(StatsSection, {}),
      tab === "joueurs" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "players-accounts", title: "👥 Comptes joueurs", description: "Liste, recherche, actions rapides", accent: "primary", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(UsersList, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AdminSection, { id: "players-security", title: "🔐 Demandes de sécurité", description: "Téléphones à vérifier et mots de passe oubliés", accent: "amber", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Shield, { className: "w-4 h-4" }), children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneRequests, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(PasswordResetRequestsAdmin, {})
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "players-chat-mod", title: "🗣️ Modération chat", description: "Utilisateurs sourdinés", accent: "rose", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChatMutesAdmin, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "players-persona", title: "🎭 Persona admin", description: "Alias et apparence publique de l'admin", accent: "violet", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(SlidersVertical, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(PersonaAdmin, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "players-history", title: "📋 Historique joueur", description: "Rechercher et consulter l'historique d'un joueur", accent: "sky", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(History, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(UserHistorySearch, {}) })
      ] }),
      tab === "parties" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AdminSection, { id: "games-live", title: "🎮 Parties en cours", description: "Suivi live et interventions", accent: "primary", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-4 h-4" }), children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(GamesList, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(GamesAdmin, {})
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "games-config", title: "⚙️ Réglages par jeu", description: "Règles, couvertures, badges, capacité", accent: "sky", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameConfigsSection, {}) })
      ] }),
      tab === "jeux" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AdminSection, { id: "games-live", title: "🎮 Parties en cours", description: "Suivi live et interventions", accent: "primary", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-4 h-4" }), children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(GamesList, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(GamesAdmin, {})
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "games-config", title: "⚙️ Réglages par jeu", description: "Règles, couvertures, badges, capacité", accent: "sky", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameConfigsSection, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "tournaments-main", title: "🏆 Tournois", description: "Créer, arbitrer, suivre", accent: "amber", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(TournamentsSection, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "tournaments-seasons", title: "📅 Saisons", description: "Cycles de compétition", accent: "violet", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ChartColumn, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(SeasonsAdmin, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "classement", title: "🥇 Classement", description: "Podium et récompenses", accent: "emerald", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(LeaderboardAdmin, {}) })
      ] }),
      tab === "parties" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AdminSection, { id: "games-live", title: "🎮 Parties en cours", description: "Suivi live et interventions", accent: "primary", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-4 h-4" }), children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(GamesList, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(GamesAdmin, {})
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "games-config", title: "⚙️ Réglages par jeu", description: "Règles, couvertures, badges, capacité", accent: "sky", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameConfigsSection, {}) })
      ] }),
      tab === "tournois" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "tournaments-main", title: "🏆 Tournois", description: "Créer, arbitrer, suivre", accent: "primary", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(TournamentsSection, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "tournaments-seasons", title: "📅 Saisons & classements", description: "Cycles de compétition", accent: "violet", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ChartColumn, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(SeasonsAdmin, {}) })
      ] }),
      tab === "classement" && /* @__PURE__ */ jsxRuntimeExports.jsx(LeaderboardAdmin, {}),
      tab === "contenu" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "content-pause", title: "🛑 Contrôle global", description: "Mettre l'app en pause", accent: "rose", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(PauseControl, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AdminSection, { id: "content-comm", title: "📣 Communication", description: "Annonces, offres, messages", accent: "amber", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4" }), children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(AnnouncementsAdmin, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(OffersAdmin, {})
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "content-support", title: "💬 Messages support", description: "Messages des joueurs depuis le centre d'aide", accent: "primary", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }), defaultOpen: true, children: /* @__PURE__ */ jsxRuntimeExports.jsx(SupportMessagesAdmin, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "content-banners", title: "🎨 Bannières d'accueil", description: "Carousel promo sur la page d'accueil", accent: "violet", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ImagePlus, { className: "w-4 h-4" }), defaultOpen: true, children: /* @__PURE__ */ jsxRuntimeExports.jsx(BannersAdmin, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AdminSection, { id: "content-help", title: "📚 Aide, tutoriels & textes", description: "Contenu pédagogique, textes d'aide, CGU, mentions légales", accent: "sky", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Info, { className: "w-4 h-4" }), children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(TutorialsAdmin, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(CmsEditor, {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx(ContentTextsEditor, {})
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "content-communities", title: "🌍 Communautés", description: "Réseaux et liens externes", accent: "emerald", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(Communities, {}) })
      ] }),
      tab === "config" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "config-security", title: "🔐 Sécurité", description: "PIN admin", accent: "rose", defaultOpen: true, icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(AdminPinSetup, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "config-timers", title: "⏱️ Timers", description: "Tour, salle d'attente, minuteurs globaux", accent: "primary", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameTimersQuick, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "config-app", title: "🛠️ Paramètres de l'application", description: "Finance, contact, chat, points, statut des jeux", accent: "sky", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(AppConfigForm, {}) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(AdminSection, { id: "config-referral", title: "🤝 Parrainage", description: "Commission, niveaux, anti-fraude", accent: "emerald", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), children: /* @__PURE__ */ jsxRuntimeExports.jsx(ReferralAdmin, {}) })
      ] })
    ] }, v)
  ] }) });
}
const SEARCH_INDEX = [
  // Dashboard
  {
    id: "dashboard",
    tab: "dashboard",
    tabLabel: "Accueil",
    title: "🏠 Tableau de bord",
    description: "Vue d'ensemble, éléments en attente, stats rapides",
    keywords: "dashboard accueil overview stats pending attente resume"
  },
  // Finance
  {
    id: "finance",
    tab: "finance",
    tabLabel: "Finance",
    title: "💰 Finance",
    description: "Dépôts, retraits, transactions",
    keywords: "argent solde depot retrait commission mobile money"
  },
  // Stats
  {
    id: "stats",
    tab: "stats",
    tabLabel: "Stats",
    title: "📊 Statistiques",
    description: "Vue d'ensemble de l'app",
    keywords: "chiffres kpi utilisateurs actifs"
  },
  // Joueurs
  {
    id: "players-accounts",
    tab: "joueurs",
    tabLabel: "Joueurs",
    title: "👥 Comptes joueurs",
    description: "Liste, recherche, ban, suspension",
    keywords: "utilisateur user profil banni suspension pseudo email"
  },
  {
    id: "players-security",
    tab: "joueurs",
    tabLabel: "Joueurs",
    title: "🔐 Demandes de sécurité",
    description: "Téléphone, mot de passe oublié",
    keywords: "telephone otp verification mot de passe reset password"
  },
  {
    id: "players-chat-mod",
    tab: "joueurs",
    tabLabel: "Joueurs",
    title: "🗣️ Modération chat",
    description: "Mute / sourdine",
    keywords: "mute sourdine chat moderation ban"
  },
  {
    id: "players-persona",
    tab: "joueurs",
    tabLabel: "Joueurs",
    title: "🎭 Persona admin",
    description: "Alias public de l'admin",
    keywords: "alias persona apparence admin avatar"
  },
  // Parties
  {
    id: "games-live",
    tab: "jeux",
    tabLabel: "Jeux",
    title: "🎮 Parties en cours",
    description: "Suivi live des parties",
    keywords: "live partie active jeu terminer annuler"
  },
  {
    id: "games-config",
    tab: "jeux",
    tabLabel: "Jeux",
    title: "⚙️ Réglages par jeu",
    description: "Règles, couvertures, badges, capacité",
    keywords: "regles cover image badge capacite instructions ludo chess domino rami fanorona poker"
  },
  // Tournois
  {
    id: "tournaments-main",
    tab: "jeux",
    tabLabel: "Jeux",
    title: "🏆 Tournois",
    description: "Créer, arbitrer, suivre",
    keywords: "tournoi bracket inscription arbitrage forfait test bot"
  },
  {
    id: "tournaments-seasons",
    tab: "jeux",
    tabLabel: "Jeux",
    title: "📅 Saisons & classements",
    description: "Cycles de compétition",
    keywords: "saison season leaderboard cycle"
  },
  // Classement
  {
    id: "classement",
    tab: "jeux",
    tabLabel: "Jeux",
    title: "🥇 Classement",
    description: "Podium et récompenses",
    keywords: "leaderboard classement trophee podium winners recompenses"
  },
  // Contenu
  {
    id: "content-pause",
    tab: "contenu",
    tabLabel: "Contenu",
    title: "🛑 Contrôle global",
    description: "Mettre l'app en pause",
    keywords: "pause maintenance stop app fermer"
  },
  {
    id: "content-comm",
    tab: "contenu",
    tabLabel: "Contenu",
    title: "📣 Communication",
    description: "Annonces, offres, messages",
    keywords: "annonce offre message notification broadcast push"
  },
  {
    id: "content-support",
    tab: "contenu",
    tabLabel: "Contenu",
    title: "💬 Messages support",
    description: "Répondre aux joueurs",
    keywords: "support chat message repondre joueur aide centre"
  },
  {
    id: "content-banners",
    tab: "contenu",
    tabLabel: "Contenu",
    title: "🎨 Bannières d'accueil",
    description: "Carousel promo",
    keywords: "banniere carousel promo image accueil slider"
  },
  {
    id: "content-help",
    tab: "contenu",
    tabLabel: "Contenu",
    title: "📚 Aide & tutoriels",
    description: "CMS, FAQ, conditions",
    keywords: "tutoriel aide help faq cgu conditions cms markdown texte"
  },
  {
    id: "content-communities",
    tab: "contenu",
    tabLabel: "Contenu",
    title: "🌍 Communautés",
    description: "Réseaux et liens externes",
    keywords: "reseau social communaute facebook whatsapp telegram lien"
  },
  // Config
  {
    id: "config-timers",
    tab: "config",
    tabLabel: "Config",
    title: "⏱️ Timers",
    description: "Tour, salle d'attente, minuteurs Échecs/Fanorona",
    keywords: "timer temps duree tour salle attente ready pret minuteur echec fanorona chrono"
  },
  {
    id: "config-app",
    tab: "config",
    tabLabel: "Config",
    title: "🛠️ Paramètres de l'application",
    description: "Contact, chat, spectateurs, AFK, statut des jeux",
    keywords: "contact facebook whatsapp email telephone apk download chat spectateur afk statut jeu actif desactive"
  },
  {
    id: "config-points",
    tab: "config",
    tabLabel: "Config",
    title: "🎯 Points & niveaux",
    description: "Barème XP",
    keywords: "points xp niveau level bareme progression"
  },
  {
    id: "config-referral",
    tab: "config",
    tabLabel: "Config",
    title: "🤝 Parrainage",
    description: "Commission, fenêtre, anti-fraude",
    keywords: "parrainage referral referral_events commission 5% 10 parties fraude bonus code invite"
  },
  {
    id: "config-advanced",
    tab: "config",
    tabLabel: "Config",
    title: "🧩 Réglages avancés",
    description: "Techniques et divers",
    keywords: "avance technique divers debug"
  }
];
function T({
  icon,
  label,
  active,
  onClick,
  danger,
  badge
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: ["px-3 py-2 rounded-xl flex items-center gap-1.5 text-sm font-semibold transition-all shrink-0", active ? danger ? "bg-rose-500 text-white" : "bg-primary text-primary-foreground" : danger ? "hover:bg-rose-50 dark:hover:bg-rose-950/30 text-rose-500" : "hover:bg-accent text-muted-foreground"].join(" "), children: [
    icon,
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: label }),
    badge > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "bg-rose-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full leading-none min-w-[18px] text-center", children: badge })
  ] });
}
function Card({
  children
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3", children });
}
function FinanceSection() {
  const [scope, setScope] = reactExports.useState("pending");
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(FinancialIntegrityCard, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setScope("pending"), className: `px-4 py-2 rounded-full text-sm font-semibold ${scope === "pending" ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: "⏳ En attente" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setScope("all"), className: `px-4 py-2 rounded-full text-sm font-semibold ${scope === "all" ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: "📋 Historique" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(DepositsList, { scope }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(WithdrawalsList, { scope })
  ] });
}
function FinancialIntegrityCard() {
  const [kpi, setKpi] = reactExports.useState(null);
  const [report, setReport] = reactExports.useState(null);
  const [busy, setBusy] = reactExports.useState(false);
  const fmt = (n) => Number(n || 0).toLocaleString("fr-FR") + " Ar";
  const loadKpi = async () => {
    const {
      data,
      error
    } = await supabase.rpc("admin_finance_kpi");
    if (error) return toast.error(error.message);
    setKpi(data);
  };
  reactExports.useEffect(() => {
    loadKpi();
  }, []);
  const runAudit = async () => {
    setBusy(true);
    const {
      data,
      error
    } = await supabase.rpc("admin_reconcile_balances");
    setBusy(false);
    if (error) return toast.error(error.message);
    setReport(data || []);
    if (!data || data.length === 0) toast.success("✅ Aucun écart détecté");
  };
  const runAlign = async () => {
    if (!confirm("Aligner automatiquement tous les soldes sur l'historique ? Une transaction 'admin_adjust' traçable sera créée pour chaque correction.")) return;
    setBusy(true);
    const {
      data,
      error
    } = await supabase.rpc("admin_align_balances");
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(`✅ ${data?.length || 0} solde(s) aligné(s)`);
    setReport(null);
    loadKpi();
  };
  const gap = Number(kpi?.reconciliation_gap || 0);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm uppercase text-muted-foreground flex items-center gap-2 mb-3", children: "🔐 Intégrité financière" }),
    kpi ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 md:grid-cols-3 gap-2 text-xs", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Dépôts", value: fmt(kpi.total_deposits), tone: "emerald" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Retraits", value: fmt(kpi.total_withdraws), tone: "rose" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Mises jouées", value: fmt(kpi.total_stakes), tone: "slate" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Gains payés", value: fmt(kpi.total_payouts), tone: "slate" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Remboursements", value: fmt(kpi.total_refunds), tone: "slate" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Bonus + Parrainage", value: fmt(kpi.total_bonus), tone: "slate" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Total soldes", value: fmt(kpi.sum_balances), tone: "slate" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Total ledger", value: fmt(kpi.sum_transactions), tone: "slate" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Écart", value: fmt(gap), tone: Math.abs(gap) < 1 ? "emerald" : "amber" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Retraits en attente", value: fmt(kpi.pending_withdrawals), tone: "amber" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Dépôts en attente", value: fmt(kpi.pending_deposits), tone: "amber" })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Chargement…" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap gap-2 mt-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: runAudit, className: "px-3 py-1.5 rounded-full bg-secondary text-xs font-semibold disabled:opacity-50", children: "🔎 Lancer l'audit" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: runAlign, className: "px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-semibold disabled:opacity-50", children: "🛠 Aligner automatiquement" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { disabled: busy, onClick: async () => {
        setBusy(true);
        const {
          data,
          error
        } = await supabase.rpc("admin_audit_unlogged_changes", {
          _hours: 24
        });
        setBusy(false);
        if (error) return toast.error(error.message);
        const rows = data || [];
        if (rows.length === 0) toast.success("✅ Aucun mouvement non tracé (24h)");
        else toast.warning(`⚠️ ${rows.length} utilisateur(s) avec des mouvements non tracés`, {
          description: rows.slice(0, 3).map((r) => `${r.pseudo}: ${Number(r.unlogged).toLocaleString("fr-FR")} Ar`).join(" · ")
        });
      }, className: "px-3 py-1.5 rounded-full bg-secondary text-xs font-semibold disabled:opacity-50", children: "🕵️ Détecter mouvements non tracés (24h)" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: loadKpi, className: "px-3 py-1.5 rounded-full bg-secondary text-xs font-semibold", children: "↻ Recharger KPI" })
    ] }),
    report && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-3 border-t border-border/60 pt-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs font-semibold mb-2", children: [
        "Écarts détectés : ",
        report.length
      ] }),
      report.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-emerald-600", children: "Ledger cohérent." }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1 max-h-64 overflow-y-auto text-xs", children: report.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between gap-2 border-b border-border/40 py-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: r.pseudo || "—" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
          "solde ",
          fmt(r.balance),
          " · txs ",
          fmt(r.tx_sum)
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: Number(r.diff) > 0 ? "text-amber-600 font-semibold" : "text-sky-600 font-semibold", children: [
          Number(r.diff) > 0 ? "+" : "",
          fmt(r.diff)
        ] })
      ] }, r.user_id)) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(HouseIncomePanel, {})
  ] });
}
function HouseIncomePanel() {
  const [rows, setRows] = reactExports.useState(null);
  const [days, setDays] = reactExports.useState(30);
  const fmt = (n) => Number(n || 0).toLocaleString("fr-FR") + " Ar";
  const load = async () => {
    const since = new Date(Date.now() - days * 864e5).toISOString();
    const {
      data,
      error
    } = await supabase.rpc("admin_house_income", {
      _since: since
    });
    if (error) return toast.error(error.message);
    setRows(data || []);
  };
  reactExports.useEffect(() => {
    load();
  }, [days]);
  const totalCom = (rows || []).reduce((s, r) => s + Number(r.commission_total || 0), 0);
  const totalHouse = (rows || []).reduce((s, r) => s + Number(r.house_win_total || 0), 0);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-4 border-t border-border/60 pt-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-semibold", children: "💰 Revenus de la maison" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("select", { value: days, onChange: (e) => setDays(Number(e.target.value)), className: "text-[11px] bg-secondary rounded px-1.5 py-0.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 7, children: "7 j" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 30, children: "30 j" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 90, children: "90 j" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: 365, children: "1 an" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2 text-xs mb-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Commissions", value: fmt(totalCom), tone: "emerald" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Kpi, { label: "Gains vs bots", value: fmt(totalHouse), tone: "emerald" })
    ] }),
    rows && rows.length > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1 text-xs", children: rows.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex justify-between border-b border-border/40 py-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "capitalize font-semibold", children: r.game_type }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
        "com. ",
        fmt(r.commission_total),
        " · maison ",
        fmt(r.house_win_total)
      ] })
    ] }, r.game_type)) }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground", children: "Aucun revenu sur la période." })
  ] });
}
function Kpi({
  label,
  value,
  tone
}) {
  const bg = {
    emerald: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300",
    rose: "bg-rose-500/10 text-rose-700 dark:text-rose-300",
    amber: "bg-amber-500/10 text-amber-700 dark:text-amber-300",
    slate: "bg-secondary text-foreground"
  }[tone];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-lg px-2 py-1.5 ${bg}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase tracking-wide opacity-75", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: value })
  ] });
}
function DepositsList({
  scope
}) {
  const [items, setItems] = reactExports.useState([]);
  const load = async () => {
    let q = supabase.from("deposits").select("*").order("created_at", {
      ascending: false
    }).limit(200);
    if (scope === "pending") q = q.eq("status", "pending");
    else q = q.in("status", ["approved", "rejected"]);
    const {
      data,
      error
    } = await q;
    if (error) {
      toast.error(error.message);
      return;
    }
    const rows = data || [];
    const ids = Array.from(new Set(rows.map((r) => r.user_id)));
    let profMap = {};
    if (ids.length) {
      const {
        data: profs
      } = await supabase.from("profiles").select("id,pseudo,email,unique_code").in("id", ids);
      profMap = Object.fromEntries((profs || []).map((p) => [p.id, p]));
    }
    setItems(rows.map((r) => ({
      ...r,
      profiles: profMap[r.user_id]
    })));
  };
  reactExports.useEffect(() => {
    load();
  }, [scope]);
  const act = async (id, ok) => {
    const {
      error
    } = await supabase.rpc("admin_process_deposit", {
      _id: id,
      _approve: ok
    });
    if (error) return toast.error(error.message);
    toast.success(ok ? "✅ Dépôt approuvé — solde crédité" : "❌ Dépôt rejeté");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm uppercase text-muted-foreground flex items-center gap-2", children: [
      "💰 Dépôts ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] normal-case font-normal bg-secondary px-2 py-0.5 rounded-full", children: items.length })
    ] }),
    items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center text-muted-foreground py-3 text-sm", children: [
      "Aucun dépôt ",
      scope === "pending" ? "en attente" : ""
    ] }) : items.map((d) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "border-t border-border/60 pt-3 space-y-1.5", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
          Number(d.amount).toLocaleString("fr-FR"),
          " Ar ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-normal text-muted-foreground", children: [
            "· ",
            d.method
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: d.profiles?.pseudo || "—" }),
          " ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
            "(",
            d.profiles?.email,
            ")"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground font-mono", children: d.profiles?.unique_code || "—" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "Réf payeur: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "font-mono text-primary", children: d.user_reference || d.reference })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "Tel: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: d.user_phone || "—" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: new Date(d.created_at).toLocaleString("fr-FR") }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "Statut: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: d.status === "pending" ? "text-amber-600" : d.status === "approved" ? "text-emerald-600" : "text-destructive", children: d.status })
        ] })
      ] }),
      d.status === "pending" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col gap-1.5 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => act(d.id, true), className: "px-3 py-1.5 rounded-full bg-emerald-500 text-white text-xs font-semibold", children: "✓ Valider" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => act(d.id, false), className: "px-3 py-1.5 rounded-full bg-destructive text-white text-xs font-semibold", children: "✕ Refuser" })
      ] })
    ] }) }, d.id))
  ] });
}
function WithdrawalsList({
  scope
}) {
  const [items, setItems] = reactExports.useState([]);
  const load = async () => {
    let q = supabase.from("withdrawals").select("*").order("created_at", {
      ascending: false
    }).limit(200);
    if (scope === "pending") q = q.eq("status", "pending");
    else q = q.in("status", ["approved", "rejected"]);
    const {
      data,
      error
    } = await q;
    if (error) {
      toast.error(error.message);
      return;
    }
    const rows = data || [];
    const ids = Array.from(new Set(rows.map((r) => r.user_id)));
    let profMap = {};
    if (ids.length) {
      const {
        data: profs
      } = await supabase.from("profiles").select("id,pseudo,email,unique_code").in("id", ids);
      profMap = Object.fromEntries((profs || []).map((p) => [p.id, p]));
    }
    setItems(rows.map((r) => ({
      ...r,
      profiles: profMap[r.user_id]
    })));
  };
  reactExports.useEffect(() => {
    load();
  }, [scope]);
  const act = async (id, ok) => {
    const {
      error
    } = await supabase.rpc("admin_process_withdrawal", {
      _id: id,
      _approve: ok
    });
    if (error) return toast.error(error.message);
    toast.success(ok ? "✅ Retrait approuvé" : "❌ Retrait rejeté");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm uppercase text-muted-foreground flex items-center gap-2", children: [
      "💸 Retraits ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] normal-case font-normal bg-secondary px-2 py-0.5 rounded-full", children: items.length })
    ] }),
    items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center text-muted-foreground py-3 text-sm", children: [
      "Aucun retrait ",
      scope === "pending" ? "en attente" : ""
    ] }) : items.map((d) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "border-t border-border/60 pt-3 space-y-1.5", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
          Number(d.amount).toLocaleString("fr-FR"),
          " Ar ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-normal text-muted-foreground", children: [
            "· ",
            d.method
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: d.profiles?.pseudo || "—" }),
          " ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
            "(",
            d.profiles?.email,
            ")"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground font-mono", children: d.profiles?.unique_code || "—" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "📱 Tel destinataire: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "text-primary", children: d.user_phone })
        ] }),
        d.bank_name && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "🏦 Banque: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "text-primary", children: d.bank_name })
        ] }),
        d.bank_account_number && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "💳 Compte: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "font-mono text-primary", children: d.bank_account_number })
        ] }),
        d.recipient_name && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "👤 Nom destinataire: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "text-foreground", children: d.recipient_name })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: new Date(d.created_at).toLocaleString("fr-FR") }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "Statut: ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: d.status === "pending" ? "text-amber-600" : d.status === "approved" ? "text-emerald-600" : "text-destructive", children: d.status })
        ] })
      ] }),
      d.status === "pending" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col gap-1.5 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => act(d.id, true), className: "px-3 py-1.5 rounded-full bg-emerald-500 text-white text-xs font-semibold", children: "✓ Valider" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => act(d.id, false), className: "px-3 py-1.5 rounded-full bg-destructive text-white text-xs font-semibold", children: "✕ Refuser" })
      ] })
    ] }) }, d.id))
  ] });
}
const PERIODS = [{
  d: 1,
  l: "Aujourd'hui"
}, {
  d: 2,
  l: "2j"
}, {
  d: 7,
  l: "7j"
}, {
  d: 14,
  l: "14j"
}, {
  d: 30,
  l: "30j"
}];
function StatsSection() {
  const [days, setDays] = reactExports.useState(7);
  const [rows, setRows] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(false);
  const load = async () => {
    setLoading(true);
    const {
      data,
      error
    } = await supabase.rpc("admin_stats_daily", {
      _days: days
    });
    setLoading(false);
    if (error) return toast.error(error.message);
    setRows(data || []);
  };
  reactExports.useEffect(() => {
    load();
  }, [days]);
  const totals = rows.reduce((acc, r) => ({
    deposits: acc.deposits + Number(r.deposits || 0),
    withdrawals: acc.withdrawals + Number(r.withdrawals || 0),
    wins: acc.wins + Number(r.wins || 0),
    commission: acc.commission + Number(r.commission || 0),
    stakes: acc.stakes + Number(r.stakes || 0),
    new_users: acc.new_users + Number(r.new_users || 0),
    active_users: Math.max(acc.active_users, Number(r.active_users || 0)),
    games: acc.games + Number(r.games_finished || 0)
  }), {
    deposits: 0,
    withdrawals: 0,
    wins: 0,
    commission: 0,
    stakes: 0,
    new_users: 0,
    active_users: 0,
    games: 0
  });
  const netProfit = totals.commission - Math.max(0, totals.withdrawals - totals.deposits);
  const maxCommission = Math.max(1, ...rows.map((r) => Number(r.commission || 0)));
  const exportCsv = () => {
    const header = "Date;Dépôts;Retraits;Gains joueurs;Commission;Mises;Nouveaux;Actifs;Parties\n";
    const body = rows.map((r) => [new Date(r.day).toLocaleDateString("fr-FR"), Math.round(r.deposits), Math.round(r.withdrawals), Math.round(r.wins), Math.round(r.commission), Math.round(r.stakes), r.new_users, r.active_users, r.games_finished].join(";")).join("\n");
    const blob = new Blob([header + body], {
      type: "text/csv;charset=utf-8"
    });
    const url2 = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url2;
    a.download = `stats-${days}j-${(/* @__PURE__ */ new Date()).toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url2);
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap items-center justify-between gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-2", children: PERIODS.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setDays(p.d), className: `px-3 py-1.5 rounded-full text-sm font-semibold transition ${days === p.d ? "bg-primary text-primary-foreground shadow" : "bg-secondary hover:bg-secondary/70"}`, children: p.l }, p.d)) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: exportCsv, disabled: loading || rows.length === 0, className: "px-3 py-1.5 rounded-full text-xs font-semibold bg-secondary hover:bg-secondary/70 disabled:opacity-50", children: "📥 Export CSV" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-3 rounded-2xl bg-gradient-to-br from-primary/15 to-primary/5 border border-primary/20 p-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] uppercase tracking-wide text-muted-foreground font-semibold", children: "Bénéfice net estimé" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-2xl font-extrabold ${netProfit >= 0 ? "text-emerald-600" : "text-destructive"}`, children: [
          netProfit >= 0 ? "+" : "",
          Math.round(netProfit).toLocaleString("fr-FR"),
          " Ar"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
          "Commission − (retraits − dépôts) sur ",
          days,
          "j"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 sm:grid-cols-4 gap-2 pt-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "💰 Commission", value: totals.commission, color: "text-primary", suffix: "Ar" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "🎯 Mises totales", value: totals.stakes, color: "text-indigo-600", suffix: "Ar" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "📥 Dépôts", value: totals.deposits, color: "text-emerald-600", suffix: "Ar" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "📤 Retraits", value: totals.withdrawals, color: "text-destructive", suffix: "Ar" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "🏆 Gains payés", value: totals.wins, color: "text-amber-600", suffix: "Ar" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "🎮 Parties", value: totals.games, color: "text-sky-600" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "👥 Nouveaux", value: totals.new_users, color: "text-fuchsia-600" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Stat, { label: "⚡ Actifs (pic/j)", value: totals.active_users, color: "text-teal-600" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm uppercase text-muted-foreground mb-2", children: "Commission par jour" }),
      loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-3", children: "Chargement…" }) : rows.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-3 text-sm", children: "Aucune donnée" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-end gap-1 h-24", children: [...rows].reverse().map((r) => {
        const v = Number(r.commission || 0);
        const h = Math.max(2, Math.round(v / maxCommission * 100));
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 flex flex-col items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full bg-primary/70 hover:bg-primary rounded-t transition", style: {
            height: `${h}%`
          }, title: `${new Date(r.day).toLocaleDateString("fr-FR")} · ${Math.round(v).toLocaleString("fr-FR")} Ar` }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[8px] text-muted-foreground", children: new Date(r.day).getDate() })
        ] }, r.day);
      }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm uppercase text-muted-foreground", children: "Détail par jour" }),
      loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-3", children: "Chargement…" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "overflow-x-auto -mx-3 px-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("table", { className: "w-full text-xs min-w-[560px]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("thead", { children: /* @__PURE__ */ jsxRuntimeExports.jsxs("tr", { className: "text-left text-muted-foreground border-b border-border/60", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "py-2", children: "Date" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right", children: "Dépôts" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right", children: "Retraits" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right", children: "Commission" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right", children: "Parties" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right", children: "Nouveaux" })
        ] }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("tbody", { children: rows.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("tr", { className: "border-b border-border/40 last:border-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("td", { className: "py-2 font-semibold", children: new Date(r.day).toLocaleDateString("fr-FR", {
            weekday: "short",
            day: "2-digit",
            month: "2-digit"
          }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("td", { className: "text-right text-emerald-600", children: [
            "+",
            Number(r.deposits).toLocaleString("fr-FR")
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("td", { className: "text-right text-destructive", children: [
            "-",
            Number(r.withdrawals).toLocaleString("fr-FR")
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("td", { className: "text-right text-primary font-semibold", children: Math.round(Number(r.commission)).toLocaleString("fr-FR") }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("td", { className: "text-right text-sky-600", children: r.games_finished }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("td", { className: "text-right text-fuchsia-600", children: r.new_users })
        ] }, r.day)) })
      ] }) })
    ] })
  ] });
}
function Stat({
  label,
  value,
  color,
  suffix
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary p-3 text-center", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase text-muted-foreground font-semibold", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-base font-extrabold ${color} leading-tight mt-0.5`, children: [
      Math.round(value).toLocaleString("fr-FR"),
      suffix ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-semibold text-muted-foreground ml-0.5", children: suffix }) : null
    ] })
  ] });
}
function UserHistorySearch() {
  const [q, setQ] = reactExports.useState("");
  const [users, setUsers] = reactExports.useState([]);
  const [hist, setHist] = reactExports.useState(null);
  const search = async () => {
    if (!q.trim()) return;
    const {
      data
    } = await supabase.rpc("admin_list_users");
    setUsers((data || []).filter((u) => u.pseudo?.toLowerCase().includes(q.toLowerCase()) || u.email?.toLowerCase().includes(q.toLowerCase())).slice(0, 10));
  };
  const view = async (u) => {
    const {
      data,
      error
    } = await supabase.rpc("admin_user_history", {
      _user_id: u.id
    });
    if (error) return toast.error(error.message);
    setHist(data);
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm uppercase text-muted-foreground", children: "Historique d'un joueur" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: q, onChange: (e) => setQ(e.target.value), placeholder: "pseudo ou email", className: "flex-1 px-4 py-2 rounded-full bg-card border border-border outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: search, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold", children: "Chercher" })
    ] }),
    users.length > 0 && !hist && users.map((u) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => view(u), className: "w-full text-left px-3 py-2 rounded-xl hover:bg-accent", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold", children: u.pseudo }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground", children: [
        u.email,
        " · ",
        Math.round(Number(u.balance_ar)).toLocaleString("fr-FR"),
        " Ar"
      ] })
    ] }, u.id)),
    hist && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
        setHist(null);
        setUsers([]);
        setQ("");
      }, className: "text-xs underline", children: "← retour" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
        hist.profile?.pseudo,
        " — ",
        Math.round(Number(hist.profile?.balance_ar || 0)).toLocaleString("fr-FR"),
        " Ar"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { title: `Transactions (${hist.transactions?.length || 0})`, items: hist.transactions, render: (t) => `${new Date(t.created_at).toLocaleDateString("fr-FR")} · ${t.type} · ${Number(t.amount).toLocaleString("fr-FR")} Ar${t.note ? " — " + t.note : ""}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { title: `Dépôts (${hist.deposits?.length || 0})`, items: hist.deposits, render: (d) => `${new Date(d.created_at).toLocaleDateString("fr-FR")} · ${Number(d.amount).toLocaleString("fr-FR")} Ar · ${d.status}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { title: `Retraits (${hist.withdrawals?.length || 0})`, items: hist.withdrawals, render: (w) => `${new Date(w.created_at).toLocaleDateString("fr-FR")} · ${Number(w.amount).toLocaleString("fr-FR")} Ar · ${w.status}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { title: `Parties (${hist.games?.length || 0})`, items: hist.games, render: (g) => `${g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : "—"} · mise ${Number(g.stake).toLocaleString("fr-FR")} Ar · ${g.status}${g.won ? " · 🏆 gagné" : ""}` })
    ] })
  ] });
}
function Section({
  title,
  items,
  render
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs uppercase font-bold text-muted-foreground", children: title }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-0.5 max-h-48 overflow-y-auto", children: (items || []).map((x, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs border-b border-border/40 py-1", children: render(x) }, i)) })
  ] });
}
function UsersList() {
  const confirm2 = useConfirm();
  const [q, setQ] = reactExports.useState("");
  const [sort, setSort] = reactExports.useState("recent");
  const [items, setItems] = reactExports.useState([]);
  const [showList, setShowList] = reactExports.useState(false);
  const [loading, setLoading] = reactExports.useState(false);
  const isBotUser = (u) => u?.is_bot === true || /@bot\.lalaomada\.internal$/i.test(u?.email || "") || /@lalao\.local$/i.test(u?.email || "") || /^chessbot_/i.test(u?.email || "");
  const load = async () => {
    setLoading(true);
    try {
      if (q.trim()) {
        const {
          data
        } = await supabase.rpc("admin_search_users", {
          _q: q
        });
        setItems((data || []).filter((u) => !isBotUser(u)));
      } else {
        const {
          data
        } = await supabase.rpc("admin_list_users_sorted", {
          _sort: sort
        });
        setItems((data || []).filter((u) => !isBotUser(u)));
      }
    } finally {
      setLoading(false);
    }
  };
  reactExports.useEffect(() => {
    if (showList) load();
  }, [sort, showList]);
  const adjust = async (id) => {
    const v = prompt("Montant à ajouter/retirer (ex: +500 ou -200):");
    if (!v) return;
    const note = prompt("Note (visible dans l'historique):") || "";
    const {
      error
    } = await supabase.rpc("admin_adjust_balance", {
      _user_id: id,
      _amount: Number(v),
      _note: note
    });
    if (error) return toast.error(error.message);
    toast.success("Solde ajusté");
    load();
  };
  const ban = async (id, b) => {
    if (b && !await confirm2({
      title: "Bannir cet utilisateur ? Il ne pourra plus se connecter.",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("admin_set_user_banned", {
      _user_id: id,
      _banned: b
    });
    if (error) return toast.error(error.message);
    toast.success(b ? "Utilisateur banni" : "Utilisateur débanni");
    load();
  };
  const permanentlyDelete = async (u) => {
    const ok = await confirm2({
      title: `Supprimer définitivement ${u.pseudo} ?`,
      description: "Toutes les données de ce joueur (profil, transactions, historique) seront effacées de la plateforme. Cette action est irréversible.",
      confirmLabel: "Supprimer définitivement",
      destructive: true
    });
    if (!ok) return;
    const {
      error
    } = await supabase.rpc("admin_permanently_delete_user", {
      _user_id: u.id
    });
    if (error) return toast.error(error.message);
    toast.success(`Compte de ${u.pseudo} supprimé définitivement.`);
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-4", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-base font-bold", children: "👥 Joueurs" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Recherche, tri et gestion des comptes" })
        ] }),
        showList && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] px-2 py-1 rounded-full bg-secondary font-semibold", children: items.length })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground text-sm", children: "🔍" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: q, onChange: (e) => setQ(e.target.value), onKeyDown: (e) => {
          if (e.key === "Enter") {
            setShowList(true);
            load();
          }
        }, placeholder: "Pseudo, email ou ID unique…", className: "w-full pl-9 pr-3 py-2.5 rounded-xl bg-secondary/60 border border-border/60 outline-none focus:border-primary focus:bg-card text-sm transition" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center gap-1 p-1 rounded-xl bg-secondary/50 text-xs font-semibold", children: [{
        k: "recent",
        label: "Récents"
      }, {
        k: "balance",
        label: "Solde"
      }, {
        k: "pseudo",
        label: "A–Z"
      }].map((o) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setSort(o.k), className: `flex-1 py-1.5 rounded-lg transition ${sort === o.k ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"}`, children: o.label }, o.k)) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
        setShowList(true);
        load();
      }, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground font-semibold text-sm shadow-sm active:scale-[0.99] transition", children: showList ? "🔄 Actualiser" : "👥 Afficher la liste" })
    ] }),
    showList && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-4 space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] uppercase tracking-wide text-muted-foreground font-semibold", children: "Résultats" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowList(false), className: "text-[11px] text-muted-foreground hover:text-foreground underline", children: "Masquer" })
      ] }),
      loading && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-xs text-muted-foreground py-6", children: "Chargement…" }),
      !loading && items.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-xs text-muted-foreground py-6", children: "Aucun joueur" }),
      !loading && items.map((u) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-3 rounded-xl bg-secondary/40 border border-border/40 hover:border-border transition space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm flex items-center gap-1.5 flex-wrap", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: u.pseudo }),
              u.is_admin && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] px-1.5 py-0.5 rounded-full bg-primary text-primary-foreground", children: "admin" }),
              u.banned && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] px-1.5 py-0.5 rounded-full bg-destructive text-white", children: "banni" }),
              !u.phone_verified && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700", children: "non vérifié" })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground truncate", children: u.email }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-mono text-muted-foreground/80 mt-0.5", children: u.unique_code })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right shrink-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase text-muted-foreground", children: "Solde" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm", children: [
              Math.round(Number(u.balance_ar)).toLocaleString("fr-FR"),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-normal ml-0.5", children: "Ar" })
            ] })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1.5 pt-1 border-t border-border/40", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => adjust(u.id), className: "flex-1 px-2 py-1.5 rounded-lg bg-card text-xs font-semibold hover:bg-primary hover:text-primary-foreground transition", children: "💰 Solde" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => ban(u.id, !u.banned), className: `flex-1 px-2 py-1.5 rounded-lg text-xs font-semibold transition ${u.banned ? "bg-emerald-500 text-white" : "bg-card hover:bg-destructive hover:text-white"}`, children: u.banned ? "Débannir" : "Bannir" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => permanentlyDelete(u), className: "px-2.5 py-1.5 rounded-lg text-xs font-semibold bg-card hover:bg-rose-900 hover:text-white transition", title: "Supprimer", children: "🗑" })
        ] })
      ] }, u.id))
    ] })
  ] }) });
}
function GamesList() {
  const [items, setItems] = reactExports.useState([]);
  const load = async () => {
    const {
      data
    } = await supabase.from("ludo_games").select("*, ludo_participants(*)").in("status", ["open", "playing"]).order("created_at", {
      ascending: false
    });
    setItems(data || []);
  };
  reactExports.useEffect(() => {
    load();
  }, []);
  const addBot = async (gameId) => {
    const name = prompt("Nom du bot:", "BotMax");
    if (!name) return;
    const intel = Number(prompt("Niveau d'intelligence (0-100):", "70")) || 70;
    const bias = Number(prompt("Biais de gain (0-100, 0 = équitable):", "0")) || 0;
    const {
      error
    } = await supabase.rpc("admin_add_bot", {
      _game_id: gameId,
      _bot_name: name,
      _intelligence: intel,
      _win_bias: bias
    });
    if (error) return toast.error(error.message);
    toast.success("Bot ajouté");
    load();
  };
  const editBot = async (p) => {
    const {
      data: cfg
    } = await supabase.rpc("admin_get_bot_config", {
      _participant_id: p.id
    });
    const current = (Array.isArray(cfg) ? cfg[0] : cfg) || {
      intelligence: 70,
      win_bias: 0
    };
    const name = prompt("Nouveau nom:", p.display_name) ?? p.display_name;
    const intel = Number(prompt("Intelligence (0-100):", String(current.intelligence ?? 70)));
    const bias = Number(prompt("Biais de gain (0-100):", String(current.win_bias ?? 0)));
    if (name && name !== p.display_name) await supabase.rpc("admin_rename_bot", {
      _participant_id: p.id,
      _name: name
    });
    const {
      error
    } = await supabase.rpc("admin_update_bot", {
      _participant_id: p.id,
      _intelligence: intel,
      _win_bias: bias
    });
    if (error) return toast.error(error.message);
    toast.success("Bot mis à jour");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Card, { children: items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-6", children: "Aucune partie active en ce moment" }) : items.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "border-t border-border/60 pt-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
        "Mise: ",
        Number(g.stake).toLocaleString("fr-FR"),
        " Ar — ",
        g.ludo_participants.length,
        "/",
        g.max_players,
        " joueurs"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-xs font-semibold mt-0.5 ${g.status === "playing" ? "text-emerald-600" : "text-amber-600"}`, children: g.status === "playing" ? "🟢 En cours" : "⏳ En attente" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 mt-1 flex-wrap", children: g.ludo_participants.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => p.is_bot && editBot(p), className: `text-xs px-2 py-0.5 rounded-full bg-secondary ${p.is_bot ? "hover:bg-primary hover:text-primary-foreground cursor-pointer border border-primary/30" : ""}`, title: p.is_bot ? "Bot · cliquez pour modifier" : "", children: [
        p.display_name,
        p.is_bot ? " [IA]" : ""
      ] }, p.id)) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col gap-2", children: [
      g.status === "open" && g.ludo_participants.length < g.max_players && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => addBot(g.id), className: "px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-sm font-semibold", children: "+ Bot" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("a", { href: `/game/${g.id}`, className: "px-3 py-1.5 rounded-full bg-secondary text-sm font-semibold text-center", children: "👁 Entrer" })
    ] })
  ] }) }, g.id)) }) });
}
function TournamentsSection() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(TournamentAdminPanel, {});
}
function PauseControl() {
  const [s, setS] = reactExports.useState(null);
  const [msg, setMsg] = reactExports.useState("");
  const load = async () => {
    const {
      data
    } = await supabase.from("app_settings").select("*").eq("id", 1).maybeSingle();
    setS(data);
    setMsg(data?.pause_message || "");
  };
  reactExports.useEffect(() => {
    load();
  }, []);
  const toggle = async () => {
    const {
      error
    } = await supabase.rpc("admin_set_pause", {
      _paused: !s?.paused,
      _message: msg
    });
    if (error) return toast.error(error.message);
    toast.success(s?.paused ? "▶️ Application reprise" : "⏸ Application en pause");
    load();
  };
  if (!s) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "État de l'application" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-xs font-semibold mt-0.5 ${s.paused ? "text-destructive" : "text-emerald-600"}`, children: s.paused ? "⏸ EN PAUSE (tous les joueurs voient la bannière)" : "▶️ EN LIGNE" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: toggle, className: `px-4 py-2 rounded-full text-sm font-bold flex items-center gap-2 ${s.paused ? "bg-emerald-500 text-white" : "bg-destructive text-white"}`, children: s.paused ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-4 h-4" }),
        " Reprendre"
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-4 h-4" }),
        " Mettre en pause"
      ] }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: msg, onChange: (e) => setMsg(e.target.value), placeholder: "Message affiché aux joueurs (ex: Maintenance en cours, retour dans 30 min)", className: "w-full px-4 py-2.5 rounded-full bg-card border border-border outline-none text-sm" })
  ] });
}
function AdminPinSetup() {
  const [newPin, setNewPin] = reactExports.useState("");
  const [confirmPin, setConfirmPin] = reactExports.useState("");
  const [saving, setSaving] = reactExports.useState(false);
  const [hasPin, setHasPin] = reactExports.useState(null);
  reactExports.useEffect(() => {
    supabase.rpc("admin_verify_pin", {
      _pin: ""
    }).then(({
      data
    }) => {
      setHasPin(data?.reason !== "no_pin_set");
    }).catch(() => setHasPin(null));
  }, []);
  const save = async () => {
    if (newPin.length < 4) return toast.error("PIN trop court (min 4 caractères)");
    if (newPin !== confirmPin) return toast.error("Les PIN ne correspondent pas");
    if (!/^[A-Za-z0-9]+$/.test(newPin)) return toast.error("Alphanumérique uniquement");
    setSaving(true);
    const {
      error
    } = await supabase.rpc("admin_set_pin", {
      _pin: newPin
    });
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success("PIN admin défini ✅");
    setHasPin(true);
    setNewPin("");
    setConfirmPin("");
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold", children: "PIN de sécurité admin" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-xs font-semibold ${hasPin ? "text-emerald-600" : "text-amber-600"}`, children: hasPin ? "✅ PIN configuré" : "⚠️ Aucun PIN défini — l'accès admin est non protégé" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs text-muted-foreground mb-1 block", children: "Nouveau PIN (min 4 caractères alphanumériques)" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "password", inputMode: "numeric", value: newPin, onChange: (e) => setNewPin(e.target.value), maxLength: 12, placeholder: "••••", className: "w-full px-4 py-2.5 rounded-xl bg-secondary outline-none text-sm tracking-widest" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs text-muted-foreground mb-1 block", children: "Confirmer le PIN" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "password", inputMode: "numeric", value: confirmPin, onChange: (e) => setConfirmPin(e.target.value), maxLength: 12, placeholder: "••••", className: "w-full px-4 py-2.5 rounded-xl bg-secondary outline-none text-sm tracking-widest" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: save, disabled: saving || newPin.length < 4, className: "w-full py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-50", children: saving ? "Enregistrement…" : hasPin ? "🔒 Changer le PIN" : "🔑 Définir mon PIN" })
    ] })
  ] });
}
function ReferralAdmin() {
  const confirm2 = useConfirm();
  const [flags, setFlags] = reactExports.useState([]);
  const [cfg, setCfg] = reactExports.useState(null);
  const [loadingCfg, setLoadingCfg] = reactExports.useState(true);
  const [saving, setSaving] = reactExports.useState(false);
  const [flagFilter, setFlagFilter] = reactExports.useState("pending");
  const [stats, setStats] = reactExports.useState(null);
  const loadFlags = async () => {
    const {
      data
    } = await supabase.rpc("admin_get_fraud_flags", {
      _status: flagFilter
    });
    setFlags(data || []);
  };
  const loadCfg = async () => {
    setLoadingCfg(true);
    const {
      data
    } = await supabase.from("referral_settings").select("*").eq("id", 1).maybeSingle();
    setCfg(data || {});
    setLoadingCfg(false);
  };
  const loadStats = async () => {
    const {
      data
    } = await supabase.from("v_referral_stats").select("*").order("total_earned_ar", {
      ascending: false
    }).limit(10);
    setStats(data || []);
  };
  reactExports.useEffect(() => {
    loadFlags();
    loadCfg();
    loadStats();
  }, []);
  reactExports.useEffect(() => {
    loadFlags();
  }, [flagFilter]);
  const saveCfg = async () => {
    if (!cfg) return;
    setSaving(true);
    const {
      error
    } = await supabase.rpc("admin_update_referral_settings", {
      _deposit_bonus_pct: Number(cfg.deposit_bonus_pct),
      _deposit_min_ar: Number(cfg.deposit_min_ar),
      _win_commission_pct: Number(cfg.win_commission_pct),
      _tier_silver_min: Number(cfg.tier_silver_min),
      _tier_gold_min: Number(cfg.tier_gold_min),
      _tier_diamond_min: Number(cfg.tier_diamond_min),
      _tier_silver_mult: Number(cfg.tier_silver_mult),
      _tier_gold_mult: Number(cfg.tier_gold_mult),
      _tier_diamond_mult: Number(cfg.tier_diamond_mult),
      _require_phone: Boolean(cfg.require_phone_verification),
      _max_daily: Number(cfg.max_daily_new_referrals),
      _auto_flag_velocity: Number(cfg.auto_flag_velocity),
      _enabled: Boolean(cfg.enabled),
      _campaign_label: cfg.campaign_label || null,
      _campaign_expires: cfg.campaign_expires_at || null,
      _campaign_bonus_pct: cfg.campaign_bonus_pct ? Number(cfg.campaign_bonus_pct) : null
    });
    setSaving(false);
    if (error) toast.error(error.message);
    else toast.success("✅ Paramètres parrainage enregistrés");
  };
  const resolveFlag = async (flagId, resolution, payAnyway = false) => {
    const ok = await confirm2({
      title: resolution === "cleared" ? "Valider ce parrainage ?" : "Confirmer la fraude ?",
      description: resolution === "cleared" ? payAnyway ? "Le parrainage sera validé et la récompense créditée." : "Le flag sera effacé sans crédit." : "Ce parrainage sera marqué comme frauduleux. Aucune récompense ne sera versée.",
      confirmLabel: resolution === "cleared" ? "Valider" : "Confirmer fraude",
      destructive: resolution === "confirmed"
    });
    if (!ok) return;
    const {
      error
    } = await supabase.rpc("admin_resolve_fraud_flag", {
      _flag_id: flagId,
      _resolution: resolution,
      _pay_anyway: payAnyway
    });
    if (error) toast.error(error.message);
    else {
      toast.success("✅ Flag résolu");
      loadFlags();
    }
  };
  const Field2 = ({
    label,
    fieldKey,
    type = "number",
    hint
  }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground", children: label }),
    type === "boolean" ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: Boolean(cfg?.[fieldKey]), onChange: (e) => setCfg({
        ...cfg,
        [fieldKey]: e.target.checked
      }), className: "w-4 h-4" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm", children: cfg?.[fieldKey] ? "Oui" : "Non" })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type, value: cfg?.[fieldKey] ?? "", onChange: (e) => setCfg({
      ...cfg,
      [fieldKey]: type === "number" ? e.target.value : e.target.value
    }), className: "mt-1 w-full px-3 py-2 rounded-xl bg-secondary border border-border text-sm" }),
    hint && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground mt-0.5", children: hint })
  ] });
  const REASON_LABELS = {
    self_referral: "⚠️ Auto-parrainage",
    velocity_exceeded: "⚡ Vélocité anormale",
    daily_limit_exceeded: "🚫 Limite journalière"
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-5", children: [
    stats && stats.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 border border-border shadow-sm space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold flex items-center gap-2", children: "📊 Top parrains" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "overflow-x-auto", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("table", { className: "w-full text-xs", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("thead", { children: /* @__PURE__ */ jsxRuntimeExports.jsxs("tr", { className: "text-muted-foreground border-b border-border", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-left py-1.5 pr-3", children: "Parrain" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right py-1.5 pr-3", children: "Filleuls" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right py-1.5 pr-3", children: "Actifs" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("th", { className: "text-right py-1.5", children: "Gains" })
        ] }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("tbody", { children: stats.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsxs("tr", { className: "border-b border-border/40", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("td", { className: "py-2 pr-3 font-semibold", children: [
            s.referrer_id?.slice(0, 8),
            "…"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("td", { className: "text-right py-2 pr-3", children: s.total_referrals }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("td", { className: "text-right py-2 pr-3 text-emerald-600 font-bold", children: s.active_referrals }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("td", { className: "text-right py-2 text-primary font-bold", children: [
            Math.round(Number(s.total_earned_ar)).toLocaleString("fr-FR"),
            " Ar"
          ] })
        ] }, s.referrer_id)) })
      ] }) })
    ] }),
    loadingCfg ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "py-8 text-center text-muted-foreground animate-pulse", children: "Chargement…" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 border border-border shadow-sm space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold flex items-center gap-2", children: "⚙️ Paramètres du programme" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center gap-3 p-3 rounded-xl bg-secondary", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Programme activé", fieldKey: "enabled", type: "boolean" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Commission 1er dépôt (%)", fieldKey: "deposit_bonus_pct", hint: "% du montant du dépôt du filleul" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Dépôt minimum (Ar)", fieldKey: "deposit_min_ar", hint: "Montant min pour déclencher la commission" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Commission victoires (%)", fieldKey: "win_commission_pct", hint: "% comm. plateforme sur victoires filleul" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Max filleuls/jour", fieldKey: "max_daily_new_referrals", hint: "Limite anti-fraude journalière" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm pt-1", children: "Seuils de niveaux (filleuls actifs)" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "🥈 Argent (min)", fieldKey: "tier_silver_min" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "🥇 Or (min)", fieldKey: "tier_gold_min" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "💎 Diamant (min)", fieldKey: "tier_diamond_min" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: "Multiplicateurs de commission" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "🥈 Argent ×", fieldKey: "tier_silver_mult", hint: "Ex: 1.25 = +25%" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "🥇 Or ×", fieldKey: "tier_gold_mult", hint: "Ex: 1.60 = +60%" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "💎 Diamant ×", fieldKey: "tier_diamond_mult", hint: "Ex: 2.00 = ×2" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm pt-1", children: "Campagne promotionnelle (optionnel)" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Label campagne", fieldKey: "campaign_label", type: "text", hint: "Ex: Ramadan bonus 🎁" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Bonus campagne (%)", fieldKey: "campaign_bonus_pct", hint: "% supplémentaire pendant la campagne" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-xs font-semibold text-muted-foreground", children: "Date d'expiration campagne" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "datetime-local", value: cfg?.campaign_expires_at?.slice(0, 16) || "", onChange: (e) => setCfg({
          ...cfg,
          campaign_expires_at: e.target.value || null
        }), className: "mt-1 w-full px-3 py-2 rounded-xl bg-secondary border border-border text-sm" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm pt-1", children: "Anti-fraude" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Vélocité max (filleuls/heure)", fieldKey: "auto_flag_velocity", hint: "Au-delà → flag automatique" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Field2, { label: "Vérification téléphone requise", fieldKey: "require_phone_verification", type: "boolean" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: saveCfg, disabled: saving, className: "w-full py-3 rounded-full text-white font-bold", style: {
        background: "var(--gradient-primary)"
      }, children: saving ? "⏳ Enregistrement…" : "💾 Enregistrer les paramètres" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-4 border border-border shadow-sm space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2 flex-wrap", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold flex items-center gap-2", children: "🚨 Signalements de fraude" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1", children: ["pending", "cleared", "confirmed", "all"].map((f) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setFlagFilter(f), className: `px-3 py-1 rounded-full text-xs font-semibold ${flagFilter === f ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground"}`, children: f === "pending" ? "En attente" : f === "cleared" ? "Validés" : f === "confirmed" ? "Fraude" : "Tous" }, f)) })
      ] }),
      flags.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "py-6 text-center text-sm text-muted-foreground", children: flagFilter === "pending" ? "✅ Aucun signalement en attente" : "Aucun résultat" }) : flags.map((f) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-secondary/60 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: REASON_LABELS[f.reason] || f.reason }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground", children: [
              "Parrain : ",
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold", children: f.referrer_pseudo }),
              " · ",
              "Filleul : ",
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold", children: f.referee_pseudo })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: new Date(f.created_at).toLocaleString("fr-FR") })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] px-2 py-1 rounded-full font-bold ${f.status === "pending" ? "bg-amber-100 text-amber-700" : f.status === "cleared" ? "bg-emerald-100 text-emerald-700" : "bg-rose-100 text-rose-700"}`, children: f.status === "pending" ? "En attente" : f.status === "cleared" ? "Validé" : "Fraude" })
        ] }),
        f.details && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-mono bg-card px-2 py-1 rounded-lg overflow-x-auto", children: JSON.stringify(f.details) }),
        f.status === "pending" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 flex-wrap", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => resolveFlag(f.id, "cleared", true), className: "flex-1 py-2 rounded-xl bg-emerald-100 text-emerald-700 text-xs font-bold", children: "✅ Valider + créditer" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => resolveFlag(f.id, "cleared", false), className: "flex-1 py-2 rounded-xl bg-secondary text-xs font-bold", children: "✓ Valider sans paiement" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => resolveFlag(f.id, "confirmed"), className: "flex-1 py-2 rounded-xl bg-rose-100 text-rose-700 text-xs font-bold", children: "🚫 Fraude confirmée" })
        ] })
      ] }, f.id))
    ] })
  ] });
}
function PhoneRequests() {
  const confirm2 = useConfirm();
  const [items, setItems] = reactExports.useState([]);
  const load = () => supabase.rpc("admin_list_phone_requests").then(({
    data
  }) => setItems(data || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const act = async (id, approve) => {
    if (approve && !await confirm2({
      title: "Valider la vérification de ce numéro ?",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("admin_verify_phone", {
      _user_id: id,
      _approve: approve
    });
    if (error) return toast.error(error.message);
    toast.success(approve ? "Vérifié" : "Rejeté");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
      "📱 Vérifications téléphone en attente (",
      items.length,
      ")"
    ] }),
    items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-3", children: "Aucune demande" }) : items.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 flex items-center gap-2 flex-wrap", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: r.pseudo }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: r.phone }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs", children: [
          "Code attendu : ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-mono font-bold text-base", children: r.code })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => act(r.id, true), className: "px-3 py-1.5 rounded-full bg-emerald-500 text-white text-sm font-semibold", children: "Valider" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => act(r.id, false), className: "px-3 py-1.5 rounded-full bg-destructive text-white text-sm font-semibold", children: "Rejeter" })
    ] }, r.id))
  ] });
}
function PasswordResetRequestsAdmin() {
  const confirm2 = useConfirm();
  const [items, setItems] = reactExports.useState([]);
  const [filter, setFilter] = reactExports.useState("pending");
  const load = async () => {
    let q = supabase.from("password_reset_requests").select("*").order("created_at", {
      ascending: false
    }).limit(100);
    if (filter === "pending") q = q.in("status", ["pending", "sent"]);
    const {
      data
    } = await q;
    setItems(data || []);
  };
  reactExports.useEffect(() => {
    load();
  }, [filter]);
  const setCode = async (id) => {
    const code = prompt("Code à transmettre à l'utilisateur :");
    if (!code) return;
    const {
      error
    } = await supabase.from("password_reset_requests").update({
      code,
      status: "sent"
    }).eq("id", id);
    if (error) return toast.error(error.message);
    toast.success("Code enregistré");
    load();
  };
  const markDone = async (id) => {
    await supabase.from("password_reset_requests").update({
      status: "done",
      resolved_at: (/* @__PURE__ */ new Date()).toISOString()
    }).eq("id", id);
    load();
  };
  const reject = async (id) => {
    if (!await confirm2({
      title: "Rejeter cette demande ?",
      destructive: true
    })) return;
    await supabase.from("password_reset_requests").update({
      status: "rejected",
      resolved_at: (/* @__PURE__ */ new Date()).toISOString()
    }).eq("id", id);
    load();
  };
  const waLink = (phone, code) => {
    const num = phone.replace(/[^\d]/g, "");
    const txt = encodeURIComponent(`Lalao MADA — votre code de réinitialisation : ${code || "[CODE]"}`);
    return `https://wa.me/${num}?text=${txt}`;
  };
  const mailLink = (email2, code) => `mailto:${email2}?subject=${encodeURIComponent("Réinitialisation Lalao MADA")}&body=${encodeURIComponent(`Bonjour,

Voici votre code de réinitialisation Lalao MADA : ${code || "[CODE]"}

Utilisez-le sur la page « Mot de passe oublié » pour définir un nouveau mot de passe.

L'équipe Lalao MADA`)}`;
  const sendCode = async (r) => {
    const type = r.contact_type || (r.email ? "email" : "phone");
    const contact = r.contact || r.email || r.phone || "";
    if (!contact) return toast.error("Contact manquant sur cette demande");
    if (type === "phone") {
      const normalized = contact.replace(/\s/g, "");
      if (!/^\+261\d{7,}$/.test(normalized)) {
        toast.error("Numéro invalide : il doit commencer par +261 (ex : +261340000000)");
        return;
      }
    }
    let code = r.code;
    if (!code) {
      code = String(Math.floor(1e5 + Math.random() * 9e5));
      const {
        error
      } = await supabase.from("password_reset_requests").update({
        code,
        status: "sent"
      }).eq("id", r.id);
      if (error) return toast.error(error.message);
    } else if (r.status !== "sent") {
      await supabase.from("password_reset_requests").update({
        status: "sent"
      }).eq("id", r.id);
    }
    const url2 = type === "phone" ? waLink(contact, code) : mailLink(contact, code);
    window.open(url2, "_blank", "noopener,noreferrer");
    toast.success(type === "phone" ? "WhatsApp ouvert avec le code" : "E-mail ouvert avec le code");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
        "🔑 Demandes « Mot de passe oublié » (",
        items.length,
        ")"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setFilter(filter === "pending" ? "all" : "pending"), className: "text-xs px-3 py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold", children: filter === "pending" ? "Voir tout" : "En attente seulement" })
    ] }),
    items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-3", children: "Aucune demande" }) : items.map((r) => {
      const type = r.contact_type || (r.email ? "email" : r.phone ? "phone" : "");
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2 flex-wrap", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: r.pseudo || r.contact }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground break-all", children: r.contact || r.email || r.phone }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-[10px] mt-0.5 font-semibold ${r.status === "pending" ? "text-amber-600" : r.status === "sent" ? "text-blue-600" : r.status === "done" ? "text-emerald-600" : "text-destructive"}`, children: [
              r.status === "pending" ? "⏳ En attente" : r.status === "sent" ? "📨 Code envoyé" : r.status === "done" ? "✅ Terminé" : "❌ Rejeté",
              r.code && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-2 font-mono text-foreground", children: [
                "Code: ",
                r.code
              ] })
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground shrink-0", children: new Date(r.created_at).toLocaleString("fr-FR", {
            day: "2-digit",
            month: "2-digit",
            hour: "2-digit",
            minute: "2-digit"
          }) })
        ] }),
        (r.status === "pending" || r.status === "sent") && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1 flex-wrap", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => sendCode(r), className: "px-3 py-1 rounded-full bg-primary text-primary-foreground text-xs font-semibold", children: type === "phone" ? "📱 Envoyer via WhatsApp" : "📧 Envoyer par e-mail" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setCode(r.id), className: "px-2 py-1 rounded-full bg-secondary text-xs font-semibold", children: "Saisir code" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => markDone(r.id), className: "px-2 py-1 rounded-full bg-emerald-500 text-white text-xs font-semibold", children: "Terminé" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => reject(r.id), className: "px-2 py-1 rounded-full bg-destructive text-white text-xs font-semibold", children: "Rejeter" })
        ] })
      ] }, r.id);
    })
  ] });
}
function ChatMutesAdmin() {
  const [code, setCode] = reactExports.useState("");
  const [minutes, setMinutes] = reactExports.useState("60");
  const action = async (ban) => {
    const {
      data: p
    } = await supabase.from("profiles").select("id").eq("unique_code", code.trim().toUpperCase()).maybeSingle();
    if (!p) return toast.error("Utilisateur introuvable");
    const {
      error
    } = await supabase.rpc("admin_chat_mute", {
      _user_id: p.id,
      _minutes: Number(minutes) || 0,
      _ban: ban,
      _reason: null
    });
    if (error) return toast.error(error.message);
    toast.success(ban ? "Banni du chat" : "Muté");
  };
  const unmute = async () => {
    const {
      data: p
    } = await supabase.from("profiles").select("id").eq("unique_code", code.trim().toUpperCase()).maybeSingle();
    if (!p) return toast.error("Utilisateur introuvable");
    await supabase.rpc("admin_chat_unmute", {
      _user_id: p.id
    });
    toast.success("Débanni du chat");
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "🛡 Modération chat" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: code, onChange: (e) => setCode(e.target.value.toUpperCase()), placeholder: "ID utilisateur", className: "w-full px-3 py-2 rounded-full bg-secondary outline-none font-mono text-sm" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: minutes, onChange: (e) => setMinutes(e.target.value), type: "number", placeholder: "Durée mute (min, 0 = illimité)", className: "w-full px-3 py-2 rounded-full bg-secondary outline-none text-sm" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => action(false), className: "flex-1 py-2 rounded-full bg-amber-500 text-white text-sm font-semibold", children: "Muter" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => action(true), className: "flex-1 py-2 rounded-full bg-destructive text-white text-sm font-semibold", children: "Bannir" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: unmute, className: "flex-1 py-2 rounded-full bg-emerald-500 text-white text-sm font-semibold", children: "Débannir" })
    ] })
  ] });
}
function GamesAdmin() {
  const confirm2 = useConfirm();
  const [games, setGames] = reactExports.useState([]);
  const load = () => supabase.rpc("admin_list_games").then(({
    data
  }) => setGames(data || []));
  reactExports.useEffect(() => {
    let dt;
    const debouncedLoad = () => {
      clearTimeout(dt);
      dt = setTimeout(load, 1e3);
    };
    load();
    const ch = supabase.channel("admin-games-extra").on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "ludo_games"
    }, debouncedLoad).subscribe();
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
    };
  }, []);
  const del = async (id) => {
    if (!await confirm2({
      title: "Supprimer cette partie et rembourser ?",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("admin_delete_game", {
      _game_id: id
    });
    if (error) return toast.error(error.message);
    toast.success("Supprimée + remboursée");
    load();
  };
  const forceFinish = async (id, players) => {
    const winnerName = prompt(`Désigner un gagnant (pseudo) ou laisser vide pour rembourser tous :
${players.filter((p) => !p.is_bot).map((p) => `- ${p.name}`).join("\n")}`);
    let winnerId = null;
    if (winnerName?.trim()) {
      const p = players.find((p2) => p2.name?.toLowerCase() === winnerName.trim().toLowerCase());
      if (!p) return toast.error("Joueur introuvable");
      winnerId = p.user_id;
    }
    if (!await confirm2({
      title: winnerId ? "Confirmer victoire ?" : "Confirmer annulation + remboursement ?",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("admin_force_finish_game", {
      _game_id: id,
      _winner_id: winnerId
    });
    if (error) return toast.error(error.message);
    toast.success("OK");
    load();
  };
  const refund = async (id) => {
    if (!await confirm2({
      title: "Rembourser tous les joueurs de cette partie ?",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("refund_game", {
      _game_id: id
    });
    if (error) return toast.error(error.message);
    toast.success("Remboursé");
    load();
  };
  const cleanup = async () => {
    const {
      data,
      error
    } = await supabase.rpc("cleanup_stale_open_games");
    if (error) return toast.error(error.message);
    toast.success(`${data || 0} parties expirées supprimées`);
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold", children: [
        "🎮 Parties en cours / ouvertes (",
        games.length,
        ")"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: cleanup, className: "text-xs px-3 py-1.5 rounded-full bg-secondary", children: "Nettoyer expirées" })
    ] }),
    games.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-3", children: "Aucune partie active" }),
    games.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 space-y-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm flex items-center justify-between flex-wrap gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] px-2 py-0.5 rounded-full font-bold ${g.status === "open" ? "bg-amber-100 text-amber-700" : "bg-emerald-100 text-emerald-700"}`, children: g.status }),
          g.is_private && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "ml-1 text-[10px] px-2 py-0.5 rounded-full bg-purple-100 text-purple-700 font-bold", children: "privée" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-2 font-semibold", children: [
            "Mise ",
            Number(g.stake).toLocaleString("fr-FR"),
            " Ar"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-2 text-xs text-muted-foreground", children: [
            "Pot ",
            Number(g.pot).toLocaleString("fr-FR")
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => forceFinish(g.id, g.players || []), className: "px-2 py-1 rounded-full bg-amber-500 text-white text-xs font-semibold", children: "Forcer fin" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => refund(g.id), className: "px-2 py-1 rounded-full bg-blue-500 text-white text-xs font-semibold", children: "Rembourser" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => del(g.id), className: "px-2 py-1 rounded-full bg-destructive text-white text-xs font-semibold", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-3 h-3" }) })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: (g.players || []).map((p) => `${p.name}${p.is_bot ? "[IA]" : ""}${p.forfeited ? "✕" : ""}`).join(" · ") })
    ] }, g.id))
  ] });
}
function SeasonsAdmin() {
  const confirm2 = useConfirm();
  const [items, setItems] = reactExports.useState([]);
  const [f, setF] = reactExports.useState({
    name: "",
    starts_at: "",
    ends_at: "",
    reward_text: "",
    reward_amount: "0"
  });
  const load = () => supabase.from("seasons").select("*").order("starts_at", {
    ascending: false
  }).then(({
    data
  }) => setItems(data || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const create = async () => {
    if (!f.name.trim() || !f.starts_at || !f.ends_at) return toast.error("Nom, dates requis");
    const {
      error
    } = await supabase.rpc("admin_season_upsert", {
      _id: null,
      _name: f.name,
      _starts_at: new Date(f.starts_at).toISOString(),
      _ends_at: new Date(f.ends_at).toISOString(),
      _reward_text: f.reward_text || null,
      _reward_amount: Number(f.reward_amount) || 0
    });
    if (error) return toast.error(error.message);
    toast.success("Saison créée");
    setF({
      name: "",
      starts_at: "",
      ends_at: "",
      reward_text: "",
      reward_amount: "0"
    });
    load();
  };
  const close = async (id) => {
    if (!await confirm2({
      title: "Clôturer la saison et désigner le Ballon d'Or ?",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("admin_season_close", {
      _id: id
    });
    if (error) return toast.error(error.message);
    toast.success("Ballon d'Or attribué 👑");
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "👑 Saisons (Ballon d'Or Lalao MADA)" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary p-3 space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.name, onChange: (e) => setF({
        ...f,
        name: e.target.value
      }), placeholder: "Nom (ex: Saison 1 2026)", className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs", children: [
          "Début",
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "datetime-local", value: f.starts_at, onChange: (e) => setF({
            ...f,
            starts_at: e.target.value
          }), className: "w-full mt-1 px-2 py-2 rounded-xl bg-card text-sm" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs", children: [
          "Fin",
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "datetime-local", value: f.ends_at, onChange: (e) => setF({
            ...f,
            ends_at: e.target.value
          }), className: "w-full mt-1 px-2 py-2 rounded-xl bg-card text-sm" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.reward_text, onChange: (e) => setF({
        ...f,
        reward_text: e.target.value
      }), placeholder: "Description récompense", className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", value: f.reward_amount, onChange: (e) => setF({
        ...f,
        reward_amount: e.target.value
      }), placeholder: "Récompense Ar", className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: create, className: "w-full py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Ouvrir saison"
      ] })
    ] }),
    items.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 flex items-center gap-2 flex-wrap", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold", children: s.name }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground", children: [
          new Date(s.starts_at).toLocaleDateString("fr-FR"),
          " → ",
          new Date(s.ends_at).toLocaleDateString("fr-FR"),
          " · ",
          s.closed ? "Clôturée 👑" : "En cours",
          s.reward_amount > 0 ? ` · 🎁 ${Number(s.reward_amount).toLocaleString("fr-FR")} Ar` : ""
        ] })
      ] }),
      !s.closed && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => close(s.id), className: "px-3 py-1.5 rounded-full bg-amber-500 text-white text-xs font-semibold", children: "Clôturer" })
    ] }, s.id))
  ] });
}
function LeaderboardAdmin() {
  const confirm2 = useConfirm();
  const [period, setPeriod] = reactExports.useState("all");
  const [slug, setSlug] = reactExports.useState("all");
  const [items, setItems] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(false);
  const load = async () => {
    setLoading(true);
    const {
      data,
      error
    } = await supabase.rpc("admin_leaderboard_list", {
      _period: period,
      _limit: 100,
      _slug: slug === "all" ? null : slug
    });
    if (error) toast.error(error.message);
    setItems(data || []);
    setLoading(false);
  };
  reactExports.useEffect(() => {
    load();
  }, [period, slug]);
  const toggleHidden = async (u) => {
    if (!u.hidden && !await confirm2({
      title: `Retirer ${u.name} du classement ?`,
      description: "Ce joueur n'apparaîtra plus dans le Top gagnants de l'accueil, quel que soit le jeu ou la période.",
      destructive: true
    })) return;
    const {
      error
    } = await supabase.rpc("admin_set_leaderboard_hidden", {
      _user_id: u.user_id,
      _hidden: !u.hidden
    });
    if (error) return toast.error(error.message);
    toast.success(u.hidden ? "Joueur réaffiché dans le classement" : "Joueur retiré du classement");
    load();
  };
  const move = async (idx, dir) => {
    const j = idx + dir;
    if (j < 0 || j >= items.length) return;
    const a = items[idx], b = items[j];
    const rankFor = (it, pos) => it.rank_override ?? pos + 1;
    const rankA = rankFor(a, idx), rankB = rankFor(b, j);
    const [{
      error: e1
    }, {
      error: e2
    }] = await Promise.all([supabase.rpc("admin_set_leaderboard_rank", {
      _user_id: a.user_id,
      _rank_override: rankB
    }), supabase.rpc("admin_set_leaderboard_rank", {
      _user_id: b.user_id,
      _rank_override: rankA
    })]);
    if (e1 || e2) return toast.error((e1 || e2).message);
    load();
  };
  const clearRank = async (u) => {
    const {
      error
    } = await supabase.rpc("admin_set_leaderboard_rank", {
      _user_id: u.user_id,
      _rank_override: null
    });
    if (error) return toast.error(error.message);
    toast.success("Ordre manuel retiré, tri par victoires rétabli");
    load();
  };
  const slugs = [{
    id: "all",
    label: "Tous"
  }, {
    id: "ludo",
    label: "Ludo"
  }, {
    id: "domino",
    label: "Domino"
  }, {
    id: "chess",
    label: "Échecs"
  }, {
    id: "fanorona",
    label: "Fanorona"
  }, {
    id: "rami",
    label: "Rami"
  }, {
    id: "poker",
    label: "Poker"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4 text-amber-500" }),
      " Classement — Top gagnants (accueil)"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Le classement est calculé automatiquement par nombre de victoires. Vous pouvez retirer un joueur ou fixer un ordre manuel qui sera prioritaire sur le tri automatique." }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 bg-secondary/60 p-1 rounded-2xl", children: ["week", "month", "all"].map((p) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setPeriod(p), className: `flex-1 py-1.5 rounded-xl text-xs font-bold transition-all ${period === p ? "bg-primary text-primary-foreground shadow" : "text-muted-foreground hover:text-foreground"}`, children: p === "week" ? "Semaine" : p === "month" ? "Mois" : "Tout le temps" }, p)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide", children: slugs.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setSlug(s.id), className: `flex-shrink-0 px-2.5 py-1 rounded-full text-[11px] font-bold border whitespace-nowrap transition-all ${slug === s.id ? "bg-primary text-primary-foreground border-primary" : "bg-secondary/60 border-border text-muted-foreground hover:text-foreground"}`, children: s.label }, s.id)) }),
    loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-6 text-sm", children: "Chargement…" }) : items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground py-6 text-sm", children: "Aucun joueur pour cette sélection." }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: items.map((u, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2 rounded-xl px-2.5 py-2 border ${u.hidden ? "bg-destructive/5 border-destructive/20 opacity-60" : "border-border/60"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 text-center text-xs font-bold text-muted-foreground", children: i + 1 }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 rounded-full bg-accent overflow-hidden grid place-items-center font-bold text-xs flex-shrink-0", children: u.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: u.avatar_url, alt: "", className: "w-full h-full object-cover" }) : (u.name || "?").slice(0, 2).toUpperCase() }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-semibold text-sm truncate flex items-center gap-1.5", children: [
          u.name,
          u.hidden && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] px-1.5 py-0.5 rounded-full bg-destructive text-white", children: "retiré" }),
          u.rank_override != null && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] px-1.5 py-0.5 rounded-full bg-primary/15 text-primary", children: "ordre manuel" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground", children: [
          u.wins,
          " victoire",
          Number(u.wins) !== 1 ? "s" : ""
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 flex-shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => move(i, -1), disabled: i === 0, title: "Monter", className: "p-1.5 rounded-lg bg-secondary disabled:opacity-30", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowUp, { className: "w-3.5 h-3.5" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => move(i, 1), disabled: i === items.length - 1, title: "Descendre", className: "p-1.5 rounded-lg bg-secondary disabled:opacity-30", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowDown, { className: "w-3.5 h-3.5" }) }),
        u.rank_override != null && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => clearRank(u), title: "Retirer l'ordre manuel", className: "p-1.5 rounded-lg bg-secondary", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RotateCcw, { className: "w-3.5 h-3.5" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => toggleHidden(u), title: u.hidden ? "Réafficher" : "Retirer du classement", className: `p-1.5 rounded-lg ${u.hidden ? "bg-emerald-500 text-white" : "bg-destructive text-white"}`, children: u.hidden ? /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-3.5 h-3.5" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(EyeOff, { className: "w-3.5 h-3.5" }) })
      ] })
    ] }, u.user_id)) })
  ] });
}
function AnnouncementsAdmin() {
  const confirm2 = useConfirm();
  const [items, setItems] = reactExports.useState([]);
  const [f, setF] = reactExports.useState({
    title: "",
    body: "",
    image_url: "",
    link: "",
    link_label: ""
  });
  const load = () => supabase.from("announcements").select("*").order("created_at", {
    ascending: false
  }).then(({
    data
  }) => setItems(data || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const create = async () => {
    if (!f.title.trim()) return toast.error("Titre requis");
    const {
      error
    } = await supabase.rpc("admin_announcement_create", {
      _title: f.title,
      _body: f.body || null,
      _image_url: f.image_url || null,
      _link: f.link || null,
      _link_label: f.link_label || null
    });
    if (error) return toast.error(error.message);
    toast.success("Annonce publiée");
    setF({
      title: "",
      body: "",
      image_url: "",
      link: "",
      link_label: ""
    });
    load();
  };
  const toggle = async (id, active) => {
    await supabase.rpc("admin_announcement_toggle", {
      _id: id,
      _active: active
    });
    load();
  };
  const del = async (id) => {
    if (!await confirm2({
      title: "Supprimer cette annonce ?",
      destructive: true
    })) return;
    await supabase.rpc("admin_announcement_delete", {
      _id: id
    });
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "📢 Annonces (popup plein écran)" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary p-3 space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.title, onChange: (e) => setF({
        ...f,
        title: e.target.value
      }), placeholder: "Titre", className: "w-full px-3 py-2 rounded-xl bg-card outline-none text-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: f.body, onChange: (e) => setF({
        ...f,
        body: e.target.value
      }), placeholder: "Description", rows: 2, className: "w-full px-3 py-2 rounded-xl bg-card outline-none text-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.image_url, onChange: (e) => setF({
        ...f,
        image_url: e.target.value
      }), placeholder: "URL image (optionnel)", className: "w-full px-3 py-2 rounded-xl bg-card outline-none text-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.link, onChange: (e) => setF({
          ...f,
          link: e.target.value
        }), placeholder: "Lien (optionnel)", className: "px-3 py-2 rounded-xl bg-card outline-none text-sm" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.link_label, onChange: (e) => setF({
          ...f,
          link_label: e.target.value
        }), placeholder: "Libellé bouton", className: "px-3 py-2 rounded-xl bg-card outline-none text-sm" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: create, className: "w-full py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Publier"
      ] })
    ] }),
    items.map((a) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 flex items-center gap-2", children: [
      a.image_url && /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: a.image_url, alt: "", width: 48, height: 48, loading: "lazy", decoding: "async", className: "w-12 h-12 rounded-lg object-cover" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold truncate", children: a.title }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground truncate", children: a.body })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: a.active, onChange: (e) => toggle(a.id, e.target.checked) }),
        " Actif"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => del(a.id), className: "p-1.5 text-destructive", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
    ] }, a.id))
  ] });
}
function OffersAdmin() {
  const confirm2 = useConfirm();
  const [items, setItems] = reactExports.useState([]);
  const [f, setF] = reactExports.useState({
    title: "",
    description: "",
    image_url: "",
    link: "",
    expires_at: ""
  });
  const load = () => supabase.from("money_offers").select("*").order("created_at", {
    ascending: false
  }).then(({
    data
  }) => setItems(data || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const save = async () => {
    if (!f.title.trim()) return toast.error("Titre requis");
    const {
      error
    } = await supabase.rpc("admin_offer_upsert", {
      _id: null,
      _title: f.title,
      _description: f.description || null,
      _image_url: f.image_url || null,
      _link: f.link || null,
      _expires_at: f.expires_at ? new Date(f.expires_at).toISOString() : null,
      _active: true
    });
    if (error) return toast.error(error.message);
    toast.success("Offre créée");
    setF({
      title: "",
      description: "",
      image_url: "",
      link: "",
      expires_at: ""
    });
    load();
  };
  const del = async (id) => {
    if (!await confirm2({
      title: "Supprimer cette offre ?",
      destructive: true
    })) return;
    await supabase.rpc("admin_offer_delete", {
      _id: id
    });
    load();
  };
  const toggle = async (o, active) => {
    await supabase.rpc("admin_offer_upsert", {
      _id: o.id,
      _title: o.title,
      _description: o.description,
      _image_url: o.image_url,
      _link: o.link,
      _expires_at: o.expires_at,
      _active: active
    });
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "💰 Offres gratuites" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary p-3 space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.title, onChange: (e) => setF({
        ...f,
        title: e.target.value
      }), placeholder: "Titre", className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: f.description, onChange: (e) => setF({
        ...f,
        description: e.target.value
      }), placeholder: "Description", rows: 2, className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.image_url, onChange: (e) => setF({
          ...f,
          image_url: e.target.value
        }), placeholder: "URL image", className: "px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.link, onChange: (e) => setF({
          ...f,
          link: e.target.value
        }), placeholder: "Lien", className: "px-3 py-2 rounded-xl bg-card text-sm outline-none" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "datetime-local", value: f.expires_at, onChange: (e) => setF({
        ...f,
        expires_at: e.target.value
      }), className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: save, className: "w-full py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        " Créer offre"
      ] })
    ] }),
    items.map((o) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm truncate", children: o.title }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground truncate", children: o.description }),
        o.expires_at && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-amber-600", children: [
          "Expire: ",
          new Date(o.expires_at).toLocaleString("fr-FR")
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: o.active, onChange: (e) => toggle(o, e.target.checked) }),
        " Actif"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => del(o.id), className: "p-1.5 text-destructive", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
    ] }, o.id))
  ] });
}
function TutorialsAdmin() {
  const [tutos, setTutos] = reactExports.useState([]);
  const load = () => supabase.from("app_settings").select("tutorials").eq("id", 1).maybeSingle().then(({
    data
  }) => setTutos(data?.tutorials || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const saveAll = async (next) => {
    const {
      error
    } = await supabase.from("app_settings").update({
      tutorials: next
    }).eq("id", 1);
    if (error) return toast.error(error.message);
    setTutos(next);
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: "📚 Tutoriels" }),
    tutos.map((t, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1 border-t border-border/60 pt-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: t.title || "", onChange: (e) => {
          const n = [...tutos];
          n[i] = {
            ...t,
            title: e.target.value
          };
          setTutos(n);
        }, onBlur: () => saveAll(tutos), placeholder: `Titre tuto ${i + 1}`, className: "flex-1 px-2 py-1.5 rounded bg-secondary outline-none text-sm font-semibold" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => saveAll(tutos.filter((_, k) => k !== i)), className: "p-1.5 text-destructive", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: t.content || "", onChange: (e) => {
        const n = [...tutos];
        n[i] = {
          ...t,
          content: e.target.value
        };
        setTutos(n);
      }, onBlur: () => saveAll(tutos), rows: 3, placeholder: "Contenu (les liens https:// sont cliquables)", className: "w-full px-2 py-1.5 rounded bg-secondary outline-none text-sm" })
    ] }, i)),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => saveAll([...tutos, {
      title: "",
      content: ""
    }]), className: "px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-sm flex items-center gap-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
      " Ajouter"
    ] })
  ] });
}
function ContentTextsEditor() {
  const confirm2 = useConfirm();
  const [s, setS] = reactExports.useState(null);
  const [loaded, setLoaded] = reactExports.useState(false);
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("*").eq("id", 1).maybeSingle().then(({
      data
    }) => {
      setS(data || {});
      setLoaded(true);
    });
  }, []);
  const saveTexts = async () => {
    const {
      error
    } = await supabase.from("app_settings").update({
      deposit_help_html: s.deposit_help_html || "",
      withdrawal_help_html: s.withdrawal_help_html || "",
      signup_help_html: s.signup_help_html || "",
      password_reset_help_html: s.password_reset_help_html || "",
      terms_text: s.terms_text || "",
      terms_html: s.terms_html || "",
      privacy_html: s.privacy_html || ""
    }).eq("id", 1);
    if (error) return toast.error(error.message);
    toast.success("✅ Textes enregistrés");
  };
  const reshowTerms = async () => {
    const ok = await confirm2({
      title: "Réafficher les CGU à tous les utilisateurs ?",
      description: "Tous les utilisateurs devront accepter à nouveau les conditions à leur prochaine ouverture.",
      confirmLabel: "Réafficher"
    });
    if (!ok) return;
    const {
      data,
      error
    } = await supabase.rpc("admin_reset_all_terms");
    if (error) return toast.error(error.message);
    toast.success(`CGU réinitialisées pour ${data ?? 0} utilisateur(s)`);
  };
  const clearTerms = async () => {
    if (!await confirm2({
      title: "Supprimer les CGU ?",
      destructive: true
    })) return;
    setS({
      ...s,
      terms_text: ""
    });
    await supabase.from("app_settings").update({
      terms_text: ""
    }).eq("id", 1);
    toast.success("CGU supprimées");
  };
  const TextArea = ({
    k,
    label,
    hint,
    rows = 5
  }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold mb-1", children: label }),
    hint && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mb-1", children: hint }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: s[k] || "", onChange: (e) => setS({
      ...s,
      [k]: e.target.value
    }), rows, className: "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm font-mono" })
  ] });
  const RichText = ({
    k,
    label,
    placeholder
  }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "block mb-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold mb-2", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(RichTextEditor, { value: s[k] || "", onChange: (html) => setS({
      ...s,
      [k]: html
    }), placeholder, minHeight: "200px" })
  ] });
  if (!loaded) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm mb-2", children: "💬 Textes d'aide" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mb-3", children: "HTML autorisé. Affichés aux joueurs via les liens d'aide." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(TextArea, { k: "deposit_help_html", label: "Aide dépôt", hint: "Comment faire un dépôt" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(TextArea, { k: "withdrawal_help_html", label: "Aide retrait", hint: "Comment faire un retrait" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(TextArea, { k: "signup_help_html", label: "Aide inscription", hint: "Comment s'inscrire" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(TextArea, { k: "password_reset_help_html", label: "Aide mot de passe oublié", hint: "Comment réinitialiser" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm mb-2", children: "📜 Mentions légales & CGU" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mb-3", children: "Affichés aux visiteurs et nouveaux inscrits." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(RichText, { k: "terms_html", label: "Conditions d'utilisation", placeholder: "Rédigez les conditions d'utilisation…" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(RichText, { k: "privacy_html", label: "Politique de confidentialité", placeholder: "Rédigez la politique de confidentialité…" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/40 pt-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold mb-1", children: "📜 CGU (popup après inscription)" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mb-2", children: "Si vide, aucune modale n'apparaît." }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: s.terms_text || "", onChange: (e) => setS({
          ...s,
          terms_text: e.target.value
        }), rows: 6, className: "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm", placeholder: "Texte des CGU…" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 flex-wrap mt-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: reshowTerms, className: "py-2 px-3 rounded-full bg-amber-500 text-white font-semibold text-sm", children: "🔔 Réafficher à tous" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: clearTerms, className: "px-3 py-2 rounded-full bg-destructive text-destructive-foreground text-sm", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: saveTexts, className: "w-full py-3 rounded-full text-white font-bold", style: {
      background: "var(--gradient-primary)"
    }, children: "💾 Enregistrer tous les textes" })
  ] });
}
function Communities() {
  const confirm2 = useConfirm();
  const [rooms, setRooms] = reactExports.useState([]);
  const [name, setName] = reactExports.useState("");
  const fileRef = reactExports.useRef(null);
  const load = () => supabase.from("chat_rooms").select("*").eq("type", "global").order("created_at").then(({
    data
  }) => setRooms(data || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const create = async () => {
    if (!name.trim()) return;
    const {
      error
    } = await supabase.rpc("admin_create_community", {
      _name: name.trim(),
      _image_url: null
    });
    if (error) return toast.error(error.message);
    setName("");
    toast.success("Communauté créée");
    load();
  };
  const update = async (r, patch) => {
    const {
      error
    } = await supabase.rpc("admin_update_community", {
      _room_id: r.id,
      _name: patch.name ?? r.name,
      _image_url: patch.image_url ?? r.image_url,
      _enabled: patch.enabled ?? r.enabled
    });
    if (error) return toast.error(error.message);
    load();
  };
  const del = async (r) => {
    if (!await confirm2({
      title: "Supprimer ?",
      destructive: true
    })) return;
    await supabase.rpc("admin_delete_community", {
      _room_id: r.id
    });
    load();
  };
  const upload = async (r, rawFile) => {
    const f = await compressImageToWebp(rawFile, {
      maxDim: 800,
      maxSizeKB: 200
    });
    const path = `community/${r.id}.${f.name.split(".").pop()}`;
    const {
      error
    } = await supabase.storage.from("chat").upload(path, f, {
      upsert: true,
      contentType: f.type
    });
    if (error) return toast.error(error.message);
    const {
      data: {
        publicUrl
      }
    } = supabase.storage.from("chat").getPublicUrl(path);
    update(r, {
      image_url: `${publicUrl}?t=${Date.now()}`
    });
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }),
      " Communautés (chat global)"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: name, onChange: (e) => setName(e.target.value), placeholder: "Nom de la communauté", className: "flex-1 px-3 py-2 rounded-full bg-secondary outline-none text-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: create, className: "px-3 py-2 rounded-full bg-primary text-primary-foreground text-sm font-semibold flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
        "Créer"
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: rooms.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3 border-t border-border/60 pt-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
        fileRef.current.dataset.id = r.id;
        fileRef.current?.click();
      }, className: "w-12 h-12 rounded-2xl bg-accent overflow-hidden flex items-center justify-center", children: r.image_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: r.image_url, loading: "lazy", decoding: "async", className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Camera, { className: "w-5 h-5" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { defaultValue: r.name, onBlur: (e) => e.target.value !== r.name && update(r, {
        name: e.target.value
      }), className: "flex-1 px-2 py-1.5 rounded bg-secondary outline-none text-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: r.enabled, onChange: (e) => update(r, {
          enabled: e.target.checked
        }) }),
        "Actif"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => del(r), className: "p-1.5 rounded-full text-destructive hover:bg-accent", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
    ] }, r.id)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { ref: fileRef, type: "file", accept: "image/*", hidden: true, onChange: (e) => {
      const f = e.target.files?.[0];
      const id = fileRef.current?.dataset.id;
      const r = rooms.find((x) => x.id === id);
      if (f && r) upload(r, f);
    } })
  ] });
}
function AppConfigForm() {
  const [s, setS] = reactExports.useState(null);
  const fe = useFormErrors();
  const load = () => supabase.from("app_settings").select("*").eq("id", 1).maybeSingle().then(({
    data
  }) => setS(data));
  reactExports.useEffect(() => {
    load();
  }, []);
  if (!s) return null;
  const GAME_SLUGS = [{
    slug: "ludo",
    label: "Ludo"
  }, {
    slug: "domino",
    label: "Domino"
  }, {
    slug: "fanorona",
    label: "Fanorona"
  }, {
    slug: "chess",
    label: "Échecs"
  }, {
    slug: "rami",
    label: "Rami"
  }, {
    slug: "poker",
    label: "Poker"
  }];
  const disabledGames = Array.isArray(s.games_disabled) ? s.games_disabled : [];
  const getGameStatus = (slug) => {
    if (disabledGames.includes(slug)) return "hidden";
    if (disabledGames.includes(slug + ":dev")) return "dev";
    if (disabledGames.includes(slug + ":paused")) return "paused";
    return "active";
  };
  const setGameStatus = (slug, status) => {
    const cleaned = disabledGames.filter((x) => x !== slug && x !== slug + ":dev" && x !== slug + ":paused");
    const next = status === "active" ? cleaned : status === "hidden" ? [...cleaned, slug] : status === "dev" ? [...cleaned, slug + ":dev"] : [...cleaned, slug + ":paused"];
    setS({
      ...s,
      games_disabled: next
    });
  };
  const save = async () => {
    if (fe.hasErrors) {
      toast.error("⚠️ Corrige les champs en erreur", {
        description: fe.firstError || "Un ou plusieurs champs sont invalides."
      });
      return;
    }
    await saveWithToast(() => supabase.from("app_settings").update({
      // Liens & contact
      download_url: s.download_url || "",
      tuto_url: s.tuto_url || "",
      update_url: s.update_url || "",
      contact_facebook: s.contact_facebook || "",
      contact_whatsapp: s.contact_whatsapp || "",
      contact_phone: s.contact_phone || "",
      contact_email: s.contact_email || "",
      // Chat & features
      chat_global_enabled: !!s.chat_global_enabled,
      chat_room_enabled: !!s.chat_room_enabled,
      live_enabled: !!s.live_enabled,
      max_spectators: Number(s.max_spectators) || 50,
      afk_enabled: !!s.afk_enabled,
      afk_t1_max: Number(s.afk_t1_max) || 2,
      afk_t2_max: Number(s.afk_t2_max) || 2,
      signup_bonus: Number(s.signup_bonus) || 0,
      game_commission_pct: Number(s.game_commission_pct) || 0,
      min_deposit: Number(s.min_deposit) || 0,
      min_withdraw: Number(s.min_withdraw) || 0,
      withdrawal_fee_pct: Number(s.withdrawal_fee_pct) || 0,
      // Mobile money operators
      mvola_phone: s.mvola_phone || "",
      mvola_name: s.mvola_name || "",
      orange_phone: s.orange_phone || "",
      orange_name: s.orange_name || "",
      airtel_phone: s.airtel_phone || "",
      airtel_name: s.airtel_name || "",
      // Points & stakes
      points_capture: Number(s.points_capture) || 0,
      points_home: Number(s.points_home) || 0,
      points_first: Number(s.points_first) || 0,
      points_second: Number(s.points_second) || 0,
      points_third: Number(s.points_third) || 0,
      tpoints_first: Number(s.tpoints_first) || 0,
      tpoints_second: Number(s.tpoints_second) || 0,
      tpoints_third: Number(s.tpoints_third) || 0,
      min_stake: Number(s.min_stake) || 0,
      max_stake: Number(s.max_stake) || 0,
      // Game status
      games_disabled: disabledGames
    }).eq("id", 1), {
      label: "Paramètres"
    });
  };
  const F = ({
    k,
    label,
    type = "text",
    validate,
    hint
  }) => /* @__PURE__ */ jsxRuntimeExports.jsx(ValidatedField, { variant: "soft", label, value: s[k] ?? "", type, hint, validate, onValidityChange: fe.setError(k), onChange: (v) => setS({
    ...s,
    [k]: v
  }) });
  const Switch = ({
    k,
    label
  }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "flex items-center gap-2 text-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: !!s[k], onChange: (e) => setS({
      ...s,
      [k]: e.target.checked
    }) }),
    label
  ] });
  const PF = ({
    k,
    l
  }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs block", children: [
    l,
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", value: s[k] ?? 0, onChange: (e) => setS({
      ...s,
      [k]: e.target.value
    }), className: "w-full mt-1 px-2 py-2 rounded-xl bg-secondary text-sm outline-none" })
  ] });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Settings, { className: "w-4 h-4" }),
      " Paramètres de l'application"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase tracking-wide text-muted-foreground", children: "📱 Liens & Contact" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "download_url", label: "Lien téléchargement APK", validate: optional(url) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "tuto_url", label: "Lien TUTO (Facebook)", validate: optional(url) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "update_url", label: "Lien Mise à jour", validate: optional(url) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "contact_facebook", label: "Facebook URL", validate: optional(url) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "contact_whatsapp", label: "WhatsApp (numéro)", validate: optional(malagasyPhone) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "contact_phone", label: "Téléphone", validate: optional(malagasyPhone) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "contact_email", label: "Email", type: "email", validate: optional(email) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2 pt-3 border-t border-border/60", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase tracking-wide text-muted-foreground", children: "💰 Finance" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "signup_bonus", label: "🎁 Bonus inscription (Ar)", type: "number", hint: "0 = désactivé", validate: number({
        min: 0,
        max: 1e6,
        integer: true
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "game_commission_pct", label: "Commission parties (%)", type: "number", hint: "% du pot", validate: percent }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "withdrawal_fee_pct", label: "Frais de retrait (%)", type: "number", min: 0, max: 100, validate: percent }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "min_deposit", label: "Dépôt min (Ar)", type: "number", validate: number({
          min: 0,
          integer: true
        }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "min_withdraw", label: "Retrait min (Ar)", type: "number", validate: number({
          min: 0,
          integer: true
        }) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2 pt-3 border-t border-border/60", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase tracking-wide text-muted-foreground", children: "📲 Numéros de dépôt (Mobile Money)" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/50 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2 py-0.5 rounded-full text-white text-[10px] font-extrabold bg-black", children: "MVola" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "mvola_phone", label: "Numéro MVola", validate: combine(required("Requis"), malagasyPhone) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "mvola_name", label: "Titulaire MVola", validate: combine(required("Requis"), minLen(2), maxLen(80)) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-orange-50 dark:bg-orange-950/20 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2 py-0.5 rounded-full text-white text-[10px] font-extrabold bg-orange-500", children: "Orange Money" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "orange_phone", label: "Numéro Orange", validate: optional(malagasyPhone) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "orange_name", label: "Titulaire Orange", validate: maxLen(80) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-red-50 dark:bg-red-950/20 p-3 space-y-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "px-2 py-0.5 rounded-full text-white text-[10px] font-extrabold bg-red-600", children: "Airtel Money" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "airtel_phone", label: "Numéro Airtel", validate: optional(malagasyPhone) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "airtel_name", label: "Titulaire Airtel", validate: maxLen(80) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2 pt-3 border-t border-border/60", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase tracking-wide text-muted-foreground", children: "💬 Chat & Fonctionnalités" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Switch, { k: "chat_global_enabled", label: "Chat global actif" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Switch, { k: "chat_room_enabled", label: "Chat de partie actif" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Switch, { k: "live_enabled", label: "LIVE actif" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(Switch, { k: "afk_enabled", label: "Système AFK actif" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "max_spectators", label: "Max spectateurs", type: "number", validate: number({
          min: 0,
          max: 1e3,
          integer: true
        }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "afk_t1_max", label: "Max T1 (timeout)", type: "number", validate: number({
          min: 0,
          max: 20,
          integer: true
        }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(F, { k: "afk_t2_max", label: "Max T2 (timeout)", type: "number", validate: number({
          min: 0,
          max: 20,
          integer: true
        }) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2 pt-3 border-t border-border/60", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase tracking-wide text-muted-foreground", children: "🎯 Points & Limites mises" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "points_capture", l: "Capture" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "points_home", l: "Arrivée pion" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "points_first", l: "1er partie" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "points_second", l: "2e partie" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "points_third", l: "3e partie" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "tpoints_first", l: "🥇 Tournoi" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "tpoints_second", l: "🥈 Tournoi" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "tpoints_third", l: "🥉 Tournoi" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "min_stake", l: "Min mise (Ar)" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(PF, { k: "max_stake", l: "Max mise (Ar)" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "pt-3 border-t border-border/60", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-bold uppercase tracking-wide mb-2 text-muted-foreground", children: "🎮 Statut des jeux" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: GAME_SLUGS.map((g) => {
        const st = getGameStatus(g.slug);
        const BG = {
          active: "bg-emerald-500/10 border-emerald-500/20",
          hidden: "bg-destructive/10 border-destructive/20",
          dev: "bg-amber-500/10 border-amber-500/20",
          paused: "bg-sky-500/10 border-sky-500/20"
        };
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center justify-between px-3 py-2 rounded-xl border ${BG[st]}`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm font-semibold", children: g.label }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("select", { value: st, onChange: (e) => setGameStatus(g.slug, e.target.value), className: "text-xs bg-transparent border border-border/50 rounded-lg px-2 py-1 outline-none cursor-pointer", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "active", children: "✅ Actif" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "hidden", children: "🚫 Masqué" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "dev", children: "🔧 En développement" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("option", { value: "paused", children: "⏸️ En pause" })
          ] })
        ] }, g.slug);
      }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "pt-2 text-[11px] text-muted-foreground", children: [
      "⏱️ Les ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "timers" }),
      " (tour, salle d'attente, minuteries Échecs/Fanorona) sont dans le panneau ",
      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { children: "⏱️ Timers" }),
      " ci-dessus."
    ] }),
    fe.hasErrors && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs font-semibold text-destructive bg-destructive/10 border border-destructive/20 rounded-xl px-3 py-2", children: [
      "⚠️ ",
      fe.firstError || "Corrige les champs en erreur avant d'enregistrer."
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: save, disabled: fe.hasErrors, className: "w-full py-2.5 rounded-full bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-4 h-4" }),
      " Enregistrer tous les paramètres"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: async () => {
      const {
        data
      } = await supabase.rpc("ludo_purge_unready_rooms");
      toast.success(`${data || 0} parties purgées`);
    }, className: "w-full py-2 rounded-full bg-secondary text-sm", children: "🧹 Purger les parties non prêtes" })
  ] });
}
function PersonaAdmin() {
  const [aliases, setAliases] = reactExports.useState([]);
  const [personaState, setPersonaState] = reactExports.useState(null);
  const [loading, setLoading] = reactExports.useState(true);
  const [newPseudo, setNewPseudo] = reactExports.useState("");
  const [newAvatarUrl, setNewAvatarUrl] = reactExports.useState(null);
  const [newAvatarPreview, setNewAvatarPreview] = reactExports.useState(null);
  const [uploading, setUploading] = reactExports.useState(false);
  const [saving, setSaving] = reactExports.useState(null);
  const fileRef = reactExports.useRef(null);
  const load = async () => {
    setLoading(true);
    const [aliasRes, personaRes] = await Promise.all([supabase.rpc("admin_list_aliases"), supabase.rpc("admin_get_persona")]);
    if (aliasRes.data) setAliases(Array.isArray(aliasRes.data) ? aliasRes.data : []);
    const row = Array.isArray(personaRes.data) ? personaRes.data[0] : personaRes.data;
    if (row) setPersonaState(row);
    setLoading(false);
  };
  reactExports.useEffect(() => {
    load();
  }, []);
  const uploadAvatar = async (file) => {
    setUploading(true);
    const {
      compressImageToWebp: compressImageToWebp2
    } = await import("./image-compress-U7tauI3l.mjs");
    const f = await compressImageToWebp2(file, {
      maxDim: 400,
      maxSizeKB: 200
    });
    const path = `alias_${Date.now()}.webp`;
    const {
      error
    } = await supabase.storage.from("avatars").upload(path, f, {
      upsert: true,
      contentType: "image/webp"
    });
    if (error) {
      toast.error("Erreur upload : " + error.message);
      setUploading(false);
      return;
    }
    const {
      data: {
        publicUrl
      }
    } = supabase.storage.from("avatars").getPublicUrl(path);
    setNewAvatarUrl(publicUrl);
    setNewAvatarPreview(URL.createObjectURL(file));
    setUploading(false);
  };
  const saveAlias = async () => {
    if (!newPseudo.trim()) return toast.error("Le pseudo est requis");
    setSaving("new");
    const {
      error
    } = await supabase.rpc("admin_save_alias", {
      p_pseudo: newPseudo.trim(),
      p_avatar_url: newAvatarUrl
    });
    setSaving(null);
    if (error) return toast.error(error.message);
    toast.success(`✅ Alias « ${newPseudo.trim()} » enregistré`);
    setNewPseudo("");
    setNewAvatarUrl(null);
    setNewAvatarPreview(null);
    load();
  };
  const activateAlias = async (aliasId, aliasName) => {
    setSaving(aliasId);
    const {
      error
    } = await supabase.rpc("admin_activate_alias", {
      p_alias_id: aliasId
    });
    setSaving(null);
    if (error) return toast.error(error.message);
    toast.success(`✅ Alias « ${aliasName} » activé — les autres vous voient sous ce nom`);
    load();
  };
  const deactivate = async () => {
    setSaving("deactivate");
    const {
      error
    } = await supabase.rpc("admin_deactivate_persona");
    setSaving(null);
    if (error) return toast.error(error.message);
    toast.success("✅ Profil réel restauré");
    load();
  };
  const deleteAlias = async (aliasId) => {
    setSaving(aliasId + "_del");
    const {
      error
    } = await supabase.rpc("admin_delete_alias", {
      p_alias_id: aliasId
    });
    setSaving(null);
    if (error) return toast.error(error.message);
    load();
  };
  if (loading) return null;
  const isActive = personaState?.is_active ?? false;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(Card, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "🎭 Jouer sous un alias" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mt-0.5", children: "Même compte, même solde — autre nom et photo visible par les autres" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[11px] font-bold px-2.5 py-1 rounded-full flex-shrink-0 ${isActive ? "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-400" : "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-400"}`, children: isActive ? "⚠️ Alias actif" : "✅ Profil réel" })
    ] }),
    isActive && personaState && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 p-3 flex items-center gap-3", children: [
      personaState.persona_avatar ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: personaState.persona_avatar, className: "w-10 h-10 rounded-xl object-cover flex-shrink-0", alt: "" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-10 rounded-xl bg-muted flex items-center justify-center text-lg flex-shrink-0", children: "🎭" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: personaState.persona_pseudo }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Visible au classement, dans le chat et en jeu" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: deactivate, disabled: saving === "deactivate", className: "flex-shrink-0 px-3 py-1.5 rounded-full bg-secondary text-xs font-bold disabled:opacity-50", children: saving === "deactivate" ? "…" : "↩️ Restaurer" })
    ] }),
    aliases.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs font-semibold text-muted-foreground mb-2", children: [
        "Mes alias (",
        aliases.length,
        ")"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: aliases.map((alias) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2 p-2 rounded-2xl ${alias.is_active ? "bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800" : "bg-secondary/40"}`, children: [
        alias.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: alias.avatar_url, className: "w-9 h-9 rounded-xl object-cover flex-shrink-0", alt: "" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9 rounded-xl bg-muted flex items-center justify-center text-base flex-shrink-0", children: "🎭" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-w-0 font-semibold text-sm truncate", children: alias.pseudo }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => activateAlias(alias.id, alias.pseudo), disabled: !!saving, className: "flex-shrink-0 px-2.5 py-1.5 rounded-full text-white text-xs font-bold disabled:opacity-50", style: {
          background: "var(--gradient-primary)"
        }, children: saving === alias.id ? "…" : alias.is_active ? "✓ Actif" : "▶ Jouer" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => deleteAlias(alias.id), disabled: saving === alias.id + "_del", className: "flex-shrink-0 w-8 h-8 rounded-full bg-destructive/10 text-destructive flex items-center justify-center text-xs hover:bg-destructive/20 transition-colors", children: "🗑" })
      ] }, alias.id)) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs font-semibold text-muted-foreground mb-2", children: "+ Créer un nouvel alias" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => fileRef.current?.click(), disabled: uploading, className: "w-12 h-12 rounded-2xl border-2 border-dashed border-border flex items-center justify-center overflow-hidden bg-muted hover:border-primary transition-colors relative flex-shrink-0", children: [
          newAvatarPreview ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: newAvatarPreview, className: "w-full h-full object-cover", alt: "preview" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Camera, { className: "w-4 h-4 text-muted-foreground" }),
          uploading && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-black/40 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin" }) })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { ref: fileRef, type: "file", accept: "image/*", hidden: true, onChange: (e) => e.target.files?.[0] && uploadAvatar(e.target.files[0]) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: newPseudo, onChange: (e) => setNewPseudo(e.target.value), placeholder: "Pseudo de l'alias…", maxLength: 30, className: "flex-1 px-3 py-2 rounded-xl bg-card border border-border text-sm outline-none focus:border-primary" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: saveAlias, disabled: saving === "new" || uploading || !newPseudo.trim(), className: "flex-shrink-0 px-3 py-2 rounded-full text-white text-xs font-bold disabled:opacity-50", style: {
          background: "var(--gradient-primary)"
        }, children: saving === "new" ? "…" : "💾 Enregistrer" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground/60", children: "Solde, parties et historique ne changent pas. Visible au classement, dans le chat et en jeu." })
  ] });
}
function BannersAdmin() {
  const [items, setItems] = reactExports.useState([]);
  const [f, setF] = reactExports.useState({
    title: "",
    subtitle: "",
    image_url: "",
    button_text: "",
    button_link: "",
    bg_gradient: "from-primary to-orange-600",
    starts_at: "",
    ends_at: ""
  });
  const [editingId, setEditingId] = reactExports.useState(null);
  const load = () => supabase.from("banners").select("*").order("sort_order", {
    ascending: true
  }).then(({
    data
  }) => setItems(data || []));
  reactExports.useEffect(() => {
    load();
  }, []);
  const GRADIENTS = ["from-amber-500 to-orange-600", "from-emerald-500 to-teal-600", "from-rose-500 to-pink-600", "from-violet-500 to-indigo-600", "from-blue-500 to-cyan-600", "from-primary to-orange-600"];
  const save = async () => {
    if (!f.title.trim()) return toast.error("Titre requis");
    const {
      error
    } = await supabase.rpc("admin_banner_upsert", {
      _id: editingId,
      _title: f.title,
      _subtitle: f.subtitle || null,
      _image_url: f.image_url || null,
      _button_text: f.button_text || null,
      _button_link: f.button_link || null,
      _bg_gradient: f.bg_gradient || null,
      _starts_at: f.starts_at ? new Date(f.starts_at).toISOString() : null,
      _ends_at: f.ends_at ? new Date(f.ends_at).toISOString() : null,
      _active: true,
      _sort_order: 0
    });
    if (error) return toast.error(error.message);
    toast.success(editingId ? "Bannière modifiée" : "Bannière créée");
    setF({
      title: "",
      subtitle: "",
      image_url: "",
      button_text: "",
      button_link: "",
      bg_gradient: "from-primary to-orange-600",
      starts_at: "",
      ends_at: ""
    });
    setEditingId(null);
    load();
  };
  const edit = (b) => {
    setEditingId(b.id);
    setF({
      title: b.title || "",
      subtitle: b.subtitle || "",
      image_url: b.image_url || "",
      button_text: b.button_text || "",
      button_link: b.button_link || "",
      bg_gradient: b.bg_gradient || "from-primary to-orange-600",
      starts_at: b.starts_at ? new Date(b.starts_at).toISOString().slice(0, 16) : "",
      ends_at: b.ends_at ? new Date(b.ends_at).toISOString().slice(0, 16) : ""
    });
  };
  const del = async (id) => {
    if (!confirm("Supprimer cette bannière ?")) return;
    await supabase.rpc("admin_banner_delete", {
      _id: id
    });
    toast.success("Bannière supprimée");
    load();
  };
  const toggle = async (b, active) => {
    await supabase.rpc("admin_banner_upsert", {
      _id: b.id,
      _title: b.title,
      _subtitle: b.subtitle,
      _image_url: b.image_url,
      _button_text: b.button_text,
      _button_link: b.button_link,
      _bg_gradient: b.bg_gradient,
      _starts_at: b.starts_at,
      _ends_at: b.ends_at,
      _active: active,
      _sort_order: b.sort_order
    });
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ImagePlus, { className: "w-4 h-4" }),
      " Gestion des bannières"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Bannières affichées dans le carousel de la page d'accueil, juste après le solde." }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary p-3 space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-bold", children: editingId ? "✏️ Modifier" : "➕ Nouvelle bannière" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.title, onChange: (e) => setF({
        ...f,
        title: e.target.value
      }), placeholder: "Titre (ex: 🏆 TOURNOI LUDO)", className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("textarea", { value: f.subtitle, onChange: (e) => setF({
        ...f,
        subtitle: e.target.value
      }), placeholder: "Sous-titre (ex: Commence demain à 20h)", rows: 2, className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.image_url, onChange: (e) => setF({
          ...f,
          image_url: e.target.value
        }), placeholder: "URL image (optionnel)", className: "px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-wrap gap-1", children: GRADIENTS.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { type: "button", onClick: () => setF({
          ...f,
          bg_gradient: g
        }), className: `w-7 h-7 rounded-lg bg-gradient-to-br ${g} ${f.bg_gradient === g ? "ring-2 ring-foreground ring-offset-1" : ""}` }, g)) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.button_text, onChange: (e) => setF({
          ...f,
          button_text: e.target.value
        }), placeholder: "Texte bouton (ex: Participer)", className: "px-3 py-2 rounded-xl bg-card text-sm outline-none" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: f.button_link, onChange: (e) => setF({
          ...f,
          button_link: e.target.value
        }), placeholder: "Lien (ex: /tournaments)", className: "px-3 py-2 rounded-xl bg-card text-sm outline-none" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-[10px] text-muted-foreground", children: "Début (optionnel)" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "datetime-local", value: f.starts_at, onChange: (e) => setF({
            ...f,
            starts_at: e.target.value
          }), className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-[10px] text-muted-foreground", children: "Fin (optionnel)" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "datetime-local", value: f.ends_at, onChange: (e) => setF({
            ...f,
            ends_at: e.target.value
          }), className: "w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        editingId && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
          setEditingId(null);
          setF({
            title: "",
            subtitle: "",
            image_url: "",
            button_text: "",
            button_link: "",
            bg_gradient: "from-primary to-orange-600",
            starts_at: "",
            ends_at: ""
          });
        }, className: "flex-1 py-2 rounded-full bg-secondary font-bold text-sm", children: "Annuler" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: save, className: "flex-[2] py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Plus, { className: "w-4 h-4" }),
          " ",
          editingId ? "Enregistrer" : "Créer bannière"
        ] })
      ] })
    ] }),
    items.map((b) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/60 pt-2 flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-lg bg-gradient-to-br ${b.bg_gradient || "from-primary to-orange-600"} shrink-0` }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm truncate", children: b.title }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground truncate", children: b.subtitle }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground", children: [
          b.button_text && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
            "Bouton: ",
            b.button_text,
            " → ",
            b.button_link
          ] }),
          b.starts_at && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-2", children: [
            "Début: ",
            new Date(b.starts_at).toLocaleDateString("fr-FR")
          ] }),
          b.ends_at && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "ml-2", children: [
            "Fin: ",
            new Date(b.ends_at).toLocaleDateString("fr-FR")
          ] })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "text-xs flex items-center gap-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: b.active, onChange: (e) => toggle(b, e.target.checked) }),
        " Actif"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => edit(b), className: "p-1.5 text-primary", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Save, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => del(b.id), className: "p-1.5 text-destructive", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }) })
    ] }, b.id))
  ] });
}
export {
  AdminPage as component
};
