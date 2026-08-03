import { useEffect, useState } from "react";
import { useAuth } from "@/hooks/use-auth";
import { useOnlineStatus, NetworkQuality } from "@/hooks/use-online-status";
import { supabase } from "@/integrations/supabase/client";

// ── Signal bars SVG ───────────────────────────────────────────────────────
function SignalBars({ bars, color }: { bars: number; color: string }) {
  return (
    <div className={`flex items-end gap-[2px] ${color}`} style={{ height: 10, width: 14 }}>
      {[1, 2, 3, 4].map(b => (
        <div
          key={b}
          className={`w-[3px] rounded-[1px] transition-all duration-300 ${b <= bars ? "opacity-100" : "opacity-20"}`}
          style={{ height: `${b * 25}%`, background: "currentColor" }}
        />
      ))}
    </div>
  );
}

// ── Quality config ────────────────────────────────────────────────────────
const Q: Record<NetworkQuality, { bars: number; dot: string; text: string; bg: string; emoji: string; label: string }> = {
  excellent: { bars: 4, dot: "bg-emerald-500", text: "text-emerald-600 dark:text-emerald-400", bg: "bg-emerald-500/10", emoji: "🟢", label: "Excellent" },
  good:      { bars: 3, dot: "bg-emerald-400", text: "text-emerald-500 dark:text-emerald-300", bg: "bg-emerald-400/10", emoji: "🟢", label: "Excellent" },
  fair:      { bars: 2, dot: "bg-amber-500",   text: "text-amber-600  dark:text-amber-400",   bg: "bg-amber-400/10",   emoji: "🟡", label: "Moyen" },
  poor:      { bars: 1, dot: "bg-red-500",     text: "text-red-600    dark:text-red-400",      bg: "bg-red-500/10",     emoji: "🔴", label: "Mauvais" },
  offline:   { bars: 0, dot: "bg-red-600",     text: "text-red-700    dark:text-red-400",      bg: "bg-red-600/10",     emoji: "🔴", label: "Hors ligne" },
  unknown:   { bars: 0, dot: "bg-muted-foreground", text: "text-muted-foreground",            bg: "bg-muted/20",       emoji: "⚪", label: "—" },
};

// ── Games today counter ─────────────────────────────────────────────────
function useGamesToday() {
  const [count, setCount] = useState(0);
  useEffect(() => {
    const load = async () => {
      // Start of today in local time
      const start = new Date();
      start.setHours(0, 0, 0, 0);
      try {
        const { count } = await supabase
          .from("ludo_games")
          .select("id", { count: "exact", head: true })
          .gte("created_at", start.toISOString());
        const { count: d } = await supabase
          .from("domino_games")
          .select("id", { count: "exact", head: true })
          .gte("created_at", start.toISOString());
        const { count: c } = await supabase
          .from("chess_games")
          .select("id", { count: "exact", head: true })
          .gte("created_at", start.toISOString());
        const { count: p } = await supabase
          .from("poker_games")
          .select("id", { count: "exact", head: true })
          .gte("created_at", start.toISOString());
        setCount((count || 0) + (d || 0) + (c || 0) + (p || 0));
      } catch { /* ignore */ }
    };
    load();
    const id = setInterval(load, 60_000);
    return () => clearInterval(id);
  }, []);
  return count;
}

// ── Component ─────────────────────────────────────────────────────────────
export default function OnlineStatusBar() {
  const { user } = useAuth();
  const { onlineCount, latencyMs, effectiveType, quality, isOnline } = useOnlineStatus(user?.id);
  const gamesToday = useGamesToday();
  const cfg = Q[quality];

  return (
    <div className="w-full flex items-center justify-between px-4 py-[5px] border-b border-border/30 bg-background/70 backdrop-blur-sm text-[10px] leading-none z-30">

      {/* ── Left: online count + games today ── */}
      <div className="flex items-center gap-2 text-muted-foreground">
        <div className="flex items-center gap-1.5">
          <span
            className={`w-[7px] h-[7px] rounded-full flex-shrink-0 ${isOnline ? "bg-emerald-500 animate-pulse" : "bg-red-500"}`}
          />
          {onlineCount > 0 ? (
            <span>
              <span className="font-bold text-foreground">{onlineCount}</span>
              {" "}joueur{onlineCount > 1 ? "s" : ""} en ligne
            </span>
          ) : (
            <span className="opacity-50">Connexion…</span>
          )}
        </div>

        {gamesToday > 0 && (
          <span className="flex items-center gap-1 text-amber-500 font-semibold">
            🔥 {gamesToday} partie{gamesToday > 1 ? "s" : ""} aujourd'hui
          </span>
        )}
      </div>

      {/* ── Right: connection quality with emoji indicator ── */}
      <div className={`flex items-center gap-1.5 px-2 py-[3px] rounded-full ${cfg.bg} transition-all duration-500`}>
        {isOnline ? (
          <SignalBars bars={cfg.bars} color={cfg.text} />
        ) : (
          <span className="text-red-600">✕</span>
        )}

        <span className={`font-semibold ${cfg.text}`}>{cfg.emoji} {cfg.label}</span>

        {latencyMs !== null && isOnline && (
          <span className={cfg.text}>
            · {latencyMs} ms
          </span>
        )}
      </div>
    </div>
  );
}
