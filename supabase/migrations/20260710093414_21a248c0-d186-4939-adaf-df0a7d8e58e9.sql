-- Tournoi : bracket manuel, auto-avancement, batch, anti-même-pool
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS auto_advance_rounds boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public._tournament_advance_round_core(_tid uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE
  trn record; rec record;
  v_qual_per int; v_next_round int; v_count int;
  v_ids uuid[] := '{}'; v_src uuid[] := '{}';
  v_ordered_ids uuid[]; v_ordered_src uuid[];
  i int; j int; tmp_uid uuid; tmp_src uuid;
BEGIN
  SELECT * INTO trn FROM public.tournaments WHERE id = _tid FOR UPDATE;
  IF trn IS NULL THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;
  IF trn.status <> 'running' THEN RAISE EXCEPTION 'Tournoi non en cours'; END IF;
  IF EXISTS (SELECT 1 FROM public.tournament_matches WHERE tournament_id=_tid AND round=trn.current_round AND status NOT IN ('finished','forfeit','cancelled') AND is_bye=false) THEN
    RAISE EXCEPTION 'Des matchs du round actuel ne sont pas encore terminés';
  END IF;
  v_qual_per := GREATEST(COALESCE(trn.qualifiers_per_table, 2), 1);
  FOR rec IN SELECT m.id AS mid, m.player_ids, m.winner_id, m.match_rankings, m.is_bye, array_length(m.player_ids,1) AS n
    FROM public.tournament_matches m WHERE m.tournament_id=_tid AND m.round=trn.current_round AND m.status IN ('finished','forfeit')
  LOOP
    IF rec.is_bye OR COALESCE(rec.n,2) <= 2 THEN
      IF rec.winner_id IS NOT NULL THEN v_ids := v_ids || rec.winner_id; v_src := v_src || rec.mid; END IF;
    ELSE
      IF rec.match_rankings IS NOT NULL AND rec.match_rankings <> '{}'::jsonb THEN
        FOR i IN 1..LEAST(v_qual_per, rec.n - 1) LOOP
          IF rec.match_rankings ? i::text THEN v_ids := v_ids || (rec.match_rankings ->> i::text)::uuid; v_src := v_src || rec.mid; END IF;
        END LOOP;
      ELSIF rec.winner_id IS NOT NULL THEN v_ids := v_ids || rec.winner_id; v_src := v_src || rec.mid; END IF;
    END IF;
  END LOOP;
  v_count := COALESCE(array_length(v_ids,1), 0);
  IF v_count <= 1 THEN
    UPDATE public.tournaments SET status='finished', winner_id=v_ids[1], finished_at=now() WHERE id=_tid;
    IF v_ids[1] IS NOT NULL THEN
      UPDATE public.profiles SET balance_ar = balance_ar + COALESCE(trn.prize_pool,0) WHERE id = v_ids[1];
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_ids[1],'tournament_win',COALESCE(trn.prize_pool,0),_tid,'Gains tournoi '||COALESCE(trn.game_slug,'multi'));
    END IF;
    RETURN jsonb_build_object('ok',true,'finished',true,'winner_id',v_ids[1]);
  END IF;
  WITH shuffled AS (SELECT unnest(v_ids) AS uid, unnest(v_src) AS src, random() AS r),
       grouped AS (SELECT uid, src, row_number() OVER (PARTITION BY src ORDER BY r) AS grp FROM shuffled)
  SELECT array_agg(uid ORDER BY grp, r), array_agg(src ORDER BY grp, r)
    INTO v_ordered_ids, v_ordered_src FROM grouped;
  i := 1;
  WHILE i < v_count LOOP
    IF v_ordered_src[i] = v_ordered_src[i+1] THEN
      j := i + 2;
      WHILE j <= v_count LOOP
        IF v_ordered_src[j] <> v_ordered_src[i] THEN
          tmp_uid := v_ordered_ids[i+1]; tmp_src := v_ordered_src[i+1];
          v_ordered_ids[i+1] := v_ordered_ids[j]; v_ordered_src[i+1] := v_ordered_src[j];
          v_ordered_ids[j] := tmp_uid; v_ordered_src[j] := tmp_src;
          EXIT;
        END IF;
        j := j + 1;
      END LOOP;
    END IF;
    i := i + 2;
  END LOOP;
  v_next_round := trn.current_round + 1;
  UPDATE public.tournaments SET current_round = v_next_round WHERE id = _tid;
  i := 1;
  WHILE i + 1 <= v_count LOOP
    INSERT INTO public.tournament_matches(tournament_id,round,player_ids,status,is_bye)
      VALUES (_tid, v_next_round, ARRAY[v_ordered_ids[i], v_ordered_ids[i+1]], 'pending', false);
    i := i + 2;
  END LOOP;
  IF v_count % 2 = 1 THEN
    INSERT INTO public.tournament_matches(tournament_id,round,player_ids,status,is_bye,winner_id,finished_at)
      VALUES (_tid, v_next_round, ARRAY[v_ordered_ids[v_count]], 'finished', true, v_ordered_ids[v_count], now());
  END IF;
  RETURN jsonb_build_object('ok',true,'finished',false,'next_round',v_next_round,'qualifiers',v_count);
END; $$;

CREATE OR REPLACE FUNCTION public.admin_advance_tournament_round(_tid uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = auth.uid();
  IF NOT COALESCE(v_is_admin,false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  PERFORM public._tournament_advance_round_core(_tid);
END; $$;
GRANT EXECUTE ON FUNCTION public.admin_advance_tournament_round(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_tournament_auto_advance(_tid uuid, _enabled boolean)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE v_uid uuid := auth.uid(); v_is_admin boolean;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin,false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;
  UPDATE public.tournaments SET auto_advance_rounds = _enabled WHERE id = _tid;
  INSERT INTO public.admin_logs(admin_id,action,target_id,new_value)
    VALUES (v_uid,'tournament_set_auto_advance',_tid,jsonb_build_object('enabled',_enabled));
  RETURN jsonb_build_object('ok',true,'auto_advance_rounds',_enabled);
END; $$;
GRANT EXECUTE ON FUNCTION public.admin_set_tournament_auto_advance(uuid, boolean) TO authenticated;

CREATE OR REPLACE FUNCTION public._trg_tournament_match_auto_advance()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public','extensions' AS $$
DECLARE trn record; v_remaining int;
BEGIN
  IF NEW.status NOT IN ('finished','forfeit','cancelled') THEN RETURN NEW; END IF;
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF NEW.is_bye THEN RETURN NEW; END IF;
  SELECT * INTO trn FROM public.tournaments WHERE id = NEW.tournament_id;
  IF trn IS NULL OR trn.status <> 'running' OR NOT COALESCE(trn.auto_advance_rounds,false) THEN RETURN NEW; END IF;
  IF NEW.round <> trn.current_round THEN RETURN NEW; END IF;
  SELECT count(*) INTO v_remaining FROM public.tournament_matches
    WHERE tournament_id=NEW.tournament_id AND round=trn.current_round
      AND status NOT IN ('finished','forfeit','cancelled') AND is_bye=false;
  IF v_remaining = 0 THEN PERFORM public._tournament_advance_round_core(NEW.tournament_id); END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_tournament_match_auto_advance ON public.tournament_matches;
CREATE TRIGGER trg_tournament_match_auto_advance
  AFTER UPDATE ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._trg_tournament_match_auto_advance();

-- Colonnes tournament_matches
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS afk_reports    jsonb NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS extended_count int   NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS match_index    int   NOT NULL DEFAULT 0;

-- game_configs / tournaments
ALTER TABLE public.game_configs
  ADD COLUMN IF NOT EXISTS tournament_join_timeout_secs int NOT NULL DEFAULT 240;
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS game_rules jsonb NOT NULL DEFAULT '{}';

-- app_settings: legal
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS legal_terms text,
  ADD COLUMN IF NOT EXISTS legal_privacy text;

-- check_pseudo_availability
CREATE OR REPLACE FUNCTION public.check_pseudo_availability(_pseudo text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT NOT EXISTS(SELECT 1 FROM public.profiles WHERE lower(pseudo) = lower(trim(_pseudo)))
$$;
GRANT EXECUTE ON FUNCTION public.check_pseudo_availability(text) TO anon, authenticated;

-- Domino: égalité pips = pas de gagnant désigné (revert to null)
CREATE OR REPLACE FUNCTION public._domino_lowest_pip_slot(_game_id uuid, _state jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE p record; cur_sum integer; best_sum integer := 2147483647; best_slot integer := NULL; tie_count integer := 0;
BEGIN
  FOR p IN SELECT slot FROM public.domino_participants WHERE game_id=_game_id AND forfeited=false ORDER BY slot LOOP
    cur_sum := public._domino_hand_pips(COALESCE(_state->'hands'->p.slot::text, '[]'::jsonb));
    IF cur_sum < best_sum THEN best_sum := cur_sum; best_slot := p.slot; tie_count := 1;
    ELSIF cur_sum = best_sum THEN tie_count := tie_count + 1; END IF;
  END LOOP;
  IF tie_count > 1 THEN RETURN NULL; END IF;
  RETURN best_slot;
END; $$;