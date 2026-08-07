// ═══════════════════════════════════════════════════════════════════════
// validate-deposit-sms — Edge Function Supabase v3 (sécurité renforcée)
//
// POST /functions/v1/validate-deposit-sms
// Body: { "secret": "xxx", "operator": "orange|mvola", "sms": "...",
//         "timestamp": "1234567890", "signature": "hmac_hex" }
//
// SÉCURITÉ v3:
//   1. Vérification du secret API (OBLIGATOIRE)
//   2. Vérification de la signature HMAC-SHA256 (OBLIGATOIRE — anti-replay)
//   3. Vérification du timestamp (fenêtre de 5 minutes)
//   4. La clé service_role n'est JAMAIS reçue du client
//   5. CORS restreint à l'URL de l'app (pas *)
//   6. Pas de secret hardcodé en fallback
//
// Architecture:
//   ParserFactory → OrangeParser | MVolaParser
//   → validate_deposit_from_sms() (PostgreSQL, atomique)
// ═══════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

// ═══════════════════════════════════════════════════════════════════════
// TYPES
// ═══════════════════════════════════════════════════════════════════════

interface ParsedSMS {
  amount: number | null;
  sender_number: string | null;
  sender_name: string | null;
  transaction_id: string | null;
  sms_date: string | null;
}

interface ParseResult {
  success: boolean;
  data?: ParsedSMS;
  error?: string;
}

// ═══════════════════════════════════════════════════════════════════════
// ORANGE PARSER
// ═══════════════════════════════════════════════════════════════════════

class OrangeParser {
  parse(sms: string): ParseResult {
    if (/vous avez reçu/i.test(sms) || /transfert/i.test(sms)) {
      return this.parseFormat1(sms);
    }
    if (/recu de/i.test(sms) || /Ref\s+\d/i.test(sms)) {
      return this.parseFormat2(sms);
    }
    return { success: false, error: "Format Orange Money non reconnu" };
  }

  private parseFormat1(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, sender_name: null, transaction_id: null, sms_date: null };
    const amountMatch = sms.match(/(?:transfert|recu|reçu)\s+de\s+([\d\s]+)\s*Ar/i);
    if (amountMatch) result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    const senderMatch = sms.match(/venant\s+du\s+(\d[\d\s]+)/i);
    if (senderMatch) result.sender_number = senderMatch[1].trim();
    const transIdMatch = sms.match(/Trans\s*Id\s*:?\s*([A-Z0-9.]+)/i);
    if (transIdMatch) result.transaction_id = transIdMatch[1].trim();
    if (!result.transaction_id) return { success: false, error: "Trans Id manquant (Format 1)" };
    if (result.amount === null || isNaN(result.amount)) return { success: false, error: "Montant manquant (Format 1)" };
    return { success: true, data: result };
  }

  private parseFormat2(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, sender_name: null, transaction_id: null, sms_date: null };
    const amountMatch = sms.match(/([\d\s]+)\s*Ar\s+recu\s+de/i);
    if (amountMatch) result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    const senderMatch = sms.match(/recu\s+de\s+(.+?)\s+(\d{10,})/i);
    if (senderMatch) { result.sender_name = senderMatch[1].trim(); result.sender_number = senderMatch[2]; }
    const dateMatch = sms.match(/le\s+(\d{2}\/\d{2}\/\d{2,4})\s+[àa]\s+(\d{2}:\d{2})/i);
    if (dateMatch) result.sms_date = `${dateMatch[1]} ${dateMatch[2]}`;
    const refMatch = sms.match(/Ref\s+(\d+)/i);
    if (refMatch) result.transaction_id = refMatch[1];
    if (!result.transaction_id) return { success: false, error: "Ref manquante (Format 2)" };
    if (result.amount === null || isNaN(result.amount)) return { success: false, error: "Montant manquant (Format 2)" };
    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MVOLA PARSER
// ═══════════════════════════════════════════════════════════════════════

class MVolaParser {
  parse(sms: string): ParseResult {
    if (/recu/i.test(sms) || /ref/i.test(sms)) return this.parseFormat1(sms);
    if (/transaction/i.test(sms) || /montant/i.test(sms)) return this.parseFormat2(sms);
    return { success: false, error: "Format MVola non reconnu" };
  }

  private parseFormat1(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, sender_name: null, transaction_id: null, sms_date: null };
    const amountMatch = sms.match(/(?:recu|recus|reçu)\s+([\d\s]+)\s*Ar/i);
    if (amountMatch) result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    const senderMatch = sms.match(/de\s+(.+?)\s*\(?(\d{10,})?/i);
    if (senderMatch) { result.sender_name = senderMatch[1].trim(); if (senderMatch[2]) result.sender_number = senderMatch[2]; }
    const refMatch = sms.match(/(?:ref|reference)[:\s]+([A-Z0-9]+)/i);
    if (refMatch) result.transaction_id = refMatch[1];
    if (!result.transaction_id) return { success: false, error: "Ref MVola manquante (Format 1)" };
    return { success: true, data: result };
  }

  private parseFormat2(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, sender_name: null, transaction_id: null, sms_date: null };
    const amountMatch = sms.match(/montant\s*:?\s*([\d\s]+)\s*Ar/i);
    if (amountMatch) result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    const senderMatch = sms.match(/de\s*:?\s*(.+?)(?:\s+\(?(\d{10,})|$)/i);
    if (senderMatch) { result.sender_name = senderMatch[1].trim(); if (senderMatch[2]) result.sender_number = senderMatch[2]; }
    const refMatch = sms.match(/(?:ref|reference)[:\s]+([A-Z0-9]+)/i);
    if (refMatch) result.transaction_id = refMatch[1];
    if (!result.transaction_id) return { success: false, error: "Ref MVola manquante (Format 2)" };
    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PARSER FACTORY
// ═══════════════════════════════════════════════════════════════════════

class ParserFactory {
  static getParser(operator: string): OrangeParser | MVolaParser | null {
    switch (operator.toLowerCase().trim()) {
      case "orange": return new OrangeParser();
      case "mvola": case "m-vola": return new MVolaParser();
      default: return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SÉCURITÉ — HMAC VERIFICATION
// ═══════════════════════════════════════════════════════════════════════

async function verifyHMAC(secret: string, payload: string, timestamp: string, signature: string): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const ts = parseInt(timestamp, 10);
  if (isNaN(ts) || Math.abs(now - ts) > 300) {
    return false;
  }

  const message = `${timestamp}${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const expected = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  const expectedHex = Array.from(new Uint8Array(expected))
    .map(b => b.toString(16).padStart(2, "0"))
    .join("");

  return expectedHex === signature;
}

// ═══════════════════════════════════════════════════════════════════════
// HANDLER
// ═══════════════════════════════════════════════════════════════════════

// FIX v3: Pas de secret hardcodé — erreur si env var manquante
const DEPOSIT_SECRET = Deno.env.get("DEPOSIT_SMS_SECRET");
if (!DEPOSIT_SECRET) {
  console.error("ERREUR CRITIQUE: DEPOSIT_SMS_SECRET env var non définie");
}

// FIX v3: CORS restreint au domaine de l'app
const ALLOWED_ORIGINS = [
  "https://test-app.vercel.app",
  "https://gifwfjgciwbsottztzoc.supabase.co",
  "http://localhost:5173",
  "http://localhost:3000",
];

function getCORSHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Methods": "POST",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
  };
  if (origin && ALLOWED_ORIGINS.includes(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

function json(data: unknown, status = 200, corsHeaders?: Record<string, string>): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...(corsHeaders || {}),
    },
  });
}

serve(async (req: Request) => {
  const origin = req.headers.get("Origin");

  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 200,
      headers: getCORSHeaders(origin),
    });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, getCORSHeaders(origin));
  }

  // FIX v3: Vérifier que le secret est configuré
  if (!DEPOSIT_SECRET) {
    return json({ success: false, error: "SERVER_MISCONFIG", message: "Secret non configuré" }, 500, getCORSHeaders(origin));
  }

  try {
    const body = await req.json();
    const { secret, operator, sms, timestamp, signature } = body as {
      secret?: string;
      operator?: string;
      sms?: string;
      timestamp?: string;
      signature?: string;
    };

    // 1. Vérifier le secret
    if (!secret || secret !== DEPOSIT_SECRET) {
      return json({ success: false, error: "UNAUTHORIZED", message: "Secret invalide" }, 401, getCORSHeaders(origin));
    }

    // FIX v3: HMAC OBLIGATOIRE (plus de mode rétrocompatible)
    if (!timestamp || !signature) {
      return json({ success: false, error: "MISSING_SIGNATURE", message: "Timestamp et signature HMAC obligatoires" }, 401, getCORSHeaders(origin));
    }

    const payloadStr = JSON.stringify({ operator, sms });
    const valid = await verifyHMAC(DEPOSIT_SECRET, payloadStr, timestamp, signature);
    if (!valid) {
      return json({ success: false, error: "INVALID_SIGNATURE", message: "Signature HMAC invalide ou expirée" }, 401, getCORSHeaders(origin));
    }

    if (!operator || !sms) {
      return json({ success: false, error: "MISSING_PARAMS", message: "operator et sms requis" }, 400, getCORSHeaders(origin));
    }

    // 2. Obtenir le parser
    const parser = ParserFactory.getParser(operator);
    if (!parser) {
      return json({ success: false, error: "UNKNOWN_OPERATOR", message: `Opérateur inconnu: ${operator}` }, 400, getCORSHeaders(origin));
    }

    // 3. Parser le SMS
    const parseResult = parser.parse(sms);
    if (!parseResult.success || !parseResult.data) {
      const supabase = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      await supabase.from("deposit_transactions").insert({
        operator,
        transaction_id: `PARSE_ERROR_${Date.now()}`,
        sms_content: sms,
        status: "rejected",
        rejection_reason: parseResult.error || "Parse error",
      });
      return json({ success: false, error: "PARSE_ERROR", message: parseResult.error }, 422, getCORSHeaders(origin));
    }

    const parsed = parseResult.data;

    // 4. Valider via la fonction PostgreSQL (atomique)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: result, error } = await supabase.rpc("validate_deposit_from_sms", {
      _operator: operator,
      _transaction_id: parsed.transaction_id,
      _sender_number: parsed.sender_number,
      _sender_name: parsed.sender_name,
      _amount: parsed.amount,
      _sms_date: parsed.sms_date,
      _sms_content: sms,
    });

    if (error) {
      return json({ success: false, error: "DB_ERROR", message: error.message }, 500, getCORSHeaders(origin));
    }

    return json(result, result?.success ? 200 : 422, getCORSHeaders(origin));
  } catch (err) {
    return json({ success: false, error: "INTERNAL_ERROR", message: String(err) }, 500, getCORSHeaders(origin));
  }
});
