import { useState } from "react";
import { ShieldAlert, X } from "lucide-react";
import PhoneVerifyPopup from "./PhoneVerifyPopup";

/**
 * PhoneVerifyBanner — notification cliquable affichée dans les jeux avec mise.
 * S'affiche uniquement si: stake > 0 ET phoneVerified = false.
 */
export default function PhoneVerifyBanner({ stake, phoneVerified }: { stake: number; phoneVerified?: boolean }) {
  const [showPopup, setShowPopup] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  if (stake <= 0 || dismissed || phoneVerified) return null;

  return (
    <>
      <button
        onClick={() => setShowPopup(true)}
        className="w-full flex items-center gap-2 px-3 py-2 rounded-xl bg-amber-500/10 border border-amber-500/30 text-amber-600 dark:text-amber-400 text-xs font-medium active:scale-[0.98] transition animate-pulse-slow"
      >
        <ShieldAlert className="w-4 h-4 shrink-0" />
        <span className="flex-1 text-left">Vérifiez votre numéro pour jouer avec mise</span>
        <span className="font-bold underline">Vérifier →</span>
        <span
          role="button"
          tabIndex={-1}
          onClick={(e) => { e.stopPropagation(); setDismissed(true); }}
          className="shrink-0 p-0.5 hover:bg-amber-500/20 rounded-full transition"
        >
          <X className="w-3.5 h-3.5" />
        </span>
      </button>
      {showPopup && <PhoneVerifyPopup onClose={() => setShowPopup(false)} />}
    </>
  );
}
