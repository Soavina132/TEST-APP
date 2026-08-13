import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { MessageCircle, X } from "lucide-react";
import ChatRoom from "@/components/chat/ChatRoom";

// ─────────────────────────────────────────────────────────────────────────────
// GameSocialFab — single DRAGGABLE floating chat button.
// Click opens a mini panel: 8 emoji reactions on top + chat room below.
// Reactions float up from the button.
// ─────────────────────────────────────────────────────────────────────────────

const REACTIONS = [
  { emoji: "👍", label: "J'aime" },
  { emoji: "🔥", label: "Feu" },
  { emoji: "😂", label: "Haha" },
  { emoji: "❤️", label: "Cœur" },
  { emoji: "🎉", label: "Bravo" },
  { emoji: "😮", label: "Wow" },
  { emoji: "👏", label: "Clap" },
  { emoji: "😤", label: "Grrr" },
] as const;

const REACTION_LIFETIME_MS = 2200;
const BTN_SIZE = 44;
const EDGE_MARGIN = 4;
const POPUP_W = 280;
const POPUP_H = 360;

type FloatingReaction = { id: number; emoji: string; sender: string; dx: number };

export default function GameSocialFab({
  gameId,
  gameSlug,
  participants = [],
  isAdmin,
}: {
  gameId: string;
  gameSlug: string;
  participants?: { user_id?: string | null; display_name?: string | null; slot?: number; is_bot?: boolean }[];
  isAdmin?: boolean;
}) {
  const { t } = useT();
  const { profile, user } = useAuth();
  const [panelOpen, setPanelOpen] = useState(false);
  const [floaters, setFloaters] = useState<FloatingReaction[]>([]);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [unread, setUnread] = useState(0);
  const floatId = useRef(0);
  const reactionChRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

  // ── Draggable position (persisted per game) ──
  const posKey = `fabpos:${gameSlug}:${gameId}`;
  const getDefaultPos = () => {
    const saved = localStorage.getItem(posKey);
    if (saved) {
      try { return JSON.parse(saved); } catch { /* ignore */ }
    }
    return { x: window.innerWidth - BTN_SIZE - 12, y: window.innerHeight - BTN_SIZE - 80 };
  };
  const [pos, setPos] = useState<{ x: number; y: number }>({ x: 0, y: 0 });
  const [dragging, setDragging] = useState(false);
  const dragStart = useRef<{ mx: number; my: number; bx: number; by: number; moved: boolean } | null>(null);
  const wasTapRef = useRef(false);

  useEffect(() => {
    setPos(getDefaultPos());
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const onResize = () => {
      setPos((p) => ({
        x: Math.min(p.x, window.innerWidth - BTN_SIZE - EDGE_MARGIN),
        y: Math.min(p.y, window.innerHeight - BTN_SIZE - EDGE_MARGIN),
      }));
    };
    window.addEventListener("resize", onResize);
    return () => window.removeEventListener("resize", onResize);
  }, []);

  // ── Pointer drag handlers (works for mouse + touch) ──
  const onPointerDown = useCallback((e: React.PointerEvent) => {
    dragStart.current = { mx: e.clientX, my: e.clientY, bx: pos.x, by: pos.y, moved: false };
    (e.target as HTMLElement).setPointerCapture?.(e.pointerId);
  }, [pos.x, pos.y]);

  const onPointerMove = useCallback((e: React.PointerEvent) => {
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

  const onPointerUp = useCallback((e: React.PointerEvent) => {
    const ds = dragStart.current;
    dragStart.current = null;
    (e.target as HTMLElement).releasePointerCapture?.(e.pointerId);
    if (ds && !ds.moved) {
      // Mark as tap — onClick will handle opening panel
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

  const onClick = useCallback(() => {
    if (wasTapRef.current) {
      wasTapRef.current = false;
      openPanel();
    }
  }, []);

  // ── Chat room setup ──
  useEffect(() => {
    (async () => {
      const { data } = await supabase.rpc("chat_get_or_create_game_room" as any, { _game_id: gameId } as any);
      if (data) setRoomId(data as string);
    })();
  }, [gameId]);

  // ── Chat unread count ──
  const seenKey = `gamechat:lastseen:game:${gameId}`;
  useEffect(() => {
    if (!roomId || !user) return;
    const refresh = async () => {
      const lastSeen = Number(localStorage.getItem(seenKey) || 0);
      const since = lastSeen ? new Date(lastSeen).toISOString() : new Date(0).toISOString();
      const { count } = await supabase
        .from("chat_messages")
        .select("id", { count: "exact", head: true })
        .eq("room_id", roomId)
        .gt("created_at", since)
        .neq("user_id", user.id)
        .is("deleted_at", null);
      setUnread(count || 0);
    };
    refresh();
    const ch = supabase.channel(`gamechat-fab-unread-${roomId}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${roomId}` }, (payload: any) => {
        if (panelOpen) return;
        if (payload.new?.user_id === user.id) return;
        setUnread(u => u + 1);
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [roomId, user?.id, panelOpen]);

  // ── Reactions — float up from the button ──
  const getName = useCallback(
    (userId: string) => {
      if (userId === profile?.id) return profile?.pseudo || "Vous";
      const p = participants.find((p) => p.user_id === userId);
      return p?.display_name || "Joueur";
    },
    [profile?.id, profile?.pseudo, participants],
  );

  const pushReaction = useCallback((emoji: string, sender: string) => {
    const fid = ++floatId.current;
    const dx = -20 + Math.random() * 40;
    setFloaters((prev) => [...prev, { id: fid, emoji, sender, dx }]);
    setTimeout(() => setFloaters((prev) => prev.filter((f) => f.id !== fid)), REACTION_LIFETIME_MS);
  }, []);

  useEffect(() => {
    const ch = supabase
      .channel(`reactions-${gameSlug}-${gameId}`)
      .on("broadcast", { event: "reaction" }, (payload: any) => {
        const { emoji, user_id, display_name } = payload.payload || {};
        if (!emoji) return;
        const sender = display_name || getName(user_id) || "Joueur";
        pushReaction(emoji, sender);
      })
      .subscribe();
    reactionChRef.current = ch;
    return () => { supabase.removeChannel(ch); };
  }, [gameId, gameSlug, getName, pushReaction]);

  const sendReaction = useCallback(
    (emoji: string) => {
      reactionChRef.current?.send({
        type: "broadcast",
        event: "reaction",
        payload: { emoji, user_id: profile?.id, display_name: profile?.pseudo },
      });
      pushReaction(emoji, profile?.pseudo || "Vous");
    },
    [profile?.id, profile?.pseudo, pushReaction],
  );

  const openPanel = useCallback(() => {
    localStorage.setItem(seenKey, String(Date.now()));
    setUnread(0);
    setPanelOpen(true);
  }, [seenKey]);

  // Popup position: anchored near the button, clamped to viewport.
  const barBelow = pos.y < 180;
  const popupLeft = Math.max(8, Math.min(pos.x - POPUP_W / 2 + BTN_SIZE / 2, window.innerWidth - POPUP_W - 8));
  const popupTop = barBelow
    ? Math.min(pos.y + BTN_SIZE + 8, window.innerHeight - POPUP_H - 8)
    : Math.max(8, pos.y - POPUP_H - 8);

  return (
    <>
      {/* Reactions float up from the button — contained, not full-screen */}
      <div
        className="fixed pointer-events-none z-40 overflow-visible"
        style={{ left: pos.x + BTN_SIZE / 2, top: pos.y }}
      >
        {floaters.map((f) => (
          <div
            key={f.id}
            className="absolute"
            style={{ left: f.dx, top: 0, animation: "fabFloatUp 2.2s ease-out forwards" }}
          >
            <div className="flex flex-col items-center gap-0.5 -translate-x-1/2">
              <span className="text-2xl drop-shadow-lg">{f.emoji}</span>
              <span className="text-[9px] font-medium text-muted-foreground bg-card/80 rounded-full px-1.5 py-0.5 backdrop-blur-sm whitespace-nowrap">
                {f.sender}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* Draggable FAB — chat button style */}
      <div
        className="fixed z-50"
        style={{ left: pos.x, top: pos.y }}
      >
        <button
          onPointerDown={onPointerDown}
          onPointerMove={onPointerMove}
          onPointerUp={onPointerUp}
          onClick={onClick}
          className={`relative w-11 h-11 flex items-center justify-center rounded-full bg-primary text-primary-foreground shadow-lg transition-all active:scale-90 select-none ${dragging ? "cursor-grabbing opacity-80" : "cursor-grab hover:scale-110"}`}
          style={{ touchAction: "none" }}
          aria-label="Discussion et réactions — glisser pour déplacer"
        >
          <MessageCircle className="w-5 h-5 pointer-events-none" />
          {unread > 0 && !panelOpen && (
            <span className="absolute -top-1 -right-1 min-w-5 h-5 px-1 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-background">
              {unread > 99 ? "99+" : unread}
            </span>
          )}
        </button>
      </div>

      {/* Mini panel: 8 emojis on top + chat room below */}
      {panelOpen && (
        <>
          {/* Invisible tap-away layer — no dark backdrop, keeps board visible */}
          <div className="fixed inset-0 z-[54]" onClick={() => setPanelOpen(false)} />
          <div
            className="fixed z-[55] bg-card rounded-2xl overflow-hidden shadow-2xl border border-border/60 flex flex-col animate-pop-in"
            style={{ left: popupLeft, top: popupTop, width: POPUP_W, height: POPUP_H }}
            onClick={(e) => e.stopPropagation()}
          >
            {/* Header */}
            <div className="flex items-center justify-between px-3 py-1.5 border-b border-border/60 shrink-0">
              <div className="font-semibold text-xs">Discussion</div>
              <button onClick={() => setPanelOpen(false)} className="p-1 rounded-lg hover:bg-accent">
                <X className="w-3.5 h-3.5" />
              </button>
            </div>

            {/* 8 emoji reactions on top */}
            <div className="flex items-center justify-center gap-1 px-2 py-1.5 border-b border-border/60 shrink-0 bg-muted/30">
              {REACTIONS.map((r) => (
                <button
                  key={r.emoji}
                  onClick={() => { sendReaction(r.emoji); setPanelOpen(false); }}
                  className="w-8 h-8 flex items-center justify-center rounded-full hover:bg-accent hover:scale-125 transition-all duration-150 active:scale-90"
                  title={r.label}
                  aria-label={r.label}
                >
                  <span className="text-lg">{r.emoji}</span>
                </button>
              ))}
            </div>

            {/* Chat room below */}
            <div className="flex-1 overflow-hidden">
              {roomId ? (
                <ChatRoom roomId={roomId} title="Partie" height="h-full" />
              ) : (
                <div className="p-4 text-center text-xs text-muted-foreground">{t("loading_room")}</div>
              )}
            </div>
          </div>
        </>
      )}

      <style>{`
        @keyframes fabFloatUp {
          0% { transform: translateY(0) scale(0.5); opacity: 0; }
          15% { transform: translateY(-8px) scale(1.15); opacity: 1; }
          100% { transform: translateY(-90px) scale(1); opacity: 0; }
        }
      `}</style>
    </>
  );
}
