import { createFileRoute, redirect } from "@tanstack/react-router";

// Legacy redirect: /fanorona/$id → /jeux/fanorona/$id
export const Route = createFileRoute("/_authenticated/fanorona/$id")({
  beforeLoad: ({ params }) => {
    throw redirect({ to: "/jeux/fanorona/$id", params: { id: params.id } });
  },
});
