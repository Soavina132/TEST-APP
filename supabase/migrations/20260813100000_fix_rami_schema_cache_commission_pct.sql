-- ═══════════════════════════════════════════════════════════════════════════
-- Migration: Fix rami_create, rami_start_solo_bot signatures + commission_pct
-- Date: 2026-08-13
-- Issues fixed:
--   1. rami_create missing _game_mode + _seven_cards params (PGRST202)
--   2. rami_start_solo_bot missing _game_mode param (PGRST202)
--   3. Functions referencing commission_pct on app_settings instead of
--      game_commission_pct (42703: column does not exist)
-- ═══════════════════════════════════════════════════════════════════════════

-- ───────────────────────────────────────────────────────────────────────────
-- 1. rami_create: add _game_mode + _seven_cards parameters
--    DB had 5 params; frontend sends 7. rami_games already has both columns.
-- ───────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.rami_create(numeric, integer, boolean, integer);
DROP FUNCTION IF EXISTS public.rami_create(numeric, integer, boolean, integer, text);
DROP FUNCTION IF EXISTS public.rami_create(numeric, integer, boolean, integer, text, text);

CREATE OR REPLACE FUNCTION public.rami_create(
  _stake       numeric,
  _max         integer,
  _private     boolean,
  _commission  integer,
  _joker_mode  text     DEFAULT 'classique',
  _game_mode   text     DEFAULT 'bordel',
  _seven_cards boolean  DEFAULT true
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  _uid   uuid := auth.uid();
  _id    uuid;
  _code  text;
  _bal   numeric;
  _name  text;
  _mode  text;
  _gmode text;
  _seven boolean;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max < 2 OR _max > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'stake invalid'; END IF;

  _mode := COALESCE(_joker_mode, 'classique');
  IF _mode NOT IN ('sans','aleatoire','classique','double') THEN
    RAISE EXCEPTION 'mode joker invalide';
  END IF;

  _gmode := COALESCE(_game_mode, 'bordel');
  IF _gmode NOT IN ('bordel','naturel') THEN RAISE EXCEPTION 'mode de jeu invalide'; END IF;

  _seven := COALESCE(_seven_cards, true);

  SELECT balance_ar, COALESCE(pseudo,'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid FOR UPDATE;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;

  _code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct,
    created_by, pot, joker_mode, game_mode, seven_cards
  ) VALUES (
    _code, COALESCE(_private, true), _stake, _max, COALESCE(_commission, 10),
    _uid, _stake, _mode, _gmode, _seven
  ) RETURNING id INTO _id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES (_uid, 'rami_stake', -_stake, _id, 'Create rami');
  END IF;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name)
  VALUES (_id, _uid, 0, _name);

  RETURN _id;
END $$;

REVOKE ALL ON FUNCTION public.rami_create(numeric, integer, boolean, integer, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_create(numeric, integer, boolean, integer, text, text, boolean) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 2. rami_start_solo_bot: add _game_mode parameter
--    DB had 3 params; frontend sends 4.
-- ───────────────────────────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.rami_start_solo_bot(text, text, integer);
DROP FUNCTION IF EXISTS public.rami_start_solo_bot(integer, text, text);

CREATE OR REPLACE FUNCTION public.rami_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty  text     DEFAULT 'medium',
  _joker_mode  text     DEFAULT 'classique',
  _game_mode   text     DEFAULT 'bordel'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid      uuid := auth.uid();
  v_game_id  uuid;
  v_code     text;
  v_name     text;
  v_intel    int;
  v_paused   boolean;
  v_banned   boolean;
  v_slot     int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
  v_max      int;
  v_deck     int[];
  v_i        int;
  v_j        int;
  v_tmp      int;
  v_hands    jsonb := '{}'::jsonb;
  v_hand     int[];
  v_key      text;
  v_rj       int := NULL;
  v_top      int;
  v_first    int;
  v_state    jsonb;
BEGIN
  PERFORM public._assert_solo_bot_enabled();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  IF _joker_mode NOT IN ('sans','aleatoire','classique','double') THEN _joker_mode := 'classique'; END IF;
  IF _game_mode NOT IN ('bordel','naturel') THEN _game_mode := 'bordel'; END IF;

  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;

  SELECT banned, COALESCE(pseudo,'Joueur') INTO v_banned, v_name
    FROM public.profiles WHERE id = v_uid;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;

  CASE lower(_difficulty)
    WHEN 'easy' THEN v_intel := 30;
    WHEN 'hard' THEN v_intel := 95;
    ELSE v_intel := 70;
  END CASE;

  v_code := public._rami_gen_code();

  INSERT INTO public.rami_games (
    room_code, is_private, stake, max_players, commission_pct,
    created_by, pot, joker_mode, game_mode, status
  ) VALUES (
    v_code, true, 0, _max_players, 0, v_uid, 0, _joker_mode, _game_mode, 'waiting'
  ) RETURNING id INTO v_game_id;

  INSERT INTO public.rami_participants(game_id, user_id, slot, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_name, true, false);

  FOR v_slot IN 1.._max_players - 1 LOOP
    INSERT INTO public.rami_participants(
      game_id, user_id, slot, display_name, ready, is_bot, bot_name, bot_intelligence
    ) VALUES (
      v_game_id, NULL, v_slot, v_bot_names[v_slot], true, true, v_bot_names[v_slot], v_intel
    );
  END LOOP;

  IF _joker_mode IN ('classique','double') THEN v_max := 56; ELSE v_max := 52; END IF;
  v_deck := ARRAY(SELECT generate_series(0, v_max - 1));
  FOR v_i IN REVERSE v_max..2 LOOP
    v_j := 1 + floor(random() * v_i)::int;
    v_tmp := v_deck[v_i]; v_deck[v_i] := v_deck[v_j]; v_deck[v_j] := v_tmp;
  END LOOP;

  FOR v_slot IN 0.._max_players - 1 LOOP
    v_hand := v_deck[1:13];
    v_deck := v_deck[14:array_length(v_deck,1)];
    v_key := CASE WHEN v_slot = 0 THEN v_uid::text ELSE 'bot:' || v_slot::text END;
    v_hands := v_hands || jsonb_build_object(v_key, to_jsonb(v_hand));
    UPDATE public.rami_participants SET hand_count = 13
      WHERE game_id = v_game_id AND slot = v_slot;
  END LOOP;

  IF _joker_mode IN ('aleatoire','double') THEN
    v_i := 1;
    WHILE v_i <= array_length(v_deck,1) AND v_deck[v_i] >= 52 LOOP
      v_i := v_i + 1;
    END LOOP;
    IF v_i <= array_length(v_deck,1) THEN
      v_rj := v_deck[v_i];
      v_deck := v_deck[1:v_i-1] || v_deck[v_i+1:array_length(v_deck,1)];
    END IF;
  END IF;

  v_top   := v_deck[1];
  v_deck  := v_deck[2:array_length(v_deck,1)];
  v_first := floor(random() * _max_players)::int;

  v_state := jsonb_build_object(
    'deck',           to_jsonb(v_deck),
    'discards',       jsonb_build_object('_seed', jsonb_build_array(v_top)),
    'last_discard_by', '_seed',
    'hands',          v_hands,
    'melds',          '[]'::jsonb,
    'first_player',   v_first
  );

  UPDATE public.rami_games SET
    status        = 'playing',
    state         = v_state,
    started_at    = now(),
    current_turn  = v_first,
    turn_phase    = 'draw',
    random_joker  = v_rj,
    turn_deadline = now() + interval '60 seconds'
  WHERE id = v_game_id;

  PERFORM public._rami_autoplay_bots(v_game_id);
  RETURN v_game_id;
END $function$;

REVOKE ALL ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.rami_start_solo_bot(integer, text, text, text) TO authenticated;

-- ───────────────────────────────────────────────────────────────────────────
-- 3. Fix commission_pct → game_commission_pct in app_settings references
--    app_settings has game_commission_pct, NOT commission_pct.
--    PostgreSQL error 42703: column "commission_pct" does not exist.
-- ───────────────────────────────────────────────────────────────────────────

-- 3a. Fix leaderboard_winners (chess_games subquery)
CREATE OR REPLACE FUNCTION public.leaderboard_winners(
  _period text DEFAULT 'all',
  _limit  integer DEFAULT 20,
  _slug   text   DEFAULT NULL
) RETURNS TABLE(rank integer, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn,
           g.pot * (1 - g.commission_pct/100.0) AS won
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'ludo')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'domino')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'fanorona')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.display_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'rami')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULL::text,
           g.stake * 2 * (1 - COALESCE((SELECT game_commission_pct FROM app_settings WHERE id=1),0)/100.0)
      FROM chess_games g, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'chess')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL
    SELECT g.winner_id, NULLIF(trim(pp.bot_name),''),
           g.pot * (1 - COALESCE(g.commission_pct,0)/100.0)
      FROM poker_games g JOIN poker_players pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE (_slug IS NULL OR _slug = 'all' OR _slug = 'poker')
        AND g.status='finished' AND g.winner_id IS NOT NULL
        AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  alias_admins AS (
    SELECT DISTINCT a.admin_id AS uid FROM public.admin_aliases a
    UNION SELECT ap.admin_id FROM public.admin_persona ap
    UNION SELECT p.id FROM public.profiles p WHERE lower(p.email) = 'soavinapierrit@gmail.com'
  ),
  filtered AS (
    SELECT r.uid, r.dn, r.won,
           (r.uid IN (SELECT uid FROM alias_admins)) AS is_alias_admin
      FROM raw r
     WHERE NOT EXISTS (SELECT 1 FROM public.profiles pb WHERE pb.id = r.uid AND (pb.is_bot = true OR pb.leaderboard_hidden = true))
  ),
  kept AS (
    SELECT f.uid, f.dn, f.won, ('alias:' || f.dn) AS key
      FROM filtered f
     WHERE f.is_alias_admin
       AND f.dn IS NOT NULL
       AND EXISTS (SELECT 1 FROM public.admin_aliases a WHERE a.admin_id = f.uid AND a.pseudo = f.dn)
    UNION ALL
    SELECT f.uid, f.dn, f.won, f.uid::text
      FROM filtered f
     WHERE NOT f.is_alias_admin
  ),
  agg AS (
    SELECT key,
           MIN(uid::text)::uuid AS uid,
           COUNT(*) AS wins,
           SUM(won) AS total_won,
           MAX(dn) AS dn,
           bool_or(key LIKE 'alias:%') AS is_alias
    FROM kept
    GROUP BY key
  )
  SELECT ROW_NUMBER() OVER (ORDER BY total_won DESC NULLS LAST, wins DESC)::int AS rank,
         a.uid AS user_id,
         COALESCE(a.dn, p.pseudo, 'Joueur') AS name,
         CASE WHEN a.is_alias
              THEN (SELECT al.avatar_url FROM public.admin_aliases al WHERE al.admin_id = a.uid AND al.pseudo = a.dn LIMIT 1)
              ELSE p.avatar_url END AS avatar_url,
         a.wins,
         a.total_won
    FROM agg a
    LEFT JOIN public.profiles p ON p.id = a.uid
    ORDER BY total_won DESC NULLS LAST, wins DESC
    LIMIT LEAST(COALESCE(_limit, 20), 100);
$function$;

REVOKE ALL ON FUNCTION public.leaderboard_winners(text, integer, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text, integer, text) TO authenticated;

-- 3b. Fix ludo_start_solo_bot: commission_pct → game_commission_pct
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _difficulty  text     DEFAULT 'medium',
  _stake       numeric  DEFAULT 0,
  _mode        text     DEFAULT 'classic',
  _match_type  text     DEFAULT 'solo'
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public' AS $function$
DECLARE
  v_uid        UUID := auth.uid();
  v_game_id    UUID;
  v_code       TEXT;
  v_commission NUMERIC;
  v_i          INT;
  v_slot       INT;
  v_color      TEXT;
  v_colors     TEXT[] := ARRAY['red','green','yellow','blue'];
  v_bots       TEXT[] := ARRAY['BotAlpha','BotBeta','BotGamma','BotDelta'];
  v_intel      INT;
  v_bias       INT;
  v_mp         INT;
  v_mode       TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  v_mp := LEAST(GREATEST(COALESCE(_max_players, 2), 2), 4);

  -- FIX: game_commission_pct (was commission_pct, which doesn't exist)
  SELECT COALESCE(game_commission_pct, 10) INTO v_commission FROM public.app_settings WHERE id = 1;

  v_code := upper(substr(md5(random()::text), 1, 6));

  INSERT INTO public.ludo_games(
    host_id, max_players, stake, pot, commission_pct,
    room_code, is_private, mode, match_type, status, is_solo
  ) VALUES (
    v_uid, v_mp, _stake, _stake * v_mp, v_commission,
    v_code, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE
  ) RETURNING id INTO v_game_id;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, ready, joined_at)
  VALUES (v_game_id, v_uid, 0, v_colors[1], FALSE, TRUE, now());

  v_intel := CASE WHEN _difficulty = 'hard' THEN 85 WHEN _difficulty = 'easy' THEN 40 ELSE 65 END;
  v_bias  := CASE WHEN _difficulty = 'hard' THEN 15 WHEN _difficulty = 'easy' THEN 0 ELSE 5 END;

  FOR v_i IN 1..v_mp - 1 LOOP
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot,
      bot_name, bot_intelligence, bot_win_bias, ready, joined_at
    ) VALUES (
      v_game_id, v_uid, v_i, v_colors[v_i+1], TRUE,
      v_bots[v_i], v_intel, v_bias, TRUE, now()
    );
  END LOOP;

  UPDATE public.ludo_games SET
    status = 'playing',
    started_at = now(),
    state = public._ludo_init_state(v_mp, v_mode),
    current_turn = 0
  WHERE id = v_game_id;

  RETURN v_game_id;
END $function$;

REVOKE ALL ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, text, numeric, text, text) TO authenticated;
