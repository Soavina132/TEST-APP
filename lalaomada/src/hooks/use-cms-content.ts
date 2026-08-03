import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

export type CmsFaqItem = { q: string; a: string };
export type CmsFaqCategory = { category: string; items: CmsFaqItem[] };
export type CmsFaqContent = { categories: CmsFaqCategory[] };

export type CmsReferralStep = { step: string; icon: string; label: string; desc: string };
export type CmsReferralContent = {
  hero_subtitle: string;
  how_it_works: CmsReferralStep[];
  conditions: string[];
};

const cache = new Map<string, any>();

/**
 * Charge un bloc CMS depuis `cms_content`.
 * Retombe sur `fallback` si la table est vide ou en erreur.
 */
export function useCmsContent<T = any>(key: string, fallback: T) {
  const [data, setData] = useState<T>(() => (cache.get(key) as T) ?? fallback);
  const [loaded, setLoaded] = useState<boolean>(cache.has(key));

  useEffect(() => {
    let cancelled = false;
    (supabase.from("cms_content" as any).select("content").eq("key", key).maybeSingle() as any)
      .then(({ data: row }: any) => {
        if (cancelled) return;
        const content = row?.content as T | undefined;
        if (content) {
          cache.set(key, content);
          setData(content);
        }
        setLoaded(true);
      });
    return () => { cancelled = true; };
  }, [key]);

  return { data, loaded };
}

/** Invalide le cache (à appeler après une sauvegarde admin). */
export function invalidateCmsCache(key?: string) {
  if (key) cache.delete(key);
  else cache.clear();
}
