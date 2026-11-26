// UPZONE — purchases confirmed by RevenueCat (Apple App Store and Google Play).
// RevenueCat checks each purchase with the store, then calls this function. The function only decides what the
// database should record; the database (record_purchase / refund_purchase, service key only) applies the rules.
// A phone never calls this: the request is authenticated by a secret that only RevenueCat and Supabase hold.
// Secrets, set in Supabase → Edge Functions → Secrets, never in Git:
//   REVENUECAT_WEBHOOK_AUTH   the exact value typed in RevenueCat → Integrations → Webhooks → « Authorization header »
//   REVENUECAT_ALLOW_SANDBOX  "true" only while testing with the stores' test purchases; remove it for the public release
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase.
// Deploy with "Verify JWT" off: the request is authenticated by REVENUECAT_WEBHOOK_AUTH instead.

// Product identifiers, the same in App Store Connect, Google Play and RevenueCat.
const PRODUCTS: Record<string, { product: string; cents: number }> = {
  upzone_venue_pass: { product: "venue_pass", cents: 299 },
  upzone_pro_evening: { product: "pro_evening", cents: 999 },
};
const STORES: Record<string, string> = { APP_STORE: "apple", PLAY_STORE: "google" };
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;

// What to do with one RevenueCat event. Pure: no network, so it is tested as it is.
// Returns { action: "record" | "refund" | "ignore", ... }. An ignored event is answered 200 so that it is not sent again.
export function decide(event: unknown, allowSandbox: boolean) {
  const e = (event && typeof event === "object" ? event : {}) as Record<string, unknown>;
  const type = String(e.type || "");
  if (type !== "NON_RENEWING_PURCHASE" && type !== "CANCELLATION") return { action: "ignore", why: "event_type" };
  if (String(e.environment || "") !== "PRODUCTION" && !allowSandbox) return { action: "ignore", why: "sandbox" };
  const store = STORES[String(e.store || "")];
  if (!store) return { action: "ignore", why: "store" };
  const known = PRODUCTS[String(e.product_id || "")];
  if (!known) return { action: "ignore", why: "product" };
  const transaction = String(e.transaction_id || "");
  if (transaction.length < 6 || transaction.length > 200) return { action: "ignore", why: "transaction" };
  if (type === "CANCELLATION") return { action: "refund", store, transaction };
  // The member is the account signed in when the purchase was made: the app gives RevenueCat the account id, nothing else.
  const user = String(e.app_user_id || "").toLowerCase();
  if (!UUID.test(user)) return { action: "ignore", why: "user" };
  // The store's price when RevenueCat knows it, the listed price otherwise. The stores stay the reference for money.
  const price = Number(e.price_in_purchased_currency);
  const cents = Number.isFinite(price) && price > 0 ? Math.min(100000, Math.max(1, Math.round(price * 100))) : known.cents;
  const currency = /^[A-Za-z]{3}$/.test(String(e.currency || "")) ? String(e.currency).toUpperCase() : "EUR";
  return { action: "record", user, store, product: known.product, transaction, cents, currency };
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
function sameSecret(a: string, b: string) {
  const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b);
  if (x.length !== y.length) return false;
  let d = 0; for (let i = 0; i < x.length; i++) d |= x[i] ^ y[i];
  return d === 0;
}
// Errors the database raises on purpose: sending the same event again would not help, so they are answered 200.
const FINAL = ["purchase_conflict", "purchase_invalid", "purchase_missing"];

if (typeof Deno !== "undefined") Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_AUTH"), url = Deno.env.get("SUPABASE_URL"), key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!secret || secret.length < 24 || !url || !key) return json({ error: "not_configured" }, 500);
  if (!sameSecret(req.headers.get("authorization") || "", secret)) return json({ error: "forbidden" }, 401);
  let data: { event?: unknown };
  try { data = await req.json(); } catch { return json({ error: "bad_request" }, 400); }
  const d = decide(data?.event, Deno.env.get("REVENUECAT_ALLOW_SANDBOX") === "true");
  if (d.action === "ignore") return json({ ok: true, ignored: d.why });
  const [fn, args] = d.action === "refund"
    ? ["refund_purchase", { p_store: d.store, p_transaction: d.transaction }]
    : ["record_purchase", { p_user: d.user, p_store: d.store, p_product: d.product, p_transaction: d.transaction, p_amount_cents: d.cents, p_currency: d.currency }];
  const res = await fetch(`${url}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
    body: JSON.stringify(args),
  });
  const out = await res.json().catch(() => null);
  if (res.ok) return json({ ok: true, action: d.action, granted: out?.granted ?? null, note: out?.note ?? null, already: out?.already ?? null });
  const message = String(out?.message || "");
  if (FINAL.includes(message)) return json({ ok: true, ignored: message });
  // Anything else (database unreachable…): answer an error so that RevenueCat sends the event again later.
  return json({ error: "database", message: message.slice(0, 80) }, 500);
});
