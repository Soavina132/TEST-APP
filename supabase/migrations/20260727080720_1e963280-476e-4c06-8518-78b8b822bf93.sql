
-- 1) House ledger table
CREATE TABLE IF NOT EXISTS public.house_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_type text NOT NULL,
  game_id uuid,
  entry_type text NOT NULL CHECK (entry_type IN ('commission','house_win')),
  amount numeric NOT NULL,
  pot numeric,
  commission_pct numeric,
  winner_id uuid,
  note text,
  meta jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.house_ledger TO authenticated;
GRANT ALL ON public.house_ledger TO service_role;

ALTER TABLE public.house_ledger ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "house_ledger_admin_read" ON public.house_ledger;
CREATE POLICY "house_ledger_admin_read" ON public.house_ledger
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE INDEX IF NOT EXISTS idx_house_ledger_game ON public.house_ledger(game_type, game_id);
CREATE INDEX IF NOT EXISTS idx_house_ledger_created ON public.house_ledger(created_at DESC);

-- 2) Generic trigger function on game tables
CREATE OR REPLACE FUNCTION public._log_house_on_finish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_game_type text := TG_ARGV[0];
  v_pot numeric := COALESCE((row_to_json(NEW)->>'pot')::numeric, 0);
  v_pct numeric := COALESCE((row_to_json(NEW)->>'commission_pct')::numeric, 10);
  v_winner uuid := NULLIF((row_to_json(NEW)->>'winner_id'),'')::uuid;
  v_is_bot boolean := false;
  v_commission numeric;
BEGIN
  -- Only fire when status transitions to 'finished'
  IF NEW.status IS DISTINCT FROM 'finished' THEN RETURN NEW; END IF;
  IF OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF v_pot IS NULL OR v_pot <= 0 THEN RETURN NEW; END IF;

  IF v_winner IS NULL THEN
    -- Draw / refund : no house income
    RETURN NEW;
  END IF;

  SELECT COALESCE(is_bot, false) INTO v_is_bot FROM public.profiles WHERE id = v_winner;

  IF v_is_bot THEN
    -- Bot won: platform captures the full pot
    INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
    VALUES (v_game_type, NEW.id, 'house_win', v_pot, v_pot, v_pct, v_winner,
            'Gain maison — victoire bot');
  ELSE
    v_commission := round(v_pot * v_pct / 100.0);
    IF v_commission > 0 THEN
      INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
      VALUES (v_game_type, NEW.id, 'commission', v_commission, v_pot, v_pct, v_winner,
              'Commission ' || v_pct || '% sur pot');
    END IF;
  END IF;

  RETURN NEW;
END $$;

-- 3) Attach trigger to each game table
DO $$
DECLARE
  t record;
BEGIN
  FOR t IN SELECT unnest(ARRAY['chess','domino','fanorona','ludo','rami','poker']) AS name LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_house_on_finish ON public.%I_games', t.name);
    EXECUTE format(
      'CREATE TRIGGER trg_house_on_finish AFTER UPDATE OF status ON public.%I_games
         FOR EACH ROW EXECUTE FUNCTION public._log_house_on_finish(%L)',
      t.name, t.name);
  END LOOP;
END $$;

-- 4) Admin KPI helper
CREATE OR REPLACE FUNCTION public.admin_house_income(_since timestamptz DEFAULT (now() - interval '30 days'))
RETURNS TABLE(game_type text, commission_total numeric, house_win_total numeric, entries bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT
    game_type,
    COALESCE(SUM(amount) FILTER (WHERE entry_type='commission'), 0)   AS commission_total,
    COALESCE(SUM(amount) FILTER (WHERE entry_type='house_win'), 0)    AS house_win_total,
    COUNT(*)                                                          AS entries
  FROM public.house_ledger
  WHERE created_at >= _since
    AND public.is_admin()
  GROUP BY game_type
  ORDER BY game_type;
$$;

GRANT EXECUTE ON FUNCTION public.admin_house_income(timestamptz) TO authenticated;
