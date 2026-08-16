import { UUID_RE } from "@/lib/game-constants";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { GameLoader } from "@/components/game/GameLoader";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { ArrowLeft, Flag, Copy, Pause, Play, Volume2, VolumeX, Clock } from "lucide-react";
import { copyText } from "@/lib/clipboard";
import GameEndScreen from "@/components/game/GameEndScreen";
import { useConfirm } from "@/components/ConfirmDialog";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";
import { sfx, setMuted as setSfxMuted, isMuted as isSfxMuted } from "@/lib/game-sounds";

export const Route = createFileRoute("/_authenticated/jeux/penalty/$id")({
  component: PenaltyGame,
});

const ZONE_LABELS = ["", "Haut-Gauche", "Haut-Centre", "Haut-Droite", "Bas-Gauche", "Bas-Centre", "Bas-Droite"];
const ZONE_SHORT = ["", "G-H", "C-H", "D-H", "G-B", "C-B", "D-B"];
const TURN_DURATION = 30;

type GameRow = {
  id: string; host_id: string; player1_id: string | null; player2_id: string | null;
  status: "open" | "playing" | "finished" | "cancelled"; stake: number; pot: number;
  commission_pct: number; is_private: boolean; room_code: string | null;
  num_balls: number; num_keeper_choices: number; player1_ready: boolean; player2_ready: boolean;
  first_shooter_id: string | null; current_round: number; current_shooter: string | null;
  p1_score: number; p2_score: number; is_overtime: boolean; overtime_round: number;
  winner_id: string | null; created_at: string; started_at: string | null; finished_at: string | null;
  bot_difficulty: number | null;
};

type RoundRow = {
  id: string; game_id: string; round_num: number; shooter_id: string; keeper_id: string;
  shooter_choice: number | null; keeper_choices: number[] | null; result: string | null;
  is_overtime: boolean; resolved_at: string | null;
};

type Profile = { id: string; pseudo: string; avatar_url: string | null };

// Zone positions on the goal (in % of goal area)
const ZONE_POS: Record<number, { x: number; y: number }> = {
  1: { x: 16, y: 22 }, 2: { x: 50, y: 22 }, 3: { x: 84, y: 22 },
  4: { x: 16, y: 72 }, 5: { x: 50, y: 72 }, 6: { x: 84, y: 72 },
};

function PenaltyGame() {
  const { id } = Route.useParams();
  const { profile, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();

  const [game, setGame] = useState<GameRow | null>(null);
  const [rounds, setRounds] = useState<RoundRow[]>([]);
  const [p1Profile, setP1Profile] = useState<Profile | null>(null);
  const [p2Profile, setP2Profile] = useState<Profile | null>(null);
  const [currentRound, setCurrentRound] = useState<RoundRow | null>(null);
  const [myChoice, setMyChoice] = useState<number[]>([]);
  const [submitting, setSubmitting] = useState(false);
  const [resolveAnim, setResolveAnim] = useState<{ result: string; shooterChoice: number; keeperChoices: number[] } | null>(null);
  const [timeLeft, setTimeLeft] = useState(TURN_DURATION);
  const [loading, setLoading] = useState(true);
  const [paused, setPaused] = useState(false);
  const [muted, setMuted] = useState(false);
  const [ballAnim, setBallAnim] = useState<{ zone: number; result: string } | null>(null);
  const [keeperDive, setKeeperDive] = useState<number | null>(null);
  const [showGoalFlash, setShowGoalFlash] = useState(false);
  const [showSaveFlash, setShowSaveFlash] = useState(false);

  useEffect(() => { setMuted(isSfxMuted()); }, []);
  const toggleMuted = useCallback(() => {
    const next = !muted;
    setSfxMuted(next);
    setMuted(next);
  }, [muted]);

  const load = useCallback(async () => {
    if (!UUID_RE.test(id)) { navigate({ to: "/jeux" }); return; }
    try {
      const { data: g, error } = await supabase
        .from("penalty_games")
        .select("*")
        .eq("id", id)
        .single();
      if (error) throw error;
      if (!g) { toast.error("Partie introuvable"); navigate({ to: "/jeux" }); return; }
      setGame(g as GameRow);

      const ids = [g.player1_id, g.player2_id].filter(Boolean) as string[];
      if (ids.length) {
        const { data: profs } = await supabase
          .from("profiles")
          .select("id, pseudo, avatar_url")
          .in("id", ids);
        if (profs) {
          setP1Profile(profs.find((p: any) => p.id === g.player1_id) as Profile || null);
          setP2Profile(profs.find((p: any) => p.id === g.player2_id) as Profile || null);
        }
      }

      const { data: rds } = await supabase
        .from("penalty_rounds")
        .select("*")
        .eq("game_id", id)
        .order("round_num", { ascending: true });
      if (rds) setRounds(rds as RoundRow[]);

      if (g.status === "playing") {
        const cr = (rds as RoundRow[])?.find(r => r.round_num === g.current_round) || null;
        setCurrentRound(cr);
      } else {
        setCurrentRound(null);
      }
    } catch (e: any) {
      toast.error(e.message || "Erreur de chargement");
    } finally {
      setLoading(false);
    }
  }, [id, navigate]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });
  useFastRealtime({
    gameTable: "penalty_games", participantTable: "", gameId: id,
    enabled: !!profile?.id, onFinished: refreshProfile,
  } as any);

  const meId = profile?.id;
  const isBotGame = game?.bot_difficulty != null && !game?.player2_id;
  const isPlayer1 = game?.player1_id === meId;
  const isPlayer2 = game?.player2_id === meId;
  const isSpectator = !isPlayer1 && !isPlayer2 && !isBotGame;
  const myScore = isPlayer1 ? game?.p1_score ?? 0 : isPlayer2 ? game?.p2_score ?? 0 : 0;
  const oppScore = isPlayer1 ? game?.p2_score ?? 0 : isPlayer2 ? game?.p1_score ?? 0 : 0;
  const myName = profile?.pseudo || "Moi";
  const oppName = isBotGame ? "Bot" : (isPlayer1 ? p2Profile?.pseudo : isPlayer2 ? p1Profile?.pseudo : "Adversaire");
  const oppAvatar = isBotGame ? null : (isPlayer1 ? p2Profile?.avatar_url : isPlayer2 ? p1Profile?.avatar_url : null);
  const myAvatar = profile?.avatar_url;

  const amShooter = isBotGame ? game?.current_shooter === meId : game?.current_shooter === meId;
  const amKeeper = isBotGame ? (!game?.current_shooter && !!isPlayer1) : (game?.current_shooter && game?.current_shooter !== meId && (isPlayer1 || isPlayer2));
  const numZonesToPick = amShooter ? 1 : amKeeper ? game?.num_keeper_choices ?? 2 : 0;

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    if (!id) return;
    const ch = supabase
      .channel(`penalty-${id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "penalty_games", filter: `id=eq.${id}` }, () => load())
      .on("postgres_changes", { event: "*", schema: "public", table: "penalty_rounds", filter: `game_id=eq.${id}` }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  useEffect(() => {
    if (game?.status !== "playing" || !currentRound || currentRound.resolved_at || paused) return;
    setTimeLeft(TURN_DURATION);
    const startTime = Date.now();
    const interval = setInterval(() => {
      const elapsed = Math.floor((Date.now() - startTime) / 1000);
      const remaining = TURN_DURATION - elapsed;
      setTimeLeft(remaining);
      if (remaining <= 0) {
        clearInterval(interval);
        if ((amShooter || amKeeper) && !submitting) {
          const zones = [1,2,3,4,5,6];
          const picked = zones.sort(() => Math.random() - 0.5).slice(0, numZonesToPick);
          handleSubmit(picked);
        }
      }
    }, 200);
    return () => clearInterval(interval);
  }, [game?.status, currentRound?.round_num, currentRound?.resolved_at, paused]);

  useEffect(() => {
    setMyChoice([]);
    setResolveAnim(null);
    setBallAnim(null);
    setKeeperDive(null);
    setShowGoalFlash(false);
    setShowSaveFlash(false);
  }, [game?.current_round]);

  const playKickSound = useCallback(() => {
    sfx.diceRoll(); // repurposed as a "kick" sound
  }, []);

  const playResultAnim = useCallback((result: string, shooterChoice: number, keeperChoices: number[]) => {
    // Phase 1: Ball flies to the zone
    sfx.diceRoll();
    setBallAnim({ zone: shooterChoice, result });
    setKeeperDive(keeperChoices[0] ?? 5);

    // Phase 2: After ball reaches, show result
    setTimeout(() => {
      if (result === "goal") {
        sfx.win();
        setShowGoalFlash(true);
      } else {
        sfx.lose();
        setShowSaveFlash(true);
      }
    }, 700);
  }, []);

  const handleSubmit = useCallback(async (choices: number[]) => {
    if (!game || submitting) return;
    setSubmitting(true);
    try {
      const { data, error } = await supabase.rpc("penalty_submit_choice" as any, { _game_id: id, _choice: choices } as any);
      if (error) throw error;
      const result = data as any;
      if (result?.resolved) {
        setResolveAnim({ result: result.result, shooterChoice: result.shooter_choice, keeperChoices: result.keeper_choices });
        playResultAnim(result.result, result.shooter_choice, result.keeper_choices);
      }
      setMyChoice([]);
      // Don't reload immediately — let animation play, then reload
      setTimeout(() => load(), 2000);
    } catch (e: any) {
      toast.error(e.message || "Erreur");
    } finally {
      setSubmitting(false);
    }
  }, [game, submitting, id, load, playResultAnim]);

  const handleReady = useCallback(async () => {
    try {
      const { error } = await supabase.rpc("penalty_set_ready" as any, { _game_id: id, _ready: true } as any);
      if (error) throw error;
      load();
    } catch (e: any) {
      toast.error(e.message || "Erreur");
    }
  }, [id, load]);

  const handleForfeit = useCallback(async () => {
    if (!await confirm({ title: "Abandonner ?", message: "Tu perdras ta mise et l'adversaire remportera la partie." })) return;
    try {
      const { error } = await supabase.rpc("penalty_forfeit" as any, { _game_id: id } as any);
      if (error) throw error;
      toast.success("Partie abandonnée");
      navigate({ to: "/jeux" });
    } catch (e: any) {
      toast.error(e.message || "Erreur");
    }
  }, [confirm, id, navigate]);

  const toggleZone = (zone: number) => {
    if (submitting || paused) return;
    if (myChoice.includes(zone)) {
      setMyChoice(myChoice.filter(z => z !== zone));
    } else if (myChoice.length < numZonesToPick) {
      setMyChoice([...myChoice, zone]);
      sfx.pawnStep();
    }
  };

  if (loading) return <GameLoader />;
  if (!game) return <GameLoader />;

  // ── Waiting room ──
  if (game.status === "open") {
    return (
      <div className="min-h-screen bg-gradient-to-b from-green-900 to-green-950 flex flex-col items-center justify-center p-4 text-white">
        <div className="text-center mb-8">
          <div className="text-6xl mb-4">⚽</div>
          <h1 className="text-2xl font-bold">Salle d'attente Penalty</h1>
          <p className="text-green-300 text-sm mt-2">{game.num_balls} ballons · Gardien: {game.num_keeper_choices} choix</p>
        </div>
        <div className="flex items-center gap-8 mb-8">
          <div className="flex flex-col items-center gap-2">
            <div className={`w-16 h-16 rounded-full flex items-center justify-center text-2xl font-bold ${game.player1_ready ? "bg-emerald-500" : "bg-white/10"}`}>
              {p1Profile?.avatar_url ? <img src={p1Profile.avatar_url} className="w-full h-full rounded-full object-cover" /> : p1Profile?.pseudo?.[0] || "?"}
            </div>
            <span className="text-sm font-semibold">{p1Profile?.pseudo || "Joueur 1"}</span>
            {game.player1_ready && <span className="text-emerald-400 text-xs">✓ Prêt</span>}
          </div>
          <span className="text-3xl text-white/30">VS</span>
          <div className="flex flex-col items-center gap-2">
            <div className={`w-16 h-16 rounded-full flex items-center justify-center text-2xl font-bold ${game.player2_ready ? "bg-emerald-500" : "bg-white/10"}`}>
              {p2Profile?.avatar_url ? <img src={p2Profile.avatar_url} className="w-full h-full rounded-full object-cover" /> : p2Profile?.pseudo?.[0] || "?"}
            </div>
            <span className="text-sm font-semibold">{p2Profile?.pseudo || "En attente..."}</span>
            {game.player2_ready && <span className="text-emerald-400 text-xs">✓ Prêt</span>}
          </div>
        </div>
        {game.is_private && game.room_code && (
          <button onClick={() => copyText(game.room_code!)} className="mb-4 px-4 py-2 rounded-lg bg-white/10 flex items-center gap-2 text-sm">
            <Copy className="w-4 h-4" /> Code: <strong>{game.room_code}</strong>
          </button>
        )}
        {(isPlayer1 || isPlayer2) && (
          <button onClick={handleReady} disabled={(isPlayer1 && game.player1_ready) || (isPlayer2 && game.player2_ready)}
            className="px-8 py-3 rounded-full bg-emerald-500 text-white font-bold text-sm disabled:opacity-50">
            {(isPlayer1 && game.player1_ready) || (isPlayer2 && game.player2_ready) ? "✓ Prêt" : "Prêt !"}
          </button>
        )}
        {isSpectator && <p className="text-green-300 text-sm">Spectateur — en attente du démarrage...</p>}
        {isPlayer1 && !game.player2_id && <p className="text-green-300 text-sm mt-4">En attente d'un adversaire...</p>}
        <button onClick={() => navigate({ to: "/jeux" })} className="mt-8 text-white/50 text-sm flex items-center gap-1">
          <ArrowLeft className="w-4 h-4" /> Retour
        </button>
      </div>
    );
  }

  // ── Game finished ──
  if (game.status === "finished" || game.status === "cancelled") {
    return (
      <div className="min-h-screen bg-gradient-to-b from-green-900 to-green-950 flex flex-col items-center justify-center p-4 text-white">
        <GameEndScreen slug="penalty" meUserId={meId} winnerId={game.winner_id}
          participants={[{ user_id: game.player1_id, display_name: p1Profile?.pseudo || "Joueur 1" }, { user_id: game.player2_id, display_name: p2Profile?.pseudo || "Joueur 2" }].filter(p => p.user_id)}
          stake={game.stake} pot={game.pot} commissionPct={game.commission_pct}
          onReplay={() => navigate({ to: "/jeux/$slug", params: { slug: "penalty" } })} />
        <div className="mt-4 text-center">
          <p className="text-2xl font-bold">{game.p1_score} - {game.p2_score}</p>
          <p className="text-green-300 text-sm mt-1">{p1Profile?.pseudo} {game.p1_score} · {p2Profile?.pseudo} {game.p2_score}</p>
        </div>
        <button onClick={() => navigate({ to: "/jeux" })} className="mt-6 text-white/50 text-sm flex items-center gap-1">
          <ArrowLeft className="w-4 h-4" /> Retour aux jeux
        </button>
      </div>
    );
  }

  // ── Playing ──
  const totalRegularRounds = game.num_balls * 2;
  const currentShotNum = game.is_overtime
    ? Math.ceil((game.current_round - totalRegularRounds) / 2) + 1
    : Math.ceil(game.current_round / 2);

  const myRoundsSeq = isPlayer1
    ? rounds.filter(r => r.shooter_id === game.player1_id)
    : rounds.filter(r => r.shooter_id === game.player2_id);
  const oppRoundsSeq = isPlayer1
    ? rounds.filter(r => r.shooter_id === game.player2_id)
    : rounds.filter(r => r.shooter_id === game.player1_id);

  const renderDots = (seq: RoundRow[], isMine: boolean) => (
    <div className="flex items-center gap-1">
      {Array.from({ length: game.num_balls }).map((_, i) => {
        const r = seq[i];
        const isCurrent = !r && i === seq.length && currentRound && !currentRound.resolved_at &&
          ((isMine && currentShooterIsMe) || (!isMine && !currentShooterIsMe)) && !game.is_overtime;
        let cls = "bg-white/25 border border-white/30";
        if (r?.resolved_at) {
          cls = r.result === "goal" ? "bg-emerald-500 border border-emerald-300" : "bg-red-500 border border-red-300";
        } else if (isCurrent) {
          cls = "bg-amber-400 border border-amber-200 animate-pulse";
        }
        return <span key={i} className={`w-2.5 h-2.5 rounded-full ${cls}`} />;
      })}
    </div>
  );

  const currentShooterIsMe = amShooter;
  const canPick = (amShooter || amKeeper) && currentRound && !currentRound.resolved_at && !submitting && !paused;
  const isAnimating = ballAnim != null || resolveAnim != null;

  // Keeper dive position
  const keeperDiveX = keeperDive != null ? (keeperDive <= 3 ? (keeperDive === 1 ? -30 : keeperDive === 2 ? 0 : 30) : (keeperDive === 4 ? -30 : keeperDive === 5 ? 0 : 30)) : 0;
  const keeperDiveY = keeperDive != null ? (keeperDive <= 3 ? -10 : 15) : 0;
  const ballTarget = ballAnim ? ZONE_POS[ballAnim.zone] : null;

  return (
    <div className="fixed inset-0 overflow-hidden select-none" style={{ touchAction: "manipulation" }}>
      {/* ── Stadium gradient background ── */}
      <div className="absolute inset-0 bg-gradient-to-b from-sky-400 via-sky-300 to-green-500" />
      {/* Stadium stands (top) */}
      <div className="absolute top-0 inset-x-0 h-[22%] bg-gradient-to-b from-slate-700 to-slate-800" style={{ backgroundImage: "repeating-linear-gradient(90deg, rgba(0,0,0,0.15) 0px, rgba(0,0,0,0.15) 8px, transparent 8px, transparent 20px)" }} />
      {/* Crowd dots */}
      <div className="absolute top-[3%] inset-x-0 h-[16%] opacity-30" style={{ backgroundImage: "radial-gradient(circle, rgba(255,255,255,0.5) 1px, transparent 1.5px)", backgroundSize: "12px 8px" }} />

      {/* ── Goal structure (CSS) ── */}
      <div className="absolute z-10" style={{ top: "15%", left: "8%", width: "84%", height: "38%" }}>
        {/* Goal posts */}
        <div className="absolute top-0 left-0 w-2.5 h-full bg-white rounded-full shadow-lg" />
        <div className="absolute top-0 right-0 w-2.5 h-full bg-white rounded-full shadow-lg" />
        <div className="absolute top-0 left-0 right-0 h-2.5 bg-white rounded-full shadow-lg" />
        {/* Net background */}
        <div className="absolute inset-2 bg-emerald-600/20" style={{
          backgroundImage: "repeating-linear-gradient(0deg, rgba(255,255,255,0.15) 0px, rgba(255,255,255,0.15) 1px, transparent 1px, transparent 14px), repeating-linear-gradient(90deg, rgba(255,255,255,0.15) 0px, rgba(255,255,255,0.15) 1px, transparent 1px, transparent 14px)",
        }} />

        {/* Goalkeeper (animated dive) */}
        <div className="absolute z-15 transition-all duration-700 ease-out"
          style={{
            top: "30%", left: "50%",
            transform: `translate(-50%, 0) translate(${keeperDiveX}%, ${keeperDiveY}%) scale(${keeperDive != null ? 1.1 : 1})`,
            width: "14%", height: "45%",
          }}>
          <div className="w-full h-full flex items-center justify-center">
            {/* Keeper body */}
            <div className={`relative ${keeperDive != null ? "rotate-12" : ""} transition-transform duration-500`}>
              <div className="w-10 h-14 rounded-t-full bg-sky-600 border-2 border-sky-800 flex items-center justify-center shadow-lg">
                <div className="w-6 h-6 rounded-full bg-amber-200 border border-amber-400 relative">
                  <div className="absolute top-2 left-1 w-1.5 h-1 bg-slate-800 rounded-full" />
                  <div className="absolute top-2 right-1 w-1.5 h-1 bg-slate-800 rounded-full" />
                </div>
              </div>
              {/* Arms */}
              <div className={`absolute -left-2 top-3 w-4 h-2 rounded-full bg-amber-200 border border-amber-400 transition-transform duration-500 ${keeperDive != null ? "-rotate-45 -translate-x-2" : "rotate-0"}`} />
              <div className={`absolute -right-2 top-3 w-4 h-2 rounded-full bg-amber-200 border border-amber-400 transition-transform duration-500 ${keeperDive != null ? "rotate-45 translate-x-2" : "rotate-0"}`} />
            </div>
          </div>
        </div>

        {/* Clickable zones overlay */}
        <div className="absolute inset-2 grid grid-cols-3 grid-rows-2 gap-0 z-20">
          {[1, 2, 3, 4, 5, 6].map(zone => {
            const isSelected = myChoice.includes(zone);
            const isShooterZone = resolveAnim?.shooterChoice === zone;
            const isKeeperZone = resolveAnim?.keeperChoices?.includes(zone);
            const wasGoal = resolveAnim?.result === "goal";
            const isBallLanding = ballAnim?.zone === zone;
            return (
              <button key={zone} onClick={() => toggleZone(zone)}
                disabled={!canPick}
                className={`relative flex items-center justify-center transition-all duration-200
                  ${canPick ? "hover:bg-white/5 active:bg-white/10" : ""}
                `}>
                {/* Selection highlight */}
                {isSelected && !isAnimating && (
                  <div className={`absolute inset-1 rounded-lg ring-2 animate-pulse ${amShooter ? "ring-yellow-400 bg-yellow-400/20" : "ring-sky-400 bg-sky-400/20"}`} />
                )}
                {/* Zone label (always visible faintly) */}
                {!isAnimating && (
                  <span className="text-[10px] font-bold text-white/30">{ZONE_SHORT[zone]}</span>
                )}
                {/* Ball landing animation */}
                {isBallLanding && ballAnim && (
                  <div className="text-4xl drop-shadow-2xl animate-ball-land">
                    {ballAnim.result === "goal" ? "⚽" : "🧤"}
                  </div>
                )}
                {/* Keeper zone indicator */}
                {isKeeperZone && isShooterZone && resolveAnim && (
                  <div className="absolute inset-1 rounded-lg ring-2 ring-sky-400/60" />
                )}
                {/* Goal zone flash */}
                {isShooterZone && resolveAnim && wasGoal && showGoalFlash && (
                  <div className="absolute inset-0 rounded-lg bg-emerald-400/30 animate-flash" />
                )}
                {/* Save zone flash */}
                {isShooterZone && resolveAnim && !wasGoal && showSaveFlash && (
                  <div className="absolute inset-0 rounded-lg bg-sky-400/30 animate-flash" />
                )}
              </button>
            );
          })}
        </div>
      </div>

      {/* ── Penalty spot + ball (before animation) ── */}
      {!isAnimating && (
        <div className="absolute z-10" style={{ bottom: "20%", left: "50%", transform: "translateX(-50%)" }}>
          <div className="w-6 h-6 rounded-full bg-white shadow-lg flex items-center justify-center text-xs">
            ⚽
          </div>
          <div className="w-2 h-1 bg-white/40 rounded-full mt-1 mx-auto" />
        </div>
      )}

      {/* ── Animated ball flying toward goal ── */}
      {ballAnim && ballTarget && (
        <div className="absolute z-20"
          style={{
            bottom: "20%", left: "50%",
            animation: `ballFly-${ballAnim.zone} 0.7s cubic-bezier(0.3, 0.1, 0.5, 1) forwards`,
          }}>
          <div className="text-3xl drop-shadow-2xl">⚽</div>
        </div>
      )}

      {/* ── Grass pitch ── */}
      <div className="absolute bottom-0 inset-x-0 h-[30%] bg-gradient-to-b from-green-500 to-green-600"
        style={{ backgroundImage: "repeating-linear-gradient(90deg, rgba(0,0,0,0.06) 0px, rgba(0,0,0,0.06) 30px, transparent 30px, transparent 60px)" }} />

      {/* ── Top bar: pause + round + sound ── */}
      <button onClick={() => setPaused(true)}
        className="absolute top-3 left-3 z-30 w-10 h-10 rounded-xl bg-gradient-to-b from-amber-400 to-orange-600 shadow-lg flex items-center justify-center active:scale-95 transition-transform">
        <Pause className="w-4 h-4 text-white fill-white" />
      </button>

      <div className="absolute top-3 inset-x-0 flex flex-col items-center gap-1 z-20 pointer-events-none">
        <span className="px-3 py-1 rounded-full bg-black/50 backdrop-blur-sm text-xs font-bold text-white">
          {game.is_overtime ? "⚔️ PROL" : `⚽ ${currentShotNum}/${game.num_balls}`}
        </span>
        {currentRound && !currentRound.resolved_at && (amShooter || amKeeper) && (
          <span className={`flex items-center gap-1 px-2.5 py-0.5 rounded-full bg-black/50 backdrop-blur-sm text-xs font-bold ${timeLeft <= 10 ? "text-red-400" : "text-white"}`}>
            <Clock className="w-3 h-3" /> {timeLeft}s
          </span>
        )}
      </div>

      <button onClick={toggleMuted}
        className="absolute top-3 right-3 z-30 w-10 h-10 rounded-xl bg-gradient-to-b from-amber-400 to-orange-600 shadow-lg flex items-center justify-center active:scale-95 transition-transform">
        {muted ? <VolumeX className="w-4 h-4 text-white" /> : <Volume2 className="w-4 h-4 text-white" />}
      </button>

      {/* ── Turn prompt ── */}
      <div className="absolute top-[58px] inset-x-0 flex justify-center z-20 pointer-events-none px-6">
        {amShooter && currentRound && !currentRound.resolved_at && !isAnimating && (
          <p className="px-3 py-1 rounded-full bg-black/50 backdrop-blur-sm text-center text-xs text-yellow-300 font-semibold">🎯 Tire ! Choisis 1 zone</p>
        )}
        {amKeeper && currentRound && !currentRound.resolved_at && !isAnimating && (
          <p className="px-3 py-1 rounded-full bg-black/50 backdrop-blur-sm text-center text-xs text-sky-300 font-semibold">🧤 Garde ! Choisis {game.num_keeper_choices} zone{game.num_keeper_choices > 1 ? "s" : ""}</p>
        )}
        {isSpectator && game.status === "playing" && !isAnimating && (
          <p className="px-3 py-1 rounded-full bg-black/50 backdrop-blur-sm text-center text-xs text-white/70">👀 Spectateur</p>
        )}
        {currentRound?.resolved_at && !isAnimating && (
          <p className="px-3 py-1 rounded-full bg-black/50 backdrop-blur-sm text-center text-xs text-white/70">Tour suivant...</p>
        )}
      </div>

      {/* ── Goal/Save flash overlay ── */}
      {showGoalFlash && (
        <div className="absolute inset-0 z-25 flex items-center justify-center pointer-events-none">
          <div className="text-6xl font-black text-yellow-400 drop-shadow-2xl animate-goal-text">BUT !</div>
        </div>
      )}
      {showSaveFlash && (
        <div className="absolute inset-0 z-25 flex items-center justify-center pointer-events-none">
          <div className="text-5xl font-black text-sky-300 drop-shadow-2xl animate-goal-text">ARRÊT !</div>
        </div>
      )}

      {/* ── Validate button ── */}
      {canPick && !isAnimating && (
        <div className="absolute bottom-[92px] inset-x-0 flex justify-center z-20 px-8">
          <button onClick={() => handleSubmit(myChoice)} disabled={myChoice.length !== numZonesToPick}
            className="w-full max-w-xs py-3.5 rounded-full bg-emerald-500 text-white font-bold text-sm shadow-lg shadow-black/40 disabled:opacity-40 active:scale-95 transition-transform">
            {myChoice.length === numZonesToPick ? "Tirer ⚽" : `Choisis ${numZonesToPick - myChoice.length}`}
          </button>
        </div>
      )}

      {/* ── Bottom scoreboard ── */}
      <div className="absolute bottom-3 left-3 right-3 z-20 flex flex-col gap-1.5">
        <div className="flex items-center gap-2 pl-1.5 pr-2.5 py-1.5 rounded-lg bg-black/55 backdrop-blur-sm shadow-lg">
          <span className="w-1.5 h-5 rounded-sm bg-amber-400 shrink-0" />
          <span className="flex-1 text-xs font-bold truncate text-white">{myName}</span>
          <span className="min-w-[20px] px-1 py-0.5 rounded bg-sky-600 text-center text-xs font-black text-white">{myScore}</span>
          {renderDots(myRoundsSeq, true)}
        </div>
        <div className="flex items-center gap-2 pl-1.5 pr-2.5 py-1.5 rounded-lg bg-black/55 backdrop-blur-sm shadow-lg">
          <span className="w-1.5 h-5 rounded-sm bg-slate-300 shrink-0" />
          <span className="flex-1 text-xs font-bold truncate text-white">{oppName}</span>
          <span className="min-w-[20px] px-1.5 py-0.5 rounded bg-sky-600 text-center text-xs font-black text-white">{oppScore}</span>
          {renderDots(oppRoundsSeq, false)}
        </div>
      </div>

      {/* ── Pause overlay ── */}
      {paused && (
        <div className="absolute inset-0 z-40 bg-black/75 backdrop-blur-sm flex flex-col items-center justify-center gap-4 p-6">
          <h2 className="text-2xl font-black text-white">⏸ Pause</h2>
          <button onClick={() => setPaused(false)}
            className="w-full max-w-xs py-3 rounded-full bg-emerald-500 text-white font-bold text-sm flex items-center justify-center gap-2">
            <Play className="w-4 h-4 fill-white" /> Reprendre
          </button>
          <button onClick={() => { setPaused(false); handleForfeit(); }}
            className="w-full max-w-xs py-3 rounded-full bg-white/10 text-red-300 font-bold text-sm flex items-center justify-center gap-2">
            <Flag className="w-4 h-4" /> Abandonner
          </button>
          <button onClick={() => navigate({ to: "/jeux" })}
            className="text-white/50 text-sm flex items-center gap-1 mt-2">
            <ArrowLeft className="w-4 h-4" /> Retour aux jeux
          </button>
        </div>
      )}

      {/* ── Animations CSS ── */}
      <style>{`
        @keyframes ballFly-1 { 0% { bottom: 20%; left: 50%; transform: scale(1); } 100% { bottom: 44%; left: 18%; transform: scale(0.5); } }
        @keyframes ballFly-2 { 0% { bottom: 20%; left: 50%; transform: scale(1); } 100% { bottom: 44%; left: 50%; transform: scale(0.5); } }
        @keyframes ballFly-3 { 0% { bottom: 20%; left: 50%; transform: scale(1); } 100% { bottom: 44%; left: 82%; transform: scale(0.5); } }
        @keyframes ballFly-4 { 0% { bottom: 20%; left: 50%; transform: scale(1); } 100% { bottom: 30%; left: 18%; transform: scale(0.5); } }
        @keyframes ballFly-5 { 0% { bottom: 20%; left: 50%; transform: scale(1); } 100% { bottom: 30%; left: 50%; transform: scale(0.5); } }
        @keyframes ballFly-6 { 0% { bottom: 20%; left: 50%; transform: scale(1); } 100% { bottom: 30%; left: 82%; transform: scale(0.5); } }
        .animate-ball-land { animation: ballLand 0.3s ease-out; }
        @keyframes ballLand { 0% { transform: scale(0.3); opacity: 0; } 50% { transform: scale(1.2); } 100% { transform: scale(1); opacity: 1; } }
        .animate-goal-text { animation: goalText 0.8s ease-out; }
        @keyframes goalText { 0% { transform: scale(0) rotate(-10deg); opacity: 0; } 50% { transform: scale(1.3) rotate(5deg); opacity: 1; } 100% { transform: scale(1) rotate(0); opacity: 1; } }
        .animate-flash { animation: flashFade 0.6s ease-out; }
        @keyframes flashFade { 0% { opacity: 0.8; } 100% { opacity: 0; } }
      `}</style>
    </div>
  );
}

export default PenaltyGame;
