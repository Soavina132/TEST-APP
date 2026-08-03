-- ============ 1. DOMINO : pioche automatique à l'expiration du timer ============
CREATE OR REPLACE FUNCTION public._domino_auto_draw(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g record; st jsonb; stock jsonb; hand jsonb; drawn jsonb;
  slot int; guard int := 0; did boolean := false;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN false; END IF;
  st := g.state;
  IF COALESCE(st->>'draw_mode','with') <> 'with' THEN RETURN false; END IF;
  slot := g.current_turn;
  IF public._domino_slot_has_playable(st, slot) THEN RETURN false; END IF;

  stock := COALESCE(st->'stock','[]'::jsonb);
  hand  := COALESCE(st->'hands'->slot::text,'[]'::jsonb);

  WHILE jsonb_array_length(stock) > 0 AND guard < 30 LOOP
    guard := guard + 1;
    drawn := stock -> 0;
    stock := stock - 0;
    hand  := hand || jsonb_build_array(drawn);
    did   := true;
    st := jsonb_set(st, ARRAY['hands', slot::text], hand);
    st := jsonb_set(st, '{stock}', stock);
    EXIT WHEN public._domino_slot_has_playable(st, slot);
  END LOOP;

  IF NOT did THEN RETURN false; END IF;

  UPDATE public.domino_games
     SET state = st,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
  RETURN public._domino_slot_has_playable(st, slot);
END $$;

GRANT EXECUTE ON FUNCTION public._domino_auto_draw(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g record;
  cur_uid uuid;
  _cfg record;
  _skips int;
  _next int;
  remaining int;
  last_slot int;
  _break_until timestamptz;
  _reveal_until timestamptz;
  _deal_until timestamptz;
  required_slot int;
  board_empty boolean;
  cur_is_bot boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NULL OR _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games
         SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb)
       WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  SELECT COALESCE(dp.is_bot, false) INTO cur_is_bot
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  IF COALESCE(cur_is_bot, false) THEN
    PERFORM public._domino_bot_step(_game_id);
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT user_id INTO cur_uid
    FROM public.domino_participants
   WHERE game_id = _game_id
     AND slot = g.current_turn
     AND forfeited = false;

  IF cur_uid IS NULL THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games
         SET current_turn = _next,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  -- Le joueur n'a rien joué : s'il devait piocher, on pioche à sa place
  -- jusqu'à obtenir une tuile jouable, et on lui rend son temps.
  IF public._domino_auto_draw(_game_id) THEN
    RETURN;
  END IF;
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id;

  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants
       SET forfeited = true
     WHERE game_id = _game_id
       AND user_id = cur_uid;

    SELECT count(*) INTO remaining
      FROM public.domino_participants
     WHERE game_id = _game_id
       AND forfeited = false;

    IF remaining <= 1 THEN
      SELECT slot INTO last_slot
        FROM public.domino_participants
       WHERE game_id = _game_id
         AND forfeited = false
       LIMIT 1;

      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;

    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET state = g.state,
             turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);

    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games
         SET turn_skips = g.turn_skips,
             current_turn = required_slot,
             turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
       WHERE id = _game_id;
      PERFORM public._domino_bot_step(_game_id);
      RETURN;
    END IF;

    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    PERFORM public._domino_end_round(_game_id, _next);
    RETURN;
  END IF;

  UPDATE public.domino_games
     SET current_turn = _next,
         turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
   WHERE id = _game_id;

  PERFORM public._domino_bot_step(_game_id);
END;
$$;

-- ============ 2. LUDO : symétrie à 2 joueurs ============
CREATE OR REPLACE FUNCTION public.ludo_join(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.ludo_games%ROWTYPE;
  v_balance numeric;
  v_name text;
  v_count int;
  v_slot int;
  v_color text;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Connexion requise'; END IF;
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'Partie non disponible'; END IF;

  IF EXISTS(SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid) THEN
    RETURN _game_id;
  END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;
  IF v_count >= g.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;

  SELECT balance_ar, pseudo INTO v_balance, v_name FROM public.profiles WHERE id = v_uid;
  IF COALESCE(g.stake,0) > 0 AND COALESCE(v_balance,0) < g.stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;

  SELECT s INTO v_slot FROM generate_series(0, g.max_players-1) s
    WHERE s NOT IN (SELECT slot FROM public.ludo_participants WHERE game_id = _game_id)
    ORDER BY s LIMIT 1;

  IF g.max_players = 2 THEN v_color := v_colors2[v_slot + 1];
  ELSIF g.max_players = 3 THEN v_color := v_colors3[v_slot + 1];
  ELSE v_color := v_colors4[v_slot + 1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
    VALUES (_game_id, v_uid, v_slot, v_color, COALESCE(v_name, 'Joueur'));

  IF COALESCE(g.stake,0) > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'ludo_stake', -g.stake, _game_id, 'Rejoindre partie Ludo');
    UPDATE public.ludo_games SET pot = pot + g.stake WHERE id = _game_id;
  END IF;

  RETURN _game_id;
END $$;

-- Corriger les parties 2 joueurs déjà ouvertes (non démarrées)
UPDATE public.ludo_participants p
   SET color = 'yellow'
  FROM public.ludo_games g
 WHERE g.id = p.game_id AND g.status = 'open' AND g.max_players = 2
   AND p.slot = 1 AND p.color <> 'yellow';

-- ============ 3. LUDO : option déplacement automatique ============
ALTER TABLE public.ludo_games ADD COLUMN IF NOT EXISTS auto_move boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.ludo_set_auto_move(_game_id uuid, _enabled boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE g public.ludo_games%ROWTYPE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.host_id <> auth.uid() AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Réservé au créateur de la partie';
  END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'La partie a déjà commencé'; END IF;
  UPDATE public.ludo_games SET auto_move = COALESCE(_enabled, false) WHERE id = _game_id;
END $$;

GRANT EXECUTE ON FUNCTION public.ludo_set_auto_move(uuid, boolean) TO authenticated;

-- ludo_move : autoriser le déplacement automatique côté serveur
CREATE OR REPLACE FUNCTION public._ludo_auto_move(_game_id uuid, _slot integer)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_dice int; v_playable jsonb; v_count int; v_pawn int;
  ii int; idx int; pawn jsonb; best_step int := -1;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN false; END IF;
  IF NOT COALESCE(g.auto_move, false) THEN RETURN false; END IF;
  IF NOT COALESCE((g.state->>'must_move')::boolean, false) THEN RETURN false; END IF;
  v_dice := NULLIF(g.state->>'dice','null')::int;
  IF v_dice IS NULL THEN RETURN false; END IF;

  v_playable := public._ludo_playable_pawns(g.state->'pawns', _slot, v_dice);
  v_count := jsonb_array_length(COALESCE(v_playable, '[]'::jsonb));
  IF v_count = 0 THEN RETURN false; END IF;

  v_pawn := (v_playable->0)::int;
  IF v_dice = 6 THEN
    FOR ii IN 0..(v_count-1) LOOP
      idx := (v_playable->ii)::int;
      pawn := g.state->'pawns'->_slot::text->idx;
      IF pawn->>'s' = 'yard' THEN v_pawn := idx; EXIT; END IF;
    END LOOP;
  END IF;
  IF v_pawn = (v_playable->0)::int THEN
    FOR ii IN 0..(v_count-1) LOOP
      idx := (v_playable->ii)::int;
      pawn := g.state->'pawns'->_slot::text->idx;
      IF pawn->>'s' = 'track' AND (pawn->>'k')::int > best_step THEN
        best_step := (pawn->>'k')::int; v_pawn := idx;
      END IF;
    END LOOP;
  END IF;

  PERFORM set_config('app.ludo_auto', 'on', true);
  PERFORM public.ludo_move(_game_id, v_pawn);
  PERFORM set_config('app.ludo_auto', 'off', true);
  RETURN true;
END $$;

GRANT EXECUTE ON FUNCTION public._ludo_auto_move(uuid, integer) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot int; v_started timestamptz;
  v_uid uuid; v_isbot boolean; v_secs int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_uid, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  SELECT COALESCE(turn_seconds,30) INTO v_secs FROM public.app_settings WHERE id=1;
  v_started := (st->>'turn_started_at')::timestamptz;
  IF now() - v_started < (v_secs || ' seconds')::interval THEN RETURN st; END IF;

  -- Déplacement automatique : uniquement si le dé a déjà été lancé.
  IF NOT COALESCE(v_isbot,false)
     AND COALESCE((st->>'must_move')::boolean, false)
     AND COALESCE(g.auto_move, false) THEN
    IF public._ludo_auto_move(_game_id, v_slot) THEN
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    END IF;
  END IF;

  IF NOT v_isbot AND NOT (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t1 = afk_t1 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  IF NOT v_isbot AND (st->>'must_move')::BOOLEAN THEN
    UPDATE public.ludo_participants SET afk_t2 = afk_t2 + 1 WHERE game_id=_game_id AND slot=v_slot;
  END IF;

  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  IF NOT v_isbot THEN PERFORM public._ludo_check_afk(_game_id, v_slot); END IF;
  RETURN st;
END $$;

-- ============ 4. CHAT : figer l'identité de l'expéditeur ============
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS sender_name text;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS sender_avatar text;

CREATE OR REPLACE FUNCTION public._chat_snapshot_sender()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.sender_name IS NULL OR NEW.sender_avatar IS NULL THEN
    SELECT COALESCE(NEW.sender_name, p.pseudo, 'Joueur'), COALESCE(NEW.sender_avatar, p.avatar_url)
      INTO NEW.sender_name, NEW.sender_avatar
      FROM public.profiles p WHERE p.id = NEW.user_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_chat_snapshot_sender ON public.chat_messages;
CREATE TRIGGER trg_chat_snapshot_sender
BEFORE INSERT ON public.chat_messages
FOR EACH ROW EXECUTE FUNCTION public._chat_snapshot_sender();

UPDATE public.chat_messages m
   SET sender_name = p.pseudo, sender_avatar = p.avatar_url
  FROM public.profiles p
 WHERE p.id = m.user_id AND m.sender_name IS NULL;

-- ============ 5. CLASSEMENT : identité réelle admin masquée, un classement par alias ============
CREATE OR REPLACE FUNCTION public.leaderboard_winners(_period text DEFAULT 'all'::text, _limit integer DEFAULT 20, _slug text DEFAULT NULL::text)
RETURNS TABLE(rank integer, user_id uuid, name text, avatar_url text, wins bigint, total_won numeric)
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
           g.stake * 2 * (1 - COALESCE((SELECT commission_pct FROM app_settings WHERE id=1),0)/100.0)
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
    -- Les comptes à alias n'apparaissent JAMAIS sous leur identité réelle :
    -- seules les parties jouées sous un alias enregistré comptent, une ligne par alias.
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
$$;