import { toast } from "sonner";

/**
 * Wrap a Supabase save call to show a clear loading → success / error toast.
 *
 * Usage:
 *   const ok = await saveWithToast(
 *     () => supabase.rpc("admin_update_settings", { ... }),
 *     { label: "Paramètres" }
 *   );
 *   if (!ok) return; // stop the flow on failure
 */
export async function saveWithToast<T extends { error: { message: string } | null }>(
  run: () => Promise<T>,
  opts: { label: string; onSuccess?: (r: T) => void } = { label: "Modifications" },
): Promise<boolean> {
  const id = toast.loading(`💾 Enregistrement — ${opts.label}…`);
  try {
    const res = await run();
    if (res.error) {
      toast.error(`❌ Impossible d'enregistrer — ${opts.label}`, {
        id,
        description: res.error.message,
        duration: 8000,
      });
      return false;
    }
    toast.success(`✅ ${opts.label} enregistré${opts.label.endsWith("s") ? "s" : ""}`, {
      id,
      description: "Les modifications sont actives immédiatement.",
      duration: 3500,
    });
    opts.onSuccess?.(res);
    return true;
  } catch (e: any) {
    toast.error(`❌ Erreur inattendue — ${opts.label}`, {
      id,
      description: e?.message ?? String(e),
      duration: 8000,
    });
    return false;
  }
}
