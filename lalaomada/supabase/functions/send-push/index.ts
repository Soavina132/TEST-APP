// Supabase Edge Function: send-push
// Sends web push notifications (no payload, SW fetches data).
// Uses fetch directly — no external imports.

function base64UrlEncode(buf: ArrayBuffer | Uint8Array): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlDecode(str: string): Uint8Array {
  const padded = str.replace(/-/g, "+").replace(/_/g, "/");
  const pad = "=".repeat((4 - (padded.length % 4)) % 4);
  const bin = atob(padded + pad);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

async function importVapidKey(privateKeyB64: string): Promise<CryptoKey> {
  const keyBytes = base64UrlDecode(privateKeyB64);
  return crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
}

async function createVapidJwt(aud: string, subject: string, key: CryptoKey): Promise<string> {
  const header = { typ: "JWT", alg: "ES256" };
  const payload = { aud, exp: Math.floor(Date.now() / 1000) + 12 * 3600, sub: subject };
  const enc = (o: object) => base64UrlEncode(new TextEncoder().encode(JSON.stringify(o)));
  const signingInput = `${enc(header)}.${enc(payload)}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64UrlEncode(sig)}`;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { "Content-Type": "application/json" } });
  }

  try {
    const { user_id, title, body, link } = await req.json();
    if (!user_id) {
      return new Response(JSON.stringify({ error: "user_id required" }), { status: 400, headers: { "Content-Type": "application/json" } });
    }

    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:contact@lalaomada.com";

    if (!vapidPrivateKey || !vapidPublicKey) {
      return new Response(JSON.stringify({ error: "VAPID keys not configured" }), { status: 500, headers: { "Content-Type": "application/json" } });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Query push_subscriptions via REST API
    const resp = await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?user_id=eq.${encodeURIComponent(user_id)}&select=id,endpoint`, {
      headers: {
        "apikey": serviceKey,
        "Authorization": `Bearer ${serviceKey}`,
      },
    });
    const subs = await resp.json();

    if (!subs || subs.length === 0) {
      return new Response(JSON.stringify({ sent: 0, message: "No subscriptions" }), { status: 200, headers: { "Content-Type": "application/json" } });
    }

    const vapidKey = await importVapidKey(vapidPrivateKey);
    let sent = 0;
    let failed = 0;
    const failedIds: string[] = [];

    for (const sub of subs) {
      try {
        const url = new URL(sub.endpoint);
        const aud = `${url.protocol}//${url.host}`;
        const jwt = await createVapidJwt(aud, vapidSubject, vapidKey);

        const pushResp = await fetch(sub.endpoint, {
          method: "POST",
          headers: {
            "TTL": "86400",
            "Content-Length": "0",
            "Authorization": `vapid t=${jwt}, k=${vapidPublicKey}`,
          },
        });

        if (pushResp.ok || pushResp.status === 201) {
          sent++;
        } else if (pushResp.status === 404 || pushResp.status === 410) {
          failedIds.push(sub.id);
          failed++;
        } else {
          failed++;
        }
      } catch {
        failed++;
      }
    }

    // Clean up expired subscriptions via REST API
    if (failedIds.length > 0) {
      const ids = failedIds.map((id) => `"${id}"`).join(",");
      await fetch(`${supabaseUrl}/rest/v1/push_subscriptions?id=in.(${ids})`, {
        method: "DELETE",
        headers: {
          "apikey": serviceKey,
          "Authorization": `Bearer ${serviceKey}`,
        },
      });
    }

    return new Response(JSON.stringify({ sent, failed, total: subs.length }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
});
