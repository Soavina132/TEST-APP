CREATE OR REPLACE FUNCTION public.domino_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
  g public.domino_games%ROWTYPE;
  v_count int;
  v_slot int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_name text;
  v_ready_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake, 0) > 0 THEN
      RAISE EXCEPTION 'Bots réservés aux parties gratuites';
    END IF;
    IF g.host_id <> v_uid
       AND NOT EXISTS (SELECT 1 FROM public.domino_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Rejoignez la partie pour ajouter un bot';
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM public.domino_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  v_slot := v_count;
  v_name := COALESCE(NULLIF(trim(_bot_name), ''), v_bot_names[LEAST(v_slot + 1, array_length(v_bot_names, 1))]);

  INSERT INTO public.domino_participants(
    game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
  ) VALUES (_game_id, NULL, v_slot, v_name, TRUE, TRUE, v_name, 70);

  SELECT count(*), count(*) FILTER (WHERE ready)
    INTO v_count, v_ready_count
    FROM public.domino_participants
   WHERE game_id = _game_id;

  IF v_count = g.max_players AND v_ready_count = g.max_players THEN
    PERFORM public._domino_start(_game_id);
  END IF;
END $function$
