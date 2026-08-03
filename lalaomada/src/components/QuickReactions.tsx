import { useEffect, useState, useRef, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";

interface Reaction { id: string; emoji: string; x: number; y: number; uid: string; name: string; }
const REACTIONS = ["👍", "❤️", "😂", "🔥", "😮", "👏", "💪", "🎉"];

export default function QuickReactions({ gameId, myUserId, myName }: { gameId: string; myUserId: string | null; myName: string }) {
  const [reactions, setReactions] = useState<Reaction[]>([]);
  const [showPicker, setShowPicker] = useState(false);
  const channelRef = useRef<any>(null);

  useEffect(() => {
    const ch = supabase.channel(`reactions-${gameId}`)
      .on("broadcast", { event: "reaction" }, ({ payload }: any) => {
        if (!payload) return;
        const r: Reaction = { ...payload, id: crypto.randomUUID() };
        setReactions(p => [...p, r]);
        setTimeout(() => setReactions(p => p.filter(x => x.id !== r.id)), 3000);
      }).subscribe();
    channelRef.current = ch;
    return () => { supabase.removeChannel(ch); };
  }, [gameId]);

  const send = useCallback((emoji: string) => {
    if (!myUserId) return;
    channelRef.current?.send({ type: "broadcast", event: "reaction", payload: {
      emoji, x: 15 + Math.random() * 70, y: 35 + Math.random() * 35, uid: myUserId, name: myName,
    }});
    setShowPicker(false);
  }, [myUserId, myName]);

  return (
    <>
      <div className="absolute inset-0 pointer-events-none overflow-hidden z-40">
        {reactions.map(r => (
          <div key={r.id} className="absolute text-3xl" style={{ left: `${r.x}%`, top: `${r.y}%`, animation: "reaction-float 3s ease-out forwards" }}>
            {r.emoji}
          </div>
        ))}
      </div>
      <button onClick={() => setShowPicker(s => !s)}
        className="absolute bottom-2 right-2 z-50 flex h-10 w-10 items-center justify-center rounded-full bg-white/15 backdrop-blur-sm text-xl hover:bg-white/25 active:scale-90 transition">
        😊
      </button>
      {showPicker && (
        <div className="absolute bottom-14 right-2 z-50 flex gap-1 rounded-2xl bg-black/80 backdrop-blur-md p-2 shadow-xl" style={{ animation: "fadeIn 0.2s ease-out" }}>
          {REACTIONS.map(e => (
            <button key={e} onClick={() => send(e)} className="flex h-9 w-9 items-center justify-center rounded-full hover:bg-white/20 active:scale-90 transition text-lg">{e}</button>
          ))}
        </div>
      )}
    </>
  );
}
