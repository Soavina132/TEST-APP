import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState, useCallback, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";

import { copyText } from "@/lib/clipboard";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { useFastRealtime } from "@/hooks/game/use-fast-realtime";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";
import { LogOut, Copy, Plus, Pause, Ban, Volume2, VolumeX } from "lucide-react";
import GameSocialFab from "@/components/game/GameSocialFab";
import PhoneVerifyBanner from "@/components/PhoneVerifyBanner";
import GamePauseControl from "@/components/game/GamePauseControl";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameStateMessage from "@/components/game/GameStateMessage";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import DominoRoundBreak from "@/components/game/DominoRoundBreak";
import { GameLoader } from "@/components/game/GameLoader";
import DominoTable, { DominoTile, PlayerHeader } from "@/components/game/DominoTable";
import { useGameConfig } from "@/hooks/game/use-game-config";
import { useConfirm } from "@/components/ConfirmDialog";
import { useDominoSounds } from "@/hooks/game/use-domino-sounds";
import { playClack, playDraw, playPass } from "@/lib/sounds/game-sounds";
import { setSfxMuted, isSfxMuted } from "@/lib/sounds/game-sounds";


export const Route = createFileRoute("/_authenticated/jeux/domino/$id")({
  component: DominoPage,
  head: () => ({ meta: [{ title: "Domino — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

type Tile = [number, number];

type BoardEntry = { tile: Tile; flipped: boolean };

function readBoardTile(entry: unknown): Tile | null {
  if (Array.isArray(entry)) return entry.length === 2 ? [Number(entry[0]), Number(entry[1])] as Tile : null;
  const obj = entry as { tile?: unknown; t?: unknown } | null;
  const rawTile = obj?.tile ?? obj?.t;
  if (!Array.isArray(rawTile) || rawTile.length !== 2) return null;
  const a = Number(rawTile[0]);
  const b = Number(rawTile[1]);
  if (!Number.isFinite(a) || !Number.isFinite(b)) return null;
  return [a, b];
}

function solveDominoTrail(tiles: Tile[], start: number, end?: number): Tile[] | null {
  if (tiles.length === 0) return [];
  const adjacency = new Map<number, { to: number; index: number }[]>();
  const degree = new Map<number, number>();

  tiles.forEach(([a, b], index) => {
    adjacency.set(a, [...(adjacency.get(a) ?? []), { to: b, index }]);
    adjacency.set(b, [...(adjacency.get(b) ?? []), { to: a, index }]);
    degree.set(a, (degree.get(a) ?? 0) + 1);
    degree.set(b, (degree.get(b) ?? 0) + 1);
  });

  if ((degree.get(start) ?? 0) === 0) return null;

  const seen = new Set<number>();
  const pending = [start];
  while (pending.length > 0) {
    const node = pending.pop();
    if (node === undefined || seen.has(node)) continue;
    seen.add(node);
    (adjacency.get(node) ?? []).forEach(({ to }) => {
      if (!seen.has(to)) pending.push(to);
    });
  }
  if ([...degree.entries()].some(([, value]) => value > 0) && [...degree.keys()].some((node) => !seen.has(node))) return null;

  const oddNodes = [...degree.entries()].filter(([, value]) => value % 2 === 1).map(([node]) => node);
  if (end !== undefined) {
    if (start === end) {
      if (oddNodes.length !== 0) return null;
    } else if (oddNodes.length !== 2 || !oddNodes.includes(start) || !oddNodes.includes(end)) {
      return null;
    }
  } else if (oddNodes.length === 2 && !oddNodes.includes(start)) {
    return null;
  } else if (oddNodes.length !== 0 && oddNodes.length !== 2) {
    return null;
  }

  const used = new Set<number>();
  const cursors = new Map<number, number>();
  const stack: { node: number; edge?: { from: number; to: number } }[] = [{ node: start }];
  const edges: { from: number; to: number }[] = [];

  while (stack.length > 0) {
    const top = stack[stack.length - 1];
    const list = adjacency.get(top.node) ?? [];
    let cursor = cursors.get(top.node) ?? 0;
    while (cursor < list.length && used.has(list[cursor].index)) cursor += 1;
    cursors.set(top.node, cursor);

    const next = list[cursor];
    if (next) {
      used.add(next.index);
      cursors.set(top.node, cursor + 1);
      stack.push({ node: next.to, edge: { from: top.node, to: next.to } });
    } else {
      const done = stack.pop();
      if (done?.edge) edges.push(done.edge);
    }
  }

  edges.reverse();
  if (edges.length !== tiles.length) return null;
  if (end !== undefined && edges[edges.length - 1]?.to !== end) return null;
  return edges.map(({ from, to }) => [from, to] as Tile);
}

function reverseTrail(trail: Tile[]): Tile[] {
  return [...trail].reverse().map(([a, b]) => [b, a] as Tile);
}

function fallbackNormalize(rawTiles: Tile[], expectedLeft?: number, expectedRight?: number): Tile[] {
  const chain: Tile[] = [];
  let leftEnd: number | null = null;
  let rightEnd: number | null = null;

  for (const tile of rawTiles) {
    const [a, b] = tile;
    if (chain.length === 0) {
      const firstTile: Tile = Number.isFinite(expectedLeft) && b === expectedLeft && a !== expectedLeft ? [b, a] : [a, b];
      chain.push(firstTile);
      leftEnd = firstTile[0];
      rightEnd = firstTile[1];
    } else if (a === rightEnd) {
      chain.push([a, b]);
      rightEnd = b;
    } else if (b === rightEnd) {
      chain.push([b, a]);
      rightEnd = a;
    } else if (b === leftEnd) {
      chain.unshift([a, b]);
      leftEnd = a;
    } else if (a === leftEnd) {
      chain.unshift([b, a]);
      leftEnd = b;
    } else {
      chain.push([a, b]);
    }
  }

  if (Number.isFinite(expectedRight) && chain.at(-1)?.[1] !== expectedRight) {
    const reversed = reverseTrail(chain);
    if ((!Number.isFinite(expectedLeft) || reversed[0]?.[0] === expectedLeft) && reversed.at(-1)?.[1] === expectedRight) {
      return reversed;
    }
  }

  return chain;
}

function normalizeDominoBoard(rawBoard: any[], serverLeft?: unknown, serverRight?: unknown): { board: BoardEntry[]; leftEnd: number | null; rightEnd: number | null } {
  if (!Array.isArray(rawBoard) || rawBoard.length === 0) {
    return { board: [], leftEnd: null, rightEnd: null };
  }

  const expectedLeft = typeof serverLeft === "number" ? serverLeft : Number(serverLeft);
  const expectedRight = typeof serverRight === "number" ? serverRight : Number(serverRight);
  const hasExpectedLeft = Number.isFinite(expectedLeft);
  const hasExpectedRight = Number.isFinite(expectedRight);

  const rawTiles = rawBoard.map(readBoardTile).filter((tile): tile is Tile => tile !== null);
  if (rawTiles.length === 0) return { board: [], leftEnd: null, rightEnd: null };

  let trail: Tile[] | null = null;
  if (hasExpectedLeft) {
    trail = solveDominoTrail(rawTiles, expectedLeft, hasExpectedRight ? expectedRight : undefined);
  }
  if (!trail && hasExpectedRight) {
    const reversed = solveDominoTrail(rawTiles, expectedRight, hasExpectedLeft ? expectedLeft : undefined);
    if (reversed) trail = reverseTrail(reversed);
  }
  if (!trail) {
    const degree = new Map<number, number>();
    rawTiles.forEach(([a, b]) => {
      degree.set(a, (degree.get(a) ?? 0) + 1);
      degree.set(b, (degree.get(b) ?? 0) + 1);
    });
    const starts = [...new Set([
      rawTiles[0][0],
      rawTiles[0][1],
      ...[...degree.entries()].filter(([, value]) => value % 2 === 1).map(([pip]) => pip),
      ...[...degree.keys()],
    ])];
    for (const start of starts) {
      trail = solveDominoTrail(rawTiles, start) ?? null;
      if (trail) break;
    }
  }

  const normalized = trail && trail.length === rawTiles.length
    ? trail
    : fallbackNormalize(rawTiles, hasExpectedLeft ? expectedLeft : undefined, hasExpectedRight ? expectedRight : undefined);

  const leftEnd = normalized[0]?.[0] ?? null;
  const rightEnd = normalized[normalized.length - 1]?.[1] ?? null;
  return { board: normalized.map((tile) => ({ tile, flipped: false })), leftEnd, rightEnd };
}


function DominoPage() {
  const { id } = Route.useParams();
  const { profile, isAdmin, refreshProfile } = useAuth();
  const [soundOn, setSoundOn] = useState(!isSfxMuted());
  const navigate = useNavigate();
  const confirm = useConfirm();
  const { game, parts, setGame, setParts, loading, connected, reload } = useFastRealtime({
    gameTable: "domino_games",
    participantTable: "domino_participants",
    gameId: id,
    enabled: !!profile?.id,
    onFinished: refreshProfile,
  }) as any;

  // ── State variables (restored after useFastRealtime refactor) ──────────
  const [selectedTile, setSelectedTile] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  // Synchronous lock — React state (`busy`) updates are batched/async, so a
  // near-simultaneous double-fire (e.g. Android Chrome firing both `onDrop`
  // and a synthesized `onClick` for the same touch-drag gesture) can slip
  // past a state-only guard before the re-render happens. This ref is read
  // and written immediately, closing that race window.
  const actionLockRef = useRef(false);
  // Tracks which opponent's hand has no playable tile (via realtime broadcast),
  // so a red frame can be shown to all players before the auto-pass completes.
  const [remoteNoMoveSlot, setRemoteNoMoveSlot] = useState<number | null>(null);
  const noMoveChRef = useRef<any>(null);
  // Prevents auto-pass from firing repeatedly while waiting for server state update.
  const passAttemptedRef = useRef(false);
  // Delay showing the end screen by 1s so the player sees the final board state.
  const [showEndScreen, setShowEndScreen] = useState(false);
  useEffect(() => {
    if (game?.status === "finished" && !showEndScreen) {
      const t = setTimeout(() => setShowEndScreen(true), 1000);
      return () => clearTimeout(t);
    }
    if (game?.status !== "finished" && showEndScreen) {
      setShowEndScreen(false);
    }
  }, [game?.status, showEndScreen]);
  // Available width for the hand row; tile width is derived from it and from
  // the number of tiles held (a player can hold more than 7 after drawing).
  const [handAvail, setHandAvail] = useState<number>(190);
  useEffect(() => {
    const update = () => {
      const vw = typeof window !== "undefined" ? window.innerWidth : 360;
      // Reserve ~170px for the PlayerHeader block + gaps/padding.
      setHandAvail(Math.max(140, vw - 170));
    };
    update();
    window.addEventListener("resize", update);
    window.addEventListener("orientationchange", update);
    return () => {
      window.removeEventListener("resize", update);
      window.removeEventListener("orientationchange", update);
    };
  }, []);

  // ── Sound effects ──────────────────────────────────────────────────────
  useDominoSounds({ game, parts, myUserId: profile?.id });



  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: reload });

  // cancelled state handled by GameStateMessage below


  const cfg = useGameConfig("domino");
  const [remaining, setRemaining] = useState<number>(cfg.turn_timer_seconds);
  const phase = game?.state?.phase;
  const isRoundTransition = phase === "reveal" || phase === "break";
  useEffect(() => {
    if (!game || game.status !== "playing") { setRemaining(cfg.turn_timer_seconds); return; }
    // During reveal/break phases: schedule a tick right after each deadline
    // (turn_deadline is NULL between rounds — we rely on state.reveal_until /
    // state.break_until instead so the new round starts without waiting on the
    // 5s cron).
    if (phase === "reveal" || phase === "break") {
      const target = phase === "reveal"
        ? (game.state?.reveal_until as string | undefined)
        : (game.state?.break_until as string | undefined);
      if (!target) return;
      const delay = Math.max(0, new Date(target).getTime() - serverNow()) + 150;
      const t = setTimeout(() => {
        supabase.rpc("domino_tick" as any, { _game_id: id } as any);
      }, delay);
      return () => clearTimeout(t);
    }
    if (!game.turn_deadline) { setRemaining(cfg.turn_timer_seconds); return; }
    let fired = false;
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      const s = Math.max(0, Math.ceil(ms / 1000));
      setRemaining(s);
      if (s === 0 && !fired) {
        fired = true;
        supabase.rpc("domino_tick" as any, { _game_id: id } as any);
      }
    };
    tick();
    const t = setInterval(tick, 100);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, phase, game?.state?.reveal_until, game?.state?.break_until, id, cfg.turn_timer_seconds, game]);

  // Re-trigger domino_tick when a bot's "thinking delay" expires, so bot
  // moves appear with the intended pause instead of waiting for the 5s cron fallback.
  useEffect(() => {
    const think = game?.state?.bot_think_until;
    if (!think || game?.status !== "playing") return;
    const ms = new Date(think).getTime() - serverNow();
    const delay = Math.max(0, ms) + 30;
    const t = setTimeout(() => {
      supabase.rpc("domino_tick" as any, { _game_id: id } as any);
    }, delay);
    return () => clearTimeout(t);
  }, [game?.state?.bot_think_until, game?.status, id]);

  const me = parts.find((p: any) => p.user_id === profile?.id);
  const isPlayer = !!me;
  const isMyTurn = game && me && game.current_turn === me.slot && game.status === "playing" && !isRoundTransition;
  const myHand: Tile[] = Array.isArray(game?.state?.hands?.[String(me?.slot)]) ? (game.state.hands[String(me.slot)] as Tile[]) : [];
  // Tiles per row: 7 minimum, up to 10 when the hand grew from drawing.
  const handCols = myHand.length === 0 ? 0 : Math.max(7, Math.min(myHand.length, 10));
  const handTileW = Math.max(13, Math.min(28, Math.floor(handAvail / handCols) - 4));
  const normalizedBoard = normalizeDominoBoard(game?.state?.board || [], game?.state?.left_end, game?.state?.right_end);
  const board: { tile: Tile; flipped: boolean }[] = normalizedBoard.board;
  const leftEnd: number | null = normalizedBoard.leftEnd;
  const rightEnd: number | null = normalizedBoard.rightEnd;
  const stockSize: number = (game?.state?.stock || []).length;

  const firstTileRule: "libre" | "under6" = game?.state?.first_tile_rule === "under6" || game?.first_tile_rule === "under6" ? "under6" : "libre";
  // ═══ SERVER-AUTHORITATIVE playable tiles ═══
  // The server (_domino_playable_tiles) now computes which tiles are playable
  // and returns them in state.playable_tiles. We use that as the source of truth.
  // Client-side tileMatches is kept as a fallback for old game states.
  const serverPlayableTiles: number[] = game?.state?.playable_tiles || [];
  const tileMatches = useCallback((t: Tile) => {
    // If server provides playable_tiles, use it
    if (serverPlayableTiles.length > 0 || (game?.state && 'playable_tiles' in game.state)) {
      const idx = myHand.indexOf(t);
      return serverPlayableTiles.includes(idx);
    }
    // Fallback: client-side calculation
    if (board.length === 0) {
      const fd = game?.state?.first_move_double;
      if (typeof fd === "number") return t[0] === fd && t[1] === fd;
      if (firstTileRule === "under6") return (t[0] + t[1]) < 6;
      return true;
    }
    return t[0] === leftEnd || t[1] === leftEnd || t[0] === rightEnd || t[1] === rightEnd;
  }, [board.length, game?.state?.first_move_double, leftEnd, rightEnd, firstTileRule, serverPlayableTiles, myHand]);
  const canPlay = myHand.some(tileMatches);
  const drawMode: "with" | "without" = game?.state?.draw_mode === "without" ? "without" : "with";

  const noMove = !!(isMyTurn && board.length > 0 && !canPlay && (drawMode === "without" || stockSize === 0));
  const passSlot = game?.state?.last_pass_by;
  const passCount = Number(game?.state?.passes) || 0;
  const activePlayers = Array.isArray(parts) ? parts.filter((p: any) => !p.forfeited).length : 0;
  const isBlocked = passCount >= activePlayers && activePlayers > 0;
  const passPart = typeof passSlot === "number" ? parts.find((p: any) => p.slot === passSlot) : null;
  const oppNoMove = !!(!isMyTurn && passSlot !== undefined && passSlot !== me?.slot);

  const draw = async () => {
    if (actionLockRef.current) return;
    actionLockRef.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("domino_play_and_bot" as any, { _game_id: id, _move: { action: "draw" } } as any);
      if (error) throw error;
      playDraw();
    } catch (e: any) {  }
    finally { setBusy(false); actionLockRef.current = false; }
  };

  const pass = async (opts?: { silent?: boolean }) => {
    if (actionLockRef.current) return;
    actionLockRef.current = true;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("domino_play_and_bot" as any, { _game_id: id, _move: { action: "pass" } } as any);
      if (error) throw error;
      playPass();
    } catch (e: any) { if (!opts?.silent) {}}
    finally { setBusy(false); actionLockRef.current = false; }
  };

  // Subscribe to no-move broadcasts from other players so everyone sees the
  // red frame before the auto-pass completes.
  useEffect(() => {
    if (!id) return;
    const ch = supabase.channel(`domino-nomove-${id}`)
      .on("broadcast", { event: "no_move" }, (payload: any) => {
        const { slot } = payload.payload || {};
        if (typeof slot === "number") setRemoteNoMoveSlot(slot);
      })
      .on("broadcast", { event: "no_move_clear" }, () => {
        setRemoteNoMoveSlot(null);
      })
      .subscribe();
    noMoveChRef.current = ch;
    return () => {
      supabase.removeChannel(ch);
      noMoveChRef.current = null;
    };
  }, [id]);

  // Broadcast our no-move state to other players
  useEffect(() => {
    if (!noMoveChRef.current || me?.slot === undefined) return;
    if (noMove) {
      noMoveChRef.current.send({
        type: "broadcast",
        event: "no_move",
        payload: { slot: me.slot },
      });
    } else {
      noMoveChRef.current.send({
        type: "broadcast",
        event: "no_move_clear",
        payload: { slot: me.slot },
      });
    }
  }, [noMove, me?.slot]);

  // Auto-pass when player has no valid move. Retries every 2s (not just once)
  // so a transient RPC/network failure, or a stale client-side playability
  // check, can't leave the turn permanently stuck — it keeps trying until the
  // server confirms the pass (noMove flips back to false once state updates).
  // Errors are silent here to avoid toast spam on repeated retries.
  useEffect(() => {
    if (!noMove) { passAttemptedRef.current = false; return; }
    if (busy || passAttemptedRef.current) return;
    const t = setTimeout(() => {
      passAttemptedRef.current = true;
      pass({ silent: true });
    }, 800);
    return () => clearTimeout(t);
  }, [noMove, busy, id]);

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
    await supabase.rpc("domino_forfeit" as any, { _game_id: id } as any);
    navigate({ to: "/jeux" });
  };

  if (!game) return <GameLoader />;

  if (game.status === "cancelled") {
    return <GameStateMessage state="cancelled" gameLabel="Domino" slug="domino" />;
  }

  if (game.status === "open") {
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
          onQuit={forfeit}
          onToggleReady={async (ready) => {
            const { error } = await supabase.rpc("domino_set_ready" as any, { _game_id: id, _ready: ready } as any);
            if (error) {}
          }}
        />

        {(isAdmin || (Number(game.stake) === 0 && !!me)) && parts.length < game.max_players && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("domino_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
              if (error) {}
              else null;
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

  // Drag state
  const draggedTile = selectedTile !== null ? myHand[selectedTile] : null;
  const canDropLeft = !!(isMyTurn && draggedTile && (board.length === 0 ? tileMatches(draggedTile) : (draggedTile[0] === leftEnd || draggedTile[1] === leftEnd)));
  const canDropRight = !!(isMyTurn && draggedTile && (board.length === 0 ? tileMatches(draggedTile) : (draggedTile[0] === rightEnd || draggedTile[1] === rightEnd)));
  const canDropAny = !!(isMyTurn && draggedTile && tileMatches(draggedTile));

  const playSide = async (side: "left" | "right" | "auto", tileIndex = selectedTile) => {
    if (tileIndex === null || actionLockRef.current) return;
    const tile = myHand[tileIndex];
    if (!tile || !tileMatches(tile)) return;
    // Lock + clear selection synchronously so a second event fired in the
    // same tick (e.g. the synthesized click after a touch drag-drop) can't
    // slip through with the same stale tile.
    actionLockRef.current = true;
    setSelectedTile(null);
    setBusy(true);
    try {
      const move: any = side === "auto" ? { action: "play", tile } : { action: "play", tile, side };
      const { data, error } = await supabase.rpc("domino_play_and_bot" as any, { _game_id: id, _move: move } as any);
      if (error) throw error;
      // Use the RPC response to update game state IMMEDIATELY — don't wait
      // for the realtime event (100-500ms delay). This prevents the user
      // from re-selecting and re-submitting a tile that was already played.
      if (data) setGame((g: any) => g ? { ...g, state: data, current_turn: data.turn_slot ?? g.current_turn } : g);
      playClack();
    } catch (e: any) {  }
    finally { setBusy(false); actionLockRef.current = false; }
  };

  return (
    <main className="max-w-md mx-auto px-2 py-1 flex flex-col gap-1 h-full overflow-hidden overscroll-none" style={{ background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.05) 0%, transparent 70%)" }}>
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
            <div className="rounded-full bg-card px-2 py-0.5 border border-border shadow-[var(--shadow-soft)] flex items-center justify-between gap-1.5">
        <div className="flex items-baseline gap-1 min-w-0">
          <span className="text-[8px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
          <span className="text-xs font-extrabold truncate">{Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar</span>
        </div>
        {!me ? (
          <div className="px-2 py-0.5 rounded-full bg-secondary text-[10px] font-semibold flex items-center gap-1">
            Spectateur
          </div>
        ) : (
          <div className="flex items-center gap-1">
            {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
              <button
                onClick={async () => {
                  const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "domino", _game_id: id } as any);
                  if (error) {}
                  else null;
                }}
                className="px-2 py-0.5 rounded-full bg-amber-500 text-white text-[10px] font-semibold flex items-center gap-0.5"
              >
                <Pause className="w-2.5 h-2.5" /> Pause
              </button>
            )}
            <button onClick={() => { const m = !soundOn; setSoundOn(m); setSfxMuted(m); }} className="w-6 h-6 rounded-full bg-secondary text-secondary-foreground flex items-center justify-center active:scale-90 transition">
              {soundOn ? <Volume2 className="w-3 h-3" /> : <VolumeX className="w-3 h-3" />}
            </button>
            <button onClick={forfeit} className="px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5">
              <LogOut className="w-2.5 h-2.5" /> Quitter
            </button>
          </div>
        )}
      </div>



      <PhoneVerifyBanner stake={Number(game.stake) || 0} phoneVerified={!!profile?.phone_verified} />
      <div className="flex-1 min-h-0 flex flex-col">
        <DominoTable
          seats={parts.map((p: any) => ({
            user_id: p.user_id,
            display_name: p.display_name,
            avatar_url: p.avatar_url,
            slot: p.slot,
            handCount: (game.state?.hands?.[String(p.slot)] as Tile[])?.length || 0,
            isCurrent: game.current_turn === p.slot && game.status === "playing",
            remaining: game.current_turn === p.slot ? remaining : undefined,
            isMe: p.user_id === profile?.id,
            forfeited: p.forfeited,
            score: Number(game.scores?.[String(p.slot)] || 0),
            skips: Number(game.turn_skips?.[p.user_id] || 0),
            maxSkips: Number(cfg.max_turn_skips) || 5,
          }))}
          maxPlayers={game.max_players}
          meSlot={me?.slot ?? null}
          board={isRoundTransition ? [] : board}
          leftEnd={isRoundTransition ? null : leftEnd}
          rightEnd={isRoundTransition ? null : rightEnd}
          stockSize={stockSize}
          targetScore={Number(game.target_score) || undefined}
          seed={id}
          statusMessage={(() => {
            if (game.status !== "playing") return undefined;
            const currentPart = parts.find((p: any) => p.slot === game.current_turn);
            const currentName = currentPart ? (currentPart.user_id === profile?.id ? "Vous" : currentPart.display_name) : null;
            if (isMyTurn) return canPlay ? "À vous de jouer" : (drawMode === "with" && stockSize > 0 ? "Piochez pour continuer" : `Tour de ${currentName}…`);
            if (currentName) return `Tour de ${currentName}…`;
            return undefined;
          })()}
          noMoveSlot={null}
          canDropLeft={canDropLeft}
          canDropRight={canDropRight}
          canDropAny={canDropAny}
          onDropAny={() => { if (canDropAny) playSide("auto"); }}
          onDropLeft={() => { if (canDropLeft) playSide("left"); }}
          onDropRight={() => { if (canDropRight) playSide("right"); }}
        />
      </div>

      {showEndScreen && game.status === "finished" && (() => {
        const winnerSlot = game.state?.winner_slot;
        const winnerPart = typeof winnerSlot === "number" ? parts.find((p: any) => p.slot === winnerSlot) : null;
        const effectiveWinnerId = game.winner_id ?? winnerPart?.user_id ?? null;
        return (
          <GameEndScreen
            slug="domino"
            meUserId={profile?.id}
            winnerId={effectiveWinnerId}
            winnerSlot={typeof winnerSlot === "number" ? winnerSlot : null}
            participants={parts}
            stake={Number(game.stake)}
            pot={Number(game.pot)}
            commissionPct={Number(game.commission_pct) || 10}
            onReplay={async () => {
              const hadBots = parts.some((p: any) => p.is_bot);
              const newId = await (async () => {
                if (hadBots) {
                  // Recreate a solo bot game: create + add bots + set ready (auto-start)
                  const { data, error } = await supabase.rpc("domino_create" as any, {
                    _stake: Number(game.stake) || 0,
                    _max: game.max_players,
                    _private: true,
                    _mode: game.state?.target_score ? "points" : "classic",
                    _commission: Number(game.commission_pct) || 10,
                    _target_score: Number(game.target_score) || 0,
                    _draw_mode: game.state?.draw_mode === "without" ? "without" : "with",
                    _first_tile_rule: game.first_tile_rule === "under6" ? "under6" : "libre",
                  } as any);
                  if (error) { return null; }
                  const id = data as string;
                  const botsNeeded = Math.max(0, Number(game.max_players) - 1);
                  for (let i = 0; i < botsNeeded; i++) {
                    await supabase.rpc("domino_add_bot" as any, { _game_id: id, _bot_name: `Bot ${i + 1}` } as any);
                  }
                  await supabase.rpc("domino_set_ready" as any, { _game_id: id, _ready: true } as any);
                  return id;
                } else {
                  // Recreate a multiplayer game
                  const { data, error } = await supabase.rpc("domino_create" as any, {
                    _stake: Number(game.stake) || 0,
                    _max: game.max_players,
                    _private: !!game.is_private,
                    _mode: game.state?.target_score ? "points" : "classic",
                    _commission: Number(game.commission_pct) || 10,
                    _target_score: Number(game.target_score) || 0,
                    _draw_mode: game.state?.draw_mode === "without" ? "without" : "with",
                    _first_tile_rule: game.first_tile_rule === "under6" ? "under6" : "libre",
                  } as any);
                  if (error) { return null; }
                  return data as string;
                }
              })();
              if (newId) { refreshProfile(); navigate({ to: "/jeux/domino/$id", params: { id: newId } }); }
            }}
            extra={Number(game.target_score) > 0 && game.scores ? (
              <div className="text-left rounded-xl bg-secondary/50 p-3 space-y-1.5">
                <div className="text-[10px] uppercase text-muted-foreground tracking-wider font-bold">Scores (objectif {game.target_score})</div>
                {parts.map((p: any) => (
                  <div key={p.user_id} className="flex justify-between text-sm">
                    <span className="truncate">{p.display_name}</span>
                    <span className="font-mono font-bold">{Number(game.scores?.[String(p.slot)] || 0)} pts</span>
                  </div>
                ))}
              </div>
            ) : undefined}
          />
        );
      })()}

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

      {/* Hand + actions */}
      {me && game.status === "playing" && !isRoundTransition && (
        <div className="space-y-1.5 shrink-0 relative" style={{ minHeight: 70 }}>
          <div className="flex items-end gap-2 pb-1 px-0">
            {/* Your profile (avatar + name + score + timer) anchored to the bottom-left of your hand */}
            <div className="shrink-0">
              <PlayerHeader
                seat={{
                  user_id: me.user_id,
                  display_name: me.display_name,
                  avatar_url: me.avatar_url,
                  slot: me.slot,
                  handCount: myHand.length,
                  isCurrent: isMyTurn,
                  remaining: isMyTurn ? remaining : undefined,
                  isMe: true,
                  score: Number(game.scores?.[String(me.slot)] || 0),
                  skips: Number(game.turn_skips?.[me.user_id] || 0),
                  maxSkips: Number(cfg.max_turn_skips) || 5,
                }}
                side="left"
                size="lg"
              />
            </div>
            <div
              className="grid flex-1 gap-1"
              style={{ gridTemplateColumns: `repeat(${Math.max(handCols, 7)}, minmax(0, 1fr))`, transition: "grid-template-columns 200ms ease" }}
            >
              {myHand.map((t, i) => {
                const playable = isMyTurn && tileMatches(t);
                const canL = board.length > 0 && (t[0] === leftEnd || t[1] === leftEnd);
                const canR = board.length > 0 && (t[0] === rightEnd || t[1] === rightEnd);
                const needsChoice = playable && canL && canR && leftEnd !== rightEnd;
                return (
                  <div key={`${t[0]}-${t[1]}`} className={`flex justify-center transition-colors duration-200 ease-out ${playable
                    ? "relative p-0.5 rounded-lg bg-amber-400/15 border-2 border-amber-400 shadow-[0_0_14px_rgba(251,191,36,0.75)] animate-pulse"
                    : "p-0.5 border-2 border-transparent opacity-70"}`}>
                    {playable && (
                      <span className="absolute -top-1.5 -right-1.5 w-3 h-3 rounded-full bg-amber-400 border border-background shadow" />
                    )}
                    <DominoTile t={t} w={handTileW} vertical
                      onClick={playable ? () => {
                        if (needsChoice) {
                          if (selectedTile === i) { setSelectedTile(null); }
                          else { setSelectedTile(i); }
                        } else {
                          playSide("auto", i);
                        }
                      } : undefined}
                      draggable={playable}
                      onDragStart={() => setSelectedTile(i)}
                      onDragEnd={() => { setTimeout(() => setSelectedTile(null), 300); }}
                      selected={selectedTile === i} />
                  </div>
                );
              })}
            </div>
          </div>
          {isMyTurn && !canPlay && drawMode === "with" && stockSize > 0 && (
            <div className="flex gap-2">
              <button disabled={busy} onClick={draw} className="flex-1 py-2 rounded-full bg-secondary font-bold text-sm">Piocher ({stockSize})</button>
            </div>
          )}
        </div>
      )}
      <GamePauseControl
        slug="domino"
        gameId={id}
        game={game}
        isPlayer={isPlayer}
        myUserId={profile?.id ?? null}
        simplePause={parts.some((p: any) => p.is_bot)}
      />

      {game.status !== "open" && (
        <GameSocialFab gameId={id} gameSlug="domino" participants={parts} />
      )}
    </main>
  );
}


