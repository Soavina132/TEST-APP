import { useNavigate } from "@tanstack/react-router";
import { LogOut } from "lucide-react";

/**
 * A small "Quitter le live" button shown to spectators watching a game.
 * Simply navigates back to /jeux — no server-side cleanup needed
 * (spectator counts are managed by the game pages' existing subscription logic).
 */
export default function SpectatorLeaveButton({ className }: { className?: string }) {
  const navigate = useNavigate();
  return (
    <button
      onClick={() => navigate({ to: "/jeux" })}
      className={`px-2 py-0.5 rounded-full bg-destructive text-white text-[10px] font-semibold flex items-center gap-0.5 ${className || ""}`}
    >
      <LogOut className="w-2.5 h-2.5" /> Quitter
    </button>
  );
}
