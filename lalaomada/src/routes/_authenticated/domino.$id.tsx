import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /domino/$id → /jeux/domino/$id
export const Route = createFileRoute("/_authenticated/domino/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/domino/$id", params: { id: params.id } });
  },
});
