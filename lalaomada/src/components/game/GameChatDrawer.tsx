import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { MessageCircle, X } from "lucide-react";
import { useT } from "@/lib/i18n";
import ChatRoom from "./ChatRoom";

// Maps a game slug to the OFFICIAL general group room name.
// Used ONLY for game-lobby chat (the Resaka/lounge page), never for in-game chat.
const GROUP_NAME_FOR_SLUG: Record<string, string> = {
  ludo: "Groupe Ludo",
  domino: "Groupe Domino",
  chess: "Groupe Échec",
  fanorona: "Groupe Fanorona",
  rami: "Groupe Rami",
};

export default function GameChatDrawer({ gameId, isAdmin, gameSlug }: { gameId: string; isAdmin?: boolean; gameSlug?: string }) {
  const { t } = useT();
  const { user } = useAuth();
  const [open, setOpen] = useState(false);
  const [roomId, setRoomId] = useState<string | null>(null);
  const [unread, setUnread] = useState(0);

  const seenKey = `gamechat:lastseen:${gameSlug ? `group:${gameSlug}` : `game:${gameId}`}`;
  const getLastSeen = () => Number(localStorage.getItem(seenKey) || 0);

  useEffect(() => {
    (async () => {
      if (gameSlug) {
        // Lobby chat → look up the official general group; never auto-create.
        const targetName = GROUP_NAME_FOR_SLUG[gameSlug];
        if (!targetName) return;
        const { data: room } = await supabase
          .from("chat_rooms" as any)
          .select("id")
          .eq("type", "global")
          .eq("name", targetName)
          .maybeSingle();
        if (room) setRoomId((room as any).id);
      } else {
        // In-game chat → strictly isolated per-game room, no link to general groups.
        const { data } = await supabase.rpc("chat_get_or_create_game_room" as any, { _game_id: gameId } as any);
        if (data) setRoomId(data as string);
      }
    })();
  }, [gameId, gameSlug]);

  useEffect(() => {
    if (!roomId || !user) return;
    const refresh = async () => {
      const lastSeen = getLastSeen();
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
        if (open) return;
        if (payload.new?.user_id === user.id) return;
        setUnread(u => u + 1);
      })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [roomId, user?.id, open]);

  const openDrawer = () => {
    if (dragMovedRef.current) { dragMovedRef.current = false; return; }
    localStorage.setItem(seenKey, String(Date.now()));
    setUnread(0);
    setOpen(true);
  };

  // Draggable floating button (persists position per-device)
  const POS_KEY = "gamechat:fab-pos";
  const [pos, setPos] = useState<{ x: number; y: number }>(() => {
    if (typeof window === "undefined") return { x: 16, y: 96 };
    try { const s = localStorage.getItem(POS_KEY); if (s) return JSON.parse(s); } catch {}
    return { x: 16, y: 96 };
  });
  const dragRef = useRef<{ sx: number; sy: number; ox: number; oy: number; moved: boolean } | null>(null);
  const dragMovedRef = useRef(false);

  const onPointerDown = (e: React.PointerEvent) => {
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    dragRef.current = { sx: e.clientX, sy: e.clientY, ox: pos.x, oy: pos.y, moved: false };
  };
  const onPointerMove = (e: React.PointerEvent) => {
    if (!dragRef.current) return;
    const dx = e.clientX - dragRef.current.sx;
    const dy = e.clientY - dragRef.current.sy;
    if (Math.abs(dx) > 4 || Math.abs(dy) > 4) dragRef.current.moved = true;
    if (!dragRef.current.moved) return;
    const W = window.innerWidth, H = window.innerHeight;
    const nx = Math.min(Math.max(8, dragRef.current.ox - dx), W - 64);
    const ny = Math.min(Math.max(8, dragRef.current.oy - dy), H - 64);
    setPos({ x: nx, y: ny });
  };
  const onPointerUp = () => {
    if (dragRef.current?.moved) {
      dragMovedRef.current = true;
      try { localStorage.setItem(POS_KEY, JSON.stringify(pos)); } catch {}
    }
    dragRef.current = null;
  };

  return (
    <>
      <button
        onClick={openDrawer}
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        aria-label={gameSlug ? "Discussion générale" : "Discussion de la partie"}
        className="fixed z-40 h-14 w-14 rounded-full bg-primary text-primary-foreground shadow-2xl flex items-center justify-center hover:scale-110 transition touch-none select-none"
        style={{
          right: `max(${pos.x}px, env(safe-area-inset-right))`,
          bottom: `max(${pos.y}px, env(safe-area-inset-bottom))`,
        }}
      >
        <MessageCircle className="w-6 h-6" />
        {unread > 0 && (
          <span className="absolute -top-1 -right-1 min-w-5 h-5 px-1 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-background">
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>

      {open && (
        <div className="fixed inset-0 z-[55] flex items-end sm:items-center justify-center bg-black/50" onClick={() => setOpen(false)}>
          <div className="bg-card w-full sm:max-w-md sm:rounded-3xl rounded-t-3xl overflow-hidden shadow-2xl max-h-[90dvh] flex flex-col" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-4 py-2 border-b border-border/60 shrink-0">
              <div className="font-bold">{gameSlug ? `Discussion ${gameSlug}` : "Discussion de la partie"}</div>
              <button onClick={() => setOpen(false)} className="p-2 rounded-full hover:bg-accent"><X className="w-4 h-4" /></button>
            </div>
            <div className="flex-1 overflow-hidden">
              {roomId ? (
                <ChatRoom roomId={roomId} title={gameSlug ? `Groupe ${gameSlug}` : "Partie"} isAdmin={isAdmin} height="h-[60dvh]" gameSlug={gameSlug} />
              ) : (
                <div className="p-8 text-center text-muted-foreground">{t("loading_room")}</div>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
