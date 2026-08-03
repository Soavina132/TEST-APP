import { createFileRoute } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Bug, CheckCircle2, Clock, XCircle, ChevronDown, AlertTriangle, RefreshCw } from "lucide-react";
import AdminSecurityGate from "@/components/admin/AdminSecurityGate";


export const Route = createFileRoute("/_authenticated/admin-bug-reports")({
  component: AdminBugReports,
  head: () => ({ meta: [{ title: "Signalements — Admin" }, { name: "robots", content: "noindex" }] }),
});

const STATUS_CFG: Record<string, { label: string; color: string; icon: React.ReactNode }> = {
  open:        { label: "Ouvert",   color: "bg-amber-100 text-amber-700",        icon: <Clock className="w-3.5 h-3.5" /> },
  in_progress: { label: "En cours", color: "bg-blue-100 text-blue-700",          icon: <AlertTriangle className="w-3.5 h-3.5" /> },
  resolved:    { label: "Résolu",   color: "bg-emerald-100 text-emerald-700",    icon: <CheckCircle2 className="w-3.5 h-3.5" /> },
  closed:      { label: "Fermé",    color: "bg-secondary text-muted-foreground", icon: <XCircle className="w-3.5 h-3.5" /> },
};
const CAT: Record<string, string> = {
  bug: "🐛 Tech", payment: "💳 Paiement", game: "🎮 Jeu",
  suggestion: "💡 Suggestion", general: "📝 Autre",
};

function StatusBadge({ status }: { status: string }) {
  const s = STATUS_CFG[status] ?? STATUS_CFG.open;
  return (
    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold ${s.color}`}>
      {s.icon} {s.label}
    </span>
  );
}

function AdminBugReports() {
  const { isAdmin } = useAuth();
  const [reports, setReports] = useState<any[]>([]);
  const [filter, setFilter] = useState("open");
  const [loading, setLoading] = useState(false);
  const [updating, setUpdating] = useState<string | null>(null);
  const [noteEdits, setNoteEdits] = useState<Record<string, string>>({});

  const load = async () => {
    setLoading(true);
    const { data } = await (supabase.rpc as any)("admin_list_bug_reports", {
      _status: filter === "all" ? null : filter,
      _limit: 100,
    });
    setReports(data || []);
    setLoading(false);
  };

  useEffect(() => { if (isAdmin) load(); }, [isAdmin, filter]);

  async function updateStatus(id: string, status: string, note?: string) {
    setUpdating(id);
    await (supabase.rpc as any)("admin_update_bug_report", {
      _id: id, _status: status,
      _admin_note: note ?? noteEdits[id] ?? null,
    });
    setUpdating(null);
    toast.success("Mis à jour");
    load();
  }

  if (!isAdmin) return <main className="p-8 text-center text-destructive font-bold">Accès refusé</main>;

  const openCount = reports.filter(r => r.status === "open").length;

  return (
    <AdminSecurityGate>
    <main className="max-w-3xl mx-auto px-4 py-6 space-y-5">

      <div className="flex items-center justify-between flex-wrap gap-3">
        <h1 className="text-2xl font-extrabold flex items-center gap-2">
          <Bug className="w-6 h-6 text-primary" /> Signalements
          {openCount > 0 && (
            <span className="ml-1 px-2 py-0.5 rounded-full bg-destructive text-white text-sm font-bold">{openCount}</span>
          )}
        </h1>
        <div className="flex items-center gap-2">
          <button onClick={load} title="Rafraîchir" className="p-2 rounded-full hover:bg-accent">
            <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
          </button>
          <a href="/admin" className="text-xs px-3 py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold">
            ← Admin
          </a>
        </div>
      </div>

      <div className="flex gap-1.5 flex-wrap">
        {["all","open","in_progress","resolved","closed"].map(s => (
          <button key={s} onClick={() => setFilter(s)}
            className={`px-3 py-1.5 rounded-full text-xs font-bold transition-colors ${
              filter === s ? "bg-primary text-primary-foreground" : "bg-secondary hover:bg-accent"
            }`}>
            {s === "all" ? "Tous" : (STATUS_CFG[s]?.label ?? s)}
          </button>
        ))}
      </div>

      {loading && <div className="text-center text-muted-foreground py-10">Chargement…</div>}

      {!loading && reports.length === 0 && (
        <div className="text-center py-16 text-muted-foreground">
          <Bug className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <p className="font-medium">Aucun signalement</p>
        </div>
      )}

      <div className="space-y-3">
        {reports.map(r => (
          <div key={r.id} className="bg-card rounded-2xl border border-border/60 p-4 space-y-3">
            <div className="flex items-start justify-between gap-2 flex-wrap">
              <div className="flex items-center gap-2 flex-wrap">
                <span className="font-semibold text-sm">{r.pseudo ?? "Joueur"}</span>
                <span className="text-xs bg-secondary px-2 py-0.5 rounded-full">
                  {CAT[r.category] ?? r.category}
                </span>
                <StatusBadge status={r.status} />
              </div>
              <span className="text-xs text-muted-foreground whitespace-nowrap">
                {new Date(r.created_at).toLocaleString("fr-FR", {
                  day: "2-digit", month: "2-digit", year: "2-digit",
                  hour: "2-digit", minute: "2-digit",
                })}
              </span>
            </div>

            <p className="text-sm bg-secondary rounded-xl px-4 py-3 whitespace-pre-wrap break-words">{r.message}</p>

            {r.admin_note && (
              <div className="text-xs bg-blue-50 dark:bg-blue-950/30 text-blue-700 dark:text-blue-300 rounded-xl px-3 py-2">
                <span className="font-bold">Note admin : </span>{r.admin_note}
              </div>
            )}

            <div className="flex gap-2 flex-wrap items-center">
              <input type="text" placeholder="Note admin (optionnel)…"
                value={noteEdits[r.id] ?? r.admin_note ?? ""}
                onChange={e => setNoteEdits(prev => ({ ...prev, [r.id]: e.target.value }))}
                className="flex-1 min-w-[140px] bg-secondary rounded-xl px-3 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
              <div className="relative">
                <select value={r.status} disabled={updating === r.id}
                  onChange={e => updateStatus(r.id, e.target.value)}
                  className="appearance-none bg-secondary rounded-xl px-3 py-1.5 text-xs font-semibold cursor-pointer pr-8 focus:outline-none focus:ring-2 focus:ring-primary/40 disabled:opacity-50">
                  <option value="open">Ouvert</option>
                  <option value="in_progress">En cours</option>
                  <option value="resolved">Résolu</option>
                  <option value="closed">Fermé</option>
                </select>
                <ChevronDown className="absolute right-2 top-1/2 -translate-y-1/2 w-3 h-3 pointer-events-none text-muted-foreground" />
              </div>
            </div>
          </div>
        ))}
      </div>
    </main>
    </AdminSecurityGate>
  );
}

