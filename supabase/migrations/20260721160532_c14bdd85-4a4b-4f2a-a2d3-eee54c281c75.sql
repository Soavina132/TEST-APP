
-- 1) New columns
ALTER TABLE public.ludo_participants ADD COLUMN IF NOT EXISTS finish_rank int;
ALTER TABLE public.tournament_matches ADD COLUMN IF NOT EXISTS qualifiers_count int NOT NULL DEFAULT 1;
ALTER TABLE public.tournament_matches ADD COLUMN IF NOT EXISTS qualifiers_ids uuid[] DEFAULT ARRAY[]::uuid[];

-- 2) Skip already-finished slots in turn rotation
CREATE OR REPLACE FUNCTION public._ludo_next_slot(_game_id uuid, _from integer, _max integer)
 RETURNS integer LANGUAGE plpgsql STABLE SET search_path TO 'public'
AS $function$
DECLARE v_cur_start INT; v_next_slot INT;
BEGIN
  SELECT public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END)
    INTO v_cur_start FROM public.ludo_participants WHERE game_id = _game_id AND slot = _from;
  IF v_cur_start IS NULL THEN v_cur_start := 0; END IF;

  SELECT slot INTO v_next_slot FROM public.ludo_participants
   WHERE game_id = _game_id AND forfeited = FALSE AND finish_rank IS NULL
     AND public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END) > v_cur_start
   ORDER BY public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END) ASC
   LIMIT 1;

  IF v_next_slot IS NULL THEN
    SELECT slot INTO v_next_slot FROM public.ludo_participants
     WHERE game_id = _game_id AND forfeited = FALSE AND finish_rank IS NULL
     ORDER BY public._ludo_start_idx(CASE color WHEN 'red' THEN 0 WHEN 'green' THEN 1 WHEN 'yellow' THEN 2 WHEN 'blue' THEN 3 END) ASC
     LIMIT 1;
  END IF;

  RETURN COALESCE(v_next_slot, _from);
END $function$;

-- 3) ludo_move: continue playing until enough qualifiers finished
CREATE OR REPLACE FUNCTION public.ludo_move(_game_id uuid, _pawn_idx integer)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE st jsonb; g public.ludo_games%ROWTYPE; v_uid UUID := auth.uid();
  v_slot INT; v_dice INT; v_user UUID; v_isbot BOOLEAN; v_max INT;
  pawn jsonb; pawn_state TEXT; pawn_step INT; new_step INT; new_state TEXT;
  start_idx INT; abs_cell INT; captured BOOLEAN := FALSE; bonus BOOLEAN := FALSE;
  finished BOOLEAN := FALSE; all_done BOOLEAN; winner_uid UUID;
  rec RECORD; other_pawns jsonb; op jsonb; op_step INT; op_start INT;
  i INT; j INT; arr jsonb; same_slot_count INT;
  v_captured_list jsonb := '[]'::jsonb; v_now text; v_seq int;
  v_qc int; v_finishers int; v_remaining int; v_next_rank int;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  st := g.state; v_slot := (st->>'turn_slot')::INT; v_max := g.max_players;
  SELECT user_id, is_bot INTO v_user, v_isbot FROM public.ludo_participants WHERE game_id=_game_id AND slot=v_slot;
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
    IF new_step > 56 THEN RAISE EXCEPTION 'Dépassement — chiffre exact requis pour entrer à l''arrivée'; END IF;
    IF new_step = 56 THEN new_state := 'finished'; finished := TRUE; ELSE new_state := 'track'; END IF;
  END IF;
  arr := st->'pawns'->v_slot::text;
  arr := jsonb_set(arr, ARRAY[_pawn_idx::text], jsonb_build_object('s', new_state, 'k', new_step));
  st := jsonb_set(st, ARRAY['pawns', v_slot::text], arr);
  IF new_state = 'track' AND new_step <= 50 THEN
    start_idx := public._ludo_start_for(_game_id, v_slot);
    abs_cell := (start_idx + new_step) % 52;
    IF NOT public._ludo_is_safe(abs_cell) THEN
      FOR rec IN SELECT slot FROM public.ludo_participants WHERE game_id=_game_id AND slot <> v_slot LOOP
        op_start := public._ludo_start_for(_game_id, rec.slot);
        other_pawns := st->'pawns'->rec.slot::text;
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
                other_pawns := jsonb_set(other_pawns, ARRAY[j::text], jsonb_build_object('s','yard','k',-1));
                captured := TRUE;
                v_captured_list := v_captured_list || jsonb_build_object('slot', rec.slot, 'pawn', j);
              END IF;
            END IF;
          END LOOP;
          st := jsonb_set(st, ARRAY['pawns', rec.slot::text], other_pawns);
        END IF;
      END LOOP;
    END IF;
  END IF;
  all_done := TRUE;
  FOR i IN 0..3 LOOP
    IF (st->'pawns'->v_slot::text->i->>'s') <> 'finished' THEN all_done := FALSE; END IF;
  END LOOP;
  UPDATE public.ludo_participants SET missed_turns=0 WHERE game_id=_game_id AND slot=v_slot;
  UPDATE public.ludo_games SET state=st WHERE id=_game_id;
  v_now := to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"');
  v_seq := COALESCE((st->>'turn_seq')::int, 0);
  PERFORM public._ludo_push_move(_game_id, jsonb_build_object(
    'seq', v_seq, 'slot', v_slot, 'pawn', _pawn_idx, 'dice', v_dice,
    'captured', v_captured_list, 'finished', finished, 'at', v_now
  ));

  IF all_done THEN
    -- Assign finish rank to this player
    SELECT COALESCE(MAX(finish_rank),0)+1 INTO v_next_rank
      FROM public.ludo_participants WHERE game_id=_game_id;
    UPDATE public.ludo_participants SET finish_rank = v_next_rank
      WHERE game_id=_game_id AND slot=v_slot;

    -- How many qualifiers does this game/match need?
    v_qc := 1;
    IF g.tournament_match_id IS NOT NULL THEN
      SELECT COALESCE(qualifiers_count,1) INTO v_qc FROM public.tournament_matches WHERE id = g.tournament_match_id;
    END IF;

    SELECT count(*) INTO v_finishers FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NOT NULL;
    SELECT count(*) INTO v_remaining FROM public.ludo_participants
      WHERE game_id=_game_id AND finish_rank IS NULL AND forfeited=FALSE;

    IF v_finishers >= v_qc OR v_remaining <= 1 THEN
      -- End game: winner is first finisher (rank 1)
      SELECT user_id INTO winner_uid FROM public.ludo_participants
        WHERE game_id=_game_id AND finish_rank=1;
      PERFORM public.finish_game(_game_id, winner_uid);
      SELECT state INTO st FROM public.ludo_games WHERE id=_game_id;
      RETURN st;
    ELSE
      -- Continue with next non-finished player
      RETURN public._ludo_advance_turn(
        _game_id, public._ludo_next_slot(_game_id, v_slot, v_max), 'home:continue'
      );
    END IF;
  END IF;

  bonus := (v_dice = 6) OR captured OR finished;
  IF NOT bonus THEN
    UPDATE public.ludo_participants SET consecutive_sixes=0 WHERE game_id=_game_id AND slot=v_slot;
  END IF;
  RETURN public._ludo_advance_turn(
    _game_id,
    CASE WHEN bonus THEN v_slot ELSE public._ludo_next_slot(_game_id, v_slot, v_max) END,
    CASE WHEN bonus THEN (CASE WHEN captured THEN 'capture' WHEN finished THEN 'home' ELSE 'six' END || ':rejoue') ELSE 'move' END
  );
END $function$;

-- 4) Build round: set qualifiers_count per match (4-player groups qualify 2)
CREATE OR REPLACE FUNCTION public._tournament_build_round(_tid uuid, _round integer, _player_ids uuid[])
 RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_size integer; v_idx integer := 0;
  v_players uuid[]; v_ordered uuid[]; v_total integer;
  v_i integer; v_remaining integer; v_qc integer;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid FOR UPDATE;
  v_size := GREATEST(COALESCE(v_t.players_per_match, 2), 2);
  v_ordered := public._tournament_order_players(_player_ids, COALESCE(v_t.bye_strategy,'random'));
  v_total := COALESCE(array_length(v_ordered, 1), 0);

  IF v_total <= 1 THEN
    IF v_total = 1 THEN
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, winner_id, finished_at, is_bye, qualifiers_count, qualifiers_ids)
        VALUES (_tid, _round, 0, v_ordered, 'finished', v_ordered[1], now(), true, 1, v_ordered);
    END IF;
    RETURN;
  END IF;

  v_i := 1;
  WHILE v_i <= v_total LOOP
    v_remaining := v_total - v_i + 1;

    IF v_size = 2 AND v_remaining = 3 THEN
      v_players := v_ordered[v_i : v_total];
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye, qualifiers_count)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false, 1);
      v_idx := v_idx + 1;
      EXIT;
    END IF;

    IF v_remaining = v_size + 1 AND v_size >= 3 THEN
      v_players := v_ordered[v_i : v_i + v_size - 2];
      v_qc := CASE WHEN array_length(v_players,1) = 4 THEN 2 ELSE 1 END;
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye, qualifiers_count)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false, v_qc);
      v_idx := v_idx + 1;
      v_i := v_i + v_size - 1;
      v_players := v_ordered[v_i : v_total];
      v_qc := CASE WHEN array_length(v_players,1) = 4 THEN 2 ELSE 1 END;
      INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye, qualifiers_count)
        VALUES (_tid, _round, v_idx, v_players, 'pending', false, v_qc);
      v_idx := v_idx + 1;
      EXIT;
    END IF;

    v_players := v_ordered[v_i : LEAST(v_i + v_size - 1, v_total)];
    v_qc := CASE WHEN array_length(v_players,1) = 4 THEN 2 ELSE 1 END;
    INSERT INTO public.tournament_matches(tournament_id, round, match_index, player_ids, status, is_bye, qualifiers_count)
      VALUES (_tid, _round, v_idx, v_players, 'pending', false, v_qc);
    v_idx := v_idx + 1;
    v_i := v_i + v_size;
  END LOOP;
END $function$;

-- 5) On game finished: gather qualifiers list, advance with all qualifiers
CREATE OR REPLACE FUNCTION public._tournament_on_game_finished()
 RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_match public.tournament_matches%ROWTYPE;
  v_t public.tournaments%ROWTYPE;
  v_remaining int; v_winners uuid[]; v_total int;
  m record; v_game_id uuid; v_first uuid; v_color text;
  v_slot int; v_name text; v_pid uuid; v_payout numeric;
  v_top3 jsonb; v_size int; v_quals uuid[];
BEGIN
  IF NEW.status <> 'finished' OR OLD.status = 'finished' THEN RETURN NEW; END IF;
  IF NEW.tournament_match_id IS NULL THEN RETURN NEW; END IF;

  SELECT * INTO v_match FROM public.tournament_matches WHERE id = NEW.tournament_match_id FOR UPDATE;
  IF v_match.id IS NULL OR v_match.status = 'finished' THEN RETURN NEW; END IF;

  -- Compute qualifiers list from the finished game
  IF TG_TABLE_NAME = 'ludo_games' THEN
    SELECT COALESCE(array_agg(user_id ORDER BY finish_rank), ARRAY[]::uuid[])
      INTO v_quals
      FROM public.ludo_participants
      WHERE game_id = NEW.id AND finish_rank IS NOT NULL AND user_id IS NOT NULL
      LIMIT v_match.qualifiers_count;
  ELSE
    v_quals := CASE WHEN NEW.winner_id IS NOT NULL THEN ARRAY[NEW.winner_id] ELSE ARRAY[]::uuid[] END;
  END IF;

  IF (v_quals IS NULL OR array_length(v_quals,1) IS NULL) AND NEW.winner_id IS NOT NULL THEN
    v_quals := ARRAY[NEW.winner_id];
  END IF;

  -- Cap to qualifiers_count
  IF array_length(v_quals,1) > v_match.qualifiers_count THEN
    v_quals := v_quals[1 : v_match.qualifiers_count];
  END IF;

  UPDATE public.tournament_matches
    SET status='finished', winner_id = COALESCE(NEW.winner_id, v_quals[1]),
        qualifiers_ids = v_quals, finished_at = now()
    WHERE id = v_match.id;

  SELECT * INTO v_t FROM public.tournaments WHERE id = v_match.tournament_id FOR UPDATE;

  -- Eliminated = players in match not in qualifiers
  UPDATE public.tournament_registrations
    SET eliminated_round = v_t.current_round
    WHERE tournament_id = v_t.id
      AND user_id = ANY(v_match.player_ids)
      AND NOT (user_id = ANY(COALESCE(v_quals, ARRAY[]::uuid[])))
      AND eliminated_round IS NULL;

  SELECT count(*) INTO v_remaining
    FROM public.tournament_matches
    WHERE tournament_id = v_t.id AND round = v_t.current_round AND status NOT IN ('finished','bye');
  IF v_remaining > 0 THEN RETURN NEW; END IF;

  -- Collect all qualifiers from this round
  SELECT array_agg(q ORDER BY match_index, ord) INTO v_winners
    FROM (
      SELECT match_index, ord, q
      FROM public.tournament_matches tm,
           LATERAL unnest(COALESCE(tm.qualifiers_ids, CASE WHEN tm.winner_id IS NOT NULL THEN ARRAY[tm.winner_id] ELSE ARRAY[]::uuid[] END))
             WITH ORDINALITY AS u(q, ord)
      WHERE tm.tournament_id = v_t.id AND tm.round = v_t.current_round AND (tm.winner_id IS NOT NULL OR tm.qualifiers_ids IS NOT NULL)
    ) s;
  v_total := COALESCE(array_length(v_winners,1),0);

  IF v_total <= 1 THEN
    v_top3 := '[]'::jsonb;
    SELECT jsonb_agg(jsonb_build_object('user_id', user_id, 'eliminated_round', eliminated_round)
                     ORDER BY (CASE WHEN user_id = v_winners[1] THEN 999999 ELSE eliminated_round END) DESC) INTO v_top3
      FROM (
        SELECT user_id, COALESCE(eliminated_round, 999999) as eliminated_round
          FROM public.tournament_registrations
          WHERE tournament_id = v_t.id
          ORDER BY (CASE WHEN user_id = v_winners[1] THEN 999999 ELSE eliminated_round END) DESC NULLS LAST
          LIMIT 3
      ) s;

    UPDATE public.tournaments
      SET status='finished', finished_at=now(), winner_id = v_winners[1], top3 = COALESCE(v_top3,'[]'::jsonb)
      WHERE id = v_t.id;

    IF NOT v_t.is_free AND v_t.prize_pool > 0 THEN
      v_payout := v_t.prize_pool * (100 - v_t.commission_pct) / 100.0;
      UPDATE public.profiles SET balance_ar = balance_ar + v_payout WHERE id = v_winners[1];
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_winners[1],'win', v_payout, v_t.id, 'Victoire tournoi: '||v_t.name);
    END IF;
    RETURN NEW;
  END IF;

  UPDATE public.tournaments SET current_round = current_round + 1 WHERE id = v_t.id;
  PERFORM public._tournament_build_round(v_t.id, v_t.current_round + 1, v_winners);

  FOR m IN SELECT * FROM public.tournament_matches
           WHERE tournament_id = v_t.id AND round = v_t.current_round + 1 AND status = 'pending' ORDER BY match_index LOOP
    v_first := m.player_ids[1];
    v_size := GREATEST(array_length(m.player_ids,1), 2);
    INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct, room_code, is_private, mode, tournament_match_id, status)
      VALUES (v_first, v_size, 0, 0, 0, NULL, TRUE, 'classic', m.id, 'open')
      RETURNING id INTO v_game_id;
    v_slot := 0;
    FOREACH v_pid IN ARRAY m.player_ids LOOP
      v_color := (ARRAY['red','blue','green','yellow'])[v_slot+1];
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_pid;
      INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name)
        VALUES (v_game_id, v_pid, v_slot, v_color, COALESCE(v_name,'Joueur'));
      v_slot := v_slot + 1;
    END LOOP;
    UPDATE public.tournament_matches SET game_id = v_game_id, status = 'running' WHERE id = m.id;
  END LOOP;

  RETURN NEW;
END $function$;
