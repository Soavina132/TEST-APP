import { useEffect, useState } from "react";
import { serverNow } from "@/lib/server-time";
import { Link, useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { Copy, Users, Play, Check, X, Timer } from "lucide-react";
import { toast } from "sonner";
import { copyText } from "@/lib/clipboard";

const ROUTE: Record<string, string> = {
  ludo: "/game/$id",
  domino: "/domino/$id",
  chess: "/chess/$id",
  fanorona: "/fanorona/$id",
  rami: "/rami/$id",
};
const TABLE: Record<string, string> = {
  ludo: "ludo_games",
  domino: "domino_games",
  chess: "chess_games",
  fanorona: "fanorona_games",
  rami: "rami_games",
};
const PART_TABLE: Record<string, string | null> = {
  ludo: "ludo_participants",
  domino: "domino_participants",
  chess: null,
  fanorona: "fanorona_participants",
  rami: "rami_participants",
};
const LABEL: Record<string, string> = {
  ludo: "🎲 Ludo",
  domino: "🁫 Domino",
  chess: "♟️ Échecs",
  fanorona: "⚫ Fanorona",
  rami: "🂠 Rami",
};
const DEFAULT_MAX: Record<string, number> = { ludo: 4, domino: 4, chess: 2, fanorona: 2, rami: 4 };

export default function GameShareCard({ slug, gameId, onMissing }: { slug: string; gameId: string; onMissing?: () => void }) {
  const [game, setGame] = useState<any>(null);
  const [parts, setParts] = useState<any[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    let mounted = true;
    const load = async () => {
      const { data: g } = await supabase.from(TABLE[slug] as any).select("*").eq("id", gameId).maybeSingle();
      if (!mounted) return;
      setGame(g);
      if (!g) onMissing?.();
      const pt = PART_TABLE[slug];
      if (pt) {
        const { data: p } = await supabase.from(pt as any).select("user_id, display_name").eq("game_id", gameId);
        if (!mounted) return;
        setParts((p as any[]) || []);
      } else if (slug === "chess" && g) {
        const ids = [(g as any).white_id, (g as any).black_id].filter(Boolean);
        if (ids.length) {
          const { data: profs } = await supabase.from("profiles").select("id, pseudo").in("id", ids);
          if (!mounted) return;
          setParts(((profs as any[]) || []).map((p: any) => ({ user_id: p.id, display_name: p.pseudo })));
        } else setParts([]);
      }
      setLoading(false);
    };
    load();
    const ch = supabase.channel(`gameshare-${slug}-${gameId}`)
      .on("postgres_changes", { event: "*", schema: "public", table: TABLE[slug], filter: `id=eq.${gameId}` }, load)
      .on("postgres_changes", { event: "*", schema: "public", table: PART_TABLE[slug] || "chat_messages", filter: `game_id=eq.${gameId}` }, load)
      .subscribe();
    return () => { mounted = false; supabase.removeChannel(ch); };
  }, [slug, gameId]);

  const [now, setNow] = useState(() => serverNow());
  useEffect(() => { const t = setInterval(() => setNow(serverNow()), 1000); return () => clearInterval(t); }, []);

  if (loading) return null;
  if (!game) return null;

  const max = Number((game as any).max_players) || DEFAULT_MAX[slug] || 2;
  const current = parts.length;
  const status: string = (game as any).status || "open";
  const isPrivate = !!(game as any).is_private;
  const code: string | null = (game as any).room_code || null;
  const stake = Number((game as any).stake) || 0;
  const createdAt = (game as any).created_at as string | undefined;
  const expiresAt = createdAt && (status === "open" || status === "waiting") ? new Date(createdAt).getTime() + 6 * 60_000 : null;
  const remainingMs = expiresAt ? Math.max(0, expiresAt - now) : null;
  const inviteExpired = remainingMs === 0;
  const fmtCountdown = (ms: number) => { const s = Math.ceil(ms / 1000); return `${Math.floor(s/60)}:${String(s%60).padStart(2,"0")}`; };

  const statusBadge =
    inviteExpired
      ? { icon: <X className="w-3 h-3" />, text: "Expirée", cls: "bg-muted text-muted-foreground ring-border" }
      : status === "open" || status === "waiting"
      ? { icon: <Timer className="w-3 h-3" />, text: remainingMs !== null ? fmtCountdown(remainingMs) : "En attente", cls: "bg-amber-500/15 text-amber-700 dark:text-amber-300 ring-amber-500/30" }
      : status === "playing"
        ? { icon: <Play className="w-3 h-3" />, text: "En cours", cls: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 ring-emerald-500/30" }
        : { icon: <Check className="w-3 h-3" />, text: "Terminée", cls: "bg-muted text-muted-foreground ring-border" };

  const canJoin = (status === "open" || status === "waiting") && current < max && !inviteExpired;

  return (
    <div className="not-prose rounded-2xl border border-border bg-card/70 backdrop-blur p-3 my-1 space-y-2 text-foreground min-w-[240px] max-w-[320px]">
      <div className="flex items-center justify-between gap-2">
        <div className="font-bold text-sm">{LABEL[slug] || slug}</div>
        <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ring-1 ${statusBadge.cls}`}>
          {statusBadge.icon}{statusBadge.text}
        </span>
      </div>

      <div className="flex items-center justify-between text-xs">
        <span className="inline-flex items-center gap-1 text-muted-foreground">
          <Users className="w-3.5 h-3.5" />
          <span className="font-semibold text-foreground">{current}/{max}</span> joueurs
        </span>
        {stake > 0 && <span className="text-muted-foreground">Mise : <b className="text-foreground">{stake.toLocaleString("fr-FR")} Ar</b></span>}
      </div>

      {isPrivate && code && (
        <div className="flex items-center justify-between gap-2 px-2.5 py-1.5 rounded-xl bg-secondary">
          <div className="text-[10px] uppercase tracking-wider text-muted-foreground">Code privé</div>
          <div className="flex items-center gap-1.5">
            <code className="font-mono text-sm font-extrabold tracking-widest">{code}</code>
            <button
              type="button"
              onClick={() => { copyText(code).then(ok => ok ? toast.success("Code copié") : toast.error("Impossible de copier")); }}
              className="p-1 rounded-md hover:bg-background"
              aria-label="Copier le code"
            >
              <Copy className="w-3.5 h-3.5" />
            </button>
          </div>
        </div>
      )}

      {parts.length > 0 && (
        <div className="flex flex-wrap gap-1">
          {parts.map((p) => (
            <span key={p.user_id} className="text-[10px] px-1.5 py-0.5 rounded-full bg-secondary truncate max-w-[120px]">
              {p.display_name || "Joueur"}
            </span>
          ))}
          {Array.from({ length: Math.max(0, max - current) }).map((_, i) => (
            <span key={`empty-${i}`} className="text-[10px] px-1.5 py-0.5 rounded-full border border-dashed border-border text-muted-foreground">
              libre
            </span>
          ))}
        </div>
      )}

      {canJoin ? (
        <JoinButton slug={slug} gameId={gameId} code={code} isPrivate={isPrivate} parts={parts} />
      ) : status === "playing" ? (
        <Link
          to={ROUTE[slug] as any}
          params={{ id: gameId } as any}
          className="block text-center w-full px-3 py-2 rounded-full bg-secondary text-secondary-foreground text-xs font-bold hover:bg-accent"
        >
          Regarder la partie
        </Link>
      ) : (
        <div className="text-center text-[11px] text-muted-foreground inline-flex items-center justify-center gap-1 py-1">
          <X className="w-3 h-3" />{inviteExpired ? "Invitation expirée · mise remboursée" : status === "open" ? "Partie pleine" : "Partie terminée"}
        </div>
      )}
    </div>
  );
}

function JoinButton({ slug, gameId, code, isPrivate, parts }: { slug: string; gameId: string; code: string | null; isPrivate: boolean; parts: any[] }) {
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const go = () => navigate({ to: ROUTE[slug] as any, params: { id: gameId } as any });

  const handleClick = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      const meId = user?.id;
      const alreadyIn = !!(meId && parts.some((p) => p.user_id === meId));
      if (alreadyIn) { go(); return; }

      // Private games join by code; public games join directly by game id
      if (isPrivate && code) {
        const fn = slug === "ludo" ? "join_game_by_code"
          : slug === "domino" ? "domino_join_code"
          : slug === "fanorona" ? "fanorona_join_code"
          : slug === "chess" ? "chess_join_code"
          : slug === "rami" ? "rami_join_code" : null;
        if (fn) {
          const { error } = await supabase.rpc(fn as any, { _code: code } as any);
          if (error) throw error;
        }
      } else {
        const fn = slug === "ludo" ? "join_game"
          : slug === "domino" ? "domino_join"
          : slug === "fanorona" ? "fanorona_join" : null;
        if (fn) {
          const { error } = await supabase.rpc(fn as any, { _game_id: gameId } as any);
          if (error) throw error;
        }
      }
      go();
    } catch (e: any) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient") || msg.includes("solde")) {
        toast.error("Solde insuffisant pour rejoindre cette partie.");
      } else {
        toast.error(e.message || "Impossible de rejoindre");
      }
    } finally { setBusy(false); }
  };

  return (
    <button
      type="button"
      onClick={handleClick}
      disabled={busy}
      className="block text-center w-full px-3 py-2 rounded-full bg-primary text-primary-foreground text-xs font-bold hover:opacity-90 disabled:opacity-60"
    >
      {busy ? "…" : isPrivate ? "Rejoindre avec le code" : "Rejoindre la partie"}
    </button>
  );
}
