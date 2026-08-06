import { GAME_TABLE, type GameSlug } from "@/lib/game-constants";
import { createFileRoute, useNavigate } from "@tanstack/react-router";
import React, { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { useRealtimePlayerCount } from "@/hooks/use-realtime-player-count";
import { toast } from "sonner";
import { Users, RefreshCw, Plus, KeyRound, Play, Coins } from "lucide-react";
import PhoneVerifyPopup from "@/components/PhoneVerifyPopup";
import { DepotModal, useAppSettings } from "@/components/WalletButton";

import ludoImg from "@/assets/covers/ludo-cover.jpg";
import dominoImg from "@/assets/covers/domino-cover.jpg";
import fanoronaImg from "@/assets/covers/fanorona-cover.jpg";
import chessImg from "@/assets/covers/chess-cover.jpg";
import ramiImg from "@/assets/covers/rami-cover.jpg";
import pokerImg from "@/assets/covers/poker-cover.jpg";

export const Route = createFileRoute("/_authenticated/jeux/")({
  component: JeuxPage,
  head: () => ({
    meta: [
      { title: "Les jeux — Lalao MADA" },
      { name: "description", content: "Rejoignez ou créez une partie de vos jeux favoris." }],
    links: [
      { rel: "preload", as: "image", href: ludoImg, fetchpriority: "high" },
      { rel: "preload", as: "image", href: dominoImg, fetchpriority: "high" },
      { rel: "preload", as: "image", href: fanoronaImg },
      { rel: "preload", as: "image", href: chessImg },
      { rel: "preload", as: "image", href: ramiImg },
      { rel: "preload", as: "image", href: pokerImg }]})});


type Slug = GameSlug;

// ─────────────────────────────────────────────────────────────────────────────
// Covers — vraies images photoréalistes stylées
// ─────────────────────────────────────────────────────────────────────────────
const COVER_IMAGES: Record<Slug, string> = {
  ludo: ludoImg,
  domino: dominoImg,
  fanorona: fanoronaImg,
  chess: chessImg,
  rami: ramiImg,
  poker: pokerImg};

function GameCover({ slug, label }: { slug: Slug; label: string }) {
  return (
    <img
      src={COVER_IMAGES[slug]}
      alt={label}
      loading="eager"
      decoding="async"
      fetchPriority="high"
      width={512}
      height={512}
      className="w-full h-full object-cover"
      draggable={false}
    />
  );
}


const COVER_COMPONENTS: Record<Slug, () => React.ReactElement> = {
  ludo:     () => <GameCover slug="ludo" label="Ludo" />,
  domino:   () => <GameCover slug="domino" label="Domino" />,
  fanorona: () => <GameCover slug="fanorona" label="Fanorona" />,
  chess:    () => <GameCover slug="chess" label="Échecs" />,
  rami:     () => <GameCover slug="rami" label="Rami" />,
  poker:    () => <GameCover slug="poker" label="Poker" />};

// ─────────────────────────────────────────────────────────────────────────────
// Définition des jeux
// ─────────────────────────────────────────────────────────────────────────────
type GameDef = { slug: Slug; label: string; desc: string; emoji: string };
const GAMES: GameDef[] = [
  { slug: "ludo",     label: "Ludo",     desc: "2-4 joueurs", emoji: "🎲" },
  { slug: "domino",   label: "Domino",   desc: "2-4 joueurs", emoji: "🁣" },
  { slug: "fanorona", label: "Fanorona", desc: "2 joueurs",   emoji: "⚫" },
  { slug: "chess",    label: "Échecs",   desc: "2 joueurs",   emoji: "♟️" },
  { slug: "rami",     label: "Rami",     desc: "2-4 joueurs", emoji: "🃏" },
  { slug: "poker",    label: "Poker",    desc: "2-9 joueurs", emoji: "🂡" }];

const ALL_DISPLAYED_SLUGS: Slug[] = ["ludo", "domino", "fanorona", "chess", "rami", "poker"];
const DIRECT_JOIN_SLUGS: Slug[] = ["ludo", "domino", "fanorona", "chess", "rami", "poker"];

const HOST_COL: Record<Slug, string> = {
  ludo: "host_id", domino: "host_id", fanorona: "host_id",
  chess: "host_id", rami: "created_by", poker: "created_by"};
const ROUTE: Record<Slug, string> = {
  ludo: "/jeux/ludo/$id", domino: "/jeux/domino/$id", fanorona: "/jeux/fanorona/$id",
  chess: "/jeux/chess/$id", rami: "/jeux/rami/$id", poker: "/jeux/poker/$id"};
const JOIN_CODE_RPC: Record<Slug, string> = {
  ludo: "join_game_by_code", domino: "domino_join_code", fanorona: "fanorona_join_code",
  chess: "chess_join_code", rami: "rami_join_code", poker: "poker_join_code"};
const JOIN_RPC: Record<string, string> = {
  ludo: "join_game", domino: "domino_join", fanorona: "fanorona_join",
  chess: "chess_join", rami: "rami_join", poker: "poker_join"};

type OpenGame = {
  id: string; slug: Slug; stake: number; pot: number;
  players_count: number; max_players: number; created_at: string;
  is_private?: boolean;
  host_id?: string | null;
  host_name?: string;
  target_score?: number | null;
  draw_mode?: string | null;
};


// ─────────────────────────────────────────────────────────────────────────────
// Composant : compteur de joueurs en temps réel par carte de partie
// ─────────────────────────────────────────────────────────────────────────────
function LivePlayerCount({ game }: { game: OpenGame }) {
  const { liveCount, flash } = useRealtimePlayerCount(
    game.id,
    GAME_TABLE[game.slug],
    game.players_count,
  );
  const remaining = game.max_players - liveCount;

  return (
    <div className="flex items-center gap-1.5">
      {/* Dots — filled = occupied slot */}
      <div className="flex gap-0.5">
        {Array.from({ length: game.max_players }).map((_, i) => (
          <div
            key={i}
            className={`w-2 h-2 rounded-full transition-all duration-300 ${
              i < liveCount
                ? `bg-primary ${flash ? "scale-125" : ""}`
                : "bg-white/15"
            }`}
          />
        ))}
      </div>
      {/* Label */}
      {remaining <= 0 ? (
        <span className="text-[10px] font-bold text-red-400">Complet</span>
      ) : remaining === 1 ? (
        <span className={`text-[10px] font-bold text-amber-400 animate-pulse transition-transform ${flash ? "scale-110" : ""}`}>
          1 place restante !
        </span>
      ) : (
        <span
          className={`text-[10px] transition-all duration-300 ${
            flash ? "text-primary font-bold" : "text-muted-foreground"
          }`}
        >
          {remaining} places
        </span>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Page principale
// ─────────────────────────────────────────────────────────────────────────────
function JeuxPage() {
  const navigate = useNavigate();
  const { profile, refreshProfile, isAdmin } = useAuth();
  const [showPhoneVerify, setShowPhoneVerify] = useState(false);
  const [showDepositPopup, setShowDepositPopup] = useState(false);
  const walletSettings = useAppSettings();

  const [onlineCounts, setOnlineCounts]   = useState<Record<string, number>>({});
  const [disabled, setDisabled]           = useState<string[]>([]);

  // ── Game status from encoded disabled array ──────────────────────────
  type GameStatus = "active" | "hidden" | "dev" | "paused";
  const getGameStatus = (slug: string): GameStatus => {
    // Admin bypass: everything is playable
    if (isAdmin) return "active";
    if (disabled.includes(slug))           return "hidden";
    if (disabled.includes(slug + ":dev"))  return "dev";
    if (disabled.includes(slug + ":paused")) return "paused";
    return "active";
  };
  const [openGames, setOpenGames]         = useState<OpenGame[]>([]);
  const [loadingGames, setLoadingGames]   = useState(false);
  const [filterSlug, setFilterSlug]       = useState<string>("all");
  const [filterStake, setFilterStake]     = useState<"all" | "free" | "paid">("all");
  const [code, setCode]                   = useState("");
  const [codeSlug, setCodeSlug]           = useState<Slug>("ludo");
  const [busyCode, setBusyCode]           = useState(false);
  const [joiningId, setJoiningId]         = useState<string | null>(null);

  // ── Disabled games ────────────────────────────────────────────────────
  useEffect(() => {
    const load = async () => {
      const { data } = await supabase.from("app_settings").select("games_disabled" as any).eq("id", 1).maybeSingle();
      setDisabled(((data as any)?.games_disabled as string[]) || []);
    };
    load();
    const ch = supabase.channel("jeux-settings-v2")
      .on("postgres_changes", { event: "*", schema: "public", table: "app_settings" }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);

  // ── Online player counts ──────────────────────────────────────────────
  useEffect(() => {
    const active = GAMES.filter(g => getGameStatus(g.slug) === "active");
    if (!active.length) return;
    const load = async () => {
      const entries = await Promise.all(active.map(async g => {
        const { data } = await supabase.rpc("game_online_count" as any, { _slug: g.slug } as any);
        return [g.slug, (data as number) || 0] as const;
      }));
      setOnlineCounts(Object.fromEntries(entries));
    };
    load();
    const t = setInterval(load, 8000);
    return () => clearInterval(t);
  }, [disabled.join(",")]);

  // ── Open public games ─────────────────────────────────────────────────
  const loadOpenGames = useCallback(async (opts: { silent?: boolean } = {}) => {
    if (!opts.silent) setLoadingGames(true);
    const active = ALL_DISPLAYED_SLUGS.filter(s => getGameStatus(s) === "active");
    const PARTS_TABLE: Record<Slug, string | null> = {
      ludo: "ludo_participants", domino: "domino_participants",
      fanorona: "fanorona_participants", rami: "rami_participants",
      chess: null, poker: "poker_players"};
    const FIXED_MAX: Partial<Record<Slug, number>> = { chess: 2, fanorona: 2 };
    const results = await Promise.all(
      active.map(async (slug) => {
        const extraCols: string[] = [HOST_COL[slug]];
        if (slug === "domino") extraCols.push("state", "target_score");
        const hasMax = !FIXED_MAX[slug];
        const cols = ["id", "stake", "pot", "created_at", "is_private", hasMax ? "max_players" : null, ...extraCols]
          .filter(Boolean).join(", ");
        const { data } = await supabase
          .from(GAME_TABLE[slug] as any)
          .select(cols)
          .eq("status", "open")
          .eq("is_private", false)
          .order("created_at", { ascending: false })
          .limit(20);
        const rows = (data as any[]) || [];
        const partsTable = PARTS_TABLE[slug];
        const counts = await Promise.all(rows.map(async (g: any) => {
          if (slug === "chess") {
            const { data: c } = await supabase.from("chess_games" as any)
              .select("white_id, black_id").eq("id", g.id).maybeSingle();
            return ((c as any)?.white_id ? 1 : 0) + ((c as any)?.black_id ? 1 : 0);
          }
          if (!partsTable) return 0;
          const { count } = await supabase.from(partsTable as any)
            .select("*", { count: "exact", head: true }).eq("game_id", g.id);
          return count || 0;
        }));
        return rows.map((g: any, i: number) => ({
          id: g.id, stake: g.stake, pot: g.pot, created_at: g.created_at,
          is_private: g.is_private, slug,
          max_players: FIXED_MAX[slug] ?? g.max_players ?? 2,
          players_count: counts[i],
          host_id: g[HOST_COL[slug]] || null,
          target_score: slug === "domino" ? (g.target_score ?? null) : null,
          draw_mode: slug === "domino" ? (g.state?.draw_mode ?? "with") : null}));
      })
    );
    const flat: OpenGame[] = results
      .flat()
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());

    // Batch-fetch host pseudos
    const hostIds = Array.from(new Set(flat.map(g => g.host_id).filter(Boolean))) as string[];
    let nameMap: Record<string, string> = {};
    if (hostIds.length) {
      const { data: profs } = await supabase
        .from("profiles" as any)
        .select("id, pseudo")
        .in("id", hostIds);
      nameMap = Object.fromEntries(((profs as any[]) || []).map(p => [p.id, p.pseudo || "Joueur"]));
    }
    for (const g of flat) {
      if (g.host_id) g.host_name = nameMap[g.host_id] || "Joueur";
    }

    setOpenGames(flat);
    setLoadingGames(false);
  }, [disabled.join(",")]);


  useEffect(() => { loadOpenGames(); }, [loadOpenGames]);

  // Real-time refresh (silent — don't wipe the list)
  useEffect(() => {
    const refresh = () => loadOpenGames({ silent: true });
    const channels = ALL_DISPLAYED_SLUGS.map(slug =>
      supabase.channel(`open-games-${slug}`)
        .on("postgres_changes", { event: "*", schema: "public", table: GAME_TABLE[slug] }, refresh)
        .subscribe()
    );
    return () => { channels.forEach(c => supabase.removeChannel(c)); };
  }, [loadOpenGames]);


  // ── Actions ───────────────────────────────────────────────────────────
  const joinByCode = async () => {
    const trimmed = code.trim().toUpperCase();
    if (!trimmed) return;
    setBusyCode(true);
    try {
      const { data: resolved, error: resolveErr } = await supabase
        .rpc("resolve_room_code" as any, { _code: trimmed } as any);
      if (resolveErr) throw resolveErr;
      const row = (resolved as any[])?.[0];
      if (!row) throw new Error("Code introuvable ou partie déjà commencée.");
      const detectedSlug = row.slug as Slug;
      const gameId       = row.game_id as string;
      const fn = JOIN_CODE_RPC[detectedSlug];
      const { error: joinErr } = await supabase.rpc(fn as any, { _code: trimmed } as any);
      if (joinErr) throw joinErr;
      refreshProfile();
      navigate({ to: ROUTE[detectedSlug] as any, params: { id: gameId } as any });
    } catch (e: any) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient") || msg.includes("solde")) {
        toast.error("Solde insuffisant", { action: { label: "Déposer", onClick: () => setShowDepositPopup(true) } });
      } else {
        toast.error(e.message || "Code invalide");
      }
    } finally { setBusyCode(false); }
  };


  const joinGame = async (game: OpenGame) => {
    if (game.is_private) { toast.error("Cette partie est privée — rejoins par code."); return; }
    const fn = JOIN_RPC[game.slug];
    if (!fn) { toast.error("Rejoins par code pour ce jeu."); return; }
    const bal = Number(profile?.balance_ar || 0);
    if (game.stake > 0 && bal < game.stake) {
      toast.error("Solde insuffisant", { action: { label: "Déposer", onClick: () => setShowDepositPopup(true) } });
      return;
    }
    setJoiningId(game.id);
    try {
      const { error } = await supabase.rpc(fn as any, { _game_id: game.id } as any);
      if (error) throw error;
      refreshProfile();
      navigate({ to: ROUTE[game.slug] as any, params: { id: game.id } as any });
    } catch (e: any) {
      toast.error(e.message || "Erreur lors de la connexion");
    } finally { setJoiningId(null); }
  };

  // ── Derived ───────────────────────────────────────────────────────────
  const visibleGames  = GAMES.filter(g => getGameStatus(g.slug) !== "hidden");
  const filteredGames = openGames
    .filter(g => filterSlug === "all" || g.slug === filterSlug)
    .filter(g => filterStake === "all" || (filterStake === "free" ? g.stake === 0 : g.stake > 0));
  const filterOptions = [
    { slug: "all", label: "Tous", count: openGames.length },
    ...ALL_DISPLAYED_SLUGS
      .filter(s => getGameStatus(s) === "active")
      .map(s => ({
        slug: s,
        label: GAMES.find(g => g.slug === s)?.label ?? s,
        count: openGames.filter(g => g.slug === s).length}))];

  return (
    <main className="max-w-3xl mx-auto px-3 pt-2 pb-20 md:pb-4 flex flex-col gap-3 md:h-[calc(100vh-3.5rem)] md:overflow-hidden">

      {/* SECTION 1 — Créer une partie */}
      <section className="space-y-2 flex-shrink-0">
        <div className="flex items-center">
          <h1 className="text-base font-extrabold leading-tight bg-gradient-to-r from-primary via-orange-500 to-primary bg-[length:200%_100%] bg-clip-text text-transparent animate-[shimmer_3s_linear_infinite]">
            Créer une partie
          </h1>
        </div>


        <div className="grid grid-cols-6 gap-1.5">
          {visibleGames.map(g => {
            const CoverArt = COVER_COMPONENTS[g.slug];
            const status = getGameStatus(g.slug);
            const badge =
              status === "dev"
                ? { text: "En dev", cls: "bg-amber-500/90 text-white" }
                : status === "paused"
                ? { text: "En pause", cls: "bg-sky-500/90 text-white" }
                : null;
            return (
              <div key={g.slug} className="flex flex-col items-center gap-0.5 min-w-0">
                <div className="h-3 flex items-center justify-center w-full">
                  {badge && (
                    <span className={`text-[8px] font-bold leading-none px-1.5 py-0.5 rounded-full whitespace-nowrap ${badge.cls}`}>
                      {badge.text}
                    </span>
                  )}
                </div>
                <button
                  onClick={() => status === "active" && navigate({ to: "/jeux/$slug", params: { slug: g.slug } })}
                  className={`relative w-full aspect-square rounded-[22%] overflow-hidden group transition-all shadow border border-white/8 ${status === "active" ? "active:scale-[0.93] cursor-pointer" : "cursor-not-allowed opacity-70"}`}
                >
                  <div className="absolute inset-0"><CoverArt /></div>
                  <div className="absolute inset-0 bg-gradient-to-t from-black/85 via-black/20 to-transparent" />
                  {status === "active" && (
                    <div className="absolute top-[6%] right-[6%] flex items-center gap-0.5 bg-black/60 backdrop-blur-sm rounded-full px-1.5 py-0.5 border border-white/10">
                      <span className="w-1 h-1 rounded-full bg-emerald-400 animate-pulse" />
                      <span className="text-white text-[8px] font-bold tabular-nums leading-none">{onlineCounts[g.slug] ?? 0}</span>
                    </div>
                  )}
                </button>
              </div>
            );
          })}
        </div>
      </section>

      {/* SECTION 2 — Rejoindre */}
      <section className="flex flex-col gap-2 flex-1 min-h-0">
        <div className="bg-card rounded-2xl px-3 py-2 shadow-sm border border-white/8 flex items-center gap-2 flex-shrink-0">
          <div className="w-7 h-7 rounded-lg bg-primary/15 flex items-center justify-center flex-shrink-0">
            <KeyRound className="w-3.5 h-3.5 text-primary" />
          </div>
          <input
            value={code}
            onChange={e => setCode(e.target.value.toUpperCase())}
            onKeyDown={e => e.key === "Enter" && joinByCode()}
            placeholder="Code ABC123"
            maxLength={6}
            autoCapitalize="characters"
            className="flex-1 min-w-0 px-2 py-1.5 rounded-lg bg-secondary border border-border outline-none uppercase tracking-[0.25em] font-mono text-center text-sm focus:ring-2 focus:ring-primary/40 transition"
          />
          <button
            onClick={joinByCode}
            disabled={busyCode || code.trim().length < 4}
            className="flex-shrink-0 px-3 py-1.5 rounded-lg bg-primary text-primary-foreground font-bold text-xs disabled:opacity-50 active:scale-95 transition-transform"
          >
            {busyCode ? "…" : "OK"}
          </button>
        </div>

        <div className="flex items-center justify-between gap-2 flex-shrink-0">
          <div className="flex items-center gap-2">
            <span className="w-1.5 h-1.5 rounded-full bg-primary animate-pulse" />
            <span className="font-extrabold text-[15px] tracking-tight bg-gradient-to-r from-primary to-orange-500 bg-clip-text text-transparent">Parties ouvertes</span>
            {openGames.length > 0 && (
              <span className="bg-primary text-primary-foreground text-[10px] font-bold px-2 py-0.5 rounded-full shadow-sm">
                {openGames.length}
              </span>
            )}
          </div>
          <button
            onClick={() => loadOpenGames()}
            disabled={loadingGames}
            title="Rafraîchir"
            className="p-1.5 rounded-full hover:bg-accent transition-colors disabled:opacity-50"
          >
            <RefreshCw className={`w-3.5 h-3.5 ${loadingGames ? "animate-spin" : ""}`} />
          </button>
        </div>

        <div className="flex gap-1 overflow-x-auto -mx-1 px-1 no-scrollbar flex-shrink-0">
          {filterOptions.map(f => (
            <button
              key={f.slug}
              onClick={() => setFilterSlug(f.slug)}
              className={`flex-shrink-0 px-2.5 py-1 rounded-full text-[11px] font-bold transition-colors ${
                filterSlug === f.slug
                  ? "bg-primary text-primary-foreground shadow-sm"
                  : "bg-secondary hover:bg-accent"
              }`}
            >
              {f.label}{f.count > 0 ? ` ${f.count}` : ""}
            </button>
          ))}
          <span className="w-px bg-border mx-1 flex-shrink-0" />
          {(["all", "free", "paid"] as const).map(v => {
            const labels = { all: "💰", free: "🎉", paid: "💵" };
            return (
              <button
                key={v}
                onClick={() => setFilterStake(v)}
                className={`flex-shrink-0 px-2.5 py-1 rounded-full text-[11px] font-bold transition-colors ${
                  filterStake === v
                    ? "bg-amber-500 text-white shadow-sm"
                    : "bg-secondary hover:bg-accent text-muted-foreground"
                }`}
              >
                {labels[v]}
              </button>
            );
          })}
        </div>

        <div className="flex-1 min-h-0 overflow-y-auto space-y-2 pr-0.5">
          {loadingGames && filteredGames.length === 0 && (
            <div className="text-center py-6 text-muted-foreground text-xs">Chargement…</div>
          )}

          {!loadingGames && filteredGames.length === 0 && (
            <div className="rounded-2xl bg-card border border-white/8 p-4 text-center space-y-1 shadow-sm">
              <div className="text-2xl">🎲</div>
              <div className="font-bold text-sm">Aucune partie ouverte</div>
              <div className="text-[11px] text-muted-foreground">Crée une partie ci-dessus.</div>
            </div>
          )}

          {filteredGames.map(game => {
            const def = GAMES.find(g => g.slug === game.slug)!;
            const CoverMini = COVER_COMPONENTS[game.slug];
            const stakeStr = game.stake > 0 ? `${Number(game.stake).toLocaleString("fr-FR")} Ar` : "Gratuit";
            const isFull = game.players_count >= game.max_players;
            const isBusy = joiningId === game.id;
            // Domino-specific chips
            const dominoChips: string[] = [];
            if (game.slug === "domino") {
              dominoChips.push(game.draw_mode === "without" ? "sans pioche" : "avec pioche");
              if (game.target_score && game.target_score > 0) dominoChips.push(`${game.target_score} pts`);
              else dominoChips.push("1 manche");
            }
            return (
              <div key={game.id}
                className="relative bg-gradient-to-br from-card to-card/60 rounded-2xl border border-white/10 p-2.5 flex items-center gap-2.5 hover:border-primary/40 hover:shadow-lg hover:shadow-primary/10 transition-all shadow-sm overflow-hidden">
                {/* Stake ribbon */}
                {game.stake > 0 && (
                  <div className="absolute top-0 right-0 bg-amber-500/95 text-white text-[9px] font-black px-1.5 py-0.5 rounded-bl-lg shadow">
                    {Number(game.stake).toLocaleString("fr-FR")} Ar
                  </div>
                )}
                {game.stake === 0 && (
                  <div className="absolute top-0 right-0 bg-emerald-500/95 text-white text-[9px] font-black px-1.5 py-0.5 rounded-bl-lg shadow">
                    GRATUIT
                  </div>
                )}

                {/* Cover */}
                <div className="w-14 h-14 rounded-xl overflow-hidden flex-shrink-0 shadow-md ring-1 ring-white/15 relative">
                  <CoverMini />
                  <div className="absolute inset-0 bg-gradient-to-t from-black/40 to-transparent" />
                  <span className="absolute bottom-0.5 left-0.5 text-[11px] leading-none">{def.emoji}</span>
                </div>

                {/* Info */}
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-1.5">
                    <span className="font-black text-sm truncate">{def.label}</span>
                    {game.is_private && <span className="text-[10px]">🔒</span>}
                    <span className={`ml-auto mr-14 text-[10px] font-bold px-1.5 py-0.5 rounded-md ${
                      isFull ? "bg-red-500/20 text-red-400"
                        : game.max_players - game.players_count === 1
                          ? "bg-amber-500/20 text-amber-400"
                          : "bg-primary/15 text-primary"
                    }`}>
                      <Users className="inline w-2.5 h-2.5 -mt-0.5 mr-0.5" />
                      {game.players_count}/{game.max_players}
                    </span>
                  </div>

                  {game.host_name && (
                    <div className="text-[10px] text-muted-foreground truncate mt-0.5">
                      par <span className="font-semibold text-foreground/80">{game.host_name}</span>
                    </div>
                  )}

                  {dominoChips.length > 0 && (
                    <div className="flex flex-wrap gap-1 mt-1">
                      {dominoChips.map((c, i) => (
                        <span key={i} className="text-[9px] font-semibold px-1.5 py-0.5 rounded bg-white/5 border border-white/10 text-muted-foreground">
                          {c}
                        </span>
                      ))}
                    </div>
                  )}
                </div>

                {/* Action */}
                {game.is_private || !DIRECT_JOIN_SLUGS.includes(game.slug) ? (
                  <span className="flex-shrink-0 self-end px-2 py-1.5 rounded-lg bg-secondary border border-white/10 text-muted-foreground font-semibold text-[10px]">
                    🔒 Code
                  </span>
                ) : (
                  <button
                    onClick={() => joinGame(game)}
                    disabled={isBusy || isFull}
                    className="flex-shrink-0 self-end flex items-center gap-1 px-3 py-2 rounded-lg bg-primary text-primary-foreground font-black text-xs disabled:opacity-60 active:scale-95 transition-all shadow-md shadow-primary/30"
                  >
                    {isBusy ? (
                      <RefreshCw className="w-3 h-3 animate-spin" />
                    ) : (
                      <Plus className="w-3 h-3" />
                    )}
                    {isBusy ? "Connexion…" : isFull ? "Complet" : "Rejoindre"}
                  </button>
                )}
              </div>
            );

          })}
        </div>
      </section>
      {showPhoneVerify && (
        <PhoneVerifyPopup onClose={() => setShowPhoneVerify(false)} />
      )}

      <DepotModal
        open={showDepositPopup}
        onClose={() => setShowDepositPopup(false)}
        mvolaPhone={walletSettings.mvolaPhone}
        mvolaName={walletSettings.mvolaName}
        orangePhone={walletSettings.orangePhone}
        orangeName={walletSettings.orangeName}
        airtelPhone={walletSettings.airtelPhone}
        airtelName={walletSettings.airtelName}
        minDeposit={walletSettings.minDeposit}
        onSuccess={() => { refreshProfile(); }}
      />
    </main>
  );
}
