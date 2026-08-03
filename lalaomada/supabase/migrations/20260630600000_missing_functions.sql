-- ═══════════════════════════════════════════════════════════════════════════
-- Migration : fonctions manquantes détectées dans le code
-- Fixes: mark_notif_read, admin_announcement_toggle, admin_announcement_delete,
--        admin_offer_delete, admin_season_close, admin_cancel_tournament
-- ═══════════════════════════════════════════════════════════════════════════

-- ─────────────────────────────────────────────────────────────────────────
-- 1. mark_notif_read
--    Marque une ou toutes les notifications comme lues pour l'utilisateur.
--    _id = NULL  → marque toutes les notifs de l'utilisateur courant.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.mark_notif_read(_id UUID DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF _id IS NULL THEN
    UPDATE public.notifications
      SET read = TRUE, read_at = now()
      WHERE user_id = auth.uid() AND read = FALSE;
  ELSE
    UPDATE public.notifications
      SET read = TRUE, read_at = now()
      WHERE id = _id AND user_id = auth.uid();
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.mark_notif_read(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_notif_read(UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 2. admin_announcement_toggle
--    Active ou désactive une annonce (champ is_active).
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_announcement_toggle(
  _id     UUID,
  _active BOOLEAN
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.announcements SET is_active = _active WHERE id = _id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Annonce introuvable'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_announcement_toggle(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_announcement_toggle(UUID, BOOLEAN) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 3. admin_announcement_delete
--    Supprime une annonce définitivement.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_announcement_delete(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  DELETE FROM public.announcements WHERE id = _id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_announcement_delete(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_announcement_delete(UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 4. admin_offer_delete
--    Supprime une offre monétaire.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_offer_delete(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  DELETE FROM public.money_offers WHERE id = _id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_offer_delete(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_offer_delete(UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 5. admin_season_close
--    Clôture une saison : passe le statut à 'closed' et enregistre la date.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_season_close(_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.seasons
    SET status = 'closed', ended_at = COALESCE(ended_at, now())
    WHERE id = _id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Saison introuvable'; END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_season_close(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_season_close(UUID) TO authenticated;


-- ─────────────────────────────────────────────────────────────────────────
-- 6. admin_cancel_tournament
--    Annule un tournoi et rembourse les joueurs inscrits.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_cancel_tournament(_tid UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_stake NUMERIC;
  rec     RECORD;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;

  SELECT stake INTO v_stake FROM public.tournaments WHERE id = _tid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Tournoi introuvable'; END IF;

  -- Rembourser les participants si mise non nulle
  IF COALESCE(v_stake, 0) > 0 THEN
    FOR rec IN
      SELECT user_id FROM public.tournament_players WHERE tournament_id = _tid
    LOOP
      UPDATE public.profiles
        SET balance_ar = COALESCE(balance_ar, 0) + v_stake
        WHERE id = rec.user_id;
    END LOOP;
  END IF;

  UPDATE public.tournaments SET status = 'cancelled' WHERE id = _tid;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_cancel_tournament(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_cancel_tournament(UUID) TO authenticated;
