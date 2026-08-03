import * as React from "react";
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
      </head>
      <body>
        {children}
        <Scripts />
      </body>
    </html>
  );
}

function SkelBar({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse rounded bg-muted ${className}`} />;
}
function SkelBlock({ className = "" }: { className?: string }) {
  return <div className={`animate-pulse rounded-xl bg-muted ${className}`} />;
}

function GamesGridSkeleton() {
  return (
    <div className="px-4 pt-4">
      <SkelBar className="mb-4 h-6 w-40" />
      <div className="grid grid-cols-3 gap-3">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="space-y-2">
            <div className="aspect-square animate-pulse rounded-[22%] bg-muted" />
            <SkelBar className="mx-auto h-3 w-3/4" />
          </div>
        ))}
      </div>
    </div>
  );
}

function ListSkeleton() {
  return (
    <div className="space-y-3 px-4 pt-4">
      {Array.from({ length: 6 }).map((_, i) => (
        <div key={i} className="flex items-center gap-3 rounded-xl border border-border/50 p-3">
          <div className="h-10 w-10 shrink-0 animate-pulse rounded-full bg-muted" />
          <div className="flex-1 space-y-2">
            <SkelBar className="h-3 w-2/3" />
            <SkelBar className="h-3 w-1/3" />
          </div>
          <SkelBar className="h-6 w-16" />
        </div>
      ))}
    </div>
  );
}

function ProfileSkeleton() {
  return (
    <div className="space-y-4 px-4 pt-6">
      <div className="flex flex-col items-center gap-3">
        <div className="h-24 w-24 animate-pulse rounded-full bg-muted" />
        <SkelBar className="h-4 w-40" />
        <SkelBar className="h-3 w-24" />
      </div>
      <div className="grid grid-cols-3 gap-3">
        <SkelBlock className="h-20" />
        <SkelBlock className="h-20" />
        <SkelBlock className="h-20" />
      </div>
      <div className="space-y-2">
        <SkelBlock className="h-14" />
        <SkelBlock className="h-14" />
        <SkelBlock className="h-14" />
      </div>
    </div>
  );
}

function BoardSkeleton() {
  return (
    <div className="flex flex-col gap-3 px-4 pt-3">
      <div className="flex items-center justify-between">
        <SkelBar className="h-6 w-28" />
        <SkelBar className="h-6 w-16" />
      </div>
      <div className="flex items-center gap-2">
        <div className="h-10 w-10 animate-pulse rounded-full bg-muted" />
        <SkelBar className="h-3 w-24" />
      </div>
      <div className="mx-auto aspect-square w-full max-w-md animate-pulse rounded-xl bg-muted" />
      <div className="flex items-center gap-2">
        <div className="h-10 w-10 animate-pulse rounded-full bg-muted" />
        <SkelBar className="h-3 w-24" />
      </div>
    </div>
  );
}

function FormSkeleton() {
  return (
    <div className="space-y-4 px-4 pt-4">
      <SkelBar className="h-6 w-40" />
      <SkelBlock className="h-12" />
      <SkelBlock className="h-12" />
      <div className="grid grid-cols-2 gap-3">
        <SkelBlock className="h-20" />
        <SkelBlock className="h-20" />
      </div>
      <SkelBlock className="h-12" />
    </div>
  );
}

function GenericSkeleton() {
  return (
    <div className="space-y-4 px-4 pt-4">
      <SkelBar className="h-6 w-40" />
      <SkelBlock className="h-32" />
      <div className="space-y-2">
        <SkelBar className="h-3 w-full" />
        <SkelBar className="h-3 w-5/6" />
        <SkelBar className="h-3 w-2/3" />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <SkelBlock className="h-24" />
        <SkelBlock className="h-24" />
      </div>
    </div>
  );
}

function pickSkeleton(pathname: string) {
  if (pathname === "/" || pathname.startsWith("/jeux/nouveau")) return <FormSkeleton />;
  if (pathname === "/jeux" || pathname.startsWith("/jeux/")) return <GamesGridSkeleton />;
  if (
    pathname.startsWith("/game/") ||
    pathname.startsWith("/chess/") ||
    pathname.startsWith("/domino/") ||
    pathname.startsWith("/fanorona/") ||
    pathname.startsWith("/rami/") ||
    pathname.startsWith("/poker/")
  ) {
    return <BoardSkeleton />;
  }
  if (pathname.startsWith("/profile") || pathname.startsWith("/joueur")) return <ProfileSkeleton />;
  if (
    pathname.startsWith("/history") ||
    pathname.startsWith("/rankings") ||
    pathname.startsWith("/chat") ||
    pathname.startsWith("/live") ||
    pathname.startsWith("/tournaments") ||
    pathname.startsWith("/lobby") ||
    pathname.startsWith("/discussion") ||
    pathname.startsWith("/admin")
  ) {
    return <ListSkeleton />;
  }
  return <GenericSkeleton />;
}

function RouteSkeletonOverlay() {
  const { isLoading, pathname } = useRouterState({
    select: (s) => ({
      isLoading: s.status === "pending",
      pathname:
        s.pendingMatches?.[s.pendingMatches.length - 1]?.pathname ??
        s.location.pathname,
    }),
  });
  const [show, setShow] = React.useState(false);
  React.useEffect(() => {
    if (!isLoading) { setShow(false); return; }
    const t = setTimeout(() => setShow(true), 350);
    return () => clearTimeout(t);
  }, [isLoading, pathname]);
  if (!isLoading || !show) return null;
  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-x-0 bottom-0 z-30 animate-in fade-in duration-150"
      style={{ top: 56 }}
    >
      <div className="h-full w-full overflow-hidden bg-background">
        {pickSkeleton(pathname)}
      </div>
    </div>
  );
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
            <AutoTranslator />


            <Toaster richColors position="top-center" />
          </ConfirmProvider>
        </AuthProvider>
      </I18nProvider>
    </QueryClientProvider>
  );
}
