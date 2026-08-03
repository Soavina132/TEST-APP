import { useEffect, useRef, useState, type ReactNode } from "react";
import { ChevronDown } from "lucide-react";

type Props = {
  id?: string;
  title: string;
  icon?: ReactNode;
  description?: string;
  defaultOpen?: boolean;
  accent?: "primary" | "emerald" | "amber" | "sky" | "rose" | "violet";
  children: ReactNode;
};

const ACCENTS: Record<NonNullable<Props["accent"]>, string> = {
  primary: "from-primary/15 to-primary/5 text-primary",
  emerald: "from-emerald-500/15 to-emerald-500/5 text-emerald-600",
  amber:   "from-amber-500/15 to-amber-500/5 text-amber-600",
  sky:     "from-sky-500/15 to-sky-500/5 text-sky-600",
  rose:    "from-rose-500/15 to-rose-500/5 text-rose-600",
  violet:  "from-violet-500/15 to-violet-500/5 text-violet-600",
};

export default function AdminSection({
  id, title, icon, description, defaultOpen = false, accent = "primary", children,
}: Props) {
  const [open, setOpen] = useState(defaultOpen);
  const [flash, setFlash] = useState(false);
  const ref = useRef<HTMLElement>(null);

  useEffect(() => {
    if (!id) return;
    const handler = (e: Event) => {
      const detail = (e as CustomEvent<{ id: string }>).detail;
      if (detail?.id !== id) return;
      setOpen(true);
      setFlash(true);
      setTimeout(() => {
        ref.current?.scrollIntoView({ behavior: "smooth", block: "start" });
      }, 60);
      setTimeout(() => setFlash(false), 1600);
    };
    window.addEventListener("admin-section-open", handler);
    return () => window.removeEventListener("admin-section-open", handler);
  }, [id]);

  return (
    <section
      ref={ref}
      id={id ? `admin-section-${id}` : undefined}
      className={`rounded-3xl bg-card border shadow-[var(--shadow-soft)] overflow-hidden transition-all ${
        flash ? "border-primary ring-2 ring-primary/30" : "border-border/60"
      }`}
    >
      <button
        type="button"
        onClick={() => setOpen(o => !o)}
        className={`w-full flex items-center gap-3 px-4 py-3 bg-gradient-to-r ${ACCENTS[accent]} hover:brightness-105 transition-all`}
      >
        {icon && <span className="shrink-0">{icon}</span>}
        <div className="flex-1 text-left min-w-0">
          <div className="font-extrabold text-sm truncate">{title}</div>
          {description && (
            <div className="text-[11px] opacity-70 truncate">{description}</div>
          )}
        </div>
        <ChevronDown
          className={`w-4 h-4 shrink-0 transition-transform ${open ? "rotate-180" : ""}`}
        />
      </button>
      {open && (
        <div className="p-3 sm:p-4 space-y-4 bg-background/40">
          {children}
        </div>
      )}
    </section>
  );
}
