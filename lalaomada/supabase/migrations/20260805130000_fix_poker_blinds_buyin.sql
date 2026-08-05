-- ═══════════════════════════════════════════════════════════════════
-- Fix: Poker — blinds & buy-in params not accepted by poker_create
--
-- PROBLEM: Frontend sends _small_blind, _big_blind, _buy_in to
-- poker_create, but the function only accepts _stake, _max, _private,
-- _commission. PostgREST returns 404 (PGRST202) — creating a poker
-- game is completely broken.
--
-- FIX:
--   1. Add small_blind, big_blind, buy_in_chips columns to poker_games
--   2. Update poker_create to accept & store these params
--   3. Update poker_join & poker_join_code to use buy_in_chips from game
--   4. Update _poker_deal_hand to use stored blinds instead of calc
-- ═══════════════════════════════════════════════════════════════════

-- Step 1: Add columns to poker_games
ALTER TABLE public.poker_games
  ADD COLUMN IF NOT EXISTS small_blind numeric DEFAULT 10,
  ADD COLUMN IF NOT EXISTS big_blind numeric DEFAULT 20,
  ADD COLUMN IF NOT EXISTS buy_in_chips numeric DEFAULT 10000;

-- Backfill existing games with default values
UPDATE public.poker_games
  SET small_blind = GREATEST(stake * 10, 10),
      big_blind = GREATEST(stake * 20, 20),
      buy_in_chips = GREATEST(stake * 100, 10000)
WHERE small_blind IS NULL OR big_blind IS NULL OR buy_in_chips IS NULL;

-- Step 2: Update poker_create to accept blinds & buy-in
CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric,
  _max integer DEFAULT 6,
  _private boolean DEFAULT false,
  _commission numeric DEFAULT 10,
  _small_blind numeric DEFAULT 10,
  _big_blind numeric DEFAULT 20,
  _buy_in numeric DEFAULT 10000
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
  v_chips numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  IF _small_blind <= 0 THEN RAISE EXCEPTION 'Petite blinde invalide'; END IF;
  IF _big_blind < _small_blind THEN RAISE EXCEPTION 'Grosse blinde invalide'; END IF;
  IF _buy_in < _big_blind * 2 THEN RAISE EXCEPTION 'Cave trop faible'; END IF;

  -- Check balance
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;

  -- Deduct stake
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note)
      VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;

  -- Generate code
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;

  -- Create game with blinds & buy-in
  INSERT INTO public.poker_games(
    host_id, stake, commission_pct, max_players, is_private, room_code,
    created_by, state, small_blind, big_blind, buy_in_chips
  )
  VALUES(
    v_uid, _stake, _commission, _max, _private, v_code,
    v_uid, '{}', _small_blind, _big_blind, _buy_in
  )
  RETURNING id INTO v_gid;

  -- Add creator as player (seat 0) with configured buy-in
  v_chips := _buy_in;
  INSERT INTO public.poker_players(game_id, user_id, seat, chips, status, is_ready)
  VALUES(v_gid, v_uid, 0, v_chips, 'waiting', false);

  RETURN v_gid;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.poker_create(numeric, integer, boolean, numeric, numeric, numeric, numeric) TO authenticated, anon;

-- Step 3: Update poker_join to use buy_in_chips from game
CREATE OR REPLACE FUNCTION public.poker_join(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  v_seat int; v_chips numeric;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF g.is_private THEN RAISE EXCEPTION 'Partie privée, utilisez le code'; END IF;
  IF (SELECT count(*) FROM public.poker_players WHERE game_id=_game_id) >= g.max_players THEN
    RAISE EXCEPTION 'Table complète';
  END IF;
  IF EXISTS (SELECT 1 FROM public.poker_players WHERE game_id=_game_id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Vous êtes déjà assis';
  END IF;
  IF g.stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < g.stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  -- Deduct stake
  IF g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-g.stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES(v_uid,'stake',-g.stake,_game_id,'Mise Poker');
  END IF;
  -- Find next free seat
  SELECT COALESCE(MAX(seat)+1, 0) INTO v_seat FROM public.poker_players WHERE game_id=_game_id;
  v_chips := COALESCE(g.buy_in_chips, GREATEST(g.stake * 100, 10000));
  INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
  VALUES(_game_id,v_uid,v_seat,v_chips,'waiting',false);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.poker_join(uuid) TO authenticated, anon;

-- Step 4: Update poker_join_code to use buy_in_chips from game
CREATE OR REPLACE FUNCTION public.poker_join_code(_code text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $function$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  v_seat int; v_chips numeric;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE upper(room_code)=upper(_code) AND status='waiting' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Code invalide ou partie déjà commencée'; END IF;
  IF (SELECT count(*) FROM public.poker_players WHERE game_id=g.id) >= g.max_players THEN
    RAISE EXCEPTION 'Table complète';
  END IF;
  IF EXISTS (SELECT 1 FROM public.poker_players WHERE game_id=g.id AND user_id=v_uid) THEN
    RAISE EXCEPTION 'Vous êtes déjà assis';
  END IF;
  IF g.stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < g.stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  IF g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-g.stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES(v_uid,'stake',-g.stake,g.id,'Mise Poker');
  END IF;
  SELECT COALESCE(MAX(seat)+1, 0) INTO v_seat FROM public.poker_players WHERE game_id=g.id;
  v_chips := COALESCE(g.buy_in_chips, GREATEST(g.stake * 100, 10000));
  INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
  VALUES(g.id,v_uid,v_seat,v_chips,'waiting',false);
  RETURN g.id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.poker_join_code(text) TO authenticated, anon;

-- Step 5: Update _poker_deal_hand to use stored blinds from game row
CREATE OR REPLACE FUNCTION public._poker_deal_hand(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $function$
DECLARE
  g public.poker_games%ROWTYPE;
  st jsonb; deck int[]; pos int := 0;
  dealer_seat int; sb_seat int; bb_seat int; first_seat int;
  active_players jsonb[];
  p jsonb; i int; seat int;
  n_active int;
  sb_amount numeric; bb_amount numeric;
  new_state jsonb;
  cfg_sb numeric := 0; cfg_bb numeric := 0;
  pl record;
  hand_n int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;
  st := g.state;
  hand_n := COALESCE((st->>'hand_number')::int, 0) + 1;

  -- Use stored blinds from game, fallback to calculated values for old games
  cfg_sb := COALESCE(g.small_blind, 10);
  cfg_bb := COALESCE(g.big_blind, cfg_sb * 2);

  deck := public._poker_new_deck();

  -- Get active players ordered by seat
  UPDATE public.poker_players SET bet_round=0, hole_cards='{}', last_action=NULL, hand_result=NULL, status='playing'
    WHERE game_id=_gid AND status NOT IN ('out','waiting','finished');

  SELECT jsonb_agg(to_jsonb(p.*) ORDER BY seat) INTO active_players
  FROM public.poker_players p
  WHERE p.game_id=_gid AND p.status='playing';

  n_active := jsonb_array_length(active_players);
  IF n_active < 2 THEN RETURN; END IF;

  -- Dealer button rotates
  dealer_seat := COALESCE((st->>'dealer_seat')::int, -1);
  LOOP
    dealer_seat := dealer_seat + 1;
    IF dealer_seat > 100 THEN EXIT; END IF;
    FOR i IN 0..n_active-1 LOOP
      p := active_players[i];
      IF (p->>'seat')::int = dealer_seat THEN
        EXIT;
      END IF;
    END LOOP;
    EXIT WHEN FOUND;
  END LOOP;

  -- Find SB and BB seats
  sb_seat := dealer_seat + 1;
  bb_seat := dealer_seat + 2;
  first_seat := dealer_seat + 3;

  -- Post blinds
  UPDATE public.poker_players SET chips=chips-cfg_sb, bet_round=cfg_sb, total_bet=total_bet+cfg_sb
    WHERE game_id=_gid AND seat=sb_seat;
  UPDATE public.poker_players SET chips=chips-cfg_bb, bet_round=cfg_bb, total_bet=total_bet+cfg_bb
    WHERE game_id=_gid AND seat=bb_seat;

  -- Deal 2 cards to each player
  FOR i IN 0..n_active-1 LOOP
    p := active_players[i];
    seat := (p->>'seat')::int;
    PERFORM dblink_exec('UPDATE poker_players SET hole_cards=ARRAY['||deck[pos+1]||','||deck[pos+2]||'] WHERE game_id='||quote_literal(_gid::text)||' AND seat='||seat);
    pos := pos + 2;
  END LOOP;

  -- Set game state
  new_state := jsonb_build_object(
    'hand_number', hand_n,
    'phase', 'preflop',
    'dealer_seat', dealer_seat,
    'sb_seat', sb_seat,
    'bb_seat', bb_seat,
    'current_bet', cfg_bb,
    'small_blind', cfg_sb,
    'big_blind', cfg_bb,
    'turn_deadline', to_char(now() AT TIME ZONE 'UTC' + interval '30 seconds','YYYY-MM-DD"T"HH24:MI:SS"Z"')
  );

  st := st || new_state;

  -- Find first to act (after BB)
  DECLARE first_seat_int int; BEGIN
    FOR i IN 0..n_active-1 LOOP
      p := active_players[i];
      IF (p->>'seat')::int = first_seat THEN
        first_seat_int := (p->>'seat')::int;
        EXIT;
      END IF;
    END LOOP;
    st := jsonb_set(st, '{current_seat}', to_jsonb(first_seat_int));
  END;

  UPDATE public.poker_games SET state=st, phase='preflop', hand_number=hand_n, current_player=(
    SELECT user_id FROM public.poker_players WHERE game_id=_gid AND seat=(st->>'current_seat')::int
  ) WHERE id=_gid;
END;
$function$;
