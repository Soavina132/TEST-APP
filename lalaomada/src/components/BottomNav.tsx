import { Link, useLocation } from "@tanstack/react-router";
import { Home, MessageSquare, Radio, Gamepad2, User } from "lucide-react";
import { useT } from "@/lib/i18n";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useLiveAvailable } from "@/hooks/use-live-available";

function useChatUnread() {
  const { user } = useAuth();
  const [unread, setUnread] = useState(0);
  const loc = useLocation();

  useEffect(() => {
    const isDiscussion = loc.pathname === "/chat" || loc.pathname.startsWith("/discussion");
    if (!user || isDiscussion) { setUnread(0); return; }
    const lastKey = `chat_last_seen_${user.id}`;
    const lastSeen = localStorage.getItem(lastKey) || new Date(0).toISOString();

    const load = async () => {
      const { data: rooms } = await supabase.from("chat_rooms").select("id").eq("type", "global");
      if (!rooms?.length) return;
      const roomIds = rooms.map((r: any) => r.id);
      const { count } = await supabase.from("chat_messages")
        .select("id", { count: "exact", head: true })
        .in("room_id", roomIds)
        .neq("user_id", user.id)
        .gt("created_at", lastSeen)
        .is("deleted_at", null);
      setUnread(count || 0);
    };

    load();
    const ch = supabase.channel("nav-chat-" + user.id)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages" }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id, loc.pathname]);

  useEffect(() => {
    const isDiscussion = loc.pathname === "/chat" || loc.pathname.startsWith("/discussion");
    if (isDiscussion && user) {
      localStorage.setItem(`chat_last_seen_${user.id}`, new Date().toISOString());
      setUnread(0);
    }
  }, [loc.pathname, user?.id]);

  return unread;
}

function useInvitesCount() {
  const { user } = useAuth();
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!user) { setN(0); return; }
    const load = async () => {
      const { count } = await (supabase.from("game_invitations" as any) as any)
        .select("id", { count: "exact", head: true })
        .eq("receiver_id", user.id).eq("status", "pending");
      setN(count || 0);
    };
    load();
    const ch = supabase.channel("nav-inv-" + user.id)
      .on("postgres_changes", { event: "*", schema: "public", table: "game_invitations", filter: `receiver_id=eq.${user.id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id]);
  return n;
}

function useNotifsUnread() {
  const { user } = useAuth();
  const [n, setN] = useState(0);
  useEffect(() => {
    if (!user) { setN(0); return; }
    const load = async () => {
      const { count } = await (supabase.from("notifications" as any) as any)
        .select("id", { count: "exact", head: true })
        .eq("user_id", user.id).eq("read", false);
      setN(count || 0);
    };
    load();
    const ch = supabase.channel("nav-notif-" + user.id)
      .on("postgres_changes", { event: "*", schema: "public", table: "notifications", filter: `user_id=eq.${user.id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id]);
  return n;
}

export default function BottomNav() {
  const loc = useLocation();
  const { t } = useT();
  const chatUnread = useChatUnread();
  const liveAvailable = useLiveAvailable();
  const invites = useInvitesCount();
  const notifsUnread = useNotifsUnread();
  if (loc.pathname === "/login") return null;

  const items = [
    { to: "/lobby",   icon: Home,          label: t("home"),              badge: 0,   dot: false },
    { to: "/jeux",    icon: Gamepad2,      label: t("games") || "Jeux",  badge: invites, dot: false },
    { to: "/chat",    icon: MessageSquare, label: t("discussion"),        badge: chatUnread, dot: false },
    { to: "/live",    icon: Radio,         label: t("live"),              badge: 0,   dot: liveAvailable > 0 },
    { to: "/profile", icon: User,          label: t("profile"),           badge: notifsUnread, dot: false },
  ];

  return (
    <>
      <div className="h-20 md:h-0" aria-hidden />
      <div className="md:hidden fixed bottom-0 inset-x-0 z-40 pb-[env(safe-area-inset-bottom)]">
        <div className="mx-3 mb-2.5">
          <nav className="relative bg-card border border-border/50 rounded-2xl shadow-lg shadow-black/8 overflow-hidden">
            <div className="absolute inset-0 bg-gradient-to-b from-white/40 to-transparent pointer-events-none" />
            <div className="relative flex items-center justify-around px-1 py-1.5">
              {items.map(it => {
                const isChat = it.to === "/chat";
                const active = loc.pathname === it.to
                  || (it.to !== "/" && loc.pathname.startsWith(it.to))
                  || (isChat && loc.pathname.startsWith("/discussion"));
                const Icon = it.icon;
                return (
                  <Link
                    key={it.to}
                    to={it.to}
                    className="relative flex flex-col items-center gap-1 px-1 py-1 min-w-0 flex-1 group"
                  >
                    <div className={`relative flex items-center justify-center w-10 h-8 rounded-xl transition-all duration-200 ${
                      active
                        ? "bg-gradient-to-br from-primary/15 to-primary/8 shadow-sm"
                        : "group-active:bg-accent/80"
                    }`}>
                      <Icon className={`w-5 h-5 transition-all duration-200 ${
                        active ? "text-primary scale-110" : "text-muted-foreground group-hover:text-foreground"
                      }`} />
                      {it.badge > 0 && (
                        <span className="absolute -top-1.5 -right-1.5 min-w-[18px] h-[18px] px-1 rounded-full bg-destructive text-white text-[9px] font-bold flex items-center justify-center leading-none shadow-md border-2 border-card animate-bounce">
                          {it.badge > 99 ? "99+" : it.badge}
                        </span>
                      )}
                      {it.dot && (
                        <span className="absolute -top-0.5 -right-0.5 flex h-2.5 w-2.5">
                          <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-destructive opacity-75" />
                          <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-destructive border-2 border-card" />
                        </span>
                      )}
                      {active && (
                        <span className="absolute -bottom-0.5 left-1/2 -translate-x-1/2 w-1 h-1 rounded-full bg-primary" />
                      )}
                    </div>
                    <span className={`text-[9px] font-semibold truncate w-full text-center transition-colors duration-200 ${
                      active ? "text-primary" : "text-muted-foreground"
                    }`}>
                      {it.label}
                    </span>
                  </Link>
                );
              })}
            </div>
          </nav>
        </div>
      </div>
    </>
  );
}
