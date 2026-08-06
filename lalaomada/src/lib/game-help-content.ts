/**
 * Contenu de l'aide contextuelle du lobby (bouton "Aide").
 * Le texte change selon l'onglet actif (Gratuit / Mise / Code / Mes parties)
 * et selon le jeu, pour rappeler les réglages spécifiques à chaque jeu.
 */

export type LobbyTab = "public" | "private" | "code" | "mine";
export type GameSlug = "ludo" | "domino" | "fanorona" | "chess" | "rami" | "poker";

const GAME_LABELS: Record<GameSlug, string> = {
  ludo: "Ludo",
  domino: "Domino",
  fanorona: "Fanorona",
  chess: "Échecs",
  rami: "Rami",
  poker: "Poker",
};

// Réglages spécifiques à chaque jeu, affichés dans l'aide des onglets Gratuit & Mise.
const GAME_SPECIFIC_TIPS: Record<GameSlug, string[]> = {
  ludo: [
    "<strong>Équipe</strong> : joue seul (Solo) ou en équipe de 2 contre 2 (Groupe).",
    "<strong>Déplacement auto</strong> : si tu ne déplaces pas ton pion avant la fin du timer (30s), le système choisit un de tes pions jouables au hasard et le déplace automatiquement.",
    "<strong>Mode Moderne</strong> : ajoute des cases spéciales (🚀 Boost, 🛡️ Bouclier, ⚡ Deuxième lancer, ⭐ Étoile Chance) placées aléatoirement. Elles changent de position après activation.",
    "<strong>Boost</strong> : avance automatiquement de 1 à 6 cases supplémentaires.",
    "<strong>Bouclier</strong> : protège de la capture jusqu'à ton prochain tour.",
    "<strong>Deuxième lancer</strong> : deux lancers de dé au prochain tour.",
    "<strong>Étoile Chance</strong> : récompense aléatoire (boost, bouclier, double lancer, relance, ou sortie gratuite de pion).",
  ],
  domino: [
    "<strong>Format</strong> : « Par points » (le premier à atteindre le score cible gagne) ou « Victoire directe » (le premier à vider sa main gagne).",
    "<strong>Pioche</strong> : active ou désactive le tas de pioche pendant la partie.",
    "<strong>Premier coup</strong> : libre, ou obligatoirement le double le plus fort disponible.",
  ],
  fanorona: [
    "<strong>Plateau</strong> : choisis la variante du plateau et si la prise est obligatoire ou libre.",
    "<strong>Difficulté</strong> (contre un Bot) : du Débutant au Maître.",
  ],
  chess: [
    "<strong>Difficulté</strong> et <strong>couleur</strong> des pièces si tu joues contre l'IA.",
    "<strong>Temps par joueur</strong> : choisis une cadence ou une partie sans limite de temps.",
  ],
  rami: [
    "<strong>Joker</strong> : définit comment les jokers sont distribués (sans, aléatoire, classique, double).",
    "<strong>Mode de jeu</strong> : Naturel ou Bordel — les règles de combinaisons changent.",
    "<strong>Niveau des bots</strong> si tu joues contre l'IA.",
  ],
  poker: [
    "<strong>Blindes</strong> : la mise obligatoire de départ (petite / grosse blinde).",
    "<strong>Cave</strong> : le nombre de jetons de départ de chaque joueur.",
  ],
};

function tipsList(slug: GameSlug): string {
  const tips = GAME_SPECIFIC_TIPS[slug] || [];
  if (!tips.length) return "";
  return `<ul>${tips.map(t => `<li>${t}</li>`).join("")}</ul>`;
}

export function getLobbyHelp(slug: GameSlug, tab: LobbyTab): { title: string; html: string } {
  const label = GAME_LABELS[slug] || slug;

  switch (tab) {
    case "public":
      return {
        title: `Gratuit — ${label}`,
        html: `
          <p>Le mode <strong>Gratuit</strong> te permet de jouer au ${label} <strong>sans miser d'argent</strong>. Parfait pour t'entraîner ou jouer juste pour le plaisir, sans aucun risque.</p>
          <p>Choisis ton <strong>adversaire</strong> (Bot ou Amis) et, si tu joues contre des amis, si la partie est <strong>Publique</strong> (n'importe qui peut la rejoindre) ou <strong>Privée</strong> (un code d'invitation est généré).</p>
          ${tipsList(slug)}
          <p>Une fois réglé, appuie sur <strong>Créer la partie</strong> pour lancer.</p>
        `,
      };

    case "private":
      return {
        title: `Mise — ${label}`,
        html: `
          <p>Le mode <strong>Mise</strong> te permet de jouer au ${label} avec une <strong>mise en Ariary</strong>. Chaque joueur mise le même montant, et le gagnant remporte la cagnotte (moins une petite commission).</p>
          <p>Choisis ta <strong>mise</strong>, ton <strong>adversaire</strong> et si la partie est <strong>Publique</strong> ou <strong>Privée</strong> (un code à 6 caractères sera généré pour inviter tes amis).</p>
          ${tipsList(slug)}
          <p>⚠️ Assure-toi d'avoir assez de solde avant de créer ou rejoindre une partie avec mise.</p>
        `,
      };

    case "code":
      return {
        title: `Code — ${label}`,
        html: `
          <p>Un ami t'a partagé un <strong>code de partie</strong> à 6 caractères ? Saisis-le ici pour rejoindre directement sa partie de ${label}, qu'elle soit gratuite ou avec mise.</p>
          <p>Le code est généré automatiquement quand tu crées une partie <strong>Privée</strong> — pense à le partager avec la personne que tu veux inviter.</p>
        `,
      };

    case "mine":
      return {
        title: `Mes parties — ${label}`,
        html: `
          <p>Retrouve ici toutes tes parties de ${label} :</p>
          <ul>
            <li><strong>🎮 En cours</strong> : parties en attente d'un adversaire ou déjà lancées. Appuie sur <strong>Reprendre</strong> pour continuer là où tu t'es arrêté.</li>
            <li><strong>🏁 Terminées</strong> : ton historique — victoires, défaites, forfaits, la mise jouée et le montant du pot pour chaque partie.</li>
          </ul>
        `,
      };
  }
}
