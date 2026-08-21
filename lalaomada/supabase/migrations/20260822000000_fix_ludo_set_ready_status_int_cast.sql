-- ═══════════════════════════════════════════════════════════════════════════
-- FIX: ludo_set_ready crashed with "invalid input syntax for type integer: 'open'"
--
-- The variable v_total was declared as `int` but was first used to store the
-- game status (a game_status enum, e.g. "open"). PostgreSQL tried to cast
-- "open" to integer → crash on every "Je suis prêt" click.
--
-- Fix: added a separate `v_status text` variable for the status check,
-- keeping `v_total int` for the later count(*) assignment.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_status text; v_total int; v_ready int; v_verified boolean;
  v_slots int[];
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
  IF _ready AND NOT COALESCE(v_verified,false) THEN
    RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
  END IF;

  -- Fast check without locking: if game already started, just mark ready and return
  SELECT status::text INTO v_status FROM public.ludo_games WHERE id=_game_id;
  IF v_status IN ('playing', 'finished', 'cancelled') THEN
    UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
      WHERE game_id=_game_id AND user_id=v_uid;
    RETURN;
  END IF;

  -- Lock the row for the start-game logic
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN
    UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
      WHERE game_id=_game_id AND user_id=v_uid;
    RETURN;
  END IF;

  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;

  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready FROM public.ludo_participants WHERE game_id=_game_id;

  IF v_total = v_game.max_players AND v_ready = v_total THEN
    SELECT array_agg(slot) INTO v_slots FROM public.ludo_participants WHERE game_id=_game_id;
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode,'classic')),
      current_turn = v_slots[1 + public._crypto_rand_int(array_length(v_slots,1))]
      WHERE id=_game_id;
  END IF;
END;
$function$;
