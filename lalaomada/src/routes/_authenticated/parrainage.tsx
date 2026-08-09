import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import {
  Copy, Trophy, Users, Coins, Gift, ChevronDown,
  Share2, MessageCircle, Phone,
  CheckCircle2, Clock, Gamepad2, Sparkles,
} from "lucide-react";
import { PageLoader } from "@/components/layout/PageLoader";
import {
  REWARD_PER_ACTIVE_AR,
  MIN_DEPOSIT_AR,
  MIN_MATCHES,
  MIN_STAKE_AR,
  REFERRAL_TIERS,
  referralConditions,
  referralMetaDescription,
} from "@/lib/auth/referral-rules";

export const Route = createFileRoute("/_authenticated/parrainage")({
  component: ParrainagePage,
  head: () => ({
    meta: [
      { title: "Parrainage — Lalao MADA" },
      { name: "description", content: referralMetaDescription() },
    ],
  }),
});

type Tab = "filleuls" | "gains" | "classement";

// ── Status badge for a referral ─────────────────────────────────────────────
function referralStatusBadge(r: any): { label: string; color: string; icon: React.ReactNode } {
  if (r.status === "rewarded")
    return { label: "Actif ✅", color: "text-emerald-600", icon: <CheckCircle2 className="w-3 h-3" /> };
  if (!r.phone_verified)
    return { label: "Téléphone à vérifier", color: "text-amber-500", icon: <Phone className="w-3 h-3" /> };
  if (!r.deposit_validated)
    return { label: "Dépôt en attente", color: "text-orange-500", icon: <Clock className="w-3 h-3" /> };
  const matches = r.matches_completed || 0;
  return { label: `${matches}/${MIN_MATCHES} matchs`, color: "text-blue-500", icon: <Gamepad2 className="w-3 h-3" /> };
}

// ── Coin rain animation ──────────────────────────────────────────────────────
function CoinRain({ trigger }: { trigger: boolean }) {
  if (!trigger) return null;
  return (
    <div className="fixed inset-0 pointer-events-none z-50 overflow-hidden">
      {Array.from({ length: 12 }).map((_, i) => (
        <div
          key={i}
          className="absolute text-2xl"
          style={{
            left: `${5 + (i * 8) % 90}%`,
            top: "-30px",
            animation: `coin-fall ${1.5 + (i % 4) * 0.3}s ease-in ${i * 0.1}s forwards`,
          }}
        >
          🪙
        </div>
      ))}
      <style>{`
        @keyframes coin-fall {
          0% { transform: translateY(0) rotate(0deg); opacity: 1; }
          100% { transform: translateY(100vh) rotate(720deg); opacity: 0; }
        }
      `}</style>
    </div>
  );
}

// ── Tier reward card — displayed prominently ────────────────────────────────
function TierRewardCard({ activeCount }: { activeCount: number }) {
  const currentTier = [...REFERRAL_TIERS].reverse().find(t => activeCount >= t.count);
  const nextTier = REFERRAL_TIERS.find(t => activeCount < t.count);
  const progress = nextTier
    ? Math.min(100, (activeCount / nextTier.count) * 100)
    : 100;

  return (
    <div className="rounded-2xl bg-gradient-to-br from-amber-500/10 via-card to-primary/10 border border-border/60 p-3 space-y-3">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-2xl">{currentTier?.icon || "🎯"}</span>
          <div>
            <div className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Niveau actuel</div>
            <div className="font-extrabold text-sm">{currentTier?.label || "Nouveau"}</div>
          </div>
        </div>
        <div className="text-right">
          <div className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Récompense par filleul</div>
          <div className="font-extrabold text-sm text-emerald-600">{REWARD_PER_ACTIVE_AR} Ar</div>
        </div>
      </div>

      {/* Progress bar */}
      <div className="relative h-3 rounded-full bg-secondary overflow-hidden">
        <div
          className="absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-primary to-amber-400 transition-all duration-500"
          style={{ width: `${progress}%` }}
        />
        <div className="absolute inset-0 flex items-center justify-center text-[10px] font-bold text-foreground/80">
          {activeCount} / {nextTier?.count || activeCount}
        </div>
      </div>

      {/* Tier list — PROMINENT: "5 filleuls = 500 Ar" */}
      <div className="space-y-1.5">
        {REFERRAL_TIERS.map(t => {
          const reached = activeCount >= t.count;
          return (
            <div
              key={t.count}
              className={`flex items-center gap-2.5 rounded-xl px-2.5 py-2 transition-all ${
                reached
                  ? "bg-primary/15 border border-primary/30"
                  : "bg-secondary/40 border border-border/20"
              }`}
            >
              <span className="text-xl shrink-0">{t.icon}</span>
              <div className="flex-1 min-w-0">
                <div className="font-bold text-sm">
                  {t.count} filleuls {reached && <CheckCircle2 className="inline w-3.5 h-3.5 text-emerald-500 ml-1" />}
                </div>
                <div className="text-[10px] text-muted-foreground">{t.label}</div>
              </div>
              <div className={`font-extrabold text-sm shrink-0 ${reached ? "text-emerald-600" : "text-muted-foreground"}`}>
                = {t.reward.toLocaleString("fr-FR")} Ar
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

// ── Stat card ───────────────────────────────────────────────────────────────
function StatCard({ icon, label, value, sub, color = "text-foreground" }: {
  icon: React.ReactNode; label: string; value: string | number; sub?: string; color?: string;
}) {
  return (
    <div className="rounded-2xl bg-secondary/60 p-3 space-y-1">
      <div className="flex items-center gap-1.5 text-muted-foreground text-xs">{icon}{label}</div>
      <div className={`text-xl font-extrabold ${color}`}>{value}</div>
      {sub && <div className="text-[10px] text-muted-foreground">{sub}</div>}
    </div>
  );
}

// ── Main page ───────────────────────────────────────────────────────────────
export default function ParrainagePage() {
  const { profile, user } = useAuth();
  const [tab, setTab] = useState<Tab>("filleuls");
  const [data, setData] = useState<any>(null);
  const [leaderboard, setLeaderboard] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [referralEnabled, setReferralEnabled] = useState<boolean | null>(null);
  const [showCoinRain, setShowCoinRain] = useState(false);
  const [prevEarned, setPrevEarned] = useState(0);
  const [downloadUrl, setDownloadUrl] = useState<string>("");

  // Fetch app settings (referral_enabled + download_url)
  useEffect(() => {
    supabase
      .from("app_settings")
      .select("referral_enabled, download_url")
      .eq("id", 1)
      .maybeSingle()
      .then(({ data: cfg }) => {
        setReferralEnabled(cfg ? (cfg as any).referral_enabled !== false : true);
        setDownloadUrl(((cfg as any)?.download_url || "").trim());
      });
  }, []);

  const refCode = profile?.referral_code || "";
  const shareLink = typeof window !== "undefined"
    ? `${window.location.origin}/login?ref=${refCode}`
    : "";

  const copyCode = () => {
    copyText(refCode).then(ok => toast[ok ? "success" : "error"](ok ? "Code copié !" : "Impossible de copier"));
  };

  const copyLink = () => {
    copyText(shareLink).then(ok => toast[ok ? "success" : "error"](ok ? "Lien copié !" : "Impossible de copier"));
  };

  // Share via WhatsApp
  const shareWhatsApp = () => {
    const msg = encodeURIComponent(
      `🎮 Rejoins-moi sur Lalao MADA !\n\n${shareLink}\n\n📋 Mon code de parrainage : ${refCode}\n\n💰 Tu peux jouer au Ludo, Domino, Échecs et plus encore en Ariary !`
    );
    window.open(`https://wa.me/?text=${msg}`, "_blank");
  };

  // Share via Facebook
  const shareFacebook = () => {
    const url = encodeURIComponent(shareLink);
    window.open(`https://www.facebook.com/sharer/sharer.php?u=${url}`, "_blank");
  };

  // Share via SMS
  const shareSMS = () => {
    const msg = encodeURIComponent(`Rejoins Lalao MADA 🎮 ${shareLink} Code: ${refCode}`);
    window.open(`sms:?body=${msg}`, "_blank");
  };

  // Fetch dashboard data
  const refresh = () => {
    supabase.rpc("get_referral_dashboard" as any).then(({ data: d, error }: any) => {
      if (error) {
        console.error("get_referral_dashboard error:", error);
        setLoading(false);
        return;
      }
      if (d) {
        const newEarned = Number(d.total_earned || 0);
        if (newEarned > prevEarned && prevEarned > 0) {
          setShowCoinRain(true);
          setTimeout(() => setShowCoinRain(false), 2500);
        }
        setPrevEarned(newEarned);
        setData(d);
      }
      setLoading(false);
    });
  };

  useEffect(() => {
    if (!user?.id) return;
    setLoading(true);
    refresh();

    let dt: ReturnType<typeof setTimeout>;
    const debouncedRefresh = () => { clearTimeout(dt); dt = setTimeout(refresh, 800); };
    const ch = supabase
      .channel(`ref-dash-${user.id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "referral_events", filter: `referrer_id=eq.${user.id}` }, debouncedRefresh)
      .on("postgres_changes", { event: "*", schema: "public", table: "referrals", filter: `referrer_id=eq.${user.id}` }, debouncedRefresh)
      .subscribe();

    const onFocus = () => refresh();
    window.addEventListener("focus", onFocus);
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
      window.removeEventListener("focus", onFocus);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  useEffect(() => {
    if (tab !== "classement") return;
    supabase.rpc("get_referral_leaderboard" as any, { _limit: 50 } as any).then(({ data: d }: any) => {
      setLeaderboard(d || []);
    });
  }, [tab]);

  const stats = data?.stats || {};
  const referrals: any[] = data?.referrals || [];
  const events: any[] = data?.events || [];
  const totalEarned = Number(data?.total_earned || stats.total_earned_ar || 0);
  const activeCount = Number(data?.active_count || stats.active_referrals || 0);
  const totalRefs = Number(stats.total_referrals || referrals.length || 0);
  const myRank = data?.rank || null;

  const TABS: { id: Tab; label: string; icon: string }[] = [
    { id: "filleuls", label: "Filleuls", icon: "👥" },
    { id: "gains", label: "Gains", icon: "💰" },
    { id: "classement", label: "Classement", icon: "🏆" },
  ];

  if (loading || referralEnabled === null)
    return <PageLoader variant="overlay" label="Chargement du parrainage…" />;

  if (!referralEnabled)
    return (
      <main className="max-w-xl mx-auto px-4 py-10 text-center">
        <div className="text-4xl mb-3">🚫</div>
        <p className="text-muted-foreground font-semibold">
          Programme de parrainage désactivé pour le moment
        </p>
      </main>
    );

  return (
    <main className="max-w-xl mx-auto w-full px-3 pt-2 pb-2 h-[calc(100dvh-14rem)] flex flex-col gap-2.5 overflow-hidden">
      <CoinRain trigger={showCoinRain} />

      {/* ── Hero ── */}
      <div className="rounded-2xl bg-gradient-to-br from-primary/15 via-card to-amber-500/10 border border-border/60 p-3 space-y-2.5 shrink-0">
        <div className="flex items-center gap-2">
          <div className="w-9 h-9 rounded-xl bg-gradient-to-br from-primary to-amber-400 flex items-center justify-center shrink-0">
            <Gift className="w-5 h-5 text-white" />
          </div>
          <div className="flex-1">
            <h1 className="text-base font-extrabold leading-none">Parrainez vos amis</h1>
            <p className="text-[11px] text-muted-foreground mt-0.5">
              {REWARD_PER_ACTIVE_AR} Ar par filleul actif
            </p>
          </div>
          <div className="text-right">
            <div className="text-lg font-extrabold text-emerald-600">
              {Math.round(totalEarned).toLocaleString("fr-FR")}
            </div>
            <div className="text-[10px] text-muted-foreground">Ar gagnés</div>
          </div>
        </div>

        {/* Share link */}
        <div className="space-y-1">
          <div className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">Votre lien de parrainage</div>
          <button
            onClick={copyLink}
            className="w-full h-11 flex items-center gap-2 px-3 rounded-2xl bg-primary/10 border-2 border-dashed border-primary/40 active:scale-[0.98] transition-all"
          >
            <span className="flex-1 text-left truncate text-xs font-medium text-foreground">
              {shareLink || "Lien bientôt disponible"}
            </span>
            <Copy className="w-4 h-4 shrink-0 text-primary" />
          </button>
        </div>

        {/* Share buttons */}
        <div className="grid grid-cols-4 gap-1.5">
          <button
            onClick={copyCode}
            className="flex flex-col items-center gap-1 py-2 rounded-xl bg-primary/10 border border-primary/20 active:scale-95 transition-all"
          >
            <Copy className="w-4 h-4 text-primary" />
            <span className="text-[9px] font-semibold">Code</span>
          </button>
          <button
            onClick={shareWhatsApp}
            className="flex flex-col items-center gap-1 py-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20 active:scale-95 transition-all"
          >
            <MessageCircle className="w-4 h-4 text-emerald-600" />
            <span className="text-[9px] font-semibold">WhatsApp</span>
          </button>
          <button
            onClick={shareFacebook}
            className="flex flex-col items-center gap-1 py-2 rounded-xl bg-blue-500/10 border border-blue-500/20 active:scale-95 transition-all"
          >
            <Share2 className="w-4 h-4 text-blue-600" />
            <span className="text-[9px] font-semibold">Facebook</span>
          </button>
          <button
            onClick={shareSMS}
            className="flex flex-col items-center gap-1 py-2 rounded-xl bg-amber-500/10 border border-amber-500/20 active:scale-95 transition-all"
          >
            <Phone className="w-4 h-4 text-amber-600" />
            <span className="text-[9px] font-semibold">SMS</span>
          </button>
        </div>

        {/* Code display */}
        <button
          onClick={copyCode}
          className="w-full h-12 flex items-center justify-center gap-3 px-3 rounded-2xl bg-primary text-primary-foreground font-semibold active:scale-[0.98] transition-all"
        >
          <span className="font-mono font-extrabold text-xl tracking-[0.15em]">{refCode}</span>
          <Copy className="w-4 h-4 opacity-80" />
        </button>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-1.5">
          <StatCard icon={<Users className="w-3 h-3" />} label="Filleuls" value={totalRefs} sub={`${activeCount} actifs`} />
          <StatCard icon={<Coins className="w-3 h-3" />} label="Gains" value={`${Math.round(totalEarned).toLocaleString("fr-FR")} Ar`} color="text-emerald-600" />
          <StatCard icon={<Trophy className="w-3 h-3" />} label="Rang" value={myRank ? `#${myRank}` : "—"} color="text-amber-500" />
        </div>
      </div>

      {/* ── Tier rewards — PROMINENT ── */}
      <div className="shrink-0">
        <TierRewardCard activeCount={activeCount} />
      </div>

      {/* ── Tabs ── */}
      <div className="flex gap-1 bg-secondary/60 rounded-2xl p-1 shrink-0">
        {TABS.map(t => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={`flex-1 flex items-center justify-center gap-1 px-2 py-1.5 rounded-xl text-xs font-semibold transition-all ${
              tab === t.id ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"
            }`}
          >
            <span>{t.icon}</span>{t.label}
          </button>
        ))}
      </div>

      {/* ── Content ── */}
      <div className="flex-1 min-h-0 overflow-y-auto rounded-2xl bg-card px-3 py-2 shadow-sm">
        {/* Filleuls tab */}
        {tab === "filleuls" && (
          referrals.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center gap-3 py-6">
              <div className="text-4xl opacity-50">👥</div>
              <div className="text-sm text-muted-foreground">Aucun filleul pour l'instant</div>
              <div className="text-[11px] text-muted-foreground max-w-[220px] text-center">
                Partagez votre lien de parrainage avec vos amis. Dès qu'ils s'inscrivent avec votre code, ils apparaîtront ici.
              </div>
              <button onClick={copyLink} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold text-xs">
                Copier mon lien
              </button>
            </div>
          ) : referrals.map((r: any) => {
            const badge = referralStatusBadge(r);
            const earned = Number(r.reward_amount || 0);
            return (
              <div key={r.id} className="flex items-center gap-2.5 py-2.5 border-b border-border/40 last:border-0">
                <div className="w-9 h-9 rounded-full bg-accent flex items-center justify-center font-bold text-xs shrink-0 overflow-hidden">
                  {r.avatar_url
                    ? <img src={r.avatar_url} width={36} height={36} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                    : (r.pseudo || "?").slice(0, 2).toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">{r.pseudo}</div>
                  <div className={`flex items-center gap-1 text-[10px] ${badge.color}`}>
                    {badge.icon}{badge.label}
                  </div>
                </div>
                {earned > 0 && (
                  <div className="text-sm font-extrabold text-emerald-600 shrink-0">
                    +{Math.round(earned).toLocaleString("fr-FR")} Ar
                  </div>
                )}
              </div>
            );
          })
        )}

        {/* Gains tab */}
        {tab === "gains" && (
          events.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center gap-2 py-6 text-xs text-muted-foreground">
              <div className="text-4xl opacity-50">💰</div>
              <div className="font-semibold">Aucune récompense reçue</div>
              <p className="text-[10px] max-w-[220px] text-center">
                Vous gagnez {REWARD_PER_ACTIVE_AR} Ar dès qu'un filleul vérifie son téléphone, dépose {MIN_DEPOSIT_AR} Ar et joue {MIN_MATCHES} matchs à {MIN_STAKE_AR} Ar minimum.
              </p>
            </div>
          ) : (
            <>
              <div className="flex items-center justify-between py-2 px-3 mb-1 rounded-xl bg-emerald-500/10">
                <span className="text-xs font-bold text-emerald-700 dark:text-emerald-400">Total gagné</span>
                <span className="text-lg font-extrabold text-emerald-600">
                  {Math.round(totalEarned).toLocaleString("fr-FR")} Ar
                </span>
              </div>
              {events.map((e: any) => (
                <div key={e.id} className="flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0">
                  <div className="w-8 h-8 rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center text-sm shrink-0">🪙</div>
                  <div className="flex-1 min-w-0">
                    <div className="text-sm font-semibold truncate">{e.referee_pseudo}</div>
                    <div className="text-[10px] text-muted-foreground">
                      {e.note || "Filleul actif"} · {new Date(e.created_at).toLocaleDateString("fr-FR", { dateStyle: "short" })}
                    </div>
                  </div>
                  <div className="text-emerald-600 font-extrabold text-sm shrink-0">
                    +{Math.round(Number(e.reward_amount)).toLocaleString("fr-FR")} Ar
                  </div>
                </div>
              ))}
            </>
          )
        )}

        {/* Classement tab */}
        {tab === "classement" && (
          leaderboard.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center gap-2 py-6 text-xs text-muted-foreground">
              <div className="text-4xl opacity-50">🏆</div>
              <div className="font-semibold">Classement vide</div>
              <p className="text-[10px] max-w-[200px] text-center">
                Soyez le premier à parrainer des amis et à grimper au classement !
              </p>
            </div>
          ) : leaderboard.map((lb: any) => {
            const isMe = lb.referrer_id === user?.id;
            return (
              <div key={lb.referrer_id} className={`flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0 ${isMe ? "bg-primary/5 rounded-xl px-2" : ""}`}>
                <div className="w-6 text-center font-extrabold text-xs shrink-0">
                  {lb.rank === 1 ? "👑" : lb.rank === 2 ? "🥈" : lb.rank === 3 ? "🥉" : lb.rank}
                </div>
                <Link to="/joueur/$id" params={{ id: lb.referrer_id }} className="w-8 h-8 rounded-full bg-accent overflow-hidden flex items-center justify-center font-bold text-xs shrink-0">
                  {lb.avatar_url
                    ? <img src={lb.avatar_url} width={32} height={32} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                    : (lb.pseudo || "?").slice(0, 2).toUpperCase()}
                </Link>
                <div className="flex-1 min-w-0">
                  <div className={`font-bold text-sm truncate ${isMe ? "text-primary" : ""}`}>{lb.pseudo}</div>
                  <div className="text-[10px] text-muted-foreground">{lb.active_referrals || 0} filleuls actifs</div>
                </div>
                <div className="font-extrabold text-sm text-emerald-600 shrink-0">
                  {Math.round(Number(lb.total_earned_ar)).toLocaleString("fr-FR")} Ar
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* ── How it works (collapsible) ── */}
      <details className="shrink-0 rounded-2xl bg-secondary/50 px-3 py-2 group">
        <summary className="list-none flex items-center gap-2 cursor-pointer">
          <Sparkles className="w-4 h-4 shrink-0 text-primary" />
          <p className="flex-1 text-[11px] leading-snug text-muted-foreground">
            <b className="text-foreground">{REWARD_PER_ACTIVE_AR} Ar</b> par filleul actif : téléphone vérifié +
            dépôt ≥ <b className="text-foreground">{MIN_DEPOSIT_AR} Ar</b> +
            {MIN_MATCHES} matchs avec mise ≥ <b className="text-foreground">{MIN_STAKE_AR} Ar</b>
          </p>
          <ChevronDown className="w-4 h-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
        </summary>
        <div className="mt-2 space-y-1 text-[10px] leading-snug text-muted-foreground border-t border-border/40 pt-2">
          {referralConditions().map((c, i) => (
            <p key={i}>• {c}</p>
          ))}
        </div>
      </details>
    </main>
  );
}
