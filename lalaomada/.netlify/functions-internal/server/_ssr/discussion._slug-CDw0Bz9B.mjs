import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { d as Route$g, u as useAuth, r as ramiCover, e as chessCover, g as fanoronaCover, h as dominoCover, l as ludoCover } from "./router-CRCBvenY.mjs";
import { C as ChatRoom } from "./ChatRoom-DC72H67I.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import "../_libs/sonner.mjs";
import { X, A as ArrowLeft, U as Users } from "../_libs/lucide-react.mjs";
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
import "./server-time-CGSyl3Jk.mjs";
import "./LinkPreview-BF8xLSR1.mjs";
import "./share-game-wrpRJpl9.mjs";
import "./image-compress-U7tauI3l.mjs";
const toThumb = (url) => url.replace(/(-cover)(\.\w+)$/, `$1-thumb$2`);
const META = {
  ludo: {
    label: "Ludo",
    cover: toThumb(ludoCover.url),
    group: "Groupe Ludo"
  },
  domino: {
    label: "Domino",
    cover: toThumb(dominoCover.url),
    group: "Groupe Domino"
  },
  fanorona: {
    label: "Fanorona",
    cover: toThumb(fanoronaCover.url),
    group: "Groupe Fanorona"
  },
  chess: {
    label: "Échecs",
    cover: toThumb(chessCover.url),
    group: "Groupe Échec"
  },
  rami: {
    label: "Rami",
    cover: toThumb(ramiCover.url),
    group: "Groupe Rami"
  }
};
function DiscussionPage() {
  const {
    slug
  } = Route$g.useParams();
  const {
    isAdmin
  } = useAuth();
  const meta = META[slug];
  const [roomId, setRoomId] = reactExports.useState(null);
  const [onlineCount, setOnlineCount] = reactExports.useState(0);
  const [onlineUsers, setOnlineUsers] = reactExports.useState([]);
  const [panelOpen, setPanelOpen] = reactExports.useState(false);
  reactExports.useEffect(() => {
    if (!meta) return;
    (async () => {
      const {
        data: room
      } = await supabase.from("chat_rooms").select("id").eq("type", "global").eq("name", meta.group).maybeSingle();
      if (room) setRoomId(room.id);
    })();
  }, [slug, meta?.group]);
  if (!meta) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-6", children: "Jeu inconnu." });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto flex flex-col h-[calc(100dvh-56px-80px)] md:h-[calc(100dvh-56px)] relative overflow-hidden", children: [
    panelOpen && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 z-40 bg-black/40 backdrop-blur-[2px]", onClick: () => setPanelOpen(false) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `absolute top-0 right-0 h-full w-72 z-50 bg-card border-l border-border shadow-2xl flex flex-col transition-transform duration-300 ease-in-out ${panelOpen ? "translate-x-0" : "translate-x-full"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-4 py-4 border-b border-border", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-bold text-base", children: "Joueurs en ligne" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground mt-0.5", children: [
            onlineCount,
            " ",
            onlineCount === 1 ? "joueur actif" : "joueurs actifs"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setPanelOpen(false), className: "p-1.5 rounded-full hover:bg-accent transition-colors", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 overflow-y-auto py-2", children: onlineUsers.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 py-8 text-center text-muted-foreground text-sm", children: "Aucun joueur en ligne pour l'instant" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("ul", { className: "divide-y divide-border/50", children: onlineUsers.map((u) => /* @__PURE__ */ jsxRuntimeExports.jsxs("li", { className: "flex items-center gap-3 px-4 py-3 hover:bg-accent/50 transition-colors", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-10 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-sm font-bold ring-2 ring-background", children: u.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: u.avatar_url, width: 40, height: 40, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: "" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary", children: (u.pseudo || "?").slice(0, 2).toUpperCase() }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-0 right-0 w-3 h-3 rounded-full bg-green-500 ring-2 ring-card" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-semibold text-sm truncate", children: u.pseudo }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-green-500 font-medium", children: "En ligne" })
        ] })
      ] }, u.id)) }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 py-3 border-t border-border", children: /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground text-center", children: "Mis à jour en temps réel" }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2.5 px-2 py-2 border-b border-border bg-card shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/jeux", className: "p-2 rounded-full hover:bg-accent text-foreground transition-colors shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-5 h-5" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-10 rounded-full overflow-hidden ring-1 ring-border", children: /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: meta.cover, alt: `Couverture ${meta.label}`, loading: "lazy", decoding: "async", className: "w-full h-full object-cover" }) }),
        onlineCount > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-0 right-0 w-3 h-3 rounded-full bg-green-500 ring-2 ring-card" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "font-bold text-[15px] leading-tight truncate", children: meta.group }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground truncate", children: onlineCount > 0 ? `${onlineCount} ${onlineCount === 1 ? "actif" : "actifs"}` : "Communauté " + meta.label })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setPanelOpen(true), className: "p-2 rounded-full hover:bg-accent text-muted-foreground hover:text-foreground transition-colors shrink-0", title: "Joueurs en ligne", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-5 h-5" }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-h-0", children: roomId ? /* @__PURE__ */ jsxRuntimeExports.jsx(ChatRoom, { roomId, title: meta.group, isAdmin, height: "h-full", gameSlug: slug, onOnlineCountChange: setOnlineCount, onOnlineUsersChange: setOnlineUsers }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-8 text-center text-muted-foreground", children: "Chargement du salon…" }) })
  ] });
}
export {
  DiscussionPage as component
};
