import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useMemo, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import {
  Gamepad2, ArrowDownCircle, ArrowUpCircle,
  ReceiptText, Trophy, XCircle, Clock, Flame, Gift, Hourglass, CheckCircle2, Ban,
} from "lucide-react";

export const Route = createFileRoute("/_authenticated/history")({
  component: HistoryPage,
  head: () => ({ meta: [
    { title: "Finance & Historique — Lalao MADA" },
    { name: "description", content: "Suivi de vos dépôts, retraits et transactions en temps réel." },
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
function relTime(d: string) {
  const diff = (Date.now() - new Date(d).getTime()) / 1000;
  if (diff < 60) return "à l'instant";
  if (diff < 3600) return `il y a ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `il y a ${Math.floor(diff / 3600)} h`;
  return `il y a ${Math.floor(diff / 86400)} j`;
}

const TXKind: Record<string, { icon: React.ReactNode; label: string; color: string }> = {
  game_win:      { icon: <Trophy className="w-4 h-4" />,          label: "Gain de partie",       color: "text-emerald-600" },
  game_loss:     { icon: <XCircle className="w-4 h-4" />,         label: "Pari perdu",            color: "text-rose-500" },
  game_stake:    { icon: <Gamepad2 className="w-4 h-4" />,        label: "Mise de partie",        color: "text-rose-400" },
  daily_bonus:   { icon: <Gift className="w-4 h-4" />,            label: "Bonus quotidien",       color: "text-amber-500" },
  signup_bonus:  { icon: <Gift className="w-4 h-4" />,            label: "Bonus inscription",     color: "text-amber-500" },
  referral:      { icon: <Flame className="w-4 h-4" />,           label: "Commission parrainage", color: "text-orange-500" },
  deposit:       { icon: <ArrowDownCircle className="w-4 h-4" />, label: "Dépôt",                 color: "text-emerald-600" },
  withdrawal:    { icon: <ArrowUpCircle className="w-4 h-4" />,   label: "Retrait",               color: "text-rose-500" },
  tournament_win:{ icon: <Trophy className="w-4 h-4" />,          label: "Gain tournoi",          color: "text-amber-600" },
  refund:        { icon: <ReceiptText className="w-4 h-4" />,     label: "Remboursement",         color: "text-blue-500" },
};
function txConfig(kind: string) {
  return TXKind[kind] ?? { icon: <ReceiptText className="w-4 h-4" />, label: kind, color: "text-muted-foreground" };
}

function StatusBadge({ status }: { status: string }) {
  const cfg: Record<string, { cls: string; icon: React.ReactNode; label: string }> = {
    pending:   { cls: "bg-amber-100 text-amber-700 border-amber-300",     icon: <Hourglass className="w-2.5 h-2.5" />,     label: "En attente" },
    approved:  { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", icon: <CheckCircle2 className="w-2.5 h-2.5" />, label: "Approuvé" },
    completed: { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", icon: <CheckCircle2 className="w-2.5 h-2.5" />, label: "Terminé" },
    rejected:  { cls: "bg-rose-100 text-rose-600 border-rose-300",         icon: <Ban className="w-2.5 h-2.5" />,           label: "Refusé" },
    cancelled: { cls: "bg-secondary text-muted-foreground border-border",  icon: <Ban className="w-2.5 h-2.5" />,           label: "Annulé" },
  };
  const c = cfg[status] ?? { cls: "bg-secondary text-muted-foreground border-border", icon: null, label: status };
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold border ${c.cls}`}>
      {c.icon}{c.label}
    </span>
  );
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

    // Load stake game history
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

  // Aggregations
  const pendingDeps  = useMemo(() => deps.filter(d => (d.status ?? "pending") === "pending"), [deps]);
  const pendingWiths = useMemo(() => withs.filter(w => (w.status ?? "pending") === "pending"), [withs]);
  const totalDeposited  = deps.filter(d => d.status === "approved").reduce((s, d) => s + Number(d.amount_ar ?? d.amount ?? 0), 0);
  const totalWithdrawn  = withs.filter(w => w.status === "approved").reduce((s, w) => s + Number(w.amount_ar ?? w.amount ?? 0), 0);
  const pendingDepAmt   = pendingDeps.reduce((s, d) => s + Number(d.amount_ar ?? d.amount ?? 0), 0);
  const pendingWithAmt  = pendingWiths.reduce((s, w) => s + Number(w.amount_ar ?? w.amount ?? 0), 0);
  const totalPending    = pendingDeps.length + pendingWiths.length;

  const filteredDeps  = statusFilter === "all" ? deps  : deps.filter(d => (d.status ?? "pending") === statusFilter);
  const filteredWiths = statusFilter === "all" ? withs : withs.filter(w => (w.status ?? "pending") === statusFilter);

  const tabs: { id: Tab; label: string; icon: React.ReactNode; count: number; badge?: boolean }[] = [
    { id: "pending",      label: "En attente",   icon: <Hourglass className="w-4 h-4" />,       count: totalPending, badge: totalPending > 0 },
    { id: "deposits",     label: "Dépôts",       icon: <ArrowDownCircle className="w-4 h-4" />, count: deps.length },
    { id: "withdrawals",  label: "Retraits",     icon: <ArrowUpCircle className="w-4 h-4" />,   count: withs.length },
    { id: "transactions", label: "Mouvements",   icon: <ReceiptText className="w-4 h-4" />,     count: tx.length },
    { id: "parties",      label: "Parties",      icon: <Gamepad2 className="w-4 h-4" />,        count: stakeGames.length },
  ];

  return (
    <main className="max-w-2xl mx-auto px-3 py-3 space-y-3 pb-24">
      {/* Header */}
      <div className="flex items-center justify-between">
        <h1 className="text-xl font-extrabold flex items-center gap-2">
          💰 Finance
        </h1>
        {totalPending > 0 && (
          <span className="inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-amber-100 text-amber-700 border border-amber-300 animate-pulse">
            <Hourglass className="w-3 h-3" /> {totalPending} en attente
          </span>
        )}
      </div>

      {/* Résumé principal — Dépôts / Retraits */}
      <div className="grid grid-cols-2 gap-2">
        <div className="rounded-2xl p-3 bg-gradient-to-br from-emerald-500 to-emerald-600 text-white shadow-lg">
          <div className="flex items-center gap-1.5 text-[11px] font-semibold opacity-90">
            <ArrowDownCircle className="w-3.5 h-3.5" /> Total déposé
          </div>
          <div className="text-lg font-extrabold tabular-nums mt-1 leading-tight">{fmtAr(totalDeposited)}</div>
          {pendingDepAmt > 0 && (
            <div className="text-[10px] mt-1 opacity-90 flex items-center gap-1">
              <Hourglass className="w-2.5 h-2.5" /> {fmtAr(pendingDepAmt)} en attente
            </div>
          )}
        </div>
        <div className="rounded-2xl p-3 bg-gradient-to-br from-rose-500 to-rose-600 text-white shadow-lg">
          <div className="flex items-center gap-1.5 text-[11px] font-semibold opacity-90">
            <ArrowUpCircle className="w-3.5 h-3.5" /> Total retiré
          </div>
          <div className="text-lg font-extrabold tabular-nums mt-1 leading-tight">{fmtAr(totalWithdrawn)}</div>
          {pendingWithAmt > 0 && (
            <div className="text-[10px] mt-1 opacity-90 flex items-center gap-1">
              <Hourglass className="w-2.5 h-2.5" /> {fmtAr(pendingWithAmt)} en attente
            </div>
          )}
        </div>
      </div>

      {/* Tabs */}
      <div className="flex gap-1 bg-card/80 p-1 rounded-2xl shadow-sm border border-white/8 overflow-x-auto">
        {tabs.map(t => (
          <button key={t.id} onClick={() => setTab(t.id)}
            className={`relative flex-1 min-w-[80px] flex items-center justify-center gap-1 py-2.5 rounded-xl text-[11px] font-bold transition-all whitespace-nowrap ${tab === t.id ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "text-muted-foreground hover:text-foreground"}`}>
            {t.icon} {t.label}
            {t.count > 0 && (
              <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${tab === t.id ? "bg-white/25" : t.badge ? "bg-amber-500 text-white" : "bg-white/8"}`}>
                {t.count}
              </span>
            )}
          </button>
        ))}
      </div>

      {/* Status filter (only on deposits/withdrawals) */}
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
        <div className="rounded-3xl bg-card shadow-md border border-white/8 overflow-hidden">

          {/* En attente */}
          {tab === "pending" && (
            (pendingDeps.length + pendingWiths.length) === 0
              ? <EmptyState icon={<CheckCircle2 className="w-10 h-10" />} label="Rien en attente 🎉" hint="Tous vos dépôts et retraits sont traités." />
              : <div className="divide-y divide-border/40">
                  {pendingDeps.map(item => <PendingItem key={"d-"+item.id} kind="deposit" item={item} />)}
                  {pendingWiths.map(item => <PendingItem key={"w-"+item.id} kind="withdrawal" item={item} />)}
                </div>
          )}

          {/* Dépôts */}
          {tab === "deposits" && (
            filteredDeps.length === 0
              ? <EmptyState label="Aucun dépôt" />
              : <div className="divide-y divide-border/40">
                  {filteredDeps.map(item => <FinanceRow key={item.id} kind="deposit" item={item} />)}
                </div>
          )}

          {/* Retraits */}
          {tab === "withdrawals" && (
            filteredWiths.length === 0
              ? <EmptyState label="Aucun retrait" />
              : <div className="divide-y divide-border/40">
                  {filteredWiths.map(item => <FinanceRow key={item.id} kind="withdrawal" item={item} />)}
                </div>
          )}

          {/* Mouvements */}
          {tab === "parties" && (
            <StakeGameHistory games={stakeGames} loading={loadingStakeGames} />
          )}
          {tab === "transactions" && (
            tx.length === 0
              ? <EmptyState label="Aucune transaction" />
              : <div className="divide-y divide-border/40">
                  {tx.map(item => {
                    const cfg = txConfig(item.kind);
                    const amount = Number(item.amount ?? 0);
                    const isPositive = ["game_win","tournament_win","daily_bonus","signup_bonus","referral","deposit","refund"].includes(item.kind);
                    return (
                      <div key={item.id} className="flex items-start gap-3 p-3.5">
                        <div className={`mt-0.5 p-2 rounded-xl bg-white/5 border border-white/8 ${cfg.color}`}>{cfg.icon}</div>
                        <div className="flex-1 min-w-0">
                          <div className="font-semibold text-sm">{cfg.label}</div>
                          {item.meta?.game && <div className="text-[10px] text-muted-foreground">{item.meta.game}</div>}
                          {item.meta?.streak && <div className="text-[10px] text-amber-600">🔥 Série {item.meta.streak} jours{item.meta.multiplier > 1 ? ` (×${item.meta.multiplier})` : ""}</div>}
                          <div className="text-[10px] text-muted-foreground flex items-center gap-1 mt-0.5"><Clock className="w-2.5 h-2.5" />{fmtDate(item.created_at)}</div>
                        </div>
                        <div className={`font-extrabold text-sm tabular-nums ${isPositive ? "text-emerald-600" : "text-rose-500"}`}>
                          {isPositive ? "+" : "-"}{fmtAr(Math.abs(amount))}
                        </div>
                      </div>
                    );
                  })}
                </div>
          )}
        </div>
      )}
    </main>
  );
}

// ── Rows ──────────────────────────────────────────────────────────────────
function PendingItem({ kind, item }: { kind: "deposit" | "withdrawal"; item: any }) {
  const isDep = kind === "deposit";
  const color = isDep ? "emerald" : "rose";
  const amount = Number(item.amount_ar ?? item.amount ?? 0);
  return (
    <div className={`p-3.5 bg-amber-50/60 dark:bg-amber-950/10 border-l-4 border-amber-400`}>
      <div className="flex items-start gap-3">
        <div className={`mt-0.5 p-2 rounded-xl bg-${color}-100 dark:bg-${color}-900/30 text-${color}-600`}>
          {isDep ? <ArrowDownCircle className="w-4 h-4" /> : <ArrowUpCircle className="w-4 h-4" />}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <div className="font-semibold text-sm">{isDep ? "Dépôt" : "Retrait"}</div>
            <StatusBadge status="pending" />
          </div>
          {item.operator && <div className="text-[11px] text-muted-foreground mt-0.5">📱 {item.operator}{item.phone ? ` · ${item.phone}` : ""}</div>}
          <div className="text-[10px] text-muted-foreground flex items-center gap-1 mt-1">
            <Clock className="w-2.5 h-2.5" /> {fmtDate(item.created_at)} · {relTime(item.created_at)}
          </div>
        </div>
        <div className={`font-extrabold text-base ${isDep ? "text-emerald-600" : "text-rose-500"} tabular-nums`}>
          {isDep ? "+" : "-"}{fmtAr(amount)}
        </div>
      </div>
      <div className="mt-2 text-[10px] text-amber-700 dark:text-amber-400 font-medium">
        ⏳ En cours de traitement par l'administrateur.
      </div>
    </div>
  );
}

function FinanceRow({ kind, item }: { kind: "deposit" | "withdrawal"; item: any }) {
  const isDep = kind === "deposit";
  const color = isDep ? "emerald" : "rose";
  const amount = Number(item.amount_ar ?? item.amount ?? 0);
  const status = item.status ?? "pending";
  return (
    <div className="flex items-start gap-3 p-3.5">
      <div className={`mt-0.5 p-2 rounded-xl bg-${color}-100 dark:bg-${color}-900/30 text-${color}-600`}>
        {isDep ? <ArrowDownCircle className="w-4 h-4" /> : <ArrowUpCircle className="w-4 h-4" />}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <div className="font-semibold text-sm">{isDep ? "Dépôt" : "Retrait"}</div>
          <StatusBadge status={status} />
        </div>
        {item.operator && <div className="text-[11px] text-muted-foreground mt-0.5">📱 {item.operator}{item.phone ? ` · ${item.phone}` : ""}</div>}
        {item.reject_reason && status === "rejected" && (
          <div className="text-[10px] text-rose-600 mt-0.5">Raison : {item.reject_reason}</div>
        )}
        <div className="text-[10px] text-muted-foreground flex items-center gap-1 mt-0.5">
          <Clock className="w-2.5 h-2.5" /> {fmtDate(item.created_at)}
        </div>
      </div>
      <div className={`font-extrabold text-sm ${status === "rejected" || status === "cancelled" ? "text-muted-foreground line-through" : (isDep ? "text-emerald-600" : "text-rose-500")} tabular-nums`}>
        {isDep ? "+" : "-"}{fmtAr(amount)}
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

// ── Stake Game History Component ─────────────────────────────────────────
function StakeGameHistory({ games, loading }: { games: any[]; loading: boolean }) {
  const [selected, setSelected] = useState<any>(null);
  if (loading) {
    return <div className="text-center text-muted-foreground py-8">Chargement de l'historique…</div>;
  }
  if (games.length === 0) {
    return <div className="text-center text-muted-foreground py-8">Aucune partie avec mise pour le moment</div>;
  }

  const STATUS_CFG: Record<string, { cls: string; label: string }> = {
    open:      { cls: "bg-amber-100 text-amber-700 border-amber-300",     label: "Ouverte" },
    playing:   { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", label: "En cours" },
    finished:  { cls: "bg-secondary text-muted-foreground border-border",  label: "Terminée" },
    cancelled: { cls: "bg-rose-100 text-rose-600 border-rose-300",         label: "Annulée" },
    waiting:   { cls: "bg-amber-100 text-amber-700 border-amber-300",     label: "En attente" },
  };

  return (
    <div className="space-y-2">
      {selected ? (
        <div className="space-y-3">
          <button onClick={() => setSelected(null)}
            className="text-sm text-primary font-bold flex items-center gap-1">
            ← Retour à la liste
          </button>
          <div className="rounded-2xl border border-border bg-card p-4 space-y-3">
            <div className="flex items-center justify-between">
              <div>
                <div className="text-xl font-mono font-black text-primary">
                  {selected.formatted_number}
                </div>
                <div className="text-xs text-muted-foreground">
                  {selected.game_label} · Mise {Number(selected.stake).toLocaleString("fr-FR")} Ar
                </div>
              </div>
              <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${STATUS_CFG[selected.status]?.cls || "bg-secondary"}`}>
                {STATUS_CFG[selected.status]?.label || selected.status}
              </span>
            </div>
            <div className="grid grid-cols-2 gap-2 text-xs">
              <div>
                <div className="text-muted-foreground">Date</div>
                <div className="font-semibold">{selected.created_at ? new Date(selected.created_at).toLocaleString("fr-FR") : "—"}</div>
              </div>
              <div>
                <div className="text-muted-foreground">Terminée</div>
                <div className="font-semibold">{selected.finished_at ? new Date(selected.finished_at).toLocaleString("fr-FR") : "—"}</div>
              </div>
              <div>
                <div className="text-muted-foreground">Durée</div>
                <div className="font-semibold">
                  {selected.duration_seconds != null ? `${Math.floor(selected.duration_seconds / 60)}min ${selected.duration_seconds % 60}s` : "—"}
                </div>
              </div>
              <div>
                <div className="text-muted-foreground">Résultat</div>
                <div className="font-semibold">
                  {selected.is_winner ? "🏆 Gagné" : selected.status === "finished" ? "❌ Perdu" : "—"}
                </div>
              </div>
              <div>
                <div className="text-muted-foreground">Raison de fin</div>
                <div className="font-semibold">{selected.result || selected.end_reason || "—"}</div>
              </div>
              <div>
                <div className="text-muted-foreground">Rôle</div>
                <div className="font-semibold">{selected.is_host ? "Hôte" : "Invité"}</div>
              </div>
            </div>
          </div>
        </div>
      ) : (
        <div className="space-y-1.5">
          {games.map((g, i) => (
            <button key={i} onClick={() => setSelected(g)}
              className="w-full flex items-center gap-3 text-left bg-card border border-border rounded-xl px-3 py-2.5 hover:border-primary/40 transition-colors">
              <span className="font-mono font-black text-primary text-[11px] min-w-[80px]">
                {g.formatted_number}
              </span>
              <span className="text-sm font-semibold flex-1">{g.game_label}</span>
              <span className="text-xs text-amber-500 font-bold">
                {Number(g.stake).toLocaleString("fr-FR")} Ar
              </span>
              {g.status === "finished" && (
                g.is_winner
                  ? <span className="px-2 py-0.5 rounded-full text-[10px] font-bold border bg-emerald-100 text-emerald-700 border-emerald-300">🏆 Gagné</span>
                  : <span className="px-2 py-0.5 rounded-full text-[10px] font-bold border bg-rose-100 text-rose-600 border-rose-300">Perdu</span>
              )}
              {g.status === "cancelled" && (
                <span className="px-2 py-0.5 rounded-full text-[10px] font-bold border bg-rose-100 text-rose-600 border-rose-300">Annulée</span>
              )}
              {(g.status === "playing" || g.status === "open" || g.status === "waiting") && (
                <span className={`px-2 py-0.5 rounded-full text-[10px] font-bold border ${STATUS_CFG[g.status]?.cls || "bg-secondary"}`}>
                  {STATUS_CFG[g.status]?.label || g.status}
                </span>
              )}
              <span className="text-xs text-muted-foreground ml-auto">
                {g.created_at ? new Date(g.created_at).toLocaleDateString("fr-FR") : ""}
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
