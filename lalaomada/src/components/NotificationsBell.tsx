import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Bell, X, Send, Trophy, Zap, CheckCheck, Coins, ArrowDownLeft, ArrowUpRight, Gift, Megaphone, AlertCircle } from "lucide-react";
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
const KIND: Record<string, { emoji: string; icon: React.ReactNode; bg: string; border: string; dot: string; label: string }> = {
  deposit:    { emoji:"💰", icon:<ArrowDownLeft className="w-4 h-4"/>, bg:"bg-emerald-50 dark:bg-emerald-950/40", border:"border-emerald-200 dark:border-emerald-800", dot:"bg-emerald-500", label:"Dépôt" },
  withdraw:   { emoji:"💸", icon:<ArrowUpRight  className="w-4 h-4"/>, bg:"bg-rose-50 dark:bg-rose-950/40",       border:"border-rose-200 dark:border-rose-800",         dot:"bg-rose-500",    label:"Retrait" },
  tournament: { emoji:"🏆", icon:<Trophy        className="w-4 h-4"/>, bg:"bg-amber-50 dark:bg-amber-950/40",     border:"border-amber-200 dark:border-amber-800",       dot:"bg-amber-500",   label:"Tournoi" },
  reward:     { emoji:"🎁", icon:<Gift          className="w-4 h-4"/>, bg:"bg-violet-50 dark:bg-violet-950/40",   border:"border-violet-200 dark:border-violet-800",     dot:"bg-violet-500",  label:"Récompense" },
  admin:      { emoji:"📢", icon:<Megaphone     className="w-4 h-4"/>, bg:"bg-blue-50 dark:bg-blue-950/40",       border:"border-blue-200 dark:border-blue-800",         dot:"bg-blue-500",    label:"Admin" },
  system:     { emoji:"⚙️", icon:<AlertCircle   className="w-4 h-4"/>, bg:"bg-secondary",                         border:"border-border",                                dot:"bg-muted-foreground", label:"Système" },
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

// ── Notification card ──────────────────────────────────────────────────────
function NotifCard({ n, urgent }: { n: any; urgent?: boolean }) {
  const k = kindOf(n.kind);
  return (
    <a href={n.link || "#"}
      className={`flex gap-3 rounded-2xl p-3 border transition-colors hover:brightness-95 ${urgent ? "bg-amber-50 dark:bg-amber-950/40 border-amber-300 dark:border-amber-700 ring-1 ring-amber-400/40" : `${!n.read_at ? k.bg + " " + k.border : "bg-secondary/60 border-transparent"}`}`}>
      {/* Icon bubble */}
      <div className={`w-9 h-9 rounded-full flex items-center justify-center text-lg flex-shrink-0 border ${!n.read_at ? k.border : "border-transparent"} bg-card shadow-sm`}>
        {k.emoji}
      </div>
      {/* Content */}
      <div className="flex-1 min-w-0">
        <div className="flex items-start justify-between gap-2">
          <p className={`text-sm leading-snug ${!n.read_at ? "font-bold" : "font-medium"} line-clamp-2`}>{n.title}</p>
          {!n.read_at && <span className={`mt-1 w-2 h-2 rounded-full flex-shrink-0 ${k.dot}`} />}
        </div>
        {n.body && <p className={`text-xs mt-0.5 line-clamp-2 leading-snug ${!n.read_at ? "text-foreground font-semibold" : "text-muted-foreground"}`}>{n.body}</p>}
        <div className="flex items-center justify-between mt-1.5 gap-2">
          <span className="text-[10px] text-muted-foreground">{timeAgo(n.created_at)}</span>
          {urgent && (
            <span className="text-[10px] bg-amber-500 text-white px-2 py-0.5 rounded-full font-bold flex items-center gap-1">
              <Zap className="w-2.5 h-2.5" /> Rejoindre →
            </span>
          )}
          {!urgent && n.link && (
            <span className="text-[10px] text-primary font-semibold">Voir →</span>
          )}
        </div>
      </div>
    </a>
  );
}

// ── Main component ─────────────────────────────────────────────────────────
export default function NotificationsBell() {
  const { t } = useT();
  const { user } = useAuth();
  const [open, setOpen]   = useState(false);
  const [notifs, setNotifs] = useState<any[]>([]);
  const [dms, setDms]     = useState<any[]>([]);
  const [reply, setReply] = useState("");
  const [pulse, setPulse] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const prevMatchRef = useRef<Set<string>>(new Set());

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
    const ch = supabase.channel("notif-" + user.id)
      .on("postgres_changes", { event: "*", schema: "public", table: "notifications",       filter: `user_id=eq.${user.id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "admin_user_messages", filter: `user_id=eq.${user.id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id, load]);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const unreadNotifs = notifs.filter(n => !n.read_at).length;
  const unreadDms    = dms.filter(d => d.from_admin && !d.read_at).length;
  const unread       = unreadNotifs + unreadDms;
  const urgentMatch  = notifs.some(n => !n.read_at && n.kind === "tournament");
  const matchAlerts  = notifs.filter(n => n.kind === "tournament" && !n.read_at);
  const otherNotifs  = notifs.filter(n => !(n.kind === "tournament" && !n.read_at));

  const openPanel = async () => {
    setOpen(true);
    await supabase.rpc("mark_notif_read" as any, { _id: null } as any);
    await supabase.rpc("mark_messages_read" as any);
    setTimeout(load, 300);
  };

  const sendReply = async () => {
    if (!reply.trim() || !user) return;
    const { error } = await supabase.from("admin_user_messages").insert({
      user_id: user.id, from_admin: false, message: reply.trim(),
    });
    if (error) return toast.error(error.message);
    setReply(""); toast.success(t("sent_msg")); load();
  };

  return (
    <div className="relative" ref={ref}>
      {/* ── Bell button ── */}
      <button
        onClick={() => open ? setOpen(false) : openPanel()}
        className={`relative p-2 rounded-full transition-colors ${urgentMatch ? "hover:bg-amber-100 dark:hover:bg-amber-900/20" : "hover:bg-accent"}`}
        aria-label="Notifications"
      >
        <Bell className={`w-5 h-5 ${urgentMatch ? "text-amber-500" : ""}`} />
        {urgentMatch && <span className="absolute inset-0 rounded-full animate-ping bg-amber-400/30 pointer-events-none" />}
        {unread > 0 && (
          <span className={`absolute -top-0.5 -right-0.5 min-w-4 h-4 px-1 rounded-full text-white text-[10px] font-bold flex items-center justify-center ${urgentMatch ? "bg-amber-500" : "bg-destructive"} ${pulse ? "scale-125" : ""} transition-transform`}>
            {unread > 99 ? "99+" : unread}
          </span>
        )}
      </button>

      {/* ── Panel ── */}
      {open && (
        <div className="fixed inset-x-3 top-16 sm:absolute sm:inset-x-auto sm:right-0 sm:top-auto sm:mt-2 sm:w-96 max-h-[80vh] flex flex-col rounded-2xl bg-card shadow-2xl border border-border z-50 overflow-hidden">
          {/* Header */}
          <div className="px-4 py-3 border-b border-border/60 flex items-center justify-between flex-shrink-0 bg-card">
            <div className="flex items-center gap-2">
              <Bell className="w-4 h-4 text-primary" />
              <span className="font-bold text-sm">{t("notifications_title")}</span>
              {unread > 0 && (
                <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold ${urgentMatch ? "bg-amber-500 text-white animate-pulse" : "bg-primary/15 text-primary"}`}>
                  {unread} nouveau{unread > 1 ? "x" : ""}
                </span>
              )}
            </div>
            <div className="flex items-center gap-1">
              {unread > 0 && (
                <button
                  title="Tout marquer comme lu"
                  onClick={async () => {
                    await supabase.rpc("mark_notif_read" as any, { _id: null } as any);
                    await supabase.rpc("mark_messages_read" as any);
                    load();
                  }}
                  className="p-1.5 rounded-full hover:bg-accent text-muted-foreground hover:text-foreground transition-colors"
                >
                  <CheckCheck className="w-4 h-4" />
                </button>
              )}
              <button onClick={() => setOpen(false)} className="p-1.5 rounded-full hover:bg-accent text-muted-foreground hover:text-foreground transition-colors">
                <X className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* Scrollable body */}
          <div className="overflow-y-auto flex-1 p-3 space-y-4">

            {/* Empty state */}
            {notifs.length === 0 && dms.length === 0 && (
              <div className="flex flex-col items-center justify-center py-10 gap-3 text-center">
                <div className="w-14 h-14 rounded-full bg-muted flex items-center justify-center text-2xl">🔔</div>
                <div>
                  <p className="font-semibold text-sm">Tout est à jour</p>
                  <p className="text-xs text-muted-foreground mt-0.5">Vous n'avez aucune notification pour le moment.</p>
                </div>
              </div>
            )}

            {/* Urgent match alerts */}
            {matchAlerts.length > 0 && (
              <div className="space-y-2">
                <p className="text-[10px] font-bold uppercase tracking-widest text-amber-600 flex items-center gap-1.5 px-1">
                  <Zap className="w-3 h-3" /> Matchs urgents
                </p>
                {matchAlerts.map(n => <NotifCard key={n.id} n={n} urgent />)}
              </div>
            )}

            {/* Other notifications */}
            {otherNotifs.length > 0 && (
              <div className="space-y-2">
                {matchAlerts.length > 0 && (
                  <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground px-1">Autres</p>
                )}
                {otherNotifs.map(n => <NotifCard key={n.id} n={n} />)}
              </div>
            )}

            {/* Admin DMs */}
            {dms.length > 0 && (
              <div className="space-y-2">
                <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground flex items-center gap-1.5 px-1">
                  <Megaphone className="w-3 h-3" /> {t("admin_conversation")}
                </p>
                <div className="rounded-2xl bg-secondary/60 p-3 space-y-2 max-h-48 overflow-y-auto">
                  {dms.map(d => (
                    <div key={d.id} className={`flex ${d.from_admin ? "justify-start" : "justify-end"}`}>
                      <div className={`max-w-[85%] px-3 py-2 rounded-2xl text-sm ${d.from_admin ? "bg-card shadow-sm rounded-tl-sm" : "bg-primary text-primary-foreground rounded-tr-sm"}`}>
                        <p className="leading-snug">{d.message}</p>
                        <p className={`text-[10px] mt-1 ${d.from_admin ? "text-muted-foreground" : "text-primary-foreground/70"}`}>
                          {timeAgo(d.created_at)}
                        </p>
                      </div>
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Reply input (if has DMs) */}
          {(dms.length > 0 || notifs.some(n => n.kind === "admin")) && (
            <div className="px-3 pb-3 pt-2 border-t border-border/60 flex-shrink-0 flex gap-2">
              <input
                value={reply}
                onChange={e => setReply(e.target.value)}
                onKeyDown={e => e.key === "Enter" && !e.shiftKey && sendReply()}
                placeholder={t("reply_to_admin_placeholder")}
                className="flex-1 px-3 py-2 rounded-full bg-secondary border border-border text-sm outline-none focus:ring-2 focus:ring-primary/30"
              />
              <button
                onClick={sendReply}
                disabled={!reply.trim()}
                className="p-2 rounded-full bg-primary text-primary-foreground disabled:opacity-50 active:scale-95 transition-transform"
              >
                <Send className="w-4 h-4" />
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
