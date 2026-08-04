import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { copyText } from "@/lib/clipboard";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  Camera, Copy, Coins, ShieldCheck, LogOut, Trash2,
  Phone, Trophy, Gamepad2, User, ChevronRight,
  CheckCheck, Send, Moon, Sun,
} from "lucide-react";
import { DeleteAccountDialog } from "@/components/DeleteAccountDialog";
import ThemeToggle from "@/components/ThemeToggle";
import { compressImageToWebp } from "@/lib/image-compress";
import { useTheme } from "@/hooks/use-theme";

export const Route = createFileRoute("/_authenticated/profile")({
  component: ProfilePage,
  head: () => ({ meta: [
    { title: "Mon profil — Lalao MADA" },
    { name: "description", content: "Profil joueur Lalao MADA : statistiques, jeux, classement et historique." },
  ] }),
});

const TABS = [
  { id: "apercu",   label: "Aperçu",   icon: <User className="w-4 h-4" /> },
  { id: "stats",    label: "Stats",    icon: <Gamepad2 className="w-4 h-4" /> },
  { id: "activite", label: "Activité", icon: <Coins className="w-4 h-4" /> },
  { id: "compte",   label: "Compte",   icon: <ChevronRight className="w-4 h-4" /> },
] as const;

type Tab = typeof TABS[number]["id"];

// ═══════════════════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════════════════

function levelTitle(l: number) {
  return (["Débutant", "Amateur", "Confirmé", "Expert", "Légende"] as const)[l - 1] || `Niveau ${l}`;
}

function xpForLevel(l: number) { return l * l * 10; }

function labelType(type: string, t: (k: string) => string) {
  return ({ deposit: t("tx_deposit"), withdraw: t("tx_withdraw"), stake: t("tx_stake"), win: t("tx_win"), bonus: t("tx_bonus"), referral: t("tx_referral"), admin_adjust: t("tx_admin_adjust"), refund: t("tx_refund") } as any)[type] || type;
}

function preferredGame(gameStats: Record<string, { played: number; wins: number }>) {
  let best = "—";
  let max = 0;
  for (const [k, v] of Object.entries(gameStats)) {
    if (v.played > max) { max = v.played; best = k.charAt(0).toUpperCase() + k.slice(1); }
  }
  return best;
}

// ═══════════════════════════════════════════════════════════════════════════
// Sub-components
// ═══════════════════════════════════════════════════════════════════════════

function XPBar({ level, wins }: { level: number; wins: number }) {
  const needed = xpForLevel(level);
  const prev = xpForLevel(level - 1);
  const pct = Math.min(100, Math.round(((wins - prev) / Math.max(1, needed - prev)) * 100));
  const [w, setW] = useState(0);
  useEffect(() => { const id = requestAnimationFrame(() => setW(pct)); return () => cancelAnimationFrame(id); }, [pct]);
  return (
    <div className="space-y-1.5">
      <div className="flex justify-between text-[11px] font-semibold">
        <span className="text-foreground">{levelTitle(level)}</span>
        <span className="text-muted-foreground tabular-nums">{wins}/{needed} XP</span>
      </div>
      <div className="h-2 rounded-full bg-secondary overflow-hidden">
        <div className="h-full rounded-full bg-primary transition-[width] duration-700 ease-out" style={{ width: `${w}%` }} />
      </div>
      <div className="text-right text-[10px] text-muted-foreground tabular-nums">{Math.max(0, needed - wins)} XP → Niv. {level + 1}</div>
    </div>
  );
}

function GameStatsRow({ game, icon, played, wins }: { game: string; icon: string; played: number; wins: number }) {
  const rate = played > 0 ? Math.round((wins / played) * 100) : 0;
  return (
    <div className="flex items-center gap-3 py-2.5">
      <div className="w-10 h-10 rounded-xl bg-secondary flex items-center justify-center text-lg shrink-0">{icon}</div>
      <div className="flex-1 min-w-0">
        <div className="font-semibold text-sm">{game}</div>
        <div className="text-[11px] text-muted-foreground">{played} parties · {wins}V · {played - wins}D</div>
      </div>
      <div className="text-right shrink-0">
        <div className="text-sm font-bold tabular-nums">{rate}%</div>
        <div className="h-1 w-12 rounded-full bg-secondary overflow-hidden mt-0.5">
          <div className="h-full rounded-full bg-emerald-500" style={{ width: `${rate}%` }} />
        </div>
      </div>
    </div>
  );
}

function FinRow({ left, status, amount, date }: any) {
  const { t } = useT();
  const cls = status === "approved" ? "bg-emerald-100 text-emerald-700" : status === "rejected" ? "bg-rose-100 text-rose-700" : "bg-amber-100 text-amber-700";
  const lbl = status === "approved" ? t("validated") : status === "rejected" ? t("rejected") : t("pending");
  return (
    <div className="flex items-center justify-between py-2.5 border-b border-border/40 last:border-0">
      <div className="min-w-0">
        <div className="font-semibold text-sm truncate max-w-[180px]">{left}</div>
        <div className="text-[10px] text-muted-foreground">{new Date(date).toLocaleString("fr-FR")}</div>
      </div>
      <div className="flex items-center gap-2 shrink-0">
        <span className={`text-[10px] px-2 py-1 rounded-full font-bold ${cls}`}>{lbl}</span>
        <div className={`font-bold text-sm ${Number(amount) >= 0 ? "text-emerald-600" : "text-destructive"}`}>
          {Number(amount) >= 0 ? "+" : ""}{Math.round(Number(amount)).toLocaleString("fr-FR")} Ar
        </div>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="rounded-2xl bg-card p-4 shadow-sm">
      <div className="font-bold text-xs uppercase tracking-widest text-muted-foreground mb-3">{title}</div>
      <div>{children}</div>
    </div>
  );
}

function Empty() {
  const { t } = useT();
  return <div className="text-center text-muted-foreground text-sm py-4">{t("no_items")}</div>;
}

function PhoneVerification({ adminPhone }: { adminPhone: string }) {
  const { t } = useT();
  const { profile, refreshProfile } = useAuth();
  const p: any = profile;
  const [phone, setPhone] = useState(p?.phone || "");
  const [code, setCode] = useState<string | null>(p?.phone_verification_code || null);
  const [busy, setBusy] = useState(false);

  const generate = async () => {
    if (!phone.trim()) return toast.error(t("enter_phone_error"));
    setBusy(true);
    const { data, error } = await supabase.rpc("request_phone_verification" as any, { _phone: phone.trim() } as any);
    setBusy(false);
    if (error) return toast.error(error.message);
    setCode(data as string);
    toast.success(t("code_generated"));
    refreshProfile();
  };

  if (p?.phone_verified) {
    return (
      <div className="rounded-2xl bg-card p-4 shadow-sm flex items-center gap-3">
        <ShieldCheck className="w-5 h-5 text-emerald-500 shrink-0" />
        <div>
          <div className="font-semibold text-sm text-emerald-600">{t("phone_verified_status")}</div>
          <div className="text-xs text-muted-foreground">{p.phone}</div>
        </div>
      </div>
    );
  }

  return (
    <div className="rounded-2xl bg-card p-4 shadow-sm space-y-3">
      <div className="font-semibold text-sm flex items-center gap-2"><Phone className="w-4 h-4 text-primary" /> {t("phone_verification_title")}</div>
      <div className="text-xs text-amber-700 bg-amber-50 dark:bg-amber-950/20 rounded-xl p-2.5">{t("phone_required_info")}</div>
      <input value={phone} onChange={e => setPhone(e.target.value)} placeholder={t("phone_placeholder")}
        className="w-full px-4 py-2.5 rounded-xl bg-secondary outline-none text-sm focus:ring-2 focus:ring-primary/30" />
      <button onClick={generate} disabled={busy} className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-sm">
        {busy ? "..." : code ? t("regenerate_code_btn") : t("generate_code_btn")}
      </button>
      {code && (
        <div className="rounded-xl bg-accent p-3 space-y-1 text-center">
          <div className="text-xs uppercase text-muted-foreground">{t("your_code_label")}</div>
          <div className="text-3xl font-black tracking-wider">{code}</div>
          <div className="text-xs text-muted-foreground">
            Envoyez ce code au numéro admin : <span className="font-bold">{adminPhone}</span>
          </div>
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Notifications Tab
// ═══════════════════════════════════════════════════════════════════════════

const NOTIF_KIND: Record<string, { emoji: string; bg: string; border: string; dot: string; label: string }> = {
  deposit:    { emoji:"💰", bg:"bg-emerald-50 dark:bg-emerald-950/30", border:"border-emerald-200 dark:border-emerald-800", dot:"bg-emerald-500",          label:"Dépôt" },
  withdraw:   { emoji:"💸", bg:"bg-rose-50 dark:bg-rose-950/30",       border:"border-rose-200 dark:border-rose-800",        dot:"bg-rose-500",             label:"Retrait" },
  tournament: { emoji:"🏆", bg:"bg-amber-50 dark:bg-amber-950/30",     border:"border-amber-200 dark:border-amber-800",      dot:"bg-amber-500",            label:"Tournoi" },
  reward:     { emoji:"🎁", bg:"bg-violet-50 dark:bg-violet-950/30",   border:"border-violet-200 dark:border-violet-800",    dot:"bg-violet-500",           label:"Récompense" },
  admin:      { emoji:"📢", bg:"bg-blue-50 dark:bg-blue-950/30",       border:"border-blue-200 dark:border-blue-800",        dot:"bg-blue-500",             label:"Admin" },
  system:     { emoji:"⚙️", bg:"bg-secondary",                          border:"border-border",                              dot:"bg-muted-foreground",     label:"Système" },
};
function nKind(k: string) { return NOTIF_KIND[k] ?? NOTIF_KIND.system; }

function nTimeAgo(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const m = Math.floor(diff / 60000);
  if (m < 1)  return "À l'instant";
  if (m < 60) return `Il y a ${m} min`;
  const h = Math.floor(m / 60);
  if (h < 24) return `Il y a ${h}h`;
  const d = Math.floor(h / 24);
  if (d < 7)  return `Il y a ${d}j`;
  return new Date(iso).toLocaleDateString("fr-FR");
}
function nDateLabel(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const h = diff / 3600000;
  if (h < 24) return "Aujourd'hui";
  if (h < 48) return "Hier";
  if (h < 168) return "Cette semaine";
  return "Plus ancien";
}

function NotifsTab() {
  const { user } = useAuth();
  const [loading, setLoading] = useState(true);
  const [notifs, setNotifs] = useState<any[]>([]);
  const [dms, setDms] = useState<any[]>([]);
  const [reply, setReply] = useState("");
  const [busy, setBusy] = useState(false);

  const load = async () => {
    if (!user) return;
    const [n, d] = await Promise.all([
      supabase.from("notifications").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(50),
      supabase.from("admin_user_messages").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(50),
    ]);
    setNotifs(n.data || []);
    setDms(d.data || []);
    setLoading(false);
  };

  useEffect(() => {
    if (!user) return;
    load();
    supabase.rpc("mark_notif_read" as any, { _id: null } as any);
    supabase.rpc("mark_messages_read" as any);
    const ch = supabase.channel("profile-notifs-" + user.id)
      .on("postgres_changes", { event: "*", schema: "public", table: "notifications",       filter: `user_id=eq.${user.id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "admin_user_messages", filter: `user_id=eq.${user.id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [user?.id]);

  const sendReply = async () => {
    if (!reply.trim() || !user) return;
    setBusy(true);
    const { error } = await supabase.from("admin_user_messages").insert({ user_id: user.id, from_admin: false, message: reply.trim() });
    setBusy(false);
    if (error) { toast.error(error.message); return; }
    setReply(""); toast.success("Message envoyé"); load();
  };

  const unread = notifs.filter(n => !n.read_at).length + dms.filter(d => d.from_admin && !d.read_at).length;

  const groups: { label: string; items: any[] }[] = [];
  const buckets: Record<string, any[]> = {};
  for (const n of notifs) {
    const lbl = nDateLabel(n.created_at);
    if (!buckets[lbl]) buckets[lbl] = [];
    buckets[lbl].push(n);
  }
  const ORDER = ["Aujourd'hui", "Hier", "Cette semaine", "Plus ancien"];
  for (const lbl of ORDER) {
    if (buckets[lbl]?.length) groups.push({ label: lbl, items: buckets[lbl] });
  }

  if (loading) return <div className="py-10 text-center text-muted-foreground text-sm animate-pulse">Chargement…</div>;

  return (
    <div className="space-y-4">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h2 className="font-bold text-sm">Notifications</h2>
          {unread > 0 && <span className="text-[10px] bg-destructive text-white px-2 py-0.5 rounded-full font-bold">{unread}</span>}
        </div>
        {unread > 0 && (
          <button onClick={async () => { await supabase.rpc("mark_notif_read" as any, { _id: null } as any); await supabase.rpc("mark_messages_read" as any); load(); }}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors">
            <CheckCheck className="w-3.5 h-3.5" /> Tout marquer lu
          </button>
        )}
      </div>

      {notifs.length === 0 && dms.length === 0 && (
        <div className="rounded-2xl bg-card p-8 flex flex-col items-center gap-3 text-center shadow-sm">
          <div className="w-14 h-14 rounded-full bg-secondary flex items-center justify-center text-2xl">🔔</div>
          <div>
            <p className="font-semibold text-sm">Tout est à jour</p>
            <p className="text-xs text-muted-foreground mt-0.5">Vos notifications apparaîtront ici.</p>
          </div>
        </div>
      )}

      {groups.map(grp => (
        <div key={grp.label} className="space-y-2">
          <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground px-1">{grp.label}</p>
          <div className="rounded-2xl bg-card shadow-sm overflow-hidden divide-y divide-border/50">
            {grp.items.map(n => {
              const k = nKind(n.kind);
              const isUrgent = n.kind === "tournament" && !n.read_at;
              return (
                <a key={n.id} href={n.link || "#"}
                  className={`flex gap-3 p-3.5 transition-colors hover:bg-accent/40 ${isUrgent ? "bg-amber-50/80 dark:bg-amber-950/20" : !n.read_at ? k.bg : ""}`}>
                  <div className={`w-9 h-9 rounded-xl flex items-center justify-center text-lg flex-shrink-0 ${!n.read_at ? k.bg + " border " + k.border : "bg-secondary"}`}>{k.emoji}</div>
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2">
                      <p className={`text-sm leading-snug ${!n.read_at ? "font-bold" : "font-medium"} line-clamp-2`}>{n.title}</p>
                      {!n.read_at && <span className={`mt-1.5 w-2 h-2 rounded-full flex-shrink-0 ${k.dot}`} />}
                    </div>
                    {n.body && <p className={`text-xs mt-0.5 line-clamp-2 ${!n.read_at ? "text-foreground" : "text-muted-foreground"}`}>{n.body}</p>}
                    <div className="flex items-center justify-between mt-1.5 gap-2">
                      <span className="text-[10px] text-muted-foreground">{nTimeAgo(n.created_at)}</span>
                      {isUrgent && <span className="text-[10px] bg-amber-500 text-white px-2 py-0.5 rounded-full font-bold">⚡ Rejoindre</span>}
                    </div>
                  </div>
                </a>
              );
            })}
          </div>
        </div>
      ))}

      {dms.length > 0 && (
        <div className="space-y-3">
          <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground px-1">Conversation avec l'équipe</p>
          <div className="rounded-2xl bg-card shadow-sm p-4 space-y-3">
            <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
              {dms.map(d => (
                <div key={d.id} className={`flex ${d.from_admin ? "justify-start" : "justify-end"}`}>
                  <div className="max-w-[80%]">
                    {d.from_admin && <p className="text-[10px] font-bold text-muted-foreground px-1">Équipe Lalao</p>}
                    <div className={`px-3.5 py-2.5 rounded-2xl text-sm ${d.from_admin ? "bg-secondary rounded-tl-sm" : "bg-primary text-primary-foreground rounded-tr-sm"}`}>{d.message}</div>
                    <p className="text-[10px] px-1 text-muted-foreground">{nTimeAgo(d.created_at)}</p>
                  </div>
                </div>
              ))}
            </div>
            <div className="flex gap-2 pt-1 border-t border-border/60">
              <input value={reply} onChange={e => setReply(e.target.value)} onKeyDown={e => e.key === "Enter" && !e.shiftKey && sendReply()}
                placeholder="Votre réponse…" className="flex-1 px-4 py-2.5 rounded-full bg-secondary border border-border outline-none text-sm focus:ring-2 focus:ring-primary/30" />
              <button onClick={sendReply} disabled={busy || !reply.trim()} className="p-2.5 rounded-full bg-primary text-primary-foreground disabled:opacity-50 active:scale-95 transition-transform shrink-0">
                <Send className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Main Profile Page
// ═══════════════════════════════════════════════════════════════════════════

function ProfilePage() {
  const { user, profile, refreshProfile, signOut } = useAuth();
  const navigate = useNavigate();
  const { t } = useT();
  const { theme, toggle: toggleTheme } = useTheme();
  const isDark = theme === "dark";
  const [tab, setTab] = useState<Tab>("apercu");
  const [pseudo, setPseudo] = useState(profile?.pseudo || "");
  const [uploading, setUploading] = useState(false);
  const [tx, setTx] = useState<any[]>([]);
  const [deps, setDeps] = useState<any[]>([]);
  const [withs, setWiths] = useState<any[]>([]);
  const [adminPhone, setAdminPhone] = useState("");
  const [referralEnabled, setReferralEnabled] = useState(true);
  const [playerStats, setPlayerStats] = useState<any>(null);
  const [gameStats, setGameStats] = useState<Record<string, { played: number; wins: number }>>({});
  const [biggestWin, setBiggestWin] = useState(0);
  const [myRank, setMyRank] = useState<number | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [achievements, setAchievements] = useState<any[]>([]);

  useEffect(() => { setPseudo(profile?.pseudo || ""); }, [profile?.pseudo]);

  useEffect(() => {
    if (!user) return;
    const uid = user.id;

    supabase.from("transactions").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(100).then(({ data }) => setTx(data || []));
    supabase.from("deposits").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setDeps(data || []));
    supabase.from("withdrawals").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setWiths(data || []));
    supabase.from("app_settings").select("admin_phone, referral_enabled").eq("id", 1).maybeSingle().then(({ data }) => {
      setAdminPhone((data?.admin_phone as string) || "");
      setReferralEnabled((data as any)?.referral_enabled !== false);
    });

    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => {
      if (data) setPlayerStats(data);
    });

    supabase.from("transactions").select("amount").eq("user_id", uid).eq("type", "win").order("amount", { ascending: false }).limit(1).then(({ data }) => {
      if (data && data[0]) setBiggestWin(Number(data[0].amount));
    });

    const fetchGameStats = async () => {
      const stats: Record<string, { played: number; wins: number }> = {
        ludo: { played: 0, wins: 0 }, domino: { played: 0, wins: 0 },
        fanorona: { played: 0, wins: 0 }, rami: { played: 0, wins: 0 }, chess: { played: 0, wins: 0 },
      };
      const [ludo, domino, fanorona, rami, chessW, chessB, ludoWin, dominoWin, fanoronaWin, ramiWin, chessWin] = await Promise.all([
        supabase.from("ludo_participants").select("id", { count: "exact", head: true }).eq("user_id", uid).eq("is_bot", false),
        supabase.from("domino_participants").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("fanorona_participants").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("rami_participants").select("id", { count: "exact", head: true }).eq("user_id", uid),
        supabase.from("chess_games").select("id", { count: "exact", head: true }).eq("white_id", uid),
        supabase.from("chess_games").select("id", { count: "exact", head: true }).eq("black_id", uid),
        supabase.from("ludo_games").select("id", { count: "exact", head: true }).eq("winner_id", uid),
        supabase.from("domino_games").select("id", { count: "exact", head: true }).eq("winner_id", uid),
        supabase.from("fanorona_games").select("id", { count: "exact", head: true }).eq("winner_id", uid),
        supabase.from("rami_games").select("id", { count: "exact", head: true }).eq("winner_id", uid),
        supabase.from("chess_games").select("id", { count: "exact", head: true }).eq("winner_id", uid),
      ]);
      stats.ludo.played = ludo.count || 0; stats.domino.played = domino.count || 0;
      stats.fanorona.played = fanorona.count || 0; stats.rami.played = rami.count || 0;
      stats.chess.played = (chessW.count || 0) + (chessB.count || 0);
      stats.ludo.wins = ludoWin.count || 0; stats.domino.wins = dominoWin.count || 0;
      stats.fanorona.wins = fanoronaWin.count || 0; stats.rami.wins = ramiWin.count || 0;
      stats.chess.wins = chessWin.count || 0;
      setGameStats(stats);
    };
    fetchGameStats();

    supabase.rpc("leaderboard_winners" as any, { _limit: 200 } as any).then(({ data }: any) => {
      if (!data) return;
      const idx = (data as any[]).findIndex((r: any) => r.id === uid || r.name === profile?.pseudo);
      if (idx >= 0) setMyRank((data[idx] as any).rank);
    });

    supabase.rpc("get_player_achievements" as any, { _uid: uid } as any).then(({ data }: any) => {
      setAchievements(data || []);
    });
  }, [user?.id]);

  const savePseudo = async () => {
    if (!pseudo.trim() || pseudo === profile?.pseudo) return;
    const { error } = await supabase.from("profiles").update({ pseudo: pseudo.trim() }).eq("id", user!.id);
    if (error) return toast.error(error.message);
    toast.success("Pseudo mis à jour"); refreshProfile();
  };

  const upload = async (rawFile: File) => {
    if (!user || !rawFile) return;
    setUploading(true);
    const f = await compressImageToWebp(rawFile, { maxDim: 512 });
    const ext = f.name.split(".").pop();
    const path = `${user.id}/avatar.${ext}`;
    const { error: upErr } = await supabase.storage.from("avatars").upload(path, f, { upsert: true, contentType: f.type });
    if (upErr) { setUploading(false); return toast.error(upErr.message); }
    const { data: { publicUrl } } = supabase.storage.from("avatars").getPublicUrl(path);
    const url = `${publicUrl}?t=${Date.now()}`;
    const { error } = await supabase.from("profiles").update({ avatar_url: url }).eq("id", user.id);
    setUploading(false);
    if (error) return toast.error(error.message);
    toast.success("Photo mise à jour"); refreshProfile();
  };

  if (!profile) return <main className="p-8 text-center text-muted-foreground">Chargement…</main>;

  const p: any = profile;
  const ps: any = playerStats || {};
  const initials = (profile.pseudo || "?").slice(0, 2).toUpperCase();
  const totalWins = ps.total_wins ?? 0;
  const totalGames = ps.total_games ?? 0;
  const level = ps.player_level ?? 1;
  const streak = ps.daily_streak ?? 0;
  const winRate = totalGames > 0 ? Math.round((totalWins / totalGames) * 100) : 0;
  const totalGained = tx.filter(t => Number(t.amount) > 0).reduce((s, t) => s + Number(t.amount), 0);
  const totalLost = Math.abs(tx.filter(t => Number(t.amount) < 0).reduce((s, t) => s + Number(t.amount), 0));
  const memberDays = Math.floor((Date.now() - new Date((profile as any).created_at || Date.now()).getTime()) / 86400000);

  return (
    <main className="max-w-2xl mx-auto px-4 py-5 space-y-5 pb-20">
      {/* ═══ Hero Card ═══ */}
      <div className="relative rounded-3xl overflow-hidden shadow-lg">
        <div className="absolute inset-0 bg-gradient-to-br from-primary/90 via-primary to-orange-600" />
        <div className="absolute inset-0 opacity-20" style={{ background: "radial-gradient(circle at 30% 50%, white 0%, transparent 60%)" }} />

        <div className="relative p-5 pt-6 space-y-4 text-white">
          {/* Avatar + name + balance */}
          <div className="flex items-center gap-4">
            <div className="relative shrink-0">
              <div className="w-16 h-16 rounded-2xl bg-white/20 backdrop-blur-sm ring-2 ring-white/30 flex items-center justify-center text-2xl font-black overflow-hidden">
                {profile.avatar_url
                  ? <img src={profile.avatar_url} alt={`Avatar de ${profile.pseudo}`} className="w-full h-full object-cover" />
                  : <span>{initials}</span>}
              </div>
              <button onClick={() => fileRef.current?.click()} disabled={uploading}
                aria-label="Changer la photo"
                className="absolute -bottom-1 -right-1 p-1.5 rounded-full bg-white text-primary shadow-md ring-2 ring-white/0 hover:scale-105 transition-transform">
                <Camera className="w-3.5 h-3.5" strokeWidth={2.2} />
              </button>
              <input ref={fileRef} type="file" accept="image/*" hidden onChange={e => e.target.files?.[0] && upload(e.target.files[0])} />
            </div>

            <div className="flex-1 min-w-0">
              <div className="flex items-center gap-2">
                <h1 className="text-lg font-black truncate leading-tight">{profile.pseudo}</h1>
                {p.phone_verified && <ShieldCheck className="w-4 h-4 shrink-0" strokeWidth={2.5} />}
              </div>
              <div className="flex items-center gap-2 mt-1 text-xs text-white/80">
                {myRank && <span className="font-bold">Rang #{myRank}</span>}
                {myRank && <span className="opacity-50">·</span>}
                <span>{levelTitle(level)}</span>
                {streak > 0 && <><span className="opacity-50">·</span><span className="font-bold">{streak}j 🔥</span></>}
              </div>
            </div>

            <div className="text-right shrink-0">
              <div className="flex items-center gap-2 justify-end">
                <button
                  onClick={toggleTheme}
                  aria-label={isDark ? "Mode clair" : "Mode sombre"}
                  className="p-1.5 rounded-lg bg-white/20 hover:bg-white/30 transition-colors text-white"
                >
                  {isDark ? <Sun className="w-3.5 h-3.5" /> : <Moon className="w-3.5 h-3.5" />}
                </button>
                <div>
                  <div className="text-xl font-black tabular-nums leading-none">{Math.round(profile.balance_ar).toLocaleString("fr-FR")}</div>
                  <div className="text-[10px] text-white/70 uppercase tracking-wider mt-1">Ariary</div>
                </div>
              </div>
            </div>
          </div>

          {/* XP bar */}
          <XPBar level={level} wins={totalWins} />

          {/* Code parrainage */}
          {profile.unique_code && (
            <button onClick={() => { copyText(profile.unique_code!).then(ok => toast[ok ? "success" : "error"](ok ? "Code copié !" : "Erreur")); }}
              className="flex items-center gap-1.5 text-xs text-white/70 hover:text-white transition-colors">
              <Copy className="w-3 h-3" /> Code: <span className="font-mono font-bold text-white/90">{profile.unique_code}</span>
            </button>
          )}
        </div>
      </div>

      {/* ═══ Quick Stats Bar ═══ */}
      <div className="grid grid-cols-4 gap-2">
        {[
          { label: "Parties", value: totalGames, color: "" },
          { label: "Victoires", value: totalWins, color: "text-emerald-500" },
          { label: "Win rate", value: `${winRate}%`, color: "text-primary" },
          { label: "Série", value: `${streak}j`, color: "text-amber-500" },
        ].map(s => (
          <div key={s.label} className="rounded-2xl bg-card p-3 text-center shadow-sm">
            <div className={`text-lg font-black tabular-nums leading-none ${s.color}`}>{s.value}</div>
            <div className="text-[10px] text-muted-foreground mt-1 uppercase tracking-wide">{s.label}</div>
          </div>
        ))}
      </div>

      {/* ═══ Tab Bar ═══ */}
      <div className="flex gap-1 bg-card border border-border rounded-2xl p-1 shadow-sm">
        {TABS.map(tb => (
          <button key={tb.id} onClick={() => setTab(tb.id)}
            className={`flex-1 flex items-center justify-center gap-1.5 px-2 py-2 rounded-xl text-xs font-bold transition-all ${tab === tb.id ? "bg-primary text-primary-foreground shadow-sm" : "text-muted-foreground hover:text-foreground hover:bg-secondary"}`}>
            {tb.icon}{tb.label}
          </button>
        ))}
      </div>

      {/* ═══ Tab: Aperçu ═══ */}
      {tab === "apercu" && (
        <div className="space-y-4">
          {/* Highlights */}
          <div className="rounded-2xl bg-card p-4 shadow-sm space-y-0">
            <div className="flex items-center justify-between py-2.5 border-b border-border/40">
              <span className="text-sm text-muted-foreground">Membre depuis</span>
              <span className="text-sm font-semibold">{memberDays} jours</span>
            </div>
            <div className="flex items-center justify-between py-2.5 border-b border-border/40">
              <span className="text-sm text-muted-foreground">Plus gros gain</span>
              <span className="text-sm font-bold text-emerald-600">{Math.round(biggestWin).toLocaleString("fr-FR")} Ar</span>
            </div>
            <div className="flex items-center justify-between py-2.5 border-b border-border/40">
              <span className="text-sm text-muted-foreground">Jeu préféré</span>
              <span className="text-sm font-bold">{preferredGame(gameStats)}</span>
            </div>
            <div className="flex items-center justify-between py-2.5">
              <span className="text-sm text-muted-foreground">Total reçu</span>
              <span className="text-sm font-bold text-emerald-600">{Math.round(totalGained).toLocaleString("fr-FR")} Ar</span>
            </div>
          </div>

          {/* Achievements */}
          {achievements.length > 0 && (
            <div className="rounded-2xl bg-card p-4 shadow-sm">
              <div className="flex items-center gap-2 mb-3">
                <Trophy className="w-4 h-4 text-amber-500" />
                <span className="font-bold text-xs uppercase tracking-widest text-muted-foreground">Trophées</span>
              </div>
              <div className="flex flex-wrap gap-2">
                {achievements.map((a: any, i: number) => (
                  <div key={i} className="flex items-center gap-2 rounded-xl bg-amber-50 dark:bg-amber-950/20 px-3 py-2 border border-amber-200 dark:border-amber-800">
                    <span className="text-lg">{a.emoji || a.icon || "🏆"}</span>
                    <div>
                      <div className="text-xs font-bold">{a.name || a.title || "Trophée"}</div>
                      {a.description && <div className="text-[10px] text-muted-foreground">{a.description}</div>}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Parrainage */}
          {referralEnabled && (
            <Link to="/parrainage"
              className="rounded-2xl bg-gradient-to-r from-primary/10 to-violet-500/5 border border-primary/20 p-4 shadow-sm flex items-center justify-between gap-3 hover:bg-primary/5 transition-colors">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center text-xl">🤝</div>
                <div>
                  <div className="font-bold text-sm">Parrainage</div>
                  <div className="text-xs text-muted-foreground">Invitez des amis, gagnez des commissions</div>
                </div>
              </div>
              <ChevronRight className="w-5 h-5 text-muted-foreground shrink-0" />
            </Link>
          )}
        </div>
      )}

      {/* ═══ Tab: Stats ═══ */}
      {tab === "stats" && (
        <div className="space-y-4">
          {/* Financial summary */}
          <div className="rounded-2xl bg-card p-4 shadow-sm">
            <div className="font-bold text-xs uppercase tracking-widest text-muted-foreground mb-3 flex items-center gap-2">
              <Coins className="w-4 h-4 text-primary" /> Finances
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="rounded-xl bg-secondary/60 p-3">
                <div className="text-xs text-muted-foreground">Solde</div>
                <div className="text-lg font-black text-primary tabular-nums">{Math.round(profile.balance_ar).toLocaleString("fr-FR")} Ar</div>
              </div>
              <div className="rounded-xl bg-secondary/60 p-3">
                <div className="text-xs text-muted-foreground">Plus gros gain</div>
                <div className="text-lg font-black text-emerald-600 tabular-nums">{Math.round(biggestWin).toLocaleString("fr-FR")} Ar</div>
              </div>
              <div className="rounded-xl bg-secondary/60 p-3">
                <div className="text-xs text-muted-foreground">Total reçu</div>
                <div className="text-lg font-black text-emerald-600 tabular-nums">{Math.round(totalGained).toLocaleString("fr-FR")} Ar</div>
              </div>
              <div className="rounded-xl bg-secondary/60 p-3">
                <div className="text-xs text-muted-foreground">Total dépensé</div>
                <div className="text-lg font-black text-destructive tabular-nums">{Math.round(totalLost).toLocaleString("fr-FR")} Ar</div>
              </div>
            </div>
          </div>

          {/* Game stats */}
          <div className="rounded-2xl bg-card p-4 shadow-sm">
            <div className="font-bold text-xs uppercase tracking-widest text-muted-foreground mb-2 flex items-center gap-2">
              <Gamepad2 className="w-4 h-4 text-primary" /> Statistiques par jeu
            </div>
            <div className="divide-y divide-border/40">
              <GameStatsRow game="Ludo" icon="🎲" played={gameStats.ludo?.played || 0} wins={gameStats.ludo?.wins || 0} />
              <GameStatsRow game="Domino" icon="🁣" played={gameStats.domino?.played || 0} wins={gameStats.domino?.wins || 0} />
              <GameStatsRow game="Fanorona" icon="♟" played={gameStats.fanorona?.played || 0} wins={gameStats.fanorona?.wins || 0} />
              <GameStatsRow game="Rami" icon="🃏" played={gameStats.rami?.played || 0} wins={gameStats.rami?.wins || 0} />
              <GameStatsRow game="Échecs" icon="♜" played={gameStats.chess?.played || 0} wins={gameStats.chess?.wins || 0} />
            </div>
          </div>

          {/* Level progression */}
          <div className="rounded-2xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-xs uppercase tracking-widest text-muted-foreground mb-1">Progression</div>
            <XPBar level={level} wins={totalWins} />
            <div className="space-y-1.5 mt-2">
              {[1, 2, 3, 4, 5].map(l => (
                <div key={l} className={`flex items-center gap-3 px-3 py-2 rounded-xl ${l === level ? "bg-primary/10 border border-primary/30" : l < level ? "opacity-60" : "opacity-30"}`}>
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-extrabold ${l <= level ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>{l}</div>
                  <div className="flex-1">
                    <div className="text-sm font-semibold">{levelTitle(l)}</div>
                    <div className="text-[10px] text-muted-foreground">{xpForLevel(l)} victoires requises</div>
                  </div>
                  {l < level && <span className="text-[10px] text-emerald-600 font-bold">✓</span>}
                  {l === level && <span className="text-[10px] text-primary font-bold">En cours</span>}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}

      {/* ═══ Tab: Activité ═══ */}
      {tab === "activite" && (
        <div className="space-y-4">
          <Section title="Transactions récentes">
            {tx.length === 0 ? <Empty /> : tx.slice(0, 30).map(txItem => (
              <div key={txItem.id} className="flex items-center justify-between py-2.5 border-b border-border/40 last:border-0">
                <div className="min-w-0">
                  <div className="font-semibold text-sm">{labelType(txItem.type, t)}</div>
                  {txItem.note && <div className="text-xs text-muted-foreground truncate max-w-[200px]">{txItem.note}</div>}
                  <div className="text-[10px] text-muted-foreground">{new Date(txItem.created_at).toLocaleString("fr-FR")}</div>
                </div>
                <div className={`font-bold text-sm shrink-0 ${Number(txItem.amount) >= 0 ? "text-emerald-600" : "text-destructive"}`}>
                  {Number(txItem.amount) >= 0 ? "+" : ""}{Math.round(Number(txItem.amount)).toLocaleString("fr-FR")} Ar
                </div>
              </div>
            ))}
          </Section>

          <Section title={t("my_deposits_section")}>
            {deps.length === 0 ? <Empty /> : deps.slice(0, 20).map(d => <FinRow key={d.id} left={`${d.method} · ${d.reference}`} status={d.status} amount={d.amount} date={d.created_at} />)}
          </Section>

          <Section title={t("my_withdrawals_section")}>
            {withs.length === 0 ? <Empty /> : withs.slice(0, 20).map(w => <FinRow key={w.id} left={`${w.method} · ${w.user_phone}`} status={w.status} amount={-w.amount} date={w.created_at} />)}
          </Section>
        </div>
      )}

      {/* ═══ Tab: Compte ═══ */}
      {tab === "compte" && (
        <div className="space-y-4">
          {/* Edit profile */}
          <div className="rounded-2xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-xs uppercase tracking-widest text-muted-foreground">Profil</div>
            <div className="flex gap-2">
              <input value={pseudo} onChange={e => setPseudo(e.target.value)} className="flex-1 px-4 py-2.5 rounded-xl bg-secondary border border-border outline-none text-sm focus:ring-2 focus:ring-primary/30" placeholder="Pseudo" />
              <button onClick={savePseudo} className="px-5 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-sm">OK</button>
            </div>
            <button onClick={() => fileRef.current?.click()} disabled={uploading}
              className="flex items-center gap-2 px-4 py-2.5 rounded-xl bg-secondary font-semibold text-sm w-full justify-center">
              <Camera className="w-4 h-4" /> {uploading ? "Upload…" : "Changer la photo"}
            </button>
          </div>

          {/* Phone verification */}
          <PhoneVerification adminPhone={adminPhone} />

          {/* FAQ link */}
          <Link to="/faq"
            className="rounded-2xl bg-card p-4 shadow-sm flex items-center justify-between hover:bg-accent/40 transition-colors">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-xl bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-lg">❓</div>
              <div>
                <div className="font-semibold text-sm">Centre d'aide / FAQ</div>
                <div className="text-xs text-muted-foreground">Paiements, jeux, compte…</div>
              </div>
            </div>
            <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
          </Link>

          {/* Theme toggle */}
          <ThemeToggle />

          {/* Security */}
          <div className="rounded-2xl bg-card p-4 shadow-sm space-y-2">
            <div className="font-bold text-xs uppercase tracking-widest text-muted-foreground mb-1">Sécurité</div>
            <button onClick={async () => { await signOut(); navigate({ to: "/login" }); }}
              className="w-full py-2.5 rounded-xl bg-secondary font-semibold flex items-center justify-center gap-2 text-sm hover:bg-accent transition-colors">
              <LogOut className="w-4 h-4" /> {t("logout")}
            </button>
            <button onClick={() => setShowDeleteDialog(true)}
              className="w-full py-2.5 rounded-xl bg-destructive/10 text-destructive font-semibold flex items-center justify-center gap-2 text-sm border border-destructive/20 hover:bg-destructive/20 transition-colors">
              <Trash2 className="w-4 h-4" /> {t("delete_account_btn")}
            </button>
          </div>
        </div>
      )}

      <DeleteAccountDialog open={showDeleteDialog} onClose={() => setShowDeleteDialog(false)} />
    </main>
  );
}
