import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /jeux/nouveau/$slug → /jeux/$slug
export const Route = createFileRoute("/_authenticated/jeux/nouveau/$slug")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/$slug", params: { slug: params.slug } });
  },
});
