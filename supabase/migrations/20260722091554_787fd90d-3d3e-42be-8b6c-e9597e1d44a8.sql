
CREATE OR REPLACE FUNCTION public._tournaments_validate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  d jsonb;
  s numeric;
  wc int;
  p1 numeric; p2 numeric; p3 numeric; pp numeric;
BEGIN
  IF NEW.max_players IS NULL OR NEW.max_players < 2 OR NEW.max_players > 128 THEN
    RAISE EXCEPTION 'Nombre de joueurs invalide (2 à 128).';
  END IF;

  IF COALESCE(NEW.is_free, false) THEN
    IF COALESCE(NEW.stake, 0) <> 0 THEN
      RAISE EXCEPTION 'Tournoi gratuit : la mise doit être 0.';
    END IF;
    IF COALESCE(NEW.prize_pool, 0) < 0 THEN
      RAISE EXCEPTION 'Cagnotte invalide (doit être ≥ 0).';
    END IF;
    IF COALESCE(NEW.prize_pool, 0) > 100000000 THEN
      RAISE EXCEPTION 'Cagnotte trop élevée (max 100 000 000 Ar).';
    END IF;
  ELSE
    IF COALESCE(NEW.stake, 0) <= 0 THEN
      RAISE EXCEPTION 'La mise doit être > 0 pour un tournoi payant.';
    END IF;
    IF NEW.stake < 100 THEN
      RAISE EXCEPTION 'Mise minimum : 100 Ar.';
    END IF;
    IF NEW.stake > 10000000 THEN
      RAISE EXCEPTION 'Mise trop élevée (max 10 000 000 Ar).';
    END IF;
  END IF;

  wc := COALESCE(NEW.winners_count, 3);
  IF wc < 1 OR wc > 3 THEN
    RAISE EXCEPTION 'Nombre de vainqueurs invalide (1, 2 ou 3).';
  END IF;
  IF wc >= NEW.max_players THEN
    RAISE EXCEPTION 'Le nombre de vainqueurs doit être < nombre de joueurs.';
  END IF;
  NEW.winners_count := wc;

  d := NEW.reward_distribution;
  IF d IS NOT NULL THEN
    p1 := COALESCE((d->>'first')::numeric, 0);
    p2 := COALESCE((d->>'second')::numeric, 0);
    p3 := COALESCE((d->>'third')::numeric, 0);
    pp := COALESCE((d->>'platform')::numeric, 0);

    IF p1 < 0 OR p2 < 0 OR p3 < 0 OR pp < 0 THEN
      RAISE EXCEPTION 'Les parts de récompense ne peuvent pas être négatives.';
    END IF;

    s := p1 + p2 + p3 + pp;
    IF round(s::numeric, 2) <> 100 THEN
      RAISE EXCEPTION 'La répartition des récompenses doit totaliser 100%% (actuel: %).', s;
    END IF;

    IF wc < 3 AND p3 <> 0 THEN
      RAISE EXCEPTION '3ᵉ part doit être 0 quand winners_count < 3.';
    END IF;
    IF wc < 2 AND p2 <> 0 THEN
      RAISE EXCEPTION '2ᵉ part doit être 0 quand winners_count < 2.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_tournaments_validate ON public.tournaments;
CREATE TRIGGER trg_tournaments_validate
  BEFORE INSERT OR UPDATE ON public.tournaments
  FOR EACH ROW
  EXECUTE FUNCTION public._tournaments_validate();
