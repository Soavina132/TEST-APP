-- ═════════════════════════════════════════════════════════════════════════════
-- Migration : Correction du blocage de partie Domino
--
-- Problème :
--   Quand un joueur n'a AUCUNE tuile jouable et que la pioche est encore
--   disponible (draw_mode = 'with', stock > 0), la partie reste bloquée :
--     - Le frontend ne pioche pas automatiquement (il attend un clic)
--     - domino_tick ne fait plus la différence entre "joueur inactif qui
--       avait un coup" et "joueur qui n'a simplement aucun coup possible"
--     - _domino_next_playable_slot considère qu'un slot est "jouable" si
--       stock > 0, donc ne renvoie jamais NULL → la manche ne se termine
--       jamais. Les compteurs turn_skips montent jusqu'au forfeit.
--
-- Cause racine :
--   La migration 20260803180000 avait ajouté une logique auto-draw +
--   force-pass dans domino_tick. La migration 20260815200000 a réécrit
--   domino_tick (pour vato maty) et a PERDU cette logique. De plus,
--   _domino_force_pass a été DROPPÉE dans 20260813050000.
--
-- Fix :
--   1. Recréer _domino_force_pass (supprimée par 20260813050000)
--   2. Réintégrer la logique auto-draw/force-pass dans domino_tick,
--      APRÈS la section vato maty et AVANT la section skip/forfeit.
--      Ainsi : un joueur sans tuile jouable → pioche auto si possible,
--      sinon passe sans sanction. Un joueur AVEC tuiles jouables qui
--      ne joue pas → sanction skip/forfeit (comportement inchangé).
-- ═════════════════════════════════════════════════════════════════════════════

-- ── 1. Recréer _domino_force_pass ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._domino_force_pass(_game_id uuid, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE
  g record; st jsonb; n_players int; next_turn int; winner_slot int; v_name text;
  v_playable jsonb;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF g.current_turn <> _slot THEN RETURN; END IF;

  st := g.state;
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(_slot));

  next_turn := public._domino_next_playable_slot(_game_id, _slot, st);

  -- Soit tout le monde a passé, soit personne ne peut jouer → manche bloquée
  IF (st->>'passes')::int >= n_players OR next_turn IS NULL THEN
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  -- Recalculer playable_tiles pour le nouveau joueur courant
  v_playable := public._domino_playable_tiles(st, next_turn);
  st := jsonb_set(st, ARRAY['playable_tiles'], v_playable, true);
  st := public._domino_arm_bot_think(_game_id, next_turn, st);

  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;
END;
$function$;

REVOKE EXECUTE ON FUNCTION public._domino_force_pass(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public._domino_force_pass(uuid, integer) TO authenticated;

-- ── 2. Réintégrer auto-draw/force-pass dans domino_tick ────────────────────
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $func$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  _bot_think timestamptz; v_is_bot boolean := false;
  v_playable jsonb; v_dead_tiles jsonb; v_dead_obj jsonb;
  v_tile_idx int; v_tile_val jsonb; i int; j int;
  v_next_dbl jsonb; first_dbl int; is_dead boolean;
  -- Variables pour auto-draw / force-pass
  v_draw_mode text;
  v_stock_len int;
  v_drew_playable boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN PERFORM public._domino_deal_hands(_game_id); END IF;
    RETURN;
  END IF;
  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN PERFORM public._domino_start_play(_game_id); END IF;
    RETURN;
  END IF;
  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN PERFORM public._domino_start_round(_game_id); END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games SET current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    RETURN;
  END IF;

  _bot_think := NULLIF(g.state->>'bot_think_until', '')::timestamptz;
  IF _bot_think IS NOT NULL AND _bot_think <= now() THEN PERFORM public._domino_bot_step(_game_id); RETURN; END IF;
  IF _bot_think IS NULL THEN
    SELECT COALESCE(dp.is_bot, false) INTO v_is_bot FROM public.domino_participants dp
     WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
    IF v_is_bot THEN PERFORM public._domino_bot_step(_game_id); RETURN; END IF;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  SELECT COALESCE(dp.is_bot, false), dp.user_id INTO v_is_bot, cur_uid
    FROM public.domino_participants dp WHERE dp.game_id = _game_id AND dp.slot = g.current_turn AND dp.forfeited = false;
  IF NOT FOUND THEN
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NULL THEN PERFORM public._domino_end_round(_game_id, NULL);
    ELSE UPDATE public.domino_games SET current_turn = _next, turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; END IF;
    RETURN;
  END IF;
  IF v_is_bot THEN PERFORM public._domino_bot_step(_game_id); RETURN; END IF;

  -- ═══ VATO MATY ═══
  IF COALESCE(g.vato_maty, false) THEN
    first_dbl := NULLIF(g.state->>'first_move_double', 'null')::int;
    IF board_empty AND first_dbl IS NOT NULL THEN
      -- First move with required double: only mark THAT tile as dead
      v_dead_tiles := COALESCE(g.state->'dead_tiles'->g.current_turn::text, '[]'::jsonb);
      FOR i IN 0..jsonb_array_length(COALESCE(g.state->'hands'->g.current_turn::text, '[]'::jsonb))-1 LOOP
        v_tile_val := g.state->'hands'->g.current_turn::text->i;
        IF (v_tile_val->>0)::int = first_dbl AND (v_tile_val->>1)::int = first_dbl THEN
          is_dead := false;
          FOR j IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
            IF (v_dead_tiles->j->>0)::int = (v_tile_val->>0)::int AND (v_dead_tiles->j->>1)::int = (v_tile_val->>1)::int THEN is_dead := true; END IF;
          END LOOP;
          IF NOT is_dead THEN v_dead_tiles := v_dead_tiles || jsonb_build_array(v_tile_val); END IF;
        END IF;
      END LOOP;
      v_dead_obj := COALESCE(g.state->'dead_tiles', '{}'::jsonb);
      v_dead_obj := jsonb_set(v_dead_obj, ARRAY[g.current_turn::text], v_dead_tiles, true);
      g.state := jsonb_set(g.state, ARRAY['dead_tiles'], v_dead_obj, true);
      v_next_dbl := public._domino_find_next_double(_game_id, g.state, first_dbl);
      IF v_next_dbl IS NOT NULL THEN
        g.state := jsonb_set(g.state, '{first_move_double}', to_jsonb((v_next_dbl->>'double')::int), true);
        required_slot := (v_next_dbl->>'slot')::int;
      ELSE
        g.state := jsonb_set(g.state, '{first_move_double}', 'null'::jsonb, true);
        required_slot := NULL;
      END IF;
    ELSE
      -- Normal: mark ALL playable tiles as dead
      v_playable := public._domino_playable_tiles(g.state, g.current_turn);
      IF jsonb_array_length(v_playable) > 0 THEN
        v_dead_tiles := COALESCE(g.state->'dead_tiles'->g.current_turn::text, '[]'::jsonb);
        FOR i IN 0..jsonb_array_length(v_playable)-1 LOOP
          v_tile_idx := (v_playable->i)::int;
          v_tile_val := g.state->'hands'->g.current_turn::text->v_tile_idx;
          is_dead := false;
          FOR j IN 0..jsonb_array_length(v_dead_tiles)-1 LOOP
            IF (v_dead_tiles->j->>0)::int = (v_tile_val->>0)::int AND (v_dead_tiles->j->>1)::int = (v_tile_val->>1)::int THEN is_dead := true; END IF;
          END LOOP;
          IF NOT is_dead THEN v_dead_tiles := v_dead_tiles || jsonb_build_array(v_tile_val); END IF;
        END LOOP;
        v_dead_obj := COALESCE(g.state->'dead_tiles', '{}'::jsonb);
        v_dead_obj := jsonb_set(v_dead_obj, ARRAY[g.current_turn::text], v_dead_tiles, true);
        g.state := jsonb_set(g.state, ARRAY['dead_tiles'], v_dead_obj, true);
      END IF;
    END IF;
  END IF;

  -- ═══ NOUVEAU : joueur SANS tuile jouable → pioche auto ou passe ═══
  -- Distingue "le joueur avait un coup mais n'a pas joué" (sanctionné)
  -- de "le joueur n'a tout simplement aucun coup possible" (pioche auto,
  -- puis passe si besoin — jamais sanctionné dans ce second cas).
  -- NB: ce check se fait APRÈS vato maty car vato maty peut rendre des
  -- tuiles mortes, ce qui fait que le joueur n'a plus de tuile jouable.
  IF NOT public._domino_slot_has_playable(g.state, g.current_turn) THEN
    v_draw_mode := COALESCE(g.state->>'draw_mode', 'with');
    v_stock_len := jsonb_array_length(COALESCE(g.state->'stock', '[]'::jsonb));

    -- Sauvegarder l'état modifié par vato maty avant l'auto-draw
    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      UPDATE public.domino_games SET state = g.state WHERE id = _game_id;
      v_drew_playable := public._domino_auto_draw(_game_id);
      IF v_drew_playable THEN
        -- Le joueur a maintenant une tuile jouable grâce à la pioche auto.
        -- _domino_auto_draw a déjà mis un nouveau turn_deadline. Aucune sanction.
        RETURN;
      END IF;
    END IF;

    -- Toujours aucune tuile jouable (pioche épuisée ou mode sans pioche) :
    -- on passe le tour automatiquement, sans sanction.
    -- Sauvegarder l'état (vato maty a pu modifier g.state) avant force_pass.
    UPDATE public.domino_games SET state = g.state WHERE id = _game_id;
    PERFORM public._domino_force_pass(_game_id, g.current_turn);
    RETURN;
  END IF;

  -- ── Skip/forfeit : le joueur A une tuile jouable mais n'a pas joué ──
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;
  IF _skips >= COALESCE(_cfg.max_turn_skips, 3) THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE UPDATE public.domino_games SET status = 'cancelled', finished_at = now() WHERE id = _game_id; END IF;
      RETURN;
    END IF;
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips, current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips, current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id; RETURN;
    END IF;
  END IF;
  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, _next);
    ELSE
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips WHERE id = _game_id;
      PERFORM public._domino_end_round(_game_id, NULL);
    END IF;
    RETURN;
  END IF;
  UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips, current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END;
$func$;

REVOKE EXECUTE ON FUNCTION public.domino_tick(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.domino_tick(uuid) TO authenticated;
