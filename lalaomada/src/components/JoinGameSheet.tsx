import { useEffect, useState, useCallback } from "react";
import { useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { X, KeyRound, Users, Coins, Plus, RefreshCw } from "lucide-react";
import ludoCover from "@/assets/games/ludo.asset.json";
import dominoCover from "@/assets/games/domino.asset.json";
import fanoronaCover from "@/assets/games/fanorona.asset.json";
import chessCover from "@/assets/games/chess.asset.json";
import ramiCover from "@/assets/games/rami.asset.json";
import pokerCover from "@/assets/games/poker.asset.json";

type Slug = "ludo" | "domino" | "fanorona" | "chess" | "rami" | "poker";

const GAMES = [
  { slug: "ludo"     as Slug, label: "Ludo",     cover: ludoCover.url,     emoji: "🎲" },
  { slug: "domino"   as Slug, label: "Domino",   cover: dominoCover.url,   emoji: "🁣" },
  { slug: "fanorona" as Slug, label: "Fanorona", cover: fanoronaCover.url, emoji: "⚫" },
  { slug: "chess"    as Slug, label: "Échecs",   cover: chessCover.url,    emoji: "♟️" },
  { slug: "rami"     as Slug, label: "Rami",     cover: ramiCover.url,     emoji: "🃏" },
  { slug: "poker"    as Slug, label: "Poker",    cover: pokerCover.url,    emoji: "🂡" },
];
const ALL_DISPLAYED: Slug[]        = ["ludo", "domino", "fanorona", "chess", "rami", "poker"];
const DIRECT_JOIN: Slug[]          = ["ludo", "domino", "fanorona", "chess", "rami", "poker"];
const GAME_TABLE: Record<Slug, string> = {
  ludo: "ludo_games", domino: "domino_games", fanorona: "fanorona_games",
  chess: "chess_games", rami: "rami_games", poker: "poker_games",
};
const ROUTE: Record<Slug, string> = {
  ludo: "/ludo/$id", domino: "/domino/$id", fanorona: "/fanorona/$id",
  chess: "/chess/$id", rami: "/rami/$id", poker: "/poker/$id",
};
const JOIN_CODE_RPC: Record<Slug, string> = {
  ludo: "join_game_by_code", domino: "domino_join_code", fanorona: "fanorona_join_code",
  chess: "chess_join_code",  rami: "rami_join_code",     poker: "poker_join_code",
};
const JOIN_RPC: Partial<Record<Slug, string>> = {
  ludo: "join_game", domino: "domino_join", fanorona: "fanorona_join",
  chess: "chess_join", rami: "rami_join", poker: "poker_join",
};

type OpenGame = {
  id: string; slug: Slug; stake: number; pot: number;
  players_count: number; max_players: number; created_at: string;
  is_private?: boolean;
};

interface Props { open: boolean; onClose: () => void; }

export default function JoinGameSheet({ open, onClose }: Props) {
  const navigate      = useNavigate();
  const { profile, refreshProfile, isAdmin } = useAuth();

  const [openGames,   setOpenGames]   = useState<OpenGame[]>([]);
  const [loading,     setLoading]     = useState(false);
  const [filterSlug,  setFilterSlug]  = useState<string>("all");
  const [filterStake, setFilterStake] = useState<"all" | "free" | "paid">("all");
  const [code,        setCode]        = useState("");
  const [busyCode,    setBusyCode]    = useState(false);
  const [joiningId,   setJoiningId]   = useState<string | null>(null);
  const [disabledArr,  setDisabledArr]  = useState<string[]>([]);

  type GameStatus = "active" | "hidden" | "dev" | "paused";
  const getGameStatus = (slug: string): GameStatus => {
    // Admin bypass: everything is playable
    if (isAdmin) return "active";
    if (disabledArr.includes(slug))             return "hidden";
    if (disabledArr.includes(slug + ":dev"))    return "dev";
    if (disabledArr.includes(slug + ":paused")) return "paused";
    return "active";
  };

  const loadGames = useCallback(async () => {
    setLoading(true);
    const activeDisplayed = isAdmin
      ? [...ALL_DISPLAYED]
      : ALL_DISPLAYED.filter(s => !disabledArr.includes(s) && !disabledArr.includes(s + ":dev") && !disabledArr.includes(s + ":paused"));
    const results = await Promise.all(
      activeDisplayed.map(async (slug) => {
        if (slug === "ludo") {
          const { data } = await supabase.rpc("list_public_open_games" as any);
          return ((data as any[]) || []).map((g: any) => ({ ...g, slug }));
        }
        const { data } = await supabase
          .from(GAME_TABLE[slug] as any)
          .select("id, stake, pot, max_players, players_count, created_at, is_private")
          .eq("status", "open")
          .eq("is_private", false)
          .order("created_at", { ascending: false }).limit(15);
        return ((data as any[]) || []).map((g: any) => ({
          ...g, slug, players_count: g.players_count ?? 0,
        }));
      })
    );
    const flat: OpenGame[] = results
      .flat()
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
    setOpenGames(flat);
    setLoading(false);
  }, []);

  useEffect(() => {
    if (open) {
      loadGames();
      setCode(""); setFilterSlug("all"); setFilterStake("all");
      supabase.from("app_settings").select("games_disabled").eq("id", 1).maybeSingle()
        .then(({ data }) => setDisabledArr(((data as any)?.games_disabled as string[]) || []));
    }
  }, [open, loadGames]);

  // Real-time: refresh game list on any table change while sheet is open
  useEffect(() => {
    if (!open) return;
    const channels = ALL_DISPLAYED.map(slug =>
      supabase.channel(`sheet-open-${slug}`)
        .on("postgres_changes", { event: "*", schema: "public", table: GAME_TABLE[slug] }, loadGames)
        .subscribe()
    );
    return () => { channels.forEach(ch => supabase.removeChannel(ch)); };
  }, [open, loadGames]);

  const joinByCode = async () => {
    const trimmed = code.trim().toUpperCase();
    if (!trimmed) return;
    setBusyCode(true);
    try {
      // 1) Resolve the code → slug + game_id automatically
      const { data: resolved, error: resolveErr } = await supabase
        .rpc("resolve_room_code" as any, { _code: trimmed } as any);
      if (resolveErr) throw resolveErr;
      const row = (resolved as any[])?.[0];
      if (!row) throw new Error("Code introuvable ou partie déjà commencée.");
      const detectedSlug = row.slug as Slug;
      const gameId       = row.game_id as string;

      // 2) Join using the slug-specific RPC
      const fn = JOIN_CODE_RPC[detectedSlug];
      const { error: joinErr } = await supabase.rpc(fn as any, { _code: trimmed } as any);
      if (joinErr) throw joinErr;

      refreshProfile();
      onClose();
      navigate({ to: ROUTE[detectedSlug] as any, params: { id: gameId } as any });
    } catch (e: any) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient") || msg.includes("solde"))
        toast.error("Solde insuffisant", { action: { label: "Déposer", onClick: () => { onClose(); navigate({ to: "/" }); } } });
      else toast.error(e.message || "Code invalide");
    } finally { setBusyCode(false); }
  };

  const joinGame = async (game: OpenGame) => {
    if (game.is_private) { toast.error("Partie privée — rejoins par code."); return; }
    const fn = JOIN_RPC[game.slug];
    if (!fn) { toast.error("Rejoins par code pour ce jeu."); return; }
    const bal = Number(profile?.balance_ar || 0);
    if (game.stake > 0 && bal < game.stake) {
      toast.error("Solde insuffisant", { action: { label: "Déposer", onClick: () => { onClose(); navigate({ to: "/" }); } } });
      return;
    }
    setJoiningId(game.id);
    try {
      const { error } = await supabase.rpc(fn as any, { _game_id: game.id } as any);
      if (error) throw error;
      refreshProfile();
      onClose();
      navigate({ to: ROUTE[game.slug] as any, params: { id: game.id } as any });
    } catch (e: any) {
      toast.error(e.message || "Erreur lors de la connexion");
    } finally { setJoiningId(null); }
  };

  const filteredGames = openGames
    .filter(g => filterSlug === "all" || g.slug === filterSlug)
    .filter(g => filterStake === "all" || (filterStake === "free" ? g.stake === 0 : g.stake > 0));
  const filterOptions = [
    { slug: "all", label: "Tous", count: openGames.length },
    ...ALL_DISPLAYED
      .filter(s => getGameStatus(s) === "active")
      .map(s => ({
        slug: s,
        label: GAMES.find(g => g.slug === s)?.label ?? s,
        count: openGames.filter(g => g.slug === s).length,
      })),
  ];

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-end"
      onClick={onClose}
    >
      <div
        className="bg-card w-full max-h-[90vh] overflow-y-auto rounded-t-3xl shadow-2xl animate-in slide-in-from-bottom duration-250"
        onClick={e => e.stopPropagation()}
      >
        {/* Handle */}
        <div className="flex justify-center pt-3 pb-1">
          <div className="w-10 h-1 rounded-full bg-border" />
        </div>

        <div className="px-5 pb-8 space-y-5">
          {/* Header */}
          <div className="flex items-center justify-between pt-1">
            <div>
              <h2 className="text-lg font-extrabold">🚀 Rejoindre une partie</h2>
              <p className="text-xs text-muted-foreground">Entre un code ou rejoins une partie ouverte.</p>
            </div>
            <button onClick={onClose} className="p-2 rounded-full hover:bg-accent transition-colors">
              <X className="w-5 h-5" />
            </button>
          </div>

          {/* ── Code join ──────────────────────────────────────── */}
          <div className="bg-secondary rounded-2xl p-4 space-y-3">
            <div className="font-semibold flex items-center gap-2 text-sm">
              <KeyRound className="w-4 h-4 text-primary" /> Rejoindre par code
            </div>
            <div className="flex gap-2 items-center">
              <input
                value={code}
                onChange={e => setCode(e.target.value.toUpperCase())}
                onKeyDown={e => e.key === "Enter" && joinByCode()}
                placeholder="ABC123"
                maxLength={6}
                autoCapitalize="characters"
                className="flex-1 min-w-0 px-4 py-3 rounded-xl bg-card border border-border outline-none uppercase tracking-[0.35em] font-mono text-center text-lg focus:ring-2 focus:ring-primary/40"
              />
              <button
                onClick={joinByCode}
                disabled={busyCode || code.trim().length < 6}
                className="flex-shrink-0 px-5 py-3 rounded-xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-50 active:scale-95 transition-transform"
              >
                {busyCode ? "…" : "OK"}
              </button>
            </div>
            <p className="text-[11px] text-muted-foreground">
              Entre le code à 6 caractères — le jeu est détecté automatiquement.
            </p>
          </div>

          {/* ── Open games ──────────────────────────────────────── */}
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2">
              <span className="font-bold text-sm">Parties disponibles</span>
              {openGames.length > 0 && (
                <span className="bg-primary/10 text-primary text-xs font-bold px-2 py-0.5 rounded-full">
                  {openGames.length}
                </span>
              )}
            </div>
            <button onClick={loadGames} disabled={loading} className="p-2 rounded-full hover:bg-accent transition-colors disabled:opacity-50">
              <RefreshCw className={`w-4 h-4 ${loading ? "animate-spin" : ""}`} />
            </button>
          </div>

          {/* Filter pills — par jeu */}
          <div className="flex gap-1.5 overflow-x-auto -mx-1 px-1 pb-1 no-scrollbar">
            {filterOptions.map(f => (
              <button
                key={f.slug}
                onClick={() => setFilterSlug(f.slug)}
                className={`flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-bold transition-colors ${
                  filterSlug === f.slug
                    ? "bg-primary text-primary-foreground"
                    : "bg-secondary hover:bg-accent"
                }`}
              >
                {f.label}{f.count > 0 ? ` (${f.count})` : ""}
              </button>
            ))}
          </div>

          {/* Filter pills — par mise */}
          <div className="flex gap-2">
            {(["all", "free", "paid"] as const).map(v => {
              const labels = { all: "💰 Toutes", free: "🎉 Gratuit", paid: "💵 Avec mise" };
              const count = openGames
                .filter(g => filterSlug === "all" || g.slug === filterSlug)
                .filter(g => v === "all" || (v === "free" ? g.stake === 0 : g.stake > 0)).length;
              return (
                <button
                  key={v}
                  onClick={() => setFilterStake(v)}
                  className={`flex-shrink-0 px-3 py-1.5 rounded-full text-xs font-bold transition-colors ${
                    filterStake === v
                      ? "bg-amber-500 text-white shadow-sm"
                      : "bg-secondary hover:bg-accent text-muted-foreground"
                  }`}
                >
                  {labels[v]}{count > 0 && filterStake !== v ? ` (${count})` : ""}
                </button>
              );
            })}
          </div>

          {/* List */}
          {loading && (
            <div className="text-center py-8 text-muted-foreground text-sm">Chargement…</div>
          )}
          {!loading && filteredGames.length === 0 && (
            <div className="rounded-2xl bg-secondary p-6 text-center space-y-1">
              <div className="text-2xl">🎲</div>
              <div className="font-semibold text-sm">Aucune partie ouverte</div>
              <div className="text-xs text-muted-foreground">
                {filterStake === "free" ? "Aucune partie gratuite disponible." : filterStake === "paid" ? "Aucune partie avec mise disponible." : "Crée une partie depuis l'onglet Jeux."}
              </div>
            </div>
          )}
          <div className="space-y-2">
            {filteredGames.map(game => {
              const def = GAMES.find(g => g.slug === game.slug)!;
              return (
                <div
                  key={game.id}
                  className="flex items-center gap-3 bg-secondary rounded-2xl p-3 hover:bg-accent/50 transition-colors"
                >
                  <div className="w-11 h-11 rounded-xl overflow-hidden flex-shrink-0 shadow-sm">
                    <img src={def.cover} alt={def.label} className="w-full h-full object-cover" loading="lazy" decoding="async" />
                  </div>
                  <div className="flex-1 min-w-0">
                    <div className="font-bold text-sm">
                      {def.emoji} {def.label}
                    </div>
                    <div className="flex items-center gap-2 text-xs text-muted-foreground flex-wrap mt-0.5">
                      <div className="flex items-center gap-1.5">
                        <div className="flex gap-0.5">
                          {Array.from({ length: game.max_players }).map((_,i) => (
                            <div key={i} className={`w-2 h-2 rounded-full ${i < game.players_count ? "bg-primary" : "bg-white/15"}`} />
                          ))}
                        </div>
                        {game.max_players - game.players_count <= 0 ? (
                          <span className="text-[10px] font-bold text-red-400">Complet</span>
                        ) : game.max_players - game.players_count === 1 ? (
                          <span className="text-[10px] font-bold text-amber-400 animate-pulse">1 place restante !</span>
                        ) : (
                          <span className="text-[10px] text-muted-foreground">{game.max_players - game.players_count} places</span>
                        )}
                      </div>
                      <span className="flex items-center gap-0.5">
                        <Coins className="w-3 h-3" />
                        {game.stake > 0 ? `${Number(game.stake).toLocaleString("fr-FR")} Ar` : "Gratuit"}
                      </span>
                      {game.pot > 0 && (
                        <span className="font-semibold text-emerald-600 dark:text-emerald-400">
                          Cagnotte {Number(game.pot).toLocaleString("fr-FR")} Ar
                        </span>
                      )}
                      {game.is_private ? (
                        <span className="text-[10px] font-semibold text-orange-400">🔒 Privée</span>
                      ) : (
                        <span className="text-[10px] font-semibold text-sky-400">🌐 Publique</span>
                      )}
                    </div>
                  </div>
                  {game.is_private || !DIRECT_JOIN.includes(game.slug) ? (
                    <span className="flex-shrink-0 flex items-center gap-1 px-3 py-2 rounded-full bg-secondary border border-white/10 text-muted-foreground font-semibold text-xs">
                      🔒 Code requis
                    </span>
                  ) : (
                    <button
                      onClick={() => joinGame(game)}
                      disabled={joiningId === game.id}
                      className="flex-shrink-0 flex items-center gap-1 px-3 py-2 rounded-full bg-primary text-primary-foreground font-bold text-xs disabled:opacity-60 active:scale-95 transition-transform"
                    >
                      <Plus className="w-3.5 h-3.5" />
                      {joiningId === game.id ? "…" : "Rejoindre"}
                    </button>
                  )}
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </div>
  );
}
