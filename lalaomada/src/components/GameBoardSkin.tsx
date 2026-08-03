import { ReactNode } from "react";

/**
 * Wraps a game board with a cover-themed backdrop so the play screen
 * carries the same visual identity as the lobby cover image.
 */
export default function GameBoardSkin({
  coverUrl,
  tint = "rgba(20, 12, 4, 0.78)",
  children,
}: {
  coverUrl: string;
  tint?: string;
  children: ReactNode;
}) {
  return (
    <div
      className="relative rounded-3xl overflow-hidden p-3 sm:p-4"
      style={{
        backgroundImage: `linear-gradient(${tint}, ${tint}), url(${coverUrl})`,
        backgroundSize: "cover",
        backgroundPosition: "center",
        boxShadow: "0 18px 40px rgba(0,0,0,0.45)",
      }}
    >
      {children}
    </div>
  );
}
