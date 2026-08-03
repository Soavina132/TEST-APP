import { memo } from "react";

export type PlayerBarProps = {
  name: string;
  avatarUrl?: string | null;
  color: "w" | "b";
  timeMs: number;
  isTurn: boolean;
  captured?: string[]; // list of captured piece letters (lowercase)
  materialDiff?: number;
  align?: "top" | "bottom";
};

function fmt(ms: number) {
  const s = Math.max(0, Math.floor(ms / 1000));
  const m = Math.floor(s / 60);
  const r = s % 60;
  return `${m}:${r.toString().padStart(2, "0")}`;
}

const PIECE_UNI: Record<string, string> = { p: "♟", n: "♞", b: "♝", r: "♜", q: "♛" };

export const PlayerBar = memo(function PlayerBar(p: PlayerBarProps) {
  const low = p.timeMs < 30_000;
  const critical = p.timeMs < 10_000;
  return (
    <div className="flex items-center gap-3 px-3 py-2 rounded-xl bg-card/80 backdrop-blur border border-border">
      <div
        className="w-10 h-10 rounded-full overflow-hidden flex-shrink-0 border-2"
        style={{ borderColor: p.color === "w" ? "#fafaf9" : "#1c1917" }}
      >
        {p.avatarUrl ? (
          <img src={p.avatarUrl} alt={p.name} className="w-full h-full object-cover" />
        ) : (
          <div className="w-full h-full flex items-center justify-center bg-muted text-sm font-bold">
            {p.name.slice(0, 1).toUpperCase()}
          </div>
        )}
      </div>
      <div className="flex-1 min-w-0">
        <div className="font-semibold text-sm truncate flex items-center gap-2">
          {p.name}
          {p.isTurn && <span className="w-2 h-2 rounded-full bg-amber-400 animate-pulse" />}
        </div>
        <div className="flex items-center gap-0.5 min-h-5 flex-wrap">
          {(p.captured ?? []).slice(0, 16).map((c, i) => (
            <span
              key={i}
              className="text-base leading-none"
              style={{
                color: p.color === "w" ? "#1c1917" : "#f5f5f4",
                textShadow: p.color === "w"
                  ? "0 0 1px rgba(255,255,255,0.9)"
                  : "0 0 1px rgba(0,0,0,0.9)",
              }}
            >
              {PIECE_UNI[c] ?? ""}
            </span>
          ))}
          {(p.materialDiff ?? 0) > 0 && (
            <span className="ml-1 text-xs font-bold text-emerald-600">+{p.materialDiff}</span>
          )}
        </div>
      </div>
      <div
        className={`font-mono text-lg font-bold tabular-nums px-3 py-1 rounded-md ${
          critical ? "bg-red-500 text-white animate-pulse" : low ? "text-red-600" : ""
        }`}
        style={!critical ? { background: p.isTurn ? "rgba(251,191,36,0.15)" : undefined } : undefined}
      >
        {fmt(p.timeMs)}
      </div>
    </div>
  );
});
