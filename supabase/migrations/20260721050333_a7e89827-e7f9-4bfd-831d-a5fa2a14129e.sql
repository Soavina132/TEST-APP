
CREATE OR REPLACE FUNCTION public.cleanup_stale_open_games()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_timeout int;
  v_cutoff timestamptz;
  g RECORD; p RECORD; v_count int := 0;
BEGIN
  SELECT COALESCE(game_invite_timeout_minutes, 5) INTO v_timeout
    FROM public.app_settings WHERE id = 1;
  IF v_timeout IS NULL THEN v_timeout := 5; END IF;
  v_cutoff := now() - (v_timeout || ' minutes')::interval;

  -- LUDO
  FOR g IN SELECT * FROM public.ludo_games WHERE status='open' AND created_at < v_cutoff LOOP
    FOR p IN SELECT user_id FROM public.ludo_participants WHERE game_id=g.id AND user_id IS NOT NULL AND COALESCE(is_bot,false)=false LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (p.user_id,'refund',g.stake,g.id,'Partie Ludo expirée · remboursement');
      END IF;
    END LOOP;
    DELETE FROM public.ludo_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;

  -- DOMINO
  FOR g IN SELECT * FROM public.domino_games WHERE status='open' AND created_at < v_cutoff LOOP
    FOR p IN SELECT user_id FROM public.domino_participants WHERE game_id=g.id AND user_id IS NOT NULL AND COALESCE(is_bot,false)=false LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (p.user_id,'refund',g.stake,g.id,'Partie Domino expirée · remboursement');
      END IF;
    END LOOP;
    DELETE FROM public.domino_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;

  -- RAMI
  FOR g IN SELECT * FROM public.rami_games WHERE status IN ('open','waiting') AND created_at < v_cutoff LOOP
    FOR p IN SELECT user_id FROM public.rami_participants WHERE game_id=g.id AND user_id IS NOT NULL AND COALESCE(is_bot,false)=false LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (p.user_id,'refund',g.stake,g.id,'Partie Rami expirée · remboursement');
      END IF;
    END LOOP;
    DELETE FROM public.rami_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;

  -- FANORONA
  FOR g IN SELECT * FROM public.fanorona_games WHERE status='open' AND created_at < v_cutoff LOOP
    FOR p IN SELECT user_id FROM public.fanorona_participants WHERE game_id=g.id AND user_id IS NOT NULL AND COALESCE(is_bot,false)=false LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (p.user_id,'refund',g.stake,g.id,'Partie Fanorona expirée · remboursement');
      END IF;
    END LOOP;
    DELETE FROM public.fanorona_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;

  -- CHESS (no participants table, use white_id/black_id)
  FOR g IN SELECT * FROM public.chess_games WHERE status='open' AND created_at < v_cutoff LOOP
    IF COALESCE(g.stake,0) > 0 THEN
      IF g.white_id IS NOT NULL AND NOT COALESCE(g.white_is_bot,false) THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=g.white_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (g.white_id,'refund',g.stake,g.id,'Partie Échecs expirée · remboursement');
      END IF;
      IF g.black_id IS NOT NULL AND NOT COALESCE(g.black_is_bot,false) THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=g.black_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (g.black_id,'refund',g.stake,g.id,'Partie Échecs expirée · remboursement');
      END IF;
    END IF;
    DELETE FROM public.chess_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;

  -- POKER (uses poker_players)
  FOR g IN SELECT * FROM public.poker_games WHERE status='waiting' AND created_at < v_cutoff LOOP
    FOR p IN SELECT user_id FROM public.poker_players WHERE game_id=g.id AND user_id IS NOT NULL AND COALESCE(is_bot,false)=false LOOP
      IF COALESCE(g.stake,0) > 0 THEN
        UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=p.user_id;
        INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
          VALUES (p.user_id,'refund',g.stake,g.id,'Partie Poker expirée · remboursement');
      END IF;
    END LOOP;
    DELETE FROM public.poker_games WHERE id=g.id;
    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END $$;

GRANT EXECUTE ON FUNCTION public.cleanup_stale_open_games() TO authenticated, anon, service_role;

-- Schedule every minute
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='cleanup_stale_open_games') THEN
    PERFORM cron.schedule('cleanup_stale_open_games', '* * * * *', $c$SELECT public.cleanup_stale_open_games();$c$);
  END IF;
END $$;
