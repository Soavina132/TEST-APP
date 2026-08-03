import { createFileRoute, Navigate } from "@tanstack/react-router";

export const Route = createFileRoute("/_authenticated/admin-extra")({
  component: () => <Navigate to="/admin" />,
  head: () => ({ meta: [{ title: "Admin — Lalao MADA" }, { name: "robots", content: "noindex" }] }),
});
