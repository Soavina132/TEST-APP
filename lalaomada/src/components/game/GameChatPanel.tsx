import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { MessageCircle, ChevronDown, X, Bell, BellOff, Wifi } from "lucide-react";
import { useT } from "@/lib/i18n";
import ChatRoom from "@/components/chat/ChatRoom";

// ── Constants ──────────────────────────────────────────────────────────────

const GROUP_NAME_FOR_SLUG: Record<string, string> = {
  ludo: "Groupe Ludo",
  domino: "Groupe Domino",
  chess: "Groupe Échec",
  fanorona: "Groupe Fanorona",
  rami: "Groupe Rami",
};

const COVER_FOR_SLUG: Record<string, string> = {
  chess: "/covers/chess-cover.webp",
  domino: "/covers/domino-cover.webp",
  fanorona: "/covers/fanorona-cover.webp",
  rami: "/covers/rami-cover.webp",
  ludo: "/covers/ludo-cover.webp",
};

const MUTE_STORAGE_KEY = "gamechat:muted";

// ── Notification sound ─────────────────────────────────────────────────────

function playNotificationSound() {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    const tones: [number, number, number][] = [
      [520, 0.0, 0.08],
      [680, 0.1, 0.1],
    ];
    tones.forEach(([freq, delay, dur]) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain);
      gain.connect(ctx.destination);
      osc.type = "sine";
      osc.frequency.value = freq;
      gain.gain.setValueAtTime(0, ctx.currentTime + delay);
      gain.gain.linearRampToValueAtTime(0.18, ctx.currentTime + delay + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + delay + dur);
      osc.start(ctx.currentTime + delay);
      osc.stop(ctx.currentTime + delay + dur + 0.01);
    });
  } catch {
    // silent fail
  }
}

// ── Types ──────────────────────────────────────────────────────────────────

type OnlineUser = {
  user_id: string;
  pseudo: string;
  avatar_url: string | null;
};

type MessageAlert = {
  id: string;
  senderPseudo: string;
  senderAvatar: string | null;
  body: string;
  coverUrl: string;
  groupLabel: string;
};

// ── Hooks ──────────────────────────────────────────────────────────────────

function useOnlineUsers(channelKey: string, me: OnlineUser | null) {
  const [users, setUsers] = useState<OnlineUser[]>([]);

  useEffect(() => {
    if (!me?.user_id || !channelKey) return;

    const ch = supabase.channel(`presence:${channelKey}`, {
      config: { presence: { key: me.user_id } },
    });

    ch.on("presence", { event: "sync" }, () => {
      const state = ch.presenceState<OnlineUser>();
      setUsers(
        Object.values(state)
          .flat()
          .map((p: any) => ({
            user_id: p.user_id,
            pseudo: p.pseudo || "?",
            avatar_url: p.avatar_url || null,
          }))
      );
    });

    ch.subscribe(async (status) => {
      if (status === "SUBSCRIBED") await ch.track(me);
    });

    return () => {
      ch.untrack();
      supabase.removeChannel(ch);
    };
  }, [channelKey, me?.user_id]);

  return users;
}

// ── Sub-components ─────────────────────────────────────────────────────────

function UserAvatar({ user }: { user: OnlineUser }) {
  const initials = (user.pseudo || "?").slice(0, 2).toUpperCase();
  return (
    <div
      title={user.pseudo}
      className="relative h-7 w-7 rounded-full ring-2 ring-card overflow-hidden bg-primary/20 flex items-center justify-center text-[10px] font-bold text-primary shrink-0"
    >
      {user.avatar_url ? (
        <img
          src={user.avatar_url}
          alt={user.pseudo}
          width={28}
          height={28}
          loading="lazy"
          decoding="async"
          className="w-full h-full object-cover"
        />
      ) : (
        initials
      )}
      {/* Green online dot */}
      <span className="absolute bottom-0 right-0 w-2 h-2 rounded-full bg-emerald-400 ring-1 ring-card" />
    </div>
  );
}

function FloatingAlert({
  alert,
  onOpen,
  onDismiss,
}: {
  alert: MessageAlert;
  onOpen: () => void;
  onDismiss: () => void;
}) {
  const senderInitials = alert.senderPseudo.slice(0, 2).toUpperCase();

  return (
    <div
      className="fixed bottom-24 right-4 z-50 w-72 rounded-2xl overflow-hidden shadow-2xl cursor-pointer
                 animate-in slide-in-from-bottom-4 fade-in duration-300"
      onClick={onOpen}
    >
      {/* Cover image header */}
      <div className="relative h-16 w-full overflow-hidden">
        {alert.coverUrl ? (
          <img
            src={alert.coverUrl}
            alt={alert.groupLabel}
            className="absolute inset-0 w-full h-full object-cover scale-105 blur-[2px]"
          />
        ) : (
          <div className="absolute inset-0 bg-gradient-to-br from-primary/80 to-primary/40" />
        )}
        <div className="absolute inset-0 bg-gradient-to-b from-black/30 to-black/75" />
        <div className="absolute bottom-2 left-3 flex items-center gap-1.5">
          <MessageCircle className="w-3 h-3 text-white/80" />
          <span className="text-white text-xs font-semibold drop-shadow">
            {alert.groupLabel}
          </span>
        </div>
        <button
          className="absolute top-2 right-2 h-6 w-6 rounded-full bg-black/50 flex items-center justify-center hover:bg-black/70 transition-colors backdrop-blur-sm"
          onClick={(e) => { e.stopPropagation(); onDismiss(); }}
        >
          <X className="w-3 h-3 text-white" />
        </button>
      </div>

      {/* Message preview */}
      <div className="bg-card/95 backdrop-blur-sm px-3 py-2.5 flex items-start gap-2.5">
        <div className="h-9 w-9 rounded-full overflow-hidden bg-primary/20 shrink-0 flex items-center justify-center text-xs font-bold text-primary ring-2 ring-primary/20">
          {alert.senderAvatar ? (
            <img
              src={alert.senderAvatar}
              alt={alert.senderPseudo}
              width={36}
              height={36}
              loading="lazy"
              decoding="async"
              className="w-full h-full object-cover"
            />
          ) : (
            senderInitials
          )}
        </div>
        <div className="min-w-0 flex-1 pt-0.5">
          <div className="text-xs font-bold truncate">{alert.senderPseudo}</div>
          <div className="text-xs text-muted-foreground line-clamp-2 leading-relaxed mt-0.5">
            {alert.body.substring(0, 80)}
          </div>
        </div>
      </div>

      {/* Tap hint */}
      <div className="bg-primary/8 border-t border-border/30 px-3 py-1.5 text-[10px] text-muted-foreground text-center font-medium tracking-wide">
        Appuyer pour ouvrir · auto-fermeture dans 5s
      </div>
    </div>
  );
}

// ── Main component ─────────────────────────────────────────────────────────

const MAX_VISIBLE_AVATARS = 4;

export default function GameChatPanel({
  gameId,
  isAdmin,
  gameSlug,
}: {
  gameId: string;
  isAdmin?: boolean;
  gameSlug?: string;
}) {
  const { t } = useT();
  const { user, profile } = useAuth();

  const [roomId, setRoomId] = useState<string | null>(null);
  const [open, setOpen] = useState(true);
  const [unread, setUnread] = useState(0);
  const [alert, setAlert] = useState<MessageAlert | null>(null);
  const [muted, setMuted] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return localStorage.getItem(MUTE_STORAGE_KEY) === "true";
  });

  const openRef = useRef(open);
  useEffect(() => { openRef.current = open; }, [open]);

  const mutedRef = useRef(muted);
  useEffect(() => { mutedRef.current = muted; }, [muted]);

  const alertTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // ── Presence ──────────────────────────────────────────────────────────────
  const mePresence: OnlineUser | null =
    user && profile
      ? { user_id: user.id, pseudo: profile.pseudo, avatar_url: profile.avatar_url }
      : null;

  const presenceKey = gameSlug ? `lobby:${gameSlug}` : `game:${gameId}`;
  const onlineUsers = useOnlineUsers(presenceKey, mePresence);

  const visible = onlineUsers.slice(0, MAX_VISIBLE_AVATARS);
  const overflow = onlineUsers.length - MAX_VISIBLE_AVATARS;

  const coverUrl = gameSlug ? (COVER_FOR_SLUG[gameSlug] ?? "") : "";

  // ── Room ID ───────────────────────────────────────────────────────────────
  useEffect(() => {
    (async () => {
      if (gameSlug) {
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
        const { data } = await supabase.rpc("chat_get_or_create_game_room" as any, {
          _game_id: gameId,
        } as any);
        if (data) setRoomId(data as string);
      }
    })();
  }, [gameId, gameSlug]);

  // ── New message listener ──────────────────────────────────────────────────
  useEffect(() => {
    if (!roomId || !user) return;

    const ch = supabase
      .channel(`gamechat-notify-${roomId}`)
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "chat_messages",
          filter: `room_id=eq.${roomId}`,
        },
        async (payload: any) => {
          const msg = payload.new;
          if (!msg || msg.user_id === user.id) return;

          if (!openRef.current) setUnread((u) => u + 1);

          const { data: sender } = await supabase
            .from("profiles")
            .select("pseudo, avatar_url")
            .eq("id", msg.user_id)
            .maybeSingle();

          const groupLabel = gameSlug
            ? `Discussion ${gameSlug}`
            : "Discussion de la partie";

          const newAlert: MessageAlert = {
            id: msg.id,
            senderPseudo: (sender as any)?.pseudo || "Joueur",
            senderAvatar: (sender as any)?.avatar_url || null,
            body: msg.body || "",
            coverUrl: gameSlug ? (COVER_FOR_SLUG[gameSlug] ?? "") : "",
            groupLabel,
          };

          if (!mutedRef.current) playNotificationSound();
          setAlert(newAlert);

          if (alertTimerRef.current) clearTimeout(alertTimerRef.current);
          alertTimerRef.current = setTimeout(() => setAlert(null), 5000);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(ch);
      if (alertTimerRef.current) clearTimeout(alertTimerRef.current);
    };
  }, [roomId, user?.id, gameSlug]);

  // ── Handlers ──────────────────────────────────────────────────────────────
  const handleToggle = () => {
    const next = !open;
    setOpen(next);
    if (next) setUnread(0);
  };

  const handleAlertOpen = () => {
    setOpen(true);
    setUnread(0);
    setAlert(null);
    if (alertTimerRef.current) clearTimeout(alertTimerRef.current);
  };

  const handleAlertDismiss = () => {
    setAlert(null);
    if (alertTimerRef.current) clearTimeout(alertTimerRef.current);
  };

  const handleMuteToggle = (e: React.MouseEvent) => {
    e.stopPropagation();
    const next = !muted;
    setMuted(next);
    try { localStorage.setItem(MUTE_STORAGE_KEY, String(next)); } catch {}
  };

  // ── Render ────────────────────────────────────────────────────────────────
  return (
    <>
      {alert && (
        <FloatingAlert
          alert={alert}
          onOpen={handleAlertOpen}
          onDismiss={handleAlertDismiss}
        />
      )}

      <div className="rounded-2xl overflow-hidden shadow-lg border border-white/8 bg-card">

        {/* ── Beautiful header with cover background ── */}
        <div className="relative overflow-hidden">
          {/* Blurred cover image as background */}
          {coverUrl && (
            <div
              className="absolute inset-0 bg-cover bg-center scale-110 opacity-25"
              style={{ backgroundImage: `url(${coverUrl})`, filter: "blur(12px)" }}
            />
          )}
          {/* Gradient overlay */}
          <div className="absolute inset-0 bg-gradient-to-r from-card/95 via-card/85 to-card/70" />

          {/* Header button */}
          <button
            onClick={handleToggle}
            className="relative w-full flex items-center justify-between px-4 py-3.5 hover:bg-white/5 transition-colors"
          >
            {/* Left: icon + title + unread */}
            <div className="flex items-center gap-2.5">
              <div className="relative shrink-0">
                <div className="w-8 h-8 rounded-xl bg-primary/15 flex items-center justify-center border border-primary/20">
                  <MessageCircle className="w-4 h-4 text-primary" />
                </div>
                {unread > 0 && !open && (
                  <span className="absolute -top-1.5 -right-1.5 min-w-[16px] h-4 px-1 rounded-full bg-red-500 text-white text-[9px] font-bold flex items-center justify-center shadow-lg animate-bounce">
                    {unread > 9 ? "9+" : unread}
                  </span>
                )}
              </div>
              <div className="text-left">
                <div className="font-bold text-sm leading-tight">
                  {gameSlug ? `Discussion ${gameSlug}` : "Discussion de la partie"}
                </div>
                {unread > 0 && !open ? (
                  <div className="text-[10px] text-red-400 font-semibold">
                    {unread} nouveau{unread > 1 ? "x" : ""} message{unread > 1 ? "s" : ""}
                  </div>
                ) : (
                  <div className="text-[10px] text-muted-foreground/70">
                    {open ? "Ouvert" : "Réduit"}
                  </div>
                )}
              </div>
            </div>

            {/* Right: online users + controls */}
            <div className="flex items-center gap-2">

              {/* Online count + stacked avatars */}
              {onlineUsers.length > 0 && (
                <div className="flex items-center gap-2">
                  <div className="flex -space-x-2.5">
                    {visible.map((u) => (
                      <UserAvatar key={u.user_id} user={u} />
                    ))}
                    {overflow > 0 && (
                      <div className="h-7 w-7 rounded-full ring-2 ring-card bg-secondary flex items-center justify-center text-[9px] font-bold text-muted-foreground">
                        +{overflow}
                      </div>
                    )}
                  </div>
                  <div className="flex items-center gap-1">
                    <Wifi className="w-3 h-3 text-emerald-400" />
                    <span className="text-[11px] font-semibold text-emerald-400">
                      {onlineUsers.length}
                    </span>
                  </div>
                </div>
              )}

              {/* Mute toggle */}
              <button
                onClick={handleMuteToggle}
                title={muted ? "Activer le son" : "Couper le son"}
                className="w-7 h-7 rounded-full bg-card/60 border border-white/10 flex items-center justify-center hover:bg-white/10 transition-all active:scale-90"
              >
                {muted
                  ? <BellOff className="w-3.5 h-3.5 text-muted-foreground" />
                  : <Bell className="w-3.5 h-3.5 text-muted-foreground" />
                }
              </button>

              {/* Chevron — rotates smoothly */}
              <div className={`w-7 h-7 rounded-full bg-card/60 border border-white/10 flex items-center justify-center transition-transform duration-300 ${open ? "rotate-180" : "rotate-0"}`}>
                <ChevronDown className="w-3.5 h-3.5 text-muted-foreground" />
              </div>
            </div>
          </button>
        </div>

        {/* ── Chat body — smooth slide open/close ── */}
        <div
          className={`overflow-hidden transition-all duration-300 ease-in-out ${
            open ? "max-h-[65dvh] opacity-100" : "max-h-0 opacity-0"
          }`}
        >
          <div className="border-t border-white/8">
            {roomId ? (
              <ChatRoom
                roomId={roomId}
                title={gameSlug ? `Groupe ${gameSlug}` : "Partie"}
                isAdmin={isAdmin}
                height="h-[50dvh]"
                gameSlug={gameSlug}
              />
            ) : (
              <div className="p-10 flex flex-col items-center gap-3 text-muted-foreground">
                <div className="w-8 h-8 rounded-full border-2 border-primary/30 border-t-primary animate-spin" />
                <span className="text-sm">{t("loading_room")}</span>
              </div>
            )}
          </div>
        </div>
      </div>
    </>
  );
}
