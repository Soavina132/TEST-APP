// Firebase ID token verification using Google's public certs
// This verifies that a Firebase ID token is genuine without needing the Admin SDK

interface JWTPayload {
  iss?: string;
  aud?: string;
  sub?: string;
  phone_number?: string;
  [key: string]: any;
}

const FIREBASE_PROJECT_ID = "lalao-mada-dd341";

export async function getGoogleCerts(): Promise<Record<string, string>> {
  const resp = await fetch("https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com");
  const certs = await resp.json();
  return certs as Record<string, string>;
}

export async function verifyToken(token: string, certs: Record<string, string>): Promise<JWTPayload | null> {
  // Split the JWT
  const parts = token.split(".");
  if (parts.length !== 3) return null;

  const [headerB64, payloadB64, signatureB64] = parts;

  // Decode header
  const header = JSON.parse(atob(headerB64.replace(/-/g, "+").replace(/_/g, "/")));
  const kid = header.kid;
  const alg = header.alg;

  if (alg !== "RS256") return null;

  // Get the cert for this kid
  const cert = certs[kid];
  if (!cert) return null;

  // Decode payload
  const payload: JWTPayload = JSON.parse(atob(payloadB64.replace(/-/g, "+").replace(/_/g, "/")));

  // Verify issuer
  if (payload.iss !== `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`) return null;

  // Verify audience (should be the project ID)
  if (payload.aud !== FIREBASE_PROJECT_ID) return null;

  // Verify expiration
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp && payload.exp < now) return null;

  // Verify signature using WebCrypto API
  // Import the public key from the X.509 certificate
  const pemHeader = "-----BEGIN CERTIFICATE-----";
  const pemFooter = "-----END CERTIFICATE-----";
  const certBody = cert.replace(pemHeader, "").replace(pemFooter, "").replace(/\s/g, "");
  const certBytes = Uint8Array.from(atob(certBody), c => c.charCodeAt(0));

  // Use SubtleCrypto to verify the signature
  const keyData = derFromPem(cert);
  const key = await crypto.subtle.importKey(
    "spki",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );

  // Recreate the signing input
  const signingInput = new TextEncoder().encode(`${headerB64}.${payloadB64}`);
  const signature = Uint8Array.from(atob(signatureB64.replace(/-/g, "+").replace(/_/g, "/")), c => c.charCodeAt(0));

  const valid = await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, signingInput);
  if (!valid) return null;

  return payload;
}

function derFromPem(pem: string): ArrayBuffer {
  const pemHeader = "-----BEGIN CERTIFICATE-----";
  const pemFooter = "-----END CERTIFICATE-----";
  const certBody = pem.replace(pemHeader, "").replace(pemFooter, "").replace(/\s/g, "");
  const raw = atob(certBody);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

// atob for Deno (it's available globally in Deno, but just in case)
declare function atob(s: string): string;
