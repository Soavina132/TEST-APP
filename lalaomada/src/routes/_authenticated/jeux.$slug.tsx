import { createFileRoute, redirect } from "@tanstack/react-router";

// Route legacy : redirige toujours vers le vrai écran de création de partie.
// Ne PAS ajouter de logique ici — ce composant ne se monte jamais.
export const Route = createFileRoute("/_authenticated/jeux/$slug")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/nouveau/$slug", params: { slug: params.slug } });
  },
});
