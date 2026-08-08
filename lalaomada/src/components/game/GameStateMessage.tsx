import { useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";
import { Trophy, Frown, Clock, XCircle } from "lucide-react";

/**
 * Affiche un message clair quand un utilisateur arrive sur une partie
 * qui est dans un état non jouable (terminée, annulée, éliminé).
 */
export default function GameStateMessage({
  state,
  gameLabel,
  slug,
  message,
}: {
  state: "finished" | "cancelled" | "eliminated" | "expired";
  gameLabel?: string;
  slug?: string;
  message?: string;
}) {
  const navigate = useNavigate();

  const config = {
    finished: {
      icon: Trophy,
      color: "text-amber-500",
      bg: "bg-amber-500/10",
      border: "border-amber-500/25",
      title: "Partie terminée",
      desc: message ?? "Cette partie est déjà terminée. Vous ne pouvez pas la rejoindre.",
    },
    cancelled: {
      icon: XCircle,
      color: "text-slate-400",
      bg: "bg-slate-500/10",
      border: "border-slate-500/25",
      title: "Partie annulée",
      desc: message ?? "Cette partie a été annulée. La mise a été remboursée.",
    },
    eliminated: {
      icon: Frown,
      color: "text-destructive",
      bg: "bg-destructive/10",
      border: "border-destructive/25",
      title: "Vous êtes éliminé",
      desc: message ?? "Vous avez été éliminé de cette partie. Vous pouvez la regarder en spectateur.",
    },
    expired: {
      icon: Clock,
      color: "text-slate-400",
      bg: "bg-slate-500/10",
      border: "border-slate-500/25",
      title: "Invitation expirée",
      desc: message ?? "Cette partie a expiré faute de joueurs.",
    },
  };

  const cfg = config[state];
  const Icon = cfg.icon;

  useEffect(() => {
    // Auto-redirect after 3 seconds for cancelled/expired games
    if (state === "cancelled" || state === "expired") {
      const t = setTimeout(() => {
        navigate({ to: slug ? "/jeux/$slug" : "/jeux", params: slug ? { slug } : undefined } as any);
      }, 3000);
      return () => clearTimeout(t);
    }
  }, [state, slug, navigate]);

  return (
    <main className="max-w-md mx-auto px-4 py-12 space-y-6">
      <div className={`rounded-3xl ${cfg.bg} border ${cfg.border} p-8 text-center space-y-4`}>
        <div className={`w-16 h-16 rounded-full ${cfg.bg} grid place-items-center mx-auto`}>
          <Icon className={`w-8 h-8 ${cfg.color}`} />
        </div>
        <div>
          <h1 className="text-xl font-extrabold mb-1">{cfg.title}</h1>
          {gameLabel && <p className="text-sm text-muted-foreground">{gameLabel}</p>}
        </div>
        <p className="text-sm text-muted-foreground">{cfg.desc}</p>
      </div>

      <div className="flex flex-col gap-2">
        {state === "eliminated" && (
          <button
            onClick={() => navigate({ to: "/jeux" })}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition"
          >
            Retour aux jeux
          </button>
        )}
        {state === "finished" && (
          <button
            onClick={() => navigate({ to: "/jeux" })}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition"
          >
            Nouvelle partie
          </button>
        )}
        <button
          onClick={() => navigate({ to: "/jeux" })}
          className="w-full py-3 rounded-2xl bg-secondary text-foreground font-bold text-sm active:scale-95 transition"
        >
          Accueil
        </button>
      </div>
    </main>
  );
}
