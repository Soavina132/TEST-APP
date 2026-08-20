export const GAME_TABLES: Record<string, string> = {
  ludo: "ludo_games",
  domino: "domino_games",
  chess: "chess_games",
  fanorona: "fanorona_games",
  rami: "rami_games",
};

export const GAME_PART_TABLES: Record<string, string | null> = {
  ludo: "ludo_participants",
  domino: "domino_participants",
  chess: null,
  fanorona: "fanorona_participants",
  rami: "rami_participants",
};
