import { createFileRoute } from "@tanstack/react-router";
import { createClient } from "@supabase/supabase-js";

// Reject internal / private / loopback / link-local hosts to prevent SSRF
function isPrivateHost(host: string): boolean {
  const h = host.toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".internal")) return true;
  // Bare IPv4
  const m = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const [a, b] = [parseInt(m[1], 10), parseInt(m[2], 10)];
    if (a === 10) return true;
    if (a === 127) return true;
    if (a === 0) return true;
    if (a === 169 && b === 254) return true;   // link-local (AWS metadata)
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true; // CGNAT
    if (a >= 224) return true; // multicast/reserved
    return false;
  }
  // IPv6 loopback / link-local / ULA
  if (h === "::1" || h.startsWith("[::1]")) return true;
  if (h.startsWith("fe80:") || h.startsWith("fc") || h.startsWith("fd")) return true;
  return false;
}

export const Route = createFileRoute("/api/link-preview")({
  server: {
    handlers: {
      GET: async ({ request }) => {
        // Require an authenticated caller
        const url = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL!;
        const anonKey = process.env.SUPABASE_PUBLISHABLE_KEY || process.env.VITE_SUPABASE_PUBLISHABLE_KEY!;
        const auth = request.headers.get("authorization") || "";
        const token = auth.replace(/^Bearer\s+/i, "").trim();
        if (!token) {
          return new Response(JSON.stringify({ error: "unauthorized" }), {
            status: 401, headers: { "content-type": "application/json" },
          });
        }
        const userClient = createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
        const { data: userData } = await userClient.auth.getUser();
        if (!userData?.user?.id) {
          return new Response(JSON.stringify({ error: "unauthorized" }), {
            status: 401, headers: { "content-type": "application/json" },
          });
        }

        const raw = new URL(request.url).searchParams.get("url") || "";
        if (!raw || !/^https?:\/\//i.test(raw)) {
          return new Response(JSON.stringify({ error: "url invalide" }), {
            status: 400, headers: { "content-type": "application/json" },
          });
        }
        let target: URL;
        try { target = new URL(raw); } catch {
          return new Response(JSON.stringify({ error: "url invalide" }), {
            status: 400, headers: { "content-type": "application/json" },
          });
        }
        if (target.protocol !== "http:" && target.protocol !== "https:") {
          return new Response(JSON.stringify({ error: "scheme invalide" }), {
            status: 400, headers: { "content-type": "application/json" },
          });
        }
        if (isPrivateHost(target.hostname)) {
          return new Response(JSON.stringify({ error: "host non autorisé" }), {
            status: 400, headers: { "content-type": "application/json" },
          });
        }

        try {
          const res = await fetch(target.toString(), {
            headers: {
              "User-Agent": "Mozilla/5.0 (compatible; LalaoMADA/1.0)",
              Accept: "text/html",
            },
            redirect: "follow",
            signal: AbortSignal.timeout(6000),
          });
          if (!res.ok) throw new Error(`HTTP ${res.status}`);
          // After redirects, re-validate the final host
          try {
            const finalUrl = new URL(res.url);
            if (isPrivateHost(finalUrl.hostname)) throw new Error("redirect to private host");
          } catch { /* ignore parse errors */ }
          const ct = res.headers.get("content-type") || "";
          if (!ct.includes("text/html")) throw new Error("not html");
          const html = await res.text();

          const get = (pattern: RegExp) => (html.match(pattern)?.[1] || "").trim();
          const decode = (s: string) =>
            s.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
             .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ");

          const title =
            decode(get(/<meta[^>]+property="og:title"[^>]+content="([^"]+)"/i) ||
            get(/<meta[^>]+content="([^"]+)"[^>]+property="og:title"/i) ||
            get(/<title[^>]*>([^<]{1,200})<\/title>/i));

          const description =
            decode(get(/<meta[^>]+property="og:description"[^>]+content="([^"]+)"/i) ||
            get(/<meta[^>]+content="([^"]+)"[^>]+property="og:description"/i) ||
            get(/<meta[^>]+name="description"[^>]+content="([^"]+)"/i) ||
            get(/<meta[^>]+content="([^"]+)"[^>]+name="description"/i));

          let image =
            get(/<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i) ||
            get(/<meta[^>]+content="([^"]+)"[^>]+property="og:image"/i);
          if (image && image.startsWith("/")) {
            image = `${target.protocol}//${target.host}${image}`;
          }

          const siteName =
            decode(get(/<meta[^>]+property="og:site_name"[^>]+content="([^"]+)"/i) ||
            get(/<meta[^>]+content="([^"]+)"[^>]+property="og:site_name"/i)) ||
            target.hostname.replace(/^www\./, "");

          return new Response(
            JSON.stringify({ title: title.slice(0, 120), description: description.slice(0, 200), image, siteName, url: raw }),
            { status: 200, headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" } }
          );
        } catch (e: any) {
          return new Response(JSON.stringify({ error: e?.message || "fetch failed" }), {
            status: 502, headers: { "content-type": "application/json" },
          });
        }
      },
    },
  },
});
