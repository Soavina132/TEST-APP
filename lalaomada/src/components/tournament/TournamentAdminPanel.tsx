import { useCallback, useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useConfirm } from "@/components/ConfirmDialog";
import { toast } from "sonner";
import { Link } from "@tanstack/react-router";
import { Trophy, Loader2, ExternalLink } from "lucide-react";

const GAMES = [
  { slug: "ludo", emoji: "🎲", label: "Ludo" },
  { slug: "domino", emoji: "🁣", label: "Domino" },
];

const SPLITS: Record<number, [number, number, number]> = {
  1: [100, 0, 0],
  2: [60, 40, 0],
  3: [50, 30, 20],
};

export default function TournamentAdminPanel() {
  const confirm = useConfirm();
  const [tab, setTab] = useState<"list" | "create" | "sim">("list");
  const [rows, setRows] = useState<any[]>([]);
  const [counts, setCounts] = useState<Record<string, number>>({});
  const [busy, setBusy] = useState(false);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const { data } = await (supabase.from("tournaments" as any) as any)
      .select("*").order("created_at", { ascending: false }).limit(40);
    const list = (data as any[]) || [];
    setRows(list);
    if (list.length) {
      const { data: ents } = await (supabase.from("tournament_entrants" as any) as any)
        .select("tournament_id").in("tournament_id", list.map((r) => r.id));
      const c: Record<string, number> = {};
      ((ents as any[]) || []).forEach((e) => { c[e.tournament_id] = (c[e.tournament_id] || 0) + 1; });
      setCounts(c);
    }
    setLoading(false);
  }, []);

  useEffect(() => { load(); }, [load]);

  const run = async (fn: string, args: any, ok: string) => {
    setBusy(true);
    const { error } = await (supabase.rpc as any)(fn, args);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(ok);
    load();
  };

  // ── formulaire ──
  const [f, setF] = useState({
    name: "",
    game_slug: "ludo",
    format: "knockout" as "knockout" | "pools",
    players_per_match: 2,
    max_players: 16,
    entry_fee_ar: 0,
    admin_prize_pool_ar: 0,
    winners_count: 1,
    pool_size: 4,
    qualifiers_per_pool: 2,
    max_concurrent: 8,
    lobby_minutes: 5,
    break_minutes: 3,
    batch_gap_minutes: 0,
    description: "",
  });
  const set = (k: string, v: any) => setF((p) => ({ ...p, [k]: v }));

  const create = async () => {
    if (!f.name.trim()) return toast.error("Le nom du tournoi est requis.");
    if (f.entry_fee_ar <= 0 && f.admin_prize_pool_ar <= 0) {
      const okGo = await confirm({ title: "Tournoi sans cagnotte ?", description: "Ni frais d'inscription ni cagnotte offerte : les gagnants ne recevront rien." });
      if (!okGo) return;
    }
    const [p1, p2, p3] = SPLITS[f.winners_count];
    const ppm = f.game_slug === "domino" ? 2 : f.players_per_match;
    setBusy(true);
    const { error } = await (supabase.rpc as any)("admin_tournament_create", {
      _name: f.name.trim(),
      _game_slug: f.game_slug,
      _format: f.format,
      _players_per_match: ppm,
      _max_players: f.max_players,
      _entry_fee_ar: f.entry_fee_ar,
      _admin_prize_pool_ar: f.admin_prize_pool_ar,
      _winners_count: f.winners_count,
      _p1: p1, _p2: p2, _p3: p3,
      _pool_size: f.pool_size,
      _qualifiers_per_pool: f.qualifiers_per_pool,
      _max_concurrent: f.max_concurrent,
      _lobby_minutes: f.lobby_minutes,
      _description: f.description || null,
      _registration_closes_at: null,
      _starts_at: null,
      _break_seconds: f.break_minutes * 60,
      _batch_gap_seconds: f.batch_gap_minutes * 60,
    });
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success("🏆 Tournoi créé — inscriptions ouvertes !");
    setF((p) => ({ ...p, name: "", description: "" }));
    setTab("list");
    load();
  };

  // ── auto-simulation ──
  const [sim, setSim] = useState({ game_slug: "domino", format: "pools" as "pools" | "knockout", players: 16, pool_size: 4, qualifiers_per_pool: 2 });
  const [simReport, setSimReport] = useState<any>(null);

  const runSim = async () => {
    setBusy(true);
    setSimReport(null);
    const { data, error } = await (supabase.rpc as any)("admin_tournament_simulate_new", {
      _game_slug: sim.game_slug,
      _format: sim.format,
      _players: sim.players,
      _players_per_match: sim.game_slug === "ludo" ? 4 : 2,
      _pool_size: sim.pool_size,
      _qualifiers_per_pool: sim.qualifiers_per_pool,
    });
    setBusy(false);
    if (error) return toast.error(error.message);
    setSimReport(data);
    if (data?.ok) toast.success("✅ Simulation terminée : poules, classement et bracket cohérents");
    else toast.error("⚠️ Anomalies détectées, voir le rapport");
    load();
  };

  const simulateExisting = async (id: string) => {
    setBusy(true);
    const { data, error } = await (supabase.rpc as any)("admin_tournament_simulate", { _tid: id, _max_steps: 300 });
    setBusy(false);
    if (error) return toast.error(error.message);
    setSimReport(data);
    setTab("sim");
    load();
  };

  return (
    <div className="space-y-4">
      <div className="flex gap-2">
        <button onClick={() => setTab("list")}
          className={`px-4 py-2 rounded-full text-sm font-semibold ${tab === "list" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
          📋 Tournois ({rows.length})
        </button>
        <button onClick={() => setTab("create")}
          className={`px-4 py-2 rounded-full text-sm font-semibold ${tab === "create" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
          ➕ Créer
        </button>
        <button onClick={() => setTab("sim")}
          className={`px-4 py-2 rounded-full text-sm font-semibold ${tab === "sim" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
          🧪 Simulation
        </button>
      </div>

      {tab === "list" && (
        loading ? (
          <div className="flex justify-center py-10"><Loader2 className="w-5 h-5 animate-spin text-muted-foreground" /></div>
        ) : rows.length === 0 ? (
          <div className="text-sm text-muted-foreground text-center py-8">Aucun tournoi.</div>
        ) : (
          <div className="space-y-2">
            {rows.map((t) => {
              const g = GAMES.find((x) => x.slug === t.game_slug);
              const n = counts[t.id] ?? 0;
              return (
                <div key={t.id} className="rounded-2xl bg-secondary/50 p-3 space-y-2">
                  <div className="flex items-start gap-2">
                    <span className="text-xl">{g?.emoji ?? "🏆"}</span>
                    <div className="min-w-0 flex-1">
                      <div className="font-bold text-sm truncate">
                        {t.is_simulation && <span className="mr-1 text-[10px] px-1.5 py-0.5 rounded bg-primary/15 text-primary align-middle">SIMU</span>}
                        {t.name}
                      </div>
                      <div className="text-[11px] text-muted-foreground">
                        {g?.label} · {t.format === "pools" ? "Poules" : "Élimination"} · {n}/{t.max_players} joueurs · {t.status}
                        {t.status === "running" && ` · étape : ${t.stage}`}
                      </div>
                    </div>
                    <Link to="/tournaments/$id" params={{ id: t.id }} className="text-primary shrink-0">
                      <ExternalLink className="w-4 h-4" />
                    </Link>
                  </div>
                  <div className="flex flex-wrap gap-1.5">
                    {t.is_simulation && !["finished", "cancelled"].includes(t.status) && (
                      <button disabled={busy} onClick={() => simulateExisting(t.id)}
                        className="px-2.5 py-1 rounded-lg bg-primary/15 text-primary text-[11px] font-bold">🧪 Simuler jusqu'à la fin</button>
                    )}
                    {t.status === "open" && (
                      <>
                        <button disabled={busy} onClick={() => run("admin_tournament_add_bots", { _tid: t.id, _count: 4 }, "4 bots ajoutés")}
                          className="px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold">+4 bots</button>
                        <button disabled={busy} onClick={() => run("admin_tournament_start", { _tid: t.id }, "Tournoi démarré")}
                          className="px-2.5 py-1 rounded-lg bg-primary text-primary-foreground text-[11px] font-bold">▶ Démarrer</button>
                      </>
                    )}
                    {t.status === "running" && (
                      <>
                        <button disabled={busy} onClick={() => run("admin_tournament_next_stage", { _tid: t.id }, "Étape suivante")}
                          className="px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold">⏭ Étape suivante</button>
                        <button disabled={busy} onClick={() => run("admin_tournament_set_status", { _tid: t.id, _status: "paused" }, "En pause")}
                          className="px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold">⏸ Pause</button>
                        <button disabled={busy} onClick={() => run("admin_tournament_set_auto", { _tid: t.id, _auto: !t.auto_advance }, "Mode mis à jour")}
                          className="px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold">{t.auto_advance ? "⚡ Auto ON" : "✋ Auto OFF"}</button>
                      </>
                    )}
                    {t.status === "paused" && (
                      <button disabled={busy} onClick={() => run("admin_tournament_set_status", { _tid: t.id, _status: "running" }, "Repris")}
                        className="px-2.5 py-1 rounded-lg bg-primary text-primary-foreground text-[11px] font-bold">▶ Reprendre</button>
                    )}
                    {!["finished", "cancelled"].includes(t.status) && (
                      <button disabled={busy}
                        onClick={async () => {
                          if (!(await confirm({ title: "Annuler ce tournoi ?", description: "Les inscriptions payantes seront remboursées.", destructive: true }))) return;
                          run("admin_tournament_cancel", { _tid: t.id, _reason: null }, "Tournoi annulé");
                        }}
                        className="px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold text-destructive">✕ Annuler</button>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )
      )}

      {tab === "sim" && (
        <div className="space-y-3">
          <div className="rounded-2xl bg-secondary/50 p-3 text-[12px] text-muted-foreground">
            Lance un tournoi complet avec des bots et des résultats aléatoires (aucune vraie partie, aucun gain réel)
            puis vérifie automatiquement les poules, le classement et le bracket jusqu'au champion.
          </div>

          <div className="flex gap-2">
            {GAMES.map((g) => (
              <button key={g.slug} onClick={() => setSim((p) => ({ ...p, game_slug: g.slug }))}
                className={`flex-1 py-3 rounded-2xl text-sm font-bold ${sim.game_slug === g.slug ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                {g.emoji} {g.label}
              </button>
            ))}
          </div>

          <div className="flex gap-2">
            {(["pools", "knockout"] as const).map((fm) => (
              <button key={fm} onClick={() => setSim((p) => ({ ...p, format: fm }))}
                className={`flex-1 py-2.5 rounded-2xl text-sm font-bold ${sim.format === fm ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                {fm === "pools" ? "Poules + finales" : "Élimination directe"}
              </button>
            ))}
          </div>

          <div className="flex flex-wrap gap-2">
            {[8, 11, 16, 24, 32].map((n) => (
              <button key={n} onClick={() => setSim((p) => ({ ...p, players: n }))}
                className={`px-3 py-2 rounded-xl text-[12px] font-bold ${sim.players === n ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                {n} bots
              </button>
            ))}
          </div>

          <button disabled={busy} onClick={runSim}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-2">
            {busy ? <Loader2 className="w-4 h-4 animate-spin" /> : <Trophy className="w-4 h-4" />}
            Lancer l'auto-simulation
          </button>

          {simReport && (
            <div className="rounded-2xl bg-secondary/50 p-3 space-y-2 text-[12px]">
              <div className={`font-bold ${simReport.ok ? "text-primary" : "text-destructive"}`}>
                {simReport.ok ? "✅ Tournoi cohérent de bout en bout" : "⚠️ Anomalies détectées"}
              </div>
              <div className="text-muted-foreground">
                {simReport.entrants} joueurs · {simReport.matches} matchs · {simReport.pools} poule(s) · {simReport.rounds} tour(s) · statut : {simReport.status}
              </div>
              {simReport.champion && <div>🏆 Champion : <b>{simReport.champion}</b></div>}
              {Array.isArray(simReport.podium) && simReport.podium.length > 0 && (
                <div className="flex flex-wrap gap-1.5">
                  {simReport.podium.map((p: any) => (
                    <span key={p.rank} className="px-2 py-0.5 rounded-lg bg-card text-[11px] font-semibold">
                      {p.rank}. {p.name}
                    </span>
                  ))}
                </div>
              )}
              {Array.isArray(simReport.issues) && simReport.issues.length > 0 && (
                <ul className="list-disc pl-4 text-destructive space-y-0.5">
                  {simReport.issues.map((it: string, i: number) => <li key={i}>{it}</li>)}
                </ul>
              )}
              {Array.isArray(simReport.standings) && simReport.standings.map((p: any) => (
                <div key={p.pool} className="rounded-xl bg-card p-2">
                  <div className="font-bold mb-1">{p.pool}</div>
                  {(p.rows || []).map((r: any, i: number) => (
                    <div key={i} className="flex justify-between text-[11px] text-muted-foreground">
                      <span>{r.qualifie ? "✅" : "•"} {r.name}</span>
                      <span>{r.pts} pts · {r.v}V / {r.j}J</span>
                    </div>
                  ))}
                </div>
              ))}
            </div>
          )}
        </div>
      )}


      {tab === "create" && (
        <div className="space-y-3">
          <div className="flex gap-2">
            {GAMES.map((g) => (
              <button key={g.slug} onClick={() => set("game_slug", g.slug)}
                className={`flex-1 py-3 rounded-2xl text-sm font-bold ${f.game_slug === g.slug ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                {g.emoji} {g.label}
              </button>
            ))}
          </div>

          <Field label="Nom du tournoi">
            <input value={f.name} onChange={(e) => set("name", e.target.value)}
              placeholder="ex : Coupe Ludo — Août 2026"
              className="w-full px-3 py-2 rounded-xl bg-secondary text-sm" />
          </Field>

          <Field label="Description (optionnel)">
            <textarea value={f.description} onChange={(e) => set("description", e.target.value)} rows={2}
              className="w-full px-3 py-2 rounded-xl bg-secondary text-sm" />
          </Field>

          <div className="grid grid-cols-2 gap-2">
            <Field label="Format">
              <select value={f.format} onChange={(e) => set("format", e.target.value)}
                className="w-full px-3 py-2 rounded-xl bg-secondary text-sm">
                <option value="knockout">Élimination directe</option>
                <option value="pools">Poules + phase finale</option>
              </select>
            </Field>
            <Field label="Joueurs par match">
              <select value={f.players_per_match} disabled={f.game_slug === "domino"}
                onChange={(e) => set("players_per_match", Number(e.target.value))}
                className="w-full px-3 py-2 rounded-xl bg-secondary text-sm disabled:opacity-60">
                <option value={2}>1 vs 1</option>
                <option value={3}>3 joueurs</option>
                <option value={4}>4 joueurs</option>
              </select>
            </Field>
          </div>

          {f.format === "pools" && (
            <div className="grid grid-cols-2 gap-2">
              <Num label="Taille des poules" value={f.pool_size} onChange={(v) => set("pool_size", v)} min={2} max={6} />
              <Num label="Qualifiés / poule" value={f.qualifiers_per_pool} onChange={(v) => set("qualifiers_per_pool", v)} min={1} max={3} />
            </div>
          )}

          <div className="grid grid-cols-2 gap-2">
            <Num label="Joueurs max" value={f.max_players} onChange={(v) => set("max_players", v)} min={2} max={256} />
            <Num label="Matchs simultanés" value={f.max_concurrent} onChange={(v) => set("max_concurrent", v)} min={1} max={8} />
            <Num label="Frais d'inscription (Ar)" value={f.entry_fee_ar} onChange={(v) => set("entry_fee_ar", v)} min={0} />
            <Num label="Cagnotte offerte (Ar)" value={f.admin_prize_pool_ar} onChange={(v) => set("admin_prize_pool_ar", v)} min={0} />
            <Num label="Salle d'attente (min)" value={f.lobby_minutes} onChange={(v) => set("lobby_minutes", v)} min={1} max={60} />
            <Field label="Nombre de vainqueurs">
              <select value={f.winners_count} onChange={(e) => set("winners_count", Number(e.target.value))}
                className="w-full px-3 py-2 rounded-xl bg-secondary text-sm">
                <option value={1}>1 vainqueur (100%)</option>
                <option value={2}>2 vainqueurs (60/40)</option>
                <option value={3}>3 vainqueurs (50/30/20)</option>
              </select>
            </Field>
          </div>

          {/* ── Timing & lots ── */}
          <div className="rounded-2xl bg-secondary/30 p-3 space-y-2">
            <div className="text-[11px] font-bold text-muted-foreground uppercase">Timing des phases</div>
            <div className="grid grid-cols-2 gap-2">
              <Num label="Pause entre phases (min)" value={f.break_minutes} onChange={(v) => set("break_minutes", v)} min={0} max={60} />
              <Num label="Délai entre lots de matchs (min)" value={f.batch_gap_minutes} onChange={(v) => set("batch_gap_minutes", v)} min={0} max={60} />
            </div>
            <p className="text-[10px] text-muted-foreground leading-relaxed">
              {f.batch_gap_minutes > 0
                ? `Les ${f.max_concurrent} matchs simultanés max sont lancés par lots. Entre chaque lot, le moteur attend ${f.batch_gap_minutes} min avant de lancer le suivant.`
                : "Délai entre lots = 0 → lancement au fil de l'eau (dès qu'une place se libère). Mettez > 0 pour lancer par lots espacés."}
            </p>
          </div>

          <button onClick={create} disabled={busy}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-60 flex items-center justify-center gap-2">
            <Trophy className="w-4 h-4" /> Créer le tournoi
          </button>
        </div>
      )}
    </div>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="block space-y-1">
      <span className="text-[11px] font-bold text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}

function Num({ label, value, onChange, min, max }: { label: string; value: number; onChange: (v: number) => void; min?: number; max?: number }) {
  return (
    <Field label={label}>
      <input type="number" value={value} min={min} max={max}
        onChange={(e) => onChange(Number(e.target.value))}
        className="w-full px-3 py-2 rounded-xl bg-secondary text-sm" />
    </Field>
  );
}
