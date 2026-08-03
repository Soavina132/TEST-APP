import { useT, Lang } from "@/lib/i18n";
import { Languages } from "lucide-react";
import { useState } from "react";

const LANGS: { code: Lang; label: string; flag: string }[] = [
  { code: "fr", label: "Français", flag: "🇫🇷" },
  { code: "mg", label: "Malagasy", flag: "🇲🇬" },
  { code: "en", label: "English", flag: "🇬🇧" },
];

export default function LanguageSwitcher() {
  const { lang, setLang } = useT();
  const [open, setOpen] = useState(false);
  const cur = LANGS.find(l => l.code === lang) || LANGS[0];
  return (
    <div className="relative">
      <button onClick={() => setOpen(o => !o)} className="flex items-center gap-1 p-2 rounded-full hover:bg-accent text-sm" aria-label="Langue">
        <Languages className="w-4 h-4" /> <span className="hidden sm:inline">{cur.flag}</span>
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
          <div className="absolute right-0 mt-2 z-50 w-44 bg-card border border-border rounded-2xl shadow-xl overflow-hidden">
            {LANGS.map(l => (
              <button key={l.code} onClick={() => {
                setLang(l.code);
                setOpen(false);
                // Recharger pour appliquer proprement la traduction (auto-translate)
                // et restaurer les textes FR sans DOM résiduel.
                if (l.code !== lang) {
                  setTimeout(() => { try { window.location.reload(); } catch { /* ignore */ } }, 50);
                }
              }}
                className={`w-full text-left px-3 py-2 text-sm flex items-center gap-2 hover:bg-accent ${lang === l.code ? "bg-accent font-bold" : ""}`}>
                <span>{l.flag}</span> {l.label}
              </button>
            ))}
          </div>
        </>
      )}
    </div>
  );
}
