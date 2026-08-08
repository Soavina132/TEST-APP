import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { X, Send, MessageSquare, Loader2, CheckCircle2, Clock } from "lucide-react";

type SupportMsg = {
  id: string;
  message: string;
  reply: string | null;
  status: string;
  created_at: string;
};

export default function SupportChatPopup({ onClose }: { onClose: () => void }) {
  const [message, setMessage] = useState("");
  const [sending, setSending] = useState(false);
  const [history, setHistory] = useState<SupportMsg[]>([]);
  const [loadingHistory, setLoadingHistory] = useState(true);

  const loadHistory = async () => {
    setLoadingHistory(true);
    try {
      const { data } = await (supabase.rpc as any)("my_support_messages", { _limit: 20 });
      setHistory(data || []);
    } finally {
      setLoadingHistory(false);
    }
  };

  useEffect(() => { loadHistory(); }, []);

  const send = async () => {
    const trimmed = message.trim();
    if (trimmed.length < 5) return toast.error("Message trop court (5 caractères minimum)");
    setSending(true);
    try {
      const { data: userRes } = await supabase.auth.getUser();
      const uid = userRes.user?.id;
      if (!uid) throw new Error("Non authentifié");
      const { error } = await supabase.from("support_messages").insert({
        user_id: uid,
        message: trimmed,
      } as any);
      if (error) throw error;
      toast.success("Message envoyé à l'équipe !");
      setMessage("");
      await loadHistory();
    } catch (e: any) {
      toast.error(e?.message || "Erreur lors de l'envoi");
    } finally {
      setSending(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-[70] bg-black/50 flex items-end sm:items-center justify-center p-4"
      onClick={onClose}
    >
      <div
        className="bg-card rounded-3xl w-full max-w-sm max-h-[85vh] flex flex-col shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between p-5 pb-3 shrink-0">
          <div className="flex items-center gap-2 font-bold text-lg">
            <MessageSquare className="w-5 h-5 text-primary" /> Support chat
          </div>
          <button onClick={onClose} aria-label="Fermer">
            <X className="w-5 h-5" />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 space-y-3">
          <p className="text-xs text-muted-foreground">
            Écrivez votre message, notre équipe vous répondra directement ici.
          </p>

          {/* History */}
          {loadingHistory ? (
            <div className="flex justify-center py-4">
              <Loader2 className="w-4 h-4 animate-spin text-muted-foreground" />
            </div>
          ) : history.length > 0 && (
            <div className="space-y-2.5">
              {history.map((m) => (
                <div key={m.id} className="rounded-2xl bg-secondary/50 p-3 space-y-2">
                  <div className="flex items-start justify-between gap-2">
                    <p className="text-sm whitespace-pre-wrap break-words">{m.message}</p>
                  </div>
                  <div className="flex items-center gap-1 text-[10px] text-muted-foreground">
                    <Clock className="w-3 h-3" />
                    {new Date(m.created_at).toLocaleString("fr-FR", {
                      day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
                    })}
                  </div>
                  {m.reply ? (
                    <div className="rounded-xl bg-primary/10 border border-primary/20 p-2.5 text-sm">
                      <div className="flex items-center gap-1 text-[10px] font-bold text-primary mb-1">
                        <CheckCircle2 className="w-3 h-3" /> Réponse de l'équipe
                      </div>
                      <p className="whitespace-pre-wrap break-words">{m.reply}</p>
                    </div>
                  ) : (
                    <div className="flex items-center gap-1 text-[10px] text-amber-600 dark:text-amber-400">
                      <Loader2 className="w-3 h-3 animate-spin" /> En attente de réponse…
                    </div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>

        <div className="p-5 pt-3 shrink-0 space-y-2">
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Décrivez votre problème ou question…"
            rows={3}
            className="w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40 resize-none"
          />
          <button
            onClick={send}
            disabled={sending || message.trim().length < 5}
            className="w-full py-3 rounded-xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-2"
          >
            {sending ? <Loader2 className="w-4 h-4 animate-spin" /> : <Send className="w-4 h-4" />}
            Envoyer
          </button>
        </div>
      </div>
    </div>
  );
}
