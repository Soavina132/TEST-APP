-- ═══════════════════════════════════════════════════════════════════════
-- Bug Reports — player feedback / bug signaling system
-- ═══════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.bug_reports (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category    TEXT        NOT NULL DEFAULT 'general',
  message     TEXT        NOT NULL CHECK (length(trim(message)) >= 5),
  status      TEXT        NOT NULL DEFAULT 'open'
                          CHECK (status IN ('open','in_progress','resolved','closed')),
  admin_note  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ
);

ALTER TABLE public.bug_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "bug_reports_select" ON public.bug_reports FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

CREATE POLICY "bug_reports_insert" ON public.bug_reports FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "bug_reports_admin_update" ON public.bug_reports FOR UPDATE
  USING (public.is_admin());

CREATE OR REPLACE FUNCTION public.submit_bug_report(_category TEXT, _message TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF length(trim(_message)) < 5 THEN RAISE EXCEPTION 'Message trop court'; END IF;
  INSERT INTO public.bug_reports(user_id, category, message)
  VALUES (v_uid, COALESCE(NULLIF(trim(_category),''), 'general'), trim(_message))
  RETURNING id INTO v_id;
  BEGIN
    INSERT INTO public.notifications(user_id, type, title, body, ref_id)
    SELECT ur.user_id, 'bug_report',
      'Nouveau signalement (' || COALESCE(_category,'general') || ')',
      left(trim(_message), 100), v_id
    FROM public.user_roles ur WHERE ur.role = 'admin';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION public.submit_bug_report(TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_bug_report(TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_bug_report(
  _id UUID, _status TEXT, _admin_note TEXT DEFAULT NULL
) RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  UPDATE public.bug_reports SET
    status     = _status,
    admin_note = COALESCE(_admin_note, admin_note),
    resolved_at = CASE WHEN _status IN ('resolved','closed') THEN now() ELSE resolved_at END
  WHERE id = _id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_bug_report(UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_update_bug_report(UUID,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_bug_reports(
  _status TEXT DEFAULT NULL, _limit INT DEFAULT 100
) RETURNS TABLE(
  id UUID, user_id UUID, pseudo TEXT, category TEXT, message TEXT,
  status TEXT, admin_note TEXT, created_at TIMESTAMPTZ, resolved_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT br.id, br.user_id, COALESCE(p.pseudo, 'Joueur supprimé'),
           br.category, br.message, br.status, br.admin_note,
           br.created_at, br.resolved_at
    FROM public.bug_reports br
    LEFT JOIN public.profiles p ON p.id = br.user_id
    WHERE (_status IS NULL OR br.status = _status)
    ORDER BY br.created_at DESC
    LIMIT _limit;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_bug_reports(TEXT,INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_bug_reports(TEXT,INT) TO authenticated;
