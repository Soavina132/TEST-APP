-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: Bug 1, 2, 6 (audit Ludo)
--
-- Bug 1 (CRITIQUE): ludo_quit ne renvoie pas les pions à la base
--   Les pions sont stockés comme un objet {"0":[...],"1":[...]} et non
--   comme un array. Le code essayait jsonb_typeof = 'array' → jamais vrai.
--   Les pions restaient sur le plateau et bloquaient les autres joueurs.
--   FIX: Même pattern que _ludo_check_afk (jsonb_set sur le slot).
--
-- Bug 2 (CRITIQUE): ludo_quit en mode "open" détruisait toute la partie
--   _ludo_purge supprime la partie ET tous les autres participants.
--   Si le joueur B quitte, le joueur A est aussi éjecté.
--   FIX: Ne supprimer la partie que si plus aucun participant ne reste.
--
-- Bug 6: _ludo_check_afk appelait directement _ludo_check_last_standing
--   au lieu de _ludo_check_game_over, contournant le check "tous les
--   pions arrivés" et la logique solo/groupe.
--   FIX: Remplacer par _ludo_check_game_over qui gère tous les cas.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 1 + Bug 2: ludo_quit
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_quit(_game_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  g public.ludo_games%ROWTYPE;
  v_slot INT;
  st jsonb;
  v_pawns jsonb;
  i INT;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status NOT IN ('playing','open') THEN RAISE EXCEPTION 'Partie terminée'; END IF;

  SELECT slot INTO v_slot FROM public.ludo_participants
    WHERE game_id=_game_id AND user_id=v_uid AND is_bot=false;
  IF v_slot IS NULL THEN RAISE EXCEPTION 'Non participant'; END IF;

  -- ═══ Si partie en attente (open): remboursement simple ═══
  IF g.status = 'open' THEN
    UPDATE public.profiles SET balance_ar = balance_ar + g.stake WHERE id = v_uid;
    UPDATE public.ludo_games SET pot = pot - g.stake WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'refund', g.stake, _game_id, 'Quitter salle d''attente');
    DELETE FROM public.ludo_participants WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;
    -- Bug 2 fix: ne supprimer la partie que si plus aucun participant
    IF NOT EXISTS (SELECT 1 FROM public.ludo_participants WHERE game_id = _game_id) THEN
      DELETE FROM public.chat_rooms WHERE game_id = _game_id;
      DELETE FROM public.game_spectators WHERE game_id = _game_id;
      DELETE FROM public.game_invitations WHERE game_id = _game_id;
      DELETE FROM public.ludo_games WHERE id = _game_id;
    END IF;
    RETURN;
  END IF;

  -- ═══ Partie en cours : forfait ═══
  -- Bug 1 fix: renvoyer les pions du joueur à la base (même pattern que _ludo_check_afk)
  -- Avant: le code essayait jsonb_typeof = 'array' sur un objet → jamais vrai → pions restaient sur le plateau
  st := g.state;
  IF st IS NOT NULL AND st ? 'pawns' AND (st->'pawns') ? v_slot::text THEN
    v_pawns := '[]'::jsonb;
    FOR i IN 1..4 LOOP
      v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
    END LOOP;
    st := jsonb_set(st, ARRAY['pawns', v_slot::text], v_pawns);
    UPDATE public.ludo_games SET state = st WHERE id = _game_id;
  END IF;

  -- Mark player as forfeited
  UPDATE public.ludo_participants SET forfeited = true
    WHERE game_id = _game_id AND user_id = v_uid AND is_bot = false;

  -- ✅ Use _ludo_check_game_over (handles winner detection + finish_game call)
  PERFORM public._ludo_check_game_over(_game_id);
END;
$function$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Bug 6: _ludo_check_afk — remplacer _ludo_check_last_standing par _ludo_check_game_over
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._ludo_check_afk(_game_id uuid, _slot integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_t1      int;
  v_t2      int;
  v_max1    int;
  v_max2    int;
  v_enabled boolean;
  v_uid     uuid;
  v_isbot   boolean;
  v_name    text;
  g        public.ludo_games%ROWTYPE;
  st       jsonb;
  v_pawns  jsonb;
  i        int;
BEGIN
  SELECT afk_enabled, afk_t1_max, afk_t2_max
    INTO v_enabled, v_max1, v_max2
    FROM public.app_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, TRUE) THEN RETURN; END IF;

  SELECT afk_t1, afk_t2, user_id, is_bot, display_name
    INTO v_t1, v_t2, v_uid, v_isbot, v_name
    FROM public.ludo_participants
   WHERE game_id = _game_id AND slot = _slot;
  IF v_isbot THEN RETURN; END IF;

  -- ── Seuil forfait : T1 >= max OU T2 >= max ──
  IF v_t1 >= COALESCE(v_max1, 5) OR v_t2 >= COALESCE(v_max2, 2) THEN
    UPDATE public.ludo_participants
       SET forfeited = TRUE
     WHERE game_id = _game_id AND slot = _slot;

    -- Send all forfeited player's pawns back to the yard
    SELECT * INTO g FROM public.ludo_games WHERE id = _game_id FOR UPDATE;
    st := g.state;
    IF st ? 'pawns' AND (st->'pawns') ? _slot::text THEN
      v_pawns := '[]'::jsonb;
      FOR i IN 1..4 LOOP
        v_pawns := v_pawns || jsonb_build_object('s','yard','k',-1);
      END LOOP;
      st := jsonb_set(st, ARRAY['pawns', _slot::text], v_pawns);
      UPDATE public.ludo_games SET state = st WHERE id = _game_id;
    END IF;

    UPDATE public.ludo_games
       SET afk_warning   = NULL,
           afk_pause_for  = NULL,
           afk_pause_name = NULL
     WHERE id = _game_id;
    INSERT INTO public.transactions(user_id, type, amount, ref_id, note)
      VALUES (v_uid, 'forfeit', 0, _game_id,
              'Exclusion AFK (T1=' || v_t1 || ' T2=' || v_t2 || ')');

    -- Bug 6 fix: utiliser _ludo_check_game_over au lieu de _ludo_check_last_standing
    -- _ludo_check_game_over gère TOUS les cas:
    --   - tous les pions arrivés (nouveau check 2v2)
    --   - solo mode avec plus d'humains
    --   - dernier joueur restant (last standing)
    PERFORM public._ludo_check_game_over(_game_id);
    RETURN;
  END IF;

  -- ── Seuil avertissement : T1 = max-1 OU T2 = max-1 ──
  IF v_t1 = COALESCE(v_max1, 5) - 1 OR v_t2 = COALESCE(v_max2, 2) - 1 THEN
    UPDATE public.ludo_games
       SET afk_warning = jsonb_build_object(
             'uid',    v_uid,
             'name',   COALESCE(v_name, 'Joueur'),
             'slot',   _slot,
             't1',     v_t1,
             't1_max', COALESCE(v_max1, 5),
             't2',     v_t2,
             't2_max', COALESCE(v_max2, 2),
             'ts',     extract(epoch from now())::bigint
           )
     WHERE id = _game_id
       AND COALESCE(paused, false) = FALSE
       AND (afk_warning IS NULL
            OR (afk_warning->>'uid')::uuid IS DISTINCT FROM v_uid);
  END IF;
END $function$;
