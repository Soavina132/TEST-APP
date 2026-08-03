import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Info, X } from "lucide-react";
import { useT } from "@/lib/i18n";
import { useAuth } from "@/hooks/use-auth";

export default function PauseBanner() {
  const { t } = useT();
  const { isAdmin } = useAuth();
  const [s, setS] = useState<{ paused: boolean; pause_message: string | null } | null>(null);
  const [closed, setClosed] = useState(false);
  useEffect(() => {
    const load = () => supabase.from("app_settings").select("paused,pause_message").eq("id", 1).maybeSingle().then(({ data }) => setS(data as any));
    load();
    const ch = supabase.channel("app-settings")
      .on("postgres_changes", { event: "*", schema: "public", table: "app_settings" }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);
  if (!s?.paused || closed || isAdmin) return null;
  return (
    <div className="fixed inset-0 z-[70] bg-slate-900/80 backdrop-blur-sm flex items-center justify-center p-6">
      <div className="bg-card max-w-sm w-full rounded-3xl p-6 shadow-2xl text-center space-y-3">
        <div className="w-14 h-14 mx-auto rounded-full bg-amber-100 dark:bg-amber-900/40 flex items-center justify-center">
          <Info className="w-7 h-7 text-amber-600" />
        </div>
        <div className="text-xl font-extrabold">{t("maintenance_title")}</div>
        <div className="text-sm text-muted-foreground whitespace-pre-wrap">
          {s.pause_message || t("maintenance_default")}
        </div>
        <button onClick={() => setClosed(true)} className="w-full py-3 rounded-full bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2">
          <X className="w-4 h-4" /> {t("close_btn")}
        </button>
      </div>
    </div>
  );
}
