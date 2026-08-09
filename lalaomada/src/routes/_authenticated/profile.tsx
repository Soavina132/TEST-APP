import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { copyText } from "@/lib/clipboard";
import { useEffect, useRef, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  Camera, Copy, ShieldCheck, ShieldAlert, LogOut, Trash2,
  Phone, Gamepad2, ArrowDownLeft, ArrowUpRight, Gift, Send,
  HelpCircle, Shield, ChevronRight, Settings, Trophy, Zap, FileText, Crown, Calendar,
} from "lucide-react";
import { DeleteAccountDialog } from "@/components/DeleteAccountDialog";
import { compressImageToWebp } from "@/lib/image-compress";
import { DepotModal, RetraitModal, useAppSettings } from "@/components/WalletButton";
import {
  Dialog, DialogContent, DialogHeader, DialogTitle,
} from "@/components/ui/dialog";
import { MatchListDialog, useAllMatches } from "@/components/game/MatchStatsDialog";
import PremiumSubscriptionModal from "@/components/PremiumSubscriptionModal";

export const Route = createFileRoute("/_authenticated/profile")({
  component: ProfilePage,
  head: () => ({ meta: [
    { title: "Mon profil — Lalao MADA" },
    { name: "description", content: "Profil joueur Lalao MADA : statistiques, jeux, classement et historique." },
  ] }),
});

/* ────────────────────────────────────────────────────────────────────────────
   Constants & Helpers
─────────────────────────────────────────────────────────────────────────────── */

const BADGES = [
  { min: 0, label: "Bronze", color: "from-amber-700 to-amber-500", icon: "🥉" },
  { min: 2, label: "Argent", color: "from-slate-400 to-slate-300", icon: "🥈" },
  { min: 3, label: "Or", color: "from-yellow-500 to-amber-400", icon: "🥇" },
  { min: 4, label: "Diamant", color: "from-cyan-400 to-blue-500", icon: "💎" },
  { min: 5, label: "Platine", color: "from-violet-500 to-fuchsia-500", icon: "👑" },
];

function getBadge(level: number) {
  let b = BADGES[0];
  for (const bd of BADGES) if (level >= bd.min) b = bd;
  return b;
}

const MIN_WITHDRAWAL = 2000;

/* ────────────────────────────────────────────────────────────────────────────
   Transfer Dialog
─────────────────────────────────────────────────────────────────────────────── */

function TransferDialog({ open, onClose, balance, onSent }: {
  open: boolean; onClose: () => void; balance: number; onSent: () => void;
}) {
  const [recipient, setRecipient] = useState("");
  const [amount, setAmount] = useState("");
  const [sending, setSending] = useState(false);
  const [searchResults, setSearchResults] = useState<any[]>([]);
  const [searching, setSearching] = useState(false);

  useEffect(() => {
    if (!recipient.trim() || recipient.trim().length < 2) { setSearchResults([]); return; }
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
        _recipient: recipient.trim(), _amount: amt,
      } as any);
      if (error) throw error;
      toast.success(`Transfert de ${amt.toLocaleString("fr-FR")} Ar envoyé à ${data?.recipient || recipient} !`);
      setRecipient(""); setAmount(""); setSearchResults([]);
      onSent(); onClose();
    } catch (e: any) {
      toast.error(e.message || "Erreur lors du transfert");
    } finally { setSending(false); }
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
          <div className="rounded-xl bg-primary/5 border border-primary/20 px-3 py-2 text-center">
            <span className="text-[10px] text-muted-foreground uppercase font-semibold">Solde actuel</span>
            <div className="text-xl font-black text-primary tabular-nums">
              {Math.round(balance).toLocaleString("fr-FR")} <span className="text-xs">Ar</span>
            </div>
          </div>
          <div className="relative">
            <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">Destinataire</label>
            <input value={recipient} onChange={(e) => setRecipient(e.target.value)}
              placeholder="Numéro de téléphone ou pseudo"
              className="w-full mt-0.5 px-3 py-2 rounded-xl bg-card border border-border outline-none text-sm focus:border-primary/50 transition-colors"
              autoFocus />
            {searchResults.length > 0 && (
              <div className="absolute z-10 mt-1 w-full rounded-xl border border-border bg-popover shadow-lg overflow-hidden">
                {searchResults.map((u) => (
                  <button key={u.id} onClick={() => { setRecipient(u.phone || u.pseudo); setSearchResults([]); }}
                    className="w-full flex items-center gap-2 px-3 py-2 hover:bg-accent/30 transition-colors text-left border-b border-border/20 last:border-0">
                    {u.avatar_url
                      ? <img src={u.avatar_url} alt="" className="w-7 h-7 rounded-full object-cover" />
                      : <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary">
                          {(u.pseudo || "?").slice(0, 2).toUpperCase()}
                        </div>}
                    <div className="flex-1 min-w-0">
                      <div className="text-sm font-semibold truncate">{u.pseudo}</div>
                      {u.phone && <div className="text-[10px] text-muted-foreground truncate">{u.phone}</div>}
                    </div>
                  </button>
                ))}
              </div>
            )}
            {searching && <div className="absolute z-10 mt-1 w-full text-center text-xs text-muted-foreground py-1">Recherche…</div>}
          </div>
          <div>
            <label className="text-[10px] font-semibold text-muted-foreground uppercase tracking-wide">Montant (Ar)</label>
            <input type="number" value={amount} onChange={(e) => setAmount(e.target.value)}
              placeholder="100" min="100"
              className="w-full mt-0.5 px-3 py-2 rounded-xl bg-card border border-border outline-none text-sm focus:border-primary/50 transition-colors" />
            <div className="flex gap-1.5 mt-1.5">
              {[500, 1000, 5000, 10000].map(amt => (
                <button key={amt} onClick={() => setAmount(String(amt))}
                  className="flex-1 px-1 py-1 rounded-lg bg-secondary/60 text-xs font-semibold hover:bg-primary/10 hover:text-primary transition-colors">
                  {amt.toLocaleString("fr-FR")}
                </button>
              ))}
            </div>
          </div>
          <button onClick={doTransfer} disabled={sending}
            className="w-full flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-bold active:scale-95 transition-transform disabled:opacity-50">
            {sending ? "Envoi…" : <><Send className="w-3.5 h-3.5" /> Envoyer</>}
          </button>
          <p className="text-[10px] text-muted-foreground text-center leading-tight">
            Transfert instantané · Min 100 Ar · Max 500 000 Ar
          </p>
        </div>
      </DialogContent>
    </Dialog>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Section wrapper
─────────────────────────────────────────────────────────────────────────────── */

function Section({ icon: Icon, title, children }: {
  icon: any; title: string; children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl bg-card border border-border/40 overflow-hidden">
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30">
        <Icon className="w-4 h-4 text-primary" />
        <span className="font-bold text-sm">{title}</span>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Stat Tile
─────────────────────────────────────────────────────────────────────────────── */

function StatTile({ label, value, icon, accent }: {
  label: string; value: string | number; icon: React.ReactNode; accent?: string;
}) {
  return (
    <div className="flex flex-col items-center justify-center rounded-xl bg-secondary/40 p-2 text-center">
      <div className="mb-0.5 text-muted-foreground [&>svg]:w-4 [&>svg]:h-4">{icon}</div>
      <div className={`text-base font-black tabular-nums leading-none ${accent || "text-foreground"}`}>{value}</div>
      <div className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5">{label}</div>
    </div>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Action button — used in the balance card row (icon over label, no box)
─────────────────────────────────────────────────────────────────────────────── */

function BalanceAction({ icon: Icon, label, action }: {
  icon: any; label: string; action: () => void;
}) {
  return (
    <button onClick={action}
      className="flex flex-col items-center gap-1.5 py-3 flex-1 hover:bg-primary/5 active:scale-95 transition-all">
      <Icon className="w-5 h-5 text-primary" strokeWidth={2} />
      <span className="text-[11px] font-semibold text-foreground/80">{label}</span>
    </button>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   List row — simple menu row (icon + label + chevron)
─────────────────────────────────────────────────────────────────────────────── */

function ListRow({ icon: Icon, label, action, color, danger }: {
  icon: any; label: string; action: () => void; color?: string; danger?: boolean;
}) {
  return (
    <button onClick={action}
      className={`w-full flex items-center gap-3 px-1 py-3 border-b border-border/20 last:border-0 hover:bg-accent/20 active:scale-[0.99] transition-all ${danger ? "text-destructive" : ""}`}>
      <Icon className={`w-5 h-5 ${color || "text-primary"}`} strokeWidth={2} />
      <span className="flex-1 text-left text-sm font-semibold">{label}</span>
      {!danger && <ChevronRight className="w-4 h-4 text-muted-foreground" />}
    </button>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Main Page
─────────────────────────────────────────────────────────────────────────────── */

/* ────────────────────────────────────────────────────────────────────────────
   Main Page
─────────────────────────────────────────────────────────────────────────────── */

/* ────────────────────────────────────────────────────────────────────────────
   Subscription Section — shows current plan + details + subscribe button
─────────────────────────────────────────────────────────────────────────────── */

const TIER_INFO: Record<string, { label: string; price: number; matches: number; color: string; icon: string }> = {
  starter:  { label: "Starter",  price: 500,  matches: 50,  color: "#10b981", icon: "🌱" },
  basic:    { label: "Basic",    price: 1000, matches: 100, color: "#3b82f6", icon: "⭐" },
  standard: { label: "Standard", price: 2000, matches: 200, color: "#8b5cf6", icon: "🚀" },
  premium:  { label: "Premium",  price: 5000, matches: 500, color: "#f59e0b", icon: "👑" },
};

function SubscriptionSection({ limits, premiumTier, premiumUntil, balance, onSubscribe }: {
  limits: any; premiumTier: string | null; premiumUntil: string | null; balance: number; onSubscribe: () => void;
}) {
  const isPremium = premiumUntil && new Date(premiumUntil) > new Date();
  const tier = premiumTier && TIER_INFO[premiumTier] ? TIER_INFO[premiumTier] : null;

  // Calculate days remaining
  const daysLeft = isPremium
    ? Math.ceil((new Date(premiumUntil!).getTime() - Date.now()) / (1000 * 60 * 60 * 24))
    : 0;

  // From get_game_limits RPC
  const remainingMonthly = limits?.remaining_monthly ?? 0;
  const monthlyLimit = limits?.monthly_limit ?? 0;
  const monthlyUsed = limits?.monthly_used ?? 0;
  const remainingToday = limits?.remaining_today ?? 0;
  const activeDaysUsed = limits?.active_days_used ?? 0;
  const maxActiveDays = limits?.max_active_days ?? 5;

  return (
    <div className="rounded-2xl bg-card border border-border/40 overflow-hidden">
      {/* Header */}
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30">
        <Crown className="w-4 h-4 text-amber-500" />
        <span className="font-bold text-sm">Abonnement</span>
        {isPremium && (
          <span className="ml-auto px-2 py-0.5 rounded-full text-[10px] font-bold text-white"
            style={{ background: tier?.color || "#f59e0b" }}>
            ACTIF
          </span>
        )}
      </div>

      <div className="p-4 space-y-3">
        {isPremium && tier ? (
          <>
            {/* Active subscription card */}
            <div className="rounded-xl p-3 border" style={{ borderColor: `${tier.color}40`, background: `linear-gradient(135deg, ${tier.color}12, transparent)` }}>
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="w-9 h-9 rounded-xl flex items-center justify-center text-lg"
                    style={{ background: tier.color }}>
                    {tier.icon}
                  </div>
                  <div>
                    <div className="font-black text-sm">{tier.label}</div>
                    <div className="text-[10px] text-muted-foreground">{tier.matches} parties / mois</div>
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-xs font-bold" style={{ color: tier.color }}>{daysLeft} jours</div>
                  <div className="text-[10px] text-muted-foreground">restants</div>
                </div>
              </div>
            </div>

            {/* Details grid */}
            <div className="grid grid-cols-2 gap-2">
              <div className="rounded-xl bg-secondary/40 p-2.5 text-center">
                <div className="text-lg font-black tabular-nums" style={{ color: tier.color }}>{remainingMonthly}</div>
                <div className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Parties restantes (mois)</div>
              </div>
              <div className="rounded-xl bg-secondary/40 p-2.5 text-center">
                <div className="text-lg font-black tabular-nums">{remainingToday}</div>
                <div className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Gratuites aujourd'hui</div>
              </div>
              <div className="rounded-xl bg-secondary/40 p-2.5 text-center">
                <div className="text-lg font-black tabular-nums">{monthlyUsed}</div>
                <div className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Parties jouées (mois)</div>
              </div>
              <div className="rounded-xl bg-secondary/40 p-2.5 text-center">
                <div className="text-lg font-black tabular-nums">{activeDaysUsed}/{maxActiveDays}</div>
                <div className="text-[9px] font-semibold uppercase tracking-wide text-muted-foreground">Jours actifs</div>
              </div>
            </div>

            {/* Expiry date */}
            <div className="flex items-center gap-2 text-xs text-muted-foreground px-1">
              <Calendar className="w-3.5 h-3.5" />
              <span>Expire le {new Date(premiumUntil!).toLocaleDateString("fr-FR", { day: "numeric", month: "long", year: "numeric" })}</span>
            </div>

            {/* Renew button */}
            <button onClick={onSubscribe}
              className="w-full py-2.5 rounded-xl text-white text-sm font-bold flex items-center justify-center gap-2 active:scale-95 transition-transform"
              style={{ background: `linear-gradient(135deg, ${tier.color}, ${tier.color}dd)` }}>
              <Crown className="w-4 h-4" /> Renouveler
            </button>
          </>
        ) : (
          <>
            {/* No active subscription */}
            <div className="text-center py-2">
              <div className="w-12 h-12 rounded-full bg-secondary/60 flex items-center justify-center mx-auto mb-2">
                <Crown className="w-6 h-6 text-muted-foreground" />
              </div>
              <div className="font-bold text-sm">Aucun abonnement actif</div>
              <div className="text-[11px] text-muted-foreground mt-0.5">
                {activeDaysUsed >= maxActiveDays
                  ? "Essai gratuit expiré — abonnez-vous pour continuer"
                  : `Essai gratuit: ${remainingToday} parties aujourd'hui`}
              </div>
              <div className="text-[10px] text-muted-foreground mt-1">
                Jours actifs: {activeDaysUsed}/{maxActiveDays}
              </div>
            </div>

            {/* Plan previews */}
            <div className="space-y-1.5">
              {Object.values(TIER_INFO).map((t) => (
                <div key={t.id} className="flex items-center gap-2 rounded-lg bg-secondary/30 px-2.5 py-2">
                  <div className="w-7 h-7 rounded-lg flex items-center justify-center text-sm shrink-0"
                    style={{ background: t.color }}>
                    {t.icon}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="text-xs font-bold">{t.label}</div>
                    <div className="text-[10px] text-muted-foreground">{t.matches} parties/mois</div>
                  </div>
                  <div className="text-right">
                    <div className="text-sm font-black">{t.price.toLocaleString("fr-FR")}</div>
                    <div className="text-[9px] text-muted-foreground">Ar/mois</div>
                  </div>
                </div>
              ))}
            </div>

            {/* Subscribe button */}
            <button onClick={onSubscribe}
              className="w-full py-2.5 rounded-xl bg-gradient-to-r from-amber-500 to-orange-600 text-white text-sm font-bold flex items-center justify-center gap-2 active:scale-95 transition-transform shadow-md">
              <Crown className="w-4 h-4" /> S'abonner maintenant
            </button>
          </>
        )}
      </div>
    </div>
  );
}

/* ────────────────────────────────────────────────────────────────────────────
   Main Page
─────────────────────────────────────────────────────────────────────────────── */

function ProfilePage() {
  const { user, profile, refreshProfile, signOut } = useAuth();
  const navigate = useNavigate();
  const [pseudo, setPseudo] = useState(profile?.pseudo || "");
  const [editingName, setEditingName] = useState(false);
  const [uploading, setUploading] = useState(false);
  const [playerStats, setPlayerStats] = useState<any>(null);
  const [myRank, setMyRank] = useState<number | null>(null);
  const [rankLoaded, setRankLoaded] = useState(false);
  const fileRef = useRef<HTMLInputElement>(null);
  const [showDeleteDialog, setShowDeleteDialog] = useState(false);
  const [showDeposit, setShowDeposit] = useState(false);
  const [showRetrait, setShowRetrait] = useState(false);
  const [showTransfer, setShowTransfer] = useState(false);
  const [showSubscription, setShowSubscription] = useState(false);
  const [gameLimits, setGameLimits] = useState<any>(null);
  const appSettings = useAppSettings();
  const [statsDialog, setStatsDialog] = useState<"all" | "wins" | "losses" | null>(null);
  const { matches, loaded: matchesLoaded, loading: matchesLoading, load: loadMatches } = useAllMatches(user?.id);
  const openStats = (type: "all" | "wins" | "losses") => {
    setStatsDialog(type);
    if (!matchesLoaded) loadMatches();
  };

  useEffect(() => { setPseudo(profile?.pseudo || ""); }, [profile?.pseudo]);

  useEffect(() => {
    if (!user) return;
    const uid = user.id;
    const currentPseudo = profile?.pseudo;

    supabase.from("v_player_stats" as any).select("*").eq("id", uid).maybeSingle().then(({ data }: any) => { if (data) setPlayerStats(data); });

    supabase.rpc("leaderboard_winners" as any, { _limit: 200 } as any).then(({ data }: any) => {
      setRankLoaded(true);
      if (!data) return;
      const idx = (data as any[]).findIndex((r: any) => r.id === uid || (currentPseudo && r.name === currentPseudo));
      if (idx >= 0) setMyRank((data[idx] as any).rank);
    });

    // Fetch subscription / game limits
    supabase.rpc("get_game_limits" as any).then(({ data }: any) => {
      if (data && !data.error) setGameLimits(data);
    });
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
  const displayName = profile.pseudo || user?.email?.split("@")[0] || "Joueur";
  const initials = displayName.slice(0, 2).toUpperCase();
  const totalWins = ps.total_wins ?? p.total_wins ?? 0;
  const totalGames = ps.total_games ?? p.total_games ?? 0;
  const level = ps.player_level ?? 1;
  const winRate = totalGames > 0 ? Math.round((totalWins / totalGames) * 100) : 0;
  const totalLosses = totalGames - totalWins;
  const badge = getBadge(level);

  return (
    <main className="mx-auto max-w-md flex flex-col gap-3 p-3 pb-20 min-h-screen">

      <input ref={fileRef} type="file" accept="image/*" className="hidden"
        onChange={(e) => e.target.files?.[0] && upload(e.target.files[0])} />

      {showDeleteDialog && <DeleteAccountDialog open={showDeleteDialog} onClose={() => setShowDeleteDialog(false)} />}

      <DepotModal
        open={showDeposit}
        onClose={() => setShowDeposit(false)}
        mvolaPhone={appSettings.mvolaPhone}
        mvolaName={appSettings.mvolaName}
        orangePhone={appSettings.orangePhone}
        orangeName={appSettings.orangeName}
        airtelPhone={appSettings.airtelPhone}
        airtelName={appSettings.airtelName}
        minDeposit={appSettings.minDeposit}
        onSuccess={() => { refreshProfile(); }}
      />

      <RetraitModal
        open={showRetrait}
        onClose={() => setShowRetrait(false)}
        balance={profile.balance_ar}
        minRetrait={MIN_WITHDRAWAL}
        onSuccess={() => { refreshProfile(); }}
      />

      {/* ═══════════════════════════════════════════════════════════════════
         1.  Identity — simple card: avatar + name + verified badge + phone
      ═══════════════════════════════════════════════════════════════════ */}
      <div className="rounded-2xl bg-card border border-border/40 p-4 flex items-center gap-3">
        <div className="relative shrink-0">
          <div className={`w-16 h-16 rounded-full p-[2px] bg-gradient-to-br ${badge.color}`}>
            <div className="w-full h-full rounded-full bg-secondary flex items-center justify-center text-lg font-black overflow-hidden">
              {profile.avatar_url
                ? <img src={profile.avatar_url} alt="" className="w-full h-full object-cover rounded-full" />
                : <span className="text-primary">{initials}</span>}
            </div>
          </div>
          <button onClick={() => fileRef.current?.click()} disabled={uploading}
            className="absolute -bottom-1 -right-1 p-1.5 rounded-full bg-primary text-primary-foreground ring-2 ring-card active:scale-90 transition-transform shadow-md">
            <Camera className="w-3 h-3" strokeWidth={2.5} />
          </button>
        </div>

        <div className="flex-1 min-w-0">
          {editingName ? (
            <div className="flex gap-1">
              <input value={pseudo} onChange={e => setPseudo(e.target.value)}
                onKeyDown={e => e.key === "Enter" && savePseudo()} autoFocus
                className="flex-1 px-2 py-1 rounded-lg bg-card border border-border outline-none text-sm font-bold" />
              <button onClick={savePseudo}
                className="px-3 py-1 rounded-lg bg-primary text-primary-foreground text-xs font-bold">OK</button>
            </div>
          ) : (
            <button onClick={() => setEditingName(true)}
              className="flex items-center gap-1.5 hover:text-primary transition-colors">
              <span className="font-black text-lg leading-tight truncate">{displayName}</span>
              {p.phone_verified
                ? <ShieldCheck className="w-4 h-4 text-emerald-500 shrink-0" />
                : <ShieldAlert className="w-4 h-4 text-amber-500 shrink-0" />}
            </button>
          )}
          {p.phone && (
            <div className="flex items-center gap-1.5 mt-1 text-sm text-muted-foreground">
              <Phone className="w-3.5 h-3.5 shrink-0" />
              <span className="truncate">{p.phone}</span>
            </div>
          )}
          {profile.unique_code && (
            <button onClick={() => copyText(profile.unique_code!).then(ok => toast[ok ? "success" : "error"](ok ? "ID copié !" : "Erreur"))}
              className="inline-flex items-center gap-0.5 text-[11px] text-muted-foreground font-mono hover:text-foreground transition-colors mt-0.5">
              ID: {profile.unique_code} <Copy className="w-3 h-3" />
            </button>
          )}
        </div>
      </div>

      {/* ═══════════════════════════════════════════════════════════════════
         2.  Balance — big, prominent, with quick actions row
      ═══════════════════════════════════════════════════════════════════ */}
      <div className="rounded-2xl overflow-hidden border border-primary/20"
        style={{ background: "linear-gradient(160deg, var(--primary) 0%, transparent 120%)", backgroundColor: "var(--card)" }}>
        <div className="px-4 py-3 flex items-center justify-between gap-2" style={{ background: "linear-gradient(135deg, color-mix(in oklch, var(--primary) 14%, var(--card)) 0%, color-mix(in oklch, var(--primary) 4%, var(--card)) 100%)" }}>
          <div>
            <div className="text-[10px] font-bold uppercase tracking-wide text-primary/80">Solde disponible</div>
            <div className="text-2xl font-black text-primary tabular-nums leading-tight mt-0.5">
              {Math.round(profile.balance_ar).toLocaleString("fr-FR")}
              <span className="text-sm font-bold text-muted-foreground ml-1">Ar</span>
            </div>
          </div>
          <button onClick={() => setShowTransfer(true)}
            className="flex items-center gap-1.5 px-3 py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold active:scale-95 transition-transform shadow-sm">
            <Send className="w-3.5 h-3.5" /> Transférer
          </button>
        </div>
        <div className="flex divide-x divide-primary/10 border-t border-primary/10">
          <BalanceAction icon={ArrowDownLeft} label="Dépôt" action={() => setShowDeposit(true)} />
          <BalanceAction icon={ArrowUpRight} label="Retrait" action={() => setShowRetrait(true)} />
          <BalanceAction icon={Gamepad2} label="Historique" action={() => navigate({ to: "/history", search: {} })} />
          <BalanceAction icon={Gift} label="Parrainage" action={() => navigate({ to: "/parrainage", search: {} })} />
        </div>
      </div>
      <TransferDialog
        open={showTransfer}
        onClose={() => setShowTransfer(false)}
        balance={Number(profile.balance_ar) || 0}
        onSent={refreshProfile}
      />

      {/* ═══════════════════════════════════════════════════════════════════
         3.  Statistics — tuiles cliquables directement (pas de page detail)
      ═══════════════════════════════════════════════════════════════════ */}
      <div className="rounded-2xl bg-card border border-border/40 overflow-hidden">
        <div className="flex items-center justify-between gap-2 px-4 py-2.5 border-b border-border/30 bg-secondary/30">
          <div className="flex items-center gap-2">
            <Trophy className="w-4 h-4 text-primary" />
            <span className="font-bold text-sm">Statistiques</span>
          </div>
          <span className="flex items-center gap-2 text-[10px] font-semibold text-muted-foreground">
            <span className="flex items-center gap-0.5">{badge.icon} Niv.{level}</span>
            <span className="flex items-center gap-0.5">🥇 {rankLoaded ? (myRank ?? "—") : "…"}</span>
          </span>
        </div>
        <div className="grid grid-cols-3 gap-1.5 p-3">
          <button onClick={() => openStats("all")}
            className="flex flex-col items-center justify-center rounded-lg bg-secondary/40 p-1.5 text-center active:scale-95 transition-transform">
            <Gamepad2 className="w-3.5 h-3.5 text-muted-foreground mb-0.5" />
            <div className="text-sm font-black tabular-nums leading-none">{totalGames}</div>
            <div className="text-[8px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5">Parties</div>
          </button>
          <button onClick={() => openStats("wins")}
            className="flex flex-col items-center justify-center rounded-lg bg-secondary/40 p-1.5 text-center active:scale-95 transition-transform">
            <Trophy className="w-3.5 h-3.5 text-emerald-500 mb-0.5" />
            <div className="text-sm font-black tabular-nums leading-none text-emerald-500">{totalWins}</div>
            <div className="text-[8px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5">Victoires</div>
          </button>
          <button onClick={() => openStats("losses")}
            className="flex flex-col items-center justify-center rounded-lg bg-secondary/40 p-1.5 text-center active:scale-95 transition-transform">
            <ChevronRight className="w-3.5 h-3.5 rotate-90 text-destructive mb-0.5" />
            <div className="text-sm font-black tabular-nums leading-none text-destructive">{totalLosses}</div>
            <div className="text-[8px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5">Défaites</div>
          </button>
        </div>
      </div>
      <MatchListDialog
        open={statsDialog !== null}
        onClose={() => setStatsDialog(null)}
        dialogType={statsDialog}
        matches={matches}
        loading={matchesLoading}
      />

      {/* ═══════════════════════════════════════════════════════════════════
         4.  Plus — simple list menu
      ═══════════════════════════════════════════════════════════════════ */}
      <Section icon={Settings} title="Plus">
        <div>
          <ListRow icon={Shield} label="Sécurité" color="text-emerald-500" action={() => navigate({ to: "/securite", search: {} } as any)} />
          <ListRow icon={HelpCircle} label="FAQ" color="text-orange-500 dark:text-neutral-300" action={() => navigate({ to: "/faq", search: {} })} />
          <ListRow icon={FileText} label="Conditions d'utilisation" color="text-sky-500" action={() => navigate({ to: "/cgu", search: {} } as any)} />
          <ListRow icon={ShieldCheck} label="Politique de confidentialité" color="text-sky-500" action={() => navigate({ to: "/confidentialite", search: {} } as any)} />
          <ListRow icon={Settings} label="Paramètres" color="text-muted-foreground" action={() => navigate({ to: "/parametres", search: {} })} />
          <ListRow icon={Crown} label="Abonnement" color="text-amber-500" action={() => setShowSubscription(true)} />
        </div>
      </Section>

      {/* Logout + delete */}
      <div className="grid grid-cols-2 gap-2">
        <button onClick={() => { void signOut(); window.location.assign("/login"); }}
          className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/10 text-destructive text-xs font-bold active:scale-95 transition-transform">
          <LogOut className="w-4 h-4" /> Déconnexion
        </button>
        <button onClick={() => setShowDeleteDialog(true)}
          className="flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/5 text-destructive/80 text-xs font-bold active:scale-95 transition-transform">
          <Trash2 className="w-4 h-4" /> Supprimer
        </button>
      </div>

      <PremiumSubscriptionModal
        open={showSubscription}
        onClose={() => { setShowSubscription(false); refreshProfile(); }}
      />

    </main>
  );
}
