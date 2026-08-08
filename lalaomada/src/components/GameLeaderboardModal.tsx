import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { Trophy, Crown, Medal, X } from "lucide-react";
import { Link } from "@tanstack/react-router";
import { PageLoader } from "@/components/layout/PageLoader";

// ── Level badge (mirrors rankings.tsx) ───────────────────────────────────
const LEVELS = [
  { min: 0, max: 0, icon: "⚪", color: "text-slate-400", bg: "bg-slate-100 dark:bg-slate-800" },
  { min: 1, max: 2, icon: "🟢", color: "text-green-500", bg: "bg-green-100 dark:bg-green-900/30" },
  { min: 3, max: 6, icon: "🔵", color: "text-blue-500", bg: "bg-blue-100 dark:bg-blue-900/30" },
  { min: 7, max: 11, icon: "🟣", color: "text-violet-500", bg: "bg-violet-100 dark:bg-violet-900/30" },
  { min: 12, max: 19, icon: "🟡", color: "text-amber-500", bg: "bg-amber-100 dark:bg-amber-900/30" },
  { min: 20, max: 34, icon: "🟠", color: "text-orange-500", bg: "bg-orange-100 dark:bg-orange-900/30" },
  { min: 35, max: 59, icon: "🔴", color: "text-red-500", bg: "bg-red-100 dark:bg-red-900/30" },
  { min: 60, max: 99, icon: "🏅", color: "text-rose-600", bg: "bg-rose-100 dark:bg-rose-900/30" },
  { min: 100, max: 199, icon: "💎", color: "text-fuchsia-600", bg: "bg-fuchsia-100 dark:bg-fuchsia-900/30" },
  { min: 200, max: Infinity, icon: "👑", color: "text-yellow-500", bg: "bg-yellow-50 dark:bg-yellow-900/20" },
];
function getLevel(wins: number) { return LEVELS.find(l => wins >= l.min && wins <= l.max) ?? LEVELS[0]; }

function RankIcon({ rank }: { rank: number }) {
  if (rank === 1) return <Crown className="w-5 h-5 text-amber-400" />;
  if (rank === 2) return <Medal className="w-5 h-5 text-slate-400" />;
  if (rank === 3) return <Medal className="w-5 h-5 text-orange-400" />;
  return (
    <div className="w-7 h-7 rounded-full bg-secondary flex items-center justify-center font-bold text-xs text-muted-foreground">
      {rank}
    </div>
  );
}

export default function GameLeaderboardModal({
  slug,
  gameLabel,
  onClose,
}: {
  slug: string;
  gameLabel: string;
  onClose: () => void;
}) {
  const { user } = useAuth();
  const [items, setItems] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);
  const [myRank, setMyRank] = useState<number | null>(null);

  useEffect(() => {
    (async () => {
      const { data } = await supabase.rpc("leaderboard_winners" as any, {
        _period: "all",
        _limit: 50,
        _slug: slug,
      } as any);
      const list: any[] = (data as any[]) || [];
      setItems(list);
      if (user) {
        const idx = list.findIndex((p: any) => p.user_id === user.id || p.id === user.id);
        setMyRank(idx >= 0 ? idx + 1 : null);
      }
      setLoading(false);
    })();
  }, [slug, user?.id]);

  return (
    <div
      className="fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4"
      onClick={onClose}
    >
      <div
        className="bg-card rounded-t-3xl sm:rounded-3xl max-w-md w-full shadow-xl max-h-[85vh] overflow-y-auto"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="sticky top-0 z-10 bg-card px-4 pt-4 pb-3 border-b border-border/40">
          <div className="flex items-center justify-between mb-1">
            <div className="flex items-center gap-2">
              <span className="text-xl">🏆</span>
              <div>
                <div className="font-extrabold text-sm">Classement {gameLabel}</div>
                <div className="text-[10px] text-muted-foreground">Top joueurs de ce jeu</div>
              </div>
            </div>
            <button onClick={onClose} className="p-1.5 rounded-full bg-secondary active:scale-90 transition">
              <X className="w-4 h-4" />
            </button>
          </div>
          {myRank && (
            <div className="mt-1.5 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-primary/10 border border-primary/20">
              <Trophy className="w-3 h-3 text-primary" />
              <span className="text-[11px] font-bold text-primary">Votre rang: #{myRank}</span>
            </div>
          )}
        </div>

        {/* Body */}
        <div className="px-3 py-2">
          {loading ? (
            <div className="py-12">
              <PageLoader variant="overlay" label="Chargement du classement…" />
            </div>
          ) : items.length === 0 ? (
            <div className="py-12 text-center text-muted-foreground text-sm">
              Aucune donnée pour {gameLabel} pour le moment
            </div>
          ) : (
            <div className="space-y-0">
              {items.map((p, i) => {
                const rank = i + 1;
                const wins = Number(p.wins ?? 0);
                const isMe = p.user_id === user?.id || p.id === user?.id;
                const lvl = getLevel(wins);
                const podiumBg = rank === 1
                  ? "bg-gradient-to-r from-amber-500/8 to-transparent border-l-4 border-amber-400"
                  : rank === 2
                  ? "bg-gradient-to-r from-slate-400/6 to-transparent border-l-4 border-slate-400/50"
                  : rank === 3
                  ? "bg-gradient-to-r from-orange-500/6 to-transparent border-l-4 border-orange-400/50"
                  : "";

                const inner = (
                  <>
                    <div className="w-8 flex items-center justify-center shrink-0">
                      <RankIcon rank={rank} />
                    </div>
                    {/* Avatar */}
                    <div className="relative shrink-0">
                      <div className={`w-9 h-9 rounded-full bg-secondary overflow-hidden grid place-items-center font-bold text-xs ring-2 ${rank === 1 ? "ring-amber-400/60" : rank === 2 ? "ring-slate-400/40" : rank === 3 ? "ring-orange-400/40" : "ring-transparent"}`}>
                        {p.avatar_url
                          ? <img src={p.avatar_url} alt={p.name ?? "?"} width={36} height={36} loading="lazy" className="w-full h-full object-cover" />
                          : <span>{(p.name ?? "?").slice(0, 2).toUpperCase()}</span>
                        }
                      </div>
                      {rank <= 3 && (
                        <div className="absolute -top-1 -right-1 text-xs">{rank === 1 ? "👑" : rank === 2 ? "🥈" : "🥉"}</div>
                      )}
                    </div>
                    {/* Name + level */}
                    <div className="flex-1 min-w-0 space-y-0.5">
                      <span className={`font-bold text-sm truncate block ${isMe ? "text-primary" : ""}`}>
                        {p.name ?? "Joueur"}{isMe && <span className="text-[10px] text-primary ml-1"> (Vous)</span>}
                      </span>
                      <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${lvl.bg} ${lvl.color}`}>
                        {lvl.icon} {wins} victoires
                      </span>
                    </div>
                    {/* Wins */}
                    <div className="text-right shrink-0">
                      <div className="font-extrabold text-sm tabular-nums flex items-center gap-1 justify-end">
                        <Trophy className="w-3.5 h-3.5 text-amber-500" /> {wins}
                      </div>
                    </div>
                  </>
                );

                const rowClass = `flex items-center gap-2.5 px-3 py-2.5 rounded-xl transition-colors hover:bg-accent/30 ${podiumBg} ${isMe ? "ring-2 ring-primary/30 ring-inset" : ""}`;

                if (p.user_id || p.id) {
                  return (
                    <Link
                      key={p.user_id ?? p.id ?? i}
                      to="/joueur/$id"
                      params={{ id: p.user_id ?? p.id }}
                      className={rowClass}
                    >
                      {inner}
                    </Link>
                  );
                }
                return <div key={i} className={rowClass}>{inner}</div>;
              })}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
