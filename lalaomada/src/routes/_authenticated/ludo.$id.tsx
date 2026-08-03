import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { copyText } from "@/lib/clipboard";
import RealtimeLudoBoard from "@/components/RealtimeLudoBoard";
import { Component, ReactNode } from "react";

class BoardErrorBoundary extends Component<{ children: ReactNode }, { hasError: boolean; error?: Error }> {
  constructor(props: any) {
    super(props);
    this.state = { hasError: false };
  }
  static getDerivedStateFromError(error: Error) {
    return { hasError: true, error };
  }
  componentDidCatch(error: Error) {
    console.error("LudoBoard crash:", error);
  }
  render() {
    if (this.state.hasError) {
      return (
        <div className="flex flex-col items-center justify-center gap-4 p-8 text-center max-w-lg mx-auto">
          <p className="text-sm text-muted-foreground">Le plateau a rencontré une erreur.</p>
          <pre className="text-xs text-left text-red-500 bg-red-50 dark:bg-red-950/30 p-3 rounded-lg overflow-auto max-h-48 w-full whitespace-pre-wrap break-all">
            {this.state.error?.message || "Erreur inconnue"}
            {"\n\n"}
            {this.state.error?.stack?.split("\n").slice(0, 5).join("\n")}
          </pre>
          <button onClick={() => this.setState({ hasError: false, error: undefined })} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold">
            Réessayer
          </button>
        </div>
      );
    }
    return this.props.children;
  }
}
import GamePauseControl from "@/components/GamePauseControl";
import { toast } from "sonner";
import { LogOut, Eye, Plus, Pause } from "lucide-react";
import { useT } from "@/lib/i18n";
import GameEndScreen from "@/components/GameEndScreen";
import GameWaitingRoom from "@/components/GameWaitingRoom";
import VictoryOverlay from "@/components/VictoryOverlay";

export const Route = createFileRoute("/_authenticated/ludo/$id")({
  component: GamePage,
  head: () => ({ meta: [
    { title: "Partie en cours — Lalao MADA" },
    { name: "description", content: "Plateau de jeu Lalao MADA en temps réel : lancez les dés, capturez les pions adverses et remportez la cagnotte." },
    { name: "robots", content: "noindex" },
  ] }),
});

function GamePage() {
  const { id } = Route.useParams();
  const { profile, isAdmin, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const { t } = useT();
  const [game, setGame] = useState<any>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [confirmQuit, setConfirmQuit] = useState(false);
  const [showVictory, setShowVictory] = useState(false);
  const [now, setNowTick] = useState(serverNow());

  const load = async () => {
    const { data: g } = await supabase.from("ludo_games").select("*").eq("id", id).maybeSingle();
    const { data: p } = await supabase.from("ludo_participants").select("*").eq("game_id", id).order("slot");
    setGame(g); setParts(p || []);
    if (g?.status === "finished") { refreshProfile(); setShowVictory(true); }
  };

  useEffect(() => {
    load();
    const ch = supabase.channel("game-" + id)
      .on("postgres_changes", { event: "*", schema: "public", table: "ludo_games", filter: `id=eq.${id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "ludo_participants", filter: `game_id=eq.${id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id]);

  useEffect(() => {
    if (!profile?.id) return;
    const beat = () => { supabase.rpc("ludo_heartbeat" as any, { _game_id: id } as any); };
    beat();
    const timer = setInterval(beat, 10000);
    return () => clearInterval(timer);
  }, [id, profile?.id]);

  useEffect(() => {
    const timer = setInterval(() => setNowTick(serverNow()), 1000);
    return () => clearInterval(timer);
  }, []);

  const myPart = parts.find(p => p.user_id === profile?.id);
  const isParticipant = !!myPart;
  const isSpectator = !isParticipant;

  const quit = async () => {
    const { error } = await supabase.rpc("ludo_quit" as any, { _game_id: id } as any);
    if (error) return toast.error(error.message);
    toast.success(t("left_game"));
    refreshProfile();
    navigate({ to: "/jeux" });
  };

  const addBot = async () => {
    if (isAdmin) {
      const name = prompt("Nom du bot:", "BotMax"); if (!name) return;
      const intel = Number(prompt("Intelligence (0-100):", "70")) || 70;
      const bias = Number(prompt("Biais de gain (0-100, 0 = équitable):", "0")) || 0;
      const { error } = await supabase.rpc("admin_add_bot" as any, { _game_id: id, _bot_name: name, _intelligence: intel, _win_bias: bias } as any);
      if (error) toast.error(error.message);
      else toast.success(t("bot_added"));
      return;
    }
    const { error } = await supabase.rpc("player_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
    if (error) toast.error(error.message);
    else toast.success(t("bot_added"));
  };

  if (!game) return <main className="p-8 text-center text-muted-foreground">{t("loading")}</main>;

  if (game.status === "open") {
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="ludo"
          gameLabel={`Ludo · ${game.max_players} joueurs · ${game.mode === "fast" ? "vs AMIES" : "vs BOT"}`}
          parts={(() => {
            const bots = parts.filter((p: any) => p.is_bot).sort((a: any, b: any) => a.slot - b.slot);
            const botIndex = new Map<string, number>();
            bots.forEach((b: any, i: number) => botIndex.set(b.id, i + 1));
            return parts.map((p: any) => {
              const idx = botIndex.get(p.id);
              return {
                user_id: p.user_id,
                display_name: p.is_bot ? `Joueur ${idx}` : p.display_name,
                slot: p.slot,
                ready: p.is_bot ? true : p.ready,
                avatar_url: p.is_bot ? `https://api.dicebear.com/7.x/adventurer/svg?seed=joueur${idx || 1}` : undefined,
              };
            });
          })()}
          maxPlayers={game.max_players}
          stake={Number(game.stake)}
          pot={Number(game.pot)}
          roomCode={game.is_private ? game.room_code : null}
          shareSlug="ludo"
          meUserId={profile?.id}
          isParticipant={isParticipant}
          createdAt={game.created_at}
          onQuit={quit}
          onToggleReady={async (ready) => {
            const { error } = await supabase.rpc("ludo_set_ready" as any, { _game_id: id, _ready: ready } as any);
            if (error) toast.error(error.message);
          }}
        />
        {!game.is_private && (isAdmin || (Number(game.stake) === 0 && isParticipant)) && parts.length < game.max_players && (
          <button onClick={addBot} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2">
            <Plus className="w-4 h-4" /> {t("add_bot")}
          </button>
        )}
      </main>
    );
  }

  if (game.status === "finished") {
    return (
      <main className="max-w-3xl mx-auto px-4 py-10">
        {showVictory && (() => {
          const winner = parts.find((p: any) => p.user_id === game.winner_id);
          return <VictoryOverlay
            winnerName={winner?.display_name || "Joueur"}
            isMe={game.winner_id === profile?.id}
            onClose={() => setShowVictory(false)}
          />;
        })()}
        <GameEndScreen slug="ludo" meUserId={profile?.id} winnerId={game.winner_id}
          participants={parts as any} stake={Number(game.stake)} pot={Number(game.pot)}
          commissionPct={Number(game.commission_pct) || 10}
          onReplay={async () => {
            // Rematch: invite same players + bots
            const { data: rematchId, error: rematchErr } = await supabase.rpc("ludo_rematch" as any, { _old_game_id: id } as any);
            if (rematchErr) {
              // Fallback: create a new game with same config
              const stake = Number(game.stake) || 0;
              const maxP = Number(game.max_players) || 2;
              const mode = game.mode === "fast" ? "fast" : "classic";
              const fn = game.is_private ? "create_private_game" : "create_public_game";
              const args: any = { _max_players: maxP, _stake: stake, _mode: mode };
              const { data, error } = await supabase.rpc(fn as any, args);
              if (error) { (await import("sonner")).toast.error(error.message); return; }
              navigate({ to: "/ludo/$id", params: { id: data as string } });
              return;
            }
            // Auto-join the rematch if not already a participant
            if (game.winner_id !== profile?.id && !parts.some((p: any) => p.user_id === profile?.id)) {
              // We're not in the original game, skip
            }
            (await import("sonner")).toast.success("Revanche créée ! Mêmes joueurs recrutés.");
            navigate({ to: "/ludo/$id", params: { id: rematchId as string } });
          }} />
      </main>
    );
  }

  const state = game.state || { pawns: {}, turn_slot: 0, dice: null, must_move: false, turn_started_at: new Date().toISOString() };
  const payout = Math.round(Number(game.pot) * (100 - Number(game.commission_pct)) / 100);
  const disconnectUntil = game.disconnect_until || {};
  const pausedSlots: { slot: number; remaining: number; name: string }[] = Object.entries(disconnectUntil)
    .map(([slot, ts]) => {
      const until = new Date(ts as string).getTime();
      const rem = Math.max(0, Math.floor((until - now) / 1000));
      const p = parts.find(pp => pp.slot === Number(slot));
      return { slot: Number(slot), remaining: rem, name: p?.display_name || `Slot ${slot}` };
    }).filter(p => p.remaining > 0);

  return (
    <main className="max-w-5xl mx-auto px-3 py-3">
      <h1 className="sr-only">Partie de Ludo en cours</h1>
      <div className="rounded-full bg-card px-3 py-1.5 mb-2 shadow-[var(--shadow-soft)] flex items-center justify-between gap-2">
        <div className="flex items-baseline gap-1.5 min-w-0">
          <span className="text-[9px] uppercase text-muted-foreground tracking-wider">{t("prize_winner")}</span>
          <span className="text-sm font-extrabold truncate">{payout.toLocaleString("fr-FR")} Ar</span>
        </div>
        {isSpectator ? (
          <div className="px-2.5 py-1 rounded-full bg-secondary text-[11px] font-semibold flex items-center gap-1">
            <Eye className="w-3.5 h-3.5" /> {t("spectator_lbl")}
          </div>
        ) : (
          <div className="flex items-center gap-1.5">
            {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
              <button
                onClick={async () => {
                  const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "ludo", _game_id: id } as any);
                  if (error) toast.error(error.message);
                  else toast.success("Partie en pause");
                }}
                className="px-2.5 py-1 rounded-full bg-amber-500 text-white text-[11px] font-semibold flex items-center gap-1"
              >
                <Pause className="w-3 h-3" /> Pause
              </button>
            )}
            <button onClick={() => setConfirmQuit(true)} className="px-2.5 py-1 rounded-full bg-destructive text-white text-[11px] font-semibold flex items-center gap-1">
              <LogOut className="w-3 h-3" /> {t("quit_refunded")}
            </button>
          </div>
        )}
      </div>

      {pausedSlots.length > 0 && (
        <div className="rounded-2xl bg-amber-50 border border-amber-200 p-3 mb-3 text-sm text-amber-900">
          {pausedSlots.map(p => (
            <div key={p.slot}>⏸ <b>{p.name}</b> {t("is_paused_msg")} {Math.floor(p.remaining/60)}:{String(p.remaining%60).padStart(2,"0")}</div>
          ))}
        </div>
      )}

      <BoardErrorBoundary>
      <RealtimeLudoBoard
        gameId={id}
        state={state}
        participants={parts}
        myUserId={profile?.id || null}
        isSpectator={isSpectator}
        status={game.status}
        isAdmin={isAdmin}
        paused={game?.paused ?? false}
        pauseDeadline={game?.pause_deadline ?? null}
        afkWarning={game?.afk_warning ?? null}
        afkPauseFor={game?.afk_pause_for ?? null}
      />
      </BoardErrorBoundary>

      {confirmQuit && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4" onClick={() => setConfirmQuit(false)}>
          <div className="bg-card rounded-3xl p-6 max-w-md w-full space-y-4" onClick={e => e.stopPropagation()}>
            <h2 className="text-xl font-extrabold">{t("quit_game_title_key")}</h2>
            <p className="text-sm text-muted-foreground">
              {t("quit_game_desc_key")} <b>{Number(game.stake).toLocaleString("fr-FR")} Ar</b>.
            </p>
            <div className="flex gap-2 justify-end">
              <button onClick={() => setConfirmQuit(false)} className="px-4 py-2 rounded-full bg-secondary font-semibold">{t("cancel")}</button>
              <button onClick={quit} className="px-4 py-2 rounded-full bg-destructive text-white font-semibold">{t("confirm_quit")}</button>
            </div>
          </div>
        </div>
      )}
    </main>
  );
}

const colorBg: Record<string, string> = {
  red: "bg-red-500", green: "bg-green-500", yellow: "bg-yellow-400", blue: "bg-blue-500",
};
