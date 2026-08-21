import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { MessageCircle, Facebook, Mail, Phone, X, Headphones, BookOpen, Download, Users } from "lucide-react";
import { facebookTargets, openExternal, whatsappTargets } from "@/lib/open-external";

type Contacts = {
  contact_whatsapp?: string | null;
  contact_email?: string | null;
  admin_phone?: string | null;
  tuto_url?: string | null;
  update_url?: string | null;
};

const APK_URL =
  "https://www.mediafire.com/file/4d99q2icylpeqzj/Lalao+MADA.apk/file?dkey=py2l2af6j1z&r=1343";
const FACEBOOK_ADMIN_URL = "https://www.facebook.com/RJean.pierrit";
const WHATSAPP_GROUP_URL =
  "https://chat.whatsapp.com/El7cElnD6pyLDcT6uCK47e?s=cl&p=a&ilr=4";

export default function ContactFab() {
  const [open, setOpen] = useState(false);
  const [c, setC] = useState<Contacts>({});

  useEffect(() => {
    supabase
      .from("app_settings")
      .select("contact_whatsapp,contact_email,admin_phone,tuto_url,update_url")
      .eq("id", 1)
      .maybeSingle()
      .then(({ data }) => data && setC(data as Contacts));
  }, []);

  const waNumber = (c.contact_whatsapp || "").replace(/\D/g, "");
  const whatsappLink = waNumber ? whatsappTargets(waNumber) : null;
  const facebookAdminLink = facebookTargets(FACEBOOK_ADMIN_URL);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        aria-label="Contact"
        style={{ background: "var(--gradient-primary)" }}
        className="fixed bottom-24 right-4 z-40 h-14 w-14 rounded-full text-white shadow-2xl flex items-center justify-center hover:scale-110 active:scale-95 transition"
      >
        <Headphones className="w-6 h-6" />
      </button>

      {open && (
        <div
          className="fixed inset-0 z-[60] bg-black/50 flex items-end sm:items-center justify-center p-4"
          onClick={() => setOpen(false)}
        >
          <div
            className="bg-card rounded-3xl w-full max-w-sm p-5 space-y-3 shadow-2xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center justify-between">
              <div className="font-bold text-lg">Nous contacter</div>
              <button onClick={() => setOpen(false)} aria-label="Fermer">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-2">
              {whatsappLink && (
                <a
                  href={whatsappLink.appUrl}
                  target="_top"
                  rel="noopener noreferrer"
                  onClick={(e) => {
                    e.preventDefault();
                    openExternal(whatsappLink);
                  }}
                  className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition"
                >
                  <MessageCircle className="w-5 h-5" /> WhatsApp
                </a>
              )}
              {c.contact_email && (
                <a
                  href={`mailto:${c.contact_email}`}
                  className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition"
                >
                  <Mail className="w-5 h-5" /> E-mail
                </a>
              )}
              {c.admin_phone && (
                <a
                  href={`tel:${c.admin_phone}`}
                  className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition"
                >
                  <Phone className="w-5 h-5" /> {c.admin_phone}
                </a>
              )}
              {c.tuto_url && (() => {
                const isFb = /facebook\.com|fb\.com/i.test(c.tuto_url!);
                const target = isFb ? facebookTargets(c.tuto_url!) : { webUrl: c.tuto_url! };
                return (
                  <a
                    href={(target as any).appUrl || target.webUrl}
                    target="_top"
                    rel="noopener noreferrer"
                    onClick={(e) => {
                      e.preventDefault();
                      openExternal(target);
                    }}
                    className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition"
                  >
                    <BookOpen className="w-5 h-5" /> TUTO
                  </a>
                );
              })()}
              {c.update_url && (() => {
                const isFb = /facebook\.com|fb\.com/i.test(c.update_url!);
                const target = isFb ? facebookTargets(c.update_url!) : { webUrl: c.update_url! };
                return (
                  <a
                    href={(target as any).appUrl || target.webUrl}
                    target="_top"
                    rel="noopener noreferrer"
                    onClick={(e) => {
                      e.preventDefault();
                      openExternal(target);
                    }}
                    className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition"
                  >
                    <Download className="w-5 h-5" /> Mise à jour
                  </a>
                );
              })()}

              <div className="border-t border-border pt-2 mt-1 space-y-2">
                <a
                  href={APK_URL}
                  target="_top"
                  rel="noopener noreferrer"
                  onClick={(e) => {
                    e.preventDefault();
                    openExternal({ webUrl: APK_URL });
                  }}
                  className="w-full px-4 py-3 rounded-2xl bg-secondary font-semibold flex items-center gap-3 active:scale-95 transition"
                >
                  <Download className="w-5 h-5" /> Télécharger l'APK
                </a>

                <a
                  href={facebookAdminLink.appUrl}
                  target="_top"
                  rel="noopener noreferrer"
                  onClick={(e) => {
                    e.preventDefault();
                    openExternal(facebookAdminLink);
                  }}
                  className="w-full px-4 py-3 rounded-2xl bg-[#1877F2] text-white font-semibold flex items-center gap-3 active:scale-95 transition"
                >
                  <Facebook className="w-5 h-5" /> Facebook admin
                </a>

                <a
                  href={WHATSAPP_GROUP_URL}
                  target="_top"
                  rel="noopener noreferrer"
                  onClick={(e) => {
                    e.preventDefault();
                    openExternal({ webUrl: WHATSAPP_GROUP_URL });
                  }}
                  className="w-full px-4 py-3 rounded-2xl bg-[#25D366] text-white font-semibold flex items-center gap-3 active:scale-95 transition"
                >
                  <Users className="w-5 h-5" /> Groupe WhatsApp
                </a>
              </div>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
