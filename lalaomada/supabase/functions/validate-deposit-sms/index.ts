// ═══════════════════════════════════════════════════════════════════════
// validate-deposit-sms — Edge Function v6 (simplifiée)
//
// POST /functions/v1/validate-deposit-sms
// Body: { "secret": "xxx", "operator": "orange|mvola|airtel", "sms": "...",
//         "timestamp": "1234567890", "signature": "hmac_hex" }
//
// Détection simple par opérateur — 3 champs uniquement:
//   1. Montant
//   2. Numéro de téléphone (expéditeur)
//   3. ID/Ref de transaction
//
// Formats confirmés:
//   Orange:  "Vous avez recu un transfert de 25650Ar venant du 0322159515... Trans Id: PP260519.1245.C46612."
//   MVola:   "2 000 Ar recu de LovatianaEmmanuelRolland 0348968907... Ref 4876739165"
//   Airtel:  "Ar 2000 azo tamin'ny agent 331576366. Toebolanao Ar 2094. Trans ID: CI260811.1140.E34298"
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
// ORANGE MONEY — 3 regex
//   Montant:  "transfert de 25650Ar"  →  25650
//   Numéro:   "venant du 0322159515"  →  0322159515
//   ID:       "Trans Id: PP260519.1245.C46612."  →  PP260519.1245.C46612
// ═══════════════════════════════════════════════════════════════════════

class OrangeParser {
  parse(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, transaction_id: null };

    // 1. MONTANT — après "transfert de" ou "recu ... de" + chiffres + "Ar"
    const amt = sms.match(/(?:transfert|recu|re[uç]u)\s+de\s+([\d\s]+)\s*Ar/i)
             || sms.match(/([\d\s]+)\s*Ar\s+recu\s+de/i);
    if (amt) result.amount = parseInt(amt[1].replace(/\s/g, ""), 10);

    // 2. NUMÉRO — après "venant du" ou après "recu de ... "
    const num = sms.match(/venant\s+du\s+(\d[\d\s]+)/i)
             || sms.match(/recu\s+de\s+[\w\s]+?\s+(\d{9,10})/i);
    if (num) result.sender_number = num[1].replace(/\s/g, "").trim();

    // 3. ID — "Trans Id: PP..." ou "Ref 12345"
    const id = sms.match(/Trans\s*Id\s*:?\s*([A-Z0-9.]+)/i)
           || sms.match(/Ref\s+(\d+)/i);
    if (id) result.transaction_id = id[1].trim().replace(/\.$/, "");

    if (!result.amount || isNaN(result.amount)) return { success: false, error: "Montant manquant (Orange)" };
    if (!result.transaction_id) return { success: false, error: "Trans ID manquant (Orange)" };
    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MVOLA — 3 regex
//   Montant:  "2 000 Ar recu de"  →  2000  (AVANT "recu de", pas le Solde)
//   Numéro:   "0348968907" après le nom  →  0348968907
//   Ref:      "Ref 4876739165"  →  4876739165
// ═══════════════════════════════════════════════════════════════════════

class MVolaParser {
  parse(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, transaction_id: null };

    // 1. MONTANT — AVANT "Ar recu de" (jamais le "Solde" qui vient après)
    const amt = sms.match(/([\d\s]+)\s*Ar\s+recu\s+de/i)
             || sms.match(/(?:recu|recus|re[uç]u)\s+([\d\s]+)\s*Ar/i);
    if (amt) result.amount = parseInt(amt[1].replace(/\s/g, ""), 10);

    // 2. NUMÉRO — 9-10 chiffres après le nom (avant "le" date)
    const num = sms.match(/recu\s+de\s+\D+?(\d{9,10})/i)
             || sms.match(/de\s+.*?(\d{9,10})/i);
    if (num) result.sender_number = num[1];

    // 3. REF — "Ref 4876739165"
    const ref = sms.match(/Ref\s+(\d+)/i)
             || sms.match(/(?:ref|reference)[:\s]+([A-Z0-9]+)/i);
    if (ref) result.transaction_id = ref[1];

    if (!result.amount || isNaN(result.amount)) return { success: false, error: "Montant manquant (MVola)" };
    if (!result.transaction_id) return { success: false, error: "Ref manquante (MVola)" };
    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// AIRTEL MONEY — 3 regex (SMS en malgache)
//   Montant:  "Ar 2000 azo"  →  2000
//   Numéro:   "agent 331576366"  →  331576366
//   ID:       "Trans ID: CI260811.1140.E34298"  →  CI260811.1140.E34298
// ═══════════════════════════════════════════════════════════════════════

class AirtelParser {
  parse(sms: string): ParseResult {
    const result: ParsedSMS = { amount: null, sender_number: null, transaction_id: null };

    // 1. MONTANT — "Ar 2000 azo"
    const amt = sms.match(/Ar\s+([\d\s]+)\s+azo/i);
    if (amt) result.amount = parseInt(amt[1].replace(/\s/g, ""), 10);

    // 2. NUMÉRO — "agent 331576366"
    const num = sms.match(/agent\s+(\d+)/i);
    if (num) result.sender_number = num[1];

    // 3. ID — "Trans ID: CI260811.1140.E34298"
    const id = sms.match(/Trans\s*Id\s*:?\s*([A-Z0-9.]+)/i);
    if (id) result.transaction_id = id[1].trim().replace(/\.$/, "");

    if (!result.amount || isNaN(result.amount)) return { success: false, error: "Montant manquant (Airtel)" };
    if (!result.transaction_id) return { success: false, error: "Trans ID manquant (Airtel)" };
    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PARSER FACTORY
// ═══════════════════════════════════════════════════════════════════════

class ParserFactory {
  static getParser(operator: string): OrangeParser | MVolaParser | AirtelParser | null {
    switch (operator.toLowerCase().trim()) {
      case "orange": return new OrangeParser();
      case "mvola": case "m-vola": return new MVolaParser();
      case "airtel": return new AirtelParser();
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
// CORS
// ═══════════════════════════════════════════════════════════════════════

function getCORSHeaders(origin: string | null): Record<string, string> {
  const allowed = [
    "https://jeux-mada.vercel.app",
    "https://lalaomada.vercel.app",
    "http://localhost:3000",
  ];
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

// ═══════════════════════════════════════════════════════════════════════
// MAIN HANDLER
// ═══════════════════════════════════════════════════════════════════════

const DEPOSIT_SECRET = Deno.env.get("DEPOSIT_SMS_SECRET") || "";

serve(async (req: Request) => {
  const origin = req.headers.get("Origin");

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: getCORSHeaders(origin) });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405, getCORSHeaders(origin));
  }

  if (!DEPOSIT_SECRET) {
    return json({ success: false, error: "SERVER_MISCONFIG", message: "Secret non configuré" }, 500, getCORSHeaders(origin));
  }

  try {
    const body = await req.json();
    const { secret, operator, sms, timestamp, signature } = body as {
      secret?: string; operator?: string; sms?: string;
      timestamp?: string; signature?: string;
    };

    // 1. Vérifier le secret
    if (!secret || secret !== DEPOSIT_SECRET) {
      return json({ success: false, error: "UNAUTHORIZED", message: "Secret invalide" }, 401, getCORSHeaders(origin));
    }

    // 2. Vérifier la signature HMAC
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

    // 3. Parser le SMS
    const parser = ParserFactory.getParser(operator);
    if (!parser) {
      return json({ success: false, error: "UNKNOWN_OPERATOR", message: `Opérateur inconnu: ${operator}` }, 400, getCORSHeaders(origin));
    }

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

    // 4. Valider via la fonction PostgreSQL
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: result, error } = await supabase.rpc("validate_deposit_from_sms", {
      _operator: operator,
      _transaction_id: parsed.transaction_id,
      _sender_number: parsed.sender_number,
      _sender_name: null,
      _amount: parsed.amount,
      _sms_date: null,
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
