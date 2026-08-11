import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate, L as Link } from "../_libs/tanstack__react-router.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { a as useT, u as useAuth, b as useConfirm, c as copyText } from "./router-CRCBvenY.mjs";
import { toast } from "../_libs/sonner.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { L as LinkPreviewCard } from "./LinkPreview-BF8xLSR1.mjs";
import { p as parseGameShare } from "./share-game-wrpRJpl9.mjs";
import { compressImageToWebp } from "./image-compress-U7tauI3l.mjs";
import { ak as Search, az as BellOff, V as Bell, aA as Pin, aB as Paperclip, at as ArrowDown, X, ag as Pause, av as Play, r as Send, ar as Image, aC as Mic, aD as Square, aE as Smile, aF as Reply, d as Copy, aG as Pencil, aH as Flag, ao as Trash2, U as Users, aw as Timer, a1 as Check } from "../_libs/lucide-react.mjs";
const ROUTE = {
  ludo: "/jeux/ludo/$id",
  domino: "/jeux/domino/$id",
  chess: "/jeux/chess/$id",
  fanorona: "/jeux/fanorona/$id",
  rami: "/jeux/rami/$id"
};
const TABLE = {
  ludo: "ludo_games",
  domino: "domino_games",
  chess: "chess_games",
  fanorona: "fanorona_games",
  rami: "rami_games"
};
const PART_TABLE = {
  ludo: "ludo_participants",
  domino: "domino_participants",
  chess: null,
  fanorona: "fanorona_participants",
  rami: "rami_participants"
};
const LABEL = {
  ludo: "🎲 Ludo",
  domino: "🁫 Domino",
  chess: "♟️ Échecs",
  fanorona: "⚫ Fanorona",
  rami: "🂠 Rami"
};
const DEFAULT_MAX = { ludo: 4, domino: 4, chess: 2, fanorona: 2, rami: 4 };
function GameShareCard({ slug, gameId, onMissing }) {
  const [game, setGame] = reactExports.useState(null);
  const [parts, setParts] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(true);
  reactExports.useEffect(() => {
    let mounted = true;
    const load = async () => {
      const { data: g } = await supabase.from(TABLE[slug]).select("*").eq("id", gameId).maybeSingle();
      if (!mounted) return;
      setGame(g);
      if (!g) onMissing?.();
      const pt = PART_TABLE[slug];
      if (pt) {
        const { data: p } = await supabase.from(pt).select("user_id, display_name").eq("game_id", gameId);
        if (!mounted) return;
        setParts(p || []);
      } else if (slug === "chess" && g) {
        const ids = [g.white_id, g.black_id].filter(Boolean);
        if (ids.length) {
          const { data: profs } = await supabase.from("profiles").select("id, pseudo").in("id", ids);
          if (!mounted) return;
          setParts((profs || []).map((p) => ({ user_id: p.id, display_name: p.pseudo })));
        } else setParts([]);
      }
      setLoading(false);
    };
    load();
    const ch = supabase.channel(`gameshare-${slug}-${gameId}`).on("postgres_changes", { event: "*", schema: "public", table: TABLE[slug], filter: `id=eq.${gameId}` }, load).on("postgres_changes", { event: "*", schema: "public", table: PART_TABLE[slug] || "chat_messages", filter: `game_id=eq.${gameId}` }, load).subscribe();
    return () => {
      mounted = false;
      supabase.removeChannel(ch);
    };
  }, [slug, gameId]);
  const [now, setNow] = reactExports.useState(() => serverNow());
  reactExports.useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 1e3);
    return () => clearInterval(t);
  }, []);
  if (loading) return null;
  if (!game) return null;
  const max = Number(game.max_players) || DEFAULT_MAX[slug] || 2;
  const current = parts.length;
  const status = game.status || "open";
  const isPrivate = !!game.is_private;
  const code = game.room_code || null;
  const stake = Number(game.stake) || 0;
  const createdAt = game.created_at;
  const expiresAt = createdAt && (status === "open" || status === "waiting") ? new Date(createdAt).getTime() + 6 * 6e4 : null;
  const remainingMs = expiresAt ? Math.max(0, expiresAt - now) : null;
  const inviteExpired = remainingMs === 0;
  const fmtCountdown = (ms) => {
    const s = Math.ceil(ms / 1e3);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  };
  const statusBadge = inviteExpired ? { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" }), text: "Expirée", cls: "bg-muted text-muted-foreground ring-border" } : status === "open" || status === "waiting" ? { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-3 h-3" }), text: remainingMs !== null ? fmtCountdown(remainingMs) : "En attente", cls: "bg-amber-500/15 text-amber-700 dark:text-amber-300 ring-amber-500/30" } : status === "playing" ? { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-3 h-3" }), text: "En cours", cls: "bg-emerald-500/15 text-emerald-700 dark:text-emerald-300 ring-emerald-500/30" } : { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3 h-3" }), text: "Terminée", cls: "bg-muted text-muted-foreground ring-border" };
  const canJoin = (status === "open" || status === "waiting") && current < max && !inviteExpired;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "not-prose rounded-2xl border border-border bg-card/70 backdrop-blur p-3 my-1 space-y-2 text-foreground min-w-[240px] max-w-[320px]", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm", children: LABEL[slug] || slug }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold ring-1 ${statusBadge.cls}`, children: [
        statusBadge.icon,
        statusBadge.text
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between text-xs", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 text-muted-foreground", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3.5 h-3.5" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-semibold text-foreground", children: [
          current,
          "/",
          max
        ] }),
        " joueurs"
      ] }),
      stake > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground", children: [
        "Mise : ",
        /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { className: "text-foreground", children: [
          stake.toLocaleString("fr-FR"),
          " Ar"
        ] })
      ] })
    ] }),
    isPrivate && code && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2 px-2.5 py-1.5 rounded-xl bg-secondary", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase tracking-wider text-muted-foreground", children: "Code privé" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("code", { className: "font-mono text-sm font-extrabold tracking-widest", children: code }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            type: "button",
            onClick: () => {
              copyText(code).then((ok) => ok ? toast.success("Code copié") : toast.error("Impossible de copier"));
            },
            className: "p-1 rounded-md hover:bg-background",
            "aria-label": "Copier le code",
            children: /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-3.5 h-3.5" })
          }
        )
      ] })
    ] }),
    parts.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-wrap gap-1", children: [
      parts.map((p) => /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] px-1.5 py-0.5 rounded-full bg-secondary truncate max-w-[120px]", children: p.display_name || "Joueur" }, p.user_id)),
      Array.from({ length: Math.max(0, max - current) }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] px-1.5 py-0.5 rounded-full border border-dashed border-border text-muted-foreground", children: "libre" }, `empty-${i}`))
    ] }),
    canJoin ? /* @__PURE__ */ jsxRuntimeExports.jsx(JoinButton, { slug, gameId, code, isPrivate, parts }) : status === "playing" ? /* @__PURE__ */ jsxRuntimeExports.jsx(
      Link,
      {
        to: ROUTE[slug],
        params: { id: gameId },
        className: "block text-center w-full px-3 py-2 rounded-full bg-secondary text-secondary-foreground text-xs font-bold hover:bg-accent",
        children: "Regarder la partie"
      }
    ) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center text-[11px] text-muted-foreground inline-flex items-center justify-center gap-1 py-1", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" }),
      inviteExpired ? "Invitation expirée · mise remboursée" : status === "open" ? "Partie pleine" : "Partie terminée"
    ] })
  ] });
}
function JoinButton({ slug, gameId, code, isPrivate, parts }) {
  const navigate = useNavigate();
  const [busy, setBusy] = reactExports.useState(false);
  const go = () => navigate({ to: ROUTE[slug], params: { id: gameId } });
  const handleClick = async () => {
    if (busy) return;
    setBusy(true);
    try {
      const { data: { user } } = await supabase.auth.getUser();
      const meId = user?.id;
      const alreadyIn = !!(meId && parts.some((p) => p.user_id === meId));
      if (alreadyIn) {
        go();
        return;
      }
      if (isPrivate && code) {
        const fn = slug === "ludo" ? "join_game_by_code" : slug === "domino" ? "domino_join_code" : slug === "fanorona" ? "fanorona_join_code" : slug === "chess" ? "chess_join_code" : slug === "rami" ? "rami_join_code" : null;
        if (fn) {
          const { error } = await supabase.rpc(fn, { _code: code });
          if (error) throw error;
        }
      } else {
        const fn = slug === "ludo" ? "join_game" : slug === "domino" ? "domino_join" : slug === "fanorona" ? "fanorona_join" : null;
        if (fn) {
          const { error } = await supabase.rpc(fn, { _game_id: gameId });
          if (error) throw error;
        }
      }
      go();
    } catch (e) {
      const msg = (e?.message || "").toLowerCase();
      if (msg.includes("insufficient") || msg.includes("solde")) {
        toast.error("Solde insuffisant pour rejoindre cette partie.");
      } else {
        toast.error(e.message || "Impossible de rejoindre");
      }
    } finally {
      setBusy(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "button",
    {
      type: "button",
      onClick: handleClick,
      disabled: busy,
      className: "block text-center w-full px-3 py-2 rounded-full bg-primary text-primary-foreground text-xs font-bold hover:opacity-90 disabled:opacity-60",
      children: busy ? "…" : isPrivate ? "Rejoindre avec le code" : "Rejoindre la partie"
    }
  );
}
const PAGE_SIZE = 40;
const MAX_CHARS = 500;
const EMOJIS = [
  "❤️",
  "👍",
  "😂",
  "🔥",
  "🎉",
  "😢",
  "😮",
  "🙏",
  "👏",
  "💯",
  "🎮",
  "🏆",
  "😍",
  "🤣",
  "😅",
  "🤩",
  "💪",
  "🫡",
  "😤",
  "🥳"
];
function playPing() {
  try {
    const ctx = new AudioContext();
    const osc = ctx.createOscillator();
    const gain = ctx.createGain();
    osc.connect(gain);
    gain.connect(ctx.destination);
    osc.type = "sine";
    osc.frequency.setValueAtTime(880, ctx.currentTime);
    osc.frequency.exponentialRampToValueAtTime(660, ctx.currentTime + 0.15);
    gain.gain.setValueAtTime(0.18, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(1e-4, ctx.currentTime + 0.35);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.35);
    osc.onended = () => ctx.close();
  } catch {
  }
}
const AUDIO_MIME_CANDIDATES = [
  "audio/webm;codecs=opus",
  "audio/webm",
  "audio/ogg;codecs=opus",
  "audio/mp4;codecs=mp4a.40.2",
  "audio/mp4",
  "audio/mpeg",
  "audio/aac"
];
const getAudioExt = (mime) => mime.includes("mp4") ? "m4a" : mime.includes("ogg") ? "ogg" : mime.includes("mpeg") ? "mp3" : mime.includes("aac") ? "aac" : "webm";
const baseMime = (mime) => (mime || "").split(";")[0] || "application/octet-stream";
function linkify(text) {
  const parts = text.split(/(https?:\/\/[^\s]+)/g);
  return parts.map(
    (p, i) => /^https?:\/\//.test(p) ? /* @__PURE__ */ jsxRuntimeExports.jsx(
      "a",
      {
        href: p,
        target: "_blank",
        rel: "noopener noreferrer",
        className: "underline text-primary break-all",
        children: p
      },
      i
    ) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: p }, i)
  );
}
function renderBody(text) {
  const parts = text.split(/(@\w+)/g);
  return parts.map(
    (p, i) => /^@\w+/.test(p) ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary font-semibold", children: p }, i) : linkify(p)
  );
}
function groupReactions(rxs) {
  const map = {};
  for (const r of rxs) {
    if (!map[r.emoji]) map[r.emoji] = { count: 0, users: [] };
    map[r.emoji].count++;
    map[r.emoji].users.push(r.user_id);
  }
  return map;
}
function formatTime(iso) {
  const d = new Date(iso);
  const now = /* @__PURE__ */ new Date();
  const isToday = d.toDateString() === now.toDateString();
  const isYesterday = new Date(now.getTime() - 864e5).toDateString() === d.toDateString();
  const time = d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
  if (isToday) return time;
  if (isYesterday) return `Hier ${time}`;
  return d.toLocaleDateString("fr-FR", { day: "numeric", month: "short" }) + ` ${time}`;
}
function MessageSkeleton() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-3 p-3", children: [...Array(6)].map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex gap-2 ${i % 2 === 0 ? "" : "flex-row-reverse"}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 rounded-full bg-secondary animate-pulse shrink-0" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex flex-col gap-1 ${i % 2 === 0 ? "" : "items-end"}`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-3 w-14 rounded bg-secondary animate-pulse" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `h-10 rounded-2xl bg-secondary animate-pulse ${i % 2 === 0 ? "w-48" : "w-36"}` })
    ] })
  ] }, i)) });
}
function ImageLightbox({ url, onClose }) {
  reactExports.useEffect(() => {
    const h = (e) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, [onClose]);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "fixed inset-0 z-[100] bg-black/92 flex items-center justify-center p-4 backdrop-blur-sm",
      onClick: onClose,
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            className: "absolute top-4 right-4 p-2 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors",
            onClick: onClose,
            children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-5 h-5" })
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "img",
          {
            src: url,
            alt: "",
            className: "max-w-full max-h-[90dvh] rounded-2xl object-contain shadow-2xl",
            onClick: (e) => e.stopPropagation()
          }
        )
      ]
    }
  );
}
function ChatRoom({
  roomId,
  title,
  isAdmin,
  height = "h-[70dvh]",
  gameSlug,
  fullscreen = false,
  onBack,
  onOnlineCountChange,
  onOnlineUsersChange
}) {
  const { t } = useT();
  const { user, profile } = useAuth();
  const [messages, setMessages] = reactExports.useState([]);
  const [profiles, setProfiles] = reactExports.useState({});
  const [reactions, setReactions] = reactExports.useState({});
  const [loading, setLoading] = reactExports.useState(true);
  const [hasMore, setHasMore] = reactExports.useState(false);
  const [loadingMore, setLoadingMore] = reactExports.useState(false);
  const [input, setInput] = reactExports.useState("");
  const [reply, setReply] = reactExports.useState(null);
  const [editing, setEditing] = reactExports.useState(null);
  const [search, setSearch] = reactExports.useState("");
  const [showSearch, setShowSearch] = reactExports.useState(false);
  const [typing, setTyping] = reactExports.useState([]);
  const [actionMenu, setActionMenu] = reactExports.useState(null);
  const [profileMenu, setProfileMenu] = reactExports.useState(null);
  const navigate = useNavigate();
  const [customEmoji, setCustomEmoji] = reactExports.useState("");
  const [lightboxUrl, setLightboxUrl] = reactExports.useState(null);
  const [showNewMsg, setShowNewMsg] = reactExports.useState(false);
  const [newMsgCount, setNewMsgCount] = reactExports.useState(0);
  const [newMsgIds, setNewMsgIds] = reactExports.useState(/* @__PURE__ */ new Set());
  const [missingShares, setMissingShares] = reactExports.useState(/* @__PURE__ */ new Set());
  const [heartAnim, setHeartAnim] = reactExports.useState(null);
  const [onlineUserIds, setOnlineUserIds] = reactExports.useState(/* @__PURE__ */ new Set());
  const [muted, setMuted] = reactExports.useState(() => {
    try {
      return localStorage.getItem("chat_muted") === "1";
    } catch {
      return false;
    }
  });
  const toggleMute = () => {
    setMuted((prev) => {
      const next = !prev;
      try {
        localStorage.setItem("chat_muted", next ? "1" : "0");
      } catch {
      }
      return next;
    });
  };
  const [mentionQuery, setMentionQuery] = reactExports.useState(null);
  const [mentionSuggestions, setMentionSuggestions] = reactExports.useState([]);
  const [mentionIndex, setMentionIndex] = reactExports.useState(0);
  const [recording, setRecording] = reactExports.useState(false);
  const [recElapsed, setRecElapsed] = reactExports.useState(0);
  const [voicePreview, setVoicePreview] = reactExports.useState(null);
  const [previewPlaying, setPreviewPlaying] = reactExports.useState(false);
  const scrollRef = reactExports.useRef(null);
  const fileRef = reactExports.useRef(null);
  const textareaRef = reactExports.useRef(null);
  const recRef = reactExports.useRef(null);
  const recChunksRef = reactExports.useRef([]);
  const recStreamRef = reactExports.useRef(null);
  const recTimerRef = reactExports.useRef(null);
  const previewAudioRef = reactExports.useRef(null);
  const longPressRef = reactExports.useRef(null);
  const lastTapRef = reactExports.useRef(null);
  const isAtBottomRef = reactExports.useRef(true);
  const oldestRef = reactExports.useRef(null);
  const messageRefs = reactExports.useRef({});
  const voicePreviewRef = reactExports.useRef(null);
  reactExports.useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = Math.min(ta.scrollHeight, 120) + "px";
  }, [input]);
  reactExports.useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const onScroll = () => {
      const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
      isAtBottomRef.current = nearBottom;
      if (nearBottom) {
        setShowNewMsg(false);
        setNewMsgCount(0);
      }
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => el.removeEventListener("scroll", onScroll);
  }, []);
  reactExports.useEffect(() => {
    return () => {
      previewAudioRef.current?.pause();
      previewAudioRef.current = null;
      if (voicePreviewRef.current) {
        URL.revokeObjectURL(voicePreviewRef.current);
        voicePreviewRef.current = null;
      }
      if (recTimerRef.current) window.clearInterval(recTimerRef.current);
      if (recStreamRef.current) recStreamRef.current.getTracks().forEach((t2) => t2.stop());
    };
  }, []);
  const scrollToBottom = reactExports.useCallback((behavior = "smooth") => {
    setTimeout(() => {
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior });
    }, 50);
    setShowNewMsg(false);
    setNewMsgCount(0);
  }, []);
  const scrollToMessage = reactExports.useCallback((msgId) => {
    const el = messageRefs.current[msgId];
    if (!el) return;
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    el.style.transition = "background-color 0.3s";
    el.style.backgroundColor = "hsl(var(--primary) / 0.12)";
    setTimeout(() => {
      el.style.backgroundColor = "";
    }, 1500);
  }, []);
  const loadProfiles = reactExports.useCallback(async (ids) => {
    const missing = ids.filter((i) => i && !profiles[i]);
    if (!missing.length) return;
    const { data } = await supabase.rpc("get_public_profiles_min", { _ids: missing });
    setProfiles((p) => ({
      ...p,
      ...Object.fromEntries((data || []).map((x) => [x.id, x]))
    }));
  }, []);
  const loadReactions = reactExports.useCallback(async (msgIds) => {
    if (!msgIds.length) return;
    const { data: r } = await supabase.from("chat_reactions").select("*").in("message_id", msgIds);
    const grouped = {};
    (r || []).forEach((x) => {
      (grouped[x.message_id] = grouped[x.message_id] || []).push(x);
    });
    setReactions((prev) => ({ ...prev, ...grouped }));
  }, []);
  const loadMessages = reactExports.useCallback(async () => {
    setLoading(true);
    const { data } = await supabase.from("chat_messages").select("*").eq("room_id", roomId).is("deleted_at", null).order("created_at", { ascending: false }).limit(PAGE_SIZE);
    const msgs = (data || []).reverse();
    setMessages(msgs);
    setHasMore((data || []).length === PAGE_SIZE);
    if (msgs.length > 0) oldestRef.current = msgs[0].created_at;
    setLoading(false);
    await loadProfiles(Array.from(new Set(msgs.map((m) => m.user_id))));
    await loadReactions(msgs.map((m) => m.id));
    scrollToBottom("instant");
  }, [roomId, loadProfiles, loadReactions, scrollToBottom]);
  const loadMore = reactExports.useCallback(async () => {
    if (!hasMore || loadingMore || !oldestRef.current) return;
    setLoadingMore(true);
    const prevScrollHeight = scrollRef.current?.scrollHeight || 0;
    const { data } = await supabase.from("chat_messages").select("*").eq("room_id", roomId).is("deleted_at", null).lt("created_at", oldestRef.current).order("created_at", { ascending: false }).limit(PAGE_SIZE);
    const older = (data || []).reverse();
    setMessages((prev) => [...older, ...prev]);
    setHasMore(older.length === PAGE_SIZE);
    if (older.length > 0) oldestRef.current = older[0].created_at;
    setLoadingMore(false);
    await loadProfiles(Array.from(new Set(older.map((m) => m.user_id))));
    await loadReactions(older.map((m) => m.id));
    requestAnimationFrame(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight - prevScrollHeight;
      }
    });
  }, [hasMore, loadingMore, roomId, loadProfiles, loadReactions]);
  reactExports.useEffect(() => {
    if (!roomId) return;
    supabase.rpc("chat_join_room", { _room_id: roomId });
    loadMessages();
    const ch = supabase.channel(`chat-${roomId}`).on("postgres_changes", {
      event: "INSERT",
      schema: "public",
      table: "chat_messages",
      filter: `room_id=eq.${roomId}`
    }, async (payload) => {
      const msg = payload.new;
      if (msg.deleted_at) return;
      setMessages((prev) => prev.find((m) => m.id === msg.id) ? prev : [...prev, msg]);
      setNewMsgIds((prev) => /* @__PURE__ */ new Set([...prev, msg.id]));
      setTimeout(() => setNewMsgIds((prev) => {
        const next = new Set(prev);
        next.delete(msg.id);
        return next;
      }), 700);
      await loadProfiles([msg.user_id]);
      await loadReactions([msg.id]);
      if (isAtBottomRef.current) {
        scrollToBottom();
      } else if (msg.user_id !== user?.id) {
        setShowNewMsg(true);
        setNewMsgCount((c) => c + 1);
        if (!muted) playPing();
      }
    }).on("postgres_changes", {
      event: "UPDATE",
      schema: "public",
      table: "chat_messages",
      filter: `room_id=eq.${roomId}`
    }, (payload) => {
      setMessages(
        (prev) => payload.new.deleted_at ? prev.filter((m) => m.id !== payload.new.id) : prev.map((m) => m.id === payload.new.id ? { ...m, ...payload.new } : m)
      );
    }).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "chat_reactions"
    }, async (payload) => {
      const msgId = payload.new?.message_id || payload.old?.message_id;
      if (msgId) await loadReactions([msgId]);
    }).on("postgres_changes", {
      event: "*",
      schema: "public",
      table: "chat_presence"
    }, async () => {
      const { data } = await supabase.from("chat_presence").select("user_id,typing_until").eq("typing_room", roomId).gte("typing_until", (/* @__PURE__ */ new Date()).toISOString());
      const names = await Promise.all(
        (data || []).filter((x) => x.user_id !== user?.id).map(async (x) => {
          if (!profiles[x.user_id]) {
            const { data: p } = await supabase.rpc("get_public_profiles_min", { _ids: [x.user_id] });
            const row = Array.isArray(p) ? p[0] : null;
            if (row) setProfiles((prev) => ({ ...prev, [row.id]: row }));
            return row?.pseudo || "…";
          }
          return profiles[x.user_id].pseudo;
        })
      );
      setTyping(names.filter(Boolean));
    }).subscribe();
    const presenceCh = supabase.channel(`room-presence-${roomId}`, {
      config: { presence: { key: user?.id || "anon" } }
    });
    presenceCh.on("presence", { event: "sync" }, async () => {
      const state = presenceCh.presenceState();
      const ids = new Set(
        Object.values(state).flatMap((entries) => entries.map((e) => e.user_id)).filter(Boolean)
      );
      setOnlineUserIds(ids);
      onOnlineCountChange?.(ids.size);
      if (onOnlineUsersChange) {
        const missing = Array.from(ids).filter((id) => id && !profiles[id]);
        let enriched = { ...profiles };
        if (missing.length > 0) {
          const { data } = await supabase.rpc("get_public_profiles_min", { _ids: missing });
          (data || []).forEach((p) => {
            enriched[p.id] = p;
          });
          setProfiles((prev) => ({ ...prev, ...Object.fromEntries((data || []).map((p) => [p.id, p])) }));
        }
        onOnlineUsersChange(
          Array.from(ids).map((id) => ({
            id,
            pseudo: enriched[id]?.pseudo || "Joueur",
            avatar_url: enriched[id]?.avatar_url ?? null
          }))
        );
      }
    }).subscribe(async (status) => {
      if (status === "SUBSCRIBED" && user?.id) {
        await presenceCh.track({ user_id: user.id, at: Date.now() });
      }
    });
    return () => {
      supabase.removeChannel(ch);
      supabase.removeChannel(presenceCh);
    };
  }, [roomId]);
  reactExports.useEffect(() => {
    if (mentionQuery === null || mentionQuery.length < 1) {
      setMentionSuggestions([]);
      return;
    }
    const timer = setTimeout(async () => {
      const { data } = await supabase.from("profiles").select("id,pseudo,avatar_url").ilike("pseudo", `${mentionQuery}%`).limit(5);
      setMentionSuggestions(data || []);
    }, 200);
    return () => clearTimeout(timer);
  }, [mentionQuery]);
  const handleInputChange = (e) => {
    const val = e.target.value;
    if (val.length > MAX_CHARS) return;
    setInput(val);
    const cursor = e.target.selectionStart;
    const before = val.slice(0, cursor);
    const match = before.match(/@(\w*)$/);
    if (match) {
      setMentionQuery(match[1]);
      setMentionIndex(0);
    } else {
      setMentionQuery(null);
    }
  };
  const insertMention = (pseudo) => {
    const cursor = textareaRef.current?.selectionStart ?? input.length;
    const before = input.slice(0, cursor).replace(/@\w*$/, `@${pseudo} `);
    const after = input.slice(cursor);
    setInput(before + after);
    setMentionQuery(null);
    setMentionSuggestions([]);
    setTimeout(() => textareaRef.current?.focus(), 0);
  };
  const handlePaste = async (e) => {
    const imgItem = Array.from(e.clipboardData.items).find((i) => i.type.startsWith("image/"));
    if (!imgItem) return;
    e.preventDefault();
    const file = imgItem.getAsFile();
    if (!file) return;
    toast.promise(uploadFile(file), {
      loading: "Envoi de l'image…",
      success: "Image envoyée !",
      error: "Erreur lors de l'envoi"
    });
  };
  const send = async () => {
    const body = input.trim();
    if (!body && !editing) return;
    if (editing) {
      const { error: error2 } = await supabase.from("chat_messages").update({ body, edited_at: (/* @__PURE__ */ new Date()).toISOString() }).eq("id", editing.id);
      if (error2) return toast.error(error2.message);
      setEditing(null);
      setInput("");
      return;
    }
    const { error } = await supabase.rpc("chat_send", {
      _room_id: roomId,
      _body: body,
      _reply_to: reply?.id ?? null
    });
    if (error) return toast.error(error.message);
    setInput("");
    setReply(null);
  };
  const sendTyping = async () => {
    await supabase.rpc("chat_typing", { _room_id: roomId });
  };
  const react = async (mid, emoji) => {
    const existing = (reactions[mid] || []).find((r) => r.user_id === user?.id && r.emoji === emoji);
    if (existing) await supabase.from("chat_reactions").delete().eq("id", existing.id);
    else await supabase.from("chat_reactions").insert({ message_id: mid, user_id: user.id, emoji });
    setEmojiOpen(null);
  };
  const [emojiOpen, setEmojiOpen] = reactExports.useState(null);
  const confirmDlg = useConfirm();
  const del = async (m) => {
    const ok = await confirmDlg({ title: t("delete_message_confirm"), confirmLabel: "Supprimer", destructive: true });
    if (!ok) return;
    await supabase.from("chat_messages").update({ deleted_at: (/* @__PURE__ */ new Date()).toISOString() }).eq("id", m.id);
  };
  const pin = async (m) => {
    await supabase.rpc("chat_pin", { _message_id: m.id, _pin: !m.pinned });
  };
  const copyMessage = (body) => {
    copyText(body).then((ok) => ok ? toast.success("Copié !") : toast.error("Impossible de copier")).catch(() => toast.error("Impossible de copier"));
  };
  const reportMessage = async (m) => {
    const ok = await confirmDlg({ title: "Signaler ce message à l'équipe ?", confirmLabel: "Signaler", destructive: true });
    if (!ok) return;
    await supabase.from("chat_messages").update({ reported: true }).eq("id", m.id);
    toast.success("Message signalé — l'équipe a été notifiée");
  };
  const uploadFile = async (rawFile) => {
    if (!user) return false;
    const f = rawFile.type.startsWith("image/") ? await compressImageToWebp(rawFile, { maxDim: 1280, maxSizeKB: 200 }) : rawFile;
    const ext = f.name.split(".").pop() || "bin";
    const path = `${user.id}/${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from("chat").upload(path, f, {
      contentType: baseMime(f.type),
      upsert: false
    });
    if (error) {
      toast.error(error.message);
      return false;
    }
    const { data: signed, error: sErr } = await supabase.storage.from("chat").createSignedUrl(path, 60 * 60 * 24 * 365 * 5);
    if (sErr || !signed?.signedUrl) {
      toast.error(sErr?.message || "Lien indisponible");
      return false;
    }
    const url = signed.signedUrl;
    const type = f.type.startsWith("image/") ? "image" : f.type.startsWith("audio/") ? "audio" : "file";
    const { error: msgErr } = await supabase.rpc("chat_send", {
      _room_id: roomId,
      _body: type === "file" ? f.name : "",
      _reply_to: null,
      _attachment_url: url,
      _attachment_type: type
    });
    if (msgErr) {
      toast.error(msgErr.message);
      return false;
    }
    return true;
  };
  const startLongPress = (m) => {
    if (longPressRef.current) window.clearTimeout(longPressRef.current);
    longPressRef.current = window.setTimeout(() => setActionMenu(m), 500);
  };
  const cancelLongPress = () => {
    if (longPressRef.current) {
      window.clearTimeout(longPressRef.current);
      longPressRef.current = null;
    }
  };
  const handleDoubleTap = async (m, x, y) => {
    await react(m.id, "❤️");
    setHeartAnim({ id: m.id, x, y });
    setTimeout(() => setHeartAnim(null), 900);
  };
  const handleTouchEnd = (m, e) => {
    cancelLongPress();
    const now = Date.now();
    const touch = e.changedTouches[0];
    if (lastTapRef.current && lastTapRef.current.id === m.id && now - lastTapRef.current.time < 320) {
      lastTapRef.current = null;
      handleDoubleTap(m, touch.clientX, touch.clientY);
    } else {
      lastTapRef.current = { id: m.id, time: now };
    }
  };
  const startRecord = async () => {
    try {
      if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
        toast.error(t("mic_unavailable"));
        return;
      }
      cancelVoice();
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true
        }
      });
      recStreamRef.current = stream;
      const mime = AUDIO_MIME_CANDIDATES.find((m) => MediaRecorder.isTypeSupported(m)) || "";
      const rec = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
      recChunksRef.current = [];
      const startedAt = Date.now();
      rec.ondataavailable = (e) => {
        if (e.data.size > 0) recChunksRef.current.push(e.data);
      };
      rec.onstop = () => {
        window.setTimeout(() => {
          const type = rec.mimeType || mime || "audio/webm";
          const chunks = recChunksRef.current.filter((c) => c.size > 0);
          const blob = new Blob(chunks, { type });
          recStreamRef.current?.getTracks().forEach((t2) => t2.stop());
          recStreamRef.current = null;
          recRef.current = null;
          if (blob.size < 256) {
            toast.error("Vocal vide, veuillez réessayer.");
            return;
          }
          const url = URL.createObjectURL(blob);
          const duration = Math.max(1, Math.round((Date.now() - startedAt) / 1e3));
          previewAudioRef.current = null;
          voicePreviewRef.current = url;
          setVoicePreview({ url, blob, duration });
        }, 120);
      };
      rec.start(250);
      recRef.current = rec;
      setRecording(true);
      setRecElapsed(0);
      if (recTimerRef.current) window.clearInterval(recTimerRef.current);
      recTimerRef.current = window.setInterval(() => setRecElapsed((s) => s + 1), 1e3);
    } catch (err) {
      if (recStreamRef.current) {
        recStreamRef.current.getTracks().forEach((t2) => t2.stop());
        recStreamRef.current = null;
      }
      if (err?.name === "NotAllowedError" || err?.name === "PermissionDeniedError") {
        toast.error("Microphone access denied. Please allow microphone permission.");
      } else if (err?.name === "NotFoundError" || err?.name === "DevicesNotFoundError") {
        toast.error("No microphone found on this device.");
      } else {
        toast.error(t("mic_unavailable"));
      }
    }
  };
  const stopRecord = () => {
    if (recRef.current && recRef.current.state !== "inactive") {
      try {
        recRef.current.requestData();
      } catch {
      }
      recRef.current.stop();
    }
    setRecording(false);
    if (recTimerRef.current) {
      window.clearInterval(recTimerRef.current);
      recTimerRef.current = null;
    }
  };
  const togglePreview = () => {
    if (!voicePreview) return;
    if (!previewAudioRef.current) {
      previewAudioRef.current = new Audio(voicePreview.url);
      previewAudioRef.current.onended = () => setPreviewPlaying(false);
    }
    if (previewPlaying) {
      previewAudioRef.current.pause();
      setPreviewPlaying(false);
    } else {
      previewAudioRef.current.play();
      setPreviewPlaying(true);
    }
  };
  const cancelVoice = () => {
    previewAudioRef.current?.pause();
    previewAudioRef.current = null;
    if (voicePreviewRef.current) {
      URL.revokeObjectURL(voicePreviewRef.current);
      voicePreviewRef.current = null;
    }
    setVoicePreview(null);
    setPreviewPlaying(false);
  };
  const sendVoice = async () => {
    if (!voicePreview) return;
    const mime = voicePreview.blob.type || "audio/webm";
    const ext = getAudioExt(mime);
    const f = new File([voicePreview.blob], `voice-${Date.now()}.${ext}`, { type: mime });
    const sent = await uploadFile(f);
    if (sent) cancelVoice();
  };
  const pinned = messages.filter((m) => m.pinned);
  const filtered = search ? messages.filter((m) => m.body?.toLowerCase().includes(search.toLowerCase())) : messages;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex flex-col ${fullscreen ? "h-[calc(100dvh-7.5rem)] bg-card" : `${height} bg-card rounded-3xl shadow-[var(--shadow-soft)]`} overflow-hidden`, children: [
    lightboxUrl && /* @__PURE__ */ jsxRuntimeExports.jsx(ImageLightbox, { url: lightboxUrl, onClose: () => setLightboxUrl(null) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("style", { children: `
        @keyframes heartPop {
          0%   { transform: scale(0) translateY(0);    opacity: 0; }
          20%  { transform: scale(1.5) translateY(-4px); opacity: 1; }
          55%  { transform: scale(1.1) translateY(-14px); opacity: 1; }
          100% { transform: scale(0.6) translateY(-28px); opacity: 0; }
        }
      ` }),
    heartAnim && /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "fixed z-[200] pointer-events-none select-none text-3xl drop-shadow-lg",
        style: {
          left: heartAnim.x - 18,
          top: heartAnim.y - 18,
          animation: "heartPop 0.85s cubic-bezier(0.22, 1, 0.36, 1) forwards"
        },
        children: "❤️"
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-3 py-2 border-b border-white/8 flex items-center gap-2 shrink-0 bg-background/30", children: [
      onBack && /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: onBack,
          className: "p-1.5 rounded-full hover:bg-white/8 text-muted-foreground hover:text-foreground transition-all",
          "aria-label": "Retour",
          children: /* @__PURE__ */ jsxRuntimeExports.jsxs("svg", { xmlns: "http://www.w3.org/2000/svg", width: "16", height: "16", viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: "2", strokeLinecap: "round", strokeLinejoin: "round", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("path", { d: "M19 12H5" }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("path", { d: "m12 19-7-7 7-7" })
          ] })
        }
      ),
      title && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-sm flex-1 truncate", children: title }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => setShowSearch((s) => !s),
          className: "flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium text-muted-foreground hover:bg-white/8 hover:text-foreground transition-all border border-transparent hover:border-white/10 ml-auto",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Search, { className: "w-3.5 h-3.5" }),
            "Rechercher"
          ]
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: toggleMute,
          title: muted ? "Réactiver les sons" : "Couper les sons",
          className: `p-1.5 rounded-full hover:bg-white/8 shrink-0 transition-all ${muted ? "text-destructive/70 hover:text-destructive" : "text-muted-foreground hover:text-foreground"}`,
          children: muted ? /* @__PURE__ */ jsxRuntimeExports.jsx(BellOff, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Bell, { className: "w-4 h-4" })
        }
      )
    ] }),
    showSearch && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-3 py-2 border-b border-white/8 bg-background/40 shrink-0 animate-in slide-in-from-top-1 fade-in duration-150", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
      "input",
      {
        value: search,
        onChange: (e) => setSearch(e.target.value),
        placeholder: t("search_placeholder"),
        autoFocus: true,
        className: "w-full px-3 py-1.5 rounded-full bg-card/80 border border-white/10 outline-none text-sm focus:border-primary/40 focus:ring-1 focus:ring-primary/20 transition-all placeholder:text-muted-foreground/50"
      }
    ) }),
    pinned.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => scrollToMessage(pinned[pinned.length - 1].id),
        className: "w-full text-left px-4 py-2.5 border-b border-amber-500/20 bg-gradient-to-r from-amber-500/10 to-amber-400/5 text-xs flex items-center gap-2 hover:from-amber-500/15 hover:to-amber-400/10 transition-all shrink-0",
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Pin, { className: "w-3 h-3 text-amber-500 shrink-0" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-amber-600 dark:text-amber-400 shrink-0", children: "Épinglé ·" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate text-foreground/70", children: pinned[pinned.length - 1].body })
        ]
      }
    ),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { ref: scrollRef, className: "flex-1 overflow-y-auto relative", style: { backgroundImage: "radial-gradient(ellipse at top, hsl(var(--primary)/0.04) 0%, transparent 70%)" }, children: [
      loading ? /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSkeleton, {}) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        hasMore && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-3", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            onClick: loadMore,
            disabled: loadingMore,
            className: "px-4 py-1.5 rounded-full bg-card border border-white/10 text-xs font-semibold hover:bg-accent disabled:opacity-40 transition-all shadow-sm",
            children: loadingMore ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1.5", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-3 h-3 rounded-full border-2 border-primary/30 border-t-primary animate-spin" }),
              "Chargement…"
            ] }) : "↑ Messages précédents"
          }
        ) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-3 space-y-2", children: filtered.map((m) => {
          const mine = m.user_id === user?.id;
          const snap = m.sender_name ? { pseudo: m.sender_name, avatar_url: m.sender_avatar ?? null } : null;
          const p = snap ?? (mine ? profile : profiles[m.user_id]);
          const replied = m.reply_to ? messages.find((x) => x.id === m.reply_to) : null;
          const repliedP = replied ? replied.sender_name ? { pseudo: replied.sender_name, avatar_url: replied.sender_avatar ?? null } : replied.user_id === user?.id ? profile : profiles[replied.user_id] : null;
          const rxGroups = groupReactions(reactions[m.id] || []);
          const hasRx = Object.keys(rxGroups).length > 0;
          const initials = (p?.pseudo || "?").slice(0, 2).toUpperCase();
          const share = parseGameShare(m.body);
          const isDeleted = !!m.deleted_at;
          if (share && missingShares.has(m.id)) return null;
          return /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "div",
            {
              ref: (el) => {
                messageRefs.current[m.id] = el;
              },
              className: `flex gap-2.5 items-end ${mine ? "flex-row-reverse" : ""} px-1 ${newMsgIds.has(m.id) ? mine ? "animate-in slide-in-from-right-4 fade-in duration-300" : "animate-in slide-in-from-left-4 fade-in duration-300" : ""}`,
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    type: "button",
                    onClick: () => {
                      if (mine || !p) return;
                      setProfileMenu({ id: m.user_id, pseudo: p.pseudo, avatar_url: p.avatar_url });
                    },
                    className: `relative w-8 h-8 shrink-0 ${mine ? "cursor-default" : "cursor-pointer active:scale-95 transition-transform"}`,
                    "aria-label": mine ? void 0 : `Profil de ${p?.pseudo || "joueur"}`,
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-xs font-bold ring-2 ring-background shadow-sm", children: p?.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: p.avatar_url, width: 32, height: 32, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: "" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary", children: initials }) }),
                      onlineUserIds.has(m.user_id) && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "absolute bottom-0 right-0 w-2.5 h-2.5 rounded-full bg-green-500 ring-2 ring-background shadow-sm" })
                    ]
                  }
                ),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "max-w-[78%] group", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `text-[11px] font-semibold mb-1 px-1 flex items-center gap-1.5 ${mine ? "justify-end" : ""}`, children: [
                    !mine && /* @__PURE__ */ jsxRuntimeExports.jsx(
                      "button",
                      {
                        type: "button",
                        onClick: () => p && setProfileMenu({ id: m.user_id, pseudo: p.pseudo, avatar_url: p.avatar_url }),
                        className: "text-primary/80 truncate hover:underline",
                        children: p?.pseudo || "…"
                      }
                    ),
                    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-muted-foreground/40 font-normal text-[10px] opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap", children: formatTime(m.created_at) })
                  ] }),
                  replied && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "button",
                    {
                      className: "w-full text-left text-[11px] px-3 py-1.5 mb-1.5 rounded-xl bg-primary/8 border-l-2 border-primary/60 truncate hover:bg-primary/12 transition-colors",
                      onClick: () => scrollToMessage(replied.id),
                      children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-semibold opacity-70", children: [
                          "↩ ",
                          repliedP?.pseudo || "…"
                        ] }),
                        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "opacity-70", children: " · " }),
                        replied.attachment_type === "audio" ? "🎤 Vocal" : replied.attachment_type === "image" ? "🖼️ Image" : (replied.body || "").slice(0, 60)
                      ]
                    }
                  ),
                  share && !isDeleted ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { onContextMenu: (e) => {
                    e.preventDefault();
                    setActionMenu(m);
                  }, children: /* @__PURE__ */ jsxRuntimeExports.jsx(GameShareCard, { slug: share.slug, gameId: share.gameId, onMissing: () => setMissingShares((prev) => {
                    if (prev.has(m.id)) return prev;
                    const n = new Set(prev);
                    n.add(m.id);
                    return n;
                  }) }) }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "div",
                    {
                      className: `px-3.5 py-2 text-sm break-words whitespace-pre-wrap select-none relative rounded-[18px] ${mine ? "bg-primary text-primary-foreground shadow-sm" : "bg-[#E4E6EB] text-[#050505] dark:bg-[#3A3B3C] dark:text-[#E4E6EB] shadow-sm"}`,
                      onTouchStart: () => startLongPress(m),
                      onTouchEnd: (e) => handleTouchEnd(m, e),
                      onTouchMove: cancelLongPress,
                      onDoubleClick: (e) => handleDoubleTap(m, e.clientX, e.clientY),
                      onContextMenu: (e) => {
                        e.preventDefault();
                        setActionMenu(m);
                      },
                      children: [
                        m.attachment_url && m.attachment_type === "image" && /* @__PURE__ */ jsxRuntimeExports.jsx(
                          "img",
                          {
                            src: m.attachment_url,
                            alt: "",
                            className: "rounded-xl max-h-56 max-w-full cursor-zoom-in hover:opacity-90 transition-opacity",
                            onClick: () => setLightboxUrl(m.attachment_url)
                          }
                        ),
                        m.attachment_url && m.attachment_type === "audio" && /* @__PURE__ */ jsxRuntimeExports.jsx("audio", { controls: true, src: m.attachment_url, className: "max-w-full min-w-[200px]" }),
                        m.attachment_url && m.attachment_type === "file" && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                          "a",
                          {
                            href: m.attachment_url,
                            target: "_blank",
                            rel: "noopener noreferrer",
                            className: "flex items-center gap-2 underline text-sm",
                            children: [
                              /* @__PURE__ */ jsxRuntimeExports.jsx(Paperclip, { className: "w-4 h-4 shrink-0" }),
                              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "break-all", children: m.body || "Fichier" })
                            ]
                          }
                        ),
                        m.body && m.attachment_type !== "file" && (isDeleted ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "italic opacity-40", children: "Message supprimé" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: renderBody(m.body) })),
                        m.body && !m.attachment_url && !isDeleted && /https?:\/\//.test(m.body) && /* @__PURE__ */ jsxRuntimeExports.jsx(LinkPreviewCard, { text: m.body }),
                        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1 mt-1 ${mine ? "justify-end" : ""}`, children: [
                          m.edited_at && !isDeleted && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] opacity-40", children: "modifié ·" }),
                          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] opacity-30", children: new Date(m.created_at).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" }) })
                        ] })
                      ]
                    }
                  ),
                  hasRx && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `flex gap-1 mt-1 flex-wrap ${mine ? "justify-end" : ""}`, children: Object.entries(rxGroups).map(([emoji, { count, users }]) => {
                    const isMine = users.includes(user?.id || "");
                    return /* @__PURE__ */ jsxRuntimeExports.jsxs(
                      "button",
                      {
                        onClick: () => react(m.id, emoji),
                        title: `${count} réaction${count > 1 ? "s" : ""}`,
                        className: `inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-xs border transition-all active:scale-90 ${isMine ? "bg-primary/15 border-primary/30 text-primary font-semibold" : "bg-card border-white/10 hover:bg-accent shadow-sm"}`,
                        children: [
                          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: emoji }),
                          count > 1 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-[10px]", children: count })
                        ]
                      },
                      emoji
                    );
                  }) })
                ] })
              ]
            },
            m.id
          );
        }) })
      ] }),
      showNewMsg && /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => scrollToBottom(),
          className: "absolute bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-1.5 px-4 py-2 rounded-full bg-primary text-primary-foreground text-xs font-bold shadow-xl shadow-primary/30 hover:scale-105 active:scale-95 transition-all z-10 animate-in slide-in-from-bottom-2 fade-in duration-200",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowDown, { className: "w-3 h-3 animate-bounce" }),
            newMsgCount > 1 ? `${newMsgCount} nouveaux messages` : "Nouveau message"
          ]
        }
      )
    ] }),
    typing.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 pb-2 flex items-center gap-2.5 shrink-0 animate-in fade-in slide-in-from-bottom-1 duration-200", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 px-3 py-2.5 rounded-[18px] bg-[#E4E6EB] dark:bg-[#3A3B3C] shadow-sm", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce", style: { animationDelay: "0ms" } }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce", style: { animationDelay: "150ms" } }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce", style: { animationDelay: "300ms" } })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground/50 font-medium", children: typing.length === 1 ? `${typing[0]} écrit…` : `${typing.length} personnes écrivent…` })
    ] }),
    (reply || editing) && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mx-3 mb-1 px-3 py-2 rounded-xl bg-primary/8 border-l-2 border-primary/60 flex items-center justify-between text-xs shrink-0 animate-in slide-in-from-bottom-1 fade-in duration-150", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "truncate", children: editing ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-primary", children: "Modifier · " }),
        editing.body?.slice(0, 60)
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-semibold", children: [
          "↩ ",
          reply?.user_id === user?.id ? "Vous" : profiles[reply?.user_id]?.pseudo || "…",
          " · "
        ] }),
        reply?.body?.slice(0, 60)
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => {
            setReply(null);
            setEditing(null);
            setInput("");
          },
          className: "ml-2 p-1 rounded-full hover:bg-accent shrink-0",
          children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" })
        }
      )
    ] }),
    mentionSuggestions.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mx-3 mb-1 rounded-2xl bg-card border border-border shadow-lg overflow-hidden shrink-0 max-h-40 overflow-y-auto", children: mentionSuggestions.map((s, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        className: `w-full flex items-center gap-2 px-3 py-2 text-sm hover:bg-accent transition-colors text-left ${i === mentionIndex ? "bg-accent" : ""}`,
        onMouseDown: (e) => {
          e.preventDefault();
          insertMention(s.pseudo);
        },
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 h-6 rounded-full bg-secondary overflow-hidden shrink-0 flex items-center justify-center text-[10px] font-bold", children: s.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: s.avatar_url, width: 40, height: 40, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: "" }) : (s.pseudo || "?").slice(0, 2).toUpperCase() }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-medium", children: [
            "@",
            s.pseudo
          ] })
        ]
      },
      s.id
    )) }),
    voicePreview && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mx-3 mb-1 px-3 py-2 rounded-2xl bg-secondary flex items-center gap-2 shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: togglePreview, className: "p-1.5 rounded-full bg-primary text-primary-foreground", children: previewPlaying ? /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-3 h-3" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-3 h-3" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex-1 h-1.5 rounded-full bg-border overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-full w-1/3 bg-primary rounded-full" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs text-muted-foreground tabular-nums", children: [
        voicePreview.duration,
        "s"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: sendVoice, className: "p-1.5 rounded-full bg-primary text-primary-foreground", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-3 h-3" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: cancelVoice, className: "p-1.5 rounded-full bg-destructive/10 text-destructive", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-3 h-3" }) })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-2.5 py-2 border-t border-border bg-card flex items-center gap-1.5 shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => fileRef.current?.click(),
          className: "p-2 rounded-full hover:bg-accent text-primary shrink-0 transition-all",
          children: /* @__PURE__ */ jsxRuntimeExports.jsx(Image, { className: "w-5 h-5" })
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "input",
        {
          ref: fileRef,
          type: "file",
          accept: "image/*,audio/*,.pdf,.doc,.docx",
          className: "hidden",
          onChange: async (e) => {
            const f = e.target.files?.[0];
            if (f) await uploadFile(f);
            e.target.value = "";
          }
        }
      ),
      !input.trim() && !recording && /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: startRecord,
          title: "Enregistrer un message vocal",
          className: "p-2 rounded-full hover:bg-accent text-primary shrink-0 transition-all active:scale-90",
          children: /* @__PURE__ */ jsxRuntimeExports.jsx(Mic, { className: "w-5 h-5" })
        }
      ),
      recording ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 flex items-center gap-2 px-4 py-2 rounded-full bg-[#F0F2F5] dark:bg-[#3A3B3C]", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "w-2 h-2 rounded-full bg-destructive animate-pulse shrink-0" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs text-destructive font-mono tabular-nums flex-1", children: [
          recElapsed,
          "s"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: stopRecord, className: "p-1.5 rounded-full bg-destructive text-white shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Square, { className: "w-3.5 h-3.5" }) })
      ] }) : (
        /* Pill-shaped input with trailing emoji button */
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 relative flex items-end gap-1 px-1.5 py-1 rounded-full bg-[#F0F2F5] dark:bg-[#3A3B3C]", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "textarea",
            {
              ref: textareaRef,
              rows: 1,
              value: input,
              onChange: handleInputChange,
              onPaste: handlePaste,
              onKeyDown: (e) => {
                if (mentionSuggestions.length > 0) {
                  if (e.key === "ArrowDown") {
                    e.preventDefault();
                    setMentionIndex((i) => Math.min(i + 1, mentionSuggestions.length - 1));
                    return;
                  }
                  if (e.key === "ArrowUp") {
                    e.preventDefault();
                    setMentionIndex((i) => Math.max(i - 1, 0));
                    return;
                  }
                  if (e.key === "Enter" || e.key === "Tab") {
                    e.preventDefault();
                    insertMention(mentionSuggestions[mentionIndex]?.pseudo);
                    return;
                  }
                  if (e.key === "Escape") {
                    setMentionQuery(null);
                    setMentionSuggestions([]);
                    return;
                  }
                }
                if (e.key === "Enter" && !e.shiftKey) {
                  e.preventDefault();
                  send();
                }
              },
              onInput: sendTyping,
              placeholder: editing ? "Modifier le message…" : "Message",
              className: "flex-1 min-w-0 px-2.5 py-1.5 bg-transparent outline-none text-sm resize-none leading-5 max-h-[120px] overflow-y-auto",
              style: { height: "auto" }
            }
          ),
          input.length > MAX_CHARS * 0.8 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `absolute -top-5 right-1 text-[10px] font-semibold tabular-nums ${input.length >= MAX_CHARS ? "text-destructive" : "text-muted-foreground"}`, children: MAX_CHARS - input.length }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              type: "button",
              onClick: () => setInput((v) => v + "😊"),
              className: "p-1.5 rounded-full hover:bg-black/5 dark:hover:bg-white/10 text-amber-500 shrink-0 transition-all",
              title: "Emoji",
              children: /* @__PURE__ */ jsxRuntimeExports.jsx(Smile, { className: "w-5 h-5" })
            }
          )
        ] })
      ),
      input.trim() && /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: send,
          className: "p-2 rounded-full bg-primary text-primary-foreground hover:scale-105 active:scale-90 shrink-0 transition-all shadow-md shadow-primary/30",
          children: /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4" })
        }
      )
    ] }),
    actionMenu && /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "fixed inset-0 z-50 bg-black/40 flex items-end justify-center p-4 backdrop-blur-sm",
        onClick: () => {
          setActionMenu(null);
          setCustomEmoji("");
        },
        children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "w-full max-w-sm bg-card/95 backdrop-blur-md rounded-3xl p-4 space-y-3 shadow-2xl border border-white/8 animate-in slide-in-from-bottom-3 fade-in duration-200",
            onClick: (e) => e.stopPropagation(),
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] uppercase text-muted-foreground mb-2 font-semibold tracking-wide", children: "Réagir" }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 flex-wrap", children: EMOJIS.map((e) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                  "button",
                  {
                    onClick: () => {
                      react(actionMenu.id, e);
                      setActionMenu(null);
                    },
                    className: "text-xl hover:scale-125 transition-transform p-0.5 active:scale-110",
                    children: e
                  },
                  e
                )) }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-2 flex gap-2", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(
                    "input",
                    {
                      value: customEmoji,
                      onChange: (e) => setCustomEmoji(e.target.value),
                      placeholder: "😀 Autre emoji…",
                      className: "flex-1 px-3 py-2 rounded-2xl bg-secondary outline-none text-sm"
                    }
                  ),
                  /* @__PURE__ */ jsxRuntimeExports.jsx(
                    "button",
                    {
                      onClick: () => {
                        if (customEmoji.trim()) {
                          react(actionMenu.id, customEmoji.trim());
                          setCustomEmoji("");
                          setActionMenu(null);
                        }
                      },
                      className: "px-3 py-2 rounded-2xl bg-primary text-primary-foreground font-semibold text-sm",
                      children: "OK"
                    }
                  )
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      setReply(actionMenu);
                      setActionMenu(null);
                    },
                    className: "py-2.5 rounded-2xl bg-secondary font-semibold text-sm flex items-center justify-center gap-1.5",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Reply, { className: "w-4 h-4" }),
                      " Répondre"
                    ]
                  }
                ),
                actionMenu.body && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      copyMessage(actionMenu.body);
                      setActionMenu(null);
                    },
                    className: "py-2.5 rounded-2xl bg-secondary font-semibold text-sm flex items-center justify-center gap-1.5",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-4 h-4" }),
                      " Copier"
                    ]
                  }
                ),
                actionMenu.user_id === user?.id && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      setEditing(actionMenu);
                      setInput(actionMenu.body || "");
                      setActionMenu(null);
                    },
                    className: "py-2.5 rounded-2xl bg-secondary font-semibold text-sm flex items-center justify-center gap-1.5",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Pencil, { className: "w-4 h-4" }),
                      " Modifier"
                    ]
                  }
                ),
                actionMenu.user_id !== user?.id && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      reportMessage(actionMenu);
                      setActionMenu(null);
                    },
                    className: "py-2.5 rounded-2xl bg-orange-500/10 text-orange-600 dark:text-orange-400 font-semibold text-sm flex items-center justify-center gap-1.5",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Flag, { className: "w-4 h-4" }),
                      " Signaler"
                    ]
                  }
                ),
                (actionMenu.user_id === user?.id || isAdmin) && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      del(actionMenu);
                      setActionMenu(null);
                    },
                    className: "py-2.5 rounded-2xl bg-destructive/10 text-destructive font-semibold text-sm flex items-center justify-center gap-1.5",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }),
                      " Supprimer"
                    ]
                  }
                ),
                isAdmin && /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "button",
                  {
                    onClick: () => {
                      pin(actionMenu);
                      setActionMenu(null);
                    },
                    className: "py-2.5 rounded-2xl bg-amber-500/15 text-amber-700 dark:text-amber-400 font-semibold text-sm flex items-center justify-center gap-1.5",
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Pin, { className: "w-4 h-4" }),
                      " ",
                      actionMenu.pinned ? "Désépingler" : "Épingler"
                    ]
                  }
                )
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  onClick: () => {
                    setActionMenu(null);
                    setCustomEmoji("");
                  },
                  className: "w-full py-2 rounded-full bg-secondary text-sm font-medium",
                  children: "Fermer"
                }
              )
            ]
          }
        )
      }
    ),
    profileMenu && /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-end sm:items-center justify-center p-4 animate-in fade-in duration-150",
        onClick: () => setProfileMenu(null),
        children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "div",
          {
            className: "w-full max-w-sm bg-background rounded-3xl p-4 space-y-3 shadow-2xl animate-in slide-in-from-bottom-4 duration-200",
            onClick: (e) => e.stopPropagation(),
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3 px-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-12 h-12 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-sm font-bold ring-2 ring-background shadow-sm", children: profileMenu.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: profileMenu.avatar_url, className: "w-full h-full object-cover", alt: "" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary", children: (profileMenu.pseudo || "?").slice(0, 2).toUpperCase() }) }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold truncate", children: profileMenu.pseudo || "Joueur" }),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground", children: "Choisir une action" })
                ] })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid gap-2", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(
                  "button",
                  {
                    onClick: () => {
                      const id = profileMenu.id;
                      setProfileMenu(null);
                      navigate({ to: "/joueur/$id", params: { id } });
                    },
                    className: "py-3 rounded-2xl bg-primary/10 text-primary font-semibold text-sm flex items-center justify-center gap-2",
                    children: "Voir le profil"
                  }
                ),
                /* @__PURE__ */ jsxRuntimeExports.jsx(
                  "button",
                  {
                    onClick: () => {
                      const id = profileMenu.id;
                      setProfileMenu(null);
                      navigate({ to: "/chat", search: { dm: id } });
                    },
                    className: "py-3 rounded-2xl bg-primary text-primary-foreground font-semibold text-sm flex items-center justify-center gap-2 shadow-sm",
                    children: "Envoyer un message"
                  }
                )
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "button",
                {
                  onClick: () => setProfileMenu(null),
                  className: "w-full py-2 rounded-full bg-secondary text-sm font-medium",
                  children: "Fermer"
                }
              )
            ]
          }
        )
      }
    )
  ] });
}
export {
  ChatRoom as C
};
