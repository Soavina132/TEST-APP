import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState, useCallback } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useAuth } from "@/hooks/use-auth";
import ChatRoom from "@/components/chat/ChatRoom";
import { MessageSquare, Users, UserPlus, Crown, Lock, ChevronRight, X } from "lucide-react";
import { useT } from "@/lib/i18n";
import { toast } from "sonner";
import ludoGroup from "@/assets/groups/ludo-group.jpg";
import dominoGroup from "@/assets/groups/domino-group.jpg";
import fanoronaGroup from "@/assets/groups/fanorona-group.jpg";
import chessGroup from "@/assets/groups/chess-group.jpg";
import ramiGroup from "@/assets/groups/rami-group.jpg";

export const Route = createFileRoute("/_authenticated/chat")({
  component: ChatHub,
  validateSearch: (s: Record<string, unknown>) => ({ dm: typeof s.dm === "string" ? s.dm : undefined }),
  head: () => ({ meta: [{ title: "Discussion — Lalao MADA" }] }),
});

// ─── Types ────────────────────────────────────────────────────────────────────

type Tab = "global" | "dm";

// ─── Game group meta (hardcoded list — no backend needed) ─────────────────────

const GAME_GROUPS = [
  { slug: "ludo",     cover: ludoGroup,     label: "Groupe Ludo",     accent: "from-emerald-400/20 to-emerald-500/5", name: "Groupe Ludo" },
  { slug: "domino",   cover: dominoGroup,   label: "Groupe Domino",   accent: "from-stone-400/20 to-stone-500/5",    name: "Groupe Domino" },
  { slug: "fanorona", cover: fanoronaGroup, label: "Groupe Fanorona", accent: "from-amber-500/20 to-amber-700/5",     name: "Groupe Fanorona" },
  { slug: "chess",    cover: chessGroup,    label: "Groupe Échec",    accent: "from-orange-400/20 to-orange-500/5",  name: "Groupe Échec" },
  { slug: "rami",     cover: ramiGroup,     label: "Groupe Rami",     accent: "from-rose-400/20 to-rose-500/5",       name: "Groupe Rami" },
];

function metaFor(name?: string) {
  const k = (name || "").toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "");
  for (const g of GAME_GROUPS) {
    const key = g.slug.toLowerCase();
    if (k.includes(key)) return g;
  }
  return null;
}

const lastReadKey = (uid: string | undefined, rid: string) =>
  `chat_lastread_${uid || "anon"}_${rid}`;

// ─── Premium gate for DM ─────────────────────────────────────────────────────

function PremiumGate() {
  const { t } = useT();
  const premiumFeatures = [
    t("premium_feature_unlimited_dm"),
    t("premium_feature_badge"),
    t("premium_feature_priority_rooms"),
    t("premium_feature_priority_support"),
  ];
  return (
    <div className="flex-1 flex flex-col items-center justify-center px-6 py-12 text-center gap-5">
      <div className="w-20 h-20 rounded-3xl bg-gradient-to-br from-yellow-400 to-amber-500 flex items-center justify-center shadow-lg shadow-amber-500/30">
        <Crown className="w-10 h-10 text-white" />
      </div>
      <div className="space-y-2">
        <h2 className="text-xl font-bold">{t("premium_feature_title")}</h2>
        <p className="text-sm text-muted-foreground max-w-xs">
          {t("premium_dm_desc")}
        </p>
      </div>
      <div className="rounded-2xl bg-gradient-to-br from-yellow-50 to-amber-50 dark:from-yellow-950/30 dark:to-amber-950/30 border border-amber-200/50 dark:border-amber-800/40 p-4 w-full max-w-xs">
        <ul className="text-sm text-left space-y-2 text-muted-foreground">
          {premiumFeatures.map(f => (
            <li key={f} className="flex items-center gap-2">
              <span className="text-amber-500">✦</span> {f}
            </li>
          ))}
        </ul>
      </div>
      <button
        onClick={() => toast.info(t("contact_admin_premium"))}
        className="w-full max-w-xs py-3 rounded-2xl bg-gradient-to-r from-yellow-400 to-amber-500 text-white font-bold shadow-md shadow-amber-400/30 hover:from-yellow-500 hover:to-amber-600 transition-all active:scale-95 flex items-center justify-center gap-2"
      >
        <Crown className="w-4 h-4" /> {t("upgrade_premium_btn")}
      </button>
    </div>
  );
}

// ─── Main component ───────────────────────────────────────────────────────────

function ChatHub() {
  const { t } = useT();
  const { user, isAdmin, profile } = useAuth();
  const isPremium = isAdmin || profile?.is_premium === true;

  const [tab, setTab] = useState<Tab>("global");
  const [active, setActive] = useState<any | null>(null);
  const [dms, setDms] = useState<any[]>([]);
  const [addDmCode, setAddDmCode] = useState("");
  const [unread, setUnread] = useState<Record<string, number>>({});
  const [lastMsg, setLastMsg] = useState<Record<string, string>>({});
  const [showUserPicker, setShowUserPicker] = useState(false);
  const [allUsers, setAllUsers] = useState<any[]>([]);
  const [userSearch, setUserSearch] = useState("");
  const [loadingUsers, setLoadingUsers] = useState(false);
  const [openingRoom, setOpeningRoom] = useState<string | null>(null);

  // Load only DMs from the server (not global groups — those are hardcoded)
  const loadDms = async () => {
    const { data, error } = await supabase
      .from("chat_rooms")
      .select("*")
      .eq("type", "dm")
      .or(`dm_user_a.eq.${user?.id},dm_user_b.eq.${user?.id}`)
      .order("created_at", { ascending: true });
    if (error) {
      console.error("[chat] loadDms error:", error);
      setDms([]);
      return;
    }
    const myDms = data || [];
    const otherIds = myDms.map((r: any) =>
      r.dm_user_a === user?.id ? r.dm_user_b : r.dm_user_a
    );
    if (otherIds.length) {
      const { data: profs } = await supabase
        .from("profiles")
        .select("id,pseudo,avatar_url,unique_code")
        .in("id", otherIds);
      const profMap = Object.fromEntries((profs || []).map((p: any) => [p.id, p]));
      setDms(
        myDms.map((r: any) => {
          const other = r.dm_user_a === user?.id ? r.dm_user_b : r.dm_user_a;
          return { ...r, other_profile: profMap[other] };
        })
      );
    } else {
      setDms([]);
    }
  };

  // Fetch unread counts for all known room IDs (DMs)
  const refreshUnread = useCallback(async (roomIds: string[]) => {
    if (!user || !roomIds.length || typeof window === "undefined") return;
    const counts: Record<string, number> = {};
    const lasts: Record<string, string> = {};
    await Promise.all(
      roomIds.map(async rid => {
        const since = localStorage.getItem(lastReadKey(user.id, rid)) || "1970-01-01";
        const { count } = await supabase
          .from("chat_messages")
          .select("id", { count: "exact", head: true })
          .eq("room_id", rid)
          .neq("user_id", user.id)
          .gt("created_at", since)
          .is("deleted_at", null);
        counts[rid] = count || 0;
        const { data: last } = await supabase
          .from("chat_messages")
          .select("body,attachment_type")
          .eq("room_id", rid)
          .is("deleted_at", null)
          .order("created_at", { ascending: false })
          .limit(1)
          .maybeSingle();
        if (last) {
          lasts[rid] =
            last.attachment_type === "image"
              ? "📷 Image"
              : last.attachment_type === "audio"
              ? "🎤 Audio"
              : last.body?.slice(0, 50) || "";
        }
      })
    );
    setUnread(prev => ({ ...prev, ...counts }));
    setLastMsg(prev => ({ ...prev, ...lasts }));
  }, [user?.id]);

  // Load DMs on mount
  useEffect(() => {
    loadDms();
  }, [user?.id]);

  // Real-time unread refresh for DMs
  useEffect(() => {
    if (!user) return;
    let dt: ReturnType<typeof setTimeout>;
    const ch = supabase
      .channel("chat-hub-unread-" + user.id)
      .on("postgres_changes", { event: "INSERT", schema: "public", table: "chat_messages" }, () => {
        clearTimeout(dt);
        dt = setTimeout(() => {
          if (dms.length) refreshUnread(dms.map(r => r.id));
        }, 500);
      })
      .subscribe();
    return () => { clearTimeout(dt); supabase.removeChannel(ch); };
  }, [user?.id, dms.length, refreshUnread]);

  // Refresh unread for DMs when they change
  useEffect(() => {
    if (dms.length) refreshUnread(dms.map(r => r.id));
  }, [dms.length, refreshUnread]);

  // Open a global game group — fetch the room from the server only on click
  const openGameGroup = async (group: typeof GAME_GROUPS[0]) => {
    setOpeningRoom(group.slug);
    try {
      const { data: room, error } = await supabase
        .from("chat_rooms")
        .select("*")
        .eq("name", group.name)
        .eq("type", "global")
        .maybeSingle();

      if (error) {
        console.error("[chat] openGameGroup error:", error);
        toast.error("Impossible de charger ce groupe");
        setOpeningRoom(null);
        return;
      }

      if (room) {
        if (typeof window !== "undefined") {
          localStorage.setItem(lastReadKey(user?.id, room.id), new Date().toISOString());
        }
        setUnread(prev => ({ ...prev, [room.id]: 0 }));
        setActive(room);
      } else {
        toast.error("Ce groupe n'existe pas encore");
      }
    } finally {
      setOpeningRoom(null);
    }
  };

  const openRoom = (r: any) => {
    if (typeof window !== "undefined") {
      localStorage.setItem(lastReadKey(user?.id, r.id), new Date().toISOString());
    }
    setUnread(prev => ({ ...prev, [r.id]: 0 }));
    setActive(r);
  };

  const startDmWith = async (target: { id: string; pseudo?: string; avatar_url?: string; unique_code?: string }) => {
    if (!target) return;
    if (target.id === user?.id) { toast.error(t("cant_message_self")); return; }

    const existing = dms.find(
      (r: any) =>
        (r.dm_user_a === user?.id && r.dm_user_b === target.id) ||
        (r.dm_user_b === user?.id && r.dm_user_a === target.id)
    );
    if (existing) { openRoom(existing); return; }

    const { data: roomId, error } = await supabase.rpc(
      "chat_get_or_create_dm" as any,
      { _other: target.id } as any
    );
    if (error || !roomId) { toast.error(t("conversation_create_error")); return; }
    toast.success(`${t("conversation_created_with")} ${target.pseudo} ${t("conversation_created_suffix")}`);
    await loadDms();
    const { data: newRoom } = await supabase
      .from("chat_rooms")
      .select("*")
      .eq("id", roomId)
      .maybeSingle();
    if (newRoom) openRoom({ ...newRoom, other_profile: target });
  };

  const addDm = async () => {
    if (!addDmCode.trim()) return;
    const { data: target } = await supabase
      .from("profiles")
      .select("id,pseudo,avatar_url,unique_code")
      .eq("unique_code", addDmCode.trim().toUpperCase())
      .maybeSingle();
    if (!target) { toast.error(t("code_not_found")); return; }
    await startDmWith(target as any);
    setAddDmCode("");
  };

  const loadPlayerList = useCallback(async (search: string) => {
    setLoadingUsers(true);
    const { data, error } = await supabase.rpc(
      "list_players_for_dm" as any,
      { _search: search.trim() || null, _limit: 50 } as any
    );
    if (error) toast.error(t("conversation_create_error"));
    setAllUsers(data || []);
    setLoadingUsers(false);
  }, [t]);

  const openUserPicker = async () => {
    setShowUserPicker(true);
    setUserSearch("");
    await loadPlayerList("");
  };

  useEffect(() => {
    if (!showUserPicker) return;
    const id = setTimeout(() => loadPlayerList(userSearch), 300);
    return () => clearTimeout(id);
  }, [userSearch, showUserPicker, loadPlayerList]);

  const filteredUsers = allUsers;

  // Auto-open a DM when arriving with ?dm=<userId>
  const search = Route.useSearch();
  const navigate = useNavigate();
  const [dmHandled, setDmHandled] = useState(false);
  useEffect(() => {
    const other = search?.dm;
    if (!other || !user?.id || dmHandled) return;
    if (other === user.id) { setDmHandled(true); navigate({ to: "/chat", search: {} as any, replace: true }); return; }
    setDmHandled(true);
    (async () => {
      const { data: target } = await supabase
        .from("profiles")
        .select("id,pseudo,avatar_url,unique_code")
        .eq("id", other)
        .maybeSingle();
      if (target) {
        setTab("dm");
        await startDmWith(target as any);
      }
      navigate({ to: "/chat", search: {} as any, replace: true });
    })();
  }, [search?.dm, user?.id, dmHandled, navigate]);

  // ── Active room view ───────────────────────────────────────────────────────
  if (active) {
    const meta = metaFor(active.name);
    const isDm = active.type === "dm";
    const label = isDm
      ? (active.other_profile?.pseudo || t("dm_fallback_label"))
      : (meta?.label || active.name || t("group_fallback_label"));
    return (
      <div className="flex flex-col h-[calc(100dvh-4.75rem-5rem)] md:h-[calc(100dvh-4.75rem)]">
        <ChatRoom
          roomId={active.id}
          title={label}
          isAdmin={isAdmin}
          height="flex-1"
          gameSlug={meta?.slug}
          onBack={() => setActive(null)}
        />
      </div>
    );
  }

  // ── Room list view ─────────────────────────────────────────────────────────
  return (
    <main className="max-w-md mx-auto px-4 py-4 space-y-4 pb-28">
      <h1 className="text-2xl font-bold">{t("discussion")}</h1>

      <div className="grid grid-cols-2 gap-2">
        <TabBtn
          icon={<Users className="w-4 h-4" />}
          label={t("groups_tab_label")}
          active={tab === "global"}
          onClick={() => setTab("global")}
        />
        <TabBtn
          icon={isPremium ? <MessageSquare className="w-4 h-4" /> : <Lock className="w-4 h-4" />}
          label={isPremium ? t("private_messages_label") : `${t("private_messages_label")} ✦`}
          active={tab === "dm"}
          onClick={() => setTab("dm")}
          badge={isPremium ? dms.reduce((s, r) => s + (unread[r.id] || 0), 0) : 0}
          premium={!isPremium}
        />
      </div>

      {/* ── Global groups (hardcoded list — no backend query) ── */}
      {tab === "global" && (
        <div className="space-y-2">
          {GAME_GROUPS.map(group => (
            <GroupCard
              key={group.slug}
              room={{ name: group.name, enabled: true }}
              cover={group.cover}
              label={group.label}
              preview={lastMsg[group.name]}
              unread={0}
              loading={openingRoom === group.slug}
              onOpen={() => openGameGroup(group)}
            />
          ))}
        </div>
      )}

      {/* ── DM tab ── */}
      {tab === "dm" && (
        isPremium ? (
          <div className="space-y-3">
            <div className="rounded-3xl bg-card p-4 flex gap-2">
              <input
                value={addDmCode}
                onChange={e => setAddDmCode(e.target.value.toUpperCase())}
                onKeyDown={e => e.key === "Enter" && addDm()}
                placeholder={t("player_code_placeholder")}
                maxLength={12}
                className="flex-1 bg-transparent outline-none text-sm placeholder:text-muted-foreground"
              />
              <button
                onClick={addDm}
                className="px-3 py-1.5 rounded-xl bg-primary text-primary-foreground text-sm font-semibold flex items-center gap-1"
              >
                <UserPlus className="w-4 h-4" />
              </button>
            </div>
            <button
              onClick={openUserPicker}
              className="w-full rounded-2xl bg-card p-3 flex items-center justify-center gap-2 text-sm font-semibold text-primary shadow-sm hover:bg-accent"
            >
              <Users className="w-4 h-4" /> {t("browse_all_players")}
            </button>

            {dms.length === 0 ? (
              <div className="rounded-3xl bg-card p-6 text-center text-muted-foreground text-sm">
                {t("no_conversation_label")}
              </div>
            ) : (
              dms.map(r => {
                const other = r.other_profile;
                return (
                  <button
                    key={r.id}
                    onClick={() => openRoom(r)}
                    className="w-full rounded-2xl bg-card p-3 shadow-sm flex items-center gap-3 hover:bg-accent text-left"
                  >
                    <div className="w-12 h-12 rounded-full bg-accent overflow-hidden flex items-center justify-center shrink-0 border border-border">
                      {other?.avatar_url ? (
                        <img
                          src={other.avatar_url}
                          width={48}
                          height={48}
                          loading="lazy"
                          decoding="async"
                          className="w-full h-full object-cover"
                          alt={other.pseudo}
                        />
                      ) : (
                        <span className="text-lg font-bold text-primary">
                          {(other?.pseudo || "?").slice(0, 1).toUpperCase()}
                        </span>
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-semibold truncate">{other?.pseudo || t("player_fallback")}</div>
                      <div className="text-xs text-muted-foreground truncate">
                        {lastMsg[r.id] || t("start_conversation_label")}
                      </div>
                    </div>
                    {unread[r.id] > 0 && <UnreadBadge n={unread[r.id]} />}
                    <ChevronRight className="w-4 h-4 text-muted-foreground shrink-0" />
                  </button>
                );
              })
            )}
          </div>
        ) : (
          <PremiumGate />
        )
      )}

      {showUserPicker && (
        <div className="fixed inset-0 z-50 bg-black/50 flex items-end justify-center" onClick={() => setShowUserPicker(false)}>
          <div
            className="w-full max-w-md bg-background rounded-t-3xl max-h-[80vh] flex flex-col"
            onClick={e => e.stopPropagation()}
          >
            <div className="flex items-center justify-between p-4 border-b border-border">
              <div className="font-bold text-lg">{t("all_players_title")}</div>
              <button onClick={() => setShowUserPicker(false)} className="p-1.5 rounded-full hover:bg-accent">
                <X className="w-5 h-5" />
              </button>
            </div>
            <div className="p-3 border-b border-border">
              <input
                value={userSearch}
                onChange={e => setUserSearch(e.target.value)}
                placeholder={t("search_player_placeholder")}
                className="w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm"
              />
            </div>
            <div className="flex-1 overflow-y-auto p-3 space-y-2">
              {loadingUsers ? (
                <div className="text-center text-muted-foreground text-sm py-6">{t("loading_label")}</div>
              ) : filteredUsers.length === 0 ? (
                <div className="text-center text-muted-foreground text-sm py-6">{t("no_players_found")}</div>
              ) : (
                filteredUsers.map(u => (
                  <div key={u.id} className="flex items-center gap-3 rounded-2xl bg-card p-3 shadow-sm">
                    <div className="w-11 h-11 rounded-full bg-accent overflow-hidden flex items-center justify-center shrink-0 border border-border">
                      {u.avatar_url ? (
                        <img src={u.avatar_url} width={44} height={44} loading="lazy" decoding="async" className="w-full h-full object-cover" alt={u.pseudo} />
                      ) : (
                        <span className="text-base font-bold text-primary">{(u.pseudo || "?").slice(0, 1).toUpperCase()}</span>
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="font-semibold truncate">{u.pseudo || t("player_fallback")}</div>
                    </div>
                    <button
                      onClick={() => { setShowUserPicker(false); startDmWith(u); }}
                      className="shrink-0 px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-semibold flex items-center gap-1"
                    >
                      <MessageSquare className="w-3.5 h-3.5" /> {t("send_message_btn")}
                    </button>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      )}
    </main>
  );
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function TabBtn({
  icon, label, active, onClick, badge, premium,
}: {
  icon: React.ReactNode;
  label: string;
  active: boolean;
  onClick: () => void;
  badge?: number;
  premium?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={`relative py-2.5 rounded-2xl font-semibold text-sm flex items-center justify-center gap-1.5 transition-colors ${
        active
          ? premium
            ? "bg-gradient-to-r from-yellow-400 to-amber-500 text-white"
            : "bg-primary text-primary-foreground"
          : premium
          ? "bg-card border border-amber-300/60 text-amber-600 dark:text-amber-400"
          : "bg-card border border-border"
      }`}
    >
      {icon}
      <span className="truncate">{label}</span>
      {!!badge && badge > 0 && (
        <span className="absolute -top-1.5 -right-1.5 min-w-[20px] h-5 px-1 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center ring-2 ring-background">
          {badge > 99 ? "99+" : badge}
        </span>
      )}
    </button>
  );
}

function UnreadBadge({ n }: { n: number }) {
  return (
    <span className="ml-2 shrink-0 min-w-[22px] h-[22px] px-1.5 rounded-full bg-primary text-primary-foreground text-[11px] font-bold flex items-center justify-center">
      {n > 99 ? "99+" : n}
    </span>
  );
}

function GroupCard({
  room, cover, label, preview, unread, loading, onOpen,
}: {
  room: any;
  cover?: string;
  label: string;
  preview?: string;
  unread: number;
  loading?: boolean;
  onOpen: () => void;
}) {
  const { t } = useT();
  const meta = metaFor(room.name);
  return (
    <button
      onClick={onOpen}
      disabled={loading}
      className="group w-full rounded-2xl bg-card border border-border/60 overflow-hidden text-left transition-all hover:border-primary/40 hover:shadow-md active:scale-[0.99] disabled:opacity-60"
    >
      {/* Cover image — full width banner */}
      <div className={`relative h-20 overflow-hidden bg-gradient-to-br ${meta?.accent ?? "from-primary/15 to-primary/5"}`}>
        {cover ? (
          <img
            src={cover}
            alt={label}
            loading="lazy"
            decoding="async"
            className="w-full h-full object-cover transition-transform duration-300 group-hover:scale-105"
          />
        ) : (
          <div className="w-full h-full grid place-items-center">
            <Users className="w-8 h-8 text-primary/50" />
          </div>
        )}
        {/* Gradient overlay for readability */}
        <div className="absolute inset-0 bg-gradient-to-t from-card via-card/40 to-transparent" />
        {/* Status badge */}
        <div className="absolute top-2 right-2 flex items-center gap-1.5 rounded-full bg-black/40 backdrop-blur-sm px-2 py-0.5">
          <span className={`w-1.5 h-1.5 rounded-full ${room.enabled ? "bg-emerald-400" : "bg-muted-foreground"} animate-pulse`} />
          <span className="text-[10px] font-medium text-white">{room.enabled ? "Actif" : "Inactif"}</span>
        </div>
        {/* Label on image */}
        <div className="absolute bottom-1.5 left-3 font-bold text-[15px] text-foreground truncate">{label}</div>
      </div>
      {/* Footer with preview + chevron */}
      <div className="flex items-center justify-between gap-2 px-3 py-2">
        <div className="text-xs text-muted-foreground truncate flex-1">
          {loading ? "Chargement..." : (preview || (room.enabled ? t("active_label") : t("inactive_label")))}
        </div>
        {loading ? (
          <div className="w-5 h-5 border-2 border-primary/30 border-t-primary rounded-full animate-spin shrink-0" />
        ) : unread > 0 ? (
          <UnreadBadge n={unread} />
        ) : (
          <ChevronRight className="w-4 h-4 text-muted-foreground/50 shrink-0 transition-transform group-hover:translate-x-0.5" />
        )}
      </div>
    </button>
  );
}
