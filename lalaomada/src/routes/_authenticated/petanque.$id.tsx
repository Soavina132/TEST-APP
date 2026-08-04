import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useMemo, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { LogOut, Timer, Coins, Target } from "lucide-react";
import GameWaitingRoom from "@/components/GameWaitingRoom";
import GameEndScreen from "@/components/GameEndScreen";
import { useConfirm } from "@/components/ConfirmDialog";
import petanqueCover from "@/assets/games/petanque.asset.json";

export const Route = createFileRoute("/_authenticated/petanque/$id")({
  component: PetanquePage,
  head: () => ({
    meta: [
      { title: "Pétanque — Lalao MADA" },
      { name: "robots", content: "noindex" },
    ],
  }),
});

type Game = {
  id: string;
  creator_id: string | null;
  mode: string;
  stake: number;
  pot: number;
  status: "open" | "playing" | "finished" | "cancelled";
  is_private: boolean;
  room_code: string | null;
  target_points: number;
  score_team0: number;
  score_team1: number;
  current_round: number;
  cochonnet_x: number;
  cochonnet_y: number;
  current_player_id: string | null;
  turn_deadline: string | null;
  winner_team: number | null;
  boules_per_player: number;
  created_at: string;
};

type Participant = {
  id: string;
  user_id: string | null;
  team: number;
  seat: number;
  boules_left: number;
  ready: boolean;
  is_bot: boolean;
};

type Boule = {
  id: string;
  round: number;
  team: number;
  player_id: string | null;
  play_order: number;
  x: number;
  y: number;
  dead: boolean;
  distance: number;
};

// ────────────────────────────────────────────────────────────────────────────
// Isometric terrain — perspective transform so the flat court reads as 3D
// ────────────────────────────────────────────────────────────────────────────
// Terrain normalisé côté serveur: x ∈ [-1, 1], y ∈ [-0.45, 0.45]
// On mappe vers un rectangle 100% × 100% du conteneur ; l'iso vient du parent
// via `transform: perspective(800px) rotateX(52deg)`.
function toScreen(x: number, y: number) {
  return {
    left: `${((x + 1) / 2) * 100}%`,
    top: `${((y + 0.45) / 0.9) * 100}%`,
  };
}

function Boule3D({ team, size = 30, muted = false }: { team: 0 | 1; size?: number; muted?: boolean }) {
  const base = team === 0 ? "#d1d5db" : "#f59e0b";
  const dark = team === 0 ? "#6b7280" : "#b45309";
  return (
    <div
      style={{
        width: size,
        height: size,
        borderRadius: "50%",
        background: `radial-gradient(circle at 30% 25%, #fff 0%, ${base} 45%, ${dark} 100%)`,
        boxShadow: `0 4px 6px rgba(0,0,0,0.45), inset -2px -3px 5px rgba(0,0,0,0.35), inset 2px 2px 4px rgba(255,255,255,0.5)`,
        opacity: muted ? 0.35 : 1,
        transform: "translateZ(0)",
      }}
    />
  );
}

function Cochonnet({ size = 14 }: { size?: number }) {
  return (
    <div
      style={{
        width: size, height: size, borderRadius: "50%",
        background: "radial-gradient(circle at 30% 25%, #fca5a5 0%, #dc2626 55%, #7f1d1d 100%)",
        boxShadow: "0 2px 3px rgba(0,0,0,0.5), inset -1px -1px 2px rgba(0,0,0,0.35)",
      }}
    />
  );
}

// ────────────────────────────────────────────────────────────────────────────
function PetanquePage() {
  const { id } = Route.useParams();
  const navigate = useNavigate();
  const { profile, refreshProfile } = useAuth();
  const confirm = useConfirm();
  const [game, setGame] = useState<Game | null>(null);
  const [parts, setParts] = useState<Participant[]>([]);
  const [boules, setBoules] = useState<Boule[]>([]);
  const [now, setNow] = useState(Date.now());
  const [angle, setAngle] = useState(0);   // radians
  const [power, setPower] = useState(0.6);
  const [spin, setSpin] = useState(0);
  const [lob, setLob] = useState(0.35);
  const [throwing, setThrowing] = useState(false);
  const [flying, setFlying] = useState<null | { fromX: number; fromY: number; toX: number; toY: number; lob: number; team: 0 | 1 }>(null);

  const load = useCallback(async () => {
    const [{ data: g }, { data: ps }, { data: bs }] = await Promise.all([
      supabase.from("petanque_games" as any).select("*").eq("id", id).maybeSingle(),
      supabase.from("petanque_participants" as any).select("*").eq("game_id", id).order("seat"),
      supabase.from("petanque_boules" as any).select("*").eq("game_id", id).order("play_order"),
    ]);
    setGame((g as any) || null);
    setParts(((ps as any[]) || []) as Participant[]);
    setBoules(((bs as any[]) || []) as Boule[]);
  }, [id, profile?.id]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    const ch = supabase.channel(`petanque:${id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "petanque_games", filter: `id=eq.${id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "petanque_participants", filter: `game_id=eq.${id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "petanque_boules", filter: `game_id=eq.${id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 500); return () => clearInterval(t); }, []);

  // Bot polling — quand current_player_id est NULL en cours de partie, le premier humain déclenche le tour du bot
  const firstHumanId = parts.find(p => !p.is_bot && p.user_id)?.user_id;
  useEffect(() => {
    if (!game || game.status !== "playing" || game.current_player_id !== null) return;
    if (profile?.id !== firstHumanId) return;
    const t = setTimeout(async () => {
      try { await supabase.rpc("petanque_bot_step" as any, { _game_id: id } as any); }
      catch { /* ignore */ }
    }, 1400);
    return () => clearTimeout(t);
  }, [game?.status, game?.current_player_id, game?.current_round, boules.length, profile?.id, firstHumanId, id]);

  const me = useMemo(() => parts.find(p => p.user_id === profile?.id), [parts, profile?.id]);
  const opp = useMemo(() => parts.find(p => p.user_id !== profile?.id), [parts, profile?.id]);
  const myTurn = !!(game && me && game.current_player_id === me.user_id && game.status === "playing");
  const remainingMs = game?.turn_deadline ? Math.max(0, new Date(game.turn_deadline).getTime() - now) : null;

  const throwBoule = async () => {
    if (!myTurn || throwing || !game || !me) return;
    setThrowing(true);
    const fromX = -0.9;
    const fromY = me.team === 0 ? -0.25 : 0.25;
    try {
      const { data, error } = await supabase.rpc("petanque_throw" as any, {
        _game_id: id, _angle: angle, _power: power, _spin: spin, _lob: lob,
      } as any);
      if (error) throw error;
      const res: any = data;
      // Animation locale du vol jusqu'à la position finale annoncée
      setFlying({ fromX, fromY, toX: res.final_x, toY: res.final_y, lob, team: me.team as 0 | 1 });
      setTimeout(() => setFlying(null), 850);
    } catch (e: any) {
      toast.error(e.message || "Impossible de lancer");
    } finally {
      setThrowing(false);
    }
  };

  const onQuit = async () => {
    if (!game) return;
    const inGame = game.status === "playing";
    const ok = await confirm({
      title: inGame ? "Abandonner la partie ?" : "Quitter la salle ?",
      description: inGame
        ? `Vous serez déclaré perdant et votre mise${Number(game.stake) > 0 ? " sera perdue" : ""}.`
        : "Vous serez remboursé.",
      confirmLabel: inGame ? "Abandonner" : "Quitter",
      destructive: inGame,
    });
    if (!ok) return;
    try {
      const { error } = await supabase.rpc("petanque_leave" as any, { _game_id: id } as any);
      if (error) throw error;
      refreshProfile();
      navigate({ to: "/jeux" });
    } catch (e: any) { toast.error(e.message || "Erreur"); }
  };

  const onToggleReady = async (ready: boolean) => {
    try {
      const { error } = await supabase.rpc("petanque_set_ready" as any, { _game_id: id, _ready: ready } as any);
      if (error) throw error;
    } catch (e: any) { toast.error(e.message || "Erreur"); }
  };

  const addBot = async () => {
    try {
      const { error } = await supabase.rpc("petanque_add_bot" as any, { _game_id: id } as any);
      if (error) throw error;
      toast.success("Bot ajouté");
    } catch (e: any) { toast.error(e.message || "Erreur"); }
  };

  if (!game) return <main className="p-6 text-center">Chargement…</main>;

  // ── SALLE D'ATTENTE ─────────────────────────────────────────────────────
  if (game.status === "open") {
    const partsForRoom = parts.map(p => ({
      id: p.id, user_id: p.user_id || `bot-${p.id}`,
      display_name: p.is_bot ? "Bot" : undefined, ready: p.ready,
    }));
    return (
      <main className="max-w-3xl mx-auto p-3 pb-24 space-y-3">
        <GameWaitingRoom
          gameLabel="Pétanque"
          parts={partsForRoom}
          maxPlayers={2}
          stake={game.stake}
          pot={game.pot}
          roomCode={game.room_code}
          meUserId={profile?.id}
          isParticipant={!!me}
          onQuit={onQuit}
          onToggleReady={me ? onToggleReady : undefined}
          shareSlug="petanque"
          createdAt={game.created_at}
          slug="petanque"
        />
        {me && parts.length < 2 && (game.stake === 0 || (profile as any)?.is_admin) && (
          <button onClick={addBot}
            className="w-full py-3 rounded-full bg-secondary font-semibold text-sm">
            🤖 Ajouter un bot
          </button>
        )}
      </main>
    );
  }

  // ── FIN DE PARTIE ───────────────────────────────────────────────────────
  if (game.status === "finished" || game.status === "cancelled") {
    const winnerPart = parts.find(p => p.team === game.winner_team);
    const endParts = parts.map(p => ({
      user_id: p.user_id || `bot-${p.id}`,
      display_name: p.is_bot ? "Bot" : (p.user_id === profile?.id ? (profile as any)?.pseudo || "Vous" : "Adversaire"),
    }));
    return (
      <GameEndScreen
        slug="petanque"
        meUserId={profile?.id}
        winnerId={winnerPart ? (winnerPart.user_id || `bot-${winnerPart.id}`) : null}
        participants={endParts}
        stake={Number(game.stake)}
        pot={Number(game.pot)}
        extra={<div className="text-sm text-muted-foreground text-center">Score final&nbsp;: <b className="text-foreground">{game.score_team0} — {game.score_team1}</b></div>}
      />
    );
  }


  // ── PLATEAU DE JEU (isométrique) ────────────────────────────────────────
  const roundBoules = boules.filter(b => b.round === game.current_round);
  return (
    <main className="max-w-3xl mx-auto min-h-[100dvh] flex flex-col">
      {/* Header : score + timer + mise */}
      <div className="px-3 pt-2 pb-1 flex items-center gap-2 text-xs">
        <div className="flex-1 flex items-center gap-2">
          <div className="flex-1 flex items-center justify-between rounded-xl px-3 py-1.5 bg-card border">
            <div className="flex items-center gap-1.5">
              <div className="w-3 h-3 rounded-full" style={{ background: "#d1d5db" }} />
              <span className="font-bold text-base">{game.score_team0}</span>
            </div>
            <span className="text-muted-foreground font-semibold">Mène {game.current_round}</span>
            <div className="flex items-center gap-1.5">
              <span className="font-bold text-base">{game.score_team1}</span>
              <div className="w-3 h-3 rounded-full" style={{ background: "#f59e0b" }} />
            </div>
          </div>
        </div>
        {remainingMs !== null && myTurn && (
          <div className={`flex items-center gap-1 rounded-full px-2.5 py-1 font-bold ${remainingMs < 6000 ? "bg-red-500/15 text-red-600" : "bg-primary/10 text-primary"}`}>
            <Timer className="w-3.5 h-3.5" />
            {Math.ceil(remainingMs / 1000)}s
          </div>
        )}
        {Number(game.stake) > 0 && (
          <div className="flex items-center gap-1 rounded-full px-2.5 py-1 bg-amber-500/15 text-amber-700 dark:text-amber-300 font-bold">
            <Coins className="w-3.5 h-3.5" />
            {Number(game.pot).toLocaleString("fr-FR")}
          </div>
        )}
      </div>

      {/* Objectif : au gagnant */}
      <div className="px-3 pb-1 text-[11px] text-muted-foreground">
        <Target className="inline w-3 h-3 mr-1" />
        Objectif : {game.target_points} pts · Au gagnant : <b className="text-foreground">{Math.round(Number(game.pot) * 0.9).toLocaleString("fr-FR")} Ar</b>
      </div>

      {/* Boules restantes de chaque équipe */}
      <div className="px-3 pb-2 flex items-center justify-between text-[11px]">
        <div className="flex items-center gap-1">
          <span className="text-muted-foreground">Vous:</span>
          {Array.from({ length: me?.boules_left ?? 0 }).map((_, i) => (
            <Boule3D key={i} team={(me?.team ?? 0) as 0 | 1} size={14} />
          ))}
        </div>
        <div className="flex items-center gap-1">
          {Array.from({ length: opp?.boules_left ?? 0 }).map((_, i) => (
            <Boule3D key={i} team={(opp?.team ?? 1) as 0 | 1} size={14} />
          ))}
          <span className="text-muted-foreground">:Adv.</span>
        </div>
      </div>

      {/* Terrain isométrique */}
      <div className="flex-1 flex items-center justify-center px-2 pb-3" style={{ perspective: "900px" }}>
        <div
          className="relative w-full"
          style={{
            maxWidth: 560,
            aspectRatio: "16 / 9",
            transform: "rotateX(52deg)",
            transformStyle: "preserve-3d",
            background: "linear-gradient(180deg, #d4a373 0%, #c68b5f 50%, #a06842 100%)",
            borderRadius: "16px",
            boxShadow: "0 30px 60px -20px rgba(0,0,0,0.55), inset 0 0 60px rgba(120,80,50,0.4)",
            border: "3px solid #6b3f22",
          }}
        >
          {/* Texture sable */}
          <div className="absolute inset-0 rounded-[13px] opacity-40 pointer-events-none"
            style={{ backgroundImage: "radial-gradient(circle at 20% 30%, rgba(255,255,255,0.15) 0, transparent 40%), radial-gradient(circle at 70% 60%, rgba(0,0,0,0.15) 0, transparent 40%)" }} />

          {/* Ligne de lancer */}
          <div className="absolute inset-y-2" style={{ left: "5%", width: 2, background: "rgba(255,255,255,0.5)" }} />

          {/* Cochonnet */}
          <div
            className="absolute -translate-x-1/2 -translate-y-1/2"
            style={{ ...toScreen(game.cochonnet_x, game.cochonnet_y), transform: `translate(-50%, -50%) rotateX(-52deg) translateY(-6px)` }}
          >
            <Cochonnet />
          </div>

          {/* Boules jouées */}
          {roundBoules.map(b => (
            <div key={b.id} className="absolute"
              style={{ ...toScreen(b.x, b.y), transform: `translate(-50%, -50%) rotateX(-52deg) translateY(-12px)` }}>
              <Boule3D team={b.team as 0 | 1} muted={b.dead} size={28} />
            </div>
          ))}

          {/* Boule en vol (animation locale) */}
          {flying && (
            <div
              className="absolute pointer-events-none petanque-fly"
              style={{
                ...toScreen(flying.fromX, flying.fromY),
                transform: "translate(-50%, -50%)",
                ["--to-left" as any]: toScreen(flying.toX, flying.toY).left,
                ["--to-top" as any]: toScreen(flying.toX, flying.toY).top,
                ["--lob-h" as any]: `${12 + flying.lob * 60}px`,
              }}
            >
              <div style={{ transform: `rotateX(-52deg)` }}>
                <Boule3D team={flying.team} size={28} />
              </div>
            </div>
          )}

          {/* Prévisualisation de la trajectoire */}
          {myTurn && !flying && me && (
            <PreviewAim angle={angle} power={power} team={me.team as 0 | 1} />
          )}
        </div>
      </div>

      {/* Contrôles de lancer */}
      <div className="px-3 pb-3 space-y-2 bg-card/80 backdrop-blur border-t">
        <div className="text-xs font-semibold text-center">
          {myTurn ? "🎯 Votre tour" : game.current_player_id === null ? "🤖 Le bot joue…" : "⏳ Tour adverse"}
        </div>
        <Slider label="Direction" value={angle} min={-0.6} max={0.6} step={0.02} onChange={setAngle} format={v => `${Math.round(v * 100)}°`} disabled={!myTurn} />
        <Slider label="Puissance" value={power} min={0.1} max={1} step={0.02} onChange={setPower} format={v => `${Math.round(v * 100)}%`} disabled={!myTurn} accent />
        <div className="grid grid-cols-2 gap-2">
          <Slider label="Effet ↔" value={spin} min={-1} max={1} step={0.05} onChange={setSpin} format={v => v === 0 ? "—" : v > 0 ? `→ ${Math.round(v * 100)}` : `← ${Math.round(-v * 100)}`} disabled={!myTurn} />
          <Slider label="Lob ↑" value={lob} min={0} max={1} step={0.05} onChange={setLob} format={v => v < 0.15 ? "Roulée" : v > 0.7 ? "Portée" : "Mi-hauteur"} disabled={!myTurn} />
        </div>
        <div className="grid grid-cols-3 gap-2 pt-1">
          {me ? (
            <button onClick={onQuit} className="col-span-1 py-3 rounded-full bg-secondary font-semibold text-xs flex items-center justify-center gap-1">
              <LogOut className="w-3.5 h-3.5" /> Quitter
            </button>
          ) : (
            <button onClick={() => navigate({ to: "/live" })} className="col-span-1 py-3 rounded-full bg-secondary font-semibold text-xs flex items-center justify-center gap-1">
              <LogOut className="w-3.5 h-3.5" /> Sortir du live
            </button>
          )}
          <button
            onClick={throwBoule}
            disabled={!myTurn || throwing}
            className="col-span-2 py-3 rounded-full text-white font-bold text-sm shadow-lg shadow-primary/30 active:scale-[0.97] disabled:opacity-40 disabled:shadow-none"
            style={{ background: myTurn ? "var(--gradient-primary)" : "#94a3b8" }}
          >
            {throwing ? "Lancement…" : "🎳 Lancer"}
          </button>
        </div>
      </div>

      <style>{`
        @keyframes petanque-fly-kf {
          0%   { left: var(--from-left, 5%); top: var(--from-top, 50%); }
          50%  { transform: translate(-50%, calc(-50% - var(--lob-h, 30px))); }
          100% { left: var(--to-left, 90%); top: var(--to-top, 50%); }
        }
        .petanque-fly {
          animation: petanque-fly-kf 750ms cubic-bezier(0.4, 0, 0.6, 1) forwards;
        }
      `}</style>
    </main>
  );
}

// ── Composants utilitaires locaux ─────────────────────────────────────────
function Slider({ label, value, min, max, step, onChange, format, disabled, accent }: {
  label: string; value: number; min: number; max: number; step: number;
  onChange: (v: number) => void; format: (v: number) => string; disabled?: boolean; accent?: boolean;
}) {
  return (
    <label className={`block ${disabled ? "opacity-50" : ""}`}>
      <div className="flex items-center justify-between text-[11px] font-semibold mb-0.5">
        <span>{label}</span>
        <span className="text-primary tabular-nums">{format(value)}</span>
      </div>
      <input
        type="range" min={min} max={max} step={step} value={value} disabled={disabled}
        onChange={(e) => onChange(parseFloat(e.target.value))}
        className={`w-full ${accent ? "accent-primary" : "accent-orange-500"}`}
      />
    </label>
  );
}

function PreviewAim({ angle, power, team }: { angle: number; power: number; team: 0 | 1 }) {
  const fromX = -0.9;
  const fromY = team === 0 ? -0.25 : 0.25;
  const dist = 0.3 + power * 1.5;
  const toX = fromX + Math.cos(angle) * dist;
  const toY = fromY + Math.sin(angle) * dist;
  const from = toScreen(fromX, fromY);
  const to = toScreen(toX, toY);
  return (
    <svg className="absolute inset-0 w-full h-full pointer-events-none" style={{ overflow: "visible" }}>
      <defs>
        <marker id="preview-arrow" markerWidth="8" markerHeight="8" refX="4" refY="4" orient="auto">
          <path d="M0,0 L8,4 L0,8 Z" fill="white" opacity="0.7" />
        </marker>
      </defs>
      <line
        x1={from.left} y1={from.top} x2={to.left} y2={to.top}
        stroke="white" strokeWidth="1.5" strokeDasharray="4 3" opacity="0.6"
        markerEnd="url(#preview-arrow)"
      />
    </svg>
  );
}
