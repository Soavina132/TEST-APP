import { createFileRoute, Outlet, Navigate } from "@tanstack/react-router";
import { useAuth } from "@/hooks/use-auth";
import Header from "@/components/Header";
import PauseBanner from "@/components/PauseBanner";
import BottomNav from "@/components/BottomNav";
import TermsModal from "@/components/TermsModal";
import FloatingBackButton from "@/components/BackButton";
import AnnouncementsModal from "@/components/AnnouncementsModal";
import ContactFab from "@/components/ContactFab";
import ShareAppCta from "@/components/ShareAppCta";
import OnlineStatusBar from "@/components/OnlineStatusBar";
import DesktopNav from "@/components/DesktopNav";
import { useLocation } from "@tanstack/react-router";
import { useT } from "@/lib/i18n";
import { useWaitingRoomActive } from "@/lib/game-ui-state";
// AdminApprovalWatcher supprimé — sécurité admin désactivée


export const Route = createFileRoute("/_authenticated")({
  component: AuthLayout,
});

// ═══════════════════════════════════════════════════════════════════════════
// Branded splash screen — shown while the auth session is being resolved
// ═══════════════════════════════════════════════════════════════════════════

function AppSplash() {
  return (
    <div
      className="min-h-screen flex flex-col items-center justify-center gap-7 px-4"
      style={{ background: "var(--background)" }}
    >
      {/* Glow behind the mark */}
      <div className="relative flex items-center justify-center">
        <div
          className="absolute w-28 h-28 rounded-full blur-2xl opacity-30"
          style={{ background: "radial-gradient(circle, #f97316, transparent 70%)" }}
        />
        <div
          className="relative w-20 h-20 rounded-3xl flex items-center justify-center text-4xl shadow-xl"
          style={{
            background: "linear-gradient(135deg, #f97316, #fb923c)",
            animation: "lm-splash-pop 1.6s ease-in-out infinite",
          }}
        >
          🎲
        </div>
      </div>

      {/* Brand name */}
      <div className="flex flex-col items-center gap-1.5">
        <h1
          className="text-3xl font-extrabold tracking-tight"
          style={{
            background: "linear-gradient(90deg, #f97316, #fb923c, #f97316)",
            backgroundSize: "200% auto",
            WebkitBackgroundClip: "text",
            WebkitTextFillColor: "transparent",
            animation: "lm-splash-shimmer 2s linear infinite",
          }}
        >
          Lalao MADA
        </h1>
        <p className="text-xs font-medium text-muted-foreground tracking-wide">
          Jouez. Gagnez. Retirez en Ariary.
        </p>
      </div>

      {/* Progress dots */}
      <div className="flex items-center gap-1.5">
        {[0, 1, 2].map((i) => (
          <span
            key={i}
            className="w-2 h-2 rounded-full"
            style={{
              background: "#f97316",
              animation: `lm-splash-dot 1s ease-in-out ${i * 0.15}s infinite`,
            }}
          />
        ))}
      </div>

      <style>{`
        @keyframes lm-splash-pop {
          0%, 100% { transform: scale(1) rotate(0deg); }
          50% { transform: scale(1.08) rotate(8deg); }
        }
        @keyframes lm-splash-shimmer {
          0% { background-position: 200% center; }
          100% { background-position: -200% center; }
        }
        @keyframes lm-splash-dot {
          0%, 80%, 100% { opacity: 0.25; transform: translateY(0); }
          40% { opacity: 1; transform: translateY(-4px); }
        }
      `}</style>
    </div>
  );
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
