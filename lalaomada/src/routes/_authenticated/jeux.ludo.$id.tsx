import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { copyText } from "@/lib/clipboard";
import RealtimeLudoBoard from "@/components/game/RealtimeLudoBoard";
import GamePauseControl from "@/components/game/GamePauseControl";
import { toast } from "sonner";
import { LogOut, Eye, Plus, Pause, Volume2, VolumeX, ShieldAlert } from "lucide-react";
import { setMuted as setSfxMuted, isMuted as isSfxMuted } from "@/lib/game-sounds";
import { useT } from "@/lib/i18n";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import { GameLoader } from "@/components/game/GameLoader";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import GameSocialFab from "@/components/game/GameSocialFab";
import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";

export const Route = createFileRoute("/_authenticated/jeux/ludo/$id")({
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
  const [confirmQuit, setConfirmQuit] = useState(false);
  const [gameNumber, setGameNumber] = useState<string | null>(null);
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const [now, setNowTick] = useState(serverNow());
  const [loadError, setLoadError] = useState(false);
  const [loadRetried, setLoadRetried] = useState(0);

  const { game, parts, setGame, setParts, loading, connected, reload, optTurnRef } = useFastRealtime({
    gameTable: "ludo_games",
    participantTable: "ludo_participants",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile,
  });

  // Keep loadError in sync for the retry UI

  // Fetch game number from game_registrations
  useEffect(() => {
    if (!id) return;
    supabase.from("game_registrations")
      .select("game_number")
      .eq("game_id", id)
      .maybeSingle()
      .then(({ data }: any) => {
        if (data?.game_number) {
          setGameNumber('#' + String(data.game_number).padStart(8, '0'));
        }
      });
  }, [id]);

  useEffect(() => {
    if (loading && !game) setLoadError(false);
    else if (!loading && !game) setLoadError(true);
    else setLoadError(false);
  }, [loading, game]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: reload });

  // Retry load when profile becomes available (auth session restored)
  useEffect(() => {
    if (profile?.id && (!game || loadError)) {
      reload();
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [profile?.id]);

  useEffect(() => {
    if (!profile?.id) return;
    const beat = () => { supabase.rpc("ludo_heartbeat" as any, { _game_id: id } as any); };
    beat();
    const timer = setInterval(beat, 15000);
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
    if (error) { toast.error(error.message); return; }
    toast.success(t("left_game"));
    refreshProfile();
    navigate({ to: "/jeux" });
  };

  const addBot = async () => {
    if (isAdmin) {
      const name = prompt("Nom du bot:", "BotMax"); if (!name) return;
      const intel = Number(prompt("Intelligence (0-100):", "70")) || 70;
      const { error } = await supabase.rpc("admin_add_bot" as any, { _game_id: id, _bot_name: name, _intelligence: intel } as any);
      if (error) toast.error(error.message);
      else toast.success(t("bot_added"));
      return;
    }
    const { error } = await supabase.rpc("player_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
    if (error) toast.error(error.message);
    else toast.success(t("bot_added"));
  };

  if (!game) {
    if (loadError) {
      return <GameLoader retryFn={() => { setLoadError(false); setLoadRetried(r => r + 1); }} />;
    }
    return <GameLoader />;
  }

  if (game.status === "open") {
    if (Number(game.stake) > 0 && profile?.phone_verified !== true) {
      return (
        <main className="max-w-md mx-auto px-4 py-8 flex flex-col items-center justify-center gap-3 text-center">
          <ShieldAlert className="w-10 h-10 text-amber-500" />
          <p className="text-sm font-semibold">Numéro non vérifié</p>
          <p className="text-xs text-muted-foreground">Vérifiez votre numéro de téléphone pour rejoindre cette partie payante.</p>
          <button onClick={() => navigate({ to: "/securite" })} className="px-4 py-2 rounded-full bg-primary text-primary-foreground text-xs font-semibold">Vérifier mon numéro</button>
        </main>
      );
    }
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="ludo"
          gameLabel={`Ludo · ${game.max_players} joueurs · ${game.match_type === "groupe" ? "2v2 Groupe" : "Solo"}`}
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
                team: p.team,
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
          gameStatus={game.status}
          gameId={id}
          onQuit={quit}
          onToggleReady={async (ready): Promise<void> => {
            const { error } = await supabase.rpc("ludo_set_ready" as any, { _game_id: id, _ready: ready } as any);
            if (error) { void toast.error(error.message); }
          }}
          matchType={game.match_type === "groupe" ? "groupe" : "solo"}
          onJoinTeam={async (team) => {
            const { error } = await supabase.rpc("ludo_join_team" as any, { _game_id: id, _team: team } as any);
            if (error) toast.error(error.message);
            else toast.success(team === 1 ? "Groupe 1 rejoint !" : "Groupe 2 rejoint !");
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

  if (game.status === "cancelled") {
    return <GameStateMessage state="cancelled" gameLabel="Ludo" slug="ludo" />;
  }

  if (game.status === "finished") {
    return (
      <main className="max-w-3xl mx-auto px-4 py-10">
        <GameEndScreen slug="ludo" meUserId={profile?.id} winnerId={game.winner_id}
          participants={parts as any} stake={Number(game.stake)} pot={Number(game.pot)}
          commissionPct={Number(game.commission_pct) || 10}
          onReplay={async () => {
            const stake = Number(game.stake) || 0;
            const maxP = Number(game.max_players) || 2;
            const mode = game.mode === "fast" ? "fast" : "classic";
            const hadBots = parts.some((p: any) => p.is_bot);
            if (hadBots) {
              // Recreate a solo bot game (with stake)
              const { data, error } = await supabase.rpc("ludo_start_solo_bot" as any, {
                _max_players: maxP, _stake: stake, _mode: mode, _match_type: "solo",
              } as any);
              if (error) { (await import("sonner")).toast.error(error.message); return; }
              refreshProfile();
              navigate({ to: "/jeux/ludo/$id", params: { id: data as string } });
            } else {
              const fn = game.is_private ? "create_private_game" : "create_public_game";
              const origMatchType = game.match_type === "solo" ? "solo" : "groupe"; const args: any = { _max_players: maxP, _stake: stake, _mode: mode, _match_type: origMatchType };
              const { data, error } = await supabase.rpc(fn as any, args);
              if (error) { (await import("sonner")).toast.error(error.message); return; }
              refreshProfile();
              navigate({ to: "/jeux/ludo/$id", params: { id: data as string } });
            }
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
    <main className="max-w-5xl mx-auto px-3 py-1 h-full overflow-hidden overscroll-none">
      <PhoneVerifyBanner stake={Number(game?.stake) || 0} phoneVerified={profile?.phone_verified === true} />
      <h1 className="sr-only">Partie de Ludo en cours</h1>
      <div className="rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5">
        <div className="flex items-baseline gap-1 min-w-0">
          <span className="text-[8px] uppercase text-muted-foreground tracking-wider">{t("prize_winner")}</span>
          <span className="text-xs font-extrabold truncate">{payout.toLocaleString("fr-FR")} Ar</span>
          {gameNumber && <span className="text-[10px] font-mono font-bold text-primary/80 ml-1">{gameNumber}</span>}
        </div>
        {isSpectator ? (
          <div className="px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1">
            <Eye className="w-3 h-3" /> {t("spectator_lbl")}
          </div>
        ) : (
          <div className="flex items-center gap-1">
            {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
              <button
                onClick={async () => {
                  const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "ludo", _game_id: id } as any);
                  if (error) toast.error(error.message);
                  else toast.success("Partie en pause");
                }}
                className="px-2 py-0.5 rounded-full bg-amber-500 text-white text-[10px] font-semibold flex items-center gap-0.5"
              >
                <Pause className="w-2.5 h-2.5" /> Pause
              </button>
            )}
            <button
              onClick={() => { const m = !soundOn; setSoundOn(m); setSfxMuted(m); }}
              className="w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition"
            >
              {soundOn ? <Volume2 className="w-3 h-3" /> : <VolumeX className="w-3 h-3" />}
            </button>
            <button onClick={() => setConfirmQuit(true)} className="px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5">
              <LogOut className="w-2.5 h-2.5" /> {t("quit_refunded")}
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
        matchType={game.match_type}
        onStateUpdate={(newState) => {
          setGame((g: any) => g ? { ...g, state: newState } : g);
        }}
      />

      <GameSocialFab gameId={id} gameSlug="ludo" participants={parts} />
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

      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
    </main>
  );
}

const colorBg: Record<string, string> = {
  red: "bg-red-500", green: "bg-green-500", yellow: "bg-yellow-400", blue: "bg-blue-500",
};
