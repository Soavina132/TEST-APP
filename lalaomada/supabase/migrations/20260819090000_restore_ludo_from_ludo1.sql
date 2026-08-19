-- ============================================================
-- RESTORE LUDO FUNCTIONS TO MATCH Ludo1 MIGRATIONS
-- This migration restores all Ludo-related PostgreSQL functions
-- from the Ludo1 snapshot to ensure behavioral consistency.
-- ============================================================

-- ── _log_ludo_house_on_finish ──
CREATE OR REPLACE FUNCTION public._log_ludo_house_on_finish()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_pot numeric := COALESCE(NEW.pot, 0);
  v_pct numeric := COALESCE(NEW.commission_pct, 10);
  v_winner uuid := NULLIF(NEW.winner_id, ''::text);
  v_commission numeric;
  v_is_bot boolean := false;
BEGIN
  -- Only when transitioning to 'finished'
  IF NEW.status IS DISTINCT FROM 'finished' THEN RETURN NEW; END IF;
  IF OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF v_pot IS NULL OR v_pot <= 0 THEN RETURN NEW; END IF;

  IF v_winner IS NULL THEN
    -- No winner: bot won or game force-ended → platform keeps the pot
    INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
    VALUES ('ludo', NEW.id, 'house_win', v_pot, v_pot, v_pct, NULL,
            'Gain maison — victoire bot ou partie sans gagnant');
    RETURN NEW;
  END IF;

  -- Check if winner is a bot (bots have is_bot=true in ludo_participants, not profiles)
  SELECT COALESCE(is_bot, false) INTO v_is_bot 
  FROM public.ludo_participants 
  WHERE game_id = NEW.id AND user_id = v_winner LIMIT 1;

  IF v_is_bot THEN
    -- Bot won (shouldn't normally happen, but safety net)
    INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
    VALUES ('ludo', NEW.id, 'house_win', v_pot, v_pot, v_pct, v_winner,
            'Gain maison — victoire bot');
  ELSE
    -- Human won: log commission
    v_commission := round(v_pot * v_pct / 100.0, 2);
    IF v_commission > 0 THEN
      INSERT INTO public.house_ledger(game_type, game_id, entry_type, amount, pot, commission_pct, winner_id, note)
      VALUES ('ludo', NEW.id, 'commission', v_commission, v_pot, v_pct, v_winner,
              'Commission ' || v_pct || '% sur pot Ludo');
    END IF;
  END IF;

  RETURN NEW;
END $function$;

-- ── _ludo_active_humans ──
CREATE OR REPLACE FUNCTION public._ludo_active_humans(_game_id UUID) RETURNS INT
LANGUAGE sql STABLE AS $$
  SELECT count(*)::INT FROM public.ludo_participants
  WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE
$$;

-- ── _ludo_advance_turn ──
CREATE OR REPLACE FUNCTION public._ludo_advance_turn(_game_id uuid, _new_slot integer, _last_event text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_isbot boolean;
  v_spin_ms int; v_seq int; v_now text; v_shields jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id;
  st := g.state;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  SELECT is_bot INTO v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=_new_slot;
  v_spin_ms := CASE WHEN COALESCE(v_isbot, FALSE) THEN 2500 ELSE 0 END;
  v_seq := COALESCE((st->>'turn_seq')::int, 0) + 1;
  st := jsonb_set(st, '{turn_slot}', to_jsonb(_new_slot));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{turn_seq}', to_jsonb(v_seq));
  st := jsonb_set(st, '{phase}', to_jsonb('spinning'::text));
  st := jsonb_set(st, '{phase_started_at}', to_jsonb(v_now));
  st := jsonb_set(st, '{spin_ms}', to_jsonb(v_spin_ms));
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{last_event}', to_jsonb(_last_event));
  -- Mode Moderne: clear shields for new player (expires at owner next turn)
  IF st ? 'shields' THEN
    v_shields := st->'shields';
    IF v_shields ? _new_slot::text THEN
      v_shields := v_shields - _new_slot::text;
      st := jsonb_set(st, '{shields}', v_shields, true);
    END IF;
  END IF;
  -- FIX 5: Decrement power tile cooldowns on every turn advance
  st := public._ludo_decrement_cooldowns(st);
  st := st - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=_new_slot WHERE id=_game_id;
  RETURN st;
END $function$;

-- ── _ludo_auto_move ──
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

-- ── _ludo_auto_move_random ──
CREATE OR REPLACE FUNCTION public._ludo_auto_move_random(_game_id uuid, _slot int)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  v_dice int;
  v_playable jsonb;
  v_count int;
  v_pawn int;
  v_idx int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN false; END IF;
  IF NOT COALESCE(g.auto_move, false) THEN RETURN false; END IF;
  IF NOT COALESCE((g.state->>'must_move')::boolean, false) THEN RETURN false; END IF;
  v_dice := NULLIF(g.state->>'dice', 'null')::int;
  IF v_dice IS NULL THEN RETURN false; END IF;

  v_playable := public._ludo_playable_pawns(g.state->'pawns', _slot, v_dice);
  v_count := jsonb_array_length(COALESCE(v_playable, '[]'::jsonb));
  IF v_count = 0 THEN RETURN false; END IF;

  -- Pick a random playable pawn
  v_idx := floor(random() * v_count)::int;
  v_pawn := (v_playable->v_idx)::int;

  PERFORM set_config('app.ludo_auto', 'on', true);
  PERFORM public.ludo_move(_game_id, v_pawn);
  PERFORM set_config('app.ludo_auto', 'off', true);
  RETURN true;
END
$function$;

-- ── _ludo_check_afk ──
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t1 int; v_t2 int; v_max1 int; v_max2 int;
  v_enabled boolean; v_uid uuid; v_isbot boolean; v_winner uuid;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max
    INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;

  SELECT afk_t1, afk_t2, user_id, is_bot
    INTO v_t1, v_t2, v_uid, v_isbot
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  IF v_t1 >= COALESCE(v_max1, 2) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants
       SET forfeited = TRUE
     WHERE game_id = _game_id AND slot = _slot;
    UPDATE public.ludo_games
       SET afk_warning = NULL, afk_pause_for = NULL, afk_pause_name = NULL
     WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
              'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
  END IF;
END $$;

-- ── _ludo_check_game_over ──
CREATE OR REPLACE FUNCTION public._ludo_check_game_over(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_count INT; v_humans INT; v_winner UUID; g public.ludo_games%ROWTYPE;
  v_is_solo BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN FALSE; END IF;

  SELECT count(*) INTO v_count
    FROM public.ludo_participants WHERE game_id=_game_id AND forfeited=FALSE;
  SELECT count(*) INTO v_humans
    FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=FALSE AND forfeited=FALSE;

  v_is_solo := COALESCE(g.is_solo, FALSE) OR g.match_type = 'solo';

  IF v_is_solo AND v_humans = 0 THEN
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN TRUE;
  END IF;

  IF v_count <= 1 THEN
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL AND v_humans > 0 THEN
      PERFORM public.finish_game(_game_id, v_winner);
    ELSE
      UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END $function$;

-- ── _ludo_check_last_standing ──
CREATE OR REPLACE FUNCTION public._ludo_check_last_standing(_game_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE v_count INT; v_uid UUID; v_host UUID; v_host_forfeited BOOLEAN;
BEGIN
  SELECT count(*) INTO v_count FROM public.ludo_participants
   WHERE game_id=_game_id AND forfeited=FALSE;
  IF v_count <= 1 THEN
    -- Try non-bot survivor first
    SELECT user_id INTO v_uid FROM public.ludo_participants
     WHERE game_id=_game_id AND forfeited=FALSE AND is_bot=FALSE LIMIT 1;
    IF v_uid IS NOT NULL THEN RETURN v_uid; END IF;

    -- If only bots remain, check if host is still active (not forfeited)
    SELECT host_id INTO v_host FROM public.ludo_games WHERE id = _game_id;
    IF v_host IS NOT NULL THEN
      SELECT forfeited INTO v_host_forfeited FROM public.ludo_participants
       WHERE game_id=_game_id AND user_id=v_host AND is_bot=FALSE LIMIT 1;
      -- Only return host if they haven't forfeited
      IF COALESCE(v_host_forfeited, TRUE) = FALSE THEN
        RETURN v_host;
      END IF;
    END IF;

    -- Host forfeited or not found → no winner
    RETURN NULL;
  END IF;
  RETURN NULL;
END $function$;

-- ── _ludo_check_power_tile ──
CREATE OR REPLACE FUNCTION public._ludo_check_power_tile(st jsonb, _slot integer, _pawn_idx integer, _new_k integer, _start_idx integer)
RETURNS jsonb
LANGUAGE plpgsql
AS $function$
DECLARE
  tiles jsonb;
  i INT;
  tile_type TEXT;
  tile_cell INT;
  landing_cell INT;
  new_st jsonb := st;
  power_event jsonb;
  reward_type TEXT;
  arr jsonb;
  pawn jsonb;
  new_k INT;
  boost_amount INT;
  free_pawn_idx INT := -1;
  j INT;
  current_k INT := _new_k;
  loop_count INT := 0;
  found_tile BOOLEAN;
BEGIN
  -- Only check if on main track (k <= 50)
  IF _new_k > 50 THEN RETURN st; END IF;

  LOOP
    loop_count := loop_count + 1;
    IF loop_count > 10 THEN EXIT; END IF; -- safety limit

    IF current_k > 50 THEN EXIT; END IF;

    tiles := new_st->'power_tiles';
    IF tiles IS NULL OR jsonb_array_length(tiles) = 0 THEN EXIT; END IF;

    -- Calculate the absolute cell the pawn is on now
    landing_cell := (_start_idx + current_k - 1) % 52;

    found_tile := FALSE;

    -- Find if there's a power tile on this cell
    FOR i IN 0..jsonb_array_length(tiles) - 1 LOOP
      tile_type := tiles->i->>'type';
      tile_cell := (tiles->i->>'cell')::INT;
      IF tile_cell = landing_cell THEN
        found_tile := TRUE;

        -- For lucky_star, pick a random reward
        IF tile_type = 'lucky_star' THEN
          reward_type := (ARRAY['boost','shield','double_roll','free_pawn'])[1 + floor(random() * 4)::INT];
        ELSE
          reward_type := tile_type;
        END IF;

        -- Apply the effect
        IF reward_type = 'boost' THEN
          -- Random boost: 1-6
          boost_amount := 1 + floor(random() * 6)::INT;
          arr := new_st->'pawns'->_slot::text;
          pawn := arr->_pawn_idx;
          new_k := current_k + boost_amount;
          IF new_k > 56 THEN new_k := 56; END IF;
          IF new_k = 56 THEN
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s','finished','k',new_k));
          ELSE
            arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s','track','k',new_k));
          END IF;
          new_st := jsonb_set(new_st, '{pawns}', jsonb_set(new_st->'pawns', ARRAY[_slot::text], arr));
          -- Update current_k so the loop checks if we landed on ANOTHER tile
          current_k := new_k;

        ELSIF reward_type = 'shield' THEN
          IF new_st->'shields' IS NULL THEN
            new_st := jsonb_set(new_st, '{shields}', jsonb_build_object(_slot::text, true));
          ELSE
            new_st := jsonb_set(new_st, ARRAY['shields', _slot::text], 'true'::jsonb);
          END IF;

        ELSIF reward_type = 'double_roll' THEN
          new_st := jsonb_set(new_st, '{double_roll_pending}', to_jsonb(_slot));

        ELSIF reward_type = 'free_pawn' THEN
          -- Find first pawn in yard and release it to track at k=1
          -- If no pawn is in yard, this bonus is simply not used (the only allowed exception)
          arr := new_st->'pawns'->_slot::text;
          FOR j IN 0..3 LOOP
            IF (arr->j->>'s') = 'yard' THEN
              free_pawn_idx := j;
              EXIT;
            END IF;
          END LOOP;
          IF free_pawn_idx >= 0 THEN
            arr := jsonb_set(arr, ARRAY[free_pawn_idx::text], jsonb_build_object('s','track','k',1));
            new_st := jsonb_set(new_st, '{pawns}', jsonb_set(new_st->'pawns', ARRAY[_slot::text], arr));
          END IF;
        END IF;

        -- Build power_event with ALL fields the frontend expects
        IF tile_type = 'lucky_star' THEN
          power_event := jsonb_build_object(
            'type', 'lucky_star',
            'reward', reward_type,
            'slot', _slot,
            'pawn', _pawn_idx,
            'free_pawn_idx', CASE WHEN reward_type = 'free_pawn' THEN free_pawn_idx ELSE NULL END,
            'cell', landing_cell,
            'dice', CASE WHEN reward_type = 'boost' THEN boost_amount ELSE NULL END,
            'at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          );
        ELSE
          power_event := jsonb_build_object(
            'type', tile_type,
            'slot', _slot,
            'pawn', _pawn_idx,
            'free_pawn_idx', CASE WHEN tile_type = 'free_pawn' THEN free_pawn_idx ELSE NULL END,
            'cell', landing_cell,
            'dice', CASE WHEN tile_type = 'boost' THEN boost_amount ELSE NULL END,
            'at', to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
          );
        END IF;
        new_st := jsonb_set(new_st, '{power_event}', power_event);

        -- Relocate the consumed power tile to a new cell
        new_st := public._ludo_relocate_power_tile(new_st, landing_cell);

        EXIT; -- exit FOR loop, continue outer LOOP to check new position
      END IF;
    END LOOP;

    -- If no tile was found at current position, stop
    IF NOT found_tile THEN EXIT; END IF;

    -- If pawn finished (reached home), stop
    IF current_k >= 56 THEN EXIT; END IF;

    -- Reset free_pawn_idx for next iteration
    free_pawn_idx := -1;
  END LOOP;

  RETURN new_st;
END;
$function$;

-- ── _ludo_check_stalemate ──
CREATE OR REPLACE FUNCTION public._ludo_check_stalemate(_game_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  st jsonb;
  v_streak INT;
  v_max_players INT;
  v_best_slot INT := 0;
  v_best_progress INT := 0;
  v_progress INT;
  v_i INT;
  v_j INT;
  v_pawns jsonb;
  v_pawn jsonb;
  v_uid UUID;
BEGIN
  SELECT state INTO st FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF st IS NULL THEN RETURN FALSE; END IF;

  v_streak := COALESCE((st->>'no_move_streak')::int, 0);
  v_max_players := COALESCE((st->>'max_players')::int, 4);

  IF v_streak >= 10 * v_max_players THEN
    FOR v_i IN 0..3 LOOP
      IF v_i >= v_max_players THEN EXIT; END IF;
      v_pawns := st->'pawns'->v_i::text;
      IF v_pawns IS NULL THEN CONTINUE; END IF;
      v_progress := 0;
      FOR v_j IN 0..3 LOOP
        v_pawn := v_pawns->v_j;
        IF v_pawn IS NULL THEN CONTINUE; END IF;
        IF v_pawn->>'s' = 'finished' THEN
          v_progress := v_progress + 56;
        ELSIF v_pawn->>'s' = 'track' THEN
          v_progress := v_progress + COALESCE((v_pawn->>'k')::int, 0);
        END IF;
      END LOOP;
      IF v_progress > v_best_progress THEN
        v_best_progress := v_progress;
        v_best_slot := v_i;
      END IF;
    END LOOP;

    SELECT user_id INTO v_uid FROM public.ludo_participants
      WHERE game_id = _game_id AND slot = v_best_slot AND is_bot = FALSE AND forfeited = FALSE
      LIMIT 1;

    IF v_uid IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_uid);
    ELSE
      UPDATE public.ludo_games SET status = 'finished', finished_at = now() WHERE id = _game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN TRUE;
  END IF;
  RETURN FALSE;
END;
$function$;

-- ── _ludo_clear_shield ──
CREATE OR REPLACE FUNCTION public._ludo_clear_shield(st jsonb, _slot integer)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT CASE
    WHEN st ? 'shields' AND (st->'shields') ? _slot::text
    THEN jsonb_set(st, '{shields}', (st->'shields') - _slot::text, true)
    ELSE st
  END
$function$;

-- ── _ludo_count_on_cell ──
CREATE OR REPLACE FUNCTION public._ludo_count_on_cell(st jsonb, _slot integer, _path_idx integer)
RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT count(*)::int
  FROM jsonb_array_elements(st->'pawns'->_slot::text) AS p
  WHERE p.value->>'s' = 'track'
    AND (public._ludo_start_idx(_slot) + (p.value->>'k')::int - 1) % 52 = _path_idx
$function$;

-- ── _ludo_decrement_cooldowns ──
CREATE OR REPLACE FUNCTION public._ludo_decrement_cooldowns(st jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT st;
$function$;

-- ── _ludo_ensure_state ──
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players, COALESCE(g.mode,'classic'));
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END $$;

-- ── _ludo_finish_team ──
CREATE OR REPLACE FUNCTION public._ludo_finish_team(_game_id uuid, _winner_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_payout numeric;
  v_half numeric;
  v_mate uuid;
  v_referrer uuid;
  v_ref_pct numeric;
  v_ref_amount numeric;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.status = 'finished' THEN RETURN; END IF;

  v_payout := v_game.pot * (100 - v_game.commission_pct) / 100.0;
  v_half := v_payout / 2.0;

  SELECT user_id INTO v_mate FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team AND user_id <> _winner_id
    AND NOT is_bot AND forfeited=FALSE LIMIT 1;

  UPDATE public.ludo_games SET status='finished', winner_id=_winner_id, finished_at=now()
    WHERE id=_game_id;

  IF v_mate IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||')');
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_half WHERE id=v_mate;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_mate,'win',v_half,_game_id,'Gain Ludo groupe (équipe '||_team||', coéquipier)');

    -- BUG 5 FIX: Referral bonus for the winner (consistant avec finish_game)
    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_half * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  ELSE
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) + v_payout WHERE id=_winner_id;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (_winner_id,'win',v_payout,_game_id,'Gain Ludo groupe (équipe '||_team||', solo)');
    SELECT referred_by INTO v_referrer FROM public.profiles WHERE id=_winner_id;
    IF v_referrer IS NOT NULL THEN
      SELECT referral_pct INTO v_ref_pct FROM public.app_settings WHERE id=1;
      v_ref_amount := v_payout * COALESCE(v_ref_pct,0) / 100.0;
      IF v_ref_amount > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + v_ref_amount WHERE id=v_referrer;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (v_referrer,'referral',v_ref_amount,_game_id,'Bonus parrainage');
      END IF;
    END IF;
  END IF;
END $function$;

-- ── _ludo_init_state ──
CREATE OR REPLACE FUNCTION public._ludo_init_state(_max_players integer)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  st jsonb;
  i INT;
  v_pawns jsonb;
BEGIN
  st := jsonb_build_object(
    'turn_slot', 0,
    'dice', 'null'::jsonb,
    'must_move', false,
    'turn_started_at', to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
    'last_event', 'init',
    'no_move_streak', 0,
    'max_players', _max_players,
    'pawns', '{}'::jsonb
  );
  FOR i IN 0..(_max_players - 1) LOOP
    v_pawns := '[]'::jsonb;
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    st := jsonb_set(st, ARRAY['pawns', i::text], v_pawns);
  END LOOP;
  RETURN st;
END;
$function$;

-- ── _ludo_is_blocked ──
CREATE OR REPLACE FUNCTION public._ludo_is_blocked(st jsonb, _moving_slot integer, _path_idx integer, _max_players integer DEFAULT 4)
RETURNS boolean
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  v_slot INT;
  v_count INT;
BEGIN
  FOR v_slot IN 0..3 LOOP
    IF v_slot = _moving_slot THEN CONTINUE; END IF;
    IF v_slot >= _max_players THEN CONTINUE; END IF;
    IF st->'pawns' ? v_slot::text THEN
      v_count := public._ludo_count_on_cell(st, v_slot, _path_idx);
      IF v_count >= 2 THEN
        RETURN TRUE;
      END IF;
    END IF;
  END LOOP;
  RETURN FALSE;
END;
$function$;

-- ── _ludo_is_safe ──
CREATE OR REPLACE FUNCTION public._ludo_is_safe(_idx integer)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $function$
  SELECT _idx IN (0, 8, 13, 21, 26, 34, 39, 47)
$function$;

-- ── _ludo_log_state_change ──
CREATE OR REPLACE FUNCTION public._ludo_log_state_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old_event TEXT;
  v_new_event TEXT;
  v_acting_slot INT;
  v_dice INT;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.status = 'playing' THEN
    v_old_event := COALESCE(OLD.state->>'last_event', '');
    v_new_event := COALESCE(NEW.state->>'last_event', '');
    
    IF v_new_event = v_old_event OR v_new_event = 'init' OR v_new_event IS NULL THEN
      RETURN NEW;
    END IF;
    
    -- Use OLD turn_slot (the slot that performed the action)
    v_acting_slot := COALESCE((OLD.state->>'turn_slot')::int, 0);
    v_dice := NULLIF(NEW.state->>'dice', '')::int;
    -- For roll events, extract dice from the event string "roll:N"
    IF v_new_event LIKE 'roll:%' THEN
      v_dice := NULLIF(split_part(v_new_event, ':', 2), '')::int;
      -- Handle "roll:N:no_move" format
      v_dice := NULLIF(split_part(v_dice::text, ':', 1), '')::int;
    END IF;
    
    INSERT INTO public.ludo_move_history(game_id, slot, action, dice, from_state, to_state)
    VALUES (
      NEW.id,
      v_acting_slot,
      v_new_event,
      v_dice,
      OLD.state,
      NEW.state
    );
  END IF;
  
  RETURN NEW;
END;
$function$;

-- ── _ludo_maybe_auto_start ──
CREATE OR REPLACE FUNCTION public._ludo_maybe_auto_start(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_game public.ludo_games%ROWTYPE;
  v_count int;
BEGIN
  SELECT * INTO v_game FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RETURN; END IF;

  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = _game_id;

  IF v_count >= v_game.max_players THEN
    UPDATE public.ludo_games
      SET status = 'playing',
          started_at = now(),
          state = public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic')),
          current_turn = 0
      WHERE id = _game_id;
  END IF;
END $$;

-- ── _ludo_movable_pawns ──
CREATE OR REPLACE FUNCTION public._ludo_movable_pawns(st jsonb, _slot integer, _dice integer)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
AS $function$
DECLARE
  arr jsonb; pawn jsonb; i INT; pstate TEXT; pstep INT;
  result jsonb := '[]'::jsonb;
  v_new_k INT;
  v_path_idx INT;
  v_max_players INT;
BEGIN
  IF _dice IS NULL OR _dice < 1 OR _dice > 6 THEN RETURN '[]'::jsonb; END IF;
  IF _slot IS NULL THEN RETURN '[]'::jsonb; END IF;
  arr := st->'pawns'->_slot::text;
  IF arr IS NULL OR arr = 'null'::jsonb THEN RETURN '[]'::jsonb; END IF;
  v_max_players := COALESCE((st->>'max_players')::int, 4);

  FOR i IN 0..3 LOOP
    pawn := arr->i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN
        v_path_idx := public._ludo_start_idx(_slot);
        IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
          result := result || to_jsonb(i);
        END IF;
      END IF;
    ELSIF pstate = 'track' THEN
      v_new_k := pstep + _dice;
      IF v_new_k <= 56 THEN
        IF v_new_k <= 50 THEN
          v_path_idx := (public._ludo_start_idx(_slot) + v_new_k - 1) % 52;
          IF NOT public._ludo_is_blocked(st, _slot, v_path_idx, v_max_players) THEN
            result := result || to_jsonb(i);
          END IF;
        ELSE
          result := result || to_jsonb(i);
        END IF;
      END IF;
    END IF;
  END LOOP;
  RETURN result;
END;
$function$;

-- ── _ludo_next_slot ──
CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id uuid, _from integer, _max integer)
RETURNS integer
LANGUAGE plpgsql
STABLE
SET search_path = public
AS $function$
DECLARE
  i INT;
  s INT;
  v_forfeited BOOLEAN;
  v_finish_rank INT;
BEGIN
  FOR i IN 1.._max LOOP
    s := (_from + i) % _max;
    SELECT forfeited, finish_rank INTO v_forfeited, v_finish_rank
      FROM public.ludo_participants
      WHERE game_id = _game_id AND slot = s;
    IF COALESCE(v_forfeited, FALSE) THEN CONTINUE; END IF;
    IF v_finish_rank IS NOT NULL THEN CONTINUE; END IF;
    RETURN s;
  END LOOP;
  RETURN _from;
END $function$;

-- ── _ludo_place_power_tiles ──
CREATE OR REPLACE FUNCTION public._ludo_place_power_tiles()
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_shuffled int[];
  v_types text[] := ARRAY['boost','boost','lucky_star','lucky_star','shield','double_roll'];
  v_tiles jsonb := '[]'::jsonb;
  v_cell int;
  i int;
  v_j int;
  v_tmp int;
BEGIN
  v_shuffled := v_valid;
  FOR i IN REVERSE array_length(v_shuffled,1)..2 LOOP
    v_j := 1 + floor(random()*i)::int;
    v_tmp := v_shuffled[i]; v_shuffled[i] := v_shuffled[v_j]; v_shuffled[v_j] := v_tmp;
  END LOOP;
  FOR i IN 1..6 LOOP
    IF i > array_length(v_shuffled,1) THEN EXIT; END IF;
    v_cell := v_shuffled[i];
    v_tiles := v_tiles || jsonb_build_object('type', v_types[i], 'cell', v_cell, 'cd', 0);
  END LOOP;
  RETURN v_tiles;
END $function$;

-- ── _ludo_playable_pawns ──
CREATE OR REPLACE FUNCTION public._ludo_playable_pawns(_pawns jsonb, _slot integer, _dice integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 IMMUTABLE
 SET search_path TO 'public'
AS $function$
DECLARE
  arr jsonb; pawn jsonb; i int; pstate text; pstep int;
  out jsonb := '[]'::jsonb;
BEGIN
  IF _dice IS NULL OR _slot IS NULL OR _pawns IS NULL THEN RETURN out; END IF;
  arr := _pawns -> _slot::text;
  IF arr IS NULL THEN RETURN out; END IF;
  FOR i IN 0..3 LOOP
    pawn := arr -> i;
    IF pawn IS NULL THEN CONTINUE; END IF;
    pstate := pawn->>'s';
    pstep  := COALESCE((pawn->>'k')::int, 0);
    IF pstate = 'finished' THEN CONTINUE; END IF;
    IF pstate = 'yard' THEN
      IF _dice = 6 THEN out := out || to_jsonb(i); END IF;
    ELSE
      IF pstep + _dice <= 56 THEN out := out || to_jsonb(i); END IF;
    END IF;
  END LOOP;
  RETURN out;
END $function$;

-- ── _ludo_power_valid_cells ──
CREATE OR REPLACE FUNCTION public._ludo_power_valid_cells()
RETURNS int[]
LANGUAGE sql IMMUTABLE
AS $$
  SELECT ARRAY(
    SELECT i FROM generate_series(0,51) i
    WHERE i NOT IN (0, 8, 13, 21, 26, 34, 39, 47)
  )
$$;

-- ── _ludo_purge ──
CREATE OR REPLACE FUNCTION public._ludo_purge(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  DELETE FROM public.chat_rooms WHERE game_id = _game_id;
  DELETE FROM public.game_spectators WHERE game_id = _game_id;
  DELETE FROM public.game_invitations WHERE game_id = _game_id;
  DELETE FROM public.ludo_participants WHERE game_id = _game_id;
  DELETE FROM public.ludo_games WHERE id = _game_id;
END $$;

-- ── _ludo_relocate_tile ──
CREATE OR REPLACE FUNCTION public._ludo_relocate_tile(_power_tiles jsonb, _type text, _game_id uuid DEFAULT NULL::uuid, _state jsonb DEFAULT NULL::jsonb, _old_cell integer DEFAULT NULL::integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_valid int[] := public._ludo_power_valid_cells();
  v_occupied int[] := ARRAY[]::int[];
  v_tile jsonb;
  v_available int[];
  v_new_cell int;
  v_result jsonb := '[]'::jsonb;
  v_relocated boolean := false;
  v_pawns jsonb;
  v_start int;
  v_step int;
  v_slot int;
  v_count int;
  v_pawn jsonb;
BEGIN
  IF _old_cell IS NULL THEN
    FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
      IF v_tile->>'type' = _type AND NOT v_relocated THEN
        _old_cell := (v_tile->>'cell')::int;
        v_relocated := true;
      END IF;
    END LOOP;
  END IF;

  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF (v_tile->>'cell')::int <> _old_cell THEN
      v_occupied := v_occupied || (v_tile->>'cell')::int;
    END IF;
  END LOOP;

  IF _game_id IS NOT NULL AND _state IS NOT NULL THEN
    FOR v_slot IN 0..3 LOOP
      v_pawns := _state->'pawns'->v_slot::text;
      IF v_pawns IS NULL THEN CONTINUE; END IF;
      v_start := public._ludo_start_for(_game_id, v_slot);
      FOR v_count IN 0..3 LOOP
        v_pawn := v_pawns->v_count;
        IF v_pawn IS NOT NULL AND v_pawn->>'s' = 'track' THEN
          v_step := (v_pawn->>'k')::int;
          IF v_step <= 50 THEN
            v_occupied := v_occupied || ((v_start + v_step) % 52);
          END IF;
        END IF;
      END LOOP;
    END LOOP;
  END IF;

  v_available := ARRAY(
    SELECT c FROM unnest(v_valid) c WHERE NOT (c = ANY(v_occupied))
  );

  IF array_length(v_available, 1) IS NULL OR array_length(v_available, 1) = 0 THEN
    FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
      v_result := v_result || v_tile;
    END LOOP;
    RETURN v_result;
  END IF;

  v_new_cell := v_available[1 + floor(random() * array_length(v_available, 1))::int];

  FOR v_tile IN SELECT value FROM jsonb_array_elements(_power_tiles) LOOP
    IF (v_tile->>'cell')::int = _old_cell THEN
      v_result := v_result || jsonb_build_object('type', v_tile->>'type', 'cell', v_new_cell);
    ELSE
      v_result := v_result || v_tile;
    END IF;
  END LOOP;

  RETURN v_result;
END $function$;

-- ── _ludo_set_ready_deadline ──
CREATE OR REPLACE FUNCTION public._ludo_set_ready_deadline()
RETURNS trigger LANGUAGE plpgsql SET search_path=public AS $$
DECLARE v_sec int;
BEGIN
  SELECT COALESCE(ready_timeout_seconds,60) INTO v_sec FROM public.app_settings WHERE id=1;
  NEW.ready_deadline := now() + (v_sec || ' seconds')::interval;
  RETURN NEW;
END $$;

-- ── _ludo_start_for ──
CREATE OR REPLACE FUNCTION public._ludo_start_for(_game_id uuid, _slot int)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE color
    WHEN 'red'    THEN 0
    WHEN 'green'  THEN 13
    WHEN 'yellow' THEN 26
    WHEN 'blue'   THEN 39
    ELSE 0
  END
  FROM public.ludo_participants
  WHERE game_id=_game_id AND slot=_slot;
$$;

-- ── _ludo_start_idx ──
CREATE OR REPLACE FUNCTION public._ludo_start_idx(_slot INT) RETURNS INT
LANGUAGE sql IMMUTABLE AS $$ SELECT (ARRAY[0,13,26,39])[_slot+1] $$;

-- ── _ludo_sync_turn_snapshot ──
CREATE OR REPLACE FUNCTION public._ludo_sync_turn_snapshot()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
DECLARE
  st jsonb; v_slot int; v_dice int; v_must boolean; v_playable jsonb;
BEGIN
  st := NEW.state;
  IF st IS NULL OR jsonb_typeof(st) <> 'object' THEN RETURN NEW; END IF;
  v_slot := NULLIF(st->>'turn_slot','')::int;
  v_dice := NULLIF(st->>'dice','null')::int;
  v_must := COALESCE((st->>'must_move')::boolean, false);
  IF v_must AND v_dice IS NOT NULL AND v_slot IS NOT NULL THEN
    v_playable := public._ludo_playable_pawns(st->'pawns', v_slot, v_dice);
  ELSE
    v_playable := '[]'::jsonb;
  END IF;
  st := jsonb_set(st, '{playable_pawns}', v_playable, true);
  IF v_slot IS NOT NULL THEN
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_slot), true);
    NEW.current_turn := v_slot;
  END IF;
  st := jsonb_set(st, '{dice}', COALESCE(to_jsonb(v_dice), 'null'::jsonb), true);
  NEW.state := st;
  RETURN NEW;
END $function$;

-- ── _maybe_end_bot_only_ludo ──
CREATE OR REPLACE FUNCTION public._maybe_end_bot_only_ludo(_game_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  UPDATE public.ludo_games g SET status='finished', finished_at=now()
  WHERE g.id=_game_id AND g.status='playing' AND COALESCE(g.is_solo,false)=false
    AND NOT EXISTS (
      SELECT 1 FROM public.ludo_participants p
      WHERE p.game_id=g.id AND p.is_bot=false
        AND COALESCE(p.forfeited,false)=false
        AND p.finish_rank IS NULL
    );
END $$;

-- ── _trg_afk_warning_non_ludo ──
CREATE OR REPLACE FUNCTION public._trg_afk_warning_non_ludo()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_max INT; v_slug TEXT; v_key TEXT; v_count INT; v_name TEXT;
BEGIN
  IF NEW.status <> 'playing' OR COALESCE(NEW.paused, FALSE) THEN RETURN NEW; END IF;
  IF NEW.turn_skips IS NOT DISTINCT FROM OLD.turn_skips THEN RETURN NEW; END IF;
  v_slug := CASE TG_TABLE_NAME WHEN 'chess_games' THEN 'chess' WHEN 'fanorona_games' THEN 'fanorona'
    WHEN 'domino_games' THEN 'domino' WHEN 'rami_games' THEN 'rami' WHEN 'poker_games' THEN 'poker' ELSE NULL END;
  IF v_slug IS NULL THEN RETURN NEW; END IF;
  SELECT max_turn_skips INTO v_max FROM public.game_configs WHERE slug = v_slug;
  IF v_max IS NULL OR v_max <= 1 THEN RETURN NEW; END IF;
  FOR v_key, v_count IN SELECT key, value::int FROM jsonb_each_text(NEW.turn_skips) LOOP
    IF v_count = v_max - 1 THEN
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_key::uuid;
      NEW.afk_warning := jsonb_build_object('uid', v_key, 'name', COALESCE(v_name, 'Joueur'),
        'skips', v_count, 'max', v_max, 'votes', '[]'::jsonb, 'votes_needed', 0,
        'ts', extract(epoch from now())::bigint);
      RETURN NEW;
    END IF;
  END LOOP;
  RETURN NEW;
END $$;

-- ── _trg_ludo_participant_end_check ──
CREATE OR REPLACE FUNCTION public._trg_ludo_participant_end_check()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NEW.is_bot=false AND (
        COALESCE(NEW.forfeited,false) IS DISTINCT FROM COALESCE(OLD.forfeited,false)
     OR NEW.finish_rank IS DISTINCT FROM OLD.finish_rank
  ) THEN
    PERFORM public._maybe_end_bot_only_ludo(NEW.game_id);
  END IF;
  RETURN NEW;
END $$;

-- ── _trg_ludo_tournament_finished ──
CREATE OR REPLACE FUNCTION public._trg_ludo_tournament_finished()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_match    record;
  v_rankings jsonb;
  v_rank     int;
  rec        record;
  v_n        int;
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.winner_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches
    WHERE id = NEW.tournament_match_id
      AND status NOT IN ('finished','forfeit','cancelled');
  IF NOT FOUND THEN RETURN NEW; END IF;

  v_n := COALESCE(array_length(v_match.player_ids, 1), 2);

  IF v_n <= 2 THEN
    -- Cas classique 1v1
    UPDATE public.tournament_matches
      SET status      = 'finished',
          winner_id   = NEW.winner_id,
          finished_at = now()
      WHERE id = NEW.tournament_match_id;
  ELSE
    -- Cas 4 joueurs : 1er = winner_id, puis classés par finish_position ASC
    -- Les joueurs sans finish_position (non éliminés) sont classés en dernier par slot
    v_rankings := jsonb_build_object('1', NEW.winner_id::text);
    v_rank := 2;

    FOR rec IN
      SELECT lp.user_id
      FROM public.ludo_participants lp
      WHERE lp.game_id  = NEW.id
        AND lp.user_id IS NOT NULL
        AND lp.user_id <> NEW.winner_id
        AND lp.is_bot   = false
      ORDER BY
        CASE WHEN lp.finish_position IS NOT NULL
             THEN lp.finish_position ELSE 9999 END ASC,
        lp.forfeited ASC,   -- forfeités en dernier
        lp.slot ASC
    LOOP
      v_rankings := v_rankings
                 || jsonb_build_object(v_rank::text, rec.user_id::text);
      v_rank := v_rank + 1;
    END LOOP;

    UPDATE public.tournament_matches
      SET status         = 'finished',
          winner_id      = NEW.winner_id,
          match_rankings = v_rankings,
          finished_at    = now()
      WHERE id = NEW.tournament_match_id;
  END IF;

  RETURN NEW;
END;
$$;

-- ── ludo_bot_play ──
CREATE OR REPLACE FUNCTION public.ludo_bot_play(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE g public.ludo_games%ROWTYPE; st jsonb; v_slot INT; v_isbot BOOLEAN;
  v_intel INT; v_dice INT; arr jsonb; pawn jsonb;
  i INT; k INT; best INT := -1; best_score INT := -1; sc INT;
  pstate TEXT; pstep INT; abs_cell INT; start_idx INT;
  other_slot INT; op jsonb; op_step INT; op_start INT; would_capture BOOLEAN;
  candidates INT[] := ARRAY[]::INT[];
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;
  SELECT is_bot, bot_intelligence INTO v_isbot, v_intel
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot THEN RETURN st; END IF;

  IF NOT (st->>'must_move')::BOOLEAN THEN
    -- Dé équitable, aucune triche
    v_dice := 1 + (floor(random()*6))::INT;
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

  -- L'intelligence du bot ne concerne QUE le choix du pion, JAMAIS le dé
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
END $function$;

-- ── ludo_check_timeout ──
CREATE OR REPLACE FUNCTION public.ludo_check_timeout(_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_started TIMESTAMPTZ;
  v_uid UUID;
  v_isbot BOOLEAN;
  v_missed INT;
  v_winner UUID;
  v_turn_seconds INT;
  v_max_skips INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN g.state; END IF;
  st := g.state;

  SELECT turn_seconds INTO v_turn_seconds FROM public.app_settings WHERE id = 1;
  v_turn_seconds := COALESCE(v_turn_seconds, 30);

  SELECT COALESCE(
    (SELECT gc.max_turn_skips FROM public.game_configs gc WHERE gc.slug = 'ludo'),
    3
  ) INTO v_max_skips;

  v_started := (st->>'turn_started_at')::TIMESTAMPTZ;
  IF now() - v_started < (v_turn_seconds || ' seconds')::interval THEN RETURN st; END IF;

  v_slot := (st->>'turn_slot')::INT;

  -- Bug 16: filter forfeited players
  SELECT user_id, is_bot, missed_turns INTO v_uid, v_isbot, v_missed
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot AND NOT forfeited;

  -- If current player forfeited or not found, advance turn
  IF NOT FOUND THEN
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := public._ludo_clear_shield(st, (st->>'turn_slot')::INT);
    st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('skip_forfeit'::text));
    st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
    UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
    RETURN st;
  END IF;

  -- Bug 17: skip bots — they're auto-played by ludo_tick_all, not timed out
  IF v_isbot THEN
    RETURN st;
  END IF;

  v_missed := COALESCE(v_missed,0) + 1;
  UPDATE public.ludo_participants SET missed_turns=v_missed WHERE game_id=_game_id AND slot=v_slot;

  UPDATE public.ludo_participants SET consecutive_sixes=0
    WHERE game_id=_game_id AND slot=v_slot;

  st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));

  IF v_missed >= v_max_skips THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND slot=v_slot;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'forfeit',0,_game_id,CONCAT('Forfait (', v_max_skips, ' timeouts)'));
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    ELSE
      UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
      PERFORM public._ludo_purge(_game_id);
    END IF;
    RETURN st;
  END IF;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;
  st := jsonb_set(st, '{must_move}', 'false'::jsonb);
  st := jsonb_set(st, '{dice}', 'null'::jsonb);
  st := public._ludo_clear_shield(st, public._ludo_next_slot(_game_id, v_slot, g.max_players));
  st := jsonb_set(st, '{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
  st := jsonb_set(st, '{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('timeout'::text));
  st := st - 'no_move_display' - 'movable_pawns' - 'power_event';
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END $function$;

-- ── ludo_choose_power ──
CREATE OR REPLACE FUNCTION public.ludo_choose_power(_game_id uuid, _choice text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE st jsonb;
BEGIN
  SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
  RETURN st;
END $function$;

-- ── ludo_cleanup_empty_rooms ──
CREATE OR REPLACE FUNCTION public.ludo_cleanup_empty_rooms()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_count int;
BEGIN
  WITH d AS (
    DELETE FROM public.ludo_games g
    WHERE g.status='open' AND NOT EXISTS (SELECT 1 FROM public.ludo_participants p WHERE p.game_id=g.id)
    RETURNING 1
  ) SELECT count(*) INTO v_count FROM d;
  RETURN v_count;
END $function$;

-- ── ludo_create ──
CREATE OR REPLACE FUNCTION public.ludo_create(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE _uid uuid := auth.uid(); _id uuid; _bal numeric; _name text;
BEGIN
  IF _uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'players 2-4'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT COALESCE(balance_ar, balance, 0), COALESCE(pseudo, display_name, 'Joueur') INTO _bal, _name
    FROM public.profiles WHERE id = _uid;
  IF _bal IS NULL OR _bal < _stake THEN RAISE EXCEPTION 'solde insuffisant'; END IF;
  INSERT INTO public.ludo_games (max_players, stake, created_by, pot, mode, match_type)
    VALUES (_max_players, _stake, _uid, _stake, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'))
    RETURNING id INTO _id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = COALESCE(balance_ar, balance) - _stake WHERE id = _uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (_uid, 'ludo_stake', -_stake, _id, 'Create ludo');
  END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, display_name, is_bot)
    VALUES (_id, _uid, 0, _name, false);
  RETURN _id;
END $function$;

-- ── ludo_heartbeat ──
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

-- ── ludo_join ──
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

-- ── ludo_join_team ──
CREATE OR REPLACE FUNCTION public.ludo_join_team(_game_id uuid, _team int)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_game public.ludo_games%ROWTYPE;
  v_count int;
  v_existing_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _team NOT IN (1, 2) THEN RAISE EXCEPTION 'Équipe invalide (1 ou 2)'; END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_game.status NOT IN ('open', 'waiting') THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF v_game.match_type <> 'groupe' THEN RAISE EXCEPTION 'Cette partie n''est pas en mode groupe'; END IF;

  -- Check player is a participant
  SELECT team INTO v_existing_team FROM public.ludo_participants
    WHERE game_id=_game_id AND user_id=v_uid;
  IF v_existing_team IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- Check team isn't full (max 2 per team)
  SELECT count(*) INTO v_count FROM public.ludo_participants
    WHERE game_id=_game_id AND team=_team;
  IF v_count >= 2 AND v_existing_team <> _team THEN
    RAISE EXCEPTION 'Groupe % complet', _team;
  END IF;

  -- Update team
  UPDATE public.ludo_participants SET team=_team
    WHERE game_id=_game_id AND user_id=v_uid;
END $function$;

-- ── ludo_move ──
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
 RETURNS jsonb
 LANGUAGE plpgsql
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_user UUID;
  v_isbot BOOLEAN;
  arr jsonb;
  pawn jsonb;
  new_k INT;
  new_state TEXT;
  v_dice INT;
  v_new_slot INT;
  v_consec INT;
  captured BOOLEAN := FALSE;
  v_arr_idx INT;
  v_target_slot INT;
  v_target_pawn jsonb;
  v_step INT;
  v_moving_path_idx INT;
  v_target_path_idx INT;
  v_movable jsonb;
  v_target_count INT;
  v_max_players INT;
  v_start_idx INT;
  v_has_power_tiles BOOLEAN;
  v_power_type TEXT;
  v_got_double_roll BOOLEAN := FALSE;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  v_max_players := g.max_players;
  SELECT user_id, is_bot, consecutive_sixes INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  IF v_dice IS NULL THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  IF NOT (v_movable @> to_jsonb(_pawn_idx)) THEN
    RAISE EXCEPTION 'Pion non jouable';
  END IF;
  
  -- Clear previous power_event
  st := st - 'power_event';
  
  arr := st->'pawns'->v_slot::text;
  pawn := arr->_pawn_idx;
  IF pawn IS NULL THEN RAISE EXCEPTION 'Pion inconnu'; END IF;
  IF pawn->>'s' = 'finished' THEN RAISE EXCEPTION 'Pion deja arrive'; END IF;
  IF pawn->>'s' = 'yard' THEN
    IF v_dice <> 6 THEN RAISE EXCEPTION 'Sortie possible avec un 6'; END IF;
    new_state := 'track';
    new_k := 1;
  ELSE
    new_k := (pawn->>'k')::INT + v_dice;
    IF new_k > 56 THEN RAISE EXCEPTION 'Depassement'; END IF;
    IF new_k = 56 THEN
      new_state := 'finished';
    ELSE
      new_state := 'track';
    END IF;
  END IF;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_k));
  st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_slot::text], arr));

  -- Capture check
  IF new_state = 'track' AND new_k <= 50 THEN
    v_moving_path_idx := (public._ludo_start_idx(v_slot) + new_k - 1) % 52;
    IF NOT public._ludo_is_safe(v_moving_path_idx) THEN
      FOR v_target_slot IN 0..3 LOOP
        IF v_target_slot = v_slot THEN CONTINUE; END IF;
        IF v_target_slot >= v_max_players THEN CONTINUE; END IF;
        IF st->'shields' ? v_target_slot::text AND (st->'shields'->>v_target_slot::text)::BOOLEAN THEN
          CONTINUE;
        END IF;
        arr := st->'pawns'->v_target_slot::text;
        IF arr IS NULL THEN CONTINUE; END IF;
        FOR v_arr_idx IN 0..3 LOOP
          v_target_pawn := arr->v_arr_idx;
          IF v_target_pawn IS NULL THEN CONTINUE; END IF;
          IF v_target_pawn->>'s' = 'track' THEN
            v_step := (v_target_pawn->>'k')::INT;
            IF v_step <= 50 THEN
              v_target_path_idx := (public._ludo_start_idx(v_target_slot) + v_step - 1) % 52;
              IF v_moving_path_idx = v_target_path_idx THEN
                v_target_count := public._ludo_count_on_cell(st, v_target_slot, v_target_path_idx);
                IF v_target_count >= 2 THEN CONTINUE; END IF;
                arr := jsonb_set(arr, ARRAY[v_arr_idx::text], jsonb_build_object('s', 'yard', 'k', 0));
                st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_target_slot::text], arr));
                captured := TRUE;
              END IF;
            END IF;
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END IF;

  -- Power tile check (Mode Moderne)
  v_start_idx := public._ludo_start_idx(v_slot);
  v_has_power_tiles := (st ? 'power_tiles') AND jsonb_array_length(st->'power_tiles') > 0;
  
  IF v_has_power_tiles AND new_state = 'track' AND new_k <= 50 THEN
    st := public._ludo_check_power_tile(st, v_slot, _pawn_idx, new_k, v_start_idx);
    
    -- Check if boost moved the pawn
    IF st ? 'power_event' THEN
      -- Always re-read pawn position (boost chains may end with non-boost tile)
      arr := st->'pawns'->v_slot::text;
      pawn := arr->_pawn_idx;
      new_k := (pawn->>'k')::INT;
      new_state := pawn->>'s';
        
        -- Re-check capture at boosted position
        IF new_state = 'track' AND new_k <= 50 THEN
          v_moving_path_idx := (v_start_idx + new_k - 1) % 52;
          IF NOT public._ludo_is_safe(v_moving_path_idx) THEN
            FOR v_target_slot IN 0..3 LOOP
              IF v_target_slot = v_slot THEN CONTINUE; END IF;
              IF v_target_slot >= v_max_players THEN CONTINUE; END IF;
              IF st->'shields' ? v_target_slot::text AND (st->'shields'->>v_target_slot::text)::BOOLEAN THEN CONTINUE; END IF;
              arr := st->'pawns'->v_target_slot::text;
              IF arr IS NULL THEN CONTINUE; END IF;
              FOR v_arr_idx IN 0..3 LOOP
                v_target_pawn := arr->v_arr_idx;
                IF v_target_pawn IS NULL THEN CONTINUE; END IF;
                IF v_target_pawn->>'s' = 'track' THEN
                  v_step := (v_target_pawn->>'k')::INT;
                  IF v_step <= 50 THEN
                    v_target_path_idx := (public._ludo_start_idx(v_target_slot) + v_step - 1) % 52;
                    IF v_moving_path_idx = v_target_path_idx THEN
                      v_target_count := public._ludo_count_on_cell(st, v_target_slot, v_target_path_idx);
                      IF v_target_count >= 2 THEN CONTINUE; END IF;
                      arr := jsonb_set(arr, ARRAY[v_arr_idx::text], jsonb_build_object('s', 'yard', 'k', 0));
                      st := jsonb_set(st, '{pawns}', jsonb_set(st->'pawns', ARRAY[v_target_slot::text], arr));
                      captured := TRUE;
                    END IF;
                  END IF;
                END IF;
              END LOOP;
            END LOOP;
          END IF;
      END IF;
      
      -- Check if double_roll was granted
      IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::INT = v_slot THEN
        v_got_double_roll := TRUE;
      END IF;
    END IF;
  END IF;

  st := jsonb_set(st, '{no_move_streak}', '0'::jsonb);
  st := st - 'movable_pawns';
  
  -- Turn continuation
  IF v_dice = 6 OR captured OR new_state = 'finished' OR v_got_double_roll THEN
    -- Consume double_roll_pending
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::INT = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb(CASE
      WHEN captured AND new_state = 'finished' THEN 'capture:home'
      WHEN captured THEN 'capture'
      WHEN new_state = 'finished' THEN 'home'
      WHEN v_got_double_roll AND st ? 'power_event' AND (st->'power_event'->>'type') = 'lucky_star' THEN 'lucky_star:rejoue'
      WHEN v_got_double_roll THEN 'double_roll:rejoue'
      ELSE 'six'
    END));
  ELSE
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{dice}','null'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('move'::text));
  END IF;
  
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ── ludo_pass ──
CREATE OR REPLACE FUNCTION public.ludo_pass(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  g public.ludo_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_dice INT;
  v_uid UUID := auth.uid();
  v_user UUID;
  v_isbot BOOLEAN;
  arr jsonb;
  pawn jsonb;
  i INT;
  pstate TEXT;
  pstep INT;
  has_move BOOLEAN := FALSE;
  v_new_slot INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT user_id, is_bot INTO v_user, v_isbot
    FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
  IF NOT v_isbot AND v_user <> v_uid THEN RAISE EXCEPTION 'Pas votre tour'; END IF;
  IF NOT (st->>'must_move')::BOOLEAN THEN RAISE EXCEPTION 'Lancez le de d''abord'; END IF;
  v_dice := (st->>'dice')::INT;
  arr := st->'pawns'->v_slot::text;
  FOR i IN 0..3 LOOP
    pawn := arr->i;
    pstate := pawn->>'s';
    pstep := COALESCE((pawn->>'k')::INT, -1);
    IF pstate='finished' THEN CONTINUE; END IF;
    IF pstate='yard' THEN
      IF v_dice = 6 THEN has_move := TRUE; EXIT; END IF;
    ELSIF pstate='track' THEN
      IF pstep + v_dice <= 56 THEN has_move := TRUE; EXIT; END IF;
    END IF;
  END LOOP;
  IF has_move THEN RAISE EXCEPTION 'Vous avez un coup possible'; END IF;

  UPDATE public.ludo_participants SET consecutive_sixes = 0
    WHERE game_id = _game_id AND slot = v_slot;

  IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
    st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
  END IF;

  st := jsonb_set(st,'{must_move}','false'::jsonb);
  st := jsonb_set(st,'{dice}','null'::jsonb);
  v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
  st := public._ludo_clear_shield(st, v_new_slot);
  st := jsonb_set(st,'{turn_slot}', to_jsonb(v_new_slot));
  st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st,'{last_event}', to_jsonb('pass'::text));
  st := st - 'no_move_display' - 'power_event' - 'movable_pawns';
  st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;
  PERFORM public._ludo_check_game_over(_game_id);
  RETURN st;
END;
$function$;

-- ── ludo_purge_unready_rooms ──
CREATE OR REPLACE FUNCTION public.ludo_purge_unready_rooms()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  g RECORD;
  p RECORD;
  v_count int := 0;
BEGIN
  FOR g IN
    SELECT * FROM public.ludo_games
    WHERE status='open'
      AND ready_deadline IS NOT NULL
      AND now() > ready_deadline
  LOOP
    -- rembourse uniquement les humains (pas les bots), montant = mise du jeu
    FOR p IN
      SELECT user_id
      FROM public.ludo_participants
      WHERE game_id = g.id
        AND user_id IS NOT NULL
        AND COALESCE(is_bot,false) = false
    LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles
          SET balance_ar = balance_ar + g.stake
          WHERE id = p.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (p.user_id, 'refund', g.stake, g.id, 'Salle Ludo expirée (non prêts)');
      END IF;
    END LOOP;
    PERFORM public._ludo_purge(g.id);
    v_count := v_count + 1;
  END LOOP;
  RETURN v_count;
END $function$;

-- ── ludo_quick_start ──
CREATE OR REPLACE FUNCTION public.ludo_quick_start(_max_players integer DEFAULT 2, _stake numeric DEFAULT 0, _mode text DEFAULT 'classic'::text, _match_type text DEFAULT 'solo'::text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid; v_game_id uuid; v_code text; v_name text; v_balance numeric; v_paused boolean; v_banned boolean;
  v_commission numeric; v_slot int; v_colors text[]; v_color text; v_team int;
  v_bot_names text[] := ARRAY['Bot Rija','Bot Naina','Bot Hery','Bot Voara'];
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  IF _max_players NOT BETWEEN 2 AND 4 THEN RAISE EXCEPTION 'Joueurs invalides (2-4)'; END IF;
  PERFORM public._validate_stake(_stake);
  SELECT paused INTO v_paused FROM public.app_settings WHERE id = 1;
  IF COALESCE(v_paused, false) THEN RAISE EXCEPTION 'Application en pause'; END IF;
  SELECT banned, COALESCE(pseudo, 'Joueur'), balance_ar INTO v_banned, v_name, v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF COALESCE(v_banned, false) THEN RAISE EXCEPTION 'Compte banni'; END IF;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;
  v_colors := CASE _max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id = 1;
  v_code := public._gen_room_code();
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, match_type)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission, 10), v_code, TRUE, COALESCE(_mode, 'classic'), COALESCE(_match_type, 'solo'))
  RETURNING id INTO v_game_id;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_uid, 'stake', -_stake, v_game_id, 'Mise creation partie solo bot');
  END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, is_bot)
    VALUES (v_game_id, v_uid, 0, v_colors[1], v_name, TRUE, FALSE);
  FOR v_slot IN 1.._max_players - 1 LOOP
    v_color := v_colors[v_slot + 1];
    IF _match_type = 'groupe' THEN v_team := CASE WHEN v_slot % 2 = 0 THEN 1 ELSE 2 END; ELSE v_team := NULL; END IF;
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready, team)
    VALUES (v_game_id, NULL, v_slot, v_color, TRUE, v_bot_names[v_slot], v_bot_names[v_slot], 70, 0, TRUE, v_team);
  END LOOP;
  UPDATE public.ludo_games SET status = 'playing'::game_status, started_at = now(), state = public._ludo_init_state(_max_players), current_turn = 0 WHERE id = v_game_id;
  RETURN v_game_id;
END $function$;

-- ── ludo_quit ──
CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); g public.ludo_games%ROWTYPE; st jsonb;
  v_slot INT; v_winner UUID; v_remaining INT;
  v_pawns jsonb; i INT;
  v_is_host boolean; v_part record;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;
  SELECT slot INTO v_slot FROM public.ludo_participants WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  IF g.status = 'open' THEN
    v_is_host := (g.host_id = v_uid);

    IF v_is_host THEN
      -- Host quits: refund ALL participants and cancel game
      FOR v_part IN SELECT user_id FROM public.ludo_participants WHERE game_id=_game_id AND is_bot=false LOOP
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_part.user_id;
        INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
          VALUES (v_part.user_id, 'refund', g.stake, _game_id, 'Annulation salle d''attente (hôte)');
      END LOOP;
      UPDATE public.ludo_games SET status = 'cancelled', finished_at = now(), pot = 0 WHERE id = _game_id;
      PERFORM public._ludo_purge(_game_id);
    ELSE
      -- Non-host quits: refund only this player, keep room open
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
      UPDATE public.ludo_games SET pot = pot - g.stake WHERE id = _game_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
        VALUES (v_uid, 'refund', g.stake, _game_id, 'Quitter salle d''attente');
      DELETE FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;
    END IF;
    RETURN;
  END IF;

  -- Playing status: same as before
  st := g.state;
  IF st ? 'pawns' AND (st->'pawns') ? v_slot::text THEN
    v_pawns := '[]'::jsonb;
    FOR i IN 1..4 LOOP
      v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    END LOOP;
    st := jsonb_set(st, ARRAY['pawns', v_slot::text], v_pawns);
  END IF;

  IF g.is_solo OR g.match_type = 'solo' THEN
    UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
    UPDATE public.ludo_games SET status='finished', finished_at=now(), state=st WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
    RETURN;
  END IF;

  UPDATE public.ludo_participants SET forfeited=TRUE WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF (st->>'turn_slot')::INT = v_slot THEN
    st := jsonb_set(st,'{turn_slot}', to_jsonb(public._ludo_next_slot(_game_id, v_slot, g.max_players)));
    st := jsonb_set(st,'{dice}','null'::jsonb);
    st := jsonb_set(st,'{must_move}','false'::jsonb);
    st := jsonb_set(st,'{turn_started_at}', to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st,'{last_event}', to_jsonb('forfeit'));
  END IF;
  UPDATE public.ludo_games SET state=st, current_turn=(st->>'turn_slot')::INT WHERE id=_game_id;

  IF public._ludo_active_humans(_game_id) > 0 THEN
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN
      PERFORM public.finish_game(_game_id, v_winner);
    END IF;
  ELSE
    UPDATE public.ludo_games SET status='finished', finished_at=now() WHERE id=_game_id;
    PERFORM public._ludo_purge(_game_id);
  END IF;
END $function$;

-- ── ludo_rematch ──
CREATE OR REPLACE FUNCTION public.ludo_rematch(_old_game_id uuid)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_old public.ludo_games%ROWTYPE; v_new_id uuid; v_part public.ludo_participants%ROWTYPE;
  v_count INT; v_slot INT; v_colors TEXT[]; v_color TEXT; v_room_code TEXT; v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  SELECT * INTO v_old FROM public.ludo_games WHERE id = _old_game_id;
  IF v_old.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF v_old.status <> 'finished' THEN RAISE EXCEPTION 'La partie doit etre terminee'; END IF;
  v_room_code := CASE WHEN v_old.is_private THEN substr(md5(random()::text), 1, 6) ELSE NULL END;
  INSERT INTO public.ludo_games(max_players, stake, mode, is_private, room_code, commission_pct, status, pot, created_by)
  VALUES (v_old.max_players, v_old.stake, v_old.mode, v_old.is_private, v_room_code, v_old.commission_pct, 'open', 0, v_uid)
  RETURNING id INTO v_new_id;
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND NOT is_bot ORDER BY slot LOOP
    IF v_old.stake > 0 AND NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_part.user_id AND balance_ar >= v_old.stake) THEN CONTINUE; END IF;
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    v_slot := v_count;
    v_colors := CASE v_old.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
    v_color := v_colors[v_slot + 1];
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready)
    VALUES (v_new_id, v_part.user_id, v_slot, v_color, v_part.display_name, false);
    IF v_old.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar - v_old.stake WHERE id = v_part.user_id;
      UPDATE public.ludo_games SET pot = pot + v_old.stake WHERE id = v_new_id;
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note) VALUES (v_part.user_id, 'stake', -v_old.stake, v_new_id, 'Mise revanche');
    END IF;
  END LOOP;
  FOR v_part IN SELECT * FROM public.ludo_participants WHERE game_id = _old_game_id AND NOT forfeited AND is_bot ORDER BY slot LOOP
    SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
    IF v_count >= v_old.max_players THEN EXIT; END IF;
    v_slot := v_count;
    v_colors := CASE v_old.max_players WHEN 2 THEN ARRAY['red','yellow'] WHEN 3 THEN ARRAY['red','green','yellow'] ELSE ARRAY['red','green','yellow','blue'] END;
    v_color := v_colors[v_slot + 1];
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready)
    VALUES (v_new_id, NULL, v_slot, v_color, TRUE, v_part.bot_name, v_part.bot_name, v_part.bot_intelligence, 0, TRUE);
  END LOOP;
  SELECT count(*) INTO v_count FROM public.ludo_participants WHERE game_id = v_new_id;
  IF v_count >= v_old.max_players THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(), state = public._ludo_init_state(v_old.max_players) WHERE id = v_new_id;
  END IF;
  RETURN v_new_id;
END $function$;

-- ── ludo_roll ──
CREATE OR REPLACE FUNCTION public.ludo_roll(_game_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  st jsonb;
  g public.ludo_games%ROWTYPE;
  v_uid UUID := auth.uid();
  v_slot INT;
  v_user UUID;
  v_isbot BOOLEAN;
  v_dice INT;
  v_consec INT;
  v_override INT;
  v_new_slot INT;
  v_movable jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := public._ludo_ensure_state(_game_id);
  v_slot := (st->>'turn_slot')::INT;

  IF NOT (st ? 'max_players') THEN
    st := jsonb_set(st, '{max_players}', to_jsonb(g.max_players));
  END IF;

  SELECT user_id, is_bot, consecutive_sixes
    INTO v_user, v_isbot, v_consec
    FROM public.ludo_participants
    WHERE game_id = _game_id AND slot = v_slot;

  IF NOT v_isbot AND v_user <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;
  IF (st->>'must_move')::BOOLEAN THEN
    RAISE EXCEPTION 'Deja lance, deplacez un pion';
  END IF;

  v_override := NULLIF(g.dice_override->>v_slot::text, '')::int;
  IF v_override IS NOT NULL AND v_override BETWEEN 1 AND 6 THEN
    v_dice := v_override;
    UPDATE public.ludo_games SET dice_override = dice_override - v_slot::text WHERE id = _game_id;
  ELSE
    v_dice := 1 + (floor(random() * 6))::INT;
  END IF;

  IF v_dice = 6 THEN
    v_consec := COALESCE(v_consec, 0) + 1;
  ELSE
    v_consec := 0;
  END IF;
  UPDATE public.ludo_participants
    SET consecutive_sixes = v_consec
    WHERE game_id = _game_id AND slot = v_slot;

  IF v_consec >= 3 THEN
    UPDATE public.ludo_participants SET consecutive_sixes = 0
      WHERE game_id = _game_id AND slot = v_slot;
    st := jsonb_set(st, '{must_move}', 'false'::jsonb);
    v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
    st := public._ludo_clear_shield(st, v_new_slot);
    st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
    st := jsonb_set(st, '{dice}', 'null'::jsonb);
    IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
      st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
    END IF;
    st := jsonb_set(st, '{turn_started_at}',
      to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    st := jsonb_set(st, '{last_event}', to_jsonb('triple_six:cancel'::text));
    st := st - 'no_move_display' - 'movable_pawns';
    st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
    UPDATE public.ludo_games
      SET state = st, current_turn = (st->>'turn_slot')::INT
      WHERE id = _game_id;
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN st;
  END IF;

  st := jsonb_set(st, '{dice}', to_jsonb(v_dice));
  st := jsonb_set(st, '{must_move}', 'true'::jsonb);
  st := jsonb_set(st, '{turn_started_at}',
    to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
  st := jsonb_set(st, '{last_event}', to_jsonb('roll:' || v_dice));
  st := st - 'no_move_display';

  v_movable := public._ludo_movable_pawns(st, v_slot, v_dice);
  st := jsonb_set(st, '{movable_pawns}', v_movable);

  IF jsonb_array_length(v_movable) = 0 THEN
    IF v_isbot THEN
      IF st ? 'double_roll_pending' AND (st->>'double_roll_pending')::int = v_slot THEN
        st := jsonb_set(st, '{double_roll_pending}', 'null'::jsonb);
      END IF;
      UPDATE public.ludo_participants SET consecutive_sixes = 0
        WHERE game_id = _game_id AND slot = v_slot;
      st := jsonb_set(st, '{must_move}', 'false'::jsonb);
      v_new_slot := public._ludo_next_slot(_game_id, v_slot, g.max_players);
      st := public._ludo_clear_shield(st, v_new_slot);
      st := jsonb_set(st, '{turn_slot}', to_jsonb(v_new_slot));
      st := jsonb_set(st, '{turn_started_at}',
        to_jsonb(to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
      st := jsonb_set(st, '{last_event}',
        to_jsonb('roll:' || v_dice || ':no_move'));
      st := jsonb_set(st, '{dice}', 'null'::jsonb);
      st := st - 'movable_pawns';
      st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
      UPDATE public.ludo_games
        SET state = st, current_turn = (st->>'turn_slot')::INT
        WHERE id = _game_id;
      PERFORM public._ludo_check_game_over(_game_id);
      RETURN st;
    ELSE
      st := jsonb_set(st, '{no_move_streak}', to_jsonb(COALESCE((st->>'no_move_streak')::int, 0) + 1));
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
      RETURN st;
    END IF;
  ELSE
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    RETURN st;
  END IF;
END;
$function$;

-- ── ludo_set_auto_move ──
CREATE OR REPLACE FUNCTION public.ludo_set_auto_move(_game_id uuid, _enabled boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;
  UPDATE ludo_games SET state = state || jsonb_build_object('auto_move_' || v_uid::text, _enabled) WHERE id = _game_id;
END;
$function$;

-- ── ludo_set_display_name ──
CREATE OR REPLACE FUNCTION public.ludo_set_display_name(_game_id uuid, _name text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _name IS NULL OR length(trim(_name)) < 2 THEN RAISE EXCEPTION 'Nom invalide'; END IF;
  UPDATE public.ludo_participants
    SET display_name = trim(_name)
    WHERE game_id=_game_id AND user_id=v_uid;
END $function$;

-- ── ludo_set_finish_position ──
CREATE OR REPLACE FUNCTION public.ludo_set_finish_position(_game_id uuid, _user_id uuid, _position integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentification requise'; END IF;
  -- L'appelant doit être le joueur lui-même ou un admin
  IF v_uid <> _user_id AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Vous ne pouvez enregistrer que votre propre position';
  END IF;
  -- Vérifier que le joueur participe bien à cette partie
  IF NOT EXISTS (
    SELECT 1 FROM public.ludo_participants
    WHERE game_id = _game_id AND user_id = _user_id
  ) THEN
    RAISE EXCEPTION 'Joueur non participant à cette partie';
  END IF;

  UPDATE public.ludo_participants
    SET finish_position = _position
    WHERE game_id = _game_id
      AND user_id = _user_id
      AND finish_position IS NULL;
END $function$;

-- ── ludo_set_ready ──
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public'
AS $$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
  IF _ready AND NOT COALESCE(v_verified,false) THEN
    RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
  END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode,'classic')) WHERE id=_game_id;
  END IF;
END $$;

-- ── ludo_start_solo_bot ──
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2, _difficulty text DEFAULT 'medium',
  _stake numeric DEFAULT 0, _mode text DEFAULT 'classic', _match_type text DEFAULT 'solo'
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $function$
DECLARE
  v_uid uuid := auth.uid(); v_game_id uuid; v_name text; v_intel int;
  v_colors4 text[] := ARRAY['red','green','yellow','blue'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text; i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_mode text; v_total int; v_ready int; v_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifie'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN RAISE EXCEPTION 'max_players doit etre entre 2 et 4'; END IF;
  v_intel := CASE _difficulty WHEN 'easy' THEN 40 WHEN 'hard' THEN 90 ELSE 70 END;
  v_mode := CASE WHEN _mode = 'fast' THEN 'fast' ELSE 'classic' END;
  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, 0, TRUE, v_mode, COALESCE(_match_type, 'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;
  SELECT COALESCE(NULLIF(trim(pseudo), ''), 'Joueur') INTO v_name FROM public.profiles WHERE id = v_uid;
  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1]; END IF;
  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;
  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name, 'Joueur'), TRUE, v_team);
  FOR i IN 1..(_max_players - 1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i + 1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i + 1];
    ELSE v_color := v_colors4[i + 1]; END IF;
    IF _match_type = 'groupe' THEN v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END; ELSE v_team := NULL; END IF;
    INSERT INTO public.ludo_participants(game_id, user_id, slot, color, is_bot, bot_name, display_name, bot_intelligence, bot_win_bias, ready, team)
    VALUES (v_game_id, NULL, i, v_color, TRUE, v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team);
  END LOOP;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot) INTO v_total, v_ready FROM public.ludo_participants WHERE game_id = v_game_id;
  IF v_total = _max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status = 'playing', started_at = now(), state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')), current_turn = 0 WHERE id = v_game_id;
  END IF;
  RETURN v_game_id;
END $function$;

-- ── ludo_tick_all ──
CREATE OR REPLACE FUNCTION public.ludo_tick_all()
RETURNS void
LANGUAGE plpgsql
AS $function$
DECLARE
  g_id UUID;
  v_slot INT;
  v_isbot BOOLEAN;
  st JSONB;
  v_turn_started TIMESTAMPTZ;
  v_elapsed FLOAT;
  v_delay_until TIMESTAMPTZ;
  v_bot_delay FLOAT;
BEGIN
  PERFORM public.cleanup_stale_open_games();

  FOR g_id IN SELECT id FROM public.ludo_games WHERE status='playing' LOOP
    BEGIN
      PERFORM public.ludo_check_timeout(g_id);
      SELECT state INTO st FROM public.ludo_games WHERE id=g_id;
      IF st IS NULL THEN CONTINUE; END IF;
      v_slot := (st->>'turn_slot')::INT;
      SELECT is_bot INTO v_isbot FROM public.ludo_participants
        WHERE game_id=g_id AND slot=v_slot;
      IF v_isbot THEN
        v_turn_started := (st->>'turn_started_at')::timestamptz;
        v_elapsed := EXTRACT(EPOCH FROM (now() - v_turn_started));
        IF NOT (st->>'must_move')::BOOLEAN THEN
          IF v_elapsed >= 3.0 + (random() * 2.0) THEN
            PERFORM public.ludo_bot_play(g_id);
          END IF;
        ELSE
          SELECT bot_delay_until INTO v_delay_until FROM public.ludo_games WHERE id=g_id;
          IF v_delay_until IS NULL OR v_delay_until < v_turn_started THEN
            v_bot_delay := 2.0 + (random() * 2.0);
            UPDATE public.ludo_games SET bot_delay_until = now() + make_interval(secs => v_bot_delay) WHERE id=g_id;
          ELSIF now() >= v_delay_until THEN
            PERFORM public.ludo_bot_move(g_id);
            UPDATE public.ludo_games SET bot_delay_until = NULL WHERE id=g_id;
          END IF;
        END IF;
      END IF;
      PERFORM public._ludo_check_stalemate(g_id);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END LOOP;
END;
$function$;

-- ── ludo_tournament_launch_game ──
CREATE OR REPLACE FUNCTION public.ludo_tournament_launch_game(_mid uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_is_admin  boolean;
  m           record;
  trn         record;
  v_game_id   uuid;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  SELECT * INTO m FROM public.tournament_matches WHERE id = _mid FOR UPDATE;
  IF m IS NULL THEN RAISE EXCEPTION 'Match introuvable'; END IF;
  IF m.is_bye THEN RAISE EXCEPTION 'Match BYE — pas de partie à lancer'; END IF;
  IF m.game_id IS NOT NULL THEN
    -- Vérifier si la partie est encore active
    IF EXISTS (SELECT 1 FROM public.ludo_games WHERE id = m.game_id AND status IN ('open','playing')) THEN
      RETURN jsonb_build_object('ok', true, 'game_id', m.game_id, 'already_exists', true);
    END IF;
  END IF;

  SELECT * INTO trn FROM public.tournaments WHERE id = m.tournament_id;

  -- Créer la partie Ludo : partie privée, mise 0 (le prize pool est géré par le tournoi)
  INSERT INTO public.ludo_games(
    status, max_players, stake, is_private, is_tournament,
    tournament_match_id, pot, commission_pct
  )
  VALUES (
    'open',
    array_length(m.player_ids, 1),
    0,   -- pas de mise individuelle dans un tournoi
    true,
    true,
    _mid,
    0,
    0
  )
  RETURNING id INTO v_game_id;

  -- Inscrire automatiquement les joueurs dans la partie
  DECLARE uid_t uuid; v_slot int := 0;
  BEGIN
    FOREACH uid_t IN ARRAY m.player_ids LOOP
      INSERT INTO public.ludo_participants(game_id, user_id, slot, display_name)
        SELECT v_game_id, uid_t, v_slot,
               COALESCE(p.pseudo, 'Joueur') || CASE WHEN trn.game_slug IS NOT NULL THEN '' ELSE '' END
        FROM public.profiles p WHERE p.id = uid_t
      ON CONFLICT DO NOTHING;
      v_slot := v_slot + 1;
    END LOOP;
  END;

  -- Lier la partie au match
  UPDATE public.tournament_matches
    SET game_id = v_game_id, status = 'running'
    WHERE id = _mid;

  -- Notifier les joueurs
  DECLARE uid_n uuid;
  BEGIN
    FOREACH uid_n IN ARRAY m.player_ids LOOP
      BEGIN
        INSERT INTO public.notifications(user_id, type, title, body, ref_id)
          VALUES (uid_n, 'tournament_game_ready',
                  '🎲 Votre partie Ludo est prête !',
                  'Rejoignez votre match de tournoi maintenant — Round ' || m.round,
                  v_game_id);
      EXCEPTION WHEN OTHERS THEN NULL; END;
    END LOOP;
  END;

  BEGIN
    INSERT INTO public.admin_logs(admin_id, action, target_user_id, new_value)
      VALUES (v_uid, 'ludo_launch_tournament_game', NULL,
              jsonb_build_object('match_id', _mid, 'game_id', v_game_id,
                                 'tournament_id', m.tournament_id, 'round', m.round));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  RETURN jsonb_build_object('ok', true, 'game_id', v_game_id);
END;
$$;

-- ── on_ludo_tournament_game_finished ──
CREATE OR REPLACE FUNCTION public.on_ludo_tournament_game_finished()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_match record;
BEGIN
  -- Seulement si c'est une partie de tournoi qui vient de se terminer
  IF NEW.is_tournament = true
    AND NEW.status = 'finished'
    AND (OLD.status IS DISTINCT FROM 'finished')
    AND NEW.tournament_match_id IS NOT NULL
    AND NEW.winner_id IS NOT NULL
  THEN
    SELECT * INTO v_match
      FROM public.tournament_matches
      WHERE id = NEW.tournament_match_id
        AND status NOT IN ('finished', 'forfeit', 'cancelled')
      FOR UPDATE;

    IF FOUND THEN
      UPDATE public.tournament_matches
        SET status     = 'finished',
            winner_id  = NEW.winner_id,
            finished_at = now()
        WHERE id = NEW.tournament_match_id;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- ── Triggers ──
CREATE OR REPLACE TRIGGER trg_ludo_ready_deadline
BEFORE INSERT ON public.ludo_games
FOR EACH ROW EXECUTE FUNCTION public._ludo_set_ready_deadline();

CREATE OR REPLACE TRIGGER trg_ludo_sync_turn_snapshot
BEFORE INSERT OR UPDATE OF state ON public.ludo_games
FOR EACH ROW EXECUTE FUNCTION public._ludo_sync_turn_snapshot();

CREATE OR REPLACE TRIGGER trg_skip_noop_ludo
BEFORE UPDATE ON public.ludo_games
FOR EACH ROW EXECUTE FUNCTION public._skip_noop_update();
