import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useState, useRef, useEffect } from "react";
import { Gamepad2, LayoutGrid, Shield, LogOut, ChevronDown, User, Zap } from "lucide-react";
import NotificationsBell from "@/components/NotificationsBell";
import { WalletButton } from "@/components/WalletButton";
import { useT } from "@/lib/i18n";

function RouteLoadingBar() {
  const status = useRouterState({ select: (s) => s.status });
  const isLoading = status === "pending";
  const [visible, setVisible] = useState(false);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    let raf: number | undefined;
    let hideTimer: number | undefined;
    if (isLoading) {
      setVisible(true);
      setProgress(10);
      const tick = () => {
        setProgress((p) => (p < 90 ? p + Math.max(0.4, (90 - p) * 0.04) : p));
        raf = window.requestAnimationFrame(tick);
      };
      raf = window.requestAnimationFrame(tick);
    } else if (visible) {
      setProgress(100);
      hideTimer = window.setTimeout(() => {
        setVisible(false);
        setProgress(0);
      }, 250);
    }
    return () => {
      if (raf !== undefined) cancelAnimationFrame(raf);
      if (hideTimer !== undefined) clearTimeout(hideTimer);
    };
  }, [isLoading]);

  if (!visible) return null;
  return (
    <div className="absolute left-0 right-0 bottom-0 h-[2px] overflow-hidden pointer-events-none">
      <div
        className="h-full bg-gradient-to-r from-orange-400 via-orange-500 to-orange-400 shadow-[0_0_8px_rgba(249,115,22,0.7)] transition-[width,opacity] duration-200 ease-out"
        style={{ width: `${progress}%`, opacity: progress === 100 ? 0 : 1 }}
      />
    </div>
  );
}

export function Logo() {
  return (
    <div className="relative w-9 h-9 flex-shrink-0">
      <div className="absolute inset-0 rounded-xl bg-gradient-to-br from-red-500 via-orange-500 to-yellow-400 opacity-20 blur-sm" />
      <div className="relative grid grid-cols-2 gap-[3px] w-9 h-9 p-1.5">
        <div className="rounded-full bg-gradient-to-br from-red-500 to-red-600 shadow-sm" />
        <div className="rounded-full bg-gradient-to-br from-green-400 to-green-600 shadow-sm" />
        <div className="rounded-full bg-gradient-to-br from-blue-500 to-blue-600 shadow-sm" />
        <div className="rounded-full bg-gradient-to-br from-yellow-400 to-orange-400 shadow-sm" />
      </div>
    </div>
  );
}

export default function Header() {
  const { user, profile, isAdmin, signOut } = useAuth();
  const { t } = useT();
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const onClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener("mousedown", onClick);
    return () => document.removeEventListener("mousedown", onClick);
  }, []);

  if (!user || !profile) return null;
  const initials = (profile.pseudo || "?").slice(0, 2).toUpperCase();
  const balance = Math.round(profile.balance_ar).toLocaleString("fr-FR");

  return (
    <>
      <header className="sticky top-0 z-30">
        <div className="relative border-b border-border/40 bg-card shadow-[0_1px_0_0_rgba(0,0,0,0.04)]">
          <div className="max-w-5xl mx-auto px-3 h-14 flex items-center justify-between gap-2">

            {/* Left: Logo + brand name — clean, fully visible */}
            <Link to="/" className="flex items-center gap-2.5 group min-w-0" aria-label="Lalao MADA">
              <Logo />
              <span className="hidden min-[360px]:inline font-black text-base sm:text-lg tracking-tight bg-gradient-to-r from-primary to-orange-400 bg-clip-text text-transparent whitespace-nowrap">
                Lalao MADA
              </span>
            </Link>

            {/* Right controls: wallet + language + bell + avatar */}
            <div className="flex items-center gap-1 shrink-0">
              {/* Wallet — moved here from under the brand name */}
              <WalletButton />

              {/* Language — hidden on very small screens to save space */}
              <div className="hidden sm:block">
              </div>

              <NotificationsBell />

              {/* Profile avatar */}
              <div className="relative" ref={ref}>
                <button
                  onClick={() => setOpen(o => !o)}
                  aria-label={t("my_profile")}
                  aria-expanded={open}
                  className={`flex items-center gap-2 pl-1.5 pr-2.5 py-1 rounded-full transition-all duration-200 border ${
                    open
                      ? "bg-primary/10 border-primary/30 shadow-sm"
                      : "bg-accent/60 hover:bg-accent border-border/40 hover:border-border"
                  }`}
                >
                  <div className="relative">
                    <div className={`w-7 h-7 rounded-full overflow-hidden flex items-center justify-center text-xs font-bold ring-2 transition-all duration-200 ${
                      open ? "ring-primary/50" : "ring-border/60"
                    }`}
                      style={{ background: "var(--color-secondary)" }}>
                      {profile.avatar_url
                        ? <img src={profile.avatar_url} alt={`Avatar de ${profile.pseudo}`} width={32} height={32} loading="lazy" decoding="async" className="w-full h-full object-cover" />
                        : <span className="text-primary font-black">{initials}</span>
                      }
                    </div>
                    <span className="absolute bottom-0 right-0 w-2 h-2 rounded-full bg-green-400 border-2 border-card" />
                  </div>
                  <span className="hidden min-[340px]:block text-xs font-semibold truncate max-w-[64px] sm:max-w-[80px]">{profile.pseudo}</span>
                  <ChevronDown className={`w-3.5 h-3.5 text-muted-foreground transition-transform duration-200 ${open ? "rotate-180" : ""}`} />
                </button>

                {open && (
                  <div className="absolute right-0 mt-2.5 w-68 rounded-2xl bg-card shadow-2xl shadow-black/10 border border-border/60 overflow-hidden animate-pop-in z-50">
                    <div className="px-4 py-3 bg-gradient-to-br from-primary/8 to-orange-400/5 border-b border-border/50">
                      <div className="flex items-center gap-3">
                        <div className="w-10 h-10 rounded-full overflow-hidden flex items-center justify-center font-black text-primary ring-2 ring-primary/20"
                          style={{ background: "var(--color-secondary)" }}>
                          {profile.avatar_url
                            ? <img src={profile.avatar_url} alt="" width={32} height={32} loading="lazy" decoding="async" className="w-full h-full object-cover" />
                            : initials
                          }
                        </div>
                        <div>
                          <div className="font-bold text-sm">{profile.pseudo}</div>
                          <div className="text-[10px] text-muted-foreground font-mono">{profile.unique_code}</div>
                          <div className="flex items-center gap-1 mt-0.5">
                            <Zap className="w-3 h-3 text-amber-500" />
                            <span className="text-xs font-semibold text-amber-600 tabular-nums">{balance} Ar</span>
                          </div>
                        </div>
                      </div>
                    </div>

                    <div className="p-1.5">
                      {[
                        { icon: LayoutGrid, label: t("my_space"), to: "/" },
                        { icon: User, label: t("my_profile"), to: "/profile" },
                        { icon: Gamepad2, label: t("lobby"), to: "/jeux" },
                      ].map(item => (
                        <button
                          key={item.to}
                          onClick={() => { setOpen(false); navigate({ to: item.to as any }); }}
                          className="w-full text-left px-3 py-2.5 rounded-xl hover:bg-accent/80 flex items-center gap-3 text-sm font-medium transition-colors group"
                        >
                          <div className="w-7 h-7 rounded-lg bg-secondary flex items-center justify-center group-hover:bg-primary/10 transition-colors">
                            <item.icon className="w-3.5 h-3.5 text-muted-foreground group-hover:text-primary transition-colors" />
                          </div>
                          {item.label}
                        </button>
                      ))}

                      {isAdmin && (
                        <>
                          <div className="mx-3 my-1 border-t border-border/40" />
                          {[
                            { icon: Shield, label: t("admin"), to: "/admin" },
                          ].map(item => (
                            <button
                              key={item.to}
                              onClick={() => { setOpen(false); navigate({ to: item.to as any }); }}
                              className="w-full text-left px-3 py-2.5 rounded-xl hover:bg-amber-50 flex items-center gap-3 text-sm font-medium transition-colors group"
                            >
                              <div className="w-7 h-7 rounded-lg bg-amber-100/80 flex items-center justify-center group-hover:bg-amber-200/60 transition-colors">
                                <item.icon className="w-3.5 h-3.5 text-amber-600" />
                              </div>
                              <span className="text-amber-700">{item.label}</span>
                            </button>
                          ))}
                        </>
                      )}

                      <div className="mx-3 my-1 border-t border-border/40" />
                      <button
                        onClick={async () => { setOpen(false); await signOut(); navigate({ to: "/login" }); }}
                        className="w-full text-left px-3 py-2.5 rounded-xl hover:bg-destructive/10 flex items-center gap-3 text-sm font-medium transition-colors group"
                      >
                        <div className="w-7 h-7 rounded-lg bg-destructive/10 flex items-center justify-center group-hover:bg-destructive/20 transition-colors">
                          <LogOut className="w-3.5 h-3.5 text-destructive" />
                        </div>
                        <span className="text-destructive">{t("logout")}</span>
                      </button>
                    </div>
                  </div>
                )}
              </div>
            </div>
          </div>

          <RouteLoadingBar />
        </div>
      </header>

    </>
  );
}
