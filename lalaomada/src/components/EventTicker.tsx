import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";

type EventItem = {
  id: string;
  name: string;
  emoji: string;
  detail: string;
};

/**
 * A thin horizontally-scrolling marquee showing active tournaments/events.
 */
export default function EventTicker() {
  const [events, setEvents] = useState<EventItem[]>([]);

  useEffect(() => {
    const load = async () => {
      const { data } = await (supabase.from("tournaments") as any)
        .select("id, name, game_slug, status, entry_fee_ar, prize_pool_ar, registration_closes_at, starts_at")
        .in("status", ["open", "ongoing"])
        .order("created_at", { ascending: false })
        .limit(10);

      const list: EventItem[] = ((data as any[]) || []).map((t: any) => ({
        id: t.id,
        name: t.name || "Tournoi",
        emoji: "🏆",
        detail: Number(t.prize_pool_ar) > 0
          ? `Prix: ${Math.round(Number(t.prize_pool_ar)).toLocaleString("fr-FR")} Ar`
          : Number(t.entry_fee_ar) > 0
            ? `Entrée: ${Math.round(Number(t.entry_fee_ar)).toLocaleString("fr-FR")} Ar`
            : "Gratuit",
      }));

      // Also check announcements
      const { data: ann } = await (supabase.from("announcements" as any) as any)
        .select("id, title")
        .eq("active", true)
        .order("created_at", { ascending: false })
        .limit(3);

      ((ann as any[]) || []).forEach((a: any) => {
        list.push({ id: a.id, name: a.title || "Annonce", emoji: "📢", detail: "" });
      });

      setEvents(list);
    };

    load();
    const id = setInterval(load, 60_000);
    return () => clearInterval(id);
  }, []);

  if (events.length === 0) return null;

  // Duplicate items for seamless scroll
  const items = [...events, ...events];

  return (
    <div className="overflow-hidden rounded-xl bg-gradient-to-r from-primary/10 via-orange-500/10 to-primary/10 border border-primary/20 py-1.5">
      <div className="flex items-center gap-6 animate-marquee whitespace-nowrap">
        {items.map((e, i) => (
          <span key={`${e.id}-${i}`} className="text-xs font-semibold text-primary flex items-center gap-1.5 shrink-0">
            {e.emoji} {e.name}
            {e.detail && <span className="text-muted-foreground font-normal">· {e.detail}</span>}
          </span>
        ))}
      </div>
      <style>{`
        @keyframes marquee-scroll {
          0% { transform: translateX(0); }
          100% { transform: translateX(-50%); }
        }
        .animate-marquee {
          animation: marquee-scroll 20s linear infinite;
          width: max-content;
        }
        .animate-marquee:hover {
          animation-play-state: paused;
        }
      `}</style>
    </div>
  );
}
