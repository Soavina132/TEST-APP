import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import DOMPurify from "dompurify";
import { ArrowLeft, FileText } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

export const Route = createFileRoute("/cgu")({
  component: CguPage,
  head: () => ({
    meta: [
      { title: "Conditions d'utilisation — Lalao MADA" },
      { name: "description", content: "Conditions générales d'utilisation de Lalao MADA." },
    ],
  }),
});

function CguPage() {
  const [html, setHtml] = useState<string>("");
  const [loaded, setLoaded] = useState(false);

  useEffect(() => {
    supabase.from("app_settings").select("terms_html, terms_text").eq("id", 1).maybeSingle().then(({ data }: any) => {
      setHtml((data?.terms_html as string) || (data?.terms_text as string) || "");
      setLoaded(true);
    });
  }, []);

  return (
    <main className="max-w-2xl mx-auto px-4 py-5 space-y-4 min-h-screen">
      <div className="flex items-center gap-2">
        <Link to="/faq" className="p-2 rounded-full bg-secondary/60 active:scale-90 transition-transform">
          <ArrowLeft className="w-4 h-4" />
        </Link>
        <FileText className="w-5 h-5 text-primary" />
        <h1 className="text-xl font-extrabold">Conditions d'utilisation</h1>
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
            Le contenu des conditions d'utilisation n'est pas encore disponible.
          </div>
        )}
      </div>
    </main>
  );
}
