-- ════════════════════════════════════════════════════════════════════
-- FIX FINAL: domino_play — "invalid input syntax for type json"
-- Cause: la migration 20260811190000 avait RE-ÉCRASÉ domino_play avec
--   une ancienne version qui (1) ne supportait plus tile:[a,b] envoyé
--   par le frontend (retour à tile_idx uniquement) et (2) utilisait
--   NULLIF(st->'left_end','') — comparaison jsonb vs '' qui force
--   Postgres à caster '' en jsonb → erreur "invalid input syntax for
--   type json".
-- Fix: réunit tous les correctifs precedents dans une seule version
--   canonique: support tile_idx OU tile:[a,b] (deux ordres), NULLIF
--   avec ->> (text) partout, jsonb_set avec ARRAY[...] partout.
-- ════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.domino_play(_game_id uuid, _move jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  g public.domino_games%ROWTYPE;
  st jsonb;
  v_slot INT;
  v_uid UUID := auth.uid();
  v_part record;
  v_action TEXT;
  v_tile_idx INT;
  v_side TEXT;
  v_playable jsonb;
  hand jsonb;
  tile jsonb;
  a INT; b INT;
  left_end INT; right_end INT;
  board jsonb;
  first_move_double INT;
  first_tile_rule TEXT;
  v_new_left INT; v_new_right INT;
  v_board_entry jsonb;
  v_passes INT;
  v_last_pass INT;
  v_next_slot INT;
  v_stock_len INT;
  v_draw_mode TEXT;
  i INT;
  v_active_count INT;
BEGIN
  SELECT * INTO g FROM public.domino_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;

  st := g.state;
  v_slot := (st->>'turn_slot')::INT;
  SELECT * INTO v_part FROM public.domino_participants
    WHERE game_id=_game_id AND slot=v_slot;

  IF v_part.user_id IS NOT NULL AND v_part.user_id <> v_uid THEN
    RAISE EXCEPTION 'Pas votre tour';
  END IF;

  v_action := _move->>'action';

  -- ─── PLAY action ──────────────────────────────────────────────
  IF v_action = 'play' THEN
    v_side := COALESCE(_move->>'side', 'auto');
    hand := st->'hands'->v_slot::text;

    -- Support both formats:
    --   1) { action:"play", tile_idx: 2 }  (index dans la main)
    --   2) { action:"play", tile: [3, 5] }  (valeurs de la tuile — format frontend actuel)
    IF _move ? 'tile_idx' AND (_move->>'tile_idx') IS NOT NULL THEN
      v_tile_idx := (_move->>'tile_idx')::INT;
    ELSIF _move ? 'tile' THEN
      tile := _move->'tile';
      v_tile_idx := -1;
      IF jsonb_array_length(hand) > 0 THEN
        FOR i IN 0..jsonb_array_length(hand)-1 LOOP
          IF ((hand->i->>0)::INT = (tile->>0)::INT AND (hand->i->>1)::INT = (tile->>1)::INT)
             OR ((hand->i->>0)::INT = (tile->>1)::INT AND (hand->i->>1)::INT = (tile->>0)::INT) THEN
            v_tile_idx := i;
            EXIT;
          END IF;
        END LOOP;
      END IF;
      IF v_tile_idx = -1 THEN
        RAISE EXCEPTION 'Tuile non trouvée dans la main: %', tile;
      END IF;
    ELSE
      RAISE EXCEPTION 'Move doit contenir tile ou tile_idx';
    END IF;

    v_playable := public._domino_playable_tiles(st, v_slot);
    IF NOT (v_playable @> to_jsonb(v_tile_idx)) THEN
      RAISE EXCEPTION 'Tuile non jouable';
    END IF;

    tile := hand->v_tile_idx;
    a := (tile->>0)::INT;
    b := (tile->>1)::INT;
    board := st->'board';
    -- IMPORTANT: ->> (text) pour NULLIF, jamais -> (jsonb) — sinon
    -- Postgres tente de caster '' en jsonb → "invalid input syntax for type json"
    left_end := NULLIF(st->>'left_end','')::INT;
    right_end := NULLIF(st->>'right_end','')::INT;
    first_move_double := NULLIF(st->>'first_move_double','')::INT;
    first_tile_rule := COALESCE(st->>'first_tile_rule', 'libre');

    IF jsonb_array_length(board) = 0 THEN
      IF first_move_double IS NOT NULL THEN
        IF NOT (a = first_move_double AND b = first_move_double) THEN
          RAISE EXCEPTION 'Doit jouer le double %', first_move_double;
        END IF;
      ELSIF first_tile_rule = 'under6' THEN
        IF a + b >= 6 THEN RAISE EXCEPTION 'Somme doit etre < 6'; END IF;
      END IF;
      v_new_left := a;
      v_new_right := b;
      v_board_entry := jsonb_build_array(jsonb_build_object('t', jsonb_build_array(a,b), 'slot', v_slot));
      st := jsonb_set(st, ARRAY['board'], v_board_entry);
      st := jsonb_set(st, ARRAY['left_end'], to_jsonb(v_new_left));
      st := jsonb_set(st, ARRAY['right_end'], to_jsonb(v_new_right));
      st := st - 'first_move_double';
    ELSE
      IF v_side = 'left' OR (v_side = 'auto' AND (a = left_end OR b = left_end)) THEN
        IF b = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('t', jsonb_build_array(b,a), 'slot', v_slot)) || board;
        ELSIF a = left_end THEN
          v_board_entry := jsonb_build_array(jsonb_build_object('t', jsonb_build_array(a,b), 'slot', v_slot)) || board;
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté gauche';
        END IF;
        v_new_left := CASE WHEN b = left_end THEN a ELSE b END;
        v_new_right := right_end;
        st := jsonb_set(st, ARRAY['board'], v_board_entry);
        st := jsonb_set(st, ARRAY['left_end'], to_jsonb(v_new_left));
      ELSIF v_side = 'right' OR (v_side = 'auto' AND (a = right_end OR b = right_end)) THEN
        IF a = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('t', jsonb_build_array(a,b), 'slot', v_slot));
        ELSIF b = right_end THEN
          v_board_entry := board || jsonb_build_array(jsonb_build_object('t', jsonb_build_array(b,a), 'slot', v_slot));
        ELSE
          RAISE EXCEPTION 'Ne match pas le côté droit';
        END IF;
        v_new_left := left_end;
        v_new_right := CASE WHEN a = right_end THEN b ELSE a END;
        st := jsonb_set(st, ARRAY['board'], v_board_entry);
        st := jsonb_set(st, ARRAY['right_end'], to_jsonb(v_new_right));
      ELSE
        RAISE EXCEPTION 'Tuile ne match ni gauche ni droite';
      END IF;
    END IF;

    -- Remove tile from hand
    hand := hand - v_tile_idx;
    -- IMPORTANT: mettre à jour hands DANS st (jsonb_set sur st->'hands' avec ARRAY path),
    -- puis réassigner dans st — jamais remplacer st par le résultat partiel
    st := jsonb_set(st, ARRAY['hands'], jsonb_set(st->'hands', ARRAY[v_slot::text], hand));

    -- Reset passes
    st := jsonb_set(st, ARRAY['passes'], '0'::jsonb);
    st := jsonb_set(st, ARRAY['last_pass_by'], 'null'::jsonb);

    -- Check if hand is empty (round winner)
    IF jsonb_array_length(hand) = 0 THEN
      PERFORM public._domino_end_round(_game_id, v_slot);
      RETURN public._domino_visible(_game_id);
    END IF;

    -- Advance turn
    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot));
    st := jsonb_set(st, ARRAY['turn_started_at'], to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('play'));

    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── DRAW action ──────────────────────────────────────────────
  ELSIF v_action = 'draw' THEN
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_stock_len = 0 THEN RAISE EXCEPTION 'Stock vide'; END IF;
    hand := st->'hands'->v_slot::text;
    tile := st->'stock'->0;
    st := jsonb_set(st, ARRAY['stock'], st->'stock' - 0);
    hand := hand || tile;
    st := jsonb_set(st, ARRAY['hands'], jsonb_set(st->'hands', ARRAY[v_slot::text], hand));
    v_playable := public._domino_playable_tiles(st, v_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('draw'));
    UPDATE public.domino_games SET state=st WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  -- ─── PASS action ───────────────────────────────────────────────
  ELSIF v_action = 'pass' THEN
    v_playable := public._domino_playable_tiles(st, v_slot);
    IF jsonb_array_length(v_playable) > 0 THEN
      RAISE EXCEPTION 'Vous avez un domino jouable';
    END IF;
    v_draw_mode := COALESCE(st->>'draw_mode', 'with');
    v_stock_len := COALESCE(jsonb_array_length(st->'stock'), 0);
    IF v_draw_mode = 'with' AND v_stock_len > 0 THEN
      RAISE EXCEPTION 'Vous devez piocher avant de passer';
    END IF;

    v_passes := COALESCE((st->>'passes')::INT, 0) + 1;
    v_last_pass := v_slot;
    st := jsonb_set(st, ARRAY['passes'], to_jsonb(v_passes));
    st := jsonb_set(st, ARRAY['last_pass_by'], to_jsonb(v_last_pass));

    SELECT count(*) INTO v_active_count FROM public.domino_participants
      WHERE game_id=_game_id AND NOT forfeited;
    IF v_passes >= v_active_count THEN
      PERFORM public._domino_end_round(_game_id, public._domino_lowest_pip_slot(_game_id, st));
      RETURN public._domino_visible(_game_id);
    END IF;

    v_next_slot := public._domino_next_playable_slot(_game_id, v_slot, st);
    st := jsonb_set(st, ARRAY['turn_slot'], to_jsonb(v_next_slot));
    st := jsonb_set(st, ARRAY['turn_started_at'], to_jsonb(to_char(now() AT TIME ZONE 'UTC','YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')));
    v_playable := public._domino_playable_tiles(st, v_next_slot);
    st := jsonb_set(st, ARRAY['playable_tiles'], v_playable);
    st := jsonb_set(st, ARRAY['last_event'], to_jsonb('pass'));
    UPDATE public.domino_games SET state=st, current_turn=v_next_slot WHERE id=_game_id;
    RETURN public._domino_visible(_game_id);

  ELSE
    RAISE EXCEPTION 'Action inconnue: %', v_action;
  END IF;
END
$$;

GRANT EXECUTE ON FUNCTION public.domino_play(uuid, jsonb) TO authenticated;
