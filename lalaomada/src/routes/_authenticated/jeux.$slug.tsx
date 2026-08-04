import { createFileRoute, useNavigate, Link, redirect } from "@tanstack/react-router";
import React, { useEffect, useState } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import ChatRoom from "@/components/ChatRoom";
import { toast } from "sonner";
import { Plus, KeyRound, ArrowLeft, Clock, Trophy, Users, Coins } from "lucide-react";
import ludoCover from "@/assets/games/ludo.asset.json";
import dominoCover from "@/assets/games/domino.asset.json";
import ramiCover from "@/assets/games/rami.asset.json";
import chessCover from "@/assets/games/chess.asset.json";
import fanoronaCover from "@/assets/games/fanorona.asset.json";

const COVER_BY_SLUG: Record<string, string> = {
  ludo: ludoCover.url, domino: dominoCover.url, fanorona: fanoronaCover.url,
  chess: chessCover.url, rami: ramiCover.url,
};

export const Route = createFileRoute("/_authenticated/jeux/$slug")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/nouveau/$slug", params: { slug: params.slug } });
  },
  component: SalonJeu,
  validateSearch: (s: Record<string, unknown>) => ({
    create: s.create ? 1 : undefined,
    join: typeof s.join === "string" ? (s.join as string) : undefined,
  }),
  head: ({ params }) => ({
    meta: [{ title: "Salon de jeu — Lalao MADA" }],
    links: COVER_BY_SLUG[params.slug]
      ? [{ rel: "preload", as: "image", href: COVER_BY_SLUG[params.slug], type: "image/webp" }]
      : [],
  }),
});

const GROUP_NAME_FOR_SLUG: Record<string, string> = {
  ludo: "Groupe Ludo", domino: "Groupe Domino", chess: "Groupe Échec",
  fanorona: "Groupe Fanorona", rami: "Groupe Rami",
};

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
  chess: { w: 1024, h: 1024 }, rami: { w: 1024, h: 1024 },
};
const META: Record<string, { label: string; cover: string; maxOpts: number[]; soon?: boolean }> = {
  ludo: { label: "Ludo", cover: ludoCover.url, maxOpts: [2,3,4] },
  domino: { label: "Domino", cover: dominoCover.url, maxOpts: [2,3] },
  fanorona: { label: "Fanorona", cover: fanoronaCover.url, maxOpts: [2] },
  chess: { label: "Échecs", cover: chessCover.url, maxOpts: [2] },
  rami: { label: "Rami", cover: ramiCover.url, maxOpts: [2,3,4] },
};

function SalonJeu() {
  const { slug } = Route.useParams();
  const search = Route.useSearch();
  const { profile, isAdmin } = useAuth();
  const navigate = useNavigate();
  const meta = META[slug];
  const [roomId, setRoomId] = useState<string | null>(null);
  const [showCreate, setShowCreate] = useState(!!search.create && !!META[slug] && !META[slug].soon);
  const [showJoin, setShowJoin] = useState(false);
  const [stake, setStake] = useState(1000);
  const [maxP, setMaxP] = useState(2);
  const [targetScore, setTargetScore] = useState(0);
  const [mode, setMode] = useState<"direct" | "points">("direct");
  const [opponentMode, setOpponentMode] = useState<"amis" | "bot">("amis");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [openTrn, setOpenTrn] = useState<any[]>([]);
  const [myTrn, setMyTrn] = useState<Set<string>>(new Set());
  const [joiningTrn, setJoiningTrn] = useState<string | null>(null);

  // Load open tournaments for this game
  const loadTrn = React.useCallback(async () => {
    const { data } = await (supabase.from("tournaments") as any)
      .select("id, name, max_players, stake, is_free, registration_closes_at, starts_at")
      .eq("status", "open").eq("is_test", false).eq("game_slug", slug)
      .order("created_at", { ascending: false }).limit(5);
    const list = ((data as any[]) || []).filter((t: any) => {
      const iso = t.registration_closes_at ?? t.starts_at;
      return !iso || new Date(iso).getTime() > Date.now();
    });
    if (list.length) {
      const ids = list.map((t: any) => t.id);
      const { data: regs } = await supabase.from("tournament_registrations")
        .select("tournament_id").in("tournament_id", ids);
      const counts: Record<string, number> = {};
      (regs || []).forEach((r: any) => { counts[r.tournament_id] = (counts[r.tournament_id] || 0) + 1; });
      list.forEach((t: any) => { t.registered_count = counts[t.id] || 0; });
      if (user) {
        const { data: mine } = await supabase.from("tournament_registrations")
          .select("tournament_id").eq("user_id", user.id).in("tournament_id", ids);
        setMyTrn(new Set((mine || []).map((r: any) => r.tournament_id)));
      } else setMyTrn(new Set());
    } else setMyTrn(new Set());
    setOpenTrn(list);
  }, [slug, user]);

  useEffect(() => {
    loadTrn();
    const ch = supabase.channel(`salon-trn:${slug}`)
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournaments" }, () => loadTrn())
      .on("postgres_changes" as any, { event: "*", schema: "public", table: "tournament_registrations" }, () => loadTrn())
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, [slug, loadTrn]);

  const joinTournament = async (trn: any) => {
    if (joiningTrn) return;
    if (myTrn.has(trn.id)) {
      toast.info("Vous êtes déjà inscrit(e) à ce tournoi.");
      navigate({ to: "/tournaments/$id", params: { id: trn.id } });
      return;
    }
    setJoiningTrn(trn.id);
    const toastId = toast.loading("Inscription en cours…");
    try {
      const { error } = await supabase.rpc("tournament_register" as any, { _tid: trn.id } as any);
      if (error) {
        const msg = (error.message || "").toLowerCase();
        if (msg.includes("déjà") || msg.includes("already") || msg.includes("duplicate")) {
          toast.info("Vous êtes déjà inscrit(e) à ce tournoi.", { id: toastId });
          loadTrn();
          navigate({ to: "/tournaments/$id", params: { id: trn.id } });
          return;
        }
        throw error;
      }
      toast.success("Inscription confirmée ! 🎉", { id: toastId });
      loadTrn();
      navigate({ to: "/tournaments/$id", params: { id: trn.id } });
    } catch (e: any) {
      toast.error(e.message || "Impossible de s'inscrire", { id: toastId });
    } finally {
      setJoiningTrn(null);
    }
  };



  useEffect(() => {
    (async () => {
      // Always use the official general group room — never auto-create.
      const target = GROUP_NAME_FOR_SLUG[slug];
      if (!target) return;
      const { data: room } = await supabase.from("chat_rooms" as any)
        .select("id").eq("type", "global").eq("name", target).maybeSingle();
      if (room) setRoomId((room as any).id);
    })();
  }, [slug]);

  // Auto-join when the URL contains a join code (from a Share link).
  useEffect(() => {
    const code = (search as any).join;
    if (!code || !profile?.id) return;
    (async () => {
      setBusy(true);
      try {
        const fn = slug === "ludo" ? "join_game_by_code" : slug === "domino" ? "domino_join_code"
          : slug === "fanorona" ? "fanorona_join_code" : slug === "chess" ? "chess_join_code"
          : "rami_join_code";
        const { data, error } = await supabase.rpc(fn as any, { _code: String(code).toUpperCase() } as any);
        if (error) throw error;
        const route: any = slug === "ludo" ? "/game/$id" : slug === "domino" ? "/domino/$id"
          : slug === "fanorona" ? "/fanorona/$id" : slug === "chess" ? "/chess/$id" : "/rami/$id";
        navigate({ to: route, params: { id: data as string } as any, replace: true });
      } catch (e: any) {
        toast.error(e.message || "Lien d'invitation invalide");
      } finally { setBusy(false); }
    })();
  }, [(search as any).join, profile?.id, slug]);

  if (!meta) return <div className="p-6">Jeu inconnu.</div>;

  const createGame = async () => {
    setBusy(true);
    try {
      let id: string | null = null;
      if (slug === "ludo") {
        const ludoMode = stake === 0 && opponentMode === "amis" ? "fast" : "classic";
        const { data, error } = await supabase.rpc("create_private_game" as any, { _max_players: maxP, _stake: stake, _mode: ludoMode } as any);
        if (error) throw error; id = data as string;
        // Auto-add bots if "vs Bot" mode selected
        if (stake === 0 && opponentMode === "bot" && id) {
          for (let i = 1; i < maxP; i++) {
            const botNames = ["Bot Rado", "Bot Mamy", "Bot Tsy Maty"];
            const { error: botErr } = await supabase.rpc("player_add_bot" as any, { _game_id: id, _bot_name: botNames[i-1] || "Bot" } as any);
            if (botErr) console.warn("Bot add failed:", botErr.message);
          }
        }
      } else if (slug === "domino") {
        const { data, error } = await supabase.rpc("domino_create" as any, { _stake: stake, _max: maxP, _private: true, _mode: mode === "points" ? "points" : "classic", _commission: 10, _target_score: mode === "points" ? targetScore : 0 } as any);
        if (error) throw error; id = data as string;
      } else if (slug === "fanorona") {
        const { data, error } = await supabase.rpc("fanorona_create" as any, { _stake: stake, _private: true, _commission: 10 } as any);
        if (error) throw error; id = data as string;
      } else if (slug === "chess") {
        const { data, error } = await supabase.rpc("chess_create" as any, { _stake: stake, _private: true, _commission: 10 } as any);
        if (error) throw error; id = data as string;
      } else if (slug === "rami") {
        const { data, error } = await supabase.rpc("rami_create" as any, { _stake: stake, _max: maxP, _private: true, _commission: 10 } as any);
        if (error) throw error; id = data as string;
      }
      const route: any = slug === "ludo" ? "/game/$id" : slug === "domino" ? "/domino/$id" : slug === "fanorona" ? "/fanorona/$id" : slug === "chess" ? "/chess/$id" : "/rami/$id";
      navigate({ to: route, params: { id } as any });
    } catch (e: any) { toast.error(e.message); } finally { setBusy(false); }
  };

  const joinByCode = async () => {
    if (!code.trim()) return;
    setBusy(true);
    try {
      const fn = slug === "ludo" ? "join_game_by_code" : slug === "domino" ? "domino_join_code" : slug === "fanorona" ? "fanorona_join_code" : slug === "chess" ? "chess_join_code" : "rami_join_code";
      const { data, error } = await supabase.rpc(fn as any, { _code: code.trim().toUpperCase() } as any);
      if (error) throw error;
      const route: any = slug === "ludo" ? "/game/$id" : slug === "domino" ? "/domino/$id" : slug === "fanorona" ? "/fanorona/$id" : slug === "chess" ? "/chess/$id" : "/rami/$id";
      navigate({ to: route, params: { id: data as string } as any });
    } catch (e: any) { toast.error(e.message || "Code invalide"); } finally { setBusy(false); }
  };

  return (
    <main className="max-w-3xl mx-auto pb-32">
      <div className="relative aspect-[16/10] overflow-hidden bg-secondary">
        <CoverImage src={meta.cover} alt={`Couverture ${meta.label}`} slug={slug} dims={COVER_DIMS[slug] ?? COVER_DIMS.chess} />
        <div className="absolute inset-0 bg-gradient-to-t from-black/80 via-black/20 to-transparent" />
        <Link to="/jeux" className="absolute top-4 left-4 p-2 rounded-full bg-black/40 backdrop-blur text-white"><ArrowLeft className="w-5 h-5" /></Link>
        {meta.soon && (
          <div className="absolute top-4 right-4 px-3 py-1 rounded-full bg-black/70 text-white text-xs font-bold flex items-center gap-1">
            <Clock className="w-3 h-3" /> Bientôt
          </div>
        )}
        <div className="absolute bottom-4 left-4 right-4 text-white">
          <div className="font-extrabold text-2xl drop-shadow-lg">Discussion {meta.label}</div>
          <div className="text-xs opacity-90">Échange avec les autres joueurs</div>
        </div>
      </div>

      {openTrn.length > 0 && (
        <section className="px-3 pt-3">
          <div className="flex items-center justify-between mb-2">
            <h2 className="font-extrabold text-sm flex items-center gap-1.5">
              <Trophy className="w-4 h-4 text-amber-500" /> Tournois ouverts
            </h2>
            <Link to="/tournaments" className="text-[11px] font-bold text-primary">Voir tout →</Link>
          </div>
          <ul className="space-y-2">
            {openTrn.map((trn) => {
              const registered = myTrn.has(trn.id);
              const full = (trn.registered_count ?? 0) >= (trn.max_players ?? 0);
              return (
              <li key={trn.id} className="grid grid-cols-[auto_minmax(0,1fr)_auto] items-center gap-3 rounded-2xl bg-card border border-border p-3">
                <Link to="/tournaments/$id" params={{ id: trn.id }} className="w-10 h-10 rounded-xl bg-amber-500/10 grid place-items-center text-lg shrink-0">🏆</Link>
                <Link to="/tournaments/$id" params={{ id: trn.id }} className="min-w-0">
                  <div className="font-extrabold text-sm truncate">{trn.name}</div>
                  <div className="flex items-center gap-2 mt-0.5 flex-wrap">
                    <span className="flex items-center gap-0.5 text-[10px] text-muted-foreground font-medium">
                      <Users className="w-3 h-3" /> {trn.registered_count ?? 0}/{trn.max_players ?? 0}
                    </span>
                    {trn.is_free ? (
                      <span className="text-[10px] font-bold text-emerald-600">🎁 Gratuit</span>
                    ) : trn.stake > 0 && (
                      <span className="flex items-center gap-0.5 text-[10px] font-bold text-amber-500">
                        <Coins className="w-3 h-3" /> {new Intl.NumberFormat("fr-FR").format(trn.stake)} Ar
                      </span>
                    )}
                  </div>
                </Link>
                {registered ? (
                  <Link to="/tournaments/$id" params={{ id: trn.id }} className="shrink-0 text-[11px] font-bold px-3 py-1.5 rounded-xl bg-emerald-500/15 text-emerald-600 active:scale-95 transition-transform">✓ Inscrit</Link>
                ) : (
                  <button
                    type="button"
                    disabled={joiningTrn === trn.id || full}
                    onClick={() => joinTournament(trn)}
                    className="shrink-0 text-[11px] font-bold px-3 py-1.5 rounded-xl bg-amber-500 text-white active:scale-95 transition-transform disabled:opacity-50"
                  >
                    {joiningTrn === trn.id ? "…" : full ? "Complet" : "Rejoindre"}
                  </button>
                )}
              </li>
              );
            })}

          </ul>
        </section>
      )}

      <div className="px-3 pt-3">
        {roomId ? <ChatRoom roomId={roomId} title={`Salon ${meta.label}`} isAdmin={isAdmin} height="h-[55dvh]" gameSlug={slug} />
          : <div className="p-8 text-center text-muted-foreground">Chargement du salon…</div>}
      </div>


      {!meta.soon && (
        <div className="fixed bottom-0 inset-x-0 z-40 bg-card/95 backdrop-blur border-t border-border p-3 flex gap-2 max-w-3xl mx-auto">
          <button onClick={() => setShowCreate(true)} className="flex-1 py-3 rounded-full text-white font-bold flex items-center justify-center gap-2" style={{ background: "var(--gradient-primary)" }}>
            <Plus className="w-4 h-4" /> Créer une partie
          </button>
          <button onClick={() => setShowJoin(true)} className="flex-1 py-3 rounded-full bg-secondary font-bold flex items-center justify-center gap-2">
            <KeyRound className="w-4 h-4" /> Rejoindre
          </button>
        </div>
      )}
      {meta.soon && (
        <div className="fixed bottom-0 inset-x-0 z-40 bg-card/95 backdrop-blur border-t border-border p-4 max-w-3xl mx-auto text-center text-sm text-muted-foreground">
          🚧 Les parties {meta.label} arrivent bientôt — pour l'instant, profite de la discussion !
        </div>
      )}

      {showCreate && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-end sm:items-center justify-center" onClick={() => setShowCreate(false)}>
          <div className="bg-card rounded-t-3xl sm:rounded-3xl w-full sm:max-w-sm p-5 space-y-3" onClick={e => e.stopPropagation()}>
            <div className="font-bold text-lg">Créer une partie {meta.label}</div>

            <div>
              <div className="text-xs uppercase text-muted-foreground mb-1">Mise (Ar)</div>
              <input type="number" min={0} step={100} value={stake} onChange={e => setStake(Number(e.target.value)||0)}
                className="w-full px-4 py-2.5 rounded-2xl bg-secondary outline-none" />
            </div>

            {slug === "ludo" && stake === 0 && (
              <div>
                <div className="text-xs uppercase text-muted-foreground mb-1">Jouer contre</div>
                <div className="flex gap-2">
                  <button onClick={() => setOpponentMode("amis")} className={`flex-1 py-2.5 rounded-xl font-bold text-sm flex items-center justify-center gap-1.5 ${opponentMode==="amis"?"bg-primary text-primary-foreground":"bg-secondary"}`}>👥 Amis</button>
                  <button onClick={() => setOpponentMode("bot")} className={`flex-1 py-2.5 rounded-xl font-bold text-sm flex items-center justify-center gap-1.5 ${opponentMode==="bot"?"bg-primary text-primary-foreground":"bg-secondary"}`}>🤖 Bot</button>
                </div>
                {opponentMode === "bot" && (
                  <p className="text-[11px] text-muted-foreground mt-1.5">Les bots rempliront automatiquement les places libres.</p>
                )}
                {opponentMode === "amis" && (
                  <p className="text-[11px] text-muted-foreground mt-1.5">Partage le code avec tes amis pour les inviter.</p>
                )}
              </div>
            )}

            {meta.maxOpts.length > 1 && (
              <div>
                <div className="text-xs uppercase text-muted-foreground mb-1">Joueurs</div>
                <div className="flex gap-2">
                  {meta.maxOpts.map(n => (
                    <button key={n} onClick={() => setMaxP(n)}
                      className={`flex-1 py-2 rounded-xl font-bold ${maxP===n?"bg-primary text-primary-foreground":"bg-secondary"}`}>{n}</button>
                  ))}
                </div>
              </div>
            )}

            {slug === "domino" && (
              <>
                <div>
                  <div className="text-xs uppercase text-muted-foreground mb-1">Mode</div>
                  <div className="flex gap-2">
                    <button onClick={() => setMode("direct")} className={`flex-1 py-2 rounded-xl font-bold ${mode==="direct"?"bg-primary text-primary-foreground":"bg-secondary"}`}>Victoire directe</button>
                    <button onClick={() => setMode("points")} className={`flex-1 py-2 rounded-xl font-bold ${mode==="points"?"bg-primary text-primary-foreground":"bg-secondary"}`}>Par points</button>
                  </div>
                </div>
                {mode === "points" && (
                  <div>
                    <div className="text-xs uppercase text-muted-foreground mb-1">Score cible (1-1000)</div>
                    <input type="number" min={1} max={1000} value={targetScore || ""} placeholder="Ex: 100"
                      onChange={e => setTargetScore(Number(e.target.value)||0)}
                      className="w-full px-4 py-2.5 rounded-2xl bg-secondary outline-none" />
                  </div>
                )}
              </>
            )}

            <button disabled={busy || (slug==="domino" && mode==="points" && targetScore<1)} onClick={createGame}
              className="w-full py-3 rounded-full text-white font-bold disabled:opacity-50" style={{ background: "var(--gradient-primary)" }}>
              {busy?"…":"Créer"}
            </button>
          </div>
        </div>
      )}

      {showJoin && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-end sm:items-center justify-center" onClick={() => setShowJoin(false)}>
          <div className="bg-card rounded-t-3xl sm:rounded-3xl w-full sm:max-w-sm p-5 space-y-3" onClick={e => e.stopPropagation()}>
            <div className="font-bold text-lg">Rejoindre avec un code</div>
            <input value={code} onChange={e => setCode(e.target.value.toUpperCase())} maxLength={6}
              placeholder="A1B2C3"
              className="w-full px-4 py-3 rounded-2xl bg-secondary outline-none uppercase tracking-[0.4em] font-mono text-center text-xl" />
            <button onClick={joinByCode} disabled={busy || !code.trim()}
              className="w-full py-3 rounded-full text-white font-bold disabled:opacity-50" style={{ background: "var(--gradient-primary)" }}>
              {busy?"…":"Rejoindre"}
            </button>
          </div>
        </div>
      )}
    </main>
  );
}
