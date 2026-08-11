import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { u as useAuth, c as copyText } from "./router-CRCBvenY.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { toast } from "../_libs/sonner.mjs";
import { compressImageToWebp } from "./image-compress-U7tauI3l.mjs";
import { u as useAppSettings, D as DepotModal, R as RetraitModal } from "./WalletButton-BwZT8Njg.mjs";
import { D as Dialog, a as DialogContent, b as DialogHeader, c as DialogTitle } from "./dialog-BkiCxqYs.mjs";
import { P as PremiumSubscriptionModal } from "./PremiumSubscriptionModal-CtNhxpDU.mjs";
import "../_libs/capacitor__core.mjs";
import "../_libs/capacitor__push-notifications.mjs";
import { an as Camera, a5 as ShieldCheck, aI as ShieldAlert, P as Phone, d as Copy, r as Send, a0 as ArrowDownLeft, $ as ArrowUpRight, G as Gamepad2, c as Gift, a as Trophy, b as ChevronRight, ad as Settings, y as Shield, m as CircleQuestionMark, a4 as FileText, ay as Crown, Q as LogOut, ao as Trash2, T as TriangleAlert, X, a6 as EyeOff, a7 as Eye, q as LoaderCircle } from "../_libs/lucide-react.mjs";
import "../_libs/tanstack__router-core.mjs";
import "../_libs/tanstack__history.mjs";
import "../_libs/cookie-es.mjs";
import "../_libs/seroval.mjs";
import "../_libs/seroval-plugins.mjs";
import "node:stream/web";
import "node:stream";
import "../_libs/react-dom.mjs";
import "util";
import "crypto";
import "async_hooks";
import "stream";
import "../_libs/isbot.mjs";
import "../_libs/tanstack__query-core.mjs";
import "../_libs/tanstack__react-query.mjs";
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
function DeleteAccountDialog({ open, onClose }) {
  const { signOut, user } = useAuth();
  const navigate = useNavigate();
  const [step, setStep] = reactExports.useState("warn");
  const [password, setPassword] = reactExports.useState("");
  const [showPwd, setShowPwd] = reactExports.useState(false);
  const [busy, setBusy] = reactExports.useState(false);
  const [error, setError] = reactExports.useState("");
  if (!open) return null;
  const handleClose = () => {
    setStep("warn");
    setPassword("");
    setError("");
    onClose();
  };
  const handleDelete = async () => {
    if (!password.trim()) {
      setError("Veuillez saisir votre mot de passe.");
      return;
    }
    setBusy(true);
    setError("");
    const { error: authErr } = await supabase.auth.signInWithPassword({
      email: user?.email || "",
      password
    });
    if (authErr) {
      setBusy(false);
      setError("Mot de passe incorrect. Veuillez réessayer.");
      return;
    }
    const { error: delErr } = await supabase.rpc("delete_my_account");
    if (delErr) {
      setBusy(false);
      setError(delErr.message);
      return;
    }
    await signOut();
    toast.success("Votre compte a été supprimé définitivement.");
    navigate({ to: "/login" });
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex items-end sm:items-center justify-center p-4 bg-black/60 backdrop-blur-sm", onClick: (e) => {
    if (e.target === e.currentTarget) handleClose();
  }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "w-full max-w-sm rounded-3xl bg-card shadow-2xl border border-border/60 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "bg-destructive/10 px-5 pt-5 pb-4 border-b border-destructive/20", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-start justify-between gap-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-10 h-10 rounded-2xl bg-destructive/20 flex items-center justify-center shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsx(TriangleAlert, { className: "w-5 h-5 text-destructive" }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-extrabold text-base text-destructive", children: "Supprimer mon compte" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xs text-muted-foreground mt-0.5", children: "Cette action est irréversible" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: handleClose, className: "p-1.5 rounded-xl hover:bg-secondary mt-0.5", children: /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4 text-muted-foreground" }) })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-5 space-y-4", children: step === "warn" ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-2 text-sm", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "font-semibold", children: "En supprimant votre compte :" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("ul", { className: "space-y-1.5 text-muted-foreground", children: [
          "Votre profil, pseudo et photo disparaîtront",
          "Votre solde de {{balance}} Ar sera perdu",
          "Votre historique de parties sera effacé",
          "Vos parrainages et bonus seront annulés",
          "Vous ne pourrez plus vous reconnecter"
        ].map((item, i) => /* @__PURE__ */ jsxRuntimeExports.jsxs("li", { className: "flex items-start gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-destructive mt-0.5 shrink-0", children: "✕" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: item.replace("{{balance}}", "votre") })
        ] }, i)) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: handleClose, className: "flex-1 py-3 rounded-full bg-secondary font-semibold text-sm", children: "Annuler" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs(
          "button",
          {
            onClick: () => setStep("password"),
            className: "flex-1 py-3 rounded-full bg-destructive text-destructive-foreground font-semibold text-sm flex items-center justify-center gap-2",
            children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }),
              " Continuer"
            ]
          }
        )
      ] })
    ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm text-muted-foreground", children: [
        "Pour confirmer la suppression de votre compte, saisissez votre ",
        /* @__PURE__ */ jsxRuntimeExports.jsx("strong", { children: "mot de passe" }),
        " :"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "input",
          {
            type: showPwd ? "text" : "password",
            value: password,
            onChange: (e) => {
              setPassword(e.target.value);
              setError("");
            },
            placeholder: "Votre mot de passe",
            autoFocus: true,
            className: `w-full px-4 py-3 rounded-2xl bg-secondary border outline-none pr-12 text-sm ${error ? "border-destructive" : "border-border"}`,
            onKeyDown: (e) => e.key === "Enter" && handleDelete()
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            type: "button",
            onClick: () => setShowPwd(!showPwd),
            className: "absolute right-3 top-1/2 -translate-y-1/2 p-1.5 text-muted-foreground hover:text-foreground",
            children: showPwd ? /* @__PURE__ */ jsxRuntimeExports.jsx(EyeOff, { className: "w-4 h-4" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Eye, { className: "w-4 h-4" })
          }
        )
      ] }),
      error && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm text-destructive font-medium flex items-center gap-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(TriangleAlert, { className: "w-4 h-4 shrink-0" }),
        " ",
        error
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            onClick: () => {
              setStep("warn");
              setPassword("");
              setError("");
            },
            className: "flex-1 py-3 rounded-full bg-secondary font-semibold text-sm",
            children: "Retour"
          }
        ),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            onClick: handleDelete,
            disabled: busy || !password.trim(),
            className: "flex-1 py-3 rounded-full bg-destructive text-destructive-foreground font-semibold text-sm flex items-center justify-center gap-2 disabled:opacity-50",
            children: busy ? /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "animate-spin", children: "⏳" }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }),
              " Supprimer"
            ] })
          }
        )
      ] })
    ] }) })
  ] }) });
}
const EMOJI = {
  ludo: "🎲",
  chess: "♜",
  domino: "🁣",
  fanorona: "♟",
  rami: "🂡",
  poker: "🃏"
};
const LABEL = {
  ludo: "Ludo",
  chess: "Échecs",
  domino: "Domino",
  fanorona: "Fanorona",
  rami: "Rami",
  poker: "Poker"
};
const ROUTE = {
  ludo: "/jeux/ludo/$id",
  chess: "/jeux/chess/$id",
  domino: "/jeux/domino/$id",
  fanorona: "/jeux/fanorona/$id",
  rami: "/jeux/rami/$id",
  poker: "/jeux/poker/$id"
};
const PART_TABLE = {
  domino: "domino_participants",
  fanorona: "fanorona_participants",
  rami: "rami_participants",
  poker: "poker_players"
};
const GAME_TABLE = {
  domino: "domino_games",
  fanorona: "fanorona_games",
  rami: "rami_games",
  poker: "poker_games"
};
function fmtDate(d) {
  if (!d) return "—";
  return new Date(d).toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "2-digit" });
}
function fmtAr(n) {
  if (n == null) return "—";
  return new Intl.NumberFormat("fr-MG").format(Math.round(Number(n) || 0)) + " Ar";
}
function useAllMatches(userId) {
  const [matches, setMatches] = reactExports.useState([]);
  const [loaded, setLoaded] = reactExports.useState(false);
  const [loading, setLoading] = reactExports.useState(false);
  const load = reactExports.useCallback(async () => {
    if (!userId) return;
    setLoading(true);
    try {
      const uid = userId;
      const all = [];
      const { data: ludoData } = await supabase.rpc("my_games");
      const ludo = ludoData || { ongoing: [], finished: [] };
      (ludo.finished || []).forEach((g) => all.push({ ...g, slug: "ludo" }));
      const { data: chessRows } = await supabase.from("chess_games").select("*").or(`white_id.eq.${uid},black_id.eq.${uid}`).order("created_at", { ascending: false }).limit(100);
      (chessRows || []).forEach((g) => {
        if (g.status === "finished") {
          all.push({ ...g, slug: "chess", won: g.winner_id === uid });
        }
      });
      await Promise.all(
        Object.entries(PART_TABLE).map(async ([slug, partTable]) => {
          if (!partTable) return;
          const { data: parts } = await supabase.from(partTable).select(`*, game:${GAME_TABLE[slug]}(*)`).eq("user_id", uid);
          (parts || []).forEach((r) => {
            const g = r.game;
            if (!g) return;
            if (g.status === "finished") {
              all.push({ ...g, slug, won: g.winner_id === uid, forfeited: r.forfeited });
            }
          });
        })
      );
      all.sort(
        (a, b) => new Date(b.finished_at || b.created_at || 0).getTime() - new Date(a.finished_at || a.created_at || 0).getTime()
      );
      setMatches(all);
    } finally {
      setLoading(false);
      setLoaded(true);
    }
  }, [userId]);
  return { matches, loaded, loading, load };
}
function MatchListDialog({
  open,
  onClose,
  dialogType,
  matches,
  loading
}) {
  const navigate = useNavigate();
  const filtered = dialogType === "wins" ? matches.filter((m) => m.won === true) : dialogType === "losses" ? matches.filter((m) => m.status === "finished" && m.won !== true) : matches;
  const title = dialogType === "wins" ? "Victoires" : dialogType === "losses" ? "Défaites" : "Toutes les parties";
  const icon = dialogType === "wins" ? /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-5 h-5 text-emerald-500" }) : dialogType === "losses" ? /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-5 h-5 rotate-90 text-destructive" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-5 h-5 text-primary" });
  const goToGame = (g) => {
    const route = ROUTE[g.slug];
    if (!route) return;
    onClose();
    navigate({ to: route, params: { id: g.id } });
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Dialog, { open, onOpenChange: (o) => {
    if (!o) onClose();
  }, children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogContent, { className: "max-w-md max-h-[80vh] flex flex-col p-0 gap-0", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(DialogHeader, { className: "px-4 pt-4 pb-2 border-b border-border/30 shrink-0", children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogTitle, { className: "flex items-center gap-2 text-base font-extrabold", children: [
      icon,
      " ",
      title,
      /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-muted-foreground font-normal text-sm", children: [
        "(",
        filtered.length,
        ")"
      ] })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "overflow-y-auto flex-1 px-4 py-3 space-y-2", children: loading ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex justify-center py-8", children: /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "w-6 h-6 animate-spin text-primary" }) }) : filtered.length === 0 ? /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-center py-8 text-sm text-muted-foreground", children: "Aucune partie." }) : filtered.map((g) => {
      const isWin = g.won === true;
      const isLoss = g.status === "finished" && !isWin;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => goToGame(g),
          className: "w-full rounded-xl bg-secondary/40 border border-border/30 p-3 flex items-center gap-3 active:scale-[0.98] transition-transform text-left",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-10 h-10 rounded-xl flex items-center justify-center text-lg shrink-0 ${isWin ? "bg-emerald-500/10 border border-emerald-500/20" : isLoss ? "bg-destructive/10 border border-destructive/20" : "bg-secondary border border-border/40"}`, children: EMOJI[g.slug] ?? "🎮" }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "min-w-0 flex-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-bold text-sm flex items-center gap-1.5", children: [
                LABEL[g.slug] ?? g.slug,
                isWin && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-emerald-500", children: "VICTOIRE" }),
                isLoss && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] font-bold text-destructive", children: "DÉFAITE" })
              ] }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-0.5", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[11px] text-muted-foreground", children: [
                  "Mise ",
                  fmtAr(g.stake)
                ] }),
                g.winner_name && /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] text-muted-foreground/70", children: [
                  "Gagnant: ",
                  g.winner_name
                ] })
              ] })
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right shrink-0", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground", children: fmtDate(g.finished_at || g.created_at) }),
              /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-4 h-4 text-muted-foreground mt-0.5 ml-auto" })
            ] })
          ]
        },
        `${g.slug}-${g.id}`
      );
    }) })
  ] }) });
}
const BADGES = [{
  min: 0,
  label: "Bronze",
  color: "from-amber-700 to-amber-500",
  icon: "🥉"
}, {
  min: 2,
  label: "Argent",
  color: "from-slate-400 to-slate-300",
  icon: "🥈"
}, {
  min: 3,
  label: "Or",
  color: "from-yellow-500 to-amber-400",
  icon: "🥇"
}, {
  min: 4,
  label: "Diamant",
  color: "from-cyan-400 to-blue-500",
  icon: "💎"
}, {
  min: 5,
  label: "Platine",
  color: "from-violet-500 to-fuchsia-500",
  icon: "👑"
}];
function getBadge(level) {
  let b = BADGES[0];
  for (const bd of BADGES) if (level >= bd.min) b = bd;
  return b;
}
const MIN_WITHDRAWAL = 2e3;
function TransferDialog({
  open,
  onClose,
  balance,
  onSent
}) {
  const [recipient, setRecipient] = reactExports.useState("");
  const [amount, setAmount] = reactExports.useState("");
  const [sending, setSending] = reactExports.useState(false);
  const [searchResults, setSearchResults] = reactExports.useState([]);
  const [searching, setSearching] = reactExports.useState(false);
  reactExports.useEffect(() => {
    if (!recipient.trim() || recipient.trim().length < 2) {
      setSearchResults([]);
      return;
    }
    const timer = setTimeout(async () => {
      setSearching(true);
      const q = recipient.trim();
      const {
        data
      } = await supabase.from("profiles").select("id, pseudo, phone, avatar_url").or(`pseudo.ilike.%${q}%,phone.ilike.%${q}%`).limit(5);
      setSearchResults(data || []);
      setSearching(false);
    }, 300);
    return () => clearTimeout(timer);
  }, [recipient]);
  const doTransfer = async () => {
    const amt = parseInt(amount);
    if (!recipient.trim()) return toast.error("Entrez le numéro ou pseudo du destinataire");
    if (!amt || amt < 100) return toast.error("Montant minimum: 100 Ar");
    if (amt > balance) return toast.error("Solde insuffisant");
    setSending(true);
    try {
      const {
        data,
        error
      } = await supabase.rpc("transfer_balance", {
        _recipient: recipient.trim(),
        _amount: amt
      });
      if (error) throw error;
      toast.success(`Transfert de ${amt.toLocaleString("fr-FR")} Ar envoyé à ${data?.recipient || recipient} !`);
      setRecipient("");
      setAmount("");
      setSearchResults([]);
      onSent();
      onClose();
    } catch (e) {
      toast.error(e.message || "Erreur lors du transfert");
    } finally {
      setSending(false);
    }
  };
  return /* @__PURE__ */ jsxRuntimeExports.jsx(Dialog, { open, onOpenChange: (v) => !v && onClose(), children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogContent, { className: "max-w-sm", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(DialogHeader, { children: /* @__PURE__ */ jsxRuntimeExports.jsxs(DialogTitle, { className: "text-center flex items-center justify-center gap-1.5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-4 h-4 text-primary" }),
      " Transférer du solde"
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "pt-2 space-y-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-xl bg-primary/5 border border-primary/20 px-3 py-2 text-center", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[10px] text-muted-foreground uppercase font-semibold", children: "Solde actuel" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xl font-black text-primary tabular-nums", children: [
          Math.round(balance).toLocaleString("fr-FR"),
          " ",
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs", children: "Ar" })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-[10px] font-semibold text-muted-foreground uppercase tracking-wide", children: "Destinataire" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: recipient, onChange: (e) => setRecipient(e.target.value), placeholder: "Numéro de téléphone ou pseudo", className: "w-full mt-0.5 px-3 py-2 rounded-xl bg-card border border-border outline-none text-sm focus:border-primary/50 transition-colors", autoFocus: true }),
        searchResults.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute z-10 mt-1 w-full rounded-xl border border-border bg-popover shadow-lg overflow-hidden", children: searchResults.map((u) => /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
          setRecipient(u.phone || u.pseudo);
          setSearchResults([]);
        }, className: "w-full flex items-center gap-2 px-3 py-2 hover:bg-accent/30 transition-colors text-left border-b border-border/20 last:border-0", children: [
          u.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: u.avatar_url, alt: "", className: "w-7 h-7 rounded-full object-cover" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-7 h-7 rounded-full bg-primary/10 flex items-center justify-center text-xs font-bold text-primary", children: (u.pseudo || "?").slice(0, 2).toUpperCase() }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-semibold truncate", children: u.pseudo }),
            u.phone && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] text-muted-foreground truncate", children: u.phone })
          ] })
        ] }, u.id)) }),
        searching && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute z-10 mt-1 w-full text-center text-xs text-muted-foreground py-1", children: "Recherche…" })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("label", { className: "text-[10px] font-semibold text-muted-foreground uppercase tracking-wide", children: "Montant (Ar)" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("input", { type: "number", value: amount, onChange: (e) => setAmount(e.target.value), placeholder: "100", min: "100", className: "w-full mt-0.5 px-3 py-2 rounded-xl bg-card border border-border outline-none text-sm focus:border-primary/50 transition-colors" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1.5 mt-1.5", children: [500, 1e3, 5e3, 1e4].map((amt) => /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => setAmount(String(amt)), className: "flex-1 px-1 py-1 rounded-lg bg-secondary/60 text-xs font-semibold hover:bg-primary/10 hover:text-primary transition-colors", children: amt.toLocaleString("fr-FR") }, amt)) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: doTransfer, disabled: sending, className: "w-full flex items-center justify-center gap-1.5 py-2.5 rounded-xl bg-primary text-primary-foreground text-sm font-bold active:scale-95 transition-transform disabled:opacity-50", children: sending ? "Envoi…" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-3.5 h-3.5" }),
        " Envoyer"
      ] }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-[10px] text-muted-foreground text-center leading-tight", children: "Transfert instantané · Min 100 Ar · Max 500 000 Ar" })
    ] })
  ] }) });
}
function Section({
  icon: Icon,
  title,
  children
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 overflow-hidden", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 px-4 py-3 border-b border-border/30 bg-secondary/30", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-4 h-4 text-primary" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: title })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "p-4", children })
  ] });
}
function BalanceAction({
  icon: Icon,
  label,
  action
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: action, className: "flex flex-col items-center gap-1.5 py-3 flex-1 hover:bg-primary/5 active:scale-95 transition-all", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: "w-5 h-5 text-primary", strokeWidth: 2 }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-[11px] font-semibold text-foreground/80", children: label })
  ] });
}
function ListRow({
  icon: Icon,
  label,
  action,
  color,
  danger
}) {
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: action, className: `w-full flex items-center gap-3 px-1 py-3 border-b border-border/20 last:border-0 hover:bg-accent/20 active:scale-[0.99] transition-all ${danger ? "text-destructive" : ""}`, children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: `w-5 h-5 ${color || "text-primary"}`, strokeWidth: 2 }),
    /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "flex-1 text-left text-sm font-semibold", children: label }),
    !danger && /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-4 h-4 text-muted-foreground" })
  ] });
}
function ProfilePage() {
  const {
    user,
    profile,
    refreshProfile,
    signOut
  } = useAuth();
  const navigate = useNavigate();
  const [pseudo, setPseudo] = reactExports.useState(profile?.pseudo || "");
  const [editingName, setEditingName] = reactExports.useState(false);
  const [uploading, setUploading] = reactExports.useState(false);
  const [playerStats, setPlayerStats] = reactExports.useState(null);
  const [myRank, setMyRank] = reactExports.useState(null);
  const [rankLoaded, setRankLoaded] = reactExports.useState(false);
  const fileRef = reactExports.useRef(null);
  const [showDeleteDialog, setShowDeleteDialog] = reactExports.useState(false);
  const [showDeposit, setShowDeposit] = reactExports.useState(false);
  const [showRetrait, setShowRetrait] = reactExports.useState(false);
  const [showTransfer, setShowTransfer] = reactExports.useState(false);
  const [showSubscription, setShowSubscription] = reactExports.useState(false);
  const [gameLimits, setGameLimits] = reactExports.useState(null);
  const appSettings = useAppSettings();
  const [statsDialog, setStatsDialog] = reactExports.useState(null);
  const {
    matches,
    loaded: matchesLoaded,
    loading: matchesLoading,
    load: loadMatches
  } = useAllMatches(user?.id);
  const openStats = (type) => {
    setStatsDialog(type);
    if (!matchesLoaded) loadMatches();
  };
  reactExports.useEffect(() => {
    setPseudo(profile?.pseudo || "");
  }, [profile?.pseudo]);
  reactExports.useEffect(() => {
    if (!user) return;
    const uid = user.id;
    const currentPseudo = profile?.pseudo;
    supabase.from("v_player_stats").select("*").eq("id", uid).maybeSingle().then(({
      data
    }) => {
      if (data) setPlayerStats(data);
    });
    supabase.rpc("leaderboard_winners", {
      _limit: 200
    }).then(({
      data
    }) => {
      setRankLoaded(true);
      if (!data) return;
      const idx = data.findIndex((r) => r.id === uid || currentPseudo && r.name === currentPseudo);
      if (idx >= 0) setMyRank(data[idx].rank);
    });
    supabase.rpc("get_game_limits").then(({
      data
    }) => {
      if (data && !data.error) setGameLimits(data);
    });
  }, [user?.id, profile?.pseudo]);
  const savePseudo = async () => {
    if (!pseudo.trim() || pseudo === profile?.pseudo) {
      setEditingName(false);
      return;
    }
    const {
      error
    } = await supabase.from("profiles").update({
      pseudo: pseudo.trim()
    }).eq("id", user.id);
    if (error) return toast.error(error.message);
    toast.success("Pseudo mis à jour");
    refreshProfile();
    setEditingName(false);
  };
  const upload = async (rawFile) => {
    if (!user || !rawFile) return;
    setUploading(true);
    const f = await compressImageToWebp(rawFile, {
      maxDim: 512,
      maxSizeKB: 200
    });
    const ext = f.name.split(".").pop();
    const path = `${user.id}/avatar.${ext}`;
    const {
      error: upErr
    } = await supabase.storage.from("avatars").upload(path, f, {
      upsert: true,
      contentType: f.type
    });
    if (upErr) {
      setUploading(false);
      return toast.error(upErr.message);
    }
    const {
      data: {
        publicUrl
      }
    } = supabase.storage.from("avatars").getPublicUrl(path);
    const url = `${publicUrl}?t=${Date.now()}`;
    const {
      error
    } = await supabase.from("profiles").update({
      avatar_url: url
    }).eq("id", user.id);
    setUploading(false);
    if (error) return toast.error(error.message);
    toast.success("Photo mise à jour");
    refreshProfile();
  };
  if (!profile) return /* @__PURE__ */ jsxRuntimeExports.jsx("main", { className: "p-8 text-center text-muted-foreground", children: "Chargement…" });
  const p = profile;
  const ps = playerStats || {};
  const displayName = profile.pseudo || user?.email?.split("@")[0] || "Joueur";
  const initials = displayName.slice(0, 2).toUpperCase();
  const totalWins = ps.total_wins ?? p.total_wins ?? 0;
  const totalGames = ps.total_games ?? p.total_games ?? 0;
  const level = ps.player_level ?? 1;
  const totalLosses = totalGames - totalWins;
  const badge = getBadge(level);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "mx-auto max-w-md flex flex-col gap-3 p-3 pb-20 min-h-screen", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("input", { ref: fileRef, type: "file", accept: "image/*", className: "hidden", onChange: (e) => e.target.files?.[0] && upload(e.target.files[0]) }),
    showDeleteDialog && /* @__PURE__ */ jsxRuntimeExports.jsx(DeleteAccountDialog, { open: showDeleteDialog, onClose: () => setShowDeleteDialog(false) }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(DepotModal, { open: showDeposit, onClose: () => setShowDeposit(false), mvolaPhone: appSettings.mvolaPhone, mvolaName: appSettings.mvolaName, orangePhone: appSettings.orangePhone, orangeName: appSettings.orangeName, airtelPhone: appSettings.airtelPhone, airtelName: appSettings.airtelName, minDeposit: appSettings.minDeposit, onSuccess: () => {
      refreshProfile();
    } }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(RetraitModal, { open: showRetrait, onClose: () => setShowRetrait(false), balance: profile.balance_ar, minRetrait: MIN_WITHDRAWAL, onSuccess: () => {
      refreshProfile();
    } }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 p-4 flex items-center gap-3", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative shrink-0", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-16 h-16 rounded-full p-[2px] bg-gradient-to-br ${badge.color}`, children: /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-full h-full rounded-full bg-secondary flex items-center justify-center text-lg font-black overflow-hidden", children: profile.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: profile.avatar_url, alt: "", className: "w-full h-full object-cover rounded-full" }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-primary", children: initials }) }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: () => fileRef.current?.click(), disabled: uploading, className: "absolute -bottom-1 -right-1 p-1.5 rounded-full bg-primary text-primary-foreground ring-2 ring-card active:scale-90 transition-transform shadow-md", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Camera, { className: "w-3 h-3", strokeWidth: 2.5 }) })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
        editingName ? /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex gap-1", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("input", { value: pseudo, onChange: (e) => setPseudo(e.target.value), onKeyDown: (e) => e.key === "Enter" && savePseudo(), autoFocus: true, className: "flex-1 px-2 py-1 rounded-lg bg-card border border-border outline-none text-sm font-bold" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: savePseudo, className: "px-3 py-1 rounded-lg bg-primary text-primary-foreground text-xs font-bold", children: "OK" })
        ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setEditingName(true), className: "flex items-center gap-1.5 hover:text-primary transition-colors", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-black text-lg leading-tight truncate", children: displayName }),
          p.phone_verified ? /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldCheck, { className: "w-4 h-4 text-emerald-500 shrink-0" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(ShieldAlert, { className: "w-4 h-4 text-amber-500 shrink-0" })
        ] }),
        p.phone && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 mt-1 text-sm text-muted-foreground", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Phone, { className: "w-3.5 h-3.5 shrink-0" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "truncate", children: p.phone })
        ] }),
        profile.unique_code && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => copyText(profile.unique_code).then((ok) => toast[ok ? "success" : "error"](ok ? "ID copié !" : "Erreur")), className: "inline-flex items-center gap-0.5 text-[11px] text-muted-foreground font-mono hover:text-foreground transition-colors mt-0.5", children: [
          "ID: ",
          profile.unique_code,
          " ",
          /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-3 h-3" })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl overflow-hidden border border-primary/20", style: {
      background: "linear-gradient(160deg, var(--primary) 0%, transparent 120%)",
      backgroundColor: "var(--card)"
    }, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-4 py-3 flex items-center justify-between gap-2", style: {
        background: "linear-gradient(135deg, color-mix(in oklch, var(--primary) 14%, var(--card)) 0%, color-mix(in oklch, var(--primary) 4%, var(--card)) 100%)"
      }, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] font-bold uppercase tracking-wide text-primary/80", children: "Solde disponible" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-2xl font-black text-primary tabular-nums leading-tight mt-0.5", children: [
            Math.round(profile.balance_ar).toLocaleString("fr-FR"),
            /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-sm font-bold text-muted-foreground ml-1", children: "Ar" })
          ] })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setShowTransfer(true), className: "flex items-center gap-1.5 px-3 py-2 rounded-xl bg-primary text-primary-foreground text-xs font-bold active:scale-95 transition-transform shadow-sm", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Send, { className: "w-3.5 h-3.5" }),
          " Transférer"
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex divide-x divide-primary/10 border-t border-primary/10", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(BalanceAction, { icon: ArrowDownLeft, label: "Dépôt", action: () => setShowDeposit(true) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(BalanceAction, { icon: ArrowUpRight, label: "Retrait", action: () => setShowRetrait(true) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(BalanceAction, { icon: Gamepad2, label: "Historique", action: () => navigate({
          to: "/history",
          search: {}
        }) }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(BalanceAction, { icon: Gift, label: "Parrainage", action: () => navigate({
          to: "/parrainage",
          search: {}
        }) })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(TransferDialog, { open: showTransfer, onClose: () => setShowTransfer(false), balance: Number(profile.balance_ar) || 0, onSent: refreshProfile }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card border border-border/40 overflow-hidden", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2 px-4 py-2.5 border-b border-border/30 bg-secondary/30", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-4 h-4 text-primary" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-bold text-sm", children: "Statistiques" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-2 text-[10px] font-semibold text-muted-foreground", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-0.5", children: [
            badge.icon,
            " Niv.",
            level
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "flex items-center gap-0.5", children: [
            "🥇 ",
            rankLoaded ? myRank ?? "—" : "…"
          ] })
        ] })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-3 gap-1.5 p-3", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openStats("all"), className: "flex flex-col items-center justify-center rounded-lg bg-secondary/40 p-1.5 text-center active:scale-95 transition-transform", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Gamepad2, { className: "w-3.5 h-3.5 text-muted-foreground mb-0.5" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-black tabular-nums leading-none", children: totalGames }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[8px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5", children: "Parties" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openStats("wins"), className: "flex flex-col items-center justify-center rounded-lg bg-secondary/40 p-1.5 text-center active:scale-95 transition-transform", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3.5 h-3.5 text-emerald-500 mb-0.5" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-black tabular-nums leading-none text-emerald-500", children: totalWins }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[8px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5", children: "Victoires" })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => openStats("losses"), className: "flex flex-col items-center justify-center rounded-lg bg-secondary/40 p-1.5 text-center active:scale-95 transition-transform", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(ChevronRight, { className: "w-3.5 h-3.5 rotate-90 text-destructive mb-0.5" }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-sm font-black tabular-nums leading-none text-destructive", children: totalLosses }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[8px] font-semibold uppercase tracking-wide text-muted-foreground mt-0.5", children: "Défaites" })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(MatchListDialog, { open: statsDialog !== null, onClose: () => setStatsDialog(null), dialogType: statsDialog, matches, loading: matchesLoading }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(Section, { icon: Settings, title: "Plus", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(ListRow, { icon: Shield, label: "Sécurité", color: "text-emerald-500", action: () => navigate({
        to: "/securite",
        search: {}
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(ListRow, { icon: CircleQuestionMark, label: "FAQ", color: "text-orange-500 dark:text-neutral-300", action: () => navigate({
        to: "/faq",
        search: {}
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(ListRow, { icon: FileText, label: "Conditions d'utilisation", color: "text-sky-500", action: () => navigate({
        to: "/cgu",
        search: {}
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(ListRow, { icon: ShieldCheck, label: "Politique de confidentialité", color: "text-sky-500", action: () => navigate({
        to: "/confidentialite",
        search: {}
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(ListRow, { icon: Settings, label: "Paramètres", color: "text-muted-foreground", action: () => navigate({
        to: "/parametres",
        search: {}
      }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx(ListRow, { icon: Crown, label: "Abonnement", color: "text-amber-500", action: () => setShowSubscription(true) })
    ] }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => {
        void signOut();
        window.location.assign("/login");
      }, className: "flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/10 text-destructive text-xs font-bold active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-4 h-4" }),
        " Déconnexion"
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: () => setShowDeleteDialog(true), className: "flex items-center justify-center gap-1.5 px-3 py-2.5 rounded-xl bg-destructive/5 text-destructive/80 text-xs font-bold active:scale-95 transition-transform", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Trash2, { className: "w-4 h-4" }),
        " Supprimer"
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsx(PremiumSubscriptionModal, { open: showSubscription, onClose: () => {
      setShowSubscription(false);
      refreshProfile();
    } })
  ] });
}
export {
  ProfilePage as component
};
