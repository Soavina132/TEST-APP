import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { x as Route$a, u as useAuth, c as copyText } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { A as ArrowLeft, d as Copy, G as Gamepad2, a as Trophy, n as MessageSquare } from "../_libs/lucide-react.mjs";
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
function PublicProfile() {
  const {
    id
  } = Route$a.useParams();
  const navigate = useNavigate();
  const {
    user
  } = useAuth();
  const [prof, setProf] = reactExports.useState(null);
  const [stats, setStats] = reactExports.useState({
    played: 0,
    wins: 0
  });
  const [loading, setLoading] = reactExports.useState(true);
  reactExports.useEffect(() => {
    (async () => {
      setLoading(true);
      const {
        data
      } = await supabase.from("profiles").select("id,pseudo,avatar_url,unique_code,created_at,bio").eq("id", id).maybeSingle();
      setProf(data);
      const {
        data: s
      } = await supabase.from("player_game_stats").select("games_played,wins").eq("user_id", id);
      if (s?.length) {
        setStats({
          played: s.reduce((a, r) => a + (r.games_played || 0), 0),
          wins: s.reduce((a, r) => a + (r.wins || 0), 0)
        });
      }
      setLoading(false);
    })();
  }, [id]);
  const sendMessage = () => navigate({
    to: "/chat",
    search: {
      dm: id
    }
  });
  if (loading) return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-muted-foreground animate-pulse", children: "Chargement…" });
  if (!prof) return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-muted-foreground", children: "Joueur introuvable" });
  const initials = (prof.pseudo || "?").slice(0, 2).toUpperCase();
  const isSelf = user?.id === prof.id;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-lg mx-auto p-4 space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => navigate({
      to: "/chat",
      search: {
        dm: void 0
      }
    }), className: "flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-4 h-4" }),
      " Retour"
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-gradient-to-br from-primary/10 via-background to-background border border-border/60 p-5 space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-20 h-20 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-2xl font-extrabold ring-4 ring-background shadow-md", children: prof.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: prof.avatar_url, alt: "", className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary", children: initials }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xl font-extrabold truncate", children: prof.pseudo || "Joueur" }),
          prof.unique_code && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
            copyText(prof.unique_code);
            toast.success("Code copié");
          }, className: "mt-1 text-xs text-muted-foreground flex items-center gap-1 hover:text-primary", children: [
            "#",
            prof.unique_code,
            " ",
            /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-3 h-3" })
          ] })
        ] })
      ] }),
      prof.bio && /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-sm text-muted-foreground italic", children: [
        '"',
        prof.bio,
        '"'
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/60 p-3 text-center", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-4 h-4 mx-auto text-muted-foreground mb-1" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold", children: stats.played }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: "Parties" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/60 p-3 text-center", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4 mx-auto text-amber-500 mb-1" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold text-emerald-600", children: stats.wins }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: "Victoires" })
        ] })
      ] }),
      !isSelf && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: sendMessage, className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2 shadow-md active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }),
        " Envoyer un message"
      ] })
    ] })
  ] });
}
export {
  PublicProfile as component
};
