import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { E as Route$2, u as useAuth, F as petanqueCover, t as pokerCover, r as ramiCover, e as chessCover, g as fanoronaCover, h as dominoCover, l as ludoCover, G as COVER_BY_SLUG } from "./router-CRCBvenY.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { A as AdminRenameDialog } from "./AdminRenameDialog-OR2qGOW5.mjs";
import { s as shareNewGameInGroup } from "./share-game-wrpRJpl9.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { a8 as KeyRound, aR as CirclePlay, L as Lock, aK as RotateCw, aS as Target } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "../_libs/radix-ui__react-alert-dialog.mjs";
import "../_libs/radix-ui__react-context.mjs";
import "../_libs/radix-ui__react-compose-refs.mjs";
import "../_libs/radix-ui__react-dialog.mjs";
import "../_libs/radix-ui__primitive.mjs";
import "../_libs/radix-ui__react-id.mjs";
import "../_libs/@radix-ui/react-use-layout-effect+[...].mjs";
import "../_libs/@radix-ui/react-use-controllable-state+[...].mjs";
import "../_libs/@radix-ui/react-use-effect-event+[...].mjs";
import "../_libs/@radix-ui/react-dismissable-layer+[...].mjs";
import "../_libs/radix-ui__react-primitive.mjs";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "../_libs/radix-ui__react-slot.mjs";
import "../_libs/@radix-ui/react-use-callback-ref+[...].mjs";
import "../_libs/radix-ui__react-focus-scope.mjs";
import "../_libs/radix-ui__react-portal.mjs";
import "../_libs/radix-ui__react-presence.mjs";
import "../_libs/radix-ui__react-focus-guards.mjs";
import "../_libs/react-remove-scroll.mjs";
import "tslib";
import "../_libs/react-remove-scroll-bar.mjs";
import "../_libs/react-style-singleton.mjs";
import "../_libs/get-nonce.mjs";
import "../_libs/use-sidecar.mjs";
import "../_libs/use-callback-ref.mjs";
import "../_libs/aria-hidden.mjs";
import "../_libs/clsx.mjs";
import "../_libs/tailwind-merge.mjs";
import "../_libs/class-variance-authority.mjs";
import "../_libs/supabase__supabase-js.mjs";
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "../_libs/supabase__functions-js.mjs";
import "../_libs/ai-sdk__openai-compatible.mjs";
import "../_libs/ai-sdk__provider.mjs";
import "../_libs/ai-sdk__provider-utils.mjs";
import "../_libs/eventsource-parser.mjs";
import "../_libs/zod.mjs";
import "../_libs/ai.mjs";
import "../_libs/ai-sdk__gateway.mjs";
import "../_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "../_libs/opentelemetry__api.mjs";
import "../_libs/isbot.mjs";
const STAKES = [100, 500, 1e3, 2e3, 5e3];
const COVER_PLACEHOLDER = {
  "chess": "data:image/webp;base64,UklGRl4DAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4IMYAAACQBQCdASoUABQAPu1urlIppiQiqAgBMB2JZgCdMoM8An/AQP4/O1m3SRtP5hc+S0w2el8JsAD+6U6Zy+QtijWclNMXaeu4ahVZfYIm9ULhxkALwvYeDhC8s0dU1+UJxS6oMPaM8Q2Gr8g14Erx3NECSpOL9/OSL29y2pRSYTOVXwDqEzYVRJjW7WVTTwRnWUPwAJq6V5ME5/8E9ZL+ht+DxAiFkPplz7B7hMtuMmalrygMYmeWI7/CGS+KuD0Zo+lQFV9/2ABYTVAgcQIAADw/eHBhY2tldCBiZWdpbj0i77u/IiBpZD0iVzVNME1wQ2VoaUh6cmVTek5UY3prYzlkIj8+IDx4OnhtcG1ldGEgeG1sbnM6eD0iYWRvYmU6bnM6bWV0YS8iIHg6eG1wdGs9IlhNUCBDb3JlIDUuNS4wIj4gPHJkZjpSREYgeG1sbnM6cmRmPSJodHRwOi8vd3d3LnczLm9yZy8xOTk5LzAyLzIyLXJkZi1zeW50YXgtbnMjIj4gPHJkZjpEZXNjcmlwdGlvbiByZGY6YWJvdXQ9IiIgeG1sbnM6SXB0YzR4bXBFeHQ9Imh0dHA6Ly9pcHRjLm9yZy9zdGQvSXB0YzR4bXBFeHQvMjAwOC0wMi0yOS8iIHhtbG5zOnBob3Rvc2hvcD0iaHR0cDovL25zLmFkb2JlLmNvbS9waG90b3Nob3AvMS4wLyIgSXB0YzR4bXBFeHQ6RGlnaXRhbFNvdXJjZUZpbGVUeXBlPSJodHRwOi8vY3YuaXB0Yy5vcmcvbmV3c2NvZGVzL2RpZ2l0YWxzb3VyY2V0eXBlL3RyYWluZWRBbGdvcml0aG1pY01lZGlhIiBJcHRjNHhtcEV4dDpEaWdpdGFsU291cmNlVHlwZT0iaHR0cDovL2N2LmlwdGMub3JnL25ld3Njb2Rlcy9kaWdpdGFsc291cmNldHlwZS90cmFpbmVkQWxnb3JpdGhtaWNNZWRpYSIgcGhvdG9zaG9wOkNyZWRpdD0iTWFkZSB3aXRoIEdvb2dsZSBBSSIvPiA8L3JkZjpSREY+IDwveDp4bXBtZXRhPiAgIDw/eHBhY2tldCBlbmQ9InciPz4A",
  "domino": "data:image/webp;base64,UklGRlQDAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4ILwAAAAwBQCdASoUABQAPu1srVIppaQiqAgBMB2JagCsMxmv/gHqybaTlmwhnSGDllKDUM100AD+6U6ZzIefBcCKSkQilO6YaclEBAnrgd2YoV/GjANqn7NTdgK6CKITbDRKFRneGER2IdAhwdoc0imJBWDpAqM83uKddiUhkaVHLvKQk9hjkT/gy8bbbpJkzGf/BsKUP/Bq4NrvtrdM0fvIfPmM2oOvSetosKpBpwaAeFvdROi+/TZRbuBR8GaAAFhNUCBxAgAAPD94cGFja2V0IGJlZ2luPSLvu78iIGlkPSJXNU0wTXBDZWhpSHpyZVN6TlRjemtjOWQiPz4gPHg6eG1wbWV0YSB4bWxuczp4PSJhZG9iZTpuczptZXRhLyIgeDp4bXB0az0iWE1QIENvcmUgNS41LjAiPiA8cmRmOlJERiB4bWxuczpyZGY9Imh0dHA6Ly93d3cudzMub3JnLzE5OTkvMDIvMjItcmRmLXN5bnRheC1ucyMiPiA8cmRmOkRlc2NyaXB0aW9uIHJkZjphYm91dD0iIiB4bWxuczpJcHRjNHhtcEV4dD0iaHR0cDovL2lwdGMub3JnL3N0ZC9JcHRjNHhtcEV4dC8yMDA4LTAyLTI5LyIgeG1sbnM6cGhvdG9zaG9wPSJodHRwOi8vbnMuYWRvYmUuY29tL3Bob3Rvc2hvcC8xLjAvIiBJcHRjNHhtcEV4dDpEaWdpdGFsU291cmNlRmlsZVR5cGU9Imh0dHA6Ly9jdi5pcHRjLm9yZy9uZXdzY29kZXMvZGlnaXRhbHNvdXJjZXR5cGUvdHJhaW5lZEFsZ29yaXRobWljTWVkaWEiIElwdGM0eG1wRXh0OkRpZ2l0YWxTb3VyY2VUeXBlPSJodHRwOi8vY3YuaXB0Yy5vcmcvbmV3c2NvZGVzL2RpZ2l0YWxzb3VyY2V0eXBlL3RyYWluZWRBbGdvcml0aG1pY01lZGlhIiBwaG90b3Nob3A6Q3JlZGl0PSJNYWRlIHdpdGggR29vZ2xlIEFJIi8+IDwvcmRmOlJERj4gPC94OnhtcG1ldGE+ICAgPD94cGFja2V0IGVuZD0idyI/PgA=",
  "fanorona": "data:image/webp;base64,UklGRsgAAABXRUJQVlA4ILwAAABwBQCdASoUABQAPu1ur1IppiQiqAgBMB2JQBOmXRS2YVvntZEak2CwzwtBGcZpROzeXSAAAP62wA0KcQqSscR9O5gJOn9LQJBAq799FyiufdV8GhlL0MtUvr9PRIxiqXSWGt61yJoFzUvm+ysBXyV8YuKjidVdBPnyk+meKRjHXJWIJnD4Fb7970xzChQGGpqFccvmTqyFeZI4vkNezP18bfzo5NY75KzOD5G3uX7YySRgrwjU4pLwBkAAAA==",
  "ludo": "data:image/webp;base64,UklGRgIEAABXRUJQVlA4WAoAAAAoAAAAEwAAEwAASUNDUBgCAAAAAAIYAAAAAAIQAABtbnRyUkdCIFhZWiAAAAAAAAAAAAAAAABhY3NwAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAQAA9tYAAQAAAADTLQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAlkZXNjAAAA8AAAAHRyWFlaAAABZAAAABRnWFlaAAABeAAAABRiWFlaAAABjAAAABRyVFJDAAABoAAAAChnVFJDAAABoAAAAChiVFJDAAABoAAAACh3dHB0AAAByAAAABRjcHJ0AAAB3AAAADxtbHVjAAAAAAAAAAEAAAAMZW5VUwAAAFgAAAAcAHMAUgBHAEIAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAFhZWiAAAAAAAABvogAAOPUAAAOQWFlaIAAAAAAAAGKZAAC3hQAAGNpYWVogAAAAAAAAJKAAAA+EAAC2z3BhcmEAAAAAAAQAAAACZmYAAPKnAAANWQAAE9AAAApbAAAAAAAAAABYWVogAAAAAAAA9tYAAQAAAADTLW1sdWMAAAAAAAAAAQAAAAxlblVTAAAAIAAAABwARwBvAG8AZwBsAGUAIABJAG4AYwAuACAAMgAwADEANlZQOCDMAAAAEAUAnQEqFAAUAD7tbq9SKaYkIqgIATAdiWwAnTMcfQEHQDdxbfftYJYywmuiGw/uYAD+6U6Ua7z5RGgZL5CfvPzOhUef9RGP1yGMEUWxifrBPE+0MVfnK+fczsUBlg7Ztg2ztMolCuX54ryoc+CidYLxqXSLWOqBlpmG766ycjcMxQZC69ROsyJLcOTMH4lFBO3GVvzlJroTpR5ZoOUcqz2bbxoJsRsWUsqY74Uwv27wiKn/UV/zHQbfXUsd5BsmdBedia1O9nwy3AAARVhJRvAAAABNTQAqAAAACAAHAQAABAAAAAEAAAQ4ARAAAgAAAAkAAABiAQEABAAAAAEAAAQoARIAAwAAAAEAAQAAATIAAgAAABQAAABrh2kABAAAAAEAAACGAQ8AAgAAAAcAAAB/AAAAAFBPVC1MWDFUADIwMjY6MDY6MTggMjI6NDc6MDYASFVBV0VJAAAFkggABAAAAAEAAAAAkAQAAgAAABQAAADIkAMAAgAAABQAAADcoAMABAAAAAEAAAQooAIABAAAAAEAAAQ4AAAAADIwMjY6MDY6MTggMjI6NDY6NTcAMjAyNjowNjoxOCAyMjo0Njo1NwA=",
  "rami": "data:image/webp;base64,UklGRlYDAABXRUJQVlA4WAoAAAAEAAAAEwAAEwAAVlA4IL4AAADQBQCdASoUABQAPu1srlIppaQiqAgBMB2JbACdMySzPn/AQPemvn5cyH5eXJN251v1PPpW+LWQAP7sTWhRWXJkiRF49d5If4J/E9pZ2k/+N888A/wyLyDPW21VB0nWNCN7UViNM1MktRPp41nd1ZztvqSG/pD6nHVzZFHR2mf5uUGGoxZJXlHJNbcIJuD+DYUof+CZG1321umaP3kPhsDbaCfpJL5MFR2uz/zC7RJ/hAOahxN/uxgqzwTaoAAAWE1QIHECAAA8P3hwYWNrZXQgYmVnaW49Iu+7vyIgaWQ9Ilc1TTBNcENlaGlIenJlU3pOVGN6a2M5ZCI/PiA8eDp4bXBtZXRhIHhtbG5zOng9ImFkb2JlOm5zOm1ldGEvIiB4OnhtcHRrPSJYTVAgQ29yZSA1LjUuMCI+IDxyZGY6UkRGIHhtbG5zOnJkZj0iaHR0cDovL3d3dy53My5vcmcvMTk5OS8wMi8yMi1yZGYtc3ludGF4LW5zIyI+IDxyZGY6RGVzY3JpcHRpb24gcmRmOmFib3V0PSIiIHhtbG5zOklwdGM0eG1wRXh0PSJodHRwOi8vaXB0Yy5vcmcvc3RkL0lwdGM0eG1wRXh0LzIwMDgtMDItMjkvIiB4bWxuczpwaG90b3Nob3A9Imh0dHA6Ly9ucy5hZG9iZS5jb20vcGhvdG9zaG9wLzEuMC8iIElwdGM0eG1wRXh0OkRpZ2l0YWxTb3VyY2VGaWxlVHlwZT0iaHR0cDovL2N2LmlwdGMub3JnL25ld3Njb2Rlcy9kaWdpdGFsc291cmNldHlwZS90cmFpbmVkQWxnb3JpdGhtaWNNZWRpYSIgSXB0YzR4bXBFeHQ6RGlnaXRhbFNvdXJjZVR5cGU9Imh0dHA6Ly9jdi5pcHRjLm9yZy9uZXdzY29kZXMvZGlnaXRhbHNvdXJjZXR5cGUvdHJhaW5lZEFsZ29yaXRobWljTWVkaWEiIHBob3Rvc2hvcDpDcmVkaXQ9Ik1hZGUgd2l0aCBHb29nbGUgQUkiLz4gPC9yZGY6UkRGPiA8L3g6eG1wbWV0YT4gICA8P3hwYWNrZXQgZW5kPSJ3Ij8+AA=="
};
function CoverImage({
  src,
  alt,
  slug,
  dims
}) {
  const [loaded, setLoaded] = reactExports.useState(false);
  const placeholder = COVER_PLACEHOLDER[slug];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    placeholder && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { "aria-hidden": true, className: "absolute inset-0 bg-cover bg-center scale-110", style: {
      backgroundImage: `url(${placeholder})`,
      filter: "blur(16px)",
      opacity: loaded ? 0 : 1,
      transition: "opacity 300ms ease-out"
    } }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src, alt, width: dims.w, height: dims.h, loading: "lazy", decoding: "async", onLoad: () => setLoaded(true), className: "absolute inset-0 w-full h-full object-cover", style: {
      opacity: loaded ? 1 : 0,
      transition: "opacity 300ms ease-out"
    } })
  ] });
}
const COVER_DIMS = {
  ludo: {
    w: 1080,
    h: 1064
  },
  domino: {
    w: 1024,
    h: 1024
  },
  fanorona: {
    w: 1024,
    h: 1024
  },
  chess: {
    w: 1024,
    h: 1024
  },
  rami: {
    w: 1024,
    h: 1024
  },
  petanque: {
    w: 1024,
    h: 1024
  }
};
const META = {
  ludo: {
    label: "Ludo",
    cover: ludoCover.url,
    maxOpts: [2, 3, 4]
  },
  domino: {
    label: "Domino",
    cover: dominoCover.url,
    maxOpts: [2, 3]
  },
  fanorona: {
    label: "Fanorona",
    cover: fanoronaCover.url,
    maxOpts: [2]
  },
  chess: {
    label: "Échecs",
    cover: chessCover.url,
    maxOpts: [2]
  },
  rami: {
    label: "Rami",
    cover: ramiCover.url,
    maxOpts: [2, 3, 4]
  },
  poker: {
    label: "Poker",
    cover: pokerCover.url,
    maxOpts: [2, 3, 4, 5, 6, 7, 8, 9]
  },
  petanque: {
    label: "Pétanque",
    cover: petanqueCover.url,
    maxOpts: [2]
  }
};
const ROUTE = {
  ludo: "/game/$id",
  domino: "/domino/$id",
  fanorona: "/fanorona/$id",
  chess: "/chess/$id",
  rami: "/rami/$id",
  poker: "/poker/$id",
  petanque: "/petanque/$id"
};
const GAME_TABLE = {
  ludo: "ludo_games",
  domino: "domino_games",
  fanorona: "fanorona_games",
  chess: "chess_games",
  rami: "rami_games",
  poker: "poker_games",
  petanque: "petanque_games"
};
const PART_TABLE = {
  ludo: "ludo_participants",
  domino: "domino_participants",
  fanorona: "fanorona_participants",
  chess: null,
  rami: "rami_participants",
  poker: "poker_players",
  petanque: "petanque_participants"
};
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
function extractGameId(data) {
  const row = Array.isArray(data) ? data[0] : data;
  const value = row && typeof row === "object" ? row.id ?? row.game_id : row;
  return typeof value === "string" && UUID_RE.test(value) ? value : null;
}
function Lobby() {
  const {
    slug: rawSlug
  } = Route$2.useParams();
  const slug = rawSlug;
  const meta = META[slug];
  const {
    profile,
    isAdmin,
    refreshProfile
  } = useAuth();
  const navigate = useNavigate();
  const [tab, setTab] = reactExports.useState("public");
  const [publicGames, setPublicGames] = reactExports.useState([]);
  const [mine, setMine] = reactExports.useState({
    ongoing: [],
    finished: []
  });
  const [mineTab, setMineTab] = reactExports.useState("ongoing");
  const [maxP, setMaxP] = reactExports.useState(meta?.maxOpts[0] ?? 2);
  const [stake, setStake] = reactExports.useState(1e3);
  const [mode, setMode] = reactExports.useState("classic");
  const [ludoAutoMove, setLudoAutoMove] = reactExports.useState(true);
  const [matchType, setMatchType] = reactExports.useState("friends");
  const [drawMode, setDrawMode] = reactExports.useState("with");
  const [firstTileRule, setFirstTileRule] = reactExports.useState("libre");
  const [targetScore, setTargetScore] = reactExports.useState(100);
  const [fanoronaVariant, setFanoronaVariant] = reactExports.useState("tsivy");
  const [fanoronaMandatory, setFanoronaMandatory] = reactExports.useState(true);
  const [ramiJokerMode, setRamiJokerMode] = reactExports.useState("sans");
  const [ramiGameMode, setRamiGameMode] = reactExports.useState("bordel");
  const [ramiBotDifficulty, setRamiBotDifficulty] = reactExports.useState("medium");
  const [pokerBlinds, setPokerBlinds] = reactExports.useState({
    sb: 10,
    bb: 20
  });
  const [pokerBuyIn, setPokerBuyIn] = reactExports.useState(2e3);
  const [chessBotDifficulty, setChessBotDifficulty] = reactExports.useState("medium");
  const [chessBotColor, setChessBotColor] = reactExports.useState("white");
  const [chessTime, setChessTime] = reactExports.useState(10);
  const [code, setCode] = reactExports.useState("");
  const [visibility, setVisibility] = reactExports.useState("public");
  const [commission] = reactExports.useState(10);
  const [busy, setBusy] = reactExports.useState(false);
  const [renameOpen, setRenameOpen] = reactExports.useState(false);
  const [pendingAction, setPendingAction] = reactExports.useState(null);
  const [sheet, setSheet] = reactExports.useState(null);
  const closeSheet = () => setSheet(null);
  const supportsPublicJoin = true;
  const checkGuards = (intendedStake) => {
    if (intendedStake <= 0) return true;
    const bal = Number(profile?.balance_ar || 0);
    if (bal < intendedStake) {
      toast.error("Solde insuffisant", {
        description: `Vous avez ${bal.toLocaleString("fr-FR")} Ar. Il vous faut ${intendedStake.toLocaleString("fr-FR")} Ar.`,
        action: {
          label: "Déposer",
          onClick: () => navigate({
            to: "/"
          })
        },
        duration: 8e3
      });
      return false;
    }
    if (!profile?.phone_verified) {
      toast.error("Numéro non vérifié", {
        description: "Vérifiez votre numéro avant de jouer avec une mise.",
        action: {
          label: "Vérifier",
          onClick: () => navigate({
            to: "/profile"
          })
        },
        duration: 8e3
      });
      return false;
    }
    return true;
  };
  const loadPublic = async () => {
    if (slug === "ludo") {
      const {
        data
      } = await supabase.rpc("list_public_open_games");
      setPublicGames(data || []);
    } else {
      const {
        data
      } = await supabase.from(GAME_TABLE[slug]).select("*").eq("status", "open").eq("is_private", false).order("created_at", {
        ascending: false
      }).limit(20);
      setPublicGames(data || []);
    }
  };
  const loadMine = async () => {
    if (!profile?.id) return;
    if (slug === "ludo") {
      const {
        data
      } = await supabase.rpc("my_games");
      setMine(data || {
        ongoing: [],
        finished: []
      });
      return;
    }
    if (slug === "chess") {
      const {
        data
      } = await supabase.from("chess_games").select("*").or(`white_id.eq.${profile.id},black_id.eq.${profile.id}`).order("created_at", {
        ascending: false
      }).limit(60);
      const rows2 = data || [];
      setMine({
        ongoing: rows2.filter((r) => r.status === "open" || r.status === "playing"),
        finished: rows2.filter((r) => r.status === "finished" || r.status === "cancelled").map((r) => ({
          ...r,
          won: r.winner_id === profile.id
        }))
      });
      return;
    }
    const part = PART_TABLE[slug];
    const {
      data: parts
    } = await supabase.from(part).select("*, game:" + GAME_TABLE[slug] + "(*)").eq("user_id", profile.id);
    const rows = parts || [];
    setMine({
      ongoing: rows.filter((r) => r.game?.status === "open" || r.game?.status === "playing").map((r) => ({
        ...r.game,
        my_forfeited: r.forfeited
      })),
      finished: rows.filter((r) => r.game?.status === "finished" || r.game?.status === "cancelled").map((r) => ({
        ...r.game,
        won: r.game?.winner_id === profile?.id,
        forfeited: r.forfeited
      }))
    });
  };
  reactExports.useEffect(() => {
    loadPublic();
    loadMine();
    const ch = supabase.channel("lobby-" + slug).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: GAME_TABLE[slug],
      filter: "status=eq.open"
    }, () => {
      loadPublic();
      loadMine();
    }).subscribe();
    return () => {
      supabase.removeChannel(ch);
    };
  }, [slug, profile?.id]);
  const withAdminRename = (action) => () => {
    action();
  };
  const applyLudoAutoMove = async (gameId) => {
    if (slug !== "ludo" || !gameId) return;
    await supabase.rpc("ludo_set_auto_move", {
      _game_id: gameId,
      _enabled: ludoAutoMove
    });
  };
  const goTo = (value) => {
    const id = extractGameId(value);
    if (!id) {
      toast("Partie créée, mais l'identifiant reçu est invalide. Réessayez depuis vos parties.");
      loadMine();
      return;
    }
    navigate({
      to: ROUTE[slug],
      params: {
        id
      }
    });
  };
  const joinPublicOrCreate = withAdminRename(async (overrideName) => {
    setBusy(true);
    try {
      if (matchType === "friends") {
        await createNewFree(visibility === "private");
        return;
      }
      let id = null;
      if (slug === "ludo") {
        const {
          data,
          error
        } = await supabase.rpc("create_private_game", {
          _max_players: maxP,
          _stake: 0,
          _mode: "classic",
          _match_type: "solo",
          _commission: commission
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        if (overrideName) await supabase.rpc("ludo_set_display_name", {
          _game_id: id,
          _name: overrideName
        });
        await applyLudoAutoMove(id);
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const {
            error: berr
          } = await supabase.rpc("player_add_bot", {
            _game_id: id,
            _bot_name: `Bot ${i + 1}`
          });
          if (berr) throw berr;
        }
        await supabase.rpc("ludo_set_ready", {
          _game_id: id,
          _ready: true
        });
      } else if (slug === "domino") {
        const {
          data,
          error
        } = await supabase.rpc("domino_create", {
          _stake: 0,
          _max: maxP,
          _private: true,
          _mode: mode === "points" ? "points" : "classic",
          _commission: commission,
          _target_score: mode === "points" ? targetScore : 0,
          _draw_mode: drawMode,
          _first_tile_rule: firstTileRule
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const {
            error: berr
          } = await supabase.rpc("domino_add_bot", {
            _game_id: id,
            _bot_name: `Bot ${i + 1}`
          });
          if (berr) throw berr;
        }
        await supabase.rpc("domino_set_ready", {
          _game_id: id,
          _ready: true
        });
      } else if (slug === "chess") {
        const diffMap = {
          very_easy: 1,
          easy: 2,
          medium: 3,
          hard: 4,
          expert: 5
        };
        const {
          data,
          error
        } = await supabase.rpc("chess_create_solo", {
          _difficulty: diffMap[chessBotDifficulty],
          _color: chessBotColor,
          _time_min: chessTime
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else if (slug === "petanque") {
        const {
          data,
          error
        } = await supabase.rpc("petanque_create", {
          p_stake: 0,
          p_public: false
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        const {
          error: berr
        } = await supabase.rpc("petanque_add_bot", {
          _game_id: id
        });
        if (berr) throw berr;
        await supabase.rpc("petanque_set_ready", {
          _game_id: id,
          _ready: true
        });
      } else if (slug === "rami") {
        const {
          data,
          error
        } = await supabase.rpc("rami_start_solo_bot", {
          _max_players: maxP,
          _difficulty: ramiBotDifficulty,
          _joker_mode: ramiJokerMode,
          _game_mode: ramiGameMode
        });
        if (error) throw error;
        id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
      } else {
        await createNewFree(false);
        return;
      }
      if (id) {
        refreshProfile();
        goTo(id);
      }
    } catch (e) {
      toast.error(e.message || "Erreur");
    } finally {
      setBusy(false);
    }
  });
  const createNewFree = async (priv) => {
    try {
      let id = null;
      if (slug === "ludo") {
        const fn = priv ? "create_private_game" : "find_or_create_game";
        const args = priv ? {
          _max_players: maxP,
          _stake: 0,
          _mode: mode === "fast" ? "fast" : "classic",
          _match_type: matchType === "bot" ? "solo" : "groupe",
          _commission: commission
        } : {
          _max_players: maxP,
          _stake: 0,
          _commission: commission
        };
        const {
          data,
          error
        } = await supabase.rpc(fn, args);
        if (error) throw error;
        id = extractGameId(data);
        await applyLudoAutoMove(id);
      } else if (slug === "domino") {
        const {
          data,
          error
        } = await supabase.rpc("domino_create", {
          _stake: 0,
          _max: maxP,
          _private: priv,
          _mode: mode === "points" ? "points" : "classic",
          _commission: commission,
          _target_score: mode === "points" ? targetScore : 0,
          _draw_mode: drawMode,
          _first_tile_rule: firstTileRule
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "fanorona") {
        const {
          data,
          error
        } = await supabase.rpc("fanorona_create", {
          _stake: 0,
          _private: priv,
          _commission: commission,
          _variant: fanoronaVariant,
          _mandatory_capture: fanoronaMandatory
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "chess") {
        const {
          data,
          error
        } = await supabase.rpc("chess_create_friends", {
          _time_min: chessTime
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "rami") {
        const {
          data,
          error
        } = await supabase.rpc("rami_create", {
          _stake: 0,
          _max: maxP,
          _private: priv,
          _commission: commission,
          _joker_mode: ramiJokerMode,
          _game_mode: ramiGameMode
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "poker") {
        const {
          data,
          error
        } = await supabase.rpc("poker_create", {
          _stake: 0,
          _max: maxP,
          _private: priv,
          _commission: commission,
          _small_blind: pokerBlinds.sb,
          _big_blind: pokerBlinds.bb,
          _buy_in: pokerBuyIn
        });
        if (error) throw error;
        id = extractGameId(data);
      } else if (slug === "petanque") {
        const {
          data,
          error
        } = await supabase.rpc("petanque_create", {
          p_stake: 0,
          p_public: !priv
        });
        if (error) throw error;
        id = extractGameId(data);
      }
      if (id) {
        shareNewGameInGroup(slug, id);
        refreshProfile();
        goTo(id);
      }
    } finally {
    }
  };
  const createNew = async (priv) => {
    let id = null;
    if (slug === "ludo") {
      const fn = priv ? "create_private_game" : "find_or_create_game";
      const args = priv ? {
        _max_players: maxP,
        _stake: stake,
        _mode: mode === "fast" ? "fast" : "classic",
        _match_type: matchType === "bot" ? "solo" : "groupe",
        _commission: commission
      } : {
        _max_players: maxP,
        _stake: stake,
        _commission: commission
      };
      const {
        data,
        error
      } = await supabase.rpc(fn, args);
      if (error) throw error;
      id = extractGameId(data);
      await applyLudoAutoMove(id);
    } else if (slug === "domino") {
      const {
        data,
        error
      } = await supabase.rpc("domino_create", {
        _stake: stake,
        _max: maxP,
        _private: priv,
        _mode: mode === "points" ? "points" : "classic",
        _commission: commission,
        _target_score: mode === "points" ? targetScore : 0,
        _draw_mode: drawMode,
        _first_tile_rule: firstTileRule
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "fanorona") {
      const {
        data,
        error
      } = await supabase.rpc("fanorona_create", {
        _stake: stake,
        _private: priv,
        _commission: commission,
        _variant: fanoronaVariant,
        _mandatory_capture: fanoronaMandatory
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "chess") {
      const {
        data,
        error
      } = await supabase.rpc("chess_create_stake", {
        _stake: stake,
        _time_min: chessTime
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "rami") {
      const {
        data,
        error
      } = await supabase.rpc("rami_create", {
        _stake: stake,
        _max: maxP,
        _private: priv,
        _commission: commission,
        _joker_mode: ramiJokerMode,
        _game_mode: ramiGameMode
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "poker") {
      const {
        data,
        error
      } = await supabase.rpc("poker_create", {
        _stake: stake,
        _max: maxP,
        _private: priv,
        _commission: commission,
        _small_blind: pokerBlinds.sb,
        _big_blind: pokerBlinds.bb,
        _buy_in: pokerBuyIn
      });
      if (error) throw error;
      id = extractGameId(data);
    } else if (slug === "petanque") {
      const {
        data,
        error
      } = await supabase.rpc("petanque_create", {
        p_stake: stake,
        p_public: !priv
      });
      if (error) throw error;
      id = extractGameId(data);
    }
    if (id) {
      shareNewGameInGroup(slug, id);
      refreshProfile();
      goTo(id);
    }
  };
  const createPrivate = withAdminRename(async (overrideName) => {
    if (!checkGuards(stake)) return;
    setBusy(true);
    try {
      if (matchType === "bot" && slug === "ludo") {
        const {
          data,
          error
        } = await supabase.rpc("create_private_game", {
          _max_players: maxP,
          _stake: stake,
          _mode: mode === "fast" ? "fast" : "classic",
          _match_type: "solo",
          _commission: commission
        });
        if (error) throw error;
        const id = extractGameId(data);
        if (!id) throw new Error("Identifiant de partie invalide");
        if (overrideName) await supabase.rpc("ludo_set_display_name", {
          _game_id: id,
          _name: overrideName
        });
        await applyLudoAutoMove(id);
        const botsNeeded = Math.max(0, maxP - 1);
        for (let i = 0; i < botsNeeded; i++) {
          const {
            error: berr
          } = await supabase.rpc("player_add_bot", {
            _game_id: id,
            _bot_name: `Bot ${i + 1}`
          });
          if (berr) throw berr;
        }
        await supabase.rpc("ludo_set_ready", {
          _game_id: id,
          _ready: true
        });
        refreshProfile();
        goTo(id);
      } else {
        await createNew(visibility === "private");
      }
    } catch (e) {
      toast.error(e.message || "Erreur");
    } finally {
      setBusy(false);
    }
  });
  const joinByCode = withAdminRename(async () => {
    if (!code.trim()) return;
    setBusy(true);
    try {
      const fn = slug === "ludo" ? "join_game_by_code" : slug === "domino" ? "domino_join_code" : slug === "fanorona" ? "fanorona_join_code" : slug === "chess" ? "chess_join_friends" : slug === "poker" ? "poker_join_code" : slug === "petanque" ? "petanque_join_code" : "rami_join_code";
      const {
        data,
        error
      } = await supabase.rpc(fn, {
        _code: code.trim().toUpperCase()
      });
      if (error) throw error;
      refreshProfile();
      goTo(data);
    } catch (e) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient")) {
        toast.error("Solde insuffisant pour rejoindre cette partie.", {
          action: {
            label: "Déposer",
            onClick: () => navigate({
              to: "/"
            })
          }
        });
      } else {
        toast.error(e.message || "Code invalide");
      }
    } finally {
      setBusy(false);
    }
  });
  if (!meta) return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-6", children: "Jeu inconnu." });
  const showMaxP = meta.maxOpts.length > 1;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-3xl mx-auto h-[100dvh] flex flex-col overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 px-3 pt-2 pb-1.5 shrink-0", children: [
      COVER_BY_SLUG[slug] && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "relative w-12 h-12 rounded-xl overflow-hidden shrink-0 ring-1 ring-primary/30 shadow bg-black/20", children: /* @__PURE__ */ jsxRuntimeExports.jsx(CoverImage, { src: COVER_BY_SLUG[slug], alt: meta.label, slug, dims: COVER_DIMS[slug] ?? {
        w: 1024,
        h: 1024
      } }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "inline-block text-[9px] uppercase tracking-[0.18em] font-bold text-primary px-1.5 py-0.5 rounded bg-primary/10 ring-1 ring-primary/20", children: "Créer une partie" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-lg leading-tight truncate mt-0.5 text-foreground", children: meta.label })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-3 pt-1 pb-3 flex flex-col gap-2 flex-1 min-h-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-4 gap-1.5 shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Gratuit", active: tab === "public", onClick: () => setTab("public"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "🆓" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Mise", active: tab === "private", onClick: () => setTab("private"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "💰" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Code", active: tab === "code", onClick: () => setTab("code"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "🔑" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: "Mes", active: tab === "mine", onClick: () => setTab("mine"), icon: /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm leading-none", children: "📂" }) })
      ] }),
      (tab === "public" && matchType === "friends" || tab === "private" && matchType === "friends") && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-1.5 shrink-0", role: "tablist", "aria-label": "Visibilité", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setVisibility("public"), "aria-pressed": visibility === "public", className: `px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] border ${visibility === "public" ? "bg-emerald-500/15 text-emerald-600 border-emerald-500/40" : "bg-card border-white/8 text-muted-foreground hover:text-foreground"}`, children: [
          "🌐 ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Public" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setVisibility("private"), "aria-pressed": visibility === "private", className: `px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] border ${visibility === "private" ? "bg-orange-500/15 text-orange-600 border-orange-500/40" : "bg-card border-white/8 text-muted-foreground hover:text-foreground"}`, children: [
          "🔒 ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Privé" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-h-0 overflow-y-auto -mx-1 px-1 space-y-2", children: [
        tab === "public" && supportsPublicJoin && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-1.5 shadow-sm divide-y divide-white/5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎯", label: "Adversaire", value: matchType === "bot" ? "🤖 vs Bot" : "👥 vs Amis", onClick: () => setSheet("opponent") }),
            meta.maxOpts.length > 1 && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "👥", label: "Joueurs", value: `${maxP}`, onClick: () => setSheet("players") }),
            slug === "domino" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Format", value: mode === "points" ? `Par points (${targetScore})` : "Victoire directe", onClick: () => setSheet("domino_mode") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🁣", label: "Pioche", value: drawMode === "with" ? "Avec" : "Sans", onClick: () => setSheet("domino_draw") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎬", label: "Premier coup", value: firstTileRule === "libre" ? "Libre" : "1er <6", onClick: () => setSheet("domino_first") })
            ] }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🤖", label: "Déplacement auto", value: ludoAutoMove ? "Activé" : "Désactivé", onClick: () => setLudoAutoMove((v) => !v) }),
            slug === "fanorona" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⚫", label: "Plateau", value: `${fanoronaVariant} · ${fanoronaMandatory ? "obligatoire" : "libre"}`, onClick: () => setSheet("fanorona") }),
            slug === "chess" && matchType === "bot" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⭐", label: "Difficulté", value: {
                very_easy: "⭐ 600",
                easy: "⭐⭐ 900",
                medium: "⭐⭐⭐ 1200",
                hard: "⭐⭐⭐⭐ 1700",
                expert: "⭐⭐⭐⭐⭐ 2200"
              }[chessBotDifficulty], onClick: () => setSheet("chess_diff") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: chessBotColor === "white" ? "⚪" : "⚫", label: "Couleur", value: chessBotColor === "white" ? "Blancs" : "Noirs", onClick: () => setSheet("chess_color") })
            ] }),
            slug === "poker" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🪙", label: "Blindes", value: `${pokerBlinds.sb} / ${pokerBlinds.bb}`, onClick: () => setSheet("poker_blinds") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "💵", label: "Cave (jetons)", value: pokerBuyIn.toLocaleString("fr-FR"), onClick: () => setSheet("poker_buyin") })
            ] }),
            slug === "rami" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🃏", label: "Joker", value: {
                sans: "Sans",
                aleatoire: "Couleur opposée",
                classique: "Classique",
                double: "Double"
              }[ramiJokerMode], onClick: () => setSheet("rami") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "📜", label: "Mode de jeu", value: ramiGameMode === "naturel" ? "Naturel" : "Bordel", onClick: () => setSheet("rami_mode") }),
              matchType === "bot" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⭐", label: "Niveau des bots", value: {
                easy: "⭐ Facile",
                medium: "⭐⭐ Moyen",
                hard: "⭐⭐⭐ Difficile"
              }[ramiBotDifficulty], onClick: () => setSheet("rami_diff") })
            ] }),
            slug === "chess" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⏱️", label: "Temps / joueur", value: chessTime === 999 ? "Illimité" : `${chessTime} min`, onClick: () => setSheet("chess_time") })
          ] }),
          matchType === "friends" && visibility === "private" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-primary/8 border border-primary/20 px-3 py-2 text-[11px] text-primary/90 flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-3.5 h-3.5 shrink-0" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: "Un code d'invitation à 6 caractères sera généré." })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: joinPublicOrCreate, disabled: busy, className: "w-full py-3.5 rounded-full text-white font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-primary/40 active:scale-[0.98] transition-transform sticky bottom-2", style: {
            background: "var(--gradient-primary)"
          }, children: matchType === "friends" ? visibility === "public" ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer la partie"
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer et inviter"
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Commencer la partie"
          ] }) })
        ] }),
        tab === "private" && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-1.5 shadow-sm divide-y divide-white/5", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎯", label: "Adversaire", value: matchType === "bot" ? "🤖 vs Bot" : "👥 vs Amis", onClick: () => setSheet("opponent") }),
            showMaxP && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "👥", label: "Joueurs", value: `${maxP}`, onClick: () => setSheet("players") }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "💰", label: "Mise", value: stake > 0 ? `${stake.toLocaleString("fr-FR")} Ar` : "Gratuit", onClick: () => setSheet("stake") }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Mode", value: mode === "fast" ? "Rapide" : "Classique", onClick: () => setSheet("ludo_mode") }),
            slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🤖", label: "Déplacement auto", value: ludoAutoMove ? "Activé" : "Désactivé", onClick: () => setLudoAutoMove((v) => !v) }),
            slug === "domino" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎲", label: "Format", value: mode === "points" ? `Par points (${targetScore})` : "Victoire directe", onClick: () => setSheet("domino_mode") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🁣", label: "Pioche", value: drawMode === "with" ? "Avec" : "Sans", onClick: () => setSheet("domino_draw") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🎬", label: "Premier coup", value: firstTileRule === "libre" ? "Libre" : "1er <6", onClick: () => setSheet("domino_first") })
            ] }),
            slug === "fanorona" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⚫", label: "Plateau", value: `${fanoronaVariant} · ${fanoronaMandatory ? "obligatoire" : "libre"}`, onClick: () => setSheet("fanorona") }),
            slug === "rami" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🃏", label: "Joker", value: {
                sans: "Sans",
                aleatoire: "Couleur opposée",
                classique: "Classique",
                double: "Double"
              }[ramiJokerMode], onClick: () => setSheet("rami") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "📜", label: "Mode de jeu", value: ramiGameMode === "naturel" ? "Naturel" : "Bordel", onClick: () => setSheet("rami_mode") })
            ] }),
            slug === "poker" && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "🪙", label: "Blindes", value: `${pokerBlinds.sb} / ${pokerBlinds.bb}`, onClick: () => setSheet("poker_blinds") }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "💵", label: "Cave (jetons)", value: pokerBuyIn.toLocaleString("fr-FR"), onClick: () => setSheet("poker_buyin") })
            ] }),
            slug === "chess" && /* @__PURE__ */ jsxRuntimeExports.jsx(SummaryRow, { icon: "⏱️", label: "Temps / joueur", value: chessTime === 999 ? "Illimité" : `${chessTime} min`, onClick: () => setSheet("chess_time") })
          ] }),
          stake > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-1.5 text-xs", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-amber-500/8 border border-amber-500/20 p-2 text-center", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] text-amber-500/80 uppercase tracking-wider font-bold", children: "Cagnotte" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm", children: [
                (stake * maxP).toLocaleString("fr-FR"),
                " Ar"
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-emerald-500/10 border border-emerald-500/25 p-2 text-center", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[9px] text-emerald-600/90 uppercase tracking-wider font-bold", children: "Gain net" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm text-emerald-600", children: [
                Math.round(stake * maxP * (100 - commission) / 100).toLocaleString("fr-FR"),
                " Ar"
              ] })
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: createPrivate, disabled: busy || slug === "domino" && mode === "points" && targetScore < 1, className: "w-full py-3.5 rounded-full text-white font-bold text-sm flex items-center justify-center gap-2 shadow-lg shadow-primary/40 active:scale-[0.98] transition-transform sticky bottom-2", style: {
            background: "var(--gradient-primary)"
          }, children: matchType === "bot" && slug === "ludo" ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Commencer la partie"
          ] }) : visibility === "public" ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CirclePlay, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer la partie"
          ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-4 h-4" }),
            " ",
            busy ? "…" : "Créer la partie privée"
          ] }) }),
          visibility === "private" && (slug !== "ludo" || matchType === "friends") && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground text-center", children: "Un code à 6 caractères sera généré pour inviter tes amis." })
        ] }),
        tab === "code" && /* @__PURE__ */ jsxRuntimeExports.jsx("section", { className: "space-y-3", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-5 shadow-md space-y-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 rounded-lg bg-primary/15 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx(KeyRound, { className: "w-4 h-4 text-primary" }) }),
            "Code de la partie"
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: code, onChange: (e) => setCode(e.target.value.toUpperCase()), placeholder: "EX: A1B2C3", maxLength: 6, className: "w-full px-4 py-3 rounded-2xl bg-secondary border border-border outline-none uppercase tracking-[0.4em] font-mono text-center text-xl" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: joinByCode, disabled: busy || !code.trim(), className: "w-full py-3 rounded-full text-white font-bold", style: {
            background: "var(--gradient-primary)"
          }, children: busy ? "…" : "Rejoindre" })
        ] }) }),
        tab === "mine" && /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-3", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: `🎮 En cours (${mine.ongoing.length})`, active: mineTab === "ongoing", onClick: () => setMineTab("ongoing") }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(TabBtn, { label: `🏁 Terminées (${mine.finished.length})`, active: mineTab === "finished", onClick: () => setMineTab("finished") })
          ] }),
          mineTab === "ongoing" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
            mine.ongoing.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Aucune partie en cours." }),
            mine.ongoing.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm hover:border-primary/20 transition-colors", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${g.status === "open" ? "bg-amber-500/10 border border-amber-500/15" : "bg-primary/10 border border-primary/15"}`, children: g.status === "open" ? "⏳" : "🎮" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: g.status === "open" ? "En attente" : "Partie en cours" }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-0.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] text-muted-foreground", children: [
                    "Mise ",
                    Number(g.stake || 0).toLocaleString("fr-FR"),
                    " Ar"
                  ] }),
                  g.is_private && g.room_code && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-mono text-muted-foreground/60 bg-white/5 px-1.5 py-0.5 rounded", children: g.room_code })
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => goTo(g.id), className: "flex items-center gap-1.5 px-3.5 py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-xs shadow-md shadow-primary/20 active:scale-95 transition-all shrink-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(RotateCw, { className: "w-3.5 h-3.5" }),
                " Reprendre"
              ] })
            ] }, g.id))
          ] }),
          mineTab === "finished" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
            mine.finished.length === 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-3xl bg-card p-6 text-center text-muted-foreground", children: "Aucune partie terminée." }),
            mine.finished.map((g) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-3.5 flex items-center gap-3 shadow-sm", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-xl shrink-0 border ${g.won ? "bg-amber-500/10 border-amber-500/20" : g.forfeited ? "bg-destructive/8 border-destructive/15" : "bg-white/5 border-white/8"}`, children: g.won ? "🏆" : g.forfeited ? "🏳️" : "💔" }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `font-bold text-sm ${g.won ? "text-amber-500" : g.forfeited ? "text-destructive" : ""}`, children: g.won ? "Victoire" : g.forfeited ? "Forfait" : "Défaite" }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
                  Number(g.stake || 0).toLocaleString("fr-FR"),
                  " Ar · ",
                  Number(g.pot || 0).toLocaleString("fr-FR"),
                  " Ar pot"
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground/50 shrink-0 text-right", children: g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : "" })
            ] }, g.id))
          ] })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "opponent", onClose: closeSheet, title: "Adversaire", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "bot",
      l: "🤖 vs Bot"
    }, {
      v: "friends",
      l: "👥 vs Amis"
    }], value: matchType, onChange: (v) => {
      setMatchType(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "players", onClose: closeSheet, title: "Nombre de joueurs", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid gap-2", style: {
      gridTemplateColumns: `repeat(${meta.maxOpts.length}, minmax(0,1fr))`
    }, children: meta.maxOpts.map((n) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
      setMaxP(n);
      closeSheet();
    }, className: `py-3 rounded-xl font-bold ${maxP === n ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-secondary"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg", children: n }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase opacity-70", children: "Joueurs" })
    ] }, n)) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "stake", onClose: closeSheet, title: "Mise (Ariary)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(StakePicker, { stake, setStake, onDone: closeSheet }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "ludo_mode", onClose: closeSheet, title: "Mode de jeu", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "classic",
      l: "Classique"
    }, {
      v: "fast",
      l: "Rapide"
    }], value: mode, onChange: (v) => {
      setMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "domino_mode", onClose: closeSheet, title: "Format", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
        v: "direct",
        l: "Victoire directe"
      }, {
        v: "points",
        l: "Par points"
      }], value: mode, onChange: (v) => setMode(v) }),
      mode === "points" && /* @__PURE__ */ jsxRuntimeExports.jsx(TargetScorePicker, { value: targetScore, onChange: setTargetScore }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: closeSheet, className: "w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "domino_draw", onClose: closeSheet, title: "Pioche", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "with",
      l: "Avec pioche"
    }, {
      v: "without",
      l: "Sans pioche"
    }], value: drawMode, onChange: (v) => {
      setDrawMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "domino_first", onClose: closeSheet, title: "Premier coup", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "libre",
      l: "Libre"
    }, {
      v: "under6",
      l: "1er domino <6"
    }], value: firstTileRule, onChange: (v) => {
      setFirstTileRule(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(BottomSheet, { open: sheet === "fanorona", onClose: closeSheet, title: "Fanorona", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(FanoronaConfigBlock, { variant: fanoronaVariant, onVariant: setFanoronaVariant, mandatory: fanoronaMandatory, onMandatory: setFanoronaMandatory }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: closeSheet, className: "mt-3 w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami", onClose: closeSheet, title: "Mode Joker", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RamiJokerBlock, { value: ramiJokerMode, onChange: (v) => {
      setRamiJokerMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami_mode", onClose: closeSheet, title: "Mode de jeu", children: /* @__PURE__ */ jsxRuntimeExports.jsx(RamiGameModeBlock, { value: ramiGameMode, onChange: (v) => {
      setRamiGameMode(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "rami_diff", onClose: closeSheet, title: "Niveau des bots", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 3, options: [{
      v: "easy",
      l: "⭐",
      sub: "Facile"
    }, {
      v: "medium",
      l: "⭐⭐",
      sub: "Moyen"
    }, {
      v: "hard",
      l: "⭐⭐⭐",
      sub: "Difficile"
    }], value: ramiBotDifficulty, onChange: (v) => {
      setRamiBotDifficulty(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "poker_blinds", onClose: closeSheet, title: "Blindes (petite / grosse)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 2, options: [{
      v: "10",
      l: "10 / 20",
      sub: "Micro"
    }, {
      v: "25",
      l: "25 / 50",
      sub: "Basse"
    }, {
      v: "50",
      l: "50 / 100",
      sub: "Moyenne"
    }, {
      v: "100",
      l: "100 / 200",
      sub: "Haute"
    }], value: String(pokerBlinds.sb), onChange: (v) => {
      const sb = Number(v);
      setPokerBlinds({
        sb,
        bb: sb * 2
      });
      setPokerBuyIn((b) => Math.max(b, sb * 2 * 20));
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "poker_buyin", onClose: closeSheet, title: "Cave de départ (jetons)", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 2, options: [{
      v: String(pokerBlinds.bb * 20),
      l: `${(pokerBlinds.bb * 20).toLocaleString("fr-FR")}`,
      sub: "20 BB"
    }, {
      v: String(pokerBlinds.bb * 50),
      l: `${(pokerBlinds.bb * 50).toLocaleString("fr-FR")}`,
      sub: "50 BB"
    }, {
      v: String(pokerBlinds.bb * 100),
      l: `${(pokerBlinds.bb * 100).toLocaleString("fr-FR")}`,
      sub: "100 BB"
    }, {
      v: String(pokerBlinds.bb * 200),
      l: `${(pokerBlinds.bb * 200).toLocaleString("fr-FR")}`,
      sub: "200 BB"
    }], value: String(pokerBuyIn), onChange: (v) => {
      setPokerBuyIn(Number(v));
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "chess_diff", onClose: closeSheet, title: "Difficulté du bot", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { columns: 5, options: [{
      v: "very_easy",
      l: "⭐",
      sub: "600"
    }, {
      v: "easy",
      l: "⭐⭐",
      sub: "900"
    }, {
      v: "medium",
      l: "⭐⭐⭐",
      sub: "1200"
    }, {
      v: "hard",
      l: "⭐⭐⭐⭐",
      sub: "1700"
    }, {
      v: "expert",
      l: "⭐⭐⭐⭐⭐",
      sub: "2200"
    }], value: chessBotDifficulty, onChange: (v) => {
      setChessBotDifficulty(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BottomSheet, { open: sheet === "chess_color", onClose: closeSheet, title: "Ta couleur", children: /* @__PURE__ */ jsxRuntimeExports.jsx(ModeBlock, { options: [{
      v: "white",
      l: "⚪ Blancs"
    }, {
      v: "black",
      l: "⚫ Noirs"
    }], value: chessBotColor, onChange: (v) => {
      setChessBotColor(v);
      closeSheet();
    } }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(BottomSheet, { open: sheet === "chess_time", onClose: closeSheet, title: "Temps par joueur", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ChessTimePicker, { value: chessTime, onChange: setChessTime }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: closeSheet, className: "mt-3 w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(AdminRenameDialog, { open: renameOpen, defaultName: profile?.pseudo || "", onCancel: () => {
      setRenameOpen(false);
      setPendingAction(null);
    }, onConfirm: async (name) => {
      setRenameOpen(false);
      const action = pendingAction;
      setPendingAction(null);
      if (action) await action(name);
    } })
  ] });
}
function SummaryRow({
  icon,
  label,
  value,
  onClick
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: "w-full flex items-center gap-3 px-3 py-3 active:bg-white/5 transition rounded-xl", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-lg leading-none w-6 text-center shrink-0", children: icon }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[13px] font-semibold text-foreground/80 shrink-0", children: label }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[13px] font-bold text-foreground truncate max-w-[55%] text-right", children: value }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground/60 text-lg leading-none shrink-0", children: "›" })
  ] });
}
function BottomSheet({
  open,
  onClose,
  title,
  children
}) {
  if (!open) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "fixed inset-0 z-50 flex items-end sm:items-center justify-center", onClick: onClose, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-black/50 backdrop-blur-sm" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative w-full sm:max-w-md bg-card rounded-t-3xl sm:rounded-3xl p-4 space-y-3 max-h-[80dvh] overflow-y-auto border-t border-white/10 shadow-2xl", onClick: (e) => e.stopPropagation(), style: {
      animation: "slideUp 200ms ease-out"
    }, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-base", children: title }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, "aria-label": "Fermer", className: "w-8 h-8 rounded-full bg-secondary flex items-center justify-center text-lg leading-none", children: "×" })
      ] }),
      children
    ] })
  ] });
}
function StakePicker({
  stake,
  setStake,
  onDone
}) {
  const [custom, setCustom] = reactExports.useState(!STAKES.includes(stake));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-end", children: /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setCustom((c) => !c), className: "text-[11px] font-semibold text-primary", children: custom ? "Préréglages" : "Saisie libre" }) }),
    custom ? /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 0, value: stake, onChange: (e) => setStake(Math.max(0, Number(e.target.value) || 0)), placeholder: "Montant en Ariary", className: "w-full px-4 py-3 rounded-xl bg-secondary outline-none text-center font-bold text-lg" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: STAKES.map((s) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setStake(s), className: `py-3 rounded-xl font-bold text-sm ${stake === s ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-secondary"}`, children: [
      s >= 1e3 ? `${s / 1e3}k` : s,
      " Ar"
    ] }, s)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onDone, className: "w-full py-2.5 rounded-full bg-primary text-primary-foreground font-bold text-sm", children: "Valider" })
  ] });
}
function TabBtn({
  label,
  active,
  onClick,
  icon
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick, className: `px-2 py-1.5 rounded-lg font-semibold text-[11px] flex items-center justify-center gap-1 transition-all active:scale-[0.97] ${active ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "bg-card border border-white/8 text-muted-foreground hover:text-foreground hover:bg-card/80"}`, children: [
    icon,
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: label })
  ] });
}
function ModeBlock({
  options,
  value,
  onChange,
  title,
  columns
}) {
  const cols = columns ?? 2;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-white/6 p-2.5 shadow-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold uppercase tracking-widest text-foreground/70 mb-1.5", children: title ?? "Mode" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid gap-1.5", style: {
      gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))`
    }, children: options.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onChange(m.v), className: `min-w-0 py-1.5 px-1 rounded-lg font-semibold text-xs transition-all active:scale-[0.97] border ${value === m.v ? "bg-primary text-primary-foreground border-primary/0 shadow-md shadow-primary/20" : "bg-secondary border-white/6 text-muted-foreground hover:text-foreground"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "leading-tight truncate", children: m.l }),
      m.sub && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[9px] mt-0.5 font-normal leading-tight truncate ${value === m.v ? "opacity-85" : "opacity-70"}`, children: m.sub })
    ] }, m.v)) })
  ] });
}
function TargetScorePicker({
  value,
  onChange
}) {
  const presets = [10, 20, 30, 40, 50];
  const [custom, setCustom] = reactExports.useState(!presets.includes(value));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold mb-2 flex items-center gap-2 justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Target, { className: "w-4 h-4" }),
        " Score cible"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setCustom((c) => !c), className: "text-xs font-semibold text-primary", children: custom ? "Préréglages" : "Saisie libre" })
    ] }),
    custom ? /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 1, max: 1e3, value, onChange: (e) => onChange(Math.max(1, Number(e.target.value) || 0)), className: "w-full px-4 py-3 rounded-2xl bg-secondary outline-none font-bold text-lg text-center" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-5 gap-2", children: presets.map((n) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => onChange(n), className: `py-2.5 rounded-2xl font-bold text-sm ${value === n ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: n }, n)) })
  ] });
}
function FanoronaConfigBlock({
  variant,
  onVariant,
  mandatory,
  onMandatory
}) {
  const variants = [{
    v: "telo",
    l: "Telo (3×3)",
    d: "9 cases"
  }, {
    v: "dimy",
    l: "Dimy (5×5)",
    d: "25 cases"
  }, {
    v: "tsivy",
    l: "Tsivy (9×5)",
    d: "45 cases · classique"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-sm space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-2", children: "Variante du plateau" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: variants.map((x) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onVariant(x.v), className: `py-2.5 rounded-2xl font-bold text-sm ${variant === x.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: x.l }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] opacity-80 font-normal", children: x.d })
      ] }, x.v)) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-2", children: "Règle de capture" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => onMandatory(true), className: `py-3 rounded-2xl font-semibold text-sm ${mandatory ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: "Capture obligatoire" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => onMandatory(false), className: `py-3 rounded-2xl font-semibold text-sm ${!mandatory ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: "Capture non obligatoire" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground mt-2", children: "L'enchaînement reste actif dans les deux cas." })
    ] })
  ] });
}
function RamiJokerBlock({
  value,
  onChange
}) {
  const opts = [{
    v: "sans",
    l: "Sans Joker",
    d: "104 cartes (2 paquets), aucun Joker"
  }, {
    v: "aleatoire",
    l: "Joker couleur opposée",
    d: "Tirage aléatoire → couleur opposée = Joker"
  }, {
    v: "classique",
    l: "Jokers classiques",
    d: "4 Jokers physiques (2 par paquet)"
  }, {
    v: "double",
    l: "Double Joker",
    d: "4 Jokers physiques + couleur opposée"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-1", children: "Mode Joker" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-2 gap-2", children: opts.map((o) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onChange(o.v), className: `py-2.5 px-2 rounded-2xl font-semibold text-xs text-left ${value === o.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: o.l }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[10px] mt-0.5 ${value === o.v ? "opacity-90" : "text-muted-foreground"}`, children: o.d })
    ] }, o.v)) })
  ] });
}
function RamiGameModeBlock({
  value,
  onChange
}) {
  const opts = [{
    v: "bordel",
    l: "🎉 Mode Bordel",
    d: "Pose libre, ajout possible dès le début"
  }, {
    v: "naturel",
    l: "📜 Mode Naturel",
    d: "1ère pose obligatoire : brelan ou suite de 3+ avant d'ajouter"
  }];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold mb-1", children: "Mode de jeu" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-1 gap-2", children: opts.map((o) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => onChange(o.v), className: `py-3 px-3 rounded-2xl font-semibold text-xs text-left ${value === o.v ? "bg-primary text-primary-foreground" : "bg-secondary"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { children: o.l }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-[10px] mt-0.5 ${value === o.v ? "opacity-90" : "text-muted-foreground"}`, children: o.d })
    ] }, o.v)) })
  ] });
}
function ChessTimePicker({
  value,
  onChange
}) {
  const presets = [3, 5, 10, 999];
  const isPreset = presets.includes(value);
  const [custom, setCustom] = reactExports.useState(isPreset ? "" : String(value));
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-3 shadow-[var(--shadow-soft)] space-y-2", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: "Temps par joueur" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-4 gap-1.5", children: [{
      v: 3,
      l: "⚡ 3′"
    }, {
      v: 5,
      l: "🔥 5′"
    }, {
      v: 10,
      l: "⏱️ 10′"
    }, {
      v: 999,
      l: "♾️"
    }].map((o) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => {
      onChange(o.v);
      setCustom("");
    }, className: `py-2 rounded-xl font-bold text-xs transition-all active:scale-95 ${value === o.v && !custom ? "bg-primary text-primary-foreground shadow-sm shadow-primary/20" : "bg-secondary text-foreground"}`, children: o.l }, o.v)) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 pt-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] text-muted-foreground shrink-0", children: "Perso." }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", min: 1, max: 180, inputMode: "numeric", placeholder: "ex. 15", value: custom, onChange: (e) => {
        const raw = e.target.value;
        setCustom(raw);
        const n = Math.max(1, Math.min(180, Number(raw) || 0));
        if (n > 0) onChange(n);
      }, className: `flex-1 min-w-0 px-3 py-1.5 rounded-lg bg-secondary text-sm font-bold text-center outline-none border ${custom ? "border-primary/40" : "border-transparent"}` }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] text-muted-foreground shrink-0", children: "min" })
    ] })
  ] });
}
export {
  Lobby as component
};
