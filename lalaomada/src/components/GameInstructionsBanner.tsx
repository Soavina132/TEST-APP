import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { X, Info } from "lucide-react";

export default function GameInstructionsBanner({ slug }: { slug: string }) {
  const [cfg, setCfg] = useState<{ rules_markdown: string; instructions_dismissible: boolean } | null>(null);
  const [hidden, setHidden] = useState(false);

  const storageKey = `rules-dismissed:${slug}`;

  useEffect(() => {
    (async () => {
      const { data } = await supabase
        .from("game_configs" as any)
        .select("rules_markdown,instructions_dismissible")
        .eq("slug", slug)
        .maybeSingle();
      if (data) setCfg(data as any);
    })();
  }, [slug]);

  useEffect(() => {
    if (!cfg) return;
    if (cfg.instructions_dismissible && localStorage.getItem(storageKey) === "1") {
      setHidden(true);
    } else {
      setHidden(false);
    }
  }, [cfg, storageKey]);

  if (!cfg || hidden || !cfg.rules_markdown?.trim()) return null;

  const dismiss = () => {
    localStorage.setItem(storageKey, "1");
    setHidden(true);
  };

  return (
    <div className="rounded-2xl bg-primary/5 border border-primary/20 p-3 flex gap-2 text-xs text-foreground">
      <Info className="w-4 h-4 shrink-0 mt-0.5 text-primary" />
      <div className="flex-1 whitespace-pre-wrap leading-relaxed">{cfg.rules_markdown}</div>
      {cfg.instructions_dismissible && (
        <button onClick={dismiss} aria-label="Masquer" className="opacity-60 hover:opacity-100 shrink-0">
          <X className="w-4 h-4" />
        </button>
      )}
    </div>
  );
}
