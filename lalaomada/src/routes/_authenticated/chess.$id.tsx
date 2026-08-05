import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /chess/$id → /jeux/chess/$id
export const Route = createFileRoute("/_authenticated/chess/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/chess/$id", params: { id: params.id } });
  },
});
