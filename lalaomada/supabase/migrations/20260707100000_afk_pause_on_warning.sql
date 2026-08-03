-- ============================================================
-- AFK Pause on Warning
--
-- Lorsqu'un joueur atteint le seuil d'avertissement AFK
-- (max - 1 timeouts), tous les joueurs actifs reçoivent une
-- notification et peuvent mettre la partie en pause 3 minutes.
-- Si le joueur AFK ne revient pas, il est forfait automatique.
-- ============================================================

-- 1) Colonnes afk_warning + afk_pause_for sur toutes les tables de jeu
ALTER TABLE public.ludo_games
  ADD COLUMN IF NOT EXISTS afk_warning   JSONB,
  ADD COLUMN IF NOT EXISTS afk_pause_for  UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

ALTER TABLE public.chess_games
  ADD COLUMN IF NOT EXISTS afk_warning   JSONB,
  ADD COLUMN IF NOT EXISTS afk_pause_for  UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

ALTER TABLE public.fanorona_games
  ADD COLUMN IF NOT EXISTS afk_warning   JSONB,
  ADD COLUMN IF NOT EXISTS afk_pause_for  UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

ALTER TABLE public.domino_games
  ADD COLUMN IF NOT EXISTS afk_warning   JSONB,
  ADD COLUMN IF NOT EXISTS afk_pause_for  UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

ALTER TABLE public.rami_games
  ADD COLUMN IF NOT EXISTS afk_warning   JSONB,
  ADD COLUMN IF NOT EXISTS afk_pause_for  UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

ALTER TABLE public.poker_games
  ADD COLUMN IF NOT EXISTS afk_warning   JSONB,
  ADD COLUMN IF NOT EXISTS afk_pause_for  UUID REFERENCES public.profiles(id),
  ADD COLUMN IF NOT EXISTS afk_pause_name TEXT;

-- 2) Modifier _ludo_check_afk pour émettre un avertissement à T1=max-1 ou T2=max-1
CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_t1     int;
  v_t2     int;
  v_max1   int;
  v_max2   int;
  v_enabled boolean;
  v_uid    uuid;
  v_isbot  boolean;
  v_name   text;
  v_winner uuid;
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

  -- ── Seuil forfait
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
    RETURN;
  END IF;

  -- ── Seuil avertissement : T1 = max-1 OU T2 = max-1
  IF v_t1 = COALESCE(v_max1, 2) - 1 OR v_t2 = COALESCE(v_max2, 2) - 1 THEN
    UPDATE public.ludo_games
       SET afk_warning = jsonb_build_object(
             'uid',  v_uid,
             'name', COALESCE(v_name, 'Joueur'),
             'slot', _slot,
             'ts',   extract(epoch from now())::bigint
           )
     WHERE id = _game_id
       AND paused = FALSE
       AND (afk_warning IS NULL
            OR (afk_warning->>'uid')::uuid <> v_uid);
  END IF;
END $$;

-- 3) Trigger pour les jeux non-Ludo : afk_warning quand turn_skips atteint max-1
CREATE OR REPLACE FUNCTION public._trg_afk_warning_non_ludo()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_max   INT;
  v_slug  TEXT;
  v_key   TEXT;
  v_count INT;
  v_name  TEXT;
BEGIN
  -- Seulement si la partie est en cours, non en pause, et turn_skips a changé
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

  -- Chercher le premier joueur au seuil d'avertissement (max - 1)
  FOR v_key, v_count IN
    SELECT key, value::int FROM jsonb_each_text(NEW.turn_skips)
  LOOP
    IF v_count = v_max - 1 THEN
      SELECT pseudo INTO v_name FROM public.profiles WHERE id = v_key::uuid;
      NEW.afk_warning := jsonb_build_object(
        'uid',   v_key,
        'name',  COALESCE(v_name, 'Joueur'),
        'skips', v_count,
        'max',   v_max,
        'ts',    extract(epoch from now())::bigint
      );
      RETURN NEW;
    END IF;
  END LOOP;

  RETURN NEW;
END $$;

-- Attacher le trigger à toutes les tables de jeu non-Ludo
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

-- 4) Nouveau RPC : game_request_afk_pause(_slug, _game_id)
--    N'importe quel joueur actif (sauf le joueur AFK) peut déclencher cette pause
CREATE OR REPLACE FUNCTION public.game_request_afk_pause(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid            UUID    := auth.uid();
  v_status         TEXT;
  v_paused         BOOLEAN;
  v_warning        JSONB;
  v_afk_uid        UUID;
  v_is_participant BOOLEAN := FALSE;
  v_remaining_s    INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  CASE _slug
    WHEN 'ludo' THEN
      SELECT status, paused, afk_warning
        INTO v_status, v_paused, v_warning
        FROM public.ludo_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.ludo_participants
         WHERE game_id = _game_id AND user_id = v_uid
           AND is_bot = FALSE AND forfeited = FALSE
      ) INTO v_is_participant;

    WHEN 'chess' THEN
      SELECT status, paused, afk_warning,
             CEIL(GREATEST(0, EXTRACT(EPOCH FROM (turn_deadline - now()))))
        INTO v_status, v_paused, v_warning, v_remaining_s
        FROM public.chess_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      SELECT EXISTS(
        SELECT 1 FROM public.chess_games
         WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid)
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
        SELECT 1 FROM public.poker_players
         WHERE game_id = _game_id AND user_id = v_uid
      ) INTO v_is_participant;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF v_status <> 'playing'  THEN RAISE EXCEPTION 'la partie n''est pas en cours'; END IF;
  IF COALESCE(v_paused, FALSE) THEN RAISE EXCEPTION 'la partie est déjà en pause'; END IF;
  IF NOT v_is_participant   THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;
  IF v_warning IS NULL      THEN RAISE EXCEPTION 'aucun joueur en état AFK critique'; END IF;

  v_afk_uid := (v_warning->>'uid')::uuid;
  IF v_uid = v_afk_uid THEN
    RAISE EXCEPTION 'vous ne pouvez pas déclencher votre propre pause AFK';
  END IF;

  -- Appliquer la pause AFK (3 minutes, indépendante de pause_used)
  -- afk_pause_name conserve le nom du joueur AFK pour affichage après effacement de afk_warning
  CASE _slug
    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused         = TRUE,
             pause_deadline  = now() + interval '3 minutes',
             afk_pause_for   = v_afk_uid,
             afk_pause_name  = v_warning->>'name',
             afk_warning     = NULL,
             -- Geler le timer du tour courant
             state = jsonb_set(
               state, '{turn_started_at}',
               to_jsonb((now() + interval '1 hour')::text), true
             )
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
             paused_turn_remaining_s = COALESCE(v_remaining_s, 60),
             turn_deadline           = NULL,
             afk_pause_for           = v_afk_uid,
             afk_pause_name          = v_warning->>'name',
             afk_warning             = NULL
       WHERE id = _game_id;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '3 minutes',
             paused_turn_remaining_s = COALESCE(v_remaining_s, 60),
             turn_deadline           = NULL,
             afk_pause_for           = v_afk_uid,
             afk_pause_name          = v_warning->>'name',
             afk_warning             = NULL
       WHERE id = _game_id;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused                  = TRUE,
             pause_deadline          = now() + interval '3 minutes',
             paused_turn_remaining_s = COALESCE(v_remaining_s, 45),
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
END $;

GRANT EXECUTE ON FUNCTION public.game_request_afk_pause(TEXT, UUID) TO authenticated;

-- 5) Forfait du joueur AFK quand le délai de pause expire
CREATE OR REPLACE FUNCTION public._afk_forfeit_player(_slug TEXT, _game_id UUID, _uid UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_max_skips INT;
  v_slot      INT;
  v_winner    UUID;
BEGIN
  CASE _slug
    WHEN 'ludo' THEN
      -- Forcer T1 au-dessus du max pour déclencher _ludo_check_afk
      UPDATE public.ludo_participants
         SET afk_t1 = 99
       WHERE game_id = _game_id AND user_id = _uid;
      -- Effacer la pause
      UPDATE public.ludo_games
         SET paused         = FALSE,
             pause_deadline  = NULL,
             afk_pause_for   = NULL,
             afk_pause_name  = NULL,
             afk_warning     = NULL,
             state = jsonb_set(
               state, '{turn_started_at}',
               to_jsonb(now()::text), true
             )
       WHERE id = _game_id;
      -- Lancer la vérification AFK pour le slot du joueur
      SELECT slot INTO v_slot
        FROM public.ludo_participants
       WHERE game_id = _game_id AND user_id = _uid;
      IF FOUND THEN
        PERFORM public._ludo_check_afk(_game_id, v_slot);
      END IF;

    ELSE
      -- Pour les autres jeux : mettre turn_skips du joueur à max+1 et forcer
      -- le tour en retard pour que le prochain tick déclenche le forfait existant
      SELECT max_turn_skips INTO v_max_skips
        FROM public.game_configs WHERE slug = _slug;
      v_max_skips := COALESCE(v_max_skips, 5);

      CASE _slug
        WHEN 'chess' THEN
          UPDATE public.chess_games
             SET paused                  = FALSE,
                 pause_deadline          = NULL,
                 afk_pause_for           = NULL,
                 afk_pause_name          = NULL,
                 afk_warning             = NULL,
                 turn_skips = COALESCE(turn_skips, '{}'::jsonb)
                              || jsonb_build_object(_uid::text, v_max_skips + 1),
                 turn_deadline = now() - interval '1 second'
           WHERE id = _game_id;
          PERFORM public.chess_tick(_game_id);

        WHEN 'fanorona' THEN
          UPDATE public.fanorona_games
             SET paused                  = FALSE,
                 pause_deadline          = NULL,
                 afk_pause_for           = NULL,
                 afk_pause_name          = NULL,
                 afk_warning             = NULL,
                 turn_skips = COALESCE(turn_skips, '{}'::jsonb)
                              || jsonb_build_object(_uid::text, v_max_skips + 1),
                 turn_deadline = now() - interval '1 second'
           WHERE id = _game_id;
          PERFORM public.fanorona_tick(_game_id);

        WHEN 'domino' THEN
          UPDATE public.domino_games
             SET paused                  = FALSE,
                 pause_deadline          = NULL,
                 afk_pause_for           = NULL,
                 afk_pause_name          = NULL,
                 afk_warning             = NULL,
                 turn_skips = COALESCE(turn_skips, '{}'::jsonb)
                              || jsonb_build_object(_uid::text, v_max_skips + 1),
                 turn_deadline = now() - interval '1 second'
           WHERE id = _game_id;
          PERFORM public.domino_tick(_game_id);

        WHEN 'rami' THEN
          UPDATE public.rami_games
             SET paused                  = FALSE,
                 pause_deadline          = NULL,
                 afk_pause_for           = NULL,
                 afk_pause_name          = NULL,
                 afk_warning             = NULL,
                 turn_skips = COALESCE(turn_skips, '{}'::jsonb)
                              || jsonb_build_object(_uid::text, v_max_skips + 1),
                 turn_deadline = now() - interval '1 second'
           WHERE id = _game_id;
          PERFORM public.rami_tick(_game_id);

        WHEN 'poker' THEN
          -- Poker : mise à jour de turn_skips + appel poker_tick si disponible
          -- (poker_tick gère la logique de timeout/fold pour le joueur AFK)
          UPDATE public.poker_games
             SET paused                  = FALSE,
                 pause_deadline          = NULL,
                 afk_pause_for           = NULL,
                 afk_pause_name          = NULL,
                 afk_warning             = NULL,
                 turn_skips = COALESCE(turn_skips, '{}'::jsonb)
                              || jsonb_build_object(_uid::text, v_max_skips + 1),
                 turn_deadline = now() - interval '1 second'
           WHERE id = _game_id;
          -- Note: poker_tick se chargera de traiter l'expiration au prochain tick
          -- (appelé par tick_all_games toutes les secondes)
      END CASE;
  END CASE;
END $$;

-- 6) Mettre à jour game_resume pour effacer l'état de pause AFK
CREATE OR REPLACE FUNCTION public.game_resume(_slug TEXT, _game_id UUID)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid             UUID    := auth.uid();
  v_status          TEXT;
  v_paused          BOOLEAN;
  v_remaining_s     INTEGER;
  v_is_participant  BOOLEAN := FALSE;
BEGIN
  CASE _slug
    WHEN 'chess' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.chess_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.chess_games
          WHERE id = _game_id AND (white_id = v_uid OR black_id = v_uid))
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'fanorona' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.fanorona_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.fanorona_participants
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'domino' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.domino_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.domino_participants
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'rami' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.rami_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.rami_participants
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'poker' THEN
      SELECT status, paused, paused_turn_remaining_s
        INTO v_status, v_paused, v_remaining_s
        FROM public.poker_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.poker_players
          WHERE game_id = _game_id AND user_id = v_uid)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    WHEN 'ludo' THEN
      SELECT status, paused
        INTO v_status, v_paused
        FROM public.ludo_games WHERE id = _game_id;
      IF NOT FOUND THEN RAISE EXCEPTION 'partie introuvable'; END IF;
      IF v_uid IS NOT NULL THEN
        SELECT EXISTS(SELECT 1 FROM public.ludo_participants
          WHERE game_id = _game_id AND user_id = v_uid AND is_bot = FALSE)
          INTO v_is_participant;
      ELSE v_is_participant := TRUE; END IF;

    ELSE RAISE EXCEPTION 'slug invalide: %', _slug;
  END CASE;

  IF v_status <> 'playing' THEN RETURN; END IF;
  IF NOT v_paused          THEN RETURN; END IF;
  IF NOT v_is_participant  THEN RAISE EXCEPTION 'vous n''êtes pas participant'; END IF;

  CASE _slug
    WHEN 'chess' THEN
      UPDATE public.chess_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             afk_pause_for           = NULL,
             afk_pause_name          = NULL,
             afk_warning             = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 30) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'fanorona' THEN
      UPDATE public.fanorona_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             afk_pause_for           = NULL,
             afk_pause_name          = NULL,
             afk_warning             = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 60) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'domino' THEN
      UPDATE public.domino_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             afk_pause_for           = NULL,
             afk_pause_name          = NULL,
             afk_warning             = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 60) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'rami' THEN
      UPDATE public.rami_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             afk_pause_for           = NULL,
             afk_pause_name          = NULL,
             afk_warning             = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 45) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'poker' THEN
      UPDATE public.poker_games
         SET paused                  = FALSE,
             pause_deadline          = NULL,
             paused_turn_remaining_s = NULL,
             afk_pause_for           = NULL,
             afk_pause_name          = NULL,
             afk_warning             = NULL,
             turn_deadline           = now() + (COALESCE(v_remaining_s, 30) || ' seconds')::interval
       WHERE id = _game_id;

    WHEN 'ludo' THEN
      UPDATE public.ludo_games
         SET paused         = FALSE,
             pause_deadline  = NULL,
             afk_pause_for   = NULL,
             afk_pause_name  = NULL,
             afk_warning     = NULL,
             state = jsonb_set(
               state, '{turn_started_at}',
               to_jsonb(now()::text), true
             )
       WHERE id = _game_id;
  END CASE;
END $;

GRANT EXECUTE ON FUNCTION public.game_resume(TEXT, UUID) TO authenticated;

-- 7) Mettre à jour _auto_resume_paused_games pour gérer le forfait AFK à l'expiration
CREATE OR REPLACE FUNCTION public._auto_resume_paused_games()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  -- Chess
  FOR r IN
    SELECT id, afk_pause_for FROM public.chess_games
     WHERE paused = TRUE AND pause_deadline IS NOT NULL
       AND pause_deadline < now() AND status = 'playing'
  LOOP
    IF r.afk_pause_for IS NOT NULL THEN
      PERFORM public._afk_forfeit_player('chess', r.id, r.afk_pause_for);
    ELSE
      PERFORM public.game_resume('chess', r.id);
    END IF;
  END LOOP;

  -- Fanorona
  FOR r IN
    SELECT id, afk_pause_for FROM public.fanorona_games
     WHERE paused = TRUE AND pause_deadline IS NOT NULL
       AND pause_deadline < now() AND status = 'playing'
  LOOP
    IF r.afk_pause_for IS NOT NULL THEN
      PERFORM public._afk_forfeit_player('fanorona', r.id, r.afk_pause_for);
    ELSE
      PERFORM public.game_resume('fanorona', r.id);
    END IF;
  END LOOP;

  -- Domino
  FOR r IN
    SELECT id, afk_pause_for FROM public.domino_games
     WHERE paused = TRUE AND pause_deadline IS NOT NULL
       AND pause_deadline < now() AND status = 'playing'
  LOOP
    IF r.afk_pause_for IS NOT NULL THEN
      PERFORM public._afk_forfeit_player('domino', r.id, r.afk_pause_for);
    ELSE
      PERFORM public.game_resume('domino', r.id);
    END IF;
  END LOOP;

  -- Rami
  FOR r IN
    SELECT id, afk_pause_for FROM public.rami_games
     WHERE paused = TRUE AND pause_deadline IS NOT NULL
       AND pause_deadline < now() AND status = 'playing'
  LOOP
    IF r.afk_pause_for IS NOT NULL THEN
      PERFORM public._afk_forfeit_player('rami', r.id, r.afk_pause_for);
    ELSE
      PERFORM public.game_resume('rami', r.id);
    END IF;
  END LOOP;

  -- Poker
  FOR r IN
    SELECT id, afk_pause_for FROM public.poker_games
     WHERE paused = TRUE AND pause_deadline IS NOT NULL
       AND pause_deadline < now() AND status = 'playing'
  LOOP
    IF r.afk_pause_for IS NOT NULL THEN
      PERFORM public._afk_forfeit_player('poker', r.id, r.afk_pause_for);
    ELSE
      PERFORM public.game_resume('poker', r.id);
    END IF;
  END LOOP;

  -- Ludo
  FOR r IN
    SELECT id, afk_pause_for FROM public.ludo_games
     WHERE paused = TRUE AND pause_deadline IS NOT NULL
       AND pause_deadline < now() AND status = 'playing'
  LOOP
    IF r.afk_pause_for IS NOT NULL THEN
      PERFORM public._afk_forfeit_player('ludo', r.id, r.afk_pause_for);
    ELSE
      PERFORM public.game_resume('ludo', r.id);
    END IF;
  END LOOP;
END $$;
