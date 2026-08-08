import { createFileRoute, Navigate, Link } from "@tanstack/react-router";
import RichTextEditor from "@/components/chat/RichTextEditor";
import { useAuth } from "@/hooks/use-auth";
import { useEffect, useState, useRef } from "react";
import { supabase } from "@/integrations/supabase/client";
import { useConfirm } from "@/components/ConfirmDialog";
import { toast } from "sonner";
import { Shield, Wallet, BarChart3, Users, Gamepad2, MessageSquare, Settings, RefreshCw, Pause, Play, Trash2, Send, Trophy, Info, ChevronDown, ChevronUp, Plus, AlertCircle, CheckCircle2, Sliders, Zap, Flag, Ban, UserX, DollarSign, RotateCcw, Eye, EyeOff, Clock, Camera, Save, ArrowUp, ArrowDown, CloudDownload, UserCheck, ImagePlus, Lock, History } from "lucide-react";
import GameConfigsSection from "@/components/admin/GameConfigsSection";
import GameTimersQuick from "@/components/admin/GameTimersQuick";
import { ValidatedField, useFormErrors } from "@/components/admin/ValidatedField";
import * as V from "@/lib/admin-validators";
import { saveWithToast } from "@/lib/save-toast";

import AdminSection from "@/components/admin/AdminSection";
import AdminSearchBar, { type AdminSearchEntry } from "@/components/admin/AdminSearchBar";
import { compressImageToWebp } from "@/lib/image-compress";
import CmsEditor from "@/components/admin/CmsEditor";
import AdminSecurityGate from "@/components/admin/AdminSecurityGate";
import AdminSessionsPanel from "@/components/admin/AdminSessionsPanel";
import TournamentAdminPanel from "@/components/tournament/TournamentAdminPanel";
import SupportMessagesAdmin from "@/components/admin/SupportMessagesAdmin";


// Bundled at build time — all migration SQL files
const MIGRATIONS = import.meta.glob("/supabase/migrations/*.sql", {
  query: "?raw",
  import: "default",
  eager: true,
}) as Record<string, string>;

export const Route = createFileRoute("/_authenticated/admin")({
  component: AdminPage,
  head: () => ({ meta: [{ title: "Admin — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});

type Tab = "finance" | "stats" | "joueurs" | "parties" | "tournois" | "classement" | "contenu" | "config";

function AdminPage() {
  const { isAdmin, loading } = useAuth();
  const [tab, setTab] = useState<Tab>("finance");
  const [v, setV] = useState(0);
  const [pendingFinance, setPendingFinance] = useState<number | null>(null);
  const [pendingJoueurs, setPendingJoueurs] = useState<number | null>(null);
  const [pendingTournois, setPendingTournois] = useState<number | null>(null);
  const [pendingContenu, setPendingContenu] = useState<number | null>(null);

  const refresh = () => setV(x => x + 1);

  // ── Export Cloud (JSON complet de toutes les tables accessibles) ──
  async function downloadCloudData() {
    toast.info("Export cloud en cours…");
    try {
      const TABLES = [
        "profiles","deposits","withdrawals","transactions","admin_logs","admin_broadcasts",
        "chess_games","chess_moves","domino_games","domino_participants",
        "fanorona_games","fanorona_participants","ludo_games","ludo_participants",
        "rami_games","rami_participants","poker_games","poker_players",
        "tournament_matches","tournament_entrants","referral_events","referral_settings",
        "notifications","chat_rooms","chat_members","chat_messages","chat_mutes",
        "bug_reports","support_messages","money_offers","password_reset_requests",
        "achievements","player_achievements","game_configs","app_settings","user_roles",
      ];
      const tablesData: Record<string, unknown[]> = {};
      const meta: Record<string, { count: number; error?: string }> = {};
      const BATCH = 8;
      for (let i = 0; i < TABLES.length; i += BATCH) {
        await Promise.all(TABLES.slice(i, i + BATCH).map(async (table) => {
          const { data, error } = await (supabase.from(table as any) as any).select("*").limit(1000);
          if (error) { meta[table] = { count: 0, error: error.message }; tablesData[table] = []; }
          else { meta[table] = { count: (data ?? []).length }; tablesData[table] = data ?? []; }
        }));
      }
      const ok = Object.values(meta).filter(m => !m.error);
      const blocked = Object.values(meta).filter(m => m.error);
      const total = ok.reduce((s, m) => s + m.count, 0);
      const blob = new Blob([JSON.stringify({ exported_at: new Date().toISOString(), project: "lalaomada", tables: tablesData, meta }, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url; a.download = `lalaomada_cloud_export_${new Date().toISOString().slice(0,10)}.json`;
      a.click(); URL.revokeObjectURL(url);
      toast.success(`Export: ${ok.length} tables (${total} lignes)${blocked.length ? ` · ${blocked.length} bloquées par RLS` : ""}`);
    } catch { toast.error("Erreur lors de l'export cloud"); }
  }

  // ── Téléchargement Joueurs (CSV complet de la table profiles) ─────────────
  async function downloadPlayers() {
    toast.info("Collecte des données joueurs en cours…");
    try {
      const { data, error } = await supabase
        .from("profiles")
        .select("id,pseudo,email,phone,phone_number,balance_ar,player_level,total_games,total_wins,is_banned,banned,status,suspended_until,suspension_reason,warning_count,is_premium,referral_code,referral_unlocked,referred_by,unique_code,created_at,first_deposit_at,first_deposit_amount,first_game_at,terms_accepted_at,phone_verified")
        .order("created_at", { ascending: false });
      if (error) throw error;
      const rows = data ?? [];
      if (rows.length === 0) { toast.warning("Aucun joueur trouvé"); return; }

      const headers = Object.keys(rows[0]);
      const escape = (v: unknown) => {
        if (v === null || v === undefined) return "";
        const s = String(v);
        return s.includes(",") || s.includes('"') || s.includes("\n") ? `"${s.replace(/"/g, '""')}"` : s;
      };
      const csv = [headers.join(","), ...rows.map(r => headers.map(h => escape((r as any)[h])).join(","))].join("\n");
      const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `lalaomada_joueurs_${new Date().toISOString().slice(0, 10)}.csv`;
      a.click();
      URL.revokeObjectURL(url);
      toast.success(`${rows.length} joueurs exportés en CSV !`);
    } catch (e) {
      toast.error("Erreur lors de l'export joueurs");
    }
  }

  useEffect(() => {
    async function fetchPending() {
      const [{ count: d }, { count: w }, phoneRes, resetRes, tRunRes, bugRes, supportRes] = await Promise.all([
        supabase.from("deposits").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.from("withdrawals").select("*", { count: "exact", head: true }).eq("status", "pending"),
        supabase.rpc("admin_list_phone_requests" as any),
        (supabase.from("password_reset_requests" as any) as any)
          .select("*", { count: "exact", head: true })
          .in("status", ["pending", "sent"]),
        (supabase.from("tournaments" as any) as any).select("*", { count: "exact", head: true }).eq("status", "running"),
        supabase.from("bug_reports").select("*", { count: "exact", head: true }).eq("status", "open"),
        (supabase.from("support_messages" as any) as any).select("*", { count: "exact", head: true }).is("reply", null),
      ]);
      setPendingFinance((d ?? 0) + (w ?? 0));
      const phoneCount = Array.isArray((phoneRes as any).data) ? (phoneRes as any).data.length : 0;
      const resetCount = (resetRes as any).count ?? 0;
      setPendingJoueurs(phoneCount + resetCount);
      setPendingTournois((tRunRes as any).count ?? 0);
      setPendingContenu(((bugRes as any).count ?? 0) + ((supportRes as any).count ?? 0));
    }
    fetchPending();
  }, [v]);

  if (loading) return <main className="p-8 text-center animate-pulse text-muted-foreground">Chargement…</main>;
  if (!isAdmin) return <Navigate to="/" />;

  return (
    <AdminSecurityGate>
    <main className="max-w-4xl mx-auto px-4 py-6 space-y-5">
      <AdminSessionsPanel />
      <div className="flex items-center justify-between">
        <h1 className="text-2xl font-extrabold flex items-center gap-2">
          <Shield className="w-6 h-6 text-primary" /> Panneau Admin
        </h1>

        <div className="flex items-center gap-1.5">
          <button
            onClick={downloadCloudData}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-blue-600 hover:bg-blue-700 text-white text-xs font-semibold transition-colors shadow-sm"
            title="Télécharger toutes les données cloud"
          >
            <CloudDownload className="w-3.5 h-3.5" />
            Cloud
          </button>
          <button
            onClick={downloadPlayers}
            className="flex items-center gap-1.5 px-3 py-1.5 rounded-xl bg-emerald-600 hover:bg-emerald-700 text-white text-xs font-semibold transition-colors shadow-sm"
            title="Télécharger les données de tous les joueurs"
          >
            <UserCheck className="w-3.5 h-3.5" />
            Joueurs
          </button>
          <button onClick={refresh} className="p-2 rounded-xl hover:bg-accent text-muted-foreground" title="Actualiser">
            <RefreshCw className="w-4 h-4" />
          </button>
        </div>
      </div>

      <AdminSearchBar
        index={SEARCH_INDEX}
        onGo={(entry) => {
          setTab(entry.tab as Tab);
          setTimeout(() => {
            window.dispatchEvent(new CustomEvent("admin-section-open", { detail: { id: entry.id } }));
          }, 80);
        }}
      />

      <div className="overflow-x-auto -mx-4 px-4">
        <div className="flex gap-1.5 bg-card rounded-2xl p-1.5 shadow-sm border border-border/60 w-max min-w-full">
          <T icon={<Wallet className="w-4 h-4" />}        active={tab === "finance"}      onClick={() => setTab("finance")}      label="Finance"      badge={pendingFinance} />
          <T icon={<BarChart3 className="w-4 h-4" />}     active={tab === "stats"}        onClick={() => setTab("stats")}        label="Stats" />
          <T icon={<Users className="w-4 h-4" />}         active={tab === "joueurs"}      onClick={() => setTab("joueurs")}      label="Joueurs"      badge={pendingJoueurs} />
          <T icon={<Gamepad2 className="w-4 h-4" />}      active={tab === "parties"}      onClick={() => setTab("parties")}      label="Parties" />
          <T icon={<Trophy className="w-4 h-4" />}        active={tab === "tournois"}     onClick={() => setTab("tournois")}     label="Tournois"     badge={pendingTournois} />
          <T icon={<BarChart3 className="w-4 h-4" />}     active={tab === "classement"}   onClick={() => setTab("classement")}   label="Classement" />
          
          <T icon={<MessageSquare className="w-4 h-4" />} active={tab === "contenu"}      onClick={() => setTab("contenu")}      label="Contenu"      badge={pendingContenu} />
          <T icon={<Settings className="w-4 h-4" />}      active={tab === "config"}       onClick={() => setTab("config")}       label="Config" />
        </div>
      </div>

      <div key={v}>
        {tab === "finance"      && <FinanceSection />}
        {tab === "stats"        && <StatsSection />}
        {tab === "joueurs" && (
          <div className="space-y-3">
            <AdminSection id="players-accounts" title="👥 Comptes joueurs" description="Liste, recherche, actions rapides" accent="primary" defaultOpen icon={<Users className="w-4 h-4" />}>
              <UsersList />
            </AdminSection>
            <AdminSection id="players-security" title="🔐 Demandes de sécurité" description="Téléphones à vérifier et mots de passe oubliés" accent="amber" icon={<Shield className="w-4 h-4" />}>
              <PhoneRequests />
              <PasswordResetRequestsAdmin />
            </AdminSection>
            <AdminSection id="players-chat-mod" title="🗣️ Modération chat" description="Utilisateurs sourdinés" accent="rose" icon={<MessageSquare className="w-4 h-4" />}>
              <ChatMutesAdmin />
            </AdminSection>
            <AdminSection id="players-persona" title="🎭 Persona admin" description="Alias et apparence publique de l'admin" accent="violet" icon={<Sliders className="w-4 h-4" />}>
              <PersonaAdmin />
            </AdminSection>
            <AdminSection id="players-history" title="📋 Historique joueur" description="Rechercher et consulter l'historique d'un joueur" accent="sky" icon={<History className="w-4 h-4" />}>
              <UserHistorySearch />
            </AdminSection>
          </div>
        )}

        {tab === "parties" && (
          <div className="space-y-3">
            <AdminSection id="games-live" title="🎮 Parties en cours" description="Suivi live et interventions" accent="primary" defaultOpen icon={<Gamepad2 className="w-4 h-4" />}>
              <GamesList />
              <GamesAdmin />
            </AdminSection>
            <AdminSection id="games-config" title="⚙️ Réglages par jeu" description="Règles, couvertures, badges, capacité" accent="sky" icon={<Settings className="w-4 h-4" />}>
              <GameConfigsSection />
            </AdminSection>
          </div>
        )}

        {tab === "tournois" && (
          <div className="space-y-3">
            <AdminSection id="tournaments-main" title="🏆 Tournois" description="Créer, arbitrer, suivre" accent="primary" defaultOpen icon={<Trophy className="w-4 h-4" />}>
              <TournamentsSection />
            </AdminSection>
            <AdminSection id="tournaments-seasons" title="📅 Saisons & classements" description="Cycles de compétition" accent="violet" icon={<BarChart3 className="w-4 h-4" />}>
              <SeasonsAdmin />
            </AdminSection>
          </div>
        )}

        {tab === "classement"   && <LeaderboardAdmin />}

        {tab === "contenu" && (
          <div className="space-y-3">
            <AdminSection id="content-pause" title="🛑 Contrôle global" description="Mettre l'app en pause" accent="rose" defaultOpen icon={<Pause className="w-4 h-4" />}>
              <PauseControl />
            </AdminSection>
            <AdminSection id="content-comm" title="📣 Communication" description="Annonces, offres, messages" accent="amber" icon={<Send className="w-4 h-4" />}>
              <AnnouncementsAdmin />
              <OffersAdmin />
            </AdminSection>
            <AdminSection id="content-support" title="💬 Messages support" description="Messages des joueurs depuis le centre d'aide" accent="primary" icon={<MessageSquare className="w-4 h-4" />} defaultOpen>
              <SupportMessagesAdmin />
            </AdminSection>
            <AdminSection id="content-banners" title="🎨 Bannières d'accueil" description="Carousel promo sur la page d'accueil" accent="violet" icon={<ImagePlus className="w-4 h-4" />} defaultOpen>
              <BannersAdmin />
            </AdminSection>
            <AdminSection id="content-help" title="📚 Aide, tutoriels & textes" description="Contenu pédagogique, textes d'aide, CGU, mentions légales" accent="sky" icon={<Info className="w-4 h-4" />}>
              <TutorialsAdmin />
              <CmsEditor />
              <ContentTextsEditor />
            </AdminSection>
            <AdminSection id="content-communities" title="🌍 Communautés" description="Réseaux et liens externes" accent="emerald" icon={<Users className="w-4 h-4" />}>
              <Communities />
            </AdminSection>
          </div>
        )}

        {tab === "config" && (
          <div className="space-y-3">
            <AdminSection id="config-security" title="🔐 Sécurité" description="PIN admin" accent="rose" defaultOpen icon={<Lock className="w-4 h-4" />}>
              <AdminPinSetup />
            </AdminSection>
            <AdminSection id="config-timers" title="⏱️ Timers" description="Tour, salle d'attente, minuteurs globaux" accent="primary" icon={<Clock className="w-4 h-4" />}>
              <GameTimersQuick />
            </AdminSection>
            <AdminSection id="config-app" title="🛠️ Paramètres de l'application" description="Finance, contact, chat, points, statut des jeux" accent="sky" icon={<Settings className="w-4 h-4" />}>
              <AppConfigForm />
            </AdminSection>
            <AdminSection id="config-referral" title="🤝 Parrainage" description="Commission, niveaux, anti-fraude" accent="emerald" icon={<Users className="w-4 h-4" />}>
              <ReferralAdmin />
            </AdminSection>
          </div>
        )}
      </div>
    </main>
    </AdminSecurityGate>
  );
}


const SEARCH_INDEX: AdminSearchEntry[] = [
  // Finance
  { id: "finance", tab: "finance", tabLabel: "Finance", title: "💰 Finance", description: "Dépôts, retraits, transactions", keywords: "argent solde depot retrait commission mobile money" },
  // Stats
  { id: "stats", tab: "stats", tabLabel: "Stats", title: "📊 Statistiques", description: "Vue d'ensemble de l'app", keywords: "chiffres kpi utilisateurs actifs" },
  // Joueurs
  { id: "players-accounts", tab: "joueurs", tabLabel: "Joueurs", title: "👥 Comptes joueurs", description: "Liste, recherche, ban, suspension", keywords: "utilisateur user profil banni suspension pseudo email" },
  { id: "players-security", tab: "joueurs", tabLabel: "Joueurs", title: "🔐 Demandes de sécurité", description: "Téléphone, mot de passe oublié", keywords: "telephone otp verification mot de passe reset password" },
  { id: "players-chat-mod", tab: "joueurs", tabLabel: "Joueurs", title: "🗣️ Modération chat", description: "Mute / sourdine", keywords: "mute sourdine chat moderation ban" },
  { id: "players-persona", tab: "joueurs", tabLabel: "Joueurs", title: "🎭 Persona admin", description: "Alias public de l'admin", keywords: "alias persona apparence admin avatar" },
  // Parties
  { id: "games-live", tab: "parties", tabLabel: "Parties", title: "🎮 Parties en cours", description: "Suivi live des parties", keywords: "live partie active jeu terminer annuler" },
  { id: "games-config", tab: "parties", tabLabel: "Parties", title: "⚙️ Réglages par jeu", description: "Règles, couvertures, badges, capacité", keywords: "regles cover image badge capacite instructions ludo chess domino rami fanorona poker" },
  // Tournois
  { id: "tournaments-main", tab: "tournois", tabLabel: "Tournois", title: "🏆 Tournois", description: "Créer, arbitrer, suivre", keywords: "tournoi bracket inscription arbitrage forfait test bot" },
  { id: "tournaments-seasons", tab: "tournois", tabLabel: "Tournois", title: "📅 Saisons & classements", description: "Cycles de compétition", keywords: "saison season leaderboard cycle" },
  // Classement
  { id: "classement", tab: "classement", tabLabel: "Classement", title: "🥇 Classement", description: "Podium et récompenses", keywords: "leaderboard classement trophee podium winners recompenses" },
  // Contenu
  { id: "content-pause", tab: "contenu", tabLabel: "Contenu", title: "🛑 Contrôle global", description: "Mettre l'app en pause", keywords: "pause maintenance stop app fermer" },
  { id: "content-comm", tab: "contenu", tabLabel: "Contenu", title: "📣 Communication", description: "Annonces, offres, messages", keywords: "annonce offre message notification broadcast push" },
  { id: "content-support", tab: "contenu", tabLabel: "Contenu", title: "💬 Messages support", description: "Répondre aux joueurs", keywords: "support chat message repondre joueur aide centre" },
  { id: "content-banners", tab: "contenu", tabLabel: "Contenu", title: "🎨 Bannières d'accueil", description: "Carousel promo", keywords: "banniere carousel promo image accueil slider" },
  { id: "content-help", tab: "contenu", tabLabel: "Contenu", title: "📚 Aide & tutoriels", description: "CMS, FAQ, conditions", keywords: "tutoriel aide help faq cgu conditions cms markdown texte" },
  { id: "content-communities", tab: "contenu", tabLabel: "Contenu", title: "🌍 Communautés", description: "Réseaux et liens externes", keywords: "reseau social communaute facebook whatsapp telegram lien" },
  // Config
  { id: "config-timers", tab: "config", tabLabel: "Config", title: "⏱️ Timers", description: "Tour, salle d'attente, minuteurs Échecs/Fanorona", keywords: "timer temps duree tour salle attente ready pret minuteur echec fanorona chrono" },
  { id: "config-app", tab: "config", tabLabel: "Config", title: "🛠️ Paramètres de l'application", description: "Contact, chat, spectateurs, AFK, statut des jeux", keywords: "contact facebook whatsapp email telephone apk download chat spectateur afk statut jeu actif desactive" },
  { id: "config-points", tab: "config", tabLabel: "Config", title: "🎯 Points & niveaux", description: "Barème XP", keywords: "points xp niveau level bareme progression" },
  { id: "config-referral", tab: "config", tabLabel: "Config", title: "🤝 Parrainage", description: "Commission, fenêtre, anti-fraude", keywords: "parrainage referral referral_events commission 5% 10 parties fraude bonus code invite" },
  { id: "config-advanced", tab: "config", tabLabel: "Config", title: "🧩 Réglages avancés", description: "Techniques et divers", keywords: "avance technique divers debug" },
];


function BroadcastHistory() {
  const [items, setItems] = useState<any[]>([]);
  useEffect(() => {
    supabase.from("admin_logs")
      .select("*, profiles!admin_id(pseudo)")
      .eq("action", "notify_tournament_players")
      .order("created_at", { ascending: false })
      .limit(10)
      .then(({ data }) => setItems((data as any[]) || []));
  }, []);
  if (items.length === 0) return <div className="text-xs text-muted-foreground py-2 text-center">Aucune diffusion envoyée.</div>;
  return (
    <div className="space-y-2">
      {items.map(l => {
        const v = l.new_value as any;
        return (
          <div key={l.id} className="border-t border-border/60 pt-2 text-xs space-y-0.5">
            <div className="flex items-center justify-between">
              <span className="font-bold">{v?.title ?? "—"}</span>
              <span className="text-muted-foreground shrink-0">{new Date(l.created_at).toLocaleString("fr-FR", { day:"2-digit", month:"2-digit", hour:"2-digit", minute:"2-digit" })}</span>
            </div>
            <div className="text-muted-foreground">{v?.body ?? ""}</div>
            <div className="text-muted-foreground">Par <b>{l.profiles?.pseudo ?? "admin"}</b> · {v?.recipients ?? "?"} destinataire(s)</div>
          </div>
        );
      })}
    </div>
  );
}




function T({ icon, label, active, onClick, danger, badge }: any) {
  return (
    <button onClick={onClick}
      className={[
        "px-3 py-2 rounded-xl flex items-center gap-1.5 text-sm font-semibold transition-all shrink-0",
        active
          ? (danger ? "bg-rose-500 text-white" : "bg-primary text-primary-foreground")
          : (danger ? "hover:bg-rose-50 dark:hover:bg-rose-950/30 text-rose-500" : "hover:bg-accent text-muted-foreground"),
      ].join(" ")}>
      {icon}
      <span>{label}</span>
      {badge > 0 && (
        <span className="bg-rose-500 text-white text-[10px] font-bold px-1.5 py-0.5 rounded-full leading-none min-w-[18px] text-center">
          {badge}
        </span>
      )}
    </button>
  );
}
function Card({ children }: any) { return <div className="rounded-3xl bg-card p-4 shadow-[var(--shadow-soft)] space-y-3">{children}</div>; }

function Tip({ children, type = "info" }: { children: React.ReactNode; type?: "info" | "warning" | "success" }) {
  const [open, setOpen] = useState(true);
  if (!open) return null;
  const styles = {
    info: "bg-blue-50 dark:bg-blue-900/20 border-blue-200 dark:border-blue-700 text-blue-800 dark:text-blue-200",
    warning: "bg-amber-50 dark:bg-amber-900/20 border-amber-200 dark:border-amber-700 text-amber-800 dark:text-amber-200",
    success: "bg-emerald-50 dark:bg-emerald-900/20 border-emerald-200 dark:border-emerald-700 text-emerald-800 dark:text-emerald-200",
  };
  const icons = { info: <Info className="w-4 h-4 shrink-0 mt-0.5" />, warning: <AlertCircle className="w-4 h-4 shrink-0 mt-0.5" />, success: <CheckCircle2 className="w-4 h-4 shrink-0 mt-0.5" /> };
  return (
    <div className={`rounded-2xl border p-3 flex gap-2 text-xs ${styles[type]}`}>
      {icons[type]}
      <div className="flex-1">{children}</div>
      <button onClick={() => setOpen(false)} className="opacity-50 hover:opacity-100 shrink-0">✕</button>
    </div>
  );
}

// =================== FINANCE ===================
function FinanceSection() {
  const [scope, setScope] = useState<"pending" | "all">("pending");
  return (
    <div className="space-y-4">
      <FinancialIntegrityCard />
      <div className="flex gap-2">
        <button onClick={() => setScope("pending")} className={`px-4 py-2 rounded-full text-sm font-semibold ${scope === "pending" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>⏳ En attente</button>
        <button onClick={() => setScope("all")} className={`px-4 py-2 rounded-full text-sm font-semibold ${scope === "all" ? "bg-primary text-primary-foreground" : "bg-secondary"}`}>📋 Historique</button>
      </div>
      <DepositsList scope={scope} />
      <WithdrawalsList scope={scope} />
    </div>
  );
}

function FinancialIntegrityCard() {
  const [kpi, setKpi] = useState<any>(null);
  const [report, setReport] = useState<any[] | null>(null);
  const [busy, setBusy] = useState(false);
  const fmt = (n: any) => Number(n || 0).toLocaleString("fr-FR") + " Ar";

  const loadKpi = async () => {
    const { data, error } = await supabase.rpc("admin_finance_kpi" as any);
    if (error) return toast.error(error.message);
    setKpi(data);
  };
  useEffect(() => { loadKpi(); }, []);

  const runAudit = async () => {
    setBusy(true);
    const { data, error } = await supabase.rpc("admin_reconcile_balances" as any);
    setBusy(false);
    if (error) return toast.error(error.message);
    setReport((data as any[]) || []);
    if (!data || (data as any[]).length === 0) toast.success("✅ Aucun écart détecté");
  };

  const runAlign = async () => {
    if (!confirm("Aligner automatiquement tous les soldes sur l'historique ? Une transaction 'admin_adjust' traçable sera créée pour chaque correction.")) return;
    setBusy(true);
    const { data, error } = await supabase.rpc("admin_align_balances" as any);
    setBusy(false);
    if (error) return toast.error(error.message);
    toast.success(`✅ ${(data as any[])?.length || 0} solde(s) aligné(s)`);
    setReport(null);
    loadKpi();
  };

  const gap = Number(kpi?.reconciliation_gap || 0);
  return (
    <Card>
      <div className="font-bold text-sm uppercase text-muted-foreground flex items-center gap-2 mb-3">
        🔐 Intégrité financière
      </div>
      {kpi ? (
        <div className="grid grid-cols-2 md:grid-cols-3 gap-2 text-xs">
          <Kpi label="Dépôts" value={fmt(kpi.total_deposits)} tone="emerald" />
          <Kpi label="Retraits" value={fmt(kpi.total_withdraws)} tone="rose" />
          <Kpi label="Mises jouées" value={fmt(kpi.total_stakes)} tone="slate" />
          <Kpi label="Gains payés" value={fmt(kpi.total_payouts)} tone="slate" />
          <Kpi label="Remboursements" value={fmt(kpi.total_refunds)} tone="slate" />
          <Kpi label="Bonus + Parrainage" value={fmt(kpi.total_bonus)} tone="slate" />
          <Kpi label="Total soldes" value={fmt(kpi.sum_balances)} tone="slate" />
          <Kpi label="Total ledger" value={fmt(kpi.sum_transactions)} tone="slate" />
          <Kpi label="Écart" value={fmt(gap)} tone={Math.abs(gap) < 1 ? "emerald" : "amber"} />
          <Kpi label="Retraits en attente" value={fmt(kpi.pending_withdrawals)} tone="amber" />
          <Kpi label="Dépôts en attente" value={fmt(kpi.pending_deposits)} tone="amber" />
        </div>
      ) : <div className="text-xs text-muted-foreground">Chargement…</div>}

      <div className="flex flex-wrap gap-2 mt-3">
        <button disabled={busy} onClick={runAudit} className="px-3 py-1.5 rounded-full bg-secondary text-xs font-semibold disabled:opacity-50">
          🔎 Lancer l'audit
        </button>
        <button disabled={busy} onClick={runAlign} className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-xs font-semibold disabled:opacity-50">
          🛠 Aligner automatiquement
        </button>
        <button disabled={busy} onClick={async () => {
          setBusy(true);
          const { data, error } = await supabase.rpc("admin_audit_unlogged_changes" as any, { _hours: 24 });
          setBusy(false);
          if (error) return toast.error(error.message);
          const rows = (data as any[]) || [];
          if (rows.length === 0) toast.success("✅ Aucun mouvement non tracé (24h)");
          else toast.warning(`⚠️ ${rows.length} utilisateur(s) avec des mouvements non tracés`, {
            description: rows.slice(0, 3).map((r: any) => `${r.pseudo}: ${Number(r.unlogged).toLocaleString("fr-FR")} Ar`).join(" · "),
          });
        }} className="px-3 py-1.5 rounded-full bg-secondary text-xs font-semibold disabled:opacity-50">
          🕵️ Détecter mouvements non tracés (24h)
        </button>
        <button onClick={loadKpi} className="px-3 py-1.5 rounded-full bg-secondary text-xs font-semibold">↻ Recharger KPI</button>
      </div>


      {report && (
        <div className="mt-3 border-t border-border/60 pt-3">
          <div className="text-xs font-semibold mb-2">Écarts détectés : {report.length}</div>
          {report.length === 0 ? (
            <div className="text-xs text-emerald-600">Ledger cohérent.</div>
          ) : (
            <div className="space-y-1 max-h-64 overflow-y-auto text-xs">
              {report.map((r: any) => (
                <div key={r.user_id} className="flex justify-between gap-2 border-b border-border/40 py-1">
                  <span className="truncate"><b>{r.pseudo || "—"}</b></span>
                  <span className="text-muted-foreground">solde {fmt(r.balance)} · txs {fmt(r.tx_sum)}</span>
                  <span className={Number(r.diff) > 0 ? "text-amber-600 font-semibold" : "text-sky-600 font-semibold"}>
                    {Number(r.diff) > 0 ? "+" : ""}{fmt(r.diff)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      <HouseIncomePanel />
    </Card>
  );
}

function HouseIncomePanel() {
  const [rows, setRows] = useState<any[] | null>(null);
  const [days, setDays] = useState(30);
  const fmt = (n: any) => Number(n || 0).toLocaleString("fr-FR") + " Ar";

  const load = async () => {
    const since = new Date(Date.now() - days * 86400_000).toISOString();
    const { data, error } = await supabase.rpc("admin_house_income" as any, { _since: since });
    if (error) return toast.error(error.message);
    setRows((data as any[]) || []);
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [days]);

  const totalCom = (rows || []).reduce((s, r) => s + Number(r.commission_total || 0), 0);
  const totalHouse = (rows || []).reduce((s, r) => s + Number(r.house_win_total || 0), 0);

  return (
    <div className="mt-4 border-t border-border/60 pt-3">
      <div className="flex items-center justify-between mb-2">
        <div className="text-xs font-semibold">💰 Revenus de la maison</div>
        <select value={days} onChange={(e) => setDays(Number(e.target.value))} className="text-[11px] bg-secondary rounded px-1.5 py-0.5">
          <option value={7}>7 j</option>
          <option value={30}>30 j</option>
          <option value={90}>90 j</option>
          <option value={365}>1 an</option>
        </select>
      </div>
      <div className="grid grid-cols-2 gap-2 text-xs mb-2">
        <Kpi label="Commissions" value={fmt(totalCom)} tone="emerald" />
        <Kpi label="Gains vs bots" value={fmt(totalHouse)} tone="emerald" />
      </div>
      {rows && rows.length > 0 ? (
        <div className="space-y-1 text-xs">
          {rows.map((r: any) => (
            <div key={r.game_type} className="flex justify-between border-b border-border/40 py-1">
              <span className="capitalize font-semibold">{r.game_type}</span>
              <span className="text-muted-foreground">com. {fmt(r.commission_total)} · maison {fmt(r.house_win_total)}</span>
            </div>
          ))}
        </div>
      ) : (
        <div className="text-[11px] text-muted-foreground">Aucun revenu sur la période.</div>
      )}
    </div>
  );
}


function Kpi({ label, value, tone }: { label: string; value: string; tone: "emerald" | "rose" | "amber" | "slate" }) {
  const bg = { emerald: "bg-emerald-500/10 text-emerald-700 dark:text-emerald-300", rose: "bg-rose-500/10 text-rose-700 dark:text-rose-300", amber: "bg-amber-500/10 text-amber-700 dark:text-amber-300", slate: "bg-secondary text-foreground" }[tone];
  return (
    <div className={`rounded-lg px-2 py-1.5 ${bg}`}>
      <div className="text-[10px] uppercase tracking-wide opacity-75">{label}</div>
      <div className="font-bold text-sm">{value}</div>
    </div>
  );
}


function DepositsList({ scope }: { scope: "pending" | "all" }) {
  const [items, setItems] = useState<any[]>([]);
  const load = async () => {
    let q = supabase.from("deposits").select("*").order("created_at", { ascending: false }).limit(200);
    if (scope === "pending") q = q.eq("status", "pending");
    else q = q.in("status", ["approved", "rejected"]);
    const { data, error } = await q;
    if (error) { toast.error(error.message); return; }
    const rows = data || [];
    const ids = Array.from(new Set(rows.map((r: any) => r.user_id)));
    let profMap: Record<string, any> = {};
    if (ids.length) {
      const { data: profs } = await supabase.from("profiles").select("id,pseudo,email,unique_code").in("id", ids as string[]);
      profMap = Object.fromEntries((profs || []).map((p: any) => [p.id, p]));
    }
    setItems(rows.map((r: any) => ({ ...r, profiles: profMap[r.user_id] })));
  };
  useEffect(() => { load(); }, [scope]);
  const act = async (id: string, ok: boolean) => {
    const { error } = await supabase.rpc("admin_process_deposit", { _id: id, _approve: ok });
    if (error) return toast.error(error.message);
    toast.success(ok ? "✅ Dépôt approuvé — solde crédité" : "❌ Dépôt rejeté"); load();
  };
  return (
    <Card>
      <div className="font-bold text-sm uppercase text-muted-foreground flex items-center gap-2">💰 Dépôts <span className="text-[10px] normal-case font-normal bg-secondary px-2 py-0.5 rounded-full">{items.length}</span></div>
      {items.length === 0 ? <div className="text-center text-muted-foreground py-3 text-sm">Aucun dépôt {scope === "pending" ? "en attente" : ""}</div> :
        items.map(d => (
          <div key={d.id} className="border-t border-border/60 pt-3 space-y-1.5">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <div className="font-bold">{Number(d.amount).toLocaleString("fr-FR")} Ar <span className="text-xs font-normal text-muted-foreground">· {d.method}</span></div>
                <div className="text-xs"><b>{d.profiles?.pseudo || "—"}</b> <span className="text-muted-foreground">({d.profiles?.email})</span></div>
                <div className="text-xs text-muted-foreground font-mono">{d.profiles?.unique_code || "—"}</div>
                <div className="text-xs">Réf payeur: <b className="font-mono text-primary">{d.user_reference || d.reference}</b></div>
                <div className="text-xs">Tel: <b>{d.user_phone || "—"}</b></div>
                <div className="text-[10px] text-muted-foreground">{new Date(d.created_at).toLocaleString("fr-FR")}</div>
                <div className="text-xs">Statut: <b className={d.status === "pending" ? "text-amber-600" : d.status === "approved" ? "text-emerald-600" : "text-destructive"}>{d.status}</b></div>
              </div>
              {d.status === "pending" && (
                <div className="flex flex-col gap-1.5 shrink-0">
                  <button onClick={() => act(d.id, true)} className="px-3 py-1.5 rounded-full bg-emerald-500 text-white text-xs font-semibold">✓ Valider</button>
                  <button onClick={() => act(d.id, false)} className="px-3 py-1.5 rounded-full bg-destructive text-white text-xs font-semibold">✕ Refuser</button>
                </div>
              )}
            </div>
          </div>
        ))}
    </Card>
  );
}

function WithdrawalsList({ scope }: { scope: "pending" | "all" }) {
  const [items, setItems] = useState<any[]>([]);
  const load = async () => {
    let q = supabase.from("withdrawals").select("*").order("created_at", { ascending: false }).limit(200);
    if (scope === "pending") q = q.eq("status", "pending");
    else q = q.in("status", ["approved", "rejected"]);
    const { data, error } = await q;
    if (error) { toast.error(error.message); return; }
    const rows = data || [];
    const ids = Array.from(new Set(rows.map((r: any) => r.user_id)));
    let profMap: Record<string, any> = {};
    if (ids.length) {
      const { data: profs } = await supabase.from("profiles").select("id,pseudo,email,unique_code").in("id", ids as string[]);
      profMap = Object.fromEntries((profs || []).map((p: any) => [p.id, p]));
    }
    setItems(rows.map((r: any) => ({ ...r, profiles: profMap[r.user_id] })));
  };
  useEffect(() => { load(); }, [scope]);
  const act = async (id: string, ok: boolean) => {
    const { error } = await supabase.rpc("admin_process_withdrawal", { _id: id, _approve: ok });
    if (error) return toast.error(error.message);
    toast.success(ok ? "✅ Retrait approuvé" : "❌ Retrait rejeté"); load();
  };
  return (
    <Card>
      <div className="font-bold text-sm uppercase text-muted-foreground flex items-center gap-2">💸 Retraits <span className="text-[10px] normal-case font-normal bg-secondary px-2 py-0.5 rounded-full">{items.length}</span></div>
      {items.length === 0 ? <div className="text-center text-muted-foreground py-3 text-sm">Aucun retrait {scope === "pending" ? "en attente" : ""}</div> :
        items.map(d => (
          <div key={d.id} className="border-t border-border/60 pt-3 space-y-1.5">
            <div className="flex items-start justify-between gap-2">
              <div className="min-w-0">
                <div className="font-bold">{Number(d.amount).toLocaleString("fr-FR")} Ar <span className="text-xs font-normal text-muted-foreground">· {d.method}</span></div>
                <div className="text-xs"><b>{d.profiles?.pseudo || "—"}</b> <span className="text-muted-foreground">({d.profiles?.email})</span></div>
                <div className="text-xs text-muted-foreground font-mono">{d.profiles?.unique_code || "—"}</div>
                <div className="text-xs">📱 Tel destinataire: <b className="text-primary">{d.user_phone}</b></div>
                {d.bank_name && (
                  <div className="text-xs">🏦 Banque: <b className="text-primary">{d.bank_name}</b></div>
                )}
                {d.bank_account_number && (
                  <div className="text-xs">💳 Compte: <b className="font-mono text-primary">{d.bank_account_number}</b></div>
                )}
                {d.recipient_name && (
                  <div className="text-xs">👤 Nom destinataire: <b className="text-foreground">{d.recipient_name}</b></div>
                )}
                <div className="text-[10px] text-muted-foreground">{new Date(d.created_at).toLocaleString("fr-FR")}</div>
                <div className="text-xs">Statut: <b className={d.status === "pending" ? "text-amber-600" : d.status === "approved" ? "text-emerald-600" : "text-destructive"}>{d.status}</b></div>
              </div>
              {d.status === "pending" && (
                <div className="flex flex-col gap-1.5 shrink-0">
                  <button onClick={() => act(d.id, true)} className="px-3 py-1.5 rounded-full bg-emerald-500 text-white text-xs font-semibold">✓ Valider</button>
                  <button onClick={() => act(d.id, false)} className="px-3 py-1.5 rounded-full bg-destructive text-white text-xs font-semibold">✕ Refuser</button>
                </div>
              )}
            </div>
          </div>
        ))}
    </Card>
  );
}

// =================== STATS ===================
const PERIODS = [{ d: 1, l: "Aujourd'hui" }, { d: 2, l: "2j" }, { d: 7, l: "7j" }, { d: 14, l: "14j" }, { d: 30, l: "30j" }];
function StatsSection() {
  const [days, setDays] = useState(7);
  const [rows, setRows] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);
  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc("admin_stats_daily" as any, { _days: days } as any);
    setLoading(false);
    if (error) return toast.error(error.message);
    setRows((data as any[]) || []);
  };
  useEffect(() => { load(); }, [days]);

  const totals = rows.reduce((acc, r) => ({
    deposits: acc.deposits + Number(r.deposits || 0),
    withdrawals: acc.withdrawals + Number(r.withdrawals || 0),
    wins: acc.wins + Number(r.wins || 0),
    commission: acc.commission + Number(r.commission || 0),
    stakes: acc.stakes + Number(r.stakes || 0),
    new_users: acc.new_users + Number(r.new_users || 0),
    active_users: Math.max(acc.active_users, Number(r.active_users || 0)),
    games: acc.games + Number(r.games_finished || 0),
  }), { deposits: 0, withdrawals: 0, wins: 0, commission: 0, stakes: 0, new_users: 0, active_users: 0, games: 0 });

  const netProfit = totals.commission - Math.max(0, totals.withdrawals - totals.deposits);
  const maxCommission = Math.max(1, ...rows.map(r => Number(r.commission || 0)));

  const exportCsv = () => {
    const header = "Date;Dépôts;Retraits;Gains joueurs;Commission;Mises;Nouveaux;Actifs;Parties\n";
    const body = rows.map(r => [
      new Date(r.day).toLocaleDateString("fr-FR"),
      Math.round(r.deposits), Math.round(r.withdrawals), Math.round(r.wins),
      Math.round(r.commission), Math.round(r.stakes),
      r.new_users, r.active_users, r.games_finished,
    ].join(";")).join("\n");
    const blob = new Blob([header + body], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `stats-${days}j-${new Date().toISOString().slice(0,10)}.csv`;
    a.click(); URL.revokeObjectURL(url);
  };

  return (
    <div className="space-y-4">
      <Card>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap gap-2">
            {PERIODS.map(p => (
              <button key={p.d} onClick={() => setDays(p.d)} className={`px-3 py-1.5 rounded-full text-sm font-semibold transition ${days === p.d ? "bg-primary text-primary-foreground shadow" : "bg-secondary hover:bg-secondary/70"}`}>{p.l}</button>
            ))}
          </div>
          <button onClick={exportCsv} disabled={loading || rows.length === 0} className="px-3 py-1.5 rounded-full text-xs font-semibold bg-secondary hover:bg-secondary/70 disabled:opacity-50">📥 Export CSV</button>
        </div>

        <div className="mt-3 rounded-2xl bg-gradient-to-br from-primary/15 to-primary/5 border border-primary/20 p-4">
          <div className="text-[11px] uppercase tracking-wide text-muted-foreground font-semibold">Bénéfice net estimé</div>
          <div className={`text-2xl font-extrabold ${netProfit >= 0 ? "text-emerald-600" : "text-destructive"}`}>
            {netProfit >= 0 ? "+" : ""}{Math.round(netProfit).toLocaleString("fr-FR")} Ar
          </div>
          <div className="text-[11px] text-muted-foreground mt-0.5">Commission − (retraits − dépôts) sur {days}j</div>
        </div>

        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 pt-3">
          <Stat label="💰 Commission" value={totals.commission} color="text-primary" suffix="Ar" />
          <Stat label="🎯 Mises totales" value={totals.stakes} color="text-indigo-600" suffix="Ar" />
          <Stat label="📥 Dépôts" value={totals.deposits} color="text-emerald-600" suffix="Ar" />
          <Stat label="📤 Retraits" value={totals.withdrawals} color="text-destructive" suffix="Ar" />
          <Stat label="🏆 Gains payés" value={totals.wins} color="text-amber-600" suffix="Ar" />
          <Stat label="🎮 Parties" value={totals.games} color="text-sky-600" />
          <Stat label="👥 Nouveaux" value={totals.new_users} color="text-fuchsia-600" />
          <Stat label="⚡ Actifs (pic/j)" value={totals.active_users} color="text-teal-600" />
        </div>
      </Card>

      <Card>
        <div className="font-bold text-sm uppercase text-muted-foreground mb-2">Commission par jour</div>
        {loading ? <div className="text-center text-muted-foreground py-3">Chargement…</div> : rows.length === 0 ? <div className="text-center text-muted-foreground py-3 text-sm">Aucune donnée</div> : (
          <div className="flex items-end gap-1 h-24">
            {[...rows].reverse().map(r => {
              const v = Number(r.commission || 0);
              const h = Math.max(2, Math.round((v / maxCommission) * 100));
              return (
                <div key={r.day} className="flex-1 flex flex-col items-center gap-1">
                  <div className="w-full bg-primary/70 hover:bg-primary rounded-t transition" style={{ height: `${h}%` }} title={`${new Date(r.day).toLocaleDateString("fr-FR")} · ${Math.round(v).toLocaleString("fr-FR")} Ar`} />
                  <div className="text-[8px] text-muted-foreground">{new Date(r.day).getDate()}</div>
                </div>
              );
            })}
          </div>
        )}
      </Card>

      <Card>
        <div className="font-bold text-sm uppercase text-muted-foreground">Détail par jour</div>
        {loading ? <div className="text-center text-muted-foreground py-3">Chargement…</div> :
          <div className="overflow-x-auto -mx-3 px-3">
            <table className="w-full text-xs min-w-[560px]">
              <thead>
                <tr className="text-left text-muted-foreground border-b border-border/60">
                  <th className="py-2">Date</th>
                  <th className="text-right">Dépôts</th>
                  <th className="text-right">Retraits</th>
                  <th className="text-right">Commission</th>
                  <th className="text-right">Parties</th>
                  <th className="text-right">Nouveaux</th>
                </tr>
              </thead>
              <tbody>
                {rows.map(r => (
                  <tr key={r.day} className="border-b border-border/40 last:border-0">
                    <td className="py-2 font-semibold">{new Date(r.day).toLocaleDateString("fr-FR", { weekday: "short", day: "2-digit", month: "2-digit" })}</td>
                    <td className="text-right text-emerald-600">+{Number(r.deposits).toLocaleString("fr-FR")}</td>
                    <td className="text-right text-destructive">-{Number(r.withdrawals).toLocaleString("fr-FR")}</td>
                    <td className="text-right text-primary font-semibold">{Math.round(Number(r.commission)).toLocaleString("fr-FR")}</td>
                    <td className="text-right text-sky-600">{r.games_finished}</td>
                    <td className="text-right text-fuchsia-600">{r.new_users}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>}
      </Card>
    </div>
  );
}
function Stat({ label, value, color, suffix }: { label: string; value: number; color: string; suffix?: string }) {
  return (
    <div className="rounded-2xl bg-secondary p-3 text-center">
      <div className="text-[10px] uppercase text-muted-foreground font-semibold">{label}</div>
      <div className={`text-base font-extrabold ${color} leading-tight mt-0.5`}>
        {Math.round(value).toLocaleString("fr-FR")}{suffix ? <span className="text-[10px] font-semibold text-muted-foreground ml-0.5">{suffix}</span> : null}
      </div>
    </div>
  );
}
function UserHistorySearch() {
  const [q, setQ] = useState(""); const [users, setUsers] = useState<any[]>([]); const [hist, setHist] = useState<any>(null);
  const search = async () => {
    if (!q.trim()) return;
    const { data } = await supabase.rpc("admin_list_users" as any);
    setUsers(((data as any[]) || []).filter((u: any) => u.pseudo?.toLowerCase().includes(q.toLowerCase()) || u.email?.toLowerCase().includes(q.toLowerCase())).slice(0, 10));
  };
  const view = async (u: any) => {
    const { data, error } = await supabase.rpc("admin_user_history" as any, { _user_id: u.id } as any);
    if (error) return toast.error(error.message);
    setHist(data);
  };
  return (
    <Card>
      <div className="font-bold text-sm uppercase text-muted-foreground">Historique d'un joueur</div>
      <div className="flex gap-2">
        <input value={q} onChange={e => setQ(e.target.value)} placeholder="pseudo ou email"
          className="flex-1 px-4 py-2 rounded-full bg-card border border-border outline-none" />
        <button onClick={search} className="px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold">Chercher</button>
      </div>
      {users.length > 0 && !hist && users.map(u => (
        <button key={u.id} onClick={() => view(u)} className="w-full text-left px-3 py-2 rounded-xl hover:bg-accent">
          <div className="font-semibold">{u.pseudo}</div>
          <div className="text-xs text-muted-foreground">{u.email} · {Math.round(Number(u.balance_ar)).toLocaleString("fr-FR")} Ar</div>
        </button>
      ))}
      {hist && (
        <div className="space-y-3">
          <button onClick={() => { setHist(null); setUsers([]); setQ(""); }} className="text-xs underline">← retour</button>
          <div className="font-bold">{hist.profile?.pseudo} — {Math.round(Number(hist.profile?.balance_ar || 0)).toLocaleString("fr-FR")} Ar</div>
          <Section title={`Transactions (${hist.transactions?.length || 0})`} items={hist.transactions} render={(t: any) => `${new Date(t.created_at).toLocaleDateString("fr-FR")} · ${t.type} · ${Number(t.amount).toLocaleString("fr-FR")} Ar${t.note ? " — " + t.note : ""}`} />
          <Section title={`Dépôts (${hist.deposits?.length || 0})`} items={hist.deposits} render={(d: any) => `${new Date(d.created_at).toLocaleDateString("fr-FR")} · ${Number(d.amount).toLocaleString("fr-FR")} Ar · ${d.status}`} />
          <Section title={`Retraits (${hist.withdrawals?.length || 0})`} items={hist.withdrawals} render={(w: any) => `${new Date(w.created_at).toLocaleDateString("fr-FR")} · ${Number(w.amount).toLocaleString("fr-FR")} Ar · ${w.status}`} />
          <Section title={`Parties (${hist.games?.length || 0})`} items={hist.games} render={(g: any) => `${g.finished_at ? new Date(g.finished_at).toLocaleDateString("fr-FR") : "—"} · mise ${Number(g.stake).toLocaleString("fr-FR")} Ar · ${g.status}${g.won ? " · 🏆 gagné" : ""}`} />
        </div>
      )}
    </Card>
  );
}
function Section({ title, items, render }: any) {
  return (
    <div>
      <div className="text-xs uppercase font-bold text-muted-foreground">{title}</div>
      <div className="space-y-0.5 max-h-48 overflow-y-auto">{(items || []).map((x: any, i: number) => <div key={i} className="text-xs border-b border-border/40 py-1">{render(x)}</div>)}</div>
    </div>
  );
}

// =================== USERS ===================
function UsersList() {
  const confirm = useConfirm();
  const [q, setQ] = useState(""); const [sort, setSort] = useState<"recent" | "balance" | "pseudo">("recent");
  const [items, setItems] = useState<any[]>([]);
  const [showList, setShowList] = useState(false);
  const [loading, setLoading] = useState(false);
  const isBotUser = (u: any) => u?.is_bot === true
    || /@bot\.lalaomada\.internal$/i.test(u?.email || "")
    || /@lalao\.local$/i.test(u?.email || "")
    || /^chessbot_/i.test(u?.email || "");
  const load = async () => {
    setLoading(true);
    try {
      if (q.trim()) { const { data } = await supabase.rpc("admin_search_users" as any, { _q: q } as any); setItems(((data as any[]) || []).filter((u: any) => !isBotUser(u))); }
      else { const { data } = await supabase.rpc("admin_list_users_sorted" as any, { _sort: sort } as any); setItems(((data as any[]) || []).filter((u: any) => !isBotUser(u))); }
    } finally { setLoading(false); }
  };
  useEffect(() => { if (showList) load(); }, [sort, showList]);
  const adjust = async (id: string) => {
    const v = prompt("Montant à ajouter/retirer (ex: +500 ou -200):"); if (!v) return;
    const note = prompt("Note (visible dans l'historique):") || "";
    const { error } = await supabase.rpc("admin_adjust_balance", { _user_id: id, _amount: Number(v), _note: note });
    if (error) return toast.error(error.message);
    toast.success("Solde ajusté"); load();
  };
  const ban = async (id: string, b: boolean) => {
    if (b && !(await confirm({ title: "Bannir cet utilisateur ? Il ne pourra plus se connecter.", destructive: true }))) return;
    const { error } = await supabase.rpc("admin_set_user_banned" as any, { _user_id: id, _banned: b } as any);
    if (error) return toast.error(error.message);
    toast.success(b ? "Utilisateur banni" : "Utilisateur débanni"); load();
  };
  const permanentlyDelete = async (u: any) => {
    const ok = await confirm({
      title: `Supprimer définitivement ${u.pseudo} ?`,
      description: "Toutes les données de ce joueur (profil, transactions, historique) seront effacées de la plateforme. Cette action est irréversible.",
      confirmLabel: "Supprimer définitivement",
      destructive: true,
    });
    if (!ok) return;
    const { error } = await supabase.rpc("admin_permanently_delete_user" as any, { _user_id: u.id } as any);
    if (error) return toast.error(error.message);
    toast.success(`Compte de ${u.pseudo} supprimé définitivement.`);
    load();
  };
  return (
    <div className="space-y-4">
      <Card>
        <div className="space-y-3">
          <div className="flex items-center justify-between gap-2">
            <div>
              <div className="text-base font-bold">👥 Joueurs</div>
              <div className="text-xs text-muted-foreground">Recherche, tri et gestion des comptes</div>
            </div>
            {showList && (
              <span className="text-[11px] px-2 py-1 rounded-full bg-secondary font-semibold">{items.length}</span>
            )}
          </div>

          <div className="relative">
            <span className="absolute left-3 top-1/2 -translate-y-1/2 text-muted-foreground text-sm">🔍</span>
            <input
              value={q}
              onChange={e => setQ(e.target.value)}
              onKeyDown={e => { if (e.key === "Enter") { setShowList(true); load(); } }}
              placeholder="Pseudo, email ou ID unique…"
              className="w-full pl-9 pr-3 py-2.5 rounded-xl bg-secondary/60 border border-border/60 outline-none focus:border-primary focus:bg-card text-sm transition"
            />
          </div>

          <div className="flex items-center gap-1 p-1 rounded-xl bg-secondary/50 text-xs font-semibold">
            {([
              { k: "recent", label: "Récents" },
              { k: "balance", label: "Solde" },
              { k: "pseudo", label: "A–Z" },
            ] as const).map(o => (
              <button
                key={o.k}
                onClick={() => setSort(o.k)}
                className={`flex-1 py-1.5 rounded-lg transition ${sort === o.k ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"}`}
              >{o.label}</button>
            ))}
          </div>

          <button
            onClick={() => { setShowList(true); load(); }}
            className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground font-semibold text-sm shadow-sm active:scale-[0.99] transition"
          >
            {showList ? "🔄 Actualiser" : "👥 Afficher la liste"}
          </button>
        </div>

        {showList && (
          <div className="mt-4 space-y-2">
            <div className="flex items-center justify-between">
              <div className="text-[11px] uppercase tracking-wide text-muted-foreground font-semibold">Résultats</div>
              <button onClick={() => setShowList(false)} className="text-[11px] text-muted-foreground hover:text-foreground underline">Masquer</button>
            </div>
            {loading && <div className="text-center text-xs text-muted-foreground py-6">Chargement…</div>}
            {!loading && items.length === 0 && <div className="text-center text-xs text-muted-foreground py-6">Aucun joueur</div>}
            {!loading && items.map(u => (
              <div key={u.id} className="p-3 rounded-xl bg-secondary/40 border border-border/40 hover:border-border transition space-y-2">
                <div className="flex items-start justify-between gap-2">
                  <div className="min-w-0 flex-1">
                    <div className="font-bold text-sm flex items-center gap-1.5 flex-wrap">
                      <span className="truncate">{u.pseudo}</span>
                      {u.is_admin && <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-primary text-primary-foreground">admin</span>}
                      {u.banned && <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-destructive text-white">banni</span>}
                      {!u.phone_verified && <span className="text-[9px] px-1.5 py-0.5 rounded-full bg-amber-100 text-amber-700">non vérifié</span>}
                    </div>
                    <div className="text-[11px] text-muted-foreground truncate">{u.email}</div>
                    <div className="text-[10px] font-mono text-muted-foreground/80 mt-0.5">{u.unique_code}</div>
                  </div>
                  <div className="text-right shrink-0">
                    <div className="text-[10px] uppercase text-muted-foreground">Solde</div>
                    <div className="font-bold text-sm">{Math.round(Number(u.balance_ar)).toLocaleString("fr-FR")}<span className="text-[10px] font-normal ml-0.5">Ar</span></div>
                  </div>
                </div>
                <div className="flex gap-1.5 pt-1 border-t border-border/40">
                  <button onClick={() => adjust(u.id)} className="flex-1 px-2 py-1.5 rounded-lg bg-card text-xs font-semibold hover:bg-primary hover:text-primary-foreground transition">💰 Solde</button>
                  <button onClick={() => ban(u.id, !u.banned)} className={`flex-1 px-2 py-1.5 rounded-lg text-xs font-semibold transition ${u.banned ? "bg-emerald-500 text-white" : "bg-card hover:bg-destructive hover:text-white"}`}>{u.banned ? "Débannir" : "Bannir"}</button>
                  <button onClick={() => permanentlyDelete(u)} className="px-2.5 py-1.5 rounded-lg text-xs font-semibold bg-card hover:bg-rose-900 hover:text-white transition" title="Supprimer">🗑</button>
                </div>
              </div>
            ))}
          </div>
        )}
      </Card>
    </div>
  );
}

// =================== GAMES ===================
function GamesList() {
  const [items, setItems] = useState<any[]>([]);
  const load = async () => { const { data } = await supabase.from("ludo_games").select("*, ludo_participants(*)").in("status", ["open", "playing"]).order("created_at", { ascending: false }); setItems(data || []); };
  useEffect(() => { load(); }, []);
  const addBot = async (gameId: string) => {
    const name = prompt("Nom du bot:", "BotMax"); if (!name) return;
    const intel = Number(prompt("Niveau d'intelligence (0-100):", "70")) || 70;
    const bias = Number(prompt("Biais de gain (0-100, 0 = équitable):", "0")) || 0;
    const { error } = await supabase.rpc("admin_add_bot" as any, { _game_id: gameId, _bot_name: name, _intelligence: intel, _win_bias: bias } as any);
    if (error) return toast.error(error.message);
    toast.success("Bot ajouté"); load();
  };
  const editBot = async (p: any) => {
    const { data: cfg } = await supabase.rpc("admin_get_bot_config" as any, { _participant_id: p.id } as any);
    const current = (Array.isArray(cfg) ? cfg[0] : cfg) || { intelligence: 70, win_bias: 0 };
    const name = prompt("Nouveau nom:", p.display_name) ?? p.display_name;
    const intel = Number(prompt("Intelligence (0-100):", String(current.intelligence ?? 70)));
    const bias = Number(prompt("Biais de gain (0-100):", String(current.win_bias ?? 0)));
    if (name && name !== p.display_name) await supabase.rpc("admin_rename_bot" as any, { _participant_id: p.id, _name: name } as any);
    const { error } = await supabase.rpc("admin_update_bot" as any, { _participant_id: p.id, _intelligence: intel, _win_bias: bias } as any);
    if (error) return toast.error(error.message);
    toast.success("Bot mis à jour"); load();
  };
  return (
    <div className="space-y-4">
      <Card>
        {items.length === 0 ? <div className="text-center text-muted-foreground py-6">Aucune partie active en ce moment</div> :
          items.map(g => (
            <div key={g.id} className="border-t border-border/60 pt-3">
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-bold">Mise: {Number(g.stake).toLocaleString("fr-FR")} Ar — {g.ludo_participants.length}/{g.max_players} joueurs</div>
                  <div className={`text-xs font-semibold mt-0.5 ${g.status === "playing" ? "text-emerald-600" : "text-amber-600"}`}>{g.status === "playing" ? "🟢 En cours" : "⏳ En attente"}</div>
                  <div className="flex gap-1 mt-1 flex-wrap">
                    {g.ludo_participants.map((p: any) => (
                      <button key={p.id} onClick={() => p.is_bot && editBot(p)}
                        className={`text-xs px-2 py-0.5 rounded-full bg-secondary ${p.is_bot ? "hover:bg-primary hover:text-primary-foreground cursor-pointer border border-primary/30" : ""}`}
                        title={p.is_bot ? "Bot · cliquez pour modifier" : ""}>
                        {p.display_name}{p.is_bot ? " [IA]" : ""}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="flex flex-col gap-2">
                  {g.status === "open" && g.ludo_participants.length < g.max_players && (
                    <button onClick={() => addBot(g.id)} className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-sm font-semibold">+ Bot</button>
                  )}
                  <a href={`/game/${g.id}`} className="px-3 py-1.5 rounded-full bg-secondary text-sm font-semibold text-center">👁 Entrer</a>
                </div>
              </div>
            </div>
          ))}
      </Card>
    </div>
  );
}

// =================== TOURNAMENTS ===================
function TournamentsSection() {
  return <TournamentAdminPanel />;
}

function PauseControl() {
  const [s, setS] = useState<any>(null); const [msg, setMsg] = useState("");
  const load = async () => { const { data } = await supabase.from("app_settings").select("*").eq("id", 1).maybeSingle(); setS(data); setMsg(data?.pause_message || ""); };
  useEffect(() => { load(); }, []);
  const toggle = async () => {
    const { error } = await supabase.rpc("admin_set_pause" as any, { _paused: !s?.paused, _message: msg } as any);
    if (error) return toast.error(error.message);
    toast.success(s?.paused ? "▶️ Application reprise" : "⏸ Application en pause"); load();
  };
  if (!s) return null;
  return (
    <Card>
      <div className="flex items-center justify-between">
        <div>
          <div className="font-bold">État de l'application</div>
          <div className={`text-xs font-semibold mt-0.5 ${s.paused ? "text-destructive" : "text-emerald-600"}`}>{s.paused ? "⏸ EN PAUSE (tous les joueurs voient la bannière)" : "▶️ EN LIGNE"}</div>
        </div>
        <button onClick={toggle} className={`px-4 py-2 rounded-full text-sm font-bold flex items-center gap-2 ${s.paused ? "bg-emerald-500 text-white" : "bg-destructive text-white"}`}>
          {s.paused ? <><Play className="w-4 h-4" /> Reprendre</> : <><Pause className="w-4 h-4" /> Mettre en pause</>}
        </button>
      </div>
      <input value={msg} onChange={e => setMsg(e.target.value)} placeholder="Message affiché aux joueurs (ex: Maintenance en cours, retour dans 30 min)"
        className="w-full px-4 py-2.5 rounded-full bg-card border border-border outline-none text-sm" />
    </Card>
  );
}

// =================== ADMIN PIN ===================

function AdminPinSetup() {
  const [newPin, setNewPin] = useState("");
  const [confirmPin, setConfirmPin] = useState("");
  const [saving, setSaving] = useState(false);
  const [hasPin, setHasPin] = useState<boolean | null>(null);

  useEffect(() => {
    (supabase.rpc("admin_verify_pin" as any, { _pin: "" } as any) as any).then(({ data }: any) => {
      setHasPin(data?.reason !== "no_pin_set");
    }).catch(() => setHasPin(null));
  }, []);

  const save = async () => {
    if (newPin.length < 4) return toast.error("PIN trop court (min 4 caractères)");
    if (newPin !== confirmPin) return toast.error("Les PIN ne correspondent pas");
    if (!/^[A-Za-z0-9]+$/.test(newPin)) return toast.error("Alphanumérique uniquement");
    setSaving(true);
    const { error } = await supabase.rpc("admin_set_pin" as any, { _pin: newPin } as any);
    setSaving(false);
    if (error) return toast.error(error.message);
    toast.success("PIN admin défini ✅");
    setHasPin(true);
    setNewPin("");
    setConfirmPin("");
  };

  return (
    <div className="space-y-4">
      <div className="flex items-center gap-2">
        <Lock className="w-4 h-4 text-primary" />
        <div className="text-sm font-semibold">PIN de sécurité admin</div>
      </div>
      <div className={`text-xs font-semibold ${hasPin ? "text-emerald-600" : "text-amber-600"}`}>
        {hasPin ? "✅ PIN configuré" : "⚠️ Aucun PIN défini — l'accès admin est non protégé"}
      </div>
      <div className="space-y-3">
        <div>
          <label className="text-xs text-muted-foreground mb-1 block">Nouveau PIN (min 4 caractères alphanumériques)</label>
          <input
            type="password"
            inputMode="numeric"
            value={newPin}
            onChange={(e) => setNewPin(e.target.value)}
            maxLength={12}
            placeholder="••••"
            className="w-full px-4 py-2.5 rounded-xl bg-secondary outline-none text-sm tracking-widest"
          />
        </div>
        <div>
          <label className="text-xs text-muted-foreground mb-1 block">Confirmer le PIN</label>
          <input
            type="password"
            inputMode="numeric"
            value={confirmPin}
            onChange={(e) => setConfirmPin(e.target.value)}
            maxLength={12}
            placeholder="••••"
            className="w-full px-4 py-2.5 rounded-xl bg-secondary outline-none text-sm tracking-widest"
          />
        </div>
        <button
          onClick={save}
          disabled={saving || newPin.length < 4}
          className="w-full py-2.5 rounded-xl bg-primary text-primary-foreground font-bold text-sm disabled:opacity-50"
        >
          {saving ? "Enregistrement…" : hasPin ? "🔒 Changer le PIN" : "🔑 Définir mon PIN"}
        </button>
      </div>
    </div>
  );
}

// =================== REFERRAL ADMIN ===================
function ReferralAdmin() {
  const confirm = useConfirm();
  const [flags, setFlags] = useState<any[]>([]);
  const [cfg, setCfg] = useState<any>(null);
  const [loadingCfg, setLoadingCfg] = useState(true);
  const [saving, setSaving] = useState(false);
  const [flagFilter, setFlagFilter] = useState<"pending"|"cleared"|"confirmed"|"all">("pending");
  const [stats, setStats] = useState<any>(null);

  const loadFlags = async () => {
    const { data } = await (supabase as any).rpc("admin_get_fraud_flags", { _status: flagFilter });
    setFlags(data || []);
  };

  const loadCfg = async () => {
    setLoadingCfg(true);
    const { data } = await supabase.from("referral_settings" as any).select("*").eq("id", 1).maybeSingle();
    setCfg(data || {});
    setLoadingCfg(false);
  };

  const loadStats = async () => {
    const { data } = await supabase.from("v_referral_stats" as any).select("*").order("total_earned_ar", { ascending: false }).limit(10);
    setStats(data || []);
  };

  useEffect(() => { loadFlags(); loadCfg(); loadStats(); }, []);
  useEffect(() => { loadFlags(); }, [flagFilter]);

  const saveCfg = async () => {
    if (!cfg) return;
    setSaving(true);
    const { error } = await (supabase as any).rpc("admin_update_referral_settings", {
      _deposit_bonus_pct: Number(cfg.deposit_bonus_pct),
      _deposit_min_ar: Number(cfg.deposit_min_ar),
      _win_commission_pct: Number(cfg.win_commission_pct),
      _tier_silver_min: Number(cfg.tier_silver_min),
      _tier_gold_min: Number(cfg.tier_gold_min),
      _tier_diamond_min: Number(cfg.tier_diamond_min),
      _tier_silver_mult: Number(cfg.tier_silver_mult),
      _tier_gold_mult: Number(cfg.tier_gold_mult),
      _tier_diamond_mult: Number(cfg.tier_diamond_mult),
      _require_phone: Boolean(cfg.require_phone_verification),
      _max_daily: Number(cfg.max_daily_new_referrals),
      _auto_flag_velocity: Number(cfg.auto_flag_velocity),
      _enabled: Boolean(cfg.enabled),
      _campaign_label: cfg.campaign_label || null,
      _campaign_expires: cfg.campaign_expires_at || null,
      _campaign_bonus_pct: cfg.campaign_bonus_pct ? Number(cfg.campaign_bonus_pct) : null,
    });
    setSaving(false);
    if (error) toast.error(error.message);
    else toast.success("✅ Paramètres parrainage enregistrés");
  };

  const resolveFlag = async (flagId: string, resolution: "cleared"|"confirmed", payAnyway = false) => {
    const ok = await confirm({
      title: resolution === "cleared" ? "Valider ce parrainage ?" : "Confirmer la fraude ?",
      description: resolution === "cleared"
        ? payAnyway ? "Le parrainage sera validé et la récompense créditée." : "Le flag sera effacé sans crédit."
        : "Ce parrainage sera marqué comme frauduleux. Aucune récompense ne sera versée.",
      confirmLabel: resolution === "cleared" ? "Valider" : "Confirmer fraude",
      destructive: resolution === "confirmed",
    });
    if (!ok) return;
    const { error } = await (supabase as any).rpc("admin_resolve_fraud_flag", {
      _flag_id: flagId, _resolution: resolution, _pay_anyway: payAnyway,
    });
    if (error) toast.error(error.message);
    else { toast.success("✅ Flag résolu"); loadFlags(); }
  };

  const Field = ({ label, fieldKey, type = "number", hint }: { label: string; fieldKey: string; type?: string; hint?: string }) => (
    <div>
      <label className="text-xs font-semibold text-muted-foreground">{label}</label>
      {type === "boolean" ? (
        <div className="flex items-center gap-2 mt-1">
          <input type="checkbox" checked={Boolean(cfg?.[fieldKey])} onChange={e => setCfg({ ...cfg, [fieldKey]: e.target.checked })} className="w-4 h-4" />
          <span className="text-sm">{cfg?.[fieldKey] ? "Oui" : "Non"}</span>
        </div>
      ) : (
        <input type={type} value={cfg?.[fieldKey] ?? ""} onChange={e => setCfg({ ...cfg, [fieldKey]: type === "number" ? e.target.value : e.target.value })}
          className="mt-1 w-full px-3 py-2 rounded-xl bg-secondary border border-border text-sm" />
      )}
      {hint && <div className="text-[10px] text-muted-foreground mt-0.5">{hint}</div>}
    </div>
  );

  const REASON_LABELS: Record<string, string> = {
    self_referral: "⚠️ Auto-parrainage",
    velocity_exceeded: "⚡ Vélocité anormale",
    daily_limit_exceeded: "🚫 Limite journalière",
  };

  return (
    <div className="space-y-5">
      {/* Stats overview */}
      {stats && stats.length > 0 && (
        <div className="rounded-2xl bg-card p-4 border border-border shadow-sm space-y-3">
          <div className="font-bold flex items-center gap-2">📊 Top parrains</div>
          <div className="overflow-x-auto">
            <table className="w-full text-xs">
              <thead><tr className="text-muted-foreground border-b border-border">
                <th className="text-left py-1.5 pr-3">Parrain</th>
                <th className="text-right py-1.5 pr-3">Filleuls</th>
                <th className="text-right py-1.5 pr-3">Actifs</th>
                <th className="text-right py-1.5">Gains</th>
              </tr></thead>
              <tbody>
                {stats.map((s: any) => (
                  <tr key={s.referrer_id} className="border-b border-border/40">
                    <td className="py-2 pr-3 font-semibold">{s.referrer_id?.slice(0,8)}…</td>
                    <td className="text-right py-2 pr-3">{s.total_referrals}</td>
                    <td className="text-right py-2 pr-3 text-emerald-600 font-bold">{s.active_referrals}</td>
                    <td className="text-right py-2 text-primary font-bold">{Math.round(Number(s.total_earned_ar)).toLocaleString("fr-FR")} Ar</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      )}

      {/* Configuration */}
      {loadingCfg ? (
        <div className="py-8 text-center text-muted-foreground animate-pulse">Chargement…</div>
      ) : (
        <div className="rounded-2xl bg-card p-4 border border-border shadow-sm space-y-4">
          <div className="font-bold flex items-center gap-2">⚙️ Paramètres du programme</div>

          <div className="flex items-center gap-3 p-3 rounded-xl bg-secondary">
            <Field label="Programme activé" fieldKey="enabled" type="boolean" />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Commission 1er dépôt (%)" fieldKey="deposit_bonus_pct" hint="% du montant du dépôt du filleul" />
            <Field label="Dépôt minimum (Ar)" fieldKey="deposit_min_ar" hint="Montant min pour déclencher la commission" />
            <Field label="Commission victoires (%)" fieldKey="win_commission_pct" hint="% comm. plateforme sur victoires filleul" />
            <Field label="Max filleuls/jour" fieldKey="max_daily_new_referrals" hint="Limite anti-fraude journalière" />
          </div>

          <div className="font-semibold text-sm pt-1">Seuils de niveaux (filleuls actifs)</div>
          <div className="grid grid-cols-3 gap-3">
            <Field label="🥈 Argent (min)" fieldKey="tier_silver_min" />
            <Field label="🥇 Or (min)" fieldKey="tier_gold_min" />
            <Field label="💎 Diamant (min)" fieldKey="tier_diamond_min" />
          </div>

          <div className="font-semibold text-sm">Multiplicateurs de commission</div>
          <div className="grid grid-cols-3 gap-3">
            <Field label="🥈 Argent ×" fieldKey="tier_silver_mult" hint="Ex: 1.25 = +25%" />
            <Field label="🥇 Or ×" fieldKey="tier_gold_mult" hint="Ex: 1.60 = +60%" />
            <Field label="💎 Diamant ×" fieldKey="tier_diamond_mult" hint="Ex: 2.00 = ×2" />
          </div>

          <div className="font-semibold text-sm pt-1">Campagne promotionnelle (optionnel)</div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Label campagne" fieldKey="campaign_label" type="text" hint="Ex: Ramadan bonus 🎁" />
            <Field label="Bonus campagne (%)" fieldKey="campaign_bonus_pct" hint="% supplémentaire pendant la campagne" />
          </div>
          <div>
            <label className="text-xs font-semibold text-muted-foreground">Date d'expiration campagne</label>
            <input type="datetime-local" value={cfg?.campaign_expires_at?.slice(0,16) || ""}
              onChange={e => setCfg({ ...cfg, campaign_expires_at: e.target.value || null })}
              className="mt-1 w-full px-3 py-2 rounded-xl bg-secondary border border-border text-sm" />
          </div>

          <div className="font-semibold text-sm pt-1">Anti-fraude</div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Vélocité max (filleuls/heure)" fieldKey="auto_flag_velocity" hint="Au-delà → flag automatique" />
            <Field label="Vérification téléphone requise" fieldKey="require_phone_verification" type="boolean" />
          </div>

          <button onClick={saveCfg} disabled={saving}
            className="w-full py-3 rounded-full text-white font-bold" style={{ background: "var(--gradient-primary)" }}>
            {saving ? "⏳ Enregistrement…" : "💾 Enregistrer les paramètres"}
          </button>
        </div>
      )}

      {/* Fraud flags */}
      <div className="rounded-2xl bg-card p-4 border border-border shadow-sm space-y-3">
        <div className="flex items-center justify-between gap-2 flex-wrap">
          <div className="font-bold flex items-center gap-2">🚨 Signalements de fraude</div>
          <div className="flex gap-1">
            {(["pending","cleared","confirmed","all"] as const).map(f => (
              <button key={f} onClick={() => setFlagFilter(f)}
                className={`px-3 py-1 rounded-full text-xs font-semibold ${flagFilter === f ? "bg-primary text-primary-foreground" : "bg-secondary text-muted-foreground"}`}>
                {f === "pending" ? "En attente" : f === "cleared" ? "Validés" : f === "confirmed" ? "Fraude" : "Tous"}
              </button>
            ))}
          </div>
        </div>

        {flags.length === 0 ? (
          <div className="py-6 text-center text-sm text-muted-foreground">
            {flagFilter === "pending" ? "✅ Aucun signalement en attente" : "Aucun résultat"}
          </div>
        ) : flags.map((f: any) => (
          <div key={f.id} className="rounded-xl bg-secondary/60 p-3 space-y-2">
            <div className="flex items-start justify-between gap-2">
              <div>
                <div className="font-bold text-sm">{REASON_LABELS[f.reason] || f.reason}</div>
                <div className="text-xs text-muted-foreground">
                  Parrain : <span className="font-semibold">{f.referrer_pseudo}</span>
                  {" · "}Filleul : <span className="font-semibold">{f.referee_pseudo}</span>
                </div>
                <div className="text-[10px] text-muted-foreground">{new Date(f.created_at).toLocaleString("fr-FR")}</div>
              </div>
              <span className={`text-[10px] px-2 py-1 rounded-full font-bold ${
                f.status === "pending" ? "bg-amber-100 text-amber-700" :
                f.status === "cleared" ? "bg-emerald-100 text-emerald-700" :
                "bg-rose-100 text-rose-700"}`}>
                {f.status === "pending" ? "En attente" : f.status === "cleared" ? "Validé" : "Fraude"}
              </span>
            </div>
            {f.details && (
              <div className="text-[10px] font-mono bg-card px-2 py-1 rounded-lg overflow-x-auto">
                {JSON.stringify(f.details)}
              </div>
            )}
            {f.status === "pending" && (
              <div className="flex gap-2 flex-wrap">
                <button onClick={() => resolveFlag(f.id, "cleared", true)}
                  className="flex-1 py-2 rounded-xl bg-emerald-100 text-emerald-700 text-xs font-bold">✅ Valider + créditer</button>
                <button onClick={() => resolveFlag(f.id, "cleared", false)}
                  className="flex-1 py-2 rounded-xl bg-secondary text-xs font-bold">✓ Valider sans paiement</button>
                <button onClick={() => resolveFlag(f.id, "confirmed")}
                  className="flex-1 py-2 rounded-xl bg-rose-100 text-rose-700 text-xs font-bold">🚫 Fraude confirmée</button>
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// =================== FROM ADMIN-EXTRA : JOUEURS ===================

function PhoneRequests() {
  const confirm = useConfirm();
  const [items, setItems] = useState<any[]>([]);
  const load = () => supabase.rpc("admin_list_phone_requests" as any).then(({ data }: any) => setItems(data || []));
  useEffect(() => { load(); }, []);
  const act = async (id: string, approve: boolean) => {
    if (approve && !(await confirm({ title: "Valider la vérification de ce numéro ?", destructive: true }))) return;
    const { error } = await supabase.rpc("admin_verify_phone" as any, { _user_id: id, _approve: approve } as any);
    if (error) return toast.error(error.message);
    toast.success(approve ? "Vérifié" : "Rejeté"); load();
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold">📱 Vérifications téléphone en attente ({items.length})</div>
      {items.length === 0 ? <div className="text-sm text-muted-foreground text-center py-3">Aucune demande</div> :
        items.map(r => (
          <div key={r.id} className="border-t border-border/60 pt-2 flex items-center gap-2 flex-wrap">
            <div className="flex-1 min-w-0">
              <div className="font-semibold text-sm">{r.pseudo}</div>
              <div className="text-xs text-muted-foreground">{r.phone}</div>
              <div className="text-xs">Code attendu : <span className="font-mono font-bold text-base">{r.code}</span></div>
            </div>
            <button onClick={() => act(r.id, true)} className="px-3 py-1.5 rounded-full bg-emerald-500 text-white text-sm font-semibold">Valider</button>
            <button onClick={() => act(r.id, false)} className="px-3 py-1.5 rounded-full bg-destructive text-white text-sm font-semibold">Rejeter</button>
          </div>
        ))}
    </div>
  );
}

function PasswordResetRequestsAdmin() {
  const confirm = useConfirm();
  const [items, setItems] = useState<any[]>([]);
  const [filter, setFilter] = useState<"pending" | "all">("pending");
  const load = async () => {
    let q = (supabase.from("password_reset_requests" as any) as any).select("*").order("created_at", { ascending: false }).limit(100);
    if (filter === "pending") q = q.in("status", ["pending", "sent"]);
    const { data } = await q;
    setItems((data as any[]) || []);
  };
  useEffect(() => { load(); /* eslint-disable-next-line */ }, [filter]);
  const setCode = async (id: string) => {
    const code = prompt("Code à transmettre à l'utilisateur :");
    if (!code) return;
    const { error } = await (supabase.from("password_reset_requests" as any) as any).update({ code, status: "sent" }).eq("id", id);
    if (error) return toast.error(error.message);
    toast.success("Code enregistré"); load();
  };
  const markDone = async (id: string) => {
    await (supabase.from("password_reset_requests" as any) as any).update({ status: "done", resolved_at: new Date().toISOString() }).eq("id", id);
    load();
  };
  const reject = async (id: string) => {
    if (!(await confirm({ title: "Rejeter cette demande ?", destructive: true }))) return;
    await (supabase.from("password_reset_requests" as any) as any).update({ status: "rejected", resolved_at: new Date().toISOString() }).eq("id", id);
    load();
  };
  const waLink = (phone: string, code?: string) => {
    const num = phone.replace(/[^\d]/g, "");
    const txt = encodeURIComponent(`Lalao MADA — votre code de réinitialisation : ${code || "[CODE]"}`);
    return `https://wa.me/${num}?text=${txt}`;
  };
  const mailLink = (email: string, code?: string) =>
    `mailto:${email}?subject=${encodeURIComponent("Réinitialisation Lalao MADA")}&body=${encodeURIComponent(`Bonjour,\n\nVoici votre code de réinitialisation Lalao MADA : ${code || "[CODE]"}\n\nUtilisez-le sur la page « Mot de passe oublié » pour définir un nouveau mot de passe.\n\nL'équipe Lalao MADA`)}`;

  const sendCode = async (r: any) => {
    const type: string = r.contact_type || (r.email ? "email" : "phone");
    const contact: string = r.contact || r.email || r.phone || "";
    if (!contact) return toast.error("Contact manquant sur cette demande");

    if (type === "phone") {
      const normalized = contact.replace(/\s/g, "");
      if (!/^\+261\d{7,}$/.test(normalized)) {
        toast.error("Numéro invalide : il doit commencer par +261 (ex : +261340000000)");
        return;
      }
    }

    let code = r.code as string | null;
    if (!code) {
      code = String(Math.floor(100000 + Math.random() * 900000));
      const { error } = await (supabase.from("password_reset_requests" as any) as any)
        .update({ code, status: "sent" }).eq("id", r.id);
      if (error) return toast.error(error.message);
    } else if (r.status !== "sent") {
      await (supabase.from("password_reset_requests" as any) as any)
        .update({ status: "sent" }).eq("id", r.id);
    }

    const url = type === "phone" ? waLink(contact, code) : mailLink(contact, code);
    window.open(url, "_blank", "noopener,noreferrer");
    toast.success(type === "phone" ? "WhatsApp ouvert avec le code" : "E-mail ouvert avec le code");
    load();
  };

  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="flex items-center justify-between">
        <div className="font-bold">🔑 Demandes « Mot de passe oublié » ({items.length})</div>
        <button onClick={() => setFilter(filter === "pending" ? "all" : "pending")}
          className="text-xs px-3 py-1.5 rounded-full bg-secondary hover:bg-accent font-semibold">
          {filter === "pending" ? "Voir tout" : "En attente seulement"}
        </button>
      </div>
      {items.length === 0 ? <div className="text-sm text-muted-foreground text-center py-3">Aucune demande</div> :
        items.map(r => {
          const type: string = r.contact_type || (r.email ? "email" : r.phone ? "phone" : "");
          return (
          <div key={r.id} className="border-t border-border/60 pt-2 space-y-2">
            <div className="flex items-start justify-between gap-2 flex-wrap">
              <div className="min-w-0">
                <div className="font-semibold text-sm">{r.pseudo || r.contact}</div>
                <div className="text-xs text-muted-foreground break-all">{r.contact || r.email || r.phone}</div>
                <div className={`text-[10px] mt-0.5 font-semibold ${r.status === "pending" ? "text-amber-600" : r.status === "sent" ? "text-blue-600" : r.status === "done" ? "text-emerald-600" : "text-destructive"}`}>
                  {r.status === "pending" ? "⏳ En attente" : r.status === "sent" ? "📨 Code envoyé" : r.status === "done" ? "✅ Terminé" : "❌ Rejeté"}
                  {r.code && <span className="ml-2 font-mono text-foreground">Code: {r.code}</span>}
                </div>
              </div>
              <div className="text-[10px] text-muted-foreground shrink-0">{new Date(r.created_at).toLocaleString("fr-FR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" })}</div>
            </div>
            {(r.status === "pending" || r.status === "sent") && (
              <div className="flex gap-1 flex-wrap">
                <button onClick={() => sendCode(r)} className="px-3 py-1 rounded-full bg-primary text-primary-foreground text-xs font-semibold">
                  {type === "phone" ? "📱 Envoyer via WhatsApp" : "📧 Envoyer par e-mail"}
                </button>
                <button onClick={() => setCode(r.id)} className="px-2 py-1 rounded-full bg-secondary text-xs font-semibold">Saisir code</button>
                <button onClick={() => markDone(r.id)} className="px-2 py-1 rounded-full bg-emerald-500 text-white text-xs font-semibold">Terminé</button>
                <button onClick={() => reject(r.id)} className="px-2 py-1 rounded-full bg-destructive text-white text-xs font-semibold">Rejeter</button>
              </div>
            )}
          </div>
          );
        })}
    </div>
  );
}

function ChatMutesAdmin() {
  const [code, setCode] = useState("");
  const [minutes, setMinutes] = useState("60");
  const action = async (ban: boolean) => {
    const { data: p } = await supabase.from("profiles").select("id").eq("unique_code", code.trim().toUpperCase()).maybeSingle();
    if (!p) return toast.error("Utilisateur introuvable");
    const { error } = await supabase.rpc("admin_chat_mute" as any, { _user_id: p.id, _minutes: Number(minutes) || 0, _ban: ban, _reason: null } as any);
    if (error) return toast.error(error.message);
    toast.success(ban ? "Banni du chat" : "Muté");
  };
  const unmute = async () => {
    const { data: p } = await supabase.from("profiles").select("id").eq("unique_code", code.trim().toUpperCase()).maybeSingle();
    if (!p) return toast.error("Utilisateur introuvable");
    await supabase.rpc("admin_chat_unmute" as any, { _user_id: p.id } as any);
    toast.success("Débanni du chat");
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold">🛡 Modération chat</div>
      <input value={code} onChange={e => setCode(e.target.value.toUpperCase())} placeholder="ID utilisateur"
        className="w-full px-3 py-2 rounded-full bg-secondary outline-none font-mono text-sm" />
      <input value={minutes} onChange={e => setMinutes(e.target.value)} type="number" placeholder="Durée mute (min, 0 = illimité)"
        className="w-full px-3 py-2 rounded-full bg-secondary outline-none text-sm" />
      <div className="flex gap-2">
        <button onClick={() => action(false)} className="flex-1 py-2 rounded-full bg-amber-500 text-white text-sm font-semibold">Muter</button>
        <button onClick={() => action(true)} className="flex-1 py-2 rounded-full bg-destructive text-white text-sm font-semibold">Bannir</button>
        <button onClick={unmute} className="flex-1 py-2 rounded-full bg-emerald-500 text-white text-sm font-semibold">Débannir</button>
      </div>
    </div>
  );
}

// =================== FROM ADMIN-EXTRA : PARTIES ===================

function GamesAdmin() {
  const confirm = useConfirm();
  const [games, setGames] = useState<any[]>([]);
  const load = () => supabase.rpc("admin_list_games" as any).then(({ data }: any) => setGames(data || []));
  useEffect(() => {
    load();
    const ch = supabase.channel("admin-games-extra")
      .on("postgres_changes", { event: "*", schema: "public", table: "ludo_games" }, load)
      .subscribe();
    return () => { supabase.removeChannel(ch); };
  }, []);
  const del = async (id: string) => {
    if (!(await confirm({ title: "Supprimer cette partie et rembourser ?", destructive: true }))) return;
    const { error } = await supabase.rpc("admin_delete_game" as any, { _game_id: id } as any);
    if (error) return toast.error(error.message); toast.success("Supprimée + remboursée"); load();
  };
  const forceFinish = async (id: string, players: any[]) => {
    const winnerName = prompt(`Désigner un gagnant (pseudo) ou laisser vide pour rembourser tous :\n${players.filter((p:any)=>!p.is_bot).map((p:any)=>`- ${p.name}`).join("\n")}`);
    let winnerId: string | null = null;
    if (winnerName?.trim()) {
      const p = players.find((p: any) => p.name?.toLowerCase() === winnerName.trim().toLowerCase());
      if (!p) return toast.error("Joueur introuvable");
      winnerId = p.user_id;
    }
    if (!(await confirm({ title: winnerId ? "Confirmer victoire ?" : "Confirmer annulation + remboursement ?", destructive: true }))) return;
    const { error } = await supabase.rpc("admin_force_finish_game" as any, { _game_id: id, _winner_id: winnerId } as any);
    if (error) return toast.error(error.message); toast.success("OK"); load();
  };
  const refund = async (id: string) => {
    if (!(await confirm({ title: "Rembourser tous les joueurs de cette partie ?", destructive: true }))) return;
    const { error } = await supabase.rpc("refund_game" as any, { _game_id: id } as any);
    if (error) return toast.error(error.message); toast.success("Remboursé"); load();
  };
  const cleanup = async () => {
    const { data, error } = await supabase.rpc("cleanup_stale_open_games" as any);
    if (error) return toast.error(error.message); toast.success(`${data || 0} parties expirées supprimées`); load();
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="flex items-center justify-between">
        <div className="font-bold">🎮 Parties en cours / ouvertes ({games.length})</div>
        <button onClick={cleanup} className="text-xs px-3 py-1.5 rounded-full bg-secondary">Nettoyer expirées</button>
      </div>
      {games.length === 0 && <div className="text-sm text-muted-foreground text-center py-3">Aucune partie active</div>}
      {games.map(g => (
        <div key={g.id} className="border-t border-border/60 pt-2 space-y-1">
          <div className="text-sm flex items-center justify-between flex-wrap gap-2">
            <div>
              <span className={`text-[10px] px-2 py-0.5 rounded-full font-bold ${g.status === "open" ? "bg-amber-100 text-amber-700" : "bg-emerald-100 text-emerald-700"}`}>{g.status}</span>
              {g.is_private && <span className="ml-1 text-[10px] px-2 py-0.5 rounded-full bg-purple-100 text-purple-700 font-bold">privée</span>}
              <span className="ml-2 font-semibold">Mise {Number(g.stake).toLocaleString("fr-FR")} Ar</span>
              <span className="ml-2 text-xs text-muted-foreground">Pot {Number(g.pot).toLocaleString("fr-FR")}</span>
            </div>
            <div className="flex gap-1">
              <button onClick={() => forceFinish(g.id, g.players || [])} className="px-2 py-1 rounded-full bg-amber-500 text-white text-xs font-semibold">Forcer fin</button>
              <button onClick={() => refund(g.id)} className="px-2 py-1 rounded-full bg-blue-500 text-white text-xs font-semibold">Rembourser</button>
              <button onClick={() => del(g.id)} className="px-2 py-1 rounded-full bg-destructive text-white text-xs font-semibold"><Trash2 className="w-3 h-3" /></button>
            </div>
          </div>
          <div className="text-xs text-muted-foreground">
            {(g.players || []).map((p: any) => `${p.name}${p.is_bot ? "[IA]" : ""}${p.forfeited ? "✕" : ""}`).join(" · ")}
          </div>
        </div>
      ))}
    </div>
  );
}

// =================== FROM ADMIN-EXTRA : TOURNOIS ===================

function SeasonsAdmin() {
  const confirm = useConfirm();
  const [items, setItems] = useState<any[]>([]);
  const [f, setF] = useState({ name: "", starts_at: "", ends_at: "", reward_text: "", reward_amount: "0" });
  const load = () => (supabase.from("seasons" as any) as any).select("*").order("starts_at", { ascending: false }).then(({ data }: any) => setItems(data || []));
  useEffect(() => { load(); }, []);
  const create = async () => {
    if (!f.name.trim() || !f.starts_at || !f.ends_at) return toast.error("Nom, dates requis");
    const { error } = await supabase.rpc("admin_season_upsert" as any, {
      _id: null, _name: f.name, _starts_at: new Date(f.starts_at).toISOString(), _ends_at: new Date(f.ends_at).toISOString(),
      _reward_text: f.reward_text || null, _reward_amount: Number(f.reward_amount) || 0,
    } as any);
    if (error) return toast.error(error.message);
    toast.success("Saison créée"); setF({ name: "", starts_at: "", ends_at: "", reward_text: "", reward_amount: "0" }); load();
  };
  const close = async (id: string) => {
    if (!(await confirm({ title: "Clôturer la saison et désigner le Ballon d'Or ?", destructive: true }))) return;
    const { error } = await supabase.rpc("admin_season_close" as any, { _id: id } as any);
    if (error) return toast.error(error.message);
    toast.success("Ballon d'Or attribué 👑"); load();
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold">👑 Saisons (Ballon d'Or Lalao MADA)</div>
      <div className="rounded-2xl bg-secondary p-3 space-y-2">
        <input value={f.name} onChange={e => setF({ ...f, name: e.target.value })} placeholder="Nom (ex: Saison 1 2026)" className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <div className="grid grid-cols-2 gap-2">
          <label className="text-xs">Début<input type="datetime-local" value={f.starts_at} onChange={e => setF({ ...f, starts_at: e.target.value })} className="w-full mt-1 px-2 py-2 rounded-xl bg-card text-sm" /></label>
          <label className="text-xs">Fin<input type="datetime-local" value={f.ends_at} onChange={e => setF({ ...f, ends_at: e.target.value })} className="w-full mt-1 px-2 py-2 rounded-xl bg-card text-sm" /></label>
        </div>
        <input value={f.reward_text} onChange={e => setF({ ...f, reward_text: e.target.value })} placeholder="Description récompense" className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <input type="number" value={f.reward_amount} onChange={e => setF({ ...f, reward_amount: e.target.value })} placeholder="Récompense Ar" className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <button onClick={create} className="w-full py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1"><Plus className="w-4 h-4" /> Ouvrir saison</button>
      </div>
      {items.map(s => (
        <div key={s.id} className="border-t border-border/60 pt-2 flex items-center gap-2 flex-wrap">
          <div className="flex-1 min-w-0">
            <div className="text-sm font-semibold">{s.name}</div>
            <div className="text-xs text-muted-foreground">{new Date(s.starts_at).toLocaleDateString("fr-FR")} → {new Date(s.ends_at).toLocaleDateString("fr-FR")} · {s.closed ? "Clôturée 👑" : "En cours"}{s.reward_amount > 0 ? ` · 🎁 ${Number(s.reward_amount).toLocaleString("fr-FR")} Ar` : ""}</div>
          </div>
          {!s.closed && <button onClick={() => close(s.id)} className="px-3 py-1.5 rounded-full bg-amber-500 text-white text-xs font-semibold">Clôturer</button>}
        </div>
      ))}
    </div>
  );
}

// =================== CLASSEMENT (Top gagnants — accueil) ===================
function LeaderboardAdmin() {
  const confirm = useConfirm();
  const [period, setPeriod] = useState<"week" | "month" | "all">("all");
  const [slug, setSlug] = useState<string>("all");
  const [items, setItems] = useState<any[]>([]);
  const [loading, setLoading] = useState(false);

  const load = async () => {
    setLoading(true);
    const { data, error } = await supabase.rpc("admin_leaderboard_list" as any, {
      _period: period, _limit: 100, _slug: slug === "all" ? null : slug,
    } as any);
    if (error) toast.error(error.message);
    setItems((data as any[]) || []);
    setLoading(false);
  };
  useEffect(() => { load(); }, [period, slug]);

  const toggleHidden = async (u: any) => {
    if (!u.hidden && !(await confirm({ title: `Retirer ${u.name} du classement ?`, description: "Ce joueur n'apparaîtra plus dans le Top gagnants de l'accueil, quel que soit le jeu ou la période.", destructive: true }))) return;
    const { error } = await supabase.rpc("admin_set_leaderboard_hidden" as any, { _user_id: u.user_id, _hidden: !u.hidden } as any);
    if (error) return toast.error(error.message);
    toast.success(u.hidden ? "Joueur réaffiché dans le classement" : "Joueur retiré du classement");
    load();
  };

  // Déplacer un joueur : fixe un rang manuel (leaderboard_rank_override) pour
  // lui et son voisin, en réutilisant les rangs existants ou en initialisant
  // une séquence 1..N sur la vue actuelle si aucun override n'existe encore.
  const move = async (idx: number, dir: -1 | 1) => {
    const j = idx + dir;
    if (j < 0 || j >= items.length) return;
    const a = items[idx], b = items[j];
    const rankFor = (it: any, pos: number) => it.rank_override ?? pos + 1;
    const rankA = rankFor(a, idx), rankB = rankFor(b, j);
    const [{ error: e1 }, { error: e2 }] = await Promise.all([
      supabase.rpc("admin_set_leaderboard_rank" as any, { _user_id: a.user_id, _rank_override: rankB } as any),
      supabase.rpc("admin_set_leaderboard_rank" as any, { _user_id: b.user_id, _rank_override: rankA } as any),
    ]);
    if (e1 || e2) return toast.error((e1 || e2)!.message);
    load();
  };

  const clearRank = async (u: any) => {
    const { error } = await supabase.rpc("admin_set_leaderboard_rank" as any, { _user_id: u.user_id, _rank_override: null } as any);
    if (error) return toast.error(error.message);
    toast.success("Ordre manuel retiré, tri par victoires rétabli"); load();
  };

  const slugs = [
    { id: "all", label: "Tous" }, { id: "ludo", label: "Ludo" }, { id: "domino", label: "Domino" },
    { id: "chess", label: "Échecs" }, { id: "fanorona", label: "Fanorona" }, { id: "rami", label: "Rami" }, { id: "poker", label: "Poker" },
  ];

  return (
    <Card>
      <div className="font-bold flex items-center gap-2"><Trophy className="w-4 h-4 text-amber-500" /> Classement — Top gagnants (accueil)</div>
      <p className="text-xs text-muted-foreground">Le classement est calculé automatiquement par nombre de victoires. Vous pouvez retirer un joueur ou fixer un ordre manuel qui sera prioritaire sur le tri automatique.</p>

      <div className="flex gap-1.5 bg-secondary/60 p-1 rounded-2xl">
        {(["week", "month", "all"] as const).map(p => (
          <button key={p} onClick={() => setPeriod(p)}
            className={`flex-1 py-1.5 rounded-xl text-xs font-bold transition-all ${period === p ? "bg-primary text-primary-foreground shadow" : "text-muted-foreground hover:text-foreground"}`}>
            {p === "week" ? "Semaine" : p === "month" ? "Mois" : "Tout le temps"}
          </button>
        ))}
      </div>
      <div className="flex gap-1.5 overflow-x-auto pb-1 -mx-1 px-1 scrollbar-hide">
        {slugs.map(s => (
          <button key={s.id} onClick={() => setSlug(s.id)}
            className={`flex-shrink-0 px-2.5 py-1 rounded-full text-[11px] font-bold border whitespace-nowrap transition-all ${slug === s.id ? "bg-primary text-primary-foreground border-primary" : "bg-secondary/60 border-border text-muted-foreground hover:text-foreground"}`}>
            {s.label}
          </button>
        ))}
      </div>

      {loading ? (
        <div className="text-center text-muted-foreground py-6 text-sm">Chargement…</div>
      ) : items.length === 0 ? (
        <div className="text-center text-muted-foreground py-6 text-sm">Aucun joueur pour cette sélection.</div>
      ) : (
        <div className="space-y-1.5">
          {items.map((u, i) => (
            <div key={u.user_id} className={`flex items-center gap-2 rounded-xl px-2.5 py-2 border ${u.hidden ? "bg-destructive/5 border-destructive/20 opacity-60" : "border-border/60"}`}>
              <div className="w-6 text-center text-xs font-bold text-muted-foreground">{i + 1}</div>
              <div className="w-8 h-8 rounded-full bg-accent overflow-hidden grid place-items-center font-bold text-xs flex-shrink-0">
                {u.avatar_url ? <img src={u.avatar_url} alt="" className="w-full h-full object-cover" /> : (u.name || "?").slice(0, 2).toUpperCase()}
              </div>
              <div className="flex-1 min-w-0">
                <div className="font-semibold text-sm truncate flex items-center gap-1.5">
                  {u.name}
                  {u.hidden && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-destructive text-white">retiré</span>}
                  {u.rank_override != null && <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-primary/15 text-primary">ordre manuel</span>}
                </div>
                <div className="text-xs text-muted-foreground">{u.wins} victoire{Number(u.wins) !== 1 ? "s" : ""}</div>
              </div>
              <div className="flex items-center gap-1 flex-shrink-0">
                <button onClick={() => move(i, -1)} disabled={i === 0} title="Monter" className="p-1.5 rounded-lg bg-secondary disabled:opacity-30"><ArrowUp className="w-3.5 h-3.5" /></button>
                <button onClick={() => move(i, 1)} disabled={i === items.length - 1} title="Descendre" className="p-1.5 rounded-lg bg-secondary disabled:opacity-30"><ArrowDown className="w-3.5 h-3.5" /></button>
                {u.rank_override != null && (
                  <button onClick={() => clearRank(u)} title="Retirer l'ordre manuel" className="p-1.5 rounded-lg bg-secondary"><RotateCcw className="w-3.5 h-3.5" /></button>
                )}
                <button onClick={() => toggleHidden(u)} title={u.hidden ? "Réafficher" : "Retirer du classement"}
                  className={`p-1.5 rounded-lg ${u.hidden ? "bg-emerald-500 text-white" : "bg-destructive text-white"}`}>
                  {u.hidden ? <Eye className="w-3.5 h-3.5" /> : <EyeOff className="w-3.5 h-3.5" />}
                </button>
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}

// =================== FROM ADMIN-EXTRA : CONTENU ===================

function AnnouncementsAdmin() {
  const confirm = useConfirm();
  const [items, setItems] = useState<any[]>([]);
  const [f, setF] = useState({ title: "", body: "", image_url: "", link: "", link_label: "" });
  const load = () => (supabase.from("announcements" as any) as any).select("*").order("created_at", { ascending: false }).then(({ data }: any) => setItems(data || []));
  useEffect(() => { load(); }, []);
  const create = async () => {
    if (!f.title.trim()) return toast.error("Titre requis");
    const { error } = await supabase.rpc("admin_announcement_create" as any, { _title: f.title, _body: f.body || null, _image_url: f.image_url || null, _link: f.link || null, _link_label: f.link_label || null } as any);
    if (error) return toast.error(error.message);
    toast.success("Annonce publiée"); setF({ title: "", body: "", image_url: "", link: "", link_label: "" }); load();
  };
  const toggle = async (id: string, active: boolean) => {
    await supabase.rpc("admin_announcement_toggle" as any, { _id: id, _active: active } as any); load();
  };
  const del = async (id: string) => {
    if (!(await confirm({ title: "Supprimer cette annonce ?", destructive: true }))) return;
    await supabase.rpc("admin_announcement_delete" as any, { _id: id } as any); load();
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold">📢 Annonces (popup plein écran)</div>
      <div className="rounded-2xl bg-secondary p-3 space-y-2">
        <input value={f.title} onChange={e => setF({ ...f, title: e.target.value })} placeholder="Titre" className="w-full px-3 py-2 rounded-xl bg-card outline-none text-sm" />
        <textarea value={f.body} onChange={e => setF({ ...f, body: e.target.value })} placeholder="Description" rows={2} className="w-full px-3 py-2 rounded-xl bg-card outline-none text-sm" />
        <input value={f.image_url} onChange={e => setF({ ...f, image_url: e.target.value })} placeholder="URL image (optionnel)" className="w-full px-3 py-2 rounded-xl bg-card outline-none text-sm" />
        <div className="grid grid-cols-2 gap-2">
          <input value={f.link} onChange={e => setF({ ...f, link: e.target.value })} placeholder="Lien (optionnel)" className="px-3 py-2 rounded-xl bg-card outline-none text-sm" />
          <input value={f.link_label} onChange={e => setF({ ...f, link_label: e.target.value })} placeholder="Libellé bouton" className="px-3 py-2 rounded-xl bg-card outline-none text-sm" />
        </div>
        <button onClick={create} className="w-full py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1"><Plus className="w-4 h-4" /> Publier</button>
      </div>
      {items.map(a => (
        <div key={a.id} className="border-t border-border/60 pt-2 flex items-center gap-2">
          {a.image_url && <img src={a.image_url} alt="" width={48} height={48} loading="lazy" decoding="async" className="w-12 h-12 rounded-lg object-cover" />}
          <div className="flex-1 min-w-0">
            <div className="text-sm font-semibold truncate">{a.title}</div>
            <div className="text-xs text-muted-foreground truncate">{a.body}</div>
          </div>
          <label className="text-xs flex items-center gap-1"><input type="checkbox" checked={a.active} onChange={e => toggle(a.id, e.target.checked)} /> Actif</label>
          <button onClick={() => del(a.id)} className="p-1.5 text-destructive"><Trash2 className="w-4 h-4" /></button>
        </div>
      ))}
    </div>
  );
}

function OffersAdmin() {
  const confirm = useConfirm();
  const [items, setItems] = useState<any[]>([]);
  const [f, setF] = useState({ title: "", description: "", image_url: "", link: "", expires_at: "" });
  const load = () => (supabase.from("money_offers" as any) as any).select("*").order("created_at", { ascending: false }).then(({ data }: any) => setItems(data || []));
  useEffect(() => { load(); }, []);
  const save = async () => {
    if (!f.title.trim()) return toast.error("Titre requis");
    const { error } = await supabase.rpc("admin_offer_upsert" as any, {
      _id: null, _title: f.title, _description: f.description || null, _image_url: f.image_url || null,
      _link: f.link || null, _expires_at: f.expires_at ? new Date(f.expires_at).toISOString() : null, _active: true,
    } as any);
    if (error) return toast.error(error.message);
    toast.success("Offre créée"); setF({ title: "", description: "", image_url: "", link: "", expires_at: "" }); load();
  };
  const del = async (id: string) => {
    if (!(await confirm({ title: "Supprimer cette offre ?", destructive: true }))) return;
    await supabase.rpc("admin_offer_delete" as any, { _id: id } as any); load();
  };
  const toggle = async (o: any, active: boolean) => {
    await supabase.rpc("admin_offer_upsert" as any, {
      _id: o.id, _title: o.title, _description: o.description, _image_url: o.image_url,
      _link: o.link, _expires_at: o.expires_at, _active: active,
    } as any); load();
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold">💰 Offres gratuites</div>
      <div className="rounded-2xl bg-secondary p-3 space-y-2">
        <input value={f.title} onChange={e => setF({ ...f, title: e.target.value })} placeholder="Titre" className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <textarea value={f.description} onChange={e => setF({ ...f, description: e.target.value })} placeholder="Description" rows={2} className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <div className="grid grid-cols-2 gap-2">
          <input value={f.image_url} onChange={e => setF({ ...f, image_url: e.target.value })} placeholder="URL image" className="px-3 py-2 rounded-xl bg-card text-sm outline-none" />
          <input value={f.link} onChange={e => setF({ ...f, link: e.target.value })} placeholder="Lien" className="px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        </div>
        <input type="datetime-local" value={f.expires_at} onChange={e => setF({ ...f, expires_at: e.target.value })} className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <button onClick={save} className="w-full py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1"><Plus className="w-4 h-4" /> Créer offre</button>
      </div>
      {items.map(o => (
        <div key={o.id} className="border-t border-border/60 pt-2 flex items-center gap-2">
          <div className="flex-1 min-w-0">
            <div className="font-semibold text-sm truncate">{o.title}</div>
            <div className="text-xs text-muted-foreground truncate">{o.description}</div>
            {o.expires_at && <div className="text-[10px] text-amber-600">Expire: {new Date(o.expires_at).toLocaleString("fr-FR")}</div>}
          </div>
          <label className="text-xs flex items-center gap-1"><input type="checkbox" checked={o.active} onChange={e => toggle(o, e.target.checked)} /> Actif</label>
          <button onClick={() => del(o.id)} className="p-1.5 text-destructive"><Trash2 className="w-4 h-4" /></button>
        </div>
      ))}
    </div>
  );
}

function TutorialsAdmin() {
  const [tutos, setTutos] = useState<any[]>([]);
  const load = () => supabase.from("app_settings").select("tutorials").eq("id",1).maybeSingle().then(({ data }) => setTutos((data?.tutorials as any[]) || []));
  useEffect(() => { load(); }, []);
  const saveAll = async (next: any[]) => {
    const { error } = await supabase.from("app_settings").update({ tutorials: next }).eq("id", 1);
    if (error) return toast.error(error.message);
    setTutos(next);
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold">📚 Tutoriels</div>
      {tutos.map((t, i) => (
        <div key={i} className="space-y-1 border-t border-border/60 pt-2">
          <div className="flex gap-2">
            <input value={t.title || ""} onChange={e => { const n = [...tutos]; n[i] = { ...t, title: e.target.value }; setTutos(n); }}
              onBlur={() => saveAll(tutos)} placeholder={`Titre tuto ${i+1}`}
              className="flex-1 px-2 py-1.5 rounded bg-secondary outline-none text-sm font-semibold" />
            <button onClick={() => saveAll(tutos.filter((_,k) => k !== i))} className="p-1.5 text-destructive"><Trash2 className="w-4 h-4" /></button>
          </div>
          <textarea value={t.content || ""} onChange={e => { const n = [...tutos]; n[i] = { ...t, content: e.target.value }; setTutos(n); }}
            onBlur={() => saveAll(tutos)} rows={3} placeholder="Contenu (les liens https:// sont cliquables)"
            className="w-full px-2 py-1.5 rounded bg-secondary outline-none text-sm" />
        </div>
      ))}
      <button onClick={() => saveAll([...tutos, { title: "", content: "" }])} className="px-3 py-1.5 rounded-full bg-primary text-primary-foreground text-sm flex items-center gap-1"><Plus className="w-4 h-4" /> Ajouter</button>
    </div>
  );
}

// =================== CONTENT TEXTS ===================
function ContentTextsEditor() {
  const confirm = useConfirm();
  const [s, setS] = useState<any>(null);
  const [loaded, setLoaded] = useState(false);
  useEffect(() => {
    supabase.from("app_settings").select("*").eq("id", 1).maybeSingle().then(({ data }) => {
      setS(data || {}); setLoaded(true);
    });
  }, []);
  const saveTexts = async () => {
    const { error } = await (supabase.from("app_settings").update({
      deposit_help_html: s.deposit_help_html || "",
      withdrawal_help_html: s.withdrawal_help_html || "",
      signup_help_html: s.signup_help_html || "",
      password_reset_help_html: s.password_reset_help_html || "",
      terms_text: s.terms_text || "",
      terms_html: s.terms_html || "",
      privacy_html: s.privacy_html || "",
    } as any) as any).eq("id", 1);
    if (error) return toast.error(error.message);
    toast.success("✅ Textes enregistrés");
  };
  const reshowTerms = async () => {
    const ok = await confirm({
      title: "Réafficher les CGU à tous les utilisateurs ?",
      description: "Tous les utilisateurs devront accepter à nouveau les conditions à leur prochaine ouverture.",
      confirmLabel: "Réafficher",
    });
    if (!ok) return;
    const { data, error } = await supabase.rpc("admin_reset_all_terms" as any);
    if (error) return toast.error(error.message);
    toast.success(`CGU réinitialisées pour ${data ?? 0} utilisateur(s)`);
  };
  const clearTerms = async () => {
    if (!(await confirm({ title: "Supprimer les CGU ?", destructive: true }))) return;
    setS({ ...s, terms_text: "" });
    await (supabase.from("app_settings").update({ terms_text: "" } as any) as any).eq("id", 1);
    toast.success("CGU supprimées");
  };
  const TextArea = ({ k, label, hint, rows = 5 }: any) => (
    <div>
      <div className="text-sm font-semibold mb-1">{label}</div>
      {hint && <div className="text-xs text-muted-foreground mb-1">{hint}</div>}
      <textarea value={s[k] || ""} onChange={e => setS({ ...s, [k]: e.target.value })} rows={rows}
        className="w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm font-mono" />
    </div>
  );
  const RichText = ({ k, label, placeholder }: any) => (
    <div className="block mb-3">
      <div className="text-sm font-semibold mb-2">{label}</div>
      <RichTextEditor
        value={s[k] || ""}
        onChange={html => setS({ ...s, [k]: html })}
        placeholder={placeholder}
        minHeight="200px"
      />
    </div>
  );
  if (!loaded) return null;
  return (
    <div className="space-y-4">
      {/* Help texts */}
      <Card>
        <div className="font-bold text-sm mb-2">💬 Textes d'aide</div>
        <div className="text-xs text-muted-foreground mb-3">HTML autorisé. Affichés aux joueurs via les liens d'aide.</div>
        <TextArea k="deposit_help_html" label="Aide dépôt" hint="Comment faire un dépôt" />
        <TextArea k="withdrawal_help_html" label="Aide retrait" hint="Comment faire un retrait" />
        <TextArea k="signup_help_html" label="Aide inscription" hint="Comment s'inscrire" />
        <TextArea k="password_reset_help_html" label="Aide mot de passe oublié" hint="Comment réinitialiser" />
      </Card>
      {/* Legal texts */}
      <Card>
        <div className="font-bold text-sm mb-2">📜 Mentions légales & CGU</div>
        <div className="text-xs text-muted-foreground mb-3">Affichés aux visiteurs et nouveaux inscrits.</div>
        <RichText k="terms_html" label="Conditions d'utilisation" placeholder="Rédigez les conditions d'utilisation…" />
        <RichText k="privacy_html" label="Politique de confidentialité" placeholder="Rédigez la politique de confidentialité…" />
        <div className="border-t border-border/40 pt-3">
          <div className="text-sm font-semibold mb-1">📜 CGU (popup après inscription)</div>
          <div className="text-xs text-muted-foreground mb-2">Si vide, aucune modale n'apparaît.</div>
          <textarea value={s.terms_text || ""} onChange={e => setS({ ...s, terms_text: e.target.value })} rows={6}
            className="w-full px-3 py-2 rounded-xl bg-secondary outline-none text-sm" placeholder="Texte des CGU…" />
          <div className="flex gap-2 flex-wrap mt-2">
            <button onClick={reshowTerms} className="py-2 px-3 rounded-full bg-amber-500 text-white font-semibold text-sm">🔔 Réafficher à tous</button>
            <button onClick={clearTerms} className="px-3 py-2 rounded-full bg-destructive text-destructive-foreground text-sm"><Trash2 className="w-4 h-4" /></button>
          </div>
        </div>
      </Card>
      <button onClick={saveTexts} className="w-full py-3 rounded-full text-white font-bold" style={{ background: "var(--gradient-primary)" }}>
        💾 Enregistrer tous les textes
      </button>
    </div>
  );
}

function Communities() {
  const confirm = useConfirm();
  const [rooms, setRooms] = useState<any[]>([]);
  const [name, setName] = useState("");
  const fileRef = useRef<HTMLInputElement>(null);
  const load = () => supabase.from("chat_rooms").select("*").eq("type","global").order("created_at").then(({ data }) => setRooms(data || []));
  useEffect(() => { load(); }, []);
  const create = async () => {
    if (!name.trim()) return;
    const { error } = await supabase.rpc("admin_create_community" as any, { _name: name.trim(), _image_url: null } as any);
    if (error) return toast.error(error.message);
    setName(""); toast.success("Communauté créée"); load();
  };
  const update = async (r: any, patch: any) => {
    const { error } = await supabase.rpc("admin_update_community" as any, { _room_id: r.id, _name: patch.name ?? r.name, _image_url: patch.image_url ?? r.image_url, _enabled: patch.enabled ?? r.enabled } as any);
    if (error) return toast.error(error.message);
    load();
  };
  const del = async (r: any) => {
    if (!(await confirm({ title: "Supprimer ?", destructive: true }))) return;
    await supabase.rpc("admin_delete_community" as any, { _room_id: r.id } as any); load();
  };
  const upload = async (r: any, rawFile: File) => {
    const f = await compressImageToWebp(rawFile, { maxDim: 800, maxSizeKB: 200 });
    const path = `community/${r.id}.${f.name.split(".").pop()}`;
    const { error } = await supabase.storage.from("chat").upload(path, f, { upsert: true, contentType: f.type });
    if (error) return toast.error(error.message);
    const { data: { publicUrl } } = supabase.storage.from("chat").getPublicUrl(path);
    update(r, { image_url: `${publicUrl}?t=${Date.now()}` });
  };
  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold flex items-center gap-2"><MessageSquare className="w-4 h-4" /> Communautés (chat global)</div>
      <div className="flex gap-2">
        <input value={name} onChange={e => setName(e.target.value)} placeholder="Nom de la communauté"
          className="flex-1 px-3 py-2 rounded-full bg-secondary outline-none text-sm" />
        <button onClick={create} className="px-3 py-2 rounded-full bg-primary text-primary-foreground text-sm font-semibold flex items-center gap-1"><Plus className="w-4 h-4" />Créer</button>
      </div>
      <div className="space-y-2">
        {rooms.map(r => (
          <div key={r.id} className="flex items-center gap-3 border-t border-border/60 pt-2">
            <button onClick={() => { fileRef.current!.dataset.id = r.id; fileRef.current?.click(); }} className="w-12 h-12 rounded-2xl bg-accent overflow-hidden flex items-center justify-center">
              {r.image_url ? <img src={r.image_url} loading="lazy" decoding="async" className="w-full h-full object-cover" /> : <Camera className="w-5 h-5" />}
            </button>
            <input defaultValue={r.name} onBlur={e => e.target.value !== r.name && update(r, { name: e.target.value })}
              className="flex-1 px-2 py-1.5 rounded bg-secondary outline-none text-sm" />
            <label className="text-xs flex items-center gap-1">
              <input type="checkbox" checked={r.enabled} onChange={e => update(r, { enabled: e.target.checked })} />
              Actif
            </label>
            <button onClick={() => del(r)} className="p-1.5 rounded-full text-destructive hover:bg-accent"><Trash2 className="w-4 h-4" /></button>
          </div>
        ))}
      </div>
      <input ref={fileRef} type="file" accept="image/*" hidden
        onChange={e => { const f = e.target.files?.[0]; const id = fileRef.current?.dataset.id; const r = rooms.find(x => x.id === id); if (f && r) upload(r, f); }} />
    </div>
  );
}

function AppConfigForm() {
  const [s, setS] = useState<any>(null);
  const fe = useFormErrors();
  const load = () => supabase.from("app_settings").select("*").eq("id", 1).maybeSingle().then(({ data }) => setS(data));
  useEffect(() => { load(); }, []);
  if (!s) return null;

  const GAME_SLUGS: { slug: string; label: string }[] = [
    { slug: "ludo",     label: "Ludo"     },
    { slug: "domino",   label: "Domino"   },
    { slug: "fanorona", label: "Fanorona" },
    { slug: "chess",    label: "Échecs"   },
    { slug: "rami",     label: "Rami"     },
    { slug: "poker",    label: "Poker"    },
  ];
  const disabledGames: string[] = Array.isArray(s.games_disabled) ? s.games_disabled : [];

  type GameStatus = "active" | "hidden" | "dev" | "paused";
  const getGameStatus = (slug: string): GameStatus => {
    if (disabledGames.includes(slug))          return "hidden";
    if (disabledGames.includes(slug + ":dev")) return "dev";
    if (disabledGames.includes(slug + ":paused")) return "paused";
    return "active";
  };
  const setGameStatus = (slug: string, status: GameStatus) => {
    const cleaned = disabledGames.filter(x => x !== slug && x !== slug + ":dev" && x !== slug + ":paused");
    const next = status === "active" ? cleaned
      : status === "hidden" ? [...cleaned, slug]
      : status === "dev"    ? [...cleaned, slug + ":dev"]
      : [...cleaned, slug + ":paused"];
    setS({ ...s, games_disabled: next });
  };

  // ── Save: unified settings (financial + app config + points) ──
  const save = async () => {
    if (fe.hasErrors) { toast.error("⚠️ Corrige les champs en erreur", { description: fe.firstError || "Un ou plusieurs champs sont invalides." }); return; }
    await saveWithToast(
      () => (supabase.from("app_settings").update({
        // Liens & contact
        download_url: s.download_url || "",
        tuto_url: s.tuto_url || "",
        update_url: s.update_url || "",
        contact_facebook: s.contact_facebook || "",
        contact_whatsapp: s.contact_whatsapp || "",
        contact_phone: s.contact_phone || "",
        contact_email: s.contact_email || "",
        // Chat & features
        chat_global_enabled: !!s.chat_global_enabled,
        chat_room_enabled: !!s.chat_room_enabled,
        live_enabled: !!s.live_enabled,
        max_spectators: Number(s.max_spectators) || 50,
        afk_enabled: !!s.afk_enabled,
        afk_t1_max: Number(s.afk_t1_max) || 2,
        afk_t2_max: Number(s.afk_t2_max) || 2,
        // Finance
        signup_bonus: Number(s.signup_bonus) || 0,
        game_commission_pct: Number(s.game_commission_pct) || 0,
        min_deposit: Number(s.min_deposit) || 0,
        min_withdraw: Number(s.min_withdraw) || 0,
        withdrawal_fee_pct: Number(s.withdrawal_fee_pct) || 0,
        // Mobile money operators
        mvola_phone: s.mvola_phone || "",
        mvola_name: s.mvola_name || "",
        orange_phone: s.orange_phone || "",
        orange_name: s.orange_name || "",
        airtel_phone: s.airtel_phone || "",
        airtel_name: s.airtel_name || "",
        // Points & stakes
        points_capture: Number(s.points_capture) || 0,
        points_home: Number(s.points_home) || 0,
        points_first: Number(s.points_first) || 0,
        points_second: Number(s.points_second) || 0,
        points_third: Number(s.points_third) || 0,
        tpoints_first: Number(s.tpoints_first) || 0,
        tpoints_second: Number(s.tpoints_second) || 0,
        tpoints_third: Number(s.tpoints_third) || 0,
        min_stake: Number(s.min_stake) || 0,
        max_stake: Number(s.max_stake) || 0,
        // Game status
        games_disabled: disabledGames,
      } as any) as any).eq("id", 1),
      { label: "Paramètres" },
    );
  };

  const F = ({ k, label, type = "text", validate, hint }: any) => (
    <ValidatedField
      variant="soft"
      label={label}
      value={s[k] ?? ""}
      type={type}
      hint={hint}
      validate={validate}
      onValidityChange={fe.setError(k)}
      onChange={(v) => setS({ ...s, [k]: v })}
    />
  );
  const Switch = ({ k, label }: any) => (
    <label className="flex items-center gap-2 text-sm">
      <input type="checkbox" checked={!!s[k]} onChange={e => setS({ ...s, [k]: e.target.checked })} />
      {label}
    </label>
  );
  const PF = ({ k, l }: any) => (
    <label className="text-xs block">{l}<input type="number" value={s[k] ?? 0} onChange={e => setS({ ...s, [k]: e.target.value })} className="w-full mt-1 px-2 py-2 rounded-xl bg-secondary text-sm outline-none" /></label>
  );

  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-4">
      <div className="font-bold flex items-center gap-2"><Settings className="w-4 h-4" /> Paramètres de l'application</div>

      {/* ── Liens ── */}
      <div className="space-y-2">
        <div className="text-xs font-bold uppercase tracking-wide text-muted-foreground">📱 Liens & Contact</div>
        <F k="download_url" label="Lien téléchargement APK" validate={V.optional(V.url)} />
        <div className="grid grid-cols-2 gap-2">
          <F k="tuto_url" label="Lien TUTO (Facebook)" validate={V.optional(V.url)} />
          <F k="update_url" label="Lien Mise à jour" validate={V.optional(V.url)} />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <F k="contact_facebook" label="Facebook URL" validate={V.optional(V.url)} />
          <F k="contact_whatsapp" label="WhatsApp (numéro)" validate={V.optional(V.malagasyPhone)} />
          <F k="contact_phone" label="Téléphone" validate={V.optional(V.malagasyPhone)} />
          <F k="contact_email" label="Email" type="email" validate={V.optional(V.email)} />
        </div>
      </div>

      {/* ── Finance ── */}
      <div className="space-y-2 pt-3 border-t border-border/60">
        <div className="text-xs font-bold uppercase tracking-wide text-muted-foreground">💰 Finance</div>
        <F k="signup_bonus" label="🎁 Bonus inscription (Ar)" type="number" hint="0 = désactivé" validate={V.number({ min: 0, max: 1_000_000, integer: true })} />
        <div className="grid grid-cols-2 gap-2">
          <F k="game_commission_pct" label="Commission parties (%)" type="number" hint="% du pot" validate={V.percent} />
          <F k="withdrawal_fee_pct" label="Frais de retrait (%)" type="number" min={0} max={100} validate={V.percent} />
          <F k="min_deposit" label="Dépôt min (Ar)" type="number" validate={V.number({ min: 0, integer: true })} />
          <F k="min_withdraw" label="Retrait min (Ar)" type="number" validate={V.number({ min: 0, integer: true })} />
        </div>
      </div>

      {/* ── Mobile Money ── */}
      <div className="space-y-2 pt-3 border-t border-border/60">
        <div className="text-xs font-bold uppercase tracking-wide text-muted-foreground">📲 Numéros de dépôt (Mobile Money)</div>
        <div className="rounded-2xl bg-secondary/50 p-3 space-y-2">
          <span className="px-2 py-0.5 rounded-full text-white text-[10px] font-extrabold bg-black">MVola</span>
          <F k="mvola_phone" label="Numéro MVola" validate={V.combine(V.required("Requis"), V.malagasyPhone)} />
          <F k="mvola_name" label="Titulaire MVola" validate={V.combine(V.required("Requis"), V.minLen(2), V.maxLen(80))} />
        </div>
        <div className="rounded-2xl bg-orange-50 dark:bg-orange-950/20 p-3 space-y-2">
          <span className="px-2 py-0.5 rounded-full text-white text-[10px] font-extrabold bg-orange-500">Orange Money</span>
          <F k="orange_phone" label="Numéro Orange" validate={V.optional(V.malagasyPhone)} />
          <F k="orange_name" label="Titulaire Orange" validate={V.maxLen(80)} />
        </div>
        <div className="rounded-2xl bg-red-50 dark:bg-red-950/20 p-3 space-y-2">
          <span className="px-2 py-0.5 rounded-full text-white text-[10px] font-extrabold bg-red-600">Airtel Money</span>
          <F k="airtel_phone" label="Numéro Airtel" validate={V.optional(V.malagasyPhone)} />
          <F k="airtel_name" label="Titulaire Airtel" validate={V.maxLen(80)} />
        </div>
      </div>

      {/* ── Chat & Features ── */}
      <div className="space-y-2 pt-3 border-t border-border/60">
        <div className="text-xs font-bold uppercase tracking-wide text-muted-foreground">💬 Chat & Fonctionnalités</div>
        <div className="grid grid-cols-2 gap-3">
          <Switch k="chat_global_enabled" label="Chat global actif" />
          <Switch k="chat_room_enabled" label="Chat de partie actif" />
          <Switch k="live_enabled" label="LIVE actif" />
          <Switch k="afk_enabled" label="Système AFK actif" />
        </div>
        <div className="grid grid-cols-3 gap-2">
          <F k="max_spectators" label="Max spectateurs" type="number" validate={V.number({ min: 0, max: 1000, integer: true })} />
          <F k="afk_t1_max" label="Max T1 (timeout)" type="number" validate={V.number({ min: 0, max: 20, integer: true })} />
          <F k="afk_t2_max" label="Max T2 (timeout)" type="number" validate={V.number({ min: 0, max: 20, integer: true })} />
        </div>
      </div>

      {/* ── Points & Stakes ── */}
      <div className="space-y-2 pt-3 border-t border-border/60">
        <div className="text-xs font-bold uppercase tracking-wide text-muted-foreground">🎯 Points & Limites mises</div>
        <div className="grid grid-cols-3 gap-2">
          <PF k="points_capture" l="Capture" />
          <PF k="points_home" l="Arrivée pion" />
          <PF k="points_first" l="1er partie" />
          <PF k="points_second" l="2e partie" />
          <PF k="points_third" l="3e partie" />
          <PF k="tpoints_first" l="🥇 Tournoi" />
          <PF k="tpoints_second" l="🥈 Tournoi" />
          <PF k="tpoints_third" l="🥉 Tournoi" />
          <PF k="min_stake" l="Min mise (Ar)" />
          <PF k="max_stake" l="Max mise (Ar)" />
        </div>
      </div>

      {/* ── Game Status ── */}
      <div className="pt-3 border-t border-border/60">
        <div className="text-xs font-bold uppercase tracking-wide mb-2 text-muted-foreground">🎮 Statut des jeux</div>
        <div className="space-y-2">
          {GAME_SLUGS.map(g => {
            const st = getGameStatus(g.slug);
            const BG: Record<GameStatus, string> = {
              active: "bg-emerald-500/10 border-emerald-500/20",
              hidden: "bg-destructive/10 border-destructive/20",
              dev:    "bg-amber-500/10 border-amber-500/20",
              paused: "bg-sky-500/10 border-sky-500/20",
            };
            const LABEL: Record<GameStatus, string> = {
              active: "✅ Actif",
              hidden: "🚫 Masqué",
              dev:    "🔧 En développement",
              paused: "⏸️ En pause",
            };
            return (
              <div key={g.slug} className={`flex items-center justify-between px-3 py-2 rounded-xl border ${BG[st]}`}>
                <span className="text-sm font-semibold">{g.label}</span>
                <select
                  value={st}
                  onChange={e => setGameStatus(g.slug, e.target.value as GameStatus)}
                  className="text-xs bg-transparent border border-border/50 rounded-lg px-2 py-1 outline-none cursor-pointer"
                >
                  <option value="active">✅ Actif</option>
                  <option value="hidden">🚫 Masqué</option>
                  <option value="dev">🔧 En développement</option>
                  <option value="paused">⏸️ En pause</option>
                </select>
              </div>
            );
          })}
        </div>
      </div>

      <div className="pt-2 text-[11px] text-muted-foreground">
        ⏱️ Les <b>timers</b> (tour, salle d'attente, minuteries Échecs/Fanorona) sont dans le panneau <b>⏱️ Timers</b> ci-dessus.
      </div>

      {fe.hasErrors && (
        <div className="text-xs font-semibold text-destructive bg-destructive/10 border border-destructive/20 rounded-xl px-3 py-2">
          ⚠️ {fe.firstError || "Corrige les champs en erreur avant d'enregistrer."}
        </div>
      )}
      <button onClick={save} disabled={fe.hasErrors} className="w-full py-2.5 rounded-full bg-primary text-primary-foreground font-semibold flex items-center justify-center gap-2 disabled:opacity-50 disabled:cursor-not-allowed"><Save className="w-4 h-4" /> Enregistrer tous les paramètres</button>
      <button onClick={async () => { const { data } = await supabase.rpc("ludo_purge_unready_rooms" as any); toast.success(`${data || 0} parties purgées`); }}
        className="w-full py-2 rounded-full bg-secondary text-sm">🧹 Purger les parties non prêtes</button>
    </div>
  );
}

// =================== ALIAS / PERSONA ===================
type PersonaState = {
  is_active: boolean;
  real_pseudo: string;
  real_avatar_url: string | null;
  persona_pseudo: string | null;
  persona_avatar: string | null;
  activated_at: string | null;
};

type AliasItem = { id: string; pseudo: string; avatar_url: string | null; is_active: boolean; created_at: string };

function PersonaAdmin() {
  const [aliases, setAliases] = useState<AliasItem[]>([]);
  const [personaState, setPersonaState] = useState<PersonaState | null>(null);
  const [loading, setLoading] = useState(true);
  const [newPseudo, setNewPseudo] = useState("");
  const [newAvatarUrl, setNewAvatarUrl] = useState<string | null>(null);
  const [newAvatarPreview, setNewAvatarPreview] = useState<string | null>(null);
  const [uploading, setUploading] = useState(false);
  // saving: id de l'alias en cours d'activation, "new", "deactivate", ou null
  const [saving, setSaving] = useState<string | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const load = async () => {
    setLoading(true);
    const [aliasRes, personaRes] = await Promise.all([
      (supabase.rpc as any)("admin_list_aliases"),
      (supabase.rpc as any)("admin_get_persona"),
    ]);
    if (aliasRes.data) setAliases(Array.isArray(aliasRes.data) ? aliasRes.data : []);
    const row = Array.isArray(personaRes.data) ? personaRes.data[0] : personaRes.data;
    if (row) setPersonaState(row as PersonaState);
    setLoading(false);
  };

  useEffect(() => { load(); }, []);

  const uploadAvatar = async (file: File) => {
    setUploading(true);
    const { compressImageToWebp } = await import("@/lib/image-compress");
    const f = await compressImageToWebp(file, { maxDim: 400, maxSizeKB: 200 });
    const path = `alias_${Date.now()}.webp`;
    const { error } = await supabase.storage.from("avatars").upload(path, f, { upsert: true, contentType: "image/webp" });
    if (error) { toast.error("Erreur upload : " + error.message); setUploading(false); return; }
    const { data: { publicUrl } } = supabase.storage.from("avatars").getPublicUrl(path);
    setNewAvatarUrl(publicUrl);
    setNewAvatarPreview(URL.createObjectURL(file));
    setUploading(false);
  };

  const saveAlias = async () => {
    if (!newPseudo.trim()) return toast.error("Le pseudo est requis");
    setSaving("new");
    const { error } = await (supabase.rpc as any)("admin_save_alias", {
      p_pseudo: newPseudo.trim(), p_avatar_url: newAvatarUrl,
    });
    setSaving(null);
    if (error) return toast.error(error.message);
    toast.success(`✅ Alias « ${newPseudo.trim()} » enregistré`);
    setNewPseudo(""); setNewAvatarUrl(null); setNewAvatarPreview(null);
    load();
  };

  const activateAlias = async (aliasId: string, aliasName: string) => {
    setSaving(aliasId);
    const { error } = await (supabase.rpc as any)("admin_activate_alias", { p_alias_id: aliasId });
    setSaving(null);
    if (error) return toast.error(error.message);
    toast.success(`✅ Alias « ${aliasName} » activé — les autres vous voient sous ce nom`);
    load();
  };

  const deactivate = async () => {
    setSaving("deactivate");
    const { error } = await (supabase.rpc as any)("admin_deactivate_persona");
    setSaving(null);
    if (error) return toast.error(error.message);
    toast.success("✅ Profil réel restauré");
    load();
  };

  const deleteAlias = async (aliasId: string) => {
    setSaving(aliasId + "_del");
    const { error } = await (supabase.rpc as any)("admin_delete_alias", { p_alias_id: aliasId });
    setSaving(null);
    if (error) return toast.error(error.message);
    load();
  };

  if (loading) return null;

  const isActive = personaState?.is_active ?? false;

  return (
    <Card>
      {/* En-tête */}
      <div className="flex items-center justify-between gap-3">
        <div>
          <div className="font-bold text-sm">🎭 Jouer sous un alias</div>
          <div className="text-xs text-muted-foreground mt-0.5">
            Même compte, même solde — autre nom et photo visible par les autres
          </div>
        </div>
        <span className={`text-[11px] font-bold px-2.5 py-1 rounded-full flex-shrink-0 ${
          isActive ? "bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-400"
                   : "bg-emerald-100 text-emerald-700 dark:bg-emerald-900/40 dark:text-emerald-400"
        }`}>
          {isActive ? "⚠️ Alias actif" : "✅ Profil réel"}
        </span>
      </div>

      {/* Alias actif en cours */}
      {isActive && personaState && (
        <div className="rounded-2xl bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 p-3 flex items-center gap-3">
          {personaState.persona_avatar
            ? <img src={personaState.persona_avatar} className="w-10 h-10 rounded-xl object-cover flex-shrink-0" alt="" />
            : <div className="w-10 h-10 rounded-xl bg-muted flex items-center justify-center text-lg flex-shrink-0">🎭</div>}
          <div className="flex-1 min-w-0">
            <div className="font-bold text-sm">{personaState.persona_pseudo}</div>
            <div className="text-xs text-muted-foreground">Visible au classement, dans le chat et en jeu</div>
          </div>
          <button onClick={deactivate} disabled={saving === "deactivate"}
            className="flex-shrink-0 px-3 py-1.5 rounded-full bg-secondary text-xs font-bold disabled:opacity-50">
            {saving === "deactivate" ? "…" : "↩️ Restaurer"}
          </button>
        </div>
      )}

      {/* Liste des alias sauvegardés */}
      {aliases.length > 0 && (
        <div>
          <div className="text-xs font-semibold text-muted-foreground mb-2">Mes alias ({aliases.length})</div>
          <div className="space-y-2">
            {aliases.map(alias => (
              <div key={alias.id} className={`flex items-center gap-2 p-2 rounded-2xl ${alias.is_active ? "bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800" : "bg-secondary/40"}`}>
                {alias.avatar_url
                  ? <img src={alias.avatar_url} className="w-9 h-9 rounded-xl object-cover flex-shrink-0" alt="" />
                  : <div className="w-9 h-9 rounded-xl bg-muted flex items-center justify-center text-base flex-shrink-0">🎭</div>}
                <div className="flex-1 min-w-0 font-semibold text-sm truncate">{alias.pseudo}</div>
                <button onClick={() => activateAlias(alias.id, alias.pseudo)}
                  disabled={!!saving}
                  className="flex-shrink-0 px-2.5 py-1.5 rounded-full text-white text-xs font-bold disabled:opacity-50"
                  style={{ background: "var(--gradient-primary)" }}>
                  {saving === alias.id ? "…" : alias.is_active ? "✓ Actif" : "▶ Jouer"}
                </button>
                <button onClick={() => deleteAlias(alias.id)}
                  disabled={saving === alias.id + "_del"}
                  className="flex-shrink-0 w-8 h-8 rounded-full bg-destructive/10 text-destructive flex items-center justify-center text-xs hover:bg-destructive/20 transition-colors">
                  🗑
                </button>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Formulaire : créer un nouvel alias */}
      <div className="border-t border-border/60 pt-3">
        <div className="text-xs font-semibold text-muted-foreground mb-2">+ Créer un nouvel alias</div>
        <div className="flex items-center gap-2">
          <button onClick={() => fileRef.current?.click()} disabled={uploading}
            className="w-12 h-12 rounded-2xl border-2 border-dashed border-border flex items-center justify-center overflow-hidden bg-muted hover:border-primary transition-colors relative flex-shrink-0">
            {newAvatarPreview
              ? <img src={newAvatarPreview} className="w-full h-full object-cover" alt="preview" />
              : <Camera className="w-4 h-4 text-muted-foreground" />}
            {uploading && (
              <div className="absolute inset-0 bg-black/40 flex items-center justify-center">
                <div className="w-3 h-3 border-2 border-white border-t-transparent rounded-full animate-spin" />
              </div>
            )}
          </button>
          <input ref={fileRef} type="file" accept="image/*" hidden
            onChange={e => e.target.files?.[0] && uploadAvatar(e.target.files[0])} />
          <input value={newPseudo} onChange={e => setNewPseudo(e.target.value)}
            placeholder="Pseudo de l'alias…" maxLength={30}
            className="flex-1 px-3 py-2 rounded-xl bg-card border border-border text-sm outline-none focus:border-primary" />
          <button onClick={saveAlias} disabled={saving === "new" || uploading || !newPseudo.trim()}
            className="flex-shrink-0 px-3 py-2 rounded-full text-white text-xs font-bold disabled:opacity-50"
            style={{ background: "var(--gradient-primary)" }}>
            {saving === "new" ? "…" : "💾 Enregistrer"}
          </button>
        </div>
      </div>

      <div className="text-[10px] text-muted-foreground/60">
        Solde, parties et historique ne changent pas. Visible au classement, dans le chat et en jeu.
      </div>
    </Card>
  );
}

// ─── BANNERS ADMIN ──────────────────────────────────────────
function BannersAdmin() {
  const [items, setItems] = useState<any[]>([]);
  const [f, setF] = useState({ title: "", subtitle: "", image_url: "", button_text: "", button_link: "", bg_gradient: "from-primary to-orange-600", starts_at: "", ends_at: "" });
  const [editingId, setEditingId] = useState<string | null>(null);

  const load = () => (supabase.from("banners" as any) as any).select("*").order("sort_order", { ascending: true }).then(({ data }: any) => setItems(data || []));
  useEffect(() => { load(); }, []);

  const GRADIENTS = [
    "from-amber-500 to-orange-600",
    "from-emerald-500 to-teal-600",
    "from-rose-500 to-pink-600",
    "from-violet-500 to-indigo-600",
    "from-blue-500 to-cyan-600",
    "from-primary to-orange-600",
  ];

  const save = async () => {
    if (!f.title.trim()) return toast.error("Titre requis");
    const { error } = await supabase.rpc("admin_banner_upsert" as any, {
      _id: editingId,
      _title: f.title,
      _subtitle: f.subtitle || null,
      _image_url: f.image_url || null,
      _button_text: f.button_text || null,
      _button_link: f.button_link || null,
      _bg_gradient: f.bg_gradient || null,
      _starts_at: f.starts_at ? new Date(f.starts_at).toISOString() : null,
      _ends_at: f.ends_at ? new Date(f.ends_at).toISOString() : null,
      _active: true,
      _sort_order: 0,
    } as any);
    if (error) return toast.error(error.message);
    toast.success(editingId ? "Bannière modifiée" : "Bannière créée");
    setF({ title: "", subtitle: "", image_url: "", button_text: "", button_link: "", bg_gradient: "from-primary to-orange-600", starts_at: "", ends_at: "" });
    setEditingId(null);
    load();
  };

  const edit = (b: any) => {
    setEditingId(b.id);
    setF({
      title: b.title || "",
      subtitle: b.subtitle || "",
      image_url: b.image_url || "",
      button_text: b.button_text || "",
      button_link: b.button_link || "",
      bg_gradient: b.bg_gradient || "from-primary to-orange-600",
      starts_at: b.starts_at ? new Date(b.starts_at).toISOString().slice(0, 16) : "",
      ends_at: b.ends_at ? new Date(b.ends_at).toISOString().slice(0, 16) : "",
    });
  };

  const del = async (id: string) => {
    if (!confirm("Supprimer cette bannière ?")) return;
    await supabase.rpc("admin_banner_delete" as any, { _id: id } as any);
    toast.success("Bannière supprimée");
    load();
  };

  const toggle = async (b: any, active: boolean) => {
    await supabase.rpc("admin_banner_upsert" as any, {
      _id: b.id, _title: b.title, _subtitle: b.subtitle, _image_url: b.image_url,
      _button_text: b.button_text, _button_link: b.button_link, _bg_gradient: b.bg_gradient,
      _starts_at: b.starts_at, _ends_at: b.ends_at, _active: active, _sort_order: b.sort_order,
    } as any);
    load();
  };

  return (
    <div className="rounded-3xl bg-card p-5 shadow-sm space-y-3">
      <div className="font-bold flex items-center gap-2"><ImagePlus className="w-4 h-4" /> Gestion des bannières</div>
      <div className="text-xs text-muted-foreground">Bannières affichées dans le carousel de la page d'accueil, juste après le solde.</div>

      {/* Form */}
      <div className="rounded-2xl bg-secondary p-3 space-y-2">
        <div className="text-sm font-bold">{editingId ? "✏️ Modifier" : "➕ Nouvelle bannière"}</div>
        <input value={f.title} onChange={e => setF({ ...f, title: e.target.value })} placeholder="Titre (ex: 🏆 TOURNOI LUDO)" className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <textarea value={f.subtitle} onChange={e => setF({ ...f, subtitle: e.target.value })} placeholder="Sous-titre (ex: Commence demain à 20h)" rows={2} className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        <div className="grid grid-cols-2 gap-2">
          <input value={f.image_url} onChange={e => setF({ ...f, image_url: e.target.value })} placeholder="URL image (optionnel)" className="px-3 py-2 rounded-xl bg-card text-sm outline-none" />
          <div className="flex flex-wrap gap-1">
            {GRADIENTS.map(g => (
              <button key={g} type="button" onClick={() => setF({ ...f, bg_gradient: g })}
                className={`w-7 h-7 rounded-lg bg-gradient-to-br ${g} ${f.bg_gradient === g ? "ring-2 ring-foreground ring-offset-1" : ""}`} />
            ))}
          </div>
        </div>
        <div className="grid grid-cols-2 gap-2">
          <input value={f.button_text} onChange={e => setF({ ...f, button_text: e.target.value })} placeholder="Texte bouton (ex: Participer)" className="px-3 py-2 rounded-xl bg-card text-sm outline-none" />
          <input value={f.button_link} onChange={e => setF({ ...f, button_link: e.target.value })} placeholder="Lien (ex: /tournaments)" className="px-3 py-2 rounded-xl bg-card text-sm outline-none" />
        </div>
        <div className="grid grid-cols-2 gap-2">
          <div>
            <label className="text-[10px] text-muted-foreground">Début (optionnel)</label>
            <input type="datetime-local" value={f.starts_at} onChange={e => setF({ ...f, starts_at: e.target.value })} className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
          </div>
          <div>
            <label className="text-[10px] text-muted-foreground">Fin (optionnel)</label>
            <input type="datetime-local" value={f.ends_at} onChange={e => setF({ ...f, ends_at: e.target.value })} className="w-full px-3 py-2 rounded-xl bg-card text-sm outline-none" />
          </div>
        </div>
        <div className="flex gap-2">
          {editingId && (
            <button onClick={() => { setEditingId(null); setF({ title: "", subtitle: "", image_url: "", button_text: "", button_link: "", bg_gradient: "from-primary to-orange-600", starts_at: "", ends_at: "" }); }}
              className="flex-1 py-2 rounded-full bg-secondary font-bold text-sm">Annuler</button>
          )}
          <button onClick={save} className="flex-[2] py-2 rounded-full bg-primary text-primary-foreground font-bold text-sm flex items-center justify-center gap-1">
            <Plus className="w-4 h-4" /> {editingId ? "Enregistrer" : "Créer bannière"}
          </button>
        </div>
      </div>

      {/* List */}
      {items.map((b: any) => (
        <div key={b.id} className="border-t border-border/60 pt-2 flex items-center gap-2">
          <div className={`w-10 h-10 rounded-lg bg-gradient-to-br ${b.bg_gradient || "from-primary to-orange-600"} shrink-0`} />
          <div className="flex-1 min-w-0">
            <div className="font-semibold text-sm truncate">{b.title}</div>
            <div className="text-xs text-muted-foreground truncate">{b.subtitle}</div>
            <div className="text-[10px] text-muted-foreground">
              {b.button_text && <span>Bouton: {b.button_text} → {b.button_link}</span>}
              {b.starts_at && <span className="ml-2">Début: {new Date(b.starts_at).toLocaleDateString("fr-FR")}</span>}
              {b.ends_at && <span className="ml-2">Fin: {new Date(b.ends_at).toLocaleDateString("fr-FR")}</span>}
            </div>
          </div>
          <label className="text-xs flex items-center gap-1">
            <input type="checkbox" checked={b.active} onChange={e => toggle(b, e.target.checked)} /> Actif
          </label>
          <button onClick={() => edit(b)} className="p-1.5 text-primary"><Save className="w-4 h-4" /></button>
          <button onClick={() => del(b.id)} className="p-1.5 text-destructive"><Trash2 className="w-4 h-4" /></button>
        </div>
      ))}
    </div>
  );
}
