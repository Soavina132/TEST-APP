import { useEffect, useRef, useState, useCallback } from "react";
import { Link } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";

type Banner = {
  id: string;
  title: string;
  subtitle: string | null;
  image_url: string | null;
  button_text: string | null;
  button_link: string | null;
  bg_gradient: string | null;
  starts_at: string | null;
  ends_at: string | null;
  active: boolean;
  sort_order: number;
};

const AUTO_SLIDE_MS = 4500;
const DEFAULT_GRADIENT = "from-primary to-orange-600";

function isInWindow(b: Banner) {
  const now = Date.now();
  if (b.starts_at && new Date(b.starts_at).getTime() > now) return false;
  if (b.ends_at && new Date(b.ends_at).getTime() < now) return false;
  return true;
}

export default function BannerCarousel() {
  const [banners, setBanners] = useState<Banner[]>([]);
  const [index, setIndex] = useState(0);
  const timerRef = useRef<ReturnType<typeof setInterval> | null>(null);
  const touchStartX = useRef<number | null>(null);
  const touchDeltaX = useRef(0);

  const load = useCallback(async () => {
    const { data } = await (supabase.from("banners" as any) as any)
      .select("*").eq("active", true).order("sort_order", { ascending: true });
    setBanners(((data as Banner[]) || []).filter(isInWindow));
  }, []);

  useEffect(() => {
    load();
    const ch = supabase.channel("banners-carousel")
      .on("postgres_changes", { event: "*", schema: "public", table: "banners" }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [load]);

  useEffect(() => {
    if (index >= banners.length) setIndex(0);
  }, [banners.length, index]);

  const startTimer = useCallback(() => {
    if (timerRef.current) clearInterval(timerRef.current);
    if (banners.length <= 1) return;
    timerRef.current = setInterval(() => {
      setIndex(i => (i + 1) % banners.length);
    }, AUTO_SLIDE_MS);
  }, [banners.length]);

  useEffect(() => {
    startTimer();
    return () => { if (timerRef.current) clearInterval(timerRef.current); };
  }, [startTimer]);

  const goTo = (i: number) => {
    setIndex(((i % banners.length) + banners.length) % banners.length);
    startTimer();
  };

  const onTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX;
    touchDeltaX.current = 0;
  };
  const onTouchMove = (e: React.TouchEvent) => {
    if (touchStartX.current == null) return;
    touchDeltaX.current = e.touches[0].clientX - touchStartX.current;
  };
  const onTouchEnd = () => {
    if (Math.abs(touchDeltaX.current) > 50) {
      if (touchDeltaX.current < 0) goTo(index + 1);
      else goTo(index - 1);
    }
    touchStartX.current = null;
    touchDeltaX.current = 0;
  };

  if (!banners.length) return null;

  return (
    <div
      className="relative rounded-2xl overflow-hidden shadow-md shadow-primary/10 h-40"
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
    >
      <div
        className="flex h-full transition-transform duration-500 ease-out"
        style={{ transform: `translateX(-${index * 100}%)` }}
      >
        {banners.map(b => (
          <div key={b.id} className="w-full h-full shrink-0 relative">
            {b.image_url ? (
              <img src={b.image_url} alt={b.title} className="absolute inset-0 w-full h-full object-cover" loading="lazy" />
            ) : (
              <div className={`absolute inset-0 bg-gradient-to-br ${b.bg_gradient || DEFAULT_GRADIENT}`} />
            )}
            <div className="absolute inset-0 bg-black/25" />
            <div className="relative h-full flex flex-col justify-center gap-1.5 p-4 text-white">
              <p className="text-base font-black leading-tight drop-shadow">{b.title}</p>
              {b.subtitle && (
                <p className="text-xs font-medium opacity-95 whitespace-pre-line leading-snug drop-shadow">
                  {b.subtitle}
                </p>
              )}
              {b.button_text && (
                b.button_link?.startsWith("http") ? (
                  <a href={b.button_link} target="_blank" rel="noopener noreferrer"
                    className="mt-1 self-start px-4 py-1.5 rounded-full bg-white text-neutral-900 text-xs font-bold shadow">
                    {b.button_text}
                  </a>
                ) : (
                  <Link to={(b.button_link || "/lobby") as any}
                    className="mt-1 self-start px-4 py-1.5 rounded-full bg-white text-neutral-900 text-xs font-bold shadow">
                    {b.button_text}
                  </Link>
                )
              )}
            </div>
          </div>
        ))}
      </div>

      {banners.length > 1 && (
        <div className="absolute bottom-2 left-0 right-0 flex items-center justify-center gap-1.5">
          {banners.map((b, i) => (
            <button
              key={b.id}
              aria-label={`Slide ${i + 1}`}
              onClick={() => goTo(i)}
              className={`rounded-full transition-all ${i === index ? "w-4 h-1.5 bg-white" : "w-1.5 h-1.5 bg-white/50"}`}
            />
          ))}
        </div>
      )}
    </div>
  );
}
