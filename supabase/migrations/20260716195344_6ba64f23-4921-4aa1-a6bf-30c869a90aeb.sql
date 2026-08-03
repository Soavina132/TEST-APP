
DROP FUNCTION IF EXISTS public.admin_add_bot(uuid, text);

CREATE OR REPLACE FUNCTION public.admin_add_bot(
  _game_id uuid,
  _bot_name text,
  _intelligence int DEFAULT 70,
  _win_bias int DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_slot int;
  v_colors text[] := ARRAY['red','blue','green','yellow'];
  v_count int;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé à l''administrateur'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT s INTO v_slot
    FROM generate_series(0, g.max_players-1) AS s
   WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id=_game_id)
   ORDER BY s LIMIT 1;

  INSERT INTO public.ludo_participants(
    game_id, user_id, slot, color, is_bot, bot_name, display_name,
    bot_intelligence, bot_win_bias, ready
  ) VALUES (
    _game_id, NULL, v_slot, v_colors[v_slot+1], TRUE,
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    COALESCE(NULLIF(trim(_bot_name),''),'Bot'),
    GREATEST(0, LEAST(100, COALESCE(_intelligence, 70))),
    GREATEST(-100, LEAST(100, COALESCE(_win_bias, 0))),
    TRUE
  );
END $function$;

GRANT EXECUTE ON FUNCTION public.admin_add_bot(uuid, text, int, int) TO authenticated;
