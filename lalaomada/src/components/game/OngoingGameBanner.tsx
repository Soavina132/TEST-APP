import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { Trophy, LogOut, X } from "lucide-react";

const ROUTE: Record<string, string> = {
  ludo:     "/jeux/ludo/$id",
  chess:    "/jeux/chess/$id",
  domino:   "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  rami:     "/jeux/rami/$id",
};

const EMOJI: Record<string, string> = {
  ludo: "🎲", chess: "♜", domino: "🁣", fanorona: "♟", rami: "🂡",
};

const LABEL: Record<string, string> = {
  ludo: "Ludo", chess: "Échecs", domino: "Domino", fanorona: "Fanorona", rami: "Rami",
};

// RPC function name + param for each game type's quit/forfeit
const QUIT_RPC: Record<string, { fn: string; param: string }> = {
  ludo:     { fn: "ludo_quit",          param: "_game_id" },
  chess:    { fn: "chess_forfeit",      param: "_id" },
  domino:   { fn: "domino_forfeit",     param: "_game_id" },
  fanorona: { fn: "fanorona_forfeit",   param: "_game_id" },
  rami:     { fn: "rami_forfeit",       param: "_game_id" },
};

type OngoingGame = {
  id: string;
  game_type: string;
  status: string;
  stake: number;
  pot: number;
  eliminated: boolean;
  players_count: number;
  is_private?: boolean;
  room_code?: string;
  created_at: string;
};

export default function OngoingGameBanner() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const [games, setGames] = useState<OngoingGame[]>([]);
  const [dismissed, setDismissed] = useState(false);
  const [quitting, setQuitting] = useState<string | null>(null);

  const load = useCallback(async () => {
    if (!user) return;
    const { data } = await supabase.rpc("my_ongoing_all" as any);
    const list = Array.isArray(data) ? (data as any[]) : [];
    // Only show games that are actively playing (not just open/waiting)
    // and where the user is not eliminated
    const active = list.filter((g: any) => !g.eliminated && g.status === "playing");
    setGames(active);
  }, [user]);

  useEffect(() => {
    load();
    if (!user) return;
    let debounce: ReturnType<typeof setTimeout>;
    const debouncedLoad = () => { clearTimeout(debounce); debounce = setTimeout(load, 500); };
    const ch = supabase.channel(`ongoing-banner-${user.id}`);
    ["ludo_games", "domino_games", "fanorona_games", "chess_games", "rami_games"].forEach(t => {
      ch.on("postgres_changes" as any, { event: "UPDATE", schema: "public", table: t, filter: "status=eq.playing" }, debouncedLoad);
    });
    ch.subscribe();
    return () => { clearTimeout(debounce); supabase.removeChannel(ch); };
  }, [user, load]);

  // Reset dismissed if games change
  useEffect(() => {
    if (games.length === 0) setDismissed(false);
  }, [games.length]);

  if (dismissed || games.length === 0) return null;

  const rejoin = (g: OngoingGame) => {
    const route = ROUTE[g.game_type];
    if (route) navigate({ to: route as any, params: { id: g.id } as any });
  };

  const quitGame = async (g: OngoingGame) => {
    setQuitting(g.id);
    try {
      const rpc = QUIT_RPC[g.game_type];
      if (rpc) {
        // Call the proper backend function — handles refund, payout, transactions
        await supabase.rpc(rpc.fn as any, { [rpc.param]: g.id } as any);
      }
      setGames(prev => prev.filter(x => x.id !== g.id));
    } catch (e) {
      // ignore
    } finally {
      setQuitting(null);
    }
  };

  return (
    <div className="rounded-2xl bg-amber-500/10 border border-amber-500/25 p-3 space-y-2">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2 text-amber-600 dark:text-amber-400">
          <Trophy className="w-4 h-4" />
          <span className="font-bold text-xs">Partie{games.length > 1 ? "s" : ""} en cours</span>
        </div>
        <button onClick={() => setDismissed(true)} className="text-muted-foreground hover:text-foreground p-1">
          <X className="w-3.5 h-3.5" />
        </button>
      </div>

      {games.map(g => (
        <div key={g.id} className="flex items-center gap-2.5 bg-card rounded-xl p-2.5 border border-border/40">
          <div className="w-9 h-9 rounded-lg bg-amber-500/15 grid place-items-center text-base shrink-0">
            {EMOJI[g.game_type] ?? "🎮"}
          </div>
          <div className="min-0 flex-1">
            <div className="font-bold text-sm">{LABEL[g.game_type] ?? g.game_type}</div>
            <div className="text-[10px] text-muted-foreground">
              {Number(g.stake || 0).toLocaleString("fr-FR")} Ar · {g.players_count} joueurs
            </div>
          </div>
          <div className="flex items-center gap-1.5 shrink-0">
            <button
              onClick={() => rejoin(g)}
              className="flex items-center gap-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground font-bold text-[11px] shadow-sm active:scale-95 transition"
            >
              <Trophy className="w-3 h-3" /> Rejoindre
            </button>
            <button
              onClick={() => quitGame(g)}
              disabled={quitting === g.id}
              className="flex items-center gap-1 px-3 py-2 rounded-lg bg-destructive/10 text-destructive font-bold text-[11px] active:scale-95 transition disabled:opacity-50"
            >
              {quitting === g.id ? "…" : <><LogOut className="w-3 h-3" /> Quitter</>}
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
