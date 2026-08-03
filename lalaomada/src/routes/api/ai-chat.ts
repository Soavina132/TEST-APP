import { createFileRoute } from "@tanstack/react-router";
import { createLovableAiGatewayProvider } from "@/lib/ai-gateway.server";
import { streamText, convertToModelMessages, type UIMessage } from "ai";
import { createClient } from "@supabase/supabase-js";

function uiTextOf(m: UIMessage): string {
  return (m.parts || []).map((p: any) => (p.type === "text" ? p.text : "")).join("").trim();
}

/** Supprime les balises HTML et décode les entités HTML basiques */
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

export const Route = createFileRoute("/api/ai-chat")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        try {
          const body = (await request.json()) as {
            messages?: UIMessage[];
            appContext?: string;
          };
          if (!Array.isArray(body.messages) || body.messages.length === 0) {
            return new Response("messages required", { status: 400 });
          }

          const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL!;
          const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY!;

          // Require an authenticated caller — prevents unauthenticated LOVABLE_API_KEY quota abuse
          const auth = request.headers.get("authorization") || "";
          const token = auth.replace(/^Bearer\s+/i, "").trim();
          if (!token) {
            return new Response("unauthorized", { status: 401 });
          }
          const userClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
          const { data: userData } = await userClient.auth.getUser();
          const userId: string | null = userData?.user?.id ?? null;
          if (!userId) {
            return new Response("unauthorized", { status: 401 });
          }

          // ── Charger TOUS les paramètres admin depuis app_settings ───────────
          // C'est la source de vérité officielle : numéro admin, opérateur,
          // montants min, instructions dépôt/retrait, notes personnalisées IA.
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
            return new Response("AI assistant disabled", { status: 403 });
          }

          const lovableKey = process.env.LOVABLE_API_KEY;
          if (!lovableKey) return new Response("Missing LOVABLE_API_KEY", { status: 500 });

          // ── Construire le bloc d'informations officielles de l'application ──
          // L'IA DOIT utiliser ces données avant de répondre sur les paiements,
          // contacts ou règles financières. Ne jamais inventer si c'est ici.
          const infoLines: string[] = [
            "=== INFORMATIONS OFFICIELLES LALAO MADA (source de vérité) ===",
          ];

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

          // ── System prompt final ────────────────────────────────────────────
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

          // Contexte temps réel envoyé par le client (page, profil, parties, etc.)
          const realtimeBlock =
            body.appContext && body.appContext.trim()
              ? `\n\n${body.appContext}`
              : "";

          const systemPrompt = `${baseInstructions}\n\n${officialInfoBlock}${realtimeBlock}`;

          const gateway = createLovableAiGatewayProvider(lovableKey);
          const result = streamText({
            model: gateway("google/gemini-3-flash-preview"),
            system: systemPrompt,
            messages: await convertToModelMessages(body.messages),
          });

          return result.toUIMessageStreamResponse({
            originalMessages: body.messages,
            onFinish: async ({ messages: finalMessages }) => {
              if (!userId) return;
              try {
                const writer = createClient(url, anonKey, {
                  global: { headers: { Authorization: `Bearer ${token}` } },
                });
                const lastUser = [...finalMessages].reverse().find((m) => m.role === "user");
                const lastAssistant = [...finalMessages].reverse().find((m) => m.role === "assistant");
                const rows: { user_id: string; role: "user" | "assistant"; content: string }[] = [];
                if (lastUser) {
                  const t = uiTextOf(lastUser as UIMessage);
                  if (t) rows.push({ user_id: userId, role: "user", content: t });
                }
                if (lastAssistant) {
                  const t = uiTextOf(lastAssistant as UIMessage);
                  if (t) rows.push({ user_id: userId, role: "assistant", content: t });
                }
                if (rows.length) await writer.from("assistant_messages").insert(rows);
              } catch {
                /* persistence failures must not break streaming */
              }
            },
          });
        } catch (e: any) {
          return new Response(e?.message || "error", { status: 500 });
        }
      },
    },
  },
});
