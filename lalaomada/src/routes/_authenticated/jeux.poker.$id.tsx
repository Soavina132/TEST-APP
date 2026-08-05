import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { serverNow } from "@/lib/server-time";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";
import { useGameConnection } from "@/hooks/game/use-game-connection";
import { GameReconnectOverlay } from "@/components/game/GameReconnectOverlay";
import { ArrowLeft, Copy, Check, Timer, Plus } from "lucide-react";
import GameSocialFab from "@/components/game/GameSocialFab";
import GamePauseControl from "@/components/game/GamePauseControl";
import GameEndScreen from "@/components/game/GameEndScreen";
import GameWaitingRoom from "@/components/game/GameWaitingRoom";
import { useConfirm } from "@/components/ConfirmDialog";

export const Route = createFileRoute("/_authenticated/jeux/poker/$id")({
  component: PokerPage,
  head: () => ({ meta: [{ title: "Poker — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

// ── Card encoding ─────────────────────────────────────────────────────────
const SUITS = ["♠","♥","♦","♣"];
const SUIT_COLORS = ["#0f172a","#dc2626","#dc2626","#0f172a"];
const RANKS = ["A","2","3","4","5","6","7","8","9","10","J","Q","K"];
const HAND_LABELS: Record<string,string> = {
  "Quinte Royale": "Quinte Royale 👑",
  "Quinte Flush": "Quinte Flush",
  "Carré": "Carré",
  "Full House": "Full House",
  "Couleur": "Couleur (Flush)",
  "Suite": "Suite",
  "Brelan": "Brelan",
  "Double Paire": "Double Paire",
  "Paire": "Paire",
  "Hauteur": "Hauteur",
};

// ── Playing Card SVG ──────────────────────────────────────────────────────
function CardBack({ w = 56, h = 84 }: { w?: number; h?: number }) {
  return (
    <svg width={w} height={h} viewBox="0 0 56 84" style={{ borderRadius: 6 }}>
      <rect x="0" y="0" width="56" height="84" rx="6" fill="#1e40af"/>
      <rect x="3" y="3" width="50" height="78" rx="5" fill="none" stroke="#3b82f6" strokeWidth="1.5"/>
      {Array.from({length:8},(_,r)=>Array.from({length:6},(_,c)=>(
        <text key={`${r}-${c}`} x={4+c*8} y={10+r*10} fontSize="8" fill="#3b82f680" fontFamily="serif">♦</text>
      )))}
    </svg>
  );
}

function PlayingCard({ c, w = 56, h = 84, faceDown }: { c: number; w?: number; h?: number; faceDown?: boolean }) {
  if (faceDown) return <CardBack w={w} h={h}/>;
  const s = Math.floor(c / 13); const r = c % 13;
  const rank = RANKS[r]; const suit = SUITS[s]; const color = SUIT_COLORS[s];
  const fs = Math.round(w * 0.22);
  return (
    <svg width={w} height={h} viewBox="0 0 56 84" style={{ borderRadius: 6, filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.3))" }}>
      <rect x="0" y="0" width="56" height="84" rx="6" fill="white" stroke="#e2e8f0" strokeWidth="1"/>
      <text x="4" y={fs+3} fontSize={fs} fontWeight="bold" fontFamily="Arial,sans-serif" fill={color}>{rank}</text>
      <text x="4" y={fs*2+4} fontSize={fs*0.85} fontFamily="Arial,sans-serif" fill={color}>{suit}</text>
      <text x="28" y="48" fontSize={Math.round(w*0.52)} fontFamily="Arial,sans-serif" fill={color} textAnchor="middle" dominantBaseline="middle">{suit}</text>
      <text x="52" y={h-3} fontSize={fs} fontWeight="bold" fontFamily="Arial,sans-serif" fill={color} textAnchor="end" transform="rotate(180,52,75)">{rank}</text>
    </svg>
  );
}

// ── Chip display ──────────────────────────────────────────────────────────
function Chips({ amount, size = "sm" }: { amount: number; size?: "sm"|"xs" }) {
  const fmt = (n: number) => n >= 1000 ? `${(n/1000).toFixed(n%1000===0?0:1)}k` : String(n);
  const cls = size === "xs" ? "text-[9px] px-1.5 py-0.5" : "text-xs px-2 py-1";
  return (
    <span className={`font-mono font-extrabold rounded-full bg-black/60 text-amber-400 ${cls}`}>
      {fmt(amount)}
    </span>
  );
}

// ── Seat position calculator ──────────────────────────────────────────────
function seatPos(idx: number, myIdx: number, total: number, rx: number, ry: number, cx: number, cy: number) {
  const angleDeg = 90 + (360 * ((idx - myIdx + total) % total)) / total;
  const a = (angleDeg * Math.PI) / 180;
  return { x: cx + rx * Math.cos(a), y: cy + ry * Math.sin(a) };
}

// ── Player seat component ─────────────────────────────────────────────────
function PlayerSeat({
  player, idx, myIdx, total, cx, cy, rx, ry,
  isActive, dealerSeat, sbSeat, bbSeat, commCards,
}: {
  player: any; idx: number; myIdx: number; total: number;
  cx: number; cy: number; rx: number; ry: number;
  isActive: boolean; dealerSeat: number; sbSeat: number; bbSeat: number;
  commCards: number[];
}) {
  const { x, y } = seatPos(idx, myIdx, total, rx, ry, cx, cy);
  const seat = player.seat;
  const isMe = idx === 0;
  const folded = player.status === "folded";
  const allIn = player.status === "all_in";
  const finished = player.result;

  return (
    <div className="absolute" style={{ left: x - 50, top: y - 52, width: 100, zIndex: isMe ? 10 : 5 }}>
      <div className={`flex flex-col items-center gap-0.5 transition-all duration-300 ${folded ? "opacity-40 grayscale" : ""}`}>
        {/* Cards (face down for others, unless showdown) */}
        {player.hole_cards?.length > 0 && !isMe && (
          <div className="flex gap-0.5 mb-1">
            {player.hole_cards.map((c: number, i: number) => (
              <PlayingCard key={i} c={c} w={24} h={36} faceDown={!finished} />
            ))}
          </div>
        )}
        {/* Avatar ring */}
        <div className={`relative w-14 h-14 rounded-full border-2 flex items-center justify-center font-bold text-sm shadow-xl
          ${isActive ? "border-amber-400 shadow-amber-500/60" : isMe ? "border-emerald-400" : "border-white/30"}
          bg-gradient-to-br from-slate-600 to-slate-900 text-white`}
          style={isActive ? { animation: "pulse 1.5s ease-in-out infinite", boxShadow: "0 0 20px rgba(251,191,36,0.5)" } : {}}>
          {player.pseudo?.slice(0,2)?.toUpperCase() || "??"}
          {/* Dealer / SB / BB badges */}
          {seat === dealerSeat && (
            <span className="absolute -top-1 -right-1 w-5 h-5 bg-white text-black text-[9px] font-extrabold rounded-full flex items-center justify-center shadow border border-gray-300">D</span>
          )}
          {seat === sbSeat && seat !== dealerSeat && (
            <span className="absolute -top-1 -left-1 bg-blue-500 text-white text-[8px] font-bold rounded-full px-1 leading-5">SB</span>
          )}
          {seat === bbSeat && seat !== dealerSeat && (
            <span className="absolute -top-1 -left-1 bg-red-500 text-white text-[8px] font-bold rounded-full px-1 leading-5">BB</span>
          )}
          {allIn && !finished && (
            <span className="absolute -bottom-1 left-1/2 -translate-x-1/2 bg-amber-500 text-black text-[8px] font-extrabold rounded px-1 whitespace-nowrap">ALL IN</span>
          )}
        </div>
        {/* Name */}
        <div className={`text-center rounded-xl px-2 py-0.5 max-w-full ${isMe ? "bg-emerald-900/80" : "bg-black/70"}`}>
          <div className="text-[10px] font-bold text-white truncate max-w-[80px]">{player.pseudo || "Joueur"}</div>
          <Chips amount={player.chips} size="xs"/>
        </div>
        {/* Bet amount (chip in center direction) */}
        {player.bet_round > 0 && (
          <div className="mt-0.5 bg-amber-500 text-black text-[8px] font-extrabold rounded-full px-2 py-0.5 shadow-md">
            {player.bet_round.toLocaleString("fr-FR")}
          </div>
        )}
        {/* Hand result at showdown */}
        {finished && player.hole_cards?.length > 0 && (
          <div className="text-[9px] bg-emerald-600 text-white px-1 rounded font-bold mt-0.5">
            {HAND_LABELS[finished.label] || finished.label}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────
function PokerPage() {
  const { id } = Route.useParams();
  const { user, profile, isAdmin, refreshProfile } = useAuth();
  const navigate = useNavigate();
  const confirm = useConfirm();

  const [game, setGame] = useState<any>(null);
  const [players, setPlayers] = useState<any[]>([]);
  const [profilesMap, setProfilesMap] = useState<Record<string,any>>({});
  const [copied, setCopied] = useState(false);
  const [raiseAmt, setRaiseAmt] = useState(0);
  const [busy, setBusy] = useState(false);
  const [timeLeft, setTimeLeft] = useState(30);
  const [betweenHands, setBetweenHands] = useState(false);
  const [countdown, setCountdown] = useState(5);

  const load = useCallback(async () => {
    const { data: g } = await supabase.from("poker_games" as any).select("*").eq("id", id).maybeSingle();
    setGame(g);
    // Explicit column projection — hole_cards is column-privilege restricted server-side
    const { data: ps } = await supabase
      .from("poker_players" as any)
      .select("id,game_id,user_id,seat,chips,bet_round,total_bet,status,is_ready,last_action,hand_result,joined_at")
      .eq("game_id", id)
      .order("seat");
    let playersArr = ((ps as any[]) || []).map((p: any) => ({ ...p, hole_cards: [] as number[] }));

    // Fetch hole cards only for rows the caller is allowed to see (own + finished games + admin)
    const { data: hc } = await supabase.rpc("poker_my_hole_cards" as any, { _game_id: id } as any);
    if (Array.isArray(hc)) {
      const byUser: Record<string, number[]> = {};
      (hc as any[]).forEach((r: any) => { byUser[r.user_id] = r.hole_cards || []; });
      playersArr = playersArr.map((p: any) => byUser[p.user_id] ? { ...p, hole_cards: byUser[p.user_id] } : p);
    }
    setPlayers(playersArr);

    const ids = playersArr.map((p: any) => p.user_id).filter(Boolean);
    if (ids.length) {
      const { data: profs } = await supabase.from("profiles").select("id,pseudo,avatar_url").in("id", ids);
      const m: Record<string,any> = {};
      (profs || []).forEach((p: any) => { m[p.id] = p; });
      setProfilesMap(prev => ({ ...prev, ...m }));
    }
  }, [id, profile?.id]);

  useEffect(() => { load(); }, [load]);

  useEffect(() => {
    const ch = supabase.channel(`poker-${id}`)
      .on("postgres_changes", { event: "*", schema: "public", table: "poker_games", filter: `id=eq.${id}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "poker_players", filter: `game_id=eq.${id}` }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [id, load]);

  const { isConnected, isReconnecting, retry } = useGameConnection({ onReconnect: load });

  // Timer
  useEffect(() => {
    if (!game?.turn_deadline || game.status !== "playing") { setTimeLeft(30); return; }
    const tick = () => {
      const ms = new Date(game.turn_deadline).getTime() - serverNow();
      setTimeLeft(Math.max(0, Math.ceil(ms / 1000)));
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [game?.turn_deadline, game?.status]);

  // Between-hands countdown
  useEffect(() => {
    if (game?.phase !== "between_hands") { setBetweenHands(false); return; }
    setBetweenHands(true);
    setCountdown(5);
    const t = setInterval(() => {
      setCountdown(c => {
        if (c <= 1) {
          clearInterval(t);
          supabase.rpc("poker_start_next_hand" as any, { _game_id: id } as any).then(load);
          return 0;
        }
        return c - 1;
      });
    }, 1000);
    return () => clearInterval(t);
  }, [game?.phase, id, load]);

  // Auto-navigate cancelled
  useEffect(() => {
    if (game?.status !== "cancelled") return;
    toast.info("Partie annulée — mise remboursée");
    const t = setTimeout(() => navigate({ to: "/jeux/$slug", params: { slug: "poker" }, search: {} }), 1500);
    return () => clearTimeout(t);
  }, [game?.status, navigate]);

  if (!game) return <div className="p-8 text-center text-muted-foreground">Chargement…</div>;

  const me = players.find(p => p.user_id === user?.id);
  const isPlayer = !!me;
  const myIdx = me ? players.findIndex(p => p.user_id === user?.id) : 0;
  const isMyTurn = game.current_player === user?.id;
  const state = game.state || {};
  const curBet: number = Number(state.current_bet || 0);
  const callAmt: number = Math.max(0, curBet - Number(me?.bet_round || 0));
  const canCheck = callAmt === 0;
  const community: number[] = game.community_cards || [];
  const dealerSeat: number = state.dealer_seat ?? -1;
  const sbSeat: number = state.sb_seat ?? -1;
  const bbSeat: number = state.bb_seat ?? -1;
  const myChips = Number(me?.chips || 0);
  // Relance minimale identique au serveur : mise courante + dernière relance (≥ grosse blinde)
  const bigBlind = Number(state.big_blind || game.big_blind || 20);
  const lastRaise = Math.max(Number(state.last_raise || 0), bigBlind);
  const maxTotal = myChips + Number(me?.bet_round || 0);
  const minRaise = Math.min(curBet + lastRaise, maxTotal);
  const canRaise = maxTotal > curBet;

  // Layout
  const W = 680; const H = 620;
  const cx = W / 2; const cy = H / 2 - 20;
  const rx = Math.min(W * 0.38, 240);
  const ry = Math.min(H * 0.33, 190);

  // Enrich players with profile data
  const enriched = players.map(p => ({
    ...p,
    pseudo: profilesMap[p.user_id]?.pseudo || "?",
    result: p.hand_result,
  }));

  const phaseLabelMap: Record<string,string> = {
    waiting:"En attente", preflop:"Pré-Flop", flop:"Flop", turn:"Turn", river:"River", showdown:"Abattage", between_hands:"Prochaine main…", finished:"Terminé",
  };

  const doAction = async (action: string, amount?: number) => {
    if (busy) return;
    setBusy(true);
    try {
      const { error } = await supabase.rpc("poker_action" as any, {
        _game_id: id, _action: action, _amount: amount ?? 0,
      } as any);
      if (error) toast.error(error.message);
      else await load();
    } finally { setBusy(false); }
  };

  const setReady = async (ready: boolean) => {
    const { error } = await supabase.rpc("poker_set_ready" as any, { _game_id: id, _ready: ready } as any);
    if (error) toast.error(error.message);
  };

  const copyCode = () => {
    if (game.room_code) { copyText(game.room_code).then(ok => { if (ok) { setCopied(true); setTimeout(()=>setCopied(false),2000); } else toast.error("Impossible de copier"); }); }
  };

  const refund = async () => {
    const ok = await confirm({ title:"Annuler la partie ?", description:"Votre mise sera remboursée.", confirmLabel:"Annuler", destructive:true });
    if (!ok) return;
    const { error } = await supabase.rpc("poker_request_refund" as any, { _game_id: id } as any);
    if (error) toast.error(error.message);
    else { toast.success("Mise remboursée"); refreshProfile(); navigate({ to:"/jeux/$slug", params:{slug:"poker"}, search:{} }); }
  };

  // ── Waiting room ─────────────────────────────────────────────────────────
  if (game.status === "waiting") {
    const seatParts = enriched.map((p: any) => ({
      id: p.id,
      user_id: p.user_id,
      display_name: p.pseudo || "Joueur",
      avatar_url: profilesMap[p.user_id]?.avatar_url,
      slot: p.seat,
      ready: !!p.is_ready,
    }));
    const canAddBot = (isAdmin || (Number(game.stake) === 0 && isPlayer)) && players.length < game.max_players;
    const quitPoker = async () => {
      if (game.created_by === user?.id && players.length === 1) {
        await refund();
        return;
      }
      navigate({ to: "/jeux/$slug", params: { slug: "poker" }, search: {} });
    };
    return (
      <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
        <GameWaitingRoom
          isTournament={!!game.tournament_match_id}
          slug="poker"
          gameLabel={`Poker · ${game.max_players} joueurs`}
          parts={seatParts}
          maxPlayers={game.max_players}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          roomCode={game.is_private ? game.room_code : null}
          shareSlug="poker"
          meUserId={user?.id}
          isParticipant={isPlayer}
          createdAt={(game as any).created_at}
          onQuit={quitPoker}
          onToggleReady={async (ready) => { await setReady(ready); }}
        />
        {canAddBot && (
          <button
            onClick={async () => {
              const { error } = await supabase.rpc("poker_add_bot" as any, { _game_id: id, _bot_name: "Bot" } as any);
              if (error) toast.error(error.message); else toast.success("Bot ajouté");
            }}
            className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold flex items-center gap-2"
          >
            <Plus className="w-4 h-4" /> Ajouter un bot
          </button>
        )}
      </main>
    );
  }

  // ── Finished ─────────────────────────────────────────────────────────────
  if (game.status === "finished") {
    const winner = enriched.find(p => p.user_id === game.winner_id);
    const gross = game.pot + (game.stake * players.length);
    return (
      <main className="max-w-3xl mx-auto px-4 py-10">
        <GameEndScreen
          slug="poker"
          meUserId={user?.id}
          winnerId={game.winner_id}
          participants={enriched as any}
          stake={Number(game.stake) || 0}
          pot={Number(game.pot) || 0}
          commissionPct={Number((game as any).commission_pct) || 10}
          onReplay={async () => {
            const { data, error } = await supabase.rpc("poker_create" as any, {
              _stake: Number(game.stake) || 0,
              _max: game.max_players,
              _private: !!(game as any).is_private,
              _commission: Number((game as any).commission_pct) || 10,
            } as any);
            if (error) { toast.error(error.message); return; }
            navigate({ to: "/jeux/poker/$id", params: { id: String(data) } });
          }}
        />
      </main>
    );
  }

  // ── In-game board ─────────────────────────────────────────────────────────
  return (
    <main className="flex flex-col h-full overflow-hidden overscroll-none" style={{ background: "radial-gradient(ellipse at 50% 30%, #166534 0%, #14532d 50%, #052e16 100%)" }}>
      <GameReconnectOverlay isConnected={isConnected} isReconnecting={isReconnecting} onRetry={retry} />
      {/* Top bar */}
      <div className="flex items-center justify-between px-4 py-2 bg-black/40 backdrop-blur z-20">
        <button onClick={() => navigate({ to:"/jeux/$slug", params:{slug:"poker"}, search:{} })} className="p-1.5 rounded-lg hover:bg-white/10 text-white">
          <ArrowLeft className="w-5 h-5"/>
        </button>
        <div className="text-center">
          <div className="text-white font-bold text-sm">{phaseLabelMap[game.phase] || game.phase}</div>
          <div className="text-white/60 text-xs">Main #{game.hand_number} · Pot {game.pot?.toLocaleString("fr-FR")} Ar</div>
        </div>
        <div className="flex items-center gap-2">
          {game.room_code && (
            <button onClick={copyCode} className="flex items-center gap-1 px-2 py-1 rounded-lg bg-white/10 text-white text-xs">
              {copied ? <Check className="w-3 h-3"/> : <Copy className="w-3 h-3"/>} {game.room_code}
            </button>
          )}
          <GameSocialFab gameId={id} gameSlug="poker" participants={enriched} />
        </div>
      </div>

      {/* Between-hands countdown */}
      {betweenHands && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 pointer-events-none">
          <div className="bg-black/80 text-white rounded-3xl px-10 py-8 text-center space-y-2 shadow-2xl">
            <div className="text-2xl font-extrabold">Prochaine main</div>
            <div className="text-6xl font-extrabold text-amber-400">{countdown}</div>
            <div className="text-white/60 text-sm">Préparation en cours…</div>
          </div>
        </div>
      )}

      {/* Poker table */}
      <div className="flex-1 relative overflow-hidden">
        <div className="absolute inset-0 flex items-center justify-center">
          <div className="relative" style={{ width: W, height: H }}>
            {/* Table felt */}
            <div className="absolute rounded-[50%] shadow-2xl" style={{
              left: cx - rx - 28, top: cy - ry - 28,
              width: (rx + 28) * 2, height: (ry + 28) * 2,
              background: "radial-gradient(ellipse at 40% 35%, #22c55e 0%, #16a34a 40%, #15803d 70%, #166534 100%)",
              boxShadow: "0 0 0 14px #7c3f00, 0 0 0 24px #5c2d00, 0 30px 80px rgba(0,0,0,0.6)",
              border: "4px solid #a16207",
            }}/>

            {/* Community cards */}
            <div className="absolute flex gap-1.5 items-center" style={{ left: cx - 150, top: cy - 42 }}>
              {[...Array(5)].map((_,i) => (
                <div key={i} style={{ transform: `rotate(${(i-2)*2}deg)` }}>
                  {i < community.length
                    ? <PlayingCard c={community[i]} w={52} h={78}/>
                    : <div className="rounded-lg border-2 border-white/20 bg-white/5" style={{width:52,height:78}}/>
                  }
                </div>
              ))}
            </div>

            {/* Pot display */}
            <div className="absolute" style={{ left: cx - 60, top: cy + 45, width: 120 }}>
              <div className="text-center">
                <div className="text-white/50 text-[9px] uppercase tracking-widest">Pot</div>
                <div className="text-amber-400 font-extrabold text-xl leading-none">
                  {Number(game.pot || 0).toLocaleString("fr-FR")}
                </div>
              </div>
            </div>

            {/* Phase label */}
            {game.phase !== "between_hands" && (
              <div className="absolute" style={{ left: cx - 50, top: cy - 70, width: 100 }}>
                <div className="text-center bg-black/50 rounded-full px-3 py-1">
                  <span className="text-white/80 text-[10px] font-bold uppercase tracking-wider">{phaseLabelMap[game.phase]}</span>
                </div>
              </div>
            )}

            {/* Player seats */}
            {enriched.map((p, i) => (
              <PlayerSeat key={p.id} player={p} idx={(i - myIdx + enriched.length) % enriched.length}
                myIdx={0} total={enriched.length} cx={cx} cy={cy} rx={rx} ry={ry}
                isActive={game.current_player === p.user_id}
                dealerSeat={dealerSeat} sbSeat={sbSeat} bbSeat={bbSeat} commCards={community}/>
            ))}
          </div>
        </div>
      </div>

      {/* My hole cards */}
      {me?.hole_cards?.length > 0 && (
        <div className="flex justify-center gap-4 py-2">
          {me.hole_cards.map((c: number, i: number) => (
            <div key={i} style={{ transform: `rotate(${i===0?-8:8}deg)`, marginTop: i===0?0:-4 }}>
              <PlayingCard c={c} w={64} h={96}/>
            </div>
          ))}
        </div>
      )}

      {/* Timer bar */}
      {isMyTurn && game.status === "playing" && (
        <div className="px-4 pb-1">
          <div className="flex items-center gap-2">
            <Timer className="w-4 h-4 text-amber-400 flex-shrink-0"/>
            <div className="flex-1 h-2 bg-white/10 rounded-full overflow-hidden">
              <div className="h-full bg-amber-400 transition-all duration-500 rounded-full" style={{ width: `${(timeLeft / 30) * 100}%` }}/>
            </div>
            <span className={`text-sm font-mono font-bold ${timeLeft <= 5 ? "text-red-400 animate-pulse" : "text-white"}`}>{timeLeft}s</span>
          </div>
        </div>
      )}

      {/* Action zone */}
      {isPlayer && isMyTurn && game.status === "playing" && me?.status === "playing" && (
        <div className="px-3 pb-4 space-y-2">
          {/* Raise slider */}
          {canRaise && maxTotal > minRaise && (
            <div className="rounded-2xl bg-black/70 backdrop-blur px-4 py-3 space-y-2">
              <div className="flex justify-between items-center text-xs">
                <span className="text-white/60">Relance</span>
                <span className="font-extrabold text-amber-400">{raiseAmt.toLocaleString("fr-FR")} jetons</span>
              </div>
              <input type="range" min={minRaise} max={maxTotal} step={bigBlind}
                value={raiseAmt || minRaise}
                onChange={e => setRaiseAmt(Number(e.target.value))}
                className="w-full accent-amber-400"/>
              <div className="grid grid-cols-4 gap-1">
                {[
                  { l:"½ Pot", v: Math.round((game.pot||0)/2) },
                  { l:"Pot",   v: game.pot||0 },
                  { l:"2×Pot", v: (game.pot||0)*2 },
                  { l:"Tapis", v: maxTotal },
                ].map(({ l, v }) => (
                  <button key={l} onClick={() => setRaiseAmt(Math.min(Math.max(v, minRaise), maxTotal))}
                    className="py-1.5 rounded-xl text-[10px] font-bold bg-white/10 text-white hover:bg-amber-500/30 transition-colors">
                    {l}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Action buttons */}
          <div className="grid gap-2" style={{ gridTemplateColumns: myChips > 0 ? "1fr 1fr 1fr" : "1fr 1fr" }}>
            <button disabled={busy} onClick={() => doAction("fold")}
              className="py-4 rounded-2xl bg-rose-700/90 hover:bg-rose-600 active:scale-95 text-white font-extrabold text-sm transition-all shadow-lg disabled:opacity-50">
              🃏 Passer
            </button>

            {canCheck ? (
              <button disabled={busy} onClick={() => doAction("check")}
                className="py-4 rounded-2xl bg-slate-600/90 hover:bg-slate-500 active:scale-95 text-white font-extrabold text-sm transition-all shadow-lg disabled:opacity-50">
                ✓ Checker
              </button>
            ) : (
              <button disabled={busy} onClick={() => doAction("call")}
                className="py-4 rounded-2xl bg-blue-600/90 hover:bg-blue-500 active:scale-95 text-white font-extrabold text-sm transition-all shadow-lg disabled:opacity-50">
                📞 Suivre<br/><span className="text-xs font-normal opacity-80">{Math.min(callAmt,myChips).toLocaleString()}</span>
              </button>
            )}

            {canRaise && (
              <button disabled={busy} onClick={() => {
                const amt = Math.min(Math.max(raiseAmt || minRaise, minRaise), maxTotal);
                if (amt >= maxTotal) return doAction("allin");
                doAction(curBet === 0 ? "bet" : "raise", amt);
              }}
                className="py-4 rounded-2xl font-extrabold text-sm transition-all shadow-lg active:scale-95 text-black disabled:opacity-50"
                style={{ background: "linear-gradient(135deg,#f59e0b,#d97706)" }}>
                ↑ {curBet===0?"Miser":"Relancer"}<br/><span className="text-xs font-normal opacity-80">{Math.min(Math.max(raiseAmt||minRaise,minRaise),maxTotal).toLocaleString()}</span>
              </button>
            )}
          </div>

          {/* All-In */}
          {myChips > 0 && (
            <button disabled={busy} onClick={() => doAction("allin")}
              className="w-full py-3.5 rounded-2xl font-extrabold text-sm shadow-xl active:scale-95 transition-all text-white disabled:opacity-50"
              style={{ background: "linear-gradient(135deg,#7f1d1d,#dc2626)" }}>
              🔥 TAPIS — {myChips.toLocaleString("fr-FR")} jetons
            </button>
          )}
        </div>
      )}

      {/* Spectator or waiting */}
      {isPlayer && !isMyTurn && game.status === "playing" && me?.status === "playing" && (
        <div className="px-4 pb-4">
          <div className="rounded-2xl bg-black/50 text-white/60 text-center py-4 text-sm font-medium">
            En attente de votre tour…
          </div>
        </div>
      )}
      {isPlayer && me?.status === "folded" && (
        <div className="px-4 pb-4">
          <div className="rounded-2xl bg-black/50 text-rose-400 text-center py-4 text-sm font-medium">
            Vous avez passé cette main.
          </div>
        </div>
      )}
      <GamePauseControl
        slug="poker"
        gameId={id}
        game={game}
        remaining={timeLeft}
        totalSeconds={30}
        isMyTurn={isMyTurn}
        isPlayer={isPlayer}
        myUserId={user?.id ?? null}
      />
    </main>
  );
}
