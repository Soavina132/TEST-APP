import { createFileRoute, useNavigate, Link } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { toast } from "sonner";
import { ArrowLeft, Plus, Users, Coins, KeyRound, Lock, PlayCircle, Folder, Trophy, RotateCw, Target } from "lucide-react";
import AdminRenameDialog from "@/components/AdminRenameDialog";
import ludoCover from "@/assets/games/ludo.asset.json";
import dominoCover from "@/assets/games/domino.asset.json";
import ramiCover from "@/assets/games/rami.asset.json";
import chessCover from "@/assets/games/chess.asset.json";
import fanoronaCover from "@/assets/games/fanorona.asset.json";
import pokerCover from "@/assets/games/poker.asset.json";
import petanqueCover from "@/assets/games/petanque.asset.json";
import { shareNewGameInGroup } from "@/lib/share-game";

const COVER_BY_SLUG: Record<string, string> = {
  ludo: ludoCover.url, domino: dominoCover.url, fanorona: fanoronaCover.url,
  chess: chessCover.url, rami: ramiCover.url, poker: pokerCover.url, petanque: petanqueCover.url,
};

export const Route = createFileRoute("/_authenticated/jeux/nouveau/$slug")({
  component: Lobby,
  head: ({ params }) => ({
    meta: [{ title: "Lobby — Lalao MADA" }],
    links: COVER_BY_SLUG[params.slug]
      ? [{ rel: "preload", as: "image", href: COVER_BY_SLUG[params.slug], type: COVER_BY_SLUG[params.slug].endsWith(".webp") ? "image/webp" : undefined }]
      : [],
  }),
});

type Slug = "ludo" | "domino" | "fanorona" | "chess" | "rami" | "poker" | "petanque";
const STAKES = [100, 500, 1000, 2000, 5000];

const COVER_PLACEHOLDER: Record<string, string> = {
  "chess": "data:image/webp;base64,UklGRl4DAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4IMYAAACQBQCdASoUABQAPu1urlIppiQiqAgBMB2JZgCdMoM8An/AQP4/O1m3SRtP5hc+S0w2el8JsAD+6U6Zy+QtijWclNMXaeu4ahVZfYIm9ULhxkALwvYeDhC8s0dU1+UJxS6oMPaM8Q2Gr8g14Erx3NECSpOL9/OSL29y2pRSYTOVXwDqEzYVRJjW7WVTTwRnWUPwAJq6V5ME5/8E9ZL+ht+DxAiFkPplz7B7hMtuMmalrygMYmeWI7/CGS+KuD0Zo+lQFV9/2ABYTVAgcQIAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNS4wIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6SXB0YzR4bXBFeHQ9Imh0dHA6Ly9pcHRjLm9yZy9zdGQvSXB0YzR4bXBFeHQvMjAwOC0wMi0yOS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgSXB0YzR4bXBFeHQ6RGlnaXRhbFNvdXJjZUZpbGVUeXBlPSJodHRwOi8vY3YuaXB0Yy5vcmcvbmV3c2NvZGVzL2RpZ2l0YWxzb3VyY2V0eXBlL3RyYWluZWRBbGdvcml0aG1pY01lZGlhIiBJcHRjNHhtcEV4dDpEaWdpdGFsU291cmNlVHlwZT0iaHR0cDovL2N2LmlwdGMub3JnL25ld3Njb2Rlcy9kaWdpdGFsc291cmNldHlwZS90cmFpbmVkQWxnb3JpdGhtaWNNZWRpYSIgcGhvdG9zaG9wOkNyZWRpdD0iTWFkZSB3aXRoIEdvb2dsZSBBSSIvPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiAgIDw/eHBhY2tldCBlbmQ9InciPz4A",
  "domino": "data:image/webp;base64,UklGRlQDAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4ILwAAAAwBQCdASoUABQAPu1srVIppaQiqAgBMB2JagCsMxmv/gHqybaTlmwhnSGDllKDUM100AD+6U6ZzIefBcCKSkQilO6YaclEBAnrgd2YoV/GjANqn7NTdgK6CKITbDRKFRneGER2IdAhwdoc0imJBWDpAqM83uKddiUhkaVHLvKQk9hjkT/gy8bbbpJkzGf/BsKUP/Bq4NrvtrdM0fvIfPmM2oOvSetosKpBpwaAeFvdROi+/TZRbuBR8GaAAFhNUCBxAgAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNS41LjAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczpJcHRjNHhtcEV4dD0iaHR0cDovL2lwdGMub3JnL3N0ZC9JcHRjNHhtcEV4dC8yMDA4LTAyLTI5LyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiBJcHRjNHhtcEV4dDpEaWdpdGFsU291cmNlRmlsZVR5cGU9Imh0dHA6Ly9jdi5pcHRjLm9yZy9uZXdzY29kZXMvZGlnaXRhbHNvdXJjZXR5cGUvdHJhaW5lZEFsZ29yaXRobWljTWVkaWEiIElwdGM0eG1wRXh0OkRpZ2l0YWxTb3VyY2VUeXBlPSJodHRwOi8vY3YuaXB0Yy5vcmcvbmV3c2NvZGVzL2RpZ2l0YWxzb3VyY2V0eXBlL3RyYWluZWRBbGdvcml0aG1pY01lZGlhIiBwaG90b3Nob3A6Q3JlZGl0PSJNYWRlIHdpdGggR29vZ2xlIEFJIi8+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+ICAgPD94cGFja2V0IGVuZD0idyI/PgA=",
  "fanorona": "data:image/webp;base64,UklGRsgAAABXRUJQVlA4ILwAAABwBQCdASoUABQAPu1ur1IppiQiqAgBMB2JQBOmXRS2YVvntZEak2CwzwtBGcZpROzeXSAAAP62wA0KcQqSscR9O5gJOn9LQJBAq799FyiufdV8GhlL0MtUvr9PRIxiqXSWGt61yJoFzUvm+ysBXyV8YuKjidVdBPnyk+meKRjHXJWIJnD4Fb7970xzChQGGpqFccvmTqyFeZI4vkNezP18bfzo5NY75KzOD5G3uX7YySRgrwjU4pLwBkAAAA==",
  "ludo": "data:image/webp;base64,UklGRgIEAABXRUJQVlA4WAoAAAAoAAAAEwAAEwAASUNDUBgCAAAAAAIYAAAAAAIQAABtbnRyUkdCIFhZWiAAAAAAAAAAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAAHRyWFlaAAABZAAAABRnWFlaAAABeAAAABRiWFlaAAABjAAAABRyVFJDAAABoAAAAChnVFJDAAABoAAAAChiVFJDAAABoAAAACh3dHB0AAAByAAAABRjcHJ0AAAB3AAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAFgAAAAcAHMAUgBHAEIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFhZWiAAAAAAAABvogAAOPUAAAOQWFlaIAAAAAAAAGKZAAC3hQAAGNpYWVogAAAAAAAAJKAAAA+EAAC2z3BhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABYWVogAAAAAAAA9tYAAQAAAADTLW1sdWMAAAAAAAAAAQAAAAxlblVTAAAAIAAAABwARwBvAG8AZwBsAGUAIABJAG4AYwAuACAAMgAwADEANlZQOCDMAAAAEAUAnQEqFAAUAD7tbq9SKaYkIqgIATAdiWwAnTMcfQEHQDdxbfftYJYywmuiGw/uYAD+6U6Ua7z5RGgZL5CfvPzOhUef9RGP1yGMEUWxifrBPE+0MVfnK+fczsUBlg7Ztg2ztMolCuX54ryoc+CidYLxqXSLWOqBlpmG766ycjcMxQZC69ROsyJLcOTMH4lFBO3GVvzlJroTpR5ZoOUcqz2bbxoJsRsWUsqY74Uwv27wiKn/UV/zHQbfXUsd5BsmdBedia1O9nwy3AAARVhJRvAAAABNTQAqAAAACAAHAQAABAAAAAEAAAQ4ARAAAgAAAAkAAABiAQEABAAAAAEAAAQoARIAAwAAAAEAAQAAATIAAgAAABQAAABrh2kABAAAAAEAAACGAQ8AAgAAAAcAAAB/AAAAAFBPVC1MWDFUADIwMjY6MDY6MTggMjI6NDc6MDYASFVBV0VJAAAFkggABAAAAAEAAAAAkAQAAgAAABQAAADIkAMAAgAAABQAAADcoAMABAAAAAEAAAQooAIABAAAAAEAAAQ4AAAAADIwMjY6MDY6MTggMjI6NDY6NTcAMjAyNjowNjoxOCAyMjo0Njo1NwA=",
  "rami": "data:image/webp;base64,UklGRlYDAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4IL4AAADQBQCdASoUABQAPu1srlIppaQiqAgBMB2JbACdMySzPn/AQPemvn5cyH5eXJN251v1PPpW+LWQAP7sTWhRWXJkiRF49d5If4J/E9pZ2k/+N888A/wyLyDPW21VB0nWNCN7UViNM1MktRPp41nd1ZztvqSG/pD6nHVzZFHR2mf5uUGGoxZJXlHJNbcIJuD+DYUof+CZG1321umaP3kPhsDbaCfpJL5MFR2uz/zC7RJ/hAOahxN/uxgqzwTaoAAAWE1QIHECAAA8P3hwYWNrZXQgYmVnaW49Iu+7vyIgaWQ9Ilc1TTBNcENlaGlIenJlU3pOVGN6a2M5ZCI/PiA8eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEvIiB4OnhtcHRrPSJYTVAgQ29yZSA1LjUuMCI+IDxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+IDxyZGY6RGVzY3JpcHRpb24gcmRmOmFib3V0PSIiIHhtbG5zOklwdGM0eG1wRXh0PSJodHRwOi8vaXB0Yy5vcmcvc3RkL0lwdGM0eG1wRXh0LzIwMDgtMDItMjkvIiB4bWxuczpwaG90b3Nob3A9Imh0dHA6Ly9ucy5hZG9iZS5jb20vcGhvdG9zaG9wLzEuMC8iIElwdGM0eG1wRXh0OkRpZ2l0YWxTb3VyY2VGaWxlVHlwZT0iaHR0cDovL2N2LmlwdGMub3JnL25ld3Njb2Rlcy9kaWdpdGFsc291cmNldHlwZS90cmFpbmVkQWxnb3JpdGhtaWNNZWRpYSIgSXB0YzR4bXBFeHQ6RGlnaXRhbFNvdXJjZVR5cGU9Imh0dHA6Ly9jdi5pcHRjLm9yZy9uZXdzY29kZXMvZGlnaXRhbHNvdXJjZXR5cGUvdHJhaW5lZEFsZ29yaXRobWljTWVkaWEiIHBob3Rvc2hvcDpDcmVkaXQ9Ik1hZGUgd2l0aCBHb29nbGUgQUkiLz4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gICA8P3hwYWNrZXQgZW5kPSJ3Ij8+AA=="
};

function CoverImage({ src, alt, slug, dims }: { src: string; alt: string; slug: string; dims: { w: number; h: number } }) {
  const [loaded, setLoaded] = useState(false);
  const placeholder = COVER_PLACEHOLDER[slug];
  return (
    <>
      {placeholder && (
        <div
          aria-hidden
          className="absolute inset-0 bg-cover bg-center scale-110"
          style={{ backgroundImage: `url(${placeholder})`, filter: "blur(16px)", opacity: loaded ? 0 : 1, transition: "opacity 300ms ease-out" }}
        />
      )}
      <img
        src={src}
        alt={alt}
        width={dims.w}
        height={dims.h}
        loading="lazy"
        decoding="async"
        onLoad={() => setLoaded(true)}
        className="absolute inset-0 w-full h-full object-cover"
        style={{ opacity: loaded ? 1 : 0, transition: "opacity 300ms ease-out" }}
      />
    </>
  );
}

const COVER_DIMS: Record<string, { w: number; h: number }> = {
  ludo: { w: 1080, h: 1064 }, domino: { w: 1024, h: 1024 }, fanorona: { w: 1024, h: 1024 },
  chess: { w: 1024, h: 1024 }, rami: { w: 1024, h: 1024 }, petanque: { w: 1024, h: 1024 },
};
const META: Record<Slug, { label: string; cover: string; maxOpts: number[] }> = {
  ludo: { label: "Ludo", cover: ludoCover.url, maxOpts: [2, 3, 4] },
  domino: { label: "Domino", cover: dominoCover.url, maxOpts: [2, 3] },
  fanorona: { label: "Fanorona", cover: fanoronaCover.url, maxOpts: [2] },
  chess: { label: "Échecs", cover: chessCover.url, maxOpts: [2] },
  rami: { label: "Rami", cover: ramiCover.url, maxOpts: [2, 3, 4] },
  poker: { label: "Poker", cover: pokerCover.url, maxOpts: [2, 3, 4, 5, 6, 7, 8, 9] },
  petanque: { label: "Pétanque", cover: petanqueCover.url, maxOpts: [2] },
};

const ROUTE: Record<Slug, any> = {
  ludo: "/game/$id", domino: "/domino/$id", fanorona: "/fanorona/$id", chess: "/chess/$id", rami: "/rami/$id", poker: "/poker/$id", petanque: "/petanque/$id",
};
const GAME_TABLE: Record<Slug, string> = {
  ludo: "ludo_games", domino: "domino_games", fanorona: "fanorona_games", chess: "chess_games", rami: "rami_games", poker: "poker_games", petanque: "petanque_games",
};
const PART_TABLE: Record<Slug, string | null> = {
  ludo: "ludo_participants", domino: "domino_participants", fanorona: "fanorona_participants", chess: null, rami: "rami_participants", poker: "poker_players", petanque: "petanque_participants",
};

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

function extractGameId(data: unknown): string | null {
  const row = Array.isArray(data) ? data[0] : data;
  const value = row && typeof row === "object" ? (row as { id?: unknown; game_id?: unknown }).id ?? (row as { game_id?: unknown }).game_id : row;
  return typeof value === "string" && UUID_RE.test(value) ? value : null;
}

type Tab = "public" | "private" | "code" | "mine";

function Lobby() {
  const { slug: rawSlug } = Route.useParams();
  const slug = rawSlug as Slug;
  const meta = META[slug];
  const { profile, isAdmin, refreshProfile } = useAuth();
  const navigate = useNavigate();

  const [tab, setTab] = useState<Tab>("public");
  const [publicGames, setPublicGames] = useState<any[]>([]);
  const [mine, setMine] = useState<{ ongoing: any[]; finished: any[] }>({ ongoing: [], finished: [] });
  const [mineTab, setMineTab] = useState<"ongoing" | "finished">("ongoing");
  const [maxP, setMaxP] = useState(meta?.maxOpts[0] ?? 2);
  const [stake, setStake] = useState(1000);
  const [mode, setMode] = useState<"classic" | "fast" | "direct" | "points">("classic");
  // Ludo : déplacement automatique d'un pion jouable quand le timer expire
  // (uniquement si le dé a déjà été lancé).
  const [ludoAutoMove, setLudoAutoMove] = useState(true);
  const [matchType, setMatchType] = useState<"bot" | "friends">("friends");
  const [drawMode, setDrawMode] = useState<"with" | "without">("with");
  const [firstTileRule, setFirstTileRule] = useState<"libre" | "under6">("libre");
  const [targetScore, setTargetScore] = useState(100);
  const [fanoronaVariant, setFanoronaVariant] = useState<"telo" | "dimy" | "tsivy">("tsivy");
  const [fanoronaMandatory, setFanoronaMandatory] = useState<boolean>(true);
  const [ramiJokerMode, setRamiJokerMode] = useState<"sans" | "aleatoire" | "classique" | "double">("sans");
  const [ramiGameMode, setRamiGameMode] = useState<"bordel" | "naturel">("bordel");
  const [ramiBotDifficulty, setRamiBotDifficulty] = useState<"easy" | "medium" | "hard">("medium");
  // Poker : blindes + cave (jetons de table, indépendants de la mise en Ar)
  const [pokerBlinds, setPokerBlinds] = useState<{ sb: number; bb: number }>({ sb: 10, bb: 20 });
  const [pokerBuyIn, setPokerBuyIn] = useState(2000);
  const [chessBotDifficulty, setChessBotDifficulty] = useState<"very_easy" | "easy" | "medium" | "hard" | "expert">("medium");
  const [chessBotColor, setChessBotColor] = useState<"white" | "black">("white");
  const [chessTime, setChessTime] = useState<number>(10);
  const [code, setCode] = useState("");
  const [visibility, setVisibility] = useState<"public" | "private">("public");
  const [commission] = useState(10);
  const [busy, setBusy] = useState(false);
  const [renameOpen, setRenameOpen] = useState(false);
  const [pendingAction, setPendingAction] = useState<((name?: string) => Promise<void>) | null>(null);
  const [sheet, setSheet] = useState<string | null>(null);
  const closeSheet = () => setSheet(null);

  const supportsPublicJoin = true; // All games can create public games

  // Pre-flight checks: balance + phone verified (only when stake > 0)
  const checkGuards = (intendedStake: number): boolean => {
    if (intendedStake <= 0) return true;
    const bal = Number(profile?.balance_ar || 0);
    if (bal < intendedStake) {
      toast.error("Solde insuffisant", {
        description: `Vous avez ${bal.toLocaleString("fr-FR")} Ar. Il vous faut ${intendedStake.toLocaleString("fr-FR")} Ar.`,
        action: { label: "Déposer", onClick: () => navigate({ to: "/" }) },
        duration: 8000,
      });
      return false;
    }
    if (!(profile as any)?.phone_verified) {
      toast.error("Numéro non vérifié", {
        description: "Vérifiez votre numéro avant de jouer avec une mise.",
        action: { label: "Vérifier", onClick: () => navigate({ to: "/profile" }) },
        duration: 8000,
      });
      return false;
    }
    return true;
  };

  const loadPublic = async () => {
    if (slug === "ludo") {
      const { data } = await supabase.rpc("list_public_open_games" as any);
      setPublicGames((data as any[]) || []);
    } else {
      const { data } = await supabase.from(GAME_TABLE[slug] as any)
        .select("*").eq("status", "open").eq("is_private", false)
        .order("created_at", { ascending: false }).limit(20);
      setPublicGames((data as any[]) || []);
    }
  };

  const loadMine = async () => {
    if (!profile?.id) return;
    if (slug === "ludo") {
      const { data } = await supabase.rpc("my_games" as any);
      setMine((data as any) || { ongoing: [], finished: [] });
      return;
    }
    if (slug === "chess") {
      const { data } = await supabase.from("chess_games" as any).select("*")
        .or(`white_id.eq.${profile.id},black_id.eq.${profile.id}`)
        .order("created_at", { ascending: false }).limit(60);
      const rows = (data as any[]) || [];
      setMine({
        ongoing: rows.filter(r => r.status === "open" || r.status === "playing"),
        finished: rows.filter(r => r.status === "finished" || r.status === "cancelled")
          .map(r => ({ ...r, won: r.winner_id === profile.id })),
      });
      return;
    }
    const part = PART_TABLE[slug]!;
    const { data: parts } = await supabase.from(part as any)
      .select("*, game:" + GAME_TABLE[slug] + "(*)").eq("user_id", profile.id);
    const rows = (parts as any[]) || [];
    setMine({
      ongoing: rows.filter(r => r.game?.status === "open" || r.game?.status === "playing")
        .map(r => ({ ...r.game, my_forfeited: r.forfeited })),
      finished: rows.filter(r => r.game?.status === "finished" || r.game?.status === "cancelled")
        .map(r => ({ ...r.game, won: r.game?.winner_id === profile?.id, forfeited: r.forfeited })),
    });
  };

  useEffect(() => {
    loadPublic(); loadMine();
    const ch = supabase.channel("lobby-" + slug)
      .on("postgres_changes", { event: "*", schema: "public", table: GAME_TABLE[slug] }, () => { loadPublic(); loadMine(); })
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [slug, profile?.id]);

  const withAdminRename = (action: (name?: string) => Promise<void>) => () => {
    action();
  };

  const applyLudoAutoMove = async (gameId: string | null) => {
    if (slug !== "ludo" || !gameId) return;
    await supabase.rpc("ludo_set_auto_move" as any, { _game_id: gameId, _enabled: ludoAutoMove } as any);
  };

  const goTo = (value: unknown) => {
    const id = extractGameId(value);
    if (!id) {
      toast("Partie créée, mais l'identifiant reçu est invalide. Réessayez depuis vos parties.");
      loadMine();
      return;
    }
    navigate({ to: ROUTE[slug], params: { id } as any });
  };

  const joinPublicOrCreate = withAdminRename(async (overrideName) => {
    // Onglet Gratuit : mise forcée à 0, aucune vérification requise
    setBusy(true);
    try {
      // vs AMIES → visibilité choisie (public : visible dans "Parties ouvertes" / privé : code)
      if (matchType === "friends") {
        await createNewFree(visibility === "private");
        return;
      }
      // vs BOT → créer une partie privée gratuite puis remplir avec des bots (démarrage immédiat)
      let id: string | null = null;
      if (slug === "ludo") {
        const { data, error } = await supabase.rpc("create_private_game" as any, {
          _max_players: maxP, _stake: 0, _mode: "classic", _match_type: "solo",
        } as any);
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        if (overrideName) await supabase.rpc("ludo_set_display_name" as any, { _game_id: id, _name: overrideName } as any);
        await applyLudoAutoMove(id);
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const { error: berr } = await supabase.rpc("player_add_bot" as any, { _game_id: id, _bot_name: `Bot ${i + 1}` } as any);
          if (berr) throw berr;
        }
        // Auto-ready pour démarrer immédiatement (bypass salle d'attente)
        await supabase.rpc("ludo_set_ready" as any, { _game_id: id, _ready: true } as any);
      } else if (slug === "domino") {
        const { data, error } = await supabase.rpc("domino_create" as any, {
          _stake: 0, _max: maxP, _private: true,
          _mode: mode === "points" ? "points" : "classic",
          _commission: commission,
          _target_score: mode === "points" ? targetScore : 0,
          _draw_mode: drawMode, _first_tile_rule: firstTileRule,
        } as any);
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const { error: berr } = await supabase.rpc("domino_add_bot" as any, { _game_id: id, _bot_name: `Bot ${i + 1}` } as any);
          if (berr) throw berr;
        }
        // Auto-ready pour démarrer immédiatement (bypass salle d'attente)
        await supabase.rpc("domino_set_ready" as any, { _game_id: id, _ready: true } as any);
      } else if (slug === "chess") {
        const diffMap = { very_easy: 1, easy: 2, medium: 3, hard: 4, expert: 5 } as const;
        const { data, error } = await supabase.rpc("chess_create_solo" as any, {
          _difficulty: diffMap[chessBotDifficulty], _color: chessBotColor, _time_min: chessTime,
        } as any);
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else if (slug === "petanque") {
        const { data, error } = await supabase.rpc("petanque_create" as any, { p_stake: 0, p_public: false } as any);
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        const { error: berr } = await supabase.rpc("petanque_add_bot" as any, { _game_id: id } as any);
        if (berr) throw berr;
        await supabase.rpc("petanque_set_ready" as any, { _game_id: id, _ready: true } as any);
      } else if (slug === "rami") {
        const { data, error } = await supabase.rpc("rami_start_solo_bot" as any, {
          _max_players: maxP, _difficulty: ramiBotDifficulty,
          _joker_mode: ramiJokerMode, _game_mode: ramiGameMode,
        } as any);
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else {
        // Jeux sans support bot pour l'instant : partie publique classique
        await createNewFree(false);
        return;
      }

      if (id) { refreshProfile(); goTo(id); }
    } catch (e: any) { toast.error(e.message || "Erreur"); } finally { setBusy(false); }
  });

  const createNewFree = async (priv: boolean) => {
    const savedStake = stake;
    (stake as any); // no-op
    try {
      // temporarily override by calling createNew with stake=0 via closure trick
      // simplest: call the RPCs directly mirroring createNew but with _stake: 0
      let id: string | null = null;
      if (slug === "ludo") {
        const fn = priv ? "create_private_game" : "find_or_create_game";
        const args: any = priv ? { _max_players: maxP, _stake: 0, _mode: mode === "fast" ? "fast" : "classic", _match_type: matchType === "bot" ? "solo" : "groupe" } : { _max_players: maxP, _stake: 0 };
        const { data, error } = await supabase.rpc(fn as any, args);
        if (error) throw error; id = extractGameId(data);
        await applyLudoAutoMove(id);
      } else if (slug === "domino") {
        const { data, error } = await supabase.rpc("domino_create" as any, {
          _stake: 0, _max: maxP, _private: priv, _mode: mode === "points" ? "points" : "classic",
          _commission: commission, _target_score: mode === "points" ? targetScore : 0,
          _draw_mode: drawMode, _first_tile_rule: firstTileRule,
        } as any);
        if (error) throw error; id = extractGameId(data);
      } else if (slug === "fanorona") {
        const { data, error } = await supabase.rpc("fanorona_create" as any, { _stake: 0, _private: priv, _commission: commission, _variant: fanoronaVariant, _mandatory_capture: fanoronaMandatory } as any);
        if (error) throw error; id = extractGameId(data);
      } else if (slug === "chess") {
        const { data, error } = await supabase.rpc("chess_create_friends" as any, { _time_min: chessTime } as any);
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "rami") {
        const { data, error } = await supabase.rpc("rami_create" as any, { _stake: 0, _max: maxP, _private: priv, _commission: commission, _joker_mode: ramiJokerMode, _game_mode: ramiGameMode } as any);
        if (error) throw error; id = extractGameId(data);
      } else if (slug === "poker") {
        const { data, error } = await supabase.rpc("poker_create" as any, { _stake: 0, _max: maxP, _private: priv, _commission: commission, _small_blind: pokerBlinds.sb, _big_blind: pokerBlinds.bb, _buy_in: pokerBuyIn } as any);
        if (error) throw error; id = extractGameId(data);
      } else if (slug === "petanque") {
        const { data, error } = await supabase.rpc("petanque_create" as any, { p_stake: 0, p_public: !priv } as any);
        if (error) throw error; id = extractGameId(data);
      }
      if (id) { shareNewGameInGroup(slug, id); refreshProfile(); goTo(id); }
    } finally { void savedStake; }
  };



  const createNew = async (priv: boolean) => {
    let id: string | null = null;
    if (slug === "ludo") {
      const fn = priv ? "create_private_game" : "find_or_create_game";
      const args: any = priv ? { _max_players: maxP, _stake: stake, _mode: mode === "fast" ? "fast" : "classic", _match_type: matchType === "bot" ? "solo" : "groupe" } : { _max_players: maxP, _stake: stake };
      const { data, error } = await supabase.rpc(fn as any, args);
      if (error) throw error; id = extractGameId(data);
      await applyLudoAutoMove(id);
    } else if (slug === "domino") {
      const { data, error } = await supabase.rpc("domino_create" as any, {
        _stake: stake, _max: maxP, _private: priv, _mode: mode === "points" ? "points" : "classic",
        _commission: commission, _target_score: mode === "points" ? targetScore : 0,
        _draw_mode: drawMode,
        _first_tile_rule: firstTileRule,
      } as any);
      if (error) throw error; id = extractGameId(data);
    } else if (slug === "fanorona") {
      const { data, error } = await supabase.rpc("fanorona_create" as any, {
        _stake: stake, _private: priv, _commission: commission,
        _variant: fanoronaVariant, _mandatory_capture: fanoronaMandatory,
      } as any);
      if (error) throw error; id = extractGameId(data);
    } else if (slug === "chess") {
      const { data, error } = await supabase.rpc("chess_create_stake" as any, { _stake: stake, _time_min: chessTime } as any);
      if (error) throw error; id = extractGameId(data);
    } else if (slug === "rami") {
      const { data, error } = await supabase.rpc("rami_create" as any, { _stake: stake, _max: maxP, _private: priv, _commission: commission, _joker_mode: ramiJokerMode, _game_mode: ramiGameMode } as any);
      if (error) throw error; id = extractGameId(data);
    } else if (slug === "poker") {
      const { data, error } = await supabase.rpc("poker_create" as any, { _stake: stake, _max: maxP, _private: priv, _commission: commission, _small_blind: pokerBlinds.sb, _big_blind: pokerBlinds.bb, _buy_in: pokerBuyIn } as any);
      if (error) throw error; id = extractGameId(data);
    } else if (slug === "petanque") {
      const { data, error } = await supabase.rpc("petanque_create" as any, { p_stake: stake, p_public: !priv } as any);
      if (error) throw error; id = extractGameId(data);
    }
    if (id) { shareNewGameInGroup(slug, id); refreshProfile(); goTo(id); }
  };

  const createPrivate = withAdminRename(async (overrideName) => {
    if (!checkGuards(stake)) return;
    setBusy(true);
    try {
      if (matchType === "bot" && slug === "ludo") {
        // Mode Solo Ludo avec mise : créer une partie privée avec bots
        const { data, error } = await supabase.rpc("create_private_game" as any, {
          _max_players: maxP, _stake: stake, _mode: mode === "fast" ? "fast" : "classic", _match_type: "solo",
        } as any);
        if (error) throw error;
        const id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        if (overrideName) await supabase.rpc("ludo_set_display_name" as any, { _game_id: id, _name: overrideName } as any);
        await applyLudoAutoMove(id);
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const { error: berr } = await supabase.rpc("player_add_bot" as any, { _game_id: id, _bot_name: `Bot ${i + 1}` } as any);
          if (berr) throw berr;
        }
        await supabase.rpc("ludo_set_ready" as any, { _game_id: id, _ready: true } as any);
        refreshProfile(); goTo(id);
      } else {
        await createNew(visibility === "private");
      }
    } catch (e: any) { toast.error(e.message || "Erreur"); } finally { setBusy(false); }
  });

  const joinExisting = (gameId: string) => withAdminRename(async () => {
    try {
      if (slug === "ludo") {
        const { error } = await supabase.rpc("join_game" as any, { _game_id: gameId } as any);
        if (error) throw error;
      } else if (slug === "domino" || slug === "fanorona") {
        const fn = slug === "domino" ? "domino_join" : "fanorona_join";
        const { error } = await supabase.rpc(fn as any, { _game_id: gameId } as any);
        if (error) throw error;
      } else if (slug === "poker") {
        const { error } = await supabase.rpc("poker_join" as any, { _game_id: gameId } as any);
        if (error) throw error;
      } else if (slug === "petanque") {
        const { error } = await supabase.rpc("petanque_join" as any, { _game_id: gameId } as any);
        if (error) throw error;
      }
      refreshProfile(); goTo(gameId);
    } catch (e: any) { toast.error(e.message || "Erreur"); }
  })();

  const joinByCode = withAdminRename(async () => {
    if (!code.trim()) return;
    setBusy(true);
    try {
      const fn = slug === "ludo" ? "join_game_by_code" :
        slug === "domino" ? "domino_join_code" :
        slug === "fanorona" ? "fanorona_join_code" :
        slug === "chess" ? "chess_join_friends" : slug === "poker" ? "poker_join_code" :
        slug === "petanque" ? "petanque_join_code" : "rami_join_code";
      const { data, error } = await supabase.rpc(fn as any, { _code: code.trim().toUpperCase() } as any);
      if (error) throw error;
      refreshProfile(); goTo(data);
    } catch (e: any) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient")) {
        toast.error("Solde insuffisant pour rejoindre cette partie.", {
          action: { label: "Déposer", onClick: () => navigate({ to: "/" }) },
        });
      } else {
        toast.error(e.message || "Code invalide");
      }
    } finally { setBusy(false); }
  });

  if (!meta) return <div className="p-6">Jeu inconnu.</div>;

  const showMaxP = meta.maxOpts.length > 1;

  return (
    <main className="max-w-3xl mx-auto h-[100dvh] flex flex-col overflow-hidden">
      <div className="flex items-center gap-2 px-3 pt-2 pb-1.5 shrink-0">
        {COVER_BY_SLUG[slug] && (
          <div className="relative w-12 h-12 rounded-xl overflow-hidden shrink-0 ring-1 ring-primary/30 shadow bg-black/20">
            <CoverImage
              src={COVER_BY_SLUG[slug]}
              alt={meta.label}
              slug={slug}
              dims={COVER_DIMS[slug] ?? { w: 1024, h: 1024 }}
            />
          </div>
        )}
        <div className="min-w-0 flex-1">
          <div className="inline-block text-[9px] uppercase tracking-[0.18em] font-bold text-primary px-1.5 py-0.5 rounded bg-primary/10 ring-1 ring-primary/20">Créer une partie</div>
          <div className="font-extrabold text-lg leading-tight truncate mt-0.5 text-foreground">{meta.label}</div>
        </div>
      </div>



      <div className="px-3 pt-1 pb-3 flex flex-col gap-2 flex-1 min-h-0">
        <div className="grid grid-cols-4 gap-1.5 shrink-0">
          {supportsPublicJoin && <TabBtn label="Gratuit" active={tab === "public"} onClick={() => setTab("public")} icon={<span className="text-sm leading-none">🆓</span>} />}
          <TabBtn label="Mise" active={tab === "private"} onClick={() => setTab("private")} icon={<span className="text-sm leading-none">💰</span>} />
          <TabBtn label="Code" active={tab === "code"} onClick={() => setTab("code")} icon={<span className="text-sm leading-none">🔑</span>} />
          <TabBtn label="Mes" active={tab === "mine"} onClick={() => setTab("mine")} icon={<span className="text-sm leading-none">📂</span>} />
        </div>
        {((tab === "public" && matchType === "friends") || (tab === "private" && matchType === "friends")) && (
          <div className="grid grid-cols-2 gap-1.5 shrink-0" role="tablist" aria-label="Visibilité">
            <button onClick={() => setVisibility("public")} aria-pressed={visibility === "public"}
              className={`px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] border ${
                visibility === "public"
                  ? "bg-emerald-500/15 text-emerald-600 border-emerald-500/40"
                  : "bg-card border-white/8 text-muted-foreground hover:text-foreground"
              }`}>
              🌐 <span>Public</span>
            </button>
            <button onClick={() => setVisibility("private")} aria-pressed={visibility === "private"}
              className={`px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] border ${
                visibility === "private"
                  ? "bg-orange-500/15 text-orange-600 border-orange-500/40"
                  : "bg-card border-white/8 text-muted-foreground hover:text-foreground"
              }`}>
              🔒 <span>Privé</span>
            </button>
          </div>
        )}
        <div className="flex-1 min-h-0 overflow-y-auto -mx-1 px-1 space-y-2">



        {tab === "public" && supportsPublicJoin && (
          <section className="space-y-2">
            <div className="rounded-2xl bg-card border border-white/6 p-1.5 shadow-sm divide-y divide-white/5">
              <SummaryRow icon="🎯" label="Adversaire" value={matchType === "bot" ? "🤖 Solo" : "👥 Groupe"} onClick={() => setSheet("opponent")} />
              {meta.maxOpts.length > 1 && (
                <SummaryRow icon="👥" label="Joueurs" value={`${maxP}`} onClick={() => setSheet("players")} />
              )}
              {slug === "domino" && (
                <>
                  <SummaryRow icon="🎲" label="Format" value={mode === "points" ? `Par points (${targetScore})` : "Victoire directe"} onClick={() => setSheet("domino_mode")} />
                  <SummaryRow icon="🁣" label="Pioche" value={drawMode === "with" ? "Avec" : "Sans"} onClick={() => setSheet("domino_draw")} />
                  <SummaryRow icon="🎬" label="Premier coup" value={firstTileRule === "libre" ? "Libre" : "1er <6"} onClick={() => setSheet("domino_first")} />
                </>
              )}
              {slug === "ludo" && (
                <SummaryRow icon="🤖" label="Déplacement auto" value={ludoAutoMove ? "Activé" : "Désactivé"} onClick={() => setLudoAutoMove(v => !v)} />
              )}
              {slug === "fanorona" && (
                <SummaryRow icon="⚫" label="Plateau" value={`${fanoronaVariant} · ${fanoronaMandatory ? "obligatoire" : "libre"}`} onClick={() => setSheet("fanorona")} />
              )}
              {slug === "chess" && matchType === "bot" && (
                <>
                  <SummaryRow icon="⭐" label="Difficulté" value={({ very_easy:"⭐ 600", easy:"⭐⭐ 900", medium:"⭐⭐⭐ 1200", hard:"⭐⭐⭐⭐ 1700", expert:"⭐⭐⭐⭐⭐ 2200" } as any)[chessBotDifficulty]} onClick={() => setSheet("chess_diff")} />
                  <SummaryRow icon={chessBotColor === "white" ? "⚪" : "⚫"} label="Couleur" value={chessBotColor === "white" ? "Blancs" : "Noirs"} onClick={() => setSheet("chess_color")} />
                </>
              )}
              {slug === "poker" && (
                <>
                  <SummaryRow icon="🪙" label="Blindes" value={`${pokerBlinds.sb} / ${pokerBlinds.bb}`} onClick={() => setSheet("poker_blinds")} />
                  <SummaryRow icon="💵" label="Cave (jetons)" value={pokerBuyIn.toLocaleString("fr-FR")} onClick={() => setSheet("poker_buyin")} />
                </>
              )}

              {slug === "rami" && (
                <>
                  <SummaryRow icon="🃏" label="Joker" value={({ sans:"Sans", aleatoire:"Aléatoire", classique:"Classique", double:"Double" } as any)[ramiJokerMode]} onClick={() => setSheet("rami")} />
                  <SummaryRow icon="📜" label="Mode de jeu" value={ramiGameMode === "naturel" ? "Naturel" : "Bordel"} onClick={() => setSheet("rami_mode")} />
                  {matchType === "bot" && (
                    <SummaryRow icon="⭐" label="Niveau des bots" value={({ easy:"⭐ Facile", medium:"⭐⭐ Moyen", hard:"⭐⭐⭐ Difficile" } as any)[ramiBotDifficulty]} onClick={() => setSheet("rami_diff")} />
                  )}
                </>
              )}

              {slug === "chess" && (
                <SummaryRow icon="⏱️" label="Temps / joueur" value={chessTime === 999 ? "Illimité" : `${chessTime} min`} onClick={() => setSheet("chess_time")} />
              )}
            </div>

            {matchType === "friends" && visibility === "private" && (
              <div className="rounded-xl bg-primary/8 border border-primary/20 px-3 py-2 text-[11px] text-primary/90 flex items-center gap-2">
                <KeyRound className="w-3.5 h-3.5 shrink-0" />
                <span>Un code d'invitation à 6 caractères sera généré.</span>
              </div>
            )}
            <button onClick={joinPublicOrCreate} disabled={busy}
              className="w-full py-3.5 rounded-full text-white font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-primary/40 active:scale-[0.98] transition-transform sticky bottom-2"
              style={{ background: "var(--gradient-primary)" }}>
              {matchType === "friends"
                ? (visibility === "public"
                    ? (<><PlayCircle className="w-4 h-4" /> {busy ? "…" : "Créer la partie"}</>)
                    : (<><KeyRound className="w-4 h-4" /> {busy ? "…" : "Créer et inviter"}</>))
                : (<><PlayCircle className="w-4 h-4" /> {busy ? "…" : "Commencer la partie"}</>)}
            </button>

          </section>
        )}


        {tab === "private" && (
          <section className="space-y-2">
            <div className="rounded-2xl bg-card border border-white/6 p-1.5 shadow-sm divide-y divide-white/5">
              <SummaryRow icon="🎯" label="Adversaire" value={matchType === "bot" ? "🤖 Solo" : "👥 Groupe"} onClick={() => setSheet("opponent")} />
              {showMaxP && (
                <SummaryRow icon="👥" label="Joueurs" value={`${maxP}`} onClick={() => setSheet("players")} />
              )}
              <SummaryRow icon="💰" label="Mise" value={stake > 0 ? `${stake.toLocaleString("fr-FR")} Ar` : "Gratuit"} onClick={() => setSheet("stake")} />
              {slug === "ludo" && (
                <SummaryRow icon="🎲" label="Mode" value={mode === "fast" ? "Rapide" : "Classique"} onClick={() => setSheet("ludo_mode")} />
              )}
              {slug === "ludo" && (
                <SummaryRow icon="🤖" label="Déplacement auto" value={ludoAutoMove ? "Activé" : "Désactivé"} onClick={() => setLudoAutoMove(v => !v)} />
              )}
              {slug === "domino" && (
                <>
                  <SummaryRow icon="🎲" label="Format" value={mode === "points" ? `Par points (${targetScore})` : "Victoire directe"} onClick={() => setSheet("domino_mode")} />
                  <SummaryRow icon="🁣" label="Pioche" value={drawMode === "with" ? "Avec" : "Sans"} onClick={() => setSheet("domino_draw")} />
                  <SummaryRow icon="🎬" label="Premier coup" value={firstTileRule === "libre" ? "Libre" : "1er <6"} onClick={() => setSheet("domino_first")} />
                </>
              )}
              {slug === "fanorona" && (
                <SummaryRow icon="⚫" label="Plateau" value={`${fanoronaVariant} · ${fanoronaMandatory ? "obligatoire" : "libre"}`} onClick={() => setSheet("fanorona")} />
              )}
              {slug === "rami" && (
                <>
                  <SummaryRow icon="🃏" label="Joker" value={({ sans:"Sans", aleatoire:"Aléatoire", classique:"Classique", double:"Double" } as any)[ramiJokerMode]} onClick={() => setSheet("rami")} />
                  <SummaryRow icon="📜" label="Mode de jeu" value={ramiGameMode === "naturel" ? "Naturel" : "Bordel"} onClick={() => setSheet("rami_mode")} />
                </>
              )}

              {slug === "poker" && (
                <>
                  <SummaryRow icon="🪙" label="Blindes" value={`${pokerBlinds.sb} / ${pokerBlinds.bb}`} onClick={() => setSheet("poker_blinds")} />
                  <SummaryRow icon="💵" label="Cave (jetons)" value={pokerBuyIn.toLocaleString("fr-FR")} onClick={() => setSheet("poker_buyin")} />
                </>
              )}

              {slug === "chess" && (
                <SummaryRow icon="⏱️" label="Temps / joueur" value={chessTime === 999 ? "Illimité" : `${chessTime} min`} onClick={() => setSheet("chess_time")} />
              )}
            </div>

            {stake > 0 && (
              <div className="grid grid-cols-2 gap-1.5 text-xs">
                <div className="rounded-xl bg-amber-500/8 border border-amber-500/20 p-2 text-center">
                  <div className="text-[9px] text-amber-500/80 uppercase tracking-wider font-bold">Cagnotte</div>
                  <div className="font-extrabold text-sm">{(stake * maxP).toLocaleString("fr-FR")} Ar</div>
                </div>
                <div className="rounded-xl bg-emerald-500/10 border border-emerald-500/25 p-2 text-center">
                  <div className="text-[9px] text-emerald-600/90 uppercase tracking-wider font-bold">Gain net</div>
                  <div className="font-extrabold text-sm text-emerald-600">{Math.round(stake * maxP * (100 - commission) / 100).toLocaleString("fr-FR")} Ar</div>
                </div>
              </div>
            )}

            <button onClick={createPrivate} disabled={busy || (slug === "domino" && mode === "points" && targetScore < 1)}
              className="w-full py-3.5 rounded-full text-white font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-primary/40 active:scale-[0.98] transition-transform sticky bottom-2"
              style={{ background: "var(--gradient-primary)" }}>
              {matchType === "bot" && slug === "ludo"
                ? (<><PlayCircle className="w-4 h-4" /> {busy ? "…" : "Commencer la partie"}</>)
                : visibility === "public"
                  ? (<><PlayCircle className="w-4 h-4" /> {busy ? "…" : "Créer la partie"}</>)
                  : (<><Lock className="w-4 h-4" /> {busy ? "…" : "Créer la partie privée"}</>)}
            </button>

            {visibility === "private" && (slug !== "ludo" || matchType === "friends") && (
              <div className="text-[11px] text-muted-foreground text-center">Un code à 6 caractères sera généré pour inviter tes amis.</div>
            )}
          </section>
        )}

        {tab === "code" && (
          <section className="space-y-3">
            <div className="rounded-2xl bg-card border border-white/6 p-5 shadow-md space-y-3">
              <div className="font-bold flex items-center gap-2">
                <div className="w-8 h-8 rounded-lg bg-primary/15 flex items-center justify-center">
                  <KeyRound className="w-4 h-4 text-primary" />
                </div>
                Code de la partie
              </div>
              <input value={code} onChange={e => setCode(e.target.value.toUpperCase())} placeholder="EX: A1B2C3" maxLength={6}
                className="w-full px-4 py-3 rounded-2xl bg-secondary border border-border outline-none uppercase tracking-[0.4em] font-mono text-center text-xl" />
              <button onClick={joinByCode} disabled={busy || !code.trim()}
                className="w-full py-3 rounded-full text-white font-bold" style={{ background: "var(--gradient-primary)" }}>
                {busy ? "…" : "Rejoindre"}
              </button>
            </div>
          </section>
        )}

        {tab === "mine" && (
          <section className="space-y-3">
            <div className="grid grid-cols-2 gap-2">
              <TabBtn label={`🎮 En cours (${mine.ongoing.length})`} active={mineTab === "ongoing"} onClick={() => setMineTab("ongoing")} />
              <TabBtn label={`🏁 Terminées (${mine.finished.length})`} active={mineTab === "finished"} onClick={() => setMineTab("finished")} />
            </div>
            {mineTab === "ongoing" && (
              <div className="space-y-3">
                {mine.ongoing.length === 0 && <div className="rounded-3xl bg-card p-6 text-center text-muted-foreground">Aucune partie en cours.</div>}
                {mine.ongoing.map((g: any) => (
                  <div key={g.id} className="rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm hover:border-primary/20 transition-colors">
                    <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${g.status === "open" ? "bg-amber-500/10 border border-amber-500/15" : "bg-primary/10 border border-primary/15"}`}>
                      {g.status === "open" ? "⏳" : "🎮"}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="font-bold text-sm">{g.status === "open" ? "En attente" : "Partie en cours"}</div>
                      <div className="flex items-center gap-2 mt-0.5">
                        <span className="text-[11px] text-muted-foreground">Mise {Number(g.stake || 0).toLocaleString("fr-FR")} Ar</span>
                        {g.is_private && g.room_code && (
                          <span className="text-[10px] font-mono text-muted-foreground/60 bg-white/5 px-1.5 py-0.5 rounded">{g.room_code}</span>
                        )}
                      </div>
                    </div>
                    <button onClick={() => goTo(g.id)}
                      className="flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-xs shadow-md shadow-primary/20 active:scale-95 transition-all shrink-0">
                      <RotateCw className="w-3.5 h-3.5" /> Reprendre
                    </button>
                  </div>
                ))}
              </div>
            )}
            {mineTab === "finished" && (
              <div className="space-y-3">
                {mine.finished.length === 0 && <div className="rounded-3xl bg-card p-6 text-center text-muted-foreground">Aucune partie terminée.</div>}
                {mine.finished.map((g: any) => (
                  <div key={g.id} className="rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm">
                    <div className={`w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0 border ${g.won ? "bg-amber-500/10 border-amber-500/20" : g.forfeited ? "bg-destructive/8 border-destructive/15" : "bg-white/5 border-white/8"}`}>
                      {g.won ? "🏆" : g.forfeited ? "🏳️" : "💔"}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className={`font-bold text-sm ${g.won ? "text-amber-500" : g.forfeited ? "text-destructive" : ""}`}>
                        {g.won ? "Victoire" : g.forfeited ? "Forfait" : "Défaite"}
                      </div>
                      <div className="text-[11px] text-muted-foreground mt-0.5">
                        {Number(g.stake || 0).toLocaleString("fr-FR")} Ar · {Number(g.pot || 0).toLocaleString("fr-FR")} Ar pot
                      </div>
                    </div>
                    <div className="text-[10px] text-muted-foreground/50 shrink-0 text-right">
                      {g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : ""}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </section>
        )}
        </div>
      </div>


      <BottomSheet open={sheet === "opponent"} onClose={closeSheet} title="Adversaire">
        <ModeBlock options={[{ v: "bot", l: "🤖 Solo" }, { v: "friends", l: "👥 Groupe" }]} value={matchType} onChange={(v) => { setMatchType(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "players"} onClose={closeSheet} title="Nombre de joueurs">
        <div className="grid gap-2" style={{ gridTemplateColumns: `repeat(${meta.maxOpts.length}, minmax(0,1fr))` }}>
          {meta.maxOpts.map(n => (
            <button key={n} onClick={() => { setMaxP(n); closeSheet(); }}
              className={`py-3 rounded-xl font-bold ${maxP === n ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-secondary"}`}>
              <div className="text-lg">{n}</div>
              <div className="text-[10px] uppercase opacity-70">Joueurs</div>
            </button>
          ))}
        </div>
      </BottomSheet>
      <BottomSheet open={sheet === "stake"} onClose={closeSheet} title="Mise (Ariary)">
        <StakePicker stake={stake} setStake={setStake} onDone={closeSheet} />
      </BottomSheet>
      <BottomSheet open={sheet === "ludo_mode"} onClose={closeSheet} title="Mode de jeu">
        <ModeBlock options={[{ v: "classic", l: "Classique" }, { v: "fast", l: "Rapide" }]} value={mode} onChange={(v) => { setMode(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "domino_mode"} onClose={closeSheet} title="Format">
        <div className="space-y-2">
          <ModeBlock options={[{ v: "direct", l: "Victoire directe" }, { v: "points", l: "Par points" }]} value={mode} onChange={(v) => setMode(v as any)} />
          {mode === "points" && <TargetScorePicker value={targetScore} onChange={setTargetScore} />}
          <button onClick={closeSheet} className="w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm">Valider</button>
        </div>
      </BottomSheet>
      <BottomSheet open={sheet === "domino_draw"} onClose={closeSheet} title="Pioche">
        <ModeBlock options={[{ v: "with", l: "Avec pioche" }, { v: "without", l: "Sans pioche" }]} value={drawMode} onChange={(v) => { setDrawMode(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "domino_first"} onClose={closeSheet} title="Premier coup">
        <ModeBlock options={[{ v: "libre", l: "Libre" }, { v: "under6", l: "1er domino <6" }]} value={firstTileRule} onChange={(v) => { setFirstTileRule(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "fanorona"} onClose={closeSheet} title="Fanorona">
        <FanoronaConfigBlock variant={fanoronaVariant} onVariant={setFanoronaVariant} mandatory={fanoronaMandatory} onMandatory={setFanoronaMandatory} />
        <button onClick={closeSheet} className="mt-3 w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm">Valider</button>
      </BottomSheet>
      <BottomSheet open={sheet === "rami"} onClose={closeSheet} title="Mode Joker">
        <RamiJokerBlock value={ramiJokerMode} onChange={(v) => { setRamiJokerMode(v); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "rami_mode"} onClose={closeSheet} title="Mode de jeu">
        <RamiGameModeBlock value={ramiGameMode} onChange={(v) => { setRamiGameMode(v); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "rami_diff"} onClose={closeSheet} title="Niveau des bots">
        <ModeBlock columns={3} options={[
          { v: "easy", l: "⭐", sub: "Facile" },
          { v: "medium", l: "⭐⭐", sub: "Moyen" },
          { v: "hard", l: "⭐⭐⭐", sub: "Difficile" },
        ]} value={ramiBotDifficulty} onChange={(v) => { setRamiBotDifficulty(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "poker_blinds"} onClose={closeSheet} title="Blindes (petite / grosse)">
        <ModeBlock columns={2} options={[
          { v: "10", l: "10 / 20", sub: "Micro" },
          { v: "25", l: "25 / 50", sub: "Basse" },
          { v: "50", l: "50 / 100", sub: "Moyenne" },
          { v: "100", l: "100 / 200", sub: "Haute" },
        ]} value={String(pokerBlinds.sb)} onChange={(v) => {
          const sb = Number(v);
          setPokerBlinds({ sb, bb: sb * 2 });
          setPokerBuyIn((b) => Math.max(b, sb * 2 * 20));
          closeSheet();
        }} />
      </BottomSheet>
      <BottomSheet open={sheet === "poker_buyin"} onClose={closeSheet} title="Cave de départ (jetons)">
        <ModeBlock columns={2} options={[
          { v: String(pokerBlinds.bb * 20), l: `${(pokerBlinds.bb * 20).toLocaleString("fr-FR")}`, sub: "20 BB" },
          { v: String(pokerBlinds.bb * 50), l: `${(pokerBlinds.bb * 50).toLocaleString("fr-FR")}`, sub: "50 BB" },
          { v: String(pokerBlinds.bb * 100), l: `${(pokerBlinds.bb * 100).toLocaleString("fr-FR")}`, sub: "100 BB" },
          { v: String(pokerBlinds.bb * 200), l: `${(pokerBlinds.bb * 200).toLocaleString("fr-FR")}`, sub: "200 BB" },
        ]} value={String(pokerBuyIn)} onChange={(v) => { setPokerBuyIn(Number(v)); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "chess_diff"} onClose={closeSheet} title="Difficulté du bot">
        <ModeBlock columns={5} options={[
          { v: "very_easy", l: "⭐", sub: "600" },
          { v: "easy", l: "⭐⭐", sub: "900" },
          { v: "medium", l: "⭐⭐⭐", sub: "1200" },
          { v: "hard", l: "⭐⭐⭐⭐", sub: "1700" },
          { v: "expert", l: "⭐⭐⭐⭐⭐", sub: "2200" },
        ]} value={chessBotDifficulty} onChange={(v) => { setChessBotDifficulty(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "chess_color"} onClose={closeSheet} title="Ta couleur">
        <ModeBlock options={[{ v: "white", l: "⚪ Blancs" }, { v: "black", l: "⚫ Noirs" }]} value={chessBotColor} onChange={(v) => { setChessBotColor(v as any); closeSheet(); }} />
      </BottomSheet>
      <BottomSheet open={sheet === "chess_time"} onClose={closeSheet} title="Temps par joueur">
        <ChessTimePicker value={chessTime} onChange={setChessTime} />
        <button onClick={closeSheet} className="mt-3 w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm">Valider</button>
      </BottomSheet>

      <AdminRenameDialog
        open={renameOpen}
        defaultName={profile?.pseudo || ""}
        onCancel={() => { setRenameOpen(false); setPendingAction(null); }}
        onConfirm={async (name) => {
          setRenameOpen(false);
          const action = pendingAction; setPendingAction(null);
          if (action) await action(name);
        }}
      />
    </main>
  );
}

function SummaryRow({ icon, label, value, onClick }: { icon: React.ReactNode; label: string; value: string; onClick: () => void }) {
  return (
    <button onClick={onClick} className="w-full flex items-center gap-3 px-3 py-3 active:bg-white/5 transition rounded-xl">
      <span className="text-lg leading-none w-6 text-center shrink-0">{icon}</span>
      <span className="text-[13px] font-semibold text-foreground/80 shrink-0">{label}</span>
      <span className="flex-1" />
      <span className="text-[13px] font-bold text-foreground truncate max-w-[55%] text-right">{value}</span>
      <span className="text-muted-foreground/60 text-lg leading-none shrink-0">›</span>
    </button>
  );
}

function BottomSheet({ open, onClose, title, children }: { open: boolean; onClose: () => void; title: string; children: React.ReactNode }) {
  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center" onClick={onClose}>
      <div className="absolute inset-0 bg-black/50 backdrop-blur-sm" />
      <div
        className="relative w-full sm:max-w-md bg-card rounded-t-3xl sm:rounded-3xl p-4 space-y-3 max-h-[80dvh] overflow-y-auto border-t border-white/10 shadow-2xl"
        onClick={e => e.stopPropagation()}
        style={{ animation: "slideUp 200ms ease-out" }}
      >
        <div className="flex items-center justify-between">
          <div className="font-bold text-base">{title}</div>
          <button onClick={onClose} aria-label="Fermer" className="w-8 h-8 rounded-full bg-secondary flex items-center justify-center text-lg leading-none">×</button>
        </div>
        {children}
      </div>
    </div>
  );
}

function StakePicker({ stake, setStake, onDone }: { stake: number; setStake: (n: number) => void; onDone: () => void }) {
  const [custom, setCustom] = useState(!STAKES.includes(stake));
  return (
    <div className="space-y-3">
      <div className="flex justify-end">
        <button onClick={() => setCustom(c => !c)} className="text-[11px] font-semibold text-primary">{custom ? "Préréglages" : "Saisie libre"}</button>
      </div>
      {custom ? (
        <input type="number" min={0} value={stake} onChange={e => setStake(Math.max(0, Number(e.target.value) || 0))}
          placeholder="Montant en Ariary"
          className="w-full px-4 py-3 rounded-xl bg-secondary outline-none text-center font-bold text-lg" />
      ) : (
        <div className="grid grid-cols-3 gap-2">
          {STAKES.map(s => (
            <button key={s} onClick={() => setStake(s)}
              className={`py-3 rounded-xl font-bold text-sm ${stake === s ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-secondary"}`}>
              {s >= 1000 ? `${s / 1000}k` : s} Ar
            </button>
          ))}
        </div>
      )}
      <button onClick={onDone} className="w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm">Valider</button>
    </div>
  );
}

function TabBtn({ label, active, onClick, icon }: { label: string; active: boolean; onClick: () => void; icon?: React.ReactNode }) {
  return (
    <button onClick={onClick}
      className={`px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] ${
        active ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-card border border-white/8 text-muted-foreground hover:text-foreground hover:bg-card/80"
      }`}>
      {icon}<span className="truncate">{label}</span>
    </button>
  );
}

function VisibilityBadge({ kind }: { kind: "public" | "private-code" | "solo" }) {
  const cfg = kind === "public"
    ? { icon: "🌐", label: "Partie publique", desc: "Visible par tous dans « Parties ouvertes ».", cls: "bg-emerald-500/10 border-emerald-500/25 text-emerald-500" }
    : kind === "solo"
    ? { icon: "🤖", label: "Partie solo (privée)", desc: "Visible uniquement par toi.", cls: "bg-sky-500/10 border-sky-500/25 text-sky-500" }
    : { icon: "🔒", label: "Partie privée", desc: "Accessible uniquement via le code d'invitation.", cls: "bg-orange-500/10 border-orange-500/25 text-orange-500" };
  return (
    <div className={`rounded-xl border px-3 py-2 flex items-center gap-2.5 ${cfg.cls}`}>
      <span className="text-base leading-none">{cfg.icon}</span>
      <div className="min-w-0 flex-1">
        <div className="text-[11px] font-bold leading-tight">{cfg.label}</div>
        <div className="text-[10px] opacity-80 leading-tight mt-0.5">{cfg.desc}</div>
      </div>
    </div>
  );
}

function ModeBlock({ options, value, onChange, title, columns }: { options: { v: string; l: string; sub?: string }[]; value: string; onChange: (v: string) => void; title?: string; columns?: number }) {
  const cols = columns ?? 2;
  return (
    <div className="rounded-2xl bg-card border border-white/6 p-2.5 shadow-sm">
      <div className="text-[10px] font-bold uppercase tracking-widest text-foreground/70 mb-1.5">{title ?? "Mode"}</div>
      <div className="grid gap-1.5" style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}>
        {options.map(m => (
          <button key={m.v} onClick={() => onChange(m.v)}
            className={`min-w-0 py-1.5 px-1 rounded-lg font-semibold text-xs transition-all active:scale-[0.97] border ${
              value === m.v
                ? "bg-primary text-primary-foreground border-primary/0 shadow-md shadow-primary/20"
                : "bg-secondary border-white/6 text-muted-foreground hover:text-foreground"
            }`}>
            <div className="leading-tight truncate">{m.l}</div>
            {m.sub && (
              <div className={`text-[9px] mt-0.5 font-normal leading-tight truncate ${value === m.v ? "opacity-85" : "opacity-70"}`}>{m.sub}</div>
            )}
          </button>
        ))}
      </div>
    </div>
  );
}


function TargetScorePicker({ value, onChange }: { value: number; onChange: (n: number) => void }) {
  const presets = [10, 20, 30, 40, 50];
  const [custom, setCustom] = useState(!presets.includes(value));
  return (
    <div className="rounded-3xl bg-card p-4 shadow-sm">
      <div className="font-bold mb-2 flex items-center gap-2 justify-between">
        <span className="flex items-center gap-2"><Target className="w-4 h-4" /> Score cible</span>
        <button onClick={() => setCustom(c => !c)} className="text-xs font-semibold text-primary">
          {custom ? "Préréglages" : "Saisie libre"}
        </button>
      </div>
      {custom ? (
        <input type="number" min={1} max={1000} value={value}
          onChange={e => onChange(Math.max(1, Number(e.target.value) || 0))}
          className="w-full px-4 py-3 rounded-2xl bg-secondary outline-none font-bold text-lg text-center" />
      ) : (
        <div className="grid grid-cols-5 gap-2">
          {presets.map(n => (
            <button key={n} onClick={() => onChange(n)}
              className={`py-2.5 rounded-2xl font-bold text-sm ${value === n ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
              {n}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

function SettingsPanel({ maxP, setMaxP, stake, setStake, commission, showMaxP, meta, hideStake }: any) {
  const [custom, setCustom] = useState(false);
  return (
    <div className="rounded-2xl bg-card border border-white/6 p-3 shadow-md space-y-2.5">
      {showMaxP && (
        <div>
          <div className="font-bold mb-1.5 flex items-center gap-1.5 text-xs"><Users className="w-3.5 h-3.5" /> Joueurs</div>
          <div className={`grid gap-1.5`} style={{ gridTemplateColumns: `repeat(${meta.maxOpts.length}, minmax(0, 1fr))` }}>
            {meta.maxOpts.map((n: number) => (
              <button key={n} onClick={() => setMaxP(n)} className={`py-1.5 rounded-lg font-bold transition-all active:scale-95 border ${maxP === n ? "bg-primary text-primary-foreground border-primary/0 shadow-md shadow-primary/20" : "bg-secondary border-white/6 text-muted-foreground hover:text-foreground"}`}>
                <div className="text-base leading-tight">{n}</div>
                <div className="text-[9px] uppercase opacity-70 leading-tight">Joueurs</div>
              </button>
            ))}
          </div>
        </div>
      )}
      {!hideStake && (
      <div>
        <div className="font-bold mb-1.5 flex items-center gap-1.5 justify-between text-xs">
          <span className="flex items-center gap-1.5"><Coins className="w-3.5 h-3.5" /> Mise (Ar)</span>
          <button onClick={() => setCustom((c: boolean) => !c)} className="text-[11px] font-semibold text-primary">{custom ? "Préréglages" : "Saisie libre"}</button>
        </div>
        {custom ? (
          <input type="number" min={0} value={stake} onChange={e => setStake(Math.max(0, Number(e.target.value) || 0))}
            placeholder="Montant en Ariary"
            className="w-full px-3 py-2 rounded-xl bg-secondary outline-none text-center font-bold text-base" />
        ) : (
          <div className="grid grid-cols-3 gap-1.5">
            {STAKES.map(s => (
              <button key={s} onClick={() => setStake(s)} className={`py-1.5 rounded-lg font-bold text-xs transition-all active:scale-95 border ${stake === s ? "bg-primary text-primary-foreground border-primary/0 shadow-sm shadow-primary/15" : "bg-secondary border-white/6 text-muted-foreground hover:text-foreground"}`}>
                {s === 0 ? "Gratuit" : `${s >= 1000 ? (s/1000)+"k" : s} Ar`}
              </button>
            ))}
          </div>
        )}
      </div>
      )}
      {!hideStake && (stake > 0 ? (
        <div className="grid grid-cols-2 gap-1.5 text-xs">
          <div className="rounded-lg bg-amber-500/8 border border-amber-500/15 p-1.5 text-center">
            <div className="text-[9px] text-amber-500/70 uppercase tracking-wider font-semibold">Cagnotte</div>
            <div className="font-extrabold text-sm">{(stake * maxP).toLocaleString("fr-FR")} Ar</div>
          </div>
          <div className="rounded-lg bg-emerald-500/8 border border-emerald-500/15 p-1.5 text-center">
            <div className="text-[9px] text-emerald-500/70 uppercase tracking-wider font-semibold">Gain net</div>
            <div className="font-extrabold text-sm text-emerald-500">{Math.round(stake * maxP * (100 - commission) / 100).toLocaleString("fr-FR")} Ar</div>
          </div>
        </div>
      ) : (
        <div className="rounded-lg bg-emerald-500/10 border border-emerald-500/30 p-1.5 text-center text-xs font-semibold text-emerald-700 dark:text-emerald-400">
          🎉 Mode gratuit
        </div>
      ))}
    </div>

  );
}

function GameRow({ g, onJoin, slug }: { g: any; onJoin: () => void; slug: Slug }) {
  const emoji: Record<string, string> = { ludo:"🎲", domino:"🁣", fanorona:"⚫", chess:"♟️", rami:"🃏", poker:"🂡" };
  const playersCount = g.players_count ?? 0;
  const maxPlayers = g.max_players ?? 2;
  const isPrivate = !!g.is_private;
  const canDirectJoin = !isPrivate;
  return (
    <div className="rounded-2xl bg-card border border-white/6 p-3.5 shadow-sm flex items-center gap-3 hover:border-primary/20 transition-colors">
      <div className="w-11 h-11 rounded-xl bg-primary/8 border border-primary/15 flex items-center justify-center text-xl shrink-0">
        {emoji[slug] ?? "🎮"}
      </div>
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2 flex-wrap">
          <span className="font-extrabold text-sm">{Number(g.stake || 0).toLocaleString("fr-FR")} Ar</span>
          {Number(g.pot || 0) > 0 && (
            <span className="text-[10px] text-emerald-500 font-semibold bg-emerald-500/10 px-1.5 py-0.5 rounded-full border border-emerald-500/15">
              cagnotte {Number(g.pot || 0).toLocaleString("fr-FR")} Ar
            </span>
          )}
          {isPrivate ? (
            <span className="text-[10px] font-semibold text-orange-400 bg-orange-500/10 px-1.5 py-0.5 rounded-full border border-orange-500/15">🔒 Privée</span>
          ) : (
            <span className="text-[10px] font-semibold text-sky-400 bg-sky-500/10 px-1.5 py-0.5 rounded-full border border-sky-500/15">🌐 Publique</span>
          )}
        </div>
        <div className="flex items-center gap-2 mt-1">
          <div className="flex gap-0.5">
            {Array.from({ length: maxPlayers }).map((_, i) => (
              <div key={i} className={`w-2 h-2 rounded-full ${i < playersCount ? "bg-primary" : "bg-white/15"}`} />
            ))}
          </div>
          <span className="text-[10px] text-muted-foreground">{playersCount}/{maxPlayers} joueurs</span>
        </div>
      </div>
      {canDirectJoin ? (
        <button onClick={onJoin}
          className="flex items-center gap-1.5 px-4 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-sm shadow-md shadow-primary/20 hover:opacity-90 active:scale-95 transition-all shrink-0">
          <Plus className="w-3.5 h-3.5" /> Rejoindre
        </button>
      ) : (
        <span className="flex items-center gap-1 px-3 py-2.5 rounded-xl bg-secondary border border-white/10 text-muted-foreground font-semibold text-xs shrink-0">
          🔒 Code requis
        </span>
      )}
    </div>
  );
}

function FanoronaConfigBlock({ variant, onVariant, mandatory, onMandatory }: {
  variant: "telo" | "dimy" | "tsivy"; onVariant: (v: "telo" | "dimy" | "tsivy") => void;
  mandatory: boolean; onMandatory: (b: boolean) => void;
}) {
  const variants: { v: "telo" | "dimy" | "tsivy"; l: string; d: string }[] = [
    { v: "telo",  l: "Telo (3×3)",  d: "9 cases" },
    { v: "dimy",  l: "Dimy (5×5)",  d: "25 cases" },
    { v: "tsivy", l: "Tsivy (9×5)", d: "45 cases · classique" },
  ];
  return (
    <div className="rounded-3xl bg-card p-4 shadow-sm space-y-3">
      <div>
        <div className="font-bold mb-2">Variante du plateau</div>
        <div className="grid grid-cols-3 gap-2">
          {variants.map(x => (
            <button key={x.v} onClick={() => onVariant(x.v)}
              className={`py-2.5 rounded-2xl font-bold text-sm ${variant === x.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
              <div>{x.l}</div>
              <div className="text-[10px] opacity-80 font-normal">{x.d}</div>
            </button>
          ))}
        </div>
      </div>
      <div>
        <div className="font-bold mb-2">Règle de capture</div>
        <div className="grid grid-cols-2 gap-2">
          <button onClick={() => onMandatory(true)}
            className={`py-3 rounded-2xl font-semibold text-sm ${mandatory ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
            Capture obligatoire
          </button>
          <button onClick={() => onMandatory(false)}
            className={`py-3 rounded-2xl font-semibold text-sm ${!mandatory ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
            Capture non obligatoire
          </button>
        </div>
        <div className="text-[11px] text-muted-foreground mt-2">
          L'enchaînement reste actif dans les deux cas.
        </div>
      </div>
    </div>
  );
}

function RamiJokerBlock({ value, onChange }: {
  value: "sans" | "aleatoire" | "classique" | "double";
  onChange: (v: "sans" | "aleatoire" | "classique" | "double") => void;
}) {
  const opts: { v: typeof value; l: string; d: string }[] = [
    { v: "sans", l: "Sans Joker", d: "52 cartes uniquement" },
    { v: "aleatoire", l: "Joker tiré au hasard", d: "Vrai Joker = couleur opposée" },
    { v: "classique", l: "Jokers classiques", d: "4 Jokers du paquet" },
    { v: "double", l: "Double Joker", d: "Classiques + tiré au hasard" },
  ];
  return (
    <div className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2">
      <div className="font-bold mb-1">Mode Joker</div>
      <div className="grid grid-cols-2 gap-2">
        {opts.map(o => (
          <button key={o.v} onClick={() => onChange(o.v)}
            className={`py-2.5 px-2 rounded-2xl font-semibold text-xs text-left ${value === o.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
            <div>{o.l}</div>
            <div className={`text-[10px] mt-0.5 ${value === o.v ? "opacity-90" : "text-muted-foreground"}`}>{o.d}</div>
          </button>
        ))}
      </div>
    </div>
  );
}

function RamiGameModeBlock({ value, onChange }: {
  value: "bordel" | "naturel";
  onChange: (v: "bordel" | "naturel") => void;
}) {
  const opts: { v: "bordel" | "naturel"; l: string; d: string }[] = [
    { v: "bordel", l: "🎉 Mode Bordel", d: "Pose libre, ajout possible dès le début" },
    { v: "naturel", l: "📜 Mode Naturel", d: "1ère pose obligatoire : brelan ou suite de 3+ avant d'ajouter" },
  ];
  return (
    <div className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2">
      <div className="font-bold mb-1">Mode de jeu</div>
      <div className="grid grid-cols-1 gap-2">
        {opts.map(o => (
          <button key={o.v} onClick={() => onChange(o.v)}
            className={`py-3 px-3 rounded-2xl font-semibold text-xs text-left ${value === o.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
            <div>{o.l}</div>
            <div className={`text-[10px] mt-0.5 ${value === o.v ? "opacity-90" : "text-muted-foreground"}`}>{o.d}</div>
          </button>
        ))}
      </div>
    </div>
  );
}

function ChessTimePicker({ value, onChange }: { value: number; onChange: (v: number) => void }) {
  const presets = [3, 5, 10, 999];
  const isPreset = presets.includes(value);
  const [custom, setCustom] = useState<string>(isPreset ? "" : String(value));
  return (
    <div className="rounded-3xl bg-card p-3 shadow-[var(--shadow-soft)] space-y-2">
      <div className="font-bold text-sm">Temps par joueur</div>
      <div className="grid grid-cols-4 gap-1.5">
        {[
          { v: 3, l: "⚡ 3′" },
          { v: 5, l: "🔥 5′" },
          { v: 10, l: "⏱️ 10′" },
          { v: 999, l: "♾️" },
        ].map(o => (
          <button key={o.v} onClick={() => { onChange(o.v); setCustom(""); }}
            className={`py-2 rounded-xl font-bold text-xs transition-all active:scale-95 ${value === o.v && !custom ? "bg-primary text-primary-foreground shadow-sm shadow-primary/20" : "bg-secondary text-foreground"}`}>
            {o.l}
          </button>
        ))}
      </div>
      <div className="flex items-center gap-2 pt-1">
        <span className="text-[11px] text-muted-foreground shrink-0">Perso.</span>
        <input
          type="number" min={1} max={180} inputMode="numeric" placeholder="ex. 15"
          value={custom}
          onChange={(e) => {
            const raw = e.target.value;
            setCustom(raw);
            const n = Math.max(1, Math.min(180, Number(raw) || 0));
            if (n > 0) onChange(n);
          }}
          className={`flex-1 min-w-0 px-3 py-1.5 rounded-lg bg-secondary text-sm font-bold text-center outline-none border ${custom ? "border-primary/40" : "border-transparent"}`}
        />
        <span className="text-[11px] text-muted-foreground shrink-0">min</span>
      </div>
    </div>
  );
}
