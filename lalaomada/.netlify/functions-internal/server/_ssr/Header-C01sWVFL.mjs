import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate, L as Link, d as useRouterState } from "../_libs/tanstack__react-router.mjs";
import { u as useAuth, a as useT } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { W as WalletButton } from "./WalletButton-BwZT8Njg.mjs";
import { h as ChevronDown, Z as Zap, O as LayoutGrid, x as User, G as Gamepad2, y as Shield, Q as LogOut, V as Bell, W as CheckCheck, X, Y as Megaphone, r as Send, _ as CircleAlert, c as Gift, a as Trophy, $ as ArrowUpRight, a0 as ArrowDownLeft } from "../_libs/lucide-react.mjs";
function playMatchPing() {
  try {
    const ctx = new (window.AudioContext || window.webkitAudioContext)();
    [0, 0.18, 0.36].forEach((t, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.type = "sine";
      osc.frequency.value = 660 + i * 110;
      gain.gain.setValueAtTime(0.4, ctx.currentTime + t);
      gain.gain.exponentialRampToValueAtTime(1e-3, ctx.currentTime + t + 0.15);
      osc.start(ctx.currentTime + t);
      osc.stop(ctx.currentTime + t + 0.15);
    });
  } catch {
  }
}
function requestBrowserNotifPermission() {
  if ("Notification" in window && Notification.permission === "default") Notification.requestPermission();
}
function showBrowserNotif(title, body, link) {
  if ("Notification" in window && Notification.permission === "granted") {
    const n = new Notification(title, { body, icon: "/favicon.ico", tag: "tournament-match" });
    if (link) n.onclick = () => {
      window.focus();
      window.location.href = link;
      n.close();
    };
    setTimeout(() => n.close(), 8e3);
  }
  if ("vibrate" in navigator) navigator.vibrate([200, 100, 200]);
}
const KIND = {
  deposit: { emoji: "💰", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowDownLeft, { className: "w-4 h-4" }), bg: "bg-emerald-50 dark:bg-emerald-950/40", border: "border-emerald-200 dark:border-emerald-800", dot: "bg-emerald-500", label: "Dépôt" },
  withdraw: { emoji: "💸", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowUpRight, { className: "w-4 h-4" }), bg: "bg-rose-50 dark:bg-rose-950/40", border: "border-rose-200 dark:border-rose-800", dot: "bg-rose-500", label: "Retrait" },
  tournament: { emoji: "🏆", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), bg: "bg-amber-50 dark:bg-amber-950/40", border: "border-amber-200 dark:border-amber-800", dot: "bg-amber-500", label: "Tournoi" },
  reward: { emoji: "🎁", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gift, { className: "w-4 h-4" }), bg: "bg-violet-50 dark:bg-violet-950/40", border: "border-violet-200 dark:border-violet-800", dot: "bg-violet-500", label: "Récompense" },
  admin: { emoji: "📢", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Megaphone, { className: "w-4 h-4" }), bg: "bg-blue-50 dark:bg-blue-950/40", border: "border-blue-200 dark:border-blue-800", dot: "bg-blue-500", label: "Admin" },
  system: { emoji: "⚙️", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleAlert, { className: "w-4 h-4" }), bg: "bg-secondary", border: "border-border", dot: "bg-muted-foreground", label: "Système" }
};
function kindOf(k) {
  return KIND[k] ?? KIND.system;
}
function timeAgo(iso) {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 6e4);
  if (m < 1) return "À l'instant";
  if (m < 60) return `Il y a ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `Il y a ${h}h`;
  const d = Math.floor(h / 24);
  if (d < 7) return `Il y a ${d}j`;
  return new Date(iso).toLocaleDateString("fr-FR", { day: "numeric", month: "short" });
}
function NotifCard({ n, urgent }) {
  const k = kindOf(n.kind);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "a",
    {
      href: n.link || "#",
      className: `flex gap-3 rounded-2xl p-3 border transition-colors hover:brightness-95 ${urgent ? "bg-amber-50 dark:bg-amber-950/40 border-amber-300 dark:border-amber-700 ring-1 ring-amber-400/40" : `${!n.read_at ? k.bg + " " + k.border : "bg-secondary/60 border-transparent"}`}`,
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-9 h-9 rounded-full flex items-center justify-center text-lg flex-shrink-0 border ${!n.read_at ? k.border : "border-transparent"} bg-card shadow-sm`, children: k.emoji }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: `text-sm leading-snug ${!n.read_at ? "font-bold" : "font-medium"} line-clamp-2`, children: n.title }),
            !n.read_at && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `mt-1 w-2 h-2 rounded-full flex-shrink-0 ${k.dot}` })
          ] }),
          n.body && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: `text-xs mt-0.5 line-clamp-2 leading-snug ${!n.read_at ? "text-foreground font-semibold" : "text-muted-foreground"}`, children: n.body }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mt-1.5 gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground", children: timeAgo(n.created_at) }),
            urgent && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] bg-amber-500 text-white px-2 py-0.5 rounded-full font-bold flex items-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-2.5 h-2.5" }),
              " Rejoindre →"
            ] }),
            !urgent && n.link && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-primary font-semibold", children: "Voir →" })
          ] })
        ] })
      ]
    }
  );
}
function NotificationsBell() {
  const { t } = useT();
  const { user } = useAuth();
  const [open, setOpen] = reactExports.useState(false);
  const [notifs, setNotifs] = reactExports.useState([]);
  const [dms, setDms] = reactExports.useState([]);
  const [reply, setReply] = reactExports.useState("");
  const [pulse, setPulse] = reactExports.useState(false);
  const ref = reactExports.useRef(null);
  const prevMatchRef = reactExports.useRef(/* @__PURE__ */ new Set());
  const load = reactExports.useCallback(async () => {
    if (!user) return;
    const [{ data: n }, { data: d }] = await Promise.all([
      supabase.from("notifications").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(50),
      supabase.from("admin_user_messages").select("*").order("created_at").limit(50)
    ]);
    const newNotifs = n || [];
    const newDms = d || [];
    const freshMatches = newNotifs.filter(
      (x) => !x.read_at && x.kind === "tournament" && !prevMatchRef.current.has(x.id)
    );
    if (freshMatches.length > 0 && prevMatchRef.current.size > 0) {
      playMatchPing();
      setPulse(true);
      setTimeout(() => setPulse(false), 2e3);
      const latest = freshMatches[0];
      showBrowserNotif(latest.title, latest.body ?? "", latest.link ?? void 0);
      if (!open) toast(latest.title, {
        description: latest.body,
        duration: 6e3,
        icon: "⚡",
        action: latest.link ? { label: "Voir", onClick: () => {
          window.location.href = latest.link;
        } } : void 0
      });
    }
    prevMatchRef.current = new Set(newNotifs.filter((x) => x.kind === "tournament").map((x) => x.id));
    setNotifs(newNotifs);
    setDms(newDms);
  }, [user, open]);
  reactExports.useEffect(() => {
    if (!user) return;
    load();
    requestBrowserNotifPermission();
    const ch = supabase.channel("notif-" + user.id).on("postgres_changes", { event: "*", schema: "public", table: "notifications", filter: `user_id=eq.${user.id}` }, load).on("postgres_changes", { event: "*", schema: "public", table: "admin_user_messages", filter: `user_id=eq.${user.id}` }, load).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [user?.id, load]);
  reactExports.useEffect(() => {
    const onClick = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);
  const unreadNotifs = notifs.filter((n) => !n.read_at).length;
  const unreadDms = dms.filter((d) => d.from_admin && !d.read_at).length;
  const unread = unreadNotifs + unreadDms;
  const urgentMatch = notifs.some((n) => !n.read_at && n.kind === "tournament");
  const matchAlerts = notifs.filter((n) => n.kind === "tournament" && !n.read_at);
  const otherNotifs = notifs.filter((n) => !(n.kind === "tournament" && !n.read_at));
  const openPanel = async () => {
    setOpen(true);
    await supabase.rpc("mark_notif_read", { _id: null });
    await supabase.rpc("mark_messages_read");
    setTimeout(load, 300);
  };
  const sendReply = async () => {
    if (!reply.trim() || !user) return;
    const { error } = await supabase.from("admin_user_messages").insert({
      user_id: user.id,
      from_admin: false,
      message: reply.trim()
    });
    if (error) return toast.error(error.message);
    setReply("");
    toast.success(t("sent_msg"));
    load();
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", ref, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => open ? setOpen(false) : openPanel(),
        className: `relative p-2 rounded-full transition-colors ${urgentMatch ? "hover:bg-amber-100 dark:hover:bg-amber-900/20" : "hover:bg-accent"}`,
        "aria-label": "Notifications",
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Bell, { className: `w-5 h-5 ${urgentMatch ? "text-amber-500" : ""}` }),
          urgentMatch && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute inset-0 rounded-full animate-ping bg-amber-400/30 pointer-events-none" }),
          unread > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `absolute -top-0.5 -right-0.5 min-w-4 h-4 px-1 rounded-full text-white text-[10px] font-bold flex items-center justify-center ${urgentMatch ? "bg-amber-500" : "bg-destructive"} ${pulse ? "scale-125" : ""} transition-transform`, children: unread > 99 ? "99+" : unread })
        ]
      }
    ),
    open && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "fixed inset-x-3 top-16 sm:absolute sm:inset-x-auto sm:right-0 sm:top-auto sm:mt-2 sm:w-96 max-h-[80vh] flex flex-col rounded-2xl bg-card shadow-2xl border border-border z-50 overflow-hidden", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 py-3 border-b border-border/60 flex items-center justify-between flex-shrink-0 bg-card", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Bell, { className: "w-4 h-4 text-primary" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: t("notifications_title") }),
          unread > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-[10px] px-2 py-0.5 rounded-full font-bold ${urgentMatch ? "bg-amber-500 text-white animate-pulse" : "bg-primary/15 text-primary"}`, children: [
            unread,
            " nouveau",
            unread > 1 ? "x" : ""
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1", children: [
          unread > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              title: "Tout marquer comme lu",
              onClick: async () => {
                await supabase.rpc("mark_notif_read", { _id: null });
                await supabase.rpc("mark_messages_read");
                load();
              },
              className: "p-1.5 rounded-full hover:bg-accent text-muted-foreground hover:text-foreground transition-colors",
              children: /* @__PURE__ */ jsxRuntimeExports.jsx(CheckCheck, { className: "w-4 h-4" })
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setOpen(false), className: "p-1.5 rounded-full hover:bg-accent text-muted-foreground hover:text-foreground transition-colors", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "overflow-y-auto flex-1 p-3 space-y-4", children: [
        notifs.length === 0 && dms.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center justify-center py-10 gap-3 text-center", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-14 h-14 rounded-full bg-muted flex items-center justify-center text-2xl", children: "🔔" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-semibold text-sm", children: "Tout est à jour" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground mt-0.5", children: "Vous n'avez aucune notification pour le moment." })
          ] })
        ] }),
        matchAlerts.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[10px] font-bold uppercase tracking-widest text-amber-600 flex items-center gap-1.5 px-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-3 h-3" }),
            " Matchs urgents"
          ] }),
          matchAlerts.map((n) => /* @__PURE__ */ jsxRuntimeExports.jsx(NotifCard, { n, urgent: true }, n.id))
        ] }),
        otherNotifs.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
          matchAlerts.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] font-bold uppercase tracking-widest text-muted-foreground px-1", children: "Autres" }),
          otherNotifs.map((n) => /* @__PURE__ */ jsxRuntimeExports.jsx(NotifCard, { n }, n.id))
        ] }),
        dms.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[10px] font-bold uppercase tracking-widest text-muted-foreground flex items-center gap-1.5 px-1", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Megaphone, { className: "w-3 h-3" }),
            " ",
            t("admin_conversation")
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl bg-secondary/60 p-3 space-y-2 max-h-48 overflow-y-auto", children: dms.map((d) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `flex ${d.from_admin ? "justify-start" : "justify-end"}`, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `max-w-[85%] px-3 py-2 rounded-2xl text-sm ${d.from_admin ? "bg-card shadow-sm rounded-tl-sm" : "bg-primary text-primary-foreground rounded-tr-sm"}`, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "leading-snug", children: d.message }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: `text-[10px] mt-1 ${d.from_admin ? "text-muted-foreground" : "text-primary-foreground/70"}`, children: timeAgo(d.created_at) })
          ] }) }, d.id)) })
        ] })
      ] }),
      (dms.length > 0 || notifs.some((n) => n.kind === "admin")) && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-3 pb-3 pt-2 border-t border-border/60 flex-shrink-0 flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "input",
          {
            value: reply,
            onChange: (e) => setReply(e.target.value),
            onKeyDown: (e) => e.key === "Enter" && !e.shiftKey && sendReply(),
            placeholder: t("reply_to_admin_placeholder"),
            className: "flex-1 px-3 py-2 rounded-full bg-secondary border border-border text-sm outline-none focus:ring-2 focus:ring-primary/30"
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            onClick: sendReply,
            disabled: !reply.trim(),
            className: "p-2 rounded-full bg-primary text-primary-foreground disabled:opacity-50 active:scale-95 transition-transform",
            children: /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4" })
          }
        )
      ] })
    ] })
  ] });
}
function RouteLoadingBar() {
  const status = useRouterState({ select: (s) => s.status });
  const isLoading = status === "pending";
  const [visible, setVisible] = reactExports.useState(false);
  const [progress, setProgress] = reactExports.useState(0);
  reactExports.useEffect(() => {
    let raf;
    let hideTimer;
    if (isLoading) {
      setVisible(true);
      setProgress(10);
      const tick = () => {
        setProgress((p) => p < 90 ? p + Math.max(0.4, (90 - p) * 0.04) : p);
        raf = window.requestAnimationFrame(tick);
      };
      raf = window.requestAnimationFrame(tick);
    } else if (visible) {
      setProgress(100);
      hideTimer = window.setTimeout(() => {
        setVisible(false);
        setProgress(0);
      }, 250);
    }
    return () => {
      if (raf !== void 0) cancelAnimationFrame(raf);
      if (hideTimer !== void 0) clearTimeout(hideTimer);
    };
  }, [isLoading]);
  if (!visible) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute left-0 right-0 bottom-0 h-[2px] overflow-hidden pointer-events-none", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      className: "h-full bg-gradient-to-r from-orange-400 via-orange-500 to-orange-400 shadow-[0_0_8px_rgba(249,115,22,0.7)] transition-[width,opacity] duration-200 ease-out",
      style: { width: `${progress}%`, opacity: progress === 100 ? 0 : 1 }
    }
  ) });
}
function Logo() {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative w-9 h-9 flex-shrink-0", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 rounded-xl bg-gradient-to-br from-red-500 via-orange-500 to-yellow-400 opacity-20 blur-sm" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative grid grid-cols-2 gap-[3px] w-9 h-9 p-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-full bg-gradient-to-br from-red-500 to-red-600 shadow-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-full bg-gradient-to-br from-green-400 to-green-600 shadow-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-full bg-gradient-to-br from-blue-500 to-blue-600 shadow-sm" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-full bg-gradient-to-br from-yellow-400 to-orange-400 shadow-sm" })
    ] })
  ] });
}
function Header() {
  const { user, profile, isAdmin, signOut } = useAuth();
  const { t } = useT();
  const navigate = useNavigate();
  const [open, setOpen] = reactExports.useState(false);
  const ref = reactExports.useRef(null);
  reactExports.useEffect(() => {
    const onClick = (e) => {
      if (ref.current && !ref.current.contains(e.target)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);
  if (!user || !profile) return null;
  const initials = (profile.pseudo || "?").slice(0, 2).toUpperCase();
  const balance = Math.round(profile.balance_ar).toLocaleString("fr-FR");
  return /* @__PURE__ */ jsxRuntimeExports.jsx(jsxRuntimeExports.Fragment, { children: /* @__PURE__ */ jsxRuntimeExports.jsx("header", { className: "sticky top-0 z-30", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative border-b border-border/40 bg-card shadow-[0_1px_0_0_rgba(0,0,0,0.04)]", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "max-w-5xl mx-auto px-3 h-14 flex items-center justify-between gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs(Link, { to: "/", className: "flex items-center gap-2.5 group min-w-0 overflow-hidden", "aria-label": "Lalao MADA", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Logo, {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "hidden min-[360px]:inline font-black text-base sm:text-lg tracking-tight bg-gradient-to-r from-primary to-orange-400 bg-clip-text text-transparent truncate", children: "Lalao MADA" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(WalletButton, {}),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "hidden sm:block" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(NotificationsBell, {}),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", ref, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "button",
            {
              onClick: () => setOpen((o) => !o),
              "aria-label": t("my_profile"),
              "aria-expanded": open,
              className: `flex items-center gap-2 pl-1.5 pr-2.5 py-1 rounded-full transition-all duration-200 border ${open ? "bg-primary/10 border-primary/30 shadow-sm" : "bg-accent/60 hover:bg-accent border-border/40 hover:border-border"}`,
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(
                    "div",
                    {
                      className: `w-7 h-7 rounded-full overflow-hidden flex items-center justify-center text-xs font-bold ring-2 transition-all duration-200 ${open ? "ring-primary/50" : "ring-border/60"}`,
                      style: { background: "var(--color-secondary)" },
                      children: profile.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: profile.avatar_url, alt: `Avatar de ${profile.pseudo}`, width: 32, height: 32, loading: "lazy", decoding: "async", className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary font-black", children: initials })
                    }
                  ),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-0 right-0 w-2 h-2 rounded-full bg-green-400 border-2 border-card" })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronDown, { className: `w-3.5 h-3.5 text-muted-foreground transition-transform duration-200 ${open ? "rotate-180" : ""}` })
              ]
            }
          ),
          open && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute right-0 mt-2.5 w-68 rounded-2xl bg-card shadow-2xl shadow-black/10 border border-border/60 overflow-hidden animate-pop-in z-50", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 py-3 bg-gradient-to-br from-primary/8 to-orange-400/5 border-b border-border/50", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: "w-10 h-10 rounded-full overflow-hidden flex items-center justify-center font-black text-primary ring-2 ring-primary/20",
                  style: { background: "var(--color-secondary)" },
                  children: profile.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: profile.avatar_url, alt: "", width: 32, height: 32, loading: "lazy", decoding: "async", className: "w-full h-full object-cover" }) : initials
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: profile.pseudo }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground font-mono", children: profile.unique_code }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 mt-0.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-3 h-3 text-amber-500" }),
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-semibold text-amber-600 tabular-nums", children: [
                    balance,
                    " Ar"
                  ] })
                ] })
              ] })
            ] }) }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-1.5", children: [
              [
                { icon: LayoutGrid, label: t("my_space"), to: "/" },
                { icon: User, label: t("my_profile"), to: "/profile" },
                { icon: Gamepad2, label: t("lobby"), to: "/jeux" }
              ].map((item) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
                "button",
                {
                  onClick: () => {
                    setOpen(false);
                    navigate({ to: item.to });
                  },
                  className: "w-full text-left px-3 py-2.5 rounded-xl hover:bg-accent/80 flex items-center gap-3 text-sm font-medium transition-colors group",
                  children: [
                    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-lg bg-secondary flex items-center justify-center group-hover:bg-primary/10 transition-colors", children: /* @__PURE__ */ jsxRuntimeExports.jsx(item.icon, { className: "w-3.5 h-3.5 text-muted-foreground group-hover:text-primary transition-colors" }) }),
                    item.label
                  ]
                },
                item.to
              )),
              isAdmin && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-3 my-1 border-t border-border/40" }),
                [
                  { icon: Shield, label: t("admin"), to: "/admin" }
                ].map((item) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      setOpen(false);
                      navigate({ to: item.to });
                    },
                    className: "w-full text-left px-3 py-2.5 rounded-xl hover:bg-amber-50 flex items-center gap-3 text-sm font-medium transition-colors group",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-lg bg-amber-100/80 flex items-center justify-center group-hover:bg-amber-200/60 transition-colors", children: /* @__PURE__ */ jsxRuntimeExports.jsx(item.icon, { className: "w-3.5 h-3.5 text-amber-600" }) }),
                      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-amber-700", children: item.label })
                    ]
                  },
                  item.to
                ))
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-3 my-1 border-t border-border/40" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs(
                "button",
                {
                  onClick: () => {
                    setOpen(false);
                    void signOut();
                    window.location.assign("/login");
                  },
                  className: "w-full text-left px-3 py-2.5 rounded-xl hover:bg-destructive/10 flex items-center gap-3 text-sm font-medium transition-colors group",
                  children: [
                    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-lg bg-destructive/10 flex items-center justify-center group-hover:bg-destructive/20 transition-colors", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-3.5 h-3.5 text-destructive" }) }),
                    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-destructive", children: t("logout") })
                  ]
                }
              )
            ] })
          ] })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(RouteLoadingBar, {})
  ] }) }) });
}
export {
  Header as H,
  Logo as L
};
