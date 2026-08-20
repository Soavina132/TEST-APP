import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";
import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";
import { LogOut, Plus, Ban, Volume2, VolumeX, ShieldAlert } from "lucide-react";
import GameSocialFab from "@/components/game/GameSocialFab";
import GamePauseControl from "@/components/game/GamePauseControl";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import DominoRoundBreak from "@/components/game/DominoRoundBreak";
import { DominoTile, PlayerHeader, DominoBoard, Tile } from "@/components/game/DominoTable";
import { useGameConfig } from "@/hooks/game/use-game-config";
import { useConfirm } from "@/components/ConfirmDialog";
import { useT } from "@/lib/i18n";
import { useDominoSounds } from "@/hooks/game/use-domino-sounds";
import { playClack, playDraw, playPass } from "@/lib/sounds/game-sounds";
import { setMuted as setSfxMuted, isMuted as isSfxMuted } from "@/lib/game-sounds";

export const Route = createFileRoute("/_authenticated/jeux/domino/$id")({
  component: DominoPage,
  head: () => ({ meta: [{ title: "Domino — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

// ── Board normalization (server stores tiles unordered, we reconstruct chain) ─
function readTile(e: unknown): Tile | null {
  const raw = Array.isArray(e) ? e : (e as { tile?: unknown })?.tile;
  if (!Array.isArray(raw) || raw.length !== 2) return null;
  const a = Number(raw[0]), b = Number(raw[1]);
  return Number.isFinite(a) && Number.isFinite(b) ? [a, b] : null;
}

function solveTrail(tiles: Tile[], start: number, end?: number): Tile[] | null {
  if (!tiles.length) return [];
  const adj = new Map<number, { to: number; idx: number }[]>();
  const deg = new Map<number, number>();
  tiles.forEach(([a, b], i) => {
    adj.set(a, [...(adj.get(a) ?? []), { to: b, idx: i }]);
    adj.set(b, [...(adj.get(b) ?? []), { to: a, idx: i }]);
    deg.set(a, (deg.get(a) ?? 0) + 1); deg.set(b, (deg.get(b) ?? 0) + 1);
  });
  if (!(deg.get(start) ?? 0)) return null;
  const seen = new Set<number>(); const st = [start];
  while (st.length) { const n = st.pop()!; if (seen.has(n)) continue; seen.add(n); (adj.get(n) ?? []).forEach(({ to }) => { if (!seen.has(to)) st.push(to); }); }
  if ([...deg.keys()].some(n => !seen.has(n))) return null;
  const odd = [...deg.entries()].filter(([, v]) => v % 2).map(([n]) => n);
  if (end !== undefined) {
    if (start === end ? odd.length !== 0 : odd.length !== 2 || !odd.includes(start) || !odd.includes(end)) return null;
  } else if (odd.length === 2 && !odd.includes(start)) return null;
  else if (odd.length && odd.length !== 2) return null;
  const used = new Set<number>(); const cursors = new Map<number, number>();
  const path: { from: number; to: number }[] = [];
  const stack: { node: number; edge?: { from: number; to: number } }[] = [{ node: start }];
  while (stack.length) {
    const top = stack[stack.length - 1]; const list = adj.get(top.node) ?? [];
    let c = cursors.get(top.node) ?? 0;
    while (c < list.length && used.has(list[c].idx)) c++;
    cursors.set(top.node, c); const nx = list[c];
    if (nx) { used.add(nx.idx); cursors.set(top.node, c + 1); stack.push({ node: nx.to, edge: { from: top.node, to: nx.to } }); }
    else { const d = stack.pop()!; if (d.edge) path.push(d.edge); }
  }
  path.reverse();
  if (path.length !== tiles.length) return null;
  if (end !== undefined && path.at(-1)?.to !== end) return null;
  return path.map(({ from, to }) => [from, to] as Tile);
}

function reverseTrail(t: Tile[]): Tile[] { return [...t].reverse().map(([a, b]) => [b, a] as Tile); }

function fallbackNorm(tiles: Tile[], expL?: number, expR?: number): Tile[] {
  const chain: Tile[] = []; let le: number | null = null, re: number | null = null;
  for (const [a, b] of tiles) {
    if (!chain.length) { const f: Tile = expL != null && b === expL && a !== expL ? [b, a] : [a, b]; chain.push(f); le = f[0]; re = f[1]; }
    else if (a === re) { chain.push([a, b]); re = b; }
    else if (b === re) { chain.push([b, a]); re = a; }
    else if (b === le) { chain.unshift([a, b]); le = a; }
    else if (a === le) { chain.unshift([b, a]); le = b; }
    else chain.push([a, b]);
  }
  if (expR != null && chain.at(-1)?.[1] !== expR) {
    const r = reverseTrail(chain);
    if ((expL == null || r[0]?.[0] === expL) && r.at(-1)?.[1] === expR) return r;
  }
  return chain;
}

function normalizeBoard(raw: any[], sL?: unknown, sR?: unknown) {
  if (!Array.isArray(raw) || !raw.length) return { board: [] as { tile: Tile; flipped: boolean }[], leftEnd: null as number | null, rightEnd: null as number | null };
  const expL = typeof sL === "number" ? sL : Number(sL);
  const expR = typeof sR === "number" ? sR : Number(sR);
  const hL = Number.isFinite(expL), hR = Number.isFinite(expR);
  const tiles = raw.map(readTile).filter((t): t is Tile => t !== null);
  if (!tiles.length) return { board: [] as { tile: Tile; flipped: boolean }[], leftEnd: null, rightEnd: null };
  let trail: Tile[] | null = null;
  if (hL) trail = solveTrail(tiles, expL, hR ? expR : undefined);
  if (!trail && hR) { const r = solveTrail(tiles, expR, hL ? expL : undefined); if (r) trail = reverseTrail(r); }
  if (!trail) {
    const deg = new Map<number, number>();
    tiles.forEach(([a, b]) => { deg.set(a, (deg.get(a) ?? 0) + 1); deg.set(b, (deg.get(b) ?? 0) + 1); });
    const starts = [...new Set([tiles[0][0], tiles[0][1], ...[...deg.entries()].filter(([, v]) => v % 2).map(([n]) => n), ...[...deg.keys()]])];
    for (const s of starts) { trail = solveTrail(tiles, s); if (trail) break; }
  }
  const norm = trail && trail.length === tiles.length ? trail : fallbackNorm(tiles, hL ? expL : undefined, hR ? expR : undefined);
  return { board: norm.map(tile => ({ tile, flipped: false })), leftEnd: norm[0]?.[0] ?? null, rightEnd: norm.at(-1)?.[1] ?? null };
}

// ── Component ───────────────────────────────────────────────────────────
function DominoPage() {
  const { t } = useT();
  const { id } = Route.useParams();
  const { profile, isAdmin } = useAuth();
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const navigate = useNavigate();
  const confirm = useConfirm();
  const [game, setGame] = useState<any>(null);
  const [gameNumber, setGameNumber] = useState<string | null>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [selectedTile, setSelectedTile] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const noMoveCh = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const [remoteNoMove, setRemoteNoMove] = useState<number | null>(null);
  const [handW, setHandW] = useState(190);


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
    const u = () => setHandW(Math.max(140, window.innerWidth - 170));
    u(); window.addEventListener("resize", u); window.addEventListener("orientationchange", u);
    return () => { window.removeEventListener("resize", u); window.removeEventListener("orientationchange", u); };
  }, []);

  // ── Load ──────────────────────────────────────────────────────────────
  const load = useCallback(async () => {
    const { data: g } = await supabase.from("domino_games" as any).select("*").eq("id", id).maybeSingle();
    setGame(g);
    const { data: p } = await supabase.from("domino_participants" as any).select("*").eq("game_id", id).order("slot");
    const rows = (p as any[]) || [];
    const ids = rows.map(r => r.user_id).filter(Boolean);
    let byId = new Map<string, string | null>();
    if (ids.length) {
      const { data: profs } = await supabase.from("profiles").select("id, avatar_url").in("id", ids);
      byId = new Map((profs || []).map((x: any) => [x.id, x.avatar_url]));
    }
    setParts(rows.map(r => ({ ...r, user_id: r.user_id || `bot_${r.slot}`, avatar_url: r.user_id ? byId.get(r.user_id) || null : null })));
  }, [id, profile?.id]);

  useDominoSounds({ game, parts, myUserId: profile?.id });

  useEffect(() => {
    load();
    const ch = supabase.channel("domino-" + id)
      .on("postgres_changes", { event: "*", schema: "public", table: "domino_games", filter: `id=eq.${id}` }, () => load())
      .on("postgres_changes", { event: "*", schema: "public", table: "domino_participants", filter: `game_id=eq.${id}` }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });
  const cfg = useGameConfig("domino");
  const [remaining, setRemaining] = useState<number>(cfg.turn_timer_seconds);
  const phase = game?.state?.phase;
  const isRoundTransition = phase === "break" || phase === "reveal";

  // ── Timer ──────────────────────────────────────────────────────────────
  useEffect(() => {
    if (!game || game.status !== "playing") { setRemaining(cfg.turn_timer_seconds); return; }
    if (isRoundTransition) {
      const target = game.state?.break_until;
      if (!target) return;
      const delay = Math.max(0, new Date(target).getTime() - serverNow()) + 250;
      const t = setTimeout(() => supabase.rpc("domino_tick" as any, { _game_id: id } as any), delay);
      return () => clearTimeout(t);
    }
    if (!game.turn_deadline) { setRemaining(cfg.turn_timer_seconds); return; }
    let fired = false;
    const tick = () => {
      const s = Math.max(0, Math.ceil((new Date(game.turn_deadline).getTime() - serverNow()) / 1000));
      setRemaining(s);
      if (s === 0 && !fired) { fired = true; supabase.rpc("domino_tick" as any, { _game_id: id } as any); }
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, phase, game?.state?.break_until, id, cfg.turn_timer_seconds, game, isRoundTransition]);

  // ── Bot think ──────────────────────────────────────────────────────────
  useEffect(() => {
    const think = game?.state?.bot_think_until;
    if (!think || game?.status !== "playing") return;
    const delay = Math.max(0, new Date(think).getTime() - serverNow()) + 150;
    const t = setTimeout(() => supabase.rpc("domino_tick" as any, { _game_id: id } as any), delay);
    return () => clearTimeout(t);
  }, [game?.state?.bot_think_until, game?.status, id]);

  // ── Derived state ──────────────────────────────────────────────────────
  const me = parts.find(p => p.user_id === profile?.id);
  const isPlayer = !!me;
  const isMyTurn = !!(game && me && game.current_turn === me.slot && game.status === "playing" && !isRoundTransition);
  const myHand: Tile[] = (game?.state?.hands?.[String(me?.slot)] as Tile[]) || [];
  const cols = Math.min(Math.max(7, myHand.length), 9);
  const tileW = Math.max(13, Math.min(28, Math.floor(handW / cols) - 4));
  const { board, leftEnd, rightEnd } = normalizeBoard(game?.state?.board, game?.state?.left_end, game?.state?.right_end);
  const firstTileIdx = Math.max(0, Math.min(board.length - 1, game?.state?.first_tile_idx ?? 0));
  const stockSize = (game?.state?.stock || []).length;
  const ftr: "libre" | "under6" = game?.state?.first_tile_rule === "under6" || game?.first_tile_rule === "under6" ? "under6" : "libre";
  const deadTiles: number[][] = (game?.state?.dead_tiles?.[String(me?.slot)] as number[][]) || [];
  const isDeadTile = (idx: number) => { const t = myHand[idx]; return !!t && deadTiles.some(dt => dt[0] === t[0] && dt[1] === t[1]); };
  const vatoMaty = !!game?.vato_maty;

  const tileMatches = useCallback((t: Tile, idx?: number) => {
    if (idx !== undefined && isDeadTile(idx)) return false;
    if (!board.length) {
      const rawFd = game?.state?.first_move_double;
      const fd = typeof rawFd === "number" ? rawFd : (rawFd != null ? Number(rawFd) : NaN);
      if (!isNaN(fd) && fd >= 0) return t[0] === fd && t[1] === fd;
      if (ftr === "under6") return (t[0] + t[1]) < 6;
      return true;
    }
    return t[0] === leftEnd || t[1] === leftEnd || t[0] === rightEnd || t[1] === rightEnd;
  }, [board.length, game?.state?.first_move_double, leftEnd, rightEnd, ftr, deadTiles]);

  const canPlay = myHand.some((t, i) => tileMatches(t, i));
  const drawMode = game?.state?.draw_mode === "without" ? "without" : "with" as const;
  const noMove = !!(isMyTurn && board.length > 0 && !canPlay && (drawMode === "without" || stockSize === 0));

  // ── Actions ────────────────────────────────────────────────────────────
  const playSide = async (side: "left" | "right" | "auto", idx = selectedTile) => {
    if (idx === null || busy) return;
    const tile = myHand[idx];
    if (!tile || !tileMatches(tile)) return;
    setBusy(true);
    try {
      const move: any = side === "auto" ? { action: "play", tile } : { action: "play", tile, side };
      const { error } = await supabase.rpc("domino_play" as any, { _game_id: id, _move: move } as any);
      if (error) throw error;
      playClack();
      setSelectedTile(null);
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };

  const draw = async () => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc("domino_play" as any, { _game_id: id, _move: { action: "draw" } } as any);
      if (error) throw error;
      playDraw();
      setRemaining(30);
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };

  const pass = async (opts?: { silent?: boolean }) => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc("domino_play" as any, { _game_id: id, _move: { action: "pass" } } as any);
      if (error) throw error;
      playPass();
    } catch (e: any) { if (!opts?.silent) toast.error(e.message); }
    finally { setBusy(false); }
  };

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
    const { error: forfeitError } = await supabase.rpc("domino_forfeit" as any, { _game_id: id } as any);
    if (forfeitError) { toast.error(forfeitError.message); return; }
    navigate({ to: "/jeux" });
  };

  // ── No-move broadcast ──────────────────────────────────────────────────
  useEffect(() => {
    if (!id) return;
    const ch = supabase.channel(`domino-nomove-${id}`)
      .on("broadcast", { event: "no_move" }, (p: any) => { if (typeof p.payload?.slot === "number") setRemoteNoMove(p.payload.slot); })
      .on("broadcast", { event: "no_move_clear" }, () => setRemoteNoMove(null))
      .subscribe();
    noMoveCh.current = ch;
    return () => { supabase.removeChannel(ch); noMoveCh.current = null; };
  }, [id]);

  useEffect(() => {
    if (!noMoveCh.current || me?.slot === undefined) return;
    noMoveCh.current.send({ type: "broadcast", event: noMove ? "no_move" : "no_move_clear", payload: { slot: me.slot } });
  }, [noMove, me?.slot]);

  useEffect(() => {
    if (!noMove || busy) return;
    const t = setTimeout(() => pass({ silent: true }), 2000);
    return () => clearTimeout(t);
  }, [noMove, busy, id]);

  const toggleSound = () => { const m = !soundOn; setSoundOn(!m); setSfxMuted(m); };

  // ── Render ──────────────────────────────────────────────────────────────
  if (!game) return <div className="p-6 text-center text-muted-foreground">Chargement…</div>;
  if (game.status === "cancelled") return <GameStateMessage state="cancelled" gameLabel="Domino" slug="domino" />;

  // Waiting room
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
      <main className="max-w-3xl mx-auto px-3 py-3 space-y-3">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="domino"
          gameLabel={`Domino · ${game.max_players} joueurs`}
          parts={parts}
          maxPlayers={game.max_players}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          roomCode={game.is_private ? game.room_code : null}
          shareSlug="domino"
          meUserId={profile?.id}
          isParticipant={!!me}
          createdAt={game.created_at}
          gameStatus={game.status}
          gameId={id}
          onQuit={forfeit}
          onToggleReady={async (r) => {
            const { error } = await supabase.rpc("domino_set_ready" as any, { _game_id: id, _ready: r } as any);
            if (error) toast.error(error.message);
          }}
        />
        {(isAdmin || (Number(game.stake) === 0 && !!me)) && parts.length < game.max_players && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("domino_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
              if (error) toast.error(error.message);
              else toast.success("Bot ajouté");
            }}
            className="w-full px-4 py-2.5 rounded-2xl bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 shadow-sm"
          >
            <Plus className="w-4 h-4" /> Ajouter un bot
          </button>
        )}
        <GameSocialFab gameId={id} gameSlug="domino" participants={parts} />
      </main>
    );
  }

  // Game state
  const dragged = selectedTile !== null ? myHand[selectedTile] : null;
  const cDL = !!(isMyTurn && dragged && (board.length === 0 ? tileMatches(dragged, myHand.findIndex(t => t[0] === dragged[0] && t[1] === dragged[1])) : dragged[0] === leftEnd || dragged[1] === leftEnd));
  const cDR = !!(isMyTurn && dragged && (board.length === 0 ? tileMatches(dragged, myHand.findIndex(t => t[0] === dragged[0] && t[1] === dragged[1])) : dragged[0] === rightEnd || dragged[1] === rightEnd));
  const cDA = !!(isMyTurn && dragged && tileMatches(dragged, myHand.findIndex(t => t[0] === dragged[0] && t[1] === dragged[1])));

  return (
    <main className="max-w-md mx-auto px-2 py-1 flex flex-col gap-1 h-full overflow-hidden overscroll-none"
      style={{ background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.05) 0%, transparent 70%)" }}>
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      <PhoneVerifyBanner stake={Number(game?.stake) || 0} phoneVerified={profile?.phone_verified === true} />

      {/* Barre gagnant + quitter — identique au Ludo */}
      {(() => {
        const payout = Math.round(Number(game.pot) * (100 - Number(game.commission_pct)) / 100);
        return (
          <div className="rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5">
            <div className="flex items-baseline gap-1 min-w-0">
              {game.target_score > 0 && <span className="text-[8px] uppercase text-muted-foreground tracking-wider hidden sm:inline">Objectif {game.target_score} pts · </span>}
              <span className="text-[8px] uppercase text-muted-foreground tracking-wider">{t("prize_winner")}</span>
              <span className="text-xs font-extrabold truncate">{payout.toLocaleString("fr-FR")} Ar</span>
              {gameNumber && <span className="text-[10px] font-mono font-bold text-primary/80 ml-1">{gameNumber}</span>}
            </div>
            <div className="flex items-center gap-1">
              {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
                <button onClick={toggleSound} className="w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition" title="Sons">
                  {soundOn ? <Volume2 className="w-3 h-3" /> : <VolumeX className="w-3 h-3" />}
                </button>
              )}
              <button onClick={forfeit} className="px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5">
                <LogOut className="w-2.5 h-2.5" /> {t("quit_refunded")}
              </button>
            </div>
          </div>
        );
      })()}

      {/* Top bar: opponent left + pot center + opponent right */}
      <div className="rounded-2xl bg-card px-2 py-2 border border-border shadow-sm flex items-center justify-between gap-1">
        {/* Left opponent */}
        <div className="shrink-0 min-w-[64px] flex justify-start">
          {(() => {
            const opps = parts.filter((p: any) => p.user_id !== profile?.id && !p.forfeited);
            const p = opps[0];
            if (!p) return null;
            return (
              <PlayerHeader key={p.user_id} seat={{
                user_id: p.user_id, display_name: p.display_name, avatar_url: p.avatar_url,
                slot: p.slot,
                handCount: p.hand_count ?? (game?.state?.hands?.[String(p.slot)] as Tile[] | undefined)?.length ?? 0,
                isCurrent: game.current_turn === p.slot,
                remaining: game.current_turn === p.slot ? remaining : undefined,
                score: Number(game.scores?.[p.user_id] || 0),
                skips: Number(game.turn_skips?.[p.user_id] || 0),
                maxSkips: Number(cfg.max_turn_skips) || 5,
              }} side="left" targetScore={Number(game.target_score) || 0} />
            );
          })()}
        </div>

        {/* Right opponent */}
        <div className="shrink-0 min-w-[64px] flex justify-end">
          {(() => {
            const opps = parts.filter((p: any) => p.user_id !== profile?.id && !p.forfeited);
            const p = opps[1];
            if (!p) return null;
            return (
              <PlayerHeader key={p.user_id} seat={{
                user_id: p.user_id, display_name: p.display_name, avatar_url: p.avatar_url,
                slot: p.slot,
                handCount: p.hand_count ?? (game?.state?.hands?.[String(p.slot)] as Tile[] | undefined)?.length ?? 0,
                isCurrent: game.current_turn === p.slot,
                remaining: game.current_turn === p.slot ? remaining : undefined,
                score: Number(game.scores?.[p.user_id] || 0),
                skips: Number(game.turn_skips?.[p.user_id] || 0),
                maxSkips: Number(cfg.max_turn_skips) || 5,
              }} side="right" targetScore={Number(game.target_score) || 0} />
            );
          })()}
        </div>
      </div>

      {/* Board — felt table */}
      <div className="flex-1 min-h-[130px] rounded-2xl overflow-hidden relative"
        style={{
          background: "radial-gradient(ellipse at 50% 40%, #1e7a42 0%, #0f4a26 65%, #0a3518 100%)",
          boxShadow: "inset 0 0 50px rgba(0,0,0,0.5), 0 4px 20px rgba(0,0,0,0.3)",
          border: "3px solid #0a3518",
        }}>
        <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-[0.06]" preserveAspectRatio="none">
          <ellipse cx="50%" cy="50%" rx="38%" ry="40%" fill="none" stroke="white" strokeWidth="1" />
          <ellipse cx="50%" cy="50%" rx="25%" ry="28%" fill="none" stroke="white" strokeWidth="0.5" />
        </svg>
        <DominoBoard
          board={board}
          leftEnd={leftEnd}
          rightEnd={rightEnd}
          canDropLeft={cDL}
          canDropRight={cDR}
          canDropAny={cDA}
          onDropLeft={() => cDL && playSide("left")}
          onDropRight={() => cDR && playSide("right")}
          onDropAny={() => cDA && playSide("auto")}
          firstTileIdx={firstTileIdx}
        />
      </div>

      {/* Round break */}
      {game.status === "playing" && isRoundTransition && game.state?.last_round && game.state?.break_until && (
        <DominoRoundBreak
          lastRound={game.state.last_round}
          scores={game.scores || {}}
          targetScore={Number(game.target_score) || 0}
          breakUntil={game.state.break_until}
          participants={parts}
          roundNumber={Number(game.state?.round ?? 1)}
        />
      )}

      {/* End screen */}
      {game.status === "finished" && (() => {
        const ws = game.state?.winner_slot;
        const wp = typeof ws === "number" ? parts.find(p => p.slot === ws) : null;
        const wid = game.winner_id ?? wp?.user_id ?? null;
        return (
          <GameEndScreen
            slug="domino"
            meUserId={profile?.id}
            winnerId={wid}
            winnerSlot={typeof ws === "number" ? ws : null}
            participants={parts}
            stake={Number(game.stake)}
            pot={Number(game.pot)}
            commissionPct={Number(game.commission_pct) || 10}
            onReplay={async () => {
              const { data, error } = await supabase.rpc("domino_create" as any, {
                _stake: Number(game.stake) || 0,
                _max: game.max_players,
                _private: !!game.is_private,
                _mode: game.target_score > 0 ? "points" : "classic",
                _commission: Number(game.commission_pct) || 10,
                _target_score: Number(game.target_score) || 0,
                _draw_mode: game.state?.draw_mode === "without" ? "without" : "with",
                _first_tile_rule: game.first_tile_rule === "under6" ? "under6" : "libre",
              } as any);
              if (error) { toast.error(error.message); return; }
              navigate({ to: "/jeux/domino/$id", params: { id: data as string } });
            }}
            extra={Number(game.target_score) > 0 && game.scores ? (
              <div className="text-left rounded-xl bg-secondary/50 p-3 space-y-1.5">
                <div className="text-[10px] uppercase text-muted-foreground tracking-wider font-bold">
                  Scores (objectif {game.target_score})
                </div>
                {parts.map(p => (
                  <div key={p.user_id} className="flex justify-between text-sm">
                    <span className="truncate">{p.display_name}</span>
                    <span className="font-mono font-bold">{Number(game.scores?.[p.user_id] || 0)} pts</span>
                  </div>
                ))}
              </div>
            ) : undefined}
          />
        );
      })()}

      {/* Hand + controls */}
      {me && game.status === "playing" && !isRoundTransition && (
        <div className={`space-y-1.5 shrink-0 relative`}>
          {isMyTurn && !canPlay && (
            <p className="text-center text-xs text-muted-foreground py-0.5">Pas de domino jouable</p>
          )}
          <div className="flex items-end gap-2 pb-1">
            <div className="shrink-0">
              <PlayerHeader seat={{
                user_id: me.user_id, display_name: me.display_name, avatar_url: me.avatar_url,
                slot: me.slot, handCount: myHand.length, isCurrent: isMyTurn, remaining: isMyTurn ? remaining : undefined,
                isMe: true,
                score: Number(game.scores?.[me.user_id] || 0),
                skips: Number(game.turn_skips?.[me.user_id] || 0),
                maxSkips: Number(cfg.max_turn_skips) || 5,
              }} side="left" size="lg" targetScore={Number(game.target_score) || 0} />
            </div>
            <div className="grid flex-1 gap-1" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
              {myHand.map((t, i) => {
                const dead = isDeadTile(i);
                const playable = isMyTurn && tileMatches(t, i);
                const cL = board.length > 0 && (t[0] === leftEnd || t[1] === leftEnd);
                const cR = board.length > 0 && (t[0] === rightEnd || t[1] === rightEnd);
                const needsChoice = playable && cL && cR;
                return (
                  <div key={i} className={`flex justify-center relative ${dead
                    ? "p-0.5 rounded-lg border-2 border-red-500/70 grayscale opacity-50"
                    : playable
                    ? "p-0.5 rounded-lg bg-amber-400/15 border-2 border-amber-400 shadow-[0_0_12px_rgba(251,191,36,0.6)]"
                    : "p-0.5 border-2 border-transparent opacity-65"}`}>
                    {playable && <span className="absolute -top-1.5 -right-1.5 w-3 h-3 rounded-full bg-amber-400 border border-background shadow" />}
                    {dead && (
                      <span className="absolute inset-0 z-10 pointer-events-none flex items-center justify-center">
                        <span className="absolute -top-2 left-1/2 -translate-x-1/2 px-1 py-0.5 rounded-full bg-red-600 text-white text-[7px] font-extrabold leading-none whitespace-nowrap shadow">MATY</span>
                        <svg className="w-4 h-4 text-red-500/80" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3" strokeLinecap="round">
                          <path d="M6 6 L18 18 M18 6 L6 18" />
                        </svg>
                      </span>
                    )}
                    <DominoTile t={t} w={tileW} vertical
                      onClick={playable ? () => { if (needsChoice) setSelectedTile(selectedTile === i ? null : i); else playSide("auto", i); } : undefined}
                      draggable={playable}
                      onDragStart={() => setSelectedTile(i)}
                      selected={selectedTile === i} />
                  </div>
                );
              })}
            </div>
          </div>
          {isMyTurn && !canPlay && drawMode === "with" && stockSize > 0 && (
            <button disabled={busy} onClick={draw}
              className="w-full py-2 rounded-full bg-secondary font-bold text-sm">
              Piocher ({stockSize} tuile{stockSize > 1 ? "s" : ""})
            </button>
          )}
        </div>
      )}

      <GamePauseControl
        slug="domino" gameId={id} game={game}
        isPlayer={isPlayer} myUserId={profile?.id ?? null}
        simplePause={parts.some((p: any) => p.is_bot)}
      />
      <GameSocialFab gameId={id} gameSlug="domino" participants={parts} />
    </main>
  );
}
