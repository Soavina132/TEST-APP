import { useEffect } from "react";
import { useT } from "@/lib/i18n";

/**
 * AutoTranslator — traduction automatique globale de l'UI.
 *
 * Quand la langue est "mg" ou "en", parcourt le DOM et remplace le texte
 * FR affiché par sa traduction via /api/translate. Cache localStorage.
 *
 * - Nœuds texte visibles (skip <script>, <style>, contentEditable, [data-no-translate])
 * - Attributs: placeholder, title, aria-label, alt
 * - Observe les mutations (debounce 200ms)
 */
export default function AutoTranslator() {
  const { lang } = useT();

  useEffect(() => {
    if (typeof window === "undefined") return;
    if (lang === "fr") {
      // Restaurer les textes originaux si disponible
      restoreOriginals();
      return;
    }

    const target = lang;
    const cachePrefix = `t:${target}:`;

    // ── Cache localStorage ────────────────────────────────────────────
    const memCache = new Map<string, string>();
    const loadCache = (src: string): string | null => {
      if (memCache.has(src)) return memCache.get(src)!;
      try {
        const v = localStorage.getItem(cachePrefix + hashKey(src));
        if (v != null) { memCache.set(src, v); return v; }
      } catch { /* quota / private mode */ }
      return null;
    };
    const saveCache = (src: string, tr: string) => {
      memCache.set(src, tr);
      try { localStorage.setItem(cachePrefix + hashKey(src), tr); } catch { /* ignore */ }
    };

    // ── Collecte + traduction ─────────────────────────────────────────
    const pending = new Set<string>();
    const nodeMap = new Map<string, Array<() => void>>();
    let scheduleTimer: ReturnType<typeof setTimeout> | null = null;
    let flushTimer: ReturnType<typeof setTimeout> | null = null;
    let inFlight = false;

    function scheduleScan() {
      if (scheduleTimer) return;
      scheduleTimer = setTimeout(() => {
        scheduleTimer = null;
        scanNode(document.body);
        scheduleFlush();
      }, 60);
    }

    function scheduleFlush() {
      if (flushTimer) return;
      flushTimer = setTimeout(() => {
        flushTimer = null;
        void flush();
      }, 180);
    }

    async function flush() {
      if (inFlight) { scheduleFlush(); return; }
      if (pending.size === 0) return;
      const batch = Array.from(pending).slice(0, 100);
      batch.forEach((s) => pending.delete(s));
      inFlight = true;
      try {
        const res = await fetch("/api/translate", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ lang: target, texts: batch }),
        });
        if (res.ok) {
          const data = (await res.json()) as { translations?: string[] };
          const tr = data.translations || [];
          batch.forEach((src, i) => {
            const val = tr[i] || src;
            saveCache(src, val);
            const jobs = nodeMap.get(src);
            if (jobs) { jobs.forEach((fn) => fn()); nodeMap.delete(src); }
          });
        }
      } catch { /* réseau — on réessaiera au prochain scan */ }
      inFlight = false;
      if (pending.size > 0) scheduleFlush();
    }

    function enqueue(src: string, apply: (translated: string) => void) {
      const cached = loadCache(src);
      if (cached != null) { apply(cached); return; }
      pending.add(src);
      const list = nodeMap.get(src) || [];
      list.push(() => {
        const t = loadCache(src);
        if (t != null) apply(t);
      });
      nodeMap.set(src, list);
    }

    // ── Scan DOM ──────────────────────────────────────────────────────
    const SKIP_TAGS = new Set(["SCRIPT", "STYLE", "NOSCRIPT", "CODE", "PRE", "TEXTAREA"]);
    const ATTR_KEYS = ["placeholder", "title", "aria-label", "alt"] as const;

    function shouldSkip(el: Element): boolean {
      if (SKIP_TAGS.has(el.tagName)) return true;
      if ((el as HTMLElement).isContentEditable) return true;
      if (el.hasAttribute("data-no-translate")) return true;
      const lang = el.getAttribute("lang");
      if (lang && (lang === "mg" || lang === "en")) return true;
      return false;
    }

    function isTranslatable(text: string): boolean {
      const t = text.trim();
      if (t.length < 2) return false;
      // ignorer numérique pur / symboles / heure / date brute
      if (/^[\d\s.,:%+\-·—/()·]+$/.test(t)) return false;
      // doit contenir au moins une lettre alpha
      if (!/[a-zA-ZÀ-ÿ]/.test(t)) return false;
      return true;
    }

    function processTextNode(node: Text) {
      const raw = node.nodeValue || "";
      if (!isTranslatable(raw)) return;
      // sauvegarder l'original + langue source sur le parent
      const parent = node.parentElement;
      if (!parent) return;
      // Utiliser une map WeakMap globale pour retrouver l'original
      let original = originalTextMap.get(node);
      if (original == null) {
        original = raw;
        originalTextMap.set(node, original);
      }
      const trimmed = original.trim();
      enqueue(trimmed, (translated) => {
        // Préserver espaces de bord
        const leading = original!.match(/^\s*/)?.[0] || "";
        const trailing = original!.match(/\s*$/)?.[0] || "";
        const next = leading + translated + trailing;
        if (node.nodeValue !== next) node.nodeValue = next;
      });
    }

    function processAttributes(el: Element) {
      for (const key of ATTR_KEYS) {
        const val = el.getAttribute(key);
        if (!val || !isTranslatable(val)) continue;
        const store = originalAttrMap.get(el) || {};
        if (store[key] == null) { store[key] = val; originalAttrMap.set(el, store); }
        const src = (store[key] as string).trim();
        enqueue(src, (translated) => {
          if (el.getAttribute(key) !== translated) el.setAttribute(key, translated);
        });
      }
    }

    function scanNode(root: Node) {
      const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
        acceptNode(n) {
          if (n.nodeType === Node.ELEMENT_NODE) {
            return shouldSkip(n as Element) ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT;
          }
          return NodeFilter.FILTER_ACCEPT;
        },
      });
      let cur: Node | null = walker.currentNode;
      // Traiter la racine si texte
      if (root.nodeType === Node.TEXT_NODE) processTextNode(root as Text);
      while ((cur = walker.nextNode())) {
        if (cur.nodeType === Node.TEXT_NODE) processTextNode(cur as Text);
        else if (cur.nodeType === Node.ELEMENT_NODE) processAttributes(cur as Element);
      }
    }

    // Premier scan
    scheduleScan();

    // ── MutationObserver ──────────────────────────────────────────────
    const observer = new MutationObserver((mutations) => {
      for (const m of mutations) {
        if (m.type === "characterData") {
          if (m.target.nodeType === Node.TEXT_NODE) processTextNode(m.target as Text);
        } else if (m.type === "childList") {
          m.addedNodes.forEach((n) => {
            if (n.nodeType === Node.ELEMENT_NODE) {
              if (shouldSkip(n as Element)) return;
              scanNode(n);
            } else if (n.nodeType === Node.TEXT_NODE) {
              processTextNode(n as Text);
            }
          });
        } else if (m.type === "attributes" && m.target.nodeType === Node.ELEMENT_NODE) {
          processAttributes(m.target as Element);
        }
      }
      scheduleFlush();
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true,
      characterData: true,
      attributes: true,
      attributeFilter: ["placeholder", "title", "aria-label", "alt"],
    });

    return () => {
      observer.disconnect();
      if (scheduleTimer) clearTimeout(scheduleTimer);
      if (flushTimer) clearTimeout(flushTimer);
    };
  }, [lang]);

  return null;
}

// ── Utilitaires globaux ────────────────────────────────────────────
const originalTextMap = new WeakMap<Text, string>();
const originalAttrMap = new WeakMap<Element, Record<string, string>>();

function restoreOriginals() {
  // On ne peut pas itérer une WeakMap, mais on peut re-scanner et
  // remettre les nodeValue depuis nos maps par sondage : ici on force
  // simplement un rechargement doux via un reload contrôlé.
  // Pour éviter tout effet de bord, on ne fait rien : le prochain rendu
  // React remettra le texte FR sur les composants montés.
}

// Petit hash stable pour ne pas exploser la taille des clés localStorage
function hashKey(s: string): string {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return (h >>> 0).toString(36) + ":" + s.length.toString(36);
}
