
CREATE OR REPLACE FUNCTION public._trg_third_place_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  trn      record;
  pid      uuid;
  v_title  text;
  v_body   text;
  v_link   text;
BEGIN
  IF COALESCE(NEW.is_third_place, false) = false THEN RETURN NEW; END IF;
  IF COALESCE(array_length(NEW.player_ids, 1), 0) < 1 THEN RETURN NEW; END IF;

  SELECT id, name, game_slug INTO trn FROM public.tournaments WHERE id = NEW.tournament_id;
  IF trn.id IS NULL THEN RETURN NEW; END IF;

  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    v_title := '🥉 Petite finale programmée';
    v_body  := 'Tu joues bientôt pour la 3e place du tournoi « ' || COALESCE(trn.name,'') || ' ». Prépare-toi !';
    v_link  := '/tournaments/' || trn.id;
    FOREACH pid IN ARRAY NEW.player_ids LOOP
      IF pid IS NOT NULL THEN
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (pid, 'tournament', 'third_place_scheduled', v_title, v_body, v_link, NEW.id);
      END IF;
    END LOOP;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.game_id IS NULL
     AND NEW.game_id IS NOT NULL THEN
    v_title := '⚔️ Petite finale : ça démarre !';
    v_body  := 'Ta petite finale du tournoi « ' || COALESCE(trn.name,'') || ' » vient de commencer. Rejoins la partie maintenant.';
    v_link  := '/' || COALESCE(trn.game_slug, 'ludo') || '/' || NEW.game_id::text;
    FOREACH pid IN ARRAY NEW.player_ids LOOP
      IF pid IS NOT NULL THEN
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (pid, 'tournament', 'third_place_started', v_title, v_body, v_link, NEW.id);
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_third_place_notify ON public.tournament_matches;
CREATE TRIGGER trg_third_place_notify
  AFTER INSERT OR UPDATE ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._trg_third_place_notify();
