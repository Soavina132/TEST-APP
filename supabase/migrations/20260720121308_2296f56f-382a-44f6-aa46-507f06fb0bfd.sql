-- Allow admin to add bots on paid Ludo/Domino games, and on any tournament (not only test).

CREATE OR REPLACE FUNCTION public.domino_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot'::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
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
END $function$;

CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot'::text)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_slot int;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_color text;
  v_count int;
  v_uid uuid := auth.uid();
  v_is_admin boolean := public.is_admin();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  IF NOT v_is_admin THEN
    IF COALESCE(g.stake,0) > 0 THEN
      RAISE EXCEPTION 'Bots réservés aux parties gratuites';
    END IF;
    IF g.host_id <> v_uid
       AND NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
      RAISE EXCEPTION 'Vous devez rejoindre la partie pour ajouter un bot';
    END IF;
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT s INTO v_slot
    FROM generate_series(0, g.max_players-1) AS s
   WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id=_game_id)
   ORDER BY s LIMIT 1;

  IF g.max_players = 2 THEN v_color := v_colors2[v_slot+1];
  ELSIF g.max_players = 3 THEN v_color := v_colors3[v_slot+1];
  ELSE v_color := v_colors4[v_slot+1];
  END IF;

  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, bot_win_bias, ready
  ) VALUES (
    _game_id, NULL, v_slot, v_color, TRUE,
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    70, 0, TRUE
  );
END $function$;

CREATE OR REPLACE FUNCTION public.admin_tournament_fill_with_bots(_tid uuid, _target_total integer DEFAULT NULL::integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_t public.tournaments%ROWTYPE; v_regs int; v_bots int; v_target int; v_needed int; i int; v_alias text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF v_t.id IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF v_t.status <> 'open' THEN RAISE EXCEPTION 'Le tournoi est déjà démarré'; END IF;

  v_target := COALESCE(_target_total, v_t.max_players);
  IF v_target < 2 THEN RAISE EXCEPTION 'Minimum 2 joueurs'; END IF;

  IF v_target <> v_t.max_players THEN
    UPDATE public.tournaments SET max_players = v_target,
      total_rounds = GREATEST(1, CEIL(LOG(2, GREATEST(v_target,2))))::int
      WHERE id = _tid;
  END IF;

  SELECT count(*) INTO v_regs FROM public.tournament_registrations WHERE tournament_id = _tid;
  SELECT count(*) INTO v_bots FROM public.tournament_bots WHERE tournament_id = _tid;
  v_needed := v_target - v_regs - v_bots;
  IF v_needed <= 0 THEN RETURN jsonb_build_object('ok', true, 'added', 0, 'total', v_regs + v_bots); END IF;

  FOR i IN 1..v_needed LOOP
    SELECT pseudo INTO v_alias FROM public.admin_aliases ORDER BY random() LIMIT 1;
    IF v_alias IS NULL THEN v_alias := 'Bot #' || (v_bots + i); END IF;
    INSERT INTO public.tournament_bots(tournament_id, display_name, strength)
      VALUES (_tid, v_alias, 40 + floor(random()*30)::int);
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'added', v_needed, 'total', v_regs + v_bots + v_needed);
END $function$;