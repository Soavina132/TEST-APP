
ALTER TABLE public.ludo_participants
  ADD COLUMN IF NOT EXISTS bot_intelligence INT NOT NULL DEFAULT 70,
  ADD COLUMN IF NOT EXISTS bot_win_bias INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS forfeited BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS missed_turns INT NOT NULL DEFAULT 0;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='ludo_games') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_games';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='ludo_participants') THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.ludo_participants';
  END IF;
END $$;

ALTER TABLE public.ludo_games REPLICA IDENTITY FULL;
ALTER TABLE public.ludo_participants REPLICA IDENTITY FULL;

CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players INT)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE p jsonb := '{}'::jsonb; i INT;
BEGIN
  FOR i IN 0.._max_players-1 LOOP
    p := p || jsonb_build_object(i::text,
      jsonb_build_array(
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1),
        jsonb_build_object('s','yard','k',-1)
      ));
  END LOOP;
  RETURN jsonb_build_object(
    'pawns', p, 'turn_slot', 0, 'dice', NULL, 'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
    'last_event', 'start');
END $$;

CREATE OR REPLACE FUNCTION public._ludo_start_idx(_slot INT) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$ SELECT (ARRAY[0,13,26,39])[_slot+1] $$;

CREATE OR REPLACE FUNCTION public._ludo_is_safe(_idx INT) RETURNS BOOLEAN
LANGUAGE sql IMMUTABLE AS $$ SELECT _idx IN (0,13,26,39) $$;

CREATE OR REPLACE FUNCTION public._ludo_active_humans(_game_id UUID) RETURNS INT
LANGUAGE sql STABLE AS $$
  SELECT count(*)::INT FROM public.ludo_participants
  WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE
$$;

CREATE OR REPLACE FUNCTION public._ludo_check_last_standing(_game_id UUID) RETURNS UUID
LANGUAGE plpgsql AS $$
DECLARE v_count INT; v_uid UUID;
BEGIN
  SELECT count(*) INTO v_count FROM public.ludo_participants
   WHERE game_id=_game_id AND forfeited=FALSE;
  IF v_count <= 1 THEN
    SELECT user_id INTO v_uid FROM public.ludo_participants
     WHERE game_id=_game_id AND forfeited=FALSE AND is_bot=FALSE LIMIT 1;
    RETURN v_uid;
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id UUID, _from INT, _max INT) RETURNS INT
LANGUAGE plpgsql STABLE AS $$
DECLARE i INT; s INT; ff BOOLEAN;
BEGIN
  FOR i IN 1.._max LOOP
    s := (_from + i) % _max;
    SELECT forfeited INTO ff FROM public.ludo_participants WHERE game_id=_game_id AND slot=s;
    IF NOT ff THEN RETURN s; END IF;
  END LOOP;
  RETURN _from;
END $$;

CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id UUID) RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players);
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_user UUID; v_isbot BOOLEAN; v_bias INT; v_dice INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, bot_win_bias INTO v_user, v_isbot, v_bias
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Déjà lancé, déplacez un pion'; END IF;
  v_dice := 1 + (floor(random()*6))::INT;
  IF v_isbot AND COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
  st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
  st := jsonb_set(st,'{must_move}','true'::jsonb);
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('roll:'||v_dice));
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  RETURN st;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_move(_game_id UUID, _pawn_idx INT)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  other_slot INT; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb;
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

  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_idx(v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR other_slot IN 0..v_max-1 LOOP
        IF other_slot <> v_slot THEN
          op_start := public._ludo_start_idx(other_slot);
          other_pawns := st->'pawns'->other_slot::text;
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
      CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue'));
  ELSE
    st := jsonb_set(st,'{turn_slot}',
      to_jsonb(public._ludo_next_slot(_game_id, v_slot, v_max)));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'));
  END IF;
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;
  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid;
  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id=_game_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'refund',g.stake,_game_id,'Annulation avant départ');
    DELETE FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid;
    RETURN;
  END IF;
  st := g.state;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  END IF;
  v_winner := public._ludo_check_last_standing(_game_id);
  IF v_winner IS NOT NULL THEN
    PERFORM public.finish_game(_game_id, v_winner);
  ELSIF public._ludo_active_humans(_game_id) = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_started TIMESTAMPTZ;
  v_uid UUID; v_isbot BOOLEAN; v_missed INT; v_winner UUID;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;
  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < interval '30 seconds' THEN RETURN st; END IF;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;
  IF v_missed >= 3 AND NOT v_isbot THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,'Forfait (3 timeouts)');
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
  st := jsonb_set(st,'{last_event}', to_jsonb('timeout'));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  RETURN st;
END $$;

CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id UUID)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_bias INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  other_slot INT; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence, bot_win_bias INTO v_isbot, v_intel, v_bias
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    v_dice := 1 + (floor(random()*6))::INT;
    IF COALESCE(v_bias,0) > 0 AND (random()*100) < v_bias THEN v_dice := 6; END IF;
    st := jsonb_set(st,'{dice}', to_jsonb(v_dice));
    st := jsonb_set(st,'{must_move}','true'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot_roll:'||v_dice));
    UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  ELSE
    v_dice := (st->>'dice')::INT;
  END IF;

  arr := st->'pawns'->v_slot::text;
  start_idx := public._ludo_start_idx(v_slot);
  FOR i IN 0..3 LOOP
    pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN candidates := candidates || i; END IF;
    ELSE
      IF pstep + v_dice <= 56 THEN candidates := candidates || i; END IF;
    END IF;
  END LOOP;

  IF array_length(candidates,1) IS NULL THEN
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('bot:pass'));
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  IF (random()*100) < COALESCE(v_intel,70) THEN
    FOREACH i IN ARRAY candidates LOOP
      pawn := arr->i; pstate := pawn->>'s'; pstep := (pawn->>'k')::INT;
      IF pstate='yard' THEN sc := 60;
      ELSIF pstep + v_dice = 56 THEN sc := 80;
      ELSE
        would_capture := FALSE;
        IF pstep + v_dice <= 50 THEN
          abs_cell := (start_idx + pstep + v_dice) % 52;
          IF NOT public._ludo_is_safe(abs_cell) THEN
            FOR other_slot IN 0..g.max_players-1 LOOP
              IF other_slot <> v_slot THEN
                op_start := public._ludo_start_idx(other_slot);
                FOR k IN 0..3 LOOP
                  op := st->'pawns'->other_slot::text->k;
                  IF op->>'s' = 'track' THEN
                    op_step := (op->>'k')::INT;
                    IF op_step <= 50 AND ((op_start + op_step) % 52) = abs_cell THEN
                      would_capture := TRUE;
                    END IF;
                  END IF;
                END LOOP;
              END IF;
            END LOOP;
          END IF;
        END IF;
        sc := pstep + v_dice + CASE WHEN would_capture THEN 100 ELSE 0 END;
      END IF;
      IF sc > best_score THEN best_score := sc; best := i; END IF;
    END LOOP;
  ELSE
    best := candidates[1 + (floor(random()*array_length(candidates,1)))::INT];
  END IF;

  RETURN public.ludo_move(_game_id, best);
END $$;

CREATE OR REPLACE FUNCTION public.admin_add_bot(_game_id UUID, _bot_name TEXT, _intelligence INT DEFAULT 70, _win_bias INT DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_game public.ludo_games%ROWTYPE; v_count INT; v_slot INT; v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_count >= v_game.max_players THEN RAISE EXCEPTION 'Partie pleine'; END IF;
  v_slot := v_count; v_color := v_colors[v_slot+1];
  INSERT INTO public.ludo_participants(game_id,user_id,slot,color,is_bot,bot_name,display_name,bot_intelligence,bot_win_bias)
    VALUES (_game_id,NULL,v_slot,v_color,TRUE,_bot_name,_bot_name,GREATEST(0,LEAST(100,_intelligence)),GREATEST(0,LEAST(100,_win_bias)));
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players) WHERE id=_game_id;
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.admin_rename_bot(_participant_id UUID, _name TEXT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.ludo_participants SET bot_name=_name, display_name=_name
    WHERE id=_participant_id AND is_bot=TRUE;
END $$;

CREATE OR REPLACE FUNCTION public.admin_update_bot(_participant_id UUID, _intelligence INT, _win_bias INT)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.ludo_participants SET
    bot_intelligence=GREATEST(0,LEAST(100,_intelligence)),
    bot_win_bias=GREATEST(0,LEAST(100,_win_bias))
    WHERE id=_participant_id AND is_bot=TRUE;
END $$;

CREATE OR REPLACE FUNCTION public.join_game(_game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid UUID := auth.uid(); v_balance NUMERIC; v_game public.ludo_games%ROWTYPE;
  v_count INT; v_slot INT; v_color TEXT;
  v_colors TEXT[] := ARRAY['red','green','yellow','blue'];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
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
  IF v_count + 1 = v_game.max_players THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players) WHERE id=_game_id;
  END IF;
END $$;
