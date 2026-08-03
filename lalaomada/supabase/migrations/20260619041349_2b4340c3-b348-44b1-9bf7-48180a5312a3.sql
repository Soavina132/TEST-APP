
CREATE TABLE IF NOT EXISTS public.game_configs (
  slug text PRIMARY KEY,
  display_name text NOT NULL,
  turn_timer_seconds integer NOT NULL DEFAULT 30,
  max_turn_skips integer NOT NULL DEFAULT 5,
  rules_markdown text NOT NULL DEFAULT '',
  cover_url text NOT NULL DEFAULT '',
  max_online_capacity integer NOT NULL DEFAULT 1000,
  instructions_dismissible boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now()
);

GRANT SELECT ON public.game_configs TO anon, authenticated;
GRANT ALL ON public.game_configs TO service_role;

ALTER TABLE public.game_configs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "game_configs readable by all"
  ON public.game_configs FOR SELECT
  USING (true);

CREATE POLICY "game_configs admin write"
  ON public.game_configs FOR ALL
  TO authenticated
  USING (public.has_role(auth.uid(), 'admin'))
  WITH CHECK (public.has_role(auth.uid(), 'admin'));

CREATE OR REPLACE FUNCTION public.touch_game_configs() RETURNS trigger AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql SET search_path = public;

DROP TRIGGER IF EXISTS trg_touch_game_configs ON public.game_configs;
CREATE TRIGGER trg_touch_game_configs
  BEFORE UPDATE ON public.game_configs
  FOR EACH ROW EXECUTE FUNCTION public.touch_game_configs();

INSERT INTO public.game_configs (slug, display_name, rules_markdown) VALUES
  ('ludo', 'Ludo', 'Lance le dé, sort tes pions avec un 6, fais le tour du plateau et rentre tous tes pions à la maison pour gagner.'),
  ('domino', 'Domino', 'Pose un domino dont une extrémité correspond à celle déjà sur la table. Premier à se débarrasser de tous ses dominos gagne.'),
  ('fanorona', 'Fanorona', 'Jeu traditionnel malgache à deux joueurs. Capture les pions adverses par approche ou par éloignement.'),
  ('chess', 'Échecs', 'Mets le roi adverse en échec et mat pour gagner la partie.'),
  ('rami', 'Rami', 'Pioche, forme des combinaisons (3+ cartes même rang ou suites de même couleur), défausse. Premier à vider sa main gagne.')
ON CONFLICT (slug) DO NOTHING;
