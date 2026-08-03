import { useEffect, useRef, useState, useCallback, useMemo } from "react";
import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport, type UIMessage } from "ai";
import { Bot, X, Send, Sparkles, WifiOff, Trash2 } from "lucide-react";
import { supabase } from "@/integrations/supabase/client";
import { useT } from "@/lib/i18n";
import { toast } from "sonner";

const ROW_TO_UI = (r: { id: string; role: string; content: string }): UIMessage =>
  ({ id: r.id, role: r.role as any, parts: [{ type: "text", text: r.content }] }) as any;

// ─────────────────────────────────────────────────────────────────────────────
// Collecte le contexte temps réel de l'application pour l'injecter dans l'IA
// ─────────────────────────────────────────────────────────────────────────────
const GAME_TABLES: Record<string, string> = {
  ludo: "ludo_games",
  domino: "domino_games",
  fanorona: "fanorona_games",
  chess: "chess_games",
  rami: "rami_games",
  poker: "poker_games",
};
const GAME_LABELS: Record<string, string> = {
  ludo: "Ludo", domino: "Domino", fanorona: "Fanorona",
  chess: "Échecs", rami: "Rami", poker: "Poker",
};
const KIND_LABEL: Record<string, string> = {
  game_win: "✅ Victoire",
  game_loss: "❌ Défaite",
  tournament_win: "🏆 Tournoi gagné",
};

async function buildAppContext(userId: string): Promise<string> {
  const now = new Date();
  const page = typeof window !== "undefined" ? window.location.pathname : "inconnue";

  const pageNames: Record<string, string> = {
    "/": "Accueil",
    "/jeux": "Créer/Rejoindre une partie",
    "/live": "LIVE en direct",
    "/chat": "Discussion",
    "/profile": "Profil",
    "/history": "Historique",
    "/rankings": "Classement",
    "/tournaments": "Tournois",
    "/parrainage": "Parrainage",
    "/tutos": "Tutoriels",
  };
  const pageName = pageNames[page] || page;

  const results = await Promise.allSettled([
    // Profil utilisateur
    supabase.from("profiles")
      .select("pseudo, balance_ar, is_premium, status")
      .eq("id", userId).maybeSingle(),
    // Parties ouvertes par jeu
    Promise.all(
      Object.entries(GAME_TABLES).map(async ([slug, table]) => {
        const { count } = await supabase
          .from(table as any)
          .select("id", { count: "exact", head: true })
          .eq("status", "open");
        return { slug, count: count ?? 0 };
      })
    ),
    // Parties LIVE en cours
    supabase.rpc("list_live_games" as any),
    // Dernières parties jouées (résultats uniquement)
    supabase
      .from("transactions")
      .select("kind, amount, created_at, meta")
      .eq("user_id", userId)
      .in("kind", ["game_win", "game_loss", "tournament_win"])
      .order("created_at", { ascending: false })
      .limit(5),
  ]);

  const profile = results[0].status === "fulfilled" ? (results[0].value as any)?.data : null;
  const openCounts: { slug: string; count: number }[] =
    results[1].status === "fulfilled" ? (results[1].value as any) : [];
  const liveGames: any[] =
    results[2].status === "fulfilled" ? ((results[2].value as any)?.data ?? []) : [];
  const recentGames: any[] =
    results[3].status === "fulfilled" ? ((results[3].value as any)?.data ?? []) : [];

  const openSummary = openCounts
    .filter(g => g.count > 0)
    .map(g => `${GAME_LABELS[g.slug]} (${g.count})`)
    .join(", ") || "aucune";

  const liveSummary =
    liveGames.length === 0
      ? "aucune partie en cours"
      : liveGames
          .map((g: any) =>
            `${GAME_LABELS[g.game_type] ?? g.game_type} — ${g.players_count}/${g.max_players} joueurs, cagnotte ${Number(g.pot).toLocaleString("fr-FR")} Ar, ${g.spectators_count} spectateur(s)`
          )
          .join("; ");

  const historySummary =
    recentGames.length === 0
      ? "aucune partie récente trouvée"
      : recentGames
          .map((g: any) => {
            const label = KIND_LABEL[g.kind as string] ?? g.kind;
            const gameName = g.meta?.game ? ` (${g.meta.game as string})` : "";
            const amount = Number(g.amount ?? 0);
            const sign = g.kind === "game_loss" ? "-" : "+";
            const date = new Date(g.created_at as string).toLocaleDateString("fr-FR", {
              day: "2-digit", month: "2-digit",
            });
            return `${date} — ${label}${gameName} : ${sign}${amount.toLocaleString("fr-FR")} Ar`;
          })
          .join("; ");

  const lines: string[] = [
    `=== CONTEXTE TEMPS RÉEL ===`,
    `Date/heure : ${now.toLocaleDateString("fr-FR")} ${now.toLocaleTimeString("fr-FR")}`,
    `Page actuelle : ${pageName} (${page})`,
    ``,
    `Joueur connecté :`,
    `  Pseudo    : ${profile?.pseudo ?? "inconnu"}`,
    `  Solde     : ${profile ? Number(profile.balance_ar).toLocaleString("fr-FR") + " Ar" : "inconnu"}`,
    `  Premium   : ${profile?.is_premium ? "Oui" : "Non"}`,
    `  Statut    : ${profile?.status ?? "actif"}`,
    ``,
    `Dernières parties jouées (5 plus récentes) :`,
    `  ${historySummary}`,
    ``,
    `Parties ouvertes (en attente de joueurs) :`,
    `  ${openSummary}`,
    ``,
    `Parties LIVE (en cours en ce moment) :`,
    `  ${liveSummary}`,
    ``,
    `Jeux disponibles : Ludo, Domino, Fanorona, Échecs, Rami, Poker`,
    `=== FIN DU CONTEXTE TEMPS RÉEL ===`,
  ];

  return lines.join("\n");
}

// ─────────────────────────────────────────────────────────────────────────────
// Composant principal
// ─────────────────────────────────────────────────────────────────────────────
export default function AIAssistant() {
  const { t } = useT();
  const [open, setOpen] = useState(false);
  const [enabled, setEnabled] = useState(true);
  const [userId, setUserId] = useState<string | null>(null);
  const [userName, setUserName] = useState("");

  // ── Masquage par l'utilisateur (×) ────────────────────────────────────────
  const [dismissed, setDismissed] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return localStorage.getItem("ai_assistant_hidden") === "true";
  });

  useEffect(() => {
    const handler = () => {
      const hidden = localStorage.getItem("ai_assistant_hidden") === "true";
      setDismissed(hidden);
    };
    window.addEventListener("ai_assistant_visibility_changed", handler);
    return () => window.removeEventListener("ai_assistant_visibility_changed", handler);
  }, []);

  const dismiss = useCallback((e: React.MouseEvent) => {
    e.stopPropagation();
    localStorage.setItem("ai_assistant_hidden", "true");
    setDismissed(true);
    setOpen(false);
    toast("Assistant masqué", {
      description: "Pour le réafficher : Profil → Aide → Assistant IA",
      duration: 4000,
    });
  }, []);

  // ── Position draggable ─────────────────────────────────────────────────────
  const [pos, setPos] = useState<{ x: number; y: number } | null>(() => {
    if (typeof window === "undefined") return null;
    try { const r = localStorage.getItem("ai_assistant_pos"); return r ? JSON.parse(r) : null; } catch { return null; }
  });
  const dragging = useRef(false);
  const dragStart = useRef({ mx: 0, my: 0, bx: 0, by: 0 });
  const moved = useRef(false);

  useEffect(() => {
    supabase.rpc("get_ai_assistant_settings" as any).then(({ data }: any) => {
      const row = Array.isArray(data) ? data[0] : data;
      setEnabled(row?.enabled !== false);
    });
  }, []);

  useEffect(() => {
    let alive = true;
    supabase.auth.getUser().then(async ({ data }) => {
      const u = data.user;
      if (!u || !alive) return;
      setUserId(u.id);
      const fallback = u.user_metadata?.pseudo || u.user_metadata?.name || u.email?.split("@")[0] || "";
      const { data: profile } = await supabase.from("profiles").select("pseudo").eq("id", u.id).maybeSingle();
      if (alive) setUserName((((profile as any)?.pseudo) || fallback || "").trim());
    });
    return () => { alive = false; };
  }, []);

  useEffect(() => {
    if (pos) try { localStorage.setItem("ai_assistant_pos", JSON.stringify(pos)); } catch {}
  }, [pos]);

  const onPointerDown = useCallback((e: React.PointerEvent) => {
    if (open) return;
    dragging.current = true;
    moved.current = false;
    const rect = (e.currentTarget as HTMLElement).getBoundingClientRect();
    dragStart.current = { mx: e.clientX, my: e.clientY, bx: rect.left, by: rect.top };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }, [open]);

  const onPointerMove = useCallback((e: React.PointerEvent) => {
    if (!dragging.current) return;
    const dx = e.clientX - dragStart.current.mx;
    const dy = e.clientY - dragStart.current.my;
    if (Math.abs(dx) > 4 || Math.abs(dy) > 4) moved.current = true;
    setPos({
      x: Math.max(8, Math.min(window.innerWidth - 64, dragStart.current.bx + dx)),
      y: Math.max(8, Math.min(window.innerHeight - 64, dragStart.current.by + dy)),
    });
  }, []);

  const onPointerUp = useCallback(() => {
    if (!dragging.current) return;
    dragging.current = false;
    if (!moved.current) setOpen(true);
  }, []);

  if (!enabled || dismissed) return null;

  const btnStyle: React.CSSProperties = pos
    ? { position: "fixed", left: pos.x, top: pos.y, zIndex: 40, bottom: "auto", right: "auto" }
    : { position: "fixed", bottom: "6rem", right: "1rem", zIndex: 40 };

  return (
    <>
      {/* Groupe bouton principal + bouton × */}
      <div style={btnStyle} className="group">
        <button
          onPointerDown={onPointerDown} onPointerMove={onPointerMove} onPointerUp={onPointerUp}
          aria-label={t("ai_assistant")}
          style={{ background: "var(--gradient-primary)", touchAction: "none" }}
          className="h-14 w-14 rounded-full text-white shadow-2xl flex items-center justify-center hover:scale-110 transition select-none cursor-grab active:cursor-grabbing relative"
        >
          <Bot className="w-6 h-6" />
          <span className="absolute -top-1 -right-1 w-4 h-4 rounded-full bg-amber-400 text-amber-900 flex items-center justify-center">
            <Sparkles className="w-2.5 h-2.5" />
          </span>
        </button>

        {/* Bouton × masquer — visible au survol */}
        <button
          onClick={dismiss}
          aria-label="Masquer l'assistant"
          className="absolute -top-2 -left-2 w-5 h-5 rounded-full bg-background border border-border shadow-md flex items-center justify-center opacity-0 group-hover:opacity-100 focus:opacity-100 transition-opacity z-10"
        >
          <X className="w-3 h-3 text-muted-foreground" />
        </button>
      </div>

      {open && userId && (
        <AssistantChatPanel userId={userId} userName={userName} onClose={() => setOpen(false)} />
      )}
    </>
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Panneau de chat
// ─────────────────────────────────────────────────────────────────────────────
function AssistantChatPanel({ userId, userName, onClose }: { userId: string; userName: string; onClose: () => void }) {
  const { t } = useT();
  const [input, setInput] = useState("");
  const [serverError, setServerError] = useState(false);
  const [history, setHistory] = useState<UIMessage[] | null>(null);
  const scrollRef = useRef<HTMLDivElement>(null);

  // ── Contexte temps réel ───────────────────────────────────────────────────
  const appContextRef = useRef<string>("");
  const [contextReady, setContextReady] = useState(false);

  const refreshContext = useCallback(async () => {
    try {
      const ctx = await buildAppContext(userId);
      appContextRef.current = ctx;
      if (!contextReady) setContextReady(true);
    } catch {
      appContextRef.current = `Page actuelle: ${typeof window !== "undefined" ? window.location.pathname : "inconnue"}`;
      if (!contextReady) setContextReady(true);
    }
  }, [userId, contextReady]);

  useEffect(() => {
    refreshContext();
    const interval = setInterval(refreshContext, 30_000);
    const channel = supabase
      .channel("ai-context-watcher")
      .on("postgres_changes", { event: "*", schema: "public", table: "ludo_games" }, refreshContext)
      .on("postgres_changes", { event: "*", schema: "public", table: "domino_games" }, refreshContext)
      .on("postgres_changes", { event: "*", schema: "public", table: "chess_games" }, refreshContext)
      .on("postgres_changes", { event: "*", schema: "public", table: "fanorona_games" }, refreshContext)
      .on("postgres_changes", { event: "*", schema: "public", table: "rami_games" }, refreshContext)
      .on("postgres_changes", { event: "*", schema: "public", table: "poker_games" }, refreshContext)
      .subscribe();
    return () => {
      clearInterval(interval);
      supabase.removeChannel(channel);
    };
  }, [refreshContext]);

  // ── Transport ─────────────────────────────────────────────────────────────
  const transport = useMemo(() => new DefaultChatTransport({ api: "/api/ai-chat" }), []);

  useEffect(() => {
    let alive = true;
    supabase
      .from("assistant_messages")
      .select("id,role,content,created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: true })
      .limit(200)
      .then(({ data, error }) => {
        if (!alive) return;
        if (error) { setHistory([]); return; }
        setHistory((data || []).map(ROW_TO_UI));
      });
    return () => { alive = false; };
  }, [userId]);

  const { messages, sendMessage, status, setMessages, stop } = useChat({
    id: `ai-${userId}`,
    messages: history ?? [],
    transport,
    onError: () => setServerError(true),
  });

  useEffect(() => {
    if (history && history.length > 0 && messages.length === 0) setMessages(history);
  }, [history]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: "smooth" });
  }, [messages.length, status]);

  const handleSend = () => {
    const text = input.trim();
    if (!text || status === "submitted" || status === "streaming") return;
    setServerError(false);
    sendMessage({ text }, { body: { appContext: appContextRef.current } });
    setInput("");
  };

  const clearHistory = async () => {
    if (!confirm("Effacer toute la conversation ?")) return;
    try { stop?.(); } catch {}
    const { error } = await supabase.from("assistant_messages").delete().eq("user_id", userId);
    if (error) { toast.error("Impossible d'effacer"); return; }
    setMessages([]);
    setInput("");
    toast.success("Conversation effacée");
  };

  const closePanel = () => {
    try { stop?.(); } catch {}
    onClose();
  };

  const greeting = `Bonjour${userName ? ` ${userName}` : ""} 👋 Comment puis-je vous aider aujourd'hui ?`;

  return (
    <div className="fixed inset-x-0 bottom-0 z-[60] sm:inset-auto sm:bottom-6 sm:right-4 sm:w-[min(400px,95vw)] flex flex-col max-h-[85dvh] bg-card sm:rounded-3xl rounded-t-3xl shadow-2xl overflow-hidden border border-border/40">
      <div className="flex items-center justify-between px-4 py-3 border-b border-border/60 shrink-0" style={{ background: "var(--gradient-primary)" }}>
        <div className="font-bold text-white flex items-center gap-2">
          <Bot className="w-5 h-5" /> {t("ai_assistant")}
          {contextReady && (
            <span className="text-[9px] font-normal text-white/70 bg-white/10 px-1.5 py-0.5 rounded-full">
              contexte live
            </span>
          )}
        </div>
        <div className="flex items-center gap-1">
          {messages.length > 0 && (
            <button onClick={clearHistory} className="p-2 rounded-full hover:bg-white/20 text-white" title="Effacer la conversation">
              <Trash2 className="w-4 h-4" />
            </button>
          )}
          <button onClick={closePanel} className="p-2 rounded-full hover:bg-white/20 text-white"><X className="w-4 h-4" /></button>
        </div>
      </div>

      <div ref={scrollRef} className="flex-1 overflow-y-auto p-3 space-y-2 min-h-[250px]">
        {history === null && (
          <div className="flex items-center justify-center py-8">
            <div className="w-6 h-6 border-2 border-primary border-t-transparent rounded-full animate-spin" />
          </div>
        )}
        {history !== null && messages.length === 0 && !serverError && (
          <div className="text-center text-muted-foreground text-sm py-6">
            <Bot className="w-10 h-10 mx-auto opacity-25 mb-2" />
            <p className="font-semibold">{greeting}</p>
          </div>
        )}
        {serverError && (
          <div className="flex flex-col items-center justify-center py-6 gap-2 text-center">
            <WifiOff className="w-8 h-8 text-muted-foreground opacity-40" />
            <p className="text-sm text-muted-foreground">{t("ai_unavailable")}</p>
          </div>
        )}
        {messages.map((m: any) => {
          const text = (m.parts || []).map((p: any) => (p.type === "text" ? p.text : "")).join("");
          return (
            <div key={m.id} className={`flex ${m.role === "user" ? "justify-end" : ""}`}>
              <div className={`max-w-[85%] px-3 py-2 rounded-2xl text-sm whitespace-pre-wrap break-words ${m.role === "user" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>
                {text}
              </div>
            </div>
          );
        })}
        {(status === "submitted" || status === "streaming") && (
          <div className="text-xs text-muted-foreground italic px-1">{t("thinking") || "En train de répondre…"}</div>
        )}
      </div>

      <div className="p-2 border-t border-border/60 flex gap-1.5 shrink-0">
        <input value={input} onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => { if (e.key === "Enter" && !e.shiftKey) { e.preventDefault(); handleSend(); } }}
          placeholder={t("ask_ai") || "Posez une question…"}
          disabled={status === "submitted" || status === "streaming" || history === null}
          className="flex-1 px-3 py-2 rounded-2xl bg-secondary outline-none text-sm" />
        <button onClick={handleSend} disabled={!input.trim() || status === "submitted" || status === "streaming"}
          className="p-2.5 rounded-full bg-primary text-primary-foreground disabled:opacity-50">
          <Send className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
}
