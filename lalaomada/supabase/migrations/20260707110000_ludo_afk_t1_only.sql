-- ============================================================
-- Ludo AFK pause : déclencher uniquement sur T1 (timeout sans lancer)
--
-- Avant : _ludo_check_afk émettait un avertissement si T1 = max-1 OU T2 = max-1
-- Après : avertissement UNIQUEMENT quand T1 = max-1
--          (le joueur n'a pas lancé le dé afk_t1_max-1 fois d'affilée)
-- Le forfait (T1 >= max) est inchangé.
--
-- On fixe afk_t1_max = 5 dans app_settings pour que l'avertissement
-- se déclenche bien à 4/5 timeouts sans lancer.
-- Le champ afk_warning inclut maintenant t1/t1_max pour l'affichage UI.
-- ============================================================

-- 1) Mettre afk_t1_max = 5 si la valeur n'a pas encore été personnalisée (≤ 2)
UPDATE public.app_settings
   SET afk_t1_max = 5
 WHERE id = 1
   AND afk_t1_max <= 2;

-- 2) Réécrire _ludo_check_afk : warning seulement sur T1 = max-1
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

  -- Lire l'état AFK actuel du joueur (valeurs post-incrément)
  SELECT afk_t1, afk_t2, user_id, is_bot, display_name
    INTO v_t1, v_t2, v_uid, v_isbot, v_name
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  -- ── Seuil forfait : T1 >= max OU T2 >= max (comportement inchangé)
  IF v_t1 >= COALESCE(v_max1, 5) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants
       SET forfeited = TRUE
     WHERE game_id = _game_id AND slot = _slot;
    UPDATE public.ludo_games
       SET afk_warning   = NULL,
           afk_pause_for  = NULL,
           afk_pause_name = NULL
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

  -- ── Seuil avertissement : UNIQUEMENT T1 = max-1
  --    Le joueur n'a pas lancé le dé (max-1) fois consécutives.
  --    On inclut t1 et t1_max dans le JSONB pour l'affichage UI.
  IF v_t1 = COALESCE(v_max1, 5) - 1 THEN
    UPDATE public.ludo_games
       SET afk_warning = jsonb_build_object(
             'uid',    v_uid,
             'name',   COALESCE(v_name, 'Joueur'),
             'slot',   _slot,
             't1',     v_t1,
             't1_max', COALESCE(v_max1, 5),
             'ts',     extract(epoch from now())::bigint
           )
     WHERE id = _game_id
       AND paused = FALSE
       AND (afk_warning IS NULL
            OR (afk_warning->>'uid')::uuid <> v_uid);
  END IF;
END $$;
