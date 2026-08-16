import { UUID_RE } from "@/lib/game-constants";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useCallback, useEffect, useRef, useState } from "react";
import { GameLoader } from "@/components/game/GameLoader";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { ArrowLeft, Flag, Copy, LogOut, Trophy, RotateCw, Clock } from "lucide-react";
import { copyText } from "@/lib/clipboard";
import GameEndScreen from "@/components/game/GameEndScreen";
import { useConfirm } from "@/components/ConfirmDialog";
import { serverNow } from "@/lib/server-time";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";

export const Route = createFileRoute("/_authenticated/jeux/penalty/$id")({
  component: PenaltyGame,
});

const ZONE_LABELS = ["", "Haut-Gauche", "Haut-Centre", "Haut-Droite", "Bas-Gauche", "Bas-Centre", "Bas-Droite"];
const ZONE_SHORT = ["", "G-H", "C-H", "D-H", "G-B", "C-B", "D-B"];
const TURN_DURATION = 30;

type GameRow = {
  id: string;
  host_id: string;
  player1_id: string | null;
  player2_id: string | null;
  status: "open" | "playing" | "finished" | "cancelled";
  stake: number;
  pot: number;
  commission_pct: number;
  is_private: boolean;
  room_code: string | null;
  num_balls: number;
  num_keeper_choices: number;
  player1_ready: boolean;
  player2_ready: boolean;
  first_shooter_id: string | null;
  current_round: number;
  current_shooter: string | null;
  p1_score: number;
  p2_score: number;
  is_overtime: boolean;
  overtime_round: number;
  winner_id: string | null;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
};

type RoundRow = {
  id: string;
  game_id: string;
  round_num: number;
  shooter_id: string;
  keeper_id: string;
  shooter_choice: number | null;
  keeper_choices: number[] | null;
  result: string | null;
  is_overtime: boolean;
  resolved_at: string | null;
};

type Profile = { id: string; pseudo: string; avatar_url: string | null };

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
    gameTable: "penalty_games",
    participantTable: "",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile,
  }) as any;

  const meId = profile?.id;
  const isPlayer1 = game?.player1_id === meId;
  const isPlayer2 = game?.player2_id === meId;
  const isSpectator = !isPlayer1 && !isPlayer2;
  const myScore = isPlayer1 ? game?.p1_score ?? 0 : isPlayer2 ? game?.p2_score ?? 0 : 0;
  const oppScore = isPlayer1 ? game?.p2_score ?? 0 : isPlayer2 ? game?.p1_score ?? 0 : 0;
  const myName = profile?.pseudo || "Moi";
  const oppName = isPlayer1 ? p2Profile?.pseudo : isPlayer2 ? p1Profile?.pseudo : "Adversaire";
  const oppAvatar = isPlayer1 ? p2Profile?.avatar_url : isPlayer2 ? p1Profile?.avatar_url : null;
  const myAvatar = profile?.avatar_url;

  const amShooter = game?.current_shooter === meId;
  const amKeeper = game?.current_shooter && game?.current_shooter !== meId && (isPlayer1 || isPlayer2);
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
    if (game?.status !== "playing" || !currentRound) return;
    if (currentRound.resolved_at) return;
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
  }, [game?.status, currentRound?.round_num, currentRound?.resolved_at]);

  useEffect(() => {
    setMyChoice([]);
    setResolveAnim(null);
  }, [game?.current_round]);

  const handleSubmit = useCallback(async (choices: number[]) => {
    if (!game || submitting) return;
    setSubmitting(true);
    try {
      const { data, error } = await supabase.rpc("penalty_submit_choice" as any, { _game_id: id, _choice: choices } as any);
      if (error) throw error;
      const result = data as any;
      if (result?.resolved) {
        setResolveAnim({ result: result.result, shooterChoice: result.shooter_choice, keeperChoices: result.keeper_choices });
      }
      setMyChoice([]);
      load();
    } catch (e: any) {
      toast.error(e.message || "Erreur");
    } finally {
      setSubmitting(false);
    }
  }, [game, submitting, id, load]);

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
    if (submitting) return;
    if (myChoice.includes(zone)) {
      setMyChoice(myChoice.filter(z => z !== zone));
    } else if (myChoice.length < numZonesToPick) {
      setMyChoice([...myChoice, zone]);
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

  return (
    <div className="min-h-screen bg-gradient-to-b from-green-800 to-green-950 flex flex-col p-3 max-w-lg mx-auto text-white">
      <div className="flex items-center justify-between mb-3">
        <button onClick={() => navigate({ to: "/jeux" })} className="text-white/70 text-sm flex items-center gap-1">
          <ArrowLeft className="w-4 h-4" /> Quitter
        </button>
        <span className="text-sm font-semibold">
          {game.is_overtime ? "⚔️ Prolongations" : `⚽ Tir ${currentShotNum}/${game.num_balls}`}
        </span>
        <button onClick={handleForfeit} className="text-red-400 text-sm flex items-center gap-1">
          <Flag className="w-4 h-4" /> Abandonner
        </button>
      </div>

      <div className="flex items-center justify-between px-4 py-3 rounded-2xl bg-white/10 mb-3">
        <div className="flex items-center gap-2">
          <div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center text-lg font-bold overflow-hidden">
            {myAvatar ? <img src={myAvatar} className="w-full h-full rounded-full object-cover" /> : myName[0]}
          </div>
          <div>
            <p className="text-sm font-semibold">{myName}</p>
            <p className="text-xs text-white/60">{myScore} but{myScore > 1 ? "s" : ""}</p>
          </div>
        </div>
        <div className="text-3xl font-black">
          {isPlayer1 ? `${game.p1_score} - ${game.p2_score}` : `${game.p2_score} - ${game.p1_score}`}
        </div>
        <div className="flex items-center gap-2">
          <div>
            <p className="text-sm font-semibold text-right">{oppName}</p>
            <p className="text-xs text-white/60 text-right">{oppScore} but{oppScore > 1 ? "s" : ""}</p>
          </div>
          <div className="w-10 h-10 rounded-full bg-white/20 flex items-center justify-center text-lg font-bold overflow-hidden">
            {oppAvatar ? <img src={oppAvatar} className="w-full h-full rounded-full object-cover" /> : (oppName?.[0] || "?")}
          </div>
        </div>
      </div>

      {currentRound && !currentRound.resolved_at && (amShooter || amKeeper) && (
        <div className="flex items-center justify-center gap-2 mb-3">
          <Clock className={`w-5 h-5 ${timeLeft <= 10 ? "text-red-400" : "text-white/60"}`} />
          <span className={`text-lg font-bold ${timeLeft <= 10 ? "text-red-400" : "text-white"}`}>{timeLeft}s</span>
        </div>
      )}

      {amShooter && currentRound && !currentRound.resolved_at && (
        <p className="text-center text-sm text-yellow-300 font-semibold mb-2">🎯 Tu tires ! Choisis 1 zone</p>
      )}
      {amKeeper && currentRound && !currentRound.resolved_at && (
        <p className="text-center text-sm text-blue-300 font-semibold mb-2">🧤 Tu gardiens ! Choisis {game.num_keeper_choices} zone{game.num_keeper_choices > 1 ? "s" : ""}</p>
      )}
      {isSpectator && game.status === "playing" && (
        <p className="text-center text-sm text-white/50 mb-2">👀 Spectateur</p>
      )}
      {currentRound?.resolved_at && (
        <p className="text-center text-sm text-white/50 mb-2">En attente du tour suivant...</p>
      )}

      <div className="relative flex-1 flex flex-col items-center justify-center">
        <div className="relative w-full max-w-sm">
          <div className="h-3 bg-white/80 rounded-t-lg mx-2" />
          <div className="grid grid-cols-3 grid-rows-2 gap-0.5 bg-white/20 p-1 rounded-b-lg" style={{ minHeight: "180px" }}>
            {[1,2,3,4,5,6].map(zone => {
              const isSelected = myChoice.includes(zone);
              const isResolved = resolveAnim != null;
              const isShooterZone = resolveAnim?.shooterChoice === zone;
              const isKeeperZone = resolveAnim?.keeperChoices?.includes(zone);
              const wasGoal = resolveAnim?.result === "goal";
              return (
                <button key={zone} onClick={() => toggleZone(zone)}
                  disabled={submitting || isSpectator || (currentRound?.resolved_at && !resolveAnim)}
                  className={`relative flex items-center justify-center text-sm font-bold transition-all
                    ${isSelected ? (amShooter ? "bg-yellow-400 text-black" : "bg-blue-400 text-black") : "bg-green-700/50 hover:bg-green-600/50"}
                    ${isShooterZone && isResolved ? "ring-2 ring-yellow-400" : ""}
                    ${isKeeperZone && isResolved ? "ring-2 ring-blue-400" : ""}
                    ${isShooterZone && isResolved && wasGoal ? "bg-green-500" : ""}
                    ${isShooterZone && isResolved && !wasGoal ? "bg-red-500/60" : ""}
                  `}>
                  {isShooterZone && isResolved && (wasGoal ? "⚽" : "🧤")}
                  {!isShooterZone && !isResolved && ZONE_SHORT[zone]}
                  {isKeeperZone && !isShooterZone && isResolved && "🧤"}
                </button>
              );
            })}
          </div>
          <div className="absolute inset-0 pointer-events-none opacity-20"
            style={{ backgroundImage: "repeating-linear-gradient(45deg, transparent, transparent 8px, rgba(255,255,255,0.1) 8px, rgba(255,255,255,0.1) 9px)" }} />
        </div>

        {resolveAnim && (
          <div className="mt-4 text-center animate-pulse">
            {resolveAnim.result === "goal" ? (
              <p className="text-3xl font-black text-yellow-400">⚽ BUT !</p>
            ) : (
              <p className="text-3xl font-black text-blue-400">🧤 ARRÊT !</p>
            )}
            <p className="text-xs text-white/60 mt-1">
              Tireur: {ZONE_LABELS[resolveAnim.shooterChoice]} · Gardien: {resolveAnim.keeperChoices.map(z => ZONE_SHORT[z]).join(", ")}
            </p>
          </div>
        )}
      </div>

      {(amShooter || amKeeper) && currentRound && !currentRound.resolved_at && (
        <button onClick={() => handleSubmit(myChoice)} disabled={myChoice.length !== numZonesToPick || submitting}
          className="w-full py-3.5 rounded-full bg-emerald-500 text-white font-bold text-sm disabled:opacity-40 mt-3">
          {submitting ? "..." : myChoice.length === numZonesToPick ? "Valider ✓" : `Choisis ${numZonesToPick - myChoice.length} zone${numZonesToPick - myChoice.length > 1 ? "s" : ""}`}
        </button>
      )}

      <div className="mt-3 flex flex-wrap gap-1 justify-center">
        {rounds.filter(r => r.resolved_at).map((r) => (
          <div key={r.id} className={`px-2 py-1 rounded text-xs font-bold ${r.result === "goal" ? "bg-emerald-500/30 text-emerald-300" : "bg-blue-500/30 text-blue-300"}`}>
            {r.result === "goal" ? "⚽" : "🧤"} {ZONE_SHORT[r.shooter_choice ?? 0]}
          </div>
        ))}
      </div>
    </div>
  );
}

export default PenaltyGame;
