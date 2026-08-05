import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Monitor, RefreshCw, LogOut, ShieldOff, User } from "lucide-react";

type Sess = {
  id: string;
  user_id: string;
  admin_name: string;
  ip: string | null;
  user_agent: string | null;
  mfa_verified: boolean;
  created_at: string;
  last_seen_at: string;
  expires_at: string;
  override_reason: string | null;
  is_me: boolean;
};

export default function AdminSessionsPanel() {
  const [sessions, setSessions] = useState<Sess[]>([]);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc("admin_list_all_active_sessions" as any);
    if (!error) setSessions((data as any) || []);
    setLoading(false);
  }, []);

  useEffect(() => {
    load();
    const t = setInterval(load, 15_000);
    return () => clearInterval(t);
  }, [load]);

  async function revoke(s: Sess) {
    const who = s.is_me ? "ma session" : `la session de ${s.admin_name}`;
    if (!confirm(`Révoquer ${who} ?`)) return;
    const rpc = s.is_me ? "admin_revoke_session" : "admin_revoke_any_session";
    const params = s.is_me
      ? { _session_id: s.id, _reason: "manual" }
      : { _session_id: s.id, _reason: "révoquée par un autre admin" };
    const { error } = await supabase.rpc(rpc as any, params as any);
    if (error) return toast.error(error.message);
    toast.success("Session révoquée");
    load();
  }

  async function revokeAllOthers() {
    if (!confirm("Déconnecter toutes les AUTRES sessions de mon compte ?")) return;
    const { data, error } = await supabase.rpc("admin_revoke_all_other_sessions" as any);
    if (error) return toast.error(error.message);
    toast.success(`${(data as any) ?? 0} session(s) révoquée(s)`);
    load();
  }

  const fmt = (d: string) => new Date(d).toLocaleString();

  return (
    <div className="rounded-2xl bg-card p-4 space-y-3 border border-border">
      <div className="flex items-center justify-between">
        <h3 className="font-bold flex items-center gap-2">
          <Monitor className="w-4 h-4" /> Sessions admin actives
          <span className="text-xs font-normal text-muted-foreground">({sessions.length})</span>
        </h3>
        <div className="flex gap-1">
          <button onClick={load} disabled={loading} className="p-2 rounded-lg bg-muted">
            <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
          </button>
          <button
            onClick={revokeAllOthers}
            className="px-3 py-2 rounded-lg bg-destructive text-destructive-foreground text-xs font-semibold flex items-center gap-1"
          >
            <ShieldOff className="w-3 h-3" /> Mes autres
          </button>
        </div>
      </div>

      {sessions.length === 0 ? (
        <div className="text-sm text-muted-foreground text-center py-4">Aucune session active</div>
      ) : (
        <div className="space-y-2">
          {sessions.map((s) => (
            <div
              key={s.id}
              className={`p-3 rounded-xl border text-xs ${
                s.is_me ? "border-primary/50 bg-primary/5" : "border-green-500/30 bg-green-500/5"
              }`}
            >
              <div className="flex items-start justify-between gap-2">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2 font-semibold">
                    <User className="w-3 h-3" />
                    <span className="truncate">{s.admin_name}</span>
                    {s.is_me && (
                      <span className="px-2 py-0.5 rounded bg-primary/20 text-primary text-[10px]">MOI</span>
                    )}
                    {s.override_reason && (
                      <span className="px-2 py-0.5 rounded bg-amber-500/20 text-amber-500 text-[10px]">
                        OVERRIDE
                      </span>
                    )}
                  </div>
                  <div className="text-muted-foreground truncate">🖥 {s.user_agent || "—"}</div>
                  <div className="text-muted-foreground">
                    📍 {s.ip || "—"} · Créée {fmt(s.created_at)}
                  </div>
                  <div className="text-muted-foreground">
                    ⏱ Expire {fmt(s.expires_at)} · Vue {fmt(s.last_seen_at)}
                  </div>
                  {s.override_reason && (
                    <div className="text-amber-500 mt-1">Motif urgence : {s.override_reason}</div>
                  )}
                </div>
                <button
                  onClick={() => revoke(s)}
                  className="p-2 rounded-lg bg-destructive/10 text-destructive shrink-0"
                  title={s.is_me ? "Me déconnecter" : "Déconnecter cet admin"}
                >
                  <LogOut className="w-4 h-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
