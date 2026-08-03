
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS third_prize_paid_at timestamptz;

CREATE OR REPLACE FUNCTION public._trg_third_place_auto_payout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  trn         record;
  dist        jsonb;
  v_prize     numeric;
  v_third_amt numeric;
BEGIN
  IF COALESCE(NEW.is_third_place, false) = false THEN RETURN NEW; END IF;
  IF NEW.status NOT IN ('finished','forfeit') THEN RETURN NEW; END IF;
  IF NEW.winner_id IS NULL THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status AND OLD.winner_id IS NOT DISTINCT FROM NEW.winner_id THEN
    RETURN NEW;
  END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = NEW.tournament_id FOR UPDATE;
  IF trn IS NULL THEN RETURN NEW; END IF;
  IF trn.third_prize_paid_at IS NOT NULL THEN RETURN NEW; END IF;

  v_prize := COALESCE(trn.prize_pool, 0);
  dist    := COALESCE(trn.reward_distribution,
                      '{"first":60,"second":20,"third":10,"platform":10}'::jsonb);
  v_third_amt := ROUND(v_prize * COALESCE((dist->>'third')::numeric, 10) / 100, 0);

  IF v_prize > 0 AND v_third_amt > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_third_amt
     WHERE id = NEW.winner_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (NEW.winner_id, 'tournament_win', v_third_amt, NEW.tournament_id,
              '🥉 3e — Tournoi ' || COALESCE(trn.name,''));
  END IF;

  UPDATE public.tournaments
     SET third_place_id = NEW.winner_id,
         third_prize_paid_at = now()
   WHERE id = NEW.tournament_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_third_place_auto_payout ON public.tournament_matches;
CREATE TRIGGER trg_third_place_auto_payout
  AFTER INSERT OR UPDATE ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._trg_third_place_auto_payout();
