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
          <div className="bg-card rounded-3xl max-w-md w-full shadow-xl max-h-[85vh] flex flex-col overflow-hidden" onClick={e => e.stopPropagation()}>
            <div className="flex items-center justify-between px-5 py-4 border-b border-white/6 shrink-0">
              <div className="flex items-center gap-2">
                <div className="w-7 h-7 rounded-full bg-primary/15 flex items-center justify-center shrink-0">
                  <HelpCircle className="w-4 h-4 text-primary" />
                </div>
                <div className="font-bold text-[15px]">{title || trigger}</div>
              </div>
              <button onClick={() => setOpen(false)} className="p-1.5 rounded-full bg-secondary shrink-0"><X className="w-4 h-4" /></button>
            </div>
            <div
              className="px-5 py-4 overflow-y-auto"
              dangerouslySetInnerHTML={{ __html: DOMPurify.sanitize(html) }}
            />
          </div>
        </div>
      )}
    </>
  );
}
