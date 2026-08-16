# Structure du projet lalaomada

```
src/
├── assets/                 # Images statiques (covers, groups, rami cards)
├── components/
│   ├── admin/              # Composants panneau admin
│   ├── chat/               # Chat & messagerie (ChatRoom, LinkPreview, RichTextEditor)
│   ├── chess/              # Composants spécifiques aux échecs
│   ├── game/               # Composants de jeu (plateaux, timers, waiting room, etc.)
│   ├── layout/             # Navigation & layout (Header, BottomNav, DesktopNav, etc.)
│   ├── tournament/         # Composants tournois
│   ├── ui/                 # shadcn/ui (boutons, dialogues, inputs, etc.)
│   └── *.tsx               # Composants génériques (ConfirmDialog, WalletButton, etc.)
├── hooks/
│   ├── game/               # Hooks spécifiques aux jeux (config, pause, timer, connection)
│   └── *.ts(x)             # Hooks génériques (auth, online, theme, push, etc.)
├── integrations/
│   └── supabase/           # Client Supabase, types, auth middleware
├── lib/
│   ├── auth/               # Fonctions auth (signup, password-reset, referral)
│   ├── sounds/             # Sons de jeu (game-sounds, fanorona-sounds)
│   └── *.ts                # Utils généraux (clipboard, server-time, i18n, etc.)
├── routes/
│   ├── api/                # API routes (link-preview, translate)
│   ├── _authenticated/     # Pages authentifiées
│   │   ├── jeux.tsx           # Layout parent /jeux
│   │   ├── jeux.index.tsx     # /jeux — liste des jeux
│   │   ├── jeux.chess.$id     # /jeux/chess/123 — partie d'échecs
│   │   ├── jeux.domino.$id    # /jeux/domino/456 — partie de domino
│   │   ├── jeux.fanorona.$id  # /jeux/fanorona/789 — partie de fanorona
│   │   ├── jeux.ludo.$id      # /jeux/ludo/abc — partie de ludo
│   │   ├── jeux.rami.$id      # /jeux/rami/ghi — partie de rami
│   │   ├── chess.$id          # /chess/123 → redirect /jeux/chess/123
│   │   ├── domino.$id         # /domino/456 → redirect /jeux/domino/456
│   │   ├── fanorona.$id       # /fanorona/789 → redirect /jeux/fanorona/789
│   │   ├── game.$id           # /game/abc → redirect /jeux/ludo/abc
│   │   ├── rami.$id           # /rami/ghi → redirect /jeux/rami/ghi
│   │   └── ...                # admin, lobby, profile, chat, tournaments, etc.
│   └── *.tsx               # Pages publiques (login, index, jeux-publics)
└── *.ts(x)                 # Entrée (server.ts, router.tsx, styles.css)
```

## Routes (URL mapping)

| URL | Route file | Description |
|-----|-----------|-------------|
| `/jeux` | `jeux.index.tsx` | Liste de tous les jeux |
| `/jeux/chess/123` | `jeux.chess.$id.tsx` | Partie d'échecs |
| `/jeux/domino/456` | `jeux.domino.$id.tsx` | Partie de domino |
| `/jeux/fanorona/789` | `jeux.fanorona.$id.tsx` | Partie de fanorona |
| `/jeux/ludo/abc` | `jeux.ludo.$id.tsx` | Partie de ludo |
| `/jeux/rami/ghi` | `jeux.rami.$id.tsx` | Partie de rami |
| `/chess/123` | `chess.$id.tsx` | → redirect `/jeux/chess/123` |
| `/domino/456` | `domino.$id.tsx` | → redirect `/jeux/domino/456` |

## Conventions

- **Imports** : utiliser l'alias `@/` (mappe vers `src/`)
- **Composants** : un fichier = un composant, nom en PascalCase
- **Hooks** : préfixer par `use-`
- **Routes** : file-based routing TanStack Router, `$id` = param dynamique
- **Migrations** : `supabase/migrations/` — ne jamais renommer (liées au tracking Supabase)
