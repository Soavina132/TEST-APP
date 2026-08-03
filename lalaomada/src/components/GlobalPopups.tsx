import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { supabase } from "@/integrations/supabase/client";
import { copyText } from "@/lib/clipboard";
import { toast } from "sonner";
import {
  X, Share2, Download, Copy, Gift, Check,
  Phone, ShieldCheck, ChevronRight, Sparkles, Users,
} from "lucide-react";

/* ═══════════════════════════════════════════════════════════════════════════
   ANIMATIONS
   ═════════════════════════════════════════════════════════════════════════ */
const PopupStyles = () => (
  <style>{`
    @keyframes popup-backdrop-in {
      from { opacity: 0; }
      to   { opacity: 1; }
    }
    @keyframes popup-card-in {
      0%   { opacity: 0; transform: scale(0.92) translateY(20px); }
      60%  { opacity: 1; transform: scale(1.02) translateY(-4px); }
      100% { opacity: 1; transform: scale(1) translateY(0); }
    }
    @keyframes popup-card-in-mobile {
      0%   { opacity: 0; transform: translateY(100%); }
      100% { opacity: 1; transform: translateY(0); }
    }
    @keyframes float-up {
      0%, 100% { transform: translateY(0); }
      50%      { transform: translateY(-6px); }
    }
    @keyframes glow-pulse {
      0%, 100% { opacity: 0.3; }
      50%      { opacity: 0.6; }
    }
  `}</style>
);

/* ═══════════════════════════════════════════════════════════════════════════
   CLOSE BUTTON
   ═════════════════════════════════════════════════════════════════════════ */
function CloseBtn({ onClose }: { onClose: () => void }) {
  return (
    <button
      onClick={onClose}
      className="absolute top-3.5 right-3.5 w-8 h-8 rounded-xl bg-secondary/80 hover:bg-accent flex items-center justify-center transition-all active:scale-90 z-10"
      aria-label="Fermer"
    >
      <X className="w-4 h-4 text-muted-foreground" />
    </button>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════
   REFERRAL / SHARE POPUP
   ═════════════════════════════════════════════════════════════════════════ */
function ReferralPopup({
  refCode,
  downloadUrl,
  onClose,
}: {
  refCode: string;
  downloadUrl: string;
  onClose: () => void;
}) {
  const [copied, setCopied] = useState(false);

  const shareLink = useCallback(() => {
    const text = `🎮 Rejoins Lalao MADA avec mon code ${refCode} ! Joue au Ludo en ligne et gagne des Ariary. ${downloadUrl}`;
    if (navigator.share) {
      navigator.share({ text, title: "Lalao MADA" });
    } else {
      copyText(text).then(() => toast.success("Lien copié !"));
    }
  }, [refCode, downloadUrl]);

  const copyCode = useCallback(() => {
    if (!refCode) return;
    copyText(refCode).then(() => {
      setCopied(true);
      toast.success("Code copié !");
      setTimeout(() => setCopied(false), 2000);
    });
  }, [refCode]);

  return (
    <div
      className="fixed inset-0 z-[100] flex items-end sm:items-center justify-center bg-black/50 backdrop-blur-sm px-0 sm:px-4"
      onClick={onClose}
      style={{ animation: "popup-backdrop-in 0.25s ease both" }}
    >
      <div
        className="relative bg-card rounded-t-3xl sm:rounded-3xl border border-border/60 shadow-2xl max-w-sm w-full overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{ animation: "popup-card-in-mobile 0.35s cubic-bezier(0.34,1.56,0.64,1) both" }}
      >
        {/* Mobile handle */}
        <div className="sm:hidden flex justify-center pt-3 pb-1">
          <div className="w-10 h-1 rounded-full bg-border" />
        </div>

        <CloseBtn onClose={onClose} />

        {/* Header gradient banner */}
        <div className="relative px-6 pt-8 pb-6 overflow-hidden">
          {/* Glow background */}
          <div
            className="absolute inset-0 bg-gradient-to-br from-primary/15 via-orange-400/8 to-transparent"
            style={{ animation: "glow-pulse 3s ease-in-out infinite" }}
          />
          {/* Floating icon */}
          <div className="relative flex justify-center mb-4">
            <div
              className="relative w-20 h-20 rounded-3xl bg-gradient-to-br from-primary to-orange-500 flex items-center justify-center shadow-xl shadow-primary/20"
              style={{ animation: "float-up 3s ease-in-out infinite" }}
            >
              <Gift className="w-9 h-9 text-white" />
              {/* Sparkle accents */}
              <Sparkles className="w-4 h-4 text-yellow-300 absolute -top-1 -right-1" />
            </div>
          </div>

          {/* Title */}
          <div className="relative text-center space-y-2">
            <h2 className="text-xl font-black tracking-tight">
              Bienvenue sur Lalao MADA ! 🎉
            </h2>
            <p className="text-sm text-muted-foreground leading-relaxed max-w-[280px] mx-auto">
              Parrainez vos amis et gagnez des commissions sur leurs parties.
            </p>
          </div>
        </div>

        {/* Referral code card */}
        {refCode && (
          <div className="px-6 pb-4">
            <button
              onClick={copyCode}
              className="group w-full relative rounded-2xl bg-gradient-to-r from-primary/10 to-orange-400/8 border-2 border-primary/20 hover:border-primary/40 transition-all p-4 active:scale-[0.98]"
            >
              <div className="text-[10px] text-muted-foreground font-bold uppercase tracking-widest mb-1.5">
                Votre code de parrainage
              </div>
              <div className="flex items-center justify-center gap-2">
                <span className="font-mono font-black text-primary text-2xl tracking-[0.2em]">
                  {refCode}
                </span>
                <div className="ml-2 w-7 h-7 rounded-lg bg-primary/10 flex items-center justify-center group-hover:bg-primary/20 transition-colors">
                  {copied
                    ? <Check className="w-3.5 h-3.5 text-emerald-600" />
                    : <Copy className="w-3.5 h-3.5 text-primary" />
                  }
                </div>
              </div>
            </button>
          </div>
        )}

        {/* Stats row */}
        <div className="px-6 pb-5">
          <div className="grid grid-cols-3 gap-2">
            {[
              { icon: Users,       label: "Invitez",  value: "Amis" },
              { icon: Gift,        label: "Gagnez",    value: "Commissions" },
              { icon: ShieldCheck, label: "100%",       value: "Sécurisé" },
            ].map((s, i) => (
              <div key={i} className="flex flex-col items-center gap-1 rounded-2xl bg-secondary/50 p-2.5">
                <s.icon className="w-4 h-4 text-primary" />
                <span className="text-[10px] font-bold text-foreground">{s.value}</span>
                <span className="text-[9px] text-muted-foreground">{s.label}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Actions */}
        <div className="px-6 pb-6 space-y-2.5">
          {/* Download */}
          {downloadUrl && (
            <a
              href={downloadUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-3 w-full px-4 py-3 rounded-2xl bg-secondary hover:bg-accent transition-all active:scale-[0.98] group"
            >
              <div className="w-9 h-9 rounded-xl bg-primary/10 flex items-center justify-center">
                <Download className="w-4 h-4 text-primary" />
              </div>
              <span className="flex-1 text-sm font-semibold text-foreground">Télécharger l'app</span>
              <Share2 className="w-4 h-4 text-muted-foreground group-hover:text-primary transition-colors" />
            </a>
          )}

          {/* Share CTA */}
          <button
            onClick={shareLink}
            className="w-full flex items-center justify-center gap-2 py-3.5 rounded-2xl bg-gradient-to-r from-primary to-orange-500 text-white font-bold text-sm shadow-lg shadow-primary/25 active:scale-[0.98] transition-all hover:shadow-primary/40"
          >
            <Share2 className="w-4 h-4" />
            Partager et parrainer
          </button>

          {/* Later */}
          <button
            onClick={onClose}
            className="w-full py-2 text-xs text-muted-foreground font-medium hover:text-foreground transition-colors"
          >
            Plus tard
          </button>
        </div>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════
   PHONE VERIFICATION POPUP
   ═════════════════════════════════════════════════════════════════════════ */
function PhonePopup({
  onClose,
  onVerify,
}: {
  onClose: () => void;
  onVerify: () => void;
}) {
  return (
    <div
      className="fixed inset-0 z-[99] flex items-end sm:items-center justify-center bg-black/50 backdrop-blur-sm px-0 sm:px-4"
      onClick={onClose}
      style={{ animation: "popup-backdrop-in 0.25s ease both" }}
    >
      <div
        className="relative bg-card rounded-t-3xl sm:rounded-3xl border border-border/60 shadow-2xl max-w-sm w-full overflow-hidden"
        onClick={(e) => e.stopPropagation()}
        style={{ animation: "popup-card-in-mobile 0.35s cubic-bezier(0.34,1.56,0.64,1) both" }}
      >
        {/* Mobile handle */}
        <div className="sm:hidden flex justify-center pt-3 pb-1">
          <div className="w-10 h-1 rounded-full bg-border" />
        </div>

        <CloseBtn onClose={onClose} />

        {/* Header */}
        <div className="relative px-6 pt-8 pb-5 overflow-hidden">
          <div
            className="absolute inset-0 bg-gradient-to-br from-amber-500/15 via-amber-400/5 to-transparent"
            style={{ animation: "glow-pulse 3s ease-in-out infinite" }}
          />
          <div className="relative flex justify-center mb-4">
            <div
              className="w-20 h-20 rounded-3xl bg-gradient-to-br from-amber-400 to-orange-500 flex items-center justify-center shadow-xl shadow-amber-500/20"
              style={{ animation: "float-up 3s ease-in-out 0.5s infinite" }}
            >
              <Phone className="w-9 h-9 text-white" />
            </div>
          </div>
          <div className="relative text-center space-y-2">
            <h2 className="text-lg font-black tracking-tight">
              Vérifiez votre numéro 📱
            </h2>
            <p className="text-sm text-muted-foreground leading-relaxed max-w-[280px] mx-auto">
              Sécurisez votre compte et débloquez les retraits en vérifiant votre téléphone.
            </p>
          </div>
        </div>

        {/* Benefits */}
        <div className="px-6 pb-5">
          <div className="space-y-2 bg-secondary/50 rounded-2xl p-4">
            {[
              { icon: ShieldCheck, text: "Compte sécurisé",    color: "text-emerald-600" },
              { icon: Gift,        text: "Retraits débloqués",  color: "text-amber-600" },
              { icon: Sparkles,    text: "Accès aux jeux payants", color: "text-primary" },
            ].map((b, i) => (
              <div key={i} className="flex items-center gap-2.5">
                <div className="w-6 h-6 rounded-lg bg-card flex items-center justify-center shadow-sm">
                  <b.icon className={`w-3.5 h-3.5 ${b.color}`} />
                </div>
                <span className="text-sm font-medium text-foreground/80">{b.text}</span>
              </div>
            ))}
          </div>
        </div>

        {/* Action */}
        <div className="px-6 pb-6 space-y-2.5">
          <button
            onClick={onVerify}
            className="w-full flex items-center justify-between gap-2 py-3.5 px-4 rounded-2xl bg-gradient-to-r from-amber-500 to-orange-500 text-white font-bold text-sm shadow-lg shadow-amber-500/25 active:scale-[0.98] transition-all"
          >
            <span className="flex items-center gap-2">
              <Phone className="w-4 h-4" />
              Vérifier mon numéro
            </span>
            <ChevronRight className="w-4 h-4" />
          </button>
          <button
            onClick={onClose}
            className="w-full py-2 text-xs text-muted-foreground font-medium hover:text-foreground transition-colors"
          >
            Plus tard
          </button>
        </div>
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════
   MAIN COMPONENT
   ═════════════════════════════════════════════════════════════════════════ */
export default function GlobalPopups() {
  const { profile, user } = useAuth();
  const navigate = useNavigate();

  const [showSharePopup, setShowSharePopup] = useState(false);
  const [showPhonePopup, setShowPhonePopup] = useState(false);
  const [downloadUrl, setDownloadUrl] = useState("");
  const [refCode, setRefCode] = useState("");

  // Charger les settings
  useEffect(() => {
    supabase
      .from("app_settings")
      .select("download_url")
      .eq("id", 1)
      .maybeSingle()
      .then(({ data }) => {
        if (data) setDownloadUrl((data as any).download_url || "");
      });
  }, []);

  // 1. Popup de parrainage — 1er lancement seulement
  useEffect(() => {
    if (!user?.id) return;
    const key = `lalaomada_share_popup_${user.id}`;
    const seen = localStorage.getItem(key);
    if (!seen) {
      const t = setTimeout(() => {
        setShowSharePopup(true);
        localStorage.setItem(key, "1");
      }, 1500);
      return () => clearTimeout(t);
    }
  }, [user?.id]);

  // 2. Popup vérification téléphone — nouveaux users non vérifiés
  useEffect(() => {
    if (!profile || !user?.id) return;
    if (!profile.phone_verified) {
      const key = `lalaomada_phone_popup_${user.id}`;
      const seen = localStorage.getItem(key);
      if (!seen) {
        const t = setTimeout(() => {
          setShowPhonePopup(true);
          localStorage.setItem(key, "1");
        }, 3500); // après le popup partage
        return () => clearTimeout(t);
      }
    }
  }, [profile?.phone_verified, user?.id]);

  // Ref code
  useEffect(() => {
    if (profile?.referral_code) setRefCode(profile.referral_code);
  }, [profile?.referral_code]);

  return (
    <>
      <PopupStyles />

      {showSharePopup && (
        <ReferralPopup
          refCode={refCode}
          downloadUrl={downloadUrl}
          onClose={() => setShowSharePopup(false)}
        />
      )}

      {showPhonePopup && !profile?.phone_verified && (
        <PhonePopup
          onClose={() => setShowPhonePopup(false)}
          onVerify={() => {
            setShowPhonePopup(false);
            navigate({ to: "/profile" });
          }}
        />
      )}
    </>
  );
}
