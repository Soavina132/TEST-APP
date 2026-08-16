import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { Trophy, Crown, Medal, Star, Flame, Zap, Shield } from "lucide-react";

export const Route = createFileRoute("/_authenticated/rankings")({
  component: RankingsPage,
  head: () => ({ meta: [
    { title: "Classement — Lalao MADA" },
    { name: "description", content: "Classement général de Lalao MADA — Top joueurs, victoires, podium." },
  ]}),
});

type Period = "all" | "month" | "week";

// ── Level badge ───────────────────────────────────────────────────────────
const LEVELS = [
  { min: 0,   max: 0,   labelKey: "level_beginner",    color: "text-slate-400",  bg: "bg-slate-100 dark:bg-slate-800",  icon: "⚪" },
  { min: 1,   max: 2,   labelKey: "level_novice",       color: "text-green-500",  bg: "bg-green-100 dark:bg-green-900/30",  icon: "🟢" },
  { min: 3,   max: 6,   labelKey: "level_intermediate", color: "text-blue-500",   bg: "bg-blue-100 dark:bg-blue-900/30",   icon: "🔵" },
  { min: 7,   max: 11,  labelKey: "level_advanced",     color: "text-violet-500", bg: "bg-violet-100 dark:bg-violet-900/30", icon: "🟣" },
  { min: 12,  max: 19,  labelKey: "level_expert",       color: "text-amber-500",  bg: "bg-amber-100 dark:bg-amber-900/30",  icon: "🟡" },
  { min: 20,  max: 34,  labelKey: "level_master",       color: "text-orange-500", bg: "bg-orange-100 dark:bg-orange-900/30", icon: "🟠" },
  { min: 35,  max: 59,  labelKey: "level_grandmaster",  color: "text-red-500",  bg: "bg-red-100 dark:bg-red-900/30",    icon: "🔴" },
  { min: 60,  max: 99,  labelKey: "level_champion",     color: "text-rose-600",   bg: "bg-rose-100 dark:bg-rose-900/30",  icon: "🏅" },
  { min: 100, max: 199, labelKey: "level_elite",        color: "text-fuchsia-600",bg: "bg-fuchsia-100 dark:bg-fuchsia-900/30", icon: "💎" },
  { min: 200, max: Infinity, labelKey: "level_legend",  color: "text-yellow-500", bg: "bg-yellow-50 dark:bg-yellow-900/20", icon: "👑" },
];

function getLevel(wins: number) {
  return LEVELS.find(l => wins >= l.min && wins <= l.max) ?? LEVELS[0];
}

function LevelBadge({ wins, compact = false }: { wins: number; compact?: boolean }) {
  const { t } = useT();
  const lvl = getLevel(wins);
  if (compact) return (
    <span className={`text-[10px] font-bold px-1.5 py-0.5 rounded-full ${lvl.bg} ${lvl.color}`}>
      {lvl.icon} {t(lvl.labelKey)}
    </span>
  );
  return (
    <span className={`text-xs font-bold px-2.5 py-1 rounded-full ${lvl.bg} ${lvl.color} flex items-center gap-1`}>
      <span>{lvl.icon}</span> {t(lvl.labelKey)}
    </span>
  );
}

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

function PodiumRow({ player, rank, myId }: { player: any; rank: number; myId?: string }) {
  const { t } = useT();
  const wins = Number(player.wins ?? 0);
  const isMe = player.id === myId || player.user_id === myId;
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
        <div className={`w-10 h-10 rounded-full bg-secondary overflow-hidden grid place-items-center font-bold text-sm ring-2 ${rank === 1 ? "ring-amber-400/60" : rank === 2 ? "ring-slate-400/40" : rank === 3 ? "ring-orange-400/40" : "ring-transparent"}`}>
          {player.avatar_url
            ? <img src={player.avatar_url} alt={player.name ?? player.pseudo} width={40} height={40} loading="lazy" decoding="async" className="w-full h-full object-cover" />
            : <span>{(player.name ?? player.pseudo ?? "?").slice(0, 2).toUpperCase()}</span>
          }
        </div>
        {rank <= 3 && (
          <div className="absolute -top-1 -right-1 text-xs">{rank === 1 ? "👑" : rank === 2 ? "🥈" : "🥉"}</div>
        )}
      </div>

      {/* Name + level */}
      <div className="flex-1 min-w-0 space-y-0.5">
        <div className="flex items-center gap-1.5 flex-wrap">
          <span className={`font-bold text-sm truncate ${isMe ? "text-primary" : ""}`}>
            {player.name ?? player.pseudo ?? t("player_fallback")}
            {isMe && <span className="text-[10px] text-primary ml-1">{t("you_suffix")}</span>}
          </span>
        </div>
        <LevelBadge wins={wins} compact />
      </div>

      {/* Wins */}
      <div className="text-right shrink-0">
        <div className="font-extrabold text-sm tabular-nums flex items-center gap-1 justify-end">
          <Trophy className="w-3.5 h-3.5 text-amber-500" /> {wins}
        </div>
        <div className="text-[10px] text-muted-foreground">{wins !== 1 ? t("win_plural") : t("win_singular")}</div>
      </div>
    </>
  );

  const rowClass = `flex items-center gap-3 px-4 py-3 border-b border-border/40 last:border-0 transition-colors hover:bg-accent/30 ${podiumBg} ${isMe ? "ring-2 ring-primary/30 ring-inset" : ""}`;

  if (player.id) {
    return (
      <Link to="/joueur/$id" params={{ id: player.id }} className={rowClass}>
        {inner}
      </Link>
    );
  }
  return <div className={rowClass}>{inner}</div>;
}

// ── Level guide ───────────────────────────────────────────────────────────
function LevelGuide() {
  const { t } = useT();
  const [open, setOpen] = useState(false);
  return (
    <div className="rounded-3xl bg-card shadow-sm border border-border/40 overflow-hidden">
      <button onClick={() => setOpen(!open)}
        className="w-full flex items-center justify-between px-5 py-4 font-bold text-sm">
        <span className="flex items-center gap-2"><Star className="w-4 h-4 text-amber-500" /> {t("level_guide_title")}</span>
        <span className="text-muted-foreground">{open ? "▲" : "▼"}</span>
      </button>
      {open && (
        <div className="px-4 pb-4 grid grid-cols-2 sm:grid-cols-3 gap-2">
          {LEVELS.map(l => (
            <div key={l.labelKey} className={`rounded-xl p-2.5 ${l.bg} flex items-center gap-2`}>
              <span className="text-lg">{l.icon}</span>
              <div>
                <div className={`text-xs font-bold ${l.color}`}>{t(l.labelKey)}</div>
                <div className="text-[10px] text-muted-foreground">
                  {l.max === Infinity ? `≥ ${l.min} ${t("win_plural")}` : l.min === 0 ? `0 ${t("win_singular")}` : `${l.min}–${l.max} ${t("win_plural")}`}
                </div>
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ── Main page ─────────────────────────────────────────────────────────────
function RankingsPage() {
  const { t } = useT();
  const { user } = useAuth();
  const [period, setPeriod] = useState<Period>("all");
  const [gameSlug, setGameSlug] = useState<string>("all");
  const [items, setItems] = useState<any[]>([]);
  const [seasons, setSeasons] = useState<any[]>([]);
  const [myRank, setMyRank] = useState<number | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setLoading(true);
    (async () => {
      const { data } = await supabase.rpc("leaderboard_winners" as any, {
        _period: period,
        _limit: 100,
        _slug: gameSlug === "all" ? null : gameSlug,
      } as any);
      const list: any[] = (data as any[]) || [];
      setItems(list);
      if (user) {
        const myIdx = list.findIndex(p => p.id === user.id || p.user_id === user.id);
        setMyRank(myIdx >= 0 ? myIdx + 1 : null);
      }
      setLoading(false);
    })();
    (supabase.from("seasons" as any) as any)
      .select("*").order("starts_at", { ascending: false }).limit(5)
      .then(({ data }: any) => setSeasons(data || []));
  }, [period, gameSlug, user?.id]);

  const periods: { id: Period; label: string; icon: React.ReactNode }[] = [
    { id: "all",   label: t("period_all"),   icon: <Shield className="w-3.5 h-3.5" /> },
    { id: "month", label: t("period_month"), icon: <Flame className="w-3.5 h-3.5" /> },
    { id: "week",  label: t("period_week"),  icon: <Zap className="w-3.5 h-3.5" /> },
  ];

  const top3 = items.slice(0, 3);
  const rest  = items.slice(3);

  return (
    <main className="max-w-2xl mx-auto px-4 py-5 space-y-4" style={{ background: "radial-gradient(ellipse at top, hsl(var(--primary)/0.04) 0%, transparent 60%)" }}>
      <div className="flex items-center justify-between pt-1">
        <h1 className="text-2xl font-extrabold flex items-center gap-2">
          <span className="text-2xl">🏆</span> {t("rankings")}
        </h1>
        {myRank && myRank <= 3 && (
          <div className="flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-amber-500/15 border border-amber-500/25">
            <Crown className="w-3.5 h-3.5 text-amber-500" />
            <span className="text-amber-500 font-bold text-xs">#{myRank} Vous</span>
          </div>
        )}
      </div>

      {/* Period selector */}
      <div className="flex gap-1 bg-card/80 p-1 rounded-2xl shadow-sm border border-white/8 backdrop-blur">
        {periods.map(p => (
          <button key={p.id} onClick={() => setPeriod(p.id)}
            className={`flex-1 flex items-center justify-center gap-1.5 py-2.5 rounded-xl text-xs sm:text-sm font-bold transition-all ${period === p.id ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "text-muted-foreground hover:text-foreground"}`}>
            {p.icon} {p.label}
          </button>
        ))}
      </div>

      {/* Game filter */}
      <div className="flex gap-1 overflow-x-auto pb-1 -mt-1 scrollbar-none">
        {[
          { slug: "all", label: "Tous", icon: "🎮" },
          { slug: "ludo", label: "Ludo", icon: "🎲" },
          { slug: "domino", label: "Domino", icon: "🁫" },
          { slug: "fanorona", label: "Fanorona", icon: "🔴" },
          { slug: "chess", label: "Échecs", icon: "♟️" },
          { slug: "rami", label: "Rami", icon: "🃏" },
        ].map(g => (
          <button
            key={g.slug}
            onClick={() => setGameSlug(g.slug)}
            className={`flex items-center gap-1 px-3 py-1.5 rounded-full text-xs font-bold whitespace-nowrap transition-all ${
              gameSlug === g.slug
                ? "bg-primary text-primary-foreground shadow-sm"
                : "bg-card border border-border/40 text-muted-foreground hover:text-foreground"
            }`}
          >
            <span>{g.icon}</span> {g.label}
          </button>
        ))}
      </div>

      {/* My rank (if not in top 50) */}
      {myRank && myRank > 3 && (
        <div className="rounded-2xl bg-primary/8 border border-primary/20 px-4 py-3 flex items-center justify-between shadow-sm">
          <div className="flex items-center gap-2 text-sm font-semibold text-primary">
            <Trophy className="w-4 h-4" /> {t("your_ranking")}
          </div>
          <div className="font-extrabold text-primary text-xl">#{myRank}</div>
        </div>
      )}

      {/* Leaderboard */}
      <div className="rounded-3xl bg-card overflow-hidden shadow-md border border-white/8">
        {loading ? (
          <div className="flex justify-center py-12">
            <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
          </div>
        ) : items.length === 0 ? (
          <div className="p-8 text-center text-muted-foreground text-sm">{t("no_data")}</div>
        ) : (
          <>
            {/* Podium top 3 */}
            {top3.map((p, i) => (
              <PodiumRow key={p.id ?? `top-${i}`} player={p} rank={i + 1} myId={user?.id} />
            ))}
            {/* Separator */}
            {rest.length > 0 && (
              <div className="px-4 py-2 bg-white/3 border-y border-white/6 text-[10px] font-bold text-muted-foreground/50 uppercase tracking-[0.2em] flex items-center gap-2">
                <div className="flex-1 h-px bg-white/6" />
                {t("general_rank")}
                <div className="flex-1 h-px bg-white/6" />
              </div>
            )}
            {rest.map((p, i) => (
              <PodiumRow key={p.id ?? `rest-${i}`} player={p} rank={i + 4} myId={user?.id} />
            ))}
          </>
        )}
      </div>

      {/* Level guide */}
      <LevelGuide />

      {/* Seasons / Ballon d'or */}
      {seasons.length > 0 && (
        <div className="rounded-3xl bg-card p-4 shadow-md border border-white/8 space-y-3">
          <div className="font-bold flex items-center gap-2">
            <Crown className="text-amber-500 w-4 h-4" /> {t("ballon_dor")}
          </div>
          {seasons.map(s => (
            <div key={s.id} className="border-t border-border/40 pt-3 space-y-0.5">
              <div className="flex items-center justify-between gap-2">
                <div className="font-semibold text-sm">{s.name}</div>
                {s.closed
                  ? <span className="text-[10px] bg-secondary px-2 py-0.5 rounded-full text-muted-foreground">{t("season_ended")}</span>
                  : <span className="text-[10px] bg-emerald-100 dark:bg-emerald-900/30 text-emerald-700 px-2 py-0.5 rounded-full font-bold animate-pulse">{t("season_ongoing")}</span>
                }
              </div>
              <div className="text-[11px] text-muted-foreground">
                {new Date(s.starts_at).toLocaleDateString("fr-FR")} → {new Date(s.ends_at).toLocaleDateString("fr-FR")}
              </div>
              {s.reward_text && (
                <div className="text-xs text-amber-600 font-semibold flex items-center gap-1 mt-1">
                  <Trophy className="w-3 h-3" /> {s.reward_text}
                </div>
              )}
              {s.closed && s.winner_id && (
                <div className="text-xs text-amber-600 font-bold flex items-center gap-1 mt-1">
                  <Crown className="w-3 h-3" /> {t("champion_designated")} 🏆
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </main>
  );
}
