-- ═══════════════════════════════════════════════════════════════════════════
-- POKER (Texas Hold'em) — Lalao MADA
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Tables ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.poker_games (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  status          text NOT NULL DEFAULT 'waiting',  -- waiting|playing|finished|cancelled
  stake           numeric NOT NULL DEFAULT 0,
  commission_pct  numeric NOT NULL DEFAULT 10,
  max_players     int NOT NULL DEFAULT 6,
  is_private      boolean NOT NULL DEFAULT false,
  room_code       text,
  created_by      uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  pot             numeric NOT NULL DEFAULT 0,
  state           jsonb NOT NULL DEFAULT '{}',
  phase           text NOT NULL DEFAULT 'waiting',  -- waiting|preflop|flop|turn|river|showdown
  hand_number     int NOT NULL DEFAULT 0,
  community_cards int[] NOT NULL DEFAULT '{}',
  current_player  uuid,
  turn_deadline   timestamptz,
  winner_id       uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  started_at      timestamptz,
  finished_at     timestamptz,
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS poker_games_status ON public.poker_games(status);
CREATE INDEX IF NOT EXISTS poker_games_created_by ON public.poker_games(created_by);

CREATE TABLE IF NOT EXISTS public.poker_players (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id         uuid NOT NULL REFERENCES public.poker_games(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  seat            int NOT NULL,
  chips           numeric NOT NULL DEFAULT 0,
  bet_round       numeric NOT NULL DEFAULT 0,
  total_bet       numeric NOT NULL DEFAULT 0,
  hole_cards      int[] NOT NULL DEFAULT '{}',
  status          text NOT NULL DEFAULT 'waiting',   -- waiting|playing|folded|all_in|out|finished
  is_ready        boolean NOT NULL DEFAULT false,
  last_action     text,
  hand_result     jsonb,
  joined_at       timestamptz NOT NULL DEFAULT now(),
  UNIQUE(game_id, seat),
  UNIQUE(game_id, user_id)
);
CREATE INDEX IF NOT EXISTS poker_players_game ON public.poker_players(game_id);
CREATE INDEX IF NOT EXISTS poker_players_user  ON public.poker_players(user_id);

-- ── 2. RLS ─────────────────────────────────────────────────────────────────
ALTER TABLE public.poker_games   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.poker_players ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "poker_games_read"   ON public.poker_games;
DROP POLICY IF EXISTS "poker_players_read" ON public.poker_players;
CREATE POLICY "poker_games_read"   ON public.poker_games   FOR SELECT USING (true);
CREATE POLICY "poker_players_read" ON public.poker_players FOR SELECT USING (true);

-- ── 3. Hand evaluator ─────────────────────────────────────────────────────
-- Card encoding: card = suit*13 + rank, rank 0=A,1=2,...,12=K
-- Poker rank (eval): A=14, 2=2, ..., K=13
CREATE OR REPLACE FUNCTION public._poker_eval_rank(_rank int) RETURNS int
LANGUAGE sql IMMUTABLE AS $$ SELECT CASE WHEN _rank=0 THEN 14 ELSE _rank+1 END; $$;

-- Score a 5-card hand. Returns bigint: higher is better.
CREATE OR REPLACE FUNCTION public._poker_score5(cards int[])
RETURNS bigint LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  ev int[]; su int[];
  c int; r int; s int;
  srt int[]; -- sorted eval ranks desc
  is_fl bool; is_st bool; st_high int;
  cnt_arr int[]; -- rank occurrence counts desc
  rv_arr  int[]; -- rank values ordered by cnt desc then rank desc
  cnt_map jsonb := '{}';
  rk int; rn int;
  pairs int := 0; trips int := 0; quads int := 0;
  pair_hi int := 0; pair_lo int := 0; trip_r int := 0; quad_r int := 0;
  kickers int[];
BEGIN
  ev := '{}'; su := '{}';
  FOREACH c IN ARRAY cards LOOP
    r := c % 13; s := c / 13;
    ev := ev || public._poker_eval_rank(r);
    su := su || s;
  END LOOP;

  -- flush check
  is_fl := (su[1]=su[2] AND su[2]=su[3] AND su[3]=su[4] AND su[4]=su[5]);

  -- sort desc
  SELECT array_agg(x ORDER BY x DESC) INTO srt FROM unnest(ev) x;

  -- straight check
  is_st := false; st_high := 0;
  IF (SELECT count(DISTINCT x) FROM unnest(ev) x) = 5 THEN
    IF srt[1]-srt[5] = 4 THEN
      is_st := true; st_high := srt[1];
    ELSIF srt[1]=14 AND srt[2]=5 AND srt[3]=4 AND srt[4]=3 AND srt[5]=2 THEN
      is_st := true; st_high := 5; -- wheel
    END IF;
  END IF;

  -- count occurrences per rank
  FOR rk IN SELECT DISTINCT x FROM unnest(ev) x LOOP
    SELECT count(*) INTO rn FROM unnest(ev) x WHERE x=rk;
    IF    rn=4 THEN quads:=quads+1; quad_r:=rk;
    ELSIF rn=3 THEN trips:=trips+1; trip_r:=rk;
    ELSIF rn=2 THEN pairs:=pairs+1;
      IF rk > pair_hi THEN pair_lo:=pair_hi; pair_hi:=rk;
      ELSE pair_lo:=GREATEST(pair_lo,rk); END IF;
    END IF;
  END LOOP;
  SELECT array_agg(x ORDER BY x DESC) INTO kickers
  FROM unnest(ev) x WHERE NOT (
    (quads>0 AND x=quad_r) OR
    (trips>0 AND x=trip_r) OR
    (pairs>0 AND x=pair_hi) OR
    (pairs>1 AND x=pair_lo)
  );

  -- Score
  IF is_fl AND is_st THEN
    IF st_high=14 THEN RETURN 9000000000::bigint; END IF; -- Royal
    RETURN 8000000000::bigint + st_high;                  -- Str flush
  ELSIF quads>0 THEN
    RETURN 7000000000::bigint + quad_r*100 + COALESCE(kickers[1],0);
  ELSIF trips>0 AND pairs>0 THEN
    RETURN 6000000000::bigint + trip_r*100 + pair_hi;
  ELSIF is_fl THEN
    RETURN 5000000000::bigint + srt[1]*14^4+srt[2]*14^3+srt[3]*14^2+srt[4]*14+srt[5];
  ELSIF is_st THEN
    RETURN 4000000000::bigint + st_high;
  ELSIF trips>0 THEN
    RETURN 3000000000::bigint + trip_r*200 + COALESCE(kickers[1],0)*14 + COALESCE(kickers[2],0);
  ELSIF pairs>1 THEN
    RETURN 2000000000::bigint + pair_hi*200 + pair_lo*14 + COALESCE(kickers[1],0);
  ELSIF pairs>0 THEN
    RETURN 1000000000::bigint + pair_hi*3000 + COALESCE(kickers[1],0)*200 + COALESCE(kickers[2],0)*14 + COALESCE(kickers[3],0);
  ELSE -- high card
    RETURN srt[1]*14^4+srt[2]*14^3+srt[3]*14^2+srt[4]*14+srt[5];
  END IF;
END;
$$;

-- Best 5-card score from all combos (hole cards + community)
CREATE OR REPLACE FUNCTION public._poker_best_score(hole int[], community int[])
RETURNS bigint LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  all_cards int[] := hole || community;
  n int := array_length(all_cards, 1);
  best bigint := -1; sc bigint;
  i1 int; i2 int; i3 int; i4 int; i5 int;
  hand int[];
BEGIN
  IF n < 5 THEN RETURN -1; END IF;
  FOR i1 IN 1..n-4 LOOP
   FOR i2 IN i1+1..n-3 LOOP
    FOR i3 IN i2+1..n-2 LOOP
     FOR i4 IN i3+1..n-1 LOOP
      FOR i5 IN i4+1..n LOOP
        hand := ARRAY[all_cards[i1],all_cards[i2],all_cards[i3],all_cards[i4],all_cards[i5]];
        sc := public._poker_score5(hand);
        IF sc > best THEN best := sc; END IF;
      END LOOP;
     END LOOP;
    END LOOP;
   END LOOP;
  END LOOP;
  RETURN best;
END;
$$;

-- Human-readable hand label
CREATE OR REPLACE FUNCTION public._poker_hand_label(score bigint) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN score >= 9000000000 THEN 'Quinte Royale'
    WHEN score >= 8000000000 THEN 'Quinte Flush'
    WHEN score >= 7000000000 THEN 'Carré'
    WHEN score >= 6000000000 THEN 'Full House'
    WHEN score >= 5000000000 THEN 'Couleur'
    WHEN score >= 4000000000 THEN 'Suite'
    WHEN score >= 3000000000 THEN 'Brelan'
    WHEN score >= 2000000000 THEN 'Double Paire'
    WHEN score >= 1000000000 THEN 'Paire'
    ELSE 'Hauteur'
  END;
$$;

-- ── 4. Internal helpers ───────────────────────────────────────────────────
-- Shuffle a 52-card deck
CREATE OR REPLACE FUNCTION public._poker_new_deck() RETURNS int[]
LANGUAGE sql VOLATILE AS $$
  SELECT array_agg(x ORDER BY random()) FROM generate_series(0,51) x;
$$;

-- Deal new hand from current state
CREATE OR REPLACE FUNCTION public._poker_deal_hand(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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

  -- Blind levels based on hand number
  DECLARE base_chips numeric;
  BEGIN
    SELECT chips INTO base_chips FROM public.poker_players WHERE game_id=_gid AND status != 'out' LIMIT 1;
    cfg_sb := GREATEST(base_chips * 0.005, 10);
    cfg_bb := cfg_sb * 2;
  END;

  deck := public._poker_new_deck();

  -- Get active players ordered by seat
  UPDATE public.poker_players SET bet_round=0, hole_cards='{}', last_action=NULL, hand_result=NULL, status='playing'
  WHERE game_id=_gid AND status NOT IN ('out','finished');

  -- Compute dealer position (rotate each hand)
  dealer_seat := COALESCE((st->>'dealer_seat')::int, -1);
  SELECT seat INTO dealer_seat FROM public.poker_players
  WHERE game_id=_gid AND status='playing' AND seat > dealer_seat
  ORDER BY seat ASC LIMIT 1;
  IF dealer_seat IS NULL THEN
    SELECT MIN(seat) INTO dealer_seat FROM public.poker_players WHERE game_id=_gid AND status='playing';
  END IF;

  -- Get active seats in order after dealer
  DECLARE seats int[];
  BEGIN
    SELECT array_agg(seat ORDER BY seat) INTO seats FROM public.poker_players WHERE game_id=_gid AND status='playing';
    n_active := array_length(seats, 1);
    -- Find SB and BB positions (next after dealer)
    DECLARE dealer_idx int := array_position(seats, dealer_seat);
    BEGIN
      IF n_active = 2 THEN -- heads-up: dealer posts SB
        sb_seat := dealer_seat;
        bb_seat := seats[((dealer_idx) % n_active) + 1];
        first_seat := sb_seat; -- dealer acts first preflop in HU
      ELSE
        sb_seat := seats[((dealer_idx) % n_active) + 1];
        bb_seat := seats[((dealer_idx + 1) % n_active) + 1];
        first_seat := seats[((dealer_idx + 2) % n_active) + 1];
      END IF;
    END;
  END;

  -- Post blinds
  UPDATE public.poker_players SET chips=chips-cfg_sb, bet_round=cfg_sb, total_bet=total_bet+cfg_sb WHERE game_id=_gid AND seat=sb_seat;
  UPDATE public.poker_players SET chips=chips-cfg_bb, bet_round=cfg_bb, total_bet=total_bet+cfg_bb WHERE game_id=_gid AND seat=bb_seat;

  -- Deal 2 hole cards per player
  DECLARE deal_pos int := 1; all_seats int[];
  BEGIN
    SELECT array_agg(seat ORDER BY seat) INTO all_seats FROM public.poker_players WHERE game_id=_gid AND status='playing';
    FOR i IN 1..2 LOOP
      FOREACH seat IN ARRAY all_seats LOOP
        UPDATE public.poker_players SET hole_cards=hole_cards||deck[deal_pos] WHERE game_id=_gid AND seat=seat;
        deal_pos := deal_pos + 1;
      END LOOP;
    END LOOP;
    -- Remove dealt cards from deck
    deck := deck[deal_pos:];
  END;

  -- Build new state
  new_state := jsonb_build_object(
    'hand_number', hand_n,
    'dealer_seat', dealer_seat,
    'sb_seat', sb_seat,
    'bb_seat', bb_seat,
    'small_blind', cfg_sb,
    'big_blind', cfg_bb,
    'current_bet', cfg_bb,
    'last_raise', cfg_bb,
    'deck', to_jsonb(deck),
    'pot', 0
  );

  UPDATE public.poker_games SET
    state = new_state,
    phase = 'preflop',
    hand_number = hand_n,
    community_cards = '{}',
    current_player = (SELECT user_id FROM public.poker_players WHERE game_id=_gid AND seat=first_seat),
    pot = cfg_sb + cfg_bb,
    turn_deadline = now() + interval '30 seconds',
    updated_at = now()
  WHERE id = _gid;
END;
$$;

-- Find next active player after current seat
CREATE OR REPLACE FUNCTION public._poker_next_player(_gid uuid, _current_seat int)
RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT seat FROM public.poker_players
  WHERE game_id=_gid AND status='playing' AND seat > _current_seat
  ORDER BY seat ASC LIMIT 1
  UNION ALL
  SELECT seat FROM public.poker_players
  WHERE game_id=_gid AND status='playing' AND seat < _current_seat
  ORDER BY seat ASC LIMIT 1
  LIMIT 1;
$$;

-- Check if betting round is complete
CREATE OR REPLACE FUNCTION public._poker_round_done(_gid uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.poker_players p, public.poker_games g
    WHERE p.game_id=_gid AND g.id=_gid AND p.status='playing'
      AND (p.bet_round < (g.state->>'current_bet')::numeric OR p.last_action IS NULL)
  );
$$;

-- Advance to next street or showdown
CREATE OR REPLACE FUNCTION public._poker_next_street(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  deck int[]; community int[]; new_phase text;
  active_cnt int; only_player uuid;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;

  -- Count still-active (not folded)
  SELECT count(*), (ARRAY_AGG(user_id))[1]
  INTO active_cnt, only_player
  FROM public.poker_players WHERE game_id=_gid AND status='playing';

  IF active_cnt = 1 THEN
    -- Everyone else folded — instant winner
    PERFORM public._poker_award(_gid, only_player);
    RETURN;
  END IF;

  -- Reset round bets
  UPDATE public.poker_players SET bet_round=0, last_action=NULL WHERE game_id=_gid AND status='playing';

  deck := ARRAY(SELECT jsonb_array_elements_text(g.state->'deck')::int);
  community := g.community_cards;

  CASE g.phase
    WHEN 'preflop' THEN new_phase := 'flop';    community := community || deck[1] || deck[2] || deck[3]; deck := deck[4:];
    WHEN 'flop'    THEN new_phase := 'turn';    community := community || deck[1]; deck := deck[2:];
    WHEN 'turn'    THEN new_phase := 'river';   community := community || deck[1]; deck := deck[2:];
    WHEN 'river'   THEN PERFORM public._poker_showdown(_gid); RETURN;
    ELSE RETURN;
  END CASE;

  -- First to act after dealer (leftmost active seat after dealer)
  DECLARE dealer_seat int; first_user uuid; first_seat int;
  BEGIN
    dealer_seat := (g.state->>'dealer_seat')::int;
    SELECT seat, user_id INTO first_seat, first_user
    FROM public.poker_players
    WHERE game_id=_gid AND status='playing' AND seat > dealer_seat
    ORDER BY seat ASC LIMIT 1;
    IF first_seat IS NULL THEN
      SELECT seat, user_id INTO first_seat, first_user
      FROM public.poker_players WHERE game_id=_gid AND status='playing' ORDER BY seat ASC LIMIT 1;
    END IF;
  END;

  UPDATE public.poker_games SET
    phase = new_phase,
    community_cards = community,
    state = state || jsonb_build_object('deck', to_jsonb(deck), 'current_bet', 0, 'last_raise', 0),
    current_player = first_user,
    turn_deadline = now() + interval '30 seconds',
    updated_at = now()
  WHERE id = _gid;
END;
$$;

-- Showdown: evaluate hands and award pot
CREATE OR REPLACE FUNCTION public._poker_showdown(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  p record; best_score bigint := -1; winner_uid uuid;
  pl_score bigint; pl_label text;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;

  FOR p IN SELECT * FROM public.poker_players WHERE game_id=_gid AND status='playing' LOOP
    pl_score := public._poker_best_score(p.hole_cards, g.community_cards);
    pl_label := public._poker_hand_label(pl_score);
    UPDATE public.poker_players SET hand_result=jsonb_build_object('score',pl_score,'label',pl_label,'cards',p.hole_cards) WHERE id=p.id;
    IF pl_score > best_score THEN best_score := pl_score; winner_uid := p.user_id; END IF;
  END LOOP;

  PERFORM public._poker_award(_gid, winner_uid);
END;
$$;

-- Award pot to winner
CREATE OR REPLACE FUNCTION public._poker_award(_gid uuid, _winner uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  gross numeric; net numeric; commission numeric;
  still_playing int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;
  gross := g.pot;
  commission := ROUND(gross * g.commission_pct / 100, 0);
  net := gross - commission;

  -- Credit winner chips
  UPDATE public.poker_players SET chips=chips+net, status='finished' WHERE game_id=_gid AND user_id=_winner;
  UPDATE public.poker_players SET status='finished' WHERE game_id=_gid AND status='playing';

  -- Check if game over (only 1 player has chips or max hands)
  SELECT count(*) INTO still_playing FROM public.poker_players WHERE game_id=_gid AND chips > 0 AND status NOT IN ('out','waiting');

  IF still_playing <= 1 THEN
    -- Game finished — pay out
    UPDATE public.profiles SET balance_ar = balance_ar + net WHERE id = _winner;
    -- Platform commission goes to house (already deducted from player balance on join)
    -- Mark out players who lost all chips
    UPDATE public.poker_players SET status='out' WHERE game_id=_gid AND chips <= 0;

    UPDATE public.poker_games SET
      status='finished', phase='finished', winner_id=_winner,
      finished_at=now(), current_player=NULL, turn_deadline=NULL, updated_at=now()
    WHERE id=_gid;

    -- Record in transactions
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
    VALUES(_winner, 'win', net, _gid, 'Victoire Poker');
    IF commission > 0 THEN
      INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES(_winner, 'stake', -commission, _gid, 'Commission Poker');
    END IF;
  ELSE
    -- Start next hand
    UPDATE public.poker_players SET status='playing', bet_round=0, hole_cards='{}', last_action=NULL WHERE game_id=_gid AND chips > 0;
    UPDATE public.poker_players SET status='out' WHERE game_id=_gid AND chips <= 0;
    UPDATE public.poker_games SET phase='between_hands', pot=0, community_cards='{}', current_player=NULL, updated_at=now() WHERE id=_gid;
    PERFORM pg_notify('poker_next_hand', _gid::text);
  END IF;
END;
$$;

-- ── 5. Public RPCs ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric, _max int DEFAULT 6, _private boolean DEFAULT false, _commission numeric DEFAULT 10
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid;
  v_code text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de joueurs invalide (2-9)'; END IF;
  -- Check balance
  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  -- Deduct stake
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;
  -- Generate code
  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;
  -- Create game
  INSERT INTO public.poker_games(stake,commission_pct,max_players,is_private,room_code,created_by,state)
  VALUES(_stake,_commission,_max,_private,v_code,v_uid,'{}')
  RETURNING id INTO v_gid;
  -- Add creator as player (seat 0)
  DECLARE v_chips numeric := GREATEST(_stake * 100, 10000);
  BEGIN
    INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
    VALUES(v_gid,v_uid,0,v_chips,'waiting',false);
  END;
  RETURN v_gid;
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_create TO authenticated;

CREATE OR REPLACE FUNCTION public.poker_join(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES(v_uid,'stake',-g.stake,_game_id,'Mise Poker');
  END IF;
  -- Find next free seat
  SELECT COALESCE(MAX(seat)+1, 0) INTO v_seat FROM public.poker_players WHERE game_id=_game_id;
  v_chips := GREATEST(g.stake * 100, 10000);
  INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
  VALUES(_game_id,v_uid,v_seat,v_chips,'waiting',false);
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_join TO authenticated;

CREATE OR REPLACE FUNCTION public.poker_join_code(_code text) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
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
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES(v_uid,'stake',-g.stake,g.id,'Mise Poker');
  END IF;
  SELECT COALESCE(MAX(seat)+1, 0) INTO v_seat FROM public.poker_players WHERE game_id=g.id;
  v_chips := GREATEST(g.stake * 100, 10000);
  INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
  VALUES(g.id,v_uid,v_seat,v_chips,'waiting',false);
  RETURN g.id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_join_code TO authenticated;

CREATE OR REPLACE FUNCTION public.poker_set_ready(_game_id uuid, _ready boolean DEFAULT true)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  all_ready boolean;
  player_cnt int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  UPDATE public.poker_players SET is_ready=_ready WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), bool_and(is_ready) INTO player_cnt, all_ready FROM public.poker_players WHERE game_id=_game_id;
  IF all_ready AND player_cnt >= 2 THEN
    UPDATE public.poker_games SET status='playing', started_at=now(), updated_at=now() WHERE id=_game_id;
    UPDATE public.poker_players SET status='playing' WHERE game_id=_game_id;
    PERFORM public._poker_deal_hand(_game_id);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_set_ready TO authenticated;

CREATE OR REPLACE FUNCTION public.poker_action(
  _game_id uuid, _action text, _amount numeric DEFAULT 0
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  me public.poker_players%ROWTYPE;
  cur_bet numeric; call_amount numeric; next_seat int; next_user uuid;
  n_active int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status != 'playing' THEN RAISE EXCEPTION 'Partie non active'; END IF;
  IF g.current_player != v_uid THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;
  SELECT * INTO me FROM public.poker_players WHERE game_id=_game_id AND user_id=v_uid;
  cur_bet := (g.state->>'current_bet')::numeric;
  call_amount := GREATEST(cur_bet - me.bet_round, 0);

  CASE _action
    WHEN 'fold' THEN
      UPDATE public.poker_players SET status='folded', last_action='fold' WHERE game_id=_game_id AND user_id=v_uid;
    WHEN 'check' THEN
      IF call_amount > 0 THEN RAISE EXCEPTION 'Vous devez suivre ou passer'; END IF;
      UPDATE public.poker_players SET last_action='check' WHERE game_id=_game_id AND user_id=v_uid;
    WHEN 'call' THEN
      DECLARE actual numeric := LEAST(call_amount, me.chips);
      BEGIN
        UPDATE public.poker_players SET chips=chips-actual, bet_round=bet_round+actual, last_action='call'
        WHERE game_id=_game_id AND user_id=v_uid;
        UPDATE public.poker_games SET pot=pot+actual, updated_at=now() WHERE id=_game_id;
        IF me.chips - actual <= 0 THEN
          UPDATE public.poker_players SET status='all_in' WHERE game_id=_game_id AND user_id=v_uid;
        END IF;
      END;
    WHEN 'raise', 'bet' THEN
      IF _amount <= cur_bet THEN RAISE EXCEPTION 'Relance insuffisante'; END IF;
      IF _amount > me.chips + me.bet_round THEN RAISE EXCEPTION 'Jetons insuffisants'; END IF;
      DECLARE add_chips numeric := _amount - me.bet_round;
      BEGIN
        UPDATE public.poker_players SET chips=chips-add_chips, bet_round=_amount, last_action=_action
        WHERE game_id=_game_id AND user_id=v_uid;
        UPDATE public.poker_games SET
          pot=pot+add_chips,
          state=state||jsonb_build_object('current_bet',_amount,'last_raise',_amount-cur_bet),
          updated_at=now()
        WHERE id=_game_id;
        IF me.chips - add_chips <= 0 THEN
          UPDATE public.poker_players SET status='all_in' WHERE game_id=_game_id AND user_id=v_uid;
        END IF;
        -- Reset last_action for others (they need to act again)
        UPDATE public.poker_players SET last_action=NULL WHERE game_id=_game_id AND user_id!=v_uid AND status='playing';
      END;
    WHEN 'allin' THEN
      DECLARE all_chips numeric := me.chips;
      DECLARE new_total numeric := me.bet_round + all_chips;
      BEGIN
        UPDATE public.poker_players SET chips=0, bet_round=new_total, status='all_in', last_action='allin'
        WHERE game_id=_game_id AND user_id=v_uid;
        UPDATE public.poker_games SET pot=pot+all_chips, updated_at=now() WHERE id=_game_id;
        IF new_total > cur_bet THEN
          UPDATE public.poker_games SET state=state||jsonb_build_object('current_bet',new_total) WHERE id=_game_id;
          UPDATE public.poker_players SET last_action=NULL WHERE game_id=_game_id AND user_id!=v_uid AND status='playing';
        END IF;
      END;
    ELSE RAISE EXCEPTION 'Action inconnue: %', _action;
  END CASE;

  -- Reload game state
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id;

  -- Count playing (not folded, not all_in)
  SELECT count(*) INTO n_active FROM public.poker_players WHERE game_id=_game_id AND status='playing';

  -- Check if only one active + round done
  IF n_active <= 1 OR public._poker_round_done(_game_id) THEN
    PERFORM public._poker_next_street(_game_id);
    RETURN;
  END IF;

  -- Move to next player
  next_seat := public._poker_next_player(_game_id, me.seat);
  SELECT user_id INTO next_user FROM public.poker_players WHERE game_id=_game_id AND seat=next_seat;
  UPDATE public.poker_games SET current_player=next_user, turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_action TO authenticated;

CREATE OR REPLACE FUNCTION public.poker_request_refund(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  cnt int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status != 'waiting' THEN RAISE EXCEPTION 'Remboursement impossible'; END IF;
  IF g.created_by != v_uid THEN RAISE EXCEPTION 'Seul le créateur peut annuler'; END IF;
  SELECT count(*) INTO cnt FROM public.poker_players WHERE game_id=_game_id;
  IF cnt > 1 THEN RAISE EXCEPTION 'Des joueurs ont rejoint, annulation impossible'; END IF;
  -- Refund stake
  IF g.stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar+g.stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note) VALUES(v_uid,'refund',g.stake,_game_id,'Remboursement Poker');
  END IF;
  UPDATE public.poker_games SET status='cancelled', updated_at=now() WHERE id=_game_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_request_refund TO authenticated;

CREATE OR REPLACE FUNCTION public.poker_start_next_hand(_game_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT public.has_role(auth.uid(),'admin') THEN
    IF auth.uid() NOT IN (SELECT user_id FROM public.poker_players WHERE game_id=_game_id LIMIT 1) THEN
      RAISE EXCEPTION 'Accès refusé';
    END IF;
  END IF;
  UPDATE public.poker_games SET phase='preflop', pot=0, community_cards='{}', updated_at=now() WHERE id=_game_id AND phase='between_hands';
  PERFORM public._poker_deal_hand(_game_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_start_next_hand TO authenticated;

-- ── 6. Update game_online_count to include poker ──────────────────────────
CREATE OR REPLACE FUNCTION public.game_online_count(_slug text)
RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT CASE _slug
    WHEN 'ludo'     THEN (SELECT count(*) FROM public.ludo_games     WHERE status IN ('waiting','playing'))
    WHEN 'domino'   THEN (SELECT count(*) FROM public.domino_games   WHERE status IN ('waiting','playing'))
    WHEN 'fanorona' THEN (SELECT count(*) FROM public.fanorona_games WHERE status IN ('waiting','playing'))
    WHEN 'chess'    THEN (SELECT count(*) FROM public.chess_games    WHERE status IN ('waiting','playing'))
    WHEN 'rami'     THEN (SELECT count(*) FROM public.rami_games     WHERE status IN ('waiting','playing'))
    WHEN 'poker'    THEN (SELECT count(*) FROM public.poker_games    WHERE status IN ('waiting','playing'))
    ELSE 0
  END;
$$;
GRANT EXECUTE ON FUNCTION public.game_online_count(text) TO authenticated, anon;
