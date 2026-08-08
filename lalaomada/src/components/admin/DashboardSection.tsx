import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Wallet, Users, Trophy, MessageSquare, Gamepad2, TrendingUp, TrendingDown, AlertCircle, Clock, ArrowRight, RefreshCw } from "lucide-react";

type PendingData = {
  deposits: number;
  withdrawals: number;
  phoneRequests: number;
  passwordResets: number;
  runningTournaments: number;
  bugReports: number;
  supportMessages: number;
  totalUsers: number;
  activeUsersToday: number;
  totalGames: number;
  totalCommission: number;
  loading: boolean;
};

export default function DashboardSection({
  onGoToTab,
}: {
  onGoToTab: (tab: string, sectionId?: string) => void;
}) {
  const [d, setD] = useState<PendingData>({
    deposits: 0, withdrawals: 0, phoneRequests: 0, passwordResets: 0,
    runningTournaments: 0, bugReports: 0, supportMessages: 0,
    totalUsers: 0, activeUsersToday: 0, totalGames: 0, totalCommission: 0,
    loading: true,
  });
  const [days] = useState(7);
  const [stats, setStats] = useState<any[]>([]);
  const [statsLoading, setStatsLoading] = useState(false);

  const load = async () => {
    setD(prev => ({ ...prev, loading: true }));
    try {
      const [
        depRes, wdRes, phoneRes, resetRes, tRunRes, bugRes, supportRes,
        usersRes,
      ] = await Promise.all([
        supabase.from("deposits").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.from("withdrawals").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.rpc("admin_list_phone_requests" as any),
        (supabase.from("password_reset_requests" as any) as any)
          .select("*", { count: "exact", head: true })
          .in("status", ["pending", "sent"]),
        (supabase.from("tournaments" as any) as any).select("*", { count: "exact", head: true }).eq("status", "running"),
        supabase.from("bug_reports").select("*", { count: "exact", head: true }).eq("status", "open"),
        (supabase.from("support_messages" as any) as any).select("*", { count: "exact", head: true }).is("reply", null),
        supabase.from("profiles").select("*", { count: "exact", head: true }),
      ]);

      setD({
        deposits: depRes.count ?? 0,
        withdrawals: wdRes.count ?? 0,
        phoneRequests: Array.isArray((phoneRes as any).data) ? (phoneRes as any).data.length : 0,
        passwordResets: (resetRes as any).count ?? 0,
        runningTournaments: (tRunRes as any).count ?? 0,
        bugReports: (bugRes as any).count ?? 0,
        supportMessages: (supportRes as any).count ?? 0,
        totalUsers: (usersRes as any).count ?? 0,
        activeUsersToday: 0,
        totalGames: 0,
        totalCommission: 0,
        loading: false,
      });
    } catch {
      setD(prev => ({ ...prev, loading: false }));
    }

    // Load 7-day stats
    setStatsLoading(true);
    try {
      const { data } = await supabase.rpc("admin_stats_daily" as any, { _days: days } as any);
      setStats((data as any[]) || []);
    } finally {
      setStatsLoading(false);
    }
  };

  useEffect(() => { load(); }, []);

  const totals = stats.reduce((acc, r) => ({
    deposits: acc.deposits + Number(r.deposits || 0),
    withdrawals: acc.withdrawals + Number(r.withdrawals || 0),
    commission: acc.commission + Number(r.commission || 0),
    games: acc.games + Number(r.games_finished || 0),
    new_users: acc.new_users + Number(r.new_users || 0),
    active_users: Math.max(acc.active_users, Number(r.active_users || 0)),
  }), { deposits: 0, withdrawals: 0, commission: 0, games: 0, new_users: 0, active_users: 0 });

  const netProfit = totals.commission - Math.max(0, totals.withdrawals - totals.deposits);
  const pendingFinance = d.deposits + d.withdrawals;
  const pendingJoueurs = d.phoneRequests + d.passwordResets;
  const pendingContenu = d.bugReports + d.supportMessages;
  const maxCommission = Math.max(1, ...stats.map(r => Number(r.commission || 0)));

  type QuickCard = {
    icon: React.ReactNode;
    label: string;
    count: number;
    tab: string;
    sectionId?: string;
    accent: string;
  };

  const cards: QuickCard[] = [
    { icon: <Wallet className="w-5 h-5" />, label: "Dépôts en attente", count: d.deposits, tab: "finance", accent: "emerald" },
    { icon: <Wallet className="w-5 h-5" />, label: "Retraits en attente", count: d.withdrawals, tab: "finance", accent: "rose" },
    { icon: <MessageSquare className="w-5 h-5" />, label: "Messages support", count: d.supportMessages, tab: "contenu", sectionId: "content-support", accent: "primary" },
    { icon: <AlertCircle className="w-5 h-5" />, label: "Signalements", count: d.bugReports, tab: "contenu", accent: "amber" },
    { icon: <Users className="w-5 h-5" />, label: "Vérif. téléphone", count: d.phoneRequests, tab: "joueurs", sectionId: "players-security", accent: "sky" },
    { icon: <Clock className="w-5 h-5" />, label: "Reset mots de passe", count: d.passwordResets, tab: "joueurs", sectionId: "players-security", accent: "violet" },
    { icon: <Trophy className="w-5 h-5" />, label: "Tournois en cours", count: d.runningTournaments, tab: "jeux", sectionId: "tournaments-main", accent: "amber" },
  ];

  const ACCENT_CLASSES: Record<string, string> = {
    emerald: "from-emerald-500/15 to-emerald-500/5 text-emerald-600 border-emerald-500/20",
    rose: "from-rose-500/15 to-rose-500/5 text-rose-600 border-rose-500/20",
    primary: "from-primary/15 to-primary/5 text-primary border-primary/20",
    amber: "from-amber-500/15 to-amber-500/5 text-amber-600 border-amber-500/20",
    sky: "from-sky-500/15 to-sky-500/5 text-sky-600 border-sky-500/20",
    violet: "from-violet-500/15 to-violet-500/5 text-violet-600 border-violet-500/20",
  };

  const totalPending = pendingFinance + pendingJoueurs + pendingContenu + d.runningTournaments;

  return (
    <div className="space-y-4">
      {/* Pending overview banner */}
      <div className={`rounded-3xl border p-5 ${totalPending > 0 ? "bg-gradient-to-br from-amber-500/10 to-rose-500/5 border-amber-500/30" : "bg-gradient-to-br from-emerald-500/10 to-emerald-500/5 border-emerald-500/20"}`}>
        <div className="flex items-center justify-between">
          <div>
            <div className="text-[11px] uppercase tracking-wide font-semibold text-muted-foreground">
              {totalPending > 0 ? "⏰ En attente d'action" : "✅ Tout est à jour"}
            </div>
            <div className={`text-3xl font-extrabold mt-1 ${totalPending > 0 ? "text-amber-600" : "text-emerald-600"}`}>
              {totalPending}
            </div>
            <div className="text-xs text-muted-foreground mt-0.5">
              {totalPending > 0 ? "éléments nécessitent votre attention" : "aucune action requise"}
            </div>
          </div>
          <button onClick={load} className="p-3 rounded-2xl bg-card hover:bg-accent transition-colors">
            <RefreshCw className={`w-5 h-5 ${d.loading ? "animate-spin" : ""}`} />
          </button>
        </div>
      </div>

      {/* Quick action cards */}
      {totalPending > 0 && (
        <div className="grid grid-cols-2 sm:grid-cols-3 gap-2.5">
          {cards.filter(c => c.count > 0).map((c, i) => (
            <button
              key={i}
              onClick={() => onGoToTab(c.tab, c.sectionId)}
              className={`text-left rounded-2xl border p-4 bg-gradient-to-br ${ACCENT_CLASSES[c.accent]} active:scale-95 transition-transform`}
            >
              <div className="flex items-center justify-between">
                {c.icon}
                <span className="text-2xl font-extrabold">{c.count}</span>
              </div>
              <div className="text-xs font-semibold mt-2 flex items-center gap-1">
                {c.label}
                <ArrowRight className="w-3 h-3" />
              </div>
            </button>
          ))}
        </div>
      )}

      {/* 7-day stats summary */}
      <div className="rounded-3xl bg-card border border-border/50 p-5 space-y-4">
        <div className="flex items-center justify-between">
          <div className="font-bold text-sm flex items-center gap-2">
            <TrendingUp className="w-4 h-4 text-primary" /> 7 derniers jours
          </div>
          <button
            onClick={() => onGoToTab("stats")}
            className="text-xs text-primary font-semibold flex items-center gap-1 hover:underline"
          >
            Voir détails <ArrowRight className="w-3 h-3" />
          </button>
        </div>

        {/* Net profit */}
        <div className="rounded-2xl bg-gradient-to-br from-primary/15 to-primary/5 border border-primary/20 p-4">
          <div className="text-[11px] uppercase tracking-wide text-muted-foreground font-semibold">Bénéfice net estimé</div>
          <div className={`text-2xl font-extrabold ${netProfit >= 0 ? "text-emerald-600" : "text-destructive"}`}>
            {netProfit >= 0 ? "+" : ""}{Math.round(netProfit).toLocaleString("fr-FR")} Ar
          </div>
          <div className="text-[11px] text-muted-foreground mt-0.5">Commission − (retraits − dépôts) sur 7j</div>
        </div>

        {/* Mini stats grid */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
          {[
            { label: "💰 Commission", value: totals.commission, suffix: "Ar", color: "text-primary" },
            { label: "📥 Dépôts", value: totals.deposits, suffix: "Ar", color: "text-emerald-600" },
            { label: "📤 Retraits", value: totals.withdrawals, suffix: "Ar", color: "text-destructive" },
            { label: "🎮 Parties", value: totals.games, color: "text-sky-600" },
            { label: "👥 Nouveaux", value: totals.new_users, color: "text-fuchsia-600" },
            { label: "⚡ Actifs (pic)", value: totals.active_users, color: "text-teal-600" },
            { label: "📊 Total joueurs", value: d.totalUsers, color: "text-indigo-600" },
            { label: "🏆 Tournois actifs", value: d.runningTournaments, color: "text-amber-600" },
          ].map((s, i) => (
            <div key={i} className="rounded-2xl bg-secondary p-3 text-center">
              <div className="text-[10px] uppercase text-muted-foreground font-semibold">{s.label}</div>
              <div className={`text-base font-extrabold ${s.color} leading-tight mt-0.5`}>
                {Math.round(s.value).toLocaleString("fr-FR")}{s.suffix ? <span className="text-[10px] font-semibold text-muted-foreground ml-0.5">{s.suffix}</span> : null}
              </div>
            </div>
          ))}
        </div>

        {/* Mini chart */}
        {stats.length > 0 && !statsLoading && (
          <div>
            <div className="font-bold text-xs uppercase text-muted-foreground mb-2">Commission par jour</div>
            <div className="flex items-end gap-1 h-16">
              {[...stats].reverse().map(r => {
                const v = Number(r.commission || 0);
                const h = Math.max(2, Math.round((v / maxCommission) * 100));
                return (
                  <div key={r.day} className="flex-1 flex flex-col items-center gap-1">
                    <div className="w-full bg-primary/70 rounded-t" style={{ height: `${h}%` }}
                      title={`${new Date(r.day).toLocaleDateString("fr-FR")} · ${Math.round(v).toLocaleString("fr-FR")} Ar`} />
                    <div className="text-[8px] text-muted-foreground">{new Date(r.day).getDate()}</div>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>

      {/* Quick links */}
      <div className="grid grid-cols-2 gap-2.5">
        <button onClick={() => onGoToTab("finance")} className="rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform">
          <Wallet className="w-5 h-5 text-emerald-600 mb-2" />
          <div className="font-bold text-sm">Finance</div>
          <div className="text-xs text-muted-foreground">Dépôts, retraits, transactions</div>
        </button>
        <button onClick={() => onGoToTab("joueurs")} className="rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform">
          <Users className="w-5 h-5 text-sky-600 mb-2" />
          <div className="font-bold text-sm">Joueurs</div>
          <div className="text-xs text-muted-foreground">Comptes, sécurité, modération</div>
        </button>
        <button onClick={() => onGoToTab("jeux")} className="rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform">
          <Gamepad2 className="w-5 h-5 text-amber-600 mb-2" />
          <div className="font-bold text-sm">Jeux & Compétition</div>
          <div className="text-xs text-muted-foreground">Parties, tournois, classement</div>
        </button>
        <button onClick={() => onGoToTab("contenu")} className="rounded-2xl bg-card border border-border/50 p-4 text-left active:scale-95 transition-transform">
          <MessageSquare className="w-5 h-5 text-violet-600 mb-2" />
          <div className="font-bold text-sm">Contenu</div>
          <div className="text-xs text-muted-foreground">Support, annonces, bannières</div>
        </button>
      </div>
    </div>
  );
}
