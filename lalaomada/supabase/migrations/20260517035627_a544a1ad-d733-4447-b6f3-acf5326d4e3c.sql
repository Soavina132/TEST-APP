
-- ============ SCHEMA ============
ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS is_private boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS mode text NOT NULL DEFAULT 'classic',
  ADD COLUMN IF NOT EXISTS disconnect_until jsonb NOT NULL DEFAULT '{}'::jsonb;

ALTER TABLE public.ludo_participants
  ADD COLUMN IF NOT EXISTS ready boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS last_seen timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS consecutive_sixes integer NOT NULL DEFAULT 0;

-- ============ join_game: stop auto-start ============
CREATE OR REPLACE FUNCTION public.join_game(_game_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT; v_paused BOOLEAN; v_banned BOOLEAN;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Déjà inscrit'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id=v_uid FOR UPDATE;
  IF v_balance < v_game.stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count; v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT _game_id, v_uid, v_slot, v_color, pseudo FROM public.profiles WHERE id=v_uid;
  UPDATE public.profiles SET balance_ar = balance_ar - v_game.stake WHERE id=v_uid;
  UPDATE public.ludo_games SET pot = pot + v_game.stake WHERE id=_game_id;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
    VALUES (v_uid,'stake',-v_game.stake,_game_id,'Mise rejoindre partie');
  -- NO auto-start anymore. Players must press Ready.
END $function$;

-- ============ create_private_game ============
CREATE OR REPLACE FUNCTION public.create_private_game(_max_players integer, _stake numeric, _mode text DEFAULT 'classic')
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game_id UUID;
  v_commission NUMERIC; v_paused BOOLEAN; v_banned BOOLEAN; v_code TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF public.is_admin() THEN RAISE EXCEPTION 'Les administrateurs ne peuvent pas jouer'; END IF;
  SELECT paused INTO v_paused FROM public.app_settings WHERE id=1;
  IF COALESCE(v_paused,FALSE) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned INTO v_banned FROM public.profiles WHERE id=v_uid;
  IF COALESCE(v_banned,FALSE) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides'; END IF;
  IF _stake < 0 THEN RAISE EXCEPTION 'Mise invalide'; END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode)
    VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,10), v_code, TRUE, COALESCE(_mode,'classic'))
    RETURNING id INTO v_game_id;
  UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
  INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie privée');
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,display_name)
    SELECT v_game_id, v_uid, 0, 'red', pseudo FROM public.profiles WHERE id = v_uid;
  RETURN v_game_id;
END $function$;

-- ============ find_or_create_public_game (override) ============
CREATE OR REPLACE FUNCTION public.find_or_create_game(_max_players integer, _stake numeric)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_target UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  PERFORM public.ludo_cleanup_empty_rooms();
  SELECT g.id INTO v_target
    FROM public.ludo_games g
    WHERE g.status='open' AND g.is_private=false AND g.max_players=_max_players AND g.stake=_stake
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) > 0
      AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players
      AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id AND p.user_id=v_uid)
    ORDER BY (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) DESC, g.created_at ASC
    LIMIT 1;
  IF v_target IS NOT NULL THEN
    PERFORM public.join_game(v_target);
    RETURN v_target;
  END IF;
  RETURN public.create_game(_max_players, _stake);
END $function$;

-- ============ join_game_by_code: clearer error ============
CREATE OR REPLACE FUNCTION public.join_game_by_code(_code text)
 RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_id UUID;
BEGIN
  SELECT id INTO v_id FROM public.ludo_games WHERE room_code = upper(_code) AND status='open';
  IF v_id IS NULL THEN RAISE EXCEPTION 'Code de partie invalide'; END IF;
  PERFORM public.join_game(v_id);
  RETURN v_id;
END $function$;

-- ============ list_public_open_games ============
CREATE OR REPLACE FUNCTION public.list_public_open_games()
 RETURNS TABLE(id uuid, max_players int, stake numeric, pot numeric, room_code text, players_count int, created_at timestamptz)
 LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT g.id, g.max_players, g.stake, g.pot, g.room_code,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id), g.created_at
  FROM public.ludo_games g
  WHERE g.status='open' AND g.is_private=false
    AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) > 0
    AND (SELECT count(*) FROM public.ludo_participants p WHERE p.game_id=g.id) < g.max_players
  ORDER BY g.created_at DESC;
$function$;

-- ============ my_games ============
CREATE OR REPLACE FUNCTION public.my_games()
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT jsonb_build_object(
    'ongoing', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id',g.id,'status',g.status,'max_players',g.max_players,'stake',g.stake,'pot',g.pot,
        'room_code',g.room_code,'is_private',g.is_private,'created_at',g.created_at,
        'players_count',(SELECT count(*) FROM public.ludo_participants pp WHERE pp.game_id=g.id))
      ORDER BY g.created_at DESC)
      FROM public.ludo_games g
      JOIN public.ludo_participants p ON p.game_id=g.id
      WHERE p.user_id=v_uid AND g.status IN ('open','playing') AND p.forfeited=false),'[]'::jsonb),
    'finished', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'id',g.id,'status',g.status,'max_players',g.max_players,'stake',g.stake,'pot',g.pot,
        'finished_at',g.finished_at,
        'won', g.winner_id=v_uid,
        'winner_name', (SELECT display_name FROM public.ludo_participants wp WHERE wp.game_id=g.id AND wp.user_id=g.winner_id LIMIT 1),
        'forfeited', p.forfeited)
      ORDER BY g.finished_at DESC NULLS LAST)
      FROM public.ludo_games g
      JOIN public.ludo_participants p ON p.game_id=g.id
      WHERE p.user_id=v_uid AND g.status='finished' LIMIT 50),'[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END $function$;

-- ============ ludo_set_ready ============
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players) WHERE id=_game_id;
  END IF;
END $function$;

-- ============ ludo_heartbeat ============
CREATE OR REPLACE FUNCTION public.ludo_heartbeat(_game_id uuid)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_slot int;
BEGIN
  IF v_uid IS NULL THEN RETURN; END IF;
  UPDATE public.ludo_participants SET last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid
    RETURNING slot INTO v_slot;
  IF v_slot IS NOT NULL THEN
    UPDATE public.ludo_games SET disconnect_until = disconnect_until - v_slot::text
      WHERE id=_game_id AND disconnect_until ? v_slot::text;
  END IF;
END $function$;

-- ============ ludo_move: remove block-by-wall ============
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  other_slot INT; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le dé d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  pawn := st->'pawns'->v_slot::text->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  pawn_state := pawn->>'s'; pawn_step := (pawn->>'k')::INT;
  IF pawn_state = 'finished' THEN RAISE EXCEPTION 'Pion déjà arrivé'; END IF;
  IF pawn_state = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track'; new_step := 0;
  ELSE
    new_step := pawn_step + v_dice;
    IF new_step > 56 THEN RAISE EXCEPTION 'Dépassement'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE;
    ELSE new_state := 'track'; END IF;
  END IF;

  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text],
    jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);

  -- CAPTURE only when single opponent pawn on a non-safe cell
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_idx(v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR other_slot IN 0..v_max-1 LOOP
        IF other_slot <> v_slot THEN
          op_start := public._ludo_start_idx(other_slot);
          other_pawns := st->'pawns'->other_slot::text;
          same_slot_count := 0;
          FOR j IN 0..3 LOOP
            op := other_pawns->j;
            IF op->>'s' = 'track' THEN
              op_step := (op->>'k')::INT;
              IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                same_slot_count := same_slot_count + 1;
              END IF;
            END IF;
          END LOOP;
          IF same_slot_count = 1 THEN
            FOR j IN 0..3 LOOP
              op := other_pawns->j;
              IF op->>'s' = 'track' THEN
                op_step := (op->>'k')::INT;
                IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                  other_pawns := jsonb_set(other_pawns, ARRAY[j::text],
                    jsonb_build_object('s','yard','k',-1));
                  captured := TRUE;
                END IF;
              END IF;
            END LOOP;
            st := jsonb_set(st, ARRAY['pawns', other_slot::text], other_pawns);
          END IF;
        END IF;
      END LOOP;
    END IF;
  END IF;

  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;

  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;

  IF all_done THEN
    SELECT user_id INTO winner_uid FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
    PERFORM public.finish_game(_game_id, winner_uid);
    RETURN st;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  IF bonus THEN
    st := jsonb_set(st,'{last_event}', to_jsonb(
      (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue')::text));
  ELSE
    st := jsonb_set(st,'{turn_slot}',
      to_jsonb(public._ludo_next_slot(_game_id, v_slot, v_max)));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $function$;

-- ============ ludo_roll: triple-6 cancel ============
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT; has_move BOOLEAN := FALSE;
  v_consec INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias, consecutive_sixes INTO v_user, v_isbot, v_bias, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;
  v_dice := 1 + (floor(random()*6))::INT;
  IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;

  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec,0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants SET consecutive_sixes=v_consec WHERE game_id=_game_id AND slot=v_slot;

  -- Triple-6 cancel
  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('triple_six:cancel'::text));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));

  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;

  IF NOT has_move THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice||':no_move'));
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  ELSE
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  END IF;
  RETURN st;
END $function$;

-- ============ ludo_check_timeout: 5-min pause after 5 misses ============
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_started TIMESTAMPTZ;
  v_uid UUID; v_isbot BOOLEAN; v_missed INT; v_winner UUID;
  v_pause_until TIMESTAMPTZ; v_pause_text TEXT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;

  -- If this slot is in a 5-min pause window, auto-pass with no 30s wait
  v_pause_text := g.disconnect_until->>v_slot::text;
  IF v_pause_text IS NOT NULL THEN
    v_pause_until := v_pause_text::TIMESTAMPTZ;
    IF now() < v_pause_until THEN
      v_missed := COALESCE(v_missed,0) + 1;
      UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;
      IF v_missed >= 10 AND NOT v_isbot THEN
        UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
        v_winner := public._ludo_check_last_standing(_game_id);
        IF v_winner IS NOT NULL THEN
          PERFORM public.finish_game(_game_id, v_winner);
          RETURN (SELECT state FROM public.ludo_games WHERE id=_game_id);
        END IF;
      END IF;
      st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
      st := jsonb_set(st,'{dice}','null'::jsonb);
      st := jsonb_set(st,'{must_move}','false'::jsonb);
      st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
      st := jsonb_set(st,'{last_event}', to_jsonb('paused_skip'::text));
      UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
      RETURN st;
    ELSE
      -- pause expired
      UPDATE public.ludo_games SET disconnect_until = disconnect_until - v_slot::text WHERE id=_game_id;
    END IF;
  END IF;

  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;

  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;

  -- After 5 misses (and player is offline > 30s based on last_seen), enable 5-min pause
  IF v_missed = 5 AND NOT v_isbot THEN
    UPDATE public.ludo_games
      SET disconnect_until = disconnect_until || jsonb_build_object(v_slot::text, to_char(now() + interval '5 minutes','YYYY-MM-DD"T"HH24:MI:SS+00'))
      WHERE id=_game_id;
  END IF;

  IF v_missed >= 10 AND NOT v_isbot THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Forfait (10 timeouts)');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
      RETURN (SELECT state FROM public.ludo_games WHERE id=_game_id);
    END IF;
  END IF;
  st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st,'{dice}','null'::jsonb);
  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'::text));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $function$;

-- ============ admin_add_bot: remove auto-start ============
CREATE OR REPLACE FUNCTION public.admin_add_bot(_game_id uuid, _bot_name text, _intelligence integer DEFAULT 70, _win_bias integer DEFAULT 0)
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE v_game public.ludo_games%ROWTYPE; v_count INT; v_slot INT; v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count; v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,is_bot,bot_name,display_name,bot_intelligence,bot_win_bias,ready)
    VALUES (_game_id,NULL,v_slot,v_color,TRUE,_bot_name,_bot_name,GREATEST(0,LEAST(100,_intelligence)),GREATEST(0,LEAST(100,_win_bias)),TRUE);
END $function$;
