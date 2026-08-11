import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as useT, u as useAuth, R as Route$x } from "./router-CRCBvenY.mjs";
import { C as ChatRoom } from "./ChatRoom-DC72H67I.mjs";
import { toast } from "../_libs/sonner.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { U as Users, n as MessageSquare, L as Lock, ax as UserPlus, b as ChevronRight, X, ay as Crown } from "../_libs/lucide-react.mjs";
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
const ludoGroup = "/assets/ludo-group-2MEb5dBN.jpg";
const dominoGroup = "/assets/domino-group-5eOs5BW1.jpg";
const fanoronaGroup = "/assets/fanorona-group-BilGmCAc.jpg";
const chessGroup = "/assets/chess-group-DGt5Hv8R.jpg";
const ramiGroup = "/assets/rami-group-C2ylwzW7.jpg";
const pokerGroup = "/assets/poker-group-B8Gl1NRF.jpg";
const GAME_META = {
  ludo: {
    slug: "ludo",
    cover: ludoGroup,
    label: "Groupe Ludo",
    accent: "from-emerald-400/20 to-emerald-500/5"
  },
  domino: {
    slug: "domino",
    cover: dominoGroup,
    label: "Groupe Domino",
    accent: "from-stone-400/20 to-stone-500/5"
  },
  fanorona: {
    slug: "fanorona",
    cover: fanoronaGroup,
    label: "Groupe Fanorona",
    accent: "from-amber-500/20 to-amber-700/5"
  },
  chess: {
    slug: "chess",
    cover: chessGroup,
    label: "Groupe Échec",
    accent: "from-orange-400/20 to-orange-500/5"
  },
  echec: {
    slug: "chess",
    cover: chessGroup,
    label: "Groupe Échec",
    accent: "from-orange-400/20 to-orange-500/5"
  },
  rami: {
    slug: "rami",
    cover: ramiGroup,
    label: "Groupe Rami",
    accent: "from-rose-400/20 to-rose-500/5"
  },
  poker: {
    slug: "poker",
    cover: pokerGroup,
    label: "Groupe Poker",
    accent: "from-red-500/20 to-neutral-700/5"
  }
};
function metaFor(name) {
  const k = (name || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  for (const key of Object.keys(GAME_META)) {
    if (k.includes(key)) return GAME_META[key];
  }
  return null;
}
const lastReadKey = (uid, rid) => `chat_lastread_${uid || "anon"}_${rid}`;
function PremiumGate() {
  const {
    t
  } = useT();
  const premiumFeatures = [t("premium_feature_unlimited_dm"), t("premium_feature_badge"), t("premium_feature_priority_rooms"), t("premium_feature_priority_support")];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 flex flex-col items-center justify-center px-6 py-12 text-center gap-5", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-20 h-20 rounded-3xl bg-gradient-to-br from-yellow-400 to-amber-500 flex items-center justify-center shadow-lg shadow-amber-500/30", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-10 h-10 text-white" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "text-xl font-bold", children: t("premium_feature_title") }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground max-w-xs", children: t("premium_dm_desc") })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl bg-gradient-to-br from-yellow-50 to-amber-50 dark:from-yellow-950/30 dark:to-amber-950/30 border border-amber-200/50 dark:border-amber-800/40 p-4 w-full max-w-xs", children: /* @__PURE__ */ jsxRuntimeExports.jsx("ul", { className: "text-sm text-left space-y-2 text-muted-foreground", children: premiumFeatures.map((f) => /* @__PURE__ */ jsxRuntimeExports.jsxs("li", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-amber-500", children: "✦" }),
      " ",
      f
    ] }, f)) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => toast.info(t("contact_admin_premium")), className: "w-full max-w-xs py-3 rounded-2xl bg-gradient-to-r from-yellow-400 to-amber-500 text-white font-bold shadow-md shadow-amber-400/30 hover:from-yellow-500 hover:to-amber-600 transition-all active:scale-95 flex items-center justify-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-4 h-4" }),
      " ",
      t("upgrade_premium_btn")
    ] })
  ] });
}
function ChatHub() {
  const {
    t
  } = useT();
  const {
    user,
    isAdmin,
    profile
  } = useAuth();
  const isPremium = isAdmin || profile?.is_premium === true;
  const [tab, setTab] = reactExports.useState("global");
  const [rooms, setRooms] = reactExports.useState([]);
  const [active, setActive] = reactExports.useState(null);
  const [dms, setDms] = reactExports.useState([]);
  const [addDmCode, setAddDmCode] = reactExports.useState("");
  const [unread, setUnread] = reactExports.useState({});
  const [lastMsg, setLastMsg] = reactExports.useState({});
  const [showUserPicker, setShowUserPicker] = reactExports.useState(false);
  const [allUsers, setAllUsers] = reactExports.useState([]);
  const [userSearch, setUserSearch] = reactExports.useState("");
  const [loadingUsers, setLoadingUsers] = reactExports.useState(false);
  const loadRooms = async () => {
    const {
      data
    } = await supabase.from("chat_rooms").select("*").order("created_at", {
      ascending: true
    });
    const all = data || [];
    setRooms(all.filter((r) => r.type === "global" && r.enabled !== false));
    const myDms = all.filter((r) => r.type === "dm");
    const otherIds = myDms.map((r) => r.dm_user_a === user?.id ? r.dm_user_b : r.dm_user_a);
    if (otherIds.length) {
      const {
        data: profs
      } = await supabase.from("profiles").select("id,pseudo,avatar_url,unique_code").in("id", otherIds);
      const profMap = Object.fromEntries((profs || []).map((p) => [p.id, p]));
      setDms(myDms.map((r) => {
        const other = r.dm_user_a === user?.id ? r.dm_user_b : r.dm_user_a;
        return {
          ...r,
          other_profile: profMap[other]
        };
      }));
    } else {
      setDms([]);
    }
  };
  const refreshUnread = reactExports.useCallback(async (roomIds) => {
    if (!user || !roomIds.length || typeof window === "undefined") return;
    const counts = {};
    const lasts = {};
    await Promise.all(roomIds.map(async (rid) => {
      const since = localStorage.getItem(lastReadKey(user.id, rid)) || "1970-01-01";
      const {
        count
      } = await supabase.from("chat_messages").select("id", {
        count: "exact",
        head: true
      }).eq("room_id", rid).neq("user_id", user.id).gt("created_at", since).is("deleted_at", null);
      counts[rid] = count || 0;
      const {
        data: last
      } = await supabase.from("chat_messages").select("body,attachment_type").eq("room_id", rid).is("deleted_at", null).order("created_at", {
        ascending: false
      }).limit(1).maybeSingle();
      if (last) {
        lasts[rid] = last.attachment_type === "image" ? "📷 Image" : last.attachment_type === "audio" ? "🎤 Audio" : last.body?.slice(0, 50) || "";
      }
    }));
    setUnread((prev) => ({
      ...prev,
      ...counts
    }));
    setLastMsg((prev) => ({
      ...prev,
      ...lasts
    }));
  }, [user?.id]);
  reactExports.useEffect(() => {
    loadRooms();
  }, [user?.id]);
  reactExports.useEffect(() => {
    const allRooms = [...rooms, ...dms];
    if (allRooms.length) refreshUnread(allRooms.map((r) => r.id));
  }, [rooms.length, dms.length, refreshUnread]);
  reactExports.useEffect(() => {
    if (!user) return;
    let dt;
    const ch = supabase.channel("chat-hub-unread-" + user.id).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "chat_messages"
    }, () => {
      clearTimeout(dt);
      dt = setTimeout(() => {
        const allRooms = [...rooms, ...dms];
        if (allRooms.length) refreshUnread(allRooms.map((r) => r.id));
      }, 500);
    }).subscribe();
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
    };
  }, [user?.id, rooms.length, dms.length, refreshUnread]);
  const openRoom = (r) => {
    if (typeof window !== "undefined") {
      localStorage.setItem(lastReadKey(user?.id, r.id), (/* @__PURE__ */ new Date()).toISOString());
    }
    setUnread((prev) => ({
      ...prev,
      [r.id]: 0
    }));
    setActive(r);
  };
  const startDmWith = async (target) => {
    if (!target) return;
    if (target.id === user?.id) {
      toast.error(t("cant_message_self"));
      return;
    }
    const existing = dms.find((r) => r.dm_user_a === user?.id && r.dm_user_b === target.id || r.dm_user_b === user?.id && r.dm_user_a === target.id);
    if (existing) {
      openRoom(existing);
      return;
    }
    const {
      data: roomId,
      error
    } = await supabase.rpc("chat_get_or_create_dm", {
      _other: target.id
    });
    if (error || !roomId) {
      toast.error(t("conversation_create_error"));
      return;
    }
    toast.success(`${t("conversation_created_with")} ${target.pseudo} ${t("conversation_created_suffix")}`);
    await loadRooms();
    const {
      data: newRoom
    } = await supabase.from("chat_rooms").select("*").eq("id", roomId).maybeSingle();
    if (newRoom) openRoom({
      ...newRoom,
      other_profile: target
    });
  };
  const addDm = async () => {
    if (!addDmCode.trim()) return;
    const {
      data: target
    } = await supabase.from("profiles").select("id,pseudo,avatar_url,unique_code").eq("unique_code", addDmCode.trim().toUpperCase()).maybeSingle();
    if (!target) {
      toast.error(t("code_not_found"));
      return;
    }
    await startDmWith(target);
    setAddDmCode("");
  };
  const loadPlayerList = reactExports.useCallback(async (search2) => {
    setLoadingUsers(true);
    const {
      data,
      error
    } = await supabase.rpc("list_players_for_dm", {
      _search: search2.trim() || null,
      _limit: 50
    });
    if (error) toast.error(t("conversation_create_error"));
    setAllUsers(data || []);
    setLoadingUsers(false);
  }, [t]);
  const openUserPicker = async () => {
    setShowUserPicker(true);
    setUserSearch("");
    await loadPlayerList("");
  };
  reactExports.useEffect(() => {
    if (!showUserPicker) return;
    const id = setTimeout(() => loadPlayerList(userSearch), 300);
    return () => clearTimeout(id);
  }, [userSearch, showUserPicker, loadPlayerList]);
  const filteredUsers = allUsers;
  const search = Route$x.useSearch();
  const navigate = useNavigate();
  const [dmHandled, setDmHandled] = reactExports.useState(false);
  reactExports.useEffect(() => {
    const other = search?.dm;
    if (!other || !user?.id || dmHandled) return;
    if (other === user.id) {
      setDmHandled(true);
      navigate({
        to: "/chat",
        search: {},
        replace: true
      });
      return;
    }
    setDmHandled(true);
    (async () => {
      const {
        data: target
      } = await supabase.from("profiles").select("id,pseudo,avatar_url,unique_code").eq("id", other).maybeSingle();
      if (target) {
        setTab("dm");
        await startDmWith(target);
      }
      navigate({
        to: "/chat",
        search: {},
        replace: true
      });
    })();
  }, [search?.dm, user?.id, dmHandled, navigate]);
  if (active) {
    const meta = metaFor(active.name);
    const isDm = active.type === "dm";
    const label = isDm ? active.other_profile?.pseudo || t("dm_fallback_label") : meta?.label || active.name || t("group_fallback_label");
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex flex-col h-[calc(100dvh-4.75rem-5rem)] md:h-[calc(100dvh-4.75rem)]", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ChatRoom, { roomId: active.id, title: label, isAdmin, height: "flex-1", gameSlug: meta?.slug, onBack: () => setActive(null) }) });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-md mx-auto px-4 py-4 space-y-4 pb-28", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-2xl font-bold", children: t("discussion") }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }), label: t("groups_tab_label"), active: tab === "global", onClick: () => setTab("global"), badge: rooms.reduce((s, r) => s + (unread[r.id] || 0), 0) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { icon: isPremium ? /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4" }), label: isPremium ? t("private_messages_label") : `${t("private_messages_label")} ✦`, active: tab === "dm", onClick: () => setTab("dm"), badge: isPremium ? dms.reduce((s, r) => s + (unread[r.id] || 0), 0) : 0, premium: !isPremium })
    ] }),
    tab === "global" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2", children: rooms.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: t("no_groups_available") }) : rooms.map((r) => {
      const meta = metaFor(r.name);
      return /* @__PURE__ */ jsxRuntimeExports.jsx(GroupCard, { room: r, cover: meta?.cover, label: meta?.label || r.name, preview: lastMsg[r.id], unread: unread[r.id] || 0, onOpen: () => openRoom(r) }, r.id);
    }) }),
    tab === "dm" && (isPremium ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: addDmCode, onChange: (e) => setAddDmCode(e.target.value.toUpperCase()), onKeyDown: (e) => e.key === "Enter" && addDm(), placeholder: t("player_code_placeholder"), maxLength: 12, className: "flex-1 bg-transparent outline-none text-sm placeholder:text-muted-foreground" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: addDm, className: "px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold flex items-center gap-1", children: /* @__PURE__ */ jsxRuntimeExports.jsx(UserPlus, { className: "w-4 h-4" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: openUserPicker, className: "w-full rounded-2xl bg-card p-3 flex items-center justify-center gap-2 text-sm font-semibold text-primary shadow-sm hover:bg-accent", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-4 h-4" }),
        " ",
        t("browse_all_players")
      ] }),
      dms.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground text-sm", children: t("no_conversation_label") }) : dms.map((r) => {
        const other = r.other_profile;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openRoom(r), className: "w-full rounded-2xl bg-card p-3 shadow-sm flex items-center gap-3 hover:bg-accent text-left", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-12 h-12 rounded-full bg-accent overflow-hidden flex items-center justify-center shrink-0 border border-border", children: other?.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: other.avatar_url, width: 48, height: 48, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: other.pseudo }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-lg font-bold text-primary", children: (other?.pseudo || "?").slice(0, 1).toUpperCase() }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold truncate", children: other?.pseudo || t("player_fallback") }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground truncate", children: lastMsg[r.id] || t("start_conversation_label") })
          ] }),
          unread[r.id] > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx(UnreadBadge, { n: unread[r.id] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-4 h-4 text-muted-foreground shrink-0" })
        ] }, r.id);
      })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx(PremiumGate, {})),
    showUserPicker && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 bg-black/50 flex items-end justify-center", onClick: () => setShowUserPicker(false), children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full max-w-md bg-background rounded-t-3xl max-h-[80vh] flex flex-col", onClick: (e) => e.stopPropagation(), children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between p-4 border-b border-border", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-lg", children: t("all_players_title") }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setShowUserPicker(false), className: "p-1.5 rounded-full hover:bg-accent", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-5 h-5" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-3 border-b border-border", children: /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: userSearch, onChange: (e) => setUserSearch(e.target.value), placeholder: t("search_player_placeholder"), className: "w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 overflow-y-auto p-3 space-y-2", children: loadingUsers ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground text-sm py-6", children: t("loading_label") }) : filteredUsers.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center text-muted-foreground text-sm py-6", children: t("no_players_found") }) : filteredUsers.map((u) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3 rounded-2xl bg-card p-3 shadow-sm", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-11 h-11 rounded-full bg-accent overflow-hidden flex items-center justify-center shrink-0 border border-border", children: u.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: u.avatar_url, width: 44, height: 44, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: u.pseudo }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-base font-bold text-primary", children: (u.pseudo || "?").slice(0, 1).toUpperCase() }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 min-w-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold truncate", children: u.pseudo || t("player_fallback") }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
          setShowUserPicker(false);
          startDmWith(u);
        }, className: "shrink-0 px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-semibold flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-3.5 h-3.5" }),
          " ",
          t("send_message_btn")
        ] })
      ] }, u.id)) })
    ] }) })
  ] });
}
function TabBtn({
  icon,
  label,
  active,
  onClick,
  badge,
  premium
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: `relative py-2.5 rounded-2xl font-semibold text-sm flex items-center justify-center gap-1.5 transition-colors ${active ? premium ? "bg-gradient-to-r from-yellow-400 to-amber-500 text-white" : "bg-primary text-primary-foreground" : premium ? "bg-card border border-amber-300/60 text-amber-600 dark:text-amber-400" : "bg-card border border-border"}`, children: [
    icon,
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: label }),
    !!badge && badge > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1.5 -right-1.5 min-w-[20px] h-5 px-1 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-background", children: badge > 99 ? "99+" : badge })
  ] });
}
function UnreadBadge({
  n
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "ml-2 shrink-0 min-w-[22px] h-[22px] px-1.5 rounded-full bg-primary text-primary-foreground text-[11px] font-bold flex items-center justify-center", children: n > 99 ? "99+" : n });
}
function GroupCard({
  room,
  cover,
  label,
  preview,
  unread,
  onOpen
}) {
  const {
    t
  } = useT();
  const meta = metaFor(room.name);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: onOpen, className: "group w-full rounded-2xl bg-card border border-border/60 p-3 flex items-center gap-3 text-left transition-all hover:border-primary/40 hover:shadow-sm active:scale-[0.99]", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `relative w-14 h-14 rounded-xl overflow-hidden shrink-0 ring-1 ring-border/60 bg-gradient-to-br ${meta?.accent ?? "from-primary/15 to-primary/5"}`, children: cover ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: cover, width: 56, height: 56, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: label }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full grid place-items-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-6 h-6 text-primary/70" }) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-[15px] truncate", children: label }),
        room.enabled && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "shrink-0 w-1.5 h-1.5 rounded-full bg-emerald-500", "aria-hidden": true })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground truncate mt-0.5", children: preview || (room.enabled ? t("active_label") : t("inactive_label")) })
    ] }),
    unread > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx(UnreadBadge, { n: unread }) : /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-4 h-4 text-muted-foreground/60 shrink-0 transition-transform group-hover:translate-x-0.5" })
  ] });
}
export {
  ChatHub as component
};
