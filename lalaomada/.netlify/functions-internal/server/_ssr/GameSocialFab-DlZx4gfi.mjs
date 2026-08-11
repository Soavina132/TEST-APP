import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as useT, u as useAuth } from "./router-CRCBvenY.mjs";
import { C as ChatRoom } from "./ChatRoom-DC72H67I.mjs";
import { M as MessageCircle, X } from "../_libs/lucide-react.mjs";
const REACTIONS = [
  { emoji: "👍", label: "J'aime" },
  { emoji: "🔥", label: "Feu" },
  { emoji: "😂", label: "Haha" },
  { emoji: "❤️", label: "Cœur" },
  { emoji: "🎉", label: "Bravo" },
  { emoji: "😮", label: "Wow" },
  { emoji: "👏", label: "Clap" },
  { emoji: "😤", label: "Grrr" }
];
const REACTION_LIFETIME_MS = 2200;
const BTN_SIZE = 44;
const EDGE_MARGIN = 4;
const POPUP_W = 280;
const POPUP_H = 360;
function GameSocialFab({
  gameId,
  gameSlug,
  participants = [],
  isAdmin
}) {
  const { t } = useT();
  const { profile, user } = useAuth();
  const [panelOpen, setPanelOpen] = reactExports.useState(false);
  const [floaters, setFloaters] = reactExports.useState([]);
  const [roomId, setRoomId] = reactExports.useState(null);
  const [unread, setUnread] = reactExports.useState(0);
  const floatId = reactExports.useRef(0);
  const reactionChRef = reactExports.useRef(null);
  const posKey = `fabpos:${gameSlug}:${gameId}`;
  const getDefaultPos = () => {
    const saved = localStorage.getItem(posKey);
    if (saved) {
      try {
        return JSON.parse(saved);
      } catch {
      }
    }
    return { x: window.innerWidth - BTN_SIZE - 12, y: window.innerHeight - BTN_SIZE - 80 };
  };
  const [pos, setPos] = reactExports.useState({ x: 0, y: 0 });
  const [dragging, setDragging] = reactExports.useState(false);
  const dragStart = reactExports.useRef(null);
  const wasTapRef = reactExports.useRef(false);
  reactExports.useEffect(() => {
    setPos(getDefaultPos());
  }, []);
  reactExports.useEffect(() => {
    const onResize = () => {
      setPos((p) => ({
        x: Math.min(p.x, window.innerWidth - BTN_SIZE - EDGE_MARGIN),
        y: Math.min(p.y, window.innerHeight - BTN_SIZE - EDGE_MARGIN)
      }));
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);
  const onPointerDown = reactExports.useCallback((e) => {
    dragStart.current = { mx: e.clientX, my: e.clientY, bx: pos.x, by: pos.y, moved: false };
    e.target.setPointerCapture?.(e.pointerId);
  }, [pos.x, pos.y]);
  const onPointerMove = reactExports.useCallback((e) => {
    const ds = dragStart.current;
    if (!ds) return;
    const dx = e.clientX - ds.mx;
    const dy = e.clientY - ds.my;
    if (!ds.moved && Math.abs(dx) + Math.abs(dy) > 6) {
      ds.moved = true;
      setDragging(true);
    }
    if (!ds.moved) return;
    const nx = Math.max(EDGE_MARGIN, Math.min(ds.bx + dx, window.innerWidth - BTN_SIZE - EDGE_MARGIN));
    const ny = Math.max(EDGE_MARGIN, Math.min(ds.by + dy, window.innerHeight - BTN_SIZE - EDGE_MARGIN));
    setPos({ x: nx, y: ny });
  }, []);
  const onPointerUp = reactExports.useCallback((e) => {
    const ds = dragStart.current;
    dragStart.current = null;
    e.target.releasePointerCapture?.(e.pointerId);
    if (ds && !ds.moved) {
      wasTapRef.current = true;
    } else {
      wasTapRef.current = false;
      setPos((p) => {
        localStorage.setItem(posKey, JSON.stringify(p));
        return p;
      });
    }
    setDragging(false);
  }, [posKey]);
  const onClick = reactExports.useCallback(() => {
    if (wasTapRef.current) {
      wasTapRef.current = false;
      openPanel();
    }
  }, []);
  reactExports.useEffect(() => {
    (async () => {
      const { data } = await supabase.rpc("chat_get_or_create_game_room", { _game_id: gameId });
      if (data) setRoomId(data);
    })();
  }, [gameId]);
  const seenKey = `gamechat:lastseen:game:${gameId}`;
  reactExports.useEffect(() => {
    if (!roomId || !user) return;
    const refresh = async () => {
      const lastSeen = Number(localStorage.getItem(seenKey) || 0);
      const since = lastSeen ? new Date(lastSeen).toISOString() : (/* @__PURE__ */ new Date(0)).toISOString();
      const { count } = await supabase.from("chat_messages").select("id", { count: "exact", head: true }).eq("room_id", roomId).gt("created_at", since).neq("user_id", user.id).is("deleted_at", null);
      setUnread(count || 0);
    };
    refresh();
    const ch = supabase.channel(`gamechat-fab-unread-${roomId}`).on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${roomId}` }, (payload) => {
      if (panelOpen) return;
      if (payload.new?.user_id === user.id) return;
      setUnread((u) => u + 1);
    }).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [roomId, user?.id, panelOpen]);
  const getName = reactExports.useCallback(
    (userId) => {
      if (userId === profile?.id) return profile?.pseudo || "Vous";
      const p = participants.find((p2) => p2.user_id === userId);
      return p?.display_name || "Joueur";
    },
    [profile?.id, profile?.pseudo, participants]
  );
  const pushReaction = reactExports.useCallback((emoji, sender) => {
    const fid = ++floatId.current;
    const dx = -20 + Math.random() * 40;
    setFloaters((prev) => [...prev, { id: fid, emoji, sender, dx }]);
    setTimeout(() => setFloaters((prev) => prev.filter((f) => f.id !== fid)), REACTION_LIFETIME_MS);
  }, []);
  reactExports.useEffect(() => {
    const ch = supabase.channel(`reactions-${gameSlug}-${gameId}`).on("broadcast", { event: "reaction" }, (payload) => {
      const { emoji, user_id, display_name } = payload.payload || {};
      if (!emoji) return;
      const sender = display_name || getName(user_id) || "Joueur";
      pushReaction(emoji, sender);
    }).subscribe();
    reactionChRef.current = ch;
    return () => {
      supabase.removeChannel(ch);
    };
  }, [gameId, gameSlug, getName, pushReaction]);
  const sendReaction = reactExports.useCallback(
    (emoji) => {
      reactionChRef.current?.send({
        type: "broadcast",
        event: "reaction",
        payload: { emoji, user_id: profile?.id, display_name: profile?.pseudo }
      });
      pushReaction(emoji, profile?.pseudo || "Vous");
    },
    [profile?.id, profile?.pseudo, pushReaction]
  );
  const openPanel = reactExports.useCallback(() => {
    localStorage.setItem(seenKey, String(Date.now()));
    setUnread(0);
    setPanelOpen(true);
  }, [seenKey]);
  const barBelow = pos.y < 180;
  const popupLeft = Math.max(8, Math.min(pos.x - POPUP_W / 2 + BTN_SIZE / 2, window.innerWidth - POPUP_W - 8));
  const popupTop = barBelow ? Math.min(pos.y + BTN_SIZE + 8, window.innerHeight - POPUP_H - 8) : Math.max(8, pos.y - POPUP_H - 8);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "fixed pointer-events-none z-40 overflow-visible",
        style: { left: pos.x + BTN_SIZE / 2, top: pos.y },
        children: floaters.map((f) => /* @__PURE__ */ jsxRuntimeExports.jsx(
          "div",
          {
            className: "absolute",
            style: { left: f.dx, top: 0, animation: "fabFloatUp 2.2s ease-out forwards" },
            children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center gap-0.5 -translate-x-1/2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-2xl drop-shadow-lg", children: f.emoji }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-medium text-muted-foreground bg-card/80 rounded-full px-1.5 py-0.5 backdrop-blur-sm whitespace-nowrap", children: f.sender })
            ] })
          },
          f.id
        ))
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "fixed z-50",
        style: { left: pos.x, top: pos.y },
        children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onPointerDown,
            onPointerMove,
            onPointerUp,
            onClick,
            className: `relative w-11 h-11 flex items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-all active:scale-90 select-none ${dragging ? "cursor-grabbing opacity-80" : "cursor-grab hover:scale-110"}`,
            style: { touchAction: "none" },
            "aria-label": "Discussion et réactions — glisser pour déplacer",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(MessageCircle, { className: "w-5 h-5 pointer-events-none" }),
              unread > 0 && !panelOpen && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute -top-1 -right-1 min-w-5 h-5 px-1 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-background", children: unread > 99 ? "99+" : unread })
            ]
          }
        )
      }
    ),
    panelOpen && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-[54]", onClick: () => setPanelOpen(false) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "div",
        {
          className: "fixed z-[55] bg-card rounded-2xl overflow-hidden shadow-2xl border border-border/60 flex flex-col animate-pop-in",
          style: { left: popupLeft, top: popupTop, width: POPUP_W, height: POPUP_H },
          onClick: (e) => e.stopPropagation(),
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between px-3 py-1.5 border-b border-border/60 shrink-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-xs", children: "Discussion" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setPanelOpen(false), className: "p-1 rounded-lg hover:bg-accent", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3.5 h-3.5" }) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-center gap-1 px-2 py-1.5 border-b border-border/60 shrink-0 bg-muted/30", children: REACTIONS.map((r) => /* @__PURE__ */ jsxRuntimeExports.jsx(
              "button",
              {
                onClick: () => sendReaction(r.emoji),
                className: "w-8 h-8 flex items-center justify-center rounded-full hover:bg-accent hover:scale-125 transition-all duration-150 active:scale-90",
                title: r.label,
                "aria-label": r.label,
                children: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-lg", children: r.emoji })
              },
              r.emoji
            )) }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 overflow-hidden", children: roomId ? /* @__PURE__ */ jsxRuntimeExports.jsx(ChatRoom, { roomId, title: "Partie", height: "h-full" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-4 text-center text-xs text-muted-foreground", children: t("loading_room") }) })
          ]
        }
      )
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("style", { children: `
        @keyframes fabFloatUp {
          0% { transform: translateY(0) scale(0.5); opacity: 0; }
          15% { transform: translateY(-8px) scale(1.15); opacity: 1; }
          100% { transform: translateY(-90px) scale(1); opacity: 0; }
        }
      ` })
  ] });
}
export {
  GameSocialFab as G
};
