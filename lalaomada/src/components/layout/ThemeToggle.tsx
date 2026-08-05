import { Moon, Sun } from "lucide-react";
import { useTheme } from "@/hooks/use-theme";

export default function ThemeToggle({ compact = false }: { compact?: boolean }) {
  const { theme, toggle } = useTheme();
  const isDark = theme === "dark";

  if (compact) {
    return (
      <button
        onClick={toggle}
        aria-label={isDark ? "Activer le mode clair" : "Activer le mode sombre"}
        className="p-2 rounded-xl bg-secondary hover:bg-accent transition-colors"
      >
        {isDark ? <Sun className="w-4 h-4" /> : <Moon className="w-4 h-4" />}
      </button>
    );
  }

  return (
    <button
      onClick={toggle}
      className="w-full flex items-center justify-between p-3.5 rounded-2xl bg-card shadow-sm hover:bg-accent/40 transition-colors"
    >
      <div className="flex items-center gap-3">
        <div className={`w-9 h-9 rounded-xl flex items-center justify-center ${isDark ? "bg-amber-100 dark:bg-amber-900/30 text-amber-600" : "bg-indigo-100 dark:bg-indigo-900/30 text-indigo-600"}`}>
          {isDark ? <Sun className="w-5 h-5" /> : <Moon className="w-5 h-5" />}
        </div>
        <div className="text-left">
          <div className="font-semibold text-sm">{isDark ? "Mode sombre" : "Mode clair"}</div>
          <div className="text-xs text-muted-foreground">{isDark ? "Tap pour passer en clair" : "Tap pour passer en sombre"}</div>
        </div>
      </div>
      <div className={`relative w-12 h-6 rounded-full transition-colors duration-200 ${isDark ? "bg-primary" : "bg-muted"}`}>
        <span className={`absolute top-0.5 left-0.5 w-5 h-5 rounded-full bg-white shadow transition-transform duration-200 ${isDark ? "translate-x-6" : "translate-x-0"}`} />
      </div>
    </button>
  );
}
