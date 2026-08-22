// ═══════════════════════════════════════════════════════════════════════
// validate-deposit-sms — Edge Function v9
//
// POST /functions/v1/validate-deposit-sms
// Body: { "secret": "xxx", "operator": "orange|mvola|airtel", "sms": "...",
//         "timestamp": "1234567890", "signature": "hmac_hex" }
//
// 3 champs extraits:
//   1. Montant — le PREMIER montant "Ar" trouvé dans le SMS
//   2. ID de transaction — PP... / CI... / Ref <nombre>
//   3. Numéro de téléphone (expéditeur)
//
// Si la référence ne match aucun format connu → "Le référence est incorrecte."
// ═══════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "npm:@supabase/supabase-js@2.39.0";

interface ParsedSMS {
  amount: number | null;
  sender_number: string | null;
  transaction_id: string | null;
}

interface ParseResult {
  success: boolean;
  data?: ParsedSMS;
  error?: string;
}

// ═══════════════════════════════════════════════════════════════════════
// PARSER UNIFIÉ
// ═══════════════════════════════════════════════════════════════════════

function parseSMS(sms: string): ParseResult {
  const result: ParsedSMS = { amount: null, sender_number: null, transaction_id: null };

  // ── 1. MONTANT — le PREMIER "Ar" trouvé dans le SMS ──
  const amountMatches = [...sms.matchAll(/(?:Ar\s+(\d[\d\s]*)|(\d[\d\s]*)\s*Ar)(?=\s|\.|,|$)/gi)];
  if (amountMatches.length > 0) {
    const m = amountMatches[0];
    const numStr = (m[1] || m[2] || "").replace(/\s/g, "");
    const val = parseInt(numStr, 10);
    if (!isNaN(val) && val > 0) result.amount = val;
  }

  // ── 2. ID DE TRANSACTION ──
  // Formats acceptés:
  //   Orange:  PP suivi de chiffres/points  (ex: PP260822.1225.D12303)
  //   Airtel:  CI suivi de chiffres/points  (ex: CI260811.1140.E34298)
  //   MVola:   Ref suivi de chiffres        (ex: Ref 5896099722)
  const ppMatch = sms.match(/\b(PP[\w.]*)/i);
  const ciMatch = sms.match(/\b(CI[\w.]*)/i);
  const refMatch = sms.match(/\bRef\s+(\d+)/i);
  if (ppMatch) result.transaction_id = ppMatch[1].replace(/\.$/, "");
  else if (ciMatch) result.transaction_id = ciMatch[1].replace(/\.$/, "");
  else if (refMatch) result.transaction_id = refMatch[1];

  // ── 3. NUMÉRO DE TÉLÉPHONE ──
  const phonePatterns = [
    /venant\s+du\s+(\d{9,10})/i,
    /from\s+\D+?(\d{9,10})/i,
    /recu\s+de\s+\D+?(\d{9,10})/i,
    /agent\s+(\d{9,10})/i,
  ];
  for (const p of phonePatterns) {
    const m = sms.match(p);
    if (m) {
      result.sender_number = m[1];
      break;
    }
  }

  // ── VALIDATION ──
  if (!result.amount || isNaN(result.amount)) return { success: false, error: "Montant manquant" };
  // Référence obligatoire — doit matcher PP, CI, ou Ref <nombre>
  if (!result.transaction_id) return { success: false, error: "Le référence est incorrecte." };
  return { success: true, data: result };
}

// ═══════════════════════════════════════════════════════════════════════
// HMAC
// ═══════════════════════════════════════════════════════════════════════

async function verifyHMAC(secret: string, payload: string, timestamp: string, signature: string): Promise<boolean> {
  const now = Math.floor(Date.now() / 1000);
  const ts = parseInt(timestamp, 10);
  if (isNaN(ts) || Math.abs(now - ts) > 300) return false;

  const message = `${timestamp}${payload}`;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign"]
  );
  const expected = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  const expectedHex = Array.from(new Uint8Array(expected)).map(b => b.toString(16).padStart(2, "0")).join("");
  return expectedHex === signature;
}

// ═══════════════════════════════════════════════════════════════════════
// CORS + HANDLER
// ═══════════════════════════════════════════════════════════════════════

function getCORSHeaders(origin: string | null): Record<string, string> {
  const allowed = ["https://jeux-mada.vercel.app", "https://lalaomada.vercel.app", "http://localhost:3000"];
  const allowOrigin = origin && allowed.includes(origin) ? origin : allowed[0];
  return {
    "Access-Control-Allow-Origin": allowOrigin,
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, Authorization",
    "Content-Type": "application/json",
  };
}

function json(data: any, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), { status, headers });
}

const DEPOSIT_SECRET = Deno.env.get("DEPOSIT_SMS_SECRET") || "";

serve(async (req: Request) => {
  const origin = req.headers.get("Origin");

  if (req.method === "OPTIONS") return new Response(null, { status: 200, headers: getCORSHeaders(origin) });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405, getCORSHeaders(origin));
  if (!DEPOSIT_SECRET) return json({ success: false, error: "SERVER_MISCONFIG", message: "Secret non configuré" }, 500, getCORSHeaders(origin));

  try {
    const body = await req.json();
    const { secret, operator, sms, timestamp, signature } = body as {
      secret?: string; operator?: string; sms?: string; timestamp?: string; signature?: string;
    };

    if (!secret || secret !== DEPOSIT_SECRET)
      return json({ success: false, error: "UNAUTHORIZED", message: "Secret invalide" }, 401, getCORSHeaders(origin));

    if (!timestamp || !signature)
      return json({ success: false, error: "MISSING_SIGNATURE", message: "Timestamp et signature HMAC obligatoires" }, 401, getCORSHeaders(origin));

    const payloadStr = JSON.stringify({ operator, sms });
    const valid = await verifyHMAC(DEPOSIT_SECRET, payloadStr, timestamp, signature);
    if (!valid)
      return json({ success: false, error: "INVALID_SIGNATURE", message: "Signature HMAC invalide ou expirée" }, 401, getCORSHeaders(origin));

    if (!operator || !sms)
      return json({ success: false, error: "MISSING_PARAMS", message: "operator et sms requis" }, 400, getCORSHeaders(origin));

    const parseResult = parseSMS(sms);
    if (!parseResult.success || !parseResult.data) {
      const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
      await supabase.from("deposit_transactions").insert({
        operator, transaction_id: `PARSE_ERROR_${Date.now()}`,
        sms_content: sms, status: "rejected",
        rejection_reason: parseResult.error || "Parse error",
      });
      return json({ success: false, error: "PARSE_ERROR", message: parseResult.error }, 422, getCORSHeaders(origin));
    }

    const parsed = parseResult.data;
    const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    const { data: result, error } = await supabase.rpc("validate_deposit_from_sms", {
      _operator: operator,
      _transaction_id: parsed.transaction_id,
      _sender_number: parsed.sender_number,
      _sender_name: null,
      _amount: parsed.amount,
      _sms_date: null,
      _sms_content: sms,
    });

    if (error) return json({ success: false, error: "DB_ERROR", message: error.message }, 500, getCORSHeaders(origin));
    return json(result, result?.success ? 200 : 422, getCORSHeaders(origin));
  } catch (err) {
    return json({ success: false, error: "INTERNAL_ERROR", message: String(err) }, 500, getCORSHeaders(origin));
  }
});
