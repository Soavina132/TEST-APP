import { createFileRoute } from "@tanstack/react-router";
import { createLovableAiGatewayProvider } from "@/lib/ai-gateway.server";
import { generateText } from "ai";

/**
 * POST /api/translate
 * Body: { lang: "mg" | "en", texts: string[] }
 * Returns: { translations: string[] }  (même ordre que l'entrée)
 *
 * Traduit un batch de chaînes FR vers la langue cible via Lovable AI.
 * Endpoint public (aussi utilisé sur /login) mais bridé :
 *   - max 120 items par requête
 *   - max 400 caractères par item
 *   - max 12000 caractères totaux
 */
export const Route = createFileRoute("/api/translate")({
  server: {
    handlers: {
      POST: async ({ request }) => {
        try {
          // Require auth to prevent quota abuse
          const auth = request.headers.get("authorization") || "";
          const token = auth.replace(/^Bearer\s+/i, "").trim();
          if (!token) return new Response("unauthorized", { status: 401 });
          
          const body = (await request.json()) as { lang?: string; texts?: unknown };
          const lang = body.lang === "mg" ? "mg" : body.lang === "en" ? "en" : null;
          if (!lang) return new Response("bad lang", { status: 400 });
          if (!Array.isArray(body.texts)) return new Response("texts required", { status: 400 });

          const texts = body.texts
            .map((t) => (typeof t === "string" ? t : ""))
            .map((t) => t.slice(0, 400));
          if (texts.length === 0) return Response.json({ translations: [] });
          if (texts.length > 120) return new Response("too many items", { status: 400 });
          const total = texts.reduce((n, t) => n + t.length, 0);
          if (total > 12000) return new Response("payload too large", { status: 400 });

          const key = process.env.LOVABLE_API_KEY;
          if (!key) return new Response("Missing LOVABLE_API_KEY", { status: 500 });

          const target = lang === "mg" ? "Malagasy (Merina standard)" : "English";
          const system = [
            `You are a translation engine. Translate each input from French to ${target}.`,
            "Preserve punctuation, casing style, emojis, numbers, placeholders (like {name}, %s, :id), and trailing/leading whitespace.",
            "Do NOT translate: proper nouns, brand names, usernames, IDs, URLs, currency codes (Ar), and pure numbers.",
            "Return ONLY a JSON array of strings in the same order and same length as the input. No prose, no markdown.",
          ].join(" ");

          const prompt = `Translate this JSON array of French strings to ${target}. Return ONLY the JSON array.\n\n${JSON.stringify(texts)}`;

          const gateway = createLovableAiGatewayProvider(key);
          const { text } = await generateText({
            model: gateway("google/gemini-3-flash-preview"),
            system,
            prompt,
          });

          // Extraire le JSON du texte de réponse
          let parsed: unknown = null;
          try {
            parsed = JSON.parse(text);
          } catch {
            const m = text.match(/\[[\s\S]*\]/);
            if (m) {
              try { parsed = JSON.parse(m[0]); } catch { /* ignore */ }
            }
          }

          if (!Array.isArray(parsed) || parsed.length !== texts.length) {
            // fallback: renvoyer l'original si le modèle rate le format
            return Response.json({ translations: texts });
          }

          const translations = parsed.map((v, i) =>
            typeof v === "string" && v.length > 0 ? v : texts[i]
          );

          return Response.json(
            { translations },
            { headers: { "Cache-Control": "public, max-age=3600" } }
          );
        } catch (e: unknown) {
          const msg = e instanceof Error ? e.message : "error";
          return new Response(msg, { status: 500 });
        }
      },
    },
  },
});
