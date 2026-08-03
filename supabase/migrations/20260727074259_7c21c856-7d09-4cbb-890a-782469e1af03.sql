-- 1) Garde-fou : le solde ne peut jamais devenir négatif
CREATE OR REPLACE FUNCTION public._guard_balance_non_negative()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF NEW.balance_ar < 0 THEN
    RAISE EXCEPTION 'Solde insuffisant (tentative de solde négatif: %)', NEW.balance_ar
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_guard_balance_non_negative ON public.profiles;
CREATE TRIGGER trg_guard_balance_non_negative
BEFORE UPDATE OF balance_ar ON public.profiles
FOR EACH ROW
WHEN (NEW.balance_ar IS DISTINCT FROM OLD.balance_ar)
EXECUTE FUNCTION public._guard_balance_non_negative();

-- 2) Corriger ludo_purge_unready_rooms : shadowing de variable + filtre bots
CREATE OR REPLACE FUNCTION public.ludo_purge_unready_rooms()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g RECORD;
  p RECORD;
  v_count int := 0;
BEGIN
  FOR g IN
    SELECT * FROM public.ludo_games
    WHERE status='open'
      AND ready_deadline IS NOT NULL
      AND now() > ready_deadline
  LOOP
    -- rembourse uniquement les humains (pas les bots), montant = mise du jeu
    FOR p IN
      SELECT user_id
      FROM public.ludo_participants
      WHERE game_id = g.id
        AND user_id IS NOT NULL
        AND COALESCE(is_bot,false) = false
    LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles
          SET balance_ar = balance_ar + g.stake
          WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', g.stake, g.id, 'Salle Ludo expirée (non prêts)');
      END IF;
    END LOOP;
    PERFORM public._ludo_purge(g.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $$;