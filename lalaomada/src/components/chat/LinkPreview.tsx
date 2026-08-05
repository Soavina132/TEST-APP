import { useEffect, useRef, useState } from "react";
import { ExternalLink } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";

interface Meta { title?: string; description?: string; image?: string; siteName?: string; url: string; }

// In-memory cache: url → meta (or null = failed)
const cache = new Map<string, Meta | null>();

function extractUrl(text: string): string | null {
  const m = text.match(/https?:\/\/[^\s"'<>]+/);
  return m ? m[0] : null;
}

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY;

function usePreview(url: string) {
  const [meta, setMeta] = useState<Meta | null | "loading">("loading");
  useEffect(() => {
    if (!url) { setMeta(null); return; }
    if (cache.has(url)) { setMeta(cache.get(url)!); return; }
    const ctrl = new AbortController();
    (async () => {
      const { data: sess } = await supabase.auth.getSession();
      const token = sess.session?.access_token;
      if (!token) { cache.set(url, null); setMeta(null); return; }
      try {
        const r = await fetch(
          `${SUPABASE_URL}/functions/v1/link-preview?url=${encodeURIComponent(url)}`,
          {
            signal: ctrl.signal,
            headers: { Authorization: `Bearer ${token}`, apikey: SUPABASE_ANON_KEY },
          }
        );
        const d: Meta | null = r.ok ? await r.json() : null;
        cache.set(url, d?.title ? d : null);
        setMeta(d?.title ? d : null);
      } catch {
        cache.set(url, null); setMeta(null);
      }
    })();
    return () => ctrl.abort();
  }, [url]);
  return meta;
}

/** Renders a rich preview card for the first URL found in `text`. */
export function LinkPreviewCard({ text, className = "" }: { text: string; className?: string }) {
  const url = extractUrl(text);
  const meta = usePreview(url || "");

  if (!url || meta === "loading" || !meta) return null;

  return (
    <a
      href={url}
      target="_blank"
      rel="noopener noreferrer"
      className={`mt-2 flex gap-3 rounded-xl overflow-hidden border border-white/10 bg-black/20 hover:bg-black/30 transition-colors group no-underline ${className}`}
      onClick={e => e.stopPropagation()}
    >
      {meta.image && (
        <img
          src={meta.image}
          alt=""
          className="w-20 h-20 object-cover shrink-0"
          onError={e => { (e.currentTarget as HTMLImageElement).style.display = "none"; }}
        />
      )}
      <div className="flex flex-col justify-center py-2 pr-3 min-w-0 gap-0.5">
        {meta.siteName && (
          <span className="text-[10px] font-semibold text-primary/70 uppercase tracking-wide truncate">
            {meta.siteName}
          </span>
        )}
        {meta.title && (
          <span className="text-xs font-semibold text-foreground truncate leading-snug">
            {meta.title}
          </span>
        )}
        {meta.description && (
          <span className="text-[10px] text-muted-foreground line-clamp-2 leading-snug">
            {meta.description}
          </span>
        )}
        <span className="flex items-center gap-1 text-[10px] text-muted-foreground/60 mt-0.5 truncate">
          <ExternalLink className="w-2.5 h-2.5 shrink-0" />
          {new URL(url).hostname.replace(/^www\./, "")}
        </span>
      </div>
    </a>
  );
}

/** Inline linkify — replaces URLs in text with <a> tags + appends a preview card below. */
export function LinkifyWithPreview({ text, className = "" }: { text: string; className?: string }) {
  const parts = text.split(/(https?:\/\/[^\s]+)/g);
  return (
    <span className={className}>
      {parts.map((p, i) =>
        /^https?:\/\//.test(p)
          ? <a key={i} href={p} target="_blank" rel="noopener noreferrer"
              className="underline text-primary break-all">{p}</a>
          : <span key={i}>{p}</span>
      )}
    </span>
  );
}
