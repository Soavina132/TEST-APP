import { createFileRoute, useRouter } from "@tanstack/react-router";
import { useEffect } from "react";
import { useAuth } from "@/hooks/use-auth";

export const Route = createFileRoute("/")({
  component: IndexRedirect,
  head: () => ({
    meta: [
      { title: "Lalao MADA — Jouez. Gagnez. Retirez en Ariary." },
      { name: "description", content: "La plateforme #1 de jeux en ligne à Madagascar : Ludo, Domino, Fanorona, Échecs, Rami — mises en Ariary via Mobile Money." },
      { property: "og:title", content: "Lalao MADA — Jouez. Gagnez. Retirez en Ariary." },
      { property: "og:description", content: "Rejoignez la première plateforme de jeux multijoueur malagasy." },
      { property: "og:type", content: "website" },
      { property: "og:url", content: "https://lalaomada.lovable.app/" },
    ],
  }),
});

function IndexRedirect() {
  const { user, loading } = useAuth();
  const router = useRouter();

  useEffect(() => {
    if (loading) return;
    router.navigate({ to: user ? "/lobby" : "/login", replace: true });
  }, [loading, user, router]);

  return (
    <div className="min-h-screen bg-background flex items-center justify-center">
      <div className="w-8 h-8 border-2 border-primary border-t-transparent rounded-full animate-spin" />
    </div>
  );
}
