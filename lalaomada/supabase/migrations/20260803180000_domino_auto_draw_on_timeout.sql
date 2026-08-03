-- ═════════════════════════════════════════════════════════════════════════════
-- Migration : Pioche automatique en cas de timeout (Domino)
--
-- Problème : quand un joueur humain n'a AUCUNE tuile jouable et laisse son
-- timer s'écouler (déconnecté / inactif), le serveur le traitait exactement
-- comme un joueur qui REFUSE de jouer un coup valide : incrémentation du
-- compteur turn_skips, pouvant menerà un forfeit après _cfg.max_turn_skips.
--
-- La fonction _domino_auto_draw() existait déjà dans la base mais n'était
-- JAMAIS appelée par domino_tick — elle est maintenant branchée :
--
-- Nouveau comportement au timeout pour un joueur humain :
--   1. A-t-il une tuile jouable ? → comportement inchangé (skip / forfeit
--      après trop d'inactivité alors qu'il pouvait jouer).
--   2. N'a-t-il AUCUNE tuile jouable ?
--      a. Mode "avec pioche" + pioche non vide → on pioche automatiquement
--         à sa place (_domino_auto_draw), tuile après tuile, jusqu'à ce
--         qu'il obtienne une tuile jouable OU que la pioche soit épuisée.
--         S'il obtient une tuile jouable : nouveau délai de 30s, AUCUNE
--         sanction (ce n'était pas de l'inaction volontaire).
--      b. Toujours pas jouable (pioche épuisée ou mode "sans pioche") →
--         passage automatique de son tour (_domino_force_pass), sans
--         sanction non plus — il n'avait tout simplement pas de coup.
-- ═════════════════════════════════════════════════════════════════════════════

-- ── _domino_force_pass : passe le tour du slot donné (utilisé par le tick
--    quand un joueur humain n'a aucune tuile jouable et que la pioche est
--    épuisée). Reprend la même logique que l'action "pass" de domino_play.
CREATE OR REPLACE FUNCTION public._domino_force_pass(_game_id uuid, _slot integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  g record; st jsonb; n_players int; next_turn int; winner_slot int; v_name text;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g.id IS NULL OR g.status <> 'playing' THEN RETURN; END IF;
  IF g.current_turn <> _slot THEN RETURN; END IF; -- le tour a déjà changé, rien à faire

  st := g.state;
  SELECT count(*) INTO n_players FROM public.domino_participants WHERE game_id = _game_id;

  st := jsonb_set(st, '{passes}', to_jsonb(COALESCE((st->>'passes')::int, 0) + 1));
  st := jsonb_set(st, '{last_pass_by}', to_jsonb(_slot));

  SELECT display_name INTO v_name FROM public.domino_participants
    WHERE game_id = _game_id AND slot = _slot;

  PERFORM public._domino_notify_all(_game_id, _slot, 'domino_pass',
    COALESCE(v_name, 'Un joueur') || ' passe son tour',
    COALESCE(v_name, 'Un joueur') || ' n''a pas de tuile jouable',
    '/domino/' || _game_id::text);

  next_turn := public._domino_next_playable_slot(_game_id, _slot, st);

  IF (st->>'passes')::int >= n_players OR next_turn IS NULL THEN
    PERFORM public._domino_notify_all(_game_id, -1, 'domino_blocked',
      '🚫 Domino bloqué !',
      'Personne ne peut jouer — la manche se termine',
      '/domino/' || _game_id::text);
    UPDATE public.domino_games SET state = st WHERE id = _game_id;
    winner_slot := public._domino_lowest_pip_slot(_game_id, st);
    PERFORM public._domino_end_round(_game_id, winner_slot);
    RETURN;
  END IF;

  st := public._domino_arm_bot_think(_game_id, next_turn, st);
  st := jsonb_set(st, '{current_turn}', to_jsonb(next_turn));
  UPDATE public.domino_games
     SET state = st, current_turn = next_turn,
         turn_deadline = now() + interval '30 seconds'
   WHERE id = _game_id;

  PERFORM public._domino_notify(_game_id, next_turn, 'domino_turn',
    'À vous de jouer — Domino',
    'C''est votre tour de jouer',
    '/domino/' || _game_id::text);
END $$;

-- ── domino_tick : branche la pioche automatique avant la logique de
--    sanction (skip/forfeit) pour les joueurs humains sans tuile jouable.
CREATE OR REPLACE FUNCTION public.domino_tick(_game_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $function$
DECLARE
  g record; cur_uid uuid; _cfg record; _skips int; _next int;
  remaining int; last_slot int;
  _break_until timestamptz; _reveal_until timestamptz; _deal_until timestamptz;
  required_slot int; board_empty boolean;
  v_is_bot boolean := false;
  v_think_until timestamptz;
  v_draw_mode text;
  v_stock_len int;
  v_drew_playable boolean;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id = _game_id FOR UPDATE;
  IF g IS NULL OR g.status <> 'playing' THEN RETURN; END IF;

  IF (g.state->>'phase') = 'dealing' THEN
    _deal_until := NULLIF(g.state->>'deal_until','')::timestamptz;
    IF _deal_until IS NOT NULL AND _deal_until <= now() THEN
      PERFORM public._domino_place_first(_game_id);
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'reveal' THEN
    _reveal_until := NULLIF(g.state->>'reveal_until','')::timestamptz;
    IF _reveal_until IS NOT NULL AND _reveal_until <= now() THEN
      UPDATE public.domino_games SET state = jsonb_set(g.state, '{phase}', '"break"'::jsonb) WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  IF (g.state->>'phase') = 'break' THEN
    _break_until := NULLIF(g.state->>'break_until','')::timestamptz;
    IF _break_until IS NOT NULL AND _break_until <= now() THEN
      PERFORM public._domino_next_round(_game_id);
    END IF;
    RETURN;
  END IF;

  SELECT * INTO _cfg FROM public._game_cfg('domino');
  board_empty := jsonb_array_length(COALESCE(g.state->'board', '[]'::jsonb)) = 0;
  required_slot := public._domino_required_starter_slot(_game_id, g.state);

  IF board_empty AND required_slot IS NOT NULL AND required_slot <> g.current_turn THEN
    UPDATE public.domino_games
       SET current_turn = required_slot,
           turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval
     WHERE id = _game_id;
    RETURN;
  END IF;

  -- ── Si c'est un bot, déléguer à _domino_bot_step (qui gère le think timer) ──
  SELECT COALESCE(dp.is_bot, false), dp.user_id
    INTO v_is_bot, cur_uid
    FROM public.domino_participants dp
   WHERE dp.game_id = _game_id
     AND dp.slot = g.current_turn
     AND dp.forfeited = false;

  IF COALESCE(v_is_bot, false) THEN
    v_think_until := NULLIF(g.state->>'bot_think_until','')::timestamptz;
    IF v_think_until IS NOT NULL AND v_think_until <= now() THEN
      PERFORM public._domino_bot_step(_game_id);
    ELSIF v_think_until IS NULL THEN
      PERFORM public._domino_bot_step(_game_id);
    END IF;
    RETURN;
  END IF;

  IF g.turn_deadline IS NULL OR g.turn_deadline > now() THEN RETURN; END IF;

  IF cur_uid IS NULL THEN
    -- Slot vide ou joueur parti — passer au suivant
    _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
    IF _next IS NOT NULL THEN
      UPDATE public.domino_games SET current_turn = _next,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- ═══ NOUVEAU : joueur humain SANS tuile jouable → pioche automatique ═══
  -- Distingue "il a un coup valide et l'ignore" (sanctionné) de "il n'a
  -- simplement aucun coup possible" (pioche auto, puis passe si besoin —
  -- jamais sanctionné dans ce second cas).
  IF NOT public._domino_slot_has_playable(g.state, g.current_turn) THEN
    v_draw_mode := COALESCE(g.state->>'draw_mode', 'with');
    v_stock_len := jsonb_array_length(COALESCE(g.state->'stock', '[]'::jsonb));
    v_drew_playable := false;

    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      v_drew_playable := public._domino_auto_draw(_game_id);
    END IF;

    IF v_drew_playable THEN
      -- Le joueur a désormais une tuile jouable : nouveau délai (déjà posé
      -- par _domino_auto_draw), aucune sanction — il pourra la jouer.
      RETURN;
    END IF;

    -- Toujours aucune tuile jouable (pioche épuisée ou mode sans pioche) :
    -- on passe son tour automatiquement, sans compter cela comme une
    -- inaction fautive.
    PERFORM public._domino_force_pass(_game_id, g.current_turn);
    RETURN;
  END IF;

  -- ── Le joueur A une tuile jouable mais n'a pas joué à temps : sanction ──
  _skips := COALESCE((g.turn_skips->>cur_uid::text)::int, 0) + 1;

  IF _skips >= _cfg.max_turn_skips THEN
    UPDATE public.domino_participants SET forfeited = true WHERE game_id = _game_id AND user_id = cur_uid;
    SELECT count(*) INTO remaining FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false;
    IF remaining <= 1 THEN
      SELECT slot INTO last_slot FROM public.domino_participants WHERE game_id = _game_id AND forfeited = false LIMIT 1;
      IF last_slot IS NOT NULL THEN
        PERFORM public._domino_finalize(_game_id, last_slot);
      ELSE
        UPDATE public.domino_games SET status='cancelled', finished_at=now() WHERE id = _game_id;
      END IF;
      RETURN;
    END IF;
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    g.state := jsonb_set(g.state, ARRAY['hands', g.current_turn::text], '[]'::jsonb, true);
    required_slot := public._domino_required_starter_slot(_game_id, g.state);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET state = g.state, turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
  ELSE
    g.turn_skips := jsonb_set(COALESCE(g.turn_skips,'{}'::jsonb), ARRAY[cur_uid::text], to_jsonb(_skips), true);
    IF board_empty AND required_slot IS NOT NULL THEN
      UPDATE public.domino_games SET turn_skips = g.turn_skips,
        current_turn = required_slot,
        turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
      RETURN;
    END IF;
    UPDATE public.domino_games SET turn_skips = g.turn_skips WHERE id = _game_id;
  END IF;

  _next := public._domino_next_playable_slot(_game_id, g.current_turn, g.state);
  IF _next IS NULL THEN
    _next := public._domino_lowest_pip_slot(_game_id, g.state);
    IF _next IS NOT NULL THEN
      PERFORM public._domino_end_round(_game_id, _next);
    END IF;
    RETURN;
  END IF;

  UPDATE public.domino_games SET current_turn = _next,
    turn_deadline = now() + (_cfg.turn_timer_seconds || ' seconds')::interval WHERE id = _game_id;
END $function$;
