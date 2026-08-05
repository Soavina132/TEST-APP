import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";

const Input = z.object({
  contact: z.string().min(3),
  contactType: z.enum(["email", "phone"]),
  code: z.string().regex(/^\d{4,8}$/),
  newPassword: z.string().min(6).max(72),
});

export const completePasswordReset = createServerFn({ method: "POST" })
  .inputValidator((d: unknown) => Input.parse(d))
  .handler(async ({ data }) => {
    const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
    const norm = data.contactType === "email"
      ? data.contact.trim().toLowerCase()
      : data.contact.trim().replace(/[\s.-]/g, "");

    const { data: rows, error } = await supabaseAdmin
      .from("password_reset_requests")
      .select("id, user_id, status, code, contact, contact_type, created_at")
      .eq("contact", norm)
      .eq("contact_type", data.contactType)
      .eq("status", "sent")
      .order("created_at", { ascending: false })
      .limit(1);
    if (error) throw new Error(error.message);
    const row = rows?.[0];
    if (!row || row.code !== data.code) {
      throw new Error("Code invalide ou non encore validé par l'administrateur");
    }
    // Expire codes older than 24h
    if (new Date(row.created_at).getTime() < Date.now() - 24 * 3600 * 1000) {
      throw new Error("Ce code a expiré, refaites une demande");
    }
    if (!row.user_id) throw new Error("Demande invalide");
    const { error: uErr } = await supabaseAdmin.auth.admin.updateUserById(row.user_id, {
      password: data.newPassword,
    });
    if (uErr) throw new Error(uErr.message);
    await supabaseAdmin
      .from("password_reset_requests")
      .update({ status: "done", resolved_at: new Date().toISOString() })
      .eq("id", row.id);
    return { ok: true };
  });
