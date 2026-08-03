import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Save, Plus, Trash2, ChevronDown, ChevronUp } from "lucide-react";
import {
  invalidateCmsCache,
  type CmsFaqCategory,
  type CmsFaqContent,
  type CmsReferralContent,
  type CmsReferralStep,
} from "@/hooks/use-cms-content";

type Section = "faq" | "referral";

export default function CmsEditor() {
  const [section, setSection] = useState<Section>("faq");
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-4">
      <div className="flex items-center justify-between gap-2">
        <div>
          <div className="font-bold">📝 Contenus éditables</div>
          <div className="text-xs text-muted-foreground">
            Modifiez les textes de la FAQ et de la page Parrainage. Les changements sont visibles immédiatement.
          </div>
        </div>
      </div>
      <div className="flex gap-2">
        <button
          onClick={() => setSection("faq")}
          className={`flex-1 py-2 rounded-full text-sm font-semibold ${section === "faq" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}
        >
          ❓ FAQ
        </button>
        <button
          onClick={() => setSection("referral")}
          className={`flex-1 py-2 rounded-full text-sm font-semibold ${section === "referral" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}
        >
          🎁 Parrainage
        </button>
      </div>
      {section === "faq" ? <FaqEditor /> : <ReferralEditor />}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// FAQ
// ────────────────────────────────────────────────────────────────
function FaqEditor() {
  const [content, setContent] = useState<CmsFaqContent | null>(null);
  const [meta, setMeta] = useState<{ updated_at?: string } | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => { load(); }, []);
  async function load() {
    const { data } = await (supabase.from("cms_content" as any).select("content, updated_at").eq("key", "faq").maybeSingle() as any);
    const c = (data?.content as CmsFaqContent) || { categories: [] };
    setContent(c);
    setMeta({ updated_at: data?.updated_at });
  }
  async function save() {
    if (!content) return;
    setSaving(true);
    const { error } = await supabase.rpc("admin_update_cms_content" as any, { _key: "faq", _content: content as any } as any);
    setSaving(false);
    if (error) return toast.error(error.message);
    invalidateCmsCache("faq");
    toast.success("FAQ enregistrée");
    load();
  }
  function updateCat(idx: number, next: Partial<CmsFaqCategory>) {
    if (!content) return;
    const cats = [...content.categories];
    cats[idx] = { ...cats[idx], ...next };
    setContent({ categories: cats });
  }
  function moveCat(idx: number, dir: -1 | 1) {
    if (!content) return;
    const cats = [...content.categories];
    const j = idx + dir;
    if (j < 0 || j >= cats.length) return;
    [cats[idx], cats[j]] = [cats[j], cats[idx]];
    setContent({ categories: cats });
  }
  function removeCat(idx: number) {
    if (!content) return;
    setContent({ categories: content.categories.filter((_, i) => i !== idx) });
  }
  function addCat() {
    if (!content) return;
    setContent({ categories: [...content.categories, { category: "📌 Nouvelle catégorie", items: [] }] });
  }

  if (!content) return <div className="text-sm text-muted-foreground py-4">Chargement…</div>;

  return (
    <div className="space-y-3">
      {meta?.updated_at && (
        <div className="text-[11px] text-muted-foreground">
          Dernière modification : {new Date(meta.updated_at).toLocaleString("fr-FR")}
        </div>
      )}
      <div className="text-[11px] text-muted-foreground bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-900 rounded-lg px-3 py-2">
        💡 Astuce : dans une réponse, écrivez <code className="font-mono">__REFERRAL_SHORT__</code> pour insérer automatiquement le résumé du parrainage.
      </div>
      {content.categories.map((cat, i) => (
        <FaqCategoryCard
          key={i}
          cat={cat}
          onChange={next => updateCat(i, next)}
          onRemove={() => removeCat(i)}
          onMoveUp={() => moveCat(i, -1)}
          onMoveDown={() => moveCat(i, 1)}
        />
      ))}
      <button onClick={addCat} className="w-full py-2 rounded-full bg-secondary hover:bg-accent font-semibold text-sm flex items-center justify-center gap-2">
        <Plus className="w-4 h-4" /> Ajouter une catégorie
      </button>
      <button onClick={save} disabled={saving} className="w-full py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 disabled:opacity-50">
        <Save className="w-4 h-4" /> {saving ? "Enregistrement…" : "Enregistrer la FAQ"}
      </button>
    </div>
  );
}

function FaqCategoryCard({
  cat, onChange, onRemove, onMoveUp, onMoveDown,
}: {
  cat: CmsFaqCategory;
  onChange: (next: Partial<CmsFaqCategory>) => void;
  onRemove: () => void;
  onMoveUp: () => void;
  onMoveDown: () => void;
}) {
  const [open, setOpen] = useState(false);
  function updateItem(idx: number, next: Partial<{ q: string; a: string }>) {
    const items = [...cat.items];
    items[idx] = { ...items[idx], ...next };
    onChange({ items });
  }
  function removeItem(idx: number) {
    onChange({ items: cat.items.filter((_, i) => i !== idx) });
  }
  function addItem() {
    onChange({ items: [...cat.items, { q: "Nouvelle question ?", a: "Nouvelle réponse." }] });
  }
  return (
    <div className="rounded-2xl border border-border/50 overflow-hidden">
      <div className="flex items-center gap-2 p-3 bg-secondary/40">
        <input
          value={cat.category}
          onChange={e => onChange({ category: e.target.value })}
          className="flex-1 px-3 py-1.5 rounded-lg bg-card outline-none text-sm font-semibold"
        />
        <button onClick={onMoveUp} className="p-1.5 rounded hover:bg-accent" title="Monter"><ChevronUp className="w-4 h-4" /></button>
        <button onClick={onMoveDown} className="p-1.5 rounded hover:bg-accent" title="Descendre"><ChevronDown className="w-4 h-4" /></button>
        <button onClick={() => setOpen(!open)} className="px-2 py-1 rounded bg-card text-xs font-semibold">
          {open ? "Replier" : `Ouvrir (${cat.items.length})`}
        </button>
        <button onClick={onRemove} className="p-1.5 rounded bg-destructive/10 text-destructive hover:bg-destructive/20" title="Supprimer">
          <Trash2 className="w-4 h-4" />
        </button>
      </div>
      {open && (
        <div className="p-3 space-y-2">
          {cat.items.map((it, i) => (
            <div key={i} className="rounded-xl border border-border/40 p-2 space-y-1.5">
              <div className="flex gap-2">
                <input
                  value={it.q}
                  onChange={e => updateItem(i, { q: e.target.value })}
                  placeholder="Question"
                  className="flex-1 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm font-semibold"
                />
                <button onClick={() => removeItem(i)} className="p-1.5 rounded bg-destructive/10 text-destructive hover:bg-destructive/20">
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
              <textarea
                value={it.a}
                onChange={e => updateItem(i, { a: e.target.value })}
                placeholder="Réponse"
                rows={3}
                className="w-full px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm"
              />
            </div>
          ))}
          <button onClick={addItem} className="w-full py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold text-xs flex items-center justify-center gap-1.5">
            <Plus className="w-3.5 h-3.5" /> Ajouter une question
          </button>
        </div>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────────────────
// Parrainage
// ────────────────────────────────────────────────────────────────
function ReferralEditor() {
  const [content, setContent] = useState<CmsReferralContent | null>(null);
  const [meta, setMeta] = useState<{ updated_at?: string } | null>(null);
  const [saving, setSaving] = useState(false);

  useEffect(() => { load(); }, []);
  async function load() {
    const { data } = await (supabase.from("cms_content" as any).select("content, updated_at").eq("key", "referral").maybeSingle() as any);
    const c = (data?.content as CmsReferralContent) || { hero_subtitle: "", how_it_works: [], conditions: [] };
    setContent(c);
    setMeta({ updated_at: data?.updated_at });
  }
  async function save() {
    if (!content) return;
    setSaving(true);
    const { error } = await supabase.rpc("admin_update_cms_content" as any, { _key: "referral", _content: content as any } as any);
    setSaving(false);
    if (error) return toast.error(error.message);
    invalidateCmsCache("referral");
    toast.success("Page Parrainage enregistrée");
    load();
  }
  function updateStep(idx: number, next: Partial<CmsReferralStep>) {
    if (!content) return;
    const steps = [...content.how_it_works];
    steps[idx] = { ...steps[idx], ...next };
    setContent({ ...content, how_it_works: steps });
  }
  function addStep() {
    if (!content) return;
    setContent({
      ...content,
      how_it_works: [...content.how_it_works, { step: String(content.how_it_works.length + 1), icon: "✨", label: "Nouvelle étape", desc: "" }],
    });
  }
  function removeStep(idx: number) {
    if (!content) return;
    setContent({ ...content, how_it_works: content.how_it_works.filter((_, i) => i !== idx) });
  }

  if (!content) return <div className="text-sm text-muted-foreground py-4">Chargement…</div>;

  return (
    <div className="space-y-4">
      {meta?.updated_at && (
        <div className="text-[11px] text-muted-foreground">
          Dernière modification : {new Date(meta.updated_at).toLocaleString("fr-FR")}
        </div>
      )}
      <div className="text-[11px] text-muted-foreground bg-amber-50 dark:bg-amber-950/20 border border-amber-200 dark:border-amber-900 rounded-lg px-3 py-2">
        💡 Utilisez <code className="font-mono">{"{pct}"}</code> pour le pourcentage de commission et <code className="font-mono">{"{max}"}</code> pour le nombre max de parties. Les vraies valeurs sont remplacées automatiquement.
      </div>

      {/* Hero */}
      <div>
        <label className="text-sm font-semibold block mb-1">Sous-titre du bandeau</label>
        <textarea
          value={content.hero_subtitle}
          onChange={e => setContent({ ...content, hero_subtitle: e.target.value })}
          rows={2}
          className="w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm"
          placeholder="Gagnez {pct}% de chaque mise…"
        />
      </div>

      {/* How it works */}
      <div className="space-y-2">
        <label className="text-sm font-semibold">Comment ça marche ?</label>
        {content.how_it_works.map((s, i) => (
          <div key={i} className="rounded-xl border border-border/40 p-2 space-y-1.5">
            <div className="flex gap-2">
              <input value={s.step} onChange={e => updateStep(i, { step: e.target.value })} placeholder="#" className="w-12 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm text-center font-bold" />
              <input value={s.icon} onChange={e => updateStep(i, { icon: e.target.value })} placeholder="🎯" className="w-14 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm text-center" />
              <input value={s.label} onChange={e => updateStep(i, { label: e.target.value })} placeholder="Titre" className="flex-1 px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm font-semibold" />
              <button onClick={() => removeStep(i)} className="p-1.5 rounded bg-destructive/10 text-destructive hover:bg-destructive/20">
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
            <textarea value={s.desc} onChange={e => updateStep(i, { desc: e.target.value })} placeholder="Description" rows={2} className="w-full px-2 py-1.5 rounded-lg bg-secondary outline-none text-sm" />
          </div>
        ))}
        <button onClick={addStep} className="w-full py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold text-xs flex items-center justify-center gap-1.5">
          <Plus className="w-3.5 h-3.5" /> Ajouter une étape
        </button>
      </div>

      {/* Conditions */}
      <div className="space-y-1">
        <label className="text-sm font-semibold">Conditions du programme (une par ligne)</label>
        <textarea
          value={content.conditions.join("\n")}
          onChange={e => setContent({ ...content, conditions: e.target.value.split("\n").map(s => s.trim()).filter(Boolean) })}
          rows={7}
          className="w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm"
          placeholder={"Aucun bonus…\nVous recevez {pct}%…"}
        />
      </div>

      <button onClick={save} disabled={saving} className="w-full py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 disabled:opacity-50">
        <Save className="w-4 h-4" /> {saving ? "Enregistrement…" : "Enregistrer la page Parrainage"}
      </button>
    </div>
  );
}
