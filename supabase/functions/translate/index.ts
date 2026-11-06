// P.Rod — chat translation (French ⇄ English) through DeepL, only when a signed-in member asks for it.
// Secret DEEPL_API_KEY is set in Supabase → Edge Functions → Secrets (never in Git). Keys ending in ":fx"
// belong to the free developer tier and must use api-free.deepl.com (DeepL API documentation).
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const TARGETS: Record<string, string> = { fr: "FR", en: "EN-GB" };
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  if (!req.headers.get("Authorization")) return json({ error: "unauthorized" }, 401); // JWT verified by the platform (verify_jwt)
  const key = Deno.env.get("DEEPL_API_KEY");
  if (!key) return json({ error: "not_configured" }, 503);
  let body: { text?: unknown; target?: unknown };
  try { body = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const text = typeof body.text === "string" ? body.text.trim() : "";
  const target = typeof body.target === "string" ? TARGETS[body.target.toLowerCase()] : undefined;
  if (!text || text.length > 2000 || !target) return json({ error: "bad_request" }, 400);
  const host = key.endsWith(":fx") ? "api-free.deepl.com" : "api.deepl.com";
  const r = await fetch(`https://${host}/v2/translate`, { method: "POST", headers: { Authorization: `DeepL-Auth-Key ${key}`, "Content-Type": "application/json" }, body: JSON.stringify({ text: [text], target_lang: target, source_lang: undefined }) });
  if (!r.ok) return json({ error: r.status === 456 ? "quota_exceeded" : "translation_failed" }, 502);
  const data = await r.json();
  const t = data?.translations?.[0];
  if (!t?.text) return json({ error: "translation_failed" }, 502);
  return json({ text: t.text, source: String(t.detected_source_language || "").toLowerCase() });
});
