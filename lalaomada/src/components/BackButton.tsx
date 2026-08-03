import { useRouter, useLocation } from "@tanstack/react-router";
import { ArrowLeft } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";

// Floating back button — draggable, default just below the header.
export default function FloatingBackButton() {
  const router = useRouter();
  const loc = useLocation();
  const dragging = useRef(false);
  const moved = useRef(false);
  const start = useRef({ mx: 0, my: 0, bx: 0, by: 0 });

  const DEFAULT = { x: 12, y: 64 };
  const [pos, setPos] = useState<{ x: number; y: number }>(() => {
    if (typeof window === "undefined") return DEFAULT;
    try {
      const raw = localStorage.getItem("backbtn_pos");
      return raw ? JSON.parse(raw) : DEFAULT;
    } catch { return DEFAULT; }
  });

  useEffect(() => {
    try { localStorage.setItem("backbtn_pos", JSON.stringify(pos)); } catch {}
  }, [pos]);

  const onDown = useCallback((e: React.PointerEvent) => {
    dragging.current = true;
    moved.current = false;
    start.current = { mx: e.clientX, my: e.clientY, bx: pos.x, by: pos.y };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }, [pos]);

  const onMove = useCallback((e: React.PointerEvent) => {
    if (!dragging.current) return;
    const dx = e.clientX - start.current.mx;
    const dy = e.clientY - start.current.my;
    if (Math.abs(dx) > 4 || Math.abs(dy) > 4) moved.current = true;
    const nx = Math.max(4, Math.min(window.innerWidth - 56, start.current.bx + dx));
    const ny = Math.max(4, Math.min(window.innerHeight - 56, start.current.by + dy));
    setPos({ x: nx, y: ny });
  }, []);

  const onUp = useCallback(() => { dragging.current = false; }, []);

  if (loc.pathname === "/" || loc.pathname === "/login") return null;

  return (
    <button
      onPointerDown={onDown}
      onPointerMove={onMove}
      onPointerUp={onUp}
      onClick={() => { if (!moved.current) router.history.back(); }}
      aria-label="Retour"
      style={{ position: "fixed", left: pos.x, top: pos.y, zIndex: 9999, touchAction: "none" }}
      className="flex items-center gap-1 rounded-full bg-card/95 backdrop-blur px-3 py-2 shadow-lg border border-border hover:bg-accent text-sm font-semibold select-none cursor-grab active:cursor-grabbing"
    >
      <ArrowLeft className="w-4 h-4" />
      <span className="hidden sm:inline">Retour</span>
    </button>
  );
}
