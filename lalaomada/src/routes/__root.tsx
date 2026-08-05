import * as React from "react";
import { usePushNotifications } from "@/hooks/use-push-notifications";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import {
  Outlet,
  Link,
  createRootRouteWithContext,
  useRouter,
  useRouterState,
  HeadContent,
  Scripts,
} from "@tanstack/react-router";

import appCss from "../styles.css?url";
import { AuthProvider } from "@/hooks/use-auth";
import { Toaster } from "@/components/ui/sonner";
import { I18nProvider } from "@/lib/i18n";
import { ConfirmProvider } from "@/components/ConfirmDialog";
import AutoTranslator from "@/components/AutoTranslator";
import { PageLoader, useDelayedPending } from "@/components/PageLoader";

function NotFoundComponent() {
  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="max-w-md text-center">
        <h1 className="text-7xl font-bold text-foreground">404</h1>
        <h2 className="mt-4 text-xl font-semibold text-foreground">Page not found</h2>
        <p className="mt-2 text-sm text-muted-foreground">
          The page you're looking for doesn't exist or has been moved.
        </p>
        <div className="mt-6">
          <Link
            to="/"
            className="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
          >
            Go home
          </Link>
        </div>
      </div>
    </div>
  );
}

function ErrorComponent({ error, reset }: { error: Error; reset: () => void }) {
  console.error(error);
  const router = useRouter();

  return (
    <div className="flex min-h-screen items-center justify-center bg-background px-4">
      <div className="max-w-md text-center">
        <h1 className="text-xl font-semibold tracking-tight text-foreground">
          This page didn't load
        </h1>
        <p className="mt-2 text-sm text-muted-foreground">
          Something went wrong on our end. You can try refreshing or head back home.
        </p>
        <div className="mt-6 flex flex-wrap justify-center gap-2">
          <button
            onClick={() => {
              router.invalidate();
              reset();
            }}
            className="inline-flex items-center justify-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-primary-foreground transition-colors hover:bg-primary/90"
          >
            Try again
          </button>
          <a
            href="/"
            className="inline-flex items-center justify-center rounded-md border border-input bg-background px-4 py-2 text-sm font-medium text-foreground transition-colors hover:bg-accent"
          >
            Go home
          </a>
        </div>
      </div>
    </div>
  );
}

export const Route = createRootRouteWithContext<{ queryClient: QueryClient }>()({
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
      { property: "og:image", content: "https://pub-bb2e103a32db4e198524a2e9ed8f35b4.r2.dev/b744f25f-6be8-4018-84db-5968ece32a9c/id-preview-2109df56--55268ec1-0df4-4faf-b44d-913c5f22f01f.lovable.app-1781835411588.png" },
      { name: "twitter:image", content: "https://pub-bb2e103a32db4e198524a2e9ed8f35b4.r2.dev/b744f25f-6be8-4018-84db-5968ece32a9c/id-preview-2109df56--55268ec1-0df4-4faf-b44d-913c5f22f01f.lovable.app-1781835411588.png" },
    ],
    links: [
      { rel: "stylesheet", href: appCss },
      { rel: "manifest", href: "/manifest.json" },
      { rel: "apple-touch-icon", href: "/favicon.ico" },
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
            description: "Application Ludo malagasy avec mises en Ariary et dépôts/retraits Mobile Money.",
          },
          {
            "@type": "Organization",
            "@id": "https://lalaomada.lovable.app/#organization",
            name: "Lalao MADA",
            url: "https://lalaomada.lovable.app/",
          },
        ],
      }),
    }],
  }),
  shellComponent: RootShell,
  component: RootComponent,
  notFoundComponent: NotFoundComponent,
  errorComponent: ErrorComponent,
});

function RootShell({ children }: { children: React.ReactNode }) {
  return (
    <html lang="fr">
      <head>
        <HeadContent />
        <script
          dangerouslySetInnerHTML={{
            __html: `(function(){try{var t=localStorage.getItem('theme');if(t==='dark'||(!t&&window.matchMedia&&window.matchMedia('(prefers-color-scheme: dark)').matches)){document.documentElement.classList.add('dark');var m=document.querySelector('meta[name=theme-color]');if(m)m.setAttribute('content','#1a1714');}}catch(e){}})();`,
          }}
        />
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

// BrandedLoader is now powered by PageLoader — see @/components/PageLoader

function RouteSkeletonOverlay() {
  const { isLoading, pathname } = useRouterState({
    select: (s) => ({
      isLoading: s.status === "pending",
      pathname:
        s.pendingMatches?.[s.pendingMatches.length - 1]?.pathname ??
        s.location.pathname,
    }),
  });
  const show = useDelayedPending(isLoading, 200);
  if (!isLoading || !show) return null;
  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-x-0 bottom-0 z-30 animate-in fade-in duration-200"
      style={{ top: 56 }}
    >
      <div className="h-full w-full overflow-hidden bg-background">
        <PageLoader variant="overlay" />
      </div>
    </div>
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Push notifications manager — registers SW and subscribes to push
// ═══════════════════════════════════════════════════════════════════════════

function PushNotificationsManager() {
  usePushNotifications();
  return null;
}

function RootComponent() {
  const { queryClient } = Route.useRouteContext();
  return (
    <QueryClientProvider client={queryClient}>
      <I18nProvider>
        <AuthProvider>
          <ConfirmProvider>
            <Outlet />
            <RouteSkeletonOverlay />
            <PushNotificationsManager />
            <AutoTranslator />
            <Toaster richColors position="top-center" />
          </ConfirmProvider>
        </AuthProvider>
      </I18nProvider>
    </QueryClientProvider>
  );
}
