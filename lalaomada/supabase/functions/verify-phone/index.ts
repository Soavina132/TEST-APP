// Supabase Edge Function: verify-phone
// POST /functions/v1/verify-phone  { firebaseToken }
// Verifies a Firebase ID token using Google's public keys,
// extracts the phone number, and updates the user's Supabase profile.
import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import { corsHeaders } from "../_shared/cors.ts";
import { verifyToken, getGoogleCerts } from "./verify.ts";

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
    const { firebaseToken } = await req.json();
    if (!firebaseToken || typeof firebaseToken !== "string") {
      return json({ error: "Token Firebase manquant" }, 400);
    }

    // Verify the Firebase ID token using Google's public certs
    const certs = await getGoogleCerts();
    const payload = await verifyToken(firebaseToken, certs);

    if (!payload) {
      return json({ error: "Token Firebase invalide" }, 401);
    }

    // Extract phone number from the verified token
    const phoneNumber = payload.phone_number as string;
    if (!phoneNumber) {
      return json({ error: "Aucun numéro de téléphone dans le token" }, 400);
    }

    // Get the Supabase user from the Authorization header
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "Non authentifié" }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabaseAdmin = createClient(supabaseUrl, serviceRoleKey);

    // Extract the Supabase JWT from the Authorization header
    const supabaseToken = authHeader.replace("Bearer ", "");

    // Get the user ID from the Supabase JWT
    const { data: userData, error: userError } = await supabaseAdmin.auth.getUser(supabaseToken);
    if (userError || !userData.user) {
      return json({ error: "Utilisateur non trouvé" }, 401);
    }

    const userId = userData.user.id;

    // Update the profile with the verified phone number
    const { error: updateError } = await supabaseAdmin
      .from("profiles")
      .update({
        phone: phoneNumber,
        phone_verified: true,
        phone_verification_code: null,
      })
      .eq("id", userId);

    if (updateError) {
      return json({ error: "Erreur lors de la mise à jour du profil" }, 500);
    }

    return json({ success: true, phone: phoneNumber });
  } catch (err) {
    return json({ error: err?.message || "Erreur serveur" }, 500);
  }
});
