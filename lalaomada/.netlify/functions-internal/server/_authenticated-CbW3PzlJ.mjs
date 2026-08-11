import { j as jsxRuntimeExports, r as reactExports } from "./_libs/react.mjs";
import { f as useLocation, N as Navigate, O as Outlet, L as Link } from "./_libs/tanstack__react-router.mjs";
import { u as useAuth, a as useT, P as PageLoader, w as whatsappTargets, f as facebookTargets, o as openExternal } from "./_ssr/router-CRCBvenY.mjs";
import { H as Header } from "./_ssr/Header-C01sWVFL.mjs";
import { s as supabase } from "./_ssr/client-4UYFom1R.mjs";
import { u as useLiveAvailable } from "./_ssr/use-live-available-aenEXr3_.mjs";
import { toast } from "./_libs/sonner.mjs";
import { u as useWaitingRoomActive } from "./_ssr/game-ui-state-y34n01Z_.mjs";
import "./_libs/capacitor__core.mjs";
import "./_libs/capacitor__push-notifications.mjs";
import { I as Info, X, u as House, G as Gamepad2, n as MessageSquare, v as Radio, a as Trophy, w as History, x as User, y as Shield, z as Bug, Z as Zap, E as ExternalLink, D as Headphones, M as MessageCircle, J as Facebook, K as Mail, P as Phone, o as BookOpen, N as Download } from "./_libs/lucide-react.mjs";
import "./_libs/tanstack__router-core.mjs";
import "./_libs/tanstack__history.mjs";
import "./_libs/cookie-es.mjs";
import "./_libs/seroval.mjs";
import "./_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "./_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "./_libs/isbot.mjs";
import "./_libs/tanstack__query-core.mjs";
import "./_libs/tanstack__react-query.mjs";
import "./_libs/radix-ui__react-alert-dialog.mjs";
import "./_libs/radix-ui__react-context.mjs";
import "./_libs/radix-ui__react-compose-refs.mjs";
import "./_libs/radix-ui__react-dialog.mjs";
import "./_libs/radix-ui__primitive.mjs";
import "./_libs/radix-ui__react-id.mjs";
import "./_libs/@radix-ui/react-use-layout-effect+[...].mjs";
import "./_libs/@radix-ui/react-use-controllable-state+[...].mjs";
import "./_libs/@radix-ui/react-use-effect-event+[...].mjs";
import "./_libs/@radix-ui/react-dismissable-layer+[...].mjs";
import "./_libs/radix-ui__react-primitive.mjs";
import "./_libs/radix-ui__react-slot.mjs";
import "./_libs/@radix-ui/react-use-callback-ref+[...].mjs";
import "./_libs/radix-ui__react-focus-scope.mjs";
import "./_libs/radix-ui__react-portal.mjs";
import "./_libs/radix-ui__react-presence.mjs";
import "./_libs/radix-ui__react-focus-guards.mjs";
import "./_libs/react-remove-scroll.mjs";
import "tslib";
import "./_libs/react-remove-scroll-bar.mjs";
import "./_libs/react-style-singleton.mjs";
import "./_libs/get-nonce.mjs";
import "./_libs/use-sidecar.mjs";
import "./_libs/use-callback-ref.mjs";
import "./_libs/aria-hidden.mjs";
import "./_libs/clsx.mjs";
import "./_libs/tailwind-merge.mjs";
import "./_libs/class-variance-authority.mjs";
import "./_libs/supabase__supabase-js.mjs";
import "./_libs/supabase__postgrest-js.mjs";
import "./_libs/supabase__realtime-js.mjs";
import "./_libs/supabase__phoenix.mjs";
import "./_libs/supabase__storage-js.mjs";
import "./_libs/iceberg-js.mjs";
import "./_libs/supabase__auth-js.mjs";
import "./_libs/supabase__functions-js.mjs";
import "./_libs/ai-sdk__openai-compatible.mjs";
import "./_libs/ai-sdk__provider.mjs";
import "./_libs/ai-sdk__provider-utils.mjs";
import "./_libs/eventsource-parser.mjs";
import "./_libs/zod.mjs";
import "./_libs/ai.mjs";
import "./_libs/ai-sdk__gateway.mjs";
import "./_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "./_libs/opentelemetry__api.mjs";
import "./_ssr/WalletButton-BwZT8Njg.mjs";
function PauseBanner() {
  const { t } = useT();
  const { isAdmin } = useAuth();
  const [s, setS] = reactExports.useState(null);
  const [closed, setClosed] = reactExports.useState(false);
  reactExports.useEffect(() => {
    const load = () => supabase.from("app_settings").select("paused,pause_message").eq("id", 1).maybeSingle().then(({ data }) => setS(data));
    load();
    const ch = supabase.channel("app-settings").on("postgres_changes", { event: "*", schema: "public", table: "app_settings" }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, []);
  if (!s?.paused || closed || isAdmin) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[70] bg-slate-900/80 backdrop-blur-sm flex items-center justify-center p-6", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card max-w-sm w-full rounded-3xl p-6 shadow-2xl text-center space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-14 h-14 mx-auto rounded-full bg-amber-100 dark:bg-amber-900/40 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Info, { className: "w-7 h-7 text-amber-600" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xl font-extrabold", children: t("maintenance_title") }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground whitespace-pre-wrap", children: s.pause_message || t("maintenance_default") }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setClosed(true), className: "w-full py-3 rounded-full bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }),
      " ",
      t("close_btn")
    ] })
  ] }) });
}
function useChatUnread() {
  const { user } = useAuth();
  const [unread, setUnread] = reactExports.useState(0);
  const loc = useLocation();
  reactExports.useEffect(() => {
    const isDiscussion = loc.pathname === "/chat" || loc.pathname.startsWith("/discussion");
    if (!user || isDiscussion) {
      setUnread(0);
      return;
    }
    const lastKey = `chat_last_seen_${user.id}`;
    const lastSeen = localStorage.getItem(lastKey) || (/* @__PURE__ */ new Date(0)).toISOString();
    const load = async () => {
      const { data: rooms } = await supabase.from("chat_rooms").select("id").eq("type", "global");
      if (!rooms?.length) return;
      const roomIds = rooms.map((r) => r.id);
      const { count } = await supabase.from("chat_messages").select("id", { count: "exact", head: true }).in("room_id", roomIds).neq("user_id", user.id).gt("created_at", lastSeen).is("deleted_at", null);
      setUnread(count || 0);
    };
    load();
    const interval = setInterval(load, 3e4);
    return () => {
      clearInterval(interval);
    };
  }, [user?.id, loc.pathname]);
  reactExports.useEffect(() => {
    const isDiscussion = loc.pathname === "/chat" || loc.pathname.startsWith("/discussion");
    if (isDiscussion && user) {
      localStorage.setItem(`chat_last_seen_${user.id}`, (/* @__PURE__ */ new Date()).toISOString());
      setUnread(0);
    }
  }, [loc.pathname, user?.id]);
  return unread;
}
function useInvitesCount() {
  const { user } = useAuth();
  const [n, setN] = reactExports.useState(0);
  reactExports.useEffect(() => {
    if (!user) {
      setN(0);
      return;
    }
    const load = async () => {
      const { count } = await supabase.from("game_invitations").select("id", { count: "exact", head: true }).eq("receiver_id", user.id).eq("status", "pending");
      setN(count || 0);
    };
    load();
    const ch = supabase.channel("nav-inv-" + user.id).on("postgres_changes", { event: "*", schema: "public", table: "game_invitations", filter: `receiver_id=eq.${user.id}` }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [user?.id]);
  return n;
}
function useNotifsUnread() {
  const { user } = useAuth();
  const [n, setN] = reactExports.useState(0);
  reactExports.useEffect(() => {
    if (!user) {
      setN(0);
      return;
    }
    const load = async () => {
      const { count } = await supabase.from("notifications").select("id", { count: "exact", head: true }).eq("user_id", user.id).eq("read", false);
      setN(count || 0);
    };
    load();
    const ch = supabase.channel("nav-notif-" + user.id).on("postgres_changes", { event: "*", schema: "public", table: "notifications", filter: `user_id=eq.${user.id}` }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [user?.id]);
  return n;
}
function BottomNav() {
  const loc = useLocation();
  const { t } = useT();
  const chatUnread = useChatUnread();
  const liveAvailable = useLiveAvailable();
  const invites = useInvitesCount();
  const notifsUnread = useNotifsUnread();
  if (loc.pathname === "/login") return null;
  const items = [
    { to: "/lobby", icon: House, label: t("home"), badge: 0, dot: false },
    { to: "/jeux", icon: Gamepad2, label: t("games") || "Jeux", badge: invites, dot: false },
    { to: "/chat", icon: MessageSquare, label: t("discussion"), badge: chatUnread, dot: false },
    { to: "/live", icon: Radio, label: t("live"), badge: 0, dot: liveAvailable > 0 },
    { to: "/profile", icon: User, label: t("profile"), badge: notifsUnread, dot: false }
  ];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-20 md:h-0", "aria-hidden": true }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "md:hidden fixed bottom-0 inset-x-0 z-40 pb-[env(safe-area-inset-bottom)]", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-3 mb-2.5", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("nav", { className: "relative bg-neutral-950 border border-white/10 rounded-2xl shadow-lg shadow-black/20 overflow-hidden", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-gradient-to-b from-white/5 to-transparent pointer-events-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "relative flex items-center justify-around px-1 py-1.5", children: items.map((it) => {
        const isChat = it.to === "/chat";
        const active = loc.pathname === it.to || it.to !== "/" && loc.pathname.startsWith(it.to) || isChat && loc.pathname.startsWith("/discussion");
        const Icon = it.icon;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs(
          Link,
          {
            to: it.to,
            className: "relative flex flex-col items-center gap-1 px-1 py-1 min-w-0 flex-1 group",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `relative flex items-center justify-center w-10 h-8 rounded-xl transition-all duration-200 ${active ? "bg-gradient-to-br from-primary/15 to-primary/8 shadow-sm" : "group-active:bg-accent/80"}`, children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: `w-5 h-5 transition-all duration-200 ${active ? "text-primary scale-110" : "text-neutral-400 group-hover:text-neutral-200"}` }),
                it.badge > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-destructive text-white text-[9px] font-bold flex items-center justify-center leading-none shadow-md border-2 border-neutral-950 animate-bounce", children: it.badge > 99 ? "99+" : it.badge }),
                it.dot && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "absolute -top-0.5 -right-0.5 flex h-2.5 w-2.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "animate-ping absolute inline-flex h-full w-full rounded-full bg-destructive opacity-75" }),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "relative inline-flex rounded-full h-2.5 w-2.5 bg-destructive border-2 border-neutral-950" })
                ] }),
                active && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -bottom-0.5 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-primary" })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[9px] font-semibold truncate w-full text-center transition-colors duration-200 ${active ? "text-primary" : "text-neutral-500"}`, children: it.label })
            ]
          },
          it.to
        );
      }) })
    ] }) }) })
  ] });
}
function TermsModal() {
  const { profile, refreshProfile, user } = useAuth();
  const [terms, setTerms] = reactExports.useState("");
  const [accepted, setAccepted] = reactExports.useState(false);
  const [busy, setBusy] = reactExports.useState(false);
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("terms_text").eq("id", 1).maybeSingle().then(({ data }) => {
      setTerms(data?.terms_text || "");
    });
  }, []);
  if (!user || !profile) return null;
  if (profile.terms_accepted_at) return null;
  if (!terms.trim()) return null;
  const accept = async () => {
    if (!accepted) return;
    setBusy(true);
    const { error } = await supabase.rpc("accept_terms");
    setBusy(false);
    if (error) return toast.error(error.message);
    await refreshProfile();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[60] bg-black/70 flex items-center justify-center p-4", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-3xl w-full max-w-lg max-h-[85vh] flex flex-col", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5 border-b border-border", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xl font-extrabold", children: "Conditions d'utilisation" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground", children: "Veuillez lire et accepter pour continuer." })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 overflow-y-auto p-5 text-sm whitespace-pre-wrap leading-relaxed", children: terms }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5 border-t border-border space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("label", { className: "flex items-start gap-2 text-sm", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "checkbox", checked: accepted, onChange: (e) => setAccepted(e.target.checked), className: "mt-0.5" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "J'ai lu et j'accepte les conditions d'utilisation." })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: accept,
          disabled: !accepted || busy,
          className: "w-full py-3 rounded-full bg-primary text-primary-foreground font-bold disabled:opacity-50",
          children: busy ? "..." : "Accepter et continuer"
        }
      )
    ] })
  ] }) });
}
function AnnouncementsModal() {
  const { t } = useT();
  const [items, setItems] = reactExports.useState([]);
  const [idx, setIdx] = reactExports.useState(0);
  reactExports.useEffect(() => {
    const load = async () => {
      const { data } = await supabase.from("announcements").select("*").eq("active", true).order("created_at", { ascending: false });
      const seen = JSON.parse(localStorage.getItem("ann:seen") || "{}");
      const unseen = (data || []).filter((a2) => !seen[a2.id]);
      setItems(unseen);
      setIdx(0);
    };
    load();
    const ch = supabase.channel("ann-modal").on("postgres_changes", { event: "INSERT", schema: "public", table: "announcements" }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, []);
  const close = () => {
    const a2 = items[idx];
    if (a2) {
      const seen = JSON.parse(localStorage.getItem("ann:seen") || "{}");
      seen[a2.id] = Date.now();
      localStorage.setItem("ann:seen", JSON.stringify(seen));
    }
    if (idx + 1 < items.length) setIdx((i) => i + 1);
    else setItems([]);
  };
  if (!items.length) return null;
  const a = items[idx];
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[80] bg-black/70 flex items-center justify-center p-4 animate-in fade-in", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card max-w-md w-full rounded-3xl overflow-hidden shadow-2xl", children: [
    a.image_url && /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: a.image_url, alt: a.title, loading: "lazy", decoding: "async", className: "w-full h-48 object-cover" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs uppercase font-bold text-primary tracking-widest", children: t("announcement_label") }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-2xl font-extrabold leading-tight", children: a.title }),
      a.body && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground whitespace-pre-wrap", children: a.body }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2 pt-2", children: [
        a.link && /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "a",
          {
            href: a.link,
            target: "_blank",
            rel: "noopener noreferrer",
            className: "flex-1 py-3 rounded-full bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(ExternalLink, { className: "w-4 h-4" }),
              " ",
              a.link_label || t("learn_more_btn")
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: close, className: `${a.link ? "px-5" : "flex-1"} py-3 rounded-full bg-secondary font-bold flex items-center justify-center gap-2`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }),
          " ",
          t("close_btn")
        ] })
      ] }),
      items.length > 1 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center text-[10px] text-muted-foreground", children: [
        idx + 1,
        " / ",
        items.length
      ] })
    ] })
  ] }) });
}
function ContactFab() {
  const [open, setOpen] = reactExports.useState(false);
  const [c, setC] = reactExports.useState({});
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("contact_whatsapp,contact_facebook,contact_email,admin_phone,tuto_url,update_url").eq("id", 1).maybeSingle().then(({ data }) => data && setC(data));
  }, []);
  const waNumber = (c.contact_whatsapp || "").replace(/\D/g, "");
  const fbUrl = c.contact_facebook ? c.contact_facebook.startsWith("http") ? c.contact_facebook : `https://facebook.com/${c.contact_facebook.replace(/^@/, "")}` : "";
  const whatsappLink = waNumber ? whatsappTargets(waNumber) : null;
  const facebookLink = fbUrl ? facebookTargets(fbUrl) : null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "button",
      {
        onClick: () => setOpen(true),
        "aria-label": "Contact",
        style: { background: "var(--gradient-primary)" },
        className: "fixed bottom-24 right-4 z-40 h-14 w-14 rounded-full text-white shadow-2xl flex items-center justify-center hover:scale-110 active:scale-95 transition",
        children: /* @__PURE__ */ jsxRuntimeExports.jsx(Headphones, { className: "w-6 h-6" })
      }
    ),
    open && /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "fixed inset-0 z-[60] bg-black/50 flex items-end sm:items-center justify-center p-4",
        onClick: () => setOpen(false),
        children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "bg-card rounded-3xl w-full max-w-sm p-5 space-y-3 shadow-2xl",
            onClick: (e) => e.stopPropagation(),
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-lg", children: "Nous contacter" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setOpen(false), "aria-label": "Fermer", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-5 h-5" }) })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
                whatsappLink && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "a",
                  {
                    href: whatsappLink.appUrl,
                    target: "_top",
                    rel: "noopener noreferrer",
                    onClick: (e) => {
                      e.preventDefault();
                      openExternal(whatsappLink);
                    },
                    className: "w-full px-4 py-3 rounded-2xl bg-[#25D366] text-white font-semibold flex items-center gap-3 active:scale-95 transition",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(MessageCircle, { className: "w-5 h-5" }),
                      " WhatsApp"
                    ]
                  }
                ),
                facebookLink && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "a",
                  {
                    href: facebookLink.appUrl,
                    target: "_top",
                    rel: "noopener noreferrer",
                    onClick: (e) => {
                      e.preventDefault();
                      openExternal(facebookLink);
                    },
                    className: "w-full px-4 py-3 rounded-2xl bg-[#1877F2] text-white font-semibold flex items-center gap-3 active:scale-95 transition",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Facebook, { className: "w-5 h-5" }),
                      " Facebook"
                    ]
                  }
                ),
                c.contact_email && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "a",
                  {
                    href: `mailto:${c.contact_email}`,
                    className: "w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Mail, { className: "w-5 h-5" }),
                      " E-mail"
                    ]
                  }
                ),
                c.admin_phone && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "a",
                  {
                    href: `tel:${c.admin_phone}`,
                    className: "w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Phone, { className: "w-5 h-5" }),
                      " ",
                      c.admin_phone
                    ]
                  }
                ),
                c.tuto_url && (() => {
                  const isFb = /facebook\.com|fb\.com/i.test(c.tuto_url);
                  const target = isFb ? facebookTargets(c.tuto_url) : { webUrl: c.tuto_url };
                  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "a",
                    {
                      href: target.appUrl || target.webUrl,
                      target: "_top",
                      rel: "noopener noreferrer",
                      onClick: (e) => {
                        e.preventDefault();
                        openExternal(target);
                      },
                      className: "w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition",
                      children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsx(BookOpen, { className: "w-5 h-5" }),
                        " TUTO"
                      ]
                    }
                  );
                })(),
                c.update_url && (() => {
                  const isFb = /facebook\.com|fb\.com/i.test(c.update_url);
                  const target = isFb ? facebookTargets(c.update_url) : { webUrl: c.update_url };
                  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "a",
                    {
                      href: target.appUrl || target.webUrl,
                      target: "_top",
                      rel: "noopener noreferrer",
                      onClick: (e) => {
                        e.preventDefault();
                        openExternal(target);
                      },
                      className: "w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition",
                      children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsx(Download, { className: "w-5 h-5" }),
                        " Mise à jour"
                      ]
                    }
                  );
                })(),
                !waNumber && !fbUrl && !c.contact_email && !c.admin_phone && !c.tuto_url && !c.update_url && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground text-center py-4", children: "Aucun contact configuré." })
              ] })
            ]
          }
        )
      }
    )
  ] });
}
function useOnlineStatus(userId) {
  const [onlineCount, setOnlineCount] = reactExports.useState(0);
  const [latencyMs, setLatencyMs] = reactExports.useState(null);
  const [effectiveType, setEffectiveType] = reactExports.useState(null);
  const [isOnline, setIsOnline] = reactExports.useState(typeof navigator !== "undefined" ? navigator.onLine : true);
  reactExports.useEffect(() => {
    const onOnline = () => setIsOnline(true);
    const onOffline = () => setIsOnline(false);
    window.addEventListener("online", onOnline);
    window.addEventListener("offline", onOffline);
    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("offline", onOffline);
    };
  }, []);
  reactExports.useEffect(() => {
    const conn = navigator.connection || navigator.mozConnection || navigator.webkitConnection;
    if (!conn) return;
    const update = () => setEffectiveType(conn.effectiveType ?? null);
    update();
    conn.addEventListener("change", update);
    return () => conn.removeEventListener("change", update);
  }, []);
  reactExports.useEffect(() => {
    if (!userId) return;
    const channel = supabase.channel("global-presence", {
      config: { presence: { key: userId } }
    });
    channel.on("presence", { event: "sync" }, () => {
      setOnlineCount(Object.keys(channel.presenceState()).length);
    }).subscribe(async (status) => {
      if (status === "SUBSCRIBED") {
        await channel.track({ user_id: userId, at: Date.now() });
      }
    });
    return () => {
      supabase.removeChannel(channel);
    };
  }, [userId]);
  reactExports.useEffect(() => {
    let cancelled = false;
    const ping = async () => {
      if (cancelled || !navigator.onLine) return;
      try {
        const url = "https://gifwfjgciwbsottztzoc.supabase.co/rest/v1/";
        const key = "sb_publishable_hXK7wUdP8YiU7qFKh7_Cmg_Os0-QzAj";
        const t0 = performance.now();
        await fetch(url, { method: "HEAD", cache: "no-store", headers: { apikey: key } });
        if (!cancelled) setLatencyMs(Math.round(performance.now() - t0));
      } catch {
        if (!cancelled) setLatencyMs(null);
      }
    };
    ping();
    const id = setInterval(ping, 3e4);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);
  const quality = !isOnline ? "offline" : latencyMs === null ? "unknown" : latencyMs < 100 ? "excellent" : latencyMs < 250 ? "good" : latencyMs < 600 ? "fair" : "poor";
  return { onlineCount, latencyMs, effectiveType, quality, isOnline };
}
function SignalBars({ bars, color }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `flex items-end gap-[2px] ${color}`, style: { height: 10, width: 14 }, children: [1, 2, 3, 4].map((b) => /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      className: `w-[3px] rounded-[1px] transition-all duration-300 ${b <= bars ? "opacity-100" : "opacity-20"}`,
      style: { height: `${b * 25}%`, background: "currentColor" }
    },
    b
  )) });
}
const Q = {
  excellent: { bars: 4, dot: "bg-emerald-500", text: "text-emerald-600 dark:text-emerald-400", bg: "bg-emerald-500/10" },
  good: { bars: 3, dot: "bg-emerald-400", text: "text-emerald-500 dark:text-emerald-300", bg: "bg-emerald-400/10" },
  fair: { bars: 2, dot: "bg-amber-500", text: "text-amber-600  dark:text-amber-400", bg: "bg-amber-400/10" },
  poor: { bars: 1, dot: "bg-red-500", text: "text-red-600    dark:text-red-400", bg: "bg-red-500/10" },
  offline: { bars: 0, dot: "bg-red-600", text: "text-red-700    dark:text-red-400", bg: "bg-red-600/10" },
  unknown: { bars: 0, dot: "bg-muted-foreground", text: "text-muted-foreground", bg: "bg-muted/20" }
};
function OnlineStatusBar() {
  const { user } = useAuth();
  const { onlineCount, latencyMs, effectiveType, quality, isOnline } = useOnlineStatus(user?.id);
  const cfg = Q[quality];
  const connLabel = !isOnline ? "Hors ligne" : effectiveType ? effectiveType === "slow-2g" ? "Slow 2G" : effectiveType.toUpperCase() : "WiFi";
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full flex items-center justify-between px-4 py-[5px] border-b border-border/30 bg-background/70 backdrop-blur-sm text-[10px] leading-none z-30", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-muted-foreground", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "span",
        {
          className: `w-[7px] h-[7px] rounded-full flex-shrink-0 ${isOnline ? "bg-emerald-500 animate-pulse" : "bg-red-500"}`
        }
      ),
      onlineCount > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-foreground", children: onlineCount }),
        " ",
        "joueur",
        onlineCount > 1 ? "s" : "",
        " en ligne"
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "opacity-50", children: "Connexion…" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1.5 px-2 py-[3px] rounded-full ${cfg.bg} transition-all duration-500`, children: [
      isOnline ? /* @__PURE__ */ jsxRuntimeExports.jsx(SignalBars, { bars: cfg.bars, color: cfg.text }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-red-600", children: "✕" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `font-semibold ${cfg.text}`, children: connLabel }),
      latencyMs !== null && isOnline && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: cfg.text, children: [
        "· ",
        latencyMs,
        " ms"
      ] })
    ] })
  ] });
}
function useAdminPending() {
  const { isAdmin } = useAuth();
  const [state, setState] = reactExports.useState({ finance: 0, bugs: 0, total: 0 });
  reactExports.useEffect(() => {
    if (!isAdmin) return;
    async function load() {
      const [{ count: dep }, { count: wit }, { count: bug }] = await Promise.all([
        supabase.from("deposits").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.from("withdrawals").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.from("bug_reports").select("*", { count: "exact", head: true }).in("status", ["open", "in_progress"])
      ]);
      const finance = (dep ?? 0) + (wit ?? 0);
      const bugs = bug ?? 0;
      setState({ finance, bugs, total: finance + bugs });
    }
    load();
    const ch = supabase.channel("admin-pending-counts").on("postgres_changes", { event: "*", schema: "public", table: "deposits" }, load).on("postgres_changes", { event: "*", schema: "public", table: "withdrawals" }, load).on("postgres_changes", { event: "*", schema: "public", table: "bug_reports" }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [isAdmin]);
  return state;
}
function NavBadge({ count }) {
  if (count <= 0) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "ml-auto min-w-5 h-5 px-1.5 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center leading-none tabular-nums flex-shrink-0 shadow-sm", children: count > 99 ? "99+" : count });
}
function DesktopNav() {
  const loc = useLocation();
  const { isAdmin, profile } = useAuth();
  const { t } = useT();
  const pending = useAdminPending();
  const liveAvailable = useLiveAvailable();
  const items = [
    { to: "/", icon: House, label: t("home"), dot: false },
    { to: "/jeux", icon: Gamepad2, label: t("games") || "Jeux", dot: false },
    { to: "/chat", icon: MessageSquare, label: t("discussion"), dot: false },
    { to: "/live", icon: Radio, label: t("live"), dot: liveAvailable > 0 },
    { to: "/rankings", icon: Trophy, label: t("rankings"), dot: false },
    { to: "/history", icon: History, label: t("history"), dot: false },
    { to: "/profile", icon: User, label: t("my_profile"), dot: false }
  ];
  const adminItems = isAdmin ? [
    { to: "/admin", icon: Shield, label: t("admin"), badge: pending.finance },
    { to: "/admin-bug-reports", icon: Bug, label: "Signalements", badge: pending.bugs }
  ] : [];
  function isActive(to) {
    return loc.pathname === to || to !== "/" && loc.pathname.startsWith(to);
  }
  if (loc.pathname === "/login") return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("nav", { className: "hidden md:flex flex-col fixed left-0 top-14 bottom-0 w-60 z-20 py-3 px-2.5 overflow-y-auto\n      bg-card/90 backdrop-blur-xl border-r border-border/50\n      shadow-[1px_0_0_0_rgba(0,0,0,0.03)]", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-0.5", children: items.map((it) => {
      const active = isActive(it.to);
      const Icon = it.icon;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs(
        Link,
        {
          to: it.to,
          className: `relative flex items-center gap-3 px-3 py-2.5 rounded-xl font-medium text-sm transition-all duration-150 group ${active ? "bg-gradient-to-r from-primary/12 to-primary/4 text-primary font-semibold shadow-sm" : "text-muted-foreground hover:bg-accent/70 hover:text-foreground"}`,
          children: [
            active && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 rounded-r-full bg-primary" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `relative w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 transition-all duration-150 ${active ? "bg-primary/15 text-primary shadow-sm" : "bg-transparent text-muted-foreground group-hover:bg-accent group-hover:text-foreground"}`, children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4" }),
              it.dot && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "absolute -top-0.5 -right-0.5 flex h-2.5 w-2.5", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "animate-ping absolute inline-flex h-full w-full rounded-full bg-destructive opacity-75" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "relative inline-flex rounded-full h-2.5 w-2.5 bg-destructive border-2 border-card" })
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: it.label })
          ]
        },
        it.to
      );
    }) }),
    adminItems.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "my-3 flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 h-px bg-border/60" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold uppercase tracking-widest text-muted-foreground", children: "Admin" }),
          pending.total > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "relative flex h-2 w-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "animate-ping absolute inline-flex h-full w-full rounded-full bg-destructive opacity-75" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "relative inline-flex rounded-full h-2 w-2 bg-destructive" })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 h-px bg-border/60" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-0.5", children: adminItems.map((it) => {
        const active = isActive(it.to);
        const Icon = it.icon;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs(
          Link,
          {
            to: it.to,
            className: `relative flex items-center gap-3 px-3 py-2.5 rounded-xl font-medium text-sm transition-all duration-150 group ${active ? "bg-gradient-to-r from-amber-500/12 to-amber-400/4 text-amber-700 font-semibold" : "text-muted-foreground hover:bg-amber-50/70 hover:text-amber-800"}`,
            children: [
              active && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 rounded-r-full bg-amber-500" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 transition-all duration-150 ${active ? "bg-amber-100 text-amber-600" : "bg-transparent group-hover:bg-amber-100/70 group-hover:text-amber-600"}`, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4" }) }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate flex-1", children: it.label }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(NavBadge, { count: it.badge })
            ]
          },
          it.to
        );
      }) })
    ] }),
    profile && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-auto pt-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative overflow-hidden rounded-2xl bg-gradient-to-br from-primary/10 via-primary/6 to-orange-400/8 border border-primary/15 p-3.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -top-4 -right-4 w-16 h-16 rounded-full bg-primary/8 blur-xl" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 mb-0.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-3 h-3 text-amber-500" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground font-semibold uppercase tracking-wider", children: "Solde" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-black text-lg tabular-nums text-primary leading-tight", children: [
          Math.round(profile.balance_ar).toLocaleString("fr-FR"),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm font-semibold text-muted-foreground ml-1", children: "Ar" })
        ] })
      ] })
    ] }) })
  ] });
}
function AppSplash() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(PageLoader, { variant: "splash" });
}
function AuthLayout() {
  const {
    user,
    profile,
    loading
  } = useAuth();
  const {
    t
  } = useT();
  const loc = useLocation();
  const path = loc.pathname;
  const waiting = useWaitingRoomActive();
  const inGameRoute = /^\/(jeux\/)?(chess|domino|fanorona|rami|poker|ludo|game)\//.test(path);
  const inGame = inGameRoute && !waiting;
  path === "/chat" || path.startsWith("/discussion/");
  const isHome = path === "/lobby" || path === "/";
  if (loading) return /* @__PURE__ */ jsxRuntimeExports.jsx(AppSplash, {});
  if (!user) return /* @__PURE__ */ jsxRuntimeExports.jsx(Navigate, { to: "/login" });
  if (profile?.banned) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "min-h-screen flex items-center justify-center p-6 text-center", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-8 max-w-sm shadow-lg", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-3xl font-extrabold text-destructive mb-2", children: t("banned_account") }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-muted-foreground", children: t("contact_admin") })
  ] }) });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(PauseBanner, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Header, {}),
    !inGame && /* @__PURE__ */ jsxRuntimeExports.jsx(OnlineStatusBar, {}),
    !inGame && /* @__PURE__ */ jsxRuntimeExports.jsx(DesktopNav, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: inGame ? "fixed inset-0 top-14 overflow-hidden overscroll-none" : "md:ml-56", style: inGame ? {
      height: "calc(100dvh - 56px)"
    } : void 0, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Outlet, {}) }),
    !inGame && /* @__PURE__ */ jsxRuntimeExports.jsx(BottomNav, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(TermsModal, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(AnnouncementsModal, {}),
    isHome && /* @__PURE__ */ jsxRuntimeExports.jsx(ContactFab, {})
  ] });
}
export {
  AuthLayout as component
};
