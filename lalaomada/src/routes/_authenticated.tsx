import { createFileRoute, Outlet, Navigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import Header from "@/components/layout/Header";
import PauseBanner from "@/components/game/PauseBanner";
import BottomNav from "@/components/layout/BottomNav";
import TermsModal from "@/components/TermsModal";
import AnnouncementsModal from "@/components/AnnouncementsModal";
import ContactFab from "@/components/ContactFab";
import OnlineStatusBar from "@/components/OnlineStatusBar";
import DesktopNav from "@/components/layout/DesktopNav";
import { useLocation } from "@tanstack/react-router";
import { useT } from "@/lib/i18n";
import { useWaitingRoomActive } from "@/lib/game-ui-state";
import { PageLoader } from "@/components/layout/PageLoader";


export const Route = createFileRoute("/_authenticated")({
  component: AuthLayout,
});

// AppSplash is now powered by PageLoader — see @/components/PageLoader
function AppSplash() {
  return <PageLoader variant="splash" />;
}

function AuthLayout() {
  const { user, profile, loading } = useAuth();
  const { t } = useT();
  const loc = useLocation();
  const path = loc.pathname;
  const waiting = useWaitingRoomActive();
  // Match both legacy routes (/domino/xxx) and actual game routes (/jeux/domino/xxx)
  const inGameRoute = /^\/(jeux\/)?(chess|domino|fanorona|rami|poker|ludo|game)\//.test(path);
  const inGame = inGameRoute && !waiting;
  const inChat = path === "/chat" || path.startsWith("/discussion/");
  const isHome = path === "/lobby" || path === "/";

  if (loading) return <AppSplash />;
  if (!user) return <Navigate to="/login" />;
  if (profile?.banned) return (
    <div className="min-h-screen flex items-center justify-center p-6 text-center">
      <div className="rounded-3xl bg-card p-8 max-w-sm shadow-lg">
        <div className="text-3xl font-extrabold text-destructive mb-2">{t("banned_account")}</div>
        <div className="text-muted-foreground">{t("contact_admin")}</div>
      </div>
    </div>
  );

  return (
    <>
      <PauseBanner />
      <Header />
      {!inGame && <OnlineStatusBar />}
      {!inGame && <DesktopNav />}
      <div
        className={inGame ? "fixed inset-0 top-14 overflow-hidden overscroll-none" : "md:ml-56"}
        style={inGame ? { height: "calc(100dvh - 56px)" } : undefined}
      >
        <Outlet />
      </div>
      {!inGame && <BottomNav />}
      <TermsModal />
      <AnnouncementsModal />
      {isHome && <ContactFab />}
      
    </>
  );
}
