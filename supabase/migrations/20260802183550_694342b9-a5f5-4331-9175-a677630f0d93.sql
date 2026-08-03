-- ══════════════════════════════════════════════════════════════════
-- POKER v2 : réglages de table, min-raise, side pots, split, rake cap
-- ══════════════════════════════════════════════════════════════════

ALTER TABLE public.poker_games
  ADD COLUMN IF NOT EXISTS small_blind numeric NOT NULL DEFAULT 10,
  ADD COLUMN IF NOT EXISTS big_blind   numeric NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS min_buy_in  numeric NOT NULL DEFAULT 1000,
  ADD COLUMN IF NOT EXISTS max_buy_in  numeric NOT NULL DEFAULT 10000,
  ADD COLUMN IF NOT EXISTS rake_cap    numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS side_pots   jsonb   NOT NULL DEFAULT '[]'::jsonb;

-- ── Distribution d'une main ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public._poker_deal_hand(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  st jsonb; deck int[]; hand_n int;
  dealer_seat int; sb_seat int; bb_seat int; first_seat int;
  seats int[]; n_active int; dealer_idx int;
  sb_amt numeric; bb_amt numeric;
  deal_pos int := 1; i int; seat int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;
  st := g.state;
  hand_n := COALESCE(g.hand_number,0) + 1;

  UPDATE public.poker_players
     SET bet_round=0, total_bet=0, hole_cards='{}', last_action=NULL, hand_result=NULL, status='playing'
   WHERE game_id=_gid AND status NOT IN ('out','finished') AND chips > 0;
  UPDATE public.poker_players SET status='out' WHERE game_id=_gid AND chips <= 0 AND status <> 'waiting';

  SELECT array_agg(seat ORDER BY seat) INTO seats
    FROM public.poker_players WHERE game_id=_gid AND status='playing';
  n_active := COALESCE(array_length(seats,1),0);
  IF n_active < 2 THEN RETURN; END IF;

  -- bouton : premier siège actif après le précédent bouton
  dealer_seat := COALESCE((st->>'dealer_seat')::int, -1);
  SELECT s INTO dealer_seat FROM unnest(seats) s WHERE s > dealer_seat ORDER BY s LIMIT 1;
  IF dealer_seat IS NULL THEN dealer_seat := seats[1]; END IF;
  dealer_idx := array_position(seats, dealer_seat);

  IF n_active = 2 THEN
    sb_seat := dealer_seat;
    bb_seat := seats[(dealer_idx % n_active) + 1];
    first_seat := sb_seat;
  ELSE
    sb_seat := seats[(dealer_idx % n_active) + 1];
    bb_seat := seats[((dealer_idx + 1) % n_active) + 1];
    first_seat := seats[((dealer_idx + 2) % n_active) + 1];
  END IF;

  deck := public._poker_new_deck();

  -- blindes (plafonnées au tapis → all-in)
  SELECT LEAST(g.small_blind, chips) INTO sb_amt FROM public.poker_players WHERE game_id=_gid AND seat=sb_seat;
  SELECT LEAST(g.big_blind,   chips) INTO bb_amt FROM public.poker_players WHERE game_id=_gid AND seat=bb_seat;

  UPDATE public.poker_players
     SET chips=chips-sb_amt, bet_round=sb_amt, total_bet=sb_amt,
         status=CASE WHEN chips-sb_amt <= 0 THEN 'all_in' ELSE status END
   WHERE game_id=_gid AND seat=sb_seat;
  UPDATE public.poker_players
     SET chips=chips-bb_amt, bet_round=bb_amt, total_bet=bb_amt,
         status=CASE WHEN chips-bb_amt <= 0 THEN 'all_in' ELSE status END
   WHERE game_id=_gid AND seat=bb_seat;

  -- 2 cartes par joueur
  FOR i IN 1..2 LOOP
    FOREACH seat IN ARRAY seats LOOP
      UPDATE public.poker_players SET hole_cards = hole_cards || deck[deal_pos]
       WHERE game_id=_gid AND seat=seat;
      deal_pos := deal_pos + 1;
    END LOOP;
  END LOOP;
  deck := deck[deal_pos:];

  UPDATE public.poker_games SET
    state = jsonb_build_object(
      'hand_number', hand_n, 'dealer_seat', dealer_seat,
      'sb_seat', sb_seat, 'bb_seat', bb_seat,
      'small_blind', g.small_blind, 'big_blind', g.big_blind,
      'current_bet', GREATEST(sb_amt, bb_amt), 'last_raise', g.big_blind,
      'deck', to_jsonb(deck)),
    phase='preflop', hand_number=hand_n, community_cards='{}', side_pots='[]'::jsonb,
    current_player=(SELECT user_id FROM public.poker_players WHERE game_id=_gid AND seat=first_seat),
    pot = sb_amt + bb_amt,
    turn_deadline = now() + interval '30 seconds',
    updated_at = now()
  WHERE id=_gid;
END;
$$;

-- ── Fin de main : réel payout / main suivante ─────────────────────
CREATE OR REPLACE FUNCTION public._poker_end_hand(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  survivors int; champ uuid;
  gross numeric; rake numeric; net numeric; n_players int;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;

  UPDATE public.poker_players SET status='out' WHERE game_id=_gid AND chips <= 0 AND status <> 'waiting';
  SELECT count(*) INTO survivors FROM public.poker_players WHERE game_id=_gid AND chips > 0;

  IF survivors <= 1 THEN
    SELECT user_id INTO champ FROM public.poker_players WHERE game_id=_gid AND chips > 0 LIMIT 1;
    IF champ IS NULL THEN
      SELECT user_id INTO champ FROM public.poker_players WHERE game_id=_gid ORDER BY chips DESC LIMIT 1;
    END IF;
    SELECT count(*) INTO n_players FROM public.poker_players WHERE game_id=_gid;
    gross := COALESCE(g.stake,0) * n_players;
    rake  := ROUND(gross * COALESCE(g.commission_pct,10) / 100, 0);
    IF COALESCE(g.rake_cap,0) > 0 THEN rake := LEAST(rake, g.rake_cap); END IF;
    net := gross - rake;

    UPDATE public.poker_players SET status='finished' WHERE game_id=_gid AND status NOT IN ('out');
    UPDATE public.poker_games SET status='finished', phase='finished', winner_id=champ,
      finished_at=now(), current_player=NULL, turn_deadline=NULL, updated_at=now()
    WHERE id=_gid;

    IF net > 0 AND champ IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + net WHERE id = champ;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES(champ,'win',net,_gid,'Victoire Poker');
    END IF;
  ELSE
    UPDATE public.poker_players
       SET status='playing', bet_round=0, total_bet=0, hole_cards='{}', last_action=NULL
     WHERE game_id=_gid AND chips > 0;
    UPDATE public.poker_games SET phase='between_hands', pot=0, community_cards='{}',
      current_player=NULL, turn_deadline=NULL, updated_at=now() WHERE id=_gid;
  END IF;
END;
$$;

-- ── Tous couchés sauf un ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._poker_award(_gid uuid, _winner uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE g public.poker_games%ROWTYPE;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;
  UPDATE public.poker_players SET chips = chips + g.pot WHERE game_id=_gid AND user_id=_winner;
  UPDATE public.poker_games SET phase='showdown', winner_id=_winner, updated_at=now() WHERE id=_gid;
  PERFORM public._poker_end_hand(_gid);
END;
$$;

-- ── Abattage avec pots secondaires ────────────────────────────────
CREATE OR REPLACE FUNCTION public._poker_showdown(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  p record; lvl record;
  prev numeric := 0; pot_amt numeric; best bigint;
  winners uuid[]; share numeric; odd numeric;
  sb_seat int; ordered uuid[]; w uuid;
  pots jsonb := '[]'::jsonb; idx int := 0;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;
  sb_seat := COALESCE((g.state->>'sb_seat')::int, 0);

  -- scores
  FOR p IN SELECT * FROM public.poker_players WHERE game_id=_gid AND status IN ('playing','all_in') LOOP
    UPDATE public.poker_players SET hand_result = jsonb_build_object(
      'score', public._poker_best_score(p.hole_cards, g.community_cards),
      'label', public._poker_hand_label(public._poker_best_score(p.hole_cards, g.community_cards)),
      'cards', p.hole_cards)
    WHERE id = p.id;
  END LOOP;

  -- paliers de mise croissants → pot principal puis pots secondaires
  FOR lvl IN
    SELECT DISTINCT total_bet AS t FROM public.poker_players
     WHERE game_id=_gid AND total_bet > 0 ORDER BY 1
  LOOP
    SELECT COALESCE(sum(LEAST(total_bet, lvl.t) - LEAST(total_bet, prev)), 0) INTO pot_amt
      FROM public.poker_players WHERE game_id=_gid;

    IF pot_amt > 0 THEN
      SELECT max((hand_result->>'score')::bigint) INTO best
        FROM public.poker_players
       WHERE game_id=_gid AND status IN ('playing','all_in') AND total_bet >= lvl.t;

      IF best IS NULL THEN
        -- personne d'éligible (ne devrait pas arriver) : rendre au dernier palier
        prev := lvl.t; CONTINUE;
      END IF;

      -- gagnants ordonnés à partir de la petite blinde (jeton impair)
      SELECT array_agg(user_id ORDER BY ((seat - sb_seat) + 100) % 100) INTO winners
        FROM public.poker_players
       WHERE game_id=_gid AND status IN ('playing','all_in')
         AND total_bet >= lvl.t AND (hand_result->>'score')::bigint = best;

      share := floor(pot_amt / array_length(winners,1));
      odd   := pot_amt - share * array_length(winners,1);

      FOREACH w IN ARRAY winners LOOP
        UPDATE public.poker_players SET chips = chips + share WHERE game_id=_gid AND user_id=w;
      END LOOP;
      IF odd > 0 THEN
        UPDATE public.poker_players SET chips = chips + odd WHERE game_id=_gid AND user_id=winners[1];
      END IF;

      pots := pots || jsonb_build_object('index', idx, 'amount', pot_amt, 'winners', to_jsonb(winners));
      idx := idx + 1;
    END IF;
    prev := lvl.t;
  END LOOP;

  SELECT user_id INTO w FROM public.poker_players
   WHERE game_id=_gid AND status IN ('playing','all_in')
   ORDER BY (hand_result->>'score')::bigint DESC NULLS LAST LIMIT 1;

  UPDATE public.poker_games SET phase='showdown', side_pots=pots, winner_id=w, updated_at=now() WHERE id=_gid;
  PERFORM public._poker_end_hand(_gid);
END;
$$;

-- ── Passage à la street suivante (avec run-out si plus d'enchères) ─
CREATE OR REPLACE FUNCTION public._poker_next_street(_gid uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  g public.poker_games%ROWTYPE;
  deck int[]; community int[]; new_phase text;
  in_hand int; can_bet int; only_player uuid;
  dealer_seat int; first_seat int; first_user uuid;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_gid FOR UPDATE;

  SELECT count(*), (array_agg(user_id))[1] INTO in_hand, only_player
    FROM public.poker_players WHERE game_id=_gid AND status IN ('playing','all_in');
  IF in_hand <= 1 THEN
    PERFORM public._poker_award(_gid, only_player);
    RETURN;
  END IF;

  UPDATE public.poker_players SET bet_round=0, last_action=NULL WHERE game_id=_gid AND status='playing';

  deck := ARRAY(SELECT jsonb_array_elements_text(g.state->'deck')::int);
  community := g.community_cards;

  CASE g.phase
    WHEN 'preflop' THEN new_phase:='flop'; community := community||deck[1]||deck[2]||deck[3]; deck := deck[4:];
    WHEN 'flop'    THEN new_phase:='turn'; community := community||deck[1]; deck := deck[2:];
    WHEN 'turn'    THEN new_phase:='river'; community := community||deck[1]; deck := deck[2:];
    WHEN 'river'   THEN PERFORM public._poker_showdown(_gid); RETURN;
    ELSE RETURN;
  END CASE;

  dealer_seat := COALESCE((g.state->>'dealer_seat')::int, -1);
  SELECT seat, user_id INTO first_seat, first_user FROM public.poker_players
   WHERE game_id=_gid AND status='playing' AND seat > dealer_seat ORDER BY seat LIMIT 1;
  IF first_seat IS NULL THEN
    SELECT seat, user_id INTO first_seat, first_user FROM public.poker_players
     WHERE game_id=_gid AND status='playing' ORDER BY seat LIMIT 1;
  END IF;

  UPDATE public.poker_games SET
    phase=new_phase, community_cards=community,
    state = state || jsonb_build_object('deck', to_jsonb(deck), 'current_bet', 0,
                                        'last_raise', (state->>'big_blind')::numeric),
    current_player=first_user,
    turn_deadline = now() + interval '30 seconds',
    updated_at=now()
  WHERE id=_gid;

  -- plus personne ne peut miser (tous à tapis) → dérouler le board
  SELECT count(*) INTO can_bet FROM public.poker_players WHERE game_id=_gid AND status='playing';
  IF can_bet < 2 THEN
    UPDATE public.poker_games SET current_player=NULL, turn_deadline=NULL WHERE id=_gid;
    PERFORM public._poker_next_street(_gid);
  END IF;
END;
$$;

-- ── Action joueur (validations strictes) ──────────────────────────
CREATE OR REPLACE FUNCTION public.poker_action(_game_id uuid, _action text, _amount numeric DEFAULT 0)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  g public.poker_games%ROWTYPE;
  me public.poker_players%ROWTYPE;
  cur_bet numeric; last_raise numeric; bb numeric;
  call_amt numeric; add_chips numeric; new_total numeric;
  min_total numeric; in_hand int; next_seat int; next_user uuid;
BEGIN
  SELECT * INTO g FROM public.poker_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie non active'; END IF;
  IF g.current_player IS DISTINCT FROM v_uid THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;

  SELECT * INTO me FROM public.poker_players WHERE game_id=_game_id AND user_id=v_uid;
  IF me.status <> 'playing' THEN RAISE EXCEPTION 'Vous ne pouvez plus agir'; END IF;

  cur_bet    := COALESCE((g.state->>'current_bet')::numeric, 0);
  bb         := COALESCE((g.state->>'big_blind')::numeric, g.big_blind);
  last_raise := GREATEST(COALESCE((g.state->>'last_raise')::numeric, bb), bb);
  call_amt   := GREATEST(cur_bet - me.bet_round, 0);

  IF _action = 'fold' THEN
    UPDATE public.poker_players SET status='folded', last_action='fold'
     WHERE game_id=_game_id AND user_id=v_uid;

  ELSIF _action = 'check' THEN
    IF call_amt > 0 THEN RAISE EXCEPTION 'Vous devez suivre, relancer ou vous coucher'; END IF;
    UPDATE public.poker_players SET last_action='check' WHERE game_id=_game_id AND user_id=v_uid;

  ELSIF _action = 'call' THEN
    add_chips := LEAST(call_amt, me.chips);
    IF add_chips <= 0 THEN RAISE EXCEPTION 'Rien à suivre'; END IF;
    UPDATE public.poker_players
       SET chips=chips-add_chips, bet_round=bet_round+add_chips, total_bet=total_bet+add_chips,
           last_action='call', status=CASE WHEN chips-add_chips <= 0 THEN 'all_in' ELSE status END
     WHERE game_id=_game_id AND user_id=v_uid;
    UPDATE public.poker_games SET pot=pot+add_chips, updated_at=now() WHERE id=_game_id;

  ELSIF _action IN ('raise','bet','allin') THEN
    IF _action = 'allin' THEN
      new_total := me.bet_round + me.chips;
    ELSE
      new_total := _amount;
      min_total := cur_bet + last_raise;
      IF new_total > me.bet_round + me.chips THEN RAISE EXCEPTION 'Jetons insuffisants'; END IF;
      IF new_total <= cur_bet THEN RAISE EXCEPTION 'Relance insuffisante'; END IF;
      IF new_total < min_total AND new_total < me.bet_round + me.chips THEN
        RAISE EXCEPTION 'Relance minimale : % jetons', min_total;
      END IF;
    END IF;

    add_chips := new_total - me.bet_round;
    IF add_chips <= 0 THEN RAISE EXCEPTION 'Montant invalide'; END IF;

    UPDATE public.poker_players
       SET chips=chips-add_chips, bet_round=new_total, total_bet=total_bet+add_chips,
           last_action=CASE WHEN _action='allin' THEN 'allin' ELSE _action END,
           status=CASE WHEN chips-add_chips <= 0 THEN 'all_in' ELSE status END
     WHERE game_id=_game_id AND user_id=v_uid;
    UPDATE public.poker_games SET pot=pot+add_chips, updated_at=now() WHERE id=_game_id;

    IF new_total > cur_bet THEN
      UPDATE public.poker_games SET state = state || jsonb_build_object(
        'current_bet', new_total,
        'last_raise', GREATEST(new_total - cur_bet, last_raise))
      WHERE id=_game_id;
      -- une relance complète rouvre les enchères ; un tapis court ne les rouvre pas
      IF new_total - cur_bet >= last_raise THEN
        UPDATE public.poker_players SET last_action=NULL
         WHERE game_id=_game_id AND user_id <> v_uid AND status='playing';
      END IF;
    END IF;
  ELSE
    RAISE EXCEPTION 'Action inconnue: %', _action;
  END IF;

  SELECT count(*) INTO in_hand FROM public.poker_players
   WHERE game_id=_game_id AND status IN ('playing','all_in');

  IF in_hand <= 1 OR public._poker_round_done(_game_id)
     OR NOT EXISTS (SELECT 1 FROM public.poker_players WHERE game_id=_game_id AND status='playing') THEN
    PERFORM public._poker_next_street(_game_id);
    RETURN;
  END IF;

  next_seat := public._poker_next_player(_game_id, me.seat);
  SELECT user_id INTO next_user FROM public.poker_players WHERE game_id=_game_id AND seat=next_seat;
  UPDATE public.poker_games SET current_player=next_user,
    turn_deadline=now()+interval '30 seconds', updated_at=now() WHERE id=_game_id;
END;
$$;

-- ── Création de table avec réglages ───────────────────────────────
CREATE OR REPLACE FUNCTION public.poker_create(
  _stake numeric, _max int DEFAULT 6, _private boolean DEFAULT false, _commission numeric DEFAULT 10,
  _small_blind numeric DEFAULT NULL, _big_blind numeric DEFAULT NULL,
  _buy_in numeric DEFAULT NULL, _rake_cap numeric DEFAULT 0
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_gid uuid; v_code text;
  v_bb numeric; v_sb numeric; v_chips numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max < 2 OR _max > 9 THEN RAISE EXCEPTION 'Nombre de sièges invalide (2-9)'; END IF;

  v_chips := COALESCE(NULLIF(_buy_in,0), GREATEST(_stake * 100, 10000));
  v_bb := COALESCE(NULLIF(_big_blind,0), GREATEST(ROUND(v_chips / 100), 20));
  v_sb := COALESCE(NULLIF(_small_blind,0), GREATEST(ROUND(v_bb / 2), 1));
  IF v_sb > v_bb THEN RAISE EXCEPTION 'La petite blinde doit être ≤ à la grosse blinde'; END IF;
  IF v_chips < v_bb * 10 THEN RAISE EXCEPTION 'La cave doit valoir au moins 10 grosses blindes'; END IF;

  IF _stake > 0 AND (SELECT balance_ar FROM public.profiles WHERE id=v_uid) < _stake THEN
    RAISE EXCEPTION 'Solde insuffisant';
  END IF;
  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar=balance_ar-_stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id,type,amount,note) VALUES(v_uid,'stake',-_stake,'Mise Poker');
  END IF;

  IF _private THEN v_code := upper(substring(md5(random()::text),1,6)); END IF;

  INSERT INTO public.poker_games(stake,commission_pct,max_players,is_private,room_code,created_by,state,
                                 small_blind,big_blind,min_buy_in,max_buy_in,rake_cap)
  VALUES(_stake,_commission,_max,_private,v_code,v_uid,'{}'::jsonb,
         v_sb,v_bb,v_chips,v_chips,COALESCE(_rake_cap,0))
  RETURNING id INTO v_gid;

  INSERT INTO public.poker_players(game_id,user_id,seat,chips,status,is_ready)
  VALUES(v_gid,v_uid,0,v_chips,'waiting',false);

  RETURN v_gid;
END;
$$;
GRANT EXECUTE ON FUNCTION public.poker_create(numeric,int,boolean,numeric,numeric,numeric,numeric,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.poker_action(uuid,text,numeric) TO authenticated;