import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { copyText } from "@/lib/clipboard";
import { toast } from "sonner";
import { Gift, Copy, Share2, X } from "lucide-react";

const SESSION_KEY = "share-cta-seen";

/**
 * CTA discret (bandeau bas, non bloquant) invitant l'utilisateur à partager
 * l'application avec son lien de téléchargement et son code de parrainage.
 * Affiché une fois par session, auto-masqué après 20 s.
 */
export default function ShareAppCta() {
  const { profile } = useAuth();
  const [visible, setVisible] = useState(false);
  const [downloadUrl, setDownloadUrl] = useState("");
  const code = profile?.referral_code || "";

  useEffect(() => {
    if (!code) return;
    if (typeof window === "undefined") return;
    if (sessionStorage.getItem(SESSION_KEY)) return;

    let alive = true;
    supabase
      .from("app_settings")
      .select("referral_enabled, download_url")
      .eq("id", 1)
      .maybeSingle()
      .then(({ data }) => {
        if (!alive) return;
        const cfg = data as any;
        if (cfg && cfg.referral_enabled === false) return;
        setDownloadUrl(((cfg?.download_url as string) || "").trim());
        const t = setTimeout(() => setVisible(true), 1200);
        return () => clearTimeout(t);
      });

    return () => { alive = false; };
  }, [code]);

  useEffect(() => {
    if (!visible) return;
    const t = setTimeout(() => close(), 20000);
    return () => clearTimeout(t);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [visible]);

  const close = () => {
    setVisible(false);
    try { sessionStorage.setItem(SESSION_KEY, "1"); } catch { /* ignore */ }
  };

  if (!visible || !code) return null;

  const link = downloadUrl || (typeof window !== "undefined" ? window.location.origin : "");
  const message = `Rejoins-moi sur Lalao MADA 🎮\n${link}\nCode de parrainage : ${code}`;

  const onShare = async () => {
    close();
    if (typeof navigator !== "undefined" && navigator.share) {
      try { await navigator.share({ title: "Lalao MADA", text: message }); return; } catch { /* annulé */ }
    }
    const ok = await copyText(message);
    toast[ok ? "success" : "error"](ok ? "Invitation copiée !" : "Impossible de copier");
  };

  const onCopy = async () => {
    const ok = await copyText(message);
    toast[ok ? "success" : "error"](ok ? "Invitation copiée !" : "Impossible de copier");
    close();
  };

  return (
    <div className="fixed inset-x-0 bottom-[4.5rem] md:bottom-4 z-40 px-3 pointer-events-none animate-in slide-in-from-bottom-4 fade-in duration-500">
      <div className="pointer-events-auto mx-auto max-w-md rounded-2xl border border-border/60 bg-card/95 backdrop-blur shadow-lg p-3 flex items-center gap-3">
        <div className="shrink-0 w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center">
          <Gift className="w-4.5 h-4.5 text-primary" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="text-sm font-semibold leading-tight">Invitez vos amis, gagnez plus</div>
          <div className="text-[11px] text-muted-foreground truncate">
            Code <span className="font-mono font-bold text-foreground">{code}</span>
            {link ? " · lien de téléchargement inclus" : ""}
          </div>
        </div>
        <button
          onClick={onCopy}
          aria-label="Copier l'invitation"
          className="shrink-0 h-9 w-9 rounded-xl bg-secondary/70 flex items-center justify-center hover:bg-secondary transition-colors"
        >
          <Copy className="w-4 h-4" />
        </button>
        <button
          onClick={onShare}
          className="shrink-0 h-9 px-3 rounded-xl bg-primary text-primary-foreground text-xs font-bold flex items-center gap-1.5 hover:opacity-90 transition-opacity"
        >
          <Share2 className="w-3.5 h-3.5" /> Partager
        </button>
        <button
          onClick={close}
          aria-label="Fermer"
          className="shrink-0 h-7 w-7 rounded-lg text-muted-foreground hover:text-foreground flex items-center justify-center"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}
