
-- 1) New columns on tournaments
ALTER TABLE public.tournaments
  ADD COLUMN IF NOT EXISTS max_concurrent_matches integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS wave_gap_min integer NOT NULL DEFAULT 15;

ALTER TABLE public.tournaments
  DROP CONSTRAINT IF EXISTS tournaments_max_concurrent_matches_check;
ALTER TABLE public.tournaments
  ADD CONSTRAINT tournaments_max_concurrent_matches_check CHECK (max_concurrent_matches >= 1 AND max_concurrent_matches <= 64);

ALTER TABLE public.tournaments
  DROP CONSTRAINT IF EXISTS tournaments_wave_gap_min_check;
ALTER TABLE public.tournaments
  ADD CONSTRAINT tournaments_wave_gap_min_check CHECK (wave_gap_min >= 1 AND wave_gap_min <= 240);

-- 2) New columns on tournament_matches
ALTER TABLE public.tournament_matches
  ADD COLUMN IF NOT EXISTS scheduled_at timestamptz,
  ADD COLUMN IF NOT EXISTS notified_marks jsonb NOT NULL DEFAULT '{}'::jsonb;

CREATE INDEX IF NOT EXISTS idx_tm_scheduled_at
  ON public.tournament_matches (tournament_id, scheduled_at)
  WHERE status = 'pending' AND scheduled_at IS NOT NULL;

-- 3) Wave assigner
CREATE OR REPLACE FUNCTION public._tournament_assign_waves(_tid uuid, _round integer)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_t public.tournaments%ROWTYPE;
  v_cap integer;
  v_gap interval;
  v_base timestamptz;
  v_prev_max timestamptz;
BEGIN
  SELECT * INTO v_t FROM public.tournaments WHERE id = _tid;
  IF NOT FOUND THEN RETURN; END IF;

  v_cap := GREATEST(COALESCE(v_t.max_concurrent_matches, 5), 1);
  v_gap := (GREATEST(COALESCE(v_t.wave_gap_min, 15), 1) || ' min')::interval;

  -- Base = last scheduled time of previous round + one gap, else tournament start, else now()+5min
  IF _round > 1 THEN
    SELECT MAX(scheduled_at) INTO v_prev_max
      FROM public.tournament_matches
     WHERE tournament_id = _tid AND round = _round - 1;
  END IF;

  IF v_prev_max IS NOT NULL THEN
    v_base := v_prev_max + v_gap;
  ELSE
    v_base := COALESCE(v_t.starts_at, now() + interval '5 min');
    IF v_base < now() + interval '2 min' THEN
      v_base := now() + interval '5 min';
    END IF;
  END IF;

  WITH ordered AS (
    SELECT id,
           ROW_NUMBER() OVER (ORDER BY match_index) - 1 AS rn
      FROM public.tournament_matches
     WHERE tournament_id = _tid
       AND round = _round
       AND NOT is_bye
  )
  UPDATE public.tournament_matches m
     SET wave = (o.rn / v_cap)::integer,
         scheduled_at = v_base + ((o.rn / v_cap)::integer) * v_gap
    FROM ordered o
   WHERE m.id = o.id;
END $fn$;

-- 4) Trigger: after inserting matches for a round, assign waves
CREATE OR REPLACE FUNCTION public._trg_tournament_matches_assign_waves()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT tournament_id, round FROM new_matches LOOP
    PERFORM public._tournament_assign_waves(r.tournament_id, r.round);
  END LOOP;
  RETURN NULL;
END $fn$;

DROP TRIGGER IF EXISTS trg_tm_assign_waves ON public.tournament_matches;
CREATE TRIGGER trg_tm_assign_waves
AFTER INSERT ON public.tournament_matches
REFERENCING NEW TABLE AS new_matches
FOR EACH STATEMENT EXECUTE FUNCTION public._trg_tournament_matches_assign_waves();

-- 5) Reminder job
CREATE OR REPLACE FUNCTION public._tournament_send_reminders()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_count integer := 0;
  v_thr integer;
  v_match record;
  v_uid uuid;
  v_key text;
  v_time_str text;
  v_game text;
BEGIN
  FOREACH v_thr IN ARRAY ARRAY[15, 5] LOOP
    v_key := v_thr::text;
    FOR v_match IN
      SELECT m.id, m.tournament_id, m.player_ids, m.scheduled_at, m.notified_marks,
             t.name AS tname, t.game_slug
        FROM public.tournament_matches m
        JOIN public.tournaments t ON t.id = m.tournament_id
       WHERE m.status = 'pending'
         AND NOT m.is_bye
         AND m.scheduled_at IS NOT NULL
         AND m.scheduled_at BETWEEN now() + ((v_thr - 1) || ' min')::interval
                                AND now() + ((v_thr + 1) || ' min')::interval
         AND COALESCE((m.notified_marks->>v_key)::boolean, false) = false
    LOOP
      v_time_str := to_char(v_match.scheduled_at AT TIME ZONE 'Indian/Antananarivo', 'HH24:MI');
      v_game := COALESCE(v_match.game_slug, 'tournoi');
      FOREACH v_uid IN ARRAY v_match.player_ids LOOP
        IF v_uid IS NOT NULL THEN
          INSERT INTO public.notifications(user_id, kind, type, title, body, link, ref_id)
          VALUES (
            v_uid, 'info', 'tournament_reminder',
            '⏰ Match dans ' || v_thr || ' min',
            'Tournoi « ' || v_match.tname || ' » — début à ' || v_time_str,
            '/tournaments/' || v_match.tournament_id::text,
            v_match.tournament_id
          );
          v_count := v_count + 1;
        END IF;
      END LOOP;
      UPDATE public.tournament_matches
         SET notified_marks = notified_marks || jsonb_build_object(v_key, true)
       WHERE id = v_match.id;
    END LOOP;
  END LOOP;
  RETURN v_count;
END $fn$;

-- 6) Update get_tournament_detail to include new fields
CREATE OR REPLACE FUNCTION public.get_tournament_detail(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v jsonb;
BEGIN
  SELECT jsonb_build_object(
    'tournament', to_jsonb(t),
    'players', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'user_id', r.user_id, 'pseudo', p.pseudo, 'avatar_url', p.avatar_url,
        'eliminated_round', r.eliminated_round, 'final_position', r.final_position
      ) ORDER BY r.registered_at)
      FROM public.tournament_registrations r
      LEFT JOIN public.profiles p ON p.id = r.user_id
      WHERE r.tournament_id = t.id
    ), '[]'::jsonb),
    'matches', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'id', m.id, 'round', m.round, 'match_index', m.match_index,
        'player_ids', m.player_ids, 'status', m.status,
        'game_id', m.game_id, 'winner_id', m.winner_id, 'finished_at', m.finished_at,
        'is_bye', m.is_bye, 'qualifiers_count', m.qualifiers_count,
        'qualifiers_ids', m.qualifiers_ids, 'admin_notes', m.admin_notes,
        'join_deadline', m.join_deadline, 'wave', m.wave,
        'scheduled_at', m.scheduled_at,
        'is_third_place', COALESCE(m.is_third_place, false),
        'is_final', COALESCE(m.is_final, false)
      ) ORDER BY m.round, m.match_index)
      FROM public.tournament_matches m WHERE m.tournament_id = t.id
    ), '[]'::jsonb)
  ) INTO v
  FROM public.tournaments t WHERE t.id = _tid;
  RETURN v;
END $fn$;

-- 7) Backfill waves for existing pending matches (per round)
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT DISTINCT tournament_id, round
      FROM public.tournament_matches
     WHERE scheduled_at IS NULL AND status = 'pending' AND NOT is_bye
  LOOP
    PERFORM public._tournament_assign_waves(r.tournament_id, r.round);
  END LOOP;
END $$;

-- 8) Schedule reminder cron every minute (idempotent)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('tournament_send_reminders');
  END IF;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'tournament_send_reminders',
      '* * * * *',
      $sql$ SELECT public._tournament_send_reminders(); $sql$
    );
  END IF;
END $$;
