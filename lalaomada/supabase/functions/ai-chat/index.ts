// Supabase Edge Function: ai-chat
// POST /functions/v1/ai-chat  { messages: UIMessage[], appContext?: string }
// Requires an authenticated caller (Authorization: Bearer <user JWT>).
// Streams back an AI SDK UIMessage stream (compatible with useChat / DefaultChatTransport).
import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import { streamText, convertToModelMessages } from "npm:ai@6.0.197";
import { createOpenAICompatible } from "npm:@ai-sdk/openai-compatible@2.0.48";
import { corsHeaders } from "../_shared/cors.ts";

function uiTextOf(m: any): string {
  return (m.parts || []).map((p: any) => (p.type === "text" ? p.text : "")).join("").trim();
}

function stripHtml(html: string): string {
  return html
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/\s{2,}/g, " ")
    .trim();
}

function createLovableAiGatewayProvider(lovableApiKey: string) {
  return createOpenAICompatible({
    name: "lovable",
    baseURL: "https://ai.gateway.lovable.dev/v1",
    headers: {
      "Lovable-API-Key": lovableApiKey,
      "X-Lovable-AIG-SDK": "vercel-ai-sdk",
    },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const body = (await req.json()) as { messages?: any[]; appContext?: string };
    if (!Array.isArray(body.messages) || body.messages.length === 0) {
      return new Response("messages required", { status: 400, headers: corsHeaders });
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const auth = req.headers.get("authorization") || "";
    const token = auth.replace(/^Bearer\s+/i, "").trim();
    if (!token) return new Response("unauthorized", { status: 401, headers: corsHeaders });

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    const userId: string | null = userData?.user?.id ?? null;
    if (!userId) return new Response("unauthorized", { status: 401, headers: corsHeaders });

    const admin = createClient(url, anonKey);
    const { data: appSettings } = await admin
      .from("app_settings")
      .select(
        "ai_assistant_enabled, ai_assistant_context, admin_phone, admin_label, " +
          "min_deposit, min_withdraw, signup_bonus, game_commission_pct, " +
          "deposit_help_html, withdrawal_help_html"
      )
      .eq("id", 1)
      .maybeSingle();

    if (appSettings && appSettings.ai_assistant_enabled === false) {
      return new Response("AI assistant disabled", { status: 403, headers: corsHeaders });
    }

    const lovableKey = Deno.env.get("LOVABLE_API_KEY");
    if (!lovableKey) return new Response("Missing LOVABLE_API_KEY", { status: 500, headers: corsHeaders });

    const infoLines: string[] = ["=== INFORMATIONS OFFICIELLES LALAO MADA (source de vérité) ==="];

    if (appSettings) {
      const phone = appSettings.admin_phone as string | null;
      const label = appSettings.admin_label as string | null;
      const minDep = appSettings.min_deposit as number | null;
      const minWith = appSettings.min_withdraw as number | null;
      const bonus = appSettings.signup_bonus as number | null;
      const commission = appSettings.game_commission_pct as number | null;
      const depHelp = appSettings.deposit_help_html as string | null;
      const withHelp = appSettings.withdrawal_help_html as string | null;
      const customCtx = appSettings.ai_assistant_context as string | null;

      infoLines.push("");
      infoLines.push("📱 CONTACT ADMIN :");
      if (phone) infoLines.push(`  Numéro Mobile Money : ${phone}`);
      if (label) infoLines.push(`  Opérateur           : ${label}`);
      if (!phone && !label) infoLines.push("  (non renseigné)");

      infoLines.push("");
      infoLines.push("💰 PARAMÈTRES FINANCIERS :");
      if (minDep != null) infoLines.push(`  Dépôt minimum   : ${Number(minDep).toLocaleString("fr-FR")} Ar`);
      if (minWith != null) infoLines.push(`  Retrait minimum : ${Number(minWith).toLocaleString("fr-FR")} Ar`);
      if (bonus != null && bonus > 0) infoLines.push(`  Bonus inscription : ${Number(bonus).toLocaleString("fr-FR")} Ar`);
      if (commission != null) infoLines.push(`  Commission sur parties : ${commission}%`);

      if (depHelp && depHelp.trim()) {
        const plain = stripHtml(depHelp);
        if (plain.length > 10) {
          infoLines.push("");
          infoLines.push("📥 INSTRUCTIONS DÉPÔT :");
          infoLines.push("  " + plain.replace(/\n/g, "\n  "));
        }
      }

      if (withHelp && withHelp.trim()) {
        const plain = stripHtml(withHelp);
        if (plain.length > 10) {
          infoLines.push("");
          infoLines.push("📤 INSTRUCTIONS RETRAIT :");
          infoLines.push("  " + plain.replace(/\n/g, "\n  "));
        }
      }

      if (customCtx && customCtx.trim()) {
        infoLines.push("");
        infoLines.push("📋 INFORMATIONS COMPLÉMENTAIRES (ajoutées par l'admin) :");
        infoLines.push(customCtx.trim());
      }
    }

    infoLines.push("=== FIN DES INFORMATIONS OFFICIELLES ===");
    const officialInfoBlock = infoLines.join("\n");

    const baseInstructions = [
      "Tu es l'assistant officiel de Lalao MADA, plateforme de jeux malgaches en ligne",
      "(Fanorona, Échecs, Domino, Ludo, Rami, Poker).",
      "Réponds en français, de façon concise, claire et amicale. Utilise du markdown si utile.",
      "",
      "RÈGLES IMPORTANTES :",
      "1. Pour toute question sur le numéro admin, dépôt, retrait, ou contact :",
      "   → Utilise UNIQUEMENT les informations officielles ci-dessous.",
      "   → Ne jamais inventer un numéro, montant ou procédure.",
      "   → Si une information est absente des données officielles, dis-le clairement.",
      "2. Pour les données en temps réel (solde, parties disponibles, page actuelle) :",
      "   → Utilise le contexte temps réel fourni avec chaque message.",
      "3. Ne répète pas les blocs de contexte dans ta réponse.",
    ].join("\n");

    const realtimeBlock = body.appContext && body.appContext.trim() ? `\n\n${body.appContext}` : "";
    const systemPrompt = `${baseInstructions}\n\n${officialInfoBlock}${realtimeBlock}`;

    const gateway = createLovableAiGatewayProvider(lovableKey);
    const result = streamText({
      model: gateway("google/gemini-3-flash-preview"),
      system: systemPrompt,
      messages: await convertToModelMessages(body.messages as any),
    });

    const streamResponse = result.toUIMessageStreamResponse({
      originalMessages: body.messages as any,
      onFinish: async ({ messages: finalMessages }: any) => {
        if (!userId) return;
        try {
          const writer = createClient(url, anonKey, {
            global: { headers: { Authorization: `Bearer ${token}` } },
          });
          const lastUser = [...finalMessages].reverse().find((m: any) => m.role === "user");
          const lastAssistant = [...finalMessages].reverse().find((m: any) => m.role === "assistant");
          const rows: { user_id: string; role: "user" | "assistant"; content: string }[] = [];
          if (lastUser) {
            const t = uiTextOf(lastUser);
            if (t) rows.push({ user_id: userId, role: "user", content: t });
          }
          if (lastAssistant) {
            const t = uiTextOf(lastAssistant);
            if (t) rows.push({ user_id: userId, role: "assistant", content: t });
          }
          if (rows.length) await writer.from("assistant_messages").insert(rows);
        } catch {
          /* persistence failures must not break streaming */
        }
      },
    });

    // Merge CORS headers into the streaming response
    const headers = new Headers(streamResponse.headers);
    for (const [k, v] of Object.entries(corsHeaders)) headers.set(k, v);
    return new Response(streamResponse.body, { status: streamResponse.status, headers });
  } catch (e) {
    return new Response((e as Error)?.message || "error", { status: 500, headers: corsHeaders });
  }
});
