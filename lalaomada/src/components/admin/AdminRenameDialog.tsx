import { useState } from "react";
import { useT } from "@/lib/i18n";

interface Props {
  open: boolean;
  defaultName: string;
  onCancel: () => void;
  onConfirm: (name: string) => void;
}
// Used by admin before creating/joining a game — forces a custom display name.
export default function AdminRenameDialog({ open, defaultName, onCancel, onConfirm }: Props) {
  const { t } = useT();
  const [name, setName] = useState(defaultName);
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4" onClick={onCancel}>
      <div className="bg-card rounded-3xl p-6 max-w-md w-full space-y-4" onClick={e => e.stopPropagation()}>
        <h2 className="text-xl font-extrabold">👑 {t("game_name_title")}</h2>
        <p className="text-sm text-muted-foreground">
          {t("game_name_desc")}
        </p>
        <input
          autoFocus
          value={name}
          onChange={e => setName(e.target.value)}
          maxLength={24}
          placeholder={t("player_pseudo_placeholder")}
          className="w-full px-4 py-3 rounded-2xl bg-secondary outline-none text-base"
        />
        <div className="flex gap-2 justify-end">
          <button onClick={onCancel} className="px-4 py-2 rounded-full bg-secondary font-semibold">{t("cancel_btn")}</button>
          <button
            onClick={() => name.trim().length >= 2 && onConfirm(name.trim())}
            disabled={name.trim().length < 2}
            className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold disabled:opacity-50"
          >
            Continuer
          </button>
        </div>
      </div>
    </div>
  );
}
