// UPZONE — push notifications: Web Push for browsers, and Expo's push service for the phone apps (Android, iPhone).
// Called only by the database (trigger push_after_notification through pg_net), authenticated by a shared secret.
// Sends a generic text (never a name or a message) and the unread count for the icon badge.
// Secrets, set in Supabase → Edge Functions → Secrets, never in Git:
//   PUSH_HOOK_SECRET   same value as the Vault secret push_hook_secret
//   VAPID_PUBLIC_KEY   same value as vapidPublicKey in src/public-config.js
//   VAPID_PRIVATE_KEY  the private half of that key pair
//   VAPID_SUBJECT      contact for the push services, e.g. "mailto:" + the operator address
//   EXPO_ACCESS_TOKEN  optional: only if « enhanced security for push notifications » is switched on in the Expo account
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase; used only to delete subscriptions and phones that no longer exist.
// Deploy with "Verify JWT" off: the request is authenticated by PUSH_HOOK_SECRET instead.
import webpush from "npm:web-push@3.6.7";

type Sub = { endpoint: string; p256dh: string; auth: string };
const TEXT: Record<string, [string, string]> = {
  introduction_received: ["Quelqu’un dit bonjour.", "Someone says hello."],
  reply_received: ["Nouvelle réponse.", "New reply."],
  message_received: ["Nouveau message.", "New message."],
  conversation_closed: ["Une conversation est terminée.", "A conversation has ended."],
  report_handled: ["Signalement examiné.", "Report reviewed."],
  account_restricted: ["Information importante sur le compte.", "Important information about the account."],
  account_warned: ["Avertissement : merci de rester respectueux·se.", "Warning: please stay respectful."],
  account_reinstated: ["Information importante sur le compte.", "Important information about the account."],
  talent_here: ["Un talent est présent dans le lieu.", "A talent is at the venue."],
};
// Phone apps. One request to Expo for all the member's phones; a phone whose app was uninstalled is reported as
// « DeviceNotRegistered » and removed. `channelId` is the notification category on Android (meet, messages, talents, account).
const EXPO_URL = "https://exp.host/--/api/v2/push/send";
const TOKEN = /^Expo(nent)?PushToken\[[A-Za-z0-9_:-]{10,200}\]$/;
const GROUPS = ["meet", "messages", "talents", "account"];
export function expoMessages(devices: unknown, group: unknown, body: string, badge: number, kind: string) {
  const to = (Array.isArray(devices) ? devices : []).filter((t): t is string => typeof t === "string" && TOKEN.test(t)).slice(0, 5);
  const channelId = GROUPS.includes(String(group)) ? String(group) : "account";
  return to.map((token) => ({ to: token, title: "UPZONE", body, badge, channelId, sound: "default", priority: "high", data: { kind } }));
}
// Which tokens Expo says no longer exist, from its answer to the messages sent (same order).
export function goneTokens(messages: { to: string }[], answer: unknown) {
  const rows = (answer as { data?: { status?: string; details?: { error?: string } }[] })?.data;
  if (!Array.isArray(rows)) return [];
  return messages.filter((_, i) => rows[i]?.status === "error" && rows[i]?.details?.error === "DeviceNotRegistered").map((m) => m.to);
}
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
  let data: { kind?: string; group?: string; lang?: string; badge?: number; subscriptions?: Sub[]; devices?: string[] };
  try { data = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const subs = (data.subscriptions || []).filter((s) => typeof s?.endpoint === "string" && s.endpoint.startsWith("https://")).slice(0, 10);
  const [fr, en] = TEXT[data.kind || ""] || ["Nouvelle activité.", "New activity."];
  const badge = Math.max(0, Math.min(999, Math.floor(Number(data.badge) || 0)));
  const text = data.lang === "en" ? en : fr;
  const payload = JSON.stringify({ title: "UPZONE", body: text, badge, tag: data.kind || "upzone", url: "./account.html" });
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
  // Phone apps.
  const messages = expoMessages(data.devices, data.group, text, badge, data.kind || "upzone");
  const goneDevices: string[] = [];
  let sentDevices = 0;
  if (messages.length) {
    try {
      const expoToken = Deno.env.get("EXPO_ACCESS_TOKEN");
      const r = await fetch(EXPO_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json", ...(expoToken ? { Authorization: `Bearer ${expoToken}` } : {}) },
        body: JSON.stringify(messages),
      });
      const answer = await r.json().catch(() => null);
      if (!r.ok) console.error("expo push failed", r.status);
      else {
        goneDevices.push(...goneTokens(messages, answer));
        sentDevices = messages.length - goneDevices.length;
      }
    } catch (e) { console.error("expo push failed", (e as Error).message); }
  }
  if (gone.length || goneDevices.length) {
    const url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (url && key) {
      for (const token of goneDevices) {
        await fetch(`${url}/rest/v1/app_devices?token=eq.${encodeURIComponent(token)}`, { method: "DELETE", headers: { apikey: key, Authorization: `Bearer ${key}` } }).catch(() => {});
      }
      for (const endpoint of gone) {
        await fetch(`${url}/rest/v1/push_subscriptions?endpoint=eq.${encodeURIComponent(endpoint)}`, { method: "DELETE", headers: { apikey: key, Authorization: `Bearer ${key}` } }).catch(() => {});
      }
    }
  }
  return json({ sent, removed: gone.length, phones: sentDevices, phonesRemoved: goneDevices.length });
});
