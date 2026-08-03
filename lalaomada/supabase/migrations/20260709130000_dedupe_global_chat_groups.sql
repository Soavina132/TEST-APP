-- Fix: duplicate "global" game group chat rooms (e.g. multiple "Groupe Ludo").
-- Merge all messages/members/reactions into the oldest room per name, then
-- delete the duplicates. Also add a guard so this cannot happen again.

DO $$
DECLARE
  r RECORD;
  v_keep uuid;
  v_dupe uuid;
BEGIN
  FOR r IN
    SELECT name FROM public.chat_rooms
    WHERE type = 'global' AND name IS NOT NULL
    GROUP BY name HAVING count(*) > 1
  LOOP
    -- Keep the oldest room for this name
    SELECT id INTO v_keep FROM public.chat_rooms
      WHERE type = 'global' AND name = r.name
      ORDER BY created_at ASC LIMIT 1;

    FOR v_dupe IN
      SELECT id FROM public.chat_rooms
        WHERE type = 'global' AND name = r.name AND id <> v_keep
    LOOP
      -- Move messages over to the surviving room
      UPDATE public.chat_messages SET room_id = v_keep WHERE room_id = v_dupe;

      -- Move members over, skipping ones already in the surviving room
      INSERT INTO public.chat_members (room_id, user_id, joined_at)
        SELECT v_keep, user_id, joined_at FROM public.chat_members WHERE room_id = v_dupe
        ON CONFLICT (room_id, user_id) DO NOTHING;
      DELETE FROM public.chat_members WHERE room_id = v_dupe;

      -- Drop the now-empty duplicate room
      DELETE FROM public.chat_rooms WHERE id = v_dupe;
    END LOOP;
  END LOOP;
END $$;

-- Prevent this from happening again: one global room per name.
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_global_name_unique
  ON public.chat_rooms(name) WHERE type = 'global';

-- Make community creation reuse an existing room with the same name
-- instead of creating a duplicate.
CREATE OR REPLACE FUNCTION public.admin_create_community(_name text, _image_url text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT id INTO v_id FROM public.chat_rooms WHERE type='global' AND name=_name;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO public.chat_rooms(type,name,image_url,created_by) VALUES('global',_name,_image_url,auth.uid()) RETURNING id INTO v_id;
  RETURN v_id;
END $$;
