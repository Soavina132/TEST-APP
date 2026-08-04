import { useEffect, useRef, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";

// ─────────────────────────────────────────────────────────────────────────────
// QuickReactions — floating emoji reactions for Ludo & Domino games.
// Uses Supabase realtime broadcast (no DB table needed).
// ─────────────────────────────────────────────────────────────────────────────

const REACTIONS = [
  { emoji: "👍", label: "J'aime" },
  { emoji: "🔥", label: "Feu" },
  { emoji: "😂", label: "Haha" },
  { emoji: "❤️", label: "Cœur" },
  { emoji: "🎉", label: "Bravo" },
  { emoji: "😮", label: "Wow" },
  { emoji: "👏", label: "Clap" },
  { emoji: "😤", label: "Grrr" },
] as const;

type FloatingReaction = {
  id: number;
  emoji: string;
  x: number;
  sender: string;
};

export default function QuickReactions({
  gameId,
  gameSlug,
  participants = [],
  position = "bottom-right",
}: {
  gameId: string;
  gameSlug: "ludo" | "domino";
  participants?: { user_id?: string | null; display_name?: string | null; slot?: number; is_bot?: boolean }[];
  position?: "bottom-right" | "top-right";
}) {
  const { profile } = useAuth();
  const [showBar, setShowBar] = useState(false);
  const [floaters, setFloaters] = useState<FloatingReaction[]>([]);
  const [recentReactions, setRecentReactions] = useState<{ emoji: string; sender: string }[]>([]);
  const floatId = useRef(0);
  const channelRef = useRef<ReturnType<typeof supabase.channel> | null>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Get display name for a user
  const getName = useCallback(
    (userId: string) => {
      if (userId === profile?.id) return profile?.pseudo || "Vous";
      const p = participants.find((p) => p.user_id === userId);
      return p?.display_name || "Joueur";
    },
    [profile?.id, profile?.pseudo, participants],
  );

  // Subscribe to reaction broadcasts
  useEffect(() => {
    const ch = supabase
      .channel(`reactions-${gameSlug}-${gameId}`)
      .on("broadcast", { event: "reaction" }, (payload: any) => {
        const { emoji, user_id, display_name } = payload.payload || {};
        if (!emoji) return;
        const sender = display_name || getName(user_id) || "Joueur";

        // Add floating emoji
        const id = ++floatId.current;
        const x = 20 + Math.random() * 60; // 20%-80% position
        setFloaters((prev) => [...prev, { id, emoji, x, sender }]);
        setTimeout(() => {
          setFloaters((prev) => prev.filter((f) => f.id !== id));
        }, 2500);

        // Add to recent reactions log
        setRecentReactions((prev) => [{ emoji, sender }, ...prev].slice(0, 5));
      })
      .subscribe();

    channelRef.current = ch;
    return () => {
      supabase.removeChannel(ch);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [gameId, gameSlug]);

  const sendReaction = useCallback(
    (emoji: string) => {
      // Broadcast to channel
      channelRef.current?.send({
        type: "broadcast",
        event: "reaction",
        payload: { emoji, user_id: profile?.id, display_name: profile?.pseudo },
      });

      // Also show locally (broadcast doesn't echo back to sender)
      const id = ++floatId.current;
      const x = 20 + Math.random() * 60;
      const sender = profile?.pseudo || "Vous";
      setFloaters((prev) => [...prev, { id, emoji, x, sender }]);
      setTimeout(() => {
        setFloaters((prev) => prev.filter((f) => f.id !== id));
      }, 2500);

      setRecentReactions((prev) => [{ emoji, sender }, ...prev].slice(0, 5));

      // Auto-hide bar after selection
      setShowBar(false);
    },
    [profile?.id, profile?.pseudo],
  );

  // Auto-hide bar after inactivity
  const openBar = useCallback(() => {
    setShowBar(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowBar(false), 4000);
  }, []);

  const keepBarOpen = useCallback(() => {
    if (hideTimer.current) clearTimeout(hideTimer.current);
    hideTimer.current = setTimeout(() => setShowBar(false), 4000);
  }, []);

  return (
    <>
      {/* Floating reactions overlay */}
      <div className="fixed inset-0 pointer-events-none z-40 overflow-hidden">
        {floaters.map((f) => (
          <div
            key={f.id}
            className={position === "top-right" ? "absolute top-24" : "absolute bottom-24"}
            style={{
              left: `${f.x}%`,
              animation: `${position === "top-right" ? "floatDown" : "floatUp"} 2.5s ease-out forwards`,
            }}
          >
            <div className="flex flex-col items-center gap-0.5">
              <span className="text-3xl drop-shadow-lg" style={{ filter: "drop-shadow(0 2px 4px rgba(0,0,0,0.2))" }}>
                {f.emoji}
              </span>
              <span className="text-[10px] font-medium text-muted-foreground bg-card/80 rounded-full px-1.5 py-0.5 backdrop-blur-sm">
                {f.sender}
              </span>
            </div>
          </div>
        ))}
      </div>

      {/* Recent reactions log (small badges above/below the bar) */}
      {recentReactions.length > 0 && !showBar && (
        <div className={`fixed z-40 flex flex-col gap-1 items-center pointer-events-none ${position === "top-right" ? "top-32 left-1/2" : "bottom-20 left-1/2"} -translate-x-1/2`}>
          {recentReactions.slice(0, 3).map((r, i) => (
            <div
              key={i}
              className="flex items-center gap-1 bg-card/90 rounded-full px-2 py-0.5 shadow-md backdrop-blur-sm animate-pop-in"
              style={{ opacity: 1 - i * 0.25 }}
            >
              <span className="text-sm">{r.emoji}</span>
              <span className="text-[10px] text-muted-foreground font-medium">{r.sender}</span>
            </div>
          ))}
        </div>
      )}

      {/* Reaction bar trigger + expanded bar */}
      <div
        className={`fixed z-40 flex flex-col items-end gap-2 ${position === "top-right" ? "top-[68px] right-3" : "bottom-4 right-3"}`}
        onMouseEnter={keepBarOpen}
      >
        {position === "top-right" ? (
          <>
            <button
              onClick={() => (showBar ? setShowBar(false) : openBar())}
              className="w-11 h-11 flex items-center justify-center rounded-full bg-card shadow-lg border border-border/60 hover:bg-accent transition-colors active:scale-90"
              aria-label="Réactions rapides"
            >
              <span className="text-2xl">😀</span>
            </button>
            {showBar && (
              <div
                className="flex items-center gap-1 bg-card rounded-full shadow-xl border border-border/60 px-2 py-1.5 animate-pop-in"
                onMouseEnter={keepBarOpen}
              >
                {REACTIONS.map((r) => (
                  <button
                    key={r.emoji}
                    onClick={() => sendReaction(r.emoji)}
                    className="w-9 h-9 flex items-center justify-center rounded-full hover:bg-accent hover:scale-125 transition-all duration-150 active:scale-90"
                    title={r.label}
                    aria-label={r.label}
                  >
                    <span className="text-xl">{r.emoji}</span>
                  </button>
                ))}
              </div>
            )}
          </>
        ) : (
          <>
            {showBar && (
              <div
                className="flex items-center gap-1 bg-card rounded-full shadow-xl border border-border/60 px-2 py-1.5 animate-pop-in"
                onMouseEnter={keepBarOpen}
              >
                {REACTIONS.map((r) => (
                  <button
                    key={r.emoji}
                    onClick={() => sendReaction(r.emoji)}
                    className="w-9 h-9 flex items-center justify-center rounded-full hover:bg-accent hover:scale-125 transition-all duration-150 active:scale-90"
                    title={r.label}
                    aria-label={r.label}
                  >
                    <span className="text-xl">{r.emoji}</span>
                  </button>
                ))}
              </div>
            )}

            <button
              onClick={() => (showBar ? setShowBar(false) : openBar())}
              className="w-11 h-11 flex items-center justify-center rounded-full bg-card shadow-lg border border-border/60 hover:bg-accent transition-colors active:scale-90"
              aria-label="Réactions rapides"
            >
              <span className="text-2xl">😀</span>
            </button>
          </>
        )}
      </div>

      {/* Keyframes injected once */}
      <style>{`
        @keyframes floatUp {
          0% { transform: translateY(0) scale(0.5); opacity: 0; }
          15% { transform: translateY(-10px) scale(1.2); opacity: 1; }
          100% { transform: translateY(-200px) scale(1); opacity: 0; }
        }
        @keyframes floatDown {
          0% { transform: translateY(0) scale(0.5); opacity: 0; }
          15% { transform: translateY(10px) scale(1.2); opacity: 1; }
          100% { transform: translateY(200px) scale(1); opacity: 0; }
        }
      `}</style>
    </>
  );
}
