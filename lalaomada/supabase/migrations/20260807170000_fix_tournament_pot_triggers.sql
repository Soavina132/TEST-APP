-- Migration: Fix tournament pot/prize distribution triggers
-- Date: 2026-08-07
-- Fixes: Column name mismatches, double payment bug, missing validation

-- 1. Add missing columns to tournaments table
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS prize_pool numeric DEFAULT 0;
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS reward_distribution jsonb DEFAULT '{"first":60,"second":20,"third":10,"platform":10}'::jsonb;
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS rewards_paid_at timestamptz;
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS winner_id uuid;
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS podium jsonb;
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS platform_cut_ar numeric DEFAULT 0;
ALTER TABLE public.tournaments ADD COLUMN IF NOT EXISTS is_free boolean DEFAULT false;

-- 2. Backfill is_free for existing tournaments
UPDATE public.tournaments SET is_free = true WHERE entry_fee_ar = 0 OR entry_fee_ar IS NULL;
UPDATE public.tournaments SET is_free = false WHERE entry_fee_ar > 0;

-- 3. Backfill prize_pool from prize_pool_ar
UPDATE public.tournaments SET prize_pool = prize_pool_ar WHERE prize_pool IS NULL OR prize_pool = 0;

-- 4. Sync trigger: prize_pool follows prize_pool_ar
CREATE OR REPLACE FUNCTION public._sync_prize_pool()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.prize_pool := NEW.prize_pool_ar;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_prize_pool ON public.tournaments;
CREATE TRIGGER trg_sync_prize_pool
  BEFORE INSERT OR UPDATE OF prize_pool_ar ON public.tournaments
  FOR EACH ROW EXECUTE FUNCTION public._sync_prize_pool();

-- 5. Fix _tournaments_validate: auto-detect is_free, use entry_fee_ar, auto-sync reward_distribution
CREATE OR REPLACE FUNCTION public._tournaments_validate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  d jsonb;
  s numeric;
  wc int;
  p1 numeric; p2 numeric; p3 numeric; pp numeric;
BEGIN
  IF NEW.max_players IS NULL OR NEW.max_players < 2 OR NEW.max_players > 128 THEN
    RAISE EXCEPTION 'Nombre de joueurs invalide (2 a 128).';
  END IF;

  -- Auto-detect is_free from entry_fee_ar
  IF NEW.entry_fee_ar IS NULL OR NEW.entry_fee_ar = 0 THEN
    NEW.is_free := true;
  ELSE
    NEW.is_free := false;
  END IF;

  IF NEW.is_free THEN
    IF COALESCE(NEW.entry_fee_ar, 0) <> 0 THEN
      RAISE EXCEPTION 'Tournoi gratuit : la mise doit etre 0.';
    END IF;
    IF COALESCE(NEW.prize_pool, 0) < 0 THEN
      RAISE EXCEPTION 'Cagnotte invalide (doit etre >= 0).';
    END IF;
    IF COALESCE(NEW.prize_pool, 0) > 100000000 THEN
      RAISE EXCEPTION 'Cagnotte trop elevee (max 100 000 000 Ar).';
    END IF;
  ELSE
    IF COALESCE(NEW.entry_fee_ar, 0) <= 0 THEN
      RAISE EXCEPTION 'La mise doit etre > 0 pour un tournoi payant.';
    END IF;
    IF NEW.entry_fee_ar < 100 THEN
      RAISE EXCEPTION 'Mise minimum : 100 Ar.';
    END IF;
    IF NEW.entry_fee_ar > 10000000 THEN
      RAISE EXCEPTION 'Mise trop elevee (max 10 000 000 Ar).';
    END IF;
  END IF;

  wc := COALESCE(NEW.winners_count, 3);
  IF wc < 1 OR wc > 3 THEN
    RAISE EXCEPTION 'Nombre de vainqueurs invalide (1, 2 ou 3).';
  END IF;
  IF wc >= NEW.max_players THEN
    RAISE EXCEPTION 'Le nombre de vainqueurs doit etre < nombre de joueurs.';
  END IF;
  NEW.winners_count := wc;

  -- Auto-sync reward_distribution from prize_X_pct if not set
  IF NEW.reward_distribution IS NULL THEN
    NEW.reward_distribution := jsonb_build_object(
      'first', COALESCE(NEW.prize_1_pct, 60),
      'second', COALESCE(NEW.prize_2_pct, 20),
      'third', COALESCE(NEW.prize_3_pct, 10),
      'platform', COALESCE(100 - COALESCE(NEW.prize_1_pct, 60) - COALESCE(NEW.prize_2_pct, 20) - COALESCE(NEW.prize_3_pct, 10), 10)
    );
  END IF;

  d := NEW.reward_distribution;
  IF d IS NOT NULL THEN
    p1 := COALESCE((d->>'first')::numeric, 0);
    p2 := COALESCE((d->>'second')::numeric, 0);
    p3 := COALESCE((d->>'third')::numeric, 0);
    pp := COALESCE((d->>'platform')::numeric, 0);

    IF p1 < 0 OR p2 < 0 OR p3 < 0 OR pp < 0 THEN
      RAISE EXCEPTION 'Les parts de recompense ne peuvent pas etre negatives.';
    END IF;

    s := p1 + p2 + p3 + pp;
    IF round(s::numeric, 2) <> 100 THEN
      RAISE EXCEPTION 'La repartition des recompenses doit totaliser 100%% (actuel: %).', s;
    END IF;

    IF wc < 3 AND p3 <> 0 THEN
      RAISE EXCEPTION '3eme part doit etre 0 quand winners_count < 3.';
    END IF;
    IF wc < 2 AND p2 <> 0 THEN
      RAISE EXCEPTION '2eme part doit etre 0 quand winners_count < 2.';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- 6. Fix _trg_third_place_notify: use entrant_ids instead of player_ids
CREATE OR REPLACE FUNCTION public._trg_third_place_notify()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
DECLARE
  trn      record;
  pid      uuid;
  v_title  text;
  v_body   text;
  v_link   text;
BEGIN
  IF COALESCE(NEW.is_third_place, false) = false THEN RETURN NEW; END IF;
  IF COALESCE(array_length(NEW.entrant_ids, 1), 0) < 1 THEN RETURN NEW; END IF;

  SELECT id, name, game_slug INTO trn FROM public.tournaments WHERE id = NEW.tournament_id;
  IF trn.id IS NULL THEN RETURN NEW; END IF;

  IF TG_OP = 'INSERT' AND NEW.status = 'pending' THEN
    v_title := '🥉 Petite finale programmée';
    v_body  := 'Tu joues bientôt pour la 3e place du tournoi « ' || COALESCE(trn.name,'') || ' ». Prépare-toi !';
    v_link  := '/tournaments/' || trn.id;
    FOREACH pid IN ARRAY NEW.entrant_ids LOOP
      IF pid IS NOT NULL THEN
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (pid, 'tournament', 'third_place_scheduled', v_title, v_body, v_link, NEW.id);
      END IF;
    END LOOP;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.game_id IS NULL
     AND NEW.game_id IS NOT NULL THEN
    v_title := '⚔️ Petite finale : ça démarre !';
    v_body  := 'Ta petite finale du tournoi « ' || COALESCE(trn.name,'') || ' » vient de commencer. Rejoins la partie maintenant.';
    v_link  := '/' || COALESCE(trn.game_slug, 'ludo') || '/' || NEW.game_id::text;
    FOREACH pid IN ARRAY NEW.entrant_ids LOOP
      IF pid IS NOT NULL THEN
        INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
        VALUES (pid, 'tournament', 'third_place_started', v_title, v_body, v_link, NEW.id);
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- 7. Fix _trg_third_place_auto_payout: make it a no-op to prevent double payment
-- _t_finish() already handles ALL prize distribution (1st, 2nd, 3rd) at tournament end
CREATE OR REPLACE FUNCTION public._trg_third_place_auto_payout()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
AS $$
BEGIN
  -- No-op: prize distribution is handled by _t_finish() at tournament end
  RETURN NEW;
END;
$$;
