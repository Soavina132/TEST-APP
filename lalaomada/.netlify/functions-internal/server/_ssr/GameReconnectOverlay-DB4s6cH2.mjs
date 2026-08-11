import { r as reactExports, j as jsxRuntimeExports } from "../_libs/react.mjs";
import { e as useNavigate } from "../_libs/tanstack__react-router.mjs";
import { c as confetti } from "../_libs/canvas-confetti.mjs";
import { r as ramiCover, t as pokerCover, l as ludoCover, g as fanoronaCover, h as dominoCover, e as chessCover, b as useConfirm, B as Button, c as copyText } from "./router-CRCBvenY.mjs";
import { s as serverNow } from "./server-time-CGSyl3Jk.mjs";
import { s as setWaitingRoomActive } from "./game-ui-state-y34n01Z_.mjs";
import { toast } from "../_libs/sonner.mjs";
import { s as supabase } from "./client-4UYFom1R.mjs";
import { l as Clock, aX as Frown, s as CircleX, a as Trophy, U as Users, f as Coins, aw as Timer, L as Lock, a1 as Check, d as Copy, e as Share2, X, Q as LogOut, g as Sparkles, ay as Crown, aK as RotateCw, q as LoaderCircle, aY as WifiOff, ab as RefreshCw, T as TriangleAlert, aZ as Vote, k as CircleCheck, ag as Pause, av as Play, a_ as UserX } from "../_libs/lucide-react.mjs";
function GameEndScreen({
  slug,
  meUserId,
  winnerId,
  winnerSlot,
  participants,
  stake,
  pot,
  commissionPct = 10,
  extra,
  onReplay
}) {
  const [busy, setBusy] = reactExports.useState(null);
  const confirm = useConfirm();
  const navigate = useNavigate();
  const winner = (winnerId != null ? participants.find((p) => p.user_id === winnerId) : void 0) || (winnerSlot !== null && winnerSlot !== void 0 ? participants.find((p) => p.slot === winnerSlot) : void 0);
  const winnerResolved = !!winnerId || winnerSlot !== null && winnerSlot !== void 0;
  const iWon = !!meUserId && (winnerId === meUserId || winner?.user_id === meUserId);
  const isDraw = !winnerResolved;
  const payout = Math.round(pot * (100 - commissionPct) / 100);
  const handleQuit = async () => {
    if (busy) return;
    setBusy("quit");
    try {
      await navigate({ to: "/jeux" });
    } finally {
      setBusy(null);
    }
  };
  const handleReplay = async () => {
    if (busy) return;
    if (onReplay) {
      const ok = await confirm({
        title: "Rejouer une partie ?",
        description: stake > 0 ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
          "Une nouvelle partie sera créée avec les mêmes paramètres. Mise :",
          " ",
          /* @__PURE__ */ jsxRuntimeExports.jsxs("b", { children: [
            Number(stake).toLocaleString("fr-FR"),
            " Ar"
          ] }),
          "."
        ] }) : "Une nouvelle partie sera créée avec les mêmes paramètres.",
        confirmLabel: "Rejouer"
      });
      if (!ok) return;
      setBusy("replay");
      try {
        await onReplay();
      } finally {
        setBusy(null);
      }
    } else {
      setBusy("replay");
      try {
        await navigate({ to: "/jeux/$slug", params: { slug } });
      } finally {
        setBusy(null);
      }
    }
  };
  reactExports.useEffect(() => {
    if (!iWon) return;
    const colors = ["#f59e0b", "#fbbf24", "#f97316", "#ef4444", "#10b981", "#3b82f6"];
    const fire = (opts) => confetti({ zIndex: 200, disableForReducedMotion: true, colors, ...opts });
    fire({ particleCount: 90, spread: 70, startVelocity: 55, origin: { y: 0.6 } });
    const t1 = setTimeout(() => {
      fire({ particleCount: 60, angle: 60, spread: 55, origin: { x: 0, y: 0.7 } });
      fire({ particleCount: 60, angle: 120, spread: 55, origin: { x: 1, y: 0.7 } });
    }, 250);
    const t2 = setTimeout(() => {
      fire({ particleCount: 120, spread: 100, startVelocity: 45, origin: { y: 0.5 }, scalar: 1.1 });
    }, 600);
    return () => {
      clearTimeout(t1);
      clearTimeout(t2);
    };
  }, [iWon]);
  const title = iWon ? "Victoire !" : isDraw ? "Match nul" : "Partie terminée";
  const emoji = iWon ? "🏆" : isDraw ? "🤝" : "🎯";
  return /* @__PURE__ */ jsxRuntimeExports.jsx(
    "div",
    {
      role: "dialog",
      "aria-modal": "true",
      className: "fixed inset-0 z-[90] flex items-center justify-center p-4 animate-in fade-in duration-300",
      style: {
        background: "radial-gradient(ellipse at center, rgba(0,0,0,0.55) 0%, rgba(0,0,0,0.85) 100%)",
        backdropFilter: "blur(10px)",
        WebkitBackdropFilter: "blur(10px)"
      },
      children: /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "div",
        {
          className: `relative w-full max-w-md rounded-[28px] overflow-hidden shadow-2xl ${iWon ? "animate-in zoom-in-95 duration-500" : "animate-in fade-in slide-in-from-bottom-4 duration-500"}`,
          children: [
            iWon && /* @__PURE__ */ jsxRuntimeExports.jsx(
              "div",
              {
                "aria-hidden": true,
                className: "pointer-events-none absolute -inset-1 rounded-[32px] opacity-70 blur-xl",
                style: {
                  background: "conic-gradient(from 0deg, #fbbf24, #f97316, #ef4444, #f59e0b, #fbbf24)"
                }
              }
            ),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative rounded-[28px] bg-card", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsxs(
                "div",
                {
                  className: "relative px-6 pt-8 pb-6 text-center overflow-hidden",
                  style: {
                    background: iWon ? "linear-gradient(135deg, rgba(251,191,36,0.18), rgba(249,115,22,0.12) 60%, transparent)" : isDraw ? "linear-gradient(135deg, rgba(59,130,246,0.12), transparent)" : "linear-gradient(135deg, rgba(148,163,184,0.14), transparent)"
                  },
                  children: [
                    iWon && /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Sparkles, { className: "absolute top-3 left-4 w-4 h-4 text-amber-400/70 animate-pulse" }),
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Sparkles, { className: "absolute top-6 right-6 w-3 h-3 text-amber-300/70 animate-pulse" }),
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Sparkles, { className: "absolute bottom-2 left-8 w-3 h-3 text-amber-400/60 animate-pulse" })
                    ] }),
                    /* @__PURE__ */ jsxRuntimeExports.jsx(
                      "div",
                      {
                        className: `mx-auto mb-3 w-20 h-20 rounded-full flex items-center justify-center text-5xl shadow-lg ${iWon ? "animate-bounce" : ""}`,
                        style: {
                          background: iWon ? "linear-gradient(135deg, #fde68a, #f59e0b)" : isDraw ? "linear-gradient(135deg, #dbeafe, #93c5fd)" : "linear-gradient(135deg, hsl(var(--secondary)), hsl(var(--muted)))"
                        },
                        children: emoji
                      }
                    ),
                    /* @__PURE__ */ jsxRuntimeExports.jsx(
                      "h2",
                      {
                        className: `text-2xl font-extrabold tracking-tight ${iWon ? "bg-gradient-to-r from-amber-500 via-orange-500 to-amber-600 bg-clip-text text-transparent" : ""}`,
                        children: title
                      }
                    ),
                    winner && !iWon && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1 text-sm text-muted-foreground flex items-center justify-center gap-1.5", children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsx(Crown, { className: "w-3.5 h-3.5 text-amber-500" }),
                      /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "text-foreground", children: winner.display_name })
                    ] })
                  ]
                }
              ),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "px-6 pb-6 space-y-4 -mt-2", children: [
                /* @__PURE__ */ jsxRuntimeExports.jsxs(
                  "div",
                  {
                    className: "rounded-2xl p-4 flex items-center justify-between shadow-sm",
                    style: {
                      background: iWon ? "linear-gradient(135deg, rgba(16,185,129,0.10), rgba(16,185,129,0.02))" : "hsl(var(--secondary))",
                      border: iWon ? "1px solid rgba(16,185,129,0.35)" : "1px solid hsl(var(--border))"
                    },
                    children: [
                      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase tracking-widest text-muted-foreground font-bold", children: "Mise" }),
                        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-base font-bold mt-0.5", children: [
                          Number(stake).toLocaleString("fr-FR"),
                          " Ar"
                        ] })
                      ] }),
                      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-10 w-px bg-border/60" }),
                      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-right", children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase tracking-widest text-muted-foreground font-bold", children: iWon ? "Vous gagnez" : "Au gagnant" }),
                        /* @__PURE__ */ jsxRuntimeExports.jsxs(
                          "div",
                          {
                            className: `text-lg font-extrabold mt-0.5 ${iWon ? "text-emerald-600" : ""}`,
                            children: [
                              payout.toLocaleString("fr-FR"),
                              " Ar"
                            ]
                          }
                        )
                      ] })
                    ]
                  }
                ),
                participants.length > 0 && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-2xl border border-border/60 divide-y divide-border/40 overflow-hidden", children: participants.map((p) => {
                  const isWin = winner ? p === winner || winnerId != null && p.user_id === winnerId || winner.slot != null && p.slot === winner.slot : false;
                  const isMe = p.user_id === meUserId;
                  return /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "div",
                    {
                      className: `flex items-center justify-between px-3 py-2.5 text-sm ${isWin ? "bg-amber-500/5" : ""}`,
                      children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 min-w-0", children: [
                          /* @__PURE__ */ jsxRuntimeExports.jsx(
                            "div",
                            {
                              className: `w-7 h-7 rounded-full flex items-center justify-center text-xs font-bold shrink-0 ${isWin ? "bg-gradient-to-br from-amber-400 to-orange-500 text-white" : "bg-secondary text-muted-foreground"}`,
                              children: p.display_name?.[0]?.toUpperCase() ?? "?"
                            }
                          ),
                          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "truncate font-medium", children: [
                            p.display_name,
                            isMe && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "ml-1 text-xs text-muted-foreground", children: "(vous)" })
                          ] })
                        ] }),
                        isWin && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1 text-xs font-bold text-amber-600 shrink-0", children: [
                          /* @__PURE__ */ jsxRuntimeExports.jsx(Trophy, { className: "w-3.5 h-3.5" }),
                          "Gagnant"
                        ] })
                      ]
                    },
                    p.user_id
                  );
                }) }),
                extra,
                /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "grid grid-cols-2 gap-2 pt-1", children: [
                  /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "button",
                    {
                      type: "button",
                      onClick: handleQuit,
                      disabled: !!busy,
                      className: "py-3 rounded-full bg-secondary hover:bg-secondary/80 font-bold flex items-center justify-center gap-1.5 transition-colors disabled:opacity-60 active:scale-[0.98]",
                      children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-4 h-4" }),
                        " Quitter"
                      ]
                    }
                  ),
                  /* @__PURE__ */ jsxRuntimeExports.jsxs(
                    "button",
                    {
                      type: "button",
                      onClick: handleReplay,
                      disabled: !!busy,
                      className: "py-3 rounded-full text-white font-bold flex items-center justify-center gap-1.5 shadow-lg disabled:opacity-60 active:scale-[0.98] transition-transform",
                      style: { background: "var(--gradient-primary)" },
                      children: [
                        /* @__PURE__ */ jsxRuntimeExports.jsx(
                          RotateCw,
                          {
                            className: `w-4 h-4 ${busy === "replay" ? "animate-spin" : ""}`
                          }
                        ),
                        busy === "replay" ? "…" : "Rejouer"
                      ]
                    }
                  )
                ] })
              ] })
            ] })
          ]
        }
      )
    }
  );
}
function GameStateMessage({
  state,
  gameLabel,
  slug,
  message
}) {
  const navigate = useNavigate();
  const config = {
    finished: {
      icon: Trophy,
      color: "text-amber-500",
      bg: "bg-amber-500/10",
      border: "border-amber-500/25",
      title: "Partie terminée",
      desc: message ?? "Cette partie est déjà terminée. Vous ne pouvez pas la rejoindre."
    },
    cancelled: {
      icon: CircleX,
      color: "text-slate-400",
      bg: "bg-slate-500/10",
      border: "border-slate-500/25",
      title: "Partie annulée",
      desc: message ?? "Cette partie a été annulée. La mise a été remboursée."
    },
    eliminated: {
      icon: Frown,
      color: "text-destructive",
      bg: "bg-destructive/10",
      border: "border-destructive/25",
      title: "Vous êtes éliminé",
      desc: message ?? "Vous avez été éliminé de cette partie. Vous pouvez la regarder en spectateur."
    },
    expired: {
      icon: Clock,
      color: "text-slate-400",
      bg: "bg-slate-500/10",
      border: "border-slate-500/25",
      title: "Invitation expirée",
      desc: message ?? "Cette partie a expiré faute de joueurs."
    }
  };
  const cfg = config[state];
  const Icon = cfg.icon;
  reactExports.useEffect(() => {
    if (state === "cancelled" || state === "expired") {
      const t = setTimeout(() => {
        navigate({ to: slug ? "/jeux/$slug" : "/jeux", params: slug ? { slug } : void 0 });
      }, 3e3);
      return () => clearTimeout(t);
    }
  }, [state, slug, navigate]);
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("main", { className: "max-w-md mx-auto px-4 py-12 space-y-6", children: [
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-3xl ${cfg.bg} border ${cfg.border} p-8 text-center space-y-4`, children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: `w-16 h-16 rounded-full ${cfg.bg} grid place-items-center mx-auto`, children: /* @__PURE__ */ jsxRuntimeExports.jsx(Icon, { className: `w-8 h-8 ${cfg.color}` }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("h1", { className: "text-xl font-extrabold mb-1", children: cfg.title }),
        gameLabel && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: gameLabel })
      ] }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: cfg.desc })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex flex-col gap-2", children: [
      state === "eliminated" && /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => navigate({ to: "/jeux" }),
          className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition",
          children: "Retour aux jeux"
        }
      ),
      state === "finished" && /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => navigate({ to: "/jeux" }),
          className: "w-full py-3 rounded-2xl bg-primary text-primary-foreground font-bold text-sm active:scale-95 transition",
          children: "Nouvelle partie"
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "button",
        {
          onClick: () => navigate({ to: "/jeux" }),
          className: "w-full py-3 rounded-2xl bg-secondary text-foreground font-bold text-sm active:scale-95 transition",
          children: "Accueil"
        }
      )
    ] })
  ] });
}
const COVERS = {
  chess: { url: chessCover.url, emoji: "♟️", title: "Échecs" },
  domino: { url: dominoCover.url, emoji: "🁣", title: "Domino" },
  fanorona: { url: fanoronaCover.url, emoji: "⚫", title: "Fanorona" },
  ludo: { url: ludoCover.url, emoji: "🎲", title: "Ludo" },
  poker: { url: pokerCover.url, emoji: "🂡", title: "Poker" },
  rami: { url: ramiCover.url, emoji: "🃏", title: "Rami" }
};
function GameWaitingRoom({
  gameLabel,
  parts,
  maxPlayers,
  stake,
  pot,
  roomCode,
  meUserId,
  isParticipant,
  onQuit,
  onToggleReady,
  shareSlug,
  createdAt,
  slug,
  isTournament = false,
  matchType = "solo",
  onJoinTeam
}) {
  const [copied, setCopied] = reactExports.useState(false);
  const [avatars, setAvatars] = reactExports.useState({});
  const [now, setNow] = reactExports.useState(() => serverNow());
  const [timeoutMin, setTimeoutMin] = reactExports.useState(6);
  reactExports.useEffect(() => {
    const t = setInterval(() => setNow(serverNow()), 1e3);
    return () => clearInterval(t);
  }, []);
  reactExports.useEffect(() => {
    setWaitingRoomActive(true);
    return () => setWaitingRoomActive(false);
  }, []);
  reactExports.useEffect(() => {
    supabase.from("app_settings").select("game_invite_timeout_minutes").eq("id", 1).maybeSingle().then(({ data }) => {
      if (data?.game_invite_timeout_minutes) setTimeoutMin(Number(data.game_invite_timeout_minutes));
    });
  }, []);
  const expiresAt = createdAt ? new Date(createdAt).getTime() + timeoutMin * 6e4 : null;
  const remainingMs = expiresAt ? Math.max(0, expiresAt - now) : null;
  const expired = remainingMs !== null && remainingMs === 0;
  const fmt2 = (ms) => {
    const s = Math.ceil(ms / 1e3);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  };
  const empty = Math.max(0, maxPlayers - parts.length);
  const me = parts.find((p) => p.user_id === meUserId);
  const meReady = !!me?.ready;
  const readyCount = parts.filter((p) => p.ready).length;
  const allReady = parts.length === maxPlayers && readyCount === maxPlayers;
  const full = parts.length >= maxPlayers;
  reactExports.useEffect(() => {
    const missing = parts.map((p) => p.user_id).filter((uid) => uid && !avatars[uid]);
    if (!missing.length) return;
    (async () => {
      const { data } = await supabase.from("profiles").select("id,pseudo,avatar_url").in("id", missing);
      const map = {};
      (data || []).forEach((p) => {
        map[p.id] = { pseudo: p.pseudo, avatar_url: p.avatar_url };
      });
      setAvatars((prev) => ({ ...prev, ...map }));
    })();
  }, [parts.map((p) => p.user_id).join(",")]);
  const copyCode = async () => {
    if (!roomCode) return;
    const ok = await copyText(roomCode);
    if (ok) {
      setCopied(true);
      toast.success("Code copié");
      setTimeout(() => setCopied(false), 1500);
    } else toast.error("Impossible de copier");
  };
  const share = async () => {
    if (!roomCode) return;
    const url = `${window.location.origin}/jeux/${shareSlug || ""}?join=${roomCode}`;
    const text = `🎮 Rejoins ma partie !
Jeu : ${gameLabel}
Code : ${roomCode}
Mise : ${Number(stake).toLocaleString("fr-FR")} Ar
Joueurs : ${parts.length}/${maxPlayers}
👉 ${url}`;
    try {
      if (navigator.share) await navigator.share({ title: "Lalao MADA", text, url });
      else {
        const ok = await copyText(text);
        toast[ok ? "success" : "error"](ok ? "Invitation copiée" : "Impossible de copier");
      }
    } catch {
    }
  };
  const cover = slug ? COVERS[slug] : null;
  return /* @__PURE__ */ jsxRuntimeExports.jsxs("section", { className: "space-y-3", children: [
    cover && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "relative rounded-3xl overflow-hidden shadow-2xl", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "img",
        {
          src: cover.url,
          alt: cover.title,
          width: 1024,
          height: 448,
          loading: "lazy",
          decoding: "async",
          className: "w-full object-cover aspect-[16/7]"
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "absolute inset-0 bg-gradient-to-t from-black/90 via-black/45 to-black/10" }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "absolute bottom-4 left-5 right-5 text-white", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[10px] uppercase opacity-70 tracking-[0.2em] font-semibold", children: "Salle d'attente" }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-extrabold text-3xl drop-shadow-xl mt-0.5 flex items-center gap-2", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { "aria-hidden": true, children: cover.emoji }),
          /* @__PURE__ */ jsxRuntimeExports.jsx("span", { children: cover.title })
        ] }),
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 mt-2 flex-wrap", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 bg-white/15 backdrop-blur-sm px-3 py-1 rounded-full text-xs font-semibold border border-white/20", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Users, { className: "w-3.5 h-3.5" }),
            parts.length,
            "/",
            maxPlayers,
            " joueurs"
          ] }),
          Number(stake) > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-1.5 bg-amber-500/20 backdrop-blur-sm px-3 py-1 rounded-full text-xs font-semibold border border-amber-400/30 text-amber-100", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Coins, { className: "w-3.5 h-3.5" }),
            Number(stake).toLocaleString("fr-FR"),
            " Ar"
          ] }),
          remainingMs !== null && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `flex items-center gap-1 rounded-full px-3 py-1 text-xs font-bold border backdrop-blur-sm ${expired ? "bg-red-500/25 border-red-400/40 text-red-100" : remainingMs < 6e4 ? "bg-amber-500/25 border-amber-400/40 text-amber-100" : "bg-white/15 border-white/20 text-white"}`, children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-3.5 h-3.5" }),
            expired ? "Expirée" : fmt2(remainingMs)
          ] })
        ] })
      ] })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-2xl bg-card p-2.5 shadow-[var(--shadow-soft)]", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between gap-2", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-sm font-extrabold min-w-0 truncate", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-primary", children: [
            parts.length,
            "/",
            maxPlayers
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "font-medium text-muted-foreground", children: [
            " joueurs · ",
            gameLabel
          ] })
        ] }),
        remainingMs !== null && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `shrink-0 flex items-center gap-1 rounded-full px-2 py-1 text-[11px] font-bold ${expired ? "bg-destructive/10 text-destructive" : remainingMs < 6e4 ? "bg-amber-500/15 text-amber-700 dark:text-amber-300" : "bg-primary/10 text-primary"}`, children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(Timer, { className: "w-3 h-3" }),
          expired ? "Expirée" : fmt2(remainingMs)
        ] })
      ] }),
      Number(stake) > 0 && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1 text-[11px] text-muted-foreground", children: [
        "Cagnotte : ",
        /* @__PURE__ */ jsxRuntimeExports.jsx("b", { className: "text-foreground", children: Number(pot).toLocaleString("fr-FR") }),
        " Ar"
      ] }),
      roomCode && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1.5 flex items-center gap-2 rounded-xl bg-secondary px-2 py-1.5", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx(Lock, { className: "w-3.5 h-3.5 text-muted-foreground shrink-0" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "font-mono font-bold tracking-[0.25em] text-sm", children: roomCode }),
        /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: copyCode, className: "ml-auto p-1.5 rounded-full bg-card", "aria-label": "Copier", children: copied ? /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3.5 h-3.5 text-emerald-500" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Copy, { className: "w-3.5 h-3.5" }) }),
        !full && /* @__PURE__ */ jsxRuntimeExports.jsx("button", { onClick: share, className: "p-1.5 rounded-full bg-primary text-primary-foreground", "aria-label": "Partager", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Share2, { className: "w-3.5 h-3.5" }) })
      ] })
    ] }),
    matchType === "groupe" && slug === "ludo" && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "grid grid-cols-2 gap-3", children: [1, 2].map((team) => {
      const teamMembers = parts.filter((p) => p.team === team);
      const myTeam = parts.find((p) => p.user_id === meUserId)?.team === team;
      const isFull = teamMembers.length >= 2;
      return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: `rounded-2xl p-3 border-2 space-y-2 ${myTeam ? "border-primary bg-primary/5" : "border-border/60 bg-card"}`, children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "font-bold text-sm text-center", children: team === 1 ? "🔴 Groupe 1" : "🔵 Groupe 2" }),
        teamMembers.map((m) => {
          const prof = avatars[m.user_id];
          const name = prof?.pseudo || m.display_name || "Joueur";
          const initials = name.slice(0, 2).toUpperCase();
          return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-7 w-7 rounded-full overflow-hidden shrink-0 bg-accent flex items-center justify-center font-bold text-[10px]", children: prof?.avatar_url || m.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: prof?.avatar_url || m.avatar_url, alt: "", width: 28, height: 28, className: "w-full h-full object-cover" }) : initials }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs font-semibold truncate", children: [
              name,
              m.user_id === meUserId ? " (vous)" : ""
            ] })
          ] }, m.user_id);
        }),
        Array.from({ length: Math.max(0, 2 - teamMembers.length) }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
          "button",
          {
            onClick: () => onJoinTeam?.(team),
            disabled: !isParticipant || isFull,
            className: `w-full py-2 rounded-lg border border-dashed flex items-center justify-center gap-1 text-xs font-semibold transition-all ${isParticipant && !isFull ? "border-primary/40 text-primary hover:bg-primary/5 active:scale-95" : "border-border/40 text-muted-foreground/50 cursor-not-allowed"}`,
            children: isFull ? "Complet" : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-base leading-none", children: "+" }),
              " Rejoindre"
            ] })
          },
          `e${i}`
        ))
      ] }, team);
    }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-5 shadow-[var(--shadow-soft)] space-y-3", children: [
      parts.map((p) => {
        const prof = avatars[p.user_id];
        const name = prof?.pseudo || p.display_name || "Joueur";
        const initials = name.slice(0, 2).toUpperCase();
        return /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center justify-between border-t border-border/60 pt-3 first:border-0 first:pt-0", children: [
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-3 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "h-9 w-9 rounded-full overflow-hidden shrink-0 bg-accent flex items-center justify-center font-bold text-sm", children: prof?.avatar_url || p.avatar_url ? /* @__PURE__ */ jsxRuntimeExports.jsx("img", { src: prof?.avatar_url || p.avatar_url, alt: "", width: 40, height: 40, loading: "lazy", decoding: "async", className: "w-full h-full object-cover" }) : initials }),
            /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "font-semibold truncate", children: [
              name,
              p.user_id === meUserId ? " (vous)" : ""
            ] })
          ] }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex items-center gap-2 shrink-0", children: [
            matchType === "groupe" && p.team && /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: `text-[10px] px-2 py-0.5 rounded-full font-bold ${p.team === 1 ? "bg-red-500/15 text-red-600" : "bg-blue-500/15 text-blue-600"}`, children: p.team === 1 ? "G1" : "G2" }),
            p.ready ? /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-xs px-3 py-1.5 rounded-full bg-emerald-100 text-emerald-700 font-bold flex items-center gap-1", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-3 h-3" }),
              " Prêt"
            ] }) : /* @__PURE__ */ jsxRuntimeExports.jsx("span", { className: "text-xs px-3 py-1.5 rounded-full bg-amber-100 text-amber-700 font-bold", children: "Pas prêt" })
          ] })
        ] }, p.id || p.user_id);
      }),
      Array.from({ length: empty }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "border-t border-border/60 pt-3 text-sm text-muted-foreground italic", children: "Place libre…" }, `e${i}`))
    ] }),
    isParticipant && onToggleReady && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "rounded-3xl bg-card p-4 shadow-sm space-y-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: () => onToggleReady(!meReady),
          className: `relative w-full py-3.5 rounded-full text-white font-bold flex items-center justify-center gap-2 overflow-hidden transition-transform active:scale-95 ${meReady ? "" : "animate-ready-pulse"}`,
          style: { background: meReady ? "#ef4444" : "var(--gradient-primary)" },
          children: [
            !meReady && /* @__PURE__ */ jsxRuntimeExports.jsx(
              "span",
              {
                "aria-hidden": true,
                className: "pointer-events-none absolute inset-0 -translate-x-full animate-ready-shimmer",
                style: { background: "linear-gradient(90deg, transparent, rgba(255,255,255,0.35), transparent)" }
              }
            ),
            meReady ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(X, { className: "w-4 h-4" }),
              " Pas prêt"
            ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx(Check, { className: "w-4 h-4" }),
              " Je suis prêt !"
            ] })
          ]
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-xs text-muted-foreground text-center", children: [
        readyCount,
        "/",
        maxPlayers,
        " prêt",
        readyCount > 1 ? "s" : "",
        " · ",
        allReady ? "Démarrage…" : parts.length < maxPlayers ? "En attente de joueurs" : "En attente des autres"
      ] }),
      isTournament && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-[11px] text-amber-700 dark:text-amber-300 text-center font-semibold", children: "⚠️ Clique sur « Prêt » avant l'expiration du timer, sinon forfait automatique." })
    ] }),
    isParticipant && /* @__PURE__ */ jsxRuntimeExports.jsxs("button", { onClick: onQuit, className: "px-5 py-3 rounded-full bg-secondary font-semibold flex items-center gap-2", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(LogOut, { className: "w-4 h-4" }),
      " ",
      Number(stake) > 0 ? "Quitter (mise remboursée)" : "Quitter"
    ] })
  ] });
}
function useGamePause({
  slug,
  gameId,
  game,
  isPlayer,
  myUserId
}) {
  const isPaused = !!game?.paused;
  const pauseDeadline = game?.pause_deadline ?? null;
  const afkPauseFor = game?.afk_pause_for ?? null;
  const isAfkPause = !!afkPauseFor;
  const isAfkPlayer = !!myUserId && myUserId === afkPauseFor;
  const afkWarning = game?.afk_warning ?? null;
  const hasVoted = !!myUserId && Array.isArray(afkWarning?.votes) && afkWarning.votes.includes(myUserId);
  const lastWarnKeyRef = reactExports.useRef("");
  reactExports.useEffect(() => {
    if (!afkWarning) return;
    const key = `${afkWarning.uid}:${afkWarning.ts}`;
    if (key === lastWarnKeyRef.current) return;
    if (myUserId && afkWarning.uid === myUserId) return;
    lastWarnKeyRef.current = key;
    toast.warning(
      `⚠️ ${afkWarning.name} est inactif — votez pour mettre la partie en pause`,
      { duration: 5e3 }
    );
  }, [afkWarning, myUserId]);
  const wasPausedRef = reactExports.useRef(isPaused);
  reactExports.useEffect(() => {
    if (!isPaused || !isAfkPause) {
      wasPausedRef.current = isPaused;
      return;
    }
    if (wasPausedRef.current) return;
    wasPausedRef.current = true;
    if (!isAfkPlayer) {
      toast.info("⏸ Partie en pause — en attente du joueur inactif");
    }
  }, [isPaused, isAfkPause, isAfkPlayer]);
  reactExports.useEffect(() => {
    if (!isPaused) wasPausedRef.current = false;
  }, [isPaused]);
  const [pauseSecondsLeft, setPauseSecondsLeft] = reactExports.useState(180);
  reactExports.useEffect(() => {
    if (!isPaused || !pauseDeadline) {
      setPauseSecondsLeft(180);
      return;
    }
    const tick = () => {
      const ms = new Date(pauseDeadline).getTime() - serverNow();
      setPauseSecondsLeft(Math.max(0, Math.ceil(ms / 1e3)));
    };
    tick();
    const t = setInterval(tick, 500);
    return () => clearInterval(t);
  }, [isPaused, pauseDeadline]);
  const canRequestAfkPause = isPlayer && !isPaused && !!afkWarning && game?.status === "playing" && !!myUserId && myUserId !== afkWarning?.uid && !hasVoted;
  const requestAfkPause = reactExports.useCallback(async () => {
    const { data, error } = await supabase.rpc("game_request_afk_pause", {
      _slug: slug,
      _game_id: gameId
    });
    if (error) {
      toast.error(error.message || "Impossible de voter pour la pause");
      return;
    }
    const result = data;
    if (!result) return;
    if (result.status === "already_voted") {
      toast.info("Vous avez déjà voté pour cette pause");
    } else if (result.status === "voted") {
      const v = result.votes ?? 1;
      const n = result.votes_needed ?? 1;
      if (v < n) {
        toast.success(`Vote enregistré (${v}/${n}) — en attente des autres joueurs`);
      }
    } else if (result.status === "paused") {
      toast.success("Partie en pause — 3 minutes pour le retour du joueur");
    }
  }, [slug, gameId]);
  const resumeGame = reactExports.useCallback(async () => {
    const { error } = await supabase.rpc("game_resume", {
      _slug: slug,
      _game_id: gameId
    });
    if (error) toast.error(error.message || "Impossible de reprendre");
    else if (isAfkPlayer) toast.success("Bienvenue ! La partie reprend.");
  }, [slug, gameId, isAfkPlayer]);
  return {
    isPaused,
    pauseSecondsLeft,
    afkWarning,
    isAfkPause,
    afkPauseFor,
    isAfkPlayer,
    canRequestAfkPause,
    hasVoted,
    requestAfkPause,
    resumeGame
  };
}
function fmt(secs) {
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return `${m}:${String(s).padStart(2, "0")}`;
}
function GamePauseControl({
  slug,
  gameId,
  game,
  isPlayer,
  myUserId,
  simplePause
}) {
  const {
    isPaused,
    pauseSecondsLeft,
    afkWarning,
    isAfkPause,
    isAfkPlayer,
    canRequestAfkPause,
    hasVoted,
    requestAfkPause,
    resumeGame
  } = useGamePause({
    slug,
    gameId,
    game,
    isPlayer,
    myUserId
  });
  const votesCount = afkWarning?.votes?.length ?? 0;
  const votesNeeded = afkWarning?.votes_needed ?? 0;
  const showVoteCount = votesNeeded > 0;
  function afkSubtitle() {
    if (afkWarning?.t1 !== void 0) {
      return `${afkWarning.t1}/${afkWarning.t1_max} timeouts sans lancer`;
    }
    if (afkWarning?.skips !== void 0) {
      return `${afkWarning.skips + 1}/${afkWarning.max} tours ratés`;
    }
    return "Seuil AFK atteint";
  }
  return /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    afkWarning && !isPaused && isPlayer && myUserId !== afkWarning.uid && /* @__PURE__ */ jsxRuntimeExports.jsxs(
      "div",
      {
        className: "fixed top-16 left-1/2 -translate-x-1/2 z-40 w-[calc(100%-2rem)] max-w-sm\n                     bg-amber-50 dark:bg-amber-950/60 border border-amber-400/60\n                     rounded-2xl px-4 py-3 shadow-xl flex items-start gap-3 animate-in\n                     slide-in-from-top-4 fade-in duration-300",
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(TriangleAlert, { className: "w-5 h-5 text-amber-500 shrink-0 mt-0.5" }),
          /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "flex-1 min-w-0", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsxs("p", { className: "text-sm font-semibold text-amber-800 dark:text-amber-200 truncate", children: [
              "Voulez-vous attendre le joueur ",
              afkWarning.name,
              " absent ?"
            ] }),
            /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-amber-600 dark:text-amber-400", children: afkSubtitle() }),
            showVoteCount && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "mt-1.5 flex items-center gap-2", children: [
              /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "flex gap-1", children: Array.from({ length: votesNeeded }).map((_, i) => /* @__PURE__ */ jsxRuntimeExports.jsx(
                "div",
                {
                  className: `w-2 h-2 rounded-full transition-colors ${i < votesCount ? "bg-amber-500" : "bg-amber-200 dark:bg-amber-800"}`
                },
                i
              )) }),
              /* @__PURE__ */ jsxRuntimeExports.jsxs("span", { className: "text-[10px] font-semibold text-amber-600 dark:text-amber-400", children: [
                votesCount,
                "/",
                votesNeeded,
                " vote",
                votesNeeded > 1 ? "s" : ""
              ] })
            ] })
          ] }),
          canRequestAfkPause && /* @__PURE__ */ jsxRuntimeExports.jsxs(
            "button",
            {
              onClick: requestAfkPause,
              className: "shrink-0 px-3 py-1.5 rounded-full bg-amber-500 hover:bg-amber-600\n                         active:scale-95 text-white text-xs font-bold flex items-center gap-1.5\n                         transition-all shadow-md shadow-amber-500/30",
              children: [
                /* @__PURE__ */ jsxRuntimeExports.jsx(Vote, { className: "w-3.5 h-3.5" }),
                votesNeeded <= 1 ? "Pause" : "Voter"
              ]
            }
          ),
          hasVoted && !canRequestAfkPause && /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "shrink-0 flex items-center gap-1 text-xs font-semibold text-amber-600 dark:text-amber-400", children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(CircleCheck, { className: "w-4 h-4 text-emerald-500" }),
            "Voté"
          ] })
        ]
      }
    ),
    isPaused && simplePause && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 bg-slate-900/85 backdrop-blur-sm flex items-center justify-center p-6", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card max-w-sm w-full rounded-3xl p-7 shadow-2xl text-center space-y-5", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "w-16 h-16 mx-auto rounded-full flex items-center justify-center bg-amber-100 dark:bg-amber-900/40", children: /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-8 h-8 text-amber-600" }) }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xl font-extrabold", children: "⏸ Partie en pause" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: "Reprenez la partie quand vous êtes prêt." }),
      isPlayer && /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: resumeGame,
          className: "w-full py-3.5 rounded-full bg-emerald-500 hover:bg-emerald-600\n                           active:scale-95 text-white font-bold flex items-center justify-center\n                           gap-2 transition-all text-sm",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-4 h-4" }),
            "Continuer"
          ]
        }
      )
    ] }) }),
    isPaused && !simplePause && /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 bg-slate-900/85 backdrop-blur-sm flex items-center justify-center p-6", children: /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "bg-card max-w-sm w-full rounded-3xl p-7 shadow-2xl text-center space-y-4", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx(
        "div",
        {
          className: `w-16 h-16 mx-auto rounded-full flex items-center justify-center ${isAfkPause ? "bg-orange-100 dark:bg-orange-900/40" : "bg-amber-100 dark:bg-amber-900/40"}`,
          children: isAfkPause ? /* @__PURE__ */ jsxRuntimeExports.jsx(UserX, { className: "w-8 h-8 text-orange-500" }) : /* @__PURE__ */ jsxRuntimeExports.jsx(Pause, { className: "w-8 h-8 text-amber-600" })
        }
      ),
      /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "text-xl font-extrabold", children: isAfkPause ? "⏸ En attente d'un joueur" : "⏸ Partie en pause" }),
      isAfkPause && !isAfkPlayer && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: `En attente du retour de ${game?.afk_pause_name ?? "ce joueur"}. S'il ne revient pas à temps, il sera déclaré forfait.` }),
      isAfkPause && isAfkPlayer && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-sm text-muted-foreground", children: "Vos coéquipiers vous attendent. Appuyez sur Reprendre pour continuer." }),
      /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "space-y-1", children: [
        /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground", children: isAfkPause ? "Forfait automatique dans" : "Reprise automatique dans" }),
        /* @__PURE__ */ jsxRuntimeExports.jsx(
          "span",
          {
            className: `text-4xl font-black font-mono tabular-nums ${pauseSecondsLeft <= 30 ? "text-destructive animate-pulse" : isAfkPause ? "text-orange-500" : "text-primary"}`,
            children: fmt(pauseSecondsLeft)
          }
        )
      ] }),
      isAfkPlayer && /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: resumeGame,
          className: "w-full py-3.5 rounded-full bg-emerald-500 hover:bg-emerald-600\n                           active:scale-95 text-white font-bold flex items-center justify-center\n                           gap-2 transition-all text-sm",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-4 h-4" }),
            "Je suis là — Reprendre"
          ]
        }
      ),
      !isAfkPlayer && isPlayer && /* @__PURE__ */ jsxRuntimeExports.jsxs(
        "button",
        {
          onClick: resumeGame,
          className: "w-full py-3.5 rounded-full bg-emerald-500 hover:bg-emerald-600\n                           active:scale-95 text-white font-bold flex items-center justify-center\n                           gap-2 transition-all text-sm",
          children: [
            /* @__PURE__ */ jsxRuntimeExports.jsx(Play, { className: "w-4 h-4" }),
            "Reprendre maintenant"
          ]
        }
      ),
      !isPlayer && /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xs text-muted-foreground italic", children: "Mode spectateur — la reprise est réservée aux joueurs" })
    ] }) })
  ] });
}
const PING_INTERVAL_MS = 1e4;
const SLOW_THRESHOLD_MS = 3e3;
const OFFLINE_TIMEOUT_MS = 5e3;
function useGameConnection({ onReconnect }) {
  const [isConnected, setIsConnected] = reactExports.useState(
    typeof navigator !== "undefined" ? navigator.onLine : true
  );
  const [isReconnecting, setIsReconnecting] = reactExports.useState(false);
  const [isSlow, setIsSlow] = reactExports.useState(false);
  const callbackRef = reactExports.useRef(onReconnect);
  reactExports.useEffect(() => {
    callbackRef.current = onReconnect;
  }, [onReconnect]);
  const wasOfflineRef = reactExports.useRef(false);
  const doReconnect = reactExports.useCallback(() => {
    setIsReconnecting(true);
    const t = setTimeout(() => {
      callbackRef.current();
      const online = typeof navigator !== "undefined" ? navigator.onLine : true;
      setIsConnected(online);
      setIsReconnecting(false);
      setIsSlow(false);
      if (online && wasOfflineRef.current) {
        wasOfflineRef.current = false;
        toast.success("Reconnecté", { duration: 1500 });
      }
    }, 1500);
    return t;
  }, []);
  reactExports.useEffect(() => {
    let cancelled = false;
    const ping = async () => {
      if (cancelled) return;
      if (typeof navigator !== "undefined" && !navigator.onLine) {
        if (!wasOfflineRef.current) {
          wasOfflineRef.current = true;
          setIsConnected(false);
        }
        return;
      }
      try {
        const url = "https://gifwfjgciwbsottztzoc.supabase.co/rest/v1/";
        const key = "sb_publishable_hXK7wUdP8YiU7qFKh7_Cmg_Os0-QzAj";
        const t0 = performance.now();
        const controller = new AbortController();
        const timeoutId = setTimeout(() => controller.abort(), OFFLINE_TIMEOUT_MS);
        await fetch(url, {
          method: "HEAD",
          cache: "no-store",
          headers: { apikey: key },
          signal: controller.signal
        });
        clearTimeout(timeoutId);
        if (cancelled) return;
        const latency = performance.now() - t0;
        if (latency > SLOW_THRESHOLD_MS) {
          if (!wasOfflineRef.current) {
            wasOfflineRef.current = true;
            setIsConnected(false);
            setIsSlow(true);
            const t = doReconnect();
            return () => clearTimeout(t);
          }
        } else {
          if (wasOfflineRef.current) {
            wasOfflineRef.current = false;
            setIsConnected(true);
            setIsSlow(false);
          } else {
            setIsConnected(true);
            setIsSlow(false);
          }
        }
      } catch {
        if (cancelled) return;
        if (!wasOfflineRef.current) {
          wasOfflineRef.current = true;
          setIsConnected(false);
        }
      }
    };
    ping();
    const id = setInterval(ping, PING_INTERVAL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, [doReconnect]);
  reactExports.useEffect(() => {
    const handleOffline = () => {
      if (!wasOfflineRef.current) {
        wasOfflineRef.current = true;
      }
      setIsConnected(false);
    };
    const handleOnline = () => {
      doReconnect();
    };
    window.addEventListener("offline", handleOffline);
    window.addEventListener("online", handleOnline);
    return () => {
      window.removeEventListener("offline", handleOffline);
      window.removeEventListener("online", handleOnline);
    };
  }, [doReconnect]);
  const retry = reactExports.useCallback(() => {
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      toast.error("Hors ligne", { duration: 1500 });
      return;
    }
    doReconnect();
  }, [doReconnect]);
  return { isConnected, isReconnecting, isSlow, retry };
}
function GameReconnectOverlay({ isConnected, isReconnecting, onRetry }) {
  if (isConnected && !isReconnecting) return null;
  return /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "fixed inset-0 z-50 flex flex-col items-center justify-center gap-5 bg-background/90 backdrop-blur-md", children: isReconnecting ? /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx(LoaderCircle, { className: "h-14 w-14 animate-spin text-primary" }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xl font-bold", children: "Reconnexion en cours…" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "mt-1 text-sm text-muted-foreground", children: "Reprise de la partie dans un instant" })
    ] })
  ] }) : /* @__PURE__ */ jsxRuntimeExports.jsxs(jsxRuntimeExports.Fragment, { children: [
    /* @__PURE__ */ jsxRuntimeExports.jsx("div", { className: "rounded-full bg-destructive/10 p-5", children: /* @__PURE__ */ jsxRuntimeExports.jsx(WifiOff, { className: "h-12 w-12 text-destructive" }) }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs("div", { className: "text-center", children: [
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "text-xl font-bold", children: "Connexion perdue" }),
      /* @__PURE__ */ jsxRuntimeExports.jsx("p", { className: "mt-1 max-w-xs text-sm text-muted-foreground", children: "Votre partie est en pause. La reconnexion se fera automatiquement dès que le réseau revient." })
    ] }),
    /* @__PURE__ */ jsxRuntimeExports.jsxs(
      Button,
      {
        variant: "outline",
        className: "mt-2 gap-2",
        onClick: onRetry,
        children: [
          /* @__PURE__ */ jsxRuntimeExports.jsx(RefreshCw, { className: "h-4 w-4" }),
          "Réessayer maintenant"
        ]
      }
    )
  ] }) });
}
export {
  GameStateMessage as G,
  GameWaitingRoom as a,
  GamePauseControl as b,
  GameEndScreen as c,
  GameReconnectOverlay as d,
  useGameConnection as u
};
