
ALTER TABLE public.app_settings
  ADD COLUMN IF NOT EXISTS terms_html text DEFAULT '<p>Lalao MADA est une plateforme de jeux d''adresse en ligne pour la communauté malagasy.</p><ul><li>Vous devez avoir 18 ans ou plus pour jouer avec de l''argent réel.</li><li>Les dépôts et retraits passent par Mobile Money.</li><li>Quitter une partie en cours entraîne la perte automatique de votre mise.</li><li>Les comptes en fraude (multi-comptes, triche) seront bannis.</li></ul>',
  ADD COLUMN IF NOT EXISTS privacy_html text DEFAULT '<p>Nous protégeons vos données personnelles.</p><ul><li>Vos informations (e-mail, téléphone, pseudo) ne sont jamais revendues.</li><li>Elles servent uniquement à gérer votre compte, vos parties et vos paiements.</li><li>Vous pouvez demander la suppression de votre compte en contactant l''admin.</li></ul>';

UPDATE public.app_settings SET terms_html = COALESCE(terms_html,''), privacy_html = COALESCE(privacy_html,'') WHERE id = 1;

CREATE OR REPLACE FUNCTION public.get_legal_texts()
RETURNS TABLE(terms_html text, privacy_html text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT COALESCE(terms_html,''), COALESCE(privacy_html,'')
  FROM public.app_settings WHERE id = 1;
$$;
GRANT EXECUTE ON FUNCTION public.get_legal_texts() TO anon, authenticated;

DROP FUNCTION IF EXISTS public.get_my_referrals();
CREATE FUNCTION public.get_my_referrals()
RETURNS TABLE(id uuid, pseudo text, created_at timestamptz, phone_verified boolean, referral_unlocked boolean, bonus_amount numeric)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.id, p.pseudo, p.created_at, p.phone_verified, p.referral_unlocked,
    COALESCE((
      SELECT SUM(t.amount) FROM public.transactions t
      WHERE t.user_id = auth.uid() AND t.type = 'referral'
        AND (t.note ILIKE '%' || p.id::text || '%' OR t.note ILIKE '%' || p.pseudo || '%')
    ), 0)::numeric AS bonus_amount
  FROM public.profiles p
  WHERE p.referred_by = auth.uid()
  ORDER BY p.created_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.get_my_referrals() TO authenticated;

CREATE OR REPLACE FUNCTION public.leaderboard_winners(_period text DEFAULT 'all', _limit int DEFAULT 20)
RETURNS TABLE(rank int, name text, avatar_url text, wins bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH bound AS (
    SELECT CASE _period
      WHEN 'week'  THEN now() - interval '7 days'
      WHEN 'month' THEN now() - interval '30 days'
      ELSE 'epoch'::timestamptz
    END AS since
  ),
  raw AS (
    SELECT g.winner_id AS uid, NULLIF(trim(pp.display_name),'') AS dn
      FROM ludo_games g JOIN ludo_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULLIF(trim(pp.display_name),'')
      FROM domino_games g JOIN domino_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULLIF(trim(pp.display_name),'')
      FROM fanorona_games g JOIN fanorona_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULLIF(trim(pp.display_name),'')
      FROM rami_games g JOIN rami_participants pp ON pp.game_id=g.id AND pp.user_id=g.winner_id, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
    UNION ALL SELECT g.winner_id, NULL::text
      FROM chess_games g, bound
      WHERE g.status='finished' AND g.winner_id IS NOT NULL AND COALESCE(g.finished_at,g.created_at) >= bound.since
  ),
  filtered AS (
    SELECT r.uid, r.dn FROM raw r
    WHERE NOT public.has_role(r.uid, 'admin'::public.app_role)
  ),
  named AS (
    SELECT COALESCE(f.dn, p.pseudo, 'Joueur') AS name, p.avatar_url, f.uid
    FROM filtered f LEFT JOIN public.profiles p ON p.id=f.uid
  ),
  agg AS (
    SELECT name, (array_agg(avatar_url))[1] AS avatar_url, count(*)::bigint AS wins
    FROM named GROUP BY name
  )
  SELECT (row_number() OVER (ORDER BY a.wins DESC, a.name ASC))::int AS rank,
         a.name, a.avatar_url, a.wins
  FROM agg a ORDER BY a.wins DESC, a.name ASC LIMIT _limit;
$$;
REVOKE ALL ON FUNCTION public.leaderboard_winners(text,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leaderboard_winners(text,int) TO authenticated, anon;

CREATE OR REPLACE FUNCTION public.get_public_profiles_min(_ids uuid[])
RETURNS TABLE(id uuid, pseudo text, avatar_url text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT p.id, p.pseudo, p.avatar_url
  FROM public.profiles p
  WHERE p.id = ANY(_ids);
$$;
GRANT EXECUTE ON FUNCTION public.get_public_profiles_min(uuid[]) TO authenticated;
