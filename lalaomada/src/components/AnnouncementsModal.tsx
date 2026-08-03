import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { X, ExternalLink } from "lucide-react";
import { useT } from "@/lib/i18n";

export default function AnnouncementsModal() {
  const { t } = useT();
  const [items, setItems] = useState<any[]>([]);
  const [idx, setIdx] = useState(0);

  useEffect(() => {
    const load = async () => {
      const { data } = await (supabase.from("announcements" as any) as any).select("*").eq("active", true).order("created_at", { ascending: false });
      const seen: Record<string, number> = JSON.parse(localStorage.getItem("ann:seen") || "{}");
      const unseen = (data || []).filter((a: any) => !seen[a.id]);
      setItems(unseen);
      setIdx(0);
    };
    load();
    const interval = setInterval(load, 60_000);
    return () => clearInterval(interval);
  }, []);

  const close = () => {
    const a = items[idx];
    if (a) {
      const seen: Record<string, number> = JSON.parse(localStorage.getItem("ann:seen") || "{}");
      seen[a.id] = Date.now();
      localStorage.setItem("ann:seen", JSON.stringify(seen));
    }
    if (idx + 1 < items.length) setIdx(i => i + 1);
    else setItems([]);
  };

  if (!items.length) return null;
  const a = items[idx];

  return (
    <div className="fixed inset-0 z-[80] bg-black/70 flex items-center justify-center p-4 animate-in fade-in">
      <div className="bg-card max-w-md w-full rounded-3xl overflow-hidden shadow-2xl">
        {a.image_url && <img src={a.image_url} alt={a.title} loading="lazy" decoding="async" className="w-full h-48 object-cover" />}
        <div className="p-5 space-y-3">
          <div className="text-xs uppercase font-bold text-primary tracking-widest">{t("announcement_label")}</div>
          <h2 className="text-2xl font-extrabold leading-tight">{a.title}</h2>
          {a.body && <p className="text-sm text-muted-foreground whitespace-pre-wrap">{a.body}</p>}
          <div className="flex gap-2 pt-2">
            {a.link && (
              <a href={a.link} target="_blank" rel="noopener noreferrer"
                className="flex-1 py-3 rounded-full bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2">
                <ExternalLink className="w-4 h-4" /> {a.link_label || t("learn_more_btn")}
              </a>
            )}
            <button onClick={close} className={`${a.link ? "px-5" : "flex-1"} py-3 rounded-full bg-secondary font-bold flex items-center justify-center gap-2`}>
              <X className="w-4 h-4" /> {t("close_btn")}
            </button>
          </div>
          {items.length > 1 && <div className="text-center text-[10px] text-muted-foreground">{idx + 1} / {items.length}</div>}
        </div>
      </div>
    </div>
  );
}
