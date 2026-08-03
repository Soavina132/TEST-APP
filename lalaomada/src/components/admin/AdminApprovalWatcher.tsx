import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { Shield, Check, X } from "lucide-react";

/**
 * AdminApprovalWatcher — écouté globalement pour les admins connectés.
 * Affiche un dialogue quand un autre admin demande à se connecter.
 */
type Req = {
  id: string;
  requesting_user_id: string;
  requesting_ip: string | null;
  requesting_user_agent: string | null;
  created_at: string;
  expires_at: string;
  status: string;
};

export default function AdminApprovalWatcher() {
  const { user, isAdmin } = useAuth();
  const [pending, setPending] = useState<Req | null>(null);
  const [requesterName, setRequesterName] = useState<string>("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (!user || !isAdmin) return;

    // Load any existing pending request (not authored by me)
    const load = async () => {
      const { data } = await supabase
        .from("admin_login_approvals")
        .select("*")
        .eq("status", "pending")
        .gt("expires_at", new Date().toISOString())
        .neq("requesting_user_id", user.id)
        .order("created_at", { ascending: false })
        .limit(1);
      if (data && data[0]) {
        setPending(data[0] as any);
        loadRequesterName(data[0].requesting_user_id);
      }
    };
    load();

    const ch = supabase
      .channel(`admin_approvals_watch:${user.id}`)
      .on("postgres_changes",
        { event: "INSERT", schema: "public", table: "admin_login_approvals" },
        (payload) => {
          const r = payload.new as Req;
          if (r.requesting_user_id === user.id) return;
          if (r.status !== "pending") return;
          setPending(r);
          loadRequesterName(r.requesting_user_id);
          try {
            new Audio("data:audio/wav;base64,UklGRhwAAABXQVZFZm10IBAAAAABAAEARKwAAIhYAQACABAAZGF0YQAAAAA=").play();
          } catch {}
          toast.info("🔐 Un admin demande à se connecter", { duration: 8000 });
        }
      )
      .subscribe();

    return () => { supabase.removeChannel(ch); };
  }, [user, isAdmin]);

  async function loadRequesterName(uid: string) {
    const { data } = await supabase.from("profiles").select("pseudo,email").eq("id", uid).maybeSingle();
    setRequesterName((data as any)?.pseudo || (data as any)?.email || uid.slice(0, 8));
  }

  async function decide(decision: "approved" | "denied") {
    if (!pending) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("admin_respond_login_approval", {
        _request_id: pending.id, _decision: decision,
      });
      if (error) throw error;
      toast.success(decision === "approved" ? "Connexion approuvée" : "Connexion refusée");
      setPending(null);
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  }

  if (!pending) return null;

  return (
    <div className="fixed inset-0 z-[9999] bg-black/70 backdrop-blur-sm flex items-center justify-center p-4">
      <div className="w-full max-w-sm rounded-3xl bg-card shadow-2xl p-6 space-y-4 border-2 border-primary">
        <div className="flex items-center gap-2 text-primary">
          <Shield className="w-6 h-6" />
          <h2 className="text-lg font-bold">Demande de connexion admin</h2>
        </div>
        <div className="space-y-1 text-sm">
          <div><span className="text-muted-foreground">Compte :</span> <strong>{requesterName}</strong></div>
          {pending.requesting_ip && <div><span className="text-muted-foreground">IP :</span> <code className="text-xs">{pending.requesting_ip}</code></div>}
          {pending.requesting_user_agent && (
            <div className="text-xs text-muted-foreground truncate">🖥 {pending.requesting_user_agent}</div>
          )}
          <div className="text-xs text-amber-500">⏱ Expire {new Date(pending.expires_at).toLocaleTimeString()}</div>
        </div>
        <div className="flex gap-2">
          <button onClick={() => decide("denied")} disabled={busy}
            className="flex-1 py-3 rounded-xl bg-destructive text-destructive-foreground font-semibold flex items-center justify-center gap-1 disabled:opacity-50">
            <X className="w-4 h-4" /> Refuser
          </button>
          <button onClick={() => decide("approved")} disabled={busy}
            className="flex-1 py-3 rounded-xl bg-green-600 text-white font-semibold flex items-center justify-center gap-1 disabled:opacity-50">
            <Check className="w-4 h-4" /> Approuver
          </button>
        </div>
      </div>
    </div>
  );
}
