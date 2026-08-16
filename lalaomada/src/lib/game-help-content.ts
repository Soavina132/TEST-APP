/**
 * Contenu de l'aide contextuelle du lobby (bouton "Aide").
 * Le texte change selon l'onglet actif (Gratuit / Mise / Code / Mes parties)
 * et selon le jeu, pour expliquer précisément les réglages spécifiques à chaque jeu.
 */

export type LobbyTab = "public" | "private" | "code" | "mine";
export type GameSlug = "ludo" | "domino" | "fanorona" | "chess" | "rami" ;

const GAME_LABELS: Record<GameSlug, string> = {
  ludo: "Ludo",
  domino: "Domino",
  fanorona: "Fanorona",
  chess: "Échecs",
  rami: "Rami",
};

type Tip = { icon: string; label: string; desc: string };

// Réglages spécifiques à chaque jeu, affichés dans l'aide des onglets Gratuit & Mise.
// Les icônes correspondent exactement à celles affichées dans la liste de réglages du lobby.
const GAME_SPECIFIC_TIPS: Record<GameSlug, Tip[]> = {
  ludo: [
    { icon: "🎯", label: "Équipe", desc: "Solo (chacun pour soi, jusqu'à 4 joueurs) ou Groupe (2 contre 2, en équipe avec un partenaire)." },
    { icon: "👥", label: "Joueurs", desc: "Nombre de participants à la partie : 2 ou 4 en Solo." },
    { icon: "🎲", label: "Mode", desc: "Classique (règles traditionnelles du Ludo) ou Moderne (ajoute des cases spéciales sur le plateau)." },
    { icon: "🎲", label: "Déplacement auto", desc: "Si tu ne joues pas ton pion avant la fin des 30 secondes, le système en déplace un au hasard pour toi — la partie ne se bloque jamais." },
    { icon: "🚀", label: "Cases spéciales (Mode Moderne)", desc: "Boost (avance de 1 à 6 cases en plus), Bouclier (protège d'une capture), Deuxième lancer (relance le dé), Étoile Chance (bonus aléatoire). Elles apparaissent à des positions aléatoires et se déplacent après chaque activation." },
  ],
  domino: [
    { icon: "🎲", label: "Format", desc: "Par points : la partie se joue en plusieurs manches jusqu'au score cible. Victoire directe : la première personne à vider sa main gagne immédiatement." },
    { icon: "🁣", label: "Pioche", desc: "Avec pioche : si tu ne peux pas jouer, tu piochers dans la réserve avant de passer. Sans pioche : tu passes directement ton tour si aucun coup n'est possible." },
    { icon: "🎬", label: "Premier coup", desc: "Libre : n'importe quelle pièce peut ouvrir la partie. 1er &lt;6 : seul le double le plus fort disponible dans les mains (double-6, double-5, etc.) peut ouvrir." },
    { icon: "💀", label: "Vato Maty", desc: "Règle optionnelle : si tu laisses ton temps s'écouler alors que tu avais un coup possible, cette pièce jouable devient « morte » (vato maty) et tu ne pourras plus jamais la jouer pour le reste de la partie." },
  ],
  fanorona: [
    { icon: "⚫", label: "Plateau", desc: "Telo (3×3, 9 cases, partie rapide), Dimy (5×5, 25 cases) ou Tsivy (9×5, 45 cases, plateau traditionnel malgache)." },
    { icon: "⚫", label: "Capture", desc: "Obligatoire : si une prise est possible, tu dois la jouer (règle traditionnelle). Libre : tu peux choisir de ne pas capturer même si c'est possible." },
    { icon: "⭐", label: "Difficulté (vs Bot)", desc: "5 niveaux, du Débutant (coups aléatoires) au Maître (anticipe plusieurs coups à l'avance)." },
  ],
  chess: [
    { icon: "⭐", label: "Difficulté (vs Bot)", desc: "5 niveaux de force, exprimés en classement Elo approximatif : de 600 (débutant) à 2200 (niveau expert)." },
    { icon: "⚪", label: "Couleur", desc: "Choisis si tu joues les pièces Blanches (tu commences) ou Noires face au Bot." },
    { icon: "⏱️", label: "Temps / joueur", desc: "La cadence de la partie : chaque joueur dispose du même temps total pour jouer tous ses coups, ou d'une partie sans limite (Illimité)." },
  ],
  rami: [
    { icon: "🃏", label: "Joker", desc: "Sans (52 cartes, aucun Joker) · Couleur opposée (52 cartes — une carte tirée au hasard désigne son rang comme Joker pour la couleur opposée, ex : 7♠ tiré ⇒ tous les 7 rouges sont Jokers) · Classique (56 cartes = 52 + 4 vrais Jokers) · Double (56 cartes, les deux règles cumulées)." },
    { icon: "7️⃣", label: "7 Cartes", desc: "Bonus optionnel (n'affecte pas le nombre de cartes distribuées, toujours 13) : le premier joueur qui pose une combinaison pure de 7 cartes d'un coup (un brelan/carré + une suite, sans Joker) récupère immédiatement sa mise, moins la moitié de la commission. La partie continue normalement ensuite." },
    { icon: "📜", label: "Mode de jeu", desc: "Naturel : tu dois d'abord poser ta propre combinaison avant de pouvoir ajouter des cartes sur celles des autres joueurs. Bordel : tu peux ajouter des cartes sur n'importe quelle combinaison posée, dès ton premier tour." },
    { icon: "⭐", label: "Niveau des bots", desc: "Facile, Moyen ou Difficile — influence la qualité des combinaisons et des défausses du Bot." },
  ],
};

function tipsSection(slug: GameSlug): string {
  const tips = GAME_SPECIFIC_TIPS[slug] || [];
  if (!tips.length) return "";
  return `
    <h4 class="text-[11px] font-bold uppercase tracking-wider text-primary mt-4 mb-2">Réglages du ${GAME_LABELS[slug] || slug}</h4>
    <div class="space-y-1.5">
      ${tips.map(t => `
        <div class="flex items-start gap-2.5 rounded-xl bg-secondary/50 border border-white/5 p-2.5">
          <span class="text-base leading-none shrink-0 mt-0.5">${t.icon}</span>
          <div class="min-w-0">
            <div class="font-semibold text-[13px] text-foreground">${t.label}</div>
            <div class="text-[12px] text-muted-foreground leading-snug mt-0.5">${t.desc}</div>
          </div>
        </div>
      `).join("")}
    </div>
  `;
}

function intro(text: string): string {
  return `<p class="text-[13px] text-foreground/90 leading-relaxed">${text}</p>`;
}

function calloutInfo(text: string): string {
  return `<div class="mt-4 rounded-xl bg-primary/10 border border-primary/20 p-3 text-[12px] text-primary leading-snug flex gap-2"><span class="shrink-0">💡</span><span>${text}</span></div>`;
}

function calloutWarning(text: string): string {
  return `<div class="mt-4 rounded-xl bg-amber-500/10 border border-amber-500/25 p-3 text-[12px] text-amber-600 dark:text-amber-400 leading-snug flex gap-2"><span class="shrink-0">⚠️</span><span>${text}</span></div>`;
}

export function getLobbyHelp(slug: GameSlug, tab: LobbyTab): { title: string; html: string } {
  const label = GAME_LABELS[slug] || slug;

  switch (tab) {
    case "public":
      return {
        title: `Gratuit — ${label}`,
        html: `
          ${intro(`Le mode <strong class="text-foreground">Gratuit</strong> te permet de jouer au ${label} <strong class="text-foreground">sans miser d'argent</strong>. Idéal pour t'entraîner ou jouer pour le plaisir, sans aucun risque.`)}
          <h4 class="text-[11px] font-bold uppercase tracking-wider text-primary mt-4 mb-2">Comment configurer ta partie</h4>
          <p class="text-[13px] text-muted-foreground leading-relaxed">Choisis ton <strong class="text-foreground">adversaire</strong> (Bot ou Amis). Si tu joues contre des amis, indique si la partie est <strong class="text-foreground">Publique</strong> (n'importe qui peut la rejoindre depuis la liste) ou <strong class="text-foreground">Privée</strong> (un code à 6 caractères est généré, à partager avec la personne que tu veux inviter).</p>
          ${tipsSection(slug)}
          ${calloutInfo(`Une fois tes réglages faits, appuie sur <strong>Créer la partie</strong> pour lancer la partie de ${label}.`)}
        `,
      };

    case "private":
      return {
        title: `Mise — ${label}`,
        html: `
          ${intro(`Le mode <strong class="text-foreground">Mise</strong> te permet de jouer au ${label} avec une <strong class="text-foreground">mise en Ariary</strong>. Chaque joueur mise le même montant ; le gagnant remporte la cagnotte totale, moins une petite commission de la plateforme.`)}
          <h4 class="text-[11px] font-bold uppercase tracking-wider text-primary mt-4 mb-2">Comment configurer ta partie</h4>
          <p class="text-[13px] text-muted-foreground leading-relaxed">Choisis ta <strong class="text-foreground">mise</strong>, ton <strong class="text-foreground">adversaire</strong> (Bot ou Amis) et, contre des amis, si la partie est <strong class="text-foreground">Publique</strong> ou <strong class="text-foreground">Privée</strong> (avec un code d'invitation à 6 caractères).</p>
          ${tipsSection(slug)}
          ${calloutWarning(`Ton solde doit couvrir la mise avant de créer ou rejoindre une partie. La mise est débitée immédiatement à la création ou en rejoignant une partie, et reversée au vainqueur à la fin (moins la commission).`)}
        `,
      };

    case "code":
      return {
        title: `Code — ${label}`,
        html: `
          ${intro(`Un ami t'a partagé un <strong class="text-foreground">code de partie</strong> à 6 caractères ? Saisis-le ici pour rejoindre directement sa partie de ${label}, qu'elle soit Gratuite ou avec Mise.`)}
          <p class="text-[13px] text-muted-foreground leading-relaxed mt-3">Ce code est généré automatiquement lorsqu'une partie est créée en mode <strong class="text-foreground">Privée</strong> — pense à le partager avec la ou les personnes que tu veux inviter.</p>
          ${calloutInfo(`Si la partie rejointe implique une mise, assure-toi d'avoir le solde nécessaire : il sera débité au moment où tu la rejoins.`)}
        `,
      };

    case "mine":
      return {
        title: `Mes parties — ${label}`,
        html: `
          ${intro(`Retrouve ici toutes tes parties de ${label}, en cours ou terminées.`)}
          <div class="space-y-1.5 mt-3">
            <div class="flex items-start gap-2.5 rounded-xl bg-secondary/50 border border-white/5 p-2.5">
              <span class="text-base leading-none shrink-0 mt-0.5">🎮</span>
              <div class="min-w-0">
                <div class="font-semibold text-[13px] text-foreground">En cours</div>
                <div class="text-[12px] text-muted-foreground leading-snug mt-0.5">Parties en attente d'un adversaire (⏳ En attente) ou déjà lancées (🎮 Partie en cours). Appuie sur <strong class="text-foreground">Reprendre</strong> pour continuer là où tu t'es arrêté.</div>
              </div>
            </div>
            <div class="flex items-start gap-2.5 rounded-xl bg-secondary/50 border border-white/5 p-2.5">
              <span class="text-base leading-none shrink-0 mt-0.5">🏁</span>
              <div class="min-w-0">
                <div class="font-semibold text-[13px] text-foreground">Terminées</div>
                <div class="text-[12px] text-muted-foreground leading-snug mt-0.5">Ton historique complet : victoires 🏆, défaites 💔 et forfaits 🏳️, avec la mise jouée et le montant du pot pour chaque partie.</div>
              </div>
            </div>
          </div>
        `,
      };
  }
}
