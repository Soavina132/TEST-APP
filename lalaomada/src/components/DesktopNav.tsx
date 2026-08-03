import { Link, useLocation } from "@tanstack/react-router";
import { Home, MessageSquare, Radio, Gamepad2, User, Shield, Trophy, History, Bug, Zap } from "lucide-react";
import { useAuth } from "@/hooks/use-auth";
import { useT } from "@/lib/i18n";
import { useAdminPending } from "@/hooks/use-admin-pending";
import { useLiveAvailable } from "@/hooks/use-live-available";

function NavBadge({ count }: { count: number }) {
  if (count <= 0) return null;
  return (
    <span className="ml-auto min-w-5 h-5 px-1.5 rounded-full bg-destructive text-white text-[10px] font-bold flex items-center justify-center leading-none tabular-nums flex-shrink-0 shadow-sm">
      {count > 99 ? "99+" : count}
    </span>
  );
}

export default function DesktopNav() {
  const loc     = useLocation();
  const { isAdmin, profile } = useAuth();
  const { t }   = useT();
  const pending = useAdminPending();
  const liveAvailable = useLiveAvailable();

  const items = [
    { to: "/",         icon: Home,          label: t("home"),   dot: false },
    { to: "/jeux",     icon: Gamepad2,      label: t("games") || "Jeux", dot: false },
    { to: "/chat",     icon: MessageSquare, label: t("discussion"), dot: false },
    { to: "/live",     icon: Radio,         label: t("live"),   dot: liveAvailable > 0 },
    { to: "/rankings", icon: Trophy,        label: t("rankings"), dot: false },
    { to: "/history",  icon: History,       label: t("history"), dot: false },
    { to: "/profile",  icon: User,          label: t("my_profile"), dot: false },
  ];

  type AdminItem = { to: string; icon: typeof Shield; label: string; badge: number };
  const adminItems: AdminItem[] = isAdmin ? [
    { to: "/admin",             icon: Shield, label: t("admin"),          badge: pending.finance },
    { to: "/admin-bug-reports", icon: Bug,    label: "Signalements",      badge: pending.bugs },
  ] : [];

  function isActive(to: string) {
    return loc.pathname === to || (to !== "/" && loc.pathname.startsWith(to));
  }

  if (loc.pathname === "/login") return null;

  return (
    <nav className="hidden md:flex flex-col fixed left-0 top-14 bottom-0 w-60 z-20 py-3 px-2.5 overflow-y-auto
      bg-card/90 backdrop-blur-xl border-r border-border/50
      shadow-[1px_0_0_0_rgba(0,0,0,0.03)]">

      <div className="space-y-0.5">
        {items.map(it => {
          const active = isActive(it.to);
          const Icon = it.icon;
          return (
            <Link
              key={it.to}
              to={it.to}
              className={`relative flex items-center gap-3 px-3 py-2.5 rounded-xl font-medium text-sm transition-all duration-150 group ${
                active
                  ? "bg-gradient-to-r from-primary/12 to-primary/4 text-primary font-semibold shadow-sm"
                  : "text-muted-foreground hover:bg-accent/70 hover:text-foreground"
              }`}
            >
              {active && (
                <span className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 rounded-r-full bg-primary" />
              )}
              <div className={`relative w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 transition-all duration-150 ${
                active
                  ? "bg-primary/15 text-primary shadow-sm"
                  : "bg-transparent text-muted-foreground group-hover:bg-accent group-hover:text-foreground"
              }`}>
                <Icon className="w-4 h-4" />
                {it.dot && (
                  <span className="absolute -top-0.5 -right-0.5 flex h-2.5 w-2.5">
                    <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-destructive opacity-75" />
                    <span className="relative inline-flex rounded-full h-2.5 w-2.5 bg-destructive border-2 border-card" />
                  </span>
                )}
              </div>
              <span className="truncate">{it.label}</span>
            </Link>
          );
        })}
      </div>

      {adminItems.length > 0 && (
        <>
          <div className="my-3 flex items-center gap-2">
            <div className="flex-1 h-px bg-border/60" />
            <div className="flex items-center gap-1.5">
              <span className="text-[10px] font-bold uppercase tracking-widest text-muted-foreground">Admin</span>
              {pending.total > 0 && (
                <span className="relative flex h-2 w-2">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-destructive opacity-75" />
                  <span className="relative inline-flex rounded-full h-2 w-2 bg-destructive" />
                </span>
              )}
            </div>
            <div className="flex-1 h-px bg-border/60" />
          </div>
          <div className="space-y-0.5">
            {adminItems.map(it => {
              const active = isActive(it.to);
              const Icon = it.icon;
              return (
                <Link
                  key={it.to}
                  to={it.to}
                  className={`relative flex items-center gap-3 px-3 py-2.5 rounded-xl font-medium text-sm transition-all duration-150 group ${
                    active
                      ? "bg-gradient-to-r from-amber-500/12 to-amber-400/4 text-amber-700 font-semibold"
                      : "text-muted-foreground hover:bg-amber-50/70 hover:text-amber-800"
                  }`}
                >
                  {active && (
                    <span className="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-5 rounded-r-full bg-amber-500" />
                  )}
                  <div className={`w-8 h-8 rounded-lg flex items-center justify-center flex-shrink-0 transition-all duration-150 ${
                    active ? "bg-amber-100 text-amber-600" : "bg-transparent group-hover:bg-amber-100/70 group-hover:text-amber-600"
                  }`}>
                    <Icon className="w-4 h-4" />
                  </div>
                  <span className="truncate flex-1">{it.label}</span>
                  <NavBadge count={it.badge} />
                </Link>
              );
            })}
          </div>
        </>
      )}

      {profile && (
        <div className="mt-auto pt-3">
          <div className="relative overflow-hidden rounded-2xl bg-gradient-to-br from-primary/10 via-primary/6 to-orange-400/8 border border-primary/15 p-3.5">
            <div className="absolute -top-4 -right-4 w-16 h-16 rounded-full bg-primary/8 blur-xl" />
            <div className="relative">
              <div className="flex items-center gap-1.5 mb-0.5">
                <Zap className="w-3 h-3 text-amber-500" />
                <span className="text-[10px] text-muted-foreground font-semibold uppercase tracking-wider">Solde</span>
              </div>
              <div className="font-black text-lg tabular-nums text-primary leading-tight">
                {Math.round(profile.balance_ar).toLocaleString("fr-FR")}
                <span className="text-sm font-semibold text-muted-foreground ml-1">Ar</span>
              </div>
            </div>
          </div>
        </div>
      )}
    </nav>
  );
}
