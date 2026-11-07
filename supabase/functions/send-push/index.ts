// ANZIAK — push notifications (Web Push). Called only by the database (trigger push_after_notification through pg_net),
// authenticated by a shared secret. Sends a generic text (never a name or a message) and the unread count for the icon badge.
// Secrets, set in Supabase → Edge Functions → Secrets, never in Git:
//   PUSH_HOOK_SECRET   same value as the Vault secret push_hook_secret
//   VAPID_PUBLIC_KEY   same value as vapidPublicKey in src/public-config.js
//   VAPID_PRIVATE_KEY  the private half of that key pair
//   VAPID_SUBJECT      contact for the push services, e.g. "mailto:" + the operator address
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase; used only to delete subscriptions that no longer exist.
// Deploy with "Verify JWT" off: the request is authenticated by PUSH_HOOK_SECRET instead.
import webpush from "npm:web-push@3.6.7";

type Sub = { endpoint: string; p256dh: string; auth: string };
const TEXT: Record<string, [string, string]> = {
  introduction_received: ["Quelqu’un s’est présenté à vous.", "Someone introduced themselves to you."],
  reply_received: ["Vous avez reçu une réponse.", "You received a reply."],
  message_received: ["Nouveau message.", "New message."],
  conversation_closed: ["Une conversation est terminée.", "A conversation has ended."],
  report_handled: ["Votre signalement a été examiné.", "Your report has been reviewed."],
  account_restricted: ["Information importante sur votre compte.", "Important information about your account."],
  account_reinstated: ["Information importante sur votre compte.", "Important information about your account."],
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
function sameSecret(a: string, b: string) {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let d = 0; for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("PUSH_HOOK_SECRET"), pub = Deno.env.get("VAPID_PUBLIC_KEY"), priv = Deno.env.get("VAPID_PRIVATE_KEY");
  const subject = Deno.env.get("VAPID_SUBJECT");
  if (!secret || !pub || !priv || !subject) return json({ error: "not_configured" }, 500);
  if (!sameSecret(req.headers.get("x-push-secret") || "", secret)) return json({ error: "forbidden" }, 401);
  let data: { kind?: string; lang?: string; badge?: number; subscriptions?: Sub[] };
  try { data = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const subs = (data.subscriptions || []).filter((s) => typeof s?.endpoint === "string" && s.endpoint.startsWith("https://")).slice(0, 10);
  const [fr, en] = TEXT[data.kind || ""] || ["Nouvelle activité.", "New activity."];
  const badge = Math.max(0, Math.min(999, Math.floor(Number(data.badge) || 0)));
  const payload = JSON.stringify({ title: "ANZIAK", body: data.lang === "en" ? en : fr, badge, tag: data.kind || "anziak", url: "./account.html" });
  webpush.setVapidDetails(subject, pub, priv);
  const gone: string[] = [];
  let sent = 0;
  await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } }, payload, { TTL: 6 * 3600, urgency: "normal" });
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number }).statusCode;
      if (code === 404 || code === 410) gone.push(s.endpoint);
      else console.error("push failed", code ?? "", (e as Error).message);
    }
  }));
  if (gone.length) {
    const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (url && key) {
      for (const endpoint of gone) {
        await fetch(`${url}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(endpoint)}`, { method: "DELETE", headers: { apikey: key, Authorization: `Bearer ${key}` } }).catch(() => {});
      }
    }
  }
  return json({ sent, removed: gone.length });
});
