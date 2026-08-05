import { createFileRoute, Outlet, Navigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import Header from "@/components/layout/Header";
import PauseBanner from "@/components/game/PauseBanner";
import BottomNav from "@/components/layout/BottomNav";
import TermsModal from "@/components/TermsModal";
import FloatingBackButton from "@/components/layout/BackButton";
import AnnouncementsModal from "@/components/AnnouncementsModal";
import ContactFab from "@/components/ContactFab";
import ShareAppCta from "@/components/ShareAppCta";
import OnlineStatusBar from "@/components/OnlineStatusBar";
import DesktopNav from "@/components/layout/DesktopNav";
import { useLocation } from "@tanstack/react-router";
import { useT } from "@/lib/i18n";
import { useWaitingRoomActive } from "@/lib/game-ui-state";
import { PageLoader } from "@/components/layout/PageLoader";
// AdminApprovalWatcher supprimé — sécurité admin désactivée


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
  const inGameRoute = /^\/(chess|domino|fanorona|rami|poker|game)\//.test(path);
  const inGame = inGameRoute && !waiting;
  const inChat = path === "/chat" || path.startsWith("/discussion/");

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
      <FloatingBackButton />
      <PauseBanner />
      <Header />
      {!inGame && <OnlineStatusBar />}
      <DesktopNav />
      <div className="md:ml-56">
        <Outlet />
      </div>
      {!inGame && <BottomNav />}
      <TermsModal />
      <AnnouncementsModal />
      {!inGame && !inChat && <ContactFab />}
      {!inGame && !inChat && <ShareAppCta />}
      
    </>
  );
}
