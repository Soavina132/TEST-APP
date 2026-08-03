import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState, useCallback, useMemo } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { useGameConnection } from "@/hooks/use-game-connection";
import { GameReconnectOverlay } from "@/components/GameReconnectOverlay";
import { LogOut, Copy, Timer, RotateCw, SkipForward, Plus } from "lucide-react";
import GameChatDrawer from "@/components/GameChatDrawer";
import GamePauseControl from "@/components/GamePauseControl";
import GameInstructionsBanner from "@/components/GameInstructionsBanner";
import GameEndScreen from "@/components/GameEndScreen";
import GameWaitingRoom from "@/components/GameWaitingRoom";
import GameBoardSkin from "@/components/GameBoardSkin";

import { useGameConfig } from "@/hooks/use-game-config";
import { useGlobalGameTimer } from "@/hooks/use-global-game-timer";
import TurnBanner from "@/components/TurnBanner";
import { useConfirm } from "@/components/ConfirmDialog";
import fanoronaCover from "@/assets/games/fanorona.asset.json";

export const Route = createFileRoute("/_authenticated/fanorona/$id")({
  component: FanoronaPage,
  head: () => ({ meta: [{ title: "Fanorona — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

const isStrong = (r: number, c: number) => (r + c) % 2 === 0;
const DIRS_ORTHO = [[-1,0],[1,0],[0,-1],[0,1]];
const DIRS_DIAG = [[-1,-1],[-1,1],[1,-1],[1,1]];

function makeHelpers(COLS: number, ROWS: number) {
  const idx = (r: number, c: number) => r * COLS + c;
  const inBounds = (r: number, c: number) => r >= 0 && r < ROWS && c >= 0 && c < COLS;
  function neighbors(r: number, c: number): number[][] {
    const dirs = isStrong(r, c) ? [...DIRS_ORTHO, ...DIRS_DIAG] : DIRS_ORTHO;
    return dirs.filter(([dr, dc]) => inBounds(r+dr, c+dc));
  }
  function computeCaptures(board: number[], from: number, to: number, myColor: number) {
    const opp = myColor === 1 ? 2 : 1;
    const fr = Math.floor(from / COLS), fc = from % COLS;
    const tr = Math.floor(to / COLS),   tc = to % COLS;
    const dr = tr - fr, dc = tc - fc;
    const approach: number[] = [];
    let r = tr + dr, c = tc + dc;
    while (inBounds(r, c) && board[idx(r, c)] === opp) { approach.push(idx(r, c)); r += dr; c += dc; }
    const withdrawal: number[] = [];
    r = fr - dr; c = fc - dc;
    while (inBounds(r, c) && board[idx(r, c)] === opp) { withdrawal.push(idx(r, c)); r -= dr; c -= dc; }
    return { approach, withdrawal };
  }
  return { idx, inBounds, neighbors, computeCaptures };
}

function FanoronaPage() {
  const { id } = Route.useParams();
  const { profile, isAdmin } = useAuth();
  const navigate = useNavigate();
  const [game, setGame] = useState<any>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [loaded, setLoaded] = useState(false);
  const [selected, setSelected] = useState<number | null>(null);
  const [captureChoice, setCaptureChoice] = useState<{ from: number; to: number; approach: number[]; withdrawal: number[] } | null>(null);
  const [busy, setBusy] = useState(false);
  const [rotated90, setRotated90] = useState(false);

  const load = useCallback(async () => {
    const { data: g, error } = await supabase.from("fanorona_games" as any).select("*").eq("id", id).maybeSingle();
    if (error) setLoadError(error.message);
    else if (!g) setLoadError("Partie introuvable ou accès refusé.");
    else setLoadError(null);
    setGame(g);
    const { data: p } = await supabase.from("fanorona_participants" as any).select("*").eq("game_id", id).order("slot");
    setParts((p as any[]) || []);
    setLoaded(true);
  }, [id]);

  useEffect(() => {
    load();
    const ch = supabase.channel("fanorona-"+id)
      .on("postgres_changes", { event: "*", schema: "public", table: "fanorona_games", filter: `id=eq.${id}` }, () => load())
      .on("postgres_changes", { event: "*", schema: "public", table: "fanorona_participants", filter: `game_id=eq.${id}` }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });

  useEffect(() => {
    if (game?.status === "cancelled") {
      toast.info("Invitation expirée — mise remboursée");
      const t = setTimeout(() => navigate({ to: "/jeux/$slug", params: { slug: "fanorona" }, search: {} }), 1500);
      return () => clearTimeout(t);
    }
  }, [game?.status, navigate]);

  const COLS: number = (game?.cols as number) || 9;
  const ROWS: number = (game?.rows as number) || 5;
  const { idx, neighbors, computeCaptures } = useMemo(() => makeHelpers(COLS, ROWS), [COLS, ROWS]);

  const me = parts.find(p => p.user_id === profile?.id);
  const isPlayer = !!me;
  const myColor = me?.color === "white" ? 1 : me?.color === "black" ? 2 : 0;
  const isMyTurn = game && me && game.current_turn === me.slot && game.status === "playing";
  const board: number[] = useMemo(() => (game?.state?.board as number[]) || Array(ROWS*COLS).fill(0), [game, ROWS, COLS]);
  const chainFrom: number | null = game?.state?.chain_from ?? null;
  const mandatoryCapture: boolean = game?.mandatory_capture !== false;

  const cfg = useGameConfig("fanorona");
  const flipped = me?.color === "black";
  const [remaining, setRemaining] = useState(cfg.turn_timer_seconds);
  useEffect(() => {
    if (!game?.turn_deadline || game.status !== "playing") { setRemaining(cfg.turn_timer_seconds); return; }
    let fired = false;
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      const s = Math.max(0, Math.ceil(ms / 1000));
      setRemaining(s);
      if (s === 0 && !fired) {
        fired = true;
        supabase.rpc("fanorona_tick" as any, { _game_id: id } as any);
      }
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, id, cfg.turn_timer_seconds]);

  const globalTimer = useGlobalGameTimer({ game: "fanorona", gameId: id, status: game?.status, deadline: game?.game_deadline });

  const sendMove = async (move: any) => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc("fanorona_play" as any, { _game_id: id, _move: move } as any);
      if (error) throw error;
      setSelected(null); setCaptureChoice(null);
    } catch (e: any) { toast.error(e.message || "Coup invalide"); }
    finally { setBusy(false); }
  };
  const endTurn = () => sendMove({ pass: true });

  const onCellClick = (cell: number) => {
    if (!isMyTurn || busy) return;
    const effectiveSelected = chainFrom !== null ? chainFrom : selected;

    if (effectiveSelected === null) {
      if (board[cell] === myColor) setSelected(cell);
      return;
    }
    if (cell === effectiveSelected) { if (chainFrom === null) setSelected(null); return; }
    if (board[cell] === myColor && chainFrom === null) { setSelected(cell); return; }

    const fr = Math.floor(effectiveSelected / COLS), fc = effectiveSelected % COLS;
    const tr = Math.floor(cell / COLS), tc = cell % COLS;
    const dr = tr - fr, dc = tc - fc;
    if (Math.abs(dr) > 1 || Math.abs(dc) > 1 || (dr===0 && dc===0)) { toast.error("Mouvement invalide"); return; }
    if (dr !== 0 && dc !== 0 && !isStrong(fr, fc)) { toast.error("Diagonale interdite ici"); return; }
    if (board[cell] !== 0) { toast.error("Case occupée"); return; }

    const { approach, withdrawal } = computeCaptures(board, effectiveSelected, cell, myColor);
    if (approach.length > 0 && withdrawal.length > 0) {
      setCaptureChoice({ from: effectiveSelected, to: cell, approach, withdrawal });
      return;
    }
    const captured = approach.length > 0 ? approach : withdrawal;
    sendMove({ from: effectiveSelected, to: cell, captured, chain: false });
  };

  const confirm = useConfirm();
  const forfeit = async () => {
    const stake = Number(game?.stake) || 0;
    if (game?.status !== "open") {
      const ok = await confirm({
        title: "Quitter la partie ?",
        description: stake > 0
          ? <>Si tu quittes, tu perdras automatiquement et ta mise sera définitivement perdue. <b>{stake.toLocaleString("fr-FR")} Ar</b>.</>
          : "Si tu quittes, tu perdras automatiquement la partie.",
        confirmLabel: "Confirmer quitter",
        destructive: true,
      });
      if (!ok) return;
    }
    await supabase.rpc("fanorona_forfeit" as any, { _game_id: id } as any);
    navigate({ to: "/jeux" });
  };

  if (!loaded) return <div className="p-6 text-center">Chargement…</div>;
  if (!game) return (
    <div className="p-6 text-center space-y-3">
      <div className="text-2xl">😕</div>
      <div className="font-bold">{loadError || "Partie introuvable"}</div>
      <button onClick={() => navigate({ to: "/jeux" })} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold">Retour aux jeux</button>
    </div>
  );

  const replayFanorona = async () => {
    const { data, error } = await supabase.rpc("fanorona_create" as any, {
      _stake: Number(game.stake) || 0,
      _private: !!game.is_private,
      _commission: Number(game.commission_pct) || 10,
      _variant: game.variant || "tsivy",
      _mandatory_capture: game.mandatory_capture !== false,
    } as any);
    if (error) { toast.error(error.message); return; }
    navigate({ to: "/fanorona/$id", params: { id: data as string } });
  };

  if (game.status === "open") {
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="fanorona"
          gameLabel="Fanorona · 2 joueurs"
          parts={parts}
          maxPlayers={2}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          roomCode={game.is_private ? game.room_code : null}
          shareSlug="fanorona"
          meUserId={profile?.id}
          isParticipant={!!me}
          createdAt={game.created_at}
          onQuit={forfeit}
          onToggleReady={async (ready) => {
            const { error } = await supabase.rpc("fanorona_set_ready" as any, { _game_id: id, _ready: ready } as any);
            if (error) toast.error(error.message);
          }}
        />
        {((isAdmin || (Number(game.stake) === 0 && !!me)) && parts.length < 2) && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("fanorona_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
              if (error) toast.error(error.message); else toast.success("Bot ajouté");
            }}
            className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2"
          >
            <Plus className="w-4 h-4" /> Ajouter un bot
          </button>
        )}
        <GameChatDrawer gameId={id} />
      </main>
    );
  }

  // Board sizing — keep cells visually similar across variants.
  const CELL_PX = 40;
  const SIZE_W = (COLS - 1) * CELL_PX;
  const SIZE_H = (ROWS - 1) * CELL_PX;
  const cx = (c: number) => c * CELL_PX;
  const cy = (r: number) => r * CELL_PX;

  return (
    <main className="max-w-2xl mx-auto px-3 py-3 space-y-3 pb-6" style={{ background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.05) 0%, transparent 70%)" }}>
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      <GameInstructionsBanner slug="fanorona" />
      <div className="rounded-2xl bg-card border border-white/8 px-4 py-3 flex items-center gap-3 shadow-sm">
        <div className="w-10 h-10 rounded-xl bg-primary/10 border border-primary/20 flex items-center justify-center text-xl shrink-0">⚫</div>
        <div className="flex-1 min-w-0">
          <div className="font-extrabold text-base leading-tight">
            Fanorona · {game.variant === "telo" ? "Telo 3×3" : game.variant === "dimy" ? "Dimy 5×5" : "Tsivy 9×5"}
          </div>
          <div className="flex items-center gap-2 mt-0.5">
            {Number(game.pot) > 0 ? (
              <span className="flex items-baseline gap-1">
                <span className="text-[9px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
                <span className="font-extrabold text-[13px] text-emerald-500">
                  {Math.round(Number(game.pot) * (100 - (Number(game.commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar
                </span>
              </span>
            ) : (
              <span className="text-[11px] text-muted-foreground">Partie gratuite</span>
            )}
            <span className={`text-[10px] px-1.5 py-0.5 rounded-full ${mandatoryCapture ? "bg-amber-500/15 text-amber-500 border border-amber-500/20" : "bg-white/6 text-muted-foreground/60"}`}>
              {mandatoryCapture ? "⚠ Capture oblig." : "Libre"}
            </span>
          </div>
          {game.is_private && (
            <button onClick={() => { copyText(game.room_code).then(ok => toast[ok ? "success" : "error"](ok ? "Copié" : "Impossible de copier")); }}
              className="mt-1 flex items-center gap-1 text-[10px] font-mono text-muted-foreground/60 hover:text-foreground transition-colors">
              {game.room_code} <Copy className="w-2.5 h-2.5" />
            </button>
          )}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <button onClick={() => setRotated90(r => !r)}
            className="flex items-center gap-1 px-2.5 py-2 rounded-xl bg-white/6 hover:bg-white/10 text-muted-foreground text-xs font-semibold transition-all">
            <RotateCw className="w-3.5 h-3.5" /> {rotated90 ? "⇔" : "↕"}
          </button>
          {me ? (
            <button onClick={forfeit}
              className="flex items-center gap-1 px-2.5 py-2 rounded-xl bg-destructive/8 text-destructive hover:bg-destructive/15 text-xs font-semibold transition-all border border-destructive/15">
              <LogOut className="w-3.5 h-3.5" /> Quitter
            </button>
          ) : (
            <button onClick={() => navigate({ to: "/live" })}
              className="flex items-center gap-1 px-2.5 py-2 rounded-xl bg-secondary text-foreground hover:bg-secondary/80 text-xs font-semibold transition-all border border-white/10">
              <LogOut className="w-3.5 h-3.5" /> Sortir du live
            </button>
          )}
        </div>
      </div>

      {game.status === "playing" && (
        <TurnBanner
          isMyTurn={!!isMyTurn}
          opponentName={parts.find(p => p.slot !== me?.slot)?.display_name}
          globalTimerEnabled={globalTimer.enabled}
          globalTimerLabel={globalTimer.remainingLabel}
        />
      )}

      <div className="grid grid-cols-2 gap-2.5">
        {parts.map(p => {
          const isCurrent = game.current_turn === p.slot && game.status === "playing";
          const skips = Number(game.turn_skips?.[p.user_id] || 0);
          const isMe = p.user_id === profile?.id;
          const isWhite = p.color === "white";
          return (
            <div key={p.id} className={`relative rounded-2xl p-3 transition-all duration-300 border ${isCurrent ? "bg-primary/8 border-primary/35 shadow-lg shadow-primary/10" : "bg-card border-white/6"}`}>
              {isCurrent && <div className="absolute inset-0 rounded-2xl ring-2 ring-primary/50 animate-pulse pointer-events-none" />}
              <div className="flex items-center gap-2.5">
                <div className={`w-10 h-10 rounded-full shrink-0 flex items-center justify-center text-xl font-bold ring-2 ${
                  isWhite ? "bg-white text-gray-900 ring-white/30" : "bg-gray-900 text-white ring-white/10"
                } ${isCurrent ? "shadow-lg" : ""}`}>
                  {isWhite ? "⚪" : "⚫"}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="font-bold text-sm truncate leading-tight">
                    {p.display_name}
                    {isMe && <span className="ml-1 text-[10px] font-normal text-primary/60">(vous)</span>}
                  </div>
                  <div className={`text-[10px] font-semibold ${isWhite ? "text-white/60" : "text-muted-foreground"}`}>
                    {isWhite ? "Blancs" : "Noirs"} {p.forfeited && <span className="text-destructive ml-1">· Forfait</span>}
                  </div>
                </div>
                <div className="shrink-0 flex flex-col items-end gap-1">
                  {isCurrent && (
                    <div className={`flex items-center gap-1 text-xs font-bold px-2 py-0.5 rounded-full ${remaining <= 10 ? "bg-destructive text-white timer-urgent" : "bg-primary/15 text-primary"}`}>
                      <Timer className="w-3 h-3" /> {remaining}s
                    </div>
                  )}
                  {skips > 0 && <div className="text-[9px] text-amber-500">⚠ {skips} skip</div>}
                </div>
              </div>
            </div>
          );
        })}
        {parts.length < 2 && (
          <div className="rounded-2xl p-3 bg-card border-2 border-dashed border-white/10 text-center text-xs text-muted-foreground col-span-1">
            <div className="text-base mb-1">⏳</div> En attente adversaire…
          </div>
        )}
      </div>

      {game.status === "finished" && (
        <GameEndScreen slug="fanorona" meUserId={profile?.id} winnerId={game.winner_id}
          participants={parts} stake={Number(game.stake)} pot={Number(game.pot)}
          commissionPct={Number(game.commission_pct) || 10}
          onReplay={replayFanorona} />
      )}

      <GameBoardSkin coverUrl={fanoronaCover.url}>
      <div className={rotated90 ? "overflow-hidden mx-auto" : "overflow-x-auto"} style={rotated90 ? { width: "min(100%, 70vh)", aspectRatio: `${ROWS} / ${COLS}`, position: "relative" } : undefined}>
        <svg viewBox={`-24 -24 ${SIZE_W+48} ${SIZE_H+48}`} className={rotated90 ? "" : "w-full"} style={rotated90 ? {
          position: "absolute",
          width: `${(COLS / ROWS) * 100}%`,
          height: `${(ROWS / COLS) * 100}%`,
          top: "50%",
          left: "50%",
          transform: `translate(-50%, -50%) rotate(${flipped ? 270 : 90}deg)`,
          transformOrigin: "center",
        } : { maxWidth: 600, transform: flipped ? "rotate(180deg)" : undefined }}>
          <defs>
            <radialGradient id="wood-inner" cx="50%" cy="35%" r="80%">
              <stop offset="0%" stopColor="#d9a86a" />
              <stop offset="60%" stopColor="#a06b35" />
              <stop offset="100%" stopColor="#5e3618" />
            </radialGradient>
            <radialGradient id="white-stone" cx="35%" cy="30%" r="70%">
              <stop offset="0%" stopColor="#ffffff" />
              <stop offset="55%" stopColor="#ece4d2" />
              <stop offset="100%" stopColor="#8b806a" />
            </radialGradient>
            <radialGradient id="black-stone" cx="35%" cy="30%" r="70%">
              <stop offset="0%" stopColor="#5a5a5a" />
              <stop offset="50%" stopColor="#1d1d1d" />
              <stop offset="100%" stopColor="#000000" />
            </radialGradient>
            <filter id="stone-shadow" x="-50%" y="-50%" width="200%" height="200%">
              <feDropShadow dx="0" dy="2" stdDeviation="1.6" floodColor="#000" floodOpacity="0.55" />
            </filter>
          </defs>

          <rect x={-18} y={-18} width={SIZE_W+36} height={SIZE_H+36} rx={14} fill="url(#wood-inner)" />

          {Array.from({length: ROWS}).map((_, r) => Array.from({length: COLS}).map((_, c) => {
            const here = idx(r,c);
            return neighbors(r,c).map(([dr,dc]) => {
              const r2 = r+dr, c2 = c+dc;
              if (r2*COLS+c2 < here) return null;
              return (
                <g key={`${r}-${c}-${dr}-${dc}`}>
                  <line x1={cx(c)} y1={cy(r)+1} x2={cx(c2)} y2={cy(r2)+1} stroke="rgba(0,0,0,0.55)" strokeWidth={1.6} strokeLinecap="round" />
                  <line x1={cx(c)} y1={cy(r)} x2={cx(c2)} y2={cy(r2)} stroke="rgba(255,225,180,0.85)" strokeWidth={1} strokeLinecap="round" />
                </g>
              );
            });
          }))}

          {board.map((_, i) => {
            const r = Math.floor(i/COLS), c = i % COLS;
            return <circle key={`s-${i}`} cx={cx(c)} cy={cy(r)} r={4} fill="rgba(0,0,0,0.35)" />;
          })}

          {board.map((v, i) => {
            const r = Math.floor(i / COLS), c = i % COLS;
            const isSel = selected === i || chainFrom === i;
            const isMine = v === myColor;
            if (v === 0) {
              return (
                <circle
                  key={i}
                  cx={cx(c)} cy={cy(r)} r={14}
                  fill="transparent"
                  onClick={() => onCellClick(i)}
                  style={{ cursor: isMyTurn && selected !== null ? "pointer" : "default" }}
                />
              );
            }
            return (
              <g key={i} onClick={() => onCellClick(i)}
                 style={{ cursor: isMyTurn && (isMine || selected !== null || chainFrom !== null) ? "pointer" : "default" }}>
                {isSel && <circle cx={cx(c)} cy={cy(r)} r={15} fill="none" stroke="#22c55e" strokeWidth={2.5} opacity={0.9} />}
                <ellipse cx={cx(c)} cy={cy(r)+2} rx={11} ry={3.5} fill="rgba(0,0,0,0.45)" />
                <circle cx={cx(c)} cy={cy(r)} r={11.5} fill={v === 1 ? "url(#white-stone)" : "url(#black-stone)"} filter="url(#stone-shadow)" />
                <ellipse cx={cx(c)-3.5} cy={cy(r)-4} rx={3.5} ry={2} fill={v === 1 ? "rgba(255,255,255,0.85)" : "rgba(255,255,255,0.3)"} />
              </g>
            );
          })}
        </svg>
        <div className="text-xs text-center mt-3 font-medium" style={{ color: "rgba(255,225,190,0.9)" }}>
          {!me ? "Spectateur" :
            game.status !== "playing" ? "En attente du démarrage…" :
            isMyTurn ? (chainFrom !== null ? "Chaîne en cours — continue ou termine" : "À toi de jouer") : "Tour de l'adversaire"}
        </div>
        {isMyTurn && (
          <button onClick={endTurn}
            className="mt-3 w-full py-2.5 rounded-full bg-amber-100 text-amber-950 font-bold text-sm shadow-lg flex items-center justify-center gap-2">
            <SkipForward className="w-4 h-4" />
            {chainFrom !== null ? "Terminer mon tour" : "Passer mon tour"}
          </button>
        )}
      </div>
      </GameBoardSkin>

      {captureChoice && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center p-4 z-50" onClick={() => setCaptureChoice(null)}>
          <div className="bg-card rounded-3xl p-5 max-w-sm w-full space-y-3" onClick={e => e.stopPropagation()}>
            <div className="font-bold text-center">Choisir le type de capture</div>
            <button onClick={() => { sendMove({ from: captureChoice.from, to: captureChoice.to, captured: captureChoice.approach, chain: false }); }}
              className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold">
              Approche ({captureChoice.approach.length} pion{captureChoice.approach.length>1?"s":""})
            </button>
            <button onClick={() => { sendMove({ from: captureChoice.from, to: captureChoice.to, captured: captureChoice.withdrawal, chain: false }); }}
              className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold">
              Éloignement ({captureChoice.withdrawal.length} pion{captureChoice.withdrawal.length>1?"s":""})
            </button>
            <button onClick={() => setCaptureChoice(null)} className="w-full py-2 rounded-full bg-secondary text-sm">Annuler</button>
          </div>
        </div>
      )}
      <GamePauseControl
        slug="fanorona"
        gameId={id}
        game={game}
        remaining={remaining}
        totalSeconds={cfg.turn_timer_seconds}
        isMyTurn={!!isMyTurn}
        isPlayer={isPlayer}
        myUserId={profile?.id ?? null}
      />
      <GameChatDrawer gameId={id} />
    </main>

  );
}
