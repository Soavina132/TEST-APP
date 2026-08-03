import { useEffect, useState } from "react";

const COLORS = ["#CC0000", "#1A9A1A", "#DDAA00", "#1155CC", "#FFD700", "#FF6B6B", "#4ECDC4", "#95E1D3"];

export function fireConfetti(duration = 3500) {
  if (typeof document === "undefined") return;
  const canvas = document.createElement("canvas");
  canvas.style.cssText = "position:fixed;top:0;left:0;width:100%;height:100%;pointer-events:none;z-index:9999;";
  canvas.width = window.innerWidth;
  canvas.height = window.innerHeight;
  document.body.appendChild(canvas);
  const ctx = canvas.getContext("2d");
  if (!ctx) { canvas.remove(); return; }
  const particles: any[] = [];
  for (let i = 0; i < 120; i++) {
    particles.push({
      x: Math.random() * canvas.width, y: -20 - Math.random() * 100,
      vx: (Math.random() - 0.5) * 5, vy: Math.random() * 3 + 2,
      size: Math.random() * 8 + 4, color: COLORS[Math.floor(Math.random() * COLORS.length)],
      rot: Math.random() * Math.PI * 2, vr: (Math.random() - 0.5) * 0.3, life: 1,
      shape: Math.random() > 0.5 ? "rect" : "circle",
    });
  }
  const start = Date.now();
  (function anim() {
    const el = Date.now() - start;
    ctx.clearRect(0, 0, canvas.width, canvas.height);
    for (const p of particles) {
      p.x += p.vx; p.y += p.vy; p.vy += 0.1; p.vx *= 0.99; p.rot += p.vr;
      if (el > duration - 1000) p.life = Math.max(0, 1 - (el - (duration - 1000)) / 1000);
      ctx.save(); ctx.globalAlpha = p.life; ctx.translate(p.x, p.y); ctx.rotate(p.rot);
      ctx.fillStyle = p.color;
      if (p.shape === "rect") ctx.fillRect(-p.size / 2, -p.size / 2, p.size, p.size * 0.6);
      else { ctx.beginPath(); ctx.arc(0, 0, p.size / 2, 0, Math.PI * 2); ctx.fill(); }
      ctx.restore();
    }
    if (el < duration) requestAnimationFrame(anim); else canvas.remove();
  })();
}

export default function VictoryOverlay({ winnerName, isMe, onClose }: { winnerName: string; isMe: boolean; onClose?: () => void }) {
  const [visible, setVisible] = useState(true);
  useEffect(() => {
    fireConfetti(4000);
    const t = setTimeout(() => setVisible(false), 5000);
    return () => clearTimeout(t);
  }, []);
  useEffect(() => { if (!visible && onClose) onClose(); }, [visible, onClose]);
  if (!visible) return null;
  return (
    <div className="fixed inset-0 z-[9998] flex items-center justify-center pointer-events-none">
      <div className="text-center" style={{ animation: "victory-pop 0.5s ease-out" }}>
        <div className="text-7xl mb-2" style={{ filter: "drop-shadow(0 4px 12px rgba(255,215,0,0.6))" }}>
          {isMe ? "🏆" : "🏁"}
        </div>
        <div className="text-3xl font-black text-white mb-1" style={{ textShadow: "0 2px 8px rgba(0,0,0,0.8)" }}>
          {isMe ? "Victoire !" : `${winnerName} gagne !`}
        </div>
        <div className="text-lg font-semibold text-yellow-300" style={{ textShadow: "0 1px 4px rgba(0,0,0,0.8)" }}>
          {isMe ? "🎉 Bravo !" : "Bien joué à tous"}
        </div>
      </div>
    </div>
  );
}
