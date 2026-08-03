import React, { useCallback, useEffect, useRef, useState } from "react";

type Side = "before" | "after";

export type DragState = {
  sourceId: string;
  x: number;
  y: number;
  ox: number;
  oy: number;
  w: number;
  h: number;
  targetId: string | null;
  targetSide: Side | null;
};

type Options = {
  delay?: number;
  onDrop: (sourceId: string, targetId: string, side: Side) => void;
};

/**
 * Long-press → drag & drop hook (pointer events, mobile + desktop).
 * Smooth: pointer capture, GPU transforms, initial finger offset stored so the
 * card follows the finger from exactly where it was grabbed.
 */
export function useLongPressDrag({ delay = 380, onDrop }: Options) {
  const [drag, setDrag] = useState<DragState | null>(null);
  const dragRef = useRef<DragState | null>(null);
  dragRef.current = drag;

  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const startRef = useRef<{ x: number; y: number; el: HTMLElement | null } | null>(null);

  const clearTimer = () => {
    if (timerRef.current) {
      clearTimeout(timerRef.current);
      timerRef.current = null;
    }
  };

  const findTarget = (x: number, y: number, sourceId: string): { id: string | null; side: Side | null } => {
    // Temporarily disable pointer events on ghost via z-index; elementFromPoint should skip pointer-events:none
    const stack = document.elementsFromPoint(x, y) as HTMLElement[];
    for (const el of stack) {
      const drop = el.closest?.("[data-drop-target]") as HTMLElement | null;
      if (!drop) continue;
      const id = drop.getAttribute("data-drop-target");
      if (!id || id === sourceId) continue;
      const r = drop.getBoundingClientRect();
      const side: Side = x - r.left < r.width / 2 ? "before" : "after";
      return { id, side };
    }
    return { id: null, side: null };
  };

  useEffect(() => {
    if (!drag) return;
    let raf = 0;
    let pending: { x: number; y: number } | null = null;
    const flush = () => {
      raf = 0;
      if (!pending) return;
      const { x, y } = pending;
      pending = null;
      const src = dragRef.current?.sourceId ?? "";
      const { id, side } = findTarget(x, y, src);
      setDrag((d) => (d ? { ...d, x, y, targetId: id, targetSide: side } : d));
    };
    const move = (e: PointerEvent) => {
      pending = { x: e.clientX, y: e.clientY };
      if (!raf) raf = requestAnimationFrame(flush);
    };
    const end = () => {
      const d = dragRef.current;
      if (d && d.targetId && d.targetSide && d.targetId !== d.sourceId) {
        onDrop(d.sourceId, d.targetId, d.targetSide);
      }
      setDrag(null);
    };
    window.addEventListener("pointermove", move, { passive: true });
    window.addEventListener("pointerup", end, { passive: true });
    window.addEventListener("pointercancel", end, { passive: true });
    return () => {
      if (raf) cancelAnimationFrame(raf);
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", end);
      window.removeEventListener("pointercancel", end);
    };
  }, [drag !== null, onDrop]);

  const getSourceProps = useCallback(
    (sourceId: string) => ({
      onPointerDown: (e: React.PointerEvent) => {
        if (e.pointerType === "mouse" && e.button !== 0) return;
        const el = e.currentTarget as HTMLElement;
        startRef.current = { x: e.clientX, y: e.clientY, el };
        clearTimer();
        const sx = e.clientX;
        const sy = e.clientY;
        try { el.setPointerCapture?.(e.pointerId); } catch {}
        timerRef.current = setTimeout(() => {
          if (typeof navigator !== "undefined" && "vibrate" in navigator) {
            try { (navigator as any).vibrate?.(12); } catch {}
          }
          const r = el.getBoundingClientRect();
          setDrag({
            sourceId,
            x: sx,
            y: sy,
            ox: sx - r.left,
            oy: sy - r.top,
            w: r.width,
            h: r.height,
            targetId: null,
            targetSide: null,
          });
        }, delay);
      },
      onPointerMove: (e: React.PointerEvent) => {
        const s = startRef.current;
        if (s && !dragRef.current) {
          const dx = e.clientX - s.x;
          const dy = e.clientY - s.y;
          if (Math.hypot(dx, dy) > 8) clearTimer();
        }
      },
      onPointerUp: () => {
        clearTimer();
        startRef.current = null;
      },
      onPointerCancel: () => {
        clearTimer();
        startRef.current = null;
      },
      "data-drag-source": sourceId,
    }),
    [delay]
  );

  const isDraggingId = (id: string) => drag?.sourceId === id;
  const isTargetId = (id: string): Side | false => {
    if (drag?.targetId === id && drag?.targetSide) return drag.targetSide;
    return false;
  };

  return { drag, getSourceProps, isDraggingId, isTargetId };
}
