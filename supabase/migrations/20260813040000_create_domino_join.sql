CREATE OR REPLACE FUNCTION public.domino_join(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g record;
  v_balance numeric;
  v_name text;
  v_count int;
  v_slot int;
  v_paused boolean;
  v_banned boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned INTO v_banned FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;

  IF EXISTS (SELECT 1 FROM public.domino_participants WHERE game_id = _game_id AND user_id = v_uid) THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie complète'; END IF;

  SELECT balance_ar, COALESCE(pseudo, 'Joueur') INTO v_balance, v_name
    FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance IS NULL OR v_balance < g.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  v_slot := v_count;

  IF g.stake > 0 THEN
    PERFORM public.debit_user_balance(v_uid, g.stake, 'domino_stake', _game_id, 'Join domino');
    UPDATE public.domino_games SET pot = pot + g.stake WHERE id = _game_id;
  END IF;

  INSERT INTO public.domino_participants(game_id, user_id, slot, ready, forfeited, score, display_name, is_bot, joined_at)
    VALUES (_game_id, v_uid, v_slot, false, false, 0, v_name, false, now());

  UPDATE public.domino_games SET updated_at = now() WHERE id = _game_id;
END;
$function$;
