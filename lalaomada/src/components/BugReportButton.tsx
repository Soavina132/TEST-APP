import { useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Bug, X, Send, ChevronDown } from "lucide-react";

const CATEGORIES = [
  { value: "bug",        label: "🐛 Problème technique" },
  { value: "payment",    label: "💳 Problème de paiement" },
  { value: "game",       label: "🎮 Problème de jeu" },
  { value: "suggestion", label: "💡 Suggestion" },
  { value: "general",    label: "📝 Autre" },
];

export default function BugReportButton() {
  const [open, setOpen] = useState(false);
  const [category, setCategory] = useState("bug");
  const [message, setMessage] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit() {
    if (message.trim().length < 5) {
      toast.error("Message trop court (min. 5 caractères)");
      return;
    }
    setBusy(true);
    const { error } = await (supabase.rpc as any)("submit_bug_report", {
      _category: category,
      _message: message.trim(),
    });
    setBusy(false);
    if (error) { toast.error("Erreur lors de l'envoi"); return; }
    toast.success("Signalement envoyé — merci !");
    setMessage("");
    setCategory("bug");
    setOpen(false);
  }

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        aria-label="Signaler un problème"
        title="Signaler un problème"
        className="fixed bottom-24 right-4 md:bottom-6 md:right-6 z-40 w-12 h-12 rounded-full bg-primary text-primary-foreground shadow-lg flex items-center justify-center hover:scale-110 active:scale-95 transition-transform"
      >
        <Bug className="w-5 h-5" />
      </button>

      {open && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-end sm:items-center justify-center p-4"
          onClick={() => setOpen(false)}>
          <div className="bg-card rounded-3xl w-full max-w-md p-5 space-y-4 shadow-2xl"
            onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between">
              <div className="font-bold text-lg flex items-center gap-2">
                <Bug className="w-5 h-5 text-primary" /> Signaler un problème
              </div>
              <button onClick={() => setOpen(false)} className="p-1.5 rounded-full hover:bg-accent">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="relative">
              <select value={category} onChange={e => setCategory(e.target.value)}
                className="w-full appearance-none bg-secondary rounded-xl px-4 py-3 text-sm font-medium cursor-pointer pr-10 focus:outline-none focus:ring-2 focus:ring-primary/40">
                {CATEGORIES.map(c => (
                  <option key={c.value} value={c.value}>{c.label}</option>
                ))}
              </select>
              <ChevronDown className="absolute right-3 top-1/2 -translate-y-1/2 w-4 h-4 pointer-events-none text-muted-foreground" />
            </div>

            <div>
              <textarea
                value={message}
                onChange={e => setMessage(e.target.value)}
                placeholder="Décrivez le problème en détail…"
                rows={4}
                maxLength={1000}
                className="w-full bg-secondary rounded-xl px-4 py-3 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-primary/40 placeholder:text-muted-foreground"
              />
              <div className="text-right text-xs text-muted-foreground mt-1">{message.length}/1000</div>
            </div>

            <button onClick={submit} disabled={busy || message.trim().length < 5}
              className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2 disabled:opacity-50 hover:bg-primary/90 active:scale-[0.98] transition-all">
              <Send className="w-4 h-4" />
              {busy ? "Envoi…" : "Envoyer le signalement"}
            </button>

            <p className="text-center text-xs text-muted-foreground">
              Votre signalement sera examiné par l'équipe dans les meilleurs délais.
            </p>
          </div>
        </div>
      )}
    </>
  );
}
