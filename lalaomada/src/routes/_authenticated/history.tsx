import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import {
  Gamepad2, ArrowDownCircle, ArrowUpCircle,
  ReceiptText, Trophy, XCircle, Clock, Flame, Gift, Hourglass, CheckCircle2, Ban,
  Crown, Swords, Target, Spade, CircleDot, TrendingUp, TrendingDown,
  ChevronRight, CalendarDays, Wallet,
} from "lucide-react";

export const Route = createFileRoute("/_authenticated/history")({
  component: HistoryPage,
  head: () => ({ meta: [
    { title: "Historique — Lalao MADA" },
    { name: "description", content: "Suivi de vos dépôts, retraits, transactions et parties." },
  ] }),
});

type Tab = "pending" | "deposits" | "withdrawals" | "transactions" | "parties";
type StatusFilter = "all" | "pending" | "approved" | "rejected";

// ── Helpers ───────────────────────────────────────────────────────────────
function fmtDate(d: string) {
  return new Date(d).toLocaleString("fr-FR", {
    day: "2-digit", month: "2-digit", year: "2-digit",
    hour: "2-digit", minute: "2-digit",
  });
}
function fmtAr(n: number | null | undefined) {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-MG").format(Math.round(Number(n) || 0)) + " Ar";
}
function fmtArShort(n: number | null | undefined) {
  if (n == null) return "—";
  const v = Math.round(Number(n) || 0);
  if (Math.abs(v) >= 1_000_000) return (v / 1_000_000).toFixed(1).replace(/\.0$/, "") + "M Ar";
  if (Math.abs(v) >= 1_000) return (v / 1_000).toFixed(0) + "k Ar";
  return v + " Ar";
}
function relTime(d: string) {
  const diff = (Date.now() - new Date(d).getTime()) / 1000;
  if (diff < 60) return "à l'instant";
  if (diff < 3600) return `il y a ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `il y a ${Math.floor(diff / 3600)} h`;
  return `il y a ${Math.floor(diff / 86400)} j`;
}
function dateGroupLabel(d: string): string {
  const date = new Date(d);
  const today = new Date(); today.setHours(0,0,0,0);
  const yesterday = new Date(today); yesterday.setDate(yesterday.getDate() - 1);
  const dOnly = new Date(date); dOnly.setHours(0,0,0,0);
  if (dOnly.getTime() === today.getTime()) return "Aujourd'hui";
  if (dOnly.getTime() === yesterday.getTime()) return "Hier";
  return date.toLocaleDateString("fr-FR", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
}

// ── Game type metadata ───────────────────────────────────────────────────
const GAME_META: Record<string, { icon: React.ReactNode; label: string; color: string; bg: string }> = {
  "ludo_games":      { icon: <CircleDot className="w-4 h-4" />,    label: "Ludo",      color: "text-red-500",       bg: "bg-red-500/10" },
  "chess_games":     { icon: <Swords className="w-4 h-4" />,       label: "Échecs",    color: "text-violet-500",    bg: "bg-violet-500/10" },
  "domino_games":    { icon: <Target className="w-4 h-4" />,       label: "Domino",    color: "text-amber-600",      bg: "bg-amber-500/10" },
  "fanorona_games":  { icon: <Swords className="w-4 h-4" />,       label: "Fanorona",  color: "text-emerald-500",   bg: "bg-emerald-500/10" },
  "rami_games":      { icon: <Spade className="w-4 h-4" />,        label: "Rami",      color: "text-blue-500",       bg: "bg-blue-500/10" },
  "poker_games":     { icon: <Spade className="w-4 h-4" />,        label: "Poker",     color: "text-indigo-500",    bg: "bg-indigo-500/10" },
  "penalty_games":   { icon: <Target className="w-4 h-4" />,       label: "Penalty",   color: "text-orange-500",     bg: "bg-orange-500/10" },
  "petanque_games":  { icon: <CircleDot className="w-4 h-4" />,    label: "Pétanque",  color: "text-teal-500",      bg: "bg-teal-500/10" },
  "billiard_games":  { icon: <CircleDot className="w-4 h-4" />,    label: "Billard",   color: "text-cyan-500",      bg: "bg-cyan-500/10" },
};
function gameMeta(type: string) {
  return GAME_META[type] ?? { icon: <Gamepad2 className="w-4 h-4" />, label: type, color: "text-muted-foreground", bg: "bg-muted" };
}

// ── Transaction type metadata ────────────────────────────────────────────
const POSITIVE_KINDS = new Set(["game_win","tournament_win","daily_bonus","signup_bonus","referral","deposit","refund","win"]);
const NEGATIVE_KINDS = new Set(["game_loss","game_stake","stake","forfeit","withdrawal"]);

const TXKind: Record<string, { icon: React.ReactNode; label: string; color: string; bg: string }> = {
  game_win:       { icon: <Trophy className="w-4 h-4" />,          label: "Gain de partie",       color: "text-emerald-600",   bg: "bg-emerald-500/10" },
  game_loss:      { icon: <XCircle className="w-4 h-4" />,        label: "Pari perdu",            color: "text-rose-500",      bg: "bg-rose-500/10" },
  game_stake:     { icon: <Gamepad2 className="w-4 h-4" />,        label: "Mise de partie",        color: "text-orange-500",   bg: "bg-orange-500/10" },
  daily_bonus:    { icon: <Gift className="w-4 h-4" />,            label: "Bonus quotidien",       color: "text-amber-500",     bg: "bg-amber-500/10" },
  signup_bonus:   { icon: <Gift className="w-4 h-4" />,            label: "Bonus inscription",     color: "text-amber-500",     bg: "bg-amber-500/10" },
  referral:       { icon: <Flame className="w-4 h-4" />,           label: "Commission parrainage", color: "text-orange-500",   bg: "bg-orange-500/10" },
  deposit:        { icon: <ArrowDownCircle className="w-4 h-4" />, label: "Dépôt",                 color: "text-emerald-600",   bg: "bg-emerald-500/10" },
  withdrawal:     { icon: <ArrowUpCircle className="w-4 h-4" />,   label: "Retrait",               color: "text-rose-500",      bg: "bg-rose-500/10" },
  tournament_win: { icon: <Crown className="w-4 h-4" />,           label: "Gain tournoi",          color: "text-amber-600",     bg: "bg-amber-500/10" },
  refund:         { icon: <ReceiptText className="w-4 h-4" />,     label: "Remboursement",         color: "text-blue-500",      bg: "bg-blue-500/10" },
  win:            { icon: <Trophy className="w-4 h-4" />,          label: "Gain",                  color: "text-emerald-600",   bg: "bg-emerald-500/10" },
  stake:          { icon: <Gamepad2 className="w-4 h-4" />,        label: "Mise",                  color: "text-orange-500",   bg: "bg-orange-500/10" },
  forfeit:        { icon: <Ban className="w-4 h-4" />,             label: "Forfait",               color: "text-rose-400",     bg: "bg-rose-500/10" },
};
function txConfig(kind: string) {
  return TXKind[kind] ?? { icon: <ReceiptText className="w-4 h-4" />, label: kind, color: "text-muted-foreground", bg: "bg-muted" };
}

function StatusBadge({ status }: { status: string }) {
  const cfg: Record<string, { cls: string; icon: React.ReactNode; label: string }> = {
    pending:   { cls: "bg-amber-100 text-amber-700 border-amber-300",       icon: <Hourglass className="w-2.5 h-2.5" />,     label: "En attente" },
    approved:  { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", icon: <CheckCircle2 className="w-2.5 h-2.5" />, label: "Approuvé" },
    completed: { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", icon: <CheckCircle2 className="w-2.5 h-2.5" />, label: "Terminé" },
    rejected:  { cls: "bg-rose-100 text-rose-600 border-rose-300",          icon: <Ban className="w-2.5 h-2.5" />,           label: "Refusé" },
    cancelled: { cls: "bg-secondary text-muted-foreground border-border",   icon: <Ban className="w-2.5 h-2.5" />,           label: "Annulé" },
  };
  const c = cfg[status] ?? { cls: "bg-secondary text-muted-foreground border-border", icon: null, label: status };
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold border ${c.cls}`}>
      {c.icon}{c.label}
    </span>
  );
}

// ── Date grouping helper ──────────────────────────────────────────────────
function groupByDate<T extends { created_at: string }>(items: T[]): { label: string; items: T[] }[] {
  const groups: Record<string, T[]> = {};
  for (const item of items) {
    const label = dateGroupLabel(item.created_at);
    if (!groups[label]) groups[label] = [];
    groups[label].push(item);
  }
  return Object.entries(groups).map(([label, items]) => ({ label, items }));
}

// ── Main page ─────────────────────────────────────────────────────────────
export default function HistoryPage() {
  const { user } = useAuth();
  const [tab, setTab] = useState<Tab>("pending");
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all");
  const [tx, setTx] = useState<any[]>([]);
  const [deps, setDeps] = useState<any[]>([]);
  const [withs, setWiths] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [stakeGames, setStakeGames] = useState<any[]>([]);
  const [loadingStakeGames, setLoadingStakeGames] = useState(false);

  async function load() {
    if (!user) { setLoading(false); return; }
    const [t, d, w] = await Promise.allSettled([
      supabase.from("transactions").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(200),
      supabase.from("deposits").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(100),
      supabase.from("withdrawals").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(100),
    ]);
    setTx(t.status === "fulfilled" ? (t.value.data || []) : []);
    setDeps(d.status === "fulfilled" ? (d.value.data || []) : []);
    setWiths(w.status === "fulfilled" ? (w.value.data || []) : []);
    setLoading(false);
    setLoadingStakeGames(true);
    const { data: sg } = await supabase.rpc("get_player_stake_history" as any);
    setStakeGames(sg || []);
    setLoadingStakeGames(false);
  }

  useEffect(() => {
    let dt: ReturnType<typeof setTimeout>;
    const debouncedLoad = () => { clearTimeout(dt); dt = setTimeout(load, 800); };
    setLoading(true);
    load();
    if (!user) return;
    const ch = supabase
      .channel(`finance:${user.id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "deposits", filter: `user_id=eq.${user.id}` }, debouncedLoad)
      .on("postgres_changes", { event: "*", schema: "public", table: "withdrawals", filter: `user_id=eq.${user.id}` }, debouncedLoad)
      .on("postgres_changes", { event: "*", schema: "public", table: "transactions", filter: `user_id=eq.${user.id}` }, debouncedLoad)
      .subscribe();
    return () => { clearTimeout(dt); supabase.removeChannel(ch); };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  // ── Aggregations ──
  const pendingDeps  = useMemo(() => deps.filter(d => (d.status ?? "pending") === "pending"), [deps]);
  const pendingWiths = useMemo(() => withs.filter(w => (w.status ?? "pending") === "pending"), [withs]);
  const totalDeposited  = deps.filter(d => d.status === "approved").reduce((s, d) => s + Number(d.amount_ar ?? d.amount ?? 0), 0);
  const totalWithdrawn  = withs.filter(w => w.status === "approved").reduce((s, w) => s + Number(w.amount_ar ?? w.amount ?? 0), 0);
  const pendingDepAmt   = pendingDeps.reduce((s, d) => s + Number(d.amount_ar ?? d.amount ?? 0), 0);
  const pendingWithAmt  = pendingWiths.reduce((s, w) => s + Number(w.amount_ar ?? w.amount ?? 0), 0);
  const totalPending    = pendingDeps.length + pendingWiths.length;

  // ── Gains vs Pertes ──
  const gameWins = useMemo(() => tx.filter(t => ["game_win","tournament_win","win"].includes(t.kind)), [tx]);
  const gameLosses = useMemo(() => tx.filter(t => ["game_loss","stake","game_stake","forfeit"].includes(t.kind)), [tx]);
  const totalGagné = useMemo(() => gameWins.reduce((s, t) => s + Number(t.amount ?? 0), 0), [gameWins]);
  const totalPerdu = useMemo(() => gameLosses.reduce((s, t) => s + Math.abs(Number(t.amount ?? 0)), 0), [gameLosses]);
  const netProfit = totalGagné - totalPerdu;

  const finishedGames = useMemo(() => stakeGames.filter(g => g.status === "finished"), [stakeGames]);
  const gamesWon = useMemo(() => finishedGames.filter(g => g.is_winner), [finishedGames]);
  const gamesLost = useMemo(() => finishedGames.filter(g => !g.is_winner), [finishedGames]);
  const winRate = finishedGames.length > 0 ? Math.round((gamesWon.length / finishedGames.length) * 100) : 0;

  const filteredDeps  = statusFilter === "all" ? deps  : deps.filter(d => (d.status ?? "pending") === statusFilter);
  const filteredWiths = statusFilter === "all" ? withs : withs.filter(w => (w.status ?? "pending") === statusFilter);

  const txGroups = useMemo(() => groupByDate(tx), [tx]);
  const depGroups = useMemo(() => groupByDate(filteredDeps), [filteredDeps]);
  const withGroups = useMemo(() => groupByDate(filteredWiths), [filteredWiths]);
  const gameGroups = useMemo(() => groupByDate(stakeGames), [stakeGames]);

  const tabs: { id: Tab; label: string; icon: React.ReactNode; count: number; badge?: boolean }[] = [
    { id: "pending",      label: "En attente",   icon: <Hourglass className="w-4 h-4" />,       count: totalPending, badge: totalPending > 0 },
    { id: "deposits",     label: "Dépôts",       icon: <ArrowDownCircle className="w-4 h-4" />, count: deps.length },
    { id: "withdrawals",  label: "Retraits",     icon: <ArrowUpCircle className="w-4 h-4" />,   count: withs.length },
    { id: "transactions", label: "Transactions",  icon: <ReceiptText className="w-4 h-4" />,     count: tx.length },
    { id: "parties",      label: "Parties",      icon: <Gamepad2 className="w-4 h-4" />,        count: stakeGames.length },
  ];

  return (
    <main className="max-w-2xl mx-auto px-3 py-3 space-y-3 pb-24">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-extrabold flex items-center gap-2">
          <Wallet className="w-5 h-5 text-primary" /> Historique
        </h1>
        {totalPending > 0 && (
          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-amber-100 text-amber-700 border border-amber-300 animate-pulse">
            <Hourglass className="w-3 h-3" /> {totalPending} en attente
          </span>
        )}
      </div>

      {/* ── Gagné vs Perdu — la distinction principale ── */}
      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-2xl p-3.5 bg-gradient-to-br from-emerald-500 to-emerald-600 text-white shadow-lg">
          <div className="flex items-center gap-1.5 text-[11px] font-semibold opacity-90">
            <TrendingUp className="w-3.5 h-3.5" /> Gagné
          </div>
          <div className="text-xl font-extrabold tabular-nums mt-1 leading-tight">+{fmtAr(totalGagné)}</div>
          <div className="text-[10px] mt-1 opacity-80 flex items-center gap-1">
            <Trophy className="w-2.5 h-2.5" /> {gameWins.length} gain{gameWins.length > 1 ? "s" : ""}
          </div>
        </div>
        <div className="rounded-2xl p-3.5 bg-gradient-to-br from-rose-500 to-rose-600 text-white shadow-lg">
          <div className="flex items-center gap-1.5 text-[11px] font-semibold opacity-90">
            <TrendingDown className="w-3.5 h-3.5" /> Perdu
          </div>
          <div className="text-xl font-extrabold tabular-nums mt-1 leading-tight">−{fmtAr(totalPerdu)}</div>
          <div className="text-[10px] mt-1 opacity-80 flex items-center gap-1">
            <XCircle className="w-2.5 h-2.5" /> {gameLosses.length} perte{gameLosses.length > 1 ? "s" : ""}
          </div>
        </div>
      </div>

      {/* ── Résultat net ── */}
      <div className={`rounded-2xl p-3.5 border-2 shadow-sm ${netProfit > 0 ? "border-emerald-500/30 bg-emerald-50 dark:bg-emerald-950/10" : netProfit < 0 ? "border-rose-500/30 bg-rose-50 dark:bg-rose-950/10" : "border-border bg-card"}`}>
        <div className="flex items-center justify-between">
          <span className="text-sm font-bold flex items-center gap-1.5">
            {netProfit > 0 ? <TrendingUp className="w-4 h-4 text-emerald-600" /> : netProfit < 0 ? <TrendingDown className="w-4 h-4 text-rose-500" /> : <ReceiptText className="w-4 h-4 text-muted-foreground" />}
            Résultat net
          </span>
          <span className={`text-lg font-extrabold tabular-nums ${netProfit > 0 ? "text-emerald-600" : netProfit < 0 ? "text-rose-500" : "text-muted-foreground"}`}>
            {netProfit > 0 ? "+" : netProfit < 0 ? "−" : ""}{fmtAr(Math.abs(netProfit))}
          </span>
        </div>
        {stakeGames.length > 0 && (
          <div className="mt-2 pt-2 border-t border-border/40 flex items-center gap-4 text-[11px]">
            <span className="text-muted-foreground">{stakeGames.length} parties</span>
            <span className="text-emerald-600 font-semibold">{gamesWon.length} V</span>
            <span className="text-rose-500 font-semibold">{gamesLost.length} D</span>
            <span className={`font-bold ${winRate >= 50 ? "text-emerald-600" : "text-rose-500"}`}>{winRate}%</span>
          </div>
        )}
      </div>

      {/* ── Dépôts / Retraits résumé ── */}
      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-xl p-2.5 bg-card border border-border shadow-sm">
          <div className="flex items-center gap-1.5 text-[10px] font-semibold text-muted-foreground">
            <ArrowDownCircle className="w-3 h-3 text-emerald-600" /> Total déposé
          </div>
          <div className="text-sm font-extrabold tabular-nums text-emerald-600 mt-0.5">{fmtAr(totalDeposited)}</div>
          {pendingDepAmt > 0 && <div className="text-[9px] text-amber-600 mt-0.5">{fmtAr(pendingDepAmt)} en attente</div>}
        </div>
        <div className="rounded-xl p-2.5 bg-card border border-border shadow-sm">
          <div className="flex items-center gap-1.5 text-[10px] font-semibold text-muted-foreground">
            <ArrowUpCircle className="w-3 h-3 text-rose-500" /> Total retiré
          </div>
          <div className="text-sm font-extrabold tabular-nums text-rose-500 mt-0.5">{fmtAr(totalWithdrawn)}</div>
          {pendingWithAmt > 0 && <div className="text-[9px] text-amber-600 mt-0.5">{fmtAr(pendingWithAmt)} en attente</div>}
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-card/80 p-1 rounded-2xl shadow-sm border border-border overflow-x-auto">
        {tabs.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className={`relative flex-1 min-w-[70px] flex items-center justify-center gap-1 py-2.5 rounded-xl text-[11px] font-bold transition-all whitespace-nowrap ${tab === t.id ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "text-muted-foreground hover:text-foreground"}`}>
            {t.icon} {t.label}
            {t.count > 0 && (
              <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${tab === t.id ? "bg-white/25" : t.badge ? "bg-amber-500 text-white" : "bg-muted"}`}>
                {t.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Status filter */}
      {(tab === "deposits" || tab === "withdrawals") && (
        <div className="flex gap-1.5 text-[11px]">
          {([
            { id: "all",      label: "Tous" },
            { id: "pending",  label: "En attente" },
            { id: "approved", label: "Approuvés" },
            { id: "rejected", label: "Refusés" },
          ] as { id: StatusFilter; label: string }[]).map(f => (
            <button key={f.id} onClick={() => setStatusFilter(f.id)}
              className={`px-2.5 py-1 rounded-full font-semibold border transition-all ${statusFilter === f.id ? "bg-primary text-primary-foreground border-primary" : "bg-card border-border text-muted-foreground"}`}>
              {f.label}
            </button>
          ))}
        </div>
      )}

      {/* Content */}
      {loading ? (
        <div className="flex justify-center py-12">
          <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
        </div>
      ) : (
        <div className="space-y-3">

          {/* En attente */}
          {tab === "pending" && (
            (pendingDeps.length + pendingWiths.length) === 0
              ? <EmptyState icon={<CheckCircle2 className="w-10 h-10" />} label="Rien en attente 🎉" hint="Tous vos dépôts et retraits sont traités." />
              : <div className="space-y-2">
                  {pendingDeps.map(item => <PendingItem key={"d-"+item.id} kind="deposit" item={item} />)}
                  {pendingWiths.map(item => <PendingItem key={"w-"+item.id} kind="withdrawal" item={item} />)}
                </div>
          )}

          {/* Dépôts — groupés par date */}
          {tab === "deposits" && (
            filteredDeps.length === 0
              ? <EmptyState label="Aucun dépôt" />
              : depGroups.map(group => (
                  <div key={group.label} className="space-y-1">
                    <DateHeader label={group.label} count={group.items.length} />
                    <div className="rounded-2xl bg-card shadow-sm border border-border overflow-hidden">
                      <div className="divide-y divide-border/40">
                        {group.items.map(item => <FinanceRow key={item.id} kind="deposit" item={item} />)}
                      </div>
                    </div>
                  </div>
                ))
          )}

          {/* Retraits — groupés par date */}
          {tab === "withdrawals" && (
            filteredWiths.length === 0
              ? <EmptyState label="Aucun retrait" />
              : withGroups.map(group => (
                  <div key={group.label} className="space-y-1">
                    <DateHeader label={group.label} count={group.items.length} />
                    <div className="rounded-2xl bg-card shadow-sm border border-border overflow-hidden">
                      <div className="divide-y divide-border/40">
                        {group.items.map(item => <FinanceRow key={item.id} kind="withdrawal" item={item} />)}
                      </div>
                    </div>
                  </div>
                ))
          )}

          {/* Transactions — groupées par date, bordure colorée gain/perte */}
          {tab === "transactions" && (
            tx.length === 0
              ? <EmptyState label="Aucune transaction" />
              : txGroups.map(group => (
                  <div key={group.label} className="space-y-1">
                    <DateHeader label={group.label} count={group.items.length} />
                    <div className="rounded-2xl bg-card shadow-sm border border-border overflow-hidden">
                      <div className="divide-y divide-border/40">
                        {group.items.map(item => {
                          const cfg = txConfig(item.kind);
                          const amount = Number(item.amount ?? 0);
                          const isPositive = POSITIVE_KINDS.has(item.kind);
                          const isNegative = NEGATIVE_KINDS.has(item.kind);
                          return (
                            <div key={item.id} className={`flex items-start gap-3 p-3.5 border-l-4 ${isPositive ? "border-l-emerald-500 bg-emerald-50/30 dark:bg-emerald-950/5" : isNegative ? "border-l-rose-500 bg-rose-50/30 dark:bg-rose-950/5" : "border-l-border"}`}>
                              <div className={`mt-0.5 p-2 rounded-xl border border-border/50 ${cfg.bg} ${cfg.color}`}>{cfg.icon}</div>
                              <div className="flex-1 min-w-0">
                                <div className="font-semibold text-sm">{cfg.label}</div>
                                {item.meta?.game && <div className="text-[10px] text-muted-foreground">{item.meta.game}</div>}
                                {item.meta?.streak && <div className="text-[10px] text-amber-600">🔥 Série {item.meta.streak} jours{item.meta.multiplier > 1 ? ` (×${item.meta.multiplier})` : ""}</div>}
                                <div className="text-[10px] text-muted-foreground flex items-center gap-1 mt-0.5"><Clock className="w-2.5 h-2.5" />{fmtDate(item.created_at)}</div>
                              </div>
                              <div className={`font-extrabold text-sm tabular-nums ${isPositive ? "text-emerald-600" : isNegative ? "text-rose-500" : "text-muted-foreground"}`}>
                                {isPositive ? "+" : isNegative ? "−" : ""}{fmtAr(Math.abs(amount))}
                              </div>
                            </div>
                          );
                        })}
                      </div>
                    </div>
                  </div>
                ))
          )}

          {/* Parties */}
          {tab === "parties" && (
            <StakeGameHistory games={stakeGames} loading={loadingStakeGames} gameGroups={gameGroups} />
          )}
        </div>
      )}
    </main>
  );
}

// ── Date header ───────────────────────────────────────────────────────────
function DateHeader({ label, count }: { label: string; count: number }) {
  return (
    <div className="flex items-center gap-2 px-1 pt-2 pb-1">
      <CalendarDays className="w-3.5 h-3.5 text-muted-foreground" />
      <span className="text-xs font-bold text-muted-foreground capitalize">{label}</span>
      <span className="text-[10px] text-muted-foreground/70">({count})</span>
      <div className="flex-1 h-px bg-border/40" />
    </div>
  );
}

// ── Pending item ──────────────────────────────────────────────────────────
function PendingItem({ kind, item }: { kind: "deposit" | "withdrawal"; item: any }) {
  const isDep = kind === "deposit";
  const amount = Number(item.amount_ar ?? item.amount ?? 0);
  return (
    <div className="rounded-2xl p-3.5 bg-amber-50/60 dark:bg-amber-950/10 border border-amber-300/50 border-l-4 border-l-amber-400">
      <div className="flex items-start gap-3">
        <div className={`mt-0.5 p-2 rounded-xl ${isDep ? "bg-emerald-100 dark:bg-emerald-900/30 text-emerald-600" : "bg-rose-100 dark:bg-rose-900/30 text-rose-500"}`}>
          {isDep ? <ArrowDownCircle className="w-4 h-4" /> : <ArrowUpCircle className="w-4 h-4" />}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <div className="font-semibold text-sm">{isDep ? "Dépôt" : "Retrait"}</div>
            <StatusBadge status="pending" />
          </div>
          {item.operator && <div className="text-[11px] text-muted-foreground mt-0.5">📱 {item.operator}{item.phone ? ` · ${item.phone}` : ""}</div>}
          <div className="text-[10px] text-muted-foreground flex items-center gap-1 mt-1"><Clock className="w-2.5 h-2.5" /> {fmtDate(item.created_at)} · {relTime(item.created_at)}</div>
        </div>
        <div className={`font-extrabold text-base ${isDep ? "text-emerald-600" : "text-rose-500"} tabular-nums`}>
          {isDep ? "+" : "−"}{fmtAr(amount)}
        </div>
      </div>
      <div className="mt-2 text-[10px] text-amber-700 dark:text-amber-400 font-medium">⏳ En cours de traitement par l'administrateur.</div>
    </div>
  );
}

// ── Finance row (deposits/withdrawals) ───────────────────────────────────
function FinanceRow({ kind, item }: { kind: "deposit" | "withdrawal"; item: any }) {
  const isDep = kind === "deposit";
  const amount = Number(item.amount_ar ?? item.amount ?? 0);
  const status = item.status ?? "pending";
  return (
    <div className={`flex items-start gap-3 p-3.5 border-l-4 ${isDep ? "border-l-emerald-500" : "border-l-rose-500"}`}>
      <div className={`mt-0.5 p-2 rounded-xl ${isDep ? "bg-emerald-100 dark:bg-emerald-900/30 text-emerald-600" : "bg-rose-100 dark:bg-rose-900/30 text-rose-500"}`}>
        {isDep ? <ArrowDownCircle className="w-4 h-4" /> : <ArrowUpCircle className="w-4 h-4" />}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <div className="font-semibold text-sm">{isDep ? "Dépôt" : "Retrait"}</div>
          <StatusBadge status={status} />
        </div>
        {item.operator && <div className="text-[11px] text-muted-foreground mt-0.5">📱 {item.operator}{item.phone ? ` · ${item.phone}` : ""}</div>}
        {item.reject_reason && status === "rejected" && <div className="text-[10px] text-rose-600 mt-0.5">Raison : {item.reject_reason}</div>}
        <div className="text-[10px] text-muted-foreground flex items-center gap-1 mt-0.5"><Clock className="w-2.5 h-2.5" /> {fmtDate(item.created_at)}</div>
      </div>
      <div className={`font-extrabold text-sm ${status === "rejected" || status === "cancelled" ? "text-muted-foreground line-through" : isDep ? "text-emerald-600" : "text-rose-500"} tabular-nums`}>
        {isDep ? "+" : "−"}{fmtAr(amount)}
      </div>
    </div>
  );
}

function EmptyState({ label, hint, icon }: { label: string; hint?: string; icon?: React.ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center py-16 text-muted-foreground gap-2 px-4 text-center">
      <div className="opacity-30">{icon ?? <ReceiptText className="w-10 h-10" />}</div>
      <span className="text-sm font-semibold">{label}</span>
      {hint && <span className="text-[11px] opacity-70">{hint}</span>}
    </div>
  );
}

// ── Stake Game History ────────────────────────────────────────────────────
function StakeGameHistory({ games, loading, gameGroups }: { games: any[]; loading: boolean; gameGroups: { label: string; items: any[] }[] }) {
  const [selected, setSelected] = useState<any>(null);

  if (loading) {
    return (
      <div className="flex flex-col items-center justify-center py-12 text-muted-foreground gap-2">
        <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
        <span className="text-sm">Chargement…</span>
      </div>
    );
  }
  if (games.length === 0) {
    return <EmptyState icon={<Gamepad2 className="w-10 h-10" />} label="Aucune partie avec mise" hint="Jouez votre première partie pour voir l'historique." />;
  }

  const STATUS_CFG: Record<string, { cls: string; label: string }> = {
    open:      { cls: "bg-amber-100 text-amber-700 border-amber-300",       label: "Ouverte" },
    playing:   { cls: "bg-blue-100 text-blue-700 border-blue-300",          label: "En cours" },
    finished:  { cls: "bg-secondary text-muted-foreground border-border",    label: "Terminée" },
    cancelled: { cls: "bg-rose-100 text-rose-600 border-rose-300",           label: "Annulée" },
    waiting:   { cls: "bg-amber-100 text-amber-700 border-amber-300",       label: "En attente" },
  };

  // ── Detail view ──
  if (selected) {
    const g = selected;
    const meta = gameMeta(g.game_type);
    const stake = Number(g.stake ?? 0);
    const isWin = g.is_winner && g.status === "finished";
    const isLoss = !g.is_winner && g.status === "finished";

    return (
      <div className="space-y-3">
        <button onClick={() => setSelected(null)} className="text-sm text-primary font-bold flex items-center gap-1">
          ← Retour
        </button>
        <div className="rounded-2xl border border-border bg-card shadow-sm overflow-hidden">
          {/* Header with game type color */}
          <div className={`p-4 ${meta.bg} border-b border-border/50`}>
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className={`p-2.5 rounded-xl bg-card border border-border/50 ${meta.color}`}>{meta.icon}</div>
                <div>
                  <div className="text-lg font-mono font-black text-foreground">{g.formatted_number}</div>
                  <div className="text-xs text-muted-foreground">{g.game_label}</div>
                </div>
              </div>
              <span className={`px-2.5 py-1 rounded-full text-[10px] font-bold border ${STATUS_CFG[g.status]?.cls || "bg-secondary"}`}>
                {STATUS_CFG[g.status]?.label || g.status}
              </span>
            </div>
          </div>

          {/* ── Big result banner ── */}
          {isWin && (
            <div className="px-4 py-3 bg-emerald-50 dark:bg-emerald-950/10 border-b border-emerald-200 dark:border-emerald-900/30">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="p-1.5 rounded-lg bg-emerald-500 text-white"><Trophy className="w-4 h-4" /></div>
                  <span className="font-bold text-emerald-700 dark:text-emerald-400">Gagné</span>
                </div>
                <span className="text-lg font-extrabold tabular-nums text-emerald-600">+{fmtAr(stake)}</span>
              </div>
            </div>
          )}
          {isLoss && (
            <div className="px-4 py-3 bg-rose-50 dark:bg-rose-950/10 border-b border-rose-200 dark:border-rose-900/30">
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <div className="p-1.5 rounded-lg bg-rose-500 text-white"><XCircle className="w-4 h-4" /></div>
                  <span className="font-bold text-rose-700 dark:text-rose-400">Perdu</span>
                </div>
                <span className="text-lg font-extrabold tabular-nums text-rose-500">−{fmtAr(stake)}</span>
              </div>
            </div>
          )}

          {/* Details */}
          <div className="p-4 space-y-3">
            <div className="grid grid-cols-2 gap-3 text-xs">
              <DetailItem label="Date" value={g.created_at ? new Date(g.created_at).toLocaleString("fr-FR") : "—"} />
              <DetailItem label="Fin" value={g.finished_at ? new Date(g.finished_at).toLocaleString("fr-FR") : "—"} />
              <DetailItem label="Durée" value={g.duration_seconds != null ? `${Math.floor(g.duration_seconds / 60)}min ${g.duration_seconds % 60}s` : "—"} />
              <DetailItem label="Rôle" value={g.is_host ? "Hôte" : "Invité"} />
              <DetailItem label="Mise" value={fmtAr(stake)} />
              <DetailItem
                label="Résultat"
                value={isWin ? "🏆 Gagné" : isLoss ? "Perdu" : "—"}
                valueClass={isWin ? "text-emerald-600 font-bold" : isLoss ? "text-rose-500 font-bold" : ""}
              />
            </div>
            {g.end_reason && g.end_reason !== "normal" && (
              <div className="pt-2 border-t border-border/50">
                <div className="text-[10px] text-muted-foreground mb-0.5">Raison de fin</div>
                <div className="text-xs font-medium">{g.end_reason}</div>
              </div>
            )}
          </div>
        </div>
      </div>
    );
  }

  // ── List view ──
  return (
    <div className="space-y-3">
      {gameGroups.map(group => (
        <div key={group.label} className="space-y-1">
          <DateHeader label={group.label} count={group.items.length} />
          <div className="rounded-2xl bg-card shadow-sm border border-border overflow-hidden">
            <div className="divide-y divide-border/40">
              {group.items.map((g, i) => {
                const meta = gameMeta(g.game_type);
                const stake = Number(g.stake ?? 0);
                const isWin = g.is_winner && g.status === "finished";
                const isLoss = !g.is_winner && g.status === "finished";
                return (
                  <button key={i} onClick={() => setSelected(g)}
                    className={`w-full flex items-center gap-3 text-left p-3 hover:bg-accent/50 transition-colors border-l-4 ${
                      isWin ? "border-l-emerald-500 bg-emerald-50/20 dark:bg-emerald-950/5"
                      : isLoss ? "border-l-rose-500 bg-rose-50/20 dark:bg-rose-950/5"
                      : "border-l-transparent"
                    }`}>
                    <div className={`p-2 rounded-xl border border-border/50 ${meta.bg} ${meta.color}`}>
                      {meta.icon}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-semibold text-sm">{meta.label}</div>
                      <div className="text-[10px] text-muted-foreground font-mono">{g.formatted_number}</div>
                    </div>
                    {/* ── Amount with clear gain/perte color ── */}
                    {isWin && (
                      <span className="text-sm font-extrabold tabular-nums text-emerald-600">+{fmtArShort(stake)}</span>
                    )}
                    {isLoss && (
                      <span className="text-sm font-extrabold tabular-nums text-rose-500">−{fmtArShort(stake)}</span>
                    )}
                    {/* Status badges for non-finished games */}
                    {g.status !== "finished" && (
                      <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${STATUS_CFG[g.status]?.cls || "bg-secondary"}`}>
                        {STATUS_CFG[g.status]?.label || g.status}
                      </span>
                    )}
                    {g.status === "finished" && (
                      <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${
                        isWin ? "bg-emerald-100 text-emerald-700 border-emerald-300"
                        : "bg-rose-100 text-rose-600 border-rose-300"
                      }`}>
                        {isWin ? "🏆 Gagné" : "Perdu"}
                      </span>
                    )}
                    <ChevronRight className="w-4 h-4 text-muted-foreground/50 flex-shrink-0" />
                  </button>
                );
              })}
            </div>
          </div>
        </div>
      ))}
    </div>
  );
}

function DetailItem({ label, value, valueClass }: { label: string; value: string; valueClass?: string }) {
  return (
    <div>
      <div className="text-[10px] text-muted-foreground mb-0.5">{label}</div>
      <div className={`font-semibold ${valueClass ?? ""}`}>{value}</div>
    </div>
  );
}
