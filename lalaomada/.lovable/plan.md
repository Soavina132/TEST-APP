# Plan — Corrections & améliorations Domino

## 1. Lobby : option « Avec pioche » / « Sans pioche »
Dans `src/routes/_authenticated/jeux.nouveau.$slug.tsx` (section Domino), ajouter un sélecteur :
- **Avec pioche** (classique) — stock pioché quand aucun coup n'est jouable.
- **Sans pioche** (bloqué direct) — pas de stock, le joueur passe immédiatement si aucun coup possible.

Stocker dans `domino_games.state.draw_mode` (`"with"` | `"without"`).

## 2. Distribution des tuiles
Garder **7 tuiles par joueur quel que soit le nombre de joueurs** (2/3/4), comme demandé.
- 2 joueurs : 14 distribuées, 14 dans le stock.
- 3 joueurs : 21 distribuées, 7 dans le stock.
- 4 joueurs : 28 distribuées, **0 dans le stock** → en mode « avec pioche » la pioche sera vide d'office (= équivalent sans pioche). C'est la règle explicitement demandée.

Corriger côté SQL (`domino_play` / fonction de distribution) pour fixer `per_hand = 7` au lieu de la logique actuelle.

## 3. Règles de jeu à corriger
- **Pass interdit si jouable** : la fonction `domino_play` refuse `action: "pass"` si une tuile de la main correspond à `left_end`/`right_end`, ou si en mode « avec pioche » le stock n'est pas vide (forcer `draw` d'abord).
- **Premier coup** : forcer le porteur du plus gros double à le poser en premier coup.
- **Égalité obligatoire** : seul un domino dont une face égale une extrémité libre peut être posé (déjà respecté par `tileMatches`, mais durci côté serveur).

## 4. Drag & drop (remplacer les boutons Gauche/Droite)
Dans `src/routes/_authenticated/domino.$id.tsx` + `DominoTable.tsx` :
- Supprimer les boutons « ⟵ Gauche » / « Droite ⟶ ».
- L'utilisateur **sélectionne une tuile jouable dans sa main** puis la **glisse** (HTML5 drag, ou pointer events) vers l'une des deux **zones de drop** placées aux deux extrémités du serpent de dominos.
- Les zones de drop apparaissent seulement pour les tuiles compatibles (highlight ambre).
- Si l'extrémité touche le bord, la chaîne se replie automatiquement (côté affichage : déjà géré en CSS `flex-wrap`, on ajoute un coude visuel en orientant la tuile verticalement au pli — pas d'interaction utilisateur supplémentaire, le serveur place toujours « gauche » ou « droite » selon la zone de drop).

## 5. Forme du « 6 » sur la tuile
Dans `DominoTable.tsx` (composant `Pips`), corriger le motif du 6 :
- Actuel : `[[0,0],[0,2],[1,0],[1,2],[2,0],[2,2]]` (3 par colonne extérieure).
- Correct domino : **deux colonnes de 3 points** alignées verticalement → `[[0,0],[1,0],[2,0],[0,2],[1,2],[2,2]]` (déjà ce qui est codé). 
**Vrai bug** : sur tuile horizontale la grille 3×3 par demi-tuile rend le 6 « écrasé ». Refondre `Pips` pour utiliser une grille **2×3** (2 colonnes × 3 lignes) pour les valeurs 6, et **3×3** pour 1-5, avec des tailles de points cohérentes. Vérifier aussi 5 (quinconce centré) et 2 (diagonale).

## 6. Avatars sans photo
Partout où un avatar est rendu (header table domino, `GameWaitingRoom`, `GameEndScreen`, listes participants) : si `profile.avatar_url` est absent/null, **ne pas afficher d'emoji robot/humain** ni d'avatar généré. Afficher un cercle neutre avec les **initiales** du pseudo (ou un cercle vide gris si pas de pseudo). Aucune photo fabriquée.

## Fichiers touchés
- `src/routes/_authenticated/jeux.nouveau.$slug.tsx` — option pioche.
- `src/routes/_authenticated/domino.$id.tsx` — drag & drop, suppression boutons, branchement `draw_mode`.
- `src/components/DominoTable.tsx` — zones de drop, refonte `Pips` (forme du 6), avatars sans photo.
- `src/components/GameWaitingRoom.tsx`, `src/components/GameEndScreen.tsx` — avatars sans photo.
- Migration SQL : `domino_play`/distribution (per_hand=7, draw_mode, blocage pass/draw, premier coup = plus gros double).

## Points techniques
- Drag & drop mobile : utiliser pointer events (`onPointerDown`/`Move`/`Up`) plutôt que HTML5 DnD (compat tactile).
- Le serveur reste autoritaire : le client envoie `{action:"play", tile, side:"left"|"right"}` après le drop sur la zone correspondante.
- `draw_mode` ajouté dans `state` au démarrage de la partie ; rétrocompat : si absent → `"with"`.