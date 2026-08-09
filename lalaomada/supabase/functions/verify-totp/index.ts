// Supabase Edge Function: verify-totp
// POST /functions/v1/verify-totp  { code: "123456" }
// Requires: authenticated user (Bearer token). Reads the TOTP secret from
// user_totp_secrets (service-role only) and verifies the code server-side.
// The secret is NEVER returned to the client.
import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import { authenticator } from "npm:otplib@12.0.1";
import { corsHeaders } from "../_shared/cors.ts";

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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return json({ error: "Non authentifié" }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Create client with the user's token to get their ID
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userErr } = await userClient.auth.getUser();
    if (userErr || !user) return json({ error: "Session invalide" }, 401);

    // Read the TOTP secret with service-role (bypasses RLS)
    const adminClient = createClient(supabaseUrl, serviceKey);
    const { data: secretRow, error: dbErr } = await adminClient
      .from("user_totp_secrets")
      .select("totp_secret, enabled")
      .eq("user_id", user.id)
      .single();

    if (dbErr || !secretRow) {
      return json({ error: "2FA non configuré" }, 400);
    }
    if (!secretRow.enabled) {
      return json({ error: "2FA désactivé" }, 400);
    }

    // Verify the TOTP code server-side
    const body = await req.json();
    const code = String(body.code || "").replace(/\D/g, "");
    if (code.length !== 6) {
      return json({ error: "Code invalide" }, 400);
    }

    const isValid = authenticator.verify({
      token: code,
      secret: secretRow.totp_secret,
    });

    if (!isValid) {
      return json({ error: "Code 2FA incorrect" }, 401);
    }

    return json({ valid: true });
  } catch (err) {
    return json({ error: err.message || "Erreur serveur" }, 500);
  }
});
