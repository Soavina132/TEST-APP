
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ NOT NULL DEFAULT now();

CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END; $$
LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS trg_tournaments_updated_at ON public.tournaments;
CREATE TRIGGER trg_tournaments_updated_at
BEFORE UPDATE ON public.tournaments
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

CREATE TABLE IF NOT EXISTS public.tournament_audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tournament_id UUID NOT NULL REFERENCES public.tournaments(id) ON DELETE CASCADE,
  match_id UUID,
  event_type TEXT NOT NULL,
  round INT,
  user_id UUID,
  actor_id UUID,
  reason TEXT,
  meta JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT ON public.tournament_audit_logs TO authenticated;
GRANT ALL ON public.tournament_audit_logs TO service_role;

ALTER TABLE public.tournament_audit_logs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admins read audit" ON public.tournament_audit_logs;
CREATE POLICY "Admins read audit" ON public.tournament_audit_logs
FOR SELECT TO authenticated
USING (public.has_role(auth.uid(), 'admin'));

DROP POLICY IF EXISTS "System insert audit" ON public.tournament_audit_logs;
CREATE POLICY "System insert audit" ON public.tournament_audit_logs
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE INDEX IF NOT EXISTS idx_taudit_tid_created ON public.tournament_audit_logs(tournament_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.admin_get_tournament_audit_logs(
  _tournament_id UUID,
  _limit INT DEFAULT 300
)
RETURNS TABLE (
  id UUID,
  tournament_id UUID,
  match_id UUID,
  event_type TEXT,
  round INT,
  user_id UUID,
  actor_id UUID,
  user_name TEXT,
  actor_name TEXT,
  reason TEXT,
  meta JSONB,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT l.id, l.tournament_id, l.match_id, l.event_type, l.round,
         l.user_id, l.actor_id,
         pu.pseudo AS user_name,
         pa.pseudo AS actor_name,
         l.reason, l.meta, l.created_at
  FROM public.tournament_audit_logs l
  LEFT JOIN public.profiles pu ON pu.id = l.user_id
  LEFT JOIN public.profiles pa ON pa.id = l.actor_id
  WHERE l.tournament_id = _tournament_id
    AND public.has_role(auth.uid(), 'admin')
  ORDER BY l.created_at DESC
  LIMIT COALESCE(_limit, 300);
$$;

GRANT EXECUTE ON FUNCTION public.admin_get_tournament_audit_logs(UUID, INT) TO authenticated;
