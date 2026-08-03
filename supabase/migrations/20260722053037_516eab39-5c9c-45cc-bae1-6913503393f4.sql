
CREATE OR REPLACE FUNCTION public.get_tournament_detail(_tid uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
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
        'match_number', m.match_number,
        'player_ids', m.player_ids, 'status', m.status,
        'game_id', m.game_id, 'winner_id', m.winner_id, 'finished_at', m.finished_at,
        'is_bye', m.is_bye, 'qualifiers_count', m.qualifiers_count,
        'qualifiers_ids', m.qualifiers_ids, 'admin_notes', m.admin_notes,
        'auto_start_at', m.auto_start_at, 'join_deadline', m.join_deadline,
        'is_third_place', COALESCE(m.is_third_place, false)
      ) ORDER BY m.round, m.match_index)
      FROM public.tournament_matches m WHERE m.tournament_id = t.id
    ), '[]'::jsonb)
  ) INTO v
  FROM public.tournaments t WHERE t.id = _tid;
  RETURN v;
END $$;
