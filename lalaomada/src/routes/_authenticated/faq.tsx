import { createFileRoute } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { ChevronDown, ChevronUp, HelpCircle, MessageSquare, Phone, Headphones, BookOpen } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useT } from "@/lib/i18n";
import { useCmsContent } from "@/hooks/use-cms-content";
import { DEFAULT_FAQ, resolveFaqAnswer } from "@/lib/faq-defaults";
import { useNavigate } from "@tanstack/react-router";

export const Route = createFileRoute("/_authenticated/faq")({
  component: FaqPage,
  head: () => ({ meta: [{ title: "Centre d'aide — Lalao MADA" }] }),
});

function FaqItem({ q, a }: { q: string; a: string }) {
  const [open, setOpen] = useState(false);
  return (
    <div className={`border-b border-border/40 last:border-0 transition-colors ${open ? "bg-accent/30" : ""}`}>
      <button
        onClick={() => setOpen(!open)}
        className="w-full flex items-start justify-between gap-3 p-4 text-left"
      >
        <span className="font-semibold text-sm leading-snug">{q}</span>
        {open
          ? <ChevronUp className="w-4 h-4 text-muted-foreground shrink-0 mt-0.5" />
          : <ChevronDown className="w-4 h-4 text-muted-foreground shrink-0 mt-0.5" />
        }
      </button>
      {open && (
        <div className="px-4 pb-4 text-sm text-muted-foreground leading-relaxed">
          {a}
        </div>
      )}
    </div>
  );
}

export default function FaqPage() {
  const { t } = useT();
  const navigate = useNavigate();
  const [search, setSearch] = useState("");
  const [adminPhone, setAdminPhone] = useState<string | null>(null);
  const { data: faq } = useCmsContent("faq", DEFAULT_FAQ);

  useEffect(() => {
    supabase.from("settings" as any)
      .select("admin_phone")
      .maybeSingle()
      .then(({ data }: any) => {
        if (data?.admin_phone) setAdminPhone(data.admin_phone);
      });
  }, []);

  const items = (faq?.categories ?? []).map(cat => ({
    ...cat,
    items: cat.items.map(it => ({ q: it.q, a: resolveFaqAnswer(it.a) })),
  }));

  const filtered = search.trim()
    ? items.map(cat => ({
        ...cat,
        items: cat.items.filter(item =>
          item.q.toLowerCase().includes(search.toLowerCase()) ||
          item.a.toLowerCase().includes(search.toLowerCase())
        ),
      })).filter(cat => cat.items.length > 0)
    : items;

  return (
    <main className="max-w-2xl mx-auto px-4 py-5 space-y-4">
      <div className="flex items-center gap-2">
        <HelpCircle className="w-6 h-6 text-primary" />
        <h1 className="text-2xl font-extrabold">Centre d'aide</h1>
      </div>

      {/* Search */}
      <div className="relative">
        <input
          value={search}
          onChange={e => setSearch(e.target.value)}
          placeholder="Rechercher une question…"
          className="w-full pl-4 pr-10 py-3 rounded-2xl bg-card border border-border/60 shadow-sm outline-none text-sm"
        />
        {search && (
          <button onClick={() => setSearch("")}
            className="absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground">
            ×
          </button>
        )}
      </div>

      {/* FAQ sections */}
      {filtered.length === 0 ? (
        <div className="text-center text-muted-foreground py-12">
          <HelpCircle className="w-10 h-10 mx-auto mb-3 opacity-30" />
          <div className="text-sm">Aucun résultat pour « {search} »</div>
        </div>
      ) : (
        filtered.map(cat => (
          <div key={cat.category} className="rounded-3xl bg-card shadow-sm border border-border/40 overflow-hidden">
            <div className="px-4 py-3 bg-accent/50 font-bold text-sm border-b border-border/40">
              {cat.category}
            </div>
            {cat.items.map(item => <FaqItem key={item.q} q={item.q} a={item.a} />)}
          </div>
        ))
      )}

      {/* Contact card */}
      <div className="rounded-3xl bg-gradient-to-br from-primary/10 to-primary/5 border border-primary/20 p-5 space-y-3">
        <div className="font-bold text-base flex items-center gap-2">
          <MessageSquare className="w-5 h-5 text-primary" /> Vous n'avez pas trouvé votre réponse ?
        </div>
        <div className="text-sm text-muted-foreground">
          Notre équipe est disponible pour vous aider directement.
        </div>
        <div className="grid grid-cols-2 gap-2">
          <button onClick={() => navigate({ to: "/chat", search: { dm: undefined } })}
            className="flex items-center justify-center gap-2 py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition-transform">
            <MessageSquare className="w-4 h-4" /> Support chat
          </button>
          {adminPhone ? (
            <a href={`tel:${adminPhone}`}
              className="flex items-center justify-center gap-2 py-3 rounded-2xl bg-secondary font-bold text-sm">
              <Phone className="w-4 h-4" /> Appeler l'admin
            </a>
          ) : (
            <button onClick={() => navigate({ to: "/tutos", search: {} })}
              className="flex items-center justify-center gap-2 py-3 rounded-2xl bg-secondary font-bold text-sm">
              <BookOpen className="w-4 h-4" /> Tutoriels
            </button>
          )}
        </div>
      </div>
    </main>
  );
}
