import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import {
  Copy, Trophy, Users, Coins,
  Gift, Download, ExternalLink, ChevronDown,
} from "lucide-react";
import {
  referralConditions,
  referralMetaDescription,
  fillReferralTokens,
  resolveReferralRules,
  REFERRAL_HERO_SUBTITLE_TEMPLATE,
  DEFAULT_COMMISSION_PCT,
  DEFAULT_MAX_STAKES,
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
    { name: "description", content: referralMetaDescription() },
  ] }),
});

type Tab = "filleuls" | "commissions" | "classement";

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

export default function ParrainagePage() {
  const { profile, user } = useAuth();
  const [tab, setTab] = useState<Tab>("filleuls");
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

  const refCode = profile?.referral_code || "";

  const copyCode = () => { copyText(refCode).then(ok => toast[ok ? "success" : "error"](ok ? "Code copié !" : "Impossible de copier")); };


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

    // Realtime : dès qu'une commission arrive ou qu'un filleul valide son téléphone, on rafraîchit
    const ch = supabase
      .channel(`ref-dash-${user.id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "referral_events", filter: `referrer_id=eq.${user.id}` }, refresh)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "profiles", filter: `referred_by=eq.${user.id}` }, refresh)
      .subscribe();

    const onFocus = () => refresh();
    window.addEventListener("focus", onFocus);

    return () => {
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

  const TABS: { id: Tab; label: string; icon: string }[] = [
    { id: "filleuls",    label: "Filleuls",    icon: "👥" },
    { id: "commissions", label: "Gains",       icon: "💰" },
    { id: "classement",  label: "Classement",  icon: "🏆" },
  ];

  const copyLink = () => {
    if (!downloadUrl) return;
    copyText(downloadUrl).then(ok => toast[ok ? "success" : "error"](ok ? "Lien copié !" : "Impossible de copier"));
  };

  if (loading || referralEnabled === null) return (
    <main className="max-w-xl mx-auto px-4 py-10 text-center text-muted-foreground">
      <div className="animate-pulse text-4xl mb-3">⏳</div>
      Chargement du programme de parrainage…
    </main>
  );

  if (!referralEnabled) return (
    <main className="max-w-xl mx-auto px-4 py-10 text-center">
      <div className="text-4xl mb-3">🚫</div>
      <p className="text-muted-foreground font-semibold">
        Programme de parrainage désactivé pour le moment
      </p>
    </main>
  );

  return (
    <main className="max-w-xl mx-auto w-full px-3 pt-2 pb-2 h-[calc(100dvh-14rem)] flex flex-col gap-2.5 overflow-hidden">
      {/* ── Hero compact ── */}
      <div className="rounded-2xl bg-gradient-to-br from-primary/15 via-card to-violet-500/10 border border-border/60 p-3 space-y-2.5 shrink-0">
        <div className="flex items-center gap-2">
          <Gift className="w-4 h-4 text-primary shrink-0" />
          <h1 className="text-base font-extrabold leading-none">Invitez vos amis</h1>
        </div>

        {/* 1. Lien de téléchargement — mis en valeur */}
        <div className="space-y-1">
          <div className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">1 · Partagez le lien</div>
          <div className="flex items-center gap-1.5">
            <button
              onClick={copyLink}
              disabled={!downloadUrl}
              className="flex-1 min-w-0 h-12 flex items-center gap-2 px-3 rounded-2xl bg-primary text-primary-foreground font-semibold text-sm shadow-[var(--shadow-soft)] active:scale-[0.98] transition-all disabled:opacity-50"
            >
              <Download className="w-4 h-4 shrink-0" />
              <span className="truncate">{downloadUrl ? downloadUrl.replace(/^https?:\/\//, "") : "Lien bientôt disponible"}</span>
              <Copy className="w-4 h-4 shrink-0 ml-auto opacity-90" />
            </button>
            {downloadUrl && (
              <a href={downloadUrl} target="_blank" rel="noopener noreferrer"
                aria-label="Ouvrir le lien"
                className="h-12 w-12 shrink-0 rounded-2xl bg-secondary flex items-center justify-center text-muted-foreground active:scale-95 transition-transform">
                <ExternalLink className="w-4 h-4" />
              </a>
            )}
          </div>
        </div>

        {/* 2. Code de parrainage */}
        <div className="space-y-1">
          <div className="text-[10px] font-bold uppercase tracking-wider text-muted-foreground">2 · Donnez votre code</div>
          <button onClick={copyCode}
            className="w-full h-12 flex items-center justify-center gap-3 px-3 rounded-2xl bg-primary/10 border-2 border-dashed border-primary/40 active:scale-[0.98] transition-all">
            <span className="font-mono font-extrabold text-primary text-xl tracking-[0.15em] truncate">{refCode}</span>
            <Copy className="w-4 h-4 shrink-0 text-primary" />
          </button>
        </div>

        {/* Stats */}
        <div className="grid grid-cols-3 gap-1.5">
          <StatCard icon={<Users className="w-3 h-3" />} label="Filleuls" value={totalRefs} />
          <StatCard icon={<Coins className="w-3 h-3" />} label="Gains" value={`${Math.round(totalEarned).toLocaleString("fr-FR")} Ar`} color="text-emerald-600" />
          <StatCard icon={<Trophy className="w-3 h-3" />} label="Rang" value={myRank ? `#${myRank}` : "—"} color="text-amber-500" />
        </div>
      </div>

      {/* ── Tabs ── */}
      <div className="flex gap-1 bg-secondary/60 rounded-2xl p-1 shrink-0">
        {TABS.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className={`flex-1 flex items-center justify-center gap-1 px-2 py-1.5 rounded-xl text-xs font-semibold transition-all ${tab === t.id ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"}`}>
            <span>{t.icon}</span>{t.label}
          </button>
        ))}
      </div>

      {/* ── Contenu (seule zone défilante) ── */}
      <div className="flex-1 min-h-0 overflow-y-auto rounded-2xl bg-card px-3 py-2 shadow-sm">
        {tab === "filleuls" && (
          referrals.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center gap-2 py-6">
              <div className="text-3xl">🤷</div>
              <div className="text-xs text-muted-foreground">Aucun filleul pour l'instant.</div>
              <button onClick={copyCode} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold text-xs">
                Copier mon code
              </button>
            </div>
          ) : referrals.map((r: any) => {
            const earned = Number(r.total_earned || 0);
            const stakeCount = Number(r.referral_stake_count ?? r.stake_count ?? 0);
            const phoneVerified = !!r.phone_verified;
            return (
              <div key={r.id} className="flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0">
                <div className="w-9 h-9 rounded-full bg-accent flex items-center justify-center font-bold text-xs shrink-0 overflow-hidden">
                  {r.avatar_url
                    ? <img src={r.avatar_url} width={36} height={36} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                    : (r.pseudo || "?").slice(0, 2).toUpperCase()}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">{r.pseudo}</div>
                  <div className="text-[10px] text-muted-foreground">
                    {phoneVerified ? `${stakeCount}/${maxStakes} parties payantes` : "📱 En attente de vérification"}
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

        {tab === "commissions" && (
          events.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center gap-2 py-6 text-xs text-muted-foreground">
              <div className="text-3xl">💰</div>
              Aucune commission reçue pour l'instant.
            </div>
          ) : events.map((e: any) => (
            <div key={e.id} className="flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0">
              <div className="w-8 h-8 rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center text-sm shrink-0">💰</div>
              <div className="flex-1 min-w-0">
                <div className="text-sm font-semibold truncate">{e.referee_pseudo}</div>
                <div className="text-[10px] text-muted-foreground">
                  {e.match_index != null && `🎮 ${e.match_index}/${e.match_max ?? maxStakes} · `}
                  {new Date(e.created_at).toLocaleDateString("fr-FR", { dateStyle: "short" })}
                </div>
              </div>
              <div className="text-emerald-600 font-extrabold text-sm shrink-0">
                +{Math.round(Number(e.reward_amount)).toLocaleString("fr-FR")} Ar
              </div>
            </div>
          ))
        )}

        {tab === "classement" && (
          leaderboard.length === 0 ? (
            <div className="h-full flex flex-col items-center justify-center text-center gap-2 py-6 text-xs text-muted-foreground">
              <div className="text-3xl">🏆</div>
              Soyez le premier au classement !
            </div>
          ) : leaderboard.map((lb: any) => {
            const isMe = lb.referrer_id === user?.id;
            return (
              <div key={lb.referrer_id}
                className={`flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0 ${isMe ? "bg-primary/5 rounded-xl px-2" : ""}`}>
                <div className="w-6 text-center font-extrabold text-xs shrink-0">
                  {lb.rank === 1 ? "👑" : lb.rank === 2 ? "🥈" : lb.rank === 3 ? "🥉" : lb.rank}
                </div>
                <Link to="/joueur/$id" params={{ id: lb.referrer_id }}
                  className="w-8 h-8 rounded-full bg-accent overflow-hidden flex items-center justify-center font-bold text-xs shrink-0">
                  {lb.avatar_url
                    ? <img src={lb.avatar_url} width={32} height={32} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                    : (lb.pseudo || "?").slice(0, 2).toUpperCase()}
                </Link>
                <div className="flex-1 min-w-0">
                  <div className={`font-bold text-sm truncate ${isMe ? "text-primary" : ""}`}>{lb.pseudo}</div>
                  <div className="text-[10px] text-muted-foreground">{lb.total_referrals || 0} filleuls</div>
                </div>
                <div className="font-extrabold text-sm text-emerald-600 shrink-0">
                  {Math.round(Number(lb.total_earned_ar)).toLocaleString("fr-FR")} Ar
                </div>
              </div>
            );
          })
        )}
      </div>

      {/* ── Explication en base, une ligne + conditions repliables ── */}
      <details className="shrink-0 rounded-2xl bg-secondary/50 px-3 py-2 group">
        <summary className="list-none flex items-center gap-2 cursor-pointer">
          <p className="flex-1 text-[11px] leading-snug text-muted-foreground">
            <b className="text-foreground">{firstDepositBonus} Ar</b> au 1<sup>er</sup> dépôt de votre filleul, puis{" "}
            <b className="text-foreground">{commissionPct}%</b> de chaque mise sur ses{" "}
            <b className="text-foreground">{maxStakes}</b> premières parties payantes.
          </p>
          <ChevronDown className="w-4 h-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" />
        </summary>
        <div className="mt-2 space-y-1 text-[10px] leading-snug text-muted-foreground border-t border-border/40 pt-2">
          {(cms.conditions?.length ? cms.conditions.map(c => fillReferralTokens(c, rules)) : referralConditions(rules)).map((c, i) => (
            <p key={i}>• {c}</p>
          ))}
        </div>
      </details>
    </main>
  );
}
