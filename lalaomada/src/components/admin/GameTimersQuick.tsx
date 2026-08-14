import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { toast } from "sonner";
import { Timer, Save, Clock, Hourglass, Swords } from "lucide-react";

type Row = {
  slug: string;
  display_name: string;
  turn_timer_seconds: number;
  tournament_join_timeout_secs: number;
};

type AppTimers = {
  ready_timeout_seconds: number;
  turn_seconds: number;
  game_invite_timeout_minutes: number;
  chess_global_timer_enabled: boolean;
  chess_global_timer_minutes: number;
  fanorona_global_timer_enabled: boolean;
  fanorona_global_timer_minutes: number;
};

const PRESETS = [15, 30, 45, 60, 90, 120, 180];

export default function GameTimersQuick() {
  const [rows, setRows] = useState<Row[]>([]);
  const [app, setApp] = useState<AppTimers | null>(null);
  const [loading, setLoading] = useState(true);
  const [savingSlug, setSavingSlug] = useState<string | null>(null);
  const [savingApp, setSavingApp] = useState(false);

  const load = async () => {
    setLoading(true);
    const [{ data: gc, error: e1 }, { data: s, error: e2 }] = await Promise.all([
      supabase.from("game_configs" as any)
        .select("slug,display_name,turn_timer_seconds,tournament_join_timeout_secs")
        .order("display_name"),
      supabase.from("app_settings" as any).select("*").eq("id", 1).maybeSingle(),
    ]);
    if (e1) toast.error(e1.message);
    if (e2) toast.error(e2.message);
    setRows((gc as any) || []);
    if (s) {
      setApp({
        ready_timeout_seconds: Number((s as any).ready_timeout_seconds) || 60,
        turn_seconds: Number((s as any).turn_seconds) || 30,
        game_invite_timeout_minutes: Number((s as any).game_invite_timeout_minutes) || 2,
        chess_global_timer_enabled: !!(s as any).chess_global_timer_enabled,
        chess_global_timer_minutes: Number((s as any).chess_global_timer_minutes) || 10,
        fanorona_global_timer_enabled: !!(s as any).fanorona_global_timer_enabled,
        fanorona_global_timer_minutes: Number((s as any).fanorona_global_timer_minutes) || 10,
      });
    }
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const setValue = (slug: string, patch: Partial<Row>) =>
    setRows(rs => rs.map(r => r.slug === slug ? { ...r, ...patch } : r));

  const save = async (row: Row) => {
    setSavingSlug(row.slug);
    const v = Math.max(5, Math.min(600, Math.round(row.turn_timer_seconds || 0)));
    const jt = Math.max(60, Math.min(1800, Math.round(row.tournament_join_timeout_secs || 240)));
    const { error } = await supabase.from("game_configs" as any)
      .update({ turn_timer_seconds: v, tournament_join_timeout_secs: jt })
      .eq("slug", row.slug);
    setSavingSlug(null);
    if (error) return toast.error(error.message);
    toast.success(`⏱️ ${row.display_name} : ${v}s / tour • ${Math.round(jt/60)} min salle`);
  };

  const saveApp = async () => {
    if (!app) return;
    setSavingApp(true);
    const { error } = await (supabase.from("app_settings") as any).update({
      ready_timeout_seconds: app.ready_timeout_seconds,
      turn_seconds: app.turn_seconds,
      game_invite_timeout_minutes: app.game_invite_timeout_minutes,
      chess_global_timer_enabled: app.chess_global_timer_enabled,
      chess_global_timer_minutes: app.chess_global_timer_minutes,
      fanorona_global_timer_enabled: app.fanorona_global_timer_enabled,
      fanorona_global_timer_minutes: app.fanorona_global_timer_minutes,
    }).eq("id", 1);
    setSavingApp(false);
    if (error) return toast.error(error.message);
    toast.success("⏱️ Timers globaux enregistrés");
  };

  if (loading) {
    return <div className="rounded-3xl bg-card p-6 text-center text-muted-foreground">Chargement…</div>;
  }

  return (
    <div className="space-y-4">
      {/* ============ GLOBAL ============ */}
      {app && (
        <div className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] border border-border/60 space-y-3">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <Clock className="w-4 h-4 text-primary" />
              <div className="font-bold text-sm">🌐 Timers globaux (toutes les parties)</div>
            </div>
            <button
              onClick={saveApp}
              disabled={savingApp}
              className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-bold flex items-center gap-1 disabled:opacity-50"
            >
              <Save className="w-3.5 h-3.5" /> {savingApp ? "…" : "Enregistrer"}
            </button>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <label className="text-[11px] font-semibold">
              Salle d'attente (min)
              <input type="number" min={1} max={30}
                value={app.game_invite_timeout_minutes}
                onChange={e => setApp({ ...app, game_invite_timeout_minutes: Number(e.target.value) })}
                className="mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono" />
            </label>
            <label className="text-[11px] font-semibold">
              Délai "Prêt" (s)
              <input type="number" min={10} max={600}
                value={app.ready_timeout_seconds}
                onChange={e => setApp({ ...app, ready_timeout_seconds: Number(e.target.value) })}
                className="mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono" />
            </label>
            <label className="text-[11px] font-semibold col-span-2">
              Durée d'un tour par défaut (s)
              <input type="number" min={5} max={600}
                value={app.turn_seconds}
                onChange={e => setApp({ ...app, turn_seconds: Number(e.target.value) })}
                className="mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono" />
            </label>
          </div>

          <div className="pt-3 border-t border-border/60 space-y-2">
            <div className="text-[11px] font-bold uppercase tracking-wide flex items-center gap-1">
              <Hourglass className="w-3.5 h-3.5" /> Minuteur global de partie
            </div>
            <div className="grid grid-cols-2 gap-2">
              <label className="flex items-center gap-2 text-xs">
                <input type="checkbox" checked={app.chess_global_timer_enabled}
                  onChange={e => setApp({ ...app, chess_global_timer_enabled: e.target.checked })} />
                Échecs : actif
              </label>
              <label className="text-[11px] font-semibold">
                Échecs : durée (min)
                <input type="number" min={1} max={180}
                  value={app.chess_global_timer_minutes}
                  onChange={e => setApp({ ...app, chess_global_timer_minutes: Number(e.target.value) })}
                  className="mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono" />
              </label>
              <label className="flex items-center gap-2 text-xs">
                <input type="checkbox" checked={app.fanorona_global_timer_enabled}
                  onChange={e => setApp({ ...app, fanorona_global_timer_enabled: e.target.checked })} />
                Fanorona : actif
              </label>
              <label className="text-[11px] font-semibold">
                Fanorona : durée (min)
                <input type="number" min={1} max={180}
                  value={app.fanorona_global_timer_minutes}
                  onChange={e => setApp({ ...app, fanorona_global_timer_minutes: Number(e.target.value) })}
                  className="mt-1 w-full px-2 py-1.5 rounded-lg bg-background border border-border text-sm text-center font-mono" />
              </label>
            </div>
          </div>
        </div>
      )}

      {/* ============ PER GAME ============ */}
      <div className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] border border-border/60 space-y-3">
        <div className="flex items-center gap-2">
          <Timer className="w-4 h-4 text-primary" />
          <div className="font-bold text-sm">⏱️ Timers par jeu</div>
        </div>
        <p className="text-[11px] text-muted-foreground">
          Durée d'un tour et délai en salle d'attente de tournoi (avant forfait automatique).
        </p>

        <div className="space-y-3">
          {rows.map(r => (
            <div key={r.slug} className="rounded-2xl bg-background/60 border border-border/40 p-3 space-y-2">
              <div className="flex items-center justify-between gap-2">
                <div className="font-semibold text-sm flex items-center gap-1.5">
                  <Swords className="w-3.5 h-3.5 text-primary/70" />{r.display_name}
                </div>
                <button
                  onClick={() => save(r)}
                  disabled={savingSlug === r.slug}
                  className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-bold flex items-center gap-1 disabled:opacity-50"
                >
                  <Save className="w-3.5 h-3.5" /> {savingSlug === r.slug ? "…" : "OK"}
                </button>
              </div>

              <div className="grid grid-cols-2 gap-2">
                <label className="text-[11px] font-semibold">
                  Timer / tour (s)
                  <input type="number" min={5} max={600}
                    value={r.turn_timer_seconds}
                    onChange={e => setValue(r.slug, { turn_timer_seconds: Number(e.target.value) })}
                    className="mt-1 w-full px-2 py-1.5 rounded-lg bg-card border border-border text-sm text-center font-mono" />
                </label>
                <label className="text-[11px] font-semibold">
                  Salle tournoi (min)
                  <input type="number" min={1} max={30}
                    value={Math.round((r.tournament_join_timeout_secs ?? 240) / 60)}
                    onChange={e => setValue(r.slug, { tournament_join_timeout_secs: Number(e.target.value) * 60 })}
                    className="mt-1 w-full px-2 py-1.5 rounded-lg bg-card border border-border text-sm text-center font-mono" />
                </label>
              </div>

              <div className="flex flex-wrap gap-1.5">
                {PRESETS.map(p => (
                  <button key={p}
                    onClick={() => setValue(r.slug, { turn_timer_seconds: p })}
                    className={`px-2.5 py-1 rounded-full text-[11px] font-bold border transition-all ${
                      r.turn_timer_seconds === p
                        ? "bg-primary text-primary-foreground border-primary"
                        : "bg-muted/40 border-border/40 text-muted-foreground hover:bg-muted"
                    }`}
                  >{p}s</button>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
