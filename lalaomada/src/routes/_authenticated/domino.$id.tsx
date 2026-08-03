import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { useGameConnection } from "@/hooks/use-game-connection";
import { GameReconnectOverlay } from "@/components/GameReconnectOverlay";
import { LogOut, Copy, Plus, Pause } from "lucide-react";
import GameChatDrawer from "@/components/GameChatDrawer";
import GamePauseControl from "@/components/GamePauseControl";
import GameInstructionsBanner from "@/components/GameInstructionsBanner";
import GameEndScreen from "@/components/GameEndScreen";
import GameWaitingRoom from "@/components/GameWaitingRoom";
import DominoRoundBreak from "@/components/DominoRoundBreak";
import DominoTable, { DominoTile, PlayerHeader } from "@/components/DominoTable";
import { useGameConfig } from "@/hooks/use-game-config";
import { useConfirm } from "@/components/ConfirmDialog";
import TurnBanner from "@/components/TurnBanner";
import { useDominoSounds } from "@/hooks/use-domino-sounds";
import { playClack, playDraw, playPass } from "@/lib/game-sounds";


export const Route = createFileRoute("/_authenticated/domino/$id")({
  component: DominoPage,
  head: () => ({ meta: [{ title: "Domino — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

type Tile = [number, number];

type BoardEntry = { tile: Tile; flipped: boolean };

function readBoardTile(entry: unknown): Tile | null {
  const rawTile = Array.isArray(entry) ? entry : (entry as { tile?: unknown } | null)?.tile;
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
  const { profile, isAdmin } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();
  const [game, setGame] = useState<any>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [selectedTile, setSelectedTile] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
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

  const load = useCallback(async () => {
    const { data: g } = await supabase.from("domino_games" as any).select("*").eq("id", id).maybeSingle();
    setGame(g);
    const { data: p } = await supabase.from("domino_participants" as any).select("*").eq("game_id", id).order("slot");
    const rows = (p as any[]) || [];
    // Give bots a synthetic key ("bot_<slot>") matching the backend so score /
    // winner lookups keyed by user_id keep working when a bot is involved.
    const ids = rows.map(r => r.user_id).filter(Boolean);
    let byId = new Map<string, string | null>();
    if (ids.length) {
      const { data: profs } = await supabase.from("profiles").select("id, avatar_url").in("id", ids);
      byId = new Map((profs || []).map((x: any) => [x.id, x.avatar_url]));
    }
    setParts(rows.map(r => ({
      ...r,
      user_id: r.user_id || `bot_${r.slot}`,
      avatar_url: r.user_id ? (byId.get(r.user_id) || null) : null,
    })));
  }, [id]);

  // ── Sound effects ──────────────────────────────────────────────────────
  useDominoSounds({ game, parts, myUserId: profile?.id });

  useEffect(() => {
    load();
    const ch = supabase.channel("domino-"+id)
      .on("postgres_changes", { event: "*", schema: "public", table: "domino_games", filter: `id=eq.${id}` }, () => load())
      .on("postgres_changes", { event: "*", schema: "public", table: "domino_participants", filter: `game_id=eq.${id}` }, () => load())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });

  useEffect(() => {
    if (game?.status === "cancelled") {
      toast.info("Invitation expirée — mise remboursée");
      const t = setTimeout(() => navigate({ to: "/jeux/$slug", params: { slug: "domino" }, search: {} }), 1500);
      return () => clearTimeout(t);
    }
  }, [game?.status, navigate]);


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
      const delay = Math.max(0, new Date(target).getTime() - serverNow()) + 250;
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
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status, phase, game?.state?.reveal_until, game?.state?.break_until, id, cfg.turn_timer_seconds, game]);

  // Re-trigger domino_tick when a bot's "thinking delay" expires, so bot
  // moves appear with the intended pause instead of waiting for the 5s cron.
  useEffect(() => {
    const think = game?.state?.bot_think_until;
    if (!think || game?.status !== "playing") return;
    const ms = new Date(think).getTime() - serverNow();
    const delay = Math.max(0, ms) + 150;
    const t = setTimeout(() => {
      supabase.rpc("domino_tick" as any, { _game_id: id } as any);
    }, delay);
    return () => clearTimeout(t);
  }, [game?.state?.bot_think_until, game?.status, id]);

  const me = parts.find(p => p.user_id === profile?.id);
  const isPlayer = !!me;
  const isMyTurn = game && me && game.current_turn === me.slot && game.status === "playing" && !isRoundTransition;
  const myHand: Tile[] = (game?.state?.hands?.[String(me?.slot)] as Tile[]) || [];
  // Tiles per row: 7 minimum, up to 10 when the hand grew from drawing.
  const handCols = Math.max(7, Math.min(myHand.length, 10));
  const handTileW = Math.max(13, Math.min(28, Math.floor(handAvail / handCols) - 4));
  const normalizedBoard = normalizeDominoBoard(game?.state?.board || [], game?.state?.left_end, game?.state?.right_end);
  const board: { tile: Tile; flipped: boolean }[] = normalizedBoard.board;
  const leftEnd: number | null = normalizedBoard.leftEnd;
  const rightEnd: number | null = normalizedBoard.rightEnd;
  const stockSize: number = (game?.state?.stock || []).length;

  const firstTileRule: "libre" | "under6" = game?.state?.first_tile_rule === "under6" || game?.first_tile_rule === "under6" ? "under6" : "libre";
  const tileMatches = useCallback((t: Tile) => {
    if (board.length === 0) {
      const fd = game?.state?.first_move_double;
      if (typeof fd === "number") return t[0] === fd && t[1] === fd;
      if (firstTileRule === "under6") return (t[0] + t[1]) < 6;
      return true;
    }
    return t[0] === leftEnd || t[1] === leftEnd || t[0] === rightEnd || t[1] === rightEnd;
  }, [board.length, game?.state?.first_move_double, leftEnd, rightEnd, firstTileRule]);
  const canPlay = myHand.some(tileMatches);
  const drawMode: "with" | "without" = game?.state?.draw_mode === "without" ? "without" : "with";

  const noMove = !!(isMyTurn && board.length > 0 && !canPlay && (drawMode === "without" || stockSize === 0));
  const oppNoMove = !!(!isMyTurn && game?.state?.last_pass_by !== undefined && game?.state?.last_pass_by !== me?.slot);

  const draw = async () => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc("domino_play" as any, { _game_id: id, _move: { action: "draw" } } as any);
      if (error) throw error;
      playDraw();
    } catch (e: any) { toast.error(e.message); }
    finally { setBusy(false); }
  };

  const pass = async (opts?: { silent?: boolean }) => {
    setBusy(true);
    try {
      const { error } = await supabase.rpc("domino_play" as any, { _game_id: id, _move: { action: "pass" } } as any);
      if (error) throw error;
      if (!opts?.silent) playPass();
    } catch (e: any) { if (!opts?.silent) toast.error(e.message); }
    finally { setBusy(false); }
  };

  // Auto-pass when player has no valid move. Retries every 2s (not just once)
  // so a transient RPC/network failure, or a stale client-side playability
  // check, can't leave the turn permanently stuck — it keeps trying until the
  // server confirms the pass (noMove flips back to false once state updates).
  // Errors are silent here to avoid toast spam on repeated retries.
  useEffect(() => {
    if (!noMove || busy) return;
    const t = setTimeout(() => {
      pass({ silent: true });
    }, 2000);
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

  if (!game) return <div className="p-6 text-center">Chargement…</div>;

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

        <GameChatDrawer gameId={id} />
      </main>
    );
  }

  // Drag state
  const draggedTile = selectedTile !== null ? myHand[selectedTile] : null;
  const canDropLeft = !!(isMyTurn && draggedTile && (board.length === 0 ? tileMatches(draggedTile) : (draggedTile[0] === leftEnd || draggedTile[1] === leftEnd)));
  const canDropRight = !!(isMyTurn && draggedTile && (board.length === 0 ? tileMatches(draggedTile) : (draggedTile[0] === rightEnd || draggedTile[1] === rightEnd)));
  const canDropAny = !!(isMyTurn && draggedTile && tileMatches(draggedTile));

  const playSide = async (side: "left" | "right" | "auto", tileIndex = selectedTile) => {
    if (tileIndex === null || busy) return;
    const tile = myHand[tileIndex];
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

  return (
    <main className="max-w-md mx-auto px-2 py-1 flex flex-col gap-1" style={{ height: "calc(100dvh - 56px)", background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.05) 0%, transparent 70%)" }}>
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      <div className="rounded-md bg-card/70 border border-white/8 px-2 py-1 flex items-center gap-2 shrink-0 text-xs">
        <span className="font-bold text-sm">🁣</span>
        {Number(game.pot) > 0 ? (
          <span className="flex items-baseline gap-1">
            <span className="text-[9px] uppercase text-muted-foreground tracking-wider">Au gagnant</span>
            <span className="font-extrabold text-sm text-emerald-500">
              {Math.round(Number(game.pot) * (100 - (Number((game as any).commission_pct) || 10)) / 100).toLocaleString("fr-FR")} Ar
            </span>
          </span>
        ) : (
          <span className="text-muted-foreground text-[11px]">Partie gratuite</span>
        )}


        {parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("game_request_pause" as any, { _slug: "domino", _game_id: id } as any);
              if (error) toast.error(error.message);
              else toast.success("Partie en pause");
            }}
            className="ml-auto flex items-center gap-1 px-2 py-1 rounded bg-amber-500/10 text-amber-600 hover:bg-amber-500/20 text-xs font-semibold border border-amber-500/20"
          >
            <Pause className="w-3.5 h-3.5" /> Pause
          </button>
        )}
        {me ? (
          <button onClick={forfeit}
            className={`${parts.some((p: any) => p.is_bot) && game.status === "playing" && !game.paused ? "" : "ml-auto "}flex items-center gap-1 px-2 py-1 rounded bg-destructive/10 text-destructive hover:bg-destructive/20 text-xs font-semibold border border-destructive/20`}>
            <LogOut className="w-3.5 h-3.5" /> Quitter
          </button>
        ) : (
          <button onClick={() => navigate({ to: "/live" })}
            className="ml-auto flex items-center gap-1 px-2 py-1 rounded bg-secondary text-foreground hover:bg-secondary/80 text-xs font-semibold border border-white/10">
            <LogOut className="w-3.5 h-3.5" /> Sortir du live
          </button>
        )}
      </div>



      <div className="flex-1 min-h-0 flex flex-col">
        <DominoTable
          seats={parts.map(p => ({
            user_id: p.user_id,
            display_name: p.display_name,
            avatar_url: p.avatar_url,
            slot: p.slot,
            handCount: (game.state?.hands?.[String(p.slot)] as Tile[])?.length || 0,
            isCurrent: game.current_turn === p.slot && game.status === "playing",
            remaining: game.current_turn === p.slot ? remaining : undefined,
            isMe: p.user_id === profile?.id,
            forfeited: p.forfeited,
            score: Number(game.scores?.[p.user_id] || 0),
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
            const passSlot = game?.state?.last_pass_by;
            const passPart = typeof passSlot === "number" ? parts.find(p => p.slot === passSlot) : null;
            const passName = passPart ? (passPart.user_id === profile?.id ? "Vous" : passPart.display_name) : null;
            const currentPart = parts.find(p => p.slot === game.current_turn);
            const currentName = currentPart ? (currentPart.user_id === profile?.id ? "Vous" : currentPart.display_name) : null;
            if (noMove) return "Aucun domino jouable — votre tour est passé";
            if (oppNoMove && passName) return `${passName} n'a aucun domino jouable — tour passé`;
            if (isMyTurn) return canPlay ? "À vous de jouer" : (drawMode === "with" && stockSize > 0 ? "À vous — piochez pour continuer" : "À vous de jouer");
            if (currentName) return `Tour de ${currentName}…`;
            return undefined;
          })()}
          canDropLeft={canDropLeft}
          canDropRight={canDropRight}
          canDropAny={canDropAny}
          onDropAny={() => { if (canDropAny) playSide("auto"); }}
          onDropLeft={() => { if (canDropLeft) playSide("left"); }}
          onDropRight={() => { if (canDropRight) playSide("right"); }}
        />
      </div>

      {game.status === "finished" && (() => {
        const winnerSlot = game.state?.winner_slot;
        const winnerPart = typeof winnerSlot === "number" ? parts.find(p => p.slot === winnerSlot) : null;
        const effectiveWinnerId = game.winner_id ?? winnerPart?.user_id ?? null;
        return (
          <GameEndScreen
            slug="domino"
            meUserId={profile?.id}
            winnerId={effectiveWinnerId}
            participants={parts}
            stake={Number(game.stake)}
            pot={Number(game.pot)}
            commissionPct={Number(game.commission_pct) || 10}
            onReplay={async () => {
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
              if (error) { toast.error(error.message); return; }
              navigate({ to: "/domino/$id", params: { id: data as string } });
            }}
            extra={Number(game.target_score) > 0 && game.scores ? (
              <div className="text-left rounded-xl bg-secondary/50 p-3 space-y-1.5">
                <div className="text-[10px] uppercase text-muted-foreground tracking-wider font-bold">Scores (objectif {game.target_score})</div>
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
        <div className="space-y-1.5 shrink-0">
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
                  score: Number(game.scores?.[me.user_id] || 0),
                  skips: Number(game.turn_skips?.[me.user_id] || 0),
                  maxSkips: Number(cfg.max_turn_skips) || 5,
                }}
                side="left"
                size="lg"
              />
            </div>
            <div
              className="grid flex-1 gap-1"
              style={{ gridTemplateColumns: `repeat(${handCols}, minmax(0, 1fr))` }}
            >
              {myHand.map((t, i) => {
                const playable = isMyTurn && tileMatches(t);
                const canL = board.length > 0 && (t[0] === leftEnd || t[1] === leftEnd);
                const canR = board.length > 0 && (t[0] === rightEnd || t[1] === rightEnd);
                const needsChoice = playable && canL && canR;
                return (
                  <div key={i} className={`flex justify-center ${playable
                    ? "relative p-0.5 rounded-lg bg-amber-400/15 border-2 border-amber-400 shadow-[0_0_14px_rgba(251,191,36,0.75)] animate-pulse"
                    : "p-0.5 border-2 border-transparent opacity-70"}`}>
                    {playable && (
                      <span className="absolute -top-1.5 -right-1.5 w-3 h-3 rounded-full bg-amber-400 border border-background shadow" />
                    )}
                    <DominoTile t={t} w={handTileW} vertical
                      onClick={playable ? () => {
                        if (needsChoice) {
                          setSelectedTile(selectedTile === i ? null : i);
                        } else {
                          playSide("auto", i);
                        }
                      } : undefined}
                      draggable={playable}
                      onDragStart={() => setSelectedTile(i)}
                      onDragEnd={() => { /* keep selection until drop completes */ }}
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
      <GameChatDrawer gameId={id} />
    </main>
  );
}

