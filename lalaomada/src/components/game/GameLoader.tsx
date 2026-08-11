/**
 * Styled loading screen for game pages.
 * Shows a spinner + localized text, consistent with the app design.
 */
import { useT } from "@/lib/i18n";

export function GameLoader({ retryFn }: { retryFn?: () => void }) {
  const { t } = useT();
  return (
    <main className="min-h-[60vh] flex flex-col items-center justify-center gap-4 px-4">
      <div className="relative w-16 h-16">
        <div className="absolute inset-0 rounded-full border-4 border-muted" />
        <div className="absolute inset-0 rounded-full border-4 border-primary border-t-transparent animate-spin" />
      </div>
      <p className="text-sm text-muted-foreground font-medium">{t("loading")}</p>
      {retryFn && (
        <button
          onClick={retryFn}
          className="px-5 py-2.5 rounded-full bg-primary text-primary-foreground text-sm font-semibold active:scale-95 transition"
        >
          Réessayer
        </button>
      )}
    </main>
  );
}
