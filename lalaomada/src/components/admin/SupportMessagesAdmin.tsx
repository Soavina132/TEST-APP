import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { MessageSquare, Send, RefreshCw, CheckCircle2, Clock } from "lucide-react";

type SupportRow = {
  id: string;
  user_id: string;
  pseudo: string;
  message: string;
  reply: string | null;
  status: string;
  created_at: string;
};

export default function SupportMessagesAdmin() {
  const [rows, setRows] = useState<SupportRow[]>([]);
  const [filter, setFilter] = useState<"all" | "open" | "answered">("open");
  const [loading, setLoading] = useState(false);
  const [replyEdits, setReplyEdits] = useState<Record<string, string>>({});
  const [sending, setSending] = useState<string | null>(null);

  const load = async () => {
    setLoading(true);
    const { data } = await (supabase.rpc as any)("admin_list_support_messages", {
      _status: filter === "all" ? null : filter,
      _limit: 100,
    });
    setRows(data || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, [filter]);

  async function sendReply(id: string) {
    const text = (replyEdits[id] || "").trim();
    if (text.length < 2) return toast.error("Réponse trop courte");
    setSending(id);
    try {
      const { error } = await (supabase.rpc as any)("admin_reply_support", { _id: id, _reply: text });
      if (error) throw error;
      toast.success("Réponse envoyée");
      load();
    } catch (e: any) {
      toast.error(e?.message || "Erreur");
    } finally {
      setSending(null);
    }
  }

  const openCount = rows.filter(r => r.status === "open").length;

  return (
    <div className="space-y-3">
      <div className="flex items-center justify-between flex-wrap gap-2">
        <div className="flex gap-1.5 flex-wrap">
          {(["open", "answered", "all"] as const).map(s => (
            <button key={s} onClick={() => setFilter(s)}
              className={`px-3 py-1.5 rounded-full text-xs font-bold transition-colors ${
                filter === s ? "bg-primary text-primary-foreground" : "bg-secondary hover:bg-accent"
              }`}>
              {s === "all" ? "Tous" : s === "open" ? "Ouverts" : "Répondus"}
            </button>
          ))}
        </div>
        <button onClick={load} title="Rafraîchir" className="p-2 rounded-full hover:bg-accent">
          <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
        </button>
      </div>

      {loading && <div className="text-center text-muted-foreground py-6 text-sm">Chargement…</div>}

      {!loading && rows.length === 0 && (
        <div className="text-center py-10 text-muted-foreground">
          <MessageSquare className="w-8 h-8 mx-auto mb-2 opacity-30" />
          <p className="text-sm font-medium">Aucun message</p>
        </div>
      )}

      <div className="space-y-3">
        {rows.map(r => (
          <div key={r.id} className="bg-secondary/40 rounded-2xl border border-border/50 p-4 space-y-2.5">
            <div className="flex items-center justify-between gap-2 flex-wrap">
              <span className="font-semibold text-sm">{r.pseudo}</span>
              <span className="flex items-center gap-1 text-xs text-muted-foreground">
                <Clock className="w-3 h-3" />
                {new Date(r.created_at).toLocaleString("fr-FR", {
                  day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit",
                })}
              </span>
            </div>

            <p className="text-sm bg-card rounded-xl px-3.5 py-2.5 whitespace-pre-wrap break-words">{r.message}</p>

            {r.reply && (
              <div className="text-sm bg-primary/10 border border-primary/20 rounded-xl px-3.5 py-2.5">
                <div className="flex items-center gap-1 text-xs font-bold text-primary mb-1">
                  <CheckCircle2 className="w-3 h-3" /> Réponse envoyée
                </div>
                {r.reply}
              </div>
            )}

            <div className="flex gap-2">
              <input
                type="text"
                placeholder={r.reply ? "Modifier la réponse…" : "Écrire une réponse…"}
                value={replyEdits[r.id] ?? r.reply ?? ""}
                onChange={e => setReplyEdits(prev => ({ ...prev, [r.id]: e.target.value }))}
                className="flex-1 bg-card rounded-xl px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary/40"
              />
              <button
                onClick={() => sendReply(r.id)}
                disabled={sending === r.id}
                className="px-4 py-2 rounded-xl bg-primary text-primary-foreground font-semibold text-sm disabled:opacity-50 flex items-center gap-1.5 shrink-0"
              >
                <Send className="w-3.5 h-3.5" /> Répondre
              </button>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
