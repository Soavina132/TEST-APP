import { createFileRoute } from "@tanstack/react-router";
import { LinkPreviewCard, LinkifyWithPreview } from "@/components/LinkPreview";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { BookOpen, FileText, PlayCircle } from "lucide-react";
import { useT } from "@/lib/i18n";
import { facebookTargets, openExternal } from "@/lib/open-external";

export const Route = createFileRoute("/_authenticated/tutos")({
  component: TutosPage,
  loader: async () => {
    const { data } = await supabase.from("app_settings").select("tutorials,terms_text").eq("id", 1).maybeSingle();
    return { tutorials: (data?.tutorials as any[]) || [], terms: (data?.terms_text as string) || "" };
  },
  head: ({ loaderData }) => {
    const faqs = (loaderData?.tutorials || []).filter((t: any) => t?.title && t?.content);
    return {
      meta: [
        { title: "Tutoriels & FAQ — Lalao MADA" },
        { name: "description", content: "Apprenez les règles du Lalao MADA : comment déposer, retirer, créer une partie, capturer un pion et remporter la cagnotte." },
        { property: "og:title", content: "Tutoriels & FAQ — Lalao MADA" },
        { property: "og:description", content: "Règles, dépôts/retraits et astuces pour jouer au Lalao MADA." },
        { property: "og:url", content: "https://lalaomada.lovable.app/tutos" },
      ],
      links: [{ rel: "canonical", href: "https://lalaomada.lovable.app/tutos" }],
      scripts: faqs.length > 0 ? [{
        type: "application/ld+json",
        children: JSON.stringify({
          "@context": "https://schema.org",
          "@type": "FAQPage",
          mainEntity: faqs.map((t: any) => ({
            "@type": "Question",
            name: t.title,
            acceptedAnswer: { "@type": "Answer", text: t.content },
          })),
        }),
      }] : [],
    };
  },
});



function TutosPage() {
  const { t } = useT();
  const [tutos, setTutos] = useState<any[]>([]);
  const [terms, setTerms] = useState("");
  const [tutoUrl, setTutoUrl] = useState<string>("");
  useEffect(() => {
    supabase.from("app_settings").select("tutorials,terms_text,tuto_url").eq("id", 1).maybeSingle().then(({ data }) => {
      setTutos((data?.tutorials as any[]) || []);
      setTerms((data?.terms_text as string) || "");
      setTutoUrl(((data as any)?.tuto_url as string) || "");
    });
  }, []);
  return (
    <main className="max-w-2xl mx-auto px-4 py-6 space-y-4">
      <h1 className="text-2xl font-extrabold flex items-center gap-2"><BookOpen className="text-primary" /> {t("tutos_title_full")}</h1>
      {tutoUrl && (() => {
        const isFb = /facebook\.com|fb\.com/i.test(tutoUrl);
        const target = isFb ? facebookTargets(tutoUrl) : { webUrl: tutoUrl };
        return (
          <a
            href={target.appUrl || target.webUrl}
            target="_top"
            rel="noopener noreferrer"
            onClick={(e) => {
              e.preventDefault();
              openExternal(target);
            }}
            className="flex items-center justify-center gap-2 w-full rounded-2xl bg-primary text-primary-foreground font-semibold py-3 shadow-sm hover:opacity-90 transition"
          >
            <PlayCircle className="w-5 h-5" /> TUTO vidéo
          </a>
        );
      })()}
      {tutos.length === 0 && !terms ? (
        <div className="rounded-3xl bg-card p-8 text-center text-muted-foreground">{t("no_content")}</div>
      ) : null}
      {tutos.map((t, i) => (
        <div key={i} className="rounded-3xl bg-card p-5 shadow-sm">
          <div className="font-bold text-lg mb-1">{t.title || `Tuto ${i + 1}`}</div>
          <div className="text-sm whitespace-pre-wrap leading-relaxed"><LinkifyWithPreview text={t.content || ""} /></div>
            {/https?:\/\//.test(t.content || "") && <LinkPreviewCard text={t.content || ""} className="mt-2" />}
        </div>
      ))}
      {terms.trim() && (
        <div className="rounded-3xl bg-card p-5 shadow-sm">
          <div className="font-bold text-lg mb-1 flex items-center gap-2"><FileText className="w-5 h-5 text-primary" /> {t("terms_of_use")}</div>
          <div className="text-sm whitespace-pre-wrap leading-relaxed"><LinkifyWithPreview text={terms} /></div>
        </div>
      )}
    </main>
  );
}
