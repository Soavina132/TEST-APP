DELETE FROM chat_rooms WHERE type='global';
INSERT INTO chat_rooms (type, name, enabled, joinable) VALUES
  ('global', 'Groupe Ludo', true, true),
  ('global', 'Groupe Domino', true, true),
  ('global', 'Groupe Fanorona', true, true),
  ('global', 'Groupe Échec', true, true),
  ('global', 'Groupe Rami', true, true);