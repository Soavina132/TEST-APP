// Supabase Edge Function: send-push
// Sends BOTH web push (VAPID) AND native FCM (Firebase Cloud Messaging) notifications.
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
  const uaPublicKeyBytes = base64UrlDecode(p256dhB64);
  const authSecret = base64UrlDecode(authB64);

  const uaPublicKey = await crypto.subtle.importKey(
    "raw", uaPublicKeyBytes,
    { name: "ECDH", namedCurve: "P-256" },
    false, [],
  );

  const esKeyPair = await crypto.subtle.generateKey(
    { name: "ECDH", namedCurve: "P-256" },
    true, ["deriveBits"],
  );

  const ecdhSecret = new Uint8Array(await crypto.subtle.deriveBits(
    { name: "ECDH", public: uaPublicKey },
    esKeyPair.privateKey,
    256,
  ));

  const esPublicKey = new Uint8Array(await crypto.subtle.exportKey(
    "raw", esKeyPair.publicKey,
  ));

  const prkKey = await hmacSHA256(authSecret, ecdhSecret);

  const salt = crypto.getRandomValues(new Uint8Array(16));

  const prk = await hmacSHA256(salt, prkKey);

  const keyInfo = concat(
    new TextEncoder().encode("WebPush: info"),
    new Uint8Array([0]),
    uaPublicKeyBytes,
    esPublicKey,
  );

  const cekInfo = concat(
    new TextEncoder().encode("Content-Encoding: aes128gcm"),
    new Uint8Array([0]),
    keyInfo,
  );

  const cekFull = await hmacSHA256(prk, concat(cekInfo, new Uint8Array([1])));
  const cek = cekFull.slice(0, 16);

  const nonceInfo = concat(
    new TextEncoder().encode("Content-Encoding: nonce"),
    new Uint8Array([0]),
    keyInfo,
  );

  const nonceFull = await hmacSHA256(prk, concat(nonceInfo, new Uint8Array([1])));
  const nonce = nonceFull.slice(0, 12);

  const cekKey = await crypto.subtle.importKey("raw", cek, { name: "AES-GCM" }, false, ["encrypt"]);

  const payloadBytes = new TextEncoder().encode(payload);
  const plaintext = concat(payloadBytes, new Uint8Array([2]));

  const ciphertext = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: nonce, tagLength: 128 },
    cekKey,
    plaintext,
  ));

  const rs = new Uint8Array([0, 0, 0x10, 0x00]);
  const idlen = new Uint8Array([esPublicKey.length]);

  return concat(salt, rs, idlen, esPublicKey, ciphertext);
}

// ═══════════════════════════════════════════════════════════════════════════
// FCM (Firebase Cloud Messaging) — native Android push notifications
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Get an OAuth2 access token for Firebase Cloud Messaging using
 * the service account credentials (JWT bearer flow).
 */
async function getFcmAccessToken(clientEmail: string, privateKeyPem: string, projectId: string): Promise<string> {
  // Clean the private key — Supabase secrets may escape newlines
  const cleanKey = privateKeyPem.replace(/\\n/g, "\n");

  // Import the RSA private key
  const keyContents = cleanKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const keyBytes = base64Decode(keyContents);

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  // Create JWT
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: clientEmail,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const enc = (o: object) => base64UrlEncode(new TextEncoder().encode(JSON.stringify(o)));
  const signingInput = `${enc(header)}.${enc(payload)}`;
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(signingInput),
  );
  const jwt = `${signingInput}.${base64UrlEncode(sig)}`;

  // Exchange JWT for access token
  const tokenResp = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenResp.ok) {
    const errText = await tokenResp.text();
    throw new Error(`FCM OAuth2 failed: ${tokenResp.status} ${errText}`);
  }

  const tokenData = await tokenResp.json();
  return tokenData.access_token;
}

/**
 * Send an FCM message to a device token.
 */
async function sendFcmMessage(
  accessToken: string,
  projectId: string,
  token: string,
  title: string,
  body: string,
  link: string,
): Promise<{ ok: boolean; invalid: boolean }> {
  const fcmUrl = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`;

  const message = {
    message: {
      token,
      notification: {
        title: title || "Lalao MADA",
        body: body || "",
      },
      data: {
        link: link || "/",
        title: title || "Lalao MADA",
        body: body || "",
      },
      android: {
        priority: "high",
        notification: {
          channel_id: "lalaomada_notifications",
          icon: "ic_launcher",
          color: "#f97316",
        },
      },
    },
  };

  const resp = await fetch(fcmUrl, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(message),
  });

  if (resp.ok) return { ok: true, invalid: false };

  const errText = await resp.text();
  // 404 = UNREGISTERED, 410 = invalid token
  if (resp.status === 404 || resp.status === 410 || errText.includes("UNREGISTERED")) {
    return { ok: false, invalid: true };
  }

  console.warn(`[FCM] Send failed for token ${token.substring(0, 20)}...: ${resp.status} ${errText}`);
  return { ok: false, invalid: false };
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

    // ── WEB PUSH (VAPID) ────────────────────────────────────────────────────
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

    const pushPayload = JSON.stringify({
      title: title || "Lalao MADA",
      body: body || "Nouvelle notification",
      url: link || "/",
      tag: notification_id ? `notif-${notification_id}` : `notif-${Date.now()}`,
    });

    const vapidKey = await importVapidKey(vapidPrivateKey);
    let webSent = 0;
    let webFailed = 0;
    const failedIds: string[] = [];

    if (subs && subs.length > 0) {
      for (const sub of subs) {
        try {
          const url = new URL(sub.endpoint);
          const aud = `${url.protocol}//${url.host}`;
          const jwt = await createVapidJwt(aud, vapidSubject, vapidKey);

          let pushResp: Response;

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
            webSent++;
          } else if (pushResp.status === 404 || pushResp.status === 410) {
            failedIds.push(sub.id);
            webFailed++;
          } else {
            webFailed++;
          }
        } catch {
          webFailed++;
        }
      }

      // Clean up expired web push subscriptions
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
    }

    // ── FCM (Firebase Cloud Messaging) — native push ────────────────────────
    let fcmSent = 0;
    let fcmFailed = 0;
    const failedTokenIds: string[] = [];

    const fcmProjectId = Deno.env.get("FCM_PROJECT_ID");
    const fcmClientEmail = Deno.env.get("FCM_CLIENT_EMAIL");
    const fcmPrivateKey = Deno.env.get("FCM_PRIVATE_KEY");

    if (fcmProjectId && fcmClientEmail && fcmPrivateKey) {
      try {
        // Query push_tokens for this user's FCM device tokens
        const tokensResp = await fetch(
          `${supabaseUrl}/rest/v1/push_tokens?user_id=eq.${encodeURIComponent(user_id)}&select=id,token`,
          {
            headers: {
              "apikey": serviceKey,
              "Authorization": `Bearer ${serviceKey}`,
            },
          },
        );
        const tokens = await tokensResp.json();

        if (tokens && tokens.length > 0) {
          const accessToken = await getFcmAccessToken(fcmClientEmail, fcmPrivateKey, fcmProjectId);
          const notifTitle = title || "Lalao MADA";
          const notifBody = body || "Nouvelle notification";
          const notifLink = link || "/";

          for (const { id, token } of tokens) {
            try {
              const result = await sendFcmMessage(accessToken, fcmProjectId, token, notifTitle, notifBody, notifLink);
              if (result.ok) {
                fcmSent++;
              } else if (result.invalid) {
                failedTokenIds.push(id);
                fcmFailed++;
              } else {
                fcmFailed++;
              }
            } catch {
              fcmFailed++;
            }
          }

          // Clean up invalid FCM tokens
          if (failedTokenIds.length > 0) {
            const ids = failedTokenIds.map((id) => `"${id}"`).join(",");
            await fetch(`${supabaseUrl}/rest/v1/push_tokens?id=in.(${ids})`, {
              method: "DELETE",
              headers: {
                "apikey": serviceKey,
                "Authorization": `Bearer ${serviceKey}`,
              },
            });
          }
        }
      } catch (fcmErr) {
        console.warn("[FCM] Error:", fcmErr);
      }
    } else {
      // FCM not configured — skip silently (web push still works)
      console.log("[FCM] Not configured — skipping native push");
    }

    return new Response(JSON.stringify({
      web_push_sent: webSent,
      web_push_failed: webFailed,
      fcm_sent: fcmSent,
      fcm_failed: fcmFailed,
      total: webSent + fcmSent,
    }), {
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
