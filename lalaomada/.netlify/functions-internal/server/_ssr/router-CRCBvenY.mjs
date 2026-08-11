import { Q as QueryClient } from "../_libs/tanstack__query-core.mjs";
import { Q as QueryClientProvider } from "../_libs/tanstack__react-query.mjs";
import { c as createRouter, a as createRootRouteWithContext, u as useRouter, L as Link, O as Outlet, H as HeadContent, S as Scripts, b as createFileRoute, l as lazyRouteComponent, d as useRouterState, e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { U as redirect } from "../_libs/tanstack__router-core.mjs";
import { j as jsxRuntimeExports, r as reactExports } from "../_libs/react.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { C as Capacitor } from "../_libs/capacitor__core.mjs";
import { P as PushNotifications } from "../_libs/capacitor__push-notifications.mjs";
import { Toaster as Toaster$1, toast } from "../_libs/sonner.mjs";
import { R as Root2, P as Portal2, C as Content2, T as Title2, D as Description2, a as Cancel, A as Action, O as Overlay2 } from "../_libs/radix-ui__react-alert-dialog.mjs";
import { c as clsx } from "../_libs/clsx.mjs";
import { t as twMerge } from "../_libs/tailwind-merge.mjs";
import { S as Slot } from "../_libs/radix-ui__react-slot.mjs";
import { c as cva } from "../_libs/class-variance-authority.mjs";
import { c as createClient } from "../_libs/supabase__supabase-js.mjs";
import { c as createOpenAICompatible } from "../_libs/ai-sdk__openai-compatible.mjs";
import { g as generateText } from "../_libs/ai.mjs";
import { T as TriangleAlert, A as ArrowLeft, B as Bot, G as Gamepad2, C as Cpu, a as Trophy, L as Lock, S as Swords, b as ChevronRight, Z as Zap, c as Gift, d as Copy, M as MessageCircle, e as Share2, P as Phone, U as Users, f as Coins, g as Sparkles, h as ChevronDown, H as Hourglass, i as CircleArrowDown, j as CircleArrowUp, R as ReceiptText, k as CircleCheck, l as Clock, m as CircleQuestionMark, n as MessageSquare, o as BookOpen, p as ChevronUp, X, q as LoaderCircle, r as Send, F as Flame, s as CircleX, t as Ban } from "../_libs/lucide-react.mjs";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "node:stream";
import "../_libs/isbot.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
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
import "../_libs/supabase__postgrest-js.mjs";
import "../_libs/supabase__realtime-js.mjs";
import "../_libs/supabase__phoenix.mjs";
import "../_libs/supabase__storage-js.mjs";
import "../_libs/iceberg-js.mjs";
import "../_libs/supabase__auth-js.mjs";
import "../_libs/supabase__functions-js.mjs";
import "../_libs/ai-sdk__provider.mjs";
import "../_libs/ai-sdk__provider-utils.mjs";
import "../_libs/eventsource-parser.mjs";
import "../_libs/zod.mjs";
import "../_libs/ai-sdk__gateway.mjs";
import "../_libs/@vercel/oidc.mjs";
import "path";
import "fs";
import "os";
import "../_libs/opentelemetry__api.mjs";
const Ctx$1 = reactExports.createContext(null);
function AuthProvider({ children }) {
  const [session, setSession] = reactExports.useState(null);
  const [user, setUser] = reactExports.useState(null);
  const [profile, setProfile] = reactExports.useState(null);
  const [isAdmin, setIsAdmin] = reactExports.useState(false);
  const [loading, setLoading] = reactExports.useState(true);
  const loadProfile = async (uid) => {
    const { data: p } = await supabase.from("profiles").select("*").eq("id", uid).maybeSingle();
    setProfile(p);
    const { data: roles } = await supabase.from("user_roles").select("role").eq("user_id", uid);
    setIsAdmin(!!roles?.some((r) => r.role === "admin"));
  };
  reactExports.useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((evt, s) => {
      if (evt === "PASSWORD_RECOVERY") {
        window.location.href = "/reset-password";
        return;
      }
      setSession(s);
      setUser(s?.user ?? null);
      if (s?.user) {
        setTimeout(() => {
          loadProfile(s.user.id);
        }, 0);
      } else {
        setProfile(null);
        setIsAdmin(false);
      }
    });
    supabase.auth.getSession().then(({ data: { session: s } }) => {
      setSession(s);
      setUser(s?.user ?? null);
      if (s?.user) {
        loadProfile(s.user.id).finally(() => setLoading(false));
      } else {
        setLoading(false);
      }
    });
    return () => {
      sub.subscription.unsubscribe();
    };
  }, []);
  reactExports.useEffect(() => {
    if (!user?.id) return;
    const uid = user.id;
    const ch = supabase.channel(`profile-live:${uid}`).on(
      "postgres_changes",
      { event: "UPDATE", schema: "public", table: "profiles", filter: `id=eq.${uid}` },
      (payload) => {
        setProfile((prev) => prev ? { ...prev, ...payload.new } : payload.new);
      }
    ).on(
      "postgres_changes",
      { event: "INSERT", schema: "public", table: "transactions", filter: `user_id=eq.${uid}` },
      () => {
        loadProfile(uid);
      }
    ).subscribe();
    const pollInterval = setInterval(() => {
      loadProfile(uid);
    }, 1e4);
    return () => {
      supabase.removeChannel(ch);
      clearInterval(pollInterval);
    };
  }, [user?.id]);
  const refreshProfile = async () => {
    if (user) await loadProfile(user.id);
  };
  const signOut = async () => {
    setSession(null);
    setUser(null);
    setProfile(null);
    setIsAdmin(false);
    try {
      await supabase.auth.signOut({ scope: "local" });
    } catch {
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Ctx$1.Provider, { value: { user, session, profile, isAdmin, loading, refreshProfile, signOut }, children });
}
const useAuth = () => {
  const c = reactExports.useContext(Ctx$1);
  if (!c) throw new Error("useAuth must be used inside AuthProvider");
  return c;
};
const VAPID_PUBLIC_KEY = "MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEIgW5W92vNMnFgOlXsTlMnpu71kxB90jqGdzMdvUDvzUjmpytXPlhhcZfHxB7sjNnbhYjI_aoG0eTjSyMs1xHYg";
function urlBase64ToUint8Array(base64String) {
  const padding = "=".repeat((4 - base64String.length % 4) % 4);
  const base64 = (base64String + padding).replace(/-/g, "+").replace(/_/g, "/");
  const rawData = atob(base64);
  const outputArray = new Uint8Array(rawData.length);
  for (let i = 0; i < rawData.length; ++i) {
    outputArray[i] = rawData.charCodeAt(i);
  }
  return outputArray;
}
function usePushNotifications() {
  const { user, profile } = useAuth();
  const registered = reactExports.useRef(false);
  const subscribe = reactExports.useCallback(async () => {
    if (!user?.id) return;
    if (Capacitor.isNativePlatform()) return;
    try {
      const reg = await navigator.serviceWorker.register("/sw.js");
      await navigator.serviceWorker.ready;
      let sub = await reg.pushManager.getSubscription();
      if (!sub) {
        const permission = await Notification.requestPermission();
        if (permission !== "granted") return;
        sub = await reg.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: urlBase64ToUint8Array(VAPID_PUBLIC_KEY)
        });
      }
      if (!sub) return;
      const subJson = sub.toJSON();
      const { error } = await supabase.from("push_subscriptions").upsert(
        {
          user_id: user.id,
          endpoint: subJson.endpoint,
          p256dh: subJson.keys?.p256dh,
          auth: subJson.keys?.auth,
          updated_at: (/* @__PURE__ */ new Date()).toISOString()
        },
        { onConflict: "user_id,endpoint", ignoreDuplicates: false }
      );
      if (error && !error.message.includes("duplicate")) {
        console.warn("[push] Failed to store subscription:", error.message);
      }
    } catch (e) {
      console.warn("[push] Subscription error:", e);
    }
  }, [user?.id]);
  reactExports.useEffect(() => {
    if (!user?.id || registered.current) return;
    registered.current = true;
    const timer = setTimeout(() => {
      if ("serviceWorker" in navigator && "PushManager" in window) {
        subscribe();
      }
    }, 2e3);
    return () => clearTimeout(timer);
  }, [user?.id, subscribe]);
  reactExports.useEffect(() => {
    if (!user?.id) return;
  }, [user?.id]);
}
function useNativePush() {
  const { user } = useAuth();
  const registered = reactExports.useRef(false);
  reactExports.useEffect(() => {
    if (!user?.id || registered.current) return;
    if (!Capacitor.isNativePlatform()) return;
    registered.current = true;
    let cleanup;
    (async () => {
      try {
        let permStatus = await PushNotifications.checkPermissions();
        if (permStatus.receive === "prompt") {
          permStatus = await PushNotifications.requestPermissions();
        }
        if (permStatus.receive !== "granted") {
          console.warn("[native-push] Permission not granted");
          return;
        }
        await PushNotifications.register();
        const tokenListener = await PushNotifications.addListener("registration", (token) => {
          console.log("[native-push] FCM token:", token.value.substring(0, 20) + "...");
          storeToken(user.id, token.value);
        });
        const errorListener = await PushNotifications.addListener("registrationError", (err) => {
          console.warn("[native-push] Registration error:", err);
        });
        const notifListener = await PushNotifications.addListener("pushNotificationReceived", (notif) => {
          console.log("[native-push] Foreground notification:", notif);
          const title = notif.title || "Lalao MADA";
          const body = notif.body || "";
          toast(title, {
            description: body,
            duration: 8e3
          });
        });
        const actionListener = await PushNotifications.addListener("pushNotificationActionPerformed", (action) => {
          console.log("[native-push] Notification tapped:", action);
          const data = action.notification.data || {};
          if (data.link || data.url) {
            const link = data.link || data.url;
            window.location.href = link;
          }
        });
        cleanup = async () => {
          await tokenListener?.remove();
          await errorListener?.remove();
          await notifListener?.remove();
          await actionListener?.remove();
        };
      } catch (e) {
        console.warn("[native-push] Setup error:", e);
      }
    })();
    return () => {
      cleanup?.();
    };
  }, [user?.id]);
}
async function storeToken(userId, token) {
  try {
    const { error } = await supabase.from("push_tokens").upsert(
      {
        user_id: userId,
        token,
        platform: "android",
        updated_at: (/* @__PURE__ */ new Date()).toISOString()
      },
      { onConflict: "user_id,token", ignoreDuplicates: false }
    );
    if (error && !error.message.includes("duplicate")) {
      console.warn("[native-push] Failed to store token:", error.message);
    } else {
      console.log("[native-push] Token stored successfully");
    }
  } catch (e) {
    console.warn("[native-push] Token storage error:", e);
  }
}
const appCss = "/assets/styles-BzRvk7_8.css";
const Toaster = ({ ...props }) => {
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    Toaster$1,
    {
      className: "toaster group",
      position: "top-center",
      duration: 2500,
      toastOptions: {
        unstyled: false,
        style: {
          padding: "6px 14px",
          borderRadius: "9999px",
          fontSize: "12px",
          fontWeight: 500,
          minHeight: "auto",
          maxWidth: "90vw"
        },
        classNames: {
          toast: "group toast group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border group-[.toaster]:border-border group-[.toaster]:shadow-sm group-[.toaster]:px-3 group-[.toaster]:py-1.5 group-[.toaster]:text-xs group-[.toaster]:font-medium group-[.toaster]:rounded-full",
          description: "group-[.toast]:text-muted-foreground group-[.toast]:text-xs",
          actionButton: "group-[.toast]:bg-primary group-[.toast]:text-primary-foreground group-[.toast]:rounded-full group-[.toast]:text-xs group-[.toast]:px-2 group-[.toast]:py-0.5",
          cancelButton: "group-[.toast]:bg-muted group-[.toast]:text-muted-foreground group-[.toast]:rounded-full group-[.toast]:text-xs",
          // Uniform styles for all types — no loud colors
          success: "group-[.toaster]:bg-card group-[.toaster]:text-foreground",
          error: "group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border-destructive/30",
          warning: "group-[.toaster]:bg-card group-[.toaster]:text-foreground group-[.toaster]:border-amber-500/30",
          info: "group-[.toaster]:bg-card group-[.toaster]:text-foreground"
        }
      },
      ...props
    }
  );
};
const DICT = {
  fr: {
    home: "Accueil",
    lobby: "Jouer",
    tournaments: "Tournois",
    rankings: "Classement",
    profile: "Profil",
    chat: "Chat",
    live: "Live",
    admin: "Admin",
    tutorial: "Tutoriel",
    contact: "Contact Support",
    balance: "Solde disponible",
    deposit: "Dépôt",
    withdraw: "Retrait",
    referral: "Parrainage",
    history: "Historique",
    deposit_sub: "Recharger",
    withdraw_sub: "Encaisser",
    referral_sub: "Inviter",
    history_sub: "Mes opérations",
    play_now: "JOUER MAINTENANT",
    language: "Langue",
    close: "Fermer",
    verified: "Vérifié",
    unverified: "Vérifier",
    banned_account: "Compte banni",
    contact_admin: "Contactez l'administrateur pour plus d'informations.",
    ongoing_games: "Mes parties en cours",
    top_players: "Top joueurs",
    waiting_status: "Attente",
    playing_status: "En cours",
    players: "joueurs",
    loading: "Chargement…",
    cancel: "Annuler",
    save: "Enregistrer",
    copy: "Copier",
    code_copied: "Code copié",
    link_copied: "Lien copié",
    no_items: "Aucun élément",
    no_data: "Aucune donnée",
    amount_label: "Montant (Ar)",
    method_label: "Méthode",
    reference_label: "Référence transaction",
    my_number_label: "Mon numéro",
    optional_label: "Mon numéro (optionnel)",
    send_request: "Envoyer la demande",
    request_withdrawal: "Demander le retrait",
    send_first_to: "Envoyer d'abord à",
    make_deposit: "Faire un dépôt",
    make_withdraw: "Demande de retrait",
    minimum_amount: "Minimum",
    pending_validation: "📌 Votre demande sera en attente de validation. Vous pouvez la suivre dans l'historique.",
    pending_admin: "📌 Demande en attente de validation par l'admin.",
    verify_phone_first: "Vérifiez votre numéro de téléphone avant de retirer",
    insufficient_balance: "Solde insuffisant",
    phone_required: "Numéro requis",
    reference_required: "Référence requise",
    validated: "Validé",
    rejected: "Rejeté",
    pending: "En attente",
    history_title: "Historique",
    deposits_section: "Dépôts",
    withdrawals_section: "Retraits",
    movements_section: "Mouvements",
    tx_deposit: "Dépôt",
    tx_withdraw: "Retrait",
    tx_stake: "Mise",
    tx_win: "Gain",
    tx_bonus: "Bonus",
    tx_referral: "Parrainage",
    tx_admin_adjust: "Ajustement",
    tx_refund: "Remboursement",
    referral_title: "Parrainage",
    referral_desc: "Partage ton code/lien. Quand ton filleul vérifie son numéro ET fait son 1er dépôt, tu reçois",
    referral_of_deposit: "de ce dépôt.",
    my_space: "Mon espace",
    my_profile: "Mon profil",
    advanced_admin: "Admin avancé",
    logout: "Déconnexion",
    discussion: "Discussion",
    tuto: "Tuto",
    tournaments_desc: "1V1 · 4 joueurs",
    rankings_desc: "Top joueurs · Ballon d'Or",
    tuto_desc: "Comment jouer",
    support_desc: "Nous contacter",
    ballon_dor: "Ballon d'Or Lalao MADA",
    champions: "Champions de tournoi",
    free_money: "Gagner de l'argent gratuitement",
    announcement: "Annonce",
    notifications: "Notifications",
    ai_unavailable: "L'assistant IA est temporairement indisponible.",
    ai_greeting: "Bonjour 👋 Je suis l'assistant Lalao MADA. Posez-moi vos questions !",
    titles: "Titres",
    finals: "Finales",
    podiums: "Podiums",
    points: "Points",
    general_rank: "Classement général",
    tournament_rank: "Classement tournois",
    admin_panel: "Panneau Admin",
    // Lobby
    public_games: "Parties publiques",
    private_games: "Parties privées",
    join_by_code: "Rejoindre par code",
    my_games_tab: "Mes parties",
    stake_label: "Mise (Ar)",
    mode_label: "Mode",
    players_max_label: "Joueurs max",
    commission_info: "Commission",
    join_btn: "Rejoindre",
    create_private_btn: "Créer (Privé)",
    private_code_label: "Code de la partie",
    enter_code_placeholder: "Code",
    ongoing_tab: "En cours",
    finished_tab: "Terminées",
    no_public_games: "Aucune partie publique. Créez-en une !",
    no_private_games: "Aucune partie privée.",
    no_mine_games: "Aucune partie en cours.",
    classic_mode: "Classique",
    speed_mode: "Moderne",
    blitz_mode: "Blitz",
    // Chat
    global_tab: "Global",
    private_tab: "Privés",
    game_tab: "Parties",
    back_btn: "← Retour",
    new_dm: "Nouveau message privé",
    user_id_placeholder: "ID utilisateur (ex: LDA1B2C)",
    open_btn: "Ouvrir",
    no_community: "Aucune communauté créée.",
    no_dm: "Aucun message privé.",
    no_game_chat: "Aucun chat de partie actif.",
    user_not_found: "Utilisateur introuvable",
    own_messages: "Ce sont vos propres messages",
    // Tournaments
    registrations_tab: "Inscriptions",
    running_tab: "En cours",
    hof_tab: "Hall of Fame",
    register_btn: "S'inscrire",
    unregister_btn: "Se désinscrire",
    registered_label: "Inscrit ✓",
    registration_confirmed: "Inscription confirmée 🏆",
    unregistered_msg: "Désinscrit",
    no_tournaments: "Aucun tournoi disponible.",
    tournament_mode: "Mode",
    max_players_label: "Joueurs max",
    prize_pool: "Cagnotte",
    // Tutos
    tutos_title_full: "Tutoriels & FAQ",
    no_content: "Aucun contenu disponible.",
    terms_of_use: "Conditions d'utilisation",
    // Live
    live_title_full: "LIVE en direct",
    live_disabled_msg: "LIVE actuellement désactivé.",
    live_badge: "EN DIRECT",
    popular_sort: "🔥 Populaire",
    recent_sort: "🆕 Récent",
    advanced_sort: "⏱ Avancé",
    watch_btn: "Regarder",
    no_live_games: "Aucune partie en cours actuellement.",
    started_at_label: "Commencé",
    // Profile
    phone_verified_status: "Téléphone vérifié",
    not_verified_status: "Non vérifié",
    pseudo_label: "Pseudo",
    unique_id_label: "Mon ID unique",
    security_section: "Sécurité",
    delete_account_btn: "Supprimer mon compte",
    phone_verification_title: "Vérification du téléphone",
    phone_required_info: "Obligatoire pour jouer et retirer. 1 numéro = 1 compte.",
    generate_code_btn: "Générer un code",
    regenerate_code_btn: "Régénérer le code",
    your_code_label: "Votre code",
    send_code_instructions: "Envoyez ce code par SMS/MVola au numéro admin :",
    admin_will_validate: "L'admin validera votre numéro manuellement.",
    my_deposits_section: "Mes dépôts",
    my_withdrawals_section: "Mes retraits",
    tx_history_section: "Historique des transactions",
    my_referrals_title: "Mes filleuls",
    phone_placeholder: "Votre numéro (ex: 0341234567)",
    copied_msg: "Copié",
    registered_on: "Inscrit le",
    code_generated: "Code généré",
    enter_phone_error: "Entrez votre numéro",
    confirm_delete: "Supprimer définitivement votre compte ?",
    round_label: "Dingana",
    // Composants partagés
    delete_message_confirm: "Supprimer ce message ?",
    search_placeholder: "Rechercher…",
    typing_single: "écrit",
    typing_plural: "écrivent",
    reply_to_label: "Réponse à",
    editing_label: "Édition",
    write_placeholder: "Écrire…",
    edited_label: "(modifié)",
    mic_unavailable: "Micro indisponible",
    download_app: "Télécharger l'application",
    contact_us_label: "Nous contacter",
    game_name_title: "Nom pour cette partie",
    game_name_desc: "En tant qu'admin, choisis un nom avant de créer ou rejoindre.",
    player_pseudo_placeholder: "Ton pseudo de joueur…",
    cancel_btn: "Annuler",
    continue_btn: "Continuer",
    announcement_label: "📢 Annonce",
    learn_more_btn: "En savoir plus",
    close_btn: "Fermer",
    earn_money_free: "💰 Gagner de l'argent gratuitement",
    participate_btn: "Participer",
    notifications_title: "Notifications",
    no_notifications: "Aucune notification",
    admin_conversation: "Conversation avec l'admin",
    reply_to_admin_placeholder: "Répondre à l'admin…",
    sent_msg: "Envoyé",
    maintenance_title: "Application en maintenance",
    maintenance_default: "Lalao MADA est en maintenance. Merci de votre compréhension.",
    game_chat_title: "Chat de la partie",
    loading_room: "Chargement du salon…",
    join_public_btn: "Rejoindre ou créer",
    login_tab: "Connexion",
    register_tab: "Inscription",
    signup_bonus: "+1 Ar offert à l'inscription",
    pseudo_field: "Pseudo",
    email_field: "Email",
    password_field: "Mot de passe",
    password_min_field: "Mot de passe (min 6 car.)",
    referral_field: "Code de parrainage",
    referral_opt: "(optionnel)",
    connect_btn: "Se connecter",
    create_account_btn: "Créer mon compte",
    welcome_connected: "Bienvenue sur Lalao MADA",
    waiting_room: "Salle d'attente",
    private_code_lbl: "Code privé",
    ready_status: "Prêt",
    waiting_ready: "En attente",
    starting_soon: "Démarrage imminent…",
    add_bot: "Ajouter un bot",
    quit_refunded: "Quitter",
    game_finished: "Partie terminée",
    winner_lbl: "Gagnant",
    no_winner: "Aucun gagnant",
    back_lobby: "Retour au lobby",
    spectator_lbl: "Spectateur",
    prize_winner: "Au gagnant",
    is_paused_msg: "est en pause — reprise dans",
    quit_game_title_key: "⚠️ Quitter la partie ?",
    quit_game_desc_key: "Si tu quittes, tu perdras automatiquement et ta mise sera définitivement perdue.",
    confirm_quit: "Confirmer quitter",
    slot_open: "Place libre…",
    bot_added: "Bot ajouté",
    left_game: "Tu as quitté la partie",
    lobby_title: "Choisir une partie",
    create_game: "Créer une partie",
    join_game: "Rejoindre",
    game_settings: "Paramètres",
    bet_amount: "Mise (Ar)",
    players_count: "Joueurs",
    start_game: "Démarrer",
    chat_title: "Chat global",
    send: "Envoyer",
    message_placeholder: "Votre message…",
    rankings_title: "Classement",
    my_rank: "Mon classement",
    profile_title: "Mon profil",
    edit_profile: "Modifier le profil",
    phone_number: "Numéro de téléphone",
    change_avatar: "Changer l'avatar",
    tournaments_title: "Tournois",
    join_tournament: "Rejoindre",
    tournament_detail: "Détail",
    live_title: "Parties en direct",
    tutos_title: "Tutoriels",
    no_open_tournaments: "Aucun tournoi ouvert",
    no_running_tournaments: "Aucun tournoi en cours",
    no_hof_tournaments: "Aucun tournoi terminé",
    season_label: "Saison",
    see_details: "Voir détails",
    four_players: "4 joueurs",
    free_badge: "GRATUIT",
    withdraw_tournament_btn: "Se retirer",
    back_to_tournaments: "Tournois",
    tournament_badge: "Tournoi",
    open_status: "Inscriptions",
    finished_status: "Terminé",
    cancelled_status: "Annulé",
    free_mode: "Mode gratuit · Pour le fun 🎮",
    description_section: "Description & règlement",
    rewards_section: "Récompenses",
    join_my_match: "Rejoindre mon match",
    champion_title: "Champion",
    registered_players: "Joueurs inscrits",
    bracket_title: "Bracket",
    no_players: "Aucun",
    top3_label: "Top 3",
    // Rankings — levels & periods
    level_beginner: "Débutant",
    level_novice: "Novice",
    level_intermediate: "Interméd.",
    level_advanced: "Avancé",
    level_expert: "Expert",
    level_master: "Maître",
    level_grandmaster: "Grand Maître",
    level_champion: "Champion",
    level_elite: "Élite",
    level_legend: "Légende",
    level_guide_title: "Guide des niveaux",
    period_all: "Tout le temps",
    period_month: "Ce mois",
    period_week: "Cette semaine",
    your_ranking: "Votre classement",
    you_suffix: "(vous)",
    win_singular: "victoire",
    win_plural: "victoires",
    season_ongoing: "En cours",
    season_ended: "Terminée",
    champion_designated: "Champion désigné",
    player_fallback: "Joueur",
    // Chat hub
    groups_tab_label: "Groupes",
    private_messages_label: "Messages privés",
    no_groups_available: "Aucun groupe disponible",
    unread_messages_label: "Messages non lus",
    no_conversation_label: "Aucune conversation. Entrez le code d'un joueur pour commencer.",
    start_conversation_label: "Commencer la conversation",
    active_label: "Actif",
    inactive_label: "Désactivé",
    code_not_found: "Code introuvable",
    cant_message_self: "Vous ne pouvez pas vous écrire à vous-même",
    conversation_create_error: "Impossible de créer la conversation",
    conversation_created_with: "Conversation avec",
    conversation_created_suffix: "créée",
    premium_feature_title: "Fonctionnalité Premium",
    premium_dm_desc: "Les messages privés sont réservés aux membres Premium. Passez à Premium pour discuter directement avec n'importe quel joueur.",
    premium_feature_unlimited_dm: "Messages privés illimités",
    premium_feature_badge: "Badge Premium exclusif",
    premium_feature_priority_rooms: "Priorité dans les salles",
    premium_feature_priority_support: "Support prioritaire",
    contact_admin_premium: "Contactez l'administrateur pour activer Premium.",
    upgrade_premium_btn: "Passer à Premium",
    player_code_placeholder: "Code unique du joueur…",
    browse_all_players: "Voir tous les joueurs",
    all_players_title: "Tous les joueurs",
    search_player_placeholder: "Rechercher un joueur…",
    loading_label: "Chargement…",
    no_players_found: "Aucun joueur trouvé",
    send_message_btn: "Envoyer un message",
    dm_fallback_label: "Message privé",
    group_fallback_label: "Groupe"
  }
};
const Ctx = reactExports.createContext({ lang: "fr", setLang: () => {
}, t: (k) => k });
function I18nProvider({ children }) {
  reactExports.useEffect(() => {
    document.documentElement.lang = "fr";
  }, []);
  const lang = "fr";
  const setLang = (_l) => {
  };
  const t = (k) => DICT.fr[k] || k;
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Ctx.Provider, { value: { lang, setLang, t }, children });
}
const useT = () => reactExports.useContext(Ctx);
function cn(...inputs) {
  return twMerge(clsx(inputs));
}
const buttonVariants = cva(
  "inline-flex items-center justify-center gap-2 whitespace-nowrap rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring disabled:pointer-events-none disabled:opacity-50 [&_svg]:pointer-events-none [&_svg]:size-4 [&_svg]:shrink-0",
  {
    variants: {
      variant: {
        default: "bg-primary text-primary-foreground shadow hover:bg-primary/90",
        destructive: "bg-destructive text-destructive-foreground shadow-sm hover:bg-destructive/90",
        outline: "border border-input bg-background shadow-sm hover:bg-accent hover:text-accent-foreground",
        secondary: "bg-secondary text-secondary-foreground shadow-sm hover:bg-secondary/80",
        ghost: "hover:bg-accent hover:text-accent-foreground",
        link: "text-primary underline-offset-4 hover:underline"
      },
      size: {
        default: "h-9 px-4 py-2",
        sm: "h-8 rounded-md px-3 text-xs",
        lg: "h-10 rounded-md px-8",
        icon: "h-9 w-9"
      }
    },
    defaultVariants: {
      variant: "default",
      size: "default"
    }
  }
);
const Button = reactExports.forwardRef(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : "button";
    return /* @__PURE__ */ jsxRuntimeExports.jsx(Comp, { className: cn(buttonVariants({ variant, size, className })), ref, ...props });
  }
);
Button.displayName = "Button";
const AlertDialog = Root2;
const AlertDialogPortal = Portal2;
const AlertDialogOverlay = reactExports.forwardRef(({ className, ...props }, ref) => /* @__PURE__ */ jsxRuntimeExports.jsx(
  Overlay2,
  {
    className: cn(
      "fixed inset-0 z-[100] bg-black/80 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0",
      className
    ),
    ...props,
    ref
  }
));
AlertDialogOverlay.displayName = Overlay2.displayName;
const AlertDialogContent = reactExports.forwardRef(({ className, ...props }, ref) => /* @__PURE__ */ jsxRuntimeExports.jsxs(AlertDialogPortal, { children: [
  /* @__PURE__ */ jsxRuntimeExports.jsx(AlertDialogOverlay, {}),
  /* @__PURE__ */ jsxRuntimeExports.jsx(
    Content2,
    {
      ref,
      className: cn(
        "fixed left-[50%] top-[50%] z-[101] grid w-full max-w-lg translate-x-[-50%] translate-y-[-50%] gap-4 border bg-background p-6 shadow-lg duration-200 data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0 data-[state=closed]:zoom-out-95 data-[state=open]:zoom-in-95 data-[state=closed]:slide-out-to-left-1/2 data-[state=closed]:slide-out-to-top-[48%] data-[state=open]:slide-in-from-left-1/2 data-[state=open]:slide-in-from-top-[48%] sm:rounded-lg",
        className
      ),
      ...props
    }
  )
] }));
AlertDialogContent.displayName = Content2.displayName;
const AlertDialogHeader = ({ className, ...props }) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: cn("flex flex-col space-y-2 text-center sm:text-left", className), ...props });
AlertDialogHeader.displayName = "AlertDialogHeader";
const AlertDialogFooter = ({ className, ...props }) => /* @__PURE__ */ jsxRuntimeExports.jsx(
  "div",
  {
    className: cn("flex flex-col-reverse sm:flex-row sm:justify-end sm:space-x-2", className),
    ...props
  }
);
AlertDialogFooter.displayName = "AlertDialogFooter";
const AlertDialogTitle = reactExports.forwardRef(({ className, ...props }, ref) => /* @__PURE__ */ jsxRuntimeExports.jsx(
  Title2,
  {
    ref,
    className: cn("text-lg font-semibold", className),
    ...props
  }
));
AlertDialogTitle.displayName = Title2.displayName;
const AlertDialogDescription = reactExports.forwardRef(({ className, ...props }, ref) => /* @__PURE__ */ jsxRuntimeExports.jsx(
  Description2,
  {
    ref,
    className: cn("text-sm text-muted-foreground", className),
    ...props
  }
));
AlertDialogDescription.displayName = Description2.displayName;
const AlertDialogAction = reactExports.forwardRef(({ className, ...props }, ref) => /* @__PURE__ */ jsxRuntimeExports.jsx(Action, { ref, className: cn(buttonVariants(), className), ...props }));
AlertDialogAction.displayName = Action.displayName;
const AlertDialogCancel = reactExports.forwardRef(({ className, ...props }, ref) => /* @__PURE__ */ jsxRuntimeExports.jsx(
  Cancel,
  {
    ref,
    className: cn(buttonVariants({ variant: "outline" }), "mt-2 sm:mt-0", className),
    ...props
  }
));
AlertDialogCancel.displayName = Cancel.displayName;
const ConfirmCtx = reactExports.createContext(null);
function ConfirmProvider({ children }) {
  const [open, setOpen] = reactExports.useState(false);
  const [opts, setOpts] = reactExports.useState(null);
  const resolver = reactExports.useRef(null);
  const confirm = reactExports.useCallback((o) => {
    setOpts(o);
    setOpen(true);
    return new Promise((resolve) => {
      resolver.current = resolve;
    });
  }, []);
  const handle = (val) => {
    setOpen(false);
    const r = resolver.current;
    resolver.current = null;
    setTimeout(() => r?.(val), 0);
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(ConfirmCtx.Provider, { value: confirm, children: [
    children,
    /* @__PURE__ */ jsxRuntimeExports.jsx(AlertDialog, { open, onOpenChange: (o) => {
      if (!o) handle(false);
    }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(AlertDialogContent, { className: "rounded-3xl max-w-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs(AlertDialogHeader, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(AlertDialogTitle, { className: "flex items-center gap-2 text-base", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(TriangleAlert, { className: `w-5 h-5 ${opts?.destructive ? "text-destructive" : "text-amber-500"}` }),
          opts?.title
        ] }),
        opts?.description && /* @__PURE__ */ jsxRuntimeExports.jsx(AlertDialogDescription, { className: "text-sm", children: opts.description })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(AlertDialogFooter, { className: "flex-row justify-end gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(AlertDialogCancel, { className: "rounded-full mt-0", children: opts?.cancelLabel || "Annuler" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          AlertDialogAction,
          {
            onClick: () => handle(true),
            className: `rounded-full ${opts?.destructive ? "bg-destructive text-destructive-foreground hover:bg-destructive/90" : ""}`,
            children: opts?.confirmLabel || "Confirmer"
          }
        )
      ] })
    ] }) })
  ] });
}
function useConfirm() {
  const ctx = reactExports.useContext(ConfirmCtx);
  if (!ctx) throw new Error("useConfirm must be used inside ConfirmProvider");
  return ctx;
}
function LudoMark({ size = 48 }) {
  const dot = Math.floor(size * 0.22);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
    "div",
    {
      className: "lm-mark",
      style: { width: size, height: size },
      "aria-hidden": true,
      children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "lm-mark__inner", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "lm-dot lm-dot--red", style: { width: dot, height: dot } }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "lm-dot lm-dot--green", style: { width: dot, height: dot } }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "lm-dot lm-dot--blue", style: { width: dot, height: dot } }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "lm-dot lm-dot--yellow", style: { width: dot, height: dot } })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "lm-mark__glow" })
      ]
    }
  );
}
function BrandText({ subtitle }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "lm-brand", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "lm-brand__title", children: "Lalao MADA" }),
    subtitle && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "lm-brand__sub", children: subtitle })
  ] });
}
function PageLoader({ variant = "overlay", label }) {
  if (variant === "splash") {
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "lm-splash", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "lm-splash__content", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(LudoMark, { size: 72 }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(BrandText, { subtitle: label ?? "Jouez. Gagnez. Retirez en Ariary." }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "lm-splash__dots", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", {}),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", {})
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "lm-splash__shimmer" })
    ] });
  }
  if (variant === "inline") {
    return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "lm-inline", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LudoMark, { size: 36 }) });
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "lm-overlay", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "lm-overlay__content", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(LudoMark, { size: 52 }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(BrandText, { subtitle: label })
  ] }) });
}
function useDelayedPending(pending, delay = 200) {
  const [show, setShow] = reactExports.useState(false);
  reactExports.useEffect(() => {
    if (!pending) {
      setShow(false);
      return;
    }
    const t = setTimeout(() => setShow(true), delay);
    return () => clearTimeout(t);
  }, [pending]);
  return show;
}
function NotFoundComponent() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex min-h-screen items-center justify-center bg-background px-4", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "max-w-md text-center", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-7xl font-bold text-foreground", children: "404" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "mt-4 text-xl font-semibold text-foreground", children: "Page not found" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "mt-2 text-sm text-muted-foreground", children: "The page you're looking for doesn't exist or has been moved." }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-6", children: /* @__PURE__ */ jsxRuntimeExports.jsx(
      Link,
      {
        to: "/",
        className: "inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90",
        children: "Go home"
      }
    ) })
  ] }) });
}
function ErrorComponent({ error, reset }) {
  console.error(error);
  const router2 = useRouter();
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex min-h-screen items-center justify-center bg-background px-4", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "max-w-md text-center", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-semibold tracking-tight text-foreground", children: "This page didn't load" }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "mt-2 text-sm text-muted-foreground", children: "Something went wrong on our end. You can try refreshing or head back home." }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-6 flex flex-wrap justify-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => {
            router2.invalidate();
            reset();
          },
          className: "inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90",
          children: "Try again"
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "a",
        {
          href: "/",
          className: "inline-flex items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium text-foreground transition-colors hover:bg-accent",
          children: "Go home"
        }
      )
    ] })
  ] }) });
}
const Route$H = createRootRouteWithContext()({
  head: () => ({
    meta: [
      { charSet: "utf-8" },
      { name: "viewport", content: "width=device-width, initial-scale=1, viewport-fit=cover" },
      { name: "google-site-verification", content: "Snwx104x8UhEDn9RvTOKUP6Jdzn3IH8sas4UYvdSp0g" },
      { name: "theme-color", content: "#f97316" },
      { title: "Lalao MADA — Jouez au Ludo en Ariary" },
      { name: "description", content: "Lalao MADA, application 100% malagasy : jouez au Ludo en ligne, mises en Ariary, dépôts et retraits via Mobile Money (MVola, Orange Money, Airtel Money)." },
      { name: "author", content: "Lalao MADA" },
      { property: "og:title", content: "Lalao MADA — Jouez au Ludo en Ariary" },
      { property: "og:description", content: "Lalao MADA, application 100% malagasy : jouez au Ludo en ligne, mises en Ariary, dépôts et retraits via Mobile Money (MVola, Orange Money, Airtel Money)." },
      { property: "og:type", content: "website" },
      { property: "og:site_name", content: "Lalao MADA" },
      { property: "og:url", content: "https://lalaomada.lovable.app/" },
      { name: "twitter:card", content: "summary_large_image" },
      { name: "twitter:title", content: "Lalao MADA — Jouez au Ludo en Ariary" },
      { name: "twitter:description", content: "Lalao MADA, application 100% malagasy : jouez au Ludo en ligne, mises en Ariary, dépôts et retraits via Mobile Money (MVola, Orange Money, Airtel Money)." },
      { property: "og:image", content: "https://pub-bb2e103a32db4e198524a2e9ed8f35b4.r2.dev/b744f25f-6be8-4018-84db-5968ece32a9c/id-preview-2109df56--55268ec1-0df4-4faf-b44d-913c5f22a01f.lovable.app-1781835411588.png" },
      { name: "twitter:image", content: "https://pub-bb2e103a32db4e198524a2e9ed8f35b4.r2.dev/b744f25f-6be8-4018-84db-5968ece32a9c/id-preview-2109df56--55268ec1-0df4-4faf-b44d-913c5f22a01f.lovable.app-1781835411588.png" }
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "manifest", href: "/manifest.json" },
      { rel: "apple-touch-icon", href: "/favicon.ico" }
    ],
    scripts: [{
      type: "application/ld+json",
      children: JSON.stringify({
        "@context": "https://schema.org",
        "@graph": [
          {
            "@type": "WebSite",
            "@id": "https://lalaomada.lovable.app/#website",
            url: "https://lalaomada.lovable.app/",
            name: "Lalao MADA",
            inLanguage: "fr-MG",
            description: "Application Ludo malagasy avec mises en Ariary et dépôts/retraits Mobile Money."
          },
          {
            "@type": "Organization",
            "@id": "https://lalaomada.lovable.app/#organization",
            name: "Lalao MADA",
            url: "https://lalaomada.lovable.app/"
          }
        ]
      })
    }]
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent
});
function RootShell({ children }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("html", { lang: "fr", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("head", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(HeadContent, {}),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "script",
        {
          dangerouslySetInnerHTML: {
            __html: `(function(){try{var t=localStorage.getItem('theme');if(t!=='light'){document.documentElement.classList.add('dark');var m=document.querySelector('meta[name=theme-color]');if(m)m.setAttribute('content','#1a1714');}}catch(e){}})();`
          }
        }
      )
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("body", { children: [
      children,
      /* @__PURE__ */ jsxRuntimeExports.jsx(Scripts, {})
    ] })
  ] });
}
function RouteSkeletonOverlay() {
  const { isLoading, pathname } = useRouterState({
    select: (s) => ({
      isLoading: s.status === "pending",
      pathname: s.pendingMatches?.[s.pendingMatches.length - 1]?.pathname ?? s.location.pathname
    })
  });
  const show = useDelayedPending(isLoading, 200);
  if (!isLoading || !show) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      "aria-hidden": true,
      className: "pointer-events-none fixed inset-x-0 bottom-0 z-30 animate-in fade-in duration-200",
      style: { top: 56 },
      children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-full w-full overflow-hidden bg-background", children: /* @__PURE__ */ jsxRuntimeExports.jsx(PageLoader, { variant: "overlay" }) })
    }
  );
}
function PushNotificationsManager() {
  usePushNotifications();
  useNativePush();
  return null;
}
function RootComponent() {
  const { queryClient } = Route$H.useRouteContext();
  return /* @__PURE__ */ jsxRuntimeExports.jsx(QueryClientProvider, { client: queryClient, children: /* @__PURE__ */ jsxRuntimeExports.jsx(I18nProvider, { children: /* @__PURE__ */ jsxRuntimeExports.jsx(AuthProvider, { children: /* @__PURE__ */ jsxRuntimeExports.jsxs(ConfirmProvider, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(Outlet, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(RouteSkeletonOverlay, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(PushNotificationsManager, {}),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Toaster, {})
  ] }) }) }) });
}
const $$splitComponentImporter$u = () => import("./index-D7A7Elb9.mjs");
const Route$G = createFileRoute("/")({
  component: lazyRouteComponent($$splitComponentImporter$u, "component"),
  head: () => ({
    meta: [{
      title: "Lalao MADA — Jouez. Gagnez. Retirez en Ariary."
    }, {
      name: "description",
      content: "La plateforme #1 de jeux en ligne à Madagascar : Ludo, Domino, Fanorona, Échecs, Poker, Rami — mises en Ariary via Mobile Money."
    }, {
      property: "og:title",
      content: "Lalao MADA — Jouez. Gagnez. Retirez en Ariary."
    }, {
      property: "og:description",
      content: "Rejoignez la première plateforme de jeux multijoueur malagasy."
    }, {
      property: "og:type",
      content: "website"
    }, {
      property: "og:url",
      content: "https://lalaomada.lovable.app/"
    }]
  })
});
const $$splitComponentImporter$t = () => import("../_authenticated-CbW3PzlJ.mjs");
const Route$F = createFileRoute("/_authenticated")({
  component: lazyRouteComponent($$splitComponentImporter$t, "component")
});
const $$splitComponentImporter$s = () => import("./cgu-niZhLJ2z.mjs");
const Route$E = createFileRoute("/cgu")({
  component: lazyRouteComponent($$splitComponentImporter$s, "component"),
  head: () => ({
    meta: [{
      title: "Conditions d'utilisation — Lalao MADA"
    }, {
      name: "description",
      content: "Conditions générales d'utilisation de Lalao MADA."
    }]
  })
});
const $$splitComponentImporter$r = () => import("./confidentialite-yp8YUUWm.mjs");
const Route$D = createFileRoute("/confidentialite")({
  component: lazyRouteComponent($$splitComponentImporter$r, "component"),
  head: () => ({
    meta: [{
      title: "Politique de confidentialité — Lalao MADA"
    }, {
      name: "description",
      content: "Politique de confidentialité de Lalao MADA."
    }]
  })
});
const Route$C = createFileRoute("/jeux-publics")({
  component: JeuxPublicsPage,
  head: () => ({
    meta: [
      { title: "Jeux disponibles — Lalao MADA" },
      { name: "description", content: "Découvrez tous les jeux disponibles sur Lalao MADA. Jouez contre un bot ou affrontez d'autres joueurs." }
    ]
  })
});
const ALL_GAMES = [
  {
    slug: "ludo",
    name: "Ludo",
    emoji: "🎲",
    desc: "Parcours et stratégie pour 2 à 4 joueurs",
    gradient: "from-rose-500 to-pink-600",
    ring: "ring-rose-500/30",
    tag: "Multijoueur",
    botSupported: true,
    cover: /* @__PURE__ */ jsxRuntimeExports.jsx(LudoCover, {})
  },
  {
    slug: "domino",
    name: "Domino",
    emoji: "🁣",
    desc: "Jeu de tuiles classique malagasy",
    gradient: "from-amber-400 to-orange-500",
    ring: "ring-amber-500/30",
    tag: "Classique",
    botSupported: true,
    cover: /* @__PURE__ */ jsxRuntimeExports.jsx(DominoCover, {})
  },
  {
    slug: "fanorona",
    name: "Fanorona",
    emoji: "♟",
    desc: "Jeu de stratégie national malgache",
    gradient: "from-emerald-400 to-teal-600",
    ring: "ring-emerald-500/30",
    tag: "Stratégie",
    botSupported: true,
    cover: /* @__PURE__ */ jsxRuntimeExports.jsx(FanoronaCover, {})
  },
  {
    slug: "chess",
    name: "Échecs",
    emoji: "♜",
    desc: "Le roi des jeux de stratégie",
    gradient: "from-slate-400 to-slate-700",
    ring: "ring-slate-500/30",
    tag: "Tournois",
    botSupported: true,
    cover: /* @__PURE__ */ jsxRuntimeExports.jsx(ChessCover, {})
  },
  {
    slug: "poker",
    name: "Poker",
    emoji: "🃏",
    desc: "Texas Hold'em — misez en Ariary",
    gradient: "from-violet-500 to-purple-700",
    ring: "ring-violet-500/30",
    tag: "Texas Hold'em",
    botSupported: false,
    cover: /* @__PURE__ */ jsxRuntimeExports.jsx(PokerCover, {})
  },
  {
    slug: "rami",
    name: "Rami",
    emoji: "🂡",
    desc: "Jeu de cartes à l'ariary",
    gradient: "from-sky-400 to-blue-600",
    ring: "ring-sky-500/30",
    tag: "Cartes",
    botSupported: false,
    cover: /* @__PURE__ */ jsxRuntimeExports.jsx(RamiCover, {})
  }
];
function LudoCover() {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full h-full grid grid-cols-2 grid-rows-2 rounded-xl overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-red-500 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 h-6 rounded-full bg-red-200 border-2 border-red-700 shadow-inner" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-green-600 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 h-6 rounded-full bg-green-200 border-2 border-green-800 shadow-inner" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-blue-600 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 h-6 rounded-full bg-blue-200 border-2 border-blue-800 shadow-inner" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-yellow-400 flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 h-6 rounded-full bg-yellow-100 border-2 border-yellow-600 shadow-inner" }) })
  ] });
}
function DominoCover() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full bg-gradient-to-br from-gray-900 to-gray-700 rounded-xl flex items-center justify-center gap-2", children: [3, 5, 2].map((dots, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `bg-white rounded shadow-lg flex flex-col items-center justify-around p-1.5 ${i === 1 ? "h-12 w-6" : "h-10 w-5 opacity-80"}`, children: Array.from({ length: dots }).map((_, j) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-1.5 h-1.5 rounded-full bg-gray-800" }, j)) }, i)) });
}
function FanoronaCover() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full bg-gradient-to-br from-amber-900 to-amber-700 rounded-xl flex items-center justify-center p-2", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-5 grid-rows-4 gap-1 w-full h-full", children: Array.from({ length: 20 }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-center justify-center", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `rounded-full border ${i % 3 === 0 ? "w-3 h-3 bg-white border-white/50" : i % 3 === 1 ? "w-3 h-3 bg-black border-black/50" : "w-1.5 h-1.5 bg-amber-500/30 border-amber-400/20"}` }) }, i)) }) });
}
function ChessCover() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full rounded-xl overflow-hidden", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-4 grid-rows-4 w-full h-full", children: Array.from({ length: 16 }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: (Math.floor(i / 4) + i) % 2 === 0 ? "bg-slate-200" : "bg-slate-700" }, i)) }) });
}
function PokerCover() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full bg-gradient-to-br from-green-900 to-green-700 rounded-xl flex items-center justify-center gap-1 p-2", children: ["♠", "♥", "♦", "♣"].map((s, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-lg font-black ${s === "♥" || s === "♦" ? "text-red-400" : "text-white"}`, children: s }, i)) });
}
function RamiCover() {
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full bg-gradient-to-br from-blue-900 to-blue-700 rounded-xl flex items-center justify-center gap-1 p-2", children: ["A", "K", "Q", "J"].map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-white/90 rounded text-xs font-black text-blue-900 px-1 py-0.5 shadow", children: c }, i)) });
}
function useOnlineCount(slug) {
  const [count, setCount] = reactExports.useState(null);
  reactExports.useEffect(() => {
    supabase.from("game_sessions").select("id", { count: "exact", head: true }).eq("slug", slug).eq("status", "waiting").then(({ count: c }) => {
      if (c !== null) setCount(c);
    });
  }, [slug]);
  return count;
}
function OnlineCount({ slug }) {
  const count = useOnlineCount(slug);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-1 text-[11px] font-semibold text-emerald-400", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "relative flex h-1.5 w-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "animate-ping absolute inline-flex h-full w-full rounded-full bg-emerald-400/60" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "relative inline-flex rounded-full h-1.5 w-1.5 bg-emerald-400" })
    ] }),
    count !== null ? `${count} en ligne` : "—"
  ] });
}
function JeuxPublicsPage() {
  const navigate = useNavigate();
  const { user, loading } = useAuth();
  function handlePlay(slug) {
    if (user) {
      navigate({ to: "/jeux/$slug", params: { slug } });
    } else {
      navigate({ to: "/login" });
    }
  }
  function handleBotPlay(slug) {
    if (user) {
      navigate({ to: "/jeux/$slug", params: { slug } });
    } else {
      navigate({ to: "/login" });
    }
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-h-screen bg-background", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative overflow-hidden", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-gradient-to-br from-primary/10 via-background to-violet-500/5 pointer-events-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute -top-20 -right-20 w-64 h-64 rounded-full bg-primary/8 blur-3xl pointer-events-none" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative max-w-md mx-auto px-5 pt-6 pb-4", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between mb-5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(
            "button",
            {
              type: "button",
              onClick: () => navigate({ to: "/login" }),
              className: "w-9 h-9 rounded-full flex items-center justify-center bg-card/70 border border-border/50 text-muted-foreground hover:text-foreground transition-colors",
              children: /* @__PURE__ */ jsxRuntimeExports.jsx(ArrowLeft, { className: "w-4 h-4" })
            }
          ),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-black tracking-tight", children: "Jeux disponibles" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-xs text-muted-foreground mt-0.5", children: [
              ALL_GAMES.length,
              " jeux · Lalao MADA"
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-primary/10 border border-primary/20 px-4 py-3 flex items-start gap-3 mb-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Bot, { className: "w-5 h-5 text-primary flex-shrink-0 mt-0.5" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs font-bold text-primary leading-snug", children: "Mode bot disponible" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[11px] text-muted-foreground mt-0.5 leading-snug", children: [
              "Entraînez-vous contre notre IA avant d'affronter de vrais joueurs.",
              !user && !loading && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
                " ",
                /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => navigate({ to: "/login" }), className: "text-primary font-semibold hover:underline", children: "Connectez-vous" }),
                " pour jouer."
              ] })
            ] })
          ] })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "max-w-md mx-auto px-5 mb-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-3 gap-2", children: [
      { icon: Gamepad2, label: "Jeux", value: ALL_GAMES.length.toString() },
      { icon: Cpu, label: "Bots IA", value: ALL_GAMES.filter((g) => g.botSupported).length.toString() },
      { icon: Trophy, label: "Tournois", value: "Actifs" }
    ].map(({ icon: Icon, label, value }) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 p-3 text-center shadow-sm", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4 text-primary mx-auto mb-1" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-extrabold", children: value }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: label })
    ] }, label)) }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "max-w-md mx-auto px-5 pb-16 space-y-3", children: ALL_GAMES.map((game) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "div",
      {
        className: "rounded-3xl bg-card border border-border/40 overflow-hidden shadow-sm hover:border-primary/20 transition-all",
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-4 p-4", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-20 h-20 rounded-2xl flex-shrink-0 ring-2 ${game.ring} shadow-md overflow-hidden`, children: game.cover }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-2 mb-1", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-base", children: game.emoji }),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("h2", { className: "font-extrabold text-base leading-tight", children: game.name })
                ] }),
                /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `flex-shrink-0 text-[10px] font-bold px-2 py-0.5 rounded-full bg-gradient-to-r ${game.gradient} text-white shadow-sm`, children: game.tag })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground leading-snug mb-2", children: game.desc }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(OnlineCount, { slug: game.slug }),
                game.botSupported && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-0.5 text-[10px] font-semibold text-sky-400", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Cpu, { className: "w-3 h-3" }),
                  " Bot dispo"
                ] })
              ] })
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "border-t border-border/40 grid grid-cols-2 divide-x divide-border/40", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs(
              "button",
              {
                type: "button",
                onClick: () => handleBotPlay(game.slug),
                disabled: !game.botSupported,
                className: `flex items-center justify-center gap-2 py-3 text-xs font-bold transition-all ${game.botSupported ? "text-sky-400 hover:bg-sky-500/10 active:scale-95" : "text-muted-foreground/40 cursor-not-allowed"}`,
                children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Cpu, { className: "w-3.5 h-3.5" }),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: game.botSupported ? "Jouer vs Bot" : "Bientôt" }),
                  !game.botSupported && /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-3 h-3" })
                ]
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsxs(
              "button",
              {
                type: "button",
                onClick: () => handlePlay(game.slug),
                className: "flex items-center justify-center gap-2 py-3 text-xs font-bold text-primary hover:bg-primary/10 active:scale-95 transition-all",
                children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Swords, { className: "w-3.5 h-3.5" }),
                  "En ligne",
                  /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-3.5 h-3.5" })
                ]
              }
            )
          ] })
        ]
      },
      game.slug
    )) }),
    !user && !loading && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed bottom-0 left-0 right-0 bg-background/95 backdrop-blur border-t border-border/40 p-4 safe-area-bottom", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "max-w-md mx-auto flex gap-3 items-center", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs font-bold leading-tight", children: "Prêt à jouer ?" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[11px] text-muted-foreground", children: "Créez un compte gratuit pour commencer" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          type: "button",
          onClick: () => navigate({ to: "/login" }),
          className: "flex-shrink-0 flex items-center gap-2 px-5 py-2.5 rounded-2xl text-sm font-bold text-white shadow-md shadow-primary/20 active:scale-95 transition-all",
          style: { background: "linear-gradient(135deg, #ef4444 0%, #f97316 50%, #eab308 100%)" },
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Zap, { className: "w-4 h-4" }),
            "Commencer"
          ]
        }
      )
    ] }) })
  ] });
}
const $$splitComponentImporter$q = () => import("./login-CiNwJHTc.mjs");
const Route$B = createFileRoute("/login")({
  component: lazyRouteComponent($$splitComponentImporter$q, "component"),
  head: () => ({
    meta: [{
      title: "Connexion — Lalao MADA"
    }, {
      name: "description",
      content: "Connectez-vous ou créez un compte sur Lalao MADA, la plateforme #1 de jeux en ligne à Madagascar."
    }, {
      property: "og:title",
      content: "Connexion — Lalao MADA"
    }, {
      property: "og:description",
      content: "Rejoignez Lalao MADA : Ludo, Domino, Fanorona, Échecs, Poker, Rami — mises en Ariary."
    }]
  })
});
const $$splitComponentImporter$p = () => import("./reset-password-CeJrLDyI.mjs");
const Route$A = createFileRoute("/reset-password")({
  component: lazyRouteComponent($$splitComponentImporter$p, "component"),
  head: () => ({
    meta: [{
      title: "Réinitialiser le mot de passe — Lalao MADA"
    }]
  })
});
const $$splitComponentImporter$o = () => import("./admin-DLXVkhjo.mjs");
const Route$z = createFileRoute("/_authenticated/admin")({
  component: lazyRouteComponent($$splitComponentImporter$o, "component"),
  head: () => ({
    meta: [{
      title: "Admin — Lalao MADA"
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const $$splitComponentImporter$n = () => import("./admin-bug-reports-Cmf6K21E.mjs");
const Route$y = createFileRoute("/_authenticated/admin-bug-reports")({
  component: lazyRouteComponent($$splitComponentImporter$n, "component"),
  head: () => ({
    meta: [{
      title: "Signalements — Admin"
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const $$splitComponentImporter$m = () => import("./chat-DDsmACd_.mjs");
const Route$x = createFileRoute("/_authenticated/chat")({
  component: lazyRouteComponent($$splitComponentImporter$m, "component"),
  validateSearch: (s) => ({
    dm: typeof s.dm === "string" ? s.dm : void 0
  }),
  head: () => ({
    meta: [{
      title: "Discussion — Lalao MADA"
    }]
  })
});
function isAndroid(userAgent) {
  return /Android/i.test(userAgent);
}
function tryNativeBridge(url2, fallbackUrl) {
  const w = window;
  const payload = { type: "openExternal", url: url2, fallbackUrl };
  try {
    const bridgeNames = ["Android", "NativeBridge", "WebAppInterface", "LalaoMada"];
    const methodNames = ["openExternal", "openUrl", "openInBrowser", "openIntent", "launchIntent", "openApp"];
    for (const bridgeName of bridgeNames) {
      const bridge = w[bridgeName];
      if (!bridge) continue;
      for (const methodName of methodNames) {
        if (typeof bridge[methodName] === "function") {
          bridge[methodName](url2, fallbackUrl || "");
          return true;
        }
      }
    }
    if (w.ReactNativeWebView?.postMessage) {
      w.ReactNativeWebView.postMessage(JSON.stringify(payload));
      return true;
    }
    if (w.webkit?.messageHandlers?.openExternal?.postMessage) {
      w.webkit.messageHandlers.openExternal.postMessage(payload);
      return true;
    }
  } catch {
    return false;
  }
  return false;
}
function openWithAnchor(url2, target = "_top") {
  const a = document.createElement("a");
  a.href = url2;
  a.target = target;
  a.rel = "noopener noreferrer";
  a.style.display = "none";
  document.body.appendChild(a);
  a.click();
  window.setTimeout(() => a.remove(), 300);
}
function openWithHiddenFrame(url2) {
  try {
    const frame = document.createElement("iframe");
    frame.src = url2;
    frame.style.display = "none";
    frame.setAttribute("aria-hidden", "true");
    document.body.appendChild(frame);
    window.setTimeout(() => frame.remove(), 1200);
  } catch {
  }
}
function openNativeUrl(url2, target) {
  openWithHiddenFrame(url2);
  openWithAnchor(url2, target);
  try {
    window.location.assign(url2);
  } catch {
  }
}
function compactUrls(urls) {
  return urls.filter((url2, index, list) => Boolean(url2) && list.indexOf(url2) === index);
}
function openExternal({ webUrl, appUrl, androidIntent, androidIntents = [], nativeUrls = [], marketUrl, preferIntent, disableAndroidCascade }) {
  if (typeof window === "undefined") return;
  const ua = navigator.userAgent || "";
  const androidDevice = isAndroid(ua);
  const topTarget = window.top !== window.self ? "_top" : "_blank";
  if (androidDevice) {
    const intents = compactUrls([...androidIntents, androidIntent]);
    const candidates = preferIntent ? compactUrls([...intents, ...nativeUrls, appUrl, marketUrl, webUrl]) : compactUrls([appUrl, ...intents, ...nativeUrls, marketUrl, webUrl]);
    const primary = candidates[0] || webUrl;
    const fallback = marketUrl || webUrl;
    if (disableAndroidCascade) {
      openWithAnchor(primary, "_self");
      window.setTimeout(() => {
        try {
          window.location.href = primary;
        } catch {
        }
      }, 50);
      return;
    }
    const bridgeTried = tryNativeBridge(primary, fallback);
    if (!bridgeTried) {
      openWithHiddenFrame(primary);
      openWithAnchor(primary, "_top");
    }
    if (!disableAndroidCascade) {
      candidates.slice(1, 4).forEach((url2, i) => {
        window.setTimeout(() => {
          if (document.visibilityState === "visible") openWithAnchor(url2, "_top");
        }, 300 + i * 500);
      });
      window.setTimeout(() => {
        if (document.visibilityState === "visible" && fallback && !candidates.slice(0, 4).includes(fallback)) {
          openWithAnchor(fallback, "_top");
        }
      }, 2200);
    }
    return;
  }
  const nativeTarget = appUrl || webUrl;
  if (!tryNativeBridge(nativeTarget, webUrl)) openNativeUrl(nativeTarget, topTarget);
  window.setTimeout(() => {
    if (document.visibilityState === "visible") {
      const opened = window.open(webUrl, "_blank", "noopener,noreferrer");
      if (!opened) openWithAnchor(webUrl, window.top !== window.self ? "_top" : "_blank");
    }
  }, 1200);
}
function whatsappTargets(phone) {
  const number = phone.replace(/\D/g, "");
  const marketUrl = "market://details?id=com.whatsapp";
  return {
    webUrl: `https://api.whatsapp.com/send?phone=${number}`,
    appUrl: `whatsapp://send?phone=${number}`,
    androidIntent: `intent://send?phone=${number}#Intent;scheme=whatsapp;package=com.whatsapp;action=android.intent.action.VIEW;S.browser_fallback_url=${encodeURIComponent(marketUrl)};end`,
    marketUrl
  };
}
function facebookTargets(url2) {
  const normalizedUrl = /^https?:\/\//i.test(url2) ? url2.trim() : `https://www.facebook.com/${url2.trim().replace(/^@/, "")}`;
  const webUrl = normalizedUrl.replace(/^https?:\/\/(?:m\.|mobile\.|web\.|www\.)?facebook\.com/i, "https://www.facebook.com").replace(/^https?:\/\/fb\.com/i, "https://www.facebook.com");
  let exactProfileUrl = webUrl;
  try {
    const parsed = new URL(webUrl);
    parsed.protocol = "https:";
    parsed.hostname = "www.facebook.com";
    exactProfileUrl = parsed.toString();
  } catch {
    exactProfileUrl = `https://www.facebook.com/${url2.trim().replace(/^@/, "").replace(/^\/+/, "")}`;
  }
  const profilePath = (() => {
    try {
      return new URL(exactProfileUrl).pathname.replace(/^\/+|\/+$/g, "");
    } catch {
      return url2.trim().replace(/^@/, "").replace(/^\/+/, "");
    }
  })();
  const postTarget = (() => {
    try {
      const parsed = new URL(exactProfileUrl);
      const parts = parsed.pathname.split("/").filter(Boolean);
      const postsIndex = parts.findIndex((part) => part.toLowerCase() === "posts");
      const ownerId = postsIndex > 0 ? parts[postsIndex - 1] : parsed.searchParams.get("id") || "";
      const postId = postsIndex >= 0 ? parts[postsIndex + 1] : parsed.searchParams.get("story_fbid") || "";
      if (!ownerId || !postId) return null;
      const storyUrl = new URL("https://www.facebook.com/story.php");
      storyUrl.searchParams.set("story_fbid", postId);
      storyUrl.searchParams.set("id", ownerId);
      const nativeProfileUrl2 = `fb://profile/${ownerId}`;
      const nativePostUrl = `fb://post/${postId}`;
      const nativeWebUrl = `fb://facewebmodal/f?href=${encodeURIComponent(storyUrl.toString())}`;
      return {
        webUrl: storyUrl.toString(),
        appUrl: nativeProfileUrl2,
        nativeUrls: [
          nativeProfileUrl2,
          nativePostUrl,
          nativeWebUrl
        ]
      };
    } catch {
      return null;
    }
  })();
  if (postTarget) {
    return {
      ...postTarget,
      preferIntent: false,
      disableAndroidCascade: true
    };
  }
  const directProfileId = (() => {
    try {
      const parsed = new URL(exactProfileUrl);
      if (parsed.pathname.replace(/^\/+|\/+$/g, "").toLowerCase() === "profile.php") {
        return parsed.searchParams.get("id") || "";
      }
      return "";
    } catch {
      return "";
    }
  })();
  if (directProfileId) {
    const nativeProfileUrl2 = `fb://profile/${directProfileId}`;
    return {
      webUrl: exactProfileUrl,
      appUrl: nativeProfileUrl2,
      nativeUrls: [nativeProfileUrl2, `fb://facewebmodal/f?href=${encodeURIComponent(exactProfileUrl)}`],
      preferIntent: false,
      disableAndroidCascade: true
    };
  }
  const knownProfileIds = {
    "rjean.pierrit": "100060433585093"
  };
  const profileId = knownProfileIds[profilePath.toLowerCase()];
  const nativeProfileUrl = profileId ? `fb://profile/${profileId}` : `fb://facewebmodal/f?href=${encodeURIComponent(exactProfileUrl)}`;
  return {
    webUrl: exactProfileUrl,
    appUrl: nativeProfileUrl,
    nativeUrls: [nativeProfileUrl],
    preferIntent: false,
    disableAndroidCascade: true
  };
}
function SupportChatPopup({ onClose }) {
  const [message, setMessage] = reactExports.useState("");
  const [sending, setSending] = reactExports.useState(false);
  const [history, setHistory] = reactExports.useState([]);
  const [loadingHistory, setLoadingHistory] = reactExports.useState(true);
  const loadHistory = async () => {
    setLoadingHistory(true);
    try {
      const { data } = await supabase.rpc("my_support_messages", { _limit: 20 });
      setHistory(data || []);
    } finally {
      setLoadingHistory(false);
    }
  };
  reactExports.useEffect(() => {
    loadHistory();
  }, []);
  const send = async () => {
    const trimmed = message.trim();
    if (trimmed.length < 5) return toast.error("Message trop court (5 caractères minimum)");
    setSending(true);
    try {
      const { data: userRes } = await supabase.auth.getUser();
      const uid = userRes.user?.id;
      if (!uid) throw new Error("Non authentifié");
      const { error } = await supabase.from("support_messages").insert({
        user_id: uid,
        message: trimmed
      });
      if (error) throw error;
      toast.success("Message envoyé à l'équipe !");
      setMessage("");
      await loadHistory();
    } catch (e) {
      toast.error(e?.message || "Erreur lors de l'envoi");
    } finally {
      setSending(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      className: "fixed inset-0 z-[70] bg-black/50 flex items-end sm:items-center justify-center p-4",
      onClick: onClose,
      children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "div",
        {
          className: "bg-card rounded-3xl w-full max-w-sm max-h-[85vh] flex flex-col shadow-2xl",
          onClick: (e) => e.stopPropagation(),
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between p-5 pb-3 shrink-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 font-bold text-lg", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-5 h-5 text-primary" }),
                " Support chat"
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: onClose, "aria-label": "Fermer", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-5 h-5" }) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 overflow-y-auto px-5 space-y-3", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: "Écrivez votre message, notre équipe vous répondra directement ici." }),
              loadingHistory ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-4", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin text-muted-foreground" }) }) : history.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-2.5", children: history.map((m) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/50 p-3 space-y-2", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex items-start justify-between gap-2", children: /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm whitespace-pre-wrap break-words", children: m.message }) }),
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 text-[10px] text-muted-foreground", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3 h-3" }),
                  new Date(m.created_at).toLocaleString("fr-FR", {
                    day: "2-digit",
                    month: "2-digit",
                    hour: "2-digit",
                    minute: "2-digit"
                  })
                ] }),
                m.reply ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-primary/10 border border-primary/20 p-2.5 text-sm", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 text-[10px] font-bold text-primary mb-1", children: [
                    /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-3 h-3" }),
                    " Réponse de l'équipe"
                  ] }),
                  /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "whitespace-pre-wrap break-words", children: m.reply })
                ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 text-[10px] text-amber-600 dark:text-amber-400", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-3 h-3 animate-spin" }),
                  " En attente de réponse…"
                ] })
              ] }, m.id)) })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "p-5 pt-3 shrink-0 space-y-2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(
                "textarea",
                {
                  value: message,
                  onChange: (e) => setMessage(e.target.value),
                  placeholder: "Décrivez votre problème ou question…",
                  rows: 3,
                  className: "w-full px-3.5 py-2.5 rounded-xl bg-secondary/40 border border-border/40 text-sm outline-none focus:ring-2 ring-primary/40 placeholder:text-muted-foreground/40 resize-none"
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsxs(
                "button",
                {
                  onClick: send,
                  disabled: sending || message.trim().length < 5,
                  className: "w-full py-3 rounded-xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 disabled:opacity-40 transition flex items-center justify-center gap-2",
                  children: [
                    sending ? /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-4 h-4 animate-spin" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4" }),
                    "Envoyer"
                  ]
                }
              )
            ] })
          ]
        }
      )
    }
  );
}
const cache = /* @__PURE__ */ new Map();
function useCmsContent(key, fallback) {
  const [data, setData] = reactExports.useState(() => cache.get(key) ?? fallback);
  const [loaded, setLoaded] = reactExports.useState(cache.has(key));
  reactExports.useEffect(() => {
    let cancelled = false;
    supabase.from("cms_content").select("content").eq("key", key).maybeSingle().then(({ data: row }) => {
      if (cancelled) return;
      const content = row?.content;
      if (content) {
        cache.set(key, content);
        setData(content);
      }
      setLoaded(true);
    });
    return () => {
      cancelled = true;
    };
  }, [key]);
  return { data, loaded };
}
function invalidateCmsCache(key) {
  if (key) cache.delete(key);
  else cache.clear();
}
const REWARD_PER_ACTIVE_AR = 100;
const MIN_DEPOSIT_AR = 500;
const MIN_MATCHES = 10;
const MIN_STAKE_AR = 200;
const REFERRAL_TIERS = [
  { count: 5, reward: 500, label: "Bronze", icon: "🥉" },
  { count: 10, reward: 1e3, label: "Argent", icon: "🥈" },
  { count: 20, reward: 2e3, label: "Or", icon: "🥇" },
  { count: 50, reward: 5e3, label: "Diamant", icon: "💎" }
];
const REFERRAL_META_DESCRIPTION_TEMPLATE = "Invitez vos amis sur Lalao MADA : {reward} Ar pour chaque filleul actif (téléphone vérifié, dépôt ≥ {min_deposit} Ar, 10 matchs avec mise ≥ {min_stake} Ar).";
function referralMetaDescription() {
  return REFERRAL_META_DESCRIPTION_TEMPLATE.replace("{reward}", String(REWARD_PER_ACTIVE_AR)).replace("{min_deposit}", String(MIN_DEPOSIT_AR)).replace("{min_stake}", String(MIN_STAKE_AR));
}
function referralConditions() {
  return [
    `Le filleul doit vérifier son numéro de téléphone par OTP.`,
    `Le filleul doit effectuer un dépôt minimum de ${MIN_DEPOSIT_AR} Ar.`,
    `Le filleul doit jouer au moins ${MIN_MATCHES} matchs avec une mise réelle (minimum ${MIN_STAKE_AR} Ar par match).`,
    `Les matchs annulés ou suspects ne sont pas comptabilisés.`,
    `La récompense de ${REWARD_PER_ACTIVE_AR} Ar est crédité automatiquement dès que toutes les conditions sont remplies.`,
    `Un numéro de téléphone ne peut être lié qu'à un seul compte.`,
    `L'auto-parrainage est strictement interdit.`,
    `Toute tentative de fraude entraîne la suspension immédiate des récompenses.`,
    `Lalao MADA se réserve le droit de modifier ou suspendre ce programme à tout moment.`
  ];
}
function referralShortAnswer() {
  return `Partagez le lien de l'application et votre code depuis la page 'Parrainage'. Vous recevez ${REWARD_PER_ACTIVE_AR} Ar dès que votre filleul a vérifié son téléphone, effectué un dépôt ≥ ${MIN_DEPOSIT_AR} Ar et joué ${MIN_MATCHES} matchs avec une mise ≥ ${MIN_STAKE_AR} Ar.`;
}
const DEFAULT_FAQ = {
  categories: [
    /* ─────────────────────────────────────────── */
    {
      category: "💰 Dépôts & Retraits",
      items: [
        {
          q: "Comment déposer de l'argent ?",
          a: "Touchez le bouton solde « + » en haut de l'écran (à côté de votre solde), puis « Dépôt ». Entrez le montant, choisissez votre opérateur Mobile Money (MVola, Orange Money, Airtel Money), puis envoyez le transfert au numéro admin affiché. Votre solde est crédité après validation manuelle par l'admin."
        },
        {
          q: "Combien de temps prend la validation d'un dépôt ?",
          a: "La validation est manuelle. En général, votre solde est crédité en quelques minutes après l'envoi du Mobile Money. Si votre dépôt n'est pas validé après 1 heure, contactez le support via le chat."
        },
        {
          q: "Comment retirer mes gains ?",
          a: "Touchez le bouton solde « + » en haut de l'écran, puis « Retrait ». Entrez le montant et votre numéro Mobile Money. L'admin traite les demandes manuellement ; le solde est débité dès l'acceptation et le transfert envoyé à votre numéro."
        },
        {
          q: "Où voir l'historique de mes dépôts et retraits ?",
          a: "Allez sur votre profil → touchez « Dépôts » ou « Retraits » dans la grille du menu. Une fenêtre s'ouvre avec la liste de vos dernières transactions."
        },
        {
          q: "Y a-t-il un montant minimum pour déposer ou retirer ?",
          a: "Le montant minimum de dépôt est de 500 Ar. Le montant minimum de retrait est de 1 000 Ar. Il n'y a pas de maximum, mais les gros retraits peuvent nécessiter une vérification supplémentaire."
        },
        {
          q: "Quels opérateurs Mobile Money sont acceptés ?",
          a: "Nous acceptons MVola, Orange Money et Airtel Money. Assurez-vous d'utiliser un numéro enregistré à votre nom pour éviter les retards de validation."
        },
        {
          q: "Mon dépôt n'est pas validé, que faire ?",
          a: "Vérifiez d'abord que vous avez bien envoyé le transfert au bon numéro admin affiché dans le formulaire de dépôt. Si tout est correct, contactez le support via le chat en indiquant le montant, l'heure du transfert et la référence Mobile Money. Un admin vérifiera et créditera votre solde."
        }
      ]
    },
    /* ─────────────────────────────────────────── */
    {
      category: "🎮 Jeux & Matchs",
      items: [
        {
          q: "Quels jeux sont disponibles ?",
          a: "Lalao MADA propose 5 jeux : Ludo, Domino, Fanorona, Rami (jeux de cartes) et Échecs. De nouveaux jeux seront ajoutés régulièrement."
        },
        {
          q: "Comment créer une partie ?",
          a: "Allez dans la section « Jeux », choisissez le jeu, puis « Nouvelle partie ». Vous pouvez définir la mise (stake) et inviter des joueurs ou ouvrir la partie au public."
        },
        {
          q: "Comment rejoindre une partie ?",
          a: "Allez dans « Jeux », choisissez un jeu, puis parcourez la liste des parties ouvertes dans le lobby. Touchez une partie pour la rejoindre si elle a de la place et que vous avez suffisamment de solde pour la mise."
        },
        {
          q: "Que se passe-t-il si je quitte une partie en cours ?",
          a: "Si vous quitte une partie en cours, vous perdez automatiquement votre mise. La partie continue avec les autres joueurs. En cas de déconnexion involontaire (réseau), vous avez un court délai pour vous reconnecter avant d'être éliminé."
        },
        {
          q: "Puis-je jouer contre des bots ?",
          a: "Oui, le Ludo propose des parties contre des bots. Les autres jeux sont actuellement en joueur contre joueur uniquement."
        },
        {
          q: "Comment fonctionnent les tournois ?",
          a: "Les tournois sont organisés par l'admin. Consultez la section « Tournois » pour voir les tournois à venir et en cours. Les inscriptions peuvent être limitées selon le nombre de participants et le niveau."
        },
        {
          q: "Où voir les parties en direct ?",
          a: "Allez dans la section « Direct » (Live) pour voir les parties en cours. Vous pouvez suivre les matchs des autres joueurs en temps réel."
        }
      ]
    },
    /* ─────────────────────────────────────────── */
    {
      category: "👤 Compte & Profil",
      items: [
        {
          q: "Comment parrainer un ami ?",
          a: "__REFERRAL_SHORT__"
        },
        {
          q: "Comment fonctionne la page profil ?",
          a: "Votre profil est organisé en 4 sections : 1) En-tête avec votre avatar, pseudo, badge et solde. 2) Statistiques (parties, victoires, défaites, taux de victoire, rang). 3) Jeux favoris et succès. 4) Menu d'actions rapides (dépôts, retraits, parties, parrainage, sécurité, aide, paramètres, téléphone) avec déconnexion et suppression en bas."
        },
        {
          q: "Comment changer mon pseudo ?",
          a: "Sur votre profil, touchez votre pseudo en haut de la page. Vous pouvez le modifier et valider en touchant « OK ». Le pseudo doit être unique."
        },
        {
          q: "Comment changer ma photo de profil ?",
          a: "Sur votre profil, touchez l'icône appareil photo en bas à droite de votre avatar. Choisissez une image depuis votre téléphone. Elle est automatiquement compressée et uploadée."
        },
        {
          q: "Comment vérifier mon numéro de téléphone ?",
          a: "La vérification se fait lors de l'inscription par code OTP (6 chiffres envoyés par SMS). Si vous n'avez pas vérifié votre numéro, le statut « Non vérifié » s'affiche sur votre profil. Touchez le bouton « Téléphone » dans le menu pour voir le statut."
        },
        {
          q: "Comment supprimer mon compte ?",
          a: "Sur votre profil, touchez « Sécurité » dans le menu (ou « Supprimer » en bas de la page). La suppression est définitive : vous perdez votre solde, votre historique et vos statistiques. Cette action est irréversible."
        },
        {
          q: "Que signifient les badges (Bronze, Or, Diamant…) ?",
          a: "Les badges représentent votre niveau de joueur. Ils sont basés sur votre niveau (déterminé par vos parties et victoires). Bronze (niveau 1), Argent (2), Or (3), Diamant (4), Platine (5+). Le badge est affiché en bandeau coloré en haut de votre profil."
        },
        {
          q: "C'est quoi la série quotidienne (streak) ?",
          a: "La série quotidienne (flame 🔥) compte le nombre de jours consécutifs où vous êtes actif sur l'app. Jouez au moins une partie par jour pour maintenir votre série ! Elle est affichée à côté de votre badge sur le profil."
        },
        {
          q: "Que montre la stat « Rang » ?",
          a: "Votre rang est votre position dans le classement global, basé sur le nombre de victoires. Si vous n'êtes pas encore classé, « — » s'affiche. Le rang se met à jour automatiquement."
        }
      ]
    },
    /* ─────────────────────────────────────────── */
    {
      category: "🏆 Classement & Succès",
      items: [
        {
          q: "Comment fonctionne le classement ?",
          a: "Le classement est basé sur le nombre total de victoires. Plus vous gagnez, plus vous montez. Consultez la section « Classement » pour voir votre rang et les meilleurs joueurs."
        },
        {
          q: "Comment débloquer des succès ?",
          a: "Les succès se débloquent automatiquement : 🏆 1er dépôt (effectuer un premier dépôt), 🔥 10 victoires (remporter 10 matchs), 👑 100 parties (jouer 100 matchs), ⭐ Parrain (parrainer un ami actif). D'autres succès seront ajoutés. Les succès sont affichés sur votre profil."
        },
        {
          q: "Où voir mes statistiques de jeu ?",
          a: "Sur votre profil, la 2e section « Stats » affiche votre nombre de parties, victoires, défaites, taux de victoire et votre rang. La section « Jeux favoris » montre combien de parties vous avez joué pour chaque jeu (Ludo, Domino, Fanorona, Rami, Échecs)."
        },
        {
          q: "Où voir mon historique de parties ?",
          a: "Sur votre profil, touchez « Parties » dans le menu. Une fenêtre s'ouvre avec vos dernières transactions de jeu (mises, gains, remboursements)."
        }
      ]
    },
    /* ─────────────────────────────────────────── */
    {
      category: "🔒 Sécurité & Règles",
      items: [
        {
          q: "Mes données sont-elles en sécurité ?",
          a: "Vos données sont stockées de manière sécurisée. Votre numéro de téléphone n'est visible que par vous et l'admin. Vos transactions sont privées. Nous ne partageons jamais vos informations avec des tiers."
        },
        {
          q: "Puis-je avoir plusieurs comptes ?",
          a: "Non. Un numéro de téléphone ne peut être lié qu'à un seul compte. Toute tentative de créer plusieurs comptes entraîne la suspension de tous les comptes associés."
        },
        {
          q: "Que se passe-t-il en cas de triche ou de fraude ?",
          a: "Toute triche, exploitation de bugs, ou fraude (y compris l'auto-parrainage) entraîne la suspension immédiate du compte et la confiscation des gains. Les matchs suspects sont annulés et les mises remboursées aux joueurs légitimes."
        },
        {
          q: "Que faire si quelqu'un triche dans une partie ?",
          a: "Signalez-le immédiatement au support via le chat avec le maximum de détails (jeu, adversaire, description du problème). Notre équipe vérifiera et prendra les mesures nécessaires."
        },
        {
          q: "Comment sont calculées les mises ?",
          a: "Chaque partie a une mise fixée par le créateur. Les gagnants reçoivent les mises des perdants (déduction faite des frais éventuels). Le solde est mis à jour automatiquement à la fin de la partie."
        },
        {
          q: "L'application est-elle gratuite ?",
          a: "L'inscription et la navigation sont gratuites. Vous jouez avec votre solde (alimenté par dépôts Mobile Money ou récompenses de parrainage). Aucun abonnement n'est requis."
        }
      ]
    },
    /* ─────────────────────────────────────────── */
    {
      category: "💬 Chat & Support",
      items: [
        {
          q: "Comment contacter le support ?",
          a: "Touchez le bouton de contact flottant (en bas à droite) pour accéder au WhatsApp, Facebook, email et téléphone admin. Vous pouvez aussi ouvrir le chat intégré depuis le menu."
        },
        {
          q: "Comment signaler un bug ?",
          a: "Utilisez le bouton « Signaler un bug » (icône insecte) disponible dans l'app. Décrivez le problème avec le maximum de détails pour aider notre équipe à le corriger rapidement."
        },
        {
          q: "Où trouver les tutoriels ?",
          a: "Allez dans la section « Tutoriels » du menu. Des guides sont disponibles pour chaque jeu (Ludo, Domino, Fanorona, Rami, Échecs) pour apprendre les règles et stratégies."
        },
        {
          q: "Comment changer la langue de l'application ?",
          a: "Allez sur votre profil → touchez « Paramètres » dans le menu. Une fenêtre s'ouvre avec le sélecteur de langue : Français 🇫🇷, Malagasy 🇲🇬, English 🇬🇧."
        },
        {
          q: "Comment changer le thème (clair/sombre) ?",
          a: "Allez sur votre profil → touchez « Paramètres » dans le menu. Une fenêtre s'ouvre avec un toggle pour passer du mode clair au mode sombre et inversement."
        },
        {
          q: "Où voir le numéro de l'admin ?",
          a: "Touchez le bouton de contact flottant en bas à droite de l'écran. Le numéro admin s'y trouve s'il a été configuré. Vous pouvez aussi l'appeler directement depuis la page d'aide."
        }
      ]
    }
  ]
};
function resolveFaqAnswer(a) {
  if (a.includes("__REFERRAL_SHORT__")) {
    return a.replace(/__REFERRAL_SHORT__/g, referralShortAnswer());
  }
  return a;
}
const Route$w = createFileRoute("/_authenticated/faq")({
  component: FaqPage,
  head: () => ({ meta: [{ title: "Centre d'aide — Lalao MADA" }] })
});
function FaqItem({ q, a }) {
  const [open, setOpen] = reactExports.useState(false);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `border-b border-border/40 last:border-0 transition-colors ${open ? "bg-accent/30" : ""}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => setOpen(!open),
        className: "w-full flex items-start justify-between gap-3 p-4 text-left",
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-semibold text-sm leading-snug", children: q }),
          open ? /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronUp, { className: "w-4 h-4 text-muted-foreground shrink-0 mt-0.5" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronDown, { className: "w-4 h-4 text-muted-foreground shrink-0 mt-0.5" })
        ]
      }
    ),
    open && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 pb-4 text-sm text-muted-foreground leading-relaxed", children: a })
  ] });
}
function FaqPage() {
  const { t } = useT();
  const navigate = useNavigate();
  const [search, setSearch] = reactExports.useState("");
  const [adminPhone, setAdminPhone] = reactExports.useState(null);
  const [tutoUrl, setTutoUrl] = reactExports.useState(null);
  const [showSupportChat, setShowSupportChat] = reactExports.useState(false);
  const { data: faq } = useCmsContent("faq", DEFAULT_FAQ);
  reactExports.useEffect(() => {
    supabase.from("settings").select("admin_phone").maybeSingle().then(({ data }) => {
      if (data?.admin_phone) setAdminPhone(data.admin_phone);
    });
    supabase.from("app_settings").select("tuto_url").eq("id", 1).maybeSingle().then(({ data }) => {
      if (data?.tuto_url) setTutoUrl(data.tuto_url);
    });
  }, []);
  const items = (faq?.categories ?? []).map((cat) => ({
    ...cat,
    items: cat.items.map((it) => ({ q: it.q, a: resolveFaqAnswer(it.a) }))
  }));
  const filtered = search.trim() ? items.map((cat) => ({
    ...cat,
    items: cat.items.filter(
      (item) => item.q.toLowerCase().includes(search.toLowerCase()) || item.a.toLowerCase().includes(search.toLowerCase())
    )
  })).filter((cat) => cat.items.length > 0) : items;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-2xl mx-auto px-4 py-5 space-y-4", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(CircleQuestionMark, { className: "w-6 h-6 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-2xl font-extrabold", children: "Centre d'aide" })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "input",
        {
          value: search,
          onChange: (e) => setSearch(e.target.value),
          placeholder: "Rechercher une question…",
          className: "w-full pl-4 pr-10 py-3 rounded-2xl bg-card border border-border/60 shadow-sm outline-none text-sm"
        }
      ),
      search && /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => setSearch(""),
          className: "absolute right-3 top-1/2 -translate-y-1/2 text-muted-foreground hover:text-foreground",
          children: "×"
        }
      )
    ] }),
    filtered.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center text-muted-foreground py-12", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(CircleQuestionMark, { className: "w-10 h-10 mx-auto mb-3 opacity-30" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm", children: [
        "Aucun résultat pour « ",
        search,
        " »"
      ] })
    ] }) : filtered.map((cat) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card shadow-sm border border-border/40 overflow-hidden", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "px-4 py-3 bg-accent/50 font-bold text-sm border-b border-border/40", children: cat.category }),
      cat.items.map((item) => /* @__PURE__ */ jsxRuntimeExports.jsx(FaqItem, { q: item.q, a: item.a }, item.q))
    ] }, cat.category)),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-gradient-to-br from-primary/10 to-primary/5 border border-primary/20 p-5 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-base flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-5 h-5 text-primary" }),
        " Vous n'avez pas trouvé votre réponse ?"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground", children: "Notre équipe est disponible pour vous aider directement." }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => setShowSupportChat(true),
            className: "flex items-center justify-center gap-2 py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition-transform",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(MessageSquare, { className: "w-4 h-4" }),
              " Support chat"
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => {
              if (tutoUrl) {
                const target = facebookTargets(tutoUrl);
                openExternal(target);
              } else {
                navigate({ to: "/tutos", search: {} });
              }
            },
            className: "flex items-center justify-center gap-2 py-3 rounded-2xl bg-secondary font-bold text-sm active:scale-95 transition-transform",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(BookOpen, { className: "w-4 h-4" }),
              " Tutoriels"
            ]
          }
        )
      ] })
    ] }),
    showSupportChat && /* @__PURE__ */ jsxRuntimeExports.jsx(SupportChatPopup, { onClose: () => setShowSupportChat(false) })
  ] });
}
const Route$v = createFileRoute("/_authenticated/history")({
  component: HistoryPage,
  head: () => ({ meta: [
    { title: "Finance & Historique — Lalao MADA" },
    { name: "description", content: "Suivi de vos dépôts, retraits et transactions en temps réel." }
  ] })
});
function fmtDate(d) {
  return new Date(d).toLocaleString("fr-FR", {
    day: "2-digit",
    month: "2-digit",
    year: "2-digit",
    hour: "2-digit",
    minute: "2-digit"
  });
}
function fmtAr(n) {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-MG").format(Math.round(Number(n) || 0)) + " Ar";
}
function relTime(d) {
  const diff = (Date.now() - new Date(d).getTime()) / 1e3;
  if (diff < 60) return "à l'instant";
  if (diff < 3600) return `il y a ${Math.floor(diff / 60)} min`;
  if (diff < 86400) return `il y a ${Math.floor(diff / 3600)} h`;
  return `il y a ${Math.floor(diff / 86400)} j`;
}
const TXKind = {
  game_win: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), label: "Gain de partie", color: "text-emerald-600" },
  game_loss: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleX, { className: "w-4 h-4" }), label: "Pari perdu", color: "text-rose-500" },
  game_stake: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-4 h-4" }), label: "Mise de partie", color: "text-rose-400" },
  daily_bonus: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gift, { className: "w-4 h-4" }), label: "Bonus quotidien", color: "text-amber-500" },
  signup_bonus: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gift, { className: "w-4 h-4" }), label: "Bonus inscription", color: "text-amber-500" },
  referral: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Flame, { className: "w-4 h-4" }), label: "Commission parrainage", color: "text-orange-500" },
  deposit: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowDown, { className: "w-4 h-4" }), label: "Dépôt", color: "text-emerald-600" },
  withdrawal: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowUp, { className: "w-4 h-4" }), label: "Retrait", color: "text-rose-500" },
  tournament_win: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4" }), label: "Gain tournoi", color: "text-amber-600" },
  refund: { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ReceiptText, { className: "w-4 h-4" }), label: "Remboursement", color: "text-blue-500" }
};
function txConfig(kind) {
  return TXKind[kind] ?? { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ReceiptText, { className: "w-4 h-4" }), label: kind, color: "text-muted-foreground" };
}
function StatusBadge({ status }) {
  const cfg = {
    pending: { cls: "bg-amber-100 text-amber-700 border-amber-300", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-2.5 h-2.5" }), label: "En attente" },
    approved: { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-2.5 h-2.5" }), label: "Approuvé" },
    completed: { cls: "bg-emerald-100 text-emerald-700 border-emerald-300", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-2.5 h-2.5" }), label: "Terminé" },
    rejected: { cls: "bg-rose-100 text-rose-600 border-rose-300", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Ban, { className: "w-2.5 h-2.5" }), label: "Refusé" },
    cancelled: { cls: "bg-secondary text-muted-foreground border-border", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Ban, { className: "w-2.5 h-2.5" }), label: "Annulé" }
  };
  const c = cfg[status] ?? { cls: "bg-secondary text-muted-foreground border-border", icon: null, label: status };
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: `inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-[10px] font-bold border ${c.cls}`, children: [
    c.icon,
    c.label
  ] });
}
function HistoryPage() {
  const { user } = useAuth();
  const [tab, setTab] = reactExports.useState("pending");
  const [statusFilter, setStatusFilter] = reactExports.useState("all");
  const [tx, setTx] = reactExports.useState([]);
  const [deps, setDeps] = reactExports.useState([]);
  const [withs, setWiths] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(true);
  async function load() {
    if (!user) {
      setLoading(false);
      return;
    }
    const [t, d, w] = await Promise.allSettled([
      supabase.from("transactions").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(200),
      supabase.from("deposits").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(100),
      supabase.from("withdrawals").select("*").eq("user_id", user.id).order("created_at", { ascending: false }).limit(100)
    ]);
    setTx(t.status === "fulfilled" ? t.value.data || [] : []);
    setDeps(d.status === "fulfilled" ? d.value.data || [] : []);
    setWiths(w.status === "fulfilled" ? w.value.data || [] : []);
    setLoading(false);
  }
  reactExports.useEffect(() => {
    let dt;
    const debouncedLoad = () => {
      clearTimeout(dt);
      dt = setTimeout(load, 800);
    };
    setLoading(true);
    load();
    if (!user) return;
    const ch = supabase.channel(`finance:${user.id}`).on("postgres_changes", { event: "*", schema: "public", table: "deposits", filter: `user_id=eq.${user.id}` }, debouncedLoad).on("postgres_changes", { event: "*", schema: "public", table: "withdrawals", filter: `user_id=eq.${user.id}` }, debouncedLoad).on("postgres_changes", { event: "*", schema: "public", table: "transactions", filter: `user_id=eq.${user.id}` }, debouncedLoad).subscribe();
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
    };
  }, [user?.id]);
  const pendingDeps = reactExports.useMemo(() => deps.filter((d) => (d.status ?? "pending") === "pending"), [deps]);
  const pendingWiths = reactExports.useMemo(() => withs.filter((w) => (w.status ?? "pending") === "pending"), [withs]);
  const totalDeposited = deps.filter((d) => d.status === "approved").reduce((s, d) => s + Number(d.amount_ar ?? d.amount ?? 0), 0);
  const totalWithdrawn = withs.filter((w) => w.status === "approved").reduce((s, w) => s + Number(w.amount_ar ?? w.amount ?? 0), 0);
  const pendingDepAmt = pendingDeps.reduce((s, d) => s + Number(d.amount_ar ?? d.amount ?? 0), 0);
  const pendingWithAmt = pendingWiths.reduce((s, w) => s + Number(w.amount_ar ?? w.amount ?? 0), 0);
  const totalPending = pendingDeps.length + pendingWiths.length;
  const filteredDeps = statusFilter === "all" ? deps : deps.filter((d) => (d.status ?? "pending") === statusFilter);
  const filteredWiths = statusFilter === "all" ? withs : withs.filter((w) => (w.status ?? "pending") === statusFilter);
  const tabs = [
    { id: "pending", label: "En attente", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-4 h-4" }), count: totalPending, badge: totalPending > 0 },
    { id: "deposits", label: "Dépôts", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowDown, { className: "w-4 h-4" }), count: deps.length },
    { id: "withdrawals", label: "Retraits", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowUp, { className: "w-4 h-4" }), count: withs.length },
    { id: "transactions", label: "Mouvements", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(ReceiptText, { className: "w-4 h-4" }), count: tx.length }
  ];
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-2xl mx-auto px-3 py-3 space-y-3 pb-24", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold flex items-center gap-2", children: "💰 Finance" }),
      totalPending > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[11px] font-bold bg-amber-100 text-amber-700 border border-amber-300 animate-pulse", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-3 h-3" }),
        " ",
        totalPending,
        " en attente"
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl p-3 bg-gradient-to-br from-emerald-500 to-emerald-600 text-white shadow-lg", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-[11px] font-semibold opacity-90", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowDown, { className: "w-3.5 h-3.5" }),
          " Total déposé"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold tabular-nums mt-1 leading-tight", children: fmtAr(totalDeposited) }),
        pendingDepAmt > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] mt-1 opacity-90 flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-2.5 h-2.5" }),
          " ",
          fmtAr(pendingDepAmt),
          " en attente"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl p-3 bg-gradient-to-br from-rose-500 to-rose-600 text-white shadow-lg", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-[11px] font-semibold opacity-90", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowUp, { className: "w-3.5 h-3.5" }),
          " Total retiré"
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold tabular-nums mt-1 leading-tight", children: fmtAr(totalWithdrawn) }),
        pendingWithAmt > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] mt-1 opacity-90 flex items-center gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Hourglass, { className: "w-2.5 h-2.5" }),
          " ",
          fmtAr(pendingWithAmt),
          " en attente"
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 bg-card/80 p-1 rounded-2xl shadow-sm border border-white/8 overflow-x-auto", children: tabs.map((t) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => setTab(t.id),
        className: `relative flex-1 min-w-[80px] flex items-center justify-center gap-1 py-2.5 rounded-xl text-[11px] font-bold transition-all whitespace-nowrap ${tab === t.id ? "bg-primary text-primary-foreground shadow-md shadow-primary/20" : "text-muted-foreground hover:text-foreground"}`,
        children: [
          t.icon,
          " ",
          t.label,
          t.count > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] px-1.5 py-0.5 rounded-full ${tab === t.id ? "bg-white/25" : t.badge ? "bg-amber-500 text-white" : "bg-white/8"}`, children: t.count })
        ]
      },
      t.id
    )) }),
    (tab === "deposits" || tab === "withdrawals") && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 text-[11px]", children: [
      { id: "all", label: "Tous" },
      { id: "pending", label: "En attente" },
      { id: "approved", label: "Approuvés" },
      { id: "rejected", label: "Refusés" }
    ].map((f) => /* @__PURE__ */ jsxRuntimeExports.jsx(
      "button",
      {
        onClick: () => setStatusFilter(f.id),
        className: `px-2.5 py-1 rounded-full font-semibold border transition-all ${statusFilter === f.id ? "bg-primary text-primary-foreground border-primary" : "bg-card border-border text-muted-foreground"}`,
        children: f.label
      },
      f.id
    )) }),
    loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-12", children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" }) }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card shadow-md border border-white/8 overflow-hidden", children: [
      tab === "pending" && (pendingDeps.length + pendingWiths.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx(EmptyState, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-10 h-10" }), label: "Rien en attente 🎉", hint: "Tous vos dépôts et retraits sont traités." }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "divide-y divide-border/40", children: [
        pendingDeps.map((item) => /* @__PURE__ */ jsxRuntimeExports.jsx(PendingItem, { kind: "deposit", item }, "d-" + item.id)),
        pendingWiths.map((item) => /* @__PURE__ */ jsxRuntimeExports.jsx(PendingItem, { kind: "withdrawal", item }, "w-" + item.id))
      ] })),
      tab === "deposits" && (filteredDeps.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx(EmptyState, { label: "Aucun dépôt" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "divide-y divide-border/40", children: filteredDeps.map((item) => /* @__PURE__ */ jsxRuntimeExports.jsx(FinanceRow, { kind: "deposit", item }, item.id)) })),
      tab === "withdrawals" && (filteredWiths.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx(EmptyState, { label: "Aucun retrait" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "divide-y divide-border/40", children: filteredWiths.map((item) => /* @__PURE__ */ jsxRuntimeExports.jsx(FinanceRow, { kind: "withdrawal", item }, item.id)) })),
      tab === "transactions" && (tx.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx(EmptyState, { label: "Aucune transaction" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "divide-y divide-border/40", children: tx.map((item) => {
        const cfg = txConfig(item.kind);
        const amount = Number(item.amount ?? 0);
        const isPositive = ["game_win", "tournament_win", "daily_bonus", "signup_bonus", "referral", "deposit", "refund"].includes(item.kind);
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start gap-3 p-3.5", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `mt-0.5 p-2 rounded-xl bg-white/5 border border-white/8 ${cfg.color}`, children: cfg.icon }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: cfg.label }),
            item.meta?.game && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: item.meta.game }),
            item.meta?.streak && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-amber-600", children: [
              "🔥 Série ",
              item.meta.streak,
              " jours",
              item.meta.multiplier > 1 ? ` (×${item.meta.multiplier})` : ""
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground flex items-center gap-1 mt-0.5", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-2.5 h-2.5" }),
              fmtDate(item.created_at)
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `font-extrabold text-sm tabular-nums ${isPositive ? "text-emerald-600" : "text-rose-500"}`, children: [
            isPositive ? "+" : "-",
            fmtAr(Math.abs(amount))
          ] })
        ] }, item.id);
      }) }))
    ] })
  ] });
}
function PendingItem({ kind, item }) {
  const isDep = kind === "deposit";
  const color = isDep ? "emerald" : "rose";
  const amount = Number(item.amount_ar ?? item.amount ?? 0);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `p-3.5 bg-amber-50/60 dark:bg-amber-950/10 border-l-4 border-amber-400`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start gap-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `mt-0.5 p-2 rounded-xl bg-${color}-100 dark:bg-${color}-900/30 text-${color}-600`, children: isDep ? /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowDown, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowUp, { className: "w-4 h-4" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: isDep ? "Dépôt" : "Retrait" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(StatusBadge, { status: "pending" })
        ] }),
        item.operator && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
          "📱 ",
          item.operator,
          item.phone ? ` · ${item.phone}` : ""
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground flex items-center gap-1 mt-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-2.5 h-2.5" }),
          " ",
          fmtDate(item.created_at),
          " · ",
          relTime(item.created_at)
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `font-extrabold text-base ${isDep ? "text-emerald-600" : "text-rose-500"} tabular-nums`, children: [
        isDep ? "+" : "-",
        fmtAr(amount)
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-2 text-[10px] text-amber-700 dark:text-amber-400 font-medium", children: "⏳ En cours de traitement par l'administrateur." })
  ] });
}
function FinanceRow({ kind, item }) {
  const isDep = kind === "deposit";
  const color = isDep ? "emerald" : "rose";
  const amount = Number(item.amount_ar ?? item.amount ?? 0);
  const status = item.status ?? "pending";
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start gap-3 p-3.5", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `mt-0.5 p-2 rounded-xl bg-${color}-100 dark:bg-${color}-900/30 text-${color}-600`, children: isDep ? /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowDown, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(CircleArrowUp, { className: "w-4 h-4" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 flex-wrap", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm", children: isDep ? "Dépôt" : "Retrait" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(StatusBadge, { status })
      ] }),
      item.operator && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
        "📱 ",
        item.operator,
        item.phone ? ` · ${item.phone}` : ""
      ] }),
      item.reject_reason && status === "rejected" && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-rose-600 mt-0.5", children: [
        "Raison : ",
        item.reject_reason
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground flex items-center gap-1 mt-0.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-2.5 h-2.5" }),
        " ",
        fmtDate(item.created_at)
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `font-extrabold text-sm ${status === "rejected" || status === "cancelled" ? "text-muted-foreground line-through" : isDep ? "text-emerald-600" : "text-rose-500"} tabular-nums`, children: [
      isDep ? "+" : "-",
      fmtAr(amount)
    ] })
  ] });
}
function EmptyState({ label, hint, icon }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col items-center justify-center py-16 text-muted-foreground gap-2 px-4 text-center", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "opacity-30", children: icon ?? /* @__PURE__ */ jsxRuntimeExports.jsx(ReceiptText, { className: "w-10 h-10" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm font-semibold", children: label }),
    hint && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] opacity-70", children: hint })
  ] });
}
const $$splitComponentImporter$l = () => import("./jeux-BFsOu0JM.mjs");
const Route$u = createFileRoute("/_authenticated/jeux")({
  component: lazyRouteComponent($$splitComponentImporter$l, "component")
});
const $$splitComponentImporter$k = () => import("./live-CeGKJGqR.mjs");
const Route$t = createFileRoute("/_authenticated/live")({
  component: lazyRouteComponent($$splitComponentImporter$k, "component"),
  head: () => ({
    meta: [{
      title: "LIVE — Lalao MADA"
    }]
  })
});
const $$splitComponentImporter$j = () => import("./lobby-of6Jje0b.mjs");
const Route$s = createFileRoute("/_authenticated/lobby")({
  component: lazyRouteComponent($$splitComponentImporter$j, "component"),
  head: () => ({
    meta: [{
      title: "Accueil — Lalao MADA"
    }]
  })
});
const $$splitComponentImporter$i = () => import("./parametres-F9C5Lw_9.mjs");
const Route$r = createFileRoute("/_authenticated/parametres")({
  component: lazyRouteComponent($$splitComponentImporter$i, "component"),
  head: () => ({
    meta: [{
      title: "Parametres — Lalao MADA"
    }, {
      name: "description",
      content: "Parametres du compte : nom, email et apparence."
    }]
  })
});
async function copyText(text) {
  if (!text) return false;
  if (navigator.clipboard?.writeText) {
    try {
      await navigator.clipboard.writeText(text);
      return true;
    } catch {
    }
  }
  try {
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.setAttribute("readonly", "");
    textarea.style.position = "fixed";
    textarea.style.top = "0";
    textarea.style.left = "0";
    textarea.style.width = "1px";
    textarea.style.height = "1px";
    textarea.style.padding = "0";
    textarea.style.border = "none";
    textarea.style.outline = "none";
    textarea.style.boxShadow = "none";
    textarea.style.background = "transparent";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.focus();
    textarea.select();
    textarea.setSelectionRange(0, textarea.value.length);
    const ok = document.execCommand("copy");
    document.body.removeChild(textarea);
    return ok;
  } catch {
    return false;
  }
}
const Route$q = createFileRoute("/_authenticated/parrainage")({
  component: ParrainagePage,
  head: () => ({
    meta: [
      { title: "Parrainage — Lalao MADA" },
      { name: "description", content: referralMetaDescription() }
    ]
  })
});
function referralStatusBadge(r) {
  if (r.status === "rewarded")
    return { label: "Actif ✅", color: "text-emerald-600", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-3 h-3" }) };
  if (!r.phone_verified)
    return { label: "Téléphone à vérifier", color: "text-amber-500", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Phone, { className: "w-3 h-3" }) };
  if (!r.deposit_validated)
    return { label: "Dépôt en attente", color: "text-orange-500", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Clock, { className: "w-3 h-3" }) };
  const matches = r.matches_completed || 0;
  return { label: `${matches}/${MIN_MATCHES} matchs`, color: "text-blue-500", icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-3 h-3" }) };
}
function CoinRain({ trigger }) {
  if (!trigger) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "fixed inset-0 pointer-events-none z-50 overflow-hidden", children: [
    Array.from({ length: 12 }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
      "div",
      {
        className: "absolute text-2xl",
        style: {
          left: `${5 + i * 8 % 90}%`,
          top: "-30px",
          animation: `coin-fall ${1.5 + i % 4 * 0.3}s ease-in ${i * 0.1}s forwards`
        },
        children: "🪙"
      },
      i
    )),
    /* @__PURE__ */ jsxRuntimeExports.jsx("style", { children: `
        @keyframes coin-fall {
          0% { transform: translateY(0) rotate(0deg); opacity: 1; }
          100% { transform: translateY(100vh) rotate(720deg); opacity: 0; }
        }
      ` })
  ] });
}
function TierRewardCard({ activeCount }) {
  const currentTier = [...REFERRAL_TIERS].reverse().find((t) => activeCount >= t.count);
  const nextTier = REFERRAL_TIERS.find((t) => activeCount < t.count);
  const progress = nextTier ? Math.min(100, activeCount / nextTier.count * 100) : 100;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-gradient-to-br from-amber-500/10 via-card to-primary/10 border border-border/60 p-3 space-y-3", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-2xl", children: currentTier?.icon || "🎯" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold uppercase tracking-wider text-muted-foreground", children: "Niveau actuel" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-sm", children: currentTier?.label || "Nouveau" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold uppercase tracking-wider text-muted-foreground", children: "Récompense par filleul" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm text-emerald-600", children: [
          REWARD_PER_ACTIVE_AR,
          " Ar"
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative h-3 rounded-full bg-secondary overflow-hidden", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "div",
        {
          className: "absolute inset-y-0 left-0 rounded-full bg-gradient-to-r from-primary to-amber-400 transition-all duration-500",
          style: { width: `${progress}%` }
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute inset-0 flex items-center justify-center text-[10px] font-bold text-foreground/80", children: [
        activeCount,
        " / ",
        nextTier?.count || activeCount
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "space-y-1.5", children: REFERRAL_TIERS.map((t) => {
      const reached = activeCount >= t.count;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "div",
        {
          className: `flex items-center gap-2.5 rounded-xl px-2.5 py-2 transition-all ${reached ? "bg-primary/15 border border-primary/30" : "bg-secondary/40 border border-border/20"}`,
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xl shrink-0", children: t.icon }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm", children: [
                t.count,
                " filleuls ",
                reached && /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "inline w-3.5 h-3.5 text-emerald-500 ml-1" })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: t.label })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `font-extrabold text-sm shrink-0 ${reached ? "text-emerald-600" : "text-muted-foreground"}`, children: [
              "= ",
              t.reward.toLocaleString("fr-FR"),
              " Ar"
            ] })
          ]
        },
        t.count
      );
    }) })
  ] });
}
function StatCard({ icon, label, value, sub, color = "text-foreground" }) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-secondary/60 p-3 space-y-1", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 text-muted-foreground text-xs", children: [
      icon,
      label
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `text-xl font-extrabold ${color}`, children: value }),
    sub && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: sub })
  ] });
}
function ParrainagePage() {
  const { profile, user } = useAuth();
  const [tab, setTab] = reactExports.useState("filleuls");
  const [data, setData] = reactExports.useState(null);
  const [leaderboard, setLeaderboard] = reactExports.useState([]);
  const [loading, setLoading] = reactExports.useState(true);
  const [referralEnabled, setReferralEnabled] = reactExports.useState(null);
  const [showCoinRain, setShowCoinRain] = reactExports.useState(false);
  const [prevEarned, setPrevEarned] = reactExports.useState(0);
  const [downloadUrl, setDownloadUrl] = reactExports.useState("");
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("referral_enabled, download_url").eq("id", 1).maybeSingle().then(({ data: cfg }) => {
      setReferralEnabled(cfg ? cfg.referral_enabled !== false : true);
      setDownloadUrl((cfg?.download_url || "").trim());
    });
  }, []);
  const refCode = profile?.referral_code || "";
  const shareLink = typeof window !== "undefined" ? `${window.location.origin}/login?ref=${refCode}` : "";
  const copyCode = () => {
    copyText(refCode).then((ok) => toast[ok ? "success" : "error"](ok ? "Code copié !" : "Impossible de copier"));
  };
  const copyLink = () => {
    copyText(shareLink).then((ok) => toast[ok ? "success" : "error"](ok ? "Lien copié !" : "Impossible de copier"));
  };
  const shareWhatsApp = () => {
    const msg = encodeURIComponent(
      `🎮 Rejoins-moi sur Lalao MADA !

${shareLink}

📋 Mon code de parrainage : ${refCode}

💰 Tu peux jouer au Ludo, Domino, Échecs et plus encore en Ariary !`
    );
    window.open(`https://wa.me/?text=${msg}`, "_blank");
  };
  const shareFacebook = () => {
    const url2 = encodeURIComponent(shareLink);
    window.open(`https://www.facebook.com/sharer/sharer.php?u=${url2}`, "_blank");
  };
  const shareSMS = () => {
    const msg = encodeURIComponent(`Rejoins Lalao MADA 🎮 ${shareLink} Code: ${refCode}`);
    window.open(`sms:?body=${msg}`, "_blank");
  };
  const refresh = () => {
    supabase.rpc("get_referral_dashboard").then(({ data: d, error }) => {
      if (error) {
        console.error("get_referral_dashboard error:", error);
        setLoading(false);
        return;
      }
      if (d) {
        const newEarned = Number(d.total_earned || 0);
        if (newEarned > prevEarned && prevEarned > 0) {
          setShowCoinRain(true);
          setTimeout(() => setShowCoinRain(false), 2500);
        }
        setPrevEarned(newEarned);
        setData(d);
      }
      setLoading(false);
    });
  };
  reactExports.useEffect(() => {
    if (!user?.id) return;
    setLoading(true);
    refresh();
    let dt;
    const debouncedRefresh = () => {
      clearTimeout(dt);
      dt = setTimeout(refresh, 800);
    };
    const ch = supabase.channel(`ref-dash-${user.id}`).on("postgres_changes", { event: "*", schema: "public", table: "referral_events", filter: `referrer_id=eq.${user.id}` }, debouncedRefresh).on("postgres_changes", { event: "*", schema: "public", table: "referrals", filter: `referrer_id=eq.${user.id}` }, debouncedRefresh).subscribe();
    const onFocus = () => refresh();
    window.addEventListener("focus", onFocus);
    return () => {
      clearTimeout(dt);
      supabase.removeChannel(ch);
      window.removeEventListener("focus", onFocus);
    };
  }, [user?.id]);
  reactExports.useEffect(() => {
    if (tab !== "classement") return;
    supabase.rpc("get_referral_leaderboard", { _limit: 50 }).then(({ data: d }) => {
      setLeaderboard(d || []);
    });
  }, [tab]);
  const stats = data?.stats || {};
  const referrals = data?.referrals || [];
  const events = data?.events || [];
  const totalEarned = Number(data?.total_earned || stats.total_earned_ar || 0);
  const activeCount = Number(data?.active_count || stats.active_referrals || 0);
  const totalRefs = Number(stats.total_referrals || referrals.length || 0);
  const myRank = data?.rank || null;
  const TABS = [
    { id: "filleuls", label: "Filleuls", icon: "👥" },
    { id: "gains", label: "Gains", icon: "💰" },
    { id: "classement", label: "Classement", icon: "🏆" }
  ];
  if (loading || referralEnabled === null)
    return /* @__PURE__ */ jsxRuntimeExports.jsx(PageLoader, { variant: "overlay", label: "Chargement du parrainage…" });
  if (!referralEnabled)
    return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-xl mx-auto px-4 py-10 text-center", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-4xl mb-3", children: "🚫" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-muted-foreground font-semibold", children: "Programme de parrainage désactivé pour le moment" })
    ] });
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-xl mx-auto w-full px-3 pt-2 pb-2 h-[calc(100dvh-14rem)] flex flex-col gap-2.5 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(CoinRain, { trigger: showCoinRain }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-gradient-to-br from-primary/15 via-card to-amber-500/10 border border-border/60 p-3 space-y-2.5 shrink-0", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9 rounded-xl bg-gradient-to-br from-primary to-amber-400 flex items-center justify-center shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Gift, { className: "w-5 h-5 text-white" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-base font-extrabold leading-none", children: "Parrainez vos amis" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[11px] text-muted-foreground mt-0.5", children: [
            REWARD_PER_ACTIVE_AR,
            " Ar par filleul actif"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-lg font-extrabold text-emerald-600", children: Math.round(totalEarned).toLocaleString("fr-FR") }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: "Ar gagnés" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold uppercase tracking-wider text-muted-foreground", children: "Votre lien de parrainage" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: copyLink,
            className: "w-full h-11 flex items-center gap-2 px-3 rounded-2xl bg-primary/10 border-2 border-dashed border-primary/40 active:scale-[0.98] transition-all",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 text-left truncate text-xs font-medium text-foreground", children: shareLink || "Lien bientôt disponible" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-4 h-4 shrink-0 text-primary" })
            ]
          }
        )
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-4 gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: copyCode,
            className: "flex flex-col items-center gap-1 py-2 rounded-xl bg-primary/10 border border-primary/20 active:scale-95 transition-all",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-4 h-4 text-primary" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold", children: "Code" })
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: shareWhatsApp,
            className: "flex flex-col items-center gap-1 py-2 rounded-xl bg-emerald-500/10 border border-emerald-500/20 active:scale-95 transition-all",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(MessageCircle, { className: "w-4 h-4 text-emerald-600" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold", children: "WhatsApp" })
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: shareFacebook,
            className: "flex flex-col items-center gap-1 py-2 rounded-xl bg-blue-500/10 border border-blue-500/20 active:scale-95 transition-all",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Share2, { className: "w-4 h-4 text-blue-600" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold", children: "Facebook" })
            ]
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: shareSMS,
            className: "flex flex-col items-center gap-1 py-2 rounded-xl bg-amber-500/10 border border-amber-500/20 active:scale-95 transition-all",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Phone, { className: "w-4 h-4 text-amber-600" }),
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[9px] font-semibold", children: "SMS" })
            ]
          }
        )
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: copyCode,
          className: "w-full h-12 flex items-center justify-center gap-3 px-3 rounded-2xl bg-primary text-primary-foreground font-semibold active:scale-[0.98] transition-all",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-mono font-extrabold text-xl tracking-[0.15em]", children: refCode }),
            /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-4 h-4 opacity-80" })
          ]
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(StatCard, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3 h-3" }), label: "Filleuls", value: totalRefs, sub: `${activeCount} actifs` }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(StatCard, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-3 h-3" }), label: "Gains", value: `${Math.round(totalEarned).toLocaleString("fr-FR")} Ar`, color: "text-emerald-600" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(StatCard, { icon: /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3 h-3" }), label: "Rang", value: myRank ? `#${myRank}` : "—", color: "text-amber-500" })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(TierRewardCard, { activeCount }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1 bg-secondary/60 rounded-2xl p-1 shrink-0", children: TABS.map((t) => /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "button",
      {
        onClick: () => setTab(t.id),
        className: `flex-1 flex items-center justify-center gap-1 px-2 py-1.5 rounded-xl text-xs font-semibold transition-all ${tab === t.id ? "bg-card shadow-sm text-foreground" : "text-muted-foreground"}`,
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: t.icon }),
          t.label
        ]
      },
      t.id
    )) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-h-0 overflow-y-auto rounded-2xl bg-card px-3 py-2 shadow-sm", children: [
      tab === "filleuls" && (referrals.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "h-full flex flex-col items-center justify-center text-center gap-3 py-6", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-4xl opacity-50", children: "👥" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm text-muted-foreground", children: "Aucun filleul pour l'instant" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-muted-foreground max-w-[220px] text-center", children: "Partagez votre lien de parrainage avec vos amis. Dès qu'ils s'inscrivent avec votre code, ils apparaîtront ici." }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: copyLink, className: "px-4 py-2 rounded-full bg-primary text-primary-foreground font-semibold text-xs", children: "Copier mon lien" })
      ] }) : referrals.map((r) => {
        const badge = referralStatusBadge(r);
        const earned = Number(r.reward_amount || 0);
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2.5 py-2.5 border-b border-border/40 last:border-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-9 h-9 rounded-full bg-accent flex items-center justify-center font-bold text-xs shrink-0 overflow-hidden", children: r.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: r.avatar_url, width: 36, height: 36, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: "" }) : (r.pseudo || "?").slice(0, 2).toUpperCase() }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold text-sm truncate", children: r.pseudo }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1 text-[10px] ${badge.color}`, children: [
              badge.icon,
              badge.label
            ] })
          ] }),
          earned > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm font-extrabold text-emerald-600 shrink-0", children: [
            "+",
            Math.round(earned).toLocaleString("fr-FR"),
            " Ar"
          ] })
        ] }, r.id);
      })),
      tab === "gains" && (events.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "h-full flex flex-col items-center justify-center text-center gap-2 py-6 text-xs text-muted-foreground", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-4xl opacity-50", children: "💰" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold", children: "Aucune récompense reçue" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-[10px] max-w-[220px] text-center", children: [
          "Vous gagnez ",
          REWARD_PER_ACTIVE_AR,
          " Ar dès qu'un filleul vérifie son téléphone, dépose ",
          MIN_DEPOSIT_AR,
          " Ar et joue ",
          MIN_MATCHES,
          " matchs à ",
          MIN_STAKE_AR,
          " Ar minimum."
        ] })
      ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between py-2 px-3 mb-1 rounded-xl bg-emerald-500/10", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs font-bold text-emerald-700 dark:text-emerald-400", children: "Total gagné" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-lg font-extrabold text-emerald-600", children: [
            Math.round(totalEarned).toLocaleString("fr-FR"),
            " Ar"
          ] })
        ] }),
        events.map((e) => /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-8 h-8 rounded-full bg-emerald-100 dark:bg-emerald-900/30 flex items-center justify-center text-sm shrink-0", children: "🪙" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold truncate", children: e.referee_pseudo }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground", children: [
              e.note || "Filleul actif",
              " · ",
              new Date(e.created_at).toLocaleDateString("fr-FR", { dateStyle: "short" })
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-emerald-600 font-extrabold text-sm shrink-0", children: [
            "+",
            Math.round(Number(e.reward_amount)).toLocaleString("fr-FR"),
            " Ar"
          ] })
        ] }, e.id))
      ] })),
      tab === "classement" && (leaderboard.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "h-full flex flex-col items-center justify-center text-center gap-2 py-6 text-xs text-muted-foreground", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-4xl opacity-50", children: "🏆" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-semibold", children: "Classement vide" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] max-w-[200px] text-center", children: "Soyez le premier à parrainer des amis et à grimper au classement !" })
      ] }) : leaderboard.map((lb) => {
        const isMe = lb.referrer_id === user?.id;
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-2.5 py-2 border-b border-border/40 last:border-0 ${isMe ? "bg-primary/5 rounded-xl px-2" : ""}`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-6 text-center font-extrabold text-xs shrink-0", children: lb.rank === 1 ? "👑" : lb.rank === 2 ? "🥈" : lb.rank === 3 ? "🥉" : lb.rank }),
          /* @__PURE__ */ jsxRuntimeExports.jsx(Link, { to: "/joueur/$id", params: { id: lb.referrer_id }, className: "w-8 h-8 rounded-full bg-accent overflow-hidden flex items-center justify-center font-bold text-xs shrink-0", children: lb.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: lb.avatar_url, width: 32, height: 32, loading: "lazy", decoding: "async", className: "w-full h-full object-cover", alt: "" }) : (lb.pseudo || "?").slice(0, 2).toUpperCase() }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `font-bold text-sm truncate ${isMe ? "text-primary" : ""}`, children: lb.pseudo }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-[10px] text-muted-foreground", children: [
              lb.active_referrals || 0,
              " filleuls actifs"
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-sm text-emerald-600 shrink-0", children: [
            Math.round(Number(lb.total_earned_ar)).toLocaleString("fr-FR"),
            " Ar"
          ] })
        ] }, lb.referrer_id);
      }))
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("details", { className: "shrink-0 rounded-2xl bg-secondary/50 px-3 py-2 group", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("summary", { className: "list-none flex items-center gap-2 cursor-pointer", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Sparkles, { className: "w-4 h-4 shrink-0 text-primary" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "flex-1 text-[11px] leading-snug text-muted-foreground", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { className: "text-foreground", children: [
            REWARD_PER_ACTIVE_AR,
            " Ar"
          ] }),
          " par filleul actif : téléphone vérifié + dépôt ≥ ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { className: "text-foreground", children: [
            MIN_DEPOSIT_AR,
            " Ar"
          ] }),
          " +",
          MIN_MATCHES,
          " matchs avec mise ≥ ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { className: "text-foreground", children: [
            MIN_STAKE_AR,
            " Ar"
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronDown, { className: "w-4 h-4 shrink-0 text-muted-foreground transition-transform group-open:rotate-180" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "mt-2 space-y-1 text-[10px] leading-snug text-muted-foreground border-t border-border/40 pt-2", children: referralConditions().map((c, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { children: [
        "• ",
        c
      ] }, i)) })
    ] })
  ] });
}
const $$splitComponentImporter$h = () => import("./profile-DXBP0rTC.mjs");
const Route$p = createFileRoute("/_authenticated/profile")({
  component: lazyRouteComponent($$splitComponentImporter$h, "component"),
  head: () => ({
    meta: [{
      title: "Mon profil — Lalao MADA"
    }, {
      name: "description",
      content: "Profil joueur Lalao MADA : statistiques, jeux, classement et historique."
    }]
  })
});
const $$splitComponentImporter$g = () => import("./rankings-BneeRKzo.mjs");
const Route$o = createFileRoute("/_authenticated/rankings")({
  component: lazyRouteComponent($$splitComponentImporter$g, "component"),
  head: () => ({
    meta: [{
      title: "Classement — Lalao MADA"
    }, {
      name: "description",
      content: "Classement général de Lalao MADA — Top joueurs, victoires, podium."
    }]
  })
});
const $$splitComponentImporter$f = () => import("./securite-DeJ5Ss6B.mjs");
const Route$n = createFileRoute("/_authenticated/securite")({
  component: lazyRouteComponent($$splitComponentImporter$f, "component"),
  head: () => ({
    meta: [{
      title: "Sécurité — Lalao MADA"
    }, {
      name: "description",
      content: "Sécurité du compte : vérification du téléphone et mot de passe."
    }]
  })
});
const $$splitComponentImporter$e = () => import("./statistiques-BlZrp3x-.mjs");
const Route$m = createFileRoute("/_authenticated/statistiques")({
  component: lazyRouteComponent($$splitComponentImporter$e, "component"),
  head: () => ({
    meta: [{
      title: "Statistiques — Lalao MADA"
    }, {
      name: "description",
      content: "Détail de vos statistiques de jeu : parties, victoires et défaites."
    }]
  })
});
const $$splitComponentImporter$d = () => import("./tournaments-qSAQx-7u.mjs");
const Route$l = createFileRoute("/_authenticated/tournaments")({
  component: lazyRouteComponent($$splitComponentImporter$d, "component"),
  head: () => ({
    meta: [{
      title: "Tournois — Lalao MADA"
    }, {
      name: "description",
      content: "Inscrivez-vous aux tournois Ludo et Domino de Lalao MADA et gagnez des récompenses."
    }, {
      property: "og:title",
      content: "Tournois — Lalao MADA"
    }, {
      property: "og:description",
      content: "Tournois Ludo et Domino avec cagnotte à gagner."
    }, {
      property: "og:type",
      content: "website"
    }, {
      name: "twitter:card",
      content: "summary"
    }]
  })
});
function StatusPill({
  status
}) {
  const map = {
    draft: {
      l: "Brouillon",
      c: "bg-secondary text-muted-foreground"
    },
    open: {
      l: "Inscriptions",
      c: "bg-emerald-100 text-emerald-700 dark:bg-emerald-950/50 dark:text-emerald-300"
    },
    running: {
      l: "En cours",
      c: "bg-amber-100 text-amber-700 dark:bg-amber-950/50 dark:text-amber-300"
    },
    paused: {
      l: "En pause",
      c: "bg-secondary text-muted-foreground"
    },
    finished: {
      l: "Terminé",
      c: "bg-secondary text-muted-foreground"
    },
    cancelled: {
      l: "Annulé",
      c: "bg-secondary text-muted-foreground"
    }
  };
  const s = map[status] ?? map.draft;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `px-2 py-0.5 rounded-full text-[10px] font-bold shrink-0 ${s.c}`, children: s.l });
}
const $$splitComponentImporter$c = () => import("./tutos-BBD6gtrd.mjs");
const Route$k = createFileRoute("/_authenticated/tutos")({
  component: lazyRouteComponent($$splitComponentImporter$c, "component"),
  loader: async () => {
    const {
      data
    } = await supabase.from("app_settings").select("tutorials,terms_text").eq("id", 1).maybeSingle();
    return {
      tutorials: data?.tutorials || [],
      terms: data?.terms_text || ""
    };
  },
  head: ({
    loaderData
  }) => {
    const faqs = (loaderData?.tutorials || []).filter((t) => t?.title && t?.content);
    return {
      meta: [{
        title: "Tutoriels & FAQ — Lalao MADA"
      }, {
        name: "description",
        content: "Apprenez les règles du Lalao MADA : comment déposer, retirer, créer une partie, capturer un pion et remporter la cagnotte."
      }, {
        property: "og:title",
        content: "Tutoriels & FAQ — Lalao MADA"
      }, {
        property: "og:description",
        content: "Règles, dépôts/retraits et astuces pour jouer au Lalao MADA."
      }, {
        property: "og:url",
        content: "https://lalaomada.lovable.app/tutos"
      }],
      links: [{
        rel: "canonical",
        href: "https://lalaomada.lovable.app/tutos"
      }],
      scripts: faqs.length > 0 ? [{
        type: "application/ld+json",
        children: JSON.stringify({
          "@context": "https://schema.org",
          "@type": "FAQPage",
          mainEntity: faqs.map((t) => ({
            "@type": "Question",
            name: t.title,
            acceptedAnswer: {
              "@type": "Answer",
              text: t.content
            }
          }))
        })
      }] : []
    };
  }
});
function isPrivateHost(host) {
  const h = host.toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".internal")) return true;
  const m = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const [a, b] = [parseInt(m[1], 10), parseInt(m[2], 10)];
    if (a === 10) return true;
    if (a === 127) return true;
    if (a === 0) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
    if (a >= 224) return true;
    return false;
  }
  if (h === "::1" || h.startsWith("[::1]")) return true;
  if (h.startsWith("fe80:") || h.startsWith("fc") || h.startsWith("fd")) return true;
  return false;
}
const Route$j = createFileRoute("/api/link-preview")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        const url2 = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
        const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
        const auth = request.headers.get("authorization") || "";
        const token = auth.replace(/^Bearer\s+/i, "").trim();
        if (!token) {
          return new Response(JSON.stringify({ error: "unauthorized" }), {
            status: 401,
            headers: { "content-type": "application/json" }
          });
        }
        const userClient = createClient(url2, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
        const { data: userData } = await userClient.auth.getUser();
        if (!userData?.user?.id) {
          return new Response(JSON.stringify({ error: "unauthorized" }), {
            status: 401,
            headers: { "content-type": "application/json" }
          });
        }
        const raw = new URL(request.url).searchParams.get("url") || "";
        if (!raw || !/^https?:\/\//i.test(raw)) {
          return new Response(JSON.stringify({ error: "url invalide" }), {
            status: 400,
            headers: { "content-type": "application/json" }
          });
        }
        let target;
        try {
          target = new URL(raw);
        } catch {
          return new Response(JSON.stringify({ error: "url invalide" }), {
            status: 400,
            headers: { "content-type": "application/json" }
          });
        }
        if (target.protocol !== "http:" && target.protocol !== "https:") {
          return new Response(JSON.stringify({ error: "scheme invalide" }), {
            status: 400,
            headers: { "content-type": "application/json" }
          });
        }
        if (isPrivateHost(target.hostname)) {
          return new Response(JSON.stringify({ error: "host non autorisé" }), {
            status: 400,
            headers: { "content-type": "application/json" }
          });
        }
        try {
          const res = await fetch(target.toString(), {
            headers: {
              "User-Agent": "Mozilla/5.0 (compatible; LalaoMADA/1.0)",
              Accept: "text/html"
            },
            redirect: "follow",
            signal: AbortSignal.timeout(6e3)
          });
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          try {
            const finalUrl = new URL(res.url);
            if (isPrivateHost(finalUrl.hostname)) throw new Error("redirect to private host");
          } catch {
          }
          const ct = res.headers.get("content-type") || "";
          if (!ct.includes("text/html")) throw new Error("not html");
          const html = await res.text();
          const get = (pattern) => (html.match(pattern)?.[1] || "").trim();
          const decode = (s) => s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ");
          const title = decode(get(/<meta[^>]+property="og:title"[^>]+content="([^"]+)"/i) || get(/<meta[^>]+content="([^"]+)"[^>]+property="og:title"/i) || get(/<title[^>]*>([^<]{1,200})<\/title>/i));
          const description = decode(get(/<meta[^>]+property="og:description"[^>]+content="([^"]+)"/i) || get(/<meta[^>]+content="([^"]+)"[^>]+property="og:description"/i) || get(/<meta[^>]+name="description"[^>]+content="([^"]+)"/i) || get(/<meta[^>]+content="([^"]+)"[^>]+name="description"/i));
          let image = get(/<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i) || get(/<meta[^>]+content="([^"]+)"[^>]+property="og:image"/i);
          if (image && image.startsWith("/")) {
            image = `${target.protocol}//${target.host}${image}`;
          }
          const siteName = decode(get(/<meta[^>]+property="og:site_name"[^>]+content="([^"]+)"/i) || get(/<meta[^>]+content="([^"]+)"[^>]+property="og:site_name"/i)) || target.hostname.replace(/^www\./, "");
          return new Response(
            JSON.stringify({ title: title.slice(0, 120), description: description.slice(0, 200), image, siteName, url: raw }),
            { status: 200, headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } }
          );
        } catch (e) {
          return new Response(JSON.stringify({ error: e?.message || "fetch failed" }), {
            status: 502,
            headers: { "content-type": "application/json" }
          });
        }
      }
    }
  }
});
function createLovableAiGatewayProvider(lovableApiKey) {
  return createOpenAICompatible({
    name: "lovable",
    baseURL: "https://ai.gateway.lovable.dev/v1",
    headers: {
      "Lovable-API-Key": lovableApiKey,
      "X-Lovable-AIG-SDK": "vercel-ai-sdk"
    }
  });
}
const Route$i = createFileRoute("/api/translate")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        try {
          const body = await request.json();
          const lang = body.lang === "mg" ? "mg" : body.lang === "en" ? "en" : null;
          if (!lang) return new Response("bad lang", { status: 400 });
          if (!Array.isArray(body.texts)) return new Response("texts required", { status: 400 });
          const texts = body.texts.map((t) => typeof t === "string" ? t : "").map((t) => t.slice(0, 400));
          if (texts.length === 0) return Response.json({ translations: [] });
          if (texts.length > 120) return new Response("too many items", { status: 400 });
          const total = texts.reduce((n, t) => n + t.length, 0);
          if (total > 12e3) return new Response("payload too large", { status: 400 });
          const key = process.env.LOVABLE_API_KEY;
          if (!key) return new Response("Missing LOVABLE_API_KEY", { status: 500 });
          const target = lang === "mg" ? "Malagasy (Merina standard)" : "English";
          const system = [
            `You are a translation engine. Translate each input from French to ${target}.`,
            "Preserve punctuation, casing style, emojis, numbers, placeholders (like {name}, %s, :id), and trailing/leading whitespace.",
            "Do NOT translate: proper nouns, brand names, usernames, IDs, URLs, currency codes (Ar), and pure numbers.",
            "Return ONLY a JSON array of strings in the same order and same length as the input. No prose, no markdown."
          ].join(" ");
          const prompt = `Translate this JSON array of French strings to ${target}. Return ONLY the JSON array.

${JSON.stringify(texts)}`;
          const gateway = createLovableAiGatewayProvider(key);
          const { text } = await generateText({
            model: gateway("google/gemini-3-flash-preview"),
            system,
            prompt
          });
          let parsed = null;
          try {
            parsed = JSON.parse(text);
          } catch {
            const m = text.match(/\[[\s\S]*\]/);
            if (m) {
              try {
                parsed = JSON.parse(m[0]);
              } catch {
              }
            }
          }
          if (!Array.isArray(parsed) || parsed.length !== texts.length) {
            return Response.json({ translations: texts });
          }
          const translations = parsed.map(
            (v, i) => typeof v === "string" && v.length > 0 ? v : texts[i]
          );
          return Response.json(
            { translations },
            { headers: { "Cache-Control": "public, max-age=3600" } }
          );
        } catch (e) {
          const msg = e instanceof Error ? e.message : "error";
          return new Response(msg, { status: 500 });
        }
      }
    }
  }
});
const Route$h = createFileRoute("/_authenticated/chess/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/chess/$id", params: { id: params.id } });
  }
});
const $$splitComponentImporter$b = () => import("./discussion._slug-CDw0Bz9B.mjs");
const Route$g = createFileRoute("/_authenticated/discussion/$slug")({
  component: lazyRouteComponent($$splitComponentImporter$b, "component"),
  head: () => ({
    meta: [{
      title: "Discussion — Lalao MADA"
    }]
  })
});
const Route$f = createFileRoute("/_authenticated/domino/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/domino/$id", params: { id: params.id } });
  }
});
const Route$e = createFileRoute("/_authenticated/fanorona/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/fanorona/$id", params: { id: params.id } });
  }
});
const Route$d = createFileRoute("/_authenticated/game/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/ludo/$id", params: { id: params.id } });
  }
});
const ludoImg = "/assets/ludo-cover-B3qgbN7v.jpg";
const dominoImg = "/assets/domino-cover-BJEHEFSO.jpg";
const fanoronaImg = "/assets/fanorona-cover-CJXsXi7t.jpg";
const chessImg = "/assets/chess-cover-BoKhRhxK.jpg";
const ramiImg = "/assets/rami-cover-RIXrKtQr.jpg";
const pokerImg = "/assets/poker-cover--i320GSR.jpg";
const $$splitComponentImporter$a = () => import("./jeux.index-DHRGWOTz.mjs");
const Route$c = createFileRoute("/_authenticated/jeux/")({
  component: lazyRouteComponent($$splitComponentImporter$a, "component"),
  head: () => ({
    meta: [{
      title: "Les jeux — Lalao MADA"
    }, {
      name: "description",
      content: "Rejoignez ou créez une partie de vos jeux favoris."
    }],
    links: [{
      rel: "preload",
      as: "image",
      href: ludoImg,
      fetchpriority: "high"
    }, {
      rel: "preload",
      as: "image",
      href: dominoImg,
      fetchpriority: "high"
    }, {
      rel: "preload",
      as: "image",
      href: fanoronaImg
    }, {
      rel: "preload",
      as: "image",
      href: chessImg
    }, {
      rel: "preload",
      as: "image",
      href: ramiImg
    }, {
      rel: "preload",
      as: "image",
      href: pokerImg
    }]
  })
});
const url$6 = "/covers/cover_ludo.png";
const ludoCover = {
  url: url$6
};
const url$5 = "/covers/cover_domino.png";
const dominoCover = {
  url: url$5
};
const url$4 = "/covers/cover_rami.png";
const ramiCover = {
  url: url$4
};
const url$3 = "/covers/cover_chess.png";
const chessCover = {
  url: url$3
};
const url$2 = "/covers/cover_fanorona.png";
const fanoronaCover = {
  url: url$2
};
const url$1 = "/covers/cover_poker.png";
const pokerCover = {
  url: url$1
};
const COVER_BY_SLUG$1 = {
  ludo: ludoCover.url,
  domino: dominoCover.url,
  fanorona: fanoronaCover.url,
  chess: chessCover.url,
  rami: ramiCover.url,
  poker: pokerCover.url
};
const $$splitComponentImporter$9 = () => import("./jeux._slug-Bgq29vnp.mjs");
const Route$b = createFileRoute("/_authenticated/jeux/$slug")({
  component: lazyRouteComponent($$splitComponentImporter$9, "component"),
  head: ({
    params
  }) => ({
    meta: [{
      title: "Lobby — Lalao MADA"
    }],
    links: COVER_BY_SLUG$1[params.slug] ? [{
      rel: "preload",
      as: "image",
      href: COVER_BY_SLUG$1[params.slug],
      type: COVER_BY_SLUG$1[params.slug].endsWith(".webp") ? "image/webp" : void 0
    }] : []
  })
});
const $$splitComponentImporter$8 = () => import("./joueur._id-Ca_zcet-.mjs");
const Route$a = createFileRoute("/_authenticated/joueur/$id")({
  component: lazyRouteComponent($$splitComponentImporter$8, "component"),
  head: () => ({
    meta: [{
      title: "Profil joueur — Lalao MADA"
    }]
  })
});
const Route$9 = createFileRoute("/_authenticated/poker/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/poker/$id", params: { id: params.id } });
  }
});
const Route$8 = createFileRoute("/_authenticated/rami/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/rami/$id", params: { id: params.id } });
  }
});
const $$splitComponentImporter$7 = () => import("./tournaments_._id-CTAJrB5w.mjs");
const Route$7 = createFileRoute("/_authenticated/tournaments_/$id")({
  component: lazyRouteComponent($$splitComponentImporter$7, "component"),
  head: () => ({
    meta: [{
      title: "Détail du tournoi — Lalao MADA"
    }, {
      name: "description",
      content: "Suivez votre tournoi Lalao MADA : bracket, matchs, classement et récompenses en direct."
    }, {
      property: "og:title",
      content: "Détail du tournoi — Lalao MADA"
    }, {
      property: "og:description",
      content: "Bracket, matchs et récompenses en direct."
    }, {
      property: "og:type",
      content: "website"
    }, {
      name: "twitter:card",
      content: "summary"
    }]
  })
});
const $$splitComponentImporter$6 = () => import("./jeux.chess._id-D3cyWIW7.mjs");
const Route$6 = createFileRoute("/_authenticated/jeux/chess/$id")({
  component: lazyRouteComponent($$splitComponentImporter$6, "component"),
  head: () => ({
    meta: [{
      title: "Échecs — Lalao MADA"
    }]
  })
});
const $$splitComponentImporter$5 = () => import("./jeux.domino._id-B0h6ETjo.mjs");
const Route$5 = createFileRoute("/_authenticated/jeux/domino/$id")({
  component: lazyRouteComponent($$splitComponentImporter$5, "component"),
  head: () => ({
    meta: [{
      title: "Domino — Lalao MADA"
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const $$splitComponentImporter$4 = () => import("./jeux.fanorona._id-CIgGoMxb.mjs");
const Route$4 = createFileRoute("/_authenticated/jeux/fanorona/$id")({
  component: lazyRouteComponent($$splitComponentImporter$4, "component"),
  head: () => ({
    meta: [{
      title: "Fanorona — Lalao MADA"
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const $$splitComponentImporter$3 = () => import("./jeux.ludo._id-aD98dMyw.mjs");
const Route$3 = createFileRoute("/_authenticated/jeux/ludo/$id")({
  component: lazyRouteComponent($$splitComponentImporter$3, "component"),
  head: () => ({
    meta: [{
      title: "Partie en cours — Lalao MADA"
    }, {
      name: "description",
      content: "Plateau de jeu Lalao MADA en temps réel : lancez les dés, capturez les pions adverses et remportez la cagnotte."
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const url = "https://images.unsplash.com/photo-1601584115197-04ecc0da31d7?w=1024&h=1024&fit=crop";
const petanqueCover = {
  url
};
const COVER_BY_SLUG = {
  ludo: ludoCover.url,
  domino: dominoCover.url,
  fanorona: fanoronaCover.url,
  chess: chessCover.url,
  rami: ramiCover.url,
  poker: pokerCover.url,
  petanque: petanqueCover.url
};
const $$splitComponentImporter$2 = () => import("./jeux.nouveau._slug-rK0jj0GG.mjs");
const Route$2 = createFileRoute("/_authenticated/jeux/nouveau/$slug")({
  component: lazyRouteComponent($$splitComponentImporter$2, "component"),
  head: ({
    params
  }) => ({
    meta: [{
      title: "Lobby — Lalao MADA"
    }],
    links: COVER_BY_SLUG[params.slug] ? [{
      rel: "preload",
      as: "image",
      href: COVER_BY_SLUG[params.slug],
      type: COVER_BY_SLUG[params.slug].endsWith(".webp") ? "image/webp" : void 0
    }] : []
  })
});
const $$splitComponentImporter$1 = () => import("./jeux.poker._id-CEREleI5.mjs");
const Route$1 = createFileRoute("/_authenticated/jeux/poker/$id")({
  component: lazyRouteComponent($$splitComponentImporter$1, "component"),
  head: () => ({
    meta: [{
      title: "Poker — Lalao MADA"
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const $$splitComponentImporter = () => import("./jeux.rami._id-BD90SNrm.mjs");
const Route = createFileRoute("/_authenticated/jeux/rami/$id")({
  component: lazyRouteComponent($$splitComponentImporter, "component"),
  head: () => ({
    meta: [{
      title: "Rami — Lalao MADA"
    }, {
      name: "robots",
      content: "noindex"
    }]
  })
});
const IndexRoute = Route$G.update({
  id: "/",
  path: "/",
  getParentRoute: () => Route$H
});
const AuthenticatedRoute = Route$F.update({
  id: "/_authenticated",
  getParentRoute: () => Route$H
});
const CguRoute = Route$E.update({
  id: "/cgu",
  path: "/cgu",
  getParentRoute: () => Route$H
});
const ConfidentialiteRoute = Route$D.update({
  id: "/confidentialite",
  path: "/confidentialite",
  getParentRoute: () => Route$H
});
const JeuxPublicsRoute = Route$C.update({
  id: "/jeux-publics",
  path: "/jeux-publics",
  getParentRoute: () => Route$H
});
const LoginRoute = Route$B.update({
  id: "/login",
  path: "/login",
  getParentRoute: () => Route$H
});
const ResetPasswordRoute = Route$A.update({
  id: "/reset-password",
  path: "/reset-password",
  getParentRoute: () => Route$H
});
const AuthenticatedAdminRoute = Route$z.update({
  id: "/admin",
  path: "/admin",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedAdminBugReportsRoute = Route$y.update({
  id: "/admin-bug-reports",
  path: "/admin-bug-reports",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedChatRoute = Route$x.update({
  id: "/chat",
  path: "/chat",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedFaqRoute = Route$w.update({
  id: "/faq",
  path: "/faq",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedHistoryRoute = Route$v.update({
  id: "/history",
  path: "/history",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedJeuxRoute = Route$u.update({
  id: "/jeux",
  path: "/jeux",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedLiveRoute = Route$t.update({
  id: "/live",
  path: "/live",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedLobbyRoute = Route$s.update({
  id: "/lobby",
  path: "/lobby",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedParametresRoute = Route$r.update({
  id: "/parametres",
  path: "/parametres",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedParrainageRoute = Route$q.update({
  id: "/parrainage",
  path: "/parrainage",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedProfileRoute = Route$p.update({
  id: "/profile",
  path: "/profile",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedRankingsRoute = Route$o.update({
  id: "/rankings",
  path: "/rankings",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedSecuriteRoute = Route$n.update({
  id: "/securite",
  path: "/securite",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedStatistiquesRoute = Route$m.update({
  id: "/statistiques",
  path: "/statistiques",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedTournamentsRoute = Route$l.update({
  id: "/tournaments",
  path: "/tournaments",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedTutosRoute = Route$k.update({
  id: "/tutos",
  path: "/tutos",
  getParentRoute: () => AuthenticatedRoute
});
const ApiLinkPreviewRoute = Route$j.update({
  id: "/api/link-preview",
  path: "/api/link-preview",
  getParentRoute: () => Route$H
});
const ApiTranslateRoute = Route$i.update({
  id: "/api/translate",
  path: "/api/translate",
  getParentRoute: () => Route$H
});
const AuthenticatedChessIdRoute = Route$h.update({
  id: "/chess/$id",
  path: "/chess/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedDiscussionSlugRoute = Route$g.update({
  id: "/discussion/$slug",
  path: "/discussion/$slug",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedDominoIdRoute = Route$f.update({
  id: "/domino/$id",
  path: "/domino/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedFanoronaIdRoute = Route$e.update({
  id: "/fanorona/$id",
  path: "/fanorona/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedGameIdRoute = Route$d.update({
  id: "/game/$id",
  path: "/game/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedJeuxIndexRoute = Route$c.update({
  id: "/",
  path: "/",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxSlugRoute = Route$b.update({
  id: "/$slug",
  path: "/$slug",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJoueurIdRoute = Route$a.update({
  id: "/joueur/$id",
  path: "/joueur/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedPokerIdRoute = Route$9.update({
  id: "/poker/$id",
  path: "/poker/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedRamiIdRoute = Route$8.update({
  id: "/rami/$id",
  path: "/rami/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedTournamentsIdRoute = Route$7.update({
  id: "/tournaments_/$id",
  path: "/tournaments/$id",
  getParentRoute: () => AuthenticatedRoute
});
const AuthenticatedJeuxChessIdRoute = Route$6.update({
  id: "/chess/$id",
  path: "/chess/$id",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxDominoIdRoute = Route$5.update({
  id: "/domino/$id",
  path: "/domino/$id",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxFanoronaIdRoute = Route$4.update({
  id: "/fanorona/$id",
  path: "/fanorona/$id",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxLudoIdRoute = Route$3.update({
  id: "/ludo/$id",
  path: "/ludo/$id",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxNouveauSlugRoute = Route$2.update({
  id: "/nouveau/$slug",
  path: "/nouveau/$slug",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxPokerIdRoute = Route$1.update({
  id: "/poker/$id",
  path: "/poker/$id",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxRamiIdRoute = Route.update({
  id: "/rami/$id",
  path: "/rami/$id",
  getParentRoute: () => AuthenticatedJeuxRoute
});
const AuthenticatedJeuxRouteChildren = {
  AuthenticatedJeuxSlugRoute,
  AuthenticatedJeuxIndexRoute,
  AuthenticatedJeuxChessIdRoute,
  AuthenticatedJeuxDominoIdRoute,
  AuthenticatedJeuxFanoronaIdRoute,
  AuthenticatedJeuxLudoIdRoute,
  AuthenticatedJeuxNouveauSlugRoute,
  AuthenticatedJeuxPokerIdRoute,
  AuthenticatedJeuxRamiIdRoute
};
const AuthenticatedJeuxRouteWithChildren = AuthenticatedJeuxRoute._addFileChildren(AuthenticatedJeuxRouteChildren);
const AuthenticatedRouteChildren = {
  AuthenticatedAdminRoute,
  AuthenticatedAdminBugReportsRoute,
  AuthenticatedChatRoute,
  AuthenticatedFaqRoute,
  AuthenticatedHistoryRoute,
  AuthenticatedJeuxRoute: AuthenticatedJeuxRouteWithChildren,
  AuthenticatedLiveRoute,
  AuthenticatedLobbyRoute,
  AuthenticatedParametresRoute,
  AuthenticatedParrainageRoute,
  AuthenticatedProfileRoute,
  AuthenticatedRankingsRoute,
  AuthenticatedSecuriteRoute,
  AuthenticatedStatistiquesRoute,
  AuthenticatedTournamentsRoute,
  AuthenticatedTutosRoute,
  AuthenticatedChessIdRoute,
  AuthenticatedDiscussionSlugRoute,
  AuthenticatedDominoIdRoute,
  AuthenticatedFanoronaIdRoute,
  AuthenticatedGameIdRoute,
  AuthenticatedJoueurIdRoute,
  AuthenticatedPokerIdRoute,
  AuthenticatedRamiIdRoute,
  AuthenticatedTournamentsIdRoute
};
const AuthenticatedRouteWithChildren = AuthenticatedRoute._addFileChildren(
  AuthenticatedRouteChildren
);
const rootRouteChildren = {
  IndexRoute,
  AuthenticatedRoute: AuthenticatedRouteWithChildren,
  CguRoute,
  ConfidentialiteRoute,
  JeuxPublicsRoute,
  LoginRoute,
  ResetPasswordRoute,
  ApiLinkPreviewRoute,
  ApiTranslateRoute
};
const routeTree = Route$H._addFileChildren(rootRouteChildren)._addFileTypes();
const getRouter = () => {
  const queryClient = new QueryClient();
  const router2 = createRouter({
    routeTree,
    context: { queryClient },
    scrollRestoration: true,
    defaultPreloadStaleTime: 0
  });
  return router2;
};
const router = /* @__PURE__ */ Object.freeze(/* @__PURE__ */ Object.defineProperty({
  __proto__: null,
  getRouter
}, Symbol.toStringTag, { value: "Module" }));
export {
  Route$4 as A,
  Button as B,
  COVER_BY_SLUG$1 as C,
  Route$3 as D,
  Route$2 as E,
  petanqueCover as F,
  COVER_BY_SLUG as G,
  Route$1 as H,
  Route as I,
  router as J,
  PageLoader as P,
  Route$x as R,
  StatusPill as S,
  useT as a,
  useConfirm as b,
  copyText as c,
  Route$g as d,
  chessCover as e,
  facebookTargets as f,
  fanoronaCover as g,
  dominoCover as h,
  invalidateCmsCache as i,
  ramiImg as j,
  chessImg as k,
  ludoCover as l,
  fanoronaImg as m,
  dominoImg as n,
  openExternal as o,
  pokerImg as p,
  ludoImg as q,
  ramiCover as r,
  Route$b as s,
  pokerCover as t,
  useAuth as u,
  cn as v,
  whatsappTargets as w,
  Route$a as x,
  Route$6 as y,
  Route$5 as z
};
