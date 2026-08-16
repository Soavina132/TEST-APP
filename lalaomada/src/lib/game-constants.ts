/**
 * Shared constants used across multiple game routes.
 * Extracted to eliminate duplication.
 */

// UUID validator regex
export const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

// Card suit / rank constants (used by Rami)
export const SUITS = ["♠", "♥", "♦", "♣"] as const;
export const SUIT_COLORS = ["#111827", "#dc2626", "#dc2626", "#111827"] as const;
export const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"] as const;

// Game slug → Supabase table mapping (used by lobby & jeux.$slug)
export type GameSlug = "ludo" | "domino" | "fanorona" | "chess" | "rami" ;

export const GAME_TABLE: Record<GameSlug, string> = {
  ludo: "ludo_games",
  domino: "domino_games",
  fanorona: "fanorona_games",
  chess: "chess_games",
  rami: "rami_games",
};
