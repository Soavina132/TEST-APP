import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /poker/$id → /jeux/poker/$id
export const Route = createFileRoute("/_authenticated/poker/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/poker/$id", params: { id: params.id } });
  },
});
