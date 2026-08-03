// Supabase Edge Function: send-push
// Sends web push notifications with encrypted payload (RFC 8291).
// Uses fetch directly — no external imports.

// ── Base64 helpers ──────────────────────────────────────────────────────────

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

function base64Decode(str: string): Uint8Array {
  const bin = atob(str.replace(/-/g, "+").replace(/_/g, "/"));
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

// ── VAPID JWT ────────────────────────────────────────────────────────────────

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

// ── Web Push Encryption (RFC 8291 + RFC 8188) ───────────────────────────────

async function hmacSHA256(key: Uint8Array, data: Uint8Array): Promise<Uint8Array> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw", key,
    { name: "HMAC", hash: "SHA-256" },
    false, ["sign"],
  );
  return new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, data));
}

function concat(...arrays: Uint8Array[]): Uint8Array {
  const total = arrays.reduce((sum, a) => sum + a.length, 0);
  const result = new Uint8Array(total);
  let offset = 0;
  for (const a of arrays) {
    result.set(a, offset);
    offset += a.length;
  }
  return result;
}

/**
 * Encrypt the push payload using RFC 8291 (Web Push Encryption).
 * Returns the binary content in aes128gcm encoding (RFC 8188).
 */
async function encryptPayload(
  payload: string,
  p256dhB64: string,
  authB64: string,
): Promise<Uint8Array> {
  // 1. Decode subscriber keys
  const uaPublicKeyBytes = base64UrlDecode(p256dhB64);
  const authSecret = base64UrlDecode(authB64);

  // 2. Import subscriber's public key (P-256, uncompressed)
  const uaPublicKey = await crypto.subtle.importKey(
    "raw", uaPublicKeyBytes,
    { name: "ECDH", namedCurve: "P-256" },
    false, [],
  );

  // 3. Generate ephemeral server key pair
  const esKeyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true, ["deriveBits"],
  );

  // 4. Compute ECDH shared secret
  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "ECDH", public: uaPublicKey },
    esKeyPair.privateKey,
    256,
  ));

  // 5. Export ephemeral public key (65 bytes, uncompressed: 0x04 || X || Y)
  const esPublicKey = new Uint8Array(await crypto.subtle.exportKey(
    "raw", esKeyPair.publicKey,
  ));

  // 6. PRK_key = HMAC-SHA-256(auth_secret, ecdh_secret)
  const prkKey = await hmacSHA256(authSecret, ecdhSecret);

  // 7. Generate random salt (16 bytes)
  const salt = crypto.getRandomValues(new Uint8Array(16));

  // 8. PRK = HKDF-Extract(salt, PRK_key) = HMAC-SHA-256(salt, PRK_key)
  const prk = await hmacSHA256(salt, prkKey);

  // 9. key_info = "WebPush: info" || 0x00 || ua_public_key || es_public_key
  const keyInfo = concat(
    new TextEncoder().encode("WebPush: info"),
    new Uint8Array([0]),
    uaPublicKeyBytes,
    esPublicKey,
  );

  // 10. cek_info = "Content-Encoding: aes128gcm" || 0x00 || key_info
  const cekInfo = concat(
    new TextEncoder().encode("Content-Encoding: aes128gcm"),
    new Uint8Array([0]),
    keyInfo,
  );

  // 11. CEK = HKDF-Expand(PRK, cek_info, 16) = HMAC-SHA-256(PRK, cek_info || 0x01)[0:16]
  const cekFull = await hmacSHA256(prk, concat(cekInfo, new Uint8Array([1])));
  const cek = cekFull.slice(0, 16);

  // 12. nonce_info = "Content-Encoding: nonce" || 0x00 || key_info
  const nonceInfo = concat(
    new TextEncoder().encode("Content-Encoding: nonce"),
    new Uint8Array([0]),
    keyInfo,
  );

  // 13. nonce = HKDF-Expand(PRK, nonce_info, 12) = HMAC-SHA-256(PRK, nonce_info || 0x01)[0:12]
  const nonceFull = await hmacSHA256(prk, concat(nonceInfo, new Uint8Array([1])));
  const nonce = nonceFull.slice(0, 12);

  // 14. Import CEK for AES-GCM
  const cekKey = await crypto.subtle.importKey("raw", cek, { name: "AES-GCM" }, false, ["encrypt"]);

  // 15. Encrypt: payload + padding (0x02 = last record marker for single record)
  const payloadBytes = new TextEncoder().encode(payload);
  const plaintext = concat(payloadBytes, new Uint8Array([2]));

  const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, tagLength: 128 },
    cekKey,
    plaintext,
  ));

  // 16. Construct aes128gcm binary: salt(16) + rs(4) + idlen(1) + keyid(65) + ciphertext
  const rs = new Uint8Array([0, 0, 0x10, 0x00]); // 4096 big-endian
  const idlen = new Uint8Array([esPublicKey.length]); // 65

  return concat(salt, rs, idlen, esPublicKey, ciphertext);
}

// ── Main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const { user_id, title, body, link, notification_id } = await req.json();
    if (!user_id) {
      return new Response(JSON.stringify({ error: "user_id required" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      });
    }

    const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
    const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
    const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:contact@lalaomada.com";

    if (!vapidPrivateKey || !vapidPublicKey) {
      return new Response(JSON.stringify({ error: "VAPID keys not configured" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    // Query push_subscriptions including p256dh and auth for encryption
    const resp = await fetch(
      `${supabaseUrl}/rest/v1/push_subscriptions?user_id=eq.${encodeURIComponent(user_id)}&select=id,endpoint,p256dh,auth`,
      {
        headers: {
          "apikey": serviceKey,
          "Authorization": `Bearer ${serviceKey}`,
        },
      },
    );
    const subs = await resp.json();

    if (!subs || subs.length === 0) {
      return new Response(JSON.stringify({ sent: 0, message: "No subscriptions" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    // Build the JSON payload to send.
    // `tag` is UNIQUE per notification (based on notification_id) so that
    // Android/Chrome NEVER replace a previous notification with a new one —
    // instead, several notifications from the app stack/group together in
    // the notification shade (title = sender, body = message), the same
    // way native chat apps show multiple messages at once.
    const pushPayload = JSON.stringify({
      title: title || "Lalao MADA",
      body: body || "Nouvelle notification",
      url: link || "/",
      tag: notification_id ? `notif-${notification_id}` : `notif-${Date.now()}`,
    });

    const vapidKey = await importVapidKey(vapidPrivateKey);
    let sent = 0;
    let failed = 0;
    const failedIds: string[] = [];

    for (const sub of subs) {
      try {
        const url = new URL(sub.endpoint);
        const aud = `${url.protocol}//${url.host}`;
        const jwt = await createVapidJwt(aud, vapidSubject, vapidKey);

        let pushResp: Response;

        // If we have p256dh and auth, send encrypted payload
        if (sub.p256dh && sub.auth) {
          const encrypted = await encryptPayload(pushPayload, sub.p256dh, sub.auth);
          pushResp = await fetch(sub.endpoint, {
            method: "POST",
            headers: {
              "TTL": "86400",
              "Content-Encoding": "aes128gcm",
              "Content-Type": "application/octet-stream",
              "Authorization": `vapid t=${jwt}, k=${vapidPublicKey}`,
            },
            body: encrypted,
          });
        } else {
          // Fallback: send a ping (no payload)
          pushResp = await fetch(sub.endpoint, {
            method: "POST",
            headers: {
              "TTL": "86400",
              "Content-Length": "0",
              "Authorization": `vapid t=${jwt}, k=${vapidPublicKey}`,
            },
          });
        }

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

    return new Response(JSON.stringify({ sent, failed, total: subs.length }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
