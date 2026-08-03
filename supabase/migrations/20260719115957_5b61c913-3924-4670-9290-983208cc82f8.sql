
-- 1) Add per-game commission columns (default from current global)
DO $$
DECLARE v_current numeric;
BEGIN
  SELECT COALESCE(game_commission_pct, 10) INTO v_current FROM public.app_settings WHERE id = 1;
  IF v_current IS NULL THEN v_current := 10; END IF;

  ALTER TABLE public.app_settings
    ADD COLUMN IF NOT EXISTS ludo_commission_pct       numeric,
    ADD COLUMN IF NOT EXISTS chess_commission_pct      numeric,
    ADD COLUMN IF NOT EXISTS domino_commission_pct     numeric,
    ADD COLUMN IF NOT EXISTS rami_commission_pct       numeric,
    ADD COLUMN IF NOT EXISTS fanorona_commission_pct   numeric,
    ADD COLUMN IF NOT EXISTS poker_commission_pct      numeric,
    ADD COLUMN IF NOT EXISTS billiard_commission_pct   numeric,
    ADD COLUMN IF NOT EXISTS tournament_commission_pct numeric;

  UPDATE public.app_settings SET
    ludo_commission_pct       = COALESCE(ludo_commission_pct, v_current),
    chess_commission_pct      = COALESCE(chess_commission_pct, v_current),
    domino_commission_pct     = COALESCE(domino_commission_pct, v_current),
    rami_commission_pct       = COALESCE(rami_commission_pct, v_current),
    fanorona_commission_pct   = COALESCE(fanorona_commission_pct, v_current),
    poker_commission_pct      = COALESCE(poker_commission_pct, v_current),
    billiard_commission_pct   = COALESCE(billiard_commission_pct, v_current),
    tournament_commission_pct = COALESCE(tournament_commission_pct, v_current)
  WHERE id = 1;
END $$;

-- 2) Central helper: reads per-game rate, falls back to global then 10
CREATE OR REPLACE FUNCTION public.get_game_commission(_game text)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v numeric; v_global numeric;
BEGIN
  SELECT
    CASE lower(_game)
      WHEN 'ludo'       THEN ludo_commission_pct
      WHEN 'chess'      THEN chess_commission_pct
      WHEN 'domino'     THEN domino_commission_pct
      WHEN 'rami'       THEN rami_commission_pct
      WHEN 'fanorona'   THEN fanorona_commission_pct
      WHEN 'poker'      THEN poker_commission_pct
      WHEN 'billiard'   THEN billiard_commission_pct
      WHEN 'tournament' THEN tournament_commission_pct
      ELSE NULL
    END,
    game_commission_pct
  INTO v, v_global
  FROM public.app_settings WHERE id = 1;

  RETURN COALESCE(v, v_global, 10);
END $$;

GRANT EXECUTE ON FUNCTION public.get_game_commission(text) TO authenticated, anon, service_role;

-- 3) Trigger factory: force commission_pct from settings on INSERT
CREATE OR REPLACE FUNCTION public._apply_game_commission()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_type text := TG_ARGV[0];
BEGIN
  NEW.commission_pct := public.get_game_commission(v_type);
  RETURN NEW;
END $$;

-- Attach one trigger per game table (drop first for idempotence)
DROP TRIGGER IF EXISTS trg_apply_commission ON public.ludo_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('ludo');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.chess_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('chess');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.domino_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('domino');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.rami_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('rami');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.fanorona_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('fanorona');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.poker_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('poker');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.billiard_games;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.billiard_games
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('billiard');

DROP TRIGGER IF EXISTS trg_apply_commission ON public.tournaments;
CREATE TRIGGER trg_apply_commission BEFORE INSERT ON public.tournaments
  FOR EACH ROW EXECUTE FUNCTION public._apply_game_commission('tournament');
