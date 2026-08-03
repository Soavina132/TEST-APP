import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Save, Image as ImageIcon, Tag } from "lucide-react";

type GameConfig = {
  slug: string;
  display_name: string;
  turn_timer_seconds: number;
  max_turn_skips: number;
  rules_markdown: string;
  cover_url: string;
  max_online_capacity: number;
  instructions_dismissible: boolean;
  badge: string | null;
  tournament_join_timeout_secs: number;
};

const BADGE_OPTIONS: { value: string | null; label: string; color: string }[] = [
  { value: null,          label: "Aucun badge",  color: "" },
  { value: "new",         label: "🆕 Nouveau",   color: "bg-emerald-500/15 text-emerald-700 border-emerald-500/30" },
  { value: "coming_soon", label: "🔜 Bientôt",  color: "bg-amber-500/15 text-amber-700 border-amber-500/30" },
  { value: "hot",         label: "🔥 Populaire", color: "bg-red-500/15 text-red-700 border-red-500/30" },
];

const BADGE_PILL: Record<string, string> = {
  new:          "bg-emerald-500 text-white",
  coming_soon:  "bg-amber-500 text-white",
  hot:          "bg-red-500 text-white",
};
const BADGE_LABEL: Record<string, string> = {
  new: "🆕 Nouveau", coming_soon: "🔜 Bientôt", hot: "🔥 Populaire",
};

export default function GameConfigsSection() {
  const [rows, setRows] = useState<GameConfig[]>([]);
  const [loading, setLoading] = useState(true);

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase
      .from("game_configs" as any)
      .select("*")
      .order("display_name");
    if (error) toast.error(error.message);
    setRows((data as any) || []);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const update = (slug: string, patch: Partial<GameConfig>) => {
    setRows(rs => rs.map(r => r.slug === slug ? { ...r, ...patch } : r));
  };

  const save = async (row: GameConfig) => {
    const { error } = await supabase.from("game_configs" as any)
      .update({
        max_turn_skips:               row.max_turn_skips,
        rules_markdown:               row.rules_markdown,
        cover_url:                    row.cover_url,
        max_online_capacity:          row.max_online_capacity,
        instructions_dismissible:     row.instructions_dismissible,
        badge:                        row.badge,
      })
      .eq("slug", row.slug);
    if (error) return toast.error(error.message);
    toast.success(`${row.display_name} mis à jour`);
  };

  if (loading) return <div className="p-6 text-center text-muted-foreground">Chargement…</div>;

  return (
    <div className="space-y-4">
      <div className="rounded-2xl bg-card p-4 text-sm text-muted-foreground">
        Configure ici le <b>nombre maximum de tours sautés</b>, le <b>texte des règles</b>, l'<b>image de couverture</b>,
        la <b>capacité affichée</b> et le <b>badge</b>. Les <b>timers</b> sont centralisés dans l'onglet <b>Config → Timers</b>.
      </div>

      {rows.map(r => (
        <div key={r.slug} className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3 border border-border/60">
          <div className="flex items-center justify-between">
            <h3 className="font-extrabold text-lg">
              {r.display_name}{" "}
              <span className="text-xs text-muted-foreground font-mono">({r.slug})</span>
            </h3>
            <button
              onClick={() => save(r)}
              className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-sm font-bold flex items-center gap-1"
            >
              <Save className="w-4 h-4" /> Enregistrer
            </button>
          </div>

          <div className="grid grid-cols-2 gap-3">
            {/* Max skips */}
            <label className="text-xs font-semibold col-span-2">
              Tours sautés max (forfait)
              <input
                type="number" min={1} max={20} value={r.max_turn_skips}
                onChange={e => update(r.slug, { max_turn_skips: Number(e.target.value) })}
                className="mt-1 w-full px-3 py-2 rounded-xl bg-background border border-border"
              />
              <div className="text-[10px] text-muted-foreground mt-1">
                ⏱️ Les timers (tour + salle d'attente tournoi) sont centralisés dans l'onglet <b>Config → Timers</b>.
              </div>
            </label>

            {/* Capacity */}
            <label className="text-xs font-semibold col-span-2">
              Capacité affichée (en ligne max)
              <input
                type="number" min={1} value={r.max_online_capacity}
                onChange={e => update(r.slug, { max_online_capacity: Number(e.target.value) })}
                className="mt-1 w-full px-3 py-2 rounded-xl bg-background border border-border"
              />
            </label>

            {/* Badge selector */}
            <div className="col-span-2">
              <div className="text-xs font-semibold mb-1.5 flex items-center gap-1">
                <Tag className="w-3.5 h-3.5" /> Badge affiché sur la page d'accueil
              </div>
              <div className="flex flex-wrap gap-2">
                {BADGE_OPTIONS.map(opt => {
                  const isActive = r.badge === opt.value;
                  const baseClass = "px-3 py-1 rounded-full border text-xs font-bold transition-all";
                  const activeClass = isActive
                    ? (opt.color || "bg-muted border-border text-foreground") + " ring-2 ring-offset-1 ring-primary/40"
                    : "bg-muted/50 border-border/40 text-muted-foreground hover:bg-muted";
                  return (
                    <button
                      key={String(opt.value)}
                      onClick={() => update(r.slug, { badge: opt.value })}
                      className={`${baseClass} ${activeClass}`}
                    >
                      {opt.label}
                    </button>
                  );
                })}
              </div>
            </div>

            {/* Dismissible */}
            <label className="text-xs font-semibold col-span-2 flex items-center gap-2 mt-1">
              <input
                type="checkbox" checked={r.instructions_dismissible}
                onChange={e => update(r.slug, { instructions_dismissible: e.target.checked })}
              />
              <span>Instructions masquables par l'utilisateur (le bouton ✕ supprime définitivement le bandeau)</span>
            </label>

            {/* Cover URL */}
            <label className="text-xs font-semibold col-span-2">
              URL image de couverture
              <div className="mt-1 flex gap-2">
                <ImageIcon className="w-4 h-4 mt-2.5 text-muted-foreground" />
                <input
                  type="text" value={r.cover_url}
                  onChange={e => update(r.slug, { cover_url: e.target.value })}
                  placeholder="/covers/cover_ludo.png ou https://…"
                  className="flex-1 px-3 py-2 rounded-xl bg-background border border-border"
                />
              </div>
              {r.cover_url && (
                <div className="mt-2 relative w-28 rounded-xl overflow-hidden shadow-md border border-border/40">
                  <img
                    src={r.cover_url} alt=""
                    loading="lazy" decoding="async"
                    className="w-full aspect-[3/4] object-cover"
                  />
                  {r.badge && BADGE_LABEL[r.badge] && (
                    <div className={`absolute top-1.5 right-1.5 text-[9px] font-black px-1.5 py-0.5 rounded-full ${BADGE_PILL[r.badge]}`}>
                      {BADGE_LABEL[r.badge]}
                    </div>
                  )}
                </div>
              )}
            </label>

            {/* Rules */}
            <label className="text-xs font-semibold col-span-2">
              Règles / Instructions (Markdown)
              <textarea
                value={r.rules_markdown}
                onChange={e => update(r.slug, { rules_markdown: e.target.value })}
                rows={5}
                className="mt-1 w-full px-3 py-2 rounded-xl bg-background border border-border font-mono text-xs"
              />
            </label>
          </div>
        </div>
      ))}
    </div>
  );
}
