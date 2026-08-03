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
import GlobalPopups from "@/components/GlobalPopups";

/* ═══════════════════════════════════════════════════════════════════════════
   SHARED SHIMMER KEYFRAMES — injected once
   ═══════════════════════════════════════════════════════════════════════════ */
const ShimmerStyle = () => (
  <style>{`
    @keyframes shimmer-sweep {
      0%   { background-position: -200% 0; }
      100% { background-position: 200% 0; }
    }
    .shimmer {
      background: linear-gradient(
        90deg,
        hsl(var(--muted)) 0%,
        hsl(var(--muted)) 40%,
        hsl(var(--muted-foreground) / 0.08) 50%,
        hsl(var(--muted)) 60%,
        hsl(var(--muted)) 100%
      );
      background-size: 200% 100%;
      animation: shimmer-sweep 1.8s ease-in-out infinite;
    }
    @keyframes skeleton-fade-in {
      from { opacity: 0; transform: translateY(6px); }
      to   { opacity: 1; transform: translateY(0); }
    }
    .skel-enter { animation: skeleton-fade-in 0.4s ease both; }
    @keyframes brand-pulse {
      0%, 100% { opacity: 0.4; transform: scale(1); }
      50%      { opacity: 1;   transform: scale(1.15); }
    }
  `}</style>
);

/* ═══════════════════════════════════════════════════════════════════════════
   NPROGRESS-STYLE TOP BAR  (replaces the old RouteLoadingBar in Header)
   ═════════════════════════════════════════════════════════════════════════ */
export function TopLoadingBar() {
  const status = useRouterState({ select: (s) => s.status });
  const isLoading = status === "pending";
  const [visible, setVisible] = useState(false);
  const [progress, setProgress] = useState(0);

  useEffect(() => {
    let raf: number | undefined;
    let hideTimer: number | undefined;
    if (isLoading) {
      setVisible(true);
      setProgress(0);
      const start = performance.now();
      const tick = () => {
        const elapsed = performance.now() - start;
        // Easing: fast start, slow near 90%
        const p = Math.min(90, 90 * (1 - Math.exp(-elapsed / 600)));
        setProgress(p);
        if (p < 90) raf = requestAnimationFrame(tick);
      };
      raf = requestAnimationFrame(tick);
    } else if (visible) {
      setProgress(100);
      hideTimer = window.setTimeout(() => {
        setVisible(false);
        setProgress(0);
      }, 350);
    }
    return () => {
      if (raf !== undefined) cancelAnimationFrame(raf);
      if (hideTimer !== undefined) clearTimeout(hideTimer);
    };
  }, [isLoading]);

  if (!visible) return null;
  return (
    <div className="fixed top-0 left-0 right-0 z-[100] h-[3px] pointer-events-none">
      <div
        className="h-full transition-[width,opacity] duration-300 ease-out"
        style={{
          width: `${progress}%`,
          opacity: progress === 100 ? 0 : 1,
          background: "linear-gradient(90deg, #f97316, #f59e0b, #f97316)",
          boxShadow: "0 0 10px rgba(249,115,22,0.5), 0 0 4px rgba(245,158,11,0.4)",
          borderRadius: "0 4px 4px 0",
        }}
      />
    </div>
  );
}

// Need useState/useEffect — import them
import { useState, useEffect } from "react";

/* ═══════════════════════════════════════════════════════════════════════════
   SKELETON PRIMITIVES — shimmer instead of pulse
   ═════════════════════════════════════════════════════════════════════════ */
function ShimmerBar({ className = "", delay = 0 }: { className?: string; delay?: number }) {
  return (
    <div
      className={`shimmer rounded-lg ${className}`}
      style={{ animationDelay: `${delay}ms` }}
    />
  );
}
function ShimmerBlock({ className = "", delay = 0 }: { className?: string; delay?: number }) {
  return (
    <div
      className={`shimmer rounded-2xl ${className}`}
      style={{ animationDelay: `${delay}ms` }}
    />
  );
}

/* ═══════════════════════════════════════════════════════════════════════════
   ROUTE-SPECIFIC SKELETONS
   ═════════════════════════════════════════════════════════════════════════ */

function GamesGridSkeleton() {
  return (
    <div className="px-4 pt-5 skel-enter">
      <ShimmerBar className="mb-5 h-7 w-44 rounded-xl" />
      <div className="grid grid-cols-3 gap-3">
        {Array.from({ length: 6 }).map((_, i) => (
          <div key={i} className="space-y-2.5" style={{ animationDelay: `${i * 80}ms` }}>
            <ShimmerBlock className="aspect-square rounded-[26%]" delay={i * 60} />
            <ShimmerBar className="mx-auto h-3 w-3/4" delay={i * 60 + 100} />
          </div>
        ))}
      </div>
    </div>
  );
}

function ListSkeleton() {
  return (
    <div className="space-y-3 px-4 pt-4 skel-enter">
      {Array.from({ length: 8 }).map((_, i) => (
        <div
          key={i}
          className="flex items-center gap-3 rounded-2xl border border-border/40 p-3.5"
          style={{ animationDelay: `${i * 60}ms` }}
        >
          <ShimmerBlock className="h-11 w-11 rounded-full" delay={i * 40} />
          <div className="flex-1 space-y-2">
            <ShimmerBar className="h-3 w-2/3" delay={i * 40 + 80} />
            <ShimmerBar className="h-3 w-1/3" delay={i * 40 + 120} />
          </div>
          <ShimmerBar className="h-7 w-18 rounded-xl" delay={i * 40 + 160} />
        </div>
      ))}
    </div>
  );
}

function ProfileSkeleton() {
  return (
    <div className="space-y-5 px-4 pt-6 skel-enter">
      {/* Avatar + name */}
      <div className="flex flex-col items-center gap-3">
        <ShimmerBlock className="h-24 w-24 rounded-full" />
        <ShimmerBar className="h-5 w-40" />
        <ShimmerBar className="h-3 w-28" />
      </div>
      {/* Stats cards */}
      <div className="grid grid-cols-3 gap-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <ShimmerBlock key={i} className="h-20 rounded-2xl" delay={i * 100} />
        ))}
      </div>
      {/* List items */}
      <div className="space-y-2.5">
        {Array.from({ length: 4 }).map((_, i) => (
          <ShimmerBlock key={i} className="h-16 rounded-2xl" delay={i * 80} />
        ))}
      </div>
    </div>
  );
}

function BoardSkeleton() {
  return (
    <div className="flex flex-col gap-3.5 px-4 pt-4 skel-enter">
      <div className="flex items-center justify-between">
        <ShimmerBar className="h-7 w-28 rounded-xl" />
        <ShimmerBar className="h-7 w-18 rounded-xl" />
      </div>
      <div className="flex items-center gap-2.5">
        <ShimmerBlock className="h-11 w-11 rounded-full" />
        <ShimmerBar className="h-3 w-28" />
      </div>
      {/* Board placeholder with subtle inner pattern */}
      <div className="relative mx-auto aspect-square w-full max-w-md">
        <ShimmerBlock className="absolute inset-0 rounded-2xl" />
        <div className="absolute inset-0 grid grid-cols-4 grid-rows-4 gap-px p-4 opacity-30">
          {Array.from({ length: 16 }).map((_, i) => (
            <div key={i} className="rounded-md bg-muted-foreground/10" />
          ))}
        </div>
      </div>
      <div className="flex items-center gap-2.5">
        <ShimmerBlock className="h-11 w-11 rounded-full" />
        <ShimmerBar className="h-3 w-28" />
      </div>
    </div>
  );
}

function FormSkeleton() {
  return (
    <div className="space-y-5 px-4 pt-5 skel-enter">
      <ShimmerBar className="h-7 w-44 rounded-xl" />
      <ShimmerBlock className="h-13 rounded-2xl" />
      <ShimmerBlock className="h-13 rounded-2xl" delay={80} />
      <div className="grid grid-cols-2 gap-3">
        <ShimmerBlock className="h-22 rounded-2xl" />
        <ShimmerBlock className="h-22 rounded-2xl" delay={80} />
      </div>
      <ShimmerBlock className="h-13 rounded-2xl" delay={160} />
    </div>
  );
}

function GenericSkeleton() {
  return (
    <div className="space-y-5 px-4 pt-5 skel-enter">
      <ShimmerBar className="h-7 w-44 rounded-xl" />
      <ShimmerBlock className="h-36 rounded-2xl" />
      <div className="space-y-2.5">
        <ShimmerBar className="h-3 w-full" />
        <ShimmerBar className="h-3 w-5/6" delay={60} />
        <ShimmerBar className="h-3 w-2/3" delay={120} />
      </div>
      <div className="grid grid-cols-2 gap-3">
        <ShimmerBlock className="h-26 rounded-2xl" />
        <ShimmerBlock className="h-26 rounded-2xl" delay={80} />
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════
   BRAND SPLASH — shown on initial full-page load (before JS hydrates)
   ═════════════════════════════════════════════════════════════════════════ */
function BrandSplash() {
  return (
    <div className="fixed inset-0 z-[200] flex flex-col items-center justify-center bg-background gap-6">
      {/* Logo dots */}
      <div className="relative w-14 h-14">
        <div className="absolute inset-0 rounded-2xl bg-gradient-to-br from-red-500 via-orange-500 to-yellow-400 opacity-20 blur-lg" />
        <div className="relative grid grid-cols-2 gap-[4px] w-14 h-14 p-2.5">
          {[0, 1, 2, 3].map(i => (
            <div
              key={i}
              className="rounded-full"
              style={{
                animation: `brand-pulse 1.2s ease-in-out ${i * 0.15}s infinite`,
                background: [
                  "linear-gradient(135deg, #ef4444, #dc2626)",
                  "linear-gradient(135deg, #4ade80, #16a34a)",
                  "linear-gradient(135deg, #3b82f6, #2563eb)",
                  "linear-gradient(135deg, #facc15, #f97316)",
                ][i],
                boxShadow: "0 2px 6px rgba(0,0,0,0.1)",
              }}
            />
          ))}
        </div>
      </div>
      {/* Brand text */}
      <div className="text-center">
        <p className="font-black text-lg tracking-tight bg-gradient-to-r from-primary to-orange-400 bg-clip-text text-transparent">
          Lalao MADA
        </p>
      </div>
      {/* Loading dots */}
      <div className="flex items-center gap-1.5">
        {[0, 1, 2].map(i => (
          <div
            key={i}
            className="w-2 h-2 rounded-full bg-primary/60"
            style={{ animation: `brand-pulse 0.9s ease-in-out ${i * 0.12}s infinite` }}
          />
        ))}
      </div>
    </div>
  );
}

function pickSkeleton(pathname: string) {
  if (pathname === "/" || pathname.startsWith("/jeux/")) return <FormSkeleton />;
  if (pathname === "/jeux" || pathname.startsWith("/jeux/")) return <GamesGridSkeleton />;
  if (
    pathname.startsWith("/ludo/") ||
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
    pathname.startsWith("/accueil") ||
    pathname.startsWith("/discussion") ||
    pathname.startsWith("/admin")
  ) {
    return <ListSkeleton />;
  }
  return <GenericSkeleton />;
}

/* ═══════════════════════════════════════════════════════════════════════════
   ROUTE SKELETON OVERLAY — fades in after 250ms delay (was 350ms)
   ═════════════════════════════════════════════════════════════════════════ */
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
    const t = setTimeout(() => setShow(true), 250);
    return () => clearTimeout(t);
  }, [isLoading, pathname]);
  if (!isLoading || !show) return null;
  return (
    <div
      aria-hidden
      className="pointer-events-none fixed inset-x-0 bottom-0 z-30 transition-opacity duration-300"
      style={{ top: 56 }}
    >
      <div className="h-full w-full overflow-hidden bg-background/80 backdrop-blur-[2px]">
        {pickSkeleton(pathname)}
      </div>
    </div>
  );
}

/* ═══════════════════════════════════════════════════════════════════════════
   NOT FOUND / ERROR — same as before but slightly polished
   ═════════════════════════════════════════════════════════════════════════ */
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

/* ═══════════════════════════════════════════════════════════════════════════
   ROOT ROUTE
   ═════════════════════════════════════════════════════════════════════════ */
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

function RootComponent() {
  const { queryClient } = Route.useRouteContext();
  const [mounted, setMounted] = React.useState(false);
  React.useEffect(() => {
    const t = setTimeout(() => setMounted(true), 50);
    return () => clearTimeout(t);
  }, []);

  return (
    <QueryClientProvider client={queryClient}>
      <I18nProvider>
        <AuthProvider>
          <ConfirmProvider>
            <ShimmerStyle />
            <TopLoadingBar />
            {!mounted && <BrandSplash />}
            <Outlet />
            <RouteSkeletonOverlay />
            <AutoTranslator />
            <GlobalPopups />
            <Toaster richColors position="top-center" />
          </ConfirmProvider>
        </AuthProvider>
      </I18nProvider>
    </QueryClientProvider>
  );
}
