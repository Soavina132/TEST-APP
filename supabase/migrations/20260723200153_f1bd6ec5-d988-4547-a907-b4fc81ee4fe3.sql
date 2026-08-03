
-- ==========================================================================
-- Jeu de Pétanque — V1 (1v1, boules = 3 chacun, physique déterministe côté serveur)
-- ==========================================================================

CREATE TABLE IF NOT EXISTS public.petanque_games (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  creator_id        UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  mode              TEXT NOT NULL DEFAULT '1v1' CHECK (mode IN ('1v1','2v2')),
  stake             NUMERIC NOT NULL DEFAULT 0,
  pot               NUMERIC NOT NULL DEFAULT 0,
  status            TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','playing','finished','cancelled')),
  is_private        BOOLEAN NOT NULL DEFAULT false,
  room_code         TEXT UNIQUE,
  target_points     INT NOT NULL DEFAULT 13,
  score_team0       INT NOT NULL DEFAULT 0,
  score_team1       INT NOT NULL DEFAULT 0,
  current_round     INT NOT NULL DEFAULT 1,
  cochonnet_x       DOUBLE PRECISION NOT NULL DEFAULT 0.55,
  cochonnet_y       DOUBLE PRECISION NOT NULL DEFAULT 0.0,
  current_player_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  turn_deadline     TIMESTAMPTZ,
  prep_deadline     TIMESTAMPTZ,
  winner_team       INT,
  boules_per_player INT NOT NULL DEFAULT 3,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  started_at        TIMESTAMPTZ,
  finished_at       TIMESTAMPTZ,
  meta              JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE TABLE IF NOT EXISTS public.petanque_participants (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id      UUID NOT NULL REFERENCES public.petanque_games(id) ON DELETE CASCADE,
  user_id      UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  team         INT NOT NULL CHECK (team IN (0,1)),
  seat         INT NOT NULL,
  boules_left  INT NOT NULL DEFAULT 3,
  ready        BOOLEAN NOT NULL DEFAULT false,
  is_bot       BOOLEAN NOT NULL DEFAULT false,
  joined_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (game_id, seat)
);
CREATE INDEX IF NOT EXISTS idx_petanque_participants_game ON public.petanque_participants(game_id);

CREATE TABLE IF NOT EXISTS public.petanque_boules (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  game_id       UUID NOT NULL REFERENCES public.petanque_games(id) ON DELETE CASCADE,
  round         INT NOT NULL,
  team          INT NOT NULL,
  player_id     UUID,
  play_order    INT NOT NULL,
  x             DOUBLE PRECISION NOT NULL,
  y             DOUBLE PRECISION NOT NULL,
  dead          BOOLEAN NOT NULL DEFAULT false,
  distance      DOUBLE PRECISION NOT NULL DEFAULT 0,
  angle         DOUBLE PRECISION,
  power         DOUBLE PRECISION,
  spin          DOUBLE PRECISION,
  lob           DOUBLE PRECISION,
  played_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_petanque_boules_game_round ON public.petanque_boules(game_id, round);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.petanque_games TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.petanque_participants TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.petanque_boules TO authenticated;
GRANT ALL ON public.petanque_games TO service_role;
GRANT ALL ON public.petanque_participants TO service_role;
GRANT ALL ON public.petanque_boules TO service_role;

ALTER TABLE public.petanque_games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.petanque_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.petanque_boules ENABLE ROW LEVEL SECURITY;

-- Tout le monde connecté peut voir les parties (comme les autres jeux)
CREATE POLICY "petanque_games_read" ON public.petanque_games FOR SELECT TO authenticated USING (true);
CREATE POLICY "petanque_participants_read" ON public.petanque_participants FOR SELECT TO authenticated USING (true);
CREATE POLICY "petanque_boules_read" ON public.petanque_boules FOR SELECT TO authenticated USING (true);
-- Écritures via RPC SECURITY DEFINER uniquement

ALTER PUBLICATION supabase_realtime ADD TABLE public.petanque_games;
ALTER PUBLICATION supabase_realtime ADD TABLE public.petanque_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.petanque_boules;
ALTER TABLE public.petanque_games REPLICA IDENTITY FULL;
ALTER TABLE public.petanque_participants REPLICA IDENTITY FULL;
ALTER TABLE public.petanque_boules REPLICA IDENTITY FULL;

-- game_configs entry
INSERT INTO public.game_configs (slug, display_name, rules_markdown)
VALUES ('petanque', 'Pétanque',
'Chaque joueur reçoit 3 boules. À tour de rôle, lancez votre boule pour la rapprocher le plus possible du cochonnet (petite boule rouge). À la fin de la mène, l''équipe la plus proche marque autant de points que de boules mieux placées que la meilleure de l''adversaire. Premier à 13 points gagne.')
ON CONFLICT (slug) DO NOTHING;

-- ── Helpers ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._petanque_distance(ax DOUBLE PRECISION, ay DOUBLE PRECISION, bx DOUBLE PRECISION, by_ DOUBLE PRECISION)
RETURNS DOUBLE PRECISION LANGUAGE sql IMMUTABLE AS $$
  SELECT sqrt((ax-bx)*(ax-bx) + (ay-by_)*(ay-by_));
$$;

-- Simulation physique déterministe:
--   throw depuis (-0.9, throw_y), angle en radians (relatif à +x), power [0,1], spin [-1,1], lob [0,1]
--   Retourne (final_x, final_y, dead) après vol parabolique + roulage + drift spin
CREATE OR REPLACE FUNCTION public._petanque_simulate(
  p_throw_y DOUBLE PRECISION,
  p_angle DOUBLE PRECISION,
  p_power DOUBLE PRECISION,
  p_spin DOUBLE PRECISION,
  p_lob DOUBLE PRECISION
) RETURNS TABLE(final_x DOUBLE PRECISION, final_y DOUBLE PRECISION, dead BOOLEAN)
LANGUAGE plpgsql IMMUTABLE AS $$
DECLARE
  fly_dist    DOUBLE PRECISION;
  roll_dist   DOUBLE PRECISION;
  land_x      DOUBLE PRECISION;
  land_y      DOUBLE PRECISION;
  fx          DOUBLE PRECISION;
  fy          DOUBLE PRECISION;
BEGIN
  -- Clamp inputs
  p_power := GREATEST(0.05, LEAST(1.0, p_power));
  p_lob   := GREATEST(0.0, LEAST(1.0, p_lob));
  p_spin  := GREATEST(-1.0, LEAST(1.0, p_spin));
  -- Distance de vol (0.3 à 1.8 depuis x=-0.9)
  fly_dist  := 0.3 + p_power * 1.5;
  -- Roulage : quasi nul si lob=1, jusqu'à 0.35 si lob=0
  roll_dist := (1.0 - p_lob) * p_power * 0.35;
  land_x := -0.9 + cos(p_angle) * fly_dist;
  land_y := p_throw_y + sin(p_angle) * fly_dist;
  -- Après atterrissage : continue tout droit + drift latéral dû au spin
  fx := land_x + cos(p_angle) * roll_dist;
  fy := land_y + sin(p_angle) * roll_dist + p_spin * roll_dist * 0.6;
  -- Terrain : x ∈ [-1, 1.0], y ∈ [-0.45, 0.45]
  IF fx > 1.0 OR fx < -1.0 OR fy > 0.45 OR fy < -0.45 THEN
    RETURN QUERY SELECT fx, fy, true;
  ELSE
    RETURN QUERY SELECT fx, fy, false;
  END IF;
END $$;

-- ── petanque_create ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.petanque_create(
  p_stake NUMERIC DEFAULT 0,
  p_public BOOLEAN DEFAULT true
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_bal NUMERIC;
  v_id  UUID;
  v_code TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  IF p_stake < 0 THEN RAISE EXCEPTION 'invalid stake'; END IF;
  IF p_stake > 0 THEN
    SELECT balance_ar INTO v_bal FROM public.profiles WHERE id = v_uid FOR UPDATE;
    IF v_bal IS NULL OR v_bal < p_stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - p_stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id, type, amount, note)
      VALUES (v_uid, 'stake', -p_stake, 'Mise pétanque');
  END IF;
  IF NOT p_public THEN
    v_code := upper(substring(md5(random()::text || clock_timestamp()::text) FROM 1 FOR 6));
  END IF;
  INSERT INTO public.petanque_games (creator_id, stake, pot, is_private, room_code)
    VALUES (v_uid, p_stake, p_stake, NOT p_public, v_code)
    RETURNING id INTO v_id;
  INSERT INTO public.petanque_participants (game_id, user_id, team, seat, boules_left, ready)
    VALUES (v_id, v_uid, 0, 0, 3, false);
  RETURN v_id;
END $$;

-- ── petanque_join ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.petanque_join(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  g public.petanque_games%ROWTYPE;
  v_bal NUMERIC;
  v_count INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO g FROM public.petanque_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'Partie non disponible'; END IF;
  IF EXISTS (SELECT 1 FROM public.petanque_participants WHERE game_id=_game_id AND user_id=v_uid) THEN
    RETURN;
  END IF;
  SELECT count(*) INTO v_count FROM public.petanque_participants WHERE game_id=_game_id;
  IF v_count >= 2 THEN RAISE EXCEPTION 'Partie complète'; END IF;
  IF g.stake > 0 THEN
    SELECT balance_ar INTO v_bal FROM public.profiles WHERE id=v_uid FOR UPDATE;
    IF v_bal IS NULL OR v_bal < g.stake THEN RAISE EXCEPTION 'insufficient balance'; END IF;
    UPDATE public.profiles SET balance_ar = balance_ar - g.stake WHERE id=v_uid;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'stake', -g.stake, _game_id, 'Mise pétanque');
    UPDATE public.petanque_games SET pot = pot + g.stake WHERE id=_game_id;
  END IF;
  INSERT INTO public.petanque_participants (game_id, user_id, team, seat, boules_left)
    VALUES (_game_id, v_uid, 1, 1, 3);
END $$;

-- ── petanque_join_code ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.petanque_join_code(_code TEXT)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  SELECT id INTO v_id FROM public.petanque_games WHERE room_code = upper(_code) AND status='open';
  IF v_id IS NULL THEN RAISE EXCEPTION 'Code invalide'; END IF;
  PERFORM public.petanque_join(v_id);
  RETURN v_id;
END $$;

-- ── petanque_leave ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.petanque_leave(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  g public.petanque_games%ROWTYPE;
  p public.petanque_participants%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RETURN; END IF;
  SELECT * INTO p FROM public.petanque_participants WHERE game_id=_game_id AND user_id=v_uid;
  IF p.id IS NULL THEN RETURN; END IF;
  IF g.status = 'open' THEN
    -- Remboursement
    IF g.stake > 0 THEN
      UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id=v_uid;
      INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
        VALUES (v_uid,'refund',g.stake,_game_id,'Départ salle d''attente pétanque');
      UPDATE public.petanque_games SET pot = pot - g.stake WHERE id=_game_id;
    END IF;
    DELETE FROM public.petanque_participants WHERE id=p.id;
    -- Si plus personne : supprimer la partie
    IF NOT EXISTS (SELECT 1 FROM public.petanque_participants WHERE game_id=_game_id) THEN
      DELETE FROM public.petanque_games WHERE id=_game_id;
    END IF;
  ELSIF g.status = 'playing' THEN
    -- Forfait : adversaire gagne
    UPDATE public.petanque_games
      SET status='finished', finished_at=now(),
          winner_team = CASE WHEN p.team=0 THEN 1 ELSE 0 END
      WHERE id=_game_id;
    PERFORM public._petanque_settle(_game_id);
  END IF;
END $$;

-- ── petanque_set_ready ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.petanque_set_ready(_game_id UUID, _ready BOOLEAN)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  g public.petanque_games%ROWTYPE;
  v_ready_count INT;
  v_total INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  UPDATE public.petanque_participants SET ready=_ready
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'open' THEN RETURN; END IF;
  SELECT count(*) INTO v_total FROM public.petanque_participants WHERE game_id=_game_id;
  SELECT count(*) INTO v_ready_count FROM public.petanque_participants WHERE game_id=_game_id AND ready=true;
  IF v_total >= 2 AND v_ready_count = v_total THEN
    -- Démarrer : équipe 0 commence
    UPDATE public.petanque_games
      SET status='playing', started_at=now(),
          current_player_id = (SELECT user_id FROM public.petanque_participants WHERE game_id=_game_id AND team=0 ORDER BY seat LIMIT 1),
          turn_deadline = now() + interval '30 seconds'
      WHERE id=_game_id;
  END IF;
END $$;

-- ── Décide quelle équipe joue la boule suivante ───────────────────────────
-- Règle: l'équipe qui n'a PAS la meilleure boule joue ensuite.
--       Si équipe sans boule restante, l'autre finit ses boules.
CREATE OR REPLACE FUNCTION public._petanque_next_player(_game_id UUID)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  g public.petanque_games%ROWTYPE;
  v_best_team INT;
  v_boules_t0 INT;
  v_boules_t1 INT;
  v_next_team INT;
  v_next_uid UUID;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id;
  SELECT COALESCE(sum(boules_left),0) INTO v_boules_t0 FROM public.petanque_participants WHERE game_id=_game_id AND team=0;
  SELECT COALESCE(sum(boules_left),0) INTO v_boules_t1 FROM public.petanque_participants WHERE game_id=_game_id AND team=1;
  IF v_boules_t0 = 0 AND v_boules_t1 = 0 THEN RETURN NULL; END IF;
  IF v_boules_t0 = 0 THEN v_next_team := 1;
  ELSIF v_boules_t1 = 0 THEN v_next_team := 0;
  ELSE
    -- Trouver la meilleure boule (plus proche du cochonnet, non morte)
    SELECT team INTO v_best_team
      FROM public.petanque_boules
      WHERE game_id=_game_id AND round=g.current_round AND dead=false
      ORDER BY distance ASC LIMIT 1;
    IF v_best_team IS NULL THEN
      -- Personne n'a encore joué : équipe 0 commence
      v_next_team := 0;
    ELSE
      v_next_team := CASE WHEN v_best_team=0 THEN 1 ELSE 0 END;
    END IF;
  END IF;
  SELECT user_id INTO v_next_uid FROM public.petanque_participants
    WHERE game_id=_game_id AND team=v_next_team AND boules_left > 0 ORDER BY seat LIMIT 1;
  RETURN v_next_uid;
END $$;

-- ── Termine la mène : calcule points, remet à zéro les boules, prépare next ─
CREATE OR REPLACE FUNCTION public._petanque_end_round(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  g public.petanque_games%ROWTYPE;
  v_best RECORD;
  v_pts INT := 0;
  v_new_x DOUBLE PRECISION;
  v_new_y DOUBLE PRECISION;
  v_starter_team INT;
  v_starter_uid UUID;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  -- Meilleure boule adverse fixe le seuil ; toutes les nôtres plus proches marquent
  SELECT team, distance INTO v_best FROM public.petanque_boules
    WHERE game_id=_game_id AND round=g.current_round AND dead=false
    ORDER BY distance ASC LIMIT 1;
  IF v_best IS NULL THEN
    -- Aucune boule : mène nulle, on continue
    v_starter_team := 0;
  ELSE
    -- Distance de la meilleure adverse
    DECLARE v_opp_best DOUBLE PRECISION;
    BEGIN
      SELECT min(distance) INTO v_opp_best FROM public.petanque_boules
        WHERE game_id=_game_id AND round=g.current_round AND dead=false AND team <> v_best.team;
      IF v_opp_best IS NULL THEN
        -- Adversaire n'a aucune boule valide : compte toutes les nôtres non mortes
        SELECT count(*) INTO v_pts FROM public.petanque_boules
          WHERE game_id=_game_id AND round=g.current_round AND dead=false AND team=v_best.team;
      ELSE
        SELECT count(*) INTO v_pts FROM public.petanque_boules
          WHERE game_id=_game_id AND round=g.current_round AND dead=false AND team=v_best.team
            AND distance < v_opp_best;
      END IF;
      IF v_best.team = 0 THEN
        UPDATE public.petanque_games SET score_team0 = score_team0 + v_pts WHERE id=_game_id;
      ELSE
        UPDATE public.petanque_games SET score_team1 = score_team1 + v_pts WHERE id=_game_id;
      END IF;
      v_starter_team := v_best.team;
    END;
  END IF;

  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id;
  IF g.score_team0 >= g.target_points OR g.score_team1 >= g.target_points THEN
    UPDATE public.petanque_games
      SET status='finished', finished_at=now(),
          winner_team = CASE WHEN g.score_team0 >= g.target_points THEN 0 ELSE 1 END
      WHERE id=_game_id;
    PERFORM public._petanque_settle(_game_id);
    RETURN;
  END IF;

  -- Nouvelle mène
  v_new_x := 0.4 + random()*0.4; -- [0.4, 0.8]
  v_new_y := (random() - 0.5) * 0.3; -- [-0.15, 0.15]
  UPDATE public.petanque_games
    SET current_round = current_round + 1,
        cochonnet_x = v_new_x, cochonnet_y = v_new_y,
        turn_deadline = now() + interval '30 seconds'
    WHERE id=_game_id;
  UPDATE public.petanque_participants SET boules_left = 3 WHERE game_id=_game_id;
  -- L'équipe gagnante lance le cochonnet et la première boule
  SELECT user_id INTO v_starter_uid FROM public.petanque_participants
    WHERE game_id=_game_id AND team=v_starter_team ORDER BY seat LIMIT 1;
  UPDATE public.petanque_games SET current_player_id = v_starter_uid WHERE id=_game_id;
END $$;

-- ── Règle les gains à la fin ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._petanque_settle(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
DECLARE
  g public.petanque_games%ROWTYPE;
  v_pot NUMERIC;
  v_commission NUMERIC;
  v_gain NUMERIC;
  v_winner_uid UUID;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id;
  IF g.winner_team IS NULL OR g.pot <= 0 THEN RETURN; END IF;
  v_pot := g.pot;
  v_commission := round(v_pot * 0.10);
  v_gain := v_pot - v_commission;
  SELECT user_id INTO v_winner_uid FROM public.petanque_participants
    WHERE game_id=_game_id AND team=g.winner_team AND is_bot=false ORDER BY seat LIMIT 1;
  IF v_winner_uid IS NOT NULL THEN
    UPDATE public.profiles SET balance_ar = balance_ar + v_gain WHERE id=v_winner_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_winner_uid,'win',v_gain,_game_id,'Gain pétanque');
  END IF;
END $$;

-- ── petanque_throw ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.petanque_throw(
  _game_id UUID,
  _angle DOUBLE PRECISION,   -- radians, [-0.6, 0.6] recommandé
  _power DOUBLE PRECISION,   -- [0, 1]
  _spin DOUBLE PRECISION,    -- [-1, 1]
  _lob DOUBLE PRECISION      -- [0, 1]
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  g public.petanque_games%ROWTYPE;
  p public.petanque_participants%ROWTYPE;
  v_throw_y DOUBLE PRECISION;
  v_order INT;
  sim RECORD;
  b RECORD;
  v_next UUID;
  v_boules_left_total INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie non en cours'; END IF;
  IF g.current_player_id <> v_uid THEN RAISE EXCEPTION 'Ce n''est pas votre tour'; END IF;
  SELECT * INTO p FROM public.petanque_participants WHERE game_id=_game_id AND user_id=v_uid;
  IF p.id IS NULL OR p.boules_left <= 0 THEN RAISE EXCEPTION 'Aucune boule restante'; END IF;

  v_throw_y := CASE WHEN p.team=0 THEN -0.25 ELSE 0.25 END;
  SELECT COALESCE(max(play_order),0)+1 INTO v_order FROM public.petanque_boules
    WHERE game_id=_game_id AND round=g.current_round;

  SELECT * INTO sim FROM public._petanque_simulate(v_throw_y, _angle, _power, _spin, _lob);

  INSERT INTO public.petanque_boules(game_id, round, team, player_id, play_order, x, y, dead, distance, angle, power, spin, lob)
    VALUES (_game_id, g.current_round, p.team, v_uid, v_order,
            sim.final_x, sim.final_y, sim.dead,
            public._petanque_distance(sim.final_x, sim.final_y, g.cochonnet_x, g.cochonnet_y),
            _angle, _power, _spin, _lob);

  -- Collisions simples : déplace la boule statique la plus proche si impact
  FOR b IN
    SELECT * FROM public.petanque_boules
      WHERE game_id=_game_id AND round=g.current_round AND dead=false AND play_order < v_order
        AND public._petanque_distance(x, y, sim.final_x, sim.final_y) < 0.08
      ORDER BY public._petanque_distance(x, y, sim.final_x, sim.final_y) ASC
      LIMIT 1
  LOOP
    DECLARE
      dx DOUBLE PRECISION := b.x - sim.final_x;
      dy DOUBLE PRECISION := b.y - sim.final_y;
      dist DOUBLE PRECISION := sqrt(dx*dx + dy*dy);
      push DOUBLE PRECISION := (0.08 - dist) + 0.1 * _power;
      nx DOUBLE PRECISION;
      ny DOUBLE PRECISION;
      is_dead BOOLEAN;
    BEGIN
      IF dist < 0.001 THEN dx := 0.01; dy := 0.0; dist := 0.01; END IF;
      nx := b.x + (dx/dist) * push;
      ny := b.y + (dy/dist) * push;
      is_dead := nx > 1.0 OR nx < -1.0 OR ny > 0.45 OR ny < -0.45;
      UPDATE public.petanque_boules
        SET x=nx, y=ny, dead=is_dead,
            distance = public._petanque_distance(nx, ny, g.cochonnet_x, g.cochonnet_y)
        WHERE id=b.id;
    END;
  END LOOP;

  UPDATE public.petanque_participants SET boules_left = boules_left - 1 WHERE id=p.id;

  -- Fin de mène ?
  SELECT COALESCE(sum(boules_left),0) INTO v_boules_left_total FROM public.petanque_participants WHERE game_id=_game_id;
  IF v_boules_left_total = 0 THEN
    PERFORM public._petanque_end_round(_game_id);
    RETURN jsonb_build_object('final_x', sim.final_x, 'final_y', sim.final_y, 'dead', sim.dead, 'round_end', true);
  END IF;

  v_next := public._petanque_next_player(_game_id);
  UPDATE public.petanque_games
    SET current_player_id = v_next, turn_deadline = now() + interval '30 seconds'
    WHERE id=_game_id;

  RETURN jsonb_build_object('final_x', sim.final_x, 'final_y', sim.final_y, 'dead', sim.dead, 'round_end', false);
END $$;

-- ── Bot: joueur normal peut ajouter un bot uniquement en gratuit ──────────
CREATE OR REPLACE FUNCTION public.petanque_add_bot(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid UUID := auth.uid();
  g public.petanque_games%ROWTYPE;
  v_count INT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  IF g.id IS NULL THEN RAISE EXCEPTION 'Partie introuvable'; END IF;
  IF g.status <> 'open' THEN RAISE EXCEPTION 'Partie déjà commencée'; END IF;
  IF g.stake > 0 AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Bots réservés à l''admin pour les parties avec mise';
  END IF;
  IF g.creator_id <> v_uid AND NOT public.has_role(v_uid, 'admin') THEN
    RAISE EXCEPTION 'Seul le créateur peut ajouter un bot';
  END IF;
  SELECT count(*) INTO v_count FROM public.petanque_participants WHERE game_id=_game_id;
  IF v_count >= 2 THEN RAISE EXCEPTION 'Partie complète'; END IF;
  INSERT INTO public.petanque_participants(game_id, user_id, team, seat, boules_left, is_bot, ready)
    VALUES (_game_id, NULL, 1, 1, 3, true, true);
END $$;

-- ── Bot: exécute automatiquement un coup si le tour est au bot ─────────────
-- Appelée par le client (le premier humain) via polling léger.
CREATE OR REPLACE FUNCTION public.petanque_bot_step(_game_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  g public.petanque_games%ROWTYPE;
  p public.petanque_participants%ROWTYPE;
  v_throw_y DOUBLE PRECISION;
  v_dx DOUBLE PRECISION;
  v_dy DOUBLE PRECISION;
  v_angle DOUBLE PRECISION;
  v_power DOUBLE PRECISION;
  v_noise DOUBLE PRECISION;
  v_order INT;
  sim RECORD;
  v_next UUID;
  v_boules_left_total INT;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RETURN; END IF;
  SELECT * INTO p FROM public.petanque_participants
    WHERE game_id=_game_id AND user_id IS NULL AND is_bot=true AND boules_left > 0
    ORDER BY seat LIMIT 1;
  IF p.id IS NULL THEN RETURN; END IF;
  -- Si le tour n'est pas au bot (donc current_player_id est un humain), rien à faire
  IF g.current_player_id IS NOT NULL THEN RETURN; END IF;

  v_throw_y := CASE WHEN p.team=0 THEN -0.25 ELSE 0.25 END;
  v_dx := g.cochonnet_x - (-0.9);
  v_dy := g.cochonnet_y - v_throw_y;
  v_angle := atan2(v_dy, v_dx);
  v_noise := (random() - 0.5) * 0.08; -- bruit sur angle
  v_angle := v_angle + v_noise;
  -- Distance visée -> power
  v_power := LEAST(1.0, GREATEST(0.2, sqrt(v_dx*v_dx + v_dy*v_dy) / 1.7 + (random()-0.5)*0.06));

  SELECT COALESCE(max(play_order),0)+1 INTO v_order FROM public.petanque_boules
    WHERE game_id=_game_id AND round=g.current_round;
  SELECT * INTO sim FROM public._petanque_simulate(v_throw_y, v_angle, v_power, 0, 0.5);

  INSERT INTO public.petanque_boules(game_id, round, team, player_id, play_order, x, y, dead, distance, angle, power, spin, lob)
    VALUES (_game_id, g.current_round, p.team, NULL, v_order,
            sim.final_x, sim.final_y, sim.dead,
            public._petanque_distance(sim.final_x, sim.final_y, g.cochonnet_x, g.cochonnet_y),
            v_angle, v_power, 0, 0.5);

  UPDATE public.petanque_participants SET boules_left = boules_left - 1 WHERE id=p.id;

  SELECT COALESCE(sum(boules_left),0) INTO v_boules_left_total FROM public.petanque_participants WHERE game_id=_game_id;
  IF v_boules_left_total = 0 THEN
    PERFORM public._petanque_end_round(_game_id);
    RETURN;
  END IF;
  v_next := public._petanque_next_player(_game_id);
  UPDATE public.petanque_games
    SET current_player_id = v_next, turn_deadline = now() + interval '30 seconds'
    WHERE id=_game_id;
END $$;

-- Wrapper pour permettre l'affichage: le tour du bot est signalé par current_player_id = NULL
-- Le client (premier humain) appelle petanque_bot_step toutes les ~2 sec quand current_player_id IS NULL.
-- On modifie _petanque_next_player pour retourner NULL si le prochain joueur est un bot.
CREATE OR REPLACE FUNCTION public._petanque_next_player(_game_id UUID)
RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
  g public.petanque_games%ROWTYPE;
  v_best_team INT;
  v_boules_t0 INT;
  v_boules_t1 INT;
  v_next_team INT;
  v_next_uid UUID;
  v_is_bot BOOLEAN;
BEGIN
  SELECT * INTO g FROM public.petanque_games WHERE id=_game_id;
  SELECT COALESCE(sum(boules_left),0) INTO v_boules_t0 FROM public.petanque_participants WHERE game_id=_game_id AND team=0;
  SELECT COALESCE(sum(boules_left),0) INTO v_boules_t1 FROM public.petanque_participants WHERE game_id=_game_id AND team=1;
  IF v_boules_t0 = 0 AND v_boules_t1 = 0 THEN RETURN NULL; END IF;
  IF v_boules_t0 = 0 THEN v_next_team := 1;
  ELSIF v_boules_t1 = 0 THEN v_next_team := 0;
  ELSE
    SELECT team INTO v_best_team FROM public.petanque_boules
      WHERE game_id=_game_id AND round=g.current_round AND dead=false
      ORDER BY distance ASC LIMIT 1;
    IF v_best_team IS NULL THEN v_next_team := 0;
    ELSE v_next_team := CASE WHEN v_best_team=0 THEN 1 ELSE 0 END; END IF;
  END IF;
  SELECT user_id, is_bot INTO v_next_uid, v_is_bot FROM public.petanque_participants
    WHERE game_id=_game_id AND team=v_next_team AND boules_left > 0 ORDER BY seat LIMIT 1;
  IF v_is_bot THEN RETURN NULL; END IF;
  RETURN v_next_uid;
END $$;
