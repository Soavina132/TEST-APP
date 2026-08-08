import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import DOMPurify from "dompurify";
import { ArrowLeft, ShieldCheck } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/confidentialite")({
  component: ConfidentialitePage,
  head: () => ({
    meta: [
      { title: "Politique de confidentialité — Lalao MADA" },
      { name: "description", content: "Politique de confidentialité de Lalao MADA." },
    ],
  }),
});

function ConfidentialitePage() {
  const [html, setHtml] = useState<string>("");
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    supabase.from("app_settings").select("privacy_html").eq("id", 1).maybeSingle().then(({ data }: any) => {
      setHtml((data?.privacy_html as string) || "");
      setLoaded(true);
    });
  }, []);

  return (
    <main className="max-w-2xl mx-auto px-4 py-5 space-y-4 min-h-screen">
      <div className="flex items-center gap-2">
        <Link to="/faq" className="p-2 rounded-full bg-secondary/60 active:scale-90 transition-transform">
          <ArrowLeft className="w-4 h-4" />
        </Link>
        <ShieldCheck className="w-5 h-5 text-primary" />
        <h1 className="text-xl font-extrabold">Politique de confidentialité</h1>
      </div>

      <div className="rounded-3xl bg-card border border-border/40 p-5">
        {!loaded ? (
          <div className="text-sm text-muted-foreground">Chargement…</div>
        ) : html.trim() ? (
          <div
            className="prose prose-sm dark:prose-invert max-w-none whitespace-pre-wrap leading-relaxed"
            dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }}
          />
        ) : (
          <div className="text-sm text-muted-foreground text-center py-8">
            Le contenu de la politique de confidentialité n'est pas encore disponible.
          </div>
        )}
      </div>
    </main>
  );
}
