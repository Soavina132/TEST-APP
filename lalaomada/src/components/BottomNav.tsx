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
    const interval = setInterval(load, 20_000);
    return () => clearInterval(interval);
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
    const interval = setInterval(load, 30_000);
    return () => clearInterval(interval);
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
    const interval = setInterval(load, 15_000);
    return () => clearInterval(interval);
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
    { to: "/accueil",  icon: Home,          label: "Accueil",    badge: 0,            dot: false },
    { to: "/jeux",     icon: Gamepad2,      label: "Jeux",       badge: invites,      dot: false },
    { to: "/chat",     icon: MessageSquare, label: "Discussion", badge: chatUnread,   dot: false, highlightBadge: true },
    { to: "/live",     icon: Radio,         label: "LIVE",       badge: 0,            dot: liveAvailable > 0, liveLabel: true },
    { to: "/profile",  icon: User,          label: "Profil",     badge: notifsUnread, dot: false },
  ];

  return (
    <>
      {/* Spacer so content isn't hidden behind nav */}
      <div className="h-[72px] md:h-0" aria-hidden />

      <nav className="md:hidden fixed bottom-0 inset-x-0 z-40"
        style={{ paddingBottom: "env(safe-area-inset-bottom)" }}>

        {/* Glassmorphism bar */}
        <div style={{
          margin: "0 0 0 0",
          background: "rgba(10, 10, 20, 0.92)",
          backdropFilter: "blur(20px)",
          WebkitBackdropFilter: "blur(20px)",
          borderTop: "1px solid rgba(255,255,255,0.10)",
          boxShadow: "0 -4px 30px rgba(0,0,0,0.4)",
        }}>
          <div className="flex items-stretch justify-around h-[60px] px-1">
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
                  className="relative flex flex-col items-center justify-center flex-1 gap-0.5 min-w-0 active:scale-90 transition-transform duration-100 select-none"
                  style={{ WebkitTapHighlightColor: "transparent" }}
                >
                  {/* Active indicator — top bar */}
                  {active && (
                    <span className="absolute top-0 left-1/2 -translate-x-1/2 w-8 h-[3px] rounded-b-full"
                      style={{ background: "linear-gradient(90deg, #6366f1, #8b5cf6)" }} />
                  )}

                  {/* Icon container */}
                  <div className="relative flex items-center justify-center w-10 h-7">
                    {(it as any).liveLabel ? (
                      <span className={`text-[11px] font-black tracking-widest transition-colors ${
                        active ? "text-violet-400" : "text-white/40"
                      } ${liveAvailable > 0 ? "animate-pulse" : ""}`}>
                        LIVE
                      </span>
                    ) : (
                      <Icon
                        strokeWidth={active ? 2.2 : 1.6}
                        className={`w-[22px] h-[22px] transition-all ${
                          active ? "text-violet-400 drop-shadow-[0_0_6px_rgba(139,92,246,0.6)]" : "text-white/45"
                        }`}
                      />
                    )}

                    {/* Badge numérique */}
                    {it.badge > 0 && (
                      <span className={`absolute -top-1 -right-0.5 min-w-[17px] h-[17px] px-1 rounded-full text-white text-[9px] font-black flex items-center justify-center leading-none shadow ${
                        (it as any).highlightBadge ? "bg-red-500" : "bg-violet-600"
                      }`}
                        style={{ border: "1.5px solid rgba(10,10,20,0.9)" }}>
                        {it.badge > 99 ? "99+" : it.badge}
                      </span>
                    )}

                    {/* Dot live */}
                    {it.dot && (
                      <span className="absolute -top-0.5 -right-0.5 flex h-2.5 w-2.5">
                        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-red-400 opacity-70" />
                        <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-red-500"
                          style={{ border: "1.5px solid rgba(10,10,20,0.9)" }} />
                      </span>
                    )}
                  </div>

                  {/* Label */}
                  <span className={`text-[9px] font-semibold tracking-wide transition-colors ${
                    active ? "text-violet-400" : "text-white/35"
                  }`}>
                    {it.label}
                  </span>
                </Link>
              );
            })}
          </div>
        </div>
      </nav>
    </>
  );
}
