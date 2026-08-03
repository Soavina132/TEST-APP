-- ============================================================
-- Migration : notifications temps réel pour les matchs tournoi
-- ============================================================

-- 1. Fonction trigger : notifie les joueurs quand un match est créé
CREATE OR REPLACE FUNCTION public._notify_tournament_match()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  uid_t     uuid;
  v_title   text;
  v_body    text;
  v_link    text;
  v_kind    text := 'tournament';
  trn       record;
  v_minutes int;
BEGIN
  -- Charger les infos du tournoi
  SELECT name, join_timeout_secs INTO trn
    FROM public.tournaments WHERE id = NEW.tournament_id;

  v_link := '/tournaments/' || NEW.tournament_id::text;

  -- ── INSERT : match créé (statut = pending) ──────────────────────────
  IF (TG_OP = 'INSERT') AND NEW.status = 'pending' AND NOT NEW.is_bye THEN
    v_minutes := COALESCE(CEIL(COALESCE(trn.join_timeout_secs, 240) / 60.0), 4);
    v_title := '⚡ Ton match de tournoi est prêt !';
    v_body  := 'Tournoi : ' || COALESCE(trn.name, 'Tournoi') ||
               ' — Round ' || NEW.round ||
               '. Tu as ' || v_minutes || ' min pour te connecter.';

    FOREACH uid_t IN ARRAY NEW.player_ids LOOP
      INSERT INTO public.notifications(user_id, kind, title, body, link)
        VALUES (uid_t, v_kind, v_title, v_body, v_link);
    END LOOP;

  -- ── UPDATE : match passe en running (les deux joueurs sont prêts) ───
  ELSIF (TG_OP = 'UPDATE')
    AND OLD.status = 'pending'
    AND NEW.status = 'running'
    AND NOT NEW.is_bye
  THEN
    v_title := '🎮 La partie commence !';
    v_body  := 'Les deux joueurs sont prêts — ' || COALESCE(trn.name, 'Tournoi') ||
               ' Round ' || NEW.round || '. Bonne chance !';

    FOREACH uid_t IN ARRAY NEW.player_ids LOOP
      INSERT INTO public.notifications(user_id, kind, title, body, link)
        VALUES (uid_t, v_kind, v_title, v_body, v_link);
    END LOOP;

  -- ── UPDATE : forfait ─────────────────────────────────────────────────
  ELSIF (TG_OP = 'UPDATE')
    AND OLD.status <> 'forfeit'
    AND NEW.status = 'forfeit'
    AND NEW.winner_id IS NOT NULL
  THEN
    -- Notifier le vainqueur
    v_title := '🏆 Victoire par forfait !';
    v_body  := 'Ton adversaire ne s''est pas présenté — ' || COALESCE(trn.name, 'Tournoi') ||
               ' Round ' || NEW.round || '. Tu passes au tour suivant.';
    INSERT INTO public.notifications(user_id, kind, title, body, link)
      VALUES (NEW.winner_id, v_kind, v_title, v_body, v_link);

    -- Notifier le perdant (s'il y en a un)
    FOREACH uid_t IN ARRAY NEW.player_ids LOOP
      IF uid_t <> NEW.winner_id THEN
        INSERT INTO public.notifications(user_id, kind, title, body, link)
          VALUES (uid_t, 'tournament',
            '🏳️ Défaite par forfait',
            'Tu n''as pas rejoint le match à temps — ' || COALESCE(trn.name, 'Tournoi') || ' Round ' || NEW.round || '.',
            v_link);
      END IF;
    END LOOP;

  -- ── UPDATE : match terminé (vainqueur connu) ─────────────────────────
  ELSIF (TG_OP = 'UPDATE')
    AND OLD.status <> 'finished'
    AND NEW.status = 'finished'
    AND NEW.winner_id IS NOT NULL
    AND NOT NEW.is_bye
  THEN
    FOREACH uid_t IN ARRAY NEW.player_ids LOOP
      IF uid_t = NEW.winner_id THEN
        INSERT INTO public.notifications(user_id, kind, title, body, link)
          VALUES (uid_t, v_kind,
            '🏆 Tu as gagné ton match !',
            COALESCE(trn.name,'Tournoi') || ' Round ' || NEW.round || ' — Tu passes au tour suivant !',
            v_link);
      ELSE
        INSERT INTO public.notifications(user_id, kind, title, body, link)
          VALUES (uid_t, v_kind,
            '❌ Match perdu',
            COALESCE(trn.name,'Tournoi') || ' Round ' || NEW.round || '. Meilleure chance la prochaine fois !',
            v_link);
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- 2. Trigger sur tournament_matches
DROP TRIGGER IF EXISTS trg_notify_tournament_match ON public.tournament_matches;
CREATE TRIGGER trg_notify_tournament_match
  AFTER INSERT OR UPDATE OF status, winner_id ON public.tournament_matches
  FOR EACH ROW EXECUTE FUNCTION public._notify_tournament_match();

-- 3. RPC : admin_notify_tournament_players (notif manuelle admin → joueurs du tournoi)
CREATE OR REPLACE FUNCTION public.admin_notify_tournament_players(
  _tid    uuid,
  _title  text,
  _body   text
)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_is_admin boolean;
  v_count    int := 0;
  uid_t      uuid;
  v_link     text := '/tournaments/' || _tid::text;
BEGIN
  SELECT is_admin INTO v_is_admin FROM public.profiles WHERE id = v_uid;
  IF NOT COALESCE(v_is_admin, false) THEN RAISE EXCEPTION 'Accès refusé'; END IF;

  FOR uid_t IN
    SELECT user_id FROM public.tournament_registrations WHERE tournament_id = _tid
  LOOP
    INSERT INTO public.notifications(user_id, kind, title, body, link)
      VALUES (uid_t, 'tournament', _title, _body, v_link);
    v_count := v_count + 1;
  END LOOP;

  INSERT INTO public.admin_logs(admin_id, action, new_value)
    VALUES (v_uid, 'notify_tournament_players',
      jsonb_build_object('tournament_id', _tid, 'title', _title, 'recipients', v_count));

  RETURN v_count;
END;
$$;
