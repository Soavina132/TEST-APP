import { Link, useNavigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import { useState, useRef, useEffect } from "react";
import { Gamepad2, LayoutGrid, Shield, LogOut, ChevronDown, User, Zap, Moon, Sun } from "lucide-react";
import NotificationsBell from "@/components/NotificationsBell";
import AppMenu from "@/components/AppMenu";
import { useT } from "@/lib/i18n";
import { useOnlineStatus, NetworkQuality } from "@/hooks/use-online-status";

// ── Dark mode hook ──────────────────────────────────────────────────────
function useDarkMode() {
  const [dark, setDark] = useState(() => {
    if (typeof document === "undefined") return false;
    const stored = localStorage.getItem("lalaomada-theme");
    if (stored) return stored === "dark";
    return document.documentElement.classList.contains("dark");
  });

  useEffect(() => {
    const root = document.documentElement;
    if (dark) root.classList.add("dark");
    else root.classList.remove("dark");
    localStorage.setItem("lalaomada-theme", dark ? "dark" : "light");
  }, [dark]);

  return { dark, toggle: () => setDark(d => !d) };
}

// ── Player level badge ─────────────────────────────────────────────────
function getLevelInfo(referralCount: number = 0, gamesPlayed: number = 0) {
  const score = referralCount + gamesPlayed;
  if (score >= 50) return { label: "Diamant", emoji: "💎", color: "text-cyan-400", bg: "bg-cyan-400/10" };
  if (score >= 20) return { label: "Or", emoji: "🥇", color: "text-amber-400", bg: "bg-amber-400/10" };
  if (score >= 5)  return { label: "Argent", emoji: "🥈", color: "text-slate-400", bg: "bg-slate-400/10" };
  return { label: "Bronze", emoji: "🥉", color: "text-orange-600", bg: "bg-orange-600/10" };
}

// ── Compact signal bars (no text) ──────────────────────────────────────
const NET_Q: Record<NetworkQuality, { bars: number; color: string }> = {
  excellent: { bars: 4, color: "text-emerald-500" },
  good:      { bars: 3, color: "text-emerald-400" },
  fair:      { bars: 2, color: "text-amber-500" },
  poor:      { bars: 1, color: "text-red-500" },
  offline:   { bars: 0, color: "text-red-600" },
  unknown:   { bars: 0, color: "text-muted-foreground" },
};

function MiniSignalBars({ bars, color }: { bars: number; color: string }) {
  return (
    <div className={`flex items-end gap-[1.5px] ${color}`} style={{ height: 9, width: 12 }}>
      {[1, 2, 3, 4].map(b => (
        <div
          key={b}
          className={`w-[2px] rounded-[0.5px] transition-all duration-300 ${b <= bars ? "opacity-100" : "opacity-20"}`}
          style={{ height: `${b * 25}%`, background: "currentColor" }}
        />
      ))}
    </div>
  );
}

function Logo() {
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
  const [menuOpen, setMenuOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const { onlineCount, quality, isOnline } = useOnlineStatus(user?.id);
  const netCfg = NET_Q[quality];
  const { dark, toggle } = useDarkMode();

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
  const level = getLevelInfo((profile as any).referral_count, (profile as any).games_played);

  return (
    <>
      <header className="sticky top-0 z-30">
        <div className="relative border-b border-border/40 bg-card shadow-[0_1px_0_0_rgba(0,0,0,0.04)]">
          <div className="max-w-5xl mx-auto px-3 h-14 flex items-center justify-between gap-2">

            <Link to="/" className="flex items-center gap-2.5 group" aria-label="Lalao MADA">
              <Logo />
              <div className="flex flex-col leading-none">
                <span className="font-black text-base tracking-tight bg-gradient-to-r from-primary to-orange-400 bg-clip-text text-transparent">
                  Lalao MADA
                </span>
                <span className="text-[9px] text-muted-foreground font-medium tracking-widest uppercase">
                  Jeux
                </span>
              </div>
            </Link>

            <div className="flex items-center gap-1.5">
              {/* Online count — just number, no text */}
              <div className="flex items-center gap-1 px-1.5">
                <span className={`w-[6px] h-[6px] rounded-full flex-shrink-0 ${isOnline ? "bg-emerald-500 animate-pulse" : "bg-red-500"}`} />
                <span className="text-xs font-bold tabular-nums text-foreground">{onlineCount}</span>
              </div>

              {/* Network signal — compact bars only */}
              <div className="flex items-center px-1">
                {isOnline ? (
                  <MiniSignalBars bars={netCfg.bars} color={netCfg.color} />
                ) : (
                  <span className="text-red-600 text-xs">✕</span>
                )}
              </div>

              <NotificationsBell />

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
                  <div className="hidden sm:flex flex-col items-start leading-none">
                    <div className="flex items-center gap-1.5">
                      <span className="text-xs font-semibold truncate max-w-[80px]">{profile.pseudo}</span>
                      <span className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[8px] font-bold ${level.bg} ${level.color}`}>
                        {level.emoji} {level.label}
                      </span>
                    </div>
                    <span className="text-[10px] text-muted-foreground font-medium tabular-nums">{balance} Ar</span>
                  </div>
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
                        <div className="flex-1">
                          <div className="font-bold text-sm">{profile.pseudo}</div>
                          <div className="text-[10px] text-muted-foreground font-mono">{profile.unique_code}</div>
                          <div className="flex items-center gap-2 mt-0.5">
                            <div className="flex items-center gap-1">
                              <Zap className="w-3 h-3 text-amber-500" />
                              <span className="text-xs font-semibold text-amber-600 tabular-nums">{balance} Ar</span>
                            </div>
                            <span className={`inline-flex items-center gap-0.5 px-1.5 py-0.5 rounded-full text-[9px] font-bold ${level.bg} ${level.color}`}>
                              {level.emoji} {level.label}
                            </span>
                          </div>
                        </div>
                        {/* Theme toggle — top-right of the dropdown header */}
                        <button
                          onClick={toggle}
                          className="p-2 rounded-xl bg-card/60 hover:bg-card border border-border/40 hover:border-border transition-colors active:scale-90 flex-shrink-0"
                          aria-label={dark ? "Mode clair" : "Mode sombre"}
                        >
                          {dark ? <Sun className="w-4 h-4 text-amber-400" /> : <Moon className="w-4 h-4 text-muted-foreground" />}
                        </button>
                      </div>
                    </div>

                    <div className="p-1.5">
                      {[
                        { icon: LayoutGrid, label: t("my_space"), to: "/" },
                        { icon: User, label: t("my_profile"), to: "/profile" },
                        ...(!isAdmin ? [{ icon: Gamepad2, label: t("lobby"), to: "/jeux" }] : []),
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
                        className="w-full text-left px-3 py-2.5 rounded-xl hover:bg-destructive/8 flex items-center gap-3 text-sm font-medium transition-colors group"
                      >
                        <div className="w-7 h-7 rounded-lg bg-destructive/10 flex items-center justify-center group-hover:bg-destructive/15 transition-colors">
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
          
        </div>
      </header>
      <AppMenu open={menuOpen} onClose={() => setMenuOpen(false)} />
    </>
  );
}

export { Logo };
