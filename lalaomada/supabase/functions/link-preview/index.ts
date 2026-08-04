// Supabase Edge Function: link-preview
// GET /functions/v1/link-preview?url=<encoded url>
// Requires an authenticated caller (Authorization: Bearer <user JWT>).
import { createClient } from "npm:@supabase/supabase-js@2.45.0";
import { corsHeaders } from "../_shared/cors.ts";

function isPrivateHost(host: string): boolean {
  const h = host.toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".internal")) return true;
  const m = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (m) {
    const a = parseInt(m[1], 10);
    const b = parseInt(m[2], 10);
    if (a === 10) return true;
    if (a === 127) return true;
    if (a === 0) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    if (a === 100 && b >= 64 && b <= 127) return true;
    if (a >= 224) return true;
    return false;
  }
  if (h === "::1" || h.startsWith("[::1]")) return true;
  if (h.startsWith("fe80:") || h.startsWith("fc") || h.startsWith("fd")) return true;
  return false;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const auth = req.headers.get("authorization") || "";
    const token = auth.replace(/^Bearer\s+/i, "").trim();
    if (!token) return json({ error: "unauthorized" }, 401);

    const userClient = createClient(url, anonKey, {
      global: { headers: { Authorization: `Bearer ${token}` } },
    });
    const { data: userData } = await userClient.auth.getUser();
    if (!userData?.user?.id) return json({ error: "unauthorized" }, 401);

    const reqUrl = new URL(req.url);
    const raw = reqUrl.searchParams.get("url") || "";
    if (!raw || !/^https?:\/\//i.test(raw)) return json({ error: "url invalide" }, 400);

    let target: URL;
    try {
      target = new URL(raw);
    } catch {
      return json({ error: "url invalide" }, 400);
    }
    if (target.protocol !== "http:" && target.protocol !== "https:") {
      return json({ error: "scheme invalide" }, 400);
    }
    if (isPrivateHost(target.hostname)) return json({ error: "host non autorisé" }, 400);

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
      try {
        const finalUrl = new URL(res.url);
        if (isPrivateHost(finalUrl.hostname)) throw new Error("redirect to private host");
      } catch {
        /* ignore parse errors */
      }
      const ct = res.headers.get("content-type") || "";
      if (!ct.includes("text/html")) throw new Error("not html");
      const html = await res.text();

      const get = (pattern: RegExp) => (html.match(pattern)?.[1] || "").trim();
      const decode = (s: string) =>
        s
          .replace(/&amp;/g, "&")
          .replace(/&lt;/g, "<")
          .replace(/&gt;/g, ">")
          .replace(/&quot;/g, '"')
          .replace(/&#39;/g, "'")
          .replace(/&nbsp;/g, " ");

      const title = decode(
        get(/<meta[^>]+property="og:title"[^>]+content="([^"]+)"/i) ||
          get(/<meta[^>]+content="([^"]+)"[^>]+property="og:title"/i) ||
          get(/<title[^>]*>([^<]{1,200})<\/title>/i)
      );

      const description = decode(
        get(/<meta[^>]+property="og:description"[^>]+content="([^"]+)"/i) ||
          get(/<meta[^>]+content="([^"]+)"[^>]+property="og:description"/i) ||
          get(/<meta[^>]+name="description"[^>]+content="([^"]+)"/i) ||
          get(/<meta[^>]+content="([^"]+)"[^>]+name="description"/i)
      );

      let image =
        get(/<meta[^>]+property="og:image"[^>]+content="([^"]+)"/i) ||
        get(/<meta[^>]+content="([^"]+)"[^>]+property="og:image"/i);
      if (image && image.startsWith("/")) {
        image = `${target.protocol}//${target.host}${image}`;
      }

      const siteName =
        decode(
          get(/<meta[^>]+property="og:site_name"[^>]+content="([^"]+)"/i) ||
            get(/<meta[^>]+content="([^"]+)"[^>]+property="og:site_name"/i)
        ) || target.hostname.replace(/^www\./, "");

      return json({
        title: title.slice(0, 120),
        description: description.slice(0, 200),
        image,
        siteName,
        url: raw,
      });
    } catch (e) {
      return json({ error: (e as Error)?.message || "fetch failed" }, 502);
    }
  } catch (e) {
    return json({ error: (e as Error)?.message || "error" }, 500);
  }
});
