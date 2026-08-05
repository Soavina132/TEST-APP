import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { ArrowLeft, MessageSquare, Trophy, Gamepad2, Copy } from "lucide-react";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";

export const Route = createFileRoute("/_authenticated/joueur/$id")({
  component: PublicProfile,
  head: () => ({ meta: [{ title: "Profil joueur — Lalao MADA" }] }),
});

function PublicProfile() {
  const { id } = Route.useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [prof, setProf] = useState<any>(null);
  const [stats, setStats] = useState<{ played: number; wins: number }>({ played: 0, wins: 0 });
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    (async () => {
      setLoading(true);
      const { data } = await supabase
        .from("profiles")
        .select("id,pseudo,avatar_url,unique_code,created_at,bio")
        .eq("id", id)
        .maybeSingle();
      setProf(data);
      const { data: s } = await supabase
        .from("player_game_stats" as any)
        .select("games_played,wins")
        .eq("user_id", id);
      if (s?.length) {
        setStats({
          played: s.reduce((a: number, r: any) => a + (r.games_played || 0), 0),
          wins: s.reduce((a: number, r: any) => a + (r.wins || 0), 0),
        });
      }
      setLoading(false);
    })();
  }, [id]);

  const sendMessage = () => navigate({ to: "/chat", search: { dm: id } as any });

  if (loading) return <main className="p-8 text-center text-muted-foreground animate-pulse">Chargement…</main>;
  if (!prof) return <main className="p-8 text-center text-muted-foreground">Joueur introuvable</main>;

  const initials = (prof.pseudo || "?").slice(0, 2).toUpperCase();
  const isSelf = user?.id === prof.id;

  return (
    <main className="max-w-lg mx-auto p-4 space-y-4">
      <button
        onClick={() => navigate({ to: "/chat" })}
        className="flex items-center gap-1.5 text-sm text-muted-foreground hover:text-foreground"
      >
        <ArrowLeft className="w-4 h-4" /> Retour
      </button>

      <div className="rounded-3xl bg-gradient-to-br from-primary/10 via-background to-background border border-border/60 p-5 space-y-4">
        <div className="flex items-center gap-4">
          <div className="w-20 h-20 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-2xl font-extrabold ring-4 ring-background shadow-md">
            {prof.avatar_url
              ? <img src={prof.avatar_url} alt="" className="w-full h-full object-cover" />
              : <span className="text-primary">{initials}</span>}
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-xl font-extrabold truncate">{prof.pseudo || "Joueur"}</div>
            {prof.unique_code && (
              <button
                onClick={() => { copyText(prof.unique_code); toast.success("Code copié"); }}
                className="mt-1 text-xs text-muted-foreground flex items-center gap-1 hover:text-primary"
              >
                #{prof.unique_code} <Copy className="w-3 h-3" />
              </button>
            )}
          </div>
        </div>

        {prof.bio && (
          <p className="text-sm text-muted-foreground italic">"{prof.bio}"</p>
        )}

        <div className="grid grid-cols-2 gap-2">
          <div className="rounded-2xl bg-secondary/60 p-3 text-center">
            <Gamepad2 className="w-4 h-4 mx-auto text-muted-foreground mb-1" />
            <div className="text-lg font-extrabold">{stats.played}</div>
            <div className="text-[10px] text-muted-foreground">Parties</div>
          </div>
          <div className="rounded-2xl bg-secondary/60 p-3 text-center">
            <Trophy className="w-4 h-4 mx-auto text-amber-500 mb-1" />
            <div className="text-lg font-extrabold text-emerald-600">{stats.wins}</div>
            <div className="text-[10px] text-muted-foreground">Victoires</div>
          </div>
        </div>

        {!isSelf && (
          <button
            onClick={sendMessage}
            className="w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold flex items-center justify-center gap-2 shadow-md active:scale-95 transition-transform"
          >
            <MessageSquare className="w-4 h-4" /> Envoyer un message
          </button>
        )}
      </div>
    </main>
  );
}
