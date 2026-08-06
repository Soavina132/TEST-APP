// ═══════════════════════════════════════════════════════════════════════
// validate-deposit-sms — Edge Function Supabase
//
// POST /functions/v1/validate-deposit-sms
// Body: { "secret": "xxx", "operator": "orange|mvola", "sms": "..." }
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
// ORANGE PARSER — reconnaît plusieurs formats
// ═══════════════════════════════════════════════════════════════════════

class OrangeParser {
  parse(sms: string): ParseResult {
    // ── Format 1 ────────────────────────────────────────────────────
    // "Vous avez reçu un transfert de XXXXXAr venant du 03XXXXXXXX
    //  Nouveau Solde: XXXXXAr.
    //  Trans Id: PP260519.1245.C46612.
    //  Orange Money vous remercie."
    if (/vous avez reçu/i.test(sms) || /transfert/i.test(sms)) {
      return this.parseFormat1(sms);
    }

    // ── Format 2 ────────────────────────────────────────────────────
    // "2 000 Ar recu de LovatianaEmmanuelRolland 0348968907
    //  le 04/08/26 a 16:45.
    //  Raison: ludo.
    //  Solde: 20 559 Ar.
    //  Ref 4876739165"
    if (/recu de/i.test(sms) || /Ref\s+\d/i.test(sms)) {
      return this.parseFormat2(sms);
    }

    return { success: false, error: "Format Orange Money non reconnu" };
  }

  private parseFormat1(sms: string): ParseResult {
    const result: ParsedSMS = {
      amount: null,
      sender_number: null,
      sender_name: null,
      transaction_id: null,
      sms_date: null,
    };

    // Amount: "transfert de XXXXXAr" ou "transfert de X XXXAr"
    const amountMatch = sms.match(/(?:transfert|recu|reçu)\s+de\s+([\d\s]+)\s*Ar/i);
    if (amountMatch) {
      result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    }

    // Sender number: "venant du 03XXXXXXXX"
    const senderMatch = sms.match(/venant\s+du\s+(\d[\d\s]+)/i);
    if (senderMatch) {
      result.sender_number = senderMatch[1].trim();
    }

    // Trans Id: "Trans Id: PP260519.1245.C46612"
    const transIdMatch = sms.match(/Trans\s*Id\s*:?\s*([A-Z0-9.]+)/i);
    if (transIdMatch) {
      result.transaction_id = transIdMatch[1].trim();
    }

    // Validate
    if (!result.transaction_id) {
      return { success: false, error: "Trans Id manquant (Format 1)" };
    }
    if (result.amount === null || isNaN(result.amount)) {
      return { success: false, error: "Montant manquant (Format 1)" };
    }

    return { success: true, data: result };
  }

  private parseFormat2(sms: string): ParseResult {
    const result: ParsedSMS = {
      amount: null,
      sender_number: null,
      sender_name: null,
      transaction_id: null,
      sms_date: null,
    };

    // Amount: "2 000 Ar recu de"
    const amountMatch = sms.match(/([\d\s]+)\s*Ar\s+recu\s+de/i);
    if (amountMatch) {
      result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    }

    // Sender name + number: "recu de LovatianaEmmanuelRolland 0348968907"
    const senderMatch = sms.match(/recu\s+de\s+(.+?)\s+(\d{10,})/i);
    if (senderMatch) {
      result.sender_name = senderMatch[1].trim();
      result.sender_number = senderMatch[2];
    }

    // Date: "le 04/08/26 a 16:45"
    const dateMatch = sms.match(/le\s+(\d{2}\/\d{2}\/\d{2,4})\s+[àa]\s+(\d{2}:\d{2})/i);
    if (dateMatch) {
      result.sms_date = `${dateMatch[1]} ${dateMatch[2]}`;
    }

    // Reference: "Ref 4876739165"
    const refMatch = sms.match(/Ref\s+(\d+)/i);
    if (refMatch) {
      result.transaction_id = refMatch[1];
    }

    // Validate
    if (!result.transaction_id) {
      return { success: false, error: "Ref manquante (Format 2)" };
    }
    if (result.amount === null || isNaN(result.amount)) {
      return { success: false, error: "Montant manquant (Format 2)" };
    }

    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// MVOLA PARSER — architecture extensible
// ═══════════════════════════════════════════════════════════════════════

class MVolaParser {
  parse(sms: string): ParseResult {
    // Format MVola 1: "Vous avez recu X Ar de XXXX (03XXXXXXXX). Ref: XXXXX"
    if (/recu/i.test(sms) || /ref/i.test(sms)) {
      return this.parseFormat1(sms);
    }

    // Format MVola 2: "Transaction reussie. Montant: X Ar. De: XXXX. Ref: XXXX"
    if (/transaction/i.test(sms) || /montant/i.test(sms)) {
      return this.parseFormat2(sms);
    }

    return { success: false, error: "Format MVola non reconnu" };
  }

  private parseFormat1(sms: string): ParseResult {
    const result: ParsedSMS = {
      amount: null,
      sender_number: null,
      sender_name: null,
      transaction_id: null,
      sms_date: null,
    };

    // Amount
    const amountMatch = sms.match(/(?:recu|recus|reçu)\s+([\d\s]+)\s*Ar/i);
    if (amountMatch) {
      result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    }

    // Sender
    const senderMatch = sms.match(/de\s+(.+?)\s*\(?(\d{10,})?/i);
    if (senderMatch) {
      result.sender_name = senderMatch[1].trim();
      if (senderMatch[2]) result.sender_number = senderMatch[2];
    }

    // Reference
    const refMatch = sms.match(/(?:ref|reference)[:\s]+([A-Z0-9]+)/i);
    if (refMatch) {
      result.transaction_id = refMatch[1];
    }

    if (!result.transaction_id) {
      return { success: false, error: "Ref MVola manquante (Format 1)" };
    }

    return { success: true, data: result };
  }

  private parseFormat2(sms: string): ParseResult {
    const result: ParsedSMS = {
      amount: null,
      sender_number: null,
      sender_name: null,
      transaction_id: null,
      sms_date: null,
    };

    const amountMatch = sms.match(/montant\s*:?\s*([\d\s]+)\s*Ar/i);
    if (amountMatch) {
      result.amount = parseInt(amountMatch[1].replace(/\s/g, ""), 10);
    }

    const senderMatch = sms.match(/de\s*:?\s*(.+?)(?:\s+\(?(\d{10,})|$)/i);
    if (senderMatch) {
      result.sender_name = senderMatch[1].trim();
      if (senderMatch[2]) result.sender_number = senderMatch[2];
    }

    const refMatch = sms.match(/(?:ref|reference)[:\s]+([A-Z0-9]+)/i);
    if (refMatch) {
      result.transaction_id = refMatch[1];
    }

    if (!result.transaction_id) {
      return { success: false, error: "Ref MVola manquante (Format 2)" };
    }

    return { success: true, data: result };
  }
}

// ═══════════════════════════════════════════════════════════════════════
// PARSER FACTORY
// ═══════════════════════════════════════════════════════════════════════

class ParserFactory {
  static getParser(operator: string): OrangeParser | MVolaParser | null {
    switch (operator.toLowerCase().trim()) {
      case "orange":
        return new OrangeParser();
      case "mvola":
      case "m-vola":
        return new MVolaParser();
      default:
        return null;
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HANDLER
// ═══════════════════════════════════════════════════════════════════════

const DEPOSIT_SECRET = Deno.env.get("DEPOSIT_SMS_SECRET") ?? "LalaoMada2026SecretKey!";

serve(async (req: Request) => {
  // CORS
  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 200,
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST",
        "Access-Control-Allow-Headers": "Content-Type, Authorization",
      },
    });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json();
    const { secret, operator, sms } = body as {
      secret?: string;
      operator?: string;
      sms?: string;
    };

    // 1. Vérifier le secret
    if (!secret || secret !== DEPOSIT_SECRET) {
      return json({ success: false, error: "UNAUTHORIZED", message: "Secret invalide" }, 401);
    }

    if (!operator || !sms) {
      return json({ success: false, error: "MISSING_PARAMS", message: "operator et sms requis" }, 400);
    }

    // 2. Obtenir le parser
    const parser = ParserFactory.getParser(operator);
    if (!parser) {
      return json({ success: false, error: "UNKNOWN_OPERATOR", message: `Opérateur inconnu: ${operator}` }, 400);
    }

    // 3. Parser le SMS
    const parseResult = parser.parse(sms);
    if (!parseResult.success || !parseResult.data) {
      // Logger l'échec de parsing
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
      return json({ success: false, error: "PARSE_ERROR", message: parseResult.error }, 422);
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
      return json({ success: false, error: "DB_ERROR", message: error.message }, 500);
    }

    // 5. Retourner le résultat
    return json(result, result?.success ? 200 : 422);
  } catch (err) {
    return json({ success: false, error: "INTERNAL_ERROR", message: String(err) }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
    },
  });
}
