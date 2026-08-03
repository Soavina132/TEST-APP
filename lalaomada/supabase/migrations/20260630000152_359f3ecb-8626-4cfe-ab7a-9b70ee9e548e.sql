CREATE TABLE IF NOT EXISTS public.assistant_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('user','assistant')),
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS assistant_messages_user_created_idx
  ON public.assistant_messages(user_id, created_at);

GRANT SELECT, INSERT, DELETE ON public.assistant_messages TO authenticated;
GRANT ALL ON public.assistant_messages TO service_role;

ALTER TABLE public.assistant_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "own assistant msgs read" ON public.assistant_messages;
CREATE POLICY "own assistant msgs read" ON public.assistant_messages
  FOR SELECT TO authenticated USING (user_id = auth.uid());
DROP POLICY IF EXISTS "own assistant msgs insert" ON public.assistant_messages;
CREATE POLICY "own assistant msgs insert" ON public.assistant_messages
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "own assistant msgs delete" ON public.assistant_messages;
CREATE POLICY "own assistant msgs delete" ON public.assistant_messages
  FOR DELETE TO authenticated USING (user_id = auth.uid());