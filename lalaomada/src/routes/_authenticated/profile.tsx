import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { copyText } from "@/lib/clipboard";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  Camera, Copy, Coins, ShieldCheck, ShieldAlert, LogOut, Trash2,
  Phone, Trophy, Gamepad2, Activity, User, Star, Zap, Flame,
  TrendingUp, Award, BarChart3, Calendar, Lock, ChevronRight,
  HelpCircle, Bug, Send, MessageSquare, Bot,
  Bell, CheckCheck, ArrowDownLeft, ArrowUpRight, Gift, Megaphone, AlertCircle,
} from "lucide-react";
import { DeleteAccountDialog } from "@/components/DeleteAccountDialog";
import { compressImageToWebp } from "@/lib/image-compress";

export const Route = createFileRoute("/_authenticated/profile")({
  component: ProfilePage,
  head: () => ({ meta: [
    { title: "Mon profil — Lalao MADA" },
    { name: "description", content: "Profil joueur Lalao MADA : statistiques, jeux, classement et historique." },
  ] }),
});

const TABS = [
  { id: "apercu",   label: "Aperçu",   icon: <User className="w-4 h-4" /> },
  { id: "stats",    label: "Stats",    icon: <BarChart3 className="w-4 h-4" /> },
  { id: "jeux",     label: "Jeux",     icon: <Gamepad2 className="w-4 h-4" /> },
  { id: "activite", label: "Activité", icon: <Activity className="w-4 h-4" /> },
  { id: "compte",   label: "Compte",   icon: <Star className="w-4 h-4" /> },
  { id: "notifs",   label: "Notifs",   icon: <Bell className="w-4 h-4" /> },
  { id: "aide",     label: "Aide",     icon: <HelpCircle className="w-4 h-4" /> },
] as const;

type Tab = typeof TABS[number]["id"];

function XPBar({ level, wins }: { level: number; wins: number }) {
  const xpForLevel = (l: number) => l * l * 10;
  const currentXP = wins;
  const needed = xpForLevel(level);
  const prev = xpForLevel(level - 1);
  const pct = Math.min(100, Math.round(((currentXP - prev) / Math.max(1, needed - prev)) * 100));
  const [w, setW] = useState(0);
  useEffect(() => { const id = requestAnimationFrame(() => setW(pct)); return () => cancelAnimationFrame(id); }, [pct]);
  return (
    <div className="space-y-1">
      <div className="flex justify-between text-[10px] font-semibold">
        <span className="text-muted-foreground">Niv. {level}</span>
        <span className="text-muted-foreground tabular-nums">{currentXP}/{needed} XP</span>
      </div>
      <div className="h-1.5 rounded-full bg-white/5 overflow-hidden relative">
        <div className="h-full rounded-full bg-gradient-to-r from-primary via-violet-500 to-fuchsia-500 transition-[width] duration-1000 ease-out relative overflow-hidden" style={{ width: `${w}%` }}>
          <div className="absolute inset-0 opacity-40 animate-pulse bg-gradient-to-r from-transparent via-white/60 to-transparent" />
        </div>
      </div>
      <div className="text-right text-[9px] text-muted-foreground tabular-nums">{Math.max(0, needed - currentXP)} XP → Niv. {level + 1}</div>
    </div>
  );
}

function Sparkline({ data, className = "" }: { data: number[]; className?: string }) {
  const max = Math.max(1, ...data);
  const pts = data.map((v, i) => `${(i / Math.max(1, data.length - 1)) * 100},${30 - (v / max) * 26 - 2}`).join(" ");
  const area = `0,30 ${pts} 100,30`;
  return (
    <svg viewBox="0 0 100 30" preserveAspectRatio="none" className={className}>
      <defs>
        <linearGradient id="spark-fill" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor="hsl(var(--primary))" stopOpacity="0.35" />
          <stop offset="100%" stopColor="hsl(var(--primary))" stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={area} fill="url(#spark-fill)" />
      <polyline points={pts} fill="none" stroke="hsl(var(--primary))" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" vectorEffect="non-scaling-stroke" />
    </svg>
  );
}

function StatCard({ label, value, sub, color = "text-foreground" }: { label: string; value: string | number; sub?: string; color?: string }) {
  return (
    <div className="rounded-2xl bg-secondary/60 p-3 space-y-0.5">
      <div className="text-xs text-muted-foreground">{label}</div>
      <div className={`text-xl font-extrabold ${color}`}>{value}</div>
      {sub && <div className="text-[10px] text-muted-foreground">{sub}</div>}
    </div>
  );
}

function GameStatsCard({ game, icon, played, wins }: { game: string; icon: string; played: number; wins: number }) {
  const rate = played > 0 ? Math.round((wins / played) * 100) : 0;
  const losses = played - wins;
  return (
    <div className="rounded-2xl border border-border/60 p-4 space-y-3">
      <div className="flex items-center gap-2 font-bold">
        <span className="text-xl">{icon}</span> {game}
      </div>
      <div className="grid grid-cols-3 gap-2 text-center">
        <div><div className="text-lg font-extrabold">{played}</div><div className="text-[10px] text-muted-foreground">Parties</div></div>
        <div><div className="text-lg font-extrabold text-emerald-600">{wins}</div><div className="text-[10px] text-muted-foreground">Victoires</div></div>
        <div><div className="text-lg font-extrabold text-destructive">{losses}</div><div className="text-[10px] text-muted-foreground">Défaites</div></div>
      </div>
      <div className="space-y-1">
        <div className="flex justify-between text-xs"><span className="text-muted-foreground">Taux de victoire</span><span className="font-bold">{rate}%</span></div>
        <div className="h-1.5 rounded-full bg-secondary overflow-hidden">
          <div className="h-full rounded-full bg-emerald-500 transition-all" style={{ width: `${rate}%` }} />
        </div>
      </div>
    </div>
  );
}

function MiniStat({ icon, label, value, color = "text-foreground" }: { icon: string; label: string; value: string | number; color?: string }) {
  return (
    <div className="rounded-xl bg-secondary/50 border border-white/5 px-2 py-1.5 flex items-center gap-2">
      <span className="text-base shrink-0">{icon}</span>
      <div className="min-w-0 flex-1">
        <div className="text-[9px] text-muted-foreground uppercase tracking-wide truncate">{label}</div>
        <div className={`text-xs font-extrabold truncate ${color}`}>{value}</div>
      </div>
    </div>
  );
}

function InfoLine({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between border-b border-border/30 last:border-0 py-1">
      <span className="text-muted-foreground text-[11px]">{label}</span>
      <span className="font-semibold text-[11px] truncate ml-2">{value}</span>
    </div>
  );
}

function ProfilePage() {
  const { user, profile, refreshProfile, signOut } = useAuth();
  const navigate = useNavigate();
  const { t } = useT();
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

    // Financial history
    supabase.from("transactions").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(100).then(({ data }) => setTx(data || []));
    supabase.from("deposits").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setDeps(data || []));
    supabase.from("withdrawals").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setWiths(data || []));
    supabase.from("app_settings").select("admin_phone, referral_enabled").eq("id", 1).maybeSingle().then(({ data }) => {
      setAdminPhone((data?.admin_phone as string) || "");
      setReferralEnabled((data as any)?.referral_enabled !== false);
    });

    // Player stats from view
    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => {
      if (data) setPlayerStats(data);
    });

    // Biggest win
    supabase.from("transactions").select("amount").eq("user_id", uid).eq("type", "win").order("amount", { ascending: false }).limit(1).then(({ data }) => {
      if (data && data[0]) setBiggestWin(Number(data[0].amount));
    });

    // Per-game stats (played)
    const fetchGameStats = async () => {
      const stats: Record<string, { played: number; wins: number }> = {
        ludo: { played: 0, wins: 0 },
        domino: { played: 0, wins: 0 },
        fanorona: { played: 0, wins: 0 },
        rami: { played: 0, wins: 0 },
        chess: { played: 0, wins: 0 },
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

      stats.ludo.played = ludo.count || 0;
      stats.domino.played = domino.count || 0;
      stats.fanorona.played = fanorona.count || 0;
      stats.rami.played = rami.count || 0;
      stats.chess.played = (chessW.count || 0) + (chessB.count || 0);
      stats.ludo.wins = ludoWin.count || 0;
      stats.domino.wins = dominoWin.count || 0;
      stats.fanorona.wins = fanoronaWin.count || 0;
      stats.rami.wins = ramiWin.count || 0;
      stats.chess.wins = chessWin.count || 0;
      setGameStats(stats);
    };
    fetchGameStats();

    // My rank from leaderboard
    supabase.rpc("leaderboard_winners" as any, { _limit: 200 } as any).then(({ data }: any) => {
      if (!data) return;
      const idx = (data as any[]).findIndex((r: any) => r.id === uid || r.name === profile?.pseudo);
      if (idx >= 0) setMyRank((data[idx] as any).rank);
    });

    // Achievements
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


  if (!profile) return <main className="p-8 text-center">Chargement…</main>;

  const p: any = profile;
  const ps: any = playerStats || {};
  const initials = (profile.pseudo || "?").slice(0, 2).toUpperCase();
  const totalWins = ps.total_wins ?? 0;
  const totalGames = ps.total_games ?? 0;
  const level = ps.player_level ?? 1;
  const streak = ps.daily_streak ?? 0;
  const winRate = totalGames > 0 ? Math.round((totalWins / totalGames) * 100) : 0;
  const totalLosses = totalGames - totalWins;
  const totalGained = tx.filter(t => Number(t.amount) > 0).reduce((s, t) => s + Number(t.amount), 0);
  const totalLost = Math.abs(tx.filter(t => Number(t.amount) < 0).reduce((s, t) => s + Number(t.amount), 0));
  const memberDays = Math.floor((Date.now() - new Date((profile as any).created_at || Date.now()).getTime()) / 86400000);

  // 7-day wins sparkline
  const now = Date.now();
  const winsPerDay = Array.from({ length: 7 }, (_, i) => {
    const dayStart = now - (6 - i) * 86400000;
    return tx.filter((t: any) => t.type === "win" && new Date(t.created_at).getTime() >= dayStart && new Date(t.created_at).getTime() < dayStart + 86400000).length;
  });
  const wins7d = winsPerDay.reduce((a, b) => a + b, 0);

  // Achievements catalogue for locked slots
  const ACHIEVEMENT_SLOTS = 8;
  const unlockedKeys = new Set(achievements.map((a: any) => a.key));
  const lockedCount = Math.max(0, ACHIEVEMENT_SLOTS - achievements.length);

  return (
    <main className="max-w-2xl mx-auto px-3 py-3 space-y-3 pb-20">
      {/* ── Hero Card ── */}
      <div className="rounded-2xl border border-white/8 bg-card p-3.5 shadow-sm relative overflow-hidden">
        <div className="absolute inset-x-0 top-0 h-20 pointer-events-none opacity-70" style={{ background:"linear-gradient(180deg, hsl(var(--primary)/0.10) 0%, transparent 100%)" }} />

        <div className="relative flex items-center gap-3">
          <div className="relative shrink-0">
            <div className="relative w-14 h-14 rounded-2xl p-[1.5px] bg-gradient-to-br from-primary/60 to-violet-500/60">
              <div className="w-full h-full rounded-[14px] bg-card flex items-center justify-center text-base font-extrabold overflow-hidden">
                {profile.avatar_url
                  ? <img src={profile.avatar_url} alt={`Avatar de ${profile.pseudo}`} className="w-full h-full object-cover rounded-[14px]" />
                  : <span className="text-primary">{initials}</span>}
              </div>
            </div>
            <div className="absolute -bottom-1 -left-1 min-w-[20px] h-5 px-1 rounded-full bg-amber-500 flex items-center justify-center text-[10px] font-black text-amber-950 ring-2 ring-card tabular-nums">
              {level}
            </div>
            <button onClick={() => fileRef.current?.click()} disabled={uploading}
              aria-label="Changer la photo"
              className="absolute -bottom-1 -right-1 p-1 rounded-full bg-primary text-primary-foreground ring-2 ring-card">
              <Camera className="w-3 h-3" strokeWidth={2} />
            </button>
            <input ref={fileRef} type="file" accept="image/*" hidden onChange={e => e.target.files?.[0] && upload(e.target.files[0])} />
          </div>

          <div className="flex-1 min-w-0">
            <div className="flex items-center gap-1.5">
              <h1 className="text-base font-black truncate leading-tight tracking-tight">{profile.pseudo}</h1>
              {p.phone_verified && <ShieldCheck className="w-3.5 h-3.5 text-emerald-500 shrink-0" strokeWidth={2.2} />}
            </div>
            <div className="flex items-center gap-1.5 mt-1 text-[11px] text-muted-foreground">
              {myRank && <span className="font-semibold text-violet-400">#{myRank}</span>}
              {myRank && <span className="opacity-40">·</span>}
              {profile.unique_code && (
                <button onClick={() => { copyText(profile.unique_code!).then(ok => toast[ok ? "success" : "error"](ok ? "Copié !" : "Erreur")); }}
                  className="font-mono hover:text-foreground transition-colors inline-flex items-center gap-0.5">
                  #{profile.unique_code}<Copy className="w-2.5 h-2.5" strokeWidth={1.8} />
                </button>
              )}
            </div>
          </div>

          <div className="text-right shrink-0">
            <div className="flex items-center gap-1 text-base font-black text-primary justify-end leading-none tabular-nums">
              <Coins className="w-4 h-4" strokeWidth={2} />{Math.round(profile.balance_ar).toLocaleString("fr-FR")}
            </div>
            <div className="text-[9px] text-muted-foreground mt-1 uppercase tracking-widest">Ariary</div>
          </div>
        </div>

        <div className="mt-3">
          <XPBar level={level} wins={totalWins} />
        </div>
      </div>

      {/* ── Quick stats (3 col plate) ── */}
      <div className="grid grid-cols-3 rounded-2xl border border-white/8 bg-card divide-x divide-white/5 overflow-hidden">
        <div className="py-2.5 text-center">
          <div className="text-base font-black text-emerald-500 leading-none tabular-nums">{totalWins}</div>
          <div className="text-[9px] text-muted-foreground mt-1 uppercase tracking-wider">Victoires</div>
        </div>
        <div className="py-2.5 text-center">
          <div className="text-base font-black leading-none tabular-nums">{totalGames}</div>
          <div className="text-[9px] text-muted-foreground mt-1 uppercase tracking-wider">Parties</div>
        </div>
        <div className="py-2.5 text-center">
          <div className="text-base font-black text-primary leading-none tabular-nums">{winRate}%</div>
          <div className="text-[9px] text-muted-foreground mt-1 uppercase tracking-wider">Win rate</div>
        </div>
      </div>

      {/* ── Tabs ── */}
      <div className="flex gap-0.5 bg-card/80 border border-white/8 rounded-xl p-0.5 overflow-x-auto shadow-sm scrollbar-hide">
        {TABS.map(tb => (
          <button key={tb.id} onClick={() => setTab(tb.id)}
            className={`flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-[11px] font-bold whitespace-nowrap transition-all ${tab === tb.id ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground"}`}>
            {tb.icon}{tb.label}
          </button>
        ))}
      </div>

      {/* ── Tab: Aperçu ── */}
      {tab === "apercu" && (
        <div className="space-y-3">
          {/* Info + highlights fusionnés */}
          <div className="rounded-2xl bg-card border border-white/8 divide-y divide-white/5">
            <div className="p-3 grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs">
              <InfoLine label="Membre" value={`${memberDays}j`} />
              <InfoLine label="Série" value={<span className="font-bold text-amber-500">{streak}j 🔥</span>} />
              <InfoLine label="Plus gros gain" value={<span className="font-bold text-emerald-500">{Math.round(biggestWin).toLocaleString("fr-FR")} Ar</span>} />
              <InfoLine label="Jeu préféré" value={<span className="font-bold text-violet-400">{preferredGame(gameStats)}</span>} />
            </div>
          </div>

          {/* Trophées — simple grid */}
          {(achievements.length > 0 || lockedCount > 0) && (
            <div className="rounded-2xl bg-card p-3 border border-white/8">
              <div className="flex items-center justify-between mb-2">
                <div className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground flex items-center gap-1.5">
                  <Trophy className="w-3 h-3 text-amber-500" strokeWidth={1.8} />Trophées
                </div>
                <span className="text-[9px] text-muted-foreground tabular-nums">{achievements.length}/{ACHIEVEMENT_SLOTS}</span>
              </div>
              <div className="grid grid-cols-8 gap-1.5">
                {achievements.map((ach: any) => (
                  <div key={ach.key} title={ach.label}
                    className="aspect-square rounded-lg bg-amber-500/10 border border-amber-500/25 flex items-center justify-center text-base">
                    {ach.icon}
                  </div>
                ))}
                {Array.from({ length: lockedCount }).map((_, i) => (
                  <div key={`locked-${i}`} title="À débloquer"
                    className="aspect-square rounded-lg border border-dashed border-white/10 bg-white/[0.02] flex items-center justify-center">
                    <Lock className="w-3 h-3 text-muted-foreground/40" strokeWidth={1.5} />
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      )}



      {/* ── Tab: Stats ── */}
      {tab === "stats" && (
        <div className="space-y-4">
          <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-sm flex items-center gap-2"><BarChart3 className="w-4 h-4 text-primary" />Statistiques globales</div>
            <div className="grid grid-cols-2 gap-3">
              <StatCard label="Parties jouées" value={totalGames} />
              <StatCard label="Victoires" value={totalWins} color="text-emerald-600" />
              <StatCard label="Défaites" value={totalLosses} color="text-destructive" />
              <StatCard label="Taux de victoire" value={`${winRate}%`} color={winRate >= 50 ? "text-emerald-600" : "text-amber-600"} />
              <StatCard label="Série de connexion" value={`${streak} jours`} sub="Bonus quotidien" color="text-amber-600" />
              <StatCard label="Niveau actuel" value={level} sub="Basé sur les victoires" color="text-primary" />
            </div>
          </div>

          <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-sm flex items-center gap-2"><Coins className="w-4 h-4 text-primary" />Finances</div>
            <div className="grid grid-cols-2 gap-3">
              <StatCard label="Solde actuel" value={`${Math.round(profile.balance_ar).toLocaleString("fr-FR")} Ar`} color="text-primary" />
              <StatCard label="Plus gros gain" value={`${Math.round(biggestWin).toLocaleString("fr-FR")} Ar`} color="text-emerald-600" />
              <StatCard label="Total reçu" value={`${Math.round(totalGained).toLocaleString("fr-FR")} Ar`} color="text-emerald-600" />
              <StatCard label="Total dépensé" value={`${Math.round(totalLost).toLocaleString("fr-FR")} Ar`} color="text-destructive" />
            </div>
          </div>

          <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-sm flex items-center gap-2"><TrendingUp className="w-4 h-4 text-primary" />Progression</div>
            <XPBar level={level} wins={totalWins} />
            <div className="mt-3 space-y-2">
              {[1,2,3,4,5].map(l => (
                <div key={l} className={`flex items-center gap-3 px-3 py-2 rounded-xl ${l === level ? "bg-primary/10 border border-primary/30" : l < level ? "opacity-50" : "opacity-30"}`}>
                  <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-extrabold ${l <= level ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>{l}</div>
                  <div className="flex-1">
                    <div className="text-xs font-bold">{levelTitle(l)}</div>
                    <div className="text-[10px] text-muted-foreground">{l * l * 10} victoires</div>
                  </div>
                  {l < level && <span className="text-[10px] text-emerald-600 font-bold">✅ Atteint</span>}
                  {l === level && <span className="text-[10px] text-primary font-bold">En cours</span>}
                </div>
              ))}
            </div>
          </div>
        </div>
      )}


      {/* ── Tab: Jeux ── */}
      {tab === "jeux" && (
        <div className="space-y-3">
          <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-sm flex items-center gap-2"><Gamepad2 className="w-4 h-4 text-primary" />Statistiques par jeu</div>
            <GameStatsCard game="Ludo" icon="🎲" played={gameStats.ludo?.played || 0} wins={gameStats.ludo?.wins || 0} />
            <GameStatsCard game="Domino" icon="🁣" played={gameStats.domino?.played || 0} wins={gameStats.domino?.wins || 0} />
            <GameStatsCard game="Fanorona" icon="♟" played={gameStats.fanorona?.played || 0} wins={gameStats.fanorona?.wins || 0} />
            <GameStatsCard game="Rami" icon="🃏" played={gameStats.rami?.played || 0} wins={gameStats.rami?.wins || 0} />
            <GameStatsCard game="Échecs" icon="♜" played={gameStats.chess?.played || 0} wins={gameStats.chess?.wins || 0} />
          </div>
        </div>
      )}

      {/* ── Tab: Activité ── */}
      {tab === "activite" && (
        <div className="space-y-4">
          <Section title="Activité récente">
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

      {/* ── Tab: Compte ── */}
      {tab === "compte" && (
        <div className="space-y-4">
          {/* Edit pseudo */}
          <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
            <div className="font-bold text-sm flex items-center gap-2"><User className="w-4 h-4 text-primary" />Modifier le profil</div>
            <label className="block">
              <div className="text-sm font-semibold mb-1.5">{t("pseudo_label")}</div>
              <div className="flex gap-2">
                <input value={pseudo} onChange={e => setPseudo(e.target.value)} className="flex-1 px-4 py-2.5 rounded-full bg-secondary border border-border outline-none" />
                <button onClick={savePseudo} className="px-4 py-2.5 rounded-full bg-primary text-primary-foreground font-semibold">OK</button>
              </div>
            </label>
            <div className="flex items-center gap-3">
              <button onClick={() => fileRef.current?.click()} disabled={uploading}
                className="flex items-center gap-2 px-4 py-2.5 rounded-full bg-secondary font-semibold text-sm">
                <Camera className="w-4 h-4" /> {uploading ? "Upload…" : "Changer la photo"}
              </button>
            </div>
          </div>

          <PhoneVerification adminPhone={adminPhone} />
          {referralEnabled && <MyReferrals />}

          {/* Security */}
          <div className="rounded-3xl bg-card p-4 shadow-sm space-y-2">
            <div className="font-bold text-sm uppercase text-muted-foreground">{t("security_section")}</div>
            <button onClick={async () => { await signOut(); navigate({ to: "/login" }); }}
              className="w-full py-2.5 rounded-full bg-secondary font-semibold flex items-center justify-center gap-2 text-sm">
              <LogOut className="w-4 h-4" /> {t("logout")}
            </button>
            <button onClick={() => setShowDeleteDialog(true)}
              className="w-full py-2.5 rounded-full bg-destructive/10 text-destructive font-semibold flex items-center justify-center gap-2 text-sm border border-destructive/20">
              <Trash2 className="w-4 h-4" /> {t("delete_account_btn")}
            </button>
          </div>
        </div>
      )}

      {/* ── Tab: Notifs ── */}
      {tab === "notifs" && <NotifsTab />}

      {/* ── Tab: Aide ── */}
      {tab === "aide" && <AideSection />}

      <DeleteAccountDialog open={showDeleteDialog} onClose={() => setShowDeleteDialog(false)} />
    </main>
  );
}

// ── Notifications tab ───────────────────────────────────────────────────────
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
  return new Date(iso).toLocaleDateString("fr-FR", { day:"numeric", month:"short" });
}

function nDateLabel(iso: string) {
  const diff = Date.now() - new Date(iso).getTime();
  const d = Math.floor(diff / 86400000);
  if (d === 0) return "Aujourd'hui";
  if (d === 1) return "Hier";
  if (d < 7)   return "Cette semaine";
  return "Plus ancien";
}

function NotifsTab() {
  const { user } = useAuth();
  const [notifs, setNotifs] = useState<any[]>([]);
  const [dms,    setDms]    = useState<any[]>([]);
  const [reply,  setReply]  = useState("");
  const [busy,   setBusy]   = useState(false);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    if (!user) return;
    const [{ data: n }, { data: d }] = await Promise.all([
      (supabase.from("notifications" as any) as any)
        .select("*").eq("user_id", user.id)
        .order("created_at", { ascending: false }).limit(60),
      supabase.from("admin_user_messages").select("*").order("created_at").limit(60),
    ]);
    setNotifs(n || []); setDms(d || []);
    setLoading(false);
  };

  useEffect(() => {
    if (!user) return;
    load();
    // Mark all as read when tab opens
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
    const { error } = await supabase.from("admin_user_messages").insert({
      user_id: user.id, from_admin: false, message: reply.trim(),
    });
    setBusy(false);
    if (error) { toast.error(error.message); return; }
    setReply(""); toast.success("Message envoyé");
    load();
  };

  const unread = notifs.filter(n => !n.read_at).length + dms.filter(d => d.from_admin && !d.read_at).length;

  // Group notifications by date bucket
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

  if (loading) return (
    <div className="py-10 text-center text-muted-foreground text-sm animate-pulse">Chargement…</div>
  );

  return (
    <div className="space-y-5">
      {/* Header row */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h2 className="font-bold text-sm">Mes notifications</h2>
          {unread > 0 && (
            <span className="text-[10px] bg-destructive text-white px-2 py-0.5 rounded-full font-bold">
              {unread} non lu{unread > 1 ? "s" : ""}
            </span>
          )}
        </div>
        {unread > 0 && (
          <button
            onClick={async () => {
              await supabase.rpc("mark_notif_read" as any, { _id: null } as any);
              await supabase.rpc("mark_messages_read" as any);
              load();
            }}
            className="flex items-center gap-1.5 text-xs text-muted-foreground hover:text-foreground transition-colors"
          >
            <CheckCheck className="w-3.5 h-3.5" /> Tout marquer lu
          </button>
        )}
      </div>

      {/* Empty state */}
      {notifs.length === 0 && dms.length === 0 && (
        <div className="rounded-3xl bg-card p-8 flex flex-col items-center gap-3 text-center shadow-sm">
          <div className="w-16 h-16 rounded-full bg-muted flex items-center justify-center text-3xl">🔔</div>
          <div>
            <p className="font-bold">Tout est à jour</p>
            <p className="text-sm text-muted-foreground mt-0.5">Vous recevrez ici vos notifications de dépôts, tournois, et messages admin.</p>
          </div>
        </div>
      )}

      {/* Notification groups */}
      {groups.map(grp => (
        <div key={grp.label} className="space-y-2">
          <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground px-1">{grp.label}</p>
          <div className="rounded-3xl bg-card shadow-sm overflow-hidden divide-y divide-border/50">
            {grp.items.map(n => {
              const k = nKind(n.kind);
              const isUrgent = n.kind === "tournament" && !n.read_at;
              return (
                <a key={n.id} href={n.link || "#"}
                  className={`flex gap-3 p-4 transition-colors hover:bg-accent/40 ${isUrgent ? "bg-amber-50/80 dark:bg-amber-950/20" : !n.read_at ? k.bg : ""}`}>
                  {/* Icon */}
                  <div className={`w-10 h-10 rounded-2xl flex items-center justify-center text-xl flex-shrink-0 ${!n.read_at ? k.bg + " border " + k.border : "bg-secondary"}`}>
                    {k.emoji}
                  </div>
                  {/* Body */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-start justify-between gap-2">
                      <p className={`text-sm leading-snug ${!n.read_at ? "font-bold" : "font-medium"} line-clamp-2`}>{n.title}</p>
                      {!n.read_at && <span className={`mt-1.5 w-2 h-2 rounded-full flex-shrink-0 ${k.dot}`} />}
                    </div>
                    {n.body && <p className={`text-xs mt-0.5 line-clamp-3 leading-relaxed ${!n.read_at ? "text-foreground font-semibold" : "text-muted-foreground"}`}>{n.body}</p>}
                    <div className="flex items-center justify-between mt-2 gap-2">
                      <span className="text-[10px] text-muted-foreground">{nTimeAgo(n.created_at)}</span>
                      {isUrgent && (
                        <span className="text-[10px] bg-amber-500 text-white px-2 py-0.5 rounded-full font-bold">⚡ Rejoindre</span>
                      )}
                      {!isUrgent && n.link && (
                        <span className="text-[10px] text-primary font-semibold">Voir →</span>
                      )}
                    </div>
                  </div>
                </a>
              );
            })}
          </div>
        </div>
      ))}

      {/* Admin DMs thread */}
      {dms.length > 0 && (
        <div className="space-y-3">
          <p className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground px-1 flex items-center gap-1.5">
            <Megaphone className="w-3 h-3" /> Conversation avec l'équipe
          </p>
          <div className="rounded-3xl bg-card shadow-sm p-4 space-y-3">
            {/* Chat bubbles */}
            <div className="space-y-2 max-h-72 overflow-y-auto pr-1">
              {dms.map(d => (
                <div key={d.id} className={`flex ${d.from_admin ? "justify-start" : "justify-end"}`}>
                  <div className={`max-w-[80%] space-y-0.5`}>
                    {d.from_admin && (
                      <p className="text-[10px] font-bold text-muted-foreground px-1">Équipe Lalao</p>
                    )}
                    <div className={`px-3.5 py-2.5 rounded-2xl text-sm leading-snug ${d.from_admin
                      ? "bg-secondary rounded-tl-sm"
                      : "bg-primary text-primary-foreground rounded-tr-sm"}`}>
                      {d.message}
                    </div>
                    <p className={`text-[10px] px-1 ${d.from_admin ? "text-muted-foreground" : "text-right text-muted-foreground"}`}>
                      {nTimeAgo(d.created_at)}
                    </p>
                  </div>
                </div>
              ))}
            </div>
            {/* Reply input */}
            <div className="flex gap-2 pt-1 border-t border-border/60">
              <input
                value={reply}
                onChange={e => setReply(e.target.value)}
                onKeyDown={e => e.key === "Enter" && !e.shiftKey && sendReply()}
                placeholder="Votre réponse…"
                className="flex-1 px-4 py-2.5 rounded-full bg-secondary border border-border outline-none text-sm focus:ring-2 focus:ring-primary/30"
              />
              <button onClick={sendReply} disabled={busy || !reply.trim()}
                className="p-2.5 rounded-full bg-primary text-primary-foreground disabled:opacity-50 active:scale-95 transition-transform flex-shrink-0">
                <Send className="w-4 h-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

// ── Aide & Support ─────────────────────────────────────────────────────────
function AideSection() {
  const [category, setCategory] = useState("bug");
  const [message,  setMessage]  = useState("");
  const [busy,     setBusy]     = useState(false);
  const [adminPhone, setAdminPhone] = useState("");

  useEffect(() => {
    supabase.from("app_settings").select("admin_phone").eq("id", 1).maybeSingle()
      .then(({ data }) => setAdminPhone((data?.admin_phone as string) || ""));
  }, []);

  const CATEGORIES = [
    { value: "bug",        label: "🐛 Problème technique" },
    { value: "payment",    label: "💳 Problème de paiement" },
    { value: "game",       label: "🎮 Problème de jeu" },
    { value: "suggestion", label: "💡 Suggestion" },
    { value: "general",    label: "📝 Autre" },
  ];


  // ── Assistant IA toggle ───────────────────────────────────────────────────
  const [aiHidden, setAiHidden] = useState<boolean>(() => {
    if (typeof window === 'undefined') return false;
    return localStorage.getItem('ai_assistant_hidden') === 'true';
  });
  const toggleAI = () => {
    const newVal = !aiHidden;
    localStorage.setItem('ai_assistant_hidden', newVal ? 'true' : 'false');
    setAiHidden(newVal);
    window.dispatchEvent(new Event('ai_assistant_visibility_changed'));
    toast.success(newVal ? 'Assistant IA masqué' : '✅ Assistant IA réactivé');
  };

  const submit = async () => {
    if (message.trim().length < 5) { toast.error("Message trop court (min. 5 caractères)"); return; }
    setBusy(true);
    const { error } = await (supabase.rpc as any)("submit_bug_report", {
      _category: category, _message: message.trim(),
    });
    setBusy(false);
    if (error) { toast.error("Erreur lors de l'envoi"); return; }
    toast.success("Signalement envoyé — merci !"); setMessage(""); setCategory("bug");
  };

  return (
    <div className="space-y-4">
      {/* Quick links */}
      <div className="rounded-3xl bg-card p-4 shadow-sm space-y-1">
        <div className="font-bold text-sm flex items-center gap-2 mb-3">
          <HelpCircle className="w-4 h-4 text-primary" /> Aide & Ressources
        </div>
        <Link to="/faq"
          className="flex items-center justify-between py-2.5 px-3 -mx-1 rounded-2xl hover:bg-accent/60 transition-colors group">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-blue-100 dark:bg-blue-900/30 flex items-center justify-center text-lg flex-shrink-0">❓</div>
            <div>
              <div className="font-semibold text-sm">Centre d'aide / FAQ</div>
              <div className="text-xs text-muted-foreground">Paiements, jeux, compte…</div>
            </div>
          </div>
          <ChevronRight className="w-4 h-4 text-muted-foreground group-hover:translate-x-0.5 transition-transform" />
        </Link>
        <Link to="/tutos"
          className="flex items-center justify-between py-2.5 px-3 -mx-1 rounded-2xl hover:bg-accent/60 transition-colors group">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-violet-100 dark:bg-violet-900/30 flex items-center justify-center text-lg flex-shrink-0">📚</div>
            <div>
              <div className="font-semibold text-sm">Tutoriels</div>
              <div className="text-xs text-muted-foreground">Comment jouer à chaque jeu</div>
            </div>
          </div>
          <ChevronRight className="w-4 h-4 text-muted-foreground group-hover:translate-x-0.5 transition-transform" />
        </Link>
      </div>

      {/* Contact admin */}
      {adminPhone && (
        <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
          <div className="font-bold text-sm flex items-center gap-2">
            <MessageSquare className="w-4 h-4 text-primary" /> Contact support
          </div>
          <p className="text-xs text-muted-foreground">
            Pour les urgences (paiements, blocage de compte), contactez l'admin directement :
          </p>
          <div className="flex items-center gap-3 bg-secondary rounded-2xl px-4 py-3">
            <span className="text-2xl">📱</span>
            <div>
              <div className="text-[10px] text-muted-foreground font-semibold uppercase tracking-wide">Numéro admin</div>
              <div className="font-extrabold text-lg tracking-wide">{adminPhone}</div>
            </div>
          </div>
        </div>
      )}


      {/* Assistant IA — activer/masquer */}
      <div className="rounded-3xl bg-card p-4 shadow-sm">
        <div className="flex items-center justify-between gap-3">
          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center flex-shrink-0">
              <Bot className="w-5 h-5 text-primary" />
            </div>
            <div>
              <div className="font-semibold text-sm">Assistant IA</div>
              <div className="text-xs text-muted-foreground">
                {aiHidden ? 'Masqué — appuyez pour réafficher' : 'Visible sur toutes les pages'}
              </div>
            </div>
          </div>
          <button
            onClick={toggleAI}
            className={["relative w-12 h-6 rounded-full transition-colors duration-200 focus:outline-none", aiHidden ? "bg-muted" : "bg-primary"].join(" ")}
            aria-label="Activer ou désactiver l'assistant IA"
          >
            <span className={["absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform duration-200", aiHidden ? "translate-x-0" : "translate-x-6"].join(" ")} />
          </button>
        </div>
      </div>

      {/* Bug report inline form */}
      <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
        <div className="font-bold text-sm flex items-center gap-2">
          <Bug className="w-4 h-4 text-destructive" /> Signaler un problème
        </div>
        <p className="text-xs text-muted-foreground">
          Bug, problème de paiement ou suggestion ? Notre équipe vous répond rapidement.
        </p>

        {/* Category selector */}
        <div className="relative">
          <select value={category} onChange={e => setCategory(e.target.value)}
            className="w-full appearance-none bg-secondary rounded-xl px-4 py-3 text-sm font-medium pr-10 focus:outline-none focus:ring-2 focus:ring-primary/40 cursor-pointer">
            {CATEGORIES.map(c => <option key={c.value} value={c.value}>{c.label}</option>)}
          </select>
          <ChevronRight className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 pointer-events-none text-muted-foreground rotate-90" />
        </div>

        {/* Message */}
        <div>
          <textarea value={message} onChange={e => setMessage(e.target.value)}
            placeholder="Décrivez le problème en détail…"
            rows={4} maxLength={1000}
            className="w-full bg-secondary rounded-xl px-4 py-3 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/40 placeholder:text-muted-foreground" />
          <div className="text-right text-xs text-muted-foreground mt-1">{message.length}/1000</div>
        </div>

        <button onClick={submit} disabled={busy || message.trim().length < 5}
          className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2 disabled:opacity-50 active:scale-[0.98] transition-all">
          <Send className="w-4 h-4" />
          {busy ? "Envoi en cours…" : "Envoyer le signalement"}
        </button>

        <p className="text-center text-xs text-muted-foreground">
          Votre signalement sera examiné par l'équipe dans les meilleurs délais.
        </p>
      </div>
    </div>
  );
}

// ── Helpers ──

function preferredGame(gs: Record<string, { played: number; wins: number }>) {
  const map: Record<string, string> = { ludo: "🎲 Ludo", domino: "🁣 Domino", fanorona: "♟ Fanorona", rami: "🃏 Rami", chess: "♜ Échecs" };
  let best = "—"; let max = 0;
  for (const [k, v] of Object.entries(gs)) { if (v.played > max) { max = v.played; best = map[k] || k; } }
  return best;
}

function levelTitle(l: number) {
  return (["Débutant", "Amateur", "Confirmé", "Expert", "Légende"] as const)[l - 1] || `Niveau ${l}`;
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 py-1.5 border-b border-border/40 last:border-0">
      <span className="text-sm text-muted-foreground shrink-0">{label}</span>
      <span className="text-sm font-semibold text-right">{value}</span>
    </div>
  );
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
      <div className="rounded-3xl bg-card p-4 shadow-sm space-y-2">
        <div className="font-bold flex items-center gap-2 text-emerald-600"><ShieldCheck className="w-5 h-5" /> {t("phone_verified_status")}</div>
        <div className="text-sm">{p.phone}</div>
      </div>
    );
  }

  return (
    <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
      <div className="font-bold flex items-center gap-2"><Phone className="w-4 h-4" /> {t("phone_verification_title")}</div>
      <div className="text-xs text-amber-700 bg-amber-50 dark:bg-amber-950/20 rounded-xl p-2">{t("phone_required_info")}</div>
      <input value={phone} onChange={e => setPhone(e.target.value)} placeholder={t("phone_placeholder")}
        className="w-full px-4 py-3 rounded-2xl bg-secondary outline-none" />
      <button onClick={generate} disabled={busy} className="w-full py-3 rounded-full bg-primary text-primary-foreground font-bold">
        {busy ? "..." : code ? t("regenerate_code_btn") : t("generate_code_btn")}
      </button>
      {code && (
        <div className="rounded-2xl bg-accent p-3 space-y-1">
          <div className="text-xs uppercase text-muted-foreground">{t("your_code_label")}</div>
          <div className="text-3xl font-black tracking-wider text-center">{code}</div>
          <div className="text-xs text-center">
            Envoyez ce code par SMS/MVola au numéro admin&nbsp;:
            <div className="text-base font-extrabold mt-1">{adminPhone}</div>
            {t("admin_will_validate")}
          </div>
        </div>
      )}
    </div>
  );
}

function MyReferrals() {
  return (
    <Link to="/parrainage"
      className="rounded-3xl bg-gradient-to-r from-primary/10 via-card to-violet-500/5 border border-primary/20 p-4 shadow-sm flex items-center justify-between gap-3 hover:bg-primary/5 transition-colors">
      <div className="flex items-center gap-3">
        <div className="w-10 h-10 rounded-2xl bg-primary/10 flex items-center justify-center text-xl">🤝</div>
        <div>
          <div className="font-bold text-sm">Programme de parrainage</div>
          <div className="text-xs text-muted-foreground">Invitez des amis et gagnez des commissions</div>
        </div>
      </div>
      <ChevronRight className="w-5 h-5 text-muted-foreground shrink-0" />
    </Link>
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
    <div className="rounded-3xl bg-card p-4 shadow-sm">
      <div className="font-bold text-sm uppercase text-muted-foreground mb-3">{title}</div>
      <div>{children}</div>
    </div>
  );
}

function Empty() {
  const { t } = useT();
  return <div className="text-center text-muted-foreground text-sm py-4">{t("no_items")}</div>;
}

function labelType(type: string, t: (k: string) => string) {
  return ({ deposit: t("tx_deposit"), withdraw: t("tx_withdraw"), stake: t("tx_stake"), win: t("tx_win"), bonus: t("tx_bonus"), referral: t("tx_referral"), admin_adjust: t("tx_admin_adjust"), refund: t("tx_refund") } as any)[type] || type;
}
