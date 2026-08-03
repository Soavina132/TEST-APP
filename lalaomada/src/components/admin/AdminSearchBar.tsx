import { useMemo, useRef, useState, useEffect } from "react";
import { Search, X } from "lucide-react";

export type AdminSearchEntry = {
  id: string;
  tab: string;
  tabLabel: string;
  title: string;
  description?: string;
  keywords?: string;
};

type Props = {
  index: AdminSearchEntry[];
  onGo: (entry: AdminSearchEntry) => void;
};

function norm(s: string) {
  return s
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

export default function AdminSearchBar({ index, onGo }: Props) {
  const [q, setQ] = useState("");
  const [open, setOpen] = useState(false);
  const [activeIdx, setActiveIdx] = useState(0);
  const wrapRef = useRef<HTMLDivElement>(null);

  const results = useMemo(() => {
    const query = norm(q.trim());
    if (!query) return [];
    const tokens = query.split(/\s+/).filter(Boolean);
    return index
      .map((e) => {
        const hay = norm([e.title, e.description ?? "", e.keywords ?? "", e.tabLabel].join(" "));
        const score = tokens.every((t) => hay.includes(t))
          ? tokens.reduce((s, t) => s + (hay.indexOf(t) >= 0 ? 1 : 0), 0)
          : 0;
        return { e, score };
      })
      .filter((x) => x.score > 0)
      .slice(0, 10)
      .map((x) => x.e);
  }, [q, index]);

  useEffect(() => setActiveIdx(0), [q]);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (!wrapRef.current?.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  const go = (entry: AdminSearchEntry) => {
    onGo(entry);
    setOpen(false);
    setQ("");
  };

  return (
    <div ref={wrapRef} className="relative">
      <div className="flex items-center gap-2 px-3 py-2 rounded-2xl bg-card border border-border/60 shadow-sm focus-within:border-primary focus-within:ring-2 focus-within:ring-primary/20 transition-all">
        <Search className="w-4 h-4 text-muted-foreground shrink-0" />
        <input
          value={q}
          onChange={(e) => { setQ(e.target.value); setOpen(true); }}
          onFocus={() => setOpen(true)}
          onKeyDown={(e) => {
            if (e.key === "ArrowDown") { e.preventDefault(); setActiveIdx((i) => Math.min(i + 1, results.length - 1)); }
            else if (e.key === "ArrowUp") { e.preventDefault(); setActiveIdx((i) => Math.max(0, i - 1)); }
            else if (e.key === "Enter" && results[activeIdx]) { e.preventDefault(); go(results[activeIdx]); }
            else if (e.key === "Escape") { setOpen(false); }
          }}
          placeholder="Rechercher un paramètre (timer, parrainage, chat, tournoi…)"
          className="flex-1 bg-transparent outline-none text-sm min-w-0"
        />
        {q && (
          <button onClick={() => { setQ(""); setOpen(false); }} className="text-muted-foreground hover:text-foreground">
            <X className="w-4 h-4" />
          </button>
        )}
      </div>

      {open && q && (
        <div className="absolute z-30 left-0 right-0 mt-1 max-h-[60vh] overflow-y-auto rounded-2xl bg-card border border-border/60 shadow-lg">
          {results.length === 0 ? (
            <div className="px-4 py-6 text-center text-sm text-muted-foreground">
              Aucun paramètre trouvé pour « {q} »
            </div>
          ) : (
            results.map((r, i) => (
              <button
                key={r.id}
                onMouseEnter={() => setActiveIdx(i)}
                onClick={() => go(r)}
                className={`w-full text-left px-3 py-2.5 flex items-center gap-3 border-b border-border/40 last:border-0 transition-colors ${
                  i === activeIdx ? "bg-primary/10" : "hover:bg-accent"
                }`}
              >
                <div className="flex-1 min-w-0">
                  <div className="font-semibold text-sm truncate">{r.title}</div>
                  {r.description && (
                    <div className="text-[11px] text-muted-foreground truncate">{r.description}</div>
                  )}
                </div>
                <span className="shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full bg-primary/10 text-primary uppercase tracking-wide">
                  {r.tabLabel}
                </span>
              </button>
            ))
          )}
        </div>
      )}
    </div>
  );
}
