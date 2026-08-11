-- ═══════════════════════════════════════════════════════════════════════
-- FIX: 2 bugs critiques — le 1er joueur ne peut pas cliquer le dé au Ludo
--
--   A. ludo_start_solo_bot ne démarre jamais la partie (status='open')
--      → le joueur arrive dans la salle d'attente au lieu du plateau
--
--   B. Deux surcharges de _ludo_init_state coexistent :
--      _ludo_init_state(INT)               → IMMUTABLE, timestamp SANS ms
--      _ludo_init_state(INT, TEXT DEFAULT)  → SECURITY DEFINER, timestamp AVEC ms
--      ludo_set_ready appelle la 1-arg → ancienne version → timing issues
-- ═══════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════
-- BUG B: Dropper l'ancienne surcharge _ludo_init_state(INT)
-- Tous les appelants à 1 arg utiliseront maintenant la 2-args (DEFAULT)
-- ═══════════════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public._ludo_init_state(integer);

-- Sécurité : vérifier que la 2-args existe toujours
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = '_ludo_init_state'
  ) THEN
    RAISE EXCEPTION '_ludo_init_state introuvable après DROP — migration 20260811090000 manquante ?';
  END IF;
END $$;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG B (suite): ludo_set_ready — passer le mode à _ludo_init_state
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ludo_set_ready(_game_id uuid, _ready boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public
AS $function$
DECLARE v_uid UUID := auth.uid(); v_game public.ludo_games%ROWTYPE;
  v_total int; v_ready int; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  SELECT phone_verified INTO v_verified FROM public.profiles WHERE id=v_uid;
  IF _ready AND NOT COALESCE(v_verified,false) THEN
    RAISE EXCEPTION 'Vérifiez votre numéro de téléphone dans votre profil';
  END IF;
  SELECT * INTO v_game FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF v_game.id IS NULL OR v_game.status <> 'open' THEN RAISE EXCEPTION 'Partie non ouverte'; END IF;
  UPDATE public.ludo_participants SET ready=_ready, last_seen=now()
    WHERE game_id=_game_id AND user_id=v_uid;
  SELECT count(*), count(*) FILTER (WHERE ready OR is_bot)
    INTO v_total, v_ready
    FROM public.ludo_participants WHERE game_id=_game_id;
  IF v_total = v_game.max_players AND v_ready = v_total THEN
    UPDATE public.ludo_games SET status='playing', started_at=now(),
      state=public._ludo_init_state(v_game.max_players, COALESCE(v_game.mode, 'classic')),
      current_turn = 0
    WHERE id=_game_id;
  END IF;
END $function$;

REVOKE EXECUTE ON FUNCTION public.ludo_set_ready(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ludo_set_ready(uuid, boolean) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG A: ludo_start_solo_bot — auto-démarrer la partie
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.ludo_start_solo_bot(
  _max_players integer DEFAULT 2,
  _stake numeric DEFAULT 0,
  _mode text DEFAULT 'classic',
  _match_type text DEFAULT 'solo'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_game_id uuid;
  v_name text;
  v_intel int := 70;
  v_colors4 text[] := ARRAY['red','blue','green','yellow'];
  v_colors3 text[] := ARRAY['red','green','yellow'];
  v_colors2 text[] := ARRAY['red','yellow'];
  v_color text;
  i int;
  v_bot_names text[] := ARRAY['Bot Rina','Bot Naina','Bot Toky','Bot Sanda'];
  v_balance numeric;
  v_commission numeric;
  v_team int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Non authentifié'; END IF;
  IF _max_players < 2 OR _max_players > 4 THEN
    RAISE EXCEPTION 'max_players doit être entre 2 et 4';
  END IF;
  SELECT balance_ar INTO v_balance FROM public.profiles WHERE id = v_uid FOR UPDATE;
  IF v_balance < _stake THEN RAISE EXCEPTION 'Solde insuffisant'; END IF;

  SELECT game_commission_pct INTO v_commission FROM public.app_settings WHERE id=1;

  INSERT INTO public.ludo_games(host_id, max_players, stake, pot, commission_pct,
                                is_private, mode, match_type, status, is_solo)
  VALUES (v_uid, _max_players, _stake, _stake, COALESCE(v_commission,0),
          TRUE, COALESCE(_mode,'classic'), COALESCE(_match_type,'solo'), 'open', TRUE)
  RETURNING id INTO v_game_id;

  IF _stake > 0 THEN
    UPDATE public.profiles SET balance_ar = balance_ar - _stake WHERE id = v_uid;
    INSERT INTO public.transactions(user_id,type,amount,ref_id,note)
      VALUES (v_uid,'stake',-_stake,v_game_id,'Mise création partie solo bot');
  END IF;

  SELECT COALESCE(NULLIF(trim(pseudo),''),'Joueur') INTO v_name
    FROM public.profiles WHERE id = v_uid;

  IF _match_type = 'groupe' THEN v_team := 1; ELSE v_team := NULL; END IF;

  IF _max_players = 2 THEN v_color := v_colors2[1];
  ELSIF _max_players = 3 THEN v_color := v_colors3[1];
  ELSE v_color := v_colors4[1];
  END IF;

  INSERT INTO public.ludo_participants(game_id, user_id, slot, color, display_name, ready, team)
  VALUES (v_game_id, v_uid, 0, v_color, COALESCE(v_name,'Joueur'), TRUE, v_team);

  FOR i IN 1..(_max_players-1) LOOP
    IF _max_players = 2 THEN v_color := v_colors2[i+1];
    ELSIF _max_players = 3 THEN v_color := v_colors3[i+1];
    ELSE v_color := v_colors4[i+1];
    END IF;
    IF _match_type = 'groupe' THEN
      v_team := CASE WHEN i % 2 = 0 THEN 1 ELSE 2 END;
    ELSE
      v_team := NULL;
    END IF;
    INSERT INTO public.ludo_participants(
      game_id, user_id, slot, color, is_bot, bot_name, display_name,
      bot_intelligence, bot_win_bias, ready, team
    ) VALUES (
      v_game_id, NULL, i, v_color, TRUE,
      v_bot_names[i], v_bot_names[i], v_intel, 0, TRUE, v_team
    );
  END LOOP;

  -- ═══ AUTO-START: tous les participants sont prêts → démarrer immédiatement
  UPDATE public.ludo_games
    SET status = 'playing',
        started_at = now(),
        state = public._ludo_init_state(_max_players, COALESCE(_mode, 'classic')),
        current_turn = 0
    WHERE id = v_game_id;

  RETURN v_game_id;
END $$;

REVOKE EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) FROM anon;
GRANT EXECUTE ON FUNCTION public.ludo_start_solo_bot(integer, numeric, text, text) TO authenticated;

-- ═══════════════════════════════════════════════════════════════════════
-- BUG B (suite): _ludo_ensure_state — passer le mode aussi
-- ═══════════════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._ludo_ensure_state(_game_id UUID) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE g public.ludo_games%ROWTYPE; st jsonb;
BEGIN
  SELECT * INTO g FROM public.ludo_games WHERE id=_game_id FOR UPDATE;
  IF g.status <> 'playing' THEN RAISE EXCEPTION 'Partie pas en cours'; END IF;
  IF (g.state ? 'pawns') IS NOT TRUE OR g.state->'pawns' = '{}'::jsonb THEN
    st := public._ludo_init_state(g.max_players, COALESCE(g.mode, 'classic'));
    UPDATE public.ludo_games SET state=st, current_turn=0 WHERE id=_game_id;
    RETURN st;
  END IF;
  RETURN g.state;
END $$;
