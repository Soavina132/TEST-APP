import { createFileRoute, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import ChatRoom from "@/components/chat/ChatRoom";
import { ArrowLeft, Users, X } from "lucide-react";
import ludoCover from "@/assets/games/ludo.asset.json";
import dominoCover from "@/assets/games/domino.asset.json";
import ramiCover from "@/assets/games/rami.asset.json";
import chessCover from "@/assets/games/chess.asset.json";
import fanoronaCover from "@/assets/games/fanorona.asset.json";

export const Route = createFileRoute("/_authenticated/discussion/$slug")({
  component: DiscussionPage,
  head: () => ({ meta: [{ title: "Discussion — Lalao Mada" }] }),
});

// Small header avatar only needs a thumbnail — avoid loading the full
// 1024px cover for a 40x40 circle.
// The asset JSON url is like "/covers/cover_ludo.png" (1-2 MB PNG).
// We map it to the pre-built thumbnail "/covers/ludo-cover-thumb.webp" (~8 KB).
const toThumb = (url: string) => {
  // Pattern: cover_ludo.png -> ludo-cover-thumb.webp
  const m = url.match(/cover_([a-z]+)\.\w+$/);
  if (m) return `/covers/${m[1]}-cover-thumb.webp`;
  // Fallback: ludo-cover.jpg -> ludo-cover-thumb.webp
  const m2 = url.match(/([a-z]+)-cover\.\w+$/);
  if (m2) return `/covers/${m2[1]}-cover-thumb.webp`;
  return url;
};

const META: Record<string, { label: string; cover: string; group: string }> = {
  ludo:     { label: "Ludo",     cover: toThumb(ludoCover.url),     group: "Groupe Ludo" },
  domino:   { label: "Domino",   cover: toThumb(dominoCover.url),   group: "Groupe Domino" },
  fanorona: { label: "Fanorona", cover: toThumb(fanoronaCover.url), group: "Groupe Fanarona" },
  chess:    { label: "Échecs",   cover: toThumb(chessCover.url),    group: "Groupe Échec" },
  rami:     { label: "Rami",     cover: toThumb(ramiCover.url),     group: "Groupe Rami" },
};

type OnlineUser = { id: string; pseudo: string; avatar_url?: string | null };

function DiscussionPage() {
  const { slug } = Route.useParams();
  const { isAdmin } = useAuth();
  const meta = META[slug];
  const [roomId, setRoomId] = useState<string | null>(null);
  const [onlineCount, setOnlineCount] = useState<number>(0);
  const [onlineUsers, setOnlineUsers] = useState<OnlineUser[]>([]);
  const [panelOpen, setPanelOpen] = useState(false);

  useEffect(() => {
    if (!meta) return;
    (async () => {
      const { data: room } = await supabase.from("chat_rooms" as any)
        .select("id").eq("type", "global").eq("name", meta.group).maybeSingle();
      if (room) setRoomId((room as any).id);
    })();
  }, [slug, meta?.group]);

  if (!meta) return <div className="p-6">Jeu inconnu.</div>;

  return (
    <main className="max-w-3xl mx-auto flex flex-col h-[calc(100dvh-56px-80px)] md:h-[calc(100dvh-56px)] relative overflow-hidden">

      {/* ── Slide-over panel: joueurs en ligne ── */}
      {/* Backdrop */}
      {panelOpen && (
        <div
          className="absolute inset-0 z-40 bg-black/40 backdrop-blur-[2px]"
          onClick={() => setPanelOpen(false)}
        />
      )}

      {/* Panel */}
      <div
        className={`absolute top-0 right-0 h-full w-72 z-50 bg-card border-l border-border shadow-2xl flex flex-col transition-transform duration-300 ease-in-out ${
          panelOpen ? "translate-x-0" : "translate-x-full"
        }`}
      >
        {/* Panel header */}
        <div className="flex items-center justify-between px-4 py-4 border-b border-border">
          <div>
            <p className="font-bold text-base">Joueurs en ligne</p>
            <p className="text-xs text-muted-foreground mt-0.5">
              {onlineCount} {onlineCount === 1 ? "joueur actif" : "joueurs actifs"}
            </p>
          </div>
          <button
            onClick={() => setPanelOpen(false)}
            className="p-1.5 rounded-full hover:bg-accent transition-colors"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        {/* Player list */}
        <div className="flex-1 overflow-y-auto py-2">
          {onlineUsers.length === 0 ? (
            <div className="px-4 py-8 text-center text-muted-foreground text-sm">
              Aucun joueur en ligne pour l'instant
            </div>
          ) : (
            <ul className="divide-y divide-border/50">
              {onlineUsers.map(u => (
                <li key={u.id} className="flex items-center gap-3 px-4 py-3 hover:bg-accent/50 transition-colors">
                  {/* Avatar with green dot */}
                  <div className="relative shrink-0">
                    <div className="w-10 h-10 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-sm font-bold ring-2 ring-background">
                      {u.avatar_url
                        ? <img src={u.avatar_url} width={40} height={40} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                        : <span className="text-primary">{(u.pseudo || "?").slice(0, 2).toUpperCase()}</span>}
                    </div>
                    {/* Online dot */}
                    <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-green-500 ring-2 ring-card" />
                  </div>

                  {/* Name + status */}
                  <div className="min-w-0 flex-1">
                    <p className="font-semibold text-sm truncate">{u.pseudo}</p>
                    <p className="text-[11px] text-green-500 font-medium">En ligne</p>
                  </div>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Panel footer */}
        <div className="px-4 py-3 border-t border-border">
          <p className="text-[11px] text-muted-foreground text-center">
            Mis à jour en temps réel
          </p>
        </div>
      </div>

      {/* ── Header — Messenger-style compact bar ── */}
      <div className="flex items-center gap-2.5 px-2 py-2 border-b border-border bg-card shrink-0">
        <Link
          to="/jeux"
          className="p-2 rounded-full hover:bg-accent text-foreground transition-colors shrink-0"
        >
          <ArrowLeft className="w-5 h-5" />
        </Link>

        {/* Circular group avatar with online dot */}
        <div className="relative shrink-0">
          <div className="w-10 h-10 rounded-full overflow-hidden ring-1 ring-border">
            <img
              src={meta.cover}
              alt={`Couverture ${meta.label}`}
              loading="eager"
              decoding="async"
              className="w-full h-full object-cover"
            />
          </div>
          {onlineCount > 0 && (
            <span className="absolute bottom-0 right-0 w-3 h-3 rounded-full bg-green-500 ring-2 ring-card" />
          )}
        </div>

        {/* Name + status */}
        <div className="min-w-0 flex-1">
          <h1 className="font-bold text-[15px] leading-tight truncate">
            {meta.group}
          </h1>
          <p className="text-xs text-muted-foreground truncate">
            {onlineCount > 0 ? `${onlineCount} ${onlineCount === 1 ? "actif" : "actifs"}` : "Communauté " + meta.label}
          </p>
        </div>

        {/* Members button — opens the online players panel */}
        <button
          onClick={() => setPanelOpen(true)}
          className="p-2 rounded-full hover:bg-accent text-muted-foreground hover:text-foreground transition-colors shrink-0"
          title="Joueurs en ligne"
        >
          <Users className="w-5 h-5" />
        </button>
      </div>

      {/* ── Chat area ── */}
      <div className="flex-1 min-h-0">
        {roomId ? (
          <ChatRoom
            roomId={roomId}
            title={meta.group}
            isAdmin={isAdmin}
            height="h-full"
            gameSlug={slug}
            onOnlineCountChange={setOnlineCount}
            onOnlineUsersChange={setOnlineUsers}
          />
        ) : (
          <div className="p-8 text-center text-muted-foreground">Chargement du salon…</div>
        )}
      </div>
    </main>
  );
}
