import { useEffect, useRef, useState, useCallback } from "react";
import { useNavigate } from "@tanstack/react-router";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import { copyText } from "@/lib/clipboard";
import {
  Send, Reply, Trash2, Pin, X, Search, Mic, Paperclip,
  Pencil, Play, Pause, Square, Copy, Flag, ArrowDown, BellOff, Bell,
  Image as ImageIcon, Smile,
} from "lucide-react";
import { useT } from "@/lib/i18n";
import { toast } from "sonner";
import { useConfirm } from "@/components/ConfirmDialog";
import GameShareCard from "@/components/game/GameShareCard";
import { LinkPreviewCard } from "@/components/chat/LinkPreview";
import { parseGameShare } from "@/lib/share-game";
import { compressImageToWebp } from "@/lib/image-compress";
import { GAME_TABLES, GAME_PART_TABLES } from "@/lib/game-tables";

// Check if a game share is expired/finished and delete the message
async function checkAndDeleteExpiredGameShare(msg: any, share: { slug: string; gameId: string }) {
  const table = GAME_TABLES[share.slug];
  if (!table) return;
  const { data: game } = await supabase.from(table as any).select("status, created_at").eq("id", share.gameId).maybeSingle();
  if (!game) {
    // Game deleted — remove the share message
    await supabase.from("chat_messages").update({ deleted_at: new Date().toISOString() }).eq("id", msg.id);
    return;
  }
  const status = (game as any).status;
  const createdAt = (game as any).created_at as string;
  // Only keep open/waiting games. Delete finished, expired, or playing games from chat.
  if (status === "finished") {
    await supabase.from("chat_messages").update({ deleted_at: new Date().toISOString() }).eq("id", msg.id);
    return;
  }
  // Expired: open/waiting for more than 6 minutes
  if (status === "open" || status === "waiting") {
    const expiresAt = createdAt ? new Date(createdAt).getTime() + 6 * 60_000 : 0;
    if (Date.now() >= expiresAt) {
      await supabase.from("chat_messages").update({ deleted_at: new Date().toISOString() }).eq("id", msg.id);
    }
  }
}

// ─── Constants ──────────────────────────────────────────────────────────────
const PAGE_SIZE = 40;
const MAX_CHARS = 500;

const EMOJIS = [
  "❤️","👍","😂","🔥","🎉","😢","😮","🙏","👏","💯",
  "🎮","🏆","😍","🤣","😅","🤩","💪","🫡","😤","🥳",
];


// ─── Subtle notification ping (Web Audio API — no external file) ─────────────
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
    gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + 0.35);
    osc.start(ctx.currentTime);
    osc.stop(ctx.currentTime + 0.35);
    osc.onended = () => ctx.close();
  } catch {
    // AudioContext not supported — silently skip
  }
}

const AUDIO_MIME_CANDIDATES = [
  "audio/webm;codecs=opus",
  "audio/webm",
  "audio/ogg;codecs=opus",
  "audio/mp4;codecs=mp4a.40.2",
  "audio/mp4",
  "audio/mpeg",
  "audio/aac",
];

const getAudioExt = (mime: string) =>
  mime.includes("mp4") ? "m4a" : mime.includes("ogg") ? "ogg" : mime.includes("mpeg") ? "mp3" : mime.includes("aac") ? "aac" : "webm";
const baseMime = (mime?: string) =>
  (mime || "").split(";")[0] || "application/octet-stream";

// ─── Helpers ─────────────────────────────────────────────────────────────────
function linkify(text: string) {
  const parts = text.split(/(https?:\/\/[^\s]+)/g);
  return parts.map((p, i) =>
    /^https?:\/\//.test(p) ? (
      <a key={i} href={p} target="_blank" rel="noopener noreferrer"
        className="underline text-primary break-all">{p}</a>
    ) : <span key={i}>{p}</span>
  );
}

/** Render message body: highlight @mentions and linkify URLs */
function renderBody(text: string) {
  const parts = text.split(/(@\w+)/g);
  return parts.map((p, i) =>
    /^@\w+/.test(p)
      ? <span key={i} className="text-primary font-semibold">{p}</span>
      : linkify(p)
  );
}

/** Group identical emoji reactions and count them */
function groupReactions(rxs: any[]) {
  const map: Record<string, { count: number; users: string[] }> = {};
  for (const r of rxs) {
    if (!map[r.emoji]) map[r.emoji] = { count: 0, users: [] };
    map[r.emoji].count++;
    map[r.emoji].users.push(r.user_id);
  }
  return map;
}

/** Human-readable timestamp: "HH:MM", "Hier HH:MM", or "DD MMM HH:MM" */
function formatTime(iso: string) {
  const d = new Date(iso);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  const isYesterday =
    new Date(now.getTime() - 86_400_000).toDateString() === d.toDateString();
  const time = d.toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" });
  if (isToday) return time;
  if (isYesterday) return `Hier ${time}`;
  return d.toLocaleDateString("fr-FR", { day: "numeric", month: "short" }) + ` ${time}`;
}

// ─── Sub-components ───────────────────────────────────────────────────────────
function MessageSkeleton() {
  return (
    <div className="space-y-3 p-3">
      {[...Array(6)].map((_, i) => (
        <div key={i} className={`flex gap-2 ${i % 2 === 0 ? "" : "flex-row-reverse"}`}>
          <div className="w-8 h-8 rounded-full bg-secondary animate-pulse shrink-0" />
          <div className={`flex flex-col gap-1 ${i % 2 === 0 ? "" : "items-end"}`}>
            <div className="h-3 w-14 rounded bg-secondary animate-pulse" />
            <div className={`h-10 rounded-2xl bg-secondary animate-pulse ${i % 2 === 0 ? "w-48" : "w-36"}`} />
          </div>
        </div>
      ))}
    </div>
  );
}

function ImageLightbox({ url, onClose }: { url: string; onClose: () => void }) {
  useEffect(() => {
    const h = (e: KeyboardEvent) => { if (e.key === "Escape") onClose(); };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-[100] bg-black/92 flex items-center justify-center p-4 backdrop-blur-sm"
      onClick={onClose}
    >
      <button
        className="absolute top-4 right-4 p-2 rounded-full bg-white/10 hover:bg-white/20 text-white transition-colors"
        onClick={onClose}
      >
        <X className="w-5 h-5" />
      </button>
      <img
        src={url} alt=""
        className="max-w-full max-h-[90dvh] rounded-2xl object-contain shadow-2xl"
        onClick={e => e.stopPropagation()}
      />
    </div>
  );
}

// ─── Main component ───────────────────────────────────────────────────────────
export default function ChatRoom({
  roomId, title, isAdmin, height = "h-[70dvh]", gameSlug, fullscreen = false, onBack, onOnlineCountChange, onOnlineUsersChange,
}: {
  roomId: string;
  title?: string;
  isAdmin?: boolean;
  height?: string;
  gameSlug?: string;
  fullscreen?: boolean;
  onBack?: () => void;
  onOnlineCountChange?: (count: number) => void;
  onOnlineUsersChange?: (users: Array<{ id: string; pseudo: string; avatar_url?: string | null }>) => void;
}) {
  const { t } = useT();
  const { user, profile } = useAuth();

  // ── Core state ──────────────────────────────────────────────────────────────
  const [messages, setMessages]   = useState<any[]>([]);
  const [profiles, setProfiles]   = useState<Record<string, any>>({});
  const [reactions, setReactions] = useState<Record<string, any[]>>({});
  const [loading, setLoading]     = useState(true);
  const [hasMore, setHasMore]     = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  // ── Input state ─────────────────────────────────────────────────────────────
  const [input, setInput]     = useState("");
  const [reply, setReply]     = useState<any>(null);
  const [editing, setEditing] = useState<any>(null);
  const [sending, setSending] = useState(false);

  // ── UI state ────────────────────────────────────────────────────────────────
  const [search, setSearch]           = useState("");
  const [showSearch, setShowSearch]   = useState(false);
  const [typing, setTyping]           = useState<string[]>([]);
  const [actionMenu, setActionMenu]   = useState<any>(null);
  const [profileMenu, setProfileMenu] = useState<{ id: string; pseudo?: string; avatar_url?: string | null } | null>(null);
  const navigate = useNavigate();
  const [customEmoji, setCustomEmoji] = useState("");
  const [lightboxUrl, setLightboxUrl] = useState<string | null>(null);
  const [showNewMsg, setShowNewMsg]   = useState(false);
  const [newMsgCount, setNewMsgCount] = useState(0);
  const [newMsgIds, setNewMsgIds]     = useState<Set<string>>(new Set());
  const [missingShares, setMissingShares] = useState<Set<string>>(new Set());
  const [heartAnim, setHeartAnim]     = useState<{ id: string; x: number; y: number } | null>(null);
  const [onlineUserIds, setOnlineUserIds] = useState<Set<string>>(new Set());
  const [muted, setMuted] = useState<boolean>(() => {
    try { return localStorage.getItem("chat_muted") === "1"; } catch { return false; }
  });

  const toggleMute = () => {
    setMuted(prev => {
      const next = !prev;
      try { localStorage.setItem("chat_muted", next ? "1" : "0"); } catch {}
      return next;
    });
  };

  // ── @mention state ──────────────────────────────────────────────────────────
  const [mentionQuery, setMentionQuery]           = useState<string | null>(null);
  const [mentionSuggestions, setMentionSuggestions] = useState<any[]>([]);
  const [mentionIndex, setMentionIndex]           = useState(0);

  // ── Audio state ─────────────────────────────────────────────────────────────
  const [recording, setRecording]   = useState(false);
  const [recElapsed, setRecElapsed] = useState(0);
  const [voicePreview, setVoicePreview] = useState<{ url: string; blob: Blob; duration: number } | null>(null);
  const [previewPlaying, setPreviewPlaying] = useState(false);

  // ── Refs ────────────────────────────────────────────────────────────────────
  const scrollRef      = useRef<HTMLDivElement>(null);
  const fileRef        = useRef<HTMLInputElement>(null);
  const textareaRef    = useRef<HTMLTextAreaElement>(null);
  const recRef         = useRef<MediaRecorder | null>(null);
  const recChunksRef   = useRef<Blob[]>([]);
  const recStreamRef   = useRef<MediaStream | null>(null);
  const recTimerRef    = useRef<number | null>(null);
  const previewAudioRef = useRef<HTMLAudioElement | null>(null);
  const longPressRef   = useRef<number | null>(null);
  const lastTapRef     = useRef<{ id: string; time: number } | null>(null);
  const isAtBottomRef  = useRef(true);
  const oldestRef      = useRef<string | null>(null);
  const messageRefs    = useRef<Record<string, HTMLDivElement | null>>({});
  // Track current voice preview URL separately for unmount cleanup
  const voicePreviewRef = useRef<string | null>(null);

  // ── Auto-resize textarea ────────────────────────────────────────────────────
  useEffect(() => {
    const ta = textareaRef.current;
    if (!ta) return;
    ta.style.height = "auto";
    ta.style.height = Math.min(ta.scrollHeight, 120) + "px";
  }, [input]);

  // ── Track scroll for "new message" button ───────────────────────────────────
  useEffect(() => {
    const el = scrollRef.current;
    if (!el) return;
    const onScroll = () => {
      const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
      isAtBottomRef.current = nearBottom;
      if (nearBottom) { setShowNewMsg(false); setNewMsgCount(0); }
    };
    el.addEventListener("scroll", onScroll, { passive: true });
    return () => el.removeEventListener("scroll", onScroll);
  }, []);

  // ── Cleanup voice Blob URL on unmount to prevent memory leak ────────────────
  useEffect(() => {
    return () => {
      previewAudioRef.current?.pause();
      previewAudioRef.current = null;
      if (voicePreviewRef.current) {
        URL.revokeObjectURL(voicePreviewRef.current);
        voicePreviewRef.current = null;
      }
      if (recTimerRef.current) window.clearInterval(recTimerRef.current);
      if (recStreamRef.current) recStreamRef.current.getTracks().forEach(t => t.stop());
    };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const scrollToBottom = useCallback((behavior: ScrollBehavior = "smooth") => {
    setTimeout(() => {
      scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior });
    }, 50);
    setShowNewMsg(false);
    setNewMsgCount(0);
  }, []);

  /** Scroll to a specific message and briefly highlight it */
  const scrollToMessage = useCallback((msgId: string) => {
    const el = messageRefs.current[msgId];
    if (!el) return;
    el.scrollIntoView({ behavior: "smooth", block: "center" });
    el.style.transition = "background-color 0.3s";
    el.style.backgroundColor = "hsl(var(--primary) / 0.12)";
    setTimeout(() => { el.style.backgroundColor = ""; }, 1500);
  }, []);

  // ── Data loaders ─────────────────────────────────────────────────────────────
  const loadProfiles = useCallback(async (ids: string[]) => {
    const missing = ids.filter(i => i && !profiles[i]);
    if (!missing.length) return;
    const { data } = await supabase.rpc("get_public_profiles_min" as any, { _ids: missing } as any);
    setProfiles(p => ({
      ...p,
      ...Object.fromEntries(((data as any[]) || []).map((x: any) => [x.id, x])),
    }));
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const loadReactions = useCallback(async (msgIds: string[]) => {
    if (!msgIds.length) return;
    const { data: r } = await supabase.from("chat_reactions").select("*").in("message_id", msgIds);
    const grouped: Record<string, any[]> = {};
    (r || []).forEach((x: any) => { (grouped[x.message_id] = grouped[x.message_id] || []).push(x); });
    setReactions(prev => ({ ...prev, ...grouped }));
  }, []);

  const loadMessages = useCallback(async () => {
    setLoading(true);
    const { data } = await supabase
      .from("chat_messages")
      .select("*")
      .eq("room_id", roomId)
      .is("deleted_at", null)
      .order("created_at", { ascending: false })
      .limit(PAGE_SIZE);
    const msgs = ((data || []) as any[]).reverse();
    setMessages(msgs);
    setHasMore((data || []).length === PAGE_SIZE);
    if (msgs.length > 0) oldestRef.current = msgs[0].created_at;
    setLoading(false);
    await loadProfiles(Array.from(new Set(msgs.map((m: any) => m.user_id))));
    await loadReactions(msgs.map((m: any) => m.id));
    scrollToBottom("instant");
  }, [roomId, loadProfiles, loadReactions, scrollToBottom]);

  const loadMore = useCallback(async () => {
    if (!hasMore || loadingMore || !oldestRef.current) return;
    setLoadingMore(true);
    const prevScrollHeight = scrollRef.current?.scrollHeight || 0;
    const { data } = await supabase
      .from("chat_messages")
      .select("*")
      .eq("room_id", roomId)
      .is("deleted_at", null)
      .lt("created_at", oldestRef.current)
      .order("created_at", { ascending: false })
      .limit(PAGE_SIZE);
    const older = ((data || []) as any[]).reverse();
    setMessages(prev => [...older, ...prev]);
    setHasMore(older.length === PAGE_SIZE);
    if (older.length > 0) oldestRef.current = older[0].created_at;
    setLoadingMore(false);
    await loadProfiles(Array.from(new Set(older.map((m: any) => m.user_id))));
    await loadReactions(older.map((m: any) => m.id));
    // Maintain scroll position after prepending old messages
    requestAnimationFrame(() => {
      if (scrollRef.current) {
        scrollRef.current.scrollTop = scrollRef.current.scrollHeight - prevScrollHeight;
      }
    });
  }, [hasMore, loadingMore, roomId, loadProfiles, loadReactions]);

  // ── Realtime subscription ────────────────────────────────────────────────────
  useEffect(() => {
    if (!roomId) return;
    supabase.rpc("chat_join_room" as any, { _room_id: roomId } as any);
    loadMessages();

    const ch = supabase.channel(`chat-${roomId}`)
      // New message
      .on("postgres_changes", {
        event: "INSERT", schema: "public",
        table: "chat_messages", filter: `room_id=eq.${roomId}`,
      }, async (payload: any) => {
        const msg = payload.new;
        if (msg.deleted_at) return;
        setMessages(prev => prev.find(m => m.id === msg.id) ? prev : [...prev, msg]);
        // Mark as new so it plays the entrance animation once
        setNewMsgIds(prev => new Set([...prev, msg.id]));
        setTimeout(() => setNewMsgIds(prev => { const next = new Set(prev); next.delete(msg.id); return next; }), 700);
        await loadProfiles([msg.user_id]);
        await loadReactions([msg.id]);
        if (isAtBottomRef.current) {
          scrollToBottom();
        } else if (msg.user_id !== user?.id) {
          setShowNewMsg(true);
          setNewMsgCount(c => c + 1);
          if (!muted) playPing();
        }
      })
      // Edited / deleted message
      .on("postgres_changes", {
        event: "UPDATE", schema: "public",
        table: "chat_messages", filter: `room_id=eq.${roomId}`,
      }, (payload: any) => {
        setMessages(prev =>
          payload.new.deleted_at
            ? prev.filter(m => m.id !== payload.new.id)
            : prev.map(m => m.id === payload.new.id ? { ...m, ...payload.new } : m)
        );
      })
      // Reactions
      .on("postgres_changes", {
        event: "*", schema: "public", table: "chat_reactions",
      }, async (payload: any) => {
        const msgId = (payload.new as any)?.message_id || (payload.old as any)?.message_id;
        if (msgId) await loadReactions([msgId]);
      })
      // Typing presence
      .on("postgres_changes", {
        event: "*", schema: "public", table: "chat_presence",
      }, async () => {
        const { data } = await supabase
          .from("chat_presence")
          .select("user_id,typing_until")
          .eq("typing_room", roomId)
          .gte("typing_until", new Date().toISOString());
        const names = await Promise.all(
          (data || []).filter((x: any) => x.user_id !== user?.id).map(async (x: any) => {
            if (!profiles[x.user_id]) {
              const { data: p } = await supabase.rpc("get_public_profiles_min" as any, { _ids: [x.user_id] } as any);
              const row = Array.isArray(p) ? (p[0] as any) : null;
              if (row) setProfiles(prev => ({ ...prev, [row.id]: row }));
              return row?.pseudo || "…";
            }
            return profiles[x.user_id].pseudo;
          })
        );
        setTyping(names.filter(Boolean));
      })
      .subscribe();
    // ── Room presence: track who has this room open ─────────────────────
    const presenceCh = supabase.channel(`room-presence-${roomId}`, {
      config: { presence: { key: user?.id || "anon" } },
    });
    presenceCh
      .on("presence", { event: "sync" }, async () => {
        const state = presenceCh.presenceState();
        const ids = new Set<string>(
          Object.values(state).flatMap((entries: any) => entries.map((e: any) => e.user_id)).filter(Boolean)
        );
        setOnlineUserIds(ids);
        onOnlineCountChange?.(ids.size);
        if (onOnlineUsersChange) {
          // Load any profiles we don't have yet
          const missing = Array.from(ids).filter(id => id && !profiles[id]);
          let enriched = { ...profiles };
          if (missing.length > 0) {
            const { data } = await supabase.rpc("get_public_profiles_min" as any, { _ids: missing } as any);
            ((data as any[]) || []).forEach((p: any) => { enriched[p.id] = p; });
            setProfiles(prev => ({ ...prev, ...Object.fromEntries(((data as any[]) || []).map((p: any) => [p.id, p])) }));
          }
          onOnlineUsersChange(
            Array.from(ids).map(id => ({
              id,
              pseudo: enriched[id]?.pseudo || "Joueur",
              avatar_url: enriched[id]?.avatar_url ?? null,
            }))
          );
        }
      })
      .subscribe(async (status) => {
        if (status === "SUBSCRIBED" && user?.id) {
          await presenceCh.track({ user_id: user.id, at: Date.now() });
        }
      });

    return () => { supabase.removeChannel(ch); supabase.removeChannel(presenceCh); };
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [roomId]);

  // ── @mention autocomplete ────────────────────────────────────────────────────
  useEffect(() => {
    if (mentionQuery === null || mentionQuery.length < 1) {
      setMentionSuggestions([]);
      return;
    }
    const timer = setTimeout(async () => {
      const { data } = await supabase
        .from("profiles")
        .select("id,pseudo,avatar_url")
        .ilike("pseudo", `${mentionQuery}%`)
        .limit(5);
      setMentionSuggestions(data || []);
    }, 200);
    return () => clearTimeout(timer);
  }, [mentionQuery]);

  const handleInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const val = e.target.value;
    if (val.length > MAX_CHARS) return;
    setInput(val);
    // Detect @mention at cursor
    const cursor = e.target.selectionStart;
    const before = val.slice(0, cursor);
    const match = before.match(/@(\w*)$/);
    if (match) { setMentionQuery(match[1]); setMentionIndex(0); }
    else { setMentionQuery(null); }
  };

  const insertMention = (pseudo: string) => {
    const cursor = textareaRef.current?.selectionStart ?? input.length;
    const before = input.slice(0, cursor).replace(/@\w*$/, `@${pseudo} `);
    const after  = input.slice(cursor);
    setInput(before + after);
    setMentionQuery(null);
    setMentionSuggestions([]);
    setTimeout(() => textareaRef.current?.focus(), 0);
  };

  // ── Paste image from clipboard ───────────────────────────────────────────────
  const handlePaste = async (e: React.ClipboardEvent<HTMLTextAreaElement>) => {
    const imgItem = Array.from(e.clipboardData.items).find(i => i.type.startsWith("image/"));
    if (!imgItem) return;
    e.preventDefault();
    const file = imgItem.getAsFile();
    if (!file) return;
    toast.promise(uploadFile(file), {
      loading: "Envoi de l'image…",
      success: "Image envoyée !",
      error: "Erreur lors de l'envoi",
    });
  };

  // ── Send ────────────────────────────────────────────────────────────────────
  const send = async () => {
    if (sending) return;
    const body = input.trim();
    if (!body && !editing) return;
    if (editing) {
      const { error } = await supabase.from("chat_messages")
        .update({ body, edited_at: new Date().toISOString() }).eq("id", editing.id);
      if (error) return toast.error(error.message);
      setEditing(null); setInput(""); return;
    }
    setSending(true);
    try {
      const { data: msgId, error } = await supabase.rpc("chat_send" as any, {
        _room_id: roomId, _body: body, _reply_to: reply?.id ?? null,
      } as any);
      if (error) {
        console.error("[chat] send error:", error);
        toast.error(error.message || "Erreur d'envoi");
        return;
      }
      // Local echo: add the message to the list immediately.
      // This avoids relying on Realtime (which can be unreliable due to
      // WebSocket drops, expired tokens, etc.) and avoids the skeleton
      // flash that loadMessages() causes (loading=true).
      // If Realtime also fires, the duplicate check (m.id === msgId)
      // prevents double-rendering.
      if (msgId) {
        setMessages(prev => prev.find(m => m.id === msgId) ? prev : [...prev, {
          id: msgId,
          room_id: roomId,
          user_id: user?.id,
          body,
          attachment_url: null,
          attachment_type: null,
          reply_to: reply?.id ?? null,
          pinned: false,
          edited_at: null,
          deleted_at: null,
          created_at: new Date().toISOString(),
          sender_name: profile?.pseudo ?? "Joueur",
          sender_avatar: profile?.avatar_url ?? null,
        }]);
        scrollToBottom();
      }
      setInput(""); setReply(null);
    } catch (err: any) {
      console.error("[chat] send exception:", err);
      toast.error(err?.message || "Échec de l'envoi du message");
    } finally {
      setSending(false);
    }
  };

  const sendTyping = async () => {
    await supabase.rpc("chat_typing" as any, { _room_id: roomId } as any);
  };

  // ── Reactions ────────────────────────────────────────────────────────────────
  const react = async (mid: string, emoji: string) => {
    const existing = (reactions[mid] || []).find(r => r.user_id === user?.id && r.emoji === emoji);
    if (existing) await supabase.from("chat_reactions").delete().eq("id", existing.id);
    else await supabase.from("chat_reactions").insert({ message_id: mid, user_id: user!.id, emoji });
    setEmojiOpen(null);
  };
  const [emojiOpen, setEmojiOpen] = useState<string | null>(null); // kept for compat

  // ── Moderation ───────────────────────────────────────────────────────────────
  const confirmDlg = useConfirm();

  const del = async (m: any) => {
    const ok = await confirmDlg({ title: t("delete_message_confirm"), confirmLabel: "Supprimer", destructive: true });
    if (!ok) return;
    await supabase.from("chat_messages").update({ deleted_at: new Date().toISOString() }).eq("id", m.id);
  };

  const pin = async (m: any) => {
    await supabase.rpc("chat_pin" as any, { _message_id: m.id, _pin: !m.pinned } as any);
  };

  const copyMessage = (body: string) => {
    copyText(body)
      .then(ok => ok ? toast.success("Copié !") : toast.error("Impossible de copier"))
      .catch(() => toast.error("Impossible de copier"));
  };

  const reportMessage = async (m: any) => {
    const ok = await confirmDlg({ title: "Signaler ce message à l'équipe ?", confirmLabel: "Signaler", destructive: true });
    if (!ok) return;
    // Best-effort: mark as reported if column exists, otherwise silently succeed
    await supabase.from("chat_messages" as any).update({ reported: true } as any).eq("id", m.id);
    toast.success("Message signalé — l'équipe a été notifiée");
  };

  // ── File upload ───────────────────────────────────────────────────────────────
  const uploadFile = async (rawFile: File): Promise<boolean> => {
    if (!user) return false;
    const f = rawFile.type.startsWith("image/") ? await compressImageToWebp(rawFile, { maxDim: 1280, maxSizeKB: 200 }) : rawFile;
    const ext = f.name.split(".").pop() || "bin";
    const path = `${user.id}/${Date.now()}.${ext}`;
    const { error } = await supabase.storage.from("chat").upload(path, f, {
      contentType: baseMime(f.type), upsert: false,
    });
    if (error) { toast.error(error.message); return false; }
    const { data: signed, error: sErr } = await supabase.storage
      .from("chat").createSignedUrl(path, 60 * 60 * 24 * 365 * 5);
    if (sErr || !signed?.signedUrl) { toast.error(sErr?.message || "Lien indisponible"); return false; }
    const url = signed.signedUrl;
    const type = f.type.startsWith("image/") ? "image"
      : f.type.startsWith("audio/") ? "audio" : "file";
    const { data: msgId, error: msgErr } = await supabase.rpc("chat_send" as any, {
      _room_id: roomId,
      _body: type === "file" ? f.name : "",
      _reply_to: null,
      _attachment_url: url,
      _attachment_type: type,
    } as any);
    if (msgErr) { toast.error(msgErr.message); return false; }
    // Local echo for file/image/audio messages too
    if (msgId) {
      setMessages(prev => prev.find(m => m.id === msgId) ? prev : [...prev, {
        id: msgId,
        room_id: roomId,
        user_id: user?.id,
        body: type === "file" ? f.name : "",
        attachment_url: url,
        attachment_type: type,
        reply_to: null,
        pinned: false,
        edited_at: null,
        deleted_at: null,
        created_at: new Date().toISOString(),
        sender_name: profile?.pseudo ?? "Joueur",
        sender_avatar: profile?.avatar_url ?? null,
      }]);
      scrollToBottom();
    }
    return true;
  };

  // ── Long-press (mobile action menu) ─────────────────────────────────────────
  const startLongPress = (m: any) => {
    if (longPressRef.current) window.clearTimeout(longPressRef.current);
    longPressRef.current = window.setTimeout(() => setActionMenu(m), 500);
  };
  const cancelLongPress = () => {
    if (longPressRef.current) { window.clearTimeout(longPressRef.current); longPressRef.current = null; }
  };

  /** Double-tap on mobile or double-click on desktop → ❤️ reaction */
  const handleDoubleTap = async (m: any, x: number, y: number) => {
    await react(m.id, "❤️");
    setHeartAnim({ id: m.id, x, y });
    setTimeout(() => setHeartAnim(null), 900);
  };

  const handleTouchEnd = (m: any, e: React.TouchEvent) => {
    cancelLongPress();
    const now = Date.now();
    const touch = e.changedTouches[0];
    if (
      lastTapRef.current &&
      lastTapRef.current.id === m.id &&
      now - lastTapRef.current.time < 320
    ) {
      lastTapRef.current = null;
      handleDoubleTap(m, touch.clientX, touch.clientY);
    } else {
      lastTapRef.current = { id: m.id, time: now };
    }
  };

  // ── Voice recording ───────────────────────────────────────────────────────────
  const startRecord = async () => {
    try {
      if (!navigator.mediaDevices?.getUserMedia || typeof MediaRecorder === "undefined") {
        toast.error(t("mic_unavailable")); return;
      }
      cancelVoice();
      // Request audio with echo cancellation for cleaner recordings
      const stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
        },
      });
      recStreamRef.current = stream;
      const mime = AUDIO_MIME_CANDIDATES.find(m => MediaRecorder.isTypeSupported(m)) || "";
      const rec = mime ? new MediaRecorder(stream, { mimeType: mime }) : new MediaRecorder(stream);
      recChunksRef.current = [];
      const startedAt = Date.now();
      rec.ondataavailable = e => { if (e.data.size > 0) recChunksRef.current.push(e.data); };
      rec.onstop = () => {
        window.setTimeout(() => {
          const type = rec.mimeType || mime || "audio/webm";
          const chunks = recChunksRef.current.filter(c => c.size > 0);
          const blob = new Blob(chunks, { type });
          recStreamRef.current?.getTracks().forEach(t => t.stop());
          recStreamRef.current = null;
          recRef.current = null;
          if (blob.size < 256) { toast.error("Vocal vide, veuillez réessayer."); return; }
          const url = URL.createObjectURL(blob);
          const duration = Math.max(1, Math.round((Date.now() - startedAt) / 1000));
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
      recTimerRef.current = window.setInterval(() => setRecElapsed(s => s + 1), 1000);
    } catch (err: any) {
      // Stop any partial stream
      if (recStreamRef.current) {
        recStreamRef.current.getTracks().forEach(t => t.stop());
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
      try { recRef.current.requestData(); } catch {}
      recRef.current.stop();
    }
    setRecording(false);
    if (recTimerRef.current) { window.clearInterval(recTimerRef.current); recTimerRef.current = null; }
  };

  const togglePreview = () => {
    if (!voicePreview) return;
    if (!previewAudioRef.current) {
      previewAudioRef.current = new Audio(voicePreview.url);
      previewAudioRef.current.onended = () => setPreviewPlaying(false);
    }
    if (previewPlaying) { previewAudioRef.current.pause(); setPreviewPlaying(false); }
    else { previewAudioRef.current.play(); setPreviewPlaying(true); }
  };

  const cancelVoice = () => {
    previewAudioRef.current?.pause();
    previewAudioRef.current = null;
    if (voicePreviewRef.current) { URL.revokeObjectURL(voicePreviewRef.current); voicePreviewRef.current = null; }
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

  // ── Derived data ──────────────────────────────────────────────────────────────
  const pinned   = messages.filter(m => m.pinned);
  const filtered = search
    ? messages.filter(m => m.body?.toLowerCase().includes(search.toLowerCase()))
    : messages;

  // ── Render ────────────────────────────────────────────────────────────────────
  return (
    <div className={`flex flex-col ${
      fullscreen
        ? "h-[calc(100dvh-7.5rem)] bg-card"
        : `${height} bg-card rounded-3xl shadow-[var(--shadow-soft)]`
    } overflow-hidden`}>

      {/* ── Lightbox ── */}
      {lightboxUrl && <ImageLightbox url={lightboxUrl} onClose={() => setLightboxUrl(null)} />}

      {/* ── Heart pop animation overlay ── */}
      <style>{`
        @keyframes heartPop {
          0%   { transform: scale(0) translateY(0);    opacity: 0; }
          20%  { transform: scale(1.5) translateY(-4px); opacity: 1; }
          55%  { transform: scale(1.1) translateY(-14px); opacity: 1; }
          100% { transform: scale(0.6) translateY(-28px); opacity: 0; }
        }
      `}</style>
      {heartAnim && (
        <div
          className="fixed z-[200] pointer-events-none select-none text-3xl drop-shadow-lg"
          style={{
            left: heartAnim.x - 18,
            top:  heartAnim.y - 18,
            animation: "heartPop 0.85s cubic-bezier(0.22, 1, 0.36, 1) forwards",
          }}
        >
          ❤️
        </div>
      )}

      {/* ── Header ── */}
      <div className="px-3 py-2 border-b border-white/8 flex items-center gap-2 shrink-0 bg-background/30">
        {onBack && (
          <button
            onClick={onBack}
            className="p-1.5 rounded-full hover:bg-white/8 text-muted-foreground hover:text-foreground transition-all"
            aria-label="Retour"
          >
            <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M19 12H5"/><path d="m12 19-7-7 7-7"/></svg>
          </button>
        )}
        {title && <span className="font-semibold text-sm flex-1 truncate">{title}</span>}
        <button
          onClick={() => setShowSearch(s => !s)}
          className="flex items-center gap-1.5 px-3 py-1.5 rounded-full text-xs font-medium text-muted-foreground hover:bg-white/8 hover:text-foreground transition-all border border-transparent hover:border-white/10 ml-auto"
        >
          <Search className="w-3.5 h-3.5" />
          Rechercher
        </button>
        <button
          onClick={toggleMute}
          title={muted ? "Réactiver les sons" : "Couper les sons"}
          className={`p-1.5 rounded-full hover:bg-white/8 shrink-0 transition-all ${muted ? "text-destructive/70 hover:text-destructive" : "text-muted-foreground hover:text-foreground"}`}
        >
          {muted ? <BellOff className="w-4 h-4" /> : <Bell className="w-4 h-4" />}
        </button>
      </div>

      {/* ── Search bar ── */}
      {showSearch && (
        <div className="px-3 py-2 border-b border-white/8 bg-background/40 shrink-0 animate-in slide-in-from-top-1 fade-in duration-150">
          <input
            value={search} onChange={e => setSearch(e.target.value)}
            placeholder={t("search_placeholder")} autoFocus
            className="w-full px-3 py-1.5 rounded-full bg-card/80 border border-white/10 outline-none text-sm focus:border-primary/40 focus:ring-1 focus:ring-primary/20 transition-all placeholder:text-muted-foreground/50"
          />
        </div>
      )}

      {/* ── Pinned message ── */}
      {pinned.length > 0 && (
        <button
          onClick={() => scrollToMessage(pinned[pinned.length - 1].id)}
          className="w-full text-left px-4 py-2.5 border-b border-amber-500/20 bg-gradient-to-r from-amber-500/10 to-amber-400/5 text-xs flex items-center gap-2 hover:from-amber-500/15 hover:to-amber-400/10 transition-all shrink-0"
        >
          <Pin className="w-3 h-3 text-amber-500 shrink-0" />
          <span className="font-bold text-amber-600 dark:text-amber-400 shrink-0">Épinglé ·</span>
          <span className="truncate text-foreground/70">{pinned[pinned.length - 1].body}</span>
        </button>
      )}

      {/* ── Messages area ── */}
      <div ref={scrollRef} className="flex-1 overflow-y-auto relative" style={{ backgroundImage: "radial-gradient(ellipse at top, hsl(var(--primary)/0.04) 0%, transparent 70%)" }}>
        {loading ? <MessageSkeleton /> : (
          <>
            {/* Load more */}
            {hasMore && (
              <div className="flex justify-center py-3">
                <button
                  onClick={loadMore} disabled={loadingMore}
                  className="px-4 py-1.5 rounded-full bg-card border border-white/10 text-xs font-semibold hover:bg-accent disabled:opacity-40 transition-all shadow-sm"
                >
                  {loadingMore ? (
                    <span className="flex items-center gap-1.5">
                      <span className="w-3 h-3 rounded-full border-2 border-primary/30 border-t-primary animate-spin" />
                      Chargement…
                    </span>
                  ) : "↑ Messages précédents"}
                </button>
              </div>
            )}

            <div className="p-3 space-y-2">
              {filtered.map(m => {
                const mine     = m.user_id === user?.id;
                // Identity is frozen at send time (sender_name / sender_avatar) so an
                // older message never changes name when a profile is renamed later.
                const snap     = m.sender_name ? { pseudo: m.sender_name, avatar_url: m.sender_avatar ?? null } : null;
                const p        = snap ?? (mine ? profile : profiles[m.user_id]);
                const replied  = m.reply_to ? messages.find(x => x.id === m.reply_to) : null;
                const repliedP = replied
                  ? (replied.sender_name
                      ? { pseudo: replied.sender_name, avatar_url: replied.sender_avatar ?? null }
                      : (replied.user_id === user?.id ? profile : profiles[replied.user_id]))
                  : null;
                const rxGroups  = groupReactions(reactions[m.id] || []);
                const hasRx     = Object.keys(rxGroups).length > 0;
                const initials  = (p?.pseudo || "?").slice(0, 2).toUpperCase();
                const share     = parseGameShare(m.body);
                const isDeleted = !!m.deleted_at;
                if (share && missingShares.has(m.id)) return null;
                if (share) {
                  // Check game status — delete expired/finished game shares
                  setTimeout(() => checkAndDeleteExpiredGameShare(m, share), 0);
                }

                return (
                  <div
                    key={m.id}
                    ref={el => { messageRefs.current[m.id] = el; }}
                    className={`flex gap-2.5 items-end ${mine ? "flex-row-reverse" : ""} px-1 ${
                      newMsgIds.has(m.id)
                        ? mine
                          ? "animate-in slide-in-from-right-4 fade-in duration-300"
                          : "animate-in slide-in-from-left-4 fade-in duration-300"
                        : ""
                    }`}
                  >
                    {/* Avatar with online indicator */}
                    <button
                      type="button"
                      onClick={() => {
                        if (mine || !p) return;
                        setProfileMenu({ id: m.user_id, pseudo: p.pseudo, avatar_url: p.avatar_url });
                      }}
                      className={`relative w-8 h-8 shrink-0 ${mine ? "cursor-default" : "cursor-pointer active:scale-95 transition-transform"}`}
                      aria-label={mine ? undefined : `Profil de ${p?.pseudo || "joueur"}`}
                    >
                      <div className="w-8 h-8 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-xs font-bold ring-2 ring-background shadow-sm">
                        {p?.avatar_url
                          ? <img src={p.avatar_url} width={32} height={32} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                          : <span className="text-primary">{initials}</span>}
                      </div>
                      {onlineUserIds.has(m.user_id) && (
                        <span className="absolute bottom-0 right-0 w-2.5 h-2.5 rounded-full bg-green-500 ring-2 ring-background shadow-sm" />
                      )}
                    </button>

                    <div className="max-w-[78%] group">
                      {/* Name + timestamp */}
                      <div className={`text-[11px] font-semibold mb-1 px-1 flex items-center gap-1.5 ${mine ? "justify-end" : ""}`}>
                        {!mine && (
                          <button
                            type="button"
                            onClick={() => p && setProfileMenu({ id: m.user_id, pseudo: p.pseudo, avatar_url: p.avatar_url })}
                            className="text-primary/80 truncate hover:underline"
                          >
                            {p?.pseudo || "…"}
                          </button>
                        )}
                        <span className="text-muted-foreground/40 font-normal text-[10px] opacity-0 group-hover:opacity-100 transition-opacity whitespace-nowrap">
                          {formatTime(m.created_at)}
                        </span>
                      </div>

                      {/* Reply preview — clickable to jump to original */}
                      {replied && (
                        <button
                          className="w-full text-left text-[11px] px-3 py-1.5 mb-1.5 rounded-xl bg-primary/8 border-l-2 border-primary/60 truncate hover:bg-primary/12 transition-colors"
                          onClick={() => scrollToMessage(replied.id)}
                        >
                          <span className="font-semibold opacity-70">↩ {repliedP?.pseudo || "…"}</span>
                          <span className="opacity-70"> · </span>
                          {replied.attachment_type === "audio" ? "🎤 Vocal"
                            : replied.attachment_type === "image" ? "🖼️ Image"
                            : (replied.body || "").slice(0, 60)}
                        </button>
                      )}

                      {/* Bubble */}
                      {share && !isDeleted ? (
                        <div onContextMenu={e => { e.preventDefault(); setActionMenu(m); }}>
                          <GameShareCard slug={share.slug} gameId={share.gameId} onMissing={() => setMissingShares(prev => { if (prev.has(m.id)) return prev; const n = new Set(prev); n.add(m.id); return n; })} />
                        </div>
                      ) : (
                        <div
                          className={`px-3.5 py-2 text-sm break-words whitespace-pre-wrap select-none relative rounded-[18px] ${
                            mine
                              ? "bg-primary text-primary-foreground shadow-sm"
                              : "bg-[#E4E6EB] text-[#050505] dark:bg-[#3A3B3C] dark:text-[#E4E6EB] shadow-sm"
                          }`}
                          onTouchStart={() => startLongPress(m)}
                          onTouchEnd={e => handleTouchEnd(m, e)}
                          onTouchMove={cancelLongPress}
                          onDoubleClick={e => handleDoubleTap(m, e.clientX, e.clientY)}
                          onContextMenu={e => { e.preventDefault(); setActionMenu(m); }}
                        >
                          {/* Image — click to open lightbox */}
                          {m.attachment_url && m.attachment_type === "image" && (
                            <img
                              src={m.attachment_url} alt=""
                              className="rounded-xl max-h-56 max-w-full cursor-zoom-in hover:opacity-90 transition-opacity"
                              onClick={() => setLightboxUrl(m.attachment_url)}
                            />
                          )}
                          {/* Audio */}
                          {m.attachment_url && m.attachment_type === "audio" && (
                            <audio controls src={m.attachment_url} className="max-w-full min-w-[200px]" />
                          )}
                          {/* File attachment */}
                          {m.attachment_url && m.attachment_type === "file" && (
                            <a href={m.attachment_url} target="_blank" rel="noopener noreferrer"
                              className="flex items-center gap-2 underline text-sm">
                              <Paperclip className="w-4 h-4 shrink-0" />
                              <span className="break-all">{m.body || "Fichier"}</span>
                            </a>
                          )}
                          {/* Text body */}
                          {m.body && m.attachment_type !== "file" && (
                            isDeleted
                              ? <span className="italic opacity-40">Message supprimé</span>
                              : <span>{renderBody(m.body)}</span>
                          )}
                          {/* Link preview card — only for plain text messages with URLs */}
                          {m.body && !m.attachment_url && !isDeleted && /https?:\/\//.test(m.body) && (
                            <LinkPreviewCard text={m.body} />
                          )}
                          {/* Edited badge + timestamp */}
                          <div className={`flex items-center gap-1 mt-1 ${mine ? "justify-end" : ""}`}>
                            {m.edited_at && !isDeleted && (
                              <span className="text-[9px] opacity-40">modifié ·</span>
                            )}
                            <span className="text-[9px] opacity-30">
                              {new Date(m.created_at).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}
                            </span>
                          </div>
                        </div>
                      )}

                      {/* Grouped reactions with counts */}
                      {hasRx && (
                        <div className={`flex gap-1 mt-1 flex-wrap ${mine ? "justify-end" : ""}`}>
                          {Object.entries(rxGroups).map(([emoji, { count, users }]) => {
                            const isMine = users.includes(user?.id || "");
                            return (
                              <button
                                key={emoji}
                                onClick={() => react(m.id, emoji)}
                                title={`${count} réaction${count > 1 ? "s" : ""}`}
                                className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-xs border transition-all active:scale-90 ${
                                  isMine
                                    ? "bg-primary/15 border-primary/30 text-primary font-semibold"
                                    : "bg-card border-white/10 hover:bg-accent shadow-sm"
                                }`}
                              >
                                <span>{emoji}</span>
                                {count > 1 && <span className="font-bold text-[10px]">{count}</span>}
                              </button>
                            );
                          })}
                        </div>
                      )}
                    </div>
                  </div>
                );
              })}
            </div>
          </>
        )}

        {/* ── "New message" button ── */}
        {showNewMsg && (
          <button
            onClick={() => scrollToBottom()}
            className="absolute bottom-4 left-1/2 -translate-x-1/2 flex items-center gap-1.5 px-4 py-2 rounded-full bg-primary text-primary-foreground text-xs font-bold shadow-xl shadow-primary/30 hover:scale-105 active:scale-95 transition-all z-10 animate-in slide-in-from-bottom-2 fade-in duration-200"
          >
            <ArrowDown className="w-3 h-3 animate-bounce" />
            {newMsgCount > 1 ? `${newMsgCount} nouveaux messages` : "Nouveau message"}
          </button>
        )}
      </div>

      {/* ── Typing indicator ── */}
      {typing.length > 0 && (
        <div className="px-4 pb-2 flex items-center gap-2.5 shrink-0 animate-in fade-in slide-in-from-bottom-1 duration-200">
          <div className="flex items-center gap-1 px-3 py-2.5 rounded-[18px] bg-[#E4E6EB] dark:bg-[#3A3B3C] shadow-sm">
            <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce" style={{ animationDelay: "0ms" }} />
            <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce" style={{ animationDelay: "150ms" }} />
            <span className="w-1.5 h-1.5 rounded-full bg-muted-foreground/50 animate-bounce" style={{ animationDelay: "300ms" }} />
          </div>
          <span className="text-[10px] text-muted-foreground/50 font-medium">
            {typing.length === 1 ? `${typing[0]} écrit…` : `${typing.length} personnes écrivent…`}
          </span>
        </div>
      )}

      {/* ── Reply / edit banner ── */}
      {(reply || editing) && (
        <div className="mx-3 mb-1 px-3 py-2 rounded-xl bg-primary/8 border-l-2 border-primary/60 flex items-center justify-between text-xs shrink-0 animate-in slide-in-from-bottom-1 fade-in duration-150">
          <div className="truncate">
            {editing ? (
              <><span className="font-semibold text-primary">Modifier · </span>{editing.body?.slice(0, 60)}</>
            ) : (
              <><span className="font-semibold">↩ {reply?.user_id === user?.id ? "Vous" : profiles[reply?.user_id]?.pseudo || "…"} · </span>{reply?.body?.slice(0, 60)}</>
            )}
          </div>
          <button onClick={() => { setReply(null); setEditing(null); setInput(""); }}
            className="ml-2 p-1 rounded-full hover:bg-accent shrink-0">
            <X className="w-3 h-3" />
          </button>
        </div>
      )}

      {/* ── @mention suggestions ── */}
      {mentionSuggestions.length > 0 && (
        <div className="mx-3 mb-1 rounded-2xl bg-card border border-border shadow-lg overflow-hidden shrink-0 max-h-40 overflow-y-auto">
          {mentionSuggestions.map((s, i) => (
            <button
              key={s.id}
              className={`w-full flex items-center gap-2 px-3 py-2 text-sm hover:bg-accent transition-colors text-left ${i === mentionIndex ? "bg-accent" : ""}`}
              onMouseDown={e => { e.preventDefault(); insertMention(s.pseudo); }}
            >
              <div className="w-6 h-6 rounded-full bg-secondary overflow-hidden shrink-0 flex items-center justify-center text-[10px] font-bold">
                {s.avatar_url
                  ? <img src={s.avatar_url} width={40} height={40} loading="lazy" decoding="async" className="w-full h-full object-cover" alt="" />
                  : (s.pseudo || "?").slice(0, 2).toUpperCase()}
              </div>
              <span className="font-medium">@{s.pseudo}</span>
            </button>
          ))}
        </div>
      )}

      {/* ── Voice preview bar ── */}
      {voicePreview && (
        <div className="mx-3 mb-1 px-3 py-2 rounded-2xl bg-secondary flex items-center gap-2 shrink-0">
          <button onClick={togglePreview} className="p-1.5 rounded-full bg-primary text-primary-foreground">
            {previewPlaying ? <Pause className="w-3 h-3" /> : <Play className="w-3 h-3" />}
          </button>
          <div className="flex-1 h-1.5 rounded-full bg-border overflow-hidden">
            <div className="h-full w-1/3 bg-primary rounded-full" />
          </div>
          <span className="text-xs text-muted-foreground tabular-nums">{voicePreview.duration}s</span>
          <button onClick={sendVoice} className="p-1.5 rounded-full bg-primary text-primary-foreground">
            <Send className="w-3 h-3" />
          </button>
          <button onClick={cancelVoice} className="p-1.5 rounded-full bg-destructive/10 text-destructive">
            <X className="w-3 h-3" />
          </button>
        </div>
      )}

      {/* ── Input bar — Messenger-style ── */}
      <div className="px-2.5 py-2 border-t border-border bg-card flex items-center gap-1.5 shrink-0">
        {/* Image / file attachment */}
        <button
          onClick={() => fileRef.current?.click()}
          className="p-2 rounded-full hover:bg-accent text-primary shrink-0 transition-all"
        >
          <ImageIcon className="w-5 h-5" />
        </button>
        <input
          ref={fileRef} type="file" accept="image/*,audio/*,.pdf,.doc,.docx" className="hidden"
          onChange={async e => { const f = e.target.files?.[0]; if (f) await uploadFile(f); e.target.value = ""; }}
        />

        {/* Mic (only when nothing typed and not recording) */}
        {!input.trim() && !recording && (
          <button
            onClick={startRecord}
            title="Enregistrer un message vocal"
            className="p-2 rounded-full hover:bg-accent text-primary shrink-0 transition-all active:scale-90"
          >
            <Mic className="w-5 h-5" />
          </button>
        )}

        {recording ? (
          <div className="flex-1 flex items-center gap-2 px-4 py-2 rounded-full bg-[#F0F2F5] dark:bg-[#3A3B3C]">
            <span className="w-2 h-2 rounded-full bg-destructive animate-pulse shrink-0" />
            <span className="text-xs text-destructive font-mono tabular-nums flex-1">{recElapsed}s</span>
            <button onClick={stopRecord} className="p-1.5 rounded-full bg-destructive text-white shrink-0">
              <Square className="w-3.5 h-3.5" />
            </button>
          </div>
        ) : (
          /* Pill-shaped input with trailing emoji button */
          <div className="flex-1 relative flex items-end gap-1 px-1.5 py-1 rounded-full bg-[#F0F2F5] dark:bg-[#3A3B3C]">
            <textarea
              ref={textareaRef}
              rows={1}
              value={input}
              onChange={handleInputChange}
              onPaste={handlePaste}
              onKeyDown={e => {
                // @mention keyboard navigation
                if (mentionSuggestions.length > 0) {
                  if (e.key === "ArrowDown") { e.preventDefault(); setMentionIndex(i => Math.min(i + 1, mentionSuggestions.length - 1)); return; }
                  if (e.key === "ArrowUp")   { e.preventDefault(); setMentionIndex(i => Math.max(i - 1, 0)); return; }
                  if (e.key === "Enter" || e.key === "Tab") { e.preventDefault(); insertMention(mentionSuggestions[mentionIndex]?.pseudo); return; }
                  if (e.key === "Escape") { setMentionQuery(null); setMentionSuggestions([]); return; }
                }
                if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); send(); }
              }}
              onInput={sendTyping}
              placeholder={editing ? "Modifier le message…" : "Message"}
              className="flex-1 min-w-0 px-2.5 py-1.5 bg-transparent outline-none text-sm resize-none leading-5 max-h-[120px] overflow-y-auto"
              style={{ height: "auto" }}
            />
            {/* Character counter — shown when approaching limit */}
            {input.length > MAX_CHARS * 0.8 && (
              <div className={`absolute -top-5 right-1 text-[10px] font-semibold tabular-nums ${
                input.length >= MAX_CHARS ? "text-destructive" : "text-muted-foreground"
              }`}>
                {MAX_CHARS - input.length}
              </div>
            )}
            <button
              type="button"
              onClick={() => setInput(v => v + "😊")}
              className="p-1.5 rounded-full hover:bg-black/5 dark:hover:bg-white/10 text-amber-500 shrink-0 transition-all"
              title="Emoji"
            >
              <Smile className="w-5 h-5" />
            </button>
          </div>
        )}

        {/* Send button (only when there's text) */}
        {input.trim() && (
          <button
            onClick={send}
            disabled={sending}
            className="p-2 rounded-full bg-primary text-primary-foreground hover:scale-105 active:scale-90 shrink-0 transition-all shadow-md shadow-primary/30 disabled:opacity-50 disabled:scale-90"
          >
            {sending
              ? <span className="w-4 h-4 border-2 border-white/40 border-t-white rounded-full animate-spin block" />
              : <Send className="w-4 h-4" />}
          </button>
        )}
      </div>

      {/* ── Action menu (bottom sheet) ── */}
      {actionMenu && (
        <div
          className="fixed inset-0 z-50 bg-black/40 flex items-end justify-center p-4 backdrop-blur-sm"
          onClick={() => { setActionMenu(null); setCustomEmoji(""); }}
        >
          <div
            className="w-full max-w-sm bg-card/95 backdrop-blur-md rounded-3xl p-4 space-y-3 shadow-2xl border border-white/8 animate-in slide-in-from-bottom-3 fade-in duration-200"
            onClick={e => e.stopPropagation()}
          >
            {/* Quick emoji reactions */}
            <div>
              <div className="text-[11px] uppercase text-muted-foreground mb-2 font-semibold tracking-wide">Réagir</div>
              <div className="flex gap-1 flex-wrap">
                {EMOJIS.map(e => (
                  <button
                    key={e}
                    onClick={() => { react(actionMenu.id, e); setActionMenu(null); }}
                    className="text-xl hover:scale-125 transition-transform p-0.5 active:scale-110"
                  >{e}</button>
                ))}
              </div>
              {/* Custom emoji input */}
              <div className="mt-2 flex gap-2">
                <input
                  value={customEmoji} onChange={e => setCustomEmoji(e.target.value)}
                  placeholder="😀 Autre emoji…"
                  className="flex-1 px-3 py-2 rounded-2xl bg-secondary outline-none text-sm"
                />
                <button
                  onClick={() => { if (customEmoji.trim()) { react(actionMenu.id, customEmoji.trim()); setCustomEmoji(""); setActionMenu(null); } }}
                  className="px-3 py-2 rounded-2xl bg-primary text-primary-foreground font-semibold text-sm"
                >OK</button>
              </div>
            </div>

            {/* Action buttons */}
            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => { setReply(actionMenu); setActionMenu(null); }}
                className="py-2.5 rounded-2xl bg-secondary font-semibold text-sm flex items-center justify-center gap-1.5"
              >
                <Reply className="w-4 h-4" /> Répondre
              </button>

              {actionMenu.body && (
                <button
                  onClick={() => { copyMessage(actionMenu.body); setActionMenu(null); }}
                  className="py-2.5 rounded-2xl bg-secondary font-semibold text-sm flex items-center justify-center gap-1.5"
                >
                  <Copy className="w-4 h-4" /> Copier
                </button>
              )}

              {actionMenu.user_id === user?.id && (
                <button
                  onClick={() => { setEditing(actionMenu); setInput(actionMenu.body || ""); setActionMenu(null); }}
                  className="py-2.5 rounded-2xl bg-secondary font-semibold text-sm flex items-center justify-center gap-1.5"
                >
                  <Pencil className="w-4 h-4" /> Modifier
                </button>
              )}

              {actionMenu.user_id !== user?.id && (
                <button
                  onClick={() => { reportMessage(actionMenu); setActionMenu(null); }}
                  className="py-2.5 rounded-2xl bg-orange-500/10 text-orange-600 dark:text-orange-400 font-semibold text-sm flex items-center justify-center gap-1.5"
                >
                  <Flag className="w-4 h-4" /> Signaler
                </button>
              )}

              {(actionMenu.user_id === user?.id || isAdmin) && (
                <button
                  onClick={() => { del(actionMenu); setActionMenu(null); }}
                  className="py-2.5 rounded-2xl bg-destructive/10 text-destructive font-semibold text-sm flex items-center justify-center gap-1.5"
                >
                  <Trash2 className="w-4 h-4" /> Supprimer
                </button>
              )}

              {isAdmin && (
                <button
                  onClick={() => { pin(actionMenu); setActionMenu(null); }}
                  className="py-2.5 rounded-2xl bg-amber-500/15 text-amber-700 dark:text-amber-400 font-semibold text-sm flex items-center justify-center gap-1.5"
                >
                  <Pin className="w-4 h-4" /> {actionMenu.pinned ? "Désépingler" : "Épingler"}
                </button>
              )}
            </div>

            <button
              onClick={() => { setActionMenu(null); setCustomEmoji(""); }}
              className="w-full py-2 rounded-full bg-secondary text-sm font-medium"
            >Fermer</button>
          </div>
        </div>
      )}

      {/* Profile action menu (click on avatar / pseudo) */}
      {profileMenu && (
        <div
          className="fixed inset-0 z-50 bg-black/50 backdrop-blur-sm flex items-end sm:items-center justify-center p-4 animate-in fade-in duration-150"
          onClick={() => setProfileMenu(null)}
        >
          <div
            className="w-full max-w-sm bg-background rounded-3xl p-4 space-y-3 shadow-2xl animate-in slide-in-from-bottom-4 duration-200"
            onClick={e => e.stopPropagation()}
          >
            <div className="flex items-center gap-3 px-1">
              <div className="w-12 h-12 rounded-full bg-primary/15 overflow-hidden flex items-center justify-center text-sm font-bold ring-2 ring-background shadow-sm">
                {profileMenu.avatar_url
                  ? <img src={profileMenu.avatar_url} className="w-full h-full object-cover" alt="" />
                  : <span className="text-primary">{(profileMenu.pseudo || "?").slice(0, 2).toUpperCase()}</span>}
              </div>
              <div className="min-w-0">
                <div className="font-bold truncate">{profileMenu.pseudo || "Joueur"}</div>
                <div className="text-[11px] text-muted-foreground">Choisir une action</div>
              </div>
            </div>

            <div className="grid gap-2">
              <button
                onClick={() => {
                  const id = profileMenu.id;
                  setProfileMenu(null);
                  navigate({ to: "/joueur/$id", params: { id } });
                }}
                className="py-3 rounded-2xl bg-primary/10 text-primary font-semibold text-sm flex items-center justify-center gap-2"
              >
                Voir le profil
              </button>
              <button
                onClick={() => {
                  const id = profileMenu.id;
                  setProfileMenu(null);
                  navigate({ to: "/chat", search: { dm: id } as any });
                }}
                className="py-3 rounded-2xl bg-primary text-primary-foreground font-semibold text-sm flex items-center justify-center gap-2 shadow-sm"
              >
                Envoyer un message
              </button>
            </div>

            <button
              onClick={() => setProfileMenu(null)}
              className="w-full py-2 rounded-full bg-secondary text-sm font-medium"
            >Fermer</button>
          </div>
        </div>
      )}
    </div>
  );
}
