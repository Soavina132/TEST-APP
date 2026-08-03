-- Migration: Push notifications infrastructure
-- Creates push_subscriptions table and trigger to send push on new notifications

-- 1. Create push_subscriptions table
CREATE TABLE IF NOT EXISTS public.push_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  endpoint text NOT NULL,
  p256dh text,
  auth text,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, endpoint)
);

-- Enable RLS
ALTER TABLE public.push_subscriptions ENABLE ROW LEVEL SECURITY;

-- Policies: users can only manage their own subscriptions
CREATE POLICY "Users can read own push subs" ON public.push_subscriptions
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "Users can insert own push subs" ON public.push_subscriptions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own push subs" ON public.push_subscriptions
  FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own push subs" ON public.push_subscriptions
  FOR DELETE USING (auth.uid() = user_id);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_push_subs_user ON public.push_subscriptions(user_id);

-- 2. Function to send push notification via pg_net (calls edge function)
CREATE OR REPLACE FUNCTION public._send_push_for_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_edge_url text;
  v_payload jsonb;
BEGIN
  -- Only send for new notifications
  IF TG_OP <> 'INSERT' THEN RETURN NEW; END IF;
  
  -- Edge function URL (will be configured via app_settings or hardcoded)
  SELECT COALESCE(
    (SELECT value FROM public.app_settings WHERE key = 'edge_function_url'),
    'https://gifwfjgciwbsottztzoc.supabase.co/functions/v1/send-push'
  ) INTO v_edge_url;
  
  v_payload := jsonb_build_object(
    'user_id', NEW.user_id,
    'title', NEW.title,
    'body', COALESCE(NEW.body, ''),
    'link', COALESCE(NEW.link, '/'),
    'notification_id', NEW.id
  );
  
  -- Fire and forget — don't block the insert
  PERFORM net.http_post(
    url := v_edge_url,
    headers := jsonb_build_object('Content-Type', 'application/json'),
    body := v_payload
  );
  
  RETURN NEW;
END $function$;

-- 3. Trigger on notifications table
DROP TRIGGER IF EXISTS on_notification_send_push ON public.notifications;
CREATE TRIGGER on_notification_send_push
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public._send_push_for_notification();

-- 4. Grant service role access
GRANT ALL ON public.push_subscriptions TO service_role;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_subscriptions TO authenticated;

-- 5. Add edge_function_url to app_settings if not exists
INSERT INTO public.app_settings (id, paused, game_commission_pct, signup_bonus, referral_pct, min_deposit, min_withdraw)
VALUES (1, false, 10, 0, 0, 500, 1000)
ON CONFLICT (id) DO NOTHING;
