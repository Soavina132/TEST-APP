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
│   ├── _authenticated/     # Pages authentifiées (jeux, lobby, admin, profile, etc.)
│   └── *.tsx               # Pages publiques (login, index, jeux-publics)
└── *.ts(x)                 # Entrée (server.ts, router.tsx, styles.css)
```

## Conventions

- **Imports** : utiliser l'alias `@/` (mappe vers `src/`)
- **Composants** : un fichier = un composant, nom en PascalCase
- **Hooks** : préfixer par `use-`
- **Routes** : file-based routing TanStack Router, `$id` = param dynamique
- **Migrations** : `supabase/migrations/` — ne jamais renommer (liées au tracking Supabase)
