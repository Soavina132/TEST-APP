
CREATE OR REPLACE FUNCTION public.tournament_register(_tid uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_t public.tournaments%ROWTYPE;
  v_count int;
  v_balance numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth requise'; END IF;

  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'Inscriptions fermées'; END IF;

  SELECT count(*) INTO v_count FROM public.tournament_registrations WHERE tournament_id = _tid;
  IF v_count >= v_t.max_players THEN RAISE EXCEPTION 'Tournoi complet'; END IF;

  IF EXISTS(SELECT 1 FROM public.tournament_registrations WHERE tournament_id = _tid AND user_id = v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit';
  END IF;

  IF COALESCE(v_t.is_free, false) THEN
    -- Mode gratuit : cagnotte fournie par l'admin, aucun débit joueur.
    NULL;
  ELSE
    IF COALESCE(v_t.stake, 0) <= 0 THEN
      RAISE EXCEPTION 'Configuration invalide : mise nulle pour un tournoi payant';
    END IF;
    SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid;
    IF COALESCE(v_balance, 0) < v_t.stake THEN
      RAISE EXCEPTION 'Solde insuffisant';
    END IF;
  END IF;

  INSERT INTO public.tournament_registrations(tournament_id, user_id) VALUES (_tid, v_uid);
END
$function$;
