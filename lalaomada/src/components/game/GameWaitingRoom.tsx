import { serverNow } from "@/lib/server-time";
import { LogOut, Copy, Check, X, Share2, Lock, Timer, Users, Coins } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { setWaitingRoomActive } from "@/lib/game-ui-state";
import { toast } from "sonner";
import { supabase } from "@/integrations/supabase/client";
import { copyText } from "@/lib/clipboard";
import chessCover from "@/assets/games/chess.asset.json";
import dominoCover from "@/assets/games/domino.asset.json";
import fanoronaCover from "@/assets/games/fanorona.asset.json";
import ludoCover from "@/assets/games/ludo.asset.json";
import pokerCover from "@/assets/games/poker.asset.json";
import ramiCover from "@/assets/games/rami.asset.json";

type Participant = {
  id?: string;
  user_id: string;
  display_name?: string | null;
  color?: string | null;
  slot?: number | null;
  ready?: boolean;
  avatar_url?: string;
  team?: number | null;
};

type GameSlug = "chess" | "domino" | "fanorona" | "ludo" | "poker" | "rami";

const COVERS: Record<GameSlug, { url: string; emoji: string; title: string }> = {
  chess:    { url: chessCover.url,    emoji: "♟️", title: "Échecs" },
  domino:   { url: dominoCover.url,   emoji: "🁣",  title: "Domino" },
  fanorona: { url: fanoronaCover.url, emoji: "⚫", title: "Fanorona" },
  ludo:     { url: ludoCover.url,     emoji: "🎲", title: "Ludo" },
  poker:    { url: pokerCover.url,    emoji: "🂡",  title: "Poker" },
  rami:     { url: ramiCover.url,     emoji: "🃏", title: "Rami" },
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
  gameStatus = "open",
  gameId,
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
  gameStatus?: string;
  gameId?: string;
}) {
  const [copied, setCopied] = useState(false);
  const [avatars, setAvatars] = useState<Record<string, { pseudo?: string; avatar_url?: string }>>({});
  const [now, setNow] = useState(() => serverNow());
  const [timeoutMin, setTimeoutMin] = useState(4);
  useEffect(() => { const t = setInterval(() => setNow(serverNow()), 1000); return () => clearInterval(t); }, []);
  // Auto-quit function: calls safe_leave_waiting_room (server-side status check)
  // This does NOTHING if the game has already started — only refunds if still in waiting/open
  const autoQuit = async (reason: string) => {
    if (hasAutoQuitRef.current) return;
    if (!isParticipant || !gameId || !slug) return;
    hasAutoQuitRef.current = true;
    try {
      await supabase.rpc("safe_leave_waiting_room" as any, {
        _game_type: slug, _game_id: gameId,
      } as any);
    } catch {}
  };

  useEffect(() => {
    setWaitingRoomActive(true);
    return () => {
      setWaitingRoomActive(false);
      // When leaving the waiting room (navigating away, NOT quitting), only unready
      // Do NOT auto-quit or refund — only the explicit Quit button or timeout does that
      if (meReadyRef.current && onToggleReadyRef.current) {
        onToggleReadyRef.current(false).catch(() => {});
      }
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  useEffect(() => {
    supabase.from("app_settings").select("game_invite_timeout_minutes").eq("id", 1).maybeSingle()
      .then(({ data }) => { if ((data as any)?.game_invite_timeout_minutes) setTimeoutMin(Number((data as any).game_invite_timeout_minutes)); });
  }, []);
  const expiresAt = createdAt ? new Date(createdAt).getTime() + timeoutMin * 60_000 : null;
  const remainingMs = expiresAt ? Math.max(0, expiresAt - now) : null;
  const expired = remainingMs !== null && remainingMs === 0;

  // ── Auto-quit when timer expires (refund the user) ──
  useEffect(() => {
    if (expired && !hasAutoQuitRef.current && isParticipant) {
      autoQuit("timeout");
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [expired]);
  const fmt = (ms: number) => { const s = Math.ceil(ms / 1000); return `${Math.floor(s/60)}:${String(s%60).padStart(2,"0")}`; };
  const empty = Math.max(0, maxPlayers - parts.length);
  const me = parts.find(p => p.user_id === meUserId);
  const meReady = !!me?.ready;
  // Track ready state in a ref for the unmount cleanup
  const meReadyRef = useRef(meReady);
  meReadyRef.current = meReady;
  const onToggleReadyRef = useRef(onToggleReady);
  onToggleReadyRef.current = onToggleReady;
  // Refs for auto-refund on unmount/expire


  const hasAutoQuitRef = useRef(false);
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

  const Avatar = ({ uid, url, name, size = "w-11 h-11" }: { uid: string; url?: string; name: string; size?: string }) => {
    const initials = (name || "?").slice(0, 2).toUpperCase();
    return (
      <div className={`${size} rounded-full overflow-hidden shrink-0 bg-accent flex items-center justify-center font-bold text-[10px]`}>
        {url ? <img src={url} alt="" className="w-full h-full object-cover" /> : initials}
      </div>
    );
  };

  return (
    <section className="space-y-2">
      {/* ── Compact cover header ── */}
      {cover && (
        <div className="relative rounded-2xl overflow-hidden shadow-lg h-14">
          <img src={cover.url} alt={cover.title} className="w-full h-full object-cover" />
          <div className="absolute inset-0 bg-gradient-to-r from-black/85 via-black/55 to-black/30" />
          <div className="absolute inset-0 flex items-center px-3 text-white">
            <span className="text-xl mr-2">{cover.emoji}</span>
            <div className="min-w-0">
              <div className="text-[8px] uppercase opacity-70 tracking-[0.2em] font-semibold leading-none">Salle d'attente</div>
              <div className="font-bold text-base leading-tight truncate">{cover.title}</div>
            </div>
            <div className="ml-auto flex items-center gap-1.5">
              <div className="flex items-center gap-1 bg-white/20 backdrop-blur-sm px-2 py-0.5 rounded-full text-[10px] font-bold">
                <Users className="w-3 h-3" />{parts.length}/{maxPlayers}
              </div>
              {Number(stake) > 0 && (
                <div className="flex items-center gap-0.5 bg-amber-500/30 backdrop-blur-sm px-2 py-0.5 rounded-full text-[10px] font-bold text-amber-100">
                  <Coins className="w-3 h-3" />{Number(stake).toLocaleString("fr-FR")}
                </div>
              )}
            </div>
          </div>
        </div>
      )}

      {/* ── Timer + Room code compact bar ── */}
      <div className="flex items-center gap-2 rounded-xl bg-card p-2 shadow-sm">
        {remainingMs !== null && (
          <div className={`flex items-center gap-1 rounded-full px-2 py-1 text-xs font-bold ${expired ? "bg-destructive/10 text-destructive" : remainingMs < 60_000 ? "bg-amber-500/15 text-amber-700 dark:text-amber-300" : "bg-primary/10 text-primary"}`}>
            <Timer className="w-3.5 h-3.5" />{expired ? "Expirée" : fmt(remainingMs)}
          </div>
        )}
        {!cover && (
          <div className="text-xs font-bold"><span className="text-primary">{parts.length}/{maxPlayers}</span><span className="text-muted-foreground"> joueurs</span></div>
        )}
        {Number(stake) > 0 && (
          <div className="text-[11px] text-muted-foreground">Cagnotte: <b className="text-foreground">{Number(pot).toLocaleString("fr-FR")}</b> Ar</div>
        )}
        {roomCode && (
          <div className="flex items-center gap-1.5 ml-auto bg-secondary px-2 py-1 rounded-lg">
            <Lock className="w-3 h-3 text-muted-foreground" />
            <span className="font-mono font-bold tracking-[0.2em] text-xs">{roomCode}</span>
            <button onClick={copyCode} className="p-0.5 rounded-full hover:bg-accent" aria-label="Copier">
              {copied ? <Check className="w-3 h-3 text-emerald-500" /> : <Copy className="w-3 h-3" />}
            </button>
            {!full && (
              <button onClick={share} className="p-0.5 rounded-full bg-primary text-primary-foreground" aria-label="Partager">
                <Share2 className="w-3 h-3" />
              </button>
            )}
          </div>
        )}
      </div>

      {/* ── Team selection (ludo groupe only) — compact ── */}
      {matchType === "groupe" && slug === "ludo" && (
        <div className="grid grid-cols-2 gap-2">
          {[1, 2].map((team) => {
            const teamMembers = parts.filter((p: any) => p.team === team);
            const myTeam = parts.find((p: any) => p.user_id === meUserId)?.team === team;
            const isFull = teamMembers.length >= 2;
            return (
              <div key={team} className={`rounded-xl p-2 border-2 ${myTeam ? "border-primary bg-primary/5" : "border-border/60 bg-card"}`}>
                <div className="font-bold text-[11px] text-center mb-1">{team === 1 ? "🔴 G1" : "🔵 G2"}</div>
                <div className="flex items-center gap-1.5">
                  {teamMembers.map((m: any) => {
                    const prof = avatars[m.user_id];
                    const name = prof?.pseudo || m.display_name || "?";
                    return <Avatar key={m.user_id} uid={m.user_id} url={prof?.avatar_url || m.avatar_url} name={name} size="w-7 h-7" />;
                  })}
                  {Array.from({ length: Math.max(0, 2 - teamMembers.length) }).map((_, i) => (
                    <button key={`e${i}`} onClick={() => onJoinTeam?.(team)} disabled={!isParticipant || isFull}
                      className={`w-7 h-7 rounded-full border border-dashed flex items-center justify-center text-xs ${isParticipant && !isFull ? "border-primary/40 text-primary" : "border-border/40 text-muted-foreground/40"}`}>
                      +
                    </button>
                  ))}
                </div>
              </div>
            );
          })}
        </div>
      )}

      {/* ── Players — horizontal avatar row ── */}
      <div className="rounded-2xl bg-card p-3 shadow-sm">
        <div className="flex items-center justify-center gap-3 flex-wrap">
          {parts.map((p) => {
            const prof = avatars[p.user_id];
            const name = prof?.pseudo || p.display_name || "Joueur";
            return (
              <div key={p.id || p.user_id} className="flex flex-col items-center gap-1 w-14">
                <div className="relative">
                  <Avatar uid={p.user_id} url={prof?.avatar_url || p.avatar_url} name={name} />
                  {p.ready ? (
                    <span className="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-emerald-500 flex items-center justify-center border-2 border-card">
                      <Check className="w-2.5 h-2.5 text-white" />
                    </span>
                  ) : (
                    <span className="absolute -bottom-0.5 -right-0.5 w-4 h-4 rounded-full bg-amber-400 border-2 border-card" />
                  )}
                </div>
                <span className="text-[9px] font-semibold text-center truncate max-w-[48px]">{p.user_id === meUserId ? "Vous" : name}</span>
              </div>
            );
          })}
          {Array.from({ length: empty }).map((_, i) => (
            <div key={`e${i}`} className="flex flex-col items-center gap-1 w-14">
              <div className="w-11 h-11 rounded-full border-2 border-dashed border-border/40 flex items-center justify-center text-muted-foreground/40 text-lg">+</div>
              <span className="text-[9px] text-muted-foreground/50">Libre</span>
            </div>
          ))}
        </div>
        {matchType === "groupe" && parts.some((p: any) => p.team) && (
          <div className="flex justify-center gap-3 mt-2">
            {[1, 2].map(team => {
              const count = parts.filter((p: any) => p.team === team).length;
              return count > 0 ? (
                <span key={team} className={`text-[9px] px-2 py-0.5 rounded-full font-bold ${team === 1 ? "bg-red-500/15 text-red-600" : "bg-blue-500/15 text-blue-600"}`}>
                  {team === 1 ? "🔴" : "🔵"} {count}/2
                </span>
              ) : null;
            })}
          </div>
        )}
      </div>

      {/* ── Ready + Quit — single row ── */}
      {isParticipant && (
        <div className="flex gap-2 items-center">
          {onToggleReady && (
            <button
              onClick={() => onToggleReady(!meReady)}
              className={`flex-1 py-2.5 rounded-full text-white font-bold text-xs flex items-center justify-center gap-1.5 active:scale-95 transition-transform ${meReady ? "bg-red-500" : "bg-primary"}`}
            >
              {meReady ? <><X className="w-4 h-4" /> Pas prêt</> : <><Check className="w-4 h-4" /> Je suis prêt !</>}
            </button>
          )}
          <button onClick={onQuit} className="px-3 py-2.5 rounded-full bg-secondary font-semibold text-[11px] flex items-center gap-1 shrink-0">
            <LogOut className="w-3.5 h-3.5" />
            {Number(stake) > 0 ? "Remboursé" : "Quitter"}
          </button>
        </div>
      )}

      {/* ── Status line ── */}
      {isParticipant && (
        <div className="text-center text-[11px] text-muted-foreground">
          {readyCount}/{maxPlayers} prêt{readyCount > 1 ? "s" : ""} · {allReady ? "Démarrage…" : parts.length < maxPlayers ? "En attente de joueurs" : "En attente des autres"}
          {isTournament && <span className="block text-amber-600 dark:text-amber-400 font-semibold mt-0.5">⚠️ Prêt avant l'expiration sinon forfait</span>}
        </div>
      )}
    </section>
  );
}
