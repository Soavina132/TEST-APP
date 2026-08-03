
CREATE OR REPLACE FUNCTION public.player_add_bot(_game_id uuid, _bot_name text DEFAULT 'Bot')
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;
  IF COALESCE(g.stake,0) > 0 THEN RAISE EXCEPTION 'Bots réservés aux parties gratuites'; END IF;

  IF g.host_id <> v_uid
     AND NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid)
     AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Vous devez rejoindre la partie pour ajouter un bot';
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

REVOKE EXECUTE ON FUNCTION public.player_add_bot(uuid, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.player_add_bot(uuid, text) TO authenticated;
