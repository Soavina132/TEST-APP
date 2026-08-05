import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /rami/$id → /jeux/rami/$id
export const Route = createFileRoute("/_authenticated/rami/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/rami/$id", params: { id: params.id } });
  },
});
