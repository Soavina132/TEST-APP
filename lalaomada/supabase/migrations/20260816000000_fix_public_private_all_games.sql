-- ═══════════════════════════════════════════════════════════════════════
-- Fix: Public/Private visibility for all games + lobby display
-- 1. list_all_open_games: rami uses status='waiting' not 'open'
-- 2. list_public_open_games: same fix for rami
-- 3. chess_create_friends: add _private param (was hardcoded true)
-- 4. chess_create_stake: add _private param (was hardcoded false)
-- ═══════════════════════════════════════════════════════════════════════

-- ═══ 1. list_all_open_games: fix rami status filter ═══
CREATE OR REPLACE FUNCTION public.list_all_open_games()
RETURNS TABLE (
  game_id uuid,
  slug text,
  stake numeric,
  pot numeric,
  created_at timestamptz,
  max_players integer,
  players_count integer,
  host_id uuid,
  host_name text,
  target_score numeric,
  draw_mode text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = 'public'
AS $function$
BEGIN
  RETURN QUERY
  -- Domino
  SELECT g.id, 'domino'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    COALESCE(g.target_score, 0)::numeric,
    g.state->>'draw_mode'
  FROM public.domino_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Ludo
  SELECT g.id, 'ludo'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.ludo_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Fanorona
  SELECT g.id, 'fanorona'::text, g.stake, g.pot, g.created_at,
    2,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.fanorona_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Chess
  SELECT g.id, 'chess'::text, g.stake, g.pot, g.created_at,
    2,
    ((CASE WHEN g.white_id IS NOT NULL THEN 1 ELSE 0 END) +
     (CASE WHEN g.black_id IS NOT NULL THEN 1 ELSE 0 END)),
    COALESCE(g.white_id, g.black_id),
    COALESCE(hw.pseudo, hb.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.chess_games g
  LEFT JOIN public.profiles hw ON hw.id = g.white_id
  LEFT JOIN public.profiles hb ON hb.id = g.black_id
  WHERE g.status = 'open' AND g.is_private = false

  UNION ALL
  -- Rami (uses status='waiting' not 'open')
  SELECT g.id, 'rami'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id = g.id),
    g.created_by, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.rami_games g
  LEFT JOIN public.profiles h ON h.id = g.created_by
  WHERE g.status IN ('open', 'waiting') AND g.is_private = false

  UNION ALL
  -- Poker
  SELECT g.id, 'poker'::text, g.stake, g.pot, g.created_at,
    g.max_players,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id = g.id),
    g.host_id, COALESCE(h.pseudo, 'Joueur'),
    0::numeric,
    NULL::text
  FROM public.poker_games g
  LEFT JOIN public.profiles h ON h.id = g.host_id
  WHERE g.status = 'open' AND g.is_private = false

  ORDER BY created_at DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.list_all_open_games() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.list_all_open_games() TO authenticated;

-- ═══ 2. list_public_open_games: fix rami status filter ═══
CREATE OR REPLACE FUNCTION public.list_public_open_games()
 RETURNS TABLE(id uuid, game_slug text, max_players integer, stake numeric, pot numeric, room_code text, players_count integer, is_private boolean, created_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT g.id, 'ludo'::text, g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.ludo_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'domino', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.domino_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.domino_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'fanorona', 2, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.fanorona_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.fanorona_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.fanorona_participants p WHERE p.game_id=g.id) < 2

  UNION ALL
  SELECT g.id, 'chess', 2, g.stake, g.pot, g.room_code,
    ((CASE WHEN g.white_id IS NULL THEN 0 ELSE 1 END) + (CASE WHEN g.black_id IS NULL THEN 0 ELSE 1 END)),
    g.is_private, g.created_at
  FROM public.chess_games g
  WHERE g.status='open' AND g.is_private=false
    AND (g.white_id IS NULL OR g.black_id IS NULL)

  UNION ALL
  SELECT g.id, 'rami', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.rami_games g
  WHERE g.status IN ('open', 'waiting') AND g.is_private=false
    AND (SELECT count(*) FROM public.rami_participants p WHERE p.game_id=g.id) < g.max_players

  UNION ALL
  SELECT g.id, 'poker', g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.poker_players p WHERE p.game_id=g.id),
    g.is_private, g.created_at
  FROM public.poker_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.poker_players p WHERE p.game_id=g.id) < g.max_players

  ORDER BY created_at DESC;
$function$;

-- ═══ 3. chess_create_friends: add _private param ═══
CREATE OR REPLACE FUNCTION public.chess_create_friends(
  _color    text DEFAULT 'white',
  _time_min int DEFAULT 10,
  _private  boolean DEFAULT false
) RETURNS TABLE(id uuid, code text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_code text := public._chess_gen_code();
  v_human_w boolean := (lower(coalesce(_color,'white')) <> 'black');
  v_ms int := greatest(60000, coalesce(_time_min,10) * 60000);
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status, mode,
    stake, pot, commission_pct, is_private, room_code,
    time_control_min, white_time_ms, black_time_ms,
    fen, turn, ply
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid ELSE NULL END,
    CASE WHEN v_human_w THEN NULL ELSE v_uid END,
    'open', 'friends',
    0, 0, 0, COALESCE(_private, false), v_code,
    coalesce(_time_min,10), v_ms, v_ms,
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0
  ) RETURNING chess_games.id INTO v_id;
  RETURN QUERY SELECT v_id, v_code;
END $$;
GRANT EXECUTE ON FUNCTION public.chess_create_friends(text, int, boolean) TO authenticated;

-- ═══ 4. chess_create_stake: add _private param ═══
CREATE OR REPLACE FUNCTION public.chess_create_stake(
  _stake    numeric,
  _color    text DEFAULT 'white',
  _time_min int DEFAULT 10,
  _private  boolean DEFAULT false
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_human_w boolean := (lower(coalesce(_color,'white')) <> 'black');
  v_ms int := greatest(60000, coalesce(_time_min,10) * 60000);
  v_bal numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _stake <= 0 THEN RAISE EXCEPTION 'stake must be positive'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT balance_ar INTO v_bal FROM profiles WHERE id = v_uid FOR UPDATE;
  IF coalesce(v_bal,0) < _stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
  UPDATE profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO transactions(user_id, type, amount, meta) VALUES (v_uid, 'chess_stake', -_stake, jsonb_build_object('kind','hold'));

  INSERT INTO public.chess_games(
    host_id, white_id, black_id, status, mode,
    stake, pot, commission_pct, is_private, room_code,
    time_control_min, white_time_ms, black_time_ms,
    fen, turn, ply
  ) VALUES (
    v_uid,
    CASE WHEN v_human_w THEN v_uid ELSE NULL END,
    CASE WHEN v_human_w THEN NULL ELSE v_uid END,
    'open', 'stake',
    _stake, _stake, 10, COALESCE(_private, false), public._chess_gen_code(),
    coalesce(_time_min,10), v_ms, v_ms,
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1', 'w', 0
  ) RETURNING id INTO v_id;
  RETURN v_id;
END $function$;

REVOKE ALL ON FUNCTION public.chess_create_stake(numeric, text, int, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chess_create_stake(numeric, text, int, boolean) TO authenticated;
