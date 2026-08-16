import { UUID_RE } from "@/lib/game-constants";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useState } from "react";
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

const STADIUM_BG = "https://base44.app/api/apps/6a8117572131062f5284967e/files/mp/public/6a8117572131062f5284967e/58d4386eb_stadium_bg.png";
const KEEPER_SPRITE = "https://base44.app/api/apps/6a8117572131062f5284967e/files/mp/public/6a8117572131062f5284967e/82b82f0a3_keeper_v2.png";
const BALL_SPRITE = "https://base44.app/api/apps/6a8117572131062f5284967e/files/mp/public/6a8117572131062f5284967e/d552f562f_ball_v2.png";

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

// Ball landing target for each zone, as % of viewport (top/left), aligned to the goal net
// in the stadium background image (crossbar ~40%, goal line ~59%, posts ~8%-92%).
const ZONE_TARGET: Record<number, { top: string; left: string }> = {
  1: { top: "43%", left: "24%" }, 2: { top: "43%", left: "50%" }, 3: { top: "43%", left: "76%" },
  4: { top: "54%", left: "24%" }, 5: { top: "54%", left: "50%" }, 6: { top: "54%", left: "76%" },
};
// Keeper dive transform per zone (translate is relative to the sprite's own size via %)
const KEEPER_DIVE: Record<number, string> = {
  1: "translate(-68%, -8%) rotate(-55deg)",
  2: "translate(0%, -18%) rotate(0deg)",
  3: "translate(68%, -8%) rotate(55deg)",
  4: "translate(-72%, 12%) rotate(-70deg)",
  5: "translate(0%, 6%) rotate(0deg) scaleY(0.92)",
  6: "translate(72%, 12%) rotate(70deg)",
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
  const [ballFlying, setBallFlying] = useState<{ zone: number; result: string } | null>(null);
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
    setBallFlying(null);
    setKeeperDive(null);
    setShowGoalFlash(false);
    setShowSaveFlash(false);
  }, [game?.current_round]);

  const playResultAnim = useCallback((result: string, shooterChoice: number, keeperChoices: number[]) => {
    sfx.diceRoll();
    setBallFlying({ zone: shooterChoice, result });
    setKeeperDive(keeperChoices[0] ?? 2);

    setTimeout(() => {
      if (result === "goal") { sfx.win(); setShowGoalFlash(true); }
      else { sfx.lose(); setShowSaveFlash(true); }
    }, 650);
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
      setTimeout(() => load(), 2100);
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

  const currentShooterIsMe = amShooter;

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

  const canPick = (amShooter || amKeeper) && currentRound && !currentRound.resolved_at && !submitting && !paused;
  const isAnimating = ballFlying != null || resolveAnim != null;
  const ballFlightClass = ballFlying ? `ball-fly-${ballFlying.zone}` : "";

  return (
    <div className="fixed inset-0 overflow-hidden select-none bg-sky-400" style={{ touchAction: "manipulation" }}>
      {/* ── Photorealistic stadium/goal background ── */}
      <div className="absolute inset-0" style={{
        backgroundImage: `url(${STADIUM_BG})`,
        backgroundSize: "cover",
        backgroundPosition: "center center",
      }} />
      <div className="absolute inset-0 bg-gradient-to-b from-black/30 via-transparent to-black/55" />

      {/* ── Goalkeeper sprite (dives on resolve) ── */}
      <div className="absolute z-10 transition-transform duration-500 ease-out"
        style={{
          top: "38%", left: "50%", width: "22%", height: "22%",
          transform: `translate(-50%, -20%) ${keeperDive != null ? KEEPER_DIVE[keeperDive] : ""}`,
        }}>
        <img src={KEEPER_SPRITE} alt="Gardien" className="w-full h-full object-contain drop-shadow-xl" draggable={false} />
      </div>

      {/* ── Clickable zone hotspots over the net ── */}
      <div className="absolute z-20 grid grid-cols-3 grid-rows-2" style={{ top: "37%", left: "8%", width: "84%", height: "24%" }}>
        {[1, 2, 3, 4, 5, 6].map(zone => {
          const isSelected = myChoice.includes(zone);
          return (
            <button key={zone} onClick={() => toggleZone(zone)}
              disabled={!canPick}
              className="relative flex items-center justify-center">
              {!isAnimating && (
                <span className="text-[10px] font-bold text-white/40 drop-shadow">{ZONE_SHORT[zone]}</span>
              )}
              {isSelected && !isAnimating && (
                <span className={`absolute inset-1 rounded-lg ring-2 animate-pulse ${amShooter ? "ring-yellow-400 bg-yellow-400/15" : "ring-sky-400 bg-sky-400/15"}`} />
              )}
            </button>
          );
        })}
      </div>

      {/* ── Ball at rest on the penalty spot ── */}
      {!isAnimating && (
        <img src={BALL_SPRITE} alt="Ballon" draggable={false}
          className="absolute z-10" style={{ top: "68%", left: "50%", width: "8%", transform: "translate(-50%, -50%)" }} />
      )}

      {/* ── Ball flying to target zone ── */}
      {ballFlying && (
        <img src={BALL_SPRITE} alt="Ballon" draggable={false}
          className={`absolute z-30 ${ballFlightClass}`}
          style={{ top: "68%", left: "50%", width: "8%", transform: "translate(-50%, -50%)" }} />
      )}

      {/* ── Goal/Save flash on target zone ── */}
      {resolveAnim && (showGoalFlash || showSaveFlash) && (
        <div className="absolute z-25 rounded-full animate-flash"
          style={{
            top: ZONE_TARGET[resolveAnim.shooterChoice].top, left: ZONE_TARGET[resolveAnim.shooterChoice].left,
            width: "16%", height: "10%", transform: "translate(-50%, -50%)",
            background: showGoalFlash ? "radial-gradient(circle, rgba(16,185,129,0.55), transparent 70%)" : "radial-gradient(circle, rgba(56,189,248,0.55), transparent 70%)",
          }} />
      )}

      {/* ── Top bar: pause + round + sound ── */}
      <button onClick={() => setPaused(true)}
        className="absolute top-3 left-3 z-30 w-10 h-10 rounded-xl bg-gradient-to-b from-amber-400 to-orange-600 shadow-lg flex items-center justify-center active:scale-95 transition-transform">
        <Pause className="w-4 h-4 text-white fill-white" />
      </button>

      <div className="absolute top-3 inset-x-0 flex flex-col items-center gap-1 z-30 pointer-events-none">
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

      {/* ── Goal/Save big text ── */}
      {showGoalFlash && (
        <div className="absolute inset-0 z-40 flex items-center justify-center pointer-events-none">
          <div className="text-6xl font-black text-yellow-400 drop-shadow-2xl animate-goal-text">BUT !</div>
        </div>
      )}
      {showSaveFlash && (
        <div className="absolute inset-0 z-40 flex items-center justify-center pointer-events-none">
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
      <div className="absolute bottom-3 left-3 right-3 z-30 flex flex-col gap-1.5">
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
        <div className="absolute inset-0 z-50 bg-black/75 backdrop-blur-sm flex flex-col items-center justify-center gap-4 p-6">
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
        @keyframes ballFly1 { 0% { top:68%; left:50%; width:8%; } 100% { top:${ZONE_TARGET[1].top}; left:${ZONE_TARGET[1].left}; width:4.5%; } }
        @keyframes ballFly2 { 0% { top:68%; left:50%; width:8%; } 100% { top:${ZONE_TARGET[2].top}; left:${ZONE_TARGET[2].left}; width:4.5%; } }
        @keyframes ballFly3 { 0% { top:68%; left:50%; width:8%; } 100% { top:${ZONE_TARGET[3].top}; left:${ZONE_TARGET[3].left}; width:4.5%; } }
        @keyframes ballFly4 { 0% { top:68%; left:50%; width:8%; } 100% { top:${ZONE_TARGET[4].top}; left:${ZONE_TARGET[4].left}; width:4.5%; } }
        @keyframes ballFly5 { 0% { top:68%; left:50%; width:8%; } 100% { top:${ZONE_TARGET[5].top}; left:${ZONE_TARGET[5].left}; width:4.5%; } }
        @keyframes ballFly6 { 0% { top:68%; left:50%; width:8%; } 100% { top:${ZONE_TARGET[6].top}; left:${ZONE_TARGET[6].left}; width:4.5%; } }
        .ball-fly-1 { animation: ballFly1 0.65s cubic-bezier(.25,.4,.4,1) forwards; }
        .ball-fly-2 { animation: ballFly2 0.65s cubic-bezier(.25,.4,.4,1) forwards; }
        .ball-fly-3 { animation: ballFly3 0.65s cubic-bezier(.25,.4,.4,1) forwards; }
        .ball-fly-4 { animation: ballFly4 0.65s cubic-bezier(.25,.4,.4,1) forwards; }
        .ball-fly-5 { animation: ballFly5 0.65s cubic-bezier(.25,.4,.4,1) forwards; }
        .ball-fly-6 { animation: ballFly6 0.65s cubic-bezier(.25,.4,.4,1) forwards; }
        .animate-goal-text { animation: goalText 0.8s ease-out; }
        @keyframes goalText { 0% { transform: scale(0) rotate(-10deg); opacity: 0; } 50% { transform: scale(1.3) rotate(5deg); opacity: 1; } 100% { transform: scale(1) rotate(0); opacity: 1; } }
        .animate-flash { animation: flashFade 0.7s ease-out; }
        @keyframes flashFade { 0% { opacity: 0.9; transform: translate(-50%,-50%) scale(0.7); } 100% { opacity: 0; transform: translate(-50%,-50%) scale(1.3); } }
      `}</style>
    </div>
  );
}

export default PenaltyGame;
