
DROP FUNCTION IF EXISTS public.list_live_games();

CREATE OR REPLACE FUNCTION public.list_live_games()
RETURNS TABLE(
  id uuid, max_players integer, stake numeric, pot numeric,
  players_count integer, spectators_count integer,
  started_at timestamptz, mode text, game_type text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.ludo_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'ludo'::text
  FROM public.ludo_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.ludo_participants pp WHERE pp.game_id=g.id AND pp.is_bot=TRUE
    ))
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.domino_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.mode,'classic')::text, 'domino'::text
  FROM public.domino_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.domino_participants pp WHERE pp.game_id=g.id AND pp.is_bot=TRUE
    ))
  UNION ALL
  SELECT g.id, 2, g.stake, g.pot, 2,
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, 'classic'::text, 'chess'::text
  FROM public.chess_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.profiles pr
       WHERE pr.id IN (g.white_id, g.black_id) AND COALESCE(pr.is_bot,FALSE)=TRUE
    ))
  UNION ALL
  SELECT g.id, g.max_players, g.stake, g.pot,
    (SELECT count(*)::int FROM public.rami_participants p WHERE p.game_id=g.id),
    (SELECT count(*)::int FROM public.game_spectators s WHERE s.game_id=g.id),
    g.started_at, COALESCE(g.joker_mode,'classique')::text, 'rami'::text
  FROM public.rami_games g
  WHERE g.status='playing'
    AND NOT (COALESCE(g.paused,FALSE) AND EXISTS (
      SELECT 1 FROM public.rami_participants pp WHERE pp.game_id=g.id AND pp.is_bot=TRUE
    ))
  ORDER BY 6 DESC, 7 ASC;
$$;

GRANT EXECUTE ON FUNCTION public.list_live_games() TO anon, authenticated;

-- Désactive les triggers d'avertissement AFK (source des pauses)
DROP TRIGGER IF EXISTS trg_afk_warning ON public.chess_games;
DROP TRIGGER IF EXISTS trg_afk_warning ON public.fanorona_games;
DROP TRIGGER IF EXISTS trg_afk_warning ON public.domino_games;
DROP TRIGGER IF EXISTS trg_afk_warning ON public.rami_games;
DROP TRIGGER IF EXISTS trg_afk_warning ON public.poker_games;

-- Ludo : conserve le forfait AFK, supprime la bannière d'avertissement
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

-- Purge des avertissements en cours (seulement sur les tables qui ont la colonne)
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT table_name FROM information_schema.columns
     WHERE table_schema='public' AND column_name='afk_warning'
  LOOP
    EXECUTE format('UPDATE public.%I SET afk_warning=NULL WHERE afk_warning IS NOT NULL', r.table_name);
  END LOOP;
END $$;
