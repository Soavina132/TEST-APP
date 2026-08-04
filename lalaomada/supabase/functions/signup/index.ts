// Supabase Edge Function: signup
// POST /functions/v1/signup  { phone, password, pseudo, referral_code? }
// Public endpoint (no user auth required — this IS the signup flow). Uses the
// service-role key internally to create a phone-verified user.
import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import { z } from "npm:zod@3.24.2";
import { corsHeaders } from "../_shared/cors.ts";

const PhoneSignupInput = z.object({
  phone: z.string().regex(/^\+261\d{9}$/, "Numéro invalide"),
  password: z.string().min(6).max(72),
  pseudo: z.string().trim().min(1).max(60),
  referral_code: z.string().trim().max(20).optional().nullable(),
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
    const data = PhoneSignupInput.parse(raw);

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(url, serviceRoleKey);

    // Refuse si le numéro est déjà utilisé (auth.users.phone)
    const { data: existing } = await supabaseAdmin.auth.admin.listUsers({ page: 1, perPage: 1000 });
    const already = existing?.users?.some(
      (u: any) => u.phone === data.phone.replace(/^\+/, "") || u.phone === data.phone
    );
    if (already) return json({ error: "Ce numéro est déjà utilisé" }, 409);

    const { data: created, error } = await supabaseAdmin.auth.admin.createUser({
      phone: data.phone,
      password: data.password,
      phone_confirm: true,
      user_metadata: {
        pseudo: data.pseudo,
        referral_code: (data.referral_code || "").toUpperCase() || null,
        phone: data.phone,
      },
    });
    if (error) return json({ error: error.message }, 400);

    return json({ ok: true, user_id: created.user?.id });
  } catch (e: any) {
    const message = e?.issues ? e.issues.map((i: any) => i.message).join(", ") : e?.message || "error";
    return json({ error: message }, 400);
  }
});
