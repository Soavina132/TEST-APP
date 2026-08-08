-- ═══════════════════════════════════════════════════════════════════════
-- Support messages: admin listing RPC + notify-admin trigger on new message
-- (support_messages table + admin_reply_support RPC already exist)
-- ═══════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.admin_list_support_messages(
  _status TEXT DEFAULT NULL, _limit INT DEFAULT 100
) RETURNS TABLE(
  id UUID, user_id UUID, pseudo TEXT, message TEXT, reply TEXT,
  status TEXT, created_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Réservé admin'; END IF;
  RETURN QUERY
    SELECT sm.id, sm.user_id, COALESCE(p.pseudo, 'Joueur supprimé'),
           sm.message, sm.reply, sm.status, sm.created_at
    FROM public.support_messages sm
    LEFT JOIN public.profiles p ON p.id = sm.user_id
    WHERE (_status IS NULL OR sm.status = _status)
    ORDER BY sm.created_at DESC
    LIMIT _limit;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_support_messages(TEXT,INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_list_support_messages(TEXT,INT) TO authenticated;

-- RPC for user to list their own messages + replies (for the popup history)
CREATE OR REPLACE FUNCTION public.my_support_messages(_limit INT DEFAULT 20)
RETURNS TABLE(id UUID, message TEXT, reply TEXT, status TEXT, created_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_uid UUID := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  RETURN QUERY
    SELECT sm.id, sm.message, sm.reply, sm.status, sm.created_at
    FROM public.support_messages sm
    WHERE sm.user_id = v_uid
    ORDER BY sm.created_at DESC
    LIMIT _limit;
END;
$$;
REVOKE ALL ON FUNCTION public.my_support_messages(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.my_support_messages(INT) TO authenticated;

-- Notify all admins when a new support message comes in
CREATE OR REPLACE FUNCTION public.notify_admin_new_support_message()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  BEGIN
    INSERT INTO public.notifications(user_id, kind, type, title, body, ref_id)
    SELECT ur.user_id, 'info', 'support_message',
      'Nouveau message support',
      left(trim(NEW.message), 100), NEW.id
    FROM public.user_roles ur WHERE ur.role = 'admin';
  EXCEPTION WHEN OTHERS THEN NULL;
  END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_support_message ON public.support_messages;
CREATE TRIGGER trg_notify_admin_support_message
AFTER INSERT ON public.support_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_admin_new_support_message();

-- Notify user when admin replies
CREATE OR REPLACE FUNCTION public.notify_user_support_reply()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.reply IS NOT NULL AND (OLD.reply IS NULL OR OLD.reply IS DISTINCT FROM NEW.reply) THEN
    BEGIN
      INSERT INTO public.notifications(user_id, kind, type, title, body, ref_id)
      VALUES (NEW.user_id, 'info', 'support_reply',
        'Réponse du support',
        left(trim(NEW.reply), 100), NEW.id);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_user_support_reply ON public.support_messages;
CREATE TRIGGER trg_notify_user_support_reply
AFTER UPDATE ON public.support_messages
FOR EACH ROW EXECUTE FUNCTION public.notify_user_support_reply();
