import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import {
  Bell, X, Send, Trophy, Zap, CheckCheck, ArrowDownLeft,
  ArrowUpRight, Gift, Megaphone, AlertCircle, BellOff, Inbox,
} from "lucide-react";
import { useT } from "@/lib/i18n";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";

// ── Audio ping ─────────────────────────────────────────────────────────────
function playMatchPing() {
  try {
    const ctx = new (window.AudioContext || (window as any).webkitAudioContext)();
    [0, 0.18, 0.36].forEach((t, i) => {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.connect(gain); gain.connect(ctx.destination);
      osc.type = "sine"; osc.frequency.value = 660 + i * 110;
      gain.gain.setValueAtTime(0.4, ctx.currentTime + t);
      gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + t + 0.15);
      osc.start(ctx.currentTime + t); osc.stop(ctx.currentTime + t + 0.15);
    });
  } catch {}
}
function requestBrowserNotifPermission() {
  if ("Notification" in window && Notification.permission === "default") Notification.requestPermission();
}
function showBrowserNotif(title: string, body: string, link?: string) {
  if ("Notification" in window && Notification.permission === "granted") {
    const n = new Notification(title, { body, icon: "/favicon.ico", tag: "tournament-match" });
    if (link) n.onclick = () => { window.focus(); window.location.href = link; n.close(); };
    setTimeout(() => n.close(), 8000);
  }
  if ("vibrate" in navigator) navigator.vibrate([200, 100, 200]);
}

// ── Type config ────────────────────────────────────────────────────────────
const KIND: Record<string, {
  emoji: string;
  icon: React.ReactNode;
  bg: string;
  border: string;
  dot: string;
  iconBg: string;
  label: string;
}> = {
  deposit:    { emoji:"💰", icon:<ArrowDownLeft className="w-4 h-4 text-emerald-600"/>, bg:"bg-emerald-50/80 dark:bg-emerald-950/30", border:"border-emerald-200/60 dark:border-emerald-800/60", dot:"bg-emerald-500", iconBg:"bg-emerald-100 dark:bg-emerald-900/50", label:"Dépôt" },
  withdraw:   { emoji:"💸", icon:<ArrowUpRight  className="w-4 h-4 text-rose-600"/>,    bg:"bg-rose-50/80 dark:bg-rose-950/30",       border:"border-rose-200/60 dark:border-rose-800/60",         dot:"bg-rose-500",    iconBg:"bg-rose-100 dark:bg-rose-900/50",    label:"Retrait" },
  tournament: { emoji:"🏆", icon:<Trophy        className="w-4 h-4 text-amber-600"/>,   bg:"bg-amber-50/80 dark:bg-amber-950/30",     border:"border-amber-200/60 dark:border-amber-800/60",       dot:"bg-amber-500",   iconBg:"bg-amber-100 dark:bg-amber-900/50",  label:"Tournoi" },
  reward:     { emoji:"🎁", icon:<Gift          className="w-4 h-4 text-violet-600"/>,  bg:"bg-violet-50/80 dark:bg-violet-950/30",   border:"border-violet-200/60 dark:border-violet-800/60",     dot:"bg-violet-500",  iconBg:"bg-violet-100 dark:bg-violet-900/50",label:"Récompense" },
  admin:      { emoji:"📢", icon:<Megaphone     className="w-4 h-4 text-blue-600"/>,    bg:"bg-blue-50/80 dark:bg-blue-950/30",       border:"border-blue-200/60 dark:border-blue-800/60",         dot:"bg-blue-500",    iconBg:"bg-blue-100 dark:bg-blue-900/50",    label:"Admin" },
  system:     { emoji:"⚙️", icon:<AlertCircle   className="w-4 h-4 text-muted-foreground"/>, bg:"bg-secondary/60", border:"border-border/50", dot:"bg-muted-foreground", iconBg:"bg-secondary", label:"Système" },
};
function kindOf(k: string) { return KIND[k] ?? KIND.system; }

// ── Relative time ──────────────────────────────────────────────────────────
function timeAgo(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1)  return "À l'instant";
  if (m < 60) return `Il y a ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `Il y a ${h}h`;
  const d = Math.floor(h / 24);
  if (d < 7)  return `Il y a ${d}j`;
  return new Date(iso).toLocaleDateString("fr-FR", { day:"numeric", month:"short" });
}

function dayLabel(iso: string) {
  const date = new Date(iso);
  const now = new Date();
  const diffDays = Math.floor((now.getTime() - date.getTime()) / 86400000);
  if (diffDays === 0) return "Aujourd'hui";
  if (diffDays === 1) return "Hier";
  if (diffDays < 7)  return date.toLocaleDateString("fr-FR", { weekday: "long" });
  return date.toLocaleDateString("fr-FR", { day: "numeric", month: "long" });
}

function groupByDay(items: any[]) {
  const groups: { label: string; items: any[] }[] = [];
  const map = new Map<string, any[]>();
  for (const item of items) {
    const lbl = dayLabel(item.created_at);
    if (!map.has(lbl)) { map.set(lbl, []); groups.push({ label: lbl, items: map.get(lbl)! }); }
    map.get(lbl)!.push(item);
  }
  return groups;
}

// ── Notification card ──────────────────────────────────────────────────────
function NotifCard({ n, urgent, onRead }: { n: any; urgent?: boolean; onRead?: () => void }) {
  const k = kindOf(n.kind);
  const isUnread = !n.read_at;
  return (
    <a
      href={n.link || "#"}
      onClick={onRead}
      className={`group flex gap-3 rounded-2xl p-3.5 border transition-all duration-200 active:scale-[0.98] ${
        urgent
          ? "bg-gradient-to-r from-amber-50 to-orange-50 dark:from-amber-950/30 dark:to-orange-950/20 border-amber-300/80 dark:border-amber-700/60 shadow-sm shadow-amber-200/40 dark:shadow-amber-900/20"
          : isUnread
            ? `${k.bg} ${k.border} shadow-sm`
            : "bg-transparent border-transparent hover:bg-accent/50"
      }`}
    >
      {/* Icon bubble */}
      <div className={`relative w-10 h-10 rounded-2xl flex items-center justify-center text-xl flex-shrink-0 ${isUnread ? k.iconBg : "bg-secondary/80"} shadow-sm`}>
        {k.emoji}
        {urgent && (
          <span className="absolute -top-1 -right-1 w-3.5 h-3.5 bg-amber-500 rounded-full flex items-center justify-center">
            <Zap className="w-2 h-2 text-white" />
          </span>
        )}
      </div>

      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <p className={`text-sm leading-snug line-clamp-2 ${isUnread ? "font-semibold text-foreground" : "font-medium text-muted-foreground"}`}>
            {n.title}
          </p>
          <div className="flex items-center gap-1.5 flex-shrink-0">
            {isUnread && <span className={`w-2 h-2 rounded-full flex-shrink-0 ${k.dot} mt-1`} />}
          </div>
        </div>
        {n.body && (
          <p className={`text-xs mt-0.5 line-clamp-2 leading-relaxed ${isUnread ? "text-foreground/80" : "text-muted-foreground"}`}>
            {n.body}
          </p>
        )}
        <div className="flex items-center justify-between mt-2 gap-2">
          <span className="text-[10px] text-muted-foreground/70 font-medium">{timeAgo(n.created_at)}</span>
          {urgent ? (
            <span className="text-[10px] bg-gradient-to-r from-amber-500 to-orange-500 text-white px-2.5 py-1 rounded-full font-bold flex items-center gap-1 shadow-sm">
              <Zap className="w-2.5 h-2.5" /> Rejoindre
            </span>
          ) : n.link ? (
            <span className="text-[10px] text-primary/80 font-semibold opacity-0 group-hover:opacity-100 transition-opacity">Voir →</span>
          ) : null}
        </div>
      </div>
    </a>
  );
}

// ── DM Card ────────────────────────────────────────────────────────────────
function DmCard({ dm }: { dm: any }) {
  const isUnread = dm.from_admin && !dm.read_at;
  return (
    <div className={`flex gap-3 rounded-2xl p-3.5 border transition-all ${
      isUnread ? "bg-blue-50/80 dark:bg-blue-950/30 border-blue-200/60 dark:border-blue-800/60 shadow-sm" : "bg-transparent border-transparent"
    }`}>
      <div className={`w-10 h-10 rounded-2xl flex items-center justify-center text-xl flex-shrink-0 ${isUnread ? "bg-blue-100 dark:bg-blue-900/50" : "bg-secondary/80"}`}>
        📢
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center justify-between gap-2">
          <p className={`text-xs font-semibold ${isUnread ? "text-blue-700 dark:text-blue-300" : "text-muted-foreground"}`}>
            {dm.from_admin ? "Administration" : "Vous"}
          </p>
          {isUnread && <span className="w-2 h-2 rounded-full bg-blue-500 flex-shrink-0" />}
        </div>
        <p className={`text-sm mt-0.5 line-clamp-3 leading-relaxed ${isUnread ? "font-medium text-foreground" : "text-muted-foreground"}`}>
          {dm.message}
        </p>
        <span className="text-[10px] text-muted-foreground/70 font-medium mt-1 block">{timeAgo(dm.created_at)}</span>
      </div>
    </div>
  );
}

// ── Empty state ────────────────────────────────────────────────────────────
function EmptyState() {
  return (
    <div className="flex flex-col items-center justify-center py-14 px-6 gap-4">
      <div className="w-16 h-16 rounded-3xl bg-secondary/80 flex items-center justify-center">
        <Inbox className="w-7 h-7 text-muted-foreground/50" />
      </div>
      <div className="text-center">
        <p className="text-sm font-semibold text-foreground/70">Aucune notification</p>
        <p className="text-xs text-muted-foreground mt-1">Vous êtes à jour !</p>
      </div>
    </div>
  );
}

// ── Tabs ───────────────────────────────────────────────────────────────────
type Tab = "notifs" | "messages";

// ── Main component ─────────────────────────────────────────────────────────
export default function NotificationsBell() {
  const { t } = useT();
  const { user } = useAuth();
  const [open, setOpen]     = useState(false);
  const [tab, setTab]       = useState<Tab>("notifs");
  const [notifs, setNotifs] = useState<any[]>([]);
  const [dms, setDms]       = useState<any[]>([]);
  const [reply, setReply]   = useState("");
  const [sending, setSending] = useState(false);
  const [pulse, setPulse]   = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const prevMatchRef = useRef<Set<string>>(new Set());
  const listRef = useRef<HTMLDivElement>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const [{ data: n }, { data: d }] = await Promise.all([
      (supabase.from("notifications" as any) as any)
        .select("*").eq("user_id", user.id)
        .order("created_at", { ascending: false }).limit(50),
      supabase.from("admin_user_messages").select("*")
        .order("created_at").limit(50),
    ]);
    const newNotifs: any[] = n || [];
    const newDms: any[]    = d || [];

    const freshMatches = newNotifs.filter(x =>
      !x.read_at && x.kind === "tournament" && !prevMatchRef.current.has(x.id)
    );
    if (freshMatches.length > 0 && prevMatchRef.current.size > 0) {
      playMatchPing(); setPulse(true); setTimeout(() => setPulse(false), 2000);
      const latest = freshMatches[0];
      showBrowserNotif(latest.title, latest.body ?? "", latest.link ?? undefined);
      if (!open) toast(latest.title, {
        description: latest.body, duration: 6000, icon: "⚡",
        action: latest.link ? { label: "Voir", onClick: () => { window.location.href = latest.link; } } : undefined,
      });
    }
    prevMatchRef.current = new Set(newNotifs.filter(x => x.kind === "tournament").map((x: any) => x.id));
    setNotifs(newNotifs); setDms(newDms);
  }, [user, open]);

  useEffect(() => {
    if (!user) return;
    load(); requestBrowserNotifPermission();
    // Polling every 15s — no realtime channel
    const interval = setInterval(load, 15_000);
    return () => clearInterval(interval);
  }, [user?.id, load]);

  // Close on outside click (desktop)
  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  // Lock body scroll on mobile when open
  useEffect(() => {
    if (open && window.innerWidth < 640) {
      document.body.style.overflow = "hidden";
    } else {
      document.body.style.overflow = "";
    }
    return () => { document.body.style.overflow = ""; };
  }, [open]);

  const unreadNotifs = notifs.filter(n => !n.read_at).length;
  const unreadDms    = dms.filter(d => d.from_admin && !d.read_at).length;
  const unread       = unreadNotifs + unreadDms;
  const urgentMatch  = notifs.some(n => !n.read_at && n.kind === "tournament");
  const matchAlerts  = notifs.filter(n => n.kind === "tournament" && !n.read_at);
  const otherNotifs  = notifs.filter(n => !(n.kind === "tournament" && !n.read_at));
  const groups       = groupByDay(otherNotifs);

  const openPanel = async () => {
    setOpen(true);
    await supabase.rpc("mark_notif_read" as any, { _id: null } as any);
    await supabase.rpc("mark_messages_read" as any);
    setTimeout(load, 300);
  };

  const markAllRead = async () => {
    await supabase.rpc("mark_notif_read" as any, { _id: null } as any);
    await supabase.rpc("mark_messages_read" as any);
    setTimeout(load, 200);
    toast.success("Tout marqué comme lu");
  };

  const sendReply = async () => {
    if (!reply.trim() || !user) return;
    setSending(true);
    const { error } = await supabase.from("admin_user_messages").insert({
      user_id: user.id, from_admin: false, message: reply.trim(),
    });
    setSending(false);
    if (error) return toast.error(error.message);
    setReply(""); toast.success(t("sent_msg")); load();
  };

  // ── Panel content ──────────────────────────────────────────────────────
  const PanelContent = (
    <div className="flex flex-col h-full">
      {/* Header */}
      <div className="flex-shrink-0 px-4 pt-4 pb-3 border-b border-border/50">
        <div className="flex items-center justify-between mb-3">
          <div>
            <h2 className="text-base font-bold text-foreground">Notifications</h2>
            {unread > 0 && (
              <p className="text-xs text-muted-foreground mt-0.5">
                {unread} non lue{unread > 1 ? "s" : ""}
              </p>
            )}
          </div>
          <div className="flex items-center gap-2">
            {unread > 0 && (
              <button
                onClick={markAllRead}
                className="flex items-center gap-1.5 text-xs font-semibold text-primary hover:text-primary/80 transition-colors px-2.5 py-1.5 rounded-xl hover:bg-primary/8 active:scale-95"
              >
                <CheckCheck className="w-3.5 h-3.5" />
                Tout lire
              </button>
            )}
            <button
              onClick={() => setOpen(false)}
              className="w-8 h-8 rounded-xl hover:bg-accent flex items-center justify-center transition-colors active:scale-95"
            >
              <X className="w-4 h-4 text-muted-foreground" />
            </button>
          </div>
        </div>

        {/* Tabs */}
        <div className="flex gap-1 bg-secondary/60 rounded-2xl p-1">
          {([
            { key: "notifs" as Tab,   label: "Activité",  count: unreadNotifs },
            { key: "messages" as Tab, label: "Messages",  count: unreadDms },
          ] as { key: Tab; label: string; count: number }[]).map(tb => (
            <button
              key={tb.key}
              onClick={() => setTab(tb.key)}
              className={`flex-1 flex items-center justify-center gap-1.5 py-2 px-3 rounded-xl text-xs font-semibold transition-all duration-200 ${
                tab === tb.key
                  ? "bg-card shadow-sm text-foreground"
                  : "text-muted-foreground hover:text-foreground"
              }`}
            >
              {tb.label}
              {tb.count > 0 && (
                <span className={`min-w-[18px] h-[18px] px-1 rounded-full text-[10px] font-bold flex items-center justify-center ${
                  tab === tb.key ? "bg-primary text-white" : "bg-muted-foreground/20 text-muted-foreground"
                }`}>
                  {tb.count > 9 ? "9+" : tb.count}
                </span>
              )}
            </button>
          ))}
        </div>
      </div>

      {/* Scrollable list */}
      <div ref={listRef} className="flex-1 overflow-y-auto overscroll-contain px-3 py-2 space-y-1">
        {tab === "notifs" ? (
          <>
            {/* Urgent alerts */}
            {matchAlerts.length > 0 && (
              <div className="mb-3">
                <div className="flex items-center gap-2 px-1 mb-2">
                  <span className="text-xs font-bold text-amber-600 dark:text-amber-400 uppercase tracking-wide">⚡ Match en attente</span>
                </div>
                <div className="space-y-1.5">
                  {matchAlerts.map(n => <NotifCard key={n.id} n={n} urgent />)}
                </div>
              </div>
            )}

            {/* Grouped notifs */}
            {groups.length === 0 && matchAlerts.length === 0
              ? <EmptyState />
              : groups.map(group => (
                <div key={group.label} className="mb-3">
                  <p className="text-[10px] font-bold text-muted-foreground uppercase tracking-widest px-1 mb-1.5">
                    {group.label}
                  </p>
                  <div className="space-y-1">
                    {group.items.map(n => <NotifCard key={n.id} n={n} />)}
                  </div>
                </div>
              ))
            }
          </>
        ) : (
          <>
            {/* Messages */}
            {dms.length === 0
              ? <EmptyState />
              : <div className="space-y-1.5">
                  {dms.map(d => <DmCard key={d.id} dm={d} />)}
                </div>
            }

            {/* Reply box */}
            <div className="sticky bottom-0 pt-2 pb-1">
              <div className="flex gap-2 bg-card rounded-2xl border border-border/60 shadow-sm p-1.5">
                <input
                  value={reply}
                  onChange={e => setReply(e.target.value)}
                  onKeyDown={e => e.key === "Enter" && !e.shiftKey && sendReply()}
                  placeholder="Répondre à l'admin…"
                  className="flex-1 bg-transparent text-sm px-2 py-1.5 outline-none placeholder:text-muted-foreground/60"
                />
                <button
                  onClick={sendReply}
                  disabled={!reply.trim() || sending}
                  className="w-9 h-9 rounded-xl bg-primary text-white flex items-center justify-center disabled:opacity-40 hover:bg-primary/90 active:scale-95 transition-all flex-shrink-0"
                >
                  {sending
                    ? <span className="w-3.5 h-3.5 border-2 border-white/40 border-t-white rounded-full animate-spin" />
                    : <Send className="w-3.5 h-3.5" />
                  }
                </button>
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  );

  return (
    <div className="relative" ref={ref}>
      {/* ── Bell button ── */}
      <button
        onClick={() => (open ? setOpen(false) : openPanel())}
        className={`relative p-2.5 rounded-2xl transition-all duration-200 active:scale-90 ${
          urgentMatch
            ? "text-amber-500 bg-amber-50 dark:bg-amber-950/30 hover:bg-amber-100 dark:hover:bg-amber-900/40"
            : open
              ? "bg-primary/10 text-primary"
              : "hover:bg-accent text-foreground/70"
        }`}
        aria-label="Notifications"
      >
        {urgentMatch
          ? <Bell className="w-5 h-5 fill-amber-400/30" />
          : <Bell className="w-5 h-5" />
        }

        {/* Ping ring for urgent */}
        {urgentMatch && (
          <span className="absolute inset-0 rounded-2xl animate-ping bg-amber-400/20 pointer-events-none" />
        )}

        {/* Badge */}
        {unread > 0 && (
          <span className={`absolute -top-0.5 -right-0.5 min-w-[18px] h-[18px] px-1 rounded-full text-white text-[10px] font-bold flex items-center justify-center transition-all duration-300 ${
            urgentMatch ? "bg-amber-500" : "bg-destructive"
          } ${pulse ? "scale-150" : "scale-100"} shadow-sm`}>
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>

      {/* ── Desktop popover ── */}
      {open && (
        <div className="hidden sm:block absolute right-0 mt-2.5 w-[380px] rounded-3xl bg-card shadow-2xl shadow-black/12 border border-border/50 overflow-hidden z-50 animate-[fadeSlideDown_0.2s_ease_both]"
          style={{ maxHeight: "80vh" }}>
          <style>{`@keyframes fadeSlideDown { from { opacity:0; transform:translateY(-8px) scale(0.97) } to { opacity:1; transform:translateY(0) scale(1) } }`}</style>
          {PanelContent}
        </div>
      )}

      {/* ── Mobile bottom sheet ── */}
      {open && (
        <div className="sm:hidden">
          {/* Backdrop */}
          <div
            className="fixed inset-0 bg-black/40 backdrop-blur-sm z-40 animate-[fadeIn_0.2s_ease]"
            onClick={() => setOpen(false)}
            style={{ animationName: "fadeIn" }}
          />
          <style>{`
            @keyframes fadeIn { from { opacity:0 } to { opacity:1 } }
            @keyframes slideUp { from { transform:translateY(100%) } to { transform:translateY(0) } }
          `}</style>
          {/* Sheet */}
          <div className="fixed bottom-0 left-0 right-0 z-50 bg-card rounded-t-3xl shadow-2xl border-t border-border/50 animate-[slideUp_0.3s_cubic-bezier(0.34,1.56,0.64,1)_both]"
            style={{ maxHeight: "88vh", height: "88vh" }}>
            {/* Handle */}
            <div className="flex justify-center pt-3 pb-1 flex-shrink-0">
              <div className="w-10 h-1 rounded-full bg-border" />
            </div>
            {PanelContent}
          </div>
        </div>
      )}
    </div>
  );
}
