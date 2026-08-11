import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { s as Route$b, u as useAuth, t as pokerCover, r as ramiCover, e as chessCover, g as fanoronaCover, h as dominoCover, l as ludoCover, C as COVER_BY_SLUG$1, P as PageLoader } from "./router-CRCBvenY.mjs";
import { G as GAME_TABLE, U as UUID_RE } from "./game-constants-DbAkVx_H.mjs";
import { e as useNavigate, L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { A as AdminRenameDialog } from "./AdminRenameDialog-OR2qGOW5.mjs";
import { s as shareNewGameInGroup } from "./share-game-wrpRJpl9.mjs";
import { p as purify } from "../_libs/dompurify.mjs";
import { u as useAppSettings, D as DepotModal } from "./WalletButton-BwZT8Njg.mjs";
import { P as PremiumSubscriptionModal } from "./PremiumSubscriptionModal-CtNhxpDU.mjs";
import { P as PhoneVerifyPopup } from "./PhoneVerifyPopup-CibtDuiJ.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { a as Trophy, a8 as KeyRound, aR as CirclePlay, L as Lock, aK as RotateCw, m as CircleQuestionMark, X, aS as Target, ay as Crown, aO as Medal } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "../_libs/radix-ui__react-alert-dialog.mjs";
import "../_libs/radix-ui__react-context.mjs";
import "../_libs/radix-ui__react-compose-refs.mjs";
import "../_libs/radix-ui__react-dialog.mjs";
import "../_libs/radix-ui__primitive.mjs";
import "../_libs/radix-ui__react-id.mjs";
import "../_libs/@radix-ui/react-use-layout-effect+[...].mjs";
import "../_libs/@radix-ui/react-use-controllable-state+[...].mjs";
import "../_libs/@radix-ui/react-use-effect-event+[...].mjs";
import "../_libs/@radix-ui/react-dismissable-layer+[...].mjs";
import "../_libs/radix-ui__react-primitive.mjs";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "../_libs/radix-ui__react-slot.mjs";
import "../_libs/@radix-ui/react-use-callback-ref+[...].mjs";
import "../_libs/radix-ui__react-focus-scope.mjs";
import "../_libs/radix-ui__react-portal.mjs";
import "../_libs/radix-ui__react-presence.mjs";
import "../_libs/radix-ui__react-focus-guards.mjs";
import "../_libs/react-remove-scroll.mjs";
import "tslib";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "../_libs/supabase__functions-js.mjs";
import "../_libs/ai-sdk__openai-compatible.mjs";
import "../_libs/ai-sdk__provider.mjs";
import "../_libs/ai-sdk__provider-utils.mjs";
import "../_libs/eventsource-parser.mjs";
import "../_libs/zod.mjs";
import "../_libs/ai.mjs";
import "../_libs/ai-sdk__gateway.mjs";
import "../_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "../_libs/opentelemetry__api.mjs";
import "../_libs/isbot.mjs";
import "./dialog-BkiCxqYs.mjs";
function HelpPopover({
  trigger,
  title,
  html,
  variant = "link"
}) {
  const [open, setOpen] = reactExports.useState(false);
  if (!html?.trim()) return null;
  const triggerClass = variant === "button" ? "flex items-center gap-1 px-2.5 py-1.5 rounded-full bg-card border border-primary/25 text-primary font-semibold text-[11px] shadow-sm active:scale-95 transition-transform" : "text-xs text-primary font-semibold inline-flex items-center gap-1 underline-offset-2 hover:underline";
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { type: "button", onClick: () => setOpen(true), className: triggerClass, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(CircleQuestionMark, { className: "w-3.5 h-3.5" }),
      " ",
      trigger
    ] }),
    open && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-4", onClick: () => setOpen(false), children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card rounded-3xl max-w-md w-full p-5 shadow-xl max-h-[80vh] overflow-y-auto", onClick: (e) => e.stopPropagation(), children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold", children: title || trigger }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setOpen(false), className: "p-1.5 rounded-full bg-secondary", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "div",
        {
          className: "prose prose-sm dark:prose-invert max-w-none",
          dangerouslySetInnerHTML: { __html: purify.sanitize(html) }
        }
      )
    ] }) })
  ] });
}
const LEVELS = [
  { min: 0, max: 0, icon: "⚪", color: "text-slate-400", bg: "bg-slate-100 dark:bg-slate-800" },
  { min: 1, max: 2, icon: "🟢", color: "text-green-500", bg: "bg-green-100 dark:bg-green-900/30" },
  { min: 3, max: 6, icon: "🔵", color: "text-blue-500", bg: "bg-blue-100 dark:bg-blue-900/30" },
  { min: 7, max: 11, icon: "🟣", color: "text-violet-500", bg: "bg-violet-100 dark:bg-violet-900/30" },
  { min: 12, max: 19, icon: "🟡", color: "text-amber-500", bg: "bg-amber-100 dark:bg-amber-900/30" },
  { min: 20, max: 34, icon: "🟠", color: "text-orange-500", bg: "bg-orange-100 dark:bg-orange-900/30" },
  { min: 35, max: 59, icon: "🔴", color: "text-red-500", bg: "bg-red-100 dark:bg-red-900/30" },
  { min: 60, max: 99, icon: "🏅", color: "text-rose-600", bg: "bg-rose-100 dark:bg-rose-900/30" },
  { min: 100, max: 199, icon: "💎", color: "text-fuchsia-600", bg: "bg-fuchsia-100 dark:bg-fuchsia-900/30" },
  { min: 200, max: Infinity, icon: "👑", color: "text-yellow-500", bg: "bg-yellow-50 dark:bg-yellow-900/20" }
];
function getLevel(wins) {
  return LEVELS.find((l) => wins >= l.min && wins <= l.max) ?? LEVELS[0];
}
function RankIcon({ rank }) {
  if (rank === 1) return /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-5 h-5 text-amber-400" });
  if (rank === 2) return /* @__PURE__ */ jsxRuntimeExports.jsx(Medal, { className: "w-5 h-5 text-slate-400" });
  if (rank === 3) return /* @__PURE__ */ jsxRuntimeExports.jsx(Medal, { className: "w-5 h-5 text-orange-400" });
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-full bg-secondary flex items-center justify-center font-bold text-xs text-muted-foreground", children: rank });
}
function GameLeaderboardModal({
  slug,
  gameLabel,
  onClose
}) {
  const { user } = useAuth();
  const [items, setItems] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(true);
  const [myRank, setMyRank] = reactExports.useState(null);
  reactExports.useEffect(() => {
    (async () => {
      const { data } = await supabase.rpc("leaderboard_winners", {
        _period: "all",
        _limit: 50,
        _slug: slug
      });
      const list = data || [];
      setItems(list);
      if (user) {
        const idx = list.findIndex((p) => p.user_id === user.id || p.id === user.id);
        setMyRank(idx >= 0 ? idx + 1 : null);
      }
      setLoading(false);
    })();
  }, [slug, user?.id]);
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      className: "fixed inset-0 z-50 bg-black/60 flex items-end sm:items-center justify-center p-0 sm:p-4",
      onClick: onClose,
      children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "div",
        {
          className: "bg-card rounded-t-3xl sm:rounded-3xl max-w-md w-full shadow-xl max-h-[85vh] overflow-y-auto",
          onClick: (e) => e.stopPropagation(),
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "sticky top-0 z-10 bg-card px-4 pt-4 pb-3 border-b border-border/40", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xl", children: "🏆" }),
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
                    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm", children: [
                      "Classement ",
                      gameLabel
                    ] }),
                    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: "Top joueurs de ce jeu" })
                  ] })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, className: "p-1.5 rounded-full bg-secondary active:scale-90 transition", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }) })
              ] }),
              myRank && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1.5 inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full bg-primary/10 border border-primary/20", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3 h-3 text-primary" }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] font-bold text-primary", children: [
                  "Votre rang: #",
                  myRank
                ] })
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 py-2", children: loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "py-12", children: /* @__PURE__ */ jsxRuntimeExports.jsx(PageLoader, { variant: "overlay", label: "Chargement du classement…" }) }) : items.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "py-12 text-center text-muted-foreground text-sm", children: [
              "Aucune donnée pour ",
              gameLabel,
              " pour le moment"
            ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-0", children: items.map((p, i) => {
              const rank = i + 1;
              const wins = Number(p.wins ?? 0);
              const isMe = p.user_id === user?.id || p.id === user?.id;
              const lvl = getLevel(wins);
              const podiumBg = rank === 1 ? "bg-gradient-to-r from-amber-500/8 to-transparent border-l-4 border-amber-400" : rank === 2 ? "bg-gradient-to-r from-slate-400/6 to-transparent border-l-4 border-slate-400/50" : rank === 3 ? "bg-gradient-to-r from-orange-500/6 to-transparent border-l-4 border-orange-400/50" : "";
              const inner = /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 flex items-center justify-center shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RankIcon, { rank }) }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-9 h-9 rounded-full bg-secondary overflow-hidden grid place-items-center font-bold text-xs ring-2 ${rank === 1 ? "ring-amber-400/60" : rank === 2 ? "ring-slate-400/40" : rank === 3 ? "ring-orange-400/40" : "ring-transparent"}`, children: p.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: p.avatar_url, alt: p.name ?? "?", width: 36, height: 36, loading: "lazy", className: "w-full h-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: (p.name ?? "?").slice(0, 2).toUpperCase() }) }),
                  rank <= 3 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -top-1 -right-1 text-xs", children: rank === 1 ? "👑" : rank === 2 ? "🥈" : "🥉" })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0 space-y-0.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `font-bold text-sm truncate block ${isMe ? "text-primary" : ""}`, children: [
                    p.name ?? "Joueur",
                    isMe && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-primary ml-1", children: " (Vous)" })
                  ] }),
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `text-[10px] font-bold px-1.5 py-0.5 rounded-full ${lvl.bg} ${lvl.color}`, children: [
                    lvl.icon,
                    " ",
                    wins,
                    " victoires"
                  ] })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-right shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm tabular-nums flex items-center gap-1 justify-end", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3.5 h-3.5 text-amber-500" }),
                  " ",
                  wins
                ] }) })
              ] });
              const rowClass = `flex items-center gap-2.5 px-3 py-2.5 rounded-xl transition-colors hover:bg-accent/30 ${podiumBg} ${isMe ? "ring-2 ring-primary/30 ring-inset" : ""}`;
              if (p.user_id || p.id) {
                return /* @__PURE__ */ jsxRuntimeExports.jsx(
                  Link,
                  {
                    to: "/joueur/$id",
                    params: { id: p.user_id ?? p.id },
                    className: rowClass,
                    children: inner
                  },
                  p.user_id ?? p.id ?? i
                );
              }
              return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: rowClass, children: inner }, i);
            }) }) })
          ]
        }
      )
    }
  );
}
const GAME_LABELS = {
  ludo: "Ludo",
  domino: "Domino",
  fanorona: "Fanorona",
  chess: "Échecs",
  rami: "Rami",
  poker: "Poker"
};
const GAME_SPECIFIC_TIPS = {
  ludo: [
    "<strong>Équipe</strong> : joue seul (Solo) ou en équipe de 2 contre 2 (Groupe).",
    "<strong>Déplacement auto</strong> : si tu ne déplaces pas ton pion avant la fin du timer (30s), le système choisit un de tes pions jouables au hasard et le déplace automatiquement.",
    "<strong>Mode Moderne</strong> : ajoute des cases spéciales (🚀 Boost, 🛡️ Bouclier, ⚡ Deuxième lancer, ⭐ Étoile Chance) placées aléatoirement. Elles changent de position après activation.",
    "<strong>Boost</strong> : avance automatiquement de 1 à 6 cases supplémentaires.",
    "<strong>Bouclier</strong> : protège de la capture jusqu'à ton prochain tour.",
    "<strong>Deuxième lancer</strong> : deux lancers de dé au prochain tour.",
    "<strong>Étoile Chance</strong> : récompense aléatoire (boost, bouclier, double lancer, relance, ou sortie gratuite de pion)."
  ],
  domino: [
    "<strong>Format</strong> : « Par points » (le premier à atteindre le score cible gagne) ou « Victoire directe » (le premier à vider sa main gagne).",
    "<strong>Pioche</strong> : active ou désactive le tas de pioche pendant la partie.",
    "<strong>Premier coup</strong> : libre, ou obligatoirement le double le plus fort disponible."
  ],
  fanorona: [
    "<strong>Plateau</strong> : choisis la variante du plateau et si la prise est obligatoire ou libre.",
    "<strong>Difficulté</strong> (contre un Bot) : du Débutant au Maître."
  ],
  chess: [
    "<strong>Difficulté</strong> et <strong>couleur</strong> des pièces si tu joues contre l'IA.",
    "<strong>Temps par joueur</strong> : choisis une cadence ou une partie sans limite de temps."
  ],
  rami: [
    "<strong>Joker</strong> : 2 paquets (104 cartes) + modes Sans, Couleur opposée, Classiques (4 Jokers), ou Double (les deux).",
    "<strong>Mode de jeu</strong> : Naturel ou Bordel — les règles de combinaisons changent.",
    "<strong>Niveau des bots</strong> si tu joues contre l'IA."
  ],
  poker: [
    "<strong>Blindes</strong> : la mise obligatoire de départ (petite / grosse blinde).",
    "<strong>Cave</strong> : le nombre de jetons de départ de chaque joueur."
  ]
};
function tipsList(slug) {
  const tips = GAME_SPECIFIC_TIPS[slug] || [];
  if (!tips.length) return "";
  return `<ul>${tips.map((t) => `<li>${t}</li>`).join("")}</ul>`;
}
function getLobbyHelp(slug, tab) {
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
        `
      };
    case "private":
      return {
        title: `Mise — ${label}`,
        html: `
          <p>Le mode <strong>Mise</strong> te permet de jouer au ${label} avec une <strong>mise en Ariary</strong>. Chaque joueur mise le même montant, et le gagnant remporte la cagnotte (moins une petite commission).</p>
          <p>Choisis ta <strong>mise</strong>, ton <strong>adversaire</strong> et si la partie est <strong>Publique</strong> ou <strong>Privée</strong> (un code à 6 caractères sera généré pour inviter tes amis).</p>
          ${tipsList(slug)}
          <p>⚠️ Assure-toi d'avoir assez de solde avant de créer ou rejoindre une partie avec mise.</p>
        `
      };
    case "code":
      return {
        title: `Code — ${label}`,
        html: `
          <p>Un ami t'a partagé un <strong>code de partie</strong> à 6 caractères ? Saisis-le ici pour rejoindre directement sa partie de ${label}, qu'elle soit gratuite ou avec mise.</p>
          <p>Le code est généré automatiquement quand tu crées une partie <strong>Privée</strong> — pense à le partager avec la personne que tu veux inviter.</p>
        `
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
        `
      };
  }
}
const STAKES = [200, 500, 1e3, 2e3, 5e3];
const COVER_PLACEHOLDER = {
  "chess": "data:image/webp;base64,UklGRl4DAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4IMYAAACQBQCdASoUABQAPu1urlIppiQiqAgBMB2JZgCdMoM8An/AQP4/O1m3SRtP5hc+S0w2el8JsAD+6U6Zy+QtijWclNMXaeu4ahVZfYIm9ULhxkALwvYeDhC8s0dU1+UJxS6oMPaM8Q2Gr8g14Erx3NECSpOL9/OSL29y2pRSYTOVXwDqEzYVRJjW7WVTTwRnWUPwAJq6V5ME5/8E9ZL+ht+DxAiFkPplz7B7hMtuMmalrygMYmeWI7/CGS+KuD0Zo+lQFV9/2ABYTVAgcQIAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNS4wIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6SXB0YzR4bXBFeHQ9Imh0dHA6Ly9pcHRjLm9yZy9zdGQvSXB0YzR4bXBFeHQvMjAwOC0wMi0yOS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgSXB0YzR4bXBFeHQ6RGlnaXRhbFNvdXJjZUZpbGVUeXBlPSJodHRwOi8vY3YuaXB0Yy5vcmcvbmV3c2NvZGVzL2RpZ2l0YWxzb3VyY2V0eXBlL3RyYWluZWRBbGdvcml0aG1pY01lZGlhIiBJcHRjNHhtcEV4dDpEaWdpdGFsU291cmNlVHlwZT0iaHR0cDovL2N2LmlwdGMub3JnL25ld3Njb2Rlcy9kaWdpdGFsc291cmNldHlwZS90cmFpbmVkQWxnb3JpdGhtaWNNZWRpYSIgcGhvdG9zaG9wOkNyZWRpdD0iTWFkZSB3aXRoIEdvb2dsZSBBSSIvPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiAgIDw/eHBhY2tldCBlbmQ9InciPz4A",
  "domino": "data:image/webp;base64,UklGRlQDAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4ILwAAAAwBQCdASoUABQAPu1srVIppaQiqAgBMB2JagCsMxmv/gHqybaTlmwhnSGDllKDUM100AD+6U6ZzIefBcCKSkQilO6YaclEBAnrgd2YoV/GjANqn7NTdgK6CKITbDRKFRneGER2IdAhwdoc0imJBWDpAqM83uKddiUhkaVHLvKQk9hjkT/gy8bbbpJkzGf/BsKUP/Bq4NrvtrdM0fvIfPmM2oOvSetosKpBpwaAeFvdROi+/TZRbuBR8GaAAFhNUCBxAgAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNS41LjAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczpJcHRjNHhtcEV4dD0iaHR0cDovL2lwdGMub3JnL3N0ZC9JcHRjNHhtcEV4dC8yMDA4LTAyLTI5LyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiBJcHRjNHhtcEV4dDpEaWdpdGFsU291cmNlRmlsZVR5cGU9Imh0dHA6Ly9jdi5pcHRjLm9yZy9uZXdzY29kZXMvZGlnaXRhbHNvdXJjZXR5cGUvdHJhaW5lZEFsZ29yaXRobWljTWVkaWEiIElwdGM0eG1wRXh0OkRpZ2l0YWxTb3VyY2VUeXBlPSJodHRwOi8vY3YuaXB0Yy5vcmcvbmV3c2NvZGVzL2RpZ2l0YWxzb3VyY2V0eXBlL3RyYWluZWRBbGdvcml0aG1pY01lZGlhIiBwaG90b3Nob3A6Q3JlZGl0PSJNYWRlIHdpdGggR29vZ2xlIEFJIi8+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+ICAgPD94cGFja2V0IGVuZD0idyI/PgA=",
  "fanorona": "data:image/webp;base64,UklGRsgAAABXRUJQVlA4ILwAAABwBQCdASoUABQAPu1ur1IppiQiqAgBMB2JQBOmXRS2YVvntZEak2CwzwtBGcZpROzeXSAAAP62wA0KcQqSscR9O5gJOn9LQJBAq799FyiufdV8GhlL0MtUvr9PRIxiqXSWGt61yJoFzUvm+ysBXyV8YuKjidVdBPnyk+meKRjHXJWIJnD4Fb7970xzChQGGpqFccvmTqyFeZI4vkNezP18bfzo5NY75KzOD5G3uX7YySRgrwjU4pLwBkAAAA==",
  "ludo": "data:image/webp;base64,UklGRgIEAABXRUJQVlA4WAoAAAAoAAAAEwAAEwAASUNDUBgCAAAAAAIYAAAAAAIQAABtbnRyUkdCIFhZWiAAAAAAAAAAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAAHRyWFlaAAABZAAAABRnWFlaAAABeAAAABRiWFlaAAABjAAAABRyVFJDAAABoAAAAChnVFJDAAABoAAAAChiVFJDAAABoAAAACh3dHB0AAAByAAAABRjcHJ0AAAB3AAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAFgAAAAcAHMAUgBHAEIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFhZWiAAAAAAAABvogAAOPUAAAOQWFlaIAAAAAAAAGKZAAC3hQAAGNpYWVogAAAAAAAAJKAAAA+EAAC2z3BhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABYWVogAAAAAAAA9tYAAQAAAADTLW1sdWMAAAAAAAAAAQAAAAxlblVTAAAAIAAAABwARwBvAG8AZwBsAGUAIABJAG4AYwAuACAAMgAwADEANlZQOCDMAAAAEAUAnQEqFAAUAD7tbq9SKaYkIqgIATAdiWwAnTMcfQEHQDdxbfftYJYywmuiGw/uYAD+6U6Ua7z5RGgZL5CfvPzOhUef9RGP1yGMEUWxifrBPE+0MVfnK+fczsUBlg7Ztg2ztMolCuX54ryoc+CidYLxqXSLWOqBlpmG766ycjcMxQZC69ROsyJLcOTMH4lFBO3GVvzlJroTpR5ZoOUcqz2bbxoJsRsWUsqY74Uwv27wiKn/UV/zHQbfXUsd5BsmdBedia1O9nwy3AAARVhJRvAAAABNTQAqAAAACAAHAQAABAAAAAEAAAQ4ARAAAgAAAAkAAABiAQEABAAAAAEAAAQoARIAAwAAAAEAAQAAATIAAgAAABQAAABrh2kABAAAAAEAAACGAQ8AAgAAAAcAAAB/AAAAAFBPVC1MWDFUADIwMjY6MDY6MTggMjI6NDc6MDYASFVBV0VJAAAFkggABAAAAAEAAAAAkAQAAgAAABQAAADIkAMAAgAAABQAAADcoAMABAAAAAEAAAQooAIABAAAAAEAAAQ4AAAAADIwMjY6MDY6MTggMjI6NDY6NTcAMjAyNjowNjoxOCAyMjo0Njo1NwA=",
  "rami": "data:image/webp;base64,UklGRlYDAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4IL4AAADQBQCdASoUABQAPu1srlIppaQiqAgBMB2JbACdMySzPn/AQPemvn5cyH5eXJN251v1PPpW+LWQAP7sTWhRWXJkiRF49d5If4J/E9pZ2k/+N888A/wyLyDPW21VB0nWNCN7UViNM1MktRPp41nd1ZztvqSG/pD6nHVzZFHR2mf5uUGGoxZJXlHJNbcIJuD+DYUof+CZG1321umaP3kPhsDbaCfpJL5MFR2uz/zC7RJ/hAOahxN/uxgqzwTaoAAAWE1QIHECAAA8P3hwYWNrZXQgYmVnaW49Iu+7vyIgaWQ9Ilc1TTBNcENlaGlIenJlU3pOVGN6a2M5ZCI/PiA8eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEvIiB4OnhtcHRrPSJYTVAgQ29yZSA1LjUuMCI+IDxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+IDxyZGY6RGVzY3JpcHRpb24gcmRmOmFib3V0PSIiIHhtbG5zOklwdGM0eG1wRXh0PSJodHRwOi8vaXB0Yy5vcmcvc3RkL0lwdGM0eG1wRXh0LzIwMDgtMDItMjkvIiB4bWxuczpwaG90b3Nob3A9Imh0dHA6Ly9ucy5hZG9iZS5jb20vcGhvdG9zaG9wLzEuMC8iIElwdGM0eG1wRXh0OkRpZ2l0YWxTb3VyY2VGaWxlVHlwZT0iaHR0cDovL2N2LmlwdGMub3JnL25ld3Njb2Rlcy9kaWdpdGFsc291cmNldHlwZS90cmFpbmVkQWxnb3JpdGhtaWNNZWRpYSIgSXB0YzR4bXBFeHQ6RGlnaXRhbFNvdXJjZVR5cGU9Imh0dHA6Ly9jdi5pcHRjLm9yZy9uZXdzY29kZXMvZGlnaXRhbHNvdXJjZXR5cGUvdHJhaW5lZEFsZ29yaXRobWljTWVkaWEiIHBob3Rvc2hvcDpDcmVkaXQ9Ik1hZGUgd2l0aCBHb29nbGUgQUkiLz4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gICA8P3hwYWNrZXQgZW5kPSJ3Ij8+AA=="
};
function CoverImage({
  src,
  alt,
  slug,
  dims
}) {
  const [loaded, setLoaded] = reactExports.useState(false);
  const placeholder = COVER_PLACEHOLDER[slug];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    placeholder && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { "aria-hidden": true, className: "absolute inset-0 bg-cover bg-center scale-110", style: {
      backgroundImage: `url(${placeholder})`,
      filter: "blur(16px)",
      opacity: loaded ? 0 : 1,
      transition: "opacity 300ms ease-out"
    } }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src, alt, width: dims.w, height: dims.h, loading: "lazy", decoding: "async", onLoad: () => setLoaded(true), className: "absolute inset-0 w-full h-full object-cover", style: {
      opacity: loaded ? 1 : 0,
      transition: "opacity 300ms ease-out"
    } })
  ] });
}
const COVER_DIMS = {
  ludo: {
    w: 1080,
    h: 1064
  },
  domino: {
    w: 1024,
    h: 1024
  },
  fanorona: {
    w: 1024,
    h: 1024
  },
  chess: {
    w: 1024,
    h: 1024
  },
  rami: {
    w: 1024,
    h: 1024
  }
};
const META = {
  ludo: {
    label: "Ludo",
    cover: ludoCover.url,
    maxOpts: [2, 3, 4]
  },
  domino: {
    label: "Domino",
    cover: dominoCover.url,
    maxOpts: [2, 3]
  },
  fanorona: {
    label: "Fanorona",
    cover: fanoronaCover.url,
    maxOpts: [2]
  },
  chess: {
    label: "Échecs",
    cover: chessCover.url,
    maxOpts: [2]
  },
  rami: {
    label: "Rami",
    cover: ramiCover.url,
    maxOpts: [2, 3, 4]
  },
  poker: {
    label: "Poker",
    cover: pokerCover.url,
    maxOpts: [2, 3, 4, 5, 6, 7, 8, 9]
  }
};
const ROUTE = {
  ludo: "/jeux/ludo/$id",
  domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  chess: "/jeux/chess/$id",
  rami: "/jeux/rami/$id",
  poker: "/jeux/poker/$id"
};
const PART_TABLE = {
  ludo: "ludo_participants",
  domino: "domino_participants",
  fanorona: "fanorona_participants",
  chess: null,
  rami: "rami_participants",
  poker: "poker_players"
};
function extractGameId(data) {
  const row = Array.isArray(data) ? data[0] : data;
  const value = row && typeof row === "object" ? row.id ?? row.game_id : row;
  return typeof value === "string" && UUID_RE.test(value) ? value : null;
}
function Lobby() {
  const {
    slug: rawSlug
  } = Route$b.useParams();
  const slug = rawSlug;
  const meta = META[slug];
  const {
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const [tab, setTab] = reactExports.useState("public");
  const lobbyHelp = getLobbyHelp(slug, tab);
  const [showLeaderboard, setShowLeaderboard] = reactExports.useState(false);
  const [publicGames, setPublicGames] = reactExports.useState([]);
  const [mine, setMine] = reactExports.useState({
    ongoing: [],
    finished: []
  });
  const [mineTab, setMineTab] = reactExports.useState("ongoing");
  const [maxP, setMaxP] = reactExports.useState(meta?.maxOpts[0] ?? 2);
  const [stake, setStake] = reactExports.useState(1e3);
  const [mode, setMode] = reactExports.useState("classic");
  const [ludoAutoMove, setLudoAutoMove] = reactExports.useState(true);
  const [matchType, setMatchType] = reactExports.useState("solo");
  const [opponentMode, setOpponentMode] = reactExports.useState("bot");
  const [drawMode, setDrawMode] = reactExports.useState("without");
  const [firstTileRule, setFirstTileRule] = reactExports.useState("libre");
  const [targetScore, setTargetScore] = reactExports.useState(100);
  const [fanoronaVariant, setFanoronaVariant] = reactExports.useState("tsivy");
  const [fanoronaMandatory, setFanoronaMandatory] = reactExports.useState(true);
  const [fanoronaBotDifficulty, setFanoronaBotDifficulty] = reactExports.useState(3);
  const [ramiJokerMode, setRamiJokerMode] = reactExports.useState("sans");
  const [ramiGameMode, setRamiGameMode] = reactExports.useState("bordel");
  const [ramiSevenCards, setRamiSevenCards] = reactExports.useState(true);
  const [ramiBotDifficulty, setRamiBotDifficulty] = reactExports.useState("medium");
  const [pokerBlinds, setPokerBlinds] = reactExports.useState({
    sb: 10,
    bb: 20
  });
  const [pokerBuyIn, setPokerBuyIn] = reactExports.useState(2e3);
  const [chessBotDifficulty, setChessBotDifficulty] = reactExports.useState("medium");
  const [chessBotColor, setChessBotColor] = reactExports.useState("white");
  const [chessTime, setChessTime] = reactExports.useState(10);
  const [code, setCode] = reactExports.useState("");
  const [visibility, setVisibility] = reactExports.useState("public");
  const [commission] = reactExports.useState(10);
  const [busy, setBusy] = reactExports.useState(false);
  const [renameOpen, setRenameOpen] = reactExports.useState(false);
  const [pendingAction, setPendingAction] = reactExports.useState(null);
  const [showPhoneVerify, setShowPhoneVerify] = reactExports.useState(false);
  const [showDepositPopup, setShowDepositPopup] = reactExports.useState(false);
  const [showPremiumModal, setShowPremiumModal] = reactExports.useState(false);
  const [freeGameInfo, setFreeGameInfo] = reactExports.useState(null);
  const walletSettings = useAppSettings();
  const [sheet, setSheet] = reactExports.useState(null);
  const closeSheet = () => setSheet(null);
  const supportsPublicJoin = true;
  const checkGuards = (intendedStake) => {
    if (intendedStake <= 0) return true;
    const bal = Number(profile?.balance_ar || 0);
    if (bal < intendedStake) {
      toast.error("Solde insuffisant", {
        description: `Vous avez ${bal.toLocaleString("fr-FR")} Ar. Il vous faut ${intendedStake.toLocaleString("fr-FR")} Ar.`,
        action: {
          label: "Déposer",
          onClick: () => setShowDepositPopup(true)
        },
        duration: 8e3
      });
      return false;
    }
    if (!profile?.phone_verified) {
      toast.error("Numéro non vérifié", {
        description: "Vérifiez votre numéro avant de jouer avec une mise.",
        action: {
          label: "Vérifier",
          onClick: () => setShowPhoneVerify(true)
        },
        duration: 8e3
      });
      return false;
    }
    return true;
  };
  const loadPublic = async () => {
    if (slug === "ludo") {
      const {
        data
      } = await supabase.rpc("list_public_open_games");
      setPublicGames(data || []);
    } else {
      const {
        data
      } = await supabase.from(GAME_TABLE[slug]).select("*").eq("status", "open").eq("is_private", false).order("created_at", {
        ascending: false
      }).limit(20);
      setPublicGames(data || []);
    }
  };
  const loadMine = async () => {
    if (!profile?.id) return;
    if (slug === "ludo") {
      const {
        data
      } = await supabase.rpc("my_games");
      setMine(data || {
        ongoing: [],
        finished: []
      });
      return;
    }
    if (slug === "chess") {
      const {
        data
      } = await supabase.from("chess_games").select("*").or(`white_id.eq.${profile.id},black_id.eq.${profile.id}`).order("created_at", {
        ascending: false
      }).limit(60);
      const rows2 = data || [];
      setMine({
        ongoing: rows2.filter((r) => r.status === "open" || r.status === "playing"),
        finished: rows2.filter((r) => r.status === "finished" || r.status === "cancelled").map((r) => ({
          ...r,
          won: r.winner_id === profile.id
        }))
      });
      return;
    }
    const part = PART_TABLE[slug];
    const {
      data: parts
    } = await supabase.from(part).select("*, game:" + GAME_TABLE[slug] + "(*)").eq("user_id", profile.id);
    const rows = parts || [];
    setMine({
      ongoing: rows.filter((r) => r.game?.status === "open" || r.game?.status === "playing").map((r) => ({
        ...r.game,
        my_forfeited: r.forfeited
      })),
      finished: rows.filter((r) => r.game?.status === "finished" || r.game?.status === "cancelled").map((r) => ({
        ...r.game,
        won: r.game?.winner_id === profile?.id,
        forfeited: r.forfeited
      }))
    });
  };
  const loadFreeGameInfo = async () => {
    try {
      const {
        data,
        error
      } = await supabase.rpc("check_game_eligibility", {
        p_game_type: slug
      });
      if (!error && data) {
        const result = data;
        setFreeGameInfo({
          remainingToday: result.is_premium ? result.premium_remaining : result.remaining_today ?? 0,
          isPremium: result.is_premium || false,
          activeDaysUsed: result.active_days_used ?? 0,
          maxActiveDays: result.max_active_days ?? 5,
          premiumRemaining: result.premium_remaining ?? 0,
          tier: result.tier ?? null
        });
      }
    } catch (e) {
    }
  };
  reactExports.useEffect(() => {
    loadPublic();
    loadMine();
    loadFreeGameInfo();
    let debounceTimer;
    const ch = supabase.channel("lobby-" + slug).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: GAME_TABLE[slug],
      filter: "status=eq.open"
    }, () => {
      clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        loadPublic();
        loadMine();
      }, 500);
    }).subscribe();
    return () => {
      clearTimeout(debounceTimer);
      supabase.removeChannel(ch);
    };
  }, [slug, profile?.id]);
  const withAdminRename = (action) => () => {
    action();
  };
  const applyLudoAutoMove = async (gameId) => {
    if (slug !== "ludo" || !gameId) return;
    await supabase.rpc("ludo_set_auto_move", {
      _game_id: gameId,
      _enabled: ludoAutoMove
    });
  };
  const goTo = async (value) => {
    const id = extractGameId(value);
    if (!id) {
      toast("Partie créée, mais l'identifiant reçu est invalide. Réessayez depuis vos parties.");
      loadMine();
      return;
    }
    if (stake === 0) await incrementGameUsage();
    navigate({
      to: ROUTE[slug],
      params: {
        id
      }
    });
  };
  const checkFreeGameLimit = async () => {
    const {
      data,
      error
    } = await supabase.rpc("check_game_eligibility", {
      p_game_type: slug
    });
    if (error) {
      console.error("check_game_eligibility error:", error);
      return true;
    }
    const result = data;
    setFreeGameInfo({
      remainingToday: result.is_premium ? result.premium_remaining : result.remaining_today ?? 0,
      isPremium: result.is_premium || false,
      activeDaysUsed: result.active_days_used ?? 0,
      maxActiveDays: result.max_active_days ?? 5,
      premiumRemaining: result.premium_remaining ?? 0,
      tier: result.tier ?? null
    });
    if (!result.can_play) {
      toast("Prend un abonnement pour continuer à jouer gratuitement", {
        description: result.reason || "",
        action: {
          label: "S'abonner",
          onClick: () => setShowPremiumModal(true)
        },
        duration: 8e3
      });
      return false;
    }
    return true;
  };
  const incrementGameUsage = async () => {
    try {
      await supabase.rpc("increment_game_usage", {
        p_game_type: slug
      });
    } catch (e) {
      console.error("increment_game_usage error:", e);
    }
  };
  const joinPublicOrCreate = withAdminRename(async (overrideName) => {
    if (!await checkFreeGameLimit()) return;
    setBusy(true);
    try {
      if (opponentMode === "friends") {
        await createNewFree(visibility === "private");
        return;
      }
      let id = null;
      if (slug === "ludo") {
        const {
          data,
          error
        } = await supabase.rpc("ludo_start_solo_bot", {
          _max_players: maxP,
          _stake: 0,
          _mode: mode === "fast" ? "fast" : "classic",
          _match_type: matchType === "solo" ? "solo" : "groupe"
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        if (overrideName) await supabase.rpc("ludo_set_display_name", {
          _game_id: id,
          _name: overrideName
        });
        await applyLudoAutoMove(id);
      } else if (slug === "domino") {
        const {
          data,
          error
        } = await supabase.rpc("domino_create", {
          _stake: 0,
          _max: maxP,
          _private: true,
          _mode: mode === "points" ? "points" : "classic",
          _commission: commission,
          _target_score: mode === "points" ? targetScore : 0,
          _draw_mode: drawMode,
          _first_tile_rule: firstTileRule
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const {
            error: berr
          } = await supabase.rpc("domino_add_bot", {
            _game_id: id,
            _bot_name: `Bot ${i + 1}`
          });
          if (berr) throw berr;
        }
        await supabase.rpc("domino_set_ready", {
          _game_id: id,
          _ready: true
        });
      } else if (slug === "chess") {
        const diffMap = {
          very_easy: 1,
          easy: 2,
          medium: 3,
          hard: 4,
          expert: 5
        };
        const {
          data,
          error
        } = await supabase.rpc("chess_create_solo", {
          _difficulty: diffMap[chessBotDifficulty],
          _color: chessBotColor,
          _time_min: chessTime
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else if (slug === "fanorona") {
        const {
          data,
          error
        } = await supabase.rpc("fanorona_create_solo", {
          _stake: 0,
          _variant: fanoronaVariant,
          _mandatory_capture: fanoronaMandatory,
          _bot_intelligence: fanoronaBotDifficulty
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else if (slug === "rami") {
        const {
          data,
          error
        } = await supabase.rpc("rami_start_solo_bot", {
          _max_players: maxP,
          _difficulty: ramiBotDifficulty,
          _joker_mode: ramiJokerMode,
          _game_mode: ramiGameMode
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else if (slug === "poker") {
        const {
          data,
          error
        } = await supabase.rpc("poker_create", {
          _stake: 0,
          _max: maxP,
          _private: true,
          _commission: commission,
          _small_blind: pokerBlinds.sb,
          _big_blind: pokerBlinds.bb,
          _buy_in: pokerBuyIn
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const {
            error: berr
          } = await supabase.rpc("poker_add_bot", {
            _game_id: id
          });
          if (berr) throw berr;
        }
      } else {
        await createNewFree(false);
        return;
      }
      if (id) {
        refreshProfile();
        goTo(id);
      }
    } catch (e) {
      toast.error(e.message || "Erreur");
    } finally {
      setBusy(false);
    }
  });
  const createNewFree = async (priv) => {
    if (!await checkFreeGameLimit()) return;
    try {
      let id = null;
      if (slug === "ludo") {
        const fn = priv ? "create_private_game" : "find_or_create_game";
        const args = priv ? {
          _max_players: maxP,
          _stake: 0,
          _mode: mode === "fast" ? "fast" : "classic",
          _match_type: matchType === "solo" ? "solo" : "groupe"
        } : {
          _max_players: maxP,
          _stake: 0,
          _mode: mode === "fast" ? "fast" : "classic",
          _match_type: matchType === "solo" ? "solo" : "groupe"
        };
        const {
          data,
          error
        } = await supabase.rpc(fn, args);
        if (error) throw error;
        id = extractGameId(data);
        await applyLudoAutoMove(id);
      } else if (slug === "domino") {
        const {
          data,
          error
        } = await supabase.rpc("domino_create", {
          _stake: 0,
          _max: maxP,
          _private: priv,
          _mode: mode === "points" ? "points" : "classic",
          _commission: commission,
          _target_score: mode === "points" ? targetScore : 0,
          _draw_mode: drawMode,
          _first_tile_rule: firstTileRule
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "fanorona") {
        if (opponentMode === "bot") {
          const {
            data,
            error
          } = await supabase.rpc("fanorona_create_solo", {
            _stake: 0,
            _variant: fanoronaVariant,
            _mandatory_capture: fanoronaMandatory,
            _bot_intelligence: fanoronaBotDifficulty
          });
          if (error) throw error;
          id = extractGameId(data);
        } else {
          const {
            data,
            error
          } = await supabase.rpc("fanorona_create", {
            _stake: 0,
            _private: priv,
            _commission: commission,
            _variant: fanoronaVariant,
            _mandatory_capture: fanoronaMandatory
          });
          if (error) throw error;
          id = extractGameId(data);
        }
      } else if (slug === "chess") {
        const {
          data,
          error
        } = await supabase.rpc("chess_create_friends", {
          _time_min: chessTime
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "rami") {
        const {
          data,
          error
        } = await supabase.rpc("rami_create", {
          _stake: 0,
          _max: maxP,
          _private: priv,
          _commission: commission,
          _joker_mode: ramiJokerMode,
          _game_mode: ramiGameMode,
          _seven_cards: ramiSevenCards
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "poker") {
        const {
          data,
          error
        } = await supabase.rpc("poker_create", {
          _stake: 0,
          _max: maxP,
          _private: priv,
          _commission: commission,
          _small_blind: pokerBlinds.sb,
          _big_blind: pokerBlinds.bb,
          _buy_in: pokerBuyIn
        });
        if (error) throw error;
        id = extractGameId(data);
      }
      if (id) {
        if (stake === 0) await incrementGameUsage();
        shareNewGameInGroup(slug, id);
        refreshProfile();
        goTo(id);
      }
    } finally {
    }
  };
  const createNew = async (priv) => {
    let id = null;
    if (slug === "ludo") {
      const fn = priv ? "create_private_game" : "find_or_create_game";
      const args = priv ? {
        _max_players: maxP,
        _stake: stake,
        _mode: mode === "fast" ? "fast" : "classic",
        _match_type: matchType === "solo" ? "solo" : "groupe"
      } : {
        _max_players: maxP,
        _stake: stake,
        _mode: mode === "fast" ? "fast" : "classic",
        _match_type: matchType === "solo" ? "solo" : "groupe"
      };
      const {
        data,
        error
      } = await supabase.rpc(fn, args);
      if (error) throw error;
      id = extractGameId(data);
      await applyLudoAutoMove(id);
    } else if (slug === "domino") {
      const {
        data,
        error
      } = await supabase.rpc("domino_create", {
        _stake: stake,
        _max: maxP,
        _private: priv,
        _mode: mode === "points" ? "points" : "classic",
        _commission: commission,
        _target_score: mode === "points" ? targetScore : 0,
        _draw_mode: drawMode,
        _first_tile_rule: firstTileRule
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "fanorona") {
      if (opponentMode === "bot") {
        const {
          data,
          error
        } = await supabase.rpc("fanorona_create_solo", {
          _stake: 0,
          _variant: fanoronaVariant,
          _mandatory_capture: fanoronaMandatory,
          _bot_intelligence: fanoronaBotDifficulty
        });
        if (error) throw error;
        id = extractGameId(data);
      } else {
        const {
          data,
          error
        } = await supabase.rpc("fanorona_create", {
          _stake: stake,
          _private: priv,
          _commission: commission,
          _variant: fanoronaVariant,
          _mandatory_capture: fanoronaMandatory
        });
        if (error) throw error;
        id = extractGameId(data);
      }
    } else if (slug === "chess") {
      const {
        data,
        error
      } = await supabase.rpc("chess_create_stake", {
        _stake: stake,
        _time_min: chessTime
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "rami") {
      const {
        data,
        error
      } = await supabase.rpc("rami_create", {
        _stake: stake,
        _max: maxP,
        _private: priv,
        _commission: commission,
        _joker_mode: ramiJokerMode,
        _game_mode: ramiGameMode,
        _seven_cards: ramiSevenCards
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "poker") {
      const {
        data,
        error
      } = await supabase.rpc("poker_create", {
        _stake: stake,
        _max: maxP,
        _private: priv,
        _commission: commission,
        _small_blind: pokerBlinds.sb,
        _big_blind: pokerBlinds.bb,
        _buy_in: pokerBuyIn
      });
      if (error) throw error;
      id = extractGameId(data);
    }
    if (id) {
      if (stake === 0) await incrementGameUsage();
      shareNewGameInGroup(slug, id);
      refreshProfile();
      goTo(id);
    }
  };
  const createPrivate = withAdminRename(async (overrideName) => {
    if (!checkGuards(stake)) return;
    setBusy(true);
    try {
      await createNew(visibility === "private");
    } catch (e) {
      toast.error(e.message || "Erreur");
    } finally {
      setBusy(false);
    }
  });
  const joinByCode = withAdminRename(async () => {
    if (!code.trim()) return;
    setBusy(true);
    try {
      const fn = slug === "ludo" ? "join_game_by_code" : slug === "domino" ? "domino_join_code" : slug === "fanorona" ? "fanorona_join_code" : slug === "chess" ? "chess_join_friends" : slug === "poker" ? "poker_join_code" : "rami_join_code";
      const {
        data,
        error
      } = await supabase.rpc(fn, {
        _code: code.trim().toUpperCase()
      });
      if (error) throw error;
      refreshProfile();
      goTo(data);
    } catch (e) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient")) {
        toast.error("Solde insuffisant pour rejoindre cette partie.", {
          action: {
            label: "Déposer",
            onClick: () => setShowDepositPopup(true)
          }
        });
      } else {
        toast.error(e.message || "Code invalide");
      }
    } finally {
      setBusy(false);
    }
  });
  if (!meta) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-6", children: "Jeu inconnu." });
  const showMaxP = meta.maxOpts.length > 1;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto h-[100dvh] flex flex-col overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 px-3 pt-2 pb-1.5 shrink-0", children: [
      COVER_BY_SLUG$1[slug] && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "relative w-12 h-12 rounded-xl overflow-hidden shrink-0 ring-1 ring-primary/30 shadow bg-black/20", children: /* @__PURE__ */ jsxRuntimeExports.jsx(CoverImage, { src: COVER_BY_SLUG$1[slug], alt: meta.label, slug, dims: COVER_DIMS[slug] ?? {
        w: 1024,
        h: 1024
      } }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "inline-block text-[9px] uppercase tracking-[0.18em] font-bold text-primary px-1.5 py-0.5 rounded bg-primary/10 ring-1 ring-primary/20", children: "Créer une partie" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-lg leading-tight truncate mt-0.5 text-foreground", children: meta.label })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(HelpPopover, { trigger: "Aide", title: lobbyHelp.title, html: lobbyHelp.html, variant: "button" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { type: "button", onClick: () => setShowLeaderboard(true), className: "flex items-center gap-1 px-2.5 py-1.5 rounded-full bg-card border border-amber-500/25 text-amber-600 font-semibold text-[11px] shadow-sm active:scale-95 transition-transform", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3.5 h-3.5" }),
          " Classement"
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-3 pt-1 pb-3 flex flex-col gap-2 flex-1 min-h-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-4 gap-1.5 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Gratuit", active: tab === "public", onClick: () => setTab("public"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "🆓" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Mise", active: tab === "private", onClick: () => setTab("private"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "💰" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Code", active: tab === "code", onClick: () => setTab("code"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "🔑" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Mes", active: tab === "mine", onClick: () => setTab("mine"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "📂" }) })
      ] }),
      (tab === "public" && opponentMode === "friends" || tab === "private" && opponentMode === "friends") && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-1.5 shrink-0", role: "tablist", "aria-label": "Visibilité", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setVisibility("public"), "aria-pressed": visibility === "public", className: `px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] border ${visibility === "public" ? "bg-emerald-500/15 text-emerald-600 border-emerald-500/40" : "bg-card border-white/8 text-muted-foreground hover:text-foreground"}`, children: [
          "🌐 ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Public" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setVisibility("private"), "aria-pressed": visibility === "private", className: `px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] border ${visibility === "private" ? "bg-orange-500/15 text-orange-600 border-orange-500/40" : "bg-card border-white/8 text-muted-foreground hover:text-foreground"}`, children: [
          "🔒 ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Privé" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-h-0 overflow-y-auto -mx-1 px-1 space-y-2", children: [
        tab === "public" && supportsPublicJoin && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-1.5 shadow-sm divide-y divide-white/5", children: [
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎯", label: "Équipe", value: matchType === "solo" ? "🎯 Solo" : "👥 Groupe", onClick: () => setSheet("opponent") }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⚔️", label: "Adversaire", value: opponentMode === "bot" ? "🎯 vs Bot" : "👥 vs Amis", onClick: () => setSheet("opponent_mode") }),
            meta.maxOpts.length > 1 && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "👥", label: "Joueurs", value: `${maxP}`, onClick: () => setSheet("players") }),
            slug === "domino" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Format", value: mode === "points" ? `Par points (${targetScore})` : "Victoire directe", onClick: () => setSheet("domino_mode") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🁣", label: "Pioche", value: drawMode === "with" ? "Avec" : "Sans", onClick: () => setSheet("domino_draw") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎬", label: "Premier coup", value: firstTileRule === "libre" ? "Libre" : "1er <6", onClick: () => setSheet("domino_first") })
            ] }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Mode", value: mode === "fast" ? "Moderne" : "Classique", onClick: () => setSheet("ludo_mode") }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Déplacement auto", value: ludoAutoMove ? "Activé" : "Désactivé", onClick: () => setLudoAutoMove((v) => !v) }),
            slug === "fanorona" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⚫", label: "Plateau", value: `${fanoronaVariant} · ${fanoronaMandatory ? "obligatoire" : "libre"}`, onClick: () => setSheet("fanorona") }),
              opponentMode === "bot" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⭐", label: "Difficulté", value: {
                1: "⭐ Débutant",
                2: "⭐⭐ Amateur",
                3: "⭐⭐⭐ Confirmé",
                4: "⭐⭐⭐⭐ Expert",
                5: "⭐⭐⭐⭐⭐ Maître"
              }[fanoronaBotDifficulty], onClick: () => setSheet("fanorona_diff") })
            ] }),
            slug === "chess" && opponentMode === "bot" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⭐", label: "Difficulté", value: {
                very_easy: "⭐ 600",
                easy: "⭐⭐ 900",
                medium: "⭐⭐⭐ 1200",
                hard: "⭐⭐⭐⭐ 1700",
                expert: "⭐⭐⭐⭐⭐ 2200"
              }[chessBotDifficulty], onClick: () => setSheet("chess_diff") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: chessBotColor === "white" ? "⚪" : "⚫", label: "Couleur", value: chessBotColor === "white" ? "Blancs" : "Noirs", onClick: () => setSheet("chess_color") })
            ] }),
            slug === "poker" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🪙", label: "Blindes", value: `${pokerBlinds.sb} / ${pokerBlinds.bb}`, onClick: () => setSheet("poker_blinds") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "💵", label: "Cave (jetons)", value: pokerBuyIn.toLocaleString("fr-FR"), onClick: () => setSheet("poker_buyin") })
            ] }),
            slug === "rami" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🃏", label: "Joker", value: {
                sans: "Sans",
                aleatoire: "Couleur opposée",
                classique: "Classique",
                double: "Double"
              }[ramiJokerMode], onClick: () => setSheet("rami") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "📜", label: "Mode de jeu", value: ramiGameMode === "naturel" ? "Naturel" : "Bordel", onClick: () => setSheet("rami_mode") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "7️⃣", label: "7 Cartes", value: ramiSevenCards ? "Activé" : "Désactivé", onClick: () => setSheet("rami_seven") }),
              opponentMode === "bot" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⭐", label: "Niveau des bots", value: {
                easy: "⭐ Facile",
                medium: "⭐⭐ Moyen",
                hard: "⭐⭐⭐ Difficile"
              }[ramiBotDifficulty], onClick: () => setSheet("rami_diff") })
            ] }),
            slug === "chess" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⏱️", label: "Temps / joueur", value: chessTime === 999 ? "Illimité" : `${chessTime} min`, onClick: () => setSheet("chess_time") })
          ] }),
          opponentMode === "friends" && visibility === "private" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-primary/8 border border-primary/20 px-3 py-2 text-[11px] text-primary/90 flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-3.5 h-3.5 shrink-0" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Un code d'invitation à 6 caractères sera généré." })
          ] }),
          freeGameInfo && freeGameInfo.isPremium && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-xl bg-emerald-500/10 border border-emerald-500/20 px-3 py-2 text-[11px] text-emerald-600 flex items-center gap-2", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { children: [
            "👑 Abonnement ",
            freeGameInfo.tier,
            " actif — ",
            freeGameInfo.premiumRemaining,
            " partie(s) restante(s) ce mois"
          ] }) }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: joinPublicOrCreate, disabled: busy, className: "w-full py-3.5 rounded-full text-white font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-primary/40 active:scale-[0.98] transition-transform sticky bottom-2", style: {
            background: "var(--gradient-primary)"
          }, children: opponentMode === "friends" ? visibility === "public" ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer la partie"
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer et inviter"
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Commencer la partie"
          ] }) })
        ] }),
        tab === "private" && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-1.5 shadow-sm divide-y divide-white/5", children: [
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎯", label: "Équipe", value: matchType === "solo" ? "🎯 Solo" : "👥 Groupe", onClick: () => setSheet("opponent") }),
            showMaxP && (slug !== "ludo" || matchType === "solo") && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "👥", label: "Joueurs", value: `${maxP}`, onClick: () => setSheet("players") }),
            slug === "ludo" && matchType === "groupe" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "👥", label: "Joueurs", value: "4 (2v2)", onClick: () => {
            } }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "💰", label: "Mise", value: stake > 0 ? `${stake.toLocaleString("fr-FR")} Ar` : "Gratuit", onClick: () => setSheet("stake") }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Mode", value: mode === "fast" ? "Moderne" : "Classique", onClick: () => setSheet("ludo_mode") }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Déplacement auto", value: ludoAutoMove ? "Activé" : "Désactivé", onClick: () => setLudoAutoMove((v) => !v) }),
            slug === "domino" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Format", value: mode === "points" ? `Par points (${targetScore})` : "Victoire directe", onClick: () => setSheet("domino_mode") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🁣", label: "Pioche", value: drawMode === "with" ? "Avec" : "Sans", onClick: () => setSheet("domino_draw") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎬", label: "Premier coup", value: firstTileRule === "libre" ? "Libre" : "1er <6", onClick: () => setSheet("domino_first") })
            ] }),
            slug === "fanorona" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⚫", label: "Plateau", value: `${fanoronaVariant} · ${fanoronaMandatory ? "obligatoire" : "libre"}`, onClick: () => setSheet("fanorona") }),
              opponentMode === "bot" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⭐", label: "Difficulté", value: {
                1: "⭐ Débutant",
                2: "⭐⭐ Amateur",
                3: "⭐⭐⭐ Confirmé",
                4: "⭐⭐⭐⭐ Expert",
                5: "⭐⭐⭐⭐⭐ Maître"
              }[fanoronaBotDifficulty], onClick: () => setSheet("fanorona_diff") })
            ] }),
            slug === "rami" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🃏", label: "Joker", value: {
                sans: "Sans",
                aleatoire: "Couleur opposée",
                classique: "Classique",
                double: "Double"
              }[ramiJokerMode], onClick: () => setSheet("rami") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "📜", label: "Mode de jeu", value: ramiGameMode === "naturel" ? "Naturel" : "Bordel", onClick: () => setSheet("rami_mode") })
            ] }),
            slug === "poker" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🪙", label: "Blindes", value: `${pokerBlinds.sb} / ${pokerBlinds.bb}`, onClick: () => setSheet("poker_blinds") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "💵", label: "Cave (jetons)", value: pokerBuyIn.toLocaleString("fr-FR"), onClick: () => setSheet("poker_buyin") })
            ] }),
            slug === "chess" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⏱️", label: "Temps / joueur", value: chessTime === 999 ? "Illimité" : `${chessTime} min`, onClick: () => setSheet("chess_time") })
          ] }),
          stake > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-1.5 text-xs", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-amber-500/8 border border-amber-500/20 p-2 text-center", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] text-amber-500/80 uppercase tracking-wider font-bold", children: "Cagnotte" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm", children: [
                (stake * maxP).toLocaleString("fr-FR"),
                " Ar"
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-emerald-500/10 border border-emerald-500/25 p-2 text-center", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] text-emerald-600/90 uppercase tracking-wider font-bold", children: "Gain net" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm text-emerald-600", children: [
                Math.round(stake * maxP * (100 - commission) / 100).toLocaleString("fr-FR"),
                " Ar"
              ] })
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: createPrivate, disabled: busy || slug === "domino" && mode === "points" && targetScore < 1, className: "w-full py-3.5 rounded-full text-white font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-primary/40 active:scale-[0.98] transition-transform sticky bottom-2", style: {
            background: "var(--gradient-primary)"
          }, children: visibility === "public" ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer la partie"
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer la partie privée"
          ] }) }),
          visibility === "private" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground text-center", children: "Un code à 6 caractères sera généré pour inviter tes amis." })
        ] }),
        tab === "code" && /* @__PURE__ */ jsxRuntimeExports.jsx("section", { className: "space-y-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-5 shadow-md space-y-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 rounded-lg bg-primary/15 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-4 h-4 text-primary" }) }),
            "Code de la partie"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: code, onChange: (e) => setCode(e.target.value.toUpperCase()), placeholder: "EX: A1B2C3", maxLength: 6, className: "w-full px-4 py-3 rounded-2xl bg-secondary border border-border outline-none uppercase tracking-[0.4em] font-mono text-center text-xl" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: joinByCode, disabled: busy || !code.trim(), className: "w-full py-3 rounded-full text-white font-bold", style: {
            background: "var(--gradient-primary)"
          }, children: busy ? "…" : "Rejoindre" })
        ] }) }),
        tab === "mine" && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: `🎮 En cours (${mine.ongoing.length})`, active: mineTab === "ongoing", onClick: () => setMineTab("ongoing") }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: `🏁 Terminées (${mine.finished.length})`, active: mineTab === "finished", onClick: () => setMineTab("finished") })
          ] }),
          mineTab === "ongoing" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
            mine.ongoing.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Aucune partie en cours." }),
            mine.ongoing.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm hover:border-primary/20 transition-colors", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${g.status === "open" ? "bg-amber-500/10 border border-amber-500/15" : "bg-primary/10 border border-primary/15"}`, children: g.status === "open" ? "⏳" : "🎮" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: g.status === "open" ? "En attente" : "Partie en cours" }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-0.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] text-muted-foreground", children: [
                    "Mise ",
                    Number(g.stake || 0).toLocaleString("fr-FR"),
                    " Ar"
                  ] }),
                  g.is_private && g.room_code && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-mono text-muted-foreground/60 bg-white/5 px-1.5 py-0.5 rounded", children: g.room_code })
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => goTo(g.id), className: "flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-xs shadow-md shadow-primary/20 active:scale-95 transition-all shrink-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(RotateCw, { className: "w-3.5 h-3.5" }),
                " Reprendre"
              ] })
            ] }, g.id))
          ] }),
          mineTab === "finished" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
            mine.finished.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Aucune partie terminée." }),
            mine.finished.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0 border ${g.won ? "bg-amber-500/10 border-amber-500/20" : g.forfeited ? "bg-destructive/8 border-destructive/15" : "bg-white/5 border-white/8"}`, children: g.won ? "🏆" : g.forfeited ? "🏳️" : "💔" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `font-bold text-sm ${g.won ? "text-amber-500" : g.forfeited ? "text-destructive" : ""}`, children: g.won ? "Victoire" : g.forfeited ? "Forfait" : "Défaite" }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
                  Number(g.stake || 0).toLocaleString("fr-FR"),
                  " Ar · ",
                  Number(g.pot || 0).toLocaleString("fr-FR"),
                  " Ar pot"
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground/50 shrink-0 text-right", children: g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : "" })
            ] }, g.id))
          ] })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "opponent", onClose: closeSheet, title: "Équipe", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "solo",
      l: "🎯 Solo"
    }, {
      v: "groupe",
      l: "👥 Groupe"
    }], value: matchType, onChange: (v) => {
      setMatchType(v);
      if (v === "groupe") setMaxP(4);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "opponent_mode", onClose: closeSheet, title: "Adversaire", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "bot",
      l: "🎯 vs Bot"
    }, {
      v: "friends",
      l: "👥 vs Amis"
    }], value: opponentMode, onChange: (v) => {
      setOpponentMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "players", onClose: closeSheet, title: "Nombre de joueurs", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid gap-2", style: {
      gridTemplateColumns: `repeat(${meta.maxOpts.length}, minmax(0,1fr))`
    }, children: meta.maxOpts.map((n) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
      setMaxP(n);
      closeSheet();
    }, className: `py-3 rounded-xl font-bold ${maxP === n ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-secondary"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg", children: n }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase opacity-70", children: "Joueurs" })
    ] }, n)) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "stake", onClose: closeSheet, title: "Mise (Ariary)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(StakePicker, { stake, setStake, onDone: closeSheet }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "ludo_mode", onClose: closeSheet, title: "Mode de jeu", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "classic",
      l: "Classique"
    }, {
      v: "fast",
      l: "Moderne"
    }], value: mode, onChange: (v) => {
      setMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "domino_mode", onClose: closeSheet, title: "Format", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
        v: "direct",
        l: "Victoire directe"
      }, {
        v: "points",
        l: "Par points"
      }], value: mode, onChange: (v) => setMode(v) }),
      mode === "points" && /* @__PURE__ */ jsxRuntimeExports.jsx(TargetScorePicker, { value: targetScore, onChange: setTargetScore }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: closeSheet, className: "w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "domino_draw", onClose: closeSheet, title: "Pioche", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "with",
      l: "Avec pioche"
    }, {
      v: "without",
      l: "Sans pioche"
    }], value: drawMode, onChange: (v) => {
      setDrawMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "domino_first", onClose: closeSheet, title: "Premier coup", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "libre",
      l: "Libre"
    }, {
      v: "under6",
      l: "1er domino <6"
    }], value: firstTileRule, onChange: (v) => {
      setFirstTileRule(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(BottomSheet, { open: sheet === "fanorona", onClose: closeSheet, title: "Fanorona", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(FanoronaConfigBlock, { variant: fanoronaVariant, onVariant: setFanoronaVariant, mandatory: fanoronaMandatory, onMandatory: setFanoronaMandatory, botDifficulty: opponentMode === "bot" ? fanoronaBotDifficulty : void 0, onBotDifficulty: opponentMode === "bot" ? setFanoronaBotDifficulty : void 0 }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: closeSheet, className: "mt-3 w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "fanorona_diff", onClose: closeSheet, title: "Difficulté du bot", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 5, options: [{
      v: "1",
      l: "⭐",
      sub: "Débutant"
    }, {
      v: "2",
      l: "⭐⭐",
      sub: "Amateur"
    }, {
      v: "3",
      l: "⭐⭐⭐",
      sub: "Confirmé"
    }, {
      v: "4",
      l: "⭐⭐⭐⭐",
      sub: "Expert"
    }, {
      v: "5",
      l: "⭐⭐⭐⭐⭐",
      sub: "Maître"
    }], value: String(fanoronaBotDifficulty), onChange: (v) => {
      setFanoronaBotDifficulty(Number(v));
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami", onClose: closeSheet, title: "Mode Joker", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RamiJokerBlock, { value: ramiJokerMode, onChange: (v) => {
      setRamiJokerMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami_mode", onClose: closeSheet, title: "Mode de jeu", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RamiGameModeBlock, { value: ramiGameMode, onChange: (v) => {
      setRamiGameMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami_seven", onClose: closeSheet, title: "7 Cartes (Miverim-bola)", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
        setRamiSevenCards(true);
        closeSheet();
      }, className: `w-full py-3 px-3 rounded-2xl font-semibold text-xs text-left ${ramiSevenCards ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: "7️⃣ 7 Cartes activé" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[10px] mt-0.5 ${ramiSevenCards ? "opacity-90" : "text-muted-foreground"}`, children: "Le joueur qui valide 7 cartes (trio + carré ou trio + suite ou suite + carré) récupère sa mise. Le gagnant prend le pot restant." })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
        setRamiSevenCards(false);
        closeSheet();
      }, className: `w-full py-3 px-3 rounded-2xl font-semibold text-xs text-left ${!ramiSevenCards ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: "🚫 7 Cartes désactivé" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[10px] mt-0.5 ${!ramiSevenCards ? "opacity-90" : "text-muted-foreground"}`, children: "Le joueur doit valider toutes ses cartes pour gagner. Pas de remboursement de mise." })
      ] })
    ] }) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami_diff", onClose: closeSheet, title: "Niveau des bots", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 3, options: [{
      v: "easy",
      l: "⭐",
      sub: "Facile"
    }, {
      v: "medium",
      l: "⭐⭐",
      sub: "Moyen"
    }, {
      v: "hard",
      l: "⭐⭐⭐",
      sub: "Difficile"
    }], value: ramiBotDifficulty, onChange: (v) => {
      setRamiBotDifficulty(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "poker_blinds", onClose: closeSheet, title: "Blindes (petite / grosse)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 2, options: [{
      v: "10",
      l: "10 / 20",
      sub: "Micro"
    }, {
      v: "25",
      l: "25 / 50",
      sub: "Basse"
    }, {
      v: "50",
      l: "50 / 100",
      sub: "Moyenne"
    }, {
      v: "100",
      l: "100 / 200",
      sub: "Haute"
    }], value: String(pokerBlinds.sb), onChange: (v) => {
      const sb = Number(v);
      setPokerBlinds({
        sb,
        bb: sb * 2
      });
      setPokerBuyIn((b) => Math.max(b, sb * 2 * 20));
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "poker_buyin", onClose: closeSheet, title: "Cave de départ (jetons)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 2, options: [{
      v: String(pokerBlinds.bb * 20),
      l: `${(pokerBlinds.bb * 20).toLocaleString("fr-FR")}`,
      sub: "20 BB"
    }, {
      v: String(pokerBlinds.bb * 50),
      l: `${(pokerBlinds.bb * 50).toLocaleString("fr-FR")}`,
      sub: "50 BB"
    }, {
      v: String(pokerBlinds.bb * 100),
      l: `${(pokerBlinds.bb * 100).toLocaleString("fr-FR")}`,
      sub: "100 BB"
    }, {
      v: String(pokerBlinds.bb * 200),
      l: `${(pokerBlinds.bb * 200).toLocaleString("fr-FR")}`,
      sub: "200 BB"
    }], value: String(pokerBuyIn), onChange: (v) => {
      setPokerBuyIn(Number(v));
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "chess_diff", onClose: closeSheet, title: "Difficulté du bot", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 5, options: [{
      v: "very_easy",
      l: "⭐",
      sub: "600"
    }, {
      v: "easy",
      l: "⭐⭐",
      sub: "900"
    }, {
      v: "medium",
      l: "⭐⭐⭐",
      sub: "1200"
    }, {
      v: "hard",
      l: "⭐⭐⭐⭐",
      sub: "1700"
    }, {
      v: "expert",
      l: "⭐⭐⭐⭐⭐",
      sub: "2200"
    }], value: chessBotDifficulty, onChange: (v) => {
      setChessBotDifficulty(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "chess_color", onClose: closeSheet, title: "Ta couleur", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "white",
      l: "⚪ Blancs"
    }, {
      v: "black",
      l: "⚫ Noirs"
    }], value: chessBotColor, onChange: (v) => {
      setChessBotColor(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(BottomSheet, { open: sheet === "chess_time", onClose: closeSheet, title: "Temps par joueur", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ChessTimePicker, { value: chessTime, onChange: setChessTime }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: closeSheet, className: "mt-3 w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(AdminRenameDialog, { open: renameOpen, defaultName: profile?.pseudo || "", onCancel: () => {
      setRenameOpen(false);
      setPendingAction(null);
    }, onConfirm: async (name) => {
      setRenameOpen(false);
      const action = pendingAction;
      setPendingAction(null);
      if (action) await action(name);
    } }),
    showPhoneVerify && /* @__PURE__ */ jsxRuntimeExports.jsx(PhoneVerifyPopup, { onClose: () => setShowPhoneVerify(false) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(DepotModal, { open: showDepositPopup, onClose: () => setShowDepositPopup(false), mvolaPhone: walletSettings.mvolaPhone, mvolaName: walletSettings.mvolaName, orangePhone: walletSettings.orangePhone, orangeName: walletSettings.orangeName, airtelPhone: walletSettings.airtelPhone, airtelName: walletSettings.airtelName, minDeposit: walletSettings.minDeposit, onSuccess: () => {
      refreshProfile();
    } }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(PremiumSubscriptionModal, { open: showPremiumModal, onClose: () => setShowPremiumModal(false) }),
    showLeaderboard && /* @__PURE__ */ jsxRuntimeExports.jsx(GameLeaderboardModal, { slug, gameLabel: meta.label, onClose: () => setShowLeaderboard(false) })
  ] });
}
function SummaryRow({
  icon,
  label,
  value,
  onClick
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: "w-full flex items-center gap-3 px-3 py-3 active:bg-white/5 transition rounded-xl", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-lg leading-none w-6 text-center shrink-0", children: icon }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[13px] font-semibold text-foreground/80 shrink-0", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[13px] font-bold text-foreground truncate max-w-[55%] text-right", children: value }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground/60 text-lg leading-none shrink-0", children: "›" })
  ] });
}
function BottomSheet({
  open,
  onClose,
  title,
  children
}) {
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "fixed inset-0 z-50 flex items-end sm:items-center justify-center", onClick: onClose, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-black/50 backdrop-blur-sm" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative w-full sm:max-w-md bg-card rounded-t-3xl sm:rounded-3xl p-4 space-y-3 max-h-[80dvh] overflow-y-auto border-t border-white/10 shadow-2xl", onClick: (e) => e.stopPropagation(), style: {
      animation: "slideUp 200ms ease-out"
    }, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-base", children: title }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, "aria-label": "Fermer", className: "w-8 h-8 rounded-full bg-secondary flex items-center justify-center text-lg leading-none", children: "×" })
      ] }),
      children
    ] })
  ] });
}
function StakePicker({
  stake,
  setStake,
  onDone
}) {
  const [custom, setCustom] = reactExports.useState(!STAKES.includes(stake));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-end", children: /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setCustom((c) => !c), className: "text-[11px] font-semibold text-primary", children: custom ? "Préréglages" : "Saisie libre" }) }),
    custom ? /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 200, value: stake, onChange: (e) => setStake(Math.max(200, Number(e.target.value) || 0)), placeholder: "Montant en Ariary", className: "w-full px-4 py-3 rounded-xl bg-secondary outline-none text-center font-bold text-lg" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: STAKES.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setStake(s), className: `py-3 rounded-xl font-bold text-sm ${stake === s ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-secondary"}`, children: [
      s >= 1e3 ? `${s / 1e3}k` : s,
      " Ar"
    ] }, s)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onDone, className: "w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
  ] });
}
function TabBtn({
  label,
  active,
  onClick,
  icon
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: `px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] ${active ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-card border border-white/8 text-muted-foreground hover:text-foreground hover:bg-card/80"}`, children: [
    icon,
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: label })
  ] });
}
function ModeBlock({
  options,
  value,
  onChange,
  title,
  columns
}) {
  const cols = columns ?? 2;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-2.5 shadow-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold uppercase tracking-widest text-foreground/70 mb-1.5", children: title ?? "Mode" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid gap-1.5", style: {
      gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`
    }, children: options.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onChange(m.v), className: `min-w-0 py-1.5 px-1 rounded-lg font-semibold text-xs transition-all active:scale-[0.97] border ${value === m.v ? "bg-primary text-primary-foreground border-primary/0 shadow-md shadow-primary/20" : "bg-secondary border-white/6 text-muted-foreground hover:text-foreground"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "leading-tight truncate", children: m.l }),
      m.sub && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[9px] mt-0.5 font-normal leading-tight truncate ${value === m.v ? "opacity-85" : "opacity-70"}`, children: m.sub })
    ] }, m.v)) })
  ] });
}
function TargetScorePicker({
  value,
  onChange
}) {
  const presets = [10, 20, 30, 40, 50];
  const [custom, setCustom] = reactExports.useState(!presets.includes(value));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold mb-2 flex items-center gap-2 justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Target, { className: "w-4 h-4" }),
        " Score cible"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setCustom((c) => !c), className: "text-xs font-semibold text-primary", children: custom ? "Préréglages" : "Saisie libre" })
    ] }),
    custom ? /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 1, max: 1e3, value, onChange: (e) => onChange(Math.max(1, Number(e.target.value) || 0)), className: "w-full px-4 py-3 rounded-2xl bg-secondary outline-none font-bold text-lg text-center" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-5 gap-2", children: presets.map((n) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => onChange(n), className: `py-2.5 rounded-2xl font-bold text-sm ${value === n ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: n }, n)) })
  ] });
}
function FanoronaConfigBlock({
  variant,
  onVariant,
  mandatory,
  onMandatory,
  botDifficulty,
  onBotDifficulty
}) {
  const variants = [{
    v: "telo",
    l: "Telo (3×3)",
    d: "9 cases"
  }, {
    v: "dimy",
    l: "Dimy (5×5)",
    d: "25 cases"
  }, {
    v: "tsivy",
    l: "Tsivy (9×5)",
    d: "45 cases · classique"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-2", children: "Variante du plateau" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: variants.map((x) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onVariant(x.v), className: `py-2.5 rounded-2xl font-bold text-sm ${variant === x.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: x.l }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] opacity-80 font-normal", children: x.d })
      ] }, x.v)) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-2", children: "Règle de capture" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => onMandatory(true), className: `py-3 rounded-2xl font-semibold text-sm ${mandatory ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: "Capture obligatoire" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => onMandatory(false), className: `py-3 rounded-2xl font-semibold text-sm ${!mandatory ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: "Capture non obligatoire" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground mt-2", children: "L'enchaînement reste actif dans les deux cas." })
    ] }),
    botDifficulty !== void 0 && onBotDifficulty && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-2", children: "Difficulté du bot" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-5 gap-1.5", children: [{
        v: 1,
        l: "⭐",
        d: "Débutant"
      }, {
        v: 2,
        l: "⭐⭐",
        d: "Amateur"
      }, {
        v: 3,
        l: "⭐⭐⭐",
        d: "Confirmé"
      }, {
        v: 4,
        l: "⭐⭐⭐⭐",
        d: "Expert"
      }, {
        v: 5,
        l: "⭐⭐⭐⭐⭐",
        d: "Maître"
      }].map((x) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onBotDifficulty(x.v), className: `py-2.5 rounded-2xl font-bold text-xs ${botDifficulty === x.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: x.l }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] opacity-80 font-normal", children: x.d })
      ] }, x.v)) })
    ] })
  ] });
}
function RamiJokerBlock({
  value,
  onChange
}) {
  const opts = [{
    v: "sans",
    l: "Sans Joker",
    d: "104 cartes (2 paquets), aucun Joker"
  }, {
    v: "aleatoire",
    l: "Joker couleur opposée",
    d: "Tirage aléatoire → couleur opposée = Joker"
  }, {
    v: "classique",
    l: "Jokers classiques",
    d: "4 Jokers physiques (2 par paquet)"
  }, {
    v: "double",
    l: "Double Joker",
    d: "4 Jokers physiques + couleur opposée"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-1", children: "Mode Joker" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-2 gap-2", children: opts.map((o) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onChange(o.v), className: `py-2.5 px-2 rounded-2xl font-semibold text-xs text-left ${value === o.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: o.l }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[10px] mt-0.5 ${value === o.v ? "opacity-90" : "text-muted-foreground"}`, children: o.d })
    ] }, o.v)) })
  ] });
}
function RamiGameModeBlock({
  value,
  onChange
}) {
  const opts = [{
    v: "bordel",
    l: "🎉 Mode Bordel",
    d: "Pose libre, ajout possible dès le début"
  }, {
    v: "naturel",
    l: "📜 Mode Naturel",
    d: "1ère pose obligatoire : brelan ou suite de 3+ avant d'ajouter"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-1", children: "Mode de jeu" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-1 gap-2", children: opts.map((o) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onChange(o.v), className: `py-3 px-3 rounded-2xl font-semibold text-xs text-left ${value === o.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: o.l }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[10px] mt-0.5 ${value === o.v ? "opacity-90" : "text-muted-foreground"}`, children: o.d })
    ] }, o.v)) })
  ] });
}
function ChessTimePicker({
  value,
  onChange
}) {
  const presets = [3, 5, 10, 999];
  const isPreset = presets.includes(value);
  const [custom, setCustom] = reactExports.useState(isPreset ? "" : String(value));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-3 shadow-[var(--shadow-soft)] space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Temps par joueur" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-4 gap-1.5", children: [{
      v: 3,
      l: "⚡ 3′"
    }, {
      v: 5,
      l: "🔥 5′"
    }, {
      v: 10,
      l: "⏱️ 10′"
    }, {
      v: 999,
      l: "♾️"
    }].map((o) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
      onChange(o.v);
      setCustom("");
    }, className: `py-2 rounded-xl font-bold text-xs transition-all active:scale-95 ${value === o.v && !custom ? "bg-primary text-primary-foreground shadow-sm shadow-primary/20" : "bg-secondary text-foreground"}`, children: o.l }, o.v)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 pt-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] text-muted-foreground shrink-0", children: "Perso." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 1, max: 180, inputMode: "numeric", placeholder: "ex. 15", value: custom, onChange: (e) => {
        const raw = e.target.value;
        setCustom(raw);
        const n = Math.max(1, Math.min(180, Number(raw) || 0));
        if (n > 0) onChange(n);
      }, className: `flex-1 min-w-0 px-3 py-1.5 rounded-lg bg-secondary text-sm font-bold text-center outline-none border ${custom ? "border-primary/40" : "border-transparent"}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] text-muted-foreground shrink-0", children: "min" })
    ] })
  ] });
}
export {
  Lobby as component
};
