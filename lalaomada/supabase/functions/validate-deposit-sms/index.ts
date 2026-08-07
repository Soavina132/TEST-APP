const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(data: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: CORS });
}

function parseAmount(sms: string): number {
  const m = sms.match(/(\d[\d\s,]*\d)\s*(?:Ar|Ariary|ar)/i);
  return m ? parseInt(m[1].replace(/[\s,]/g, "")) : 0;
}

function parsePhone(sms: string): string {
  const m = sms.match(/(?:de|from)\s+(\+?\d[\d\s]{6,})/i);
  return m ? m[1].replace(/[\s+]/g, "") : "";
}

function parseTransId(sms: string): string {
  const m = sms.match(/(?:trans\s*id|transaction\s*id|reference|ref)[:\s]*([A-Za-z0-9]+)/i);
  return m ? m[1] : "";
}

function phoneMatches(a: string, b: string): boolean {
  const ca = a.replace(/[\s+\-()]/g, "");
  const cb = b.replace(/[\s+\-()]/g, "");
  if (ca.length >= 8 && cb.length >= 8) return ca.slice(-8) === cb.slice(-8);
  return ca === cb;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  if (req.method !== "POST") return json({ success: false, error: "METHOD_NOT_ALLOWED" }, 405);

  try {
    const { secret, operator, sms } = await req.json();
    const expectedSecret = Deno.env.get("DEPOSIT_API_SECRET") || "LalaoMada2026SecretKey!";
    if (secret !== expectedSecret) return json({ success: false, error: "INVALID_SECRET", message: "Secret invalide" }, 403);
    if (!sms || typeof sms !== "string") return json({ success: false, error: "MISSING_SMS", message: "SMS manquant" }, 400);

    const amount = parseAmount(sms);
    const senderPhone = parsePhone(sms);
    const transId = parseTransId(sms);

    if (!amount || amount < 100) {
      return json({ success: false, error: "PARSE_ERROR", message: "Montant non reconnu dans le SMS" });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const headers = { "apikey": serviceKey, "Authorization": `Bearer ${serviceKey}`, "Content-Type": "application/json" };

    // ── Step 1: Try to match a PENDING deposit ──
    let depositRecord: any = null;

    const depResp = await fetch(`${supabaseUrl}/rest/v1/deposits?select=id,user_id,amount,method,reference,user_phone,status&status=eq.pending&method=eq.${operator}&order=created_at.asc&limit=20`, { headers });
    const pendingDeposits = await depResp.json();

    if (Array.isArray(pendingDeposits) && pendingDeposits.length > 0) {
      for (const d of pendingDeposits) {
        if (d.amount === amount && senderPhone && d.user_phone && phoneMatches(senderPhone, d.user_phone)) {
          depositRecord = d; break;
        }
      }
      if (!depositRecord) {
        for (const d of pendingDeposits) {
          if (d.amount === amount) { depositRecord = d; break; }
        }
      }
    }

    // ── Step 2: Auto-create from sender phone ──
    if (!depositRecord && senderPhone) {
      const usersResp = await fetch(`${supabaseUrl}/rest/v1/profiles?select=id,pseudo,phone,phone_verified&phone=not.is.null&limit=1000`, { headers });
      const users = await usersResp.json();

      if (Array.isArray(users)) {
        const matchedUser = users.find((u: any) => u.phone && phoneMatches(senderPhone, u.phone));
        if (matchedUser) {
          const createResp = await fetch(`${supabaseUrl}/rest/v1/deposits`, {
            method: "POST",
            headers: { ...headers, "Prefer": "return=representation" },
            body: JSON.stringify({
              user_id: matchedUser.id, amount, method: operator,
              reference: transId || `AUTO-${Date.now()}`,
              user_phone: matchedUser.phone, status: "pending",
            }),
          });
          const newDep = await createResp.json();
          if (Array.isArray(newDep) && newDep[0]) {
            depositRecord = { ...newDep[0], user_pseudo: matchedUser.pseudo };
          }
        }
      }
    }

    if (!depositRecord) {
      return json({
        success: false,
        error: "NO_PENDING_DEPOSIT",
        message: `Aucun utilisateur trouvé pour ${amount} Ar${senderPhone ? ` de ${senderPhone}` : ""}`,
        parsed_amount: amount, parsed_phone: senderPhone, parsed_transid: transId,
      });
    }

    // ── Step 3: Validate ──
    const userId = depositRecord.user_id;
    let userPseudo = depositRecord.user_pseudo || "?";

    // Get pseudo if needed
    if (userPseudo === "?") {
      const profResp = await fetch(`${supabaseUrl}/rest/v1/profiles?select=pseudo,balance_ar,first_deposit_at&id=eq.${userId}&limit=1`, { headers });
      const profData = await profResp.json();
      if (Array.isArray(profData) && profData[0]) {
        userPseudo = profData[0].pseudo || "?";
        const profile = profData[0];
        const newBalance = Number(profile.balance_ar || 0) + amount;
        const updates: Record<string, unknown> = { balance_ar: newBalance };
        if (!profile.first_deposit_at) {
          updates.first_deposit_at = new Date().toISOString();
          updates.first_deposit_amount = amount;
        }
        await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${userId}`, {
          method: "PATCH",
          headers: { ...headers, "Prefer": "return=minimal" },
          body: JSON.stringify(updates),
        });
        await fetch(`${supabaseUrl}/rest/v1/transactions`, {
          method: "POST",
          headers: { ...headers, "Prefer": "return=minimal" },
          body: JSON.stringify({
            user_id: userId, type: "deposit", amount,
            note: `Dépôt ${operator.toUpperCase()} — ${transId || "auto"}`,
          }),
        });
      }
    } else {
      // We have pseudo but still need to credit
      const profResp = await fetch(`${supabaseUrl}/rest/v1/profiles?select=balance_ar,first_deposit_at&id=eq.${userId}&limit=1`, { headers });
      const profData = await profResp.json();
      if (Array.isArray(profData) && profData[0]) {
        const profile = profData[0];
        const newBalance = Number(profile.balance_ar || 0) + amount;
        const updates: Record<string, unknown> = { balance_ar: newBalance };
        if (!profile.first_deposit_at) {
          updates.first_deposit_at = new Date().toISOString();
          updates.first_deposit_amount = amount;
        }
        await fetch(`${supabaseUrl}/rest/v1/profiles?id=eq.${userId}`, {
          method: "PATCH",
          headers: { ...headers, "Prefer": "return=minimal" },
          body: JSON.stringify(updates),
        });
        await fetch(`${supabaseUrl}/rest/v1/transactions`, {
          method: "POST",
          headers: { ...headers, "Prefer": "return=minimal" },
          body: JSON.stringify({
            user_id: userId, type: "deposit", amount,
            note: `Dépôt ${operator.toUpperCase()} — ${transId || "auto"}`,
          }),
        });
      }
    }

    // Update deposit status
    await fetch(`${supabaseUrl}/rest/v1/deposits?id=eq.${depositRecord.id}`, {
      method: "PATCH",
      headers: { ...headers, "Prefer": "return=minimal" },
      body: JSON.stringify({
        status: "validated",
        validated_at: new Date().toISOString(),
        reference: transId || depositRecord.reference,
      }),
    });

    return json({
      success: true,
      user_pseudo: userPseudo,
      amount, transaction_id: transId || depositRecord.reference, operator,
    });

  } catch (err) {
    return json({ success: false, error: "SERVER_ERROR", message: String(err) }, 500);
  }
});
