import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import {
  Copy, Trophy, Users, Coins,
  Zap, Gift, Shield, Download, Share2, CheckCircle2, Clock,
} from "lucide-react";
import {
  referralConditions,
  referralHowItWorks,
  resolveReferralRules,
  REFERRAL_HERO_SUBTITLE_TEMPLATE,
  DEFAULT_COMMISSION_PCT,
  DEFAULT_MAX_STAKES,
  fillReferralTokens,
} from "@/lib/referral-rules";
import { useCmsContent, type CmsReferralContent } from "@/hooks/use-cms-content";

const DEFAULT_REFERRAL_CMS: CmsReferralContent = {
  hero_subtitle: REFERRAL_HERO_SUBTITLE_TEMPLATE,
  how_it_works: [],
  conditions: [],
};

export const Route = createFileRoute("/_authenticated/parrainage")({
  component: ParrainagePage,
  head: () => ({ meta: [
    { title: "Parrainage — Lalao MADA" },
    { name: "description", content: "Programme de parrainage Lalao MADA" },
  ] }),
});

type Tab = "dashboard" | "filleuls" | "commissions" | "classement";

export default function ParrainagePage() {
  const { profile, user } = useAuth();
  const [tab, setTab] = useState<Tab>("dashboard");
  const [data, setData] = useState<any>(null);
  const [leaderboard, setLeaderboard] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [referralEnabled, setReferralEnabled] = useState<boolean | null>(null);
  const { data: cms } = useCmsContent<CmsReferralContent>("referral", DEFAULT_REFERRAL_CMS);
  const [downloadUrl, setDownloadUrl] = useState<string>("");

  useEffect(() => {
    supabase.from("app_settings").select("referral_enabled, download_url").eq("id", 1).maybeSingle().then(({ data: cfg }) => {
      setReferralEnabled(cfg ? (cfg as any).referral_enabled !== false : true);
      setDownloadUrl(((cfg as any)?.download_url || "").trim());
    });
  }, []);

  const [copiedCode, setCopiedCode] = useState(false);
  const refCode = profile?.referral_code || "";
  const copyCode = () => copyText(refCode).then(ok => {
    if (ok) { setCopiedCode(true); setTimeout(() => setCopiedCode(false), 2000); toast.success("Code copié !"); }
    else toast.error("Impossible de copier");
  });
  const shareLink = () => {
    const text = `Rejoins Lalao MADA avec mon code ${refCode} ! ${downloadUrl}`;
    if (navigator.share) {
      navigator.share({ text, title: "Lalao MADA" }).catch(() => {});
    } else {
      // Fallback: open WhatsApp share link
      const waUrl = `https://wa.me/?text=${encodeURIComponent(text)}`;
      window.open(waUrl, "_blank");
      copyText(text).then(() => toast.success("Lien copié + WhatsApp ouvert !"));
    }
  };

  const refresh = () => {
    supabase.rpc("get_referral_dashboard" as any).then(({ data: d }: any) => {
      if (d) setData(d);
      setLoading(false);
    });
  };

  useEffect(() => {
    if (!user?.id) return;
    setLoading(true);
    refresh();
    const ch = supabase
      .channel(`ref-dash-${user.id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "referral_events", filter: `referrer_id=eq.${user.id}` }, refresh)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "profiles", filter: `referred_by=eq.${user.id}` }, refresh)
      .subscribe();
    const onFocus = () => refresh();
    window.addEventListener("focus", onFocus);
    return () => { supabase.removeChannel(ch); window.removeEventListener("focus", onFocus); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  useEffect(() => {
    if (tab !== "classement") return;
    supabase.rpc("get_referral_leaderboard" as any, { _limit: 10 } as any).then(({ data: d }: any) => setLeaderboard(d || []));
  }, [tab]);

  const stats = data?.stats || {};
  const settings = data?.settings || {};
  const referrals: any[] = data?.referrals || [];
  const events: any[] = data?.events || [];
  const totalEarned = Number(stats.total_earned_ar || 0);
  const totalRefs = Number(stats.total_referrals || 0);
  const myRank = data?.rank || null;
  const rules = resolveReferralRules({
    commissionPct: Number(settings.stake_commission_pct ?? DEFAULT_COMMISSION_PCT),
    maxStakes: Number(settings.referral_stake_max ?? DEFAULT_MAX_STAKES),
  });
  const { commissionPct, maxStakes } = rules;
  const firstDepositBonus = Math.round(Number(settings.first_deposit_bonus_ar ?? 25));

  // Filleuls en attente (pas encore de dépôt validé)
  const pendingReferrals = referrals.filter((r: any) => !r.phone_verified);
  const paidReferrals = referrals.filter((r: any) => r.phone_verified);
  const pendingEarnings = pendingReferrals.length * firstDepositBonus;

  const TABS: { id: Tab; label: string; icon: string }[] = [
    { id: "dashboard",   label: "Accueil",     icon: "📊" },
    { id: "filleuls",    label: "Filleuls",    icon: "👥" },
    { id: "commissions", label: "Commissions", icon: "💰" },
    { id: "classement",  label: "Classement",  icon: "🏆" },
  ];

  if (loading || referralEnabled === null) return (
    <main className="max-w-xl mx-auto px-4 py-10 text-center text-muted-foreground">
      <div className="animate-pulse text-4xl mb-3">⏳</div>
      Chargement…
    </main>
  );

  if (!referralEnabled) return (
    <main className="max-w-xl mx-auto px-4 py-10 text-center">
      <div className="text-4xl mb-3">🚫</div>
      <p className="text-muted-foreground font-semibold">Programme désactivé pour le moment</p>
    </main>
  );

  return (
    <main className="max-w-xl mx-auto px-3 py-3 space-y-3 pb-24">

      {/* ── HERO COMPACT ── */}
      <div className="rounded-2xl bg-gradient-to-br from-primary/20 via-card to-orange-500/10 border border-primary/20 p-4 space-y-3">

        {/* Titre + règles résumées */}
        <div className="flex items-center justify-between">
          <h1 className="text-lg font-extrabold flex items-center gap-2">
            <Gift className="w-5 h-5 text-primary" /> Parrainage
          </h1>
          <div className="text-xs text-muted-foreground font-medium bg-secondary/80 px-2 py-1 rounded-lg">
            +{firstDepositBonus} Ar · {commissionPct}% × {maxStakes}
          </div>
        </div>

        {/* Lien de téléchargement — bouton principal bien visible */}
        {downloadUrl ? (
          <a href={downloadUrl} target="_blank" rel="noopener noreferrer"
            className="flex items-center gap-3 w-full px-4 py-3.5 rounded-xl bg-primary text-primary-foreground font-bold text-sm shadow-lg active:scale-[0.98] transition-all">
            <Download className="w-5 h-5 shrink-0" />
            <div className="flex-1 min-w-0">
              <div className="text-[10px] font-semibold opacity-75 uppercase tracking-wide">Lien de téléchargement</div>
              <div className="truncate text-base">{downloadUrl.replace(/^https?:\/\//, "")}</div>
            </div>
            <Share2 className="w-4 h-4 opacity-70 shrink-0" />
          </a>
        ) : (
          <div className="flex items-center gap-3 w-full px-4 py-3 rounded-xl bg-secondary text-muted-foreground text-sm">
            <Download className="w-5 h-5 shrink-0" /> Lien bientôt disponible
          </div>
        )}

        {/* Code de parrainage — bien mis en avant */}
        <div>
          <div className="text-[10px] text-muted-foreground font-bold uppercase tracking-wider mb-1.5">
            Votre code de parrainage
          </div>
          <button onClick={copyCode}
            className="w-full flex items-center justify-between gap-3 px-4 py-3 rounded-xl bg-primary/10 border-2 border-primary/40 hover:bg-primary/15 active:scale-[0.98] transition-all">
            <span className="font-mono font-extrabold text-primary text-2xl tracking-widest">{refCode}</span>
            <div className={`flex items-center gap-1.5 px-3 py-1.5 rounded-lg text-xs font-bold shrink-0 transition-all ${
              copiedCode ? "bg-emerald-500 text-white" : "bg-primary text-primary-foreground"
            }`}>
              {copiedCode ? <><CheckCircle2 className="w-3.5 h-3.5" /> Copié !</> : <><Copy className="w-3.5 h-3.5" /> Copier</>}
            </div>
          </button>
        </div>

        {/* Bouton partager tout-en-un */}
        <button onClick={shareLink}
          className="w-full flex items-center justify-center gap-2 py-3 rounded-xl bg-gradient-to-r from-primary to-orange-500 text-white font-bold text-sm shadow-md active:scale-[0.98] transition-all">
          <Share2 className="w-5 h-5" /> Partager le lien + mon code
        </button>
      </div>

      {/* ── STATS : Filleuls + Gains ── */}
      <div className="grid grid-cols-2 gap-2">

        {/* Filleuls */}
        <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-1.5">
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-medium">
            <Users className="w-3.5 h-3.5" /> Mes filleuls
          </div>
          <div className="text-4xl font-extrabold leading-none">{totalRefs}</div>
          <div className="space-y-1 pt-1">
            {paidReferrals.length > 0 && (
              <div className="flex items-center gap-1 text-[11px] text-emerald-600 font-bold">
                <CheckCircle2 className="w-3 h-3" />
                {paidReferrals.length} payé{paidReferrals.length > 1 ? "s" : ""}
              </div>
            )}
            {pendingReferrals.length > 0 && (
              <div className="flex items-center gap-1 text-[11px] text-amber-600 font-bold">
                <Clock className="w-3 h-3" />
                {pendingReferrals.length} en validation
              </div>
            )}
            {totalRefs === 0 && (
              <div className="text-[11px] text-muted-foreground">Invitez des amis !</div>
            )}
          </div>
        </div>

        {/* Gains */}
        <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-1.5">
          <div className="flex items-center gap-1.5 text-xs text-muted-foreground font-medium">
            <Coins className="w-3.5 h-3.5" /> Mes gains
          </div>
          <div className="text-2xl font-extrabold text-emerald-600 leading-none">
            {Math.round(totalEarned).toLocaleString("fr-FR")}
            <span className="text-sm font-bold ml-1">Ar</span>
          </div>
          <div className="space-y-1 pt-1">
            {totalEarned > 0 && (
              <div className="flex items-center gap-1 text-[11px] text-emerald-600 font-bold">
                <CheckCircle2 className="w-3 h-3" />
                {Math.round(totalEarned).toLocaleString("fr-FR")} Ar payé
              </div>
            )}
            {pendingEarnings > 0 && (
              <div className="flex items-center gap-1 text-[11px] text-amber-600 font-bold">
                <Clock className="w-3 h-3" />
                +{pendingEarnings.toLocaleString("fr-FR")} Ar en attente
              </div>
            )}
            {totalEarned === 0 && pendingEarnings === 0 && (
              <div className="text-[11px] text-muted-foreground">Aucun gain encore</div>
            )}
          </div>
        </div>
      </div>

      {/* ── PROGRESSION vers objectif ── */}
      {(() => {
        const goal = 10;
        const progress = Math.min(100, (totalRefs / goal) * 100);
        return (
          <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-2">
            <div className="flex items-center justify-between text-xs font-semibold">
              <span className="text-muted-foreground">🎯 Objectif filleuls</span>
              <span className="font-bold">{totalRefs} / {goal}</span>
            </div>
            <div className="h-3 rounded-full bg-secondary overflow-hidden">
              <div className="h-full rounded-full bg-gradient-to-r from-primary to-orange-500 transition-all duration-500"
                style={{ width: `${progress}%` }} />
            </div>
            {totalRefs >= goal ? (
              <p className="text-[11px] text-emerald-600 font-bold">🎉 Objectif atteint ! Continuez pour grimper dans le classement.</p>
            ) : (
              <p className="text-[11px] text-muted-foreground">Plus que {goal - totalRefs} filleul{goal - totalRefs > 1 ? "s" : ""} pour atteindre l'objectif !</p>
            )}
          </div>
        );
      })()}

      {/* ── STATISTIQUES SUPPLÉMENTAIRES ── */}
      <div className="grid grid-cols-3 gap-2">
        <div className="rounded-2xl bg-card border border-border/60 p-3 text-center space-y-1">
          <div className="text-lg">⭐</div>
          <div className="text-lg font-extrabold">{referrals.length + pendingReferrals.length}</div>
          <div className="text-[9px] text-muted-foreground font-medium">Invitations envoyées</div>
        </div>
        <div className="rounded-2xl bg-card border border-border/60 p-3 text-center space-y-1">
          <div className="text-lg">📈</div>
          <div className="text-lg font-extrabold">
            {totalRefs > 0 ? Math.round((paidReferrals.length / totalRefs) * 100) : 0}%
          </div>
          <div className="text-[9px] text-muted-foreground font-medium">Taux d'inscription</div>
        </div>
        <div className="rounded-2xl bg-card border border-border/60 p-3 text-center space-y-1">
          <div className="text-lg">💰</div>
          <div className="text-lg font-extrabold text-emerald-600">{Math.round(totalEarned).toLocaleString("fr-FR")}</div>
          <div className="text-[9px] text-muted-foreground font-medium">Total gagné (Ar)</div>
        </div>
      </div>

      {/* ── BADGES DE RÉCOMPENSE ── */}
      <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-3">
        <div className="text-xs font-bold text-muted-foreground uppercase tracking-wide flex items-center gap-1.5">
          🏅 Vos badges
        </div>
        {(() => {
          const badges = [
            { threshold: 5,  label: "Bronze",  emoji: "🥉", color: "text-orange-600", bg: "bg-orange-600/10", border: "border-orange-600/30" },
            { threshold: 20, label: "Argent",  emoji: "🥈", color: "text-slate-400",  bg: "bg-slate-400/10", border: "border-slate-400/30" },
            { threshold: 50, label: "Or",      emoji: "🥇", color: "text-amber-400", bg: "bg-amber-400/10", border: "border-amber-400/30" },
          ];
          return (
            <div className="grid grid-cols-3 gap-2">
              {badges.map(b => {
                const achieved = totalRefs >= b.threshold;
                return (
                  <div key={b.label} className={`rounded-xl p-3 text-center border-2 transition-all ${
                    achieved ? `${b.bg} ${b.border}` : "bg-secondary/50 border-border/30 opacity-50"
                  }`}>
                    <div className="text-2xl mb-1">{b.emoji}</div>
                    <div className={`text-[11px] font-bold ${achieved ? b.color : "text-muted-foreground"}`}>{b.label}</div>
                    <div className="text-[9px] text-muted-foreground">{b.threshold} filleuls</div>
                  </div>
                );
              })}
            </div>
          );
        })()}
      </div>

      {/* ── COMMENT GAGNER (encadré) ── */}
      <div className="rounded-2xl bg-gradient-to-br from-primary/5 to-orange-500/5 border border-primary/20 p-4 space-y-2">
        <div className="font-bold text-sm flex items-center gap-1.5">💡 Comment gagner ?</div>
        <div className="space-y-1.5 text-sm">
          <div className="flex items-center gap-2">
            <span className="text-emerald-500 font-bold">✅</span>
            <span><b>{firstDepositBonus} Ar</b> au premier dépôt de votre filleul.</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-emerald-500 font-bold">✅</span>
            <span><b>{commissionPct}%</b> de commission sur les {maxStakes} premières parties.</span>
          </div>
          <div className="flex items-center gap-2">
            <span className="text-emerald-500 font-bold">✅</span>
            <span>Paiement <b>automatique</b> sur votre solde.</span>
          </div>
        </div>
      </div>

      {/* ── LISTE FILLEULS DIRECTEMENT VISIBLE (top 5) ── */}
      {totalRefs > 0 && (
        <div className="rounded-2xl bg-card border border-border/60 p-4">
          <div className="text-xs font-bold text-muted-foreground uppercase tracking-wide mb-3 flex items-center gap-1.5">
            <Users className="w-3.5 h-3.5" /> Filleuls ({totalRefs})
          </div>
          <div className="space-y-2.5">
            {referrals.slice(0, 5).map((r: any) => {
              const isPending = !r.phone_verified;
              const earned = Number(r.total_earned || 0);
              return (
                <div key={r.id} className="flex items-center gap-2.5">
                  <div className="w-9 h-9 rounded-full bg-accent flex items-center justify-center font-bold text-xs shrink-0 overflow-hidden">
                    {r.avatar_url
                      ? <img src={r.avatar_url} className="w-full h-full object-cover" alt="" />
                      : (r.pseudo || "?").slice(0, 2).toUpperCase()}
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-bold text-sm truncate">{r.pseudo}</div>
                    <div className={`text-[10px] font-semibold flex items-center gap-1 ${isPending ? "text-amber-600" : "text-emerald-600"}`}>
                      {isPending ? <><Clock className="w-2.5 h-2.5" /> En validation</> : <><CheckCircle2 className="w-2.5 h-2.5" /> Actif</>}
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    {isPending ? (
                      <div className="text-xs font-extrabold text-amber-600">+{firstDepositBonus} Ar<br /><span className="text-[10px] font-normal text-muted-foreground">en attente</span></div>
                    ) : earned > 0 ? (
                      <div className="text-sm font-extrabold text-emerald-600">+{Math.round(earned).toLocaleString("fr-FR")} Ar</div>
                    ) : (
                      <div className="text-xs text-muted-foreground">—</div>
                    )}
                  </div>
                </div>
              );
            })}
            {referrals.length > 5 && (
              <button onClick={() => setTab("filleuls")}
                className="text-xs text-primary font-bold hover:underline w-full text-center pt-1">
                Voir tous les {referrals.length} filleuls →
              </button>
            )}
          </div>
        </div>
      )}

      {/* ── TABS ── */}
      <div className="flex gap-1 bg-secondary/60 rounded-xl p-1 overflow-x-auto">
        {TABS.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className={`flex items-center gap-1 px-2.5 py-1.5 rounded-lg text-xs font-semibold whitespace-nowrap transition-all ${tab === t.id ? "bg-card shadow-sm text-foreground" : "text-muted-foreground hover:text-foreground"}`}>
            <span>{t.icon}</span>{t.label}
          </button>
        ))}
      </div>

      {/* ── Tab: Dashboard ── */}
      {tab === "dashboard" && (
        <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-3">
          <div className="font-bold text-sm flex items-center gap-2">
            <Zap className="w-4 h-4 text-primary" /> Comment ça marche ?
          </div>
          {(cms.how_it_works?.length ? cms.how_it_works : referralHowItWorks(rules)).map(s => (
            <div key={s.step} className="flex items-center gap-3">
              <div className="w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-extrabold text-primary shrink-0">{s.step}</div>
              <div className="text-sm font-semibold flex items-center gap-1.5">{s.icon} {fillReferralTokens(s.label, rules)}</div>
            </div>
          ))}
        </div>
      )}

      {/* ── Tab: Filleuls ── */}
      {tab === "filleuls" && (
        <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-1">
          <div className="font-bold text-sm mb-3 flex items-center gap-2">
            <Users className="w-4 h-4 text-primary" /> Mes filleuls ({totalRefs})
          </div>
          {referrals.length === 0 ? (
            <div className="py-8 text-center space-y-3">
              <div className="text-4xl">🤷</div>
              <div className="text-sm text-muted-foreground">Aucun filleul pour l'instant.</div>
              <button onClick={copyCode} className="mt-2 px-5 py-2.5 rounded-full bg-primary text-primary-foreground font-semibold text-sm">
                Copier mon code
              </button>
            </div>
          ) : referrals.map((r: any) => {
            const earned = Number(r.total_earned || 0);
            const stakeCount = Number(r.referral_stake_count ?? r.stake_count ?? 0);
            const remaining = Math.max(0, maxStakes - stakeCount);
            const isPending = !r.phone_verified;
            return (
              <div key={r.id} className="flex items-center gap-3 py-3 border-b border-border/40 last:border-0">
                <div className="w-10 h-10 rounded-full bg-accent flex items-center justify-center font-bold text-sm shrink-0 overflow-hidden">
                  {r.avatar_url ? <img src={r.avatar_url} className="w-full h-full object-cover" alt="" />
                    : (r.pseudo || "?").slice(0, 2).toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">{r.pseudo}</div>
                  <div className={`inline-flex items-center gap-1 mt-1 px-2 py-0.5 rounded-full text-[10px] font-semibold ${
                    isPending ? "bg-amber-100 text-amber-700 dark:bg-amber-950/30 dark:text-amber-400"
                    : remaining === 0 ? "bg-secondary text-muted-foreground"
                    : "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/30 dark:text-emerald-400"
                  }`}>
                    {isPending ? <><Clock className="w-2.5 h-2.5" /> En attente dépôt</>
                      : remaining === 0 ? "✅ Programme terminé"
                      : <><CheckCircle2 className="w-2.5 h-2.5" /> Actif · {stakeCount}/{maxStakes}</>}
                  </div>
                </div>
                <div className="text-right shrink-0">
                  {earned > 0 ? (
                    <div className="text-sm font-extrabold text-emerald-600">+{Math.round(earned).toLocaleString("fr-FR")} Ar</div>
                  ) : isPending ? (
                    <div className="text-xs font-bold text-amber-600">+{firstDepositBonus} Ar<br /><span className="text-[10px] font-normal text-muted-foreground">en attente</span></div>
                  ) : null}
                  <div className="text-[10px] text-muted-foreground">{new Date(r.created_at).toLocaleDateString("fr-FR")}</div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ── Tab: Commissions ── */}
      {tab === "commissions" && (
        <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-1">
          <div className="font-bold text-sm mb-3 flex items-center gap-2">
            <Coins className="w-4 h-4 text-primary" /> Commissions
          </div>
          <div className="grid grid-cols-2 gap-2 mb-4">
            <div className="rounded-xl bg-emerald-50 dark:bg-emerald-950/20 p-3 text-center">
              <div className="text-lg font-extrabold text-emerald-600">{Math.round(totalEarned).toLocaleString("fr-FR")} Ar</div>
              <div className="text-[10px] text-muted-foreground">Payé</div>
            </div>
            {pendingEarnings > 0 && (
              <div className="rounded-xl bg-amber-50 dark:bg-amber-950/20 p-3 text-center">
                <div className="text-lg font-extrabold text-amber-600">+{pendingEarnings.toLocaleString("fr-FR")} Ar</div>
                <div className="text-[10px] text-muted-foreground">En validation</div>
              </div>
            )}
          </div>
          {events.length === 0 ? (
            <div className="py-6 text-center text-sm text-muted-foreground">Aucune commission reçue.</div>
          ) : events.map((e: any) => (
            <div key={e.id} className="flex items-center gap-3 py-2.5 border-b border-border/40 last:border-0">
              <div className="w-8 h-8 rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center text-sm">💰</div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-semibold truncate">Commission de {e.referee_pseudo}</div>
                <div className="text-[10px] text-muted-foreground">
                  {new Date(e.created_at).toLocaleString("fr-FR", { dateStyle: "short", timeStyle: "short" })}
                </div>
              </div>
              <div className="text-emerald-600 font-extrabold text-sm shrink-0">
                +{Math.round(Number(e.reward_amount)).toLocaleString("fr-FR")} Ar
              </div>
            </div>
          ))}
        </div>
      )}

      {/* ── Tab: Classement ── */}
      {tab === "classement" && (
        <div className="rounded-2xl bg-card border border-border/60 p-4 space-y-1">
          <div className="font-bold text-sm mb-3 flex items-center gap-2">
            <Trophy className="w-4 h-4 text-amber-500" /> Top 10 parrains
          </div>
          {leaderboard.length === 0 ? (
            <div className="py-6 text-center text-sm text-muted-foreground">Soyez le premier !</div>
          ) : leaderboard.slice(0, 10).map((lb: any) => {
            const isMe = lb.referrer_id === user?.id;
            const rank = Number(lb.rank);
            return (
              <div key={lb.referrer_id}
                className={`flex items-center gap-3 py-2.5 border-b border-border/40 last:border-0 ${isMe ? "bg-primary/5 rounded-xl px-2" : ""}`}>
                <div className="w-8 text-center font-extrabold text-sm shrink-0">
                  {rank === 1 ? "🥇" : rank === 2 ? "🥈" : rank === 3 ? "🥉" : <span className="text-muted-foreground">{rank}</span>}
                </div>
                <Link to="/joueur/$id" params={{ id: lb.referrer_id }}
                  className="w-9 h-9 rounded-full bg-accent overflow-hidden flex items-center justify-center font-bold text-sm shrink-0">
                  {lb.avatar_url ? <img src={lb.avatar_url} className="w-full h-full object-cover" alt="" />
                    : (lb.pseudo || "?").slice(0, 2).toUpperCase()}
                </Link>
                <div className="flex-1 min-w-0">
                  <div className={`font-bold text-sm truncate ${isMe ? "text-primary" : ""}`}>
                    {lb.pseudo}{isMe && <span className="text-[10px] text-primary ml-1">(vous)</span>}
                  </div>
                  <div className="text-[10px] text-muted-foreground">{lb.total_referrals || 0} filleuls</div>
                </div>
                <div className="font-extrabold text-sm text-emerald-600 shrink-0">
                  {Math.round(Number(lb.total_earned_ar)).toLocaleString("fr-FR")} Ar
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ── Conditions — repliables, ultra compact ── */}
      <details className="rounded-2xl bg-secondary/40 p-3 text-xs text-muted-foreground">
        <summary className="flex items-center gap-1.5 cursor-pointer font-semibold list-none select-none">
          <Shield className="w-3.5 h-3.5" /> Conditions du programme
        </summary>
        <ul className="mt-2 space-y-1 pl-1 list-disc list-inside">
          {(cms.conditions?.length ? cms.conditions : referralConditions(rules)).map((c: any, i: number) => (
            <li key={i}>{typeof c === "string" ? c : c.text}</li>
          ))}
        </ul>
      </details>

    </main>
  );
}
