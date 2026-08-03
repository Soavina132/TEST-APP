
-- Delete auto-created "Salon X" rooms and their messages
DELETE FROM public.chat_messages WHERE room_id IN (
  SELECT id FROM public.chat_rooms WHERE type='global' AND name LIKE 'Salon %'
);
DELETE FROM public.chat_members WHERE room_id IN (
  SELECT id FROM public.chat_rooms WHERE type='global' AND name LIKE 'Salon %'
);
DELETE FROM public.chat_reactions WHERE message_id IN (
  SELECT cm.id FROM public.chat_messages cm
  WHERE cm.room_id IN (SELECT id FROM public.chat_rooms WHERE type='global' AND name LIKE 'Salon %')
);
DELETE FROM public.chat_rooms WHERE type='global' AND name LIKE 'Salon %';

-- Ensure the 5 official groups exist
INSERT INTO public.chat_rooms (type, name, enabled, joinable)
SELECT 'global', n, true, true
FROM (VALUES ('Groupe Ludo'),('Groupe Domino'),('Groupe Échec'),('Groupe Fanorona'),('Groupe Rami')) AS t(n)
WHERE NOT EXISTS (
  SELECT 1 FROM public.chat_rooms r WHERE r.type='global' AND r.name=t.n
);
