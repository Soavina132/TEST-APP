import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { copyText } from "@/lib/clipboard";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  Camera, Copy, Coins, ShieldCheck, ShieldAlert, LogOut, Trash2,
  Phone, Trophy, Gamepad2, User, Star, Flame,
  TrendingUp, Award, BarChart3, Lock, ChevronRight,
  HelpCircle, Bug, Send, MessageSquare, Bot,
  Bell, CheckCheck, ArrowDownLeft, ArrowUpRight, Gift,
  Mail, Settings, FileText, Shield, Sparkles,
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

/* ── Helpers ── */

const BADGES = [
  { min: 0,  label: "Bronze",  color: "from-amber-700 to-amber-500",     ring: "ring-amber-600/40",    text: "text-amber-600",     icon: "🥉" },
  { min: 2,  label: "Argent",  color: "from-slate-400 to-slate-300",     ring: "ring-slate-400/40",    text: "text-slate-400",     icon: "🥈" },
  { min: 3,  label: "Or",      color: "from-yellow-500 to-amber-400",    ring: "ring-yellow-500/40",   text: "text-yellow-500",   icon: "🥇" },
  { min: 4,  label: "Diamant", color: "from-cyan-400 to-blue-500",       ring: "ring-cyan-400/40",     text: "text-cyan-400",     icon: "💎" },
  { min: 5,  label: "Platine",color: "from-violet-500 to-fuchsia-500",   ring: "ring-violet-500/40",   text: "text-violet-500",   icon: "👑" },
];

function getBadge(level: number) {
  let b = BADGES[0];
  for (const bd of BADGES) if (level >= bd.min) b = bd;
  return b;
}

function preferredGame(gs: Record<string, { played: number; wins: number }>) {
  const map: Record<string, string> = { ludo: "Ludo", domino: "Domino", fanorona: "Fanorona", rami: "Rami", chess: "Échecs" };
  const icons: Record<string, string> = { ludo: "🎲", domino: "🁣", fanorona: "♟", rami: "🃏", chess: "♜" };
  let best = "—"; let bestIcon = ""; let max = 0;
  for (const [k, v] of Object.entries(gs)) { if (v.played > max) { max = v.played; best = map[k] || k; bestIcon = icons[k] || ""; } }
  return best === "—" ? "—" : `${bestIcon} ${best}`;
}

function labelType(type: string, t: (k: string) => string) {
  return ({ deposit: t("tx_deposit"), withdraw: t("tx_withdraw"), stake: t("tx_stake"), win: t("tx_win"), bonus: t("tx_bonus"), referral: t("tx_referral"), admin_adjust: t("tx_admin_adjust"), refund: t("tx_refund") } as any)[type] || type;
}

/* ── Page ── */

function ProfilePage() {
  const { user, profile, refreshProfile, signOut } = useAuth();
  const navigate = useNavigate();
  const { t } = useT();
  const [pseudo, setPseudo] = useState(profile?.pseudo || "");
  const [editingName, setEditingName] = useState(false);
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
  const [bonusTotal, setBonusTotal] = useState(0);
  const [showHistory, setShowHistory] = useState<"none" | "deposits" | "withdrawals" | "games">("none");

  useEffect(() => { setPseudo(profile?.pseudo || ""); }, [profile?.pseudo]);

  useEffect(() => {
    if (!user) return;
    const uid = user.id;
    supabase.from("transactions").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(100).then(({ data }) => setTx(data || []));
    supabase.from("deposits").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setDeps(data || []));
    supabase.from("withdrawals").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setWiths(data || []));
    (supabase.from("app_settings" as any) as any).select("admin_phone, referral_enabled").eq("id", 1).maybeSingle().then(({ data }: any) => {
      setAdminPhone((data?.admin_phone as string) || "");
      setReferralEnabled((data as any)?.referral_enabled !== false);
    });
    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => { if (data) setPlayerStats(data); });
    supabase.from("transactions").select("amount").eq("user_id", uid).eq("type", "win").order("amount", { ascending: false }).limit(1).then(({ data }: any) => { if (data && data[0]) setBiggestWin(Number(data[0].amount)); });
    supabase.from("transactions").select("amount").eq("user_id", uid).eq("type", "bonus").then(({ data }: any) => {
      if (data) setBonusTotal(data.reduce((s: number, r: any) => s + Number(r.amount), 0));
    });

    const fetchGameStats = async () => {
      const stats: Record<string, { played: number; wins: number }> = {
        ludo: { played: 0, wins: 0 }, domino: { played: 0, wins: 0 },
        fanorona: { played: 0, wins: 0 }, rami: { played: 0, wins: 0 },
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
    supabase.rpc("get_player_achievements" as any, { _uid: uid } as any).then(({ data }: any) => setAchievements(data || []));
  }, [user?.id]);

  const savePseudo = async () => {
    if (!pseudo.trim() || pseudo === profile?.pseudo) { setEditingName(false); return; }
    const { error } = await supabase.from("profiles").update({ pseudo: pseudo.trim() }).eq("id", user!.id);
    if (error) return toast.error(error.message);
    toast.success("Pseudo mis à jour"); refreshProfile(); setEditingName(false);
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
  const totalLosses = totalGames - totalWins;
  const memberDays = Math.floor((Date.now() - new Date((profile as any).created_at || Date.now()).getTime()) / 86400000);
  const badge = getBadge(level);

  // Achievement display
  const ACHIEVEMENT_ICONS: Record<string, { icon: string; label: string }> = {
    first_deposit: { icon: "🏆", label: "Premier dépôt" },
    win_streak_10: { icon: "🔥", label: "10 victoires d'affilée" },
    games_100:     { icon: "👑", label: "100 parties jouées" },
    referral:      { icon: "⭐", label: "Parrain confirmé" },
  };
  const ACHIEVEMENT_SLOTS = Object.keys(ACHIEVEMENT_ICONS);
  const unlockedKeys = new Set(achievements.map((a: any) => a.key));
  const lockedCount = Math.max(0, ACHIEVEMENT_SLOTS.length - achievements.length);

  const MENU_ITEMS = [
    { icon: User,      label: "Modifier le profil",    action: () => fileRef.current?.click(), color: "text-blue-500" },
    { icon: Shield,    label: "Sécurité du compte",     action: () => setShowDeleteDialog(true), color: "text-emerald-500" },
    { icon: Phone,     label: p.phone_verified ? "Numéro vérifié" : "Vérifier mon numéro", action: () => navigate({ to: "/profile", search: {} }), color: "text-violet-500" },
    { icon: Mail,      label: "E-mail",                 action: () => toast.info(profile.email || "Non défini"), color: "text-amber-500" },
    { icon: ArrowDownLeft, label: "Historique des dépôts", action: () => setShowHistory(showHistory === "deposits" ? "none" : "deposits"), color: "text-emerald-500" },
    { icon: ArrowUpRight,  label: "Historique des retraits", action: () => setShowHistory(showHistory === "withdrawals" ? "none" : "withdrawals"), color: "text-rose-500" },
    { icon: Gamepad2,  label: "Historique des parties", action: () => setShowHistory(showHistory === "games" ? "none" : "games"), color: "text-primary" },
    { icon: Gift,     label: "Parrainage & récompenses", action: () => navigate({ to: "/parrainage", search: {} }), color: "text-fuchsia-500" },
    { icon: HelpCircle, label: "Centre d'aide",        action: () => navigate({ to: "/faq", search: {} }), color: "text-blue-400" },
    { icon: Settings,   label: "Paramètres",            action: () => toast.info("Bientôt disponible"), color: "text-muted-foreground" },
  ];

  return (
    <main className="max-w-2xl mx-auto px-3 py-4 space-y-5 pb-24">
      <input ref={fileRef} type="file" accept="image/*" hidden onChange={e => e.target.files?.[0] && upload(e.target.files[0])} />

      {/* ═══ SECTION 1: Informations du joueur ═══ */}
      <section className="space-y-2">
        <div className="rounded-2xl border border-white/8 bg-card p-3.5 shadow-sm relative overflow-hidden">
          {/* Badge gradient strip */}
          <div className={`absolute inset-x-0 top-0 h-1 bg-gradient-to-r ${badge.color}`} />

          <div className="flex items-center gap-3 pt-1">
            {/* Avatar */}
            <div className="relative shrink-0">
              <div className={`w-14 h-14 rounded-full p-[2.5px] bg-gradient-to-br ${badge.color}`}>
                <div className="w-full h-full rounded-full bg-card flex items-center justify-center text-lg font-black overflow-hidden ring-2 ring-card">
                  {profile.avatar_url
                    ? <img src={profile.avatar_url} alt={`Avatar de ${profile.pseudo}`} className="w-full h-full object-cover rounded-full" />
                    : <span className="text-primary">{initials}</span>}
                </div>
              </div>
              <button onClick={() => fileRef.current?.click()} disabled={uploading}
                aria-label="Changer la photo"
                className="absolute -bottom-0.5 -right-0.5 p-1 rounded-full bg-primary text-primary-foreground ring-2 ring-card active:scale-90 transition-transform">
                <Camera className="w-3 h-3" strokeWidth={2} />
              </button>
            </div>

            {/* Right column: name, id, badge, meta */}
            <div className="flex-1 min-w-0 text-left">
              {/* Name */}
              {editingName ? (
                <div className="flex gap-1.5 max-w-xs">
                  <input
                    value={pseudo}
                    onChange={e => setPseudo(e.target.value)}
                    onKeyDown={e => e.key === "Enter" && savePseudo()}
                    autoFocus
                    className="flex-1 px-3 py-1.5 rounded-full bg-secondary border border-border outline-none text-sm font-bold"
                  />
                  <button onClick={savePseudo} className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-bold">OK</button>
                </div>
              ) : (
                <button onClick={() => setEditingName(true)} className="font-black text-base leading-tight hover:text-primary transition-colors truncate block">
                  {profile.pseudo}
                </button>
              )}

              <div className="mt-1 flex items-center flex-wrap gap-x-2 gap-y-1">
                {/* Badge */}
                <div className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-gradient-to-r ${badge.color} text-white text-[11px] font-bold shadow-sm`}>
                  <span>{badge.icon}</span>
                  <span>{badge.label}</span>
                  {myRank && <span className="opacity-80">· #{myRank}</span>}
                </div>

                {/* Player ID */}
                {profile.unique_code && (
                  <button onClick={() => copyText(profile.unique_code!).then(ok => toast[ok ? "success" : "error"](ok ? "ID copié !" : "Erreur"))}
                    className="inline-flex items-center gap-1 text-[11px] text-muted-foreground font-mono hover:text-foreground transition-colors">
                    ID: {profile.unique_code} <Copy className="w-2.5 h-2.5" strokeWidth={1.5} />
                  </button>
                )}
              </div>

              {/* Verification + member */}
              <div className="mt-1 flex items-center gap-2 text-[10.5px] text-muted-foreground">
                {p.phone_verified && <span className="inline-flex items-center gap-0.5 text-emerald-500"><ShieldCheck className="w-2.5 h-2.5" /> Vérifié</span>}
                <span>Membre depuis {memberDays}j</span>
                {streak > 0 && <span className="inline-flex items-center gap-0.5 text-amber-500"><Flame className="w-2.5 h-2.5" /> {streak}j</span>}
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ═══ SECTION 2: Solde et actions ═══ */}
      <section>
        <div className="rounded-3xl border border-white/8 bg-gradient-to-br from-primary/10 via-card to-violet-500/5 p-5 shadow-sm space-y-4">
          <div className="grid grid-cols-2 gap-3">
            {/* Main balance */}
            <div className="rounded-2xl bg-card/80 p-4 space-y-1">
              <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-semibold">
                <Coins className="w-3.5 h-3.5 text-primary" /> Solde principal
              </div>
              <div className="text-2xl font-black text-primary tabular-nums">
                {Math.round(profile.balance_ar).toLocaleString("fr-FR")}
              </div>
              <div className="text-[10px] text-muted-foreground uppercase tracking-wider">Ariary</div>
            </div>
            {/* Bonus */}
            <div className="rounded-2xl bg-card/80 p-4 space-y-1">
              <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-semibold">
                <Gift className="w-3.5 h-3.5 text-fuchsia-500" /> Bonus
              </div>
              <div className="text-2xl font-black text-fuchsia-500 tabular-nums">
                {Math.round(bonusTotal).toLocaleString("fr-FR")}
              </div>
              <div className="text-[10px] text-muted-foreground uppercase tracking-wider">Ariary</div>
            </div>
          </div>

          {/* Action buttons */}
          <div className="grid grid-cols-2 gap-3">
            <button
              onClick={() => navigate({ to: "/lobby", search: {} })}
              className="flex items-center justify-center gap-2 py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition-transform shadow-sm">
              <ArrowDownLeft className="w-4 h-4" /> Déposer
            </button>
            <button
              onClick={() => navigate({ to: "/lobby", search: {} })}
              className="flex items-center justify-center gap-2 py-3 rounded-2xl bg-secondary text-foreground font-bold text-sm active:scale-95 transition-transform border border-border shadow-sm">
              <ArrowUpRight className="w-4 h-4" /> Retirer
            </button>
          </div>
        </div>
      </section>

      {/* ═══ SECTION 3: Statistiques & Succès ═══ */}
      <section className="space-y-3">
        <h2 className="text-xs font-bold uppercase tracking-widest text-muted-foreground px-1">Statistiques</h2>

        {/* Stat cards grid */}
        <div className="grid grid-cols-2 gap-3">
          <StatTile label="Parties jouées" value={totalGames} icon="🎮" />
          <StatTile label="Victoires" value={totalWins} icon="🏆" color="text-emerald-500" />
          <StatTile label="Défaites" value={totalLosses} icon="📉" color="text-destructive" />
          <StatTile label="Taux de victoire" value={`${winRate}%`} icon="📊" color={winRate >= 50 ? "text-emerald-500" : "text-amber-500"} />
        </div>

        {/* Favorite games */}
        <div className="rounded-2xl border border-white/8 bg-card p-4 space-y-3 shadow-sm">
          <div className="text-xs font-bold uppercase tracking-widest text-muted-foreground">Jeux favoris</div>
          <div className="flex flex-wrap gap-2">
            {[
              { k: "ludo", icon: "🎲", name: "Ludo" },
              { k: "domino", icon: "🁣", name: "Domino" },
              { k: "fanorona", icon: "♟", name: "Fanorona" },
              { k: "rami", icon: "🃏", name: "Rami" },
              { k: "chess", icon: "♜", name: "Échecs" },
            ].map(g => {
              const s = gameStats[g.k];
              const played = s?.played || 0;
              return (
                <div key={g.k} className={`px-3 py-2 rounded-xl text-xs font-semibold flex items-center gap-1.5 ${played > 0 ? "bg-primary/10 text-primary border border-primary/20" : "bg-secondary/50 text-muted-foreground border border-white/5"}`}>
                  <span>{g.icon}</span> {g.name}
                  {played > 0 && <span className="text-[10px] opacity-70">({played})</span>}
                </div>
              );
            })}
          </div>
        </div>

        {/* Achievements */}
        <div className="rounded-2xl border border-white/8 bg-card p-4 space-y-3 shadow-sm">
          <div className="flex items-center justify-between">
            <div className="text-xs font-bold uppercase tracking-widest text-muted-foreground flex items-center gap-1.5">
              <Trophy className="w-3.5 h-3.5 text-amber-500" /> Succès
            </div>
            <span className="text-[10px] text-muted-foreground tabular-nums">{achievements.length}/{ACHIEVEMENT_SLOTS.length}</span>
          </div>
          <div className="grid grid-cols-4 gap-2">
            {ACHIEVEMENT_SLOTS.map(key => {
              const info = ACHIEVEMENT_ICONS[key];
              const unlocked = achievements.find((a: any) => a.key === key);
              return (
                <div key={key} className={`flex flex-col items-center gap-1 p-2 rounded-xl text-center ${unlocked ? "bg-amber-500/10 border border-amber-500/25" : "bg-secondary/30 border border-dashed border-white/8 opacity-40"}`}>
                  <span className={`text-xl ${unlocked ? "" : "grayscale"}`}>{info.icon}</span>
                  <span className="text-[9px] font-semibold leading-tight text-center">{info.label}</span>
                </div>
              );
            })}
          </div>
        </div>
      </section>

      {/* ═══ SECTION 4: Paramètres & Historique ═══ */}
      <section className="space-y-3">
        <h2 className="text-xs font-bold uppercase tracking-widest text-muted-foreground px-1">Paramètres & Historique</h2>

        <div className="rounded-2xl border border-white/8 bg-card shadow-sm overflow-hidden divide-y divide-border/30">
          {MENU_ITEMS.map((item, i) => (
            <button key={i} onClick={item.action}
              className="w-full flex items-center gap-3 px-4 py-3.5 hover:bg-accent/40 transition-colors group">
              <div className={`w-9 h-9 rounded-xl bg-secondary/60 flex items-center justify-center shrink-0 ${item.color}`}>
                <item.icon className="w-4 h-4" strokeWidth={2} />
              </div>
              <span className="flex-1 text-left text-sm font-semibold">{item.label}</span>
              <ChevronRight className="w-4 h-4 text-muted-foreground group-hover:translate-x-0.5 transition-transform shrink-0" />
            </button>
          ))}
        </div>

        {/* Inline history panels */}
        {showHistory === "deposits" && (
          <HistoryPanel title="Historique des dépôts" items={deps} type="deposit" />
        )}
        {showHistory === "withdrawals" && (
          <HistoryPanel title="Historique des retraits" items={withs} type="withdrawal" />
        )}
        {showHistory === "games" && (
          <HistoryPanel title="Historique des parties" items={tx.filter(t => t.type === "stake" || t.type === "win" || t.type === "refund")} type="game" t={t} />
        )}

        {/* Logout */}
        <div className="rounded-2xl border border-white/8 bg-card shadow-sm overflow-hidden divide-y divide-border/30">
          <button onClick={async () => { await signOut(); navigate({ to: "/login" }); }}
            className="w-full flex items-center gap-3 px-4 py-3.5 hover:bg-destructive/5 transition-colors group">
            <div className="w-9 h-9 rounded-xl bg-destructive/10 flex items-center justify-center shrink-0 text-destructive">
              <LogOut className="w-4 h-4" strokeWidth={2} />
            </div>
            <span className="flex-1 text-left text-sm font-semibold text-destructive">Déconnexion</span>
            <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
          </button>
          <button onClick={() => setShowDeleteDialog(true)}
            className="w-full flex items-center gap-3 px-4 py-3.5 hover:bg-destructive/5 transition-colors group">
            <div className="w-9 h-9 rounded-xl bg-destructive/10 flex items-center justify-center shrink-0 text-destructive">
              <Trash2 className="w-4 h-4" strokeWidth={2} />
            </div>
            <span className="flex-1 text-left text-sm font-semibold text-destructive">Supprimer mon compte</span>
            <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
          </button>
        </div>
      </section>

      {/* ═══ Footer ═══ */}
      <footer className="space-y-2 pt-2 pb-4 text-center">
        <div className="text-[10px] text-muted-foreground">Lalao MADA v1.0.0</div>
        <div className="flex items-center justify-center gap-4 text-[10px]">
          <span className="text-muted-foreground hover:text-foreground transition-colors cursor-pointer">Conditions d'utilisation</span>
          <span className="text-muted-foreground/30">·</span>
          <span className="text-muted-foreground hover:text-foreground transition-colors cursor-pointer">Politique de confidentialité</span>
        </div>
      </footer>

      <DeleteAccountDialog open={showDeleteDialog} onClose={() => setShowDeleteDialog(false)} />
    </main>
  );
}

/* ── Sub-components ── */

function StatTile({ label, value, icon, color = "text-foreground" }: { label: string; value: string | number; icon: string; color?: string }) {
  return (
    <div className="rounded-2xl border border-white/8 bg-card p-4 space-y-1 shadow-sm">
      <div className="text-lg">{icon}</div>
      <div className={`text-xl font-black ${color} tabular-nums leading-none`}>{value}</div>
      <div className="text-[10px] text-muted-foreground uppercase tracking-wider">{label}</div>
    </div>
  );
}

function HistoryPanel({ title, items, type, t }: { title: string; items: any[]; type: string; t?: (k: string) => string }) {
  return (
    <div className="rounded-2xl border border-white/8 bg-card p-4 shadow-sm space-y-2">
      <div className="text-xs font-bold uppercase tracking-widest text-muted-foreground">{title}</div>
      {items.length === 0 ? (
        <div className="text-center text-muted-foreground text-sm py-4">Aucun historique</div>
      ) : items.slice(0, 15).map((item, i) => (
        <div key={item.id || i} className="flex items-center justify-between py-2 border-b border-border/30 last:border-0">
          <div className="min-w-0">
            <div className="text-xs font-semibold truncate">
              {type === "deposit" && `${item.method} · ${item.reference || ""}`}
              {type === "withdrawal" && `${item.method} · ${item.user_phone || ""}`}
              {type === "game" && (t ? labelType(item.type, t) : item.type)}
            </div>
            <div className="text-[10px] text-muted-foreground">{new Date(item.created_at).toLocaleString("fr-FR")}</div>
          </div>
          <div className="flex items-center gap-2 shrink-0">
            {item.status && (
              <span className={`text-[9px] px-2 py-0.5 rounded-full font-bold ${
                item.status === "approved" ? "bg-emerald-100 text-emerald-700" :
                item.status === "rejected" ? "bg-rose-100 text-rose-700" :
                "bg-amber-100 text-amber-700"
              }`}>
                {item.status === "approved" ? "Validé" : item.status === "rejected" ? "Rejeté" : "En attente"}
              </span>
            )}
            <div className={`text-xs font-bold ${Number(item.amount) >= 0 ? "text-emerald-600" : "text-destructive"}`}>
              {Number(item.amount) >= 0 ? "+" : ""}{Math.round(Number(item.amount)).toLocaleString("fr-FR")} Ar
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}
