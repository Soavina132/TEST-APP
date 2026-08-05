import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /game/$id → /jeux/ludo/$id
export const Route = createFileRoute("/_authenticated/game/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/ludo/$id", params: { id: params.id } });
  },
});
