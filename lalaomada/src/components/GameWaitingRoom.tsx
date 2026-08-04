import { LogOut, Copy, Check, X, Share2, Lock, Timer, Users, Coins } from "lucide-react";
import { useEffect, useState } from "react";
import { setWaitingRoomActive } from "@/lib/game-ui-state";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { copyText } from "@/lib/clipboard";
import { serverNow } from "@/lib/server-time";
import chessCover from "@/assets/games/chess.asset.json";
import dominoCover from "@/assets/games/domino.asset.json";
import fanoronaCover from "@/assets/games/fanorona.asset.json";
import ludoCover from "@/assets/games/ludo.asset.json";
import pokerCover from "@/assets/games/poker.asset.json";
import ramiCover from "@/assets/games/rami.asset.json";
import petanqueCover from "@/assets/games/petanque.asset.json";

type Participant = {
  id?: string;
  user_id: string;
  display_name?: string | null;
  color?: string | null;
  slot?: number | null;
  ready?: boolean;
  avatar_url?: string;
};

type GameSlug = "chess" | "domino" | "fanorona" | "ludo" | "poker" | "rami" | "petanque";

const COVERS: Record<GameSlug, { url: string; emoji: string; title: string }> = {
  chess:    { url: chessCover.url,    emoji: "♟️", title: "Échecs" },
  domino:   { url: dominoCover.url,   emoji: "🁣",  title: "Domino" },
  fanorona: { url: fanoronaCover.url, emoji: "⚫", title: "Fanorona" },
  ludo:     { url: ludoCover.url,     emoji: "🎲", title: "Ludo" },
  poker:    { url: pokerCover.url,    emoji: "🂡",  title: "Poker" },
  rami:     { url: ramiCover.url,     emoji: "🃏", title: "Rami" },
  petanque: { url: petanqueCover.url, emoji: "🟤", title: "Pétanque" },
};

export default function GameWaitingRoom({
  gameLabel,
  parts,
  maxPlayers,
  stake,
  pot,
  roomCode,
  meUserId,
  isParticipant,
  onQuit,
  onToggleReady,
  shareSlug,
  createdAt,
  slug,
  isTournament = false,
  matchType = "solo",
  onJoinTeam,
}: {
  gameLabel: string;
  parts: Participant[];
  maxPlayers: number;
  stake: number;
  pot: number;
  roomCode?: string | null;
  meUserId?: string;
  isParticipant: boolean;
  onQuit: () => void | Promise<void>;
  onToggleReady?: (ready: boolean) => void | Promise<void>;
  shareSlug?: string;
  createdAt?: string | null;
  slug?: GameSlug;
  isTournament?: boolean;
  matchType?: "solo" | "groupe";
  onJoinTeam?: (team: number) => void | Promise<void>;
}) {
  const [copied, setCopied] = useState(false);
  const [avatars, setAvatars] = useState<Record<string, { pseudo?: string; avatar_url?: string }>>({});
  const [now, setNow] = useState(() => serverNow());
  const [timeoutMin, setTimeoutMin] = useState(6);
  useEffect(() => { const t = setInterval(() => setNow(serverNow()), 1000); return () => clearInterval(t); }, []);
  useEffect(() => { setWaitingRoomActive(true); return () => setWaitingRoomActive(false); }, []);
  useEffect(() => {
    supabase.from("app_settings").select("game_invite_timeout_minutes").eq("id", 1).maybeSingle()
      .then(({ data }) => { if ((data as any)?.game_invite_timeout_minutes) setTimeoutMin(Number((data as any).game_invite_timeout_minutes)); });
  }, []);
  const expiresAt = createdAt ? new Date(createdAt).getTime() + timeoutMin * 60_000 : null;
  const remainingMs = expiresAt ? Math.max(0, expiresAt - now) : null;
  const expired = remainingMs !== null && remainingMs === 0;
  const fmt = (ms: number) => { const s = Math.ceil(ms / 1000); return `${Math.floor(s/60)}:${String(s%60).padStart(2,"0")}`; };
  const empty = Math.max(0, maxPlayers - parts.length);
  const me = parts.find(p => p.user_id === meUserId);
  const meReady = !!me?.ready;
  const readyCount = parts.filter(p => p.ready).length;
  const allReady = parts.length === maxPlayers && readyCount === maxPlayers;
  const full = parts.length >= maxPlayers;

  useEffect(() => {
    const missing = parts.map(p => p.user_id).filter(uid => uid && !avatars[uid]);
    if (!missing.length) return;
    (async () => {
      const { data } = await supabase.from("profiles").select("id,pseudo,avatar_url").in("id", missing);
      const map: Record<string, any> = {};
      (data || []).forEach((p: any) => { map[p.id] = { pseudo: p.pseudo, avatar_url: p.avatar_url }; });
      setAvatars(prev => ({ ...prev, ...map }));
    })();
  }, [parts.map(p => p.user_id).join(",")]);

  const copyCode = async () => {
    if (!roomCode) return;
    const ok = await copyText(roomCode);
    if (ok) { setCopied(true); toast.success("Code copié"); setTimeout(() => setCopied(false), 1500); }
    else toast.error("Impossible de copier");
  };

  const share = async () => {
    if (!roomCode) return;
    const url = `${window.location.origin}/jeux/${shareSlug || ""}?join=${roomCode}`;
    const text = `🎮 Rejoins ma partie !\nJeu : ${gameLabel}\nCode : ${roomCode}\nMise : ${Number(stake).toLocaleString("fr-FR")} Ar\nJoueurs : ${parts.length}/${maxPlayers}\n👉 ${url}`;
    try {
      if (navigator.share) await navigator.share({ title: "Lalao MADA", text, url });
      else { const ok = await copyText(text); toast[ok ? "success" : "error"](ok ? "Invitation copiée" : "Impossible de copier"); }
    } catch {}
  };

  const cover = slug ? COVERS[slug] : null;

  return (
    <section className="space-y-3">
      {cover && (
        <div className="relative rounded-3xl overflow-hidden shadow-2xl">
          <img
            src={cover.url}
            alt={cover.title}
            width={1024}
            height={448}
            loading="lazy"
            decoding="async"
            className="w-full object-cover aspect-[16/7]"
          />
          <div className="absolute inset-0 bg-gradient-to-t from-black/90 via-black/45 to-black/10" />
          <div className="absolute bottom-4 left-5 right-5 text-white">
            <div className="text-[10px] uppercase opacity-70 tracking-[0.2em] font-semibold">
              Salle d'attente
            </div>
            <div className="font-extrabold text-3xl drop-shadow-xl mt-0.5 flex items-center gap-2">
              <span aria-hidden>{cover.emoji}</span>
              <span>{cover.title}</span>
            </div>
            <div className="flex items-center gap-2 mt-2 flex-wrap">
              <div className="flex items-center gap-1.5 bg-white/15 backdrop-blur-sm px-3 py-1 rounded-full text-xs font-semibold border border-white/20">
                <Users className="w-3.5 h-3.5" />
                {parts.length}/{maxPlayers} joueurs
              </div>
              {Number(stake) > 0 && (
                <div className="flex items-center gap-1.5 bg-amber-500/20 backdrop-blur-sm px-3 py-1 rounded-full text-xs font-semibold border border-amber-400/30 text-amber-100">
                  <Coins className="w-3.5 h-3.5" />
                  {Number(stake).toLocaleString("fr-FR")} Ar
                </div>
              )}
              {remainingMs !== null && (
                <div className={`flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold border backdrop-blur-sm ${expired ? "bg-red-500/25 border-red-400/40 text-red-100" : remainingMs < 60_000 ? "bg-amber-500/25 border-amber-400/40 text-amber-100" : "bg-white/15 border-white/20 text-white"}`}>
                  <Timer className="w-3.5 h-3.5" />
                  {expired ? "Expirée" : fmt(remainingMs)}
                </div>
              )}
            </div>
          </div>
        </div>
      )}
      <div className="rounded-2xl bg-card p-2.5 shadow-[var(--shadow-soft)]">
        <div className="flex items-center justify-between gap-2">
          <div className="text-sm font-extrabold min-w-0 truncate">
            <span className="text-primary">{parts.length}/{maxPlayers}</span>
            <span className="font-medium text-muted-foreground"> joueurs · {gameLabel}</span>
          </div>
          {remainingMs !== null && (
            <div className={`shrink-0 flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-bold ${expired ? "bg-destructive/10 text-destructive" : remainingMs < 60_000 ? "bg-amber-500/15 text-amber-700 dark:text-amber-300" : "bg-primary/10 text-primary"}`}>
              <Timer className="w-3 h-3" />
              {expired ? "Expirée" : fmt(remainingMs)}
            </div>
          )}
        </div>
        {Number(stake) > 0 && (
          <div className="mt-1 text-[11px] text-muted-foreground">
            Cagnotte : <b className="text-foreground">{Number(pot).toLocaleString("fr-FR")}</b> Ar
          </div>
        )}
        {roomCode && (
          <div className="mt-1.5 flex items-center gap-2 rounded-xl bg-secondary px-2 py-1.5">
            <Lock className="w-3.5 h-3.5 text-muted-foreground shrink-0" />
            <span className="font-mono font-bold tracking-[0.25em] text-sm">{roomCode}</span>
            <button onClick={copyCode} className="ml-auto p-1.5 rounded-full bg-card" aria-label="Copier">
              {copied ? <Check className="w-3.5 h-3.5 text-emerald-500" /> : <Copy className="w-3.5 h-3.5" />}
            </button>
            {!full && (
              <button onClick={share} className="p-1.5 rounded-full bg-primary text-primary-foreground" aria-label="Partager">
                <Share2 className="w-3.5 h-3.5" />
              </button>
            )}
          </div>
        )}
      </div>

      {matchType === "groupe" && slug === "ludo" && (
        <div className="grid grid-cols-2 gap-3">
          {[1, 2].map((team) => {
            const teamMembers = parts.filter((p: any) => p.team === team);
            const myTeam = parts.find((p: any) => p.user_id === meUserId)?.team === team;
            const isFull = teamMembers.length >= 2;
            return (
              <div key={team} className={`rounded-2xl p-3 border-2 space-y-2 ${myTeam ? "border-primary bg-primary/5" : "border-border/60 bg-card"}`}>
                <div className="font-bold text-sm text-center">
                  {team === 1 ? "🔴 Groupe 1" : "🔵 Groupe 2"}
                </div>
                {teamMembers.map((m: any) => {
                  const prof = avatars[m.user_id];
                  const name = prof?.pseudo || m.display_name || "Joueur";
                  const initials = (name || "?").slice(0, 2).toUpperCase();
                  return (
                    <div key={m.user_id} className="flex items-center gap-2">
                      <div className="h-7 w-7 rounded-full overflow-hidden shrink-0 bg-accent flex items-center justify-center font-bold text-[10px]">
                        {(prof?.avatar_url || m.avatar_url) ? <img src={prof?.avatar_url || m.avatar_url} alt="" width={28} height={28} className="w-full h-full object-cover" /> : initials}
                      </div>
                      <span className="text-xs font-semibold truncate">{name}{m.user_id === meUserId ? " (vous)" : ""}</span>
                    </div>
                  );
                })}
                {Array.from({ length: Math.max(0, 2 - teamMembers.length) }).map((_, i) => (
                  <button
                    key={`e${i}`}
                    onClick={() => onJoinTeam?.(team)}
                    disabled={!isParticipant || isFull}
                    className={`w-full py-2 rounded-lg border border-dashed flex items-center justify-center gap-1 text-xs font-semibold transition-all ${
                      isParticipant && !isFull
                        ? "border-primary/40 text-primary hover:bg-primary/5 active:scale-95"
                        : "border-border/40 text-muted-foreground/50 cursor-not-allowed"
                    }`}
                  >
                    {isFull ? "Complet" : (<><span className="text-base leading-none">+</span> Rejoindre</>)}
                  </button>
                ))}
              </div>
            );
          })}
        </div>
      )}

      <div className="rounded-3xl bg-card p-5 shadow-[var(--shadow-soft)] space-y-3">
        {parts.map((p) => {
          const prof = avatars[p.user_id];
          const name = prof?.pseudo || p.display_name || "Joueur";
          const initials = (name || "?").slice(0, 2).toUpperCase();
          return (
            <div key={p.id || p.user_id} className="flex items-center justify-between border-t border-border/60 pt-3 first:border-0 first:pt-0">
              <div className="flex items-center gap-3 min-w-0">
                <div className="h-9 w-9 rounded-full overflow-hidden shrink-0 bg-accent flex items-center justify-center font-bold text-sm">
                  {(prof?.avatar_url || p.avatar_url) ? <img src={prof?.avatar_url || p.avatar_url} alt="" width={40} height={40} loading="lazy" decoding="async" className="w-full h-full object-cover" /> : initials}
                </div>
                <div className="font-semibold truncate">
                  {name}{p.user_id === meUserId ? " (vous)" : ""}
                </div>
              </div>
              <div className="flex items-center gap-2 shrink-0">
                {matchType === "groupe" && p.team && (
                  <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold ${p.team === 1 ? "bg-red-500/15 text-red-600" : "bg-blue-500/15 text-blue-600"}`}>
                    {p.team === 1 ? "G1" : "G2"}
                  </span>
                )}
                {p.ready ? (
                  <span className="text-xs px-3 py-1.5 rounded-full bg-emerald-100 text-emerald-700 font-bold flex items-center gap-1">
                    <Check className="w-3 h-3" /> Prêt
                  </span>
                ) : (
                  <span className="text-xs px-3 py-1.5 rounded-full bg-amber-100 text-amber-700 font-bold">Pas prêt</span>
                )}
              </div>
            </div>
          );
        })}
        {Array.from({ length: empty }).map((_, i) => (
          <div key={`e${i}`} className="border-t border-border/60 pt-3 text-sm text-muted-foreground italic">
            Place libre…
          </div>
        ))}
      </div>

      {isParticipant && onToggleReady && (
        <div className="rounded-3xl bg-card p-4 shadow-sm space-y-2">
          <button
            onClick={() => onToggleReady(!meReady)}
            className={`relative w-full py-3.5 rounded-full text-white font-bold flex items-center justify-center gap-2 overflow-hidden transition-transform active:scale-95 ${meReady ? "" : "animate-ready-pulse"}`}
            style={{ background: meReady ? "#ef4444" : "var(--gradient-primary)" }}
          >
            {!meReady && (
              <span
                aria-hidden
                className="pointer-events-none absolute inset-0 -translate-x-full animate-ready-shimmer"
                style={{ background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.35), transparent)" }}
              />
            )}
            {meReady ? (<><X className="w-4 h-4" /> Pas prêt</>) : (<><Check className="w-4 h-4" /> Je suis prêt !</>)}
          </button>
          <div className="text-xs text-muted-foreground text-center">
            {readyCount}/{maxPlayers} prêt{readyCount > 1 ? "s" : ""} · {allReady ? "Démarrage…" : (parts.length < maxPlayers ? "En attente de joueurs" : "En attente des autres")}
          </div>
          {isTournament && (
            <div className="text-[11px] text-amber-700 dark:text-amber-300 text-center font-semibold">
              ⚠️ Clique sur « Prêt » avant l'expiration du timer, sinon forfait automatique.
            </div>
          )}
        </div>
      )}

      {isParticipant && (
        <button onClick={onQuit} className="px-5 py-3 rounded-full bg-secondary font-semibold flex items-center gap-2">
          <LogOut className="w-4 h-4" /> {Number(stake) > 0 ? "Quitter (mise remboursée)" : "Quitter"}
        </button>
      )}
    </section>
  );
}
