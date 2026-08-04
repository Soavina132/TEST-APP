import { useEffect, useRef, useCallback } from "react";
import DOMPurify from "dompurify";

interface RichTextEditorProps {
  value: string;
  onChange: (html: string) => void;
  placeholder?: string;
  minHeight?: string;
}

/**
 * Lightweight contentEditable rich-text editor (no external deps).
 * Supports basic formatting via the legacy document.execCommand API,
 * which still works in all current browsers and avoids pulling in
 * the entire ProseMirror / Tiptap dependency tree.
 *
 * SECURITY: All HTML passed to the editor is sanitized with DOMPurify
 * before being set as innerHTML, preventing XSS attacks.
 */
export default function RichTextEditor({
  value,
  onChange,
  placeholder = "Écrivez ici…",
  minHeight = "160px",
}: RichTextEditorProps) {
  const ref = useRef<HTMLDivElement | null>(null);

  // Sanitize HTML before injecting into the DOM
  const sanitize = useCallback((html: string): string => {
    return DOMPurify.sanitize(html || "", {
      ALLOWED_TAGS: ["b", "i", "u", "strong", "em", "br", "ul", "ol", "li", "a", "h2", "h3", "p", "span"],
      ALLOWED_ATTR: ["href", "target", "rel"],
    });
  }, []);

  // Keep DOM in sync when `value` changes externally (without losing caret on each keystroke).
  useEffect(() => {
    if (ref.current) {
      const sanitized = sanitize(value);
      if (ref.current.innerHTML !== sanitized) {
        ref.current.innerHTML = sanitized;
      }
    }
  }, [value, sanitize]);

  const exec = (cmd: string, arg?: string) => {
    document.execCommand(cmd, false, arg);
    if (ref.current) {
      // Sanitize the result of execCommand too, to strip any injected content
      const raw = ref.current.innerHTML;
      const clean = sanitize(raw);
      if (ref.current.innerHTML !== clean) {
        ref.current.innerHTML = clean;
      }
      onChange(clean);
    }
  };

  const addLink = () => {
    const url = prompt("URL du lien :", "https://");
    if (url) exec("createLink", url);
  };

  // Sanitize on paste
  const handlePaste = (e: React.ClipboardEvent<HTMLDivElement>) => {
    e.preventDefault();
    const text = e.clipboardData.getData("text/html") || e.clipboardData.getData("text/plain");
    document.execCommand("insertHTML", false, sanitize(text));
    if (ref.current) onChange(sanitize(ref.current.innerHTML));
  };

  const Btn = ({ cmd, label, arg, title }: { cmd?: string; label: string; arg?: string; title: string }) => (
    <button
      type="button"
      title={title}
      onClick={() => (cmd ? exec(cmd, arg) : addLink())}
      className="px-2 py-1 rounded text-sm font-semibold hover:bg-accent text-foreground"
    >
      {label}
    </button>
  );

  return (
    <div className="rounded-lg border border-border bg-background">
      <div className="flex flex-wrap gap-1 p-1.5 border-b border-border bg-muted/40">
        <Btn cmd="bold" label="B" title="Gras" />
        <Btn cmd="italic" label="I" title="Italique" />
        <Btn cmd="underline" label="U" title="Souligné" />
        <Btn cmd="formatBlock" arg="h2" label="H2" title="Titre" />
        <Btn cmd="formatBlock" arg="h3" label="H3" title="Sous-titre" />
        <Btn cmd="insertUnorderedList" label="• Liste" title="Liste à puces" />
        <Btn cmd="insertOrderedList" label="1. Liste" title="Liste numérotée" />
        <Btn label="🔗 Lien" title="Insérer un lien" />
        <Btn cmd="removeFormat" label="✕ Format" title="Supprimer le format" />
      </div>
      <div
        ref={ref}
        contentEditable
        suppressContentEditableWarning
        data-placeholder={placeholder}
        onInput={(e) => onChange(sanitize((e.currentTarget as HTMLDivElement).innerHTML))}
        onPaste={handlePaste}
        className="prose prose-sm max-w-none p-3 focus:outline-none [&[data-placeholder]:empty:before]:content-[attr(data-placeholder)] [&[data-placeholder]:empty:before]:text-muted-foreground"
        style={{ minHeight }}
      />
    </div>
  );
}
