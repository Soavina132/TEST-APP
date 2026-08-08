import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useTheme } from "@/hooks/use-theme";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import {
  ArrowLeft, User as UserIcon, Mail, Moon, Sun, Check,
} from "lucide-react";

export const Route = createFileRoute("/_authenticated/parametres")({
  component: ParametresPage,
  head: () => ({ meta: [
    { title: "Parametres — Lalao MADA" },
    { name: "description", content: "Parametres du compte : nom, email et apparence." },
  ] }),
});

/* Section wrapper */
function Section({ icon: Icon, title, children }: {
  icon: any; title: string; children: React.ReactNode;
}) {
  return (
    <div className="rounded-2xl bg-card border border-border/40 overflow-hidden">
      <div className="flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30">
        <Icon className="w-4 h-4 text-primary" />
        <span className="font-bold text-sm">{title}</span>
      </div>
      <div className="p-4">{children}</div>
    </div>
  );
}

/* Input field */
function Field({ label, value, onChange, type = "text", placeholder, disabled }: {
  label: string; value: string; onChange: (v: string) => void;
  type?: string; placeholder?: string; disabled?: boolean;
}) {
  return (
    <div>
      <label className="text-xs font-semibold text-muted-foreground mb-1 block">{label}</label>
      <input
        type={type}
        value={value}
        onChange={e => onChange(e.target.value)}
        placeholder={placeholder}
        disabled={disabled}
        className="w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm font-medium outline-none focus:ring-2 ring-primary/40 disabled:opacity-50"
      />
    </div>
  );
}

/* Toggle switch */
function Toggle({ checked, onChange, label, sublabel }: {
  checked: boolean; onChange: () => void; label: string; sublabel: string;
}) {
  return (
    <button onClick={onChange}
      className="w-full flex items-center justify-between p-3.5 rounded-2xl bg-card border border-border/40 hover:bg-accent/30 transition-colors">
      <div className="flex items-center gap-3">
        <div className={"w-9 h-9 rounded-xl flex items-center justify-center " + (checked ? "bg-amber-100 text-amber-600" : "bg-indigo-100 text-indigo-600")}>
          {checked ? <Moon className="w-5 h-5" /> : <Sun className="w-5 h-5" />}
        </div>
        <div className="text-left">
          <div className="font-semibold text-sm">{label}</div>
          <div className="text-xs text-muted-foreground">{sublabel}</div>
        </div>
      </div>
      <div className={"relative w-12 h-6 rounded-full transition-colors " + (checked ? "bg-primary" : "bg-muted")}>
        <span className={"absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform " + (checked ? "translate-x-6" : "translate-x-0")} />
      </div>
    </button>
  );
}

/* Parametres Page — infos générales du profil + apparence
   (le volet sécurité — téléphone/mot de passe — vit dans /securite) */
function ParametresPage() {
  const { user, profile, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const { theme, toggle } = useTheme();
  const isDark = theme === "dark";

  const [pseudo, setPseudo] = useState(profile?.pseudo || "");
  const [email, setEmail] = useState(profile?.email || user?.email || "");
  const [savingName, setSavingName] = useState(false);
  const [savingEmail, setSavingEmail] = useState(false);

  useEffect(() => {
    if (profile) {
      setPseudo(profile.pseudo || "");
      setEmail(profile.email || user?.email || "");
    }
  }, [profile?.id, profile?.pseudo, profile?.email]);

  const savePseudo = async () => {
    const trimmed = pseudo.trim();
    if (!trimmed || trimmed.length < 2) return toast.error("Le nom doit faire au moins 2 caracteres");
    setSavingName(true);
    try {
      const { error } = await supabase.from("profiles").update({ pseudo: trimmed }).eq("id", user!.id);
      if (error) throw error;
      await refreshProfile();
      toast.success("Nom mis a jour");
    } catch (e: any) {
      toast.error(e?.message || "Erreur lors de la mise a jour");
    } finally {
      setSavingName(false);
    }
  };

  const saveEmail = async () => {
    const trimmed = email.trim();
    if (!trimmed || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(trimmed)) return toast.error("Email invalide");
    if (trimmed === (profile?.email || user?.email)) return;
    setSavingEmail(true);
    try {
      const { error } = await supabase.auth.updateUser({ email: trimmed });
      if (error) throw error;
      await supabase.from("profiles").update({ email: trimmed }).eq("id", user!.id);
      await refreshProfile();
      toast.success("Email mis a jour — un e-mail de confirmation a ete envoye");
    } catch (e: any) {
      toast.error(e?.message || "Erreur lors de la mise a jour");
    } finally {
      setSavingEmail(false);
    }
  };

  const nameChanged = pseudo.trim() !== (profile?.pseudo || "") && pseudo.trim().length >= 2;
  const emailChanged = email.trim() !== (profile?.email || user?.email || "");

  return (
    <main className="min-h-screen max-w-md mx-auto px-4 pt-16 pb-28 space-y-4">
      <div className="flex items-center gap-2 mb-2">
        <button onClick={() => navigate({ to: "/profile", search: {} })}
          className="w-9 h-9 rounded-full bg-secondary/60 flex items-center justify-center active:scale-90 transition">
          <ArrowLeft className="w-5 h-5" />
        </button>
        <h1 className="text-xl font-extrabold">Parametres</h1>
      </div>

      {/* Nom */}
      <Section icon={UserIcon} title="Modifier le nom">
        <div className="space-y-3">
          <Field label="Nom affiche" value={pseudo} onChange={setPseudo} placeholder="Votre nom" />
          <button onClick={savePseudo} disabled={!nameChanged || savingName}
            className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5">
            {savingName ? "Enregistrement…" : (<><Check className="w-4 h-4" /> Enregistrer</>)}
          </button>
        </div>
      </Section>

      {/* Email */}
      <Section icon={Mail} title="Modifier l'email">
        <div className="space-y-3">
          <Field label="Adresse e-mail" value={email} onChange={setEmail} type="email" placeholder="votre@email.com" />
          {emailChanged && (
            <p className="text-[11px] text-amber-600 dark:text-amber-400">
              Un e-mail de confirmation sera envoye a la nouvelle adresse.
            </p>
          )}
          <button onClick={saveEmail} disabled={!emailChanged || savingEmail}
            className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-1.5">
            {savingEmail ? "Enregistrement…" : (<><Check className="w-4 h-4" /> Enregistrer</>)}
          </button>
        </div>
      </Section>

      {/* Theme */}
      <Section icon={isDark ? Moon : Sun} title="Apparence">
        <Toggle
          checked={isDark}
          onChange={toggle}
          label={isDark ? "Mode sombre" : "Mode clair"}
          sublabel={isDark ? "Tap pour passer en mode clair" : "Tap pour passer en mode sombre"}
        />
      </Section>
    </main>
  );
}
