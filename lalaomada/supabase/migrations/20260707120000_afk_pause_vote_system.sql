-- ============================================================
-- Système de vote pour la pause AFK — tous les jeux
--
-- Avant : 1 joueur actif pouvait déclencher la pause seul
-- Après : majorité requise  CEIL(nb_actifs_non_afk / 2)
--         → 2 joueurs : 1 vote (inchangé)
--         → 3 joueurs : 2 votes
--         → 4 joueurs : 2 votes
--
-- afk_warning JSONB inclut maintenant { votes: [], votes_needed: N }
-- game_request_afk_pause enregistre chaque vote et ne démarre
-- la pause que lorsque le seuil est atteint.
-- ============================================================

-- ── 1. DROP de la version void (impossible de changer le type de retour
--       avec CREATE OR REPLACE en PostgreSQL)
DROP FUNCTION IF EXISTS public.game_request_afk_pause(TEXT, UUID);

-- ── 2. Trigger non-Ludo : ajouter votes:[] à afk_warning
CREATE OR REPLACE FUNCTION public._trg_afk_warning_non_ludo()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_max   INT;
  v_slug  TEXT;
  v_key   TEXT;
  v_count INT;
  v_name  TEXT;
BEGIN
  IF NEW.status <> 'playing' OR COALESCE(NEW.paused, FALSE) THEN RETURN NEW; END IF;
  IF NEW.turn_skips IS NOT DISTINCT FROM OLD.turn_skips THEN RETURN NEW; END IF;

  v_slug := CASE TG_TABLE_NAME
    WHEN 'chess_games'    THEN 'chess'
    WHEN 'fanorona_games' THEN 'fanorona'
    WHEN 'domino_games'   THEN 'domino'
    WHEN 'rami_games'     THEN 'rami'
    WHEN 'poker_games'    THEN 'poker'
    ELSE NULL
  END;
  IF v_slug IS NULL THEN RETURN NEW; END IF;

  SELECT max_turn_skips INTO v_max FROM public.game_configs WHERE slug = v_slug;
  IF v_max IS NULL OR v_max <= 1 THEN RETURN NEW; END IF;

  FOR v_key, v_count IN
    SELECT key, value::int FROM jsonb_each_text(NEW.turn_skips)
  LOOP
    IF v_count = v_max - 1 THEN
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_key::uuid;
      NEW.afk_warning := jsonb_build_object(
        'uid',          v_key,
        'name',         COALESCE(v_name, 'Joueur'),
        'skips',        v_count,
        'max',          v_max,
        'votes',        '[]'::jsonb,
        'votes_needed', 0,
        'ts',           extract(epoch from now())::bigint
      );
      RETURN NEW;
    END IF;
  END LOOP;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_afk_warning ON public.chess_games;
CREATE TRIGGER trg_afk_warning
  BEFORE UPDATE ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();

DROP TRIGGER IF EXISTS trg_afk_warning ON public.fanorona_games;
CREATE TRIGGER trg_afk_warning
  BEFORE UPDATE ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();

DROP TRIGGER IF EXISTS trg_afk_warning ON public.domino_games;
CREATE TRIGGER trg_afk_warning
  BEFORE UPDATE ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();

DROP TRIGGER IF EXISTS trg_afk_warning ON public.rami_games;
CREATE TRIGGER trg_afk_warning
  BEFORE UPDATE ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();

DROP TRIGGER IF EXISTS trg_afk_warning ON public.poker_games;
CREATE TRIGGER trg_afk_warning
  BEFORE UPDATE ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._trg_afk_warning_non_ludo();

-- ── 3. _ludo_check_afk : ajouter votes:[] + votes_needed:0
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t1      int;
  v_t2      int;
  v_max1    int;
  v_max2    int;
  v_enabled boolean;
  v_uid     uuid;
  v_isbot   boolean;
  v_name    text;
  v_winner  uuid;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max
    INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;

  SELECT afk_t1, afk_t2, user_id, is_bot, display_name
    INTO v_t1, v_t2, v_uid, v_isbot, v_name
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  -- Seuil forfait (inchangé)
  IF v_t1 >= COALESCE(v_max1, 5) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants SET forfeited = TRUE WHERE game_id = _game_id AND slot = _slot;
    UPDATE public.ludo_games
       SET afk_warning = NULL, afk_pause_for = NULL, afk_pause_name = NULL
     WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
              'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');
    v_winner := public._ludo_check_last_standing(_game_id);
    IF v_winner IS NOT NULL THEN PERFORM public.finish_game(_game_id, v_winner); END IF;
    RETURN;
  END IF;

  -- Avertissement T1 uniquement (avec votes:[] et votes_needed:0)
  IF v_t1 = COALESCE(v_max1, 5) - 1 THEN
    UPDATE public.ludo_games
       SET afk_warning = jsonb_build_object(
             'uid',          v_uid,
             'name',         COALESCE(v_name, 'Joueur'),
             'slot',         _slot,
             't1',           v_t1,
             't1_max',       COALESCE(v_max1, 5),
             'votes',        '[]'::jsonb,
             'votes_needed', 0,
             'ts',           extract(epoch from now())::bigint
           )
     WHERE id = _game_id
       AND paused = FALSE
       AND (afk_warning IS NULL OR (afk_warning->>'uid')::uuid <> v_uid);
  END IF;
END $$;

-- ── 4. Nouvelle game_request_afk_pause retournant JSONB (vote system)
CREATE OR REPLACE FUNCTION public.game_request_afk_pause(_slug TEXT, _game_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid             UUID    := auth.uid();
  v_status          TEXT;
  v_paused          BOOLEAN;
  v_warning         JSONB;
  v_afk_uid         UUID;
  v_is_participant  BOOLEAN := FALSE;
  v_remaining_s     INT;
  v_votes           JSONB;
  v_votes_needed    INT;
  v_active_count    INT;
  v_updated_warning JSONB;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  -- Lire l'état de la partie selon le slug
  CASE _slug
    WHEN 'ludo' THEN
      SELECT status, paused, afk_warning
        INTO v_status, v_paused, v_warning
        FROM public.ludo_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.ludo_participants
         WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE AND forfeited = FALSE
      ) INTO v_is_participant;

    WHEN 'chess' THEN
      SELECT status, paused, afk_warning,
             CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now()))))
        INTO v_status, v_paused, v_warning, v_remaining_s
        FROM public.chess_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.chess_games WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid)
      ) INTO v_is_participant;

    WHEN 'fanorona' THEN
      SELECT status, paused, afk_warning,
             CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now()))))
        INTO v_status, v_paused, v_warning, v_remaining_s
        FROM public.fanorona_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.fanorona_participants
         WHERE game_id = _game_id AND user_id = v_uid AND forfeited = FALSE
      ) INTO v_is_participant;

    WHEN 'domino' THEN
      SELECT status, paused, afk_warning,
             CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now()))))
        INTO v_status, v_paused, v_warning, v_remaining_s
        FROM public.domino_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.domino_participants
         WHERE game_id = _game_id AND user_id = v_uid AND forfeited = FALSE
      ) INTO v_is_participant;

    WHEN 'rami' THEN
      SELECT status, paused, afk_warning,
             CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now()))))
        INTO v_status, v_paused, v_warning, v_remaining_s
        FROM public.rami_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.rami_participants
         WHERE game_id = _game_id AND user_id = v_uid AND forfeited = FALSE
      ) INTO v_is_participant;

    WHEN 'poker' THEN
      SELECT status, paused, afk_warning,
             CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now()))))
        INTO v_status, v_paused, v_warning, v_remaining_s
        FROM public.poker_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.poker_players WHERE game_id = _game_id AND user_id = v_uid
      ) INTO v_is_participant;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  -- Gardes de base
  IF v_status <> 'playing'     THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant      THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;
  IF v_warning IS NULL         THEN RAISE EXCEPTION 'aucun joueur en état AFK critique'; END IF;

  v_afk_uid := (v_warning->>'uid')::uuid;
  IF v_uid = v_afk_uid THEN
    RAISE EXCEPTION 'vous ne pouvez pas déclencher votre propre pause AFK';
  END IF;

  -- Votes courants
  v_votes := COALESCE(v_warning->'votes', '[]'::jsonb);

  -- Déjà voté ?
  IF v_votes @> to_jsonb(ARRAY[v_uid::text]) THEN
    RETURN jsonb_build_object('status', 'already_voted');
  END IF;

  -- Ajouter le vote
  v_votes := v_votes || to_jsonb(ARRAY[v_uid::text]);

  -- Compter les joueurs actifs non-AFK
  CASE _slug
    WHEN 'ludo' THEN
      SELECT COUNT(*) INTO v_active_count FROM public.ludo_participants
       WHERE game_id = _game_id AND NOT is_bot AND NOT forfeited AND user_id != v_afk_uid;
    WHEN 'chess' THEN
      v_active_count := 1;
    WHEN 'fanorona' THEN
      SELECT COUNT(*) INTO v_active_count FROM public.fanorona_participants
       WHERE game_id = _game_id AND NOT forfeited AND user_id != v_afk_uid;
    WHEN 'domino' THEN
      SELECT COUNT(*) INTO v_active_count FROM public.domino_participants
       WHERE game_id = _game_id AND NOT forfeited AND user_id != v_afk_uid;
    WHEN 'rami' THEN
      SELECT COUNT(*) INTO v_active_count FROM public.rami_participants
       WHERE game_id = _game_id AND NOT forfeited AND user_id != v_afk_uid;
    WHEN 'poker' THEN
      SELECT COUNT(*) INTO v_active_count FROM public.poker_players
       WHERE game_id = _game_id AND user_id != v_afk_uid;
  END CASE;

  -- CEIL(actifs / 2), minimum 1
  v_votes_needed := GREATEST(1, CEIL(v_active_count / 2.0)::int);

  -- Seuil atteint → démarrer la pause
  IF jsonb_array_length(v_votes) >= v_votes_needed THEN
    CASE _slug
      WHEN 'ludo' THEN
        UPDATE public.ludo_games
           SET paused        = TRUE,
               pause_deadline = now() + interval '3 minutes',
               afk_pause_for  = v_afk_uid,
               afk_pause_name = v_warning->>'name',
               afk_warning    = NULL,
               state = jsonb_set(state, '{turn_started_at}',
                         to_jsonb((now() + interval '1 hour')::text), true)
         WHERE id = _game_id;

      WHEN 'chess' THEN
        UPDATE public.chess_games
           SET paused                  = TRUE,
               pause_deadline          = now() + interval '3 minutes',
               paused_turn_remaining_s = COALESCE(v_remaining_s, 30),
               turn_deadline           = NULL,
               afk_pause_for           = v_afk_uid,
               afk_pause_name          = v_warning->>'name',
               afk_warning             = NULL
         WHERE id = _game_id;

      WHEN 'fanorona' THEN
        UPDATE public.fanorona_games
           SET paused                  = TRUE,
               pause_deadline          = now() + interval '3 minutes',
               paused_turn_remaining_s = COALESCE(v_remaining_s, 30),
               turn_deadline           = NULL,
               afk_pause_for           = v_afk_uid,
               afk_pause_name          = v_warning->>'name',
               afk_warning             = NULL
         WHERE id = _game_id;

      WHEN 'domino' THEN
        UPDATE public.domino_games
           SET paused                  = TRUE,
               pause_deadline          = now() + interval '3 minutes',
               paused_turn_remaining_s = COALESCE(v_remaining_s, 30),
               turn_deadline           = NULL,
               afk_pause_for           = v_afk_uid,
               afk_pause_name          = v_warning->>'name',
               afk_warning             = NULL
         WHERE id = _game_id;

      WHEN 'rami' THEN
        UPDATE public.rami_games
           SET paused                  = TRUE,
               pause_deadline          = now() + interval '3 minutes',
               paused_turn_remaining_s = COALESCE(v_remaining_s, 30),
               turn_deadline           = NULL,
               afk_pause_for           = v_afk_uid,
               afk_pause_name          = v_warning->>'name',
               afk_warning             = NULL
         WHERE id = _game_id;

      WHEN 'poker' THEN
        UPDATE public.poker_games
           SET paused                  = TRUE,
               pause_deadline          = now() + interval '3 minutes',
               paused_turn_remaining_s = COALESCE(v_remaining_s, 30),
               turn_deadline           = NULL,
               afk_pause_for           = v_afk_uid,
               afk_pause_name          = v_warning->>'name',
               afk_warning             = NULL
         WHERE id = _game_id;
    END CASE;

    RETURN jsonb_build_object('status', 'paused');

  ELSE
    -- Seuil non atteint : enregistrer le vote + votes_needed dans afk_warning
    -- votes_needed est mémorisé pour que l'UI n'ait pas à le recalculer
    v_updated_warning := v_warning
      || jsonb_build_object('votes', v_votes, 'votes_needed', v_votes_needed);

    CASE _slug
      WHEN 'ludo'     THEN UPDATE public.ludo_games     SET afk_warning = v_updated_warning WHERE id = _game_id;
      WHEN 'chess'    THEN UPDATE public.chess_games    SET afk_warning = v_updated_warning WHERE id = _game_id;
      WHEN 'fanorona' THEN UPDATE public.fanorona_games SET afk_warning = v_updated_warning WHERE id = _game_id;
      WHEN 'domino'   THEN UPDATE public.domino_games   SET afk_warning = v_updated_warning WHERE id = _game_id;
      WHEN 'rami'     THEN UPDATE public.rami_games     SET afk_warning = v_updated_warning WHERE id = _game_id;
      WHEN 'poker'    THEN UPDATE public.poker_games    SET afk_warning = v_updated_warning WHERE id = _game_id;
    END CASE;

    RETURN jsonb_build_object(
      'status',       'voted',
      'votes',        jsonb_array_length(v_votes),
      'votes_needed', v_votes_needed
    );
  END IF;
END $$;
