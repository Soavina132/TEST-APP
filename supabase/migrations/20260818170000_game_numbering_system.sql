-- ════════════════════════════════════════════════════════════════════
-- Système de numérotation permanente des parties avec mise
-- ════════════════════════════════════════════════════════════════════

-- ── 1. SEQUENCE globale ─────────────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS public.stake_game_number_seq
  AS bigint START 1 INCREMENT 1 NO MINVALUE NO MAXVALUE CACHE 1;

-- ── 2. TABLE centralisée ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.game_registrations (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  game_number bigint     NOT NULL DEFAULT nextval('public.stake_game_number_seq'),
  game_type   text        NOT NULL,
  game_id     uuid        NOT NULL,
  host_id     uuid,
  stake       numeric     NOT NULL,
  status      text        DEFAULT 'open',
  result      text,
  end_reason  text,
  winner_id   uuid,
  created_at  timestamptz DEFAULT now(),
  started_at  timestamptz,
  finished_at timestamptz,
  UNIQUE (game_number)
);

CREATE INDEX IF NOT EXISTS idx_game_reg_game_id   ON public.game_registrations(game_id);
CREATE INDEX IF NOT EXISTS idx_game_reg_host_id    ON public.game_registrations(host_id);
CREATE INDEX IF NOT EXISTS idx_game_reg_game_type  ON public.game_registrations(game_type);
CREATE INDEX IF NOT EXISTS idx_game_reg_status      ON public.game_registrations(status);
CREATE INDEX IF NOT EXISTS idx_game_reg_created_at  ON public.game_registrations(created_at DESC);

-- ── 3. FONCTION : immutabilité du game_number ───────────────────────
CREATE OR REPLACE FUNCTION public._prevent_game_number_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.game_number IS DISTINCT FROM OLD.game_number THEN
    RAISE EXCEPTION 'game_number est immuable et ne peut pas être modifié';
  END IF;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_prevent_number_change ON public.game_registrations;
CREATE TRIGGER trg_prevent_number_change
  BEFORE UPDATE ON public.game_registrations
  FOR EACH ROW EXECUTE FUNCTION public._prevent_game_number_change();

-- ── 4. FONCTIONS d'auto-enregistrement (par table) ──────────────────
-- Générique pour les tables AVEC host_id
CREATE OR REPLACE FUNCTION public._auto_register_stake_game()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.stake IS NULL OR NEW.stake <= 0 THEN RETURN NEW; END IF;
  INSERT INTO public.game_registrations (game_type, game_id, host_id, stake, status, created_at)
  VALUES (TG_TABLE_NAME, NEW.id, NEW.host_id, NEW.stake, NEW.status, COALESCE(NEW.created_at, now()))
  ON CONFLICT (game_number) DO NOTHING;
  RETURN NEW;
END
$function$;

-- Pour fanorona (host_id existe)
CREATE OR REPLACE FUNCTION public._auto_register_stake_fanorona()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.stake IS NULL OR NEW.stake <= 0 THEN RETURN NEW; END IF;
  INSERT INTO public.game_registrations (game_type, game_id, host_id, stake, status, created_at)
  VALUES ('fanorona_games', NEW.id, NEW.host_id, NEW.stake, NEW.status, COALESCE(NEW.created_at, now()))
  ON CONFLICT (game_number) DO NOTHING;
  RETURN NEW;
END
$function$;

-- Pour rami (pas de host_id)
CREATE OR REPLACE FUNCTION public._auto_register_stake_rami()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.stake IS NULL OR NEW.stake <= 0 THEN RETURN NEW; END IF;
  INSERT INTO public.game_registrations (game_type, game_id, host_id, stake, status, created_at)
  VALUES ('rami_games', NEW.id, NULL, NEW.stake, NEW.status, COALESCE(NEW.created_at, now()))
  ON CONFLICT (game_number) DO NOTHING;
  RETURN NEW;
END
$function$;

-- Pour petanque (pas de host_id)
CREATE OR REPLACE FUNCTION public._auto_register_stake_petanque()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.stake IS NULL OR NEW.stake <= 0 THEN RETURN NEW; END IF;
  INSERT INTO public.game_registrations (game_type, game_id, host_id, stake, status, created_at)
  VALUES ('petanque_games', NEW.id, NULL, NEW.stake, NEW.status, COALESCE(NEW.created_at, now()))
  ON CONFLICT (game_number) DO NOTHING;
  RETURN NEW;
END
$function$;

-- ── 5. TRIGGERS AFTER INSERT sur chaque table ───────────────────────
DROP TRIGGER IF EXISTS trg_register_stake_chess ON public.chess_games;
CREATE TRIGGER trg_register_stake_chess
  AFTER INSERT ON public.chess_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_game();

DROP TRIGGER IF EXISTS trg_register_stake_fanorona ON public.fanorona_games;
CREATE TRIGGER trg_register_stake_fanorona
  AFTER INSERT ON public.fanorona_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_fanorona();

DROP TRIGGER IF EXISTS trg_register_stake_ludo ON public.ludo_games;
CREATE TRIGGER trg_register_stake_ludo
  AFTER INSERT ON public.ludo_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_game();

DROP TRIGGER IF EXISTS trg_register_stake_domino ON public.domino_games;
CREATE TRIGGER trg_register_stake_domino
  AFTER INSERT ON public.domino_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_game();

DROP TRIGGER IF EXISTS trg_register_stake_rami ON public.rami_games;
CREATE TRIGGER trg_register_stake_rami
  AFTER INSERT ON public.rami_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_rami();

DROP TRIGGER IF EXISTS trg_register_stake_penalty ON public.penalty_games;
CREATE TRIGGER trg_register_stake_penalty
  AFTER INSERT ON public.penalty_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_game();

DROP TRIGGER IF EXISTS trg_register_stake_petanque ON public.petanque_games;
CREATE TRIGGER trg_register_stake_petanque
  AFTER INSERT ON public.petanque_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_petanque();

DROP TRIGGER IF EXISTS trg_register_stake_poker ON public.poker_games;
CREATE TRIGGER trg_register_stake_poker
  AFTER INSERT ON public.poker_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_game();

DROP TRIGGER IF EXISTS trg_register_stake_billiard ON public.billiard_games;
CREATE TRIGGER trg_register_stake_billiard
  AFTER INSERT ON public.billiard_games
  FOR EACH ROW EXECUTE FUNCTION public._auto_register_stake_game();

-- ── 6. FONCTION + TRIGGERS de sync au UPDATE ─────────────────────────
CREATE OR REPLACE FUNCTION public._sync_game_registration()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_new jsonb := to_jsonb(NEW);
BEGIN
  UPDATE public.game_registrations SET
    status = v_new->>'status',
    result = v_new->>'result',
    end_reason = v_new->>'end_reason',
    winner_id = NULLIF(v_new->>'winner_id', '')::uuid,
    started_at = COALESCE(NULLIF(v_new->>'started_at','')::timestamptz, started_at),
    finished_at = NULLIF(v_new->>'finished_at','')::timestamptz
  WHERE game_id = NEW.id AND game_type = TG_TABLE_NAME;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS trg_sync_reg_chess ON public.chess_games;
CREATE TRIGGER trg_sync_reg_chess AFTER UPDATE ON public.chess_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_fanorona ON public.fanorona_games;
CREATE TRIGGER trg_sync_reg_fanorona AFTER UPDATE ON public.fanorona_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_ludo ON public.ludo_games;
CREATE TRIGGER trg_sync_reg_ludo AFTER UPDATE ON public.ludo_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_domino ON public.domino_games;
CREATE TRIGGER trg_sync_reg_domino AFTER UPDATE ON public.domino_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_rami ON public.rami_games;
CREATE TRIGGER trg_sync_reg_rami AFTER UPDATE ON public.rami_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_penalty ON public.penalty_games;
CREATE TRIGGER trg_sync_reg_penalty AFTER UPDATE ON public.penalty_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_petanque ON public.petanque_games;
CREATE TRIGGER trg_sync_reg_petanque AFTER UPDATE ON public.petanque_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_poker ON public.poker_games;
CREATE TRIGGER trg_sync_reg_poker AFTER UPDATE ON public.poker_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();
DROP TRIGGER IF EXISTS trg_sync_reg_billiard ON public.billiard_games;
CREATE TRIGGER trg_sync_reg_billiard AFTER UPDATE ON public.billiard_games FOR EACH ROW EXECUTE FUNCTION public._sync_game_registration();

-- ── 7. FONCTION : formatage du numéro ───────────────────────────────
CREATE OR REPLACE FUNCTION public.format_game_number(n bigint)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT '#' || lpad(n::text, 8, '0');
$$;

-- ── 8. FONCTION : recherche admin par numéro ─────────────────────────
CREATE OR REPLACE FUNCTION public.admin_search_game_by_number(_search text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_num bigint;
  v_reg record;
  v_detail jsonb;
  v_participants jsonb;
  v_part_table text;
BEGIN
  v_num := CASE
    WHEN _search ~ '^#?\d+$' THEN regexp_replace(_search, '^#', '')::bigint
    ELSE NULL
  END;
  IF v_num IS NULL THEN RETURN jsonb_build_object('error', 'format invalide'); END IF;

  SELECT * INTO v_reg FROM public.game_registrations WHERE game_number = v_num;
  IF NOT FOUND THEN RETURN jsonb_build_object('error', 'partie introuvable', 'number', v_num); END IF;

  EXECUTE format('SELECT to_jsonb(t) FROM %I t WHERE t.id = $1', v_reg.game_type)
    INTO v_detail USING v_reg.game_id;

  v_part_table := CASE v_reg.game_type
    WHEN 'fanorona_games' THEN 'fanorona_participants'
    WHEN 'ludo_games' THEN 'ludo_participants'
    WHEN 'domino_games' THEN 'domino_participants'
    WHEN 'rami_games' THEN 'rami_participants'
    ELSE NULL
  END;

  IF v_part_table IS NOT NULL THEN
    EXECUTE format('SELECT coalesce(jsonb_agg(to_jsonb(p)), ''[]''::jsonb) FROM %I p WHERE p.game_id = $1', v_part_table)
      INTO v_participants USING v_reg.game_id;
  ELSE
    v_participants := '[]'::jsonb;
  END IF;

  RETURN jsonb_build_object(
    'registration', to_jsonb(v_reg),
    'formatted_number', public.format_game_number(v_reg.game_number),
    'game_detail', v_detail,
    'participants', v_participants
  );
END
$function$;
REVOKE ALL ON FUNCTION public.admin_search_game_by_number(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_search_game_by_number(text) TO authenticated;

-- ── 9. FONCTION : historique joueur ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_player_stake_history(_user_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := COALESCE(_user_id, auth.uid());
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth required'; END IF;

  SELECT coalesce(jsonb_agg(row_to_json(q) ORDER BY q.created_at DESC), '[]'::jsonb) INTO v_result
  FROM (
    SELECT
      gr.game_number,
      public.format_game_number(gr.game_number) as formatted_number,
      gr.game_type,
      gr.game_id,
      gr.stake,
      gr.status,
      gr.result,
      gr.end_reason,
      gr.winner_id,
      gr.created_at,
      gr.started_at,
      gr.finished_at,
      gr.host_id = v_uid as is_host,
      gr.winner_id = v_uid as is_winner,
      CASE
        WHEN gr.finished_at IS NOT NULL AND gr.started_at IS NOT NULL THEN
          EXTRACT(EPOCH FROM (gr.finished_at - gr.started_at))::int
        ELSE NULL
      END as duration_seconds,
      CASE gr.game_type
        WHEN 'chess_games' THEN 'Échecs'
        WHEN 'fanorona_games' THEN 'Fanorona'
        WHEN 'ludo_games' THEN 'Ludo'
        WHEN 'domino_games' THEN 'Domino'
        WHEN 'rami_games' THEN 'Rami'
        WHEN 'penalty_games' THEN 'Penalty'
        WHEN 'petanque_games' THEN 'Pétanque'
        WHEN 'poker_games' THEN 'Poker'
        WHEN 'billiard_games' THEN 'Billard'
        ELSE gr.game_type
      END as game_label
    FROM public.game_registrations gr
    WHERE gr.host_id = v_uid
       OR gr.game_id IN (
         SELECT game_id FROM public.fanorona_participants WHERE user_id = v_uid
         UNION ALL
         SELECT game_id FROM public.ludo_participants WHERE user_id = v_uid
         UNION ALL
         SELECT game_id FROM public.domino_participants WHERE user_id = v_uid
         UNION ALL
         SELECT game_id FROM public.rami_participants WHERE user_id = v_uid
         UNION ALL
         SELECT id FROM public.chess_games WHERE white_id = v_uid OR black_id = v_uid
         UNION ALL
         SELECT game_id FROM public.poker_participants WHERE user_id = v_uid
       )
  ) q;

  RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.get_player_stake_history(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_player_stake_history(uuid) TO authenticated;

-- ── 10. FONCTION : récupérer numéro d'une partie ─────────────────────
CREATE OR REPLACE FUNCTION public.get_game_number(_game_type text, _game_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_num bigint;
BEGIN
  SELECT game_number INTO v_num FROM public.game_registrations WHERE game_type = _game_type AND game_id = _game_id;
  IF v_num IS NULL THEN RETURN NULL; END IF;
  RETURN public.format_game_number(v_num);
END
$function$;
REVOKE ALL ON FUNCTION public.get_game_number(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_number(text, uuid) TO authenticated;

-- ── 11. FONCTION : récupérer numéros pour une liste ─────────────────
CREATE OR REPLACE FUNCTION public.get_game_numbers(_game_type text, _game_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE v_result jsonb;
BEGIN
  SELECT coalesce(jsonb_object_agg(game_id::text, public.format_game_number(game_number)), '{}'::jsonb) INTO v_result
  FROM public.game_registrations WHERE game_type = _game_type AND game_id = ANY(_game_ids);
  RETURN v_result;
END
$function$;
REVOKE ALL ON FUNCTION public.get_game_numbers(text, uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_game_numbers(text, uuid[]) TO authenticated;

-- ── 12. RLS ─────────────────────────────────────────────────────────
ALTER TABLE public.game_registrations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "players_see_own_registrations" ON public.game_registrations;
CREATE POLICY "players_see_own_registrations"
  ON public.game_registrations FOR SELECT
  TO authenticated
  USING (
    host_id = auth.uid()
    OR game_id IN (
      SELECT game_id FROM public.fanorona_participants WHERE user_id = auth.uid()
      UNION ALL
      SELECT game_id FROM public.ludo_participants WHERE user_id = auth.uid()
      UNION ALL
      SELECT game_id FROM public.domino_participants WHERE user_id = auth.uid()
      UNION ALL
      SELECT game_id FROM public.rami_participants WHERE user_id = auth.uid()
      UNION ALL
      SELECT id FROM public.chess_games WHERE white_id = auth.uid() OR black_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "admins_see_all_registrations" ON public.game_registrations;
CREATE POLICY "admins_see_all_registrations"
  ON public.game_registrations FOR SELECT
  TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin')
  );

GRANT SELECT ON public.game_registrations TO authenticated;

