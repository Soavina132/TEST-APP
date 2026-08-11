const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const SUITS = ["♠", "♥", "♦", "♣"];
const SUIT_COLORS = ["#111827", "#dc2626", "#dc2626", "#111827"];
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
const GAME_TABLE = {
  ludo: "ludo_games",
  domino: "domino_games",
  fanorona: "fanorona_games",
  chess: "chess_games",
  rami: "rami_games",
  poker: "poker_games"
};
export {
  GAME_TABLE as G,
  RANKS as R,
  SUIT_COLORS as S,
  UUID_RE as U,
  SUITS as a
};
