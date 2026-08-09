import { ReactNode } from "react";

/**
 * Wraps a game board with a cover-themed backdrop so the play screen
 * carries the same visual identity as the lobby cover image.
 */
export default function GameBoardSkin({
  coverUrl,
  tint = "rgba(20, 12, 4, 0.78)",
  compact = false,
  children,
}: {
  coverUrl: string;
  tint?: string;
  /** Minimal frame — thin padding + smaller radius, so the board itself gets max space. */
  compact?: boolean;
  children: ReactNode;
}) {
  return (
    <div
      className={
        (compact
          ? "relative rounded-lg overflow-hidden p-1"
          : "relative rounded-3xl overflow-hidden p-3 sm:p-4") + " w-full h-full"
      }
      style={{
        backgroundImage: `linear-gradient(${tint}, ${tint}), url(${coverUrl})`,
        backgroundSize: "cover",
        backgroundPosition: "center",
        boxShadow: compact ? "0 6px 16px rgba(0,0,0,0.3)" : "0 18px 40px rgba(0,0,0,0.45)",
      }}
    >
      {children}
    </div>
  );
}
