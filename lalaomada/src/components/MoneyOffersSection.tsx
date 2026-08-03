import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Gift, ExternalLink } from "lucide-react";
import { useT } from "@/lib/i18n";

export default function MoneyOffersSection() {
  const { t } = useT();
  const [items, setItems] = useState<any[]>([]);

  useEffect(() => {
    const load = async () => {
      const { data } = await (supabase.from("money_offers" as any) as any).select("*").eq("active", true)
        .order("created_at", { ascending: false });
      const now = Date.now();
      setItems((data || []).filter((o: any) => !o.expires_at || new Date(o.expires_at).getTime() > now));
    };
    load();
    const ch = supabase.channel("offers")
      .on("postgres_changes", { event: "*", schema: "public", table: "money_offers" }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  if (!items.length) return null;
  return (
    <section className="rounded-3xl bg-gradient-to-br from-emerald-50 to-cyan-50 dark:from-emerald-950/40 dark:to-cyan-950/40 p-4 shadow-sm space-y-3">
      <div className="font-extrabold flex items-center gap-2 text-emerald-700 dark:text-emerald-300">
        <Gift className="w-5 h-5" /> {t("earn_money_free")}
      </div>
      <div className="space-y-2">
        {items.map((o: any) => (
          <a key={o.id} href={o.link || "#"} target={o.link ? "_blank" : undefined} rel="noopener noreferrer"
            className="block bg-card rounded-2xl p-3 shadow-sm hover:shadow-md transition">
            <div className="flex gap-3">
              {o.image_url && <img src={o.image_url} alt={o.title} width={64} height={64} loading="lazy" decoding="async" className="w-16 h-16 rounded-xl object-cover shrink-0" />}
              <div className="flex-1 min-w-0">
                <div className="font-bold leading-tight">{o.title}</div>
                {o.description && <div className="text-xs text-muted-foreground line-clamp-2 mt-0.5">{o.description}</div>}
                {o.link && <div className="text-xs text-primary font-bold flex items-center gap-1 mt-1"><ExternalLink className="w-3 h-3" /> {t("participate_btn")}</div>}
              </div>
            </div>
          </a>
        ))}
      </div>
    </section>
  );
}
