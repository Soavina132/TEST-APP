import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Link } from "@tanstack/react-router";
import { Download, Phone, MessageCircle, Mail, BookOpen, Facebook, X } from "lucide-react";
import { useT } from "@/lib/i18n";
import { facebookTargets, openExternal, whatsappTargets } from "@/lib/open-external";

export default function AppMenu({ open, onClose }: { open: boolean; onClose: () => void }) {
  const { t } = useT();
  const [s, setS] = useState<any>(null);
  useEffect(() => {
    if (open) supabase.from("app_settings").select("*").eq("id", 1).maybeSingle().then(({ data }) => setS(data));
  }, [open]);
  if (!open) return null;
  const facebookLink = s?.contact_facebook ? facebookTargets(s.contact_facebook) : null;
  const whatsappLink = s?.contact_whatsapp ? whatsappTargets(s.contact_whatsapp) : null;

  return (
    <div className="fixed inset-0 z-50 bg-black/50 flex items-end sm:items-center justify-center p-4" onClick={onClose}>
      <div className="bg-card rounded-3xl w-full max-w-md p-5 space-y-3" onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between">
          <div className="font-bold text-lg">Menu</div>
          <button onClick={onClose}><X className="w-5 h-5" /></button>
        </div>

        {s?.download_url && (
          <a href={s.download_url} target="_blank" rel="noopener noreferrer"
            className="w-full px-4 py-3 rounded-2xl bg-primary text-primary-foreground font-semibold flex items-center gap-3">
            <Download className="w-5 h-5" /> {t("download_app")}
          </a>
        )}

        <Link to="/tutos" onClick={onClose} className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3">
          <BookOpen className="w-5 h-5" /> {t("tutorial")}
        </Link>

        <div className="text-xs uppercase text-muted-foreground tracking-wider pt-2">{t("contact_us_label")}</div>
        <div className="grid grid-cols-2 gap-2">
          {facebookLink && (
            <a href={facebookLink.appUrl} target="_top" rel="noopener noreferrer" onClick={(e) => { e.preventDefault(); openExternal(facebookLink); }} className="px-3 py-2.5 rounded-xl bg-secondary text-sm font-semibold flex items-center gap-2">
              <Facebook className="w-4 h-4" /> Facebook
            </a>
          )}
          {whatsappLink && (
            <a href={whatsappLink.appUrl} target="_top" rel="noopener noreferrer" onClick={(e) => { e.preventDefault(); openExternal(whatsappLink); }} className="px-3 py-2.5 rounded-xl bg-secondary text-sm font-semibold flex items-center gap-2">
              <MessageCircle className="w-4 h-4" /> WhatsApp
            </a>
          )}
          {s?.contact_phone && (
            <a href={`tel:${s.contact_phone}`} className="px-3 py-2.5 rounded-xl bg-secondary text-sm font-semibold flex items-center gap-2">
              <Phone className="w-4 h-4" /> {s.contact_phone}
            </a>
          )}
          {s?.contact_email && (
            <a href={`mailto:${s.contact_email}`} className="px-3 py-2.5 rounded-xl bg-secondary text-sm font-semibold flex items-center gap-2">
              <Mail className="w-4 h-4" /> Email
            </a>
          )}
        </div>
      </div>
    </div>
  );
}
