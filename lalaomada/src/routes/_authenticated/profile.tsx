import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useT, Lang } from "@/lib/i18n";
import { useTheme } from "@/hooks/use-theme";
import { copyText } from "@/lib/clipboard";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  Camera, Copy, Coins, ShieldCheck, ShieldAlert, Mail, LogOut, Trash2,
  Phone, Gamepad2,
  ArrowDownLeft, ArrowUpRight, Gift,
  HelpCircle, Shield, ChevronRight, Settings,
  Send,
} from "lucide-react";
import { DeleteAccountDialog } from "@/components/DeleteAccountDialog";
import { compressImageToWebp } from "@/lib/image-compress";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";

export const Route = createFileRoute("/_authenticated/profile")({
  component: ProfilePage,
  head: () => ({ meta: [
    { title: "Mon profil — Lalao MADA" },
    { name: "description", content: "Profil joueur Lalao MADA : statistiques, jeux, classement et historique." },
  ] }),
});

/* ── Helpers ── */

const BADGES = [
  { min: 0,  label: "Bronze",  color: "from-amber-700 to-amber-500",     icon: "🥉" },
  { min: 2,  label: "Argent",  color: "from-slate-400 to-slate-300",     icon: "🥈" },
  { min: 3,  label: "Or",      color: "from-yellow-500 to-amber-400",    icon: "🥇" },
  { min: 4,  label: "Diamant", color: "from-orange-500 to-amber-500 dark:from-neutral-900 dark:to-black", icon: "💎" },
  { min: 5,  label: "Platine", color: "from-violet-500 to-fuchsia-500",   icon: "👑" },
];

function getBadge(level: number) {
  let b = BADGES[0];
  for (const bd of BADGES) if (level >= bd.min) b = bd;
  return b;
}

function labelType(type: string, t: (k: string) => string) {
  return ({ deposit: t("tx_deposit"), withdraw: t("tx_withdraw"), stake: t("tx_stake"), win: t("tx_win"), bonus: t("tx_bonus"), referral: t("tx_referral"), admin_adjust: t("tx_admin_adjust"), refund: t("tx_refund"), transfer_sent: "Transfert envoyé", transfer_received: "Transfert reçu" } as any)[type] || type;
}

/* ── Mini stat tile ── */
function MiniStat({ label, value, icon, color }: { label: string; value: string | number; icon: string; color?: string }) {
  return (
    <div className="rounded-xl bg-secondary/50 px-1 py-1.5 text-center flex-1">
      <div className="text-sm">{icon}</div>
      <div className={`text-sm font-extrabold leading-none ${color || "text-foreground"}`}>{value}</div>
      <div className="text-[8px] text-muted-foreground uppercase tracking-wide leading-tight mt-0.5">{label}</div>
    </div>
  );
}

/* ── Menu icon button ── */
function MenuButton({ icon: Icon, label, action, color }: {
  icon: any; label: string; action: () => void; color: string;
}) {
  return (
    <button onClick={action}
      className="flex flex-col items-center gap-1 px-1 py-2 rounded-xl bg-card border border-border/40 hover:bg-accent/30 active:scale-95 transition-all">
      <div className={`w-8 h-8 rounded-lg bg-secondary/60 flex items-center justify-center ${color}`}>
        <Icon className="w-4 h-4" strokeWidth={2} />
      </div>
      <span className="text-[9px] font-semibold text-center leading-tight">{label}</span>
    </button>
  );
}


/* ── History Dialog ── */
function HistoryDialog({ open, onClose, title, items, emptyMsg, renderItem }: {
  open: boolean; onClose: () => void; title: string;
  items: any[]; emptyMsg: string;
  renderItem: (item: any) => React.ReactNode;
}) {
  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="text-center">{title}</DialogTitle>
        </DialogHeader>
        <div className="pt-2 max-h-[50vh] overflow-y-auto">
          {items.length === 0 ? (
            <div className="text-sm text-muted-foreground py-6 text-center">{emptyMsg}</div>
          ) : (
            <div className="space-y-1">
              {items.map(renderItem)}
            </div>
          )}
        </div>
      </DialogContent>
    </Dialog>
  );
}

/* ── Transfer Dialog ── */
function TransferDialog({ open, onClose, balance, onSent }: {
  open: boolean; onClose: () => void; balance: number; onSent: () => void;
}) {
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("");
  const [sending, setSending] = useState(false);
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);

  // Search users by phone or pseudo (debounced)
  useEffect(() => {
    if (!recipient.trim() || recipient.trim().length < 2) {
      setSearchResults([]);
      return;
    }
    const timer = setTimeout(async () => {
      setSearching(true);
      const q = recipient.trim();
      const { data } = await supabase
        .from("profiles")
        .select("id, pseudo, phone, avatar_url")
        .or(`pseudo.ilike.%${q}%,phone.ilike.%${q}%`)
        .limit(5);
      setSearchResults(data || []);
      setSearching(false);
    }, 300);
    return () => clearTimeout(timer);
  }, [recipient]);

  const doTransfer = async () => {
    const amt = parseInt(amount);
    if (!recipient.trim()) return toast.error("Entrez le numéro ou pseudo du destinataire");
    if (!amt || amt < 100) return toast.error("Montant minimum: 100 Ar");
    if (amt > balance) return toast.error("Solde insuffisant");
    setSending(true);
    try {
      const { data, error } = await supabase.rpc("transfer_balance" as any, {
        _recipient: recipient.trim(),
        _amount: amt,
      } as any);
      if (error) throw error;
      toast.success(`Transfert de ${amt.toLocaleString("fr-FR")} Ar envoyé à ${data?.recipient || recipient} !`);
      setRecipient("");
      setAmount("");
      setSearchResults([]);
      onSent();
      onClose();
    } catch (e: any) {
      toast.error(e.message || "Erreur lors du transfert");
    } finally {
      setSending(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-sm">
        <DialogHeader>
          <DialogTitle className="text-center flex items-center justify-center gap-1.5">
            <Send className="w-4 h-4 text-primary" /> Transférer du solde
          </DialogTitle>
        </DialogHeader>
        <div className="pt-2 space-y-3">
          {/* Balance display */}
          <div className="rounded-xl bg-primary/5 border border-primary/20 px-3 py-2 text-center">
            <span className="text-[10px] text-muted-foreground uppercase font-semibold">Solde actuel</span>
            <div className="text-xl font-black text-primary tabular-nums">
              {Math.round(balance).toLocaleString("fr-FR")} <span className="text-xs">Ar</span>
            </div>
          </div>

          {/* Recipient input */}
          <div className="relative">
            <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">Destinataire</label>
            <input
              value={recipient}
              onChange={(e) => setRecipient(e.target.value)}
              placeholder="Numéro de téléphone ou pseudo"
              className="w-full mt-0.5 px-3 py-2 rounded-xl bg-card border border-border outline-none text-sm focus:border-primary/50 transition-colors"
              autoFocus
            />
            {/* Search results dropdown */}
            {searchResults.length > 0 && (
              <div className="absolute z-10 mt-1 w-full rounded-xl border border-border bg-popover shadow-lg overflow-hidden">
                {searchResults.map((u) => (
                  <button
                    key={u.id}
                    onClick={() => {
                      setRecipient(u.phone || u.pseudo);
                      setSearchResults([]);
                    }}
                    className="w-full flex items-center gap-2 px-3 py-2 hover:bg-accent/30 transition-colors text-left border-b border-border/20 last:border-0"
                  >
                    {u.avatar_url ? (
                      <img src={u.avatar_url} alt="" className="w-7 h-7 rounded-full object-cover" />
                    ) : (
                      <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary">
                        {(u.pseudo || "?").slice(0, 2).toUpperCase()}
                      </div>
                    )}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-semibold truncate">{u.pseudo}</div>
                      {u.phone && <div className="text-[10px] text-muted-foreground truncate">{u.phone}</div>}
                    </div>
                  </button>
                ))}
              </div>
            )}
            {searching && (
              <div className="absolute z-10 mt-1 w-full text-center text-xs text-muted-foreground py-1">Recherche…</div>
            )}
          </div>

          {/* Amount input */}
          <div>
            <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">Montant (Ar)</label>
            <input
              type="number"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="100"
              min="100"
              className="w-full mt-0.5 px-3 py-2 rounded-xl bg-card border border-border outline-none text-sm focus:border-primary/50 transition-colors"
            />
            {/* Quick amounts */}
            <div className="flex gap-1.5 mt-1.5">
              {[500, 1000, 5000, 10000].map(amt => (
                <button
                  key={amt}
                  onClick={() => setAmount(String(amt))}
                  className="flex-1 px-1 py-1 rounded-lg bg-secondary/60 text-xs font-semibold hover:bg-primary/10 hover:text-primary transition-colors"
                >
                  {amt.toLocaleString("fr-FR")}
                </button>
              ))}
            </div>
          </div>

          {/* Transfer button */}
          <button
            onClick={doTransfer}
            disabled={sending || !recipient.trim() || !amount}
            className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-bold active:scale-95 transition-transform disabled:opacity-50 disabled:active:scale-100 flex items-center justify-center gap-1.5"
          >
            {sending ? (
              <span className="animate-pulse">Envoi en cours…</span>
            ) : (
              <><Send className="w-3.5 h-3.5" /> Envoyer</>
            )}
          </button>

          <p className="text-[10px] text-muted-foreground text-center leading-tight">
            Transfert instantané · Min 100 Ar · Max 500 000 Ar
          </p>
        </div>
      </DialogContent>
    </Dialog>
  );
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
  const [playerStats, setPlayerStats] = useState<any>(null);
  const [gameStats, setGameStats] = useState<Record<string, { played: number; wins: number }>>({});
  const [myRank, setMyRank] = useState<number | null>(null);
  const [rankLoaded, setRankLoaded] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [achievements, setAchievements] = useState<any[]>([]);
  const [showHistory, setShowHistory] = useState<"none" | "deposits" | "withdrawals" | "games">("none");
  const [deps, setDeps] = useState<any[]>([]);
  const [withs, setWiths] = useState<any[]>([]);
  const [showTransfer, setShowTransfer] = useState(false);

  useEffect(() => { setPseudo(profile?.pseudo || ""); }, [profile?.pseudo]);

  useEffect(() => {
    if (!user) return;
    const uid = user.id;
    const currentPseudo = profile?.pseudo;

    supabase.from("transactions").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(50).then(({ data }) => setTx(data || []));
    supabase.from("deposits").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(30).then(({ data }) => setDeps(data || []));
    supabase.from("withdrawals").select("*").eq("user_id", uid).order("created_at", { ascending: false }).limit(30).then(({ data }) => setWiths(data || []));
    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => { if (data) setPlayerStats(data); });

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
      setRankLoaded(true);
      if (!data) return;
      const idx = (data as any[]).findIndex((r: any) => r.id === uid || (currentPseudo && r.name === currentPseudo));
      if (idx >= 0) setMyRank((data[idx] as any).rank);
    });
    supabase.rpc("get_player_achievements" as any, { _uid: uid } as any).then(({ data }: any) => setAchievements(data || []));
  }, [user?.id, profile?.pseudo]);

  const savePseudo = async () => {
    if (!pseudo.trim() || pseudo === profile?.pseudo) { setEditingName(false); return; }
    const { error } = await supabase.from("profiles").update({ pseudo: pseudo.trim() }).eq("id", user!.id);
    if (error) return toast.error(error.message);
    toast.success("Pseudo mis à jour"); refreshProfile(); setEditingName(false);
  };

  const upload = async (rawFile: File) => {
    if (!user || !rawFile) return;
    setUploading(true);
    const f = await compressImageToWebp(rawFile, { maxDim: 512, maxSizeKB: 200 });
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
  const level = ps.player_level || p.level || 1;
  const badge = getBadge(level);
  const memberDays = Math.max(1, Math.floor((Date.now() - new Date(p.created_at).getTime()) / 86400000));
  const totalGames = ps.total_games ?? p.total_games ?? 0;
  const totalWins = ps.total_wins ?? p.total_wins ?? 0;
  const totalLosses = totalGames - totalWins;
  const winRate = totalGames > 0 ? Math.round((totalWins / totalGames) * 100) : 0;

  const gameTx = tx.filter(tr => ["stake", "win", "refund", "forfeit", "transfer_sent", "transfer_received"].includes(tr.type));

  const ACHIEVEMENT_SLOTS = ["first_game", "first_win", "streak_3", "streak_5", "high_roller", "first_deposit", "social", "champion"] as const;
  const ACHIEVEMENT_ICONS: Record<string, { icon: string; label: string }> = {
    first_game: { icon: "🎮", label: "1ère partie" },
    first_win: { icon: "🏆", label: "1ère victoire" },
    streak_3: { icon: "🔥", label: "3 victoires" },
    streak_5: { icon: "⚡", label: "5 d'affilée" },
    high_roller: { icon: "💰", label: "Gros joueur" },
    first_deposit: { icon: "🏆", label: "1er dépôt" },
    social: { icon: "👥", label: "Social" },
    champion: { icon: "👑", label: "Champion" },
  };

  return (
    <main className="mx-auto max-w-md flex flex-col gap-2 p-3 pb-20 min-h-screen">
      <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />

      {showDeleteDialog && <DeleteAccountDialog open={showDeleteDialog} onClose={() => setShowDeleteDialog(false)} />}

      <TransferDialog
        open={showTransfer}
        onClose={() => setShowTransfer(false)}
        balance={profile.balance_ar}
        onSent={refreshProfile}
      />

      <HistoryDialog open={showHistory === "deposits"} onClose={() => setShowHistory("none")}
        title="Dépôts" items={deps} emptyMsg="Aucun dépôt"
        renderItem={d => (
          <div key={d.id} className="flex items-center justify-between text-sm py-2 border-b border-border/20 last:border-0">
            <span className="text-muted-foreground">{new Date(d.created_at).toLocaleDateString("fr-FR")}</span>
            <span className={`font-bold ${d.status === "approved" ? "text-emerald-600" : "text-amber-500"}`}>+{Math.round(Number(d.amount)).toLocaleString("fr-FR")} Ar</span>
          </div>
        )} />
      <HistoryDialog open={showHistory === "withdrawals"} onClose={() => setShowHistory("none")}
        title="Retraits" items={withs} emptyMsg="Aucun retrait"
        renderItem={w => (
          <div key={w.id} className="flex items-center justify-between text-sm py-2 border-b border-border/20 last:border-0">
            <span className="text-muted-foreground">{new Date(w.created_at).toLocaleDateString("fr-FR")}</span>
            <span className={`font-bold ${w.status === "approved" ? "text-emerald-600" : "text-amber-500"}`}>-{Math.round(Number(w.amount)).toLocaleString("fr-FR")} Ar</span>
          </div>
        )} />
      <HistoryDialog open={showHistory === "games"} onClose={() => setShowHistory("none")}
        title="Parties récentes" items={gameTx} emptyMsg="Aucune partie"
        renderItem={tr => (
          <div key={tr.id} className="flex items-center justify-between text-sm py-2 border-b border-border/20 last:border-0">
            <span className="flex items-center gap-1.5">
              {tr.type === "win" ? "🏆" : tr.type === "stake" ? "🎮" : tr.type === "transfer_sent" ? "📤" : tr.type === "transfer_received" ? "📥" : "↩️"} {labelType(tr.type, t)}
            </span>
            <span className={`font-bold ${Number(tr.amount) >= 0 ? "text-emerald-600" : "text-destructive"}`}>
              {Number(tr.amount) >= 0 ? "+" : ""}{Math.round(Number(tr.amount)).toLocaleString("fr-FR")} Ar
            </span>
          </div>
        )} />

      {/* ════ SECTION 1: Profile Header — Modern Card ════ */}
      <div className="relative rounded-3xl overflow-hidden shrink-0 shadow-lg"
        style={{ background: "linear-gradient(135deg, var(--card) 0%, var(--secondary) 100%)" }}>

        {/* Decorative top banner with gradient */}
        <div className={`h-16 bg-gradient-to-br ${badge.color} relative overflow-hidden`}>
          <div className="absolute inset-0 opacity-20"
            style={{ backgroundImage: "radial-gradient(circle at 20% 50%, white 1px, transparent 1px), radial-gradient(circle at 80% 30%, white 1px, transparent 1px)", backgroundSize: "24px 24px" }} />
        </div>

        {/* Avatar overlapping the banner */}
        <div className="px-4 -mt-8 pb-3">
          <div className="flex items-end gap-3">
            <div className="relative shrink-0">
              <div className={`w-16 h-16 rounded-2xl p-[3px] bg-gradient-to-br ${badge.color} shadow-lg`}>
                <div className="w-full h-full rounded-xl bg-card flex items-center justify-center text-xl font-black overflow-hidden ring-1 ring-card">
                  {profile.avatar_url
                    ? <img src={profile.avatar_url} alt="" className="w-full h-full object-cover rounded-xl" />
                    : <span className="text-primary">{initials}</span>}
                </div>
              </div>
              <button onClick={() => fileRef.current?.click()} disabled={uploading}
                className="absolute -bottom-1 -right-1 p-1 rounded-full bg-primary text-primary-foreground ring-2 ring-card active:scale-90 transition-transform shadow-md">
                <Camera className="w-3 h-3" strokeWidth={2.5} />
              </button>
            </div>

            <div className="flex-1 min-w-0 pb-1">
              {editingName ? (
                <div className="flex gap-1">
                  <input value={pseudo} onChange={e => setPseudo(e.target.value)} onKeyDown={e => e.key === "Enter" && savePseudo()} autoFocus
                    className="flex-1 px-2 py-1 rounded-lg bg-card border border-border outline-none text-sm font-bold" />
                  <button onClick={savePseudo} className="px-3 py-1 rounded-lg bg-primary text-primary-foreground text-xs font-bold">OK</button>
                </div>
              ) : (
                <button onClick={() => setEditingName(true)} className="font-black text-lg leading-tight hover:text-primary transition-colors break-words text-left w-full line-clamp-2">
                  {profile.pseudo}
                </button>
              )}
              <div className="flex items-center gap-1.5 mt-0.5">
                {p.phone_verified ? (
                  <span className="inline-flex items-center gap-0.5 text-[10px] font-semibold text-emerald-500">
                    <ShieldCheck className="w-3 h-3" /> Vérifié
                  </span>
                ) : (
                  <span className="inline-flex items-center gap-0.5 text-[10px] font-semibold text-amber-500">
                    <ShieldAlert className="w-3 h-3" /> Non vérifié
                  </span>
                )}
                <span className="text-[10px] text-muted-foreground">· {memberDays}j</span>
                {profile.unique_code && (
                  <button onClick={() => copyText(profile.unique_code!).then(ok => toast[ok ? "success" : "error"](ok ? "ID copié !" : "Erreur"))}
                    className="inline-flex items-center gap-0.5 text-[10px] text-muted-foreground font-mono hover:text-foreground transition-colors">
                    {profile.unique_code} <Copy className="w-2.5 h-2.5" />
                  </button>
                )}
              </div>
            </div>
          </div>

          {/* Contact info row */}
          <div className="flex items-center gap-3 mt-2 text-[11px] text-muted-foreground">
            {profile.email && (
              <span className="inline-flex items-center gap-1 truncate">
                <Mail className="w-3 h-3 shrink-0 text-primary/60" /> <span className="truncate">{profile.email}</span>
              </span>
            )}
            {p.phone && (
              <span className="inline-flex items-center gap-1 truncate">
                <Phone className="w-3 h-3 shrink-0 text-primary/60" /> <span className="truncate">{p.phone}</span>
              </span>
            )}
          </div>

          {/* Balance card */}
          <div className="mt-3 rounded-2xl bg-gradient-to-r from-primary/10 to-primary/5 border border-primary/20 px-4 py-2.5 flex items-center justify-between">
            <div>
              <div className="flex items-center gap-1 text-[10px] text-muted-foreground font-semibold uppercase tracking-wide">
                <Coins className="w-3 h-3 text-primary" /> Solde
              </div>
              <div className="text-2xl font-black text-primary tabular-nums leading-tight mt-0.5">
                {Math.round(profile.balance_ar).toLocaleString("fr-FR")}
                <span className="text-xs font-bold text-muted-foreground ml-1">Ar</span>
              </div>
            </div>
            <div className="text-right">
              <div className="text-[10px] text-muted-foreground font-semibold uppercase tracking-wide">Niveau</div>
              <div className="text-2xl font-black leading-tight mt-0.5">{level}</div>
            </div>
          </div>
        </div>
      </div>

      {/* ════ SECTION 2: Stats (5 tiles) ════ */}
      <div className="flex gap-1.5 shrink-0">
        <MiniStat label="Parties" value={totalGames} icon="🎮" />
        <MiniStat label="Victoires" value={totalWins} icon="🏆" color="text-emerald-500" />
        <MiniStat label="Défaites" value={totalLosses} icon="📉" color="text-destructive" />
        <MiniStat label="Win rate" value={`${winRate}%`} icon="📊" color={winRate >= 50 ? "text-emerald-500" : "text-amber-500"} />
        <MiniStat label="Rang" value={rankLoaded ? (myRank ?? "—") : "…"} icon="🥇" color={myRank && myRank <= 10 ? "text-amber-500" : "text-foreground"} />
      </div>

      {/* ════ SECTION 3: Jeux favoris ════ */}
      <div className="rounded-xl border border-border/40 bg-card px-3 py-2.5 shrink-0">
        <div className="text-[9px] font-bold uppercase tracking-wider text-muted-foreground mb-2">Jeux favoris</div>
        <div className="grid grid-cols-5 gap-1.5">
          {[
            { k: "ludo", icon: "🎲", name: "Ludo" },
            { k: "domino", icon: "🁣", name: "Domino" },
            { k: "fanorona", icon: "♟", name: "Fanorona" },
            { k: "rami", icon: "🃏", name: "Rami" },
            { k: "chess", icon: "♜", name: "Échecs" },
          ].map(g => {
            const played = gameStats[g.k]?.played || 0;
            const active = played > 0;
            return (
              <div
                key={g.k}
                className={`flex flex-col items-center gap-0.5 rounded-lg py-1.5 transition-colors ${active ? "bg-primary/10" : "bg-secondary/30"}`}
              >
                <span className={`text-lg leading-none ${active ? "" : "grayscale opacity-40"}`}>{g.icon}</span>
                <span className={`text-[13px] font-black tabular-nums leading-none ${active ? "text-primary" : "text-muted-foreground/50"}`}>
                  {played}
                </span>
                <span className="text-[8px] font-semibold text-muted-foreground truncate max-w-full leading-tight">{g.name}</span>
              </div>
            );
          })}
        </div>
      </div>

      {/* ════ SECTION 4: Menu + Actions ════ */}
      <div className="flex flex-col gap-2">
        {/* Menu grid 4x2 */}
        <div className="grid grid-cols-4 gap-1.5">
          <MenuButton icon={ArrowDownLeft} label="Dépôts" color="text-emerald-500"
            action={() => setShowHistory(showHistory === "deposits" ? "none" : "deposits")} />
          <MenuButton icon={ArrowUpRight} label="Retraits" color="text-rose-500"
            action={() => setShowHistory(showHistory === "withdrawals" ? "none" : "withdrawals")} />
          <MenuButton icon={Gamepad2} label="Parties" color="text-primary"
            action={() => setShowHistory(showHistory === "games" ? "none" : "games")} />
          <MenuButton icon={Send} label="Transfert" color="text-primary"
            action={() => setShowTransfer(true)} />
          <MenuButton icon={Gift} label="Parrainage" color="text-fuchsia-500"
            action={() => navigate({ to: "/parrainage", search: {} })} />
          <MenuButton icon={Shield} label="Sécurité" color="text-emerald-500"
            action={() => navigate({ to: "/parametres", search: {} })} />
          <MenuButton icon={HelpCircle} label="Aide" color="text-orange-500 dark:text-neutral-300"
            action={() => navigate({ to: "/faq", search: {} })} />
          <MenuButton icon={Settings} label="Paramètres" color="text-muted-foreground"
            action={() => navigate({ to: "/parametres", search: {} })} />
        </div>

        {/* Logout + delete */}
        <div className="mt-1 grid grid-cols-2 gap-1.5">
          <button onClick={async () => { await signOut(); navigate({ to: "/login" }); }}
            className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/10 text-destructive text-xs font-semibold active:scale-95 transition-transform">
            <LogOut className="w-3.5 h-3.5" /> Déconnexion
          </button>
          <button onClick={() => setShowDeleteDialog(true)}
            className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/5 text-destructive/80 text-xs font-semibold active:scale-95 transition-transform">
            <Trash2 className="w-3.5 h-3.5" /> Supprimer
          </button>
        </div>
      </div>
    </main>
  );
}
