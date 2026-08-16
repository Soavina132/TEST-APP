import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { Eye, Users, Coins, Radio } from "lucide-react";
import { useT } from "@/lib/i18n";

export const Route = createFileRoute("/_authenticated/live")({
  component: LivePage,
  head: () => ({ meta: [{ title: "LIVE — Lalao MADA" }] }),
});

function LivePage() {
  const { t } = useT();
  const navigate = useNavigate();
  const [games, setGames] = useState<any[]>([]);
  const [enabled, setEnabled] = useState(true);

  const load = async () => {
    const { data: s } = await supabase.from("app_settings").select("live_enabled").eq("id", 1).maybeSingle();
    setEnabled(!!s?.live_enabled);
    const { data } = await supabase.rpc("list_live_games" as any);
    setGames((data as any[]) || []);
  };

  useEffect(() => {
    load();
    let heartbeat: ReturnType<typeof setInterval> | null = null;
    const ch = supabase.channel("live")
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "ludo_games", filter: "status=eq.open" }, load)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "ludo_games", filter: "status=eq.playing" }, load)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "domino_games", filter: "status=eq.open" }, load)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "domino_games", filter: "status=eq.playing" }, load)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chess_games", filter: "status=eq.open" }, load)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "chess_games", filter: "status=eq.playing" }, load)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "fanorona_games", filter: "status=eq.open" }, load)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "fanorona_games", filter: "status=eq.playing" }, load)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "rami_games", filter: "status=eq.open" }, load)
      .on("postgres_changes", { event: "UPDATE", schema: "public", table: "rami_games", filter: "status=eq.playing" }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: "game_spectators" }, load)
      .subscribe((status: string) => {
        if (status === "SUBSCRIBED") {
          if (heartbeat) clearInterval(heartbeat);
          heartbeat = setInterval(() => load(), 10_000);
        } else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT" || status === "CLOSED") {
          if (heartbeat) { clearInterval(heartbeat); heartbeat = null; }
          setTimeout(() => load(), 300);
        }
      });
    return () => { supabase.removeChannel(ch); if (heartbeat) clearInterval(heartbeat); };
  }, []);

  const routeFor = (g: any): { to: any; params: any; search?: any } => {
    const gt = (g.game_type || "ludo") as string;
    if (gt === "domino")   return { to: "/jeux/domino/$id",   params: { id: g.id } };
    if (gt === "chess")    return { to: "/jeux/chess/$id",    params: { id: g.id } };
    if (gt === "fanorona") return { to: "/jeux/fanorona/$id", params: { id: g.id } };
    if (gt === "rami")     return { to: "/jeux/rami/$id",     params: { id: g.id } };
    return { to: "/jeux/ludo/$id", params: { id: g.id }, search: { spectate: 1 } as any };
  };

  const labelFor = (gt?: string) => {
    switch (gt) {
      case "domino": return "Domino";
      case "chess": return "Échecs";
      case "fanorona": return "Fanorona";
      case "rami": return "Rami";
      
      default: return "Ludo";
    }
  };

  // Sort by most spectators first, then most recent
  const sorted = [...games].sort((a, b) => {
    if (b.spectators_count !== a.spectators_count) return b.spectators_count - a.spectators_count;
    return new Date(b.started_at).getTime() - new Date(a.started_at).getTime();
  });

  if (!enabled) return <main className="p-8 text-center text-muted-foreground">{t("live_disabled_msg")}</main>;

  return (
    <main className="max-w-3xl mx-auto px-4 py-6 space-y-4">
      <h1 className="text-2xl font-extrabold flex items-center gap-2"><Radio className="text-destructive" /> {t("live_title_full")}</h1>

      {sorted.length === 0 && (
        <div className="rounded-3xl bg-card p-8 text-center text-muted-foreground">{t("no_live_games")}</div>
      )}
      {sorted.map(g => {
        const r = routeFor(g);
        return (
        <button key={`${g.game_type}-${g.id}`} onClick={() => navigate(r as any)}
          className="w-full rounded-3xl bg-card p-4 shadow-sm hover:bg-accent text-left">
          <div className="flex items-center justify-between gap-3">
            <div className="flex-1 min-w-0">
              <div className="font-bold flex items-center gap-2">
                <span className="inline-flex w-2 h-2 rounded-full bg-destructive animate-pulse" /> {t("live_badge")}
                <span className="px-2 py-0.5 rounded-full bg-primary/15 text-primary text-[10px] font-extrabold uppercase tracking-wider">{labelFor(g.game_type)}</span>
              </div>
              <div className="text-sm text-muted-foreground flex items-center gap-3 mt-1">
                <span className="flex items-center gap-1"><Users className="w-3.5 h-3.5" /> {g.players_count}/{g.max_players}</span>
                <span className="flex items-center gap-1"><Coins className="w-3.5 h-3.5" /> {Number(g.pot).toLocaleString("fr-FR")} Ar</span>
                <span className="flex items-center gap-1"><Eye className="w-3.5 h-3.5" /> {g.spectators_count}</span>
              </div>
              <div className="text-xs text-muted-foreground mt-1">{t("started_at_label")}: {g.started_at ? new Date(g.started_at).toLocaleTimeString("fr-FR") : "—"} · {g.mode}</div>
            </div>
            <div className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold text-sm">{t("watch_btn")}</div>
          </div>
        </button>
        );
      })}
    </main>
  );
}
