// Supabase Edge Function: password-reset
// POST /functions/v1/password-reset  { contact, contactType, code, newPassword }
// Public endpoint (this completes an admin-approved reset code). Uses the
// service-role key internally.
import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import { z } from "npm:zod@3.24.2";
import { corsHeaders } from "../_shared/cors.ts";

const Input = z.object({
  contact: z.string().min(3),
  contactType: z.enum(["email", "phone"]),
  code: z.string().regex(/^\d{4,8}$/),
  newPassword: z.string().min(6).max(72),
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    const raw = await req.json();
    const data = Input.parse(raw);

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(url, serviceRoleKey);

    const norm =
      data.contactType === "email"
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
    if (error) return json({ error: error.message }, 400);

    const row = rows?.[0] as any;
    if (!row || row.code !== data.code) {
      return json({ error: "Code invalide ou non encore validé par l'administrateur" }, 400);
    }
    if (new Date(row.created_at).getTime() < Date.now() - 24 * 3600 * 1000) {
      return json({ error: "Ce code a expiré, refaites une demande" }, 400);
    }
    if (!row.user_id) return json({ error: "Demande invalide" }, 400);

    const { error: uErr } = await supabaseAdmin.auth.admin.updateUserById(row.user_id, {
      password: data.newPassword,
    });
    if (uErr) return json({ error: uErr.message }, 400);

    await supabaseAdmin
      .from("password_reset_requests")
      .update({ status: "done", resolved_at: new Date().toISOString() })
      .eq("id", row.id);

    return json({ ok: true });
  } catch (e: any) {
    const message = e?.issues ? e.issues.map((i: any) => i.message).join(", ") : e?.message || "error";
    return json({ error: message }, 400);
  }
});
