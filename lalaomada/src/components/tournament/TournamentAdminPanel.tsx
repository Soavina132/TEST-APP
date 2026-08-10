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

const SPLITS: Record<number, [number, number, number, number]> = {
  1: [100, 0, 0, 0],
  2: [70, 30, 0, 0],
  3: [60, 25, 15, 0],   // sum=100 (platform takes 10% of entry fees separately)
  4: [50, 25, 15, 10],  // sum=100
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

  const [f, setF] = useState({
    name: "",
    game_slug: "ludo",
    format: "knockout" as "knockout" | "pools",
    players_per_match: 4,
    max_players: 16,
    mode: "free" as "free" | "paid",
    entry_fee_ar: 0,
    admin_prize_pool_ar: 10000,
    winners_count: 1,
    pool_size: 4,
    qualifiers_per_pool: 2,
    max_concurrent: 8,
    lobby_minutes: 5,
    break_minutes: 3,
    batch_gap_minutes: 0,
    max_match_duration_secs: 600,
    check_in_minutes: 15,
    domino_scoring: "elimination" as "elimination" | "points",
    target_score: 100,
    description: "",
  });
  const set = (k: string, v: any) => setF((p) => ({ ...p, [k]: v }));

  const create = async () => {
    if (!f.name.trim()) return toast.error("Le nom du tournoi est requis.");
    if (f.mode === "free" && f.admin_prize_pool_ar <= 0) {
      const okGo = await confirm({ title: "Tournoi sans récompense ?", description: "Aucune récompense n'est offerte. Les gagnants ne recevront rien." });
      if (!okGo) return;
    }
    if (f.mode === "paid" && f.entry_fee_ar < 100) {
      return toast.error("Frais d'inscription minimum : 100 Ar");
    }
    const [p1, p2, p3, p4] = SPLITS[f.winners_count];
    const ppm = f.game_slug === "domino" ? 2 : Math.max(f.players_per_match, f.game_slug === "ludo" ? 4 : 2);
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
      _max_match_duration_secs: f.max_match_duration_secs,
      _check_in_minutes: f.check_in_minutes,
      _prize_4_pct: p4,
      _domino_scoring: f.domino_scoring,
      _target_score: f.target_score,
    });
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success("🏆 Tournoi créé — inscriptions ouvertes !");
    setF((p) => ({ ...p, name: "", description: "" }));
    setTab("list");
    load();
  };

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
                        {t.check_in_opened_at && !t.started_at && " · check-in ouvert"}
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
                        {Number(t.entry_fee_ar) === 0 && (
                          <button disabled={busy} onClick={() => run("admin_tournament_add_bots", { _tid: t.id, _count: 4 }, "4 bots ajoutés")}
                            className="px-2.5 py-1 rounded-lg bg-card text-[11px] font-bold">+4 bots</button>
                        )}
                        {!t.check_in_opened_at && (
                          <button disabled={busy} onClick={() => run("admin_tournament_open_check_in", { _tid: t.id }, "Check-in ouvert")}
                            className="px-2.5 py-1 rounded-lg bg-amber-100 text-amber-700 dark:bg-amber-950/40 dark:text-amber-300 text-[11px] font-bold">✋ Ouvrir check-in</button>
                        )}
                        {t.check_in_opened_at && (
                          <button disabled={busy} onClick={() => run("admin_tournament_close_check_in", { _tid: t.id }, "Check-in clôturé")}
                            className="px-2.5 py-1 rounded-lg bg-orange-100 text-orange-700 dark:bg-orange-950/40 dark:text-orange-300 text-[11px] font-bold">🔒 Fermer check-in</button>
                        )}
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
              <button key={g.slug} onClick={() => { set("game_slug", g.slug); set("players_per_match", g.slug === "ludo" ? 4 : 2); }}
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

          {/* Domino scoring mode */}
          {f.game_slug === "domino" && (
            <div className="rounded-2xl bg-secondary/30 p-3 space-y-2">
              <div className="text-[11px] font-bold text-muted-foreground uppercase">Mode de jeu Domino</div>
              <div className="flex gap-2">
                <button type="button" onClick={() => set("domino_scoring", "elimination")}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-bold ${f.domino_scoring === "elimination" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                  Élimination
                </button>
                <button type="button" onClick={() => set("domino_scoring", "points")}
                  className={`flex-1 py-2.5 rounded-xl text-sm font-bold ${f.domino_scoring === "points" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                  Par points
                </button>
              </div>
              {f.domino_scoring === "points" && (
                <Num label="Score cible (points)" value={f.target_score} onChange={(v) => set("target_score", v)} min={50} max={500} />
              )}
              <p className="text-[10px] text-muted-foreground leading-relaxed">
                {f.domino_scoring === "elimination"
                  ? "Le perdant de chaque match est éliminé. Le gagnant passe au tour suivant."
                  : `Les joueurs accumulent des points. Le premier à atteindre ${f.target_score} pts remporte le match. Idéal pour les parties longues.`}
              </p>
            </div>
          )}

          {/* ═══ MODE: Gratuit vs Payant ═══ */}
          <div className="rounded-2xl bg-secondary/30 p-3 space-y-3">
            <div className="text-[11px] font-bold text-muted-foreground uppercase">Mode du tournoi</div>
            <div className="grid grid-cols-2 gap-2">
              <button type="button" onClick={() => { set("mode", "free"); set("entry_fee_ar", 0); set("winners_count", 1); set("admin_prize_pool_ar", Math.max(f.admin_prize_pool_ar, 1000)); }}
                className={`py-3 rounded-xl text-sm font-bold ${f.mode === "free" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                🎁 Gratuit
              </button>
              <button type="button" onClick={() => { set("mode", "paid"); set("entry_fee_ar", Math.max(f.entry_fee_ar, 500)); set("admin_prize_pool_ar", 0); set("winners_count", 3); }}
                className={`py-3 rounded-xl text-sm font-bold ${f.mode === "paid" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                💰 Payant
              </button>
            </div>
            {f.mode === "free" ? (
              <div className="space-y-2">
                <p className="text-[10px] text-muted-foreground leading-relaxed">
                  Inscription gratuite pour les joueurs. L'admin offre une récompense unique au gagnant (ou aux 3 premiers).
                  Pas de commission plateforme. Pas de bots.
                </p>
                <Num label="Récompense offerte par l'admin (Ar)" value={f.admin_prize_pool_ar} onChange={(v) => set("admin_prize_pool_ar", v)} min={0} />
                <Field label="Nombre de vainqueurs">
                  <select value={f.winners_count} onChange={(e) => set("winners_count", Number(e.target.value))}
                    className="w-full px-3 py-2 rounded-xl bg-secondary text-sm">
                    <option value={1}>1 vainqueur (100%)</option>
                    <option value={2}>2 vainqueurs (70/30)</option>
                    <option value={3}>3 vainqueurs (60/20/10)</option>
                    <option value={4}>4 vainqueurs (50/25/10/5)</option>
                  </select>
                </Field>
              </div>
            ) : (
              <div className="space-y-2">
                <p className="text-[10px] text-muted-foreground leading-relaxed">
                  Les joueurs paient pour s'inscrire. La cagnotte grandit avec chaque inscription.
                  Commission plateforme : 10% sur les frais collectés. Pas de bots.
                </p>
                <Num label="Frais d'inscription par joueur (Ar)" value={f.entry_fee_ar} onChange={(v) => set("entry_fee_ar", v)} min={100} />
                <Field label="Nombre de vainqueurs">
                  <select value={f.winners_count} onChange={(e) => set("winners_count", Number(e.target.value))}
                    className="w-full px-3 py-2 rounded-xl bg-secondary text-sm">
                    <option value={1}>1 vainqueur (100%)</option>
                    <option value={2}>2 vainqueurs (70/30)</option>
                    <option value={3}>3 vainqueurs (60/20/10) — + match 3e place</option>
                    <option value={4}>4 vainqueurs (50/25/10/5)</option>
                  </select>
                </Field>
              </div>
            )}
          </div>

          <div className="grid grid-cols-2 gap-2">
            <Num label="Joueurs max" value={f.max_players} onChange={(v) => set("max_players", v)} min={2} max={256} />
            <Num label="Matchs simultanés" value={f.max_concurrent} onChange={(v) => set("max_concurrent", v)} min={1} max={f.game_slug === "ludo" ? 8 : 8} />
            {f.game_slug === "ludo" && <p className="text-[10px] text-amber-600 mt-0.5">Ludo : max 8 matchs simultanés</p>}
            <Num label="Salle d'attente (min)" value={f.lobby_minutes} onChange={(v) => set("lobby_minutes", v)} min={1} max={10} />
          </div>

          {/* Timing & lots */}
          <div className="rounded-2xl bg-secondary/30 p-3 space-y-2">
            <div className="text-[11px] font-bold text-muted-foreground uppercase">Timing des phases</div>
            <div className="grid grid-cols-2 gap-2">
              <Num label="Pause entre phases (min)" value={f.break_minutes} onChange={(v) => set("break_minutes", v)} min={0} max={60} />
              <Num label="Délai entre lots (min)" value={f.batch_gap_minutes} onChange={(v) => set("batch_gap_minutes", v)} min={0} max={60} />
              <Num label="Durée max match (sec)" value={f.max_match_duration_secs} onChange={(v) => set("max_match_duration_secs", v)} min={60} max={3600} />
              <Num label="Check-in avant début (min)" value={f.check_in_minutes} onChange={(v) => set("check_in_minutes", v)} min={1} max={60} />
            </div>
            <p className="text-[10px] text-muted-foreground leading-relaxed">
              {f.batch_gap_minutes > 0
                ? `Les ${f.max_concurrent} matchs simultanés max sont lancés par lots. Entre chaque lot, le moteur attend ${f.batch_gap_minutes} min avant de lancer le suivant.`
                : "Délai entre lots = 0 → lancement au fil de l'eau (dès qu'une place se libère). Mettez > 0 pour lancer par lots espacés."}
            </p>
            <p className="text-[10px] text-muted-foreground leading-relaxed">
              ⏱ Durée max match : un match qui dépasse cette limite est résolu automatiquement. Check-in : temps accordé aux joueurs pour confirmer leur présence avant le début.
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
