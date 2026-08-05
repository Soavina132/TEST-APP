import { useState } from "react";
import DOMPurify from "dompurify";
import { HelpCircle, X } from "lucide-react";

export default function HelpPopover({
  trigger,
  title,
  html,
  variant = "link",
}: {
  trigger: string;
  title?: string;
  html?: string | null;
  variant?: "link" | "button";
}) {
  const [open, setOpen] = useState(false);
  if (!html?.trim()) return null;

  const triggerClass =
    variant === "button"
      ? "flex items-center gap-1 px-2.5 py-1.5 rounded-full bg-card border border-primary/25 text-primary font-semibold text-[11px] shadow-sm active:scale-95 transition-transform"
      : "text-xs text-primary font-semibold inline-flex items-center gap-1 underline-offset-2 hover:underline";

  return (
    <>
      <button type="button" onClick={() => setOpen(true)} className={triggerClass}>
        <HelpCircle className="w-3.5 h-3.5" /> {trigger}
      </button>
      {open && (
        <div className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-4" onClick={() => setOpen(false)}>
          <div className="bg-card rounded-3xl max-w-md w-full p-5 shadow-xl max-h-[80vh] overflow-y-auto" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between mb-3">
              <div className="font-bold">{title || trigger}</div>
              <button onClick={() => setOpen(false)} className="p-1.5 rounded-full bg-secondary"><X className="w-4 h-4" /></button>
            </div>
            <div
              className="prose prose-sm dark:prose-invert max-w-none"
              dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }}
            />
          </div>
        </div>
      )}
    </>
  );
}
