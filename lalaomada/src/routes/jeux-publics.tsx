import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import {
  ArrowLeft, Bot, Gamepad2, Swords, Lock, ChevronRight,
  Cpu, Trophy, Zap,
} from "lucide-react";

export const Route = createFileRoute("/jeux-publics")({
  component: JeuxPublicsPage,
  head: () => ({
    meta: [
      { title: "Jeux disponibles — Lalao MADA" },
      { name: "description", content: "Découvrez tous les jeux disponibles sur Lalao MADA. Jouez contre un bot ou affrontez d'autres joueurs." },
    ],
  }),
});

// ─── Définition des jeux ──────────────────────────────────────────────────────
const ALL_GAMES = [
  {
    slug: "ludo",
    name: "Ludo",
    emoji: "🎲",
    desc: "Parcours et stratégie pour 2 à 4 joueurs",
    gradient: "from-rose-500 to-pink-600",
    ring: "ring-rose-500/30",
    tag: "Multijoueur",
    botSupported: true,
    cover: <LudoCover />,
  },
  {
    slug: "domino",
    name: "Domino",
    emoji: "🁣",
    desc: "Jeu de tuiles classique malagasy",
    gradient: "from-amber-400 to-orange-500",
    ring: "ring-amber-500/30",
    tag: "Classique",
    botSupported: true,
    cover: <DominoCover />,
  },
  {
    slug: "fanorona",
    name: "Fanorona",
    emoji: "♟",
    desc: "Jeu de stratégie national malgache",
    gradient: "from-emerald-400 to-teal-600",
    ring: "ring-emerald-500/30",
    tag: "Stratégie",
    botSupported: true,
    cover: <FanoronaCover />,
  },
  {
    slug: "chess",
    name: "Échecs",
    emoji: "♜",
    desc: "Le roi des jeux de stratégie",
    gradient: "from-slate-400 to-slate-700",
    ring: "ring-slate-500/30",
    tag: "Tournois",
    botSupported: true,
    cover: <ChessCover />,
  },
  {
    slug: "rami",
    name: "Rami",
    emoji: "🂡",
    desc: "Jeu de cartes à l'ariary",
    gradient: "from-sky-400 to-blue-600",
    ring: "ring-sky-500/30",
    tag: "Cartes",
    botSupported: false,
    cover: <RamiCover />,
  },
] as const;

// ─── Covers CSS ───────────────────────────────────────────────────────────────
function LudoCover() {
  return (
    <div className="w-full h-full grid grid-cols-2 grid-rows-2 rounded-xl overflow-hidden">
      <div className="bg-red-500 flex items-center justify-center">
        <div className="w-6 h-6 rounded-full bg-red-200 border-2 border-red-700 shadow-inner" />
      </div>
      <div className="bg-green-600 flex items-center justify-center">
        <div className="w-6 h-6 rounded-full bg-green-200 border-2 border-green-800 shadow-inner" />
      </div>
      <div className="bg-blue-600 flex items-center justify-center">
        <div className="w-6 h-6 rounded-full bg-blue-200 border-2 border-blue-800 shadow-inner" />
      </div>
      <div className="bg-yellow-400 flex items-center justify-center">
        <div className="w-6 h-6 rounded-full bg-yellow-100 border-2 border-yellow-600 shadow-inner" />
      </div>
    </div>
  );
}
function DominoCover() {
  return (
    <div className="w-full h-full bg-gradient-to-br from-gray-900 to-gray-700 rounded-xl flex items-center justify-center gap-2">
      {[3, 5, 2].map((dots, i) => (
        <div key={i} className={`bg-white rounded shadow-lg flex flex-col items-center justify-around p-1.5 ${i === 1 ? "h-12 w-6" : "h-10 w-5 opacity-80"}`}>
          {Array.from({ length: dots }).map((_, j) => (
            <div key={j} className="w-1.5 h-1.5 rounded-full bg-gray-800" />
          ))}
        </div>
      ))}
    </div>
  );
}
function FanoronaCover() {
  return (
    <div className="w-full h-full bg-gradient-to-br from-amber-900 to-amber-700 rounded-xl flex items-center justify-center p-2">
      <div className="grid grid-cols-5 grid-rows-4 gap-1 w-full h-full">
        {Array.from({ length: 20 }).map((_, i) => (
          <div key={i} className="flex items-center justify-center">
            <div className={`rounded-full border ${i % 3 === 0 ? "w-3 h-3 bg-white border-white/50" : i % 3 === 1 ? "w-3 h-3 bg-black border-black/50" : "w-1.5 h-1.5 bg-amber-500/30 border-amber-400/20"}`} />
          </div>
        ))}
      </div>
    </div>
  );
}
function ChessCover() {
  return (
    <div className="w-full h-full rounded-xl overflow-hidden">
      <div className="grid grid-cols-4 grid-rows-4 w-full h-full">
        {Array.from({ length: 16 }).map((_, i) => (
          <div key={i} className={(Math.floor(i / 4) + i) % 2 === 0 ? "bg-slate-200" : "bg-slate-700"} />
        ))}
      </div>
    </div>
  );
}
function PokerCover() {
  return (
    <div className="w-full h-full bg-gradient-to-br from-green-900 to-green-700 rounded-xl flex items-center justify-center gap-1 p-2">
      {["♠", "♥", "♦", "♣"].map((s, i) => (
        <div key={i} className={`text-lg font-black ${s === "♥" || s === "♦" ? "text-red-400" : "text-white"}`}>{s}</div>
      ))}
    </div>
  );
}
function RamiCover() {
  return (
    <div className="w-full h-full bg-gradient-to-br from-blue-900 to-blue-700 rounded-xl flex items-center justify-center gap-1 p-2">
      {["A", "K", "Q", "J"].map((c, i) => (
        <div key={i} className="bg-white/90 rounded text-xs font-black text-blue-900 px-1 py-0.5 shadow">{c}</div>
      ))}
    </div>
  );
}

// ─── Compteur joueurs en ligne ──────────────────────────────────────────────
function useOnlineCount(slug: string) {
  const [count, setCount] = useState<number | null>(null);
  useEffect(() => {
    supabase
      .from("game_sessions" as any)
      .select("id", { count: "exact", head: true })
      .eq("slug", slug)
      .eq("status", "waiting")
      .then(({ count: c }) => { if (c !== null) setCount(c); });
  }, [slug]);
  return count;
}

function OnlineCount({ slug }: { slug: string }) {
  const count = useOnlineCount(slug);
  return (
    <span className="flex items-center gap-1 text-[11px] font-semibold text-emerald-400">
      <span className="relative flex h-1.5 w-1.5">
        <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400/60" />
        <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-400" />
      </span>
      {count !== null ? `${count} en ligne` : "—"}
    </span>
  );
}

// ─── Page principale ─────────────────────────────────────────────────────────
export default function JeuxPublicsPage() {
  const navigate = useNavigate();
  const { user, loading } = useAuth();

  function handlePlay(slug: string) {
    if (user) {
      navigate({ to: "/jeux/$slug" as any, params: { slug } as any });
    } else {
      navigate({ to: "/login" });
    }
  }

  function handleBotPlay(slug: string) {
    if (user) {
      navigate({ to: "/jeux/$slug" as any, params: { slug } as any });
    } else {
      navigate({ to: "/login" });
    }
  }

  return (
    <div className="min-h-screen bg-background">
      {/* ── En-tête ─────────────────────────────────────────────────────── */}
      <div className="relative overflow-hidden">
        <div className="absolute inset-0 bg-gradient-to-br from-primary/10 via-background to-violet-500/5 pointer-events-none" />
        <div className="absolute -top-20 -right-20 w-64 h-64 rounded-full bg-primary/8 blur-3xl pointer-events-none" />

        <div className="relative max-w-md mx-auto px-5 pt-6 pb-4">
          <div className="flex items-center justify-between mb-5">
            <button
              type="button"
              onClick={() => navigate({ to: "/login" })}
              className="w-9 h-9 rounded-full flex items-center justify-center bg-card/70 border border-border/50 text-muted-foreground hover:text-foreground transition-colors"
            >
              <ArrowLeft className="w-4 h-4" />
            </button>

            <div className="text-center">
              <h1 className="text-xl font-black tracking-tight">Jeux disponibles</h1>
              <p className="text-xs text-muted-foreground mt-0.5">{ALL_GAMES.length} jeux · Lalao MADA</p>
            </div>

            <div className="w-9 h-9" />
          </div>

          {/* Bandeau info */}
          <div className="rounded-2xl bg-primary/10 border border-primary/20 px-4 py-3 flex items-start gap-3 mb-1">
            <Bot className="w-5 h-5 text-primary flex-shrink-0 mt-0.5" />
            <div>
              <p className="text-xs font-bold text-primary leading-snug">Mode bot disponible</p>
              <p className="text-[11px] text-muted-foreground mt-0.5 leading-snug">
                Entraînez-vous contre notre IA avant d'affronter de vrais joueurs.
                {!user && !loading && (
                  <> <button onClick={() => navigate({ to: "/login" })} className="text-primary font-semibold hover:underline">Connectez-vous</button> pour jouer.</>
                )}
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* ── Stats rapides ───────────────────────────────────────────────── */}
      <div className="max-w-md mx-auto px-5 mb-4">
        <div className="grid grid-cols-3 gap-2">
          {[
            { icon: Gamepad2, label: "Jeux", value: ALL_GAMES.length.toString() },
            { icon: Cpu, label: "Bots IA", value: ALL_GAMES.filter(g => g.botSupported).length.toString() },
            { icon: Trophy, label: "Tournois", value: "Actifs" },
          ].map(({ icon: Icon, label, value }) => (
            <div key={label} className="rounded-2xl bg-card border border-border/40 p-3 text-center shadow-sm">
              <Icon className="w-4 h-4 text-primary mx-auto mb-1" />
              <div className="text-sm font-extrabold">{value}</div>
              <div className="text-[10px] text-muted-foreground">{label}</div>
            </div>
          ))}
        </div>
      </div>

      {/* ── Liste des jeux ──────────────────────────────────────────────── */}
      <div className="max-w-md mx-auto px-5 pb-16 space-y-3">
        {ALL_GAMES.map(game => (
          <div
            key={game.slug}
            className="rounded-3xl bg-card border border-border/40 overflow-hidden shadow-sm hover:border-primary/20 transition-all"
          >
            <div className="flex gap-4 p-4">
              {/* Cover */}
              <div className={`w-20 h-20 rounded-2xl flex-shrink-0 ring-2 ${game.ring} shadow-md overflow-hidden`}>
                {game.cover}
              </div>

              {/* Info */}
              <div className="flex-1 min-w-0">
                <div className="flex items-start justify-between gap-2 mb-1">
                  <div className="flex items-center gap-1.5">
                    <span className="text-base">{game.emoji}</span>
                    <h2 className="font-extrabold text-base leading-tight">{game.name}</h2>
                  </div>
                  <span className={`flex-shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full bg-gradient-to-r ${game.gradient} text-white shadow-sm`}>
                    {game.tag}
                  </span>
                </div>

                <p className="text-xs text-muted-foreground leading-snug mb-2">{game.desc}</p>

                <div className="flex items-center gap-3">
                  <OnlineCount slug={game.slug} />
                  {game.botSupported && (
                    <span className="flex items-center gap-0.5 text-[10px] font-semibold text-sky-400">
                      <Cpu className="w-3 h-3" /> Bot dispo
                    </span>
                  )}
                </div>
              </div>
            </div>

            {/* Boutons d'action */}
            <div className="border-t border-border/40 grid grid-cols-2 divide-x divide-border/40">
              {/* Jouer contre un bot */}
              <button
                type="button"
                onClick={() => handleBotPlay(game.slug)}
                disabled={!game.botSupported}
                className={`flex items-center justify-center gap-2 py-3 text-xs font-bold transition-all ${
                  game.botSupported
                    ? "text-sky-400 hover:bg-sky-500/10 active:scale-95"
                    : "text-muted-foreground/40 cursor-not-allowed"
                }`}
              >
                <Cpu className="w-3.5 h-3.5" />
                <span>
                  {game.botSupported ? "Jouer vs Bot" : "Bientôt"}
                </span>
                {!game.botSupported && <Lock className="w-3 h-3" />}
              </button>

              {/* Jouer en ligne */}
              <button
                type="button"
                onClick={() => handlePlay(game.slug)}
                className="flex items-center justify-center gap-2 py-3 text-xs font-bold text-primary hover:bg-primary/10 active:scale-95 transition-all"
              >
                <Swords className="w-3.5 h-3.5" />
                En ligne
                <ChevronRight className="w-3.5 h-3.5" />
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* ── Footer CTA ──────────────────────────────────────────────────── */}
      {!user && !loading && (
        <div className="fixed bottom-0 left-0 right-0 bg-background/95 backdrop-blur border-t border-border/40 p-4 safe-area-bottom">
          <div className="max-w-md mx-auto flex gap-3 items-center">
            <div className="flex-1 min-w-0">
              <p className="text-xs font-bold leading-tight">Prêt à jouer ?</p>
              <p className="text-[11px] text-muted-foreground">Créez un compte gratuit pour commencer</p>
            </div>
            <button
              type="button"
              onClick={() => navigate({ to: "/login" })}
              className="flex-shrink-0 flex items-center gap-2 px-5 py-2.5 rounded-2xl text-sm font-bold text-white shadow-md shadow-primary/20 active:scale-95 transition-all"
              style={{ background: "linear-gradient(135deg, #ef4444 0%, #f97316 50%, #eab308 100%)" }}
            >
              <Zap className="w-4 h-4" />
              Commencer
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
