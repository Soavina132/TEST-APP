# Tournoi Ludo par poules — automatisation complète

Ajout d'un mode **poules (round-robin) + phase finale** au système de tournoi existant, piloté entièrement côté serveur, avec machine à états et contrôle admin permanent.

## 1. Modèle de données (nouvelles tables)

- `tournament_pools` — une poule : `tournament_id`, `label` (A…P), `batch_no` (1…4), `status` (`pending|running|finished|cancelled`), `finished_at`.
- `tournament_pool_players` — `pool_id`, `user_id`, `seat` (1..4), `played`, `wins`, `losses`, `points`, `qualified`.
- `tournament_batches` — `tournament_id`, `batch_no`, `status`, `started_at`, `finished_at`, `next_batch_at` (délai admin).
- `tournament_matches` (existant) : ajout de `pool_id`, `pool_match_no` (1..6), `phase` (`pool|final`).
- `tournaments` : ajout de `bracket_mode` (`pools|elimination`), `pool_size` (4), `qualifiers_per_pool` (2), `pools_per_batch` (4), `max_live_matches` (8), `match_gap_secs`, `batch_gap_mins`.

Toutes les tables : GRANT + RLS (lecture publique des poules/classements, écriture réservée aux fonctions serveur et à l'admin).

## 2. Machine à états serveur

Chaque entité (tournoi, lot, poule, match) a un statut ; toutes les transitions passent par des fonctions `SECURITY DEFINER` avec `FOR UPDATE` sur la ligne du tournoi (verrou global) :

```text
tournament: draft -> open -> running -> finals -> finished / cancelled / paused
batch:      pending -> running -> finished
pool:       pending -> running -> finished
match:      scheduled -> pending -> running -> finished / forfeit / cancelled
```

Fonctions principales :

- `tournament_pools_draw(_tid)` — mélange aléatoire, crée les poules de 4, les répartit en lots.
- `_tournament_pool_schedule(_pool)` — génère les 6 matchs (1v2, 3v4, 1v3, 2v4, 1v4, 2v3).
- `tournament_pump(_tid)` — le cœur : lance autant de matchs que possible sans dépasser `max_live_matches` (8), jamais deux matchs pour un même joueur, uniquement dans le lot actif ; clôture poule/lot ; démarre le lot suivant après le délai ; bascule en phase finale.
- `_tournament_pool_score(_match)` — 3 pts au gagnant, 0 au perdant, recalcul du classement (points > victoires > confrontation directe > match de départage auto).
- `_tournament_pool_finish(_pool)` — 2 qualifiés / 2 éliminés.
- `tournament_build_finals(_tid)` — bracket 32 → 16 → 8 → 4 → 2 → 1, alimenté par les qualifiés, avancement auto du vainqueur.
- Cron `tournament_pump_all()` toutes les 10 s (pg_cron) : filet de sécurité qui relance la pompe pour tous les tournois `running`.

Notifications insérées dans `notifications` à chaque transition (inscription, tournoi lancé, poule lancée, match prêt, gagné, perdu, qualifié, éliminé, phase suivante, champion).

## 3. Contrôles admin (RPC)

`admin_tournament_set_pool_config`, `admin_tournament_start_pools`, `admin_tournament_pause` / `resume` / `cancel`, `admin_tournament_force_match_result` (existant, étendu aux poules), `admin_tournament_replay_match`, `admin_tournament_disqualify`, `admin_tournament_start_next_batch` (forcer sans attendre le délai), `admin_tournament_announce`. Chaque action journalisée dans `tournament_audit_logs`.

## 4. Interface joueur (`/tournaments/$id`)

- **Barre de progression** : Inscriptions → Poules → Seizièmes → … → Finale, avec états ✅ / ⏳ / ⬜.
- **Un seul bouton principal** contextuel : S'inscrire / En attente / Rejoindre le match / Regarder / Voir le résultat.
- **Carte « Mon prochain match »** : adversaire, heure prévue, numéro, compte à rebours, bouton Rejoindre ; sinon message d'attente.
- **Onglet « Ma poule »** : les 4 joueurs, classement live (temps réel), matchs restants, points, statuts colorés (🟢🟡🔵🔴).
- **Onglet « Mes matchs »** : historique ✅/❌ avec score et date.
- **Onglet « Récompenses »** : cagnotte, répartition, gain potentiel si qualifié.
- Rafraîchissement temps réel via canaux Supabase sur poules, joueurs de poule et matchs.

## 5. Interface admin (`/admin-tournaments`)

Nouvel onglet **Poules** : vue des 16 poules groupées par lot, statut, classement, matchs actifs (x/8), bouton « Lancer le lot suivant », réglages (délai entre matchs, délai entre lots, limite simultanée), forfait/rejouer/modifier résultat sur chaque match, annonce, logs.

## 6. Livraison

- Passe 1 : migration (tables, machine à états, pompe, cron, notifications).
- Passe 2 : UI joueur (progression, prochain match, ma poule, classement live).
- Passe 3 : UI admin (onglet Poules et contrôles).

## Fichiers touchés

- `supabase/migrations/2026xxxx_tournament_pools.sql` (nouveau)
- `src/components/tournament/PoolStandings.tsx`, `NextMatchCard.tsx`, `TournamentProgress.tsx` (nouveaux)
- `src/routes/_authenticated/tournaments_.$id.tsx` (refonte de l'affichage)
- `src/routes/_authenticated/admin-tournaments.tsx` (onglet Poules)
