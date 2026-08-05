import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { MessageCircle, X } from "lucide-react";
import ChatRoom from "@/components/chat/ChatRoom";

// ─────────────────────────────────────────────────────────────────────────────
// GameSocialFab — single floating button for emoji reactions + in-game chat.
// Replaces the old separate QuickReactions + GameChatDrawer combo.
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

const REACTION_LIFETIME_MS = 3000;

type FloatingReaction = { id: number; emoji: string; x: number; sender: string };
type RecentReaction = { id: number; emoji: string; sender: string };

export default function GameSocialFab({
  gameId,
  gameSlug,
  participants = [],
}: {
  gameId: string;
  gameSlug: string;
  participants?: { user_id?: string | null; display_name?: string | null; slot?: number; is_bot?: boolean }[];
}) {
  const { t } = useT();
  const { profile, user } = useAuth();
  const [showBar, setShowBar] = useState(false);
  const [chatOpen, setChatOpen] = useState(false);
  const [floaters, setFloaters] = useState<FloatingReaction[]>([]);
  const [recentReactions, setRecentReactions] = useState<RecentReaction[]>([]);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [unread, setUnread] = useState(0);
  const floatId = useRef(0);
  const recentId = useRef(0);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const reactionChRef = useRef<ReturnType<typeof supabase.channel> | null>(null);

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
    const ch = supabase.channel(`gamechat-unread-${roomId}`)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages", filter: `room_id=eq.${roomId}` }, (payload: any) => {
        if (chatOpen) return;
        if (payload.new?.user_id === user.id) return;
        setUnread(u => u + 1);
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [roomId, user?.id, chatOpen]);

  // ── Reactions ──
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
    const x = 20 + Math.random() * 60;
    setFloaters((prev) => [...prev, { id: fid, emoji, x, sender }]);
    setTimeout(() => setFloaters((prev) => prev.filter((f) => f.id !== fid)), REACTION_LIFETIME_MS);

    const rid = ++recentId.current;
    setRecentReactions((prev) => [{ id: rid, emoji, sender }, ...prev].slice(0, 5));
    setTimeout(() => setRecentReactions((prev) => prev.filter((r) => r.id !== rid)), REACTION_LIFETIME_MS);
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

  const openBar = useCallback(() => {
    setShowBar(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowBar(false), 5000);
  }, []);

  const keepBarOpen = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowBar(false), 5000);
  }, []);

  const openChat = useCallback(() => {
    localStorage.setItem(seenKey, String(Date.now()));
    setUnread(0);
    setChatOpen(true);
    setShowBar(false);
  }, [seenKey]);

  return (
    <>
      {/* Floating reactions overlay */}
      <div className="fixed inset-0 pointer-events-none z-40 overflow-hidden">
        {floaters.map((f) => (
          <div
            key={f.id}
            className="absolute bottom-32"
            style={{ left: `${f.x}%`, animation: "floatUp 3s ease-out forwards" }}
          >
            <div className="flex flex-col items-center gap-0.5">
              <span className="text-3xl drop-shadow-lg" style={{ filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.2))" }}>
                {f.emoji}
              </span>
              <span className="text-[10px] font-medium text-muted-foreground bg-card/80 rounded-full px-1.5 py-0.5 backdrop-blur-sm">
                {f.sender}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* Recent reactions log */}
      {recentReactions.length > 0 && !showBar && (
        <div className="fixed z-40 flex flex-col gap-1 items-center pointer-events-none left-1/2 -translate-x-1/2 bottom-20">
          {recentReactions.slice(0, 3).map((r, i) => (
            <div
              key={r.id}
              className="flex items-center gap-1 bg-card/90 rounded-full px-2 py-0.5 shadow-md backdrop-blur-sm animate-pop-in"
              style={{ opacity: 1 - i * 0.25 }}
            >
              <span className="text-sm">{r.emoji}</span>
              <span className="text-[10px] text-muted-foreground font-medium">{r.sender}</span>
            </div>
          ))}
        </div>
      )}

      {/* Unified FAB — top-right of the game area, away from game controls */}
      <div
        className="fixed z-40 flex flex-col items-end gap-2 right-3 top-16"
        onMouseEnter={keepBarOpen}
      >
        {showBar && (
          <div
            className="flex items-center gap-1 bg-card rounded-2xl shadow-xl border border-border/60 px-2 py-1.5 animate-pop-in"
            onMouseEnter={keepBarOpen}
          >
            {REACTIONS.map((r) => (
              <button
                key={r.emoji}
                onClick={() => sendReaction(r.emoji)}
                className="w-9 h-9 flex items-center justify-center rounded-full hover:bg-accent hover:scale-125 transition-all duration-150 active:scale-90"
                title={r.label}
                aria-label={r.label}
              >
                <span className="text-xl">{r.emoji}</span>
              </button>
            ))}
            {/* Divider */}
            <div className="w-px h-7 bg-border/60 mx-0.5" />
            {/* Chat button */}
            <button
              onClick={openChat}
              className="h-9 px-3 flex items-center gap-1.5 rounded-full hover:bg-accent transition-all duration-150 active:scale-90"
              title="Discuter"
              aria-label="Discuter"
            >
              <MessageCircle className="w-4 h-4 text-primary" />
              <span className="text-xs font-semibold text-primary">Chat</span>
            </button>
          </div>
        )}

        <button
          onClick={() => (showBar ? setShowBar(false) : openBar())}
          className="relative w-11 h-11 flex items-center justify-center rounded-full bg-card shadow-lg border border-border/60 hover:bg-accent transition-colors active:scale-90"
          aria-label="Réactions et discussion"
        >
          <span className="text-2xl">😀</span>
          {unread > 0 && (
            <span className="absolute -top-1 -right-1 min-w-5 h-5 px-1 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-background">
              {unread > 99 ? "99+" : unread}
            </span>
          )}
        </button>
      </div>

      {/* Chat drawer */}
      {chatOpen && (
        <div className="fixed inset-0 z-[55] flex items-end sm:items-center justify-center bg-black/50" onClick={() => setChatOpen(false)}>
          <div className="bg-card w-full sm:max-w-md sm:rounded-3xl rounded-t-3xl overflow-hidden shadow-2xl max-h-[90dvh] flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-4 py-2 border-b border-border/60 shrink-0">
              <div className="font-bold">Discussion de la partie</div>
              <button onClick={() => setChatOpen(false)} className="p-2 rounded-full hover:bg-accent"><X className="w-4 h-4" /></button>
            </div>
            <div className="flex-1 overflow-hidden">
              {roomId ? (
                <ChatRoom roomId={roomId} title="Partie" height="h-[60dvh]" />
              ) : (
                <div className="p-8 text-center text-muted-foreground">{t("loading_room")}</div>
              )}
            </div>
          </div>
        </div>
      )}

      <style>{`
        @keyframes floatUp {
          0% { transform: translateY(0) scale(0.5); opacity: 0; }
          15% { transform: translateY(-10px) scale(1.2); opacity: 1; }
          100% { transform: translateY(-200px) scale(1); opacity: 0; }
        }
      `}</style>
    </>
  );
}
